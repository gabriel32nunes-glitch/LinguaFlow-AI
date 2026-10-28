import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LinguaFlowApp());
}

class LinguaFlowApp extends StatelessWidget {
  const LinguaFlowApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'LinguaFlow AI Grátis',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0A101D),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF59DFBE),
            brightness: Brightness.dark,
          ),
        ),
        home: const TranslationPage(),
      );
}

class TranslationController extends ChangeNotifier {
  static const _speech = MethodChannel('app.linguaflow/offline_speech');
  static const _speechEvents = EventChannel('app.linguaflow/offline_speech/events');

  final FlutterTts _tts = FlutterTts();
  final LanguageIdentifier _languageId = LanguageIdentifier(confidenceThreshold: 0.5);
  final OnDeviceTranslatorModelManager _models = OnDeviceTranslatorModelManager();
  final OnDeviceTranslator _enToPt = OnDeviceTranslator(
    sourceLanguage: TranslateLanguage.english,
    targetLanguage: TranslateLanguage.portuguese,
  );
  final OnDeviceTranslator _ptToEn = OnDeviceTranslator(
    sourceLanguage: TranslateLanguage.portuguese,
    targetLanguage: TranslateLanguage.english,
  );

  StreamSubscription<dynamic>? _events;
  final Map<String, Map<String, dynamic>> _voices = {};
  bool running = false;
  bool busy = false;
  bool _disposed = false;
  bool _processing = false;
  bool speaking = false;
  bool audioEnabled = true;
  // O modelo é baixado uma vez. Não impomos Wi-Fi para evitar espera sem fim.
  // Pode utilizar o plano de dados do celular na primeira instalação.
  bool allowMobileDataForModels = true;
  String status = 'Pronto para iniciar';
  String partial = '';
  String portuguese = '';
  String english = '';
  String original = '';
  String? warning;

  void _update() {
    if (!_disposed) notifyListeners();
  }

  void setAudioEnabled(bool value) {
    audioEnabled = value;
    _update();
  }

  void setAllowMobileDataForModels(bool value) {
    if (busy || running) return;
    allowMobileDataForModels = value;
    _update();
  }

  Future<void> start() async {
    if (running || busy) return;
    busy = true;
    warning = null;
    status = 'Verificando o aparelho…';
    _update();
    try {
      final support = Map<dynamic, dynamic>.from(
        await _speech.invokeMethod<dynamic>('checkSupport') as Map,
      );
      if (support['supported'] != true) {
        throw StateError(support['message']?.toString() ??
            'Este Android não oferece reconhecimento bilíngue local.');
      }

      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        throw StateError('Autorize o microfone nas configurações do Android.');
      }

      status = 'Verificando modelos de tradução instalados…';
      _update();
      await _downloadModels();
      await _initializeVoices();

      await _events?.cancel();
      _events = _speechEvents.receiveBroadcastStream().listen(
        _onSpeechEvent,
        onError: (Object err) {
          warning = 'Erro do reconhecimento de voz: $err';
          status = 'Reconhecimento interrompido';
          running = false;
          unawaited(_events?.cancel() ?? Future<void>.value());
          _events = null;
          _update();
        },
      );

      // Reconhecimento estritamente LOCAL: Android 14+ com provedor no aparelho.
      await _speech.invokeMethod<void>('start');
      running = true;
      status = 'Ouvindo português e inglês…';
      _update();
    } catch (e) {
      warning = e.toString().replaceFirst('Bad state: ', '');
      status = 'Não foi possível iniciar';
      running = false;
      await _events?.cancel();
      _events = null;
    } finally {
      busy = false;
      _update();
    }
  }

  Future<void> _downloadModels() async {
    final modelsToCheck = <(String, String)>[
      (TranslateLanguage.english.bcpCode, 'inglês'),
      (TranslateLanguage.portuguese.bcpCode, 'português'),
    ];
    for (final (code, label) in modelsToCheck) {
      try {
        status = 'Verificando modelo de $label ($code)…';
        _update();
        final alreadyInstalled = await _models.isModelDownloaded(code)
            .timeout(const Duration(seconds: 15));
        if (alreadyInstalled) continue;

        var seconds = 0;
        status = 'Baixando modelo de $label ($code) — primeira utilização…';
        _update();
        // O plugin não fornece porcentagem de progresso. Exibimos o tempo real.
        final ticker = Timer.periodic(const Duration(seconds: 5), (_) {
          seconds += 5;
          status = 'Baixando modelo de $label ($code) — $seconds s. '
              'Confira a internet; o modelo será usado offline depois.';
          _update();
        });
        var downloaded = false;
        try {
          downloaded = await _models.downloadModel(
            code,
            isWifiRequired: !allowMobileDataForModels,
          ).timeout(const Duration(minutes: 2));
        } finally {
          ticker.cancel();
        }
        if (!downloaded ||
            !await _models.isModelDownloaded(code)
                .timeout(const Duration(seconds: 15))) {
          throw StateError('O arquivo do idioma não foi confirmado pelo Android.');
        }
        status = 'Modelo de $label pronto!';
        _update();
      } on TimeoutException {
        throw StateError('O modelo de $label ($code) não terminou de baixar em até '
            '2 minutos. Verifique a internet, desative VPN/DNS privado '
            'se estiver usando, atualize o Google Play Services e tente de novo. '
            'O download anterior pode continuar em segundo plano.');
      } on PlatformException catch (error) {
        throw StateError('Não foi possível obter o modelo de $label ($code): '
            '${error.message ?? error.code}. Confira a internet, espaço livre e '
            'Google Play Services.');
      }
    }
  }

  Future<void> _initializeVoices() async {
    // Apenas vozes explicitamente declaradas offline pelo mecanismo Android.
    await _tts.awaitSpeakCompletion(true);
    await _tts.setSpeechRate(0.49);
    final allVoices = await _tts.getVoices;
    _voices.clear();
    if (allVoices is List) {
      for (final item in allVoices) {
        if (item is! Map) continue;
        final voice = item.map((key, value) => MapEntry(key.toString(), value));
        final locale = voice['locale']?.toString().replaceAll('_', '-').toLowerCase() ?? '';
        final local = voice['network_required'] == false ||
            voice['network_required']?.toString().toLowerCase() == 'false';
        if (local && voice['name'] != null) {
          if (locale.startsWith('pt')) _voices.putIfAbsent('pt', () => voice);
          if (locale.startsWith('en')) _voices.putIfAbsent('en', () => voice);
        }
      }
    }
    if (_voices.length < 2) {
      warning = 'Uma voz offline PT/EN não foi encontrada. As legendas continuam disponíveis. '
          'Instale vozes offline nas opções de texto para fala do Android.';
    }
  }

  void _onSpeechEvent(dynamic payload) {
    if (!running || payload is! Map) return;
    final event = payload.map((key, value) => MapEntry(key.toString(), value));
    switch (event['type']) {
      case 'partial':
        partial = event['text']?.toString() ?? '';
        _update();
        break;
      case 'result':
        if (_processing) return;
        _processing = true;
        unawaited(_handleFinal(event));
        break;
      case 'fatal':
        warning = event['message']?.toString() ?? 'Falha do reconhecimento.';
        status = 'O reconhecimento foi interrompido';
        running = false;
        unawaited(_events?.cancel() ?? Future<void>.value());
        _events = null;
        _update();
        break;
      case 'status':
        status = event['message']?.toString() ?? status;
        _update();
        break;
    }
  }

  Future<void> _handleFinal(Map<String, dynamic> event) async {
    try {
      if (!running) return;
      final text = event['text']?.toString().trim() ?? '';
      partial = '';
      if (text.isEmpty) return;
      original = text;
      status = 'Identificando idioma…';
      _update();

      String language = event['language']?.toString().toLowerCase() ?? '';
      if (!language.startsWith('pt') && !language.startsWith('en')) {
        language = await _languageId.identifyLanguage(text);
      }
      final isEnglish = language.startsWith('en');
      final isPortuguese = language.startsWith('pt');
      if (!isEnglish && !isPortuguese) {
        warning = 'Idioma não identificado nesta frase. Fale um pouco mais claramente.';
        return;
      }

      status = isEnglish ? 'Traduzindo para português…' : 'Traduzindo para inglês…';
      _update();
      final translation = isEnglish
          ? await _enToPt.translateText(text)
          : await _ptToEn.translateText(text);
      if (!running) return;
      if (isEnglish) {
        portuguese = translation;
      } else {
        english = translation;
      }
      status = 'Tradução concluída';
      _update();

      if (audioEnabled && _voices.containsKey(isEnglish ? 'pt' : 'en')) {
        speaking = true;
        status = 'Reproduzindo tradução…';
        _update();
        final target = isEnglish ? 'pt' : 'en';
        final voice = _voices[target]!;
        await _tts.setLanguage(target == 'pt' ? 'pt-BR' : 'en-US');
        await _tts.setVoice(<String, String>{
          'name': voice['name'].toString(),
          'locale': voice['locale'].toString(),
        });
        await _tts.speak(translation).timeout(const Duration(seconds: 60)); // evita eco
      }
    } catch (e) {
      warning = 'Falha ao traduzir/reproduzir: $e';
    } finally {
      speaking = false;
      _processing = false;
      if (running) {
        // Não captar a própria fala do TTS, nem reiniciar cedo demais.
        await Future<void>.delayed(const Duration(milliseconds: 450));
        if (running) {
          try {
            await _speech.invokeMethod<void>('resume');
            status = 'Ouvindo português e inglês…';
          } catch (e) {
            warning = 'Não foi possível continuar escutando: $e';
            status = 'Reconhecimento interrompido';
            running = false;
          }
        }
      }
      _update();
    }
  }

  Future<void> stop() async {
    running = false;
    busy = false;
    speaking = false;
    partial = '';
    status = 'Tradução encerrada';
    _update();
    try {
      await _speech.invokeMethod<void>('stop');
      await _tts.stop();
      await _events?.cancel();
      _events = null;
    } catch (e) {
      warning = 'Erro ao encerrar: $e';
      _update();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    running = false;
    unawaited(_speech.invokeMethod<void>('stop'));
    unawaited(_tts.stop());
    unawaited(_events?.cancel() ?? Future<void>.value());
    _enToPt.close();
    _ptToEn.close();
    _languageId.close();
    super.dispose();
  }
}

class TranslationPage extends StatefulWidget {
  const TranslationPage({super.key});

  @override
  State<TranslationPage> createState() => _TranslationPageState();
}

class _TranslationPageState extends State<TranslationPage> {
  final TranslationController controller = TranslationController();
  bool consent = false;

  @override
  void initState() {
    super.initState();
    controller.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    controller.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (controller.running) {
      await controller.stop();
    } else if (!consent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Avise as pessoas antes de iniciar a tradução.')),
      );
    } else {
      await controller.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = controller.running;
    final accent = const Color(0xFF59DFBE);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('LinguaFlow AI', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Chip(
              avatar: Icon(Icons.lock_outline, size: 16, color: accent),
              label: const Text('SEM API PAGA'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          children: [
            const Text('Conversa bilateral, sem botões por frase.',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.15)),
            const SizedBox(height: 10),
            Text(controller.status,
                style: const TextStyle(color: Color(0xFFA6B8CA), fontSize: 14)),
            const SizedBox(height: 20),
            _TranslationCard(
              heading: '🇺🇸 Inglês → Português',
              subtitle: 'O que o estrangeiro falou',
              translated: controller.portuguese,
              placeholder: 'A tradução aparecerá aqui…',
              accent: accent,
            ),
            const SizedBox(height: 12),
            _TranslationCard(
              heading: '🇧🇷 Português → Inglês',
              subtitle: 'Sua resposta traduzida',
              translated: controller.english,
              placeholder: 'Sua resposta aparecerá aqui…',
              accent: const Color(0xFF89AAFF),
            ),
            if (controller.partial.isNotEmpty || controller.original.isNotEmpty) ...[
              const SizedBox(height: 12),
              _InfoTile(
                icon: Icons.record_voice_over,
                title: controller.partial.isNotEmpty ? 'Ouvindo agora' : 'Última fala original',
                content: controller.partial.isNotEmpty ? controller.partial : controller.original,
              ),
            ],
            if (controller.warning != null) ...[
              const SizedBox(height: 12),
              _InfoTile(
                icon: Icons.info_outline,
                title: 'Aviso',
                content: controller.warning!,
              ),
            ],
            const SizedBox(height: 14),
            SwitchListTile.adaptive(
              value: controller.audioEnabled,
              onChanged: controller.setAudioEnabled,
              title: const Text('Falar tradução em voz alta'),
              subtitle: const Text('Somente vozes instaladas para uso offline'),
              contentPadding: EdgeInsets.zero,
            ),
            if (!running && !controller.busy) SwitchListTile.adaptive(
              value: controller.allowMobileDataForModels,
              onChanged: controller.setAllowMobileDataForModels,
              title: const Text('Permitir baixar modelos com dados móveis'),
              subtitle: const Text('Sem cobrança por API. O primeiro download usa internet '
                  'e pode consumir a franquia de dados do celular.'),
              contentPadding: EdgeInsets.zero,
            ),
            if (controller.busy) const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: LinearProgressIndicator(),
            ),
            if (!running) CheckboxListTile(
              value: consent,
              onChanged: controller.busy ? null : (v) => setState(() => consent = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Os participantes sabem que o microfone será usado.'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: controller.busy ? null : _toggle,
              icon: Icon(running ? Icons.stop_circle_outlined : Icons.mic),
              label: Text(controller.busy ? 'Preparando…' :
                  running ? 'Encerrar escuta' : 'Iniciar tradução automática'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(60),
                backgroundColor: running ? const Color(0xFFF08A96) : accent,
                foregroundColor: const Color(0xFF101622),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Requer Android 14+ e reconhecimento de voz local com troca automática '
                'de idiomas. Baixe previamente os modelos PT/EN e as vozes offline. '
                'O app precisa ficar aberto nesta versão; não guarda gravações e '
                'não utiliza serviços de tradução pagos. Durante a voz traduzida '
                'o microfone fica pausado para evitar realimentação.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF9AADC1), fontSize: 12, height: 1.45)),
          ],
        ),
      ),
    );
  }
}

class _TranslationCard extends StatelessWidget {
  const _TranslationCard({
    required this.heading,
    required this.subtitle,
    required this.translated,
    required this.placeholder,
    required this.accent,
  });
  final String heading;
  final String subtitle;
  final String translated;
  final String placeholder;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(minHeight: 155),
        decoration: BoxDecoration(
          color: const Color(0xFF152136),
          borderRadius: BorderRadius.circular(21),
          border: Border.all(color: const Color(0xFF293B52)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(heading, style: TextStyle(color: accent, fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Color(0xFFACB9C9), fontSize: 12)),
          const SizedBox(height: 19),
          Text(translated.isEmpty ? placeholder : translated,
              style: TextStyle(fontSize: 19, height: 1.35,
                  color: translated.isEmpty ? const Color(0xFF8FA1B4) : Colors.white)),
        ]),
      );
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.icon, required this.title, required this.content});
  final IconData icon;
  final String title;
  final String content;
  @override
  Widget build(BuildContext context) => Card(
        color: const Color(0xFF202D3F),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 19, color: const Color(0xFFB4C7D6)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text(content),
            ])),
          ]),
        ),
      );
}

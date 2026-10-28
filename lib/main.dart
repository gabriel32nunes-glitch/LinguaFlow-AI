import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'work_phrases.dart';
import 'language_direction.dart';
import 'device_profile.dart';
import 'voice_aura.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LinguaFlowApp());
}

class LinguaFlowApp extends StatelessWidget {
  const LinguaFlowApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'LinguaFlow AI',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF080D1C),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF58F1D0),
            brightness: Brightness.dark,
          ),
        ),
        home: const TranslationPage(),
      );
}

class TranslationTurn {
  const TranslationTurn({required this.source, required this.translation, required this.fromEnglish});
  final String source;
  final String translation;
  final bool fromEnglish;
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
  bool modelsReady = false;
  bool microphoneOnly = false;
  bool phraseOnly = false;
  bool economyMode = true;
  bool allowSystemRecognition = false;
  bool tvMode = false;
  double? tvAudioLevelDb;
  int tvRecognizedSegments = 0;
  String languageMode = 'auto';
  DeviceProfile? deviceProfile;
  String deviceStatus = 'Detectando versao Android e memoria…';
  String? deviceNotice;
  final List<TranslationTurn> history = [];
  String modelsStatus = 'Modelos ainda não verificados';
  String status = 'Pronto para iniciar';
  String partial = '';
  String portuguese = '';
  String english = '';
  String original = '';
  String? warning;

  void _update() {
    if (!_disposed) notifyListeners();
  }

  Future<void> inspectDevice() async {
    try {
      final response = await _speech.invokeMethod<dynamic>('deviceInfo')
          .timeout(const Duration(seconds: 10));
      if (response is! Map) {
        deviceStatus = 'O Android nao informou as caracteristicas do aparelho.';
        return;
      }
      final profile = DeviceProfile.fromPlatform(response);
      deviceProfile = profile;
      deviceStatus = '${profile.manufacturer} ${profile.model} · '
          'Android API ${profile.sdkInt} · memoria ${profile.memoryClassMb} MB · '
          'voz offline: ${profile.onDeviceSpeechAvailable ? 'sim' : 'nao'}';
      if (profile.isGalaxyA14FourG || profile.lowRamDevice) {
        economyMode = true;
      }
      final safeMode = profile.safeLanguageMode(languageMode);
      if (safeMode != languageMode) {
        languageMode = safeMode;
        deviceNotice = 'Este Android nao permite solicitar alternancia automatica PT/EN. '
            'Inicie em Portugues e selecione English quando necessario. '
            'Sem toques por frase no mesmo idioma.';
      } else if (!profile.onDeviceSpeechAvailable) {
        deviceNotice = profile.systemSpeechAvailable
            ? 'A voz offline nao esta disponivel. Voce pode ativar o '
                'servico de voz Android opcional; ele pode usar internet e '
                'enviar audio ao provedor de reconhecimento.'
            : 'Nao ha reconhecedor de voz Android instalado. '
                'Frases escritas continuam disponiveis.';
      } else {
        deviceNotice = null;
      }
    } on MissingPluginException {
      deviceStatus = 'Diagnostico Android so esta disponivel no celular.';
    } on TimeoutException {
      deviceStatus = 'O Android nao respondeu ao diagnostico em 10 segundos.';
    } catch (e) {
      deviceStatus = 'Nao foi possivel consultar o Android: $e';
    } finally {
      _update();
    }
  }

  void setTvMode(bool enabled) {
    if (running || busy) return;
    tvMode = enabled;
    tvAudioLevelDb = null;
    tvRecognizedSegments = 0;
    if (enabled) {
      languageMode = 'en';
      // TV continua tocando durante a traducao: voz sintetizada pode causar eco
      // e ocultar trechos. Legendas ficam ativadas como padrao.
      audioEnabled = false;
      status = 'Modo TV: ouvir ingles e exibir legendas em portugues';
    } else {
      status = 'Pronto para iniciar';
    }
    warning = null;
    _update();
  }

  void setAllowSystemRecognition(bool enabled) {
    if (running || busy) return;
    allowSystemRecognition = enabled;
    _update();
  }

  void setEconomyMode(bool enabled) {
    if (running || busy) return;
    economyMode = enabled;
    _update();
  }

  void setLanguageMode(String value) {
    if (running || busy) return;
    if (!['auto', 'pt', 'en'].contains(value)) return;
    languageMode = value;
    _update();
  }

  void clearHistory() {
    history.clear();
    _update();
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

  /// A v0.4 NÃO inicia download quando o usuário pede tradução. O download
  /// é uma ação separada e toda chamada ao plugin tem limite de espera.
  Future<void> start({bool microphoneOnly = false}) async {
    if (running || busy) return;
    busy = true;
    warning = null;
    this.microphoneOnly = microphoneOnly;
    tvAudioLevelDb = null;
    tvRecognizedSegments = 0;
    if (tvMode) languageMode = 'en';
    status = tvMode
        ? 'Configurando microfone para escutar a televisao em ingles…'
        : 'Verificando suporte de voz local do Samsung…';
    _update();
    try {
      if (deviceProfile == null) {
        await inspectDevice();
      }
      final raw = await _speech.invokeMethod<dynamic>('checkSupport', {
        'languageMode': languageMode,
        'allowSystemRecognition': allowSystemRecognition,
        'tvMode': tvMode,
      })
          .timeout(const Duration(seconds: 10));
      if (raw is! Map) {
        throw StateError('O Android não respondeu à verificação de áudio.');
      }
      final support = Map<dynamic, dynamic>.from(raw);
      if (support['supported'] != true) {
        throw StateError(support['message']?.toString() ??
            'Este Android não oferece reconhecimento de voz bilíngue local.');
      }

      final mic = await Permission.microphone.request()
          .timeout(const Duration(seconds: 20));
      if (!mic.isGranted) {
        throw StateError('Permita acesso ao microfone nas configurações do Android.');
      }
      phraseOnly = false;
      if (!microphoneOnly) {
        // Nao bloquear a conversa se o ML Kit estiver sem modelos.
        // Nesse caso, reconhecer SOMENTE as frases profissionais predefinidas.
        bool available = false;
        try {
          available = await _verifyModels();
        } catch (e) {
          modelsStatus = 'Modelos indisponiveis: $e';
        }
        phraseOnly = !available;
        status = phraseOnly
            ? 'Modo contingencia: apenas frases prontas (sem ML Kit)'
            : 'Preparando as vozes locais…';
        _update();
        if (audioEnabled) {
          try {
            await _initializeVoices().timeout(const Duration(seconds: 12));
          } catch (e) {
            // O microfone e as legendas nao devem depender do motor TTS.
            _voices.clear();
            warning = 'A voz offline nao ficou pronta: $e. '
                'A conversa pode continuar com legendas.';
          }
        }
      }
      await _events?.cancel();
      _events = _speechEvents.receiveBroadcastStream().listen(
        _onSpeechEvent,
        onError: (Object err) {
          warning = 'Erro no reconhecimento de voz: $err';
          status = 'Microfone interrompido';
          running = false;
          unawaited(_events?.cancel() ?? Future<void>.value());
          _events = null;
          _update();
        },
      );
      await _speech.invokeMethod<void>('start', {
        'languageMode': languageMode,
        'economyMode': economyMode,
        'allowSystemRecognition': allowSystemRecognition,
      })
          .timeout(const Duration(seconds: 15));
      running = true;
      status = microphoneOnly
          ? 'TESTE: ouvindo voz sem tentar traduzir…'
          : tvMode
              ? (phraseOnly
                  ? 'TV: ouvindo ingles. Modelos de traducao indisponiveis; '
                      'somente frases prontas podem ser traduzidas.'
                  : 'TV: ouvindo ingles e traduzindo trechos para portugues…')
              : phraseOnly
                  ? 'Ouvindo frases prontas PT/EN (traducao limitada)…'
                  : 'Tradução bilateral ativa — ouvindo…';
      _update();
    } catch (e) {
      warning = e.toString().replaceFirst('Bad state: ', '');
      status = microphoneOnly
          ? 'Não foi possível iniciar o teste do microfone'
          : 'Não foi possível iniciar a tradução';
      running = false;
      await _events?.cancel();
      _events = null;
    } finally {
      busy = false;
      _update();
    }
  }

  Future<bool> _verifyModels() async {
    final installed = <String>[];
    final missing = <String>[];
    for (final (code, label) in <(String, String)>[
      (TranslateLanguage.english.bcpCode, 'inglês'),
      (TranslateLanguage.portuguese.bcpCode, 'português'),
    ]) {
      status = 'Verificando modelo: $label ($code)…';
      _update();
      final ok = await _models.isModelDownloaded(code)
          .timeout(const Duration(seconds: 12));
      (ok ? installed : missing).add(label);
    }
    modelsReady = missing.isEmpty;
    modelsStatus = modelsReady
        ? 'Inglês e português instalados. Tradução liberada.'
        : 'Não instalados: ${missing.join(', ')}. Instalados: ${installed.isEmpty ? 'nenhum' : installed.join(', ')}.';
    _update();
    return modelsReady;
  }

  Future<void> checkModelStatus() async {
    if (busy || running) return;
    busy = true;
    warning = null;
    _update();
    try {
      await _verifyModels();
      status = modelsReady ? 'Modelos prontos para uso' : 'Modelos ausentes';
    } on TimeoutException {
      status = 'Verificação interrompida';
      warning = 'A verificação não respondeu em até 12 segundos por idioma. '
          'Isso indica falha de comunicação com o ML Kit no aparelho.';
    } catch (e) {
      status = 'Falha na verificação';
      warning = 'Erro do ML Kit ao verificar: $e';
    } finally {
      busy = false;
      _update();
    }
  }

  Future<void> prepareModels() async {
    if (busy || running) return;
    busy = true;
    warning = null;
    modelsReady = false;
    status = 'Iniciando download dos modelos de tradução…';
    _update();
    try {
      for (final (code, label) in <(String, String)>[
        (TranslateLanguage.english.bcpCode, 'inglês'),
        (TranslateLanguage.portuguese.bcpCode, 'português'),
      ]) {
        status = 'Consultando modelo de $label ($code)…';
        _update();
        final hasModel = await _models.isModelDownloaded(code)
            .timeout(const Duration(seconds: 12));
        if (hasModel) {
          status = '$label já está instalado.';
          _update();
          continue;
        }
        int elapsed = 0;
        status = 'Baixando $label ($code), máximo 75 segundos…';
        _update();
        final timer = Timer.periodic(const Duration(seconds: 5), (_) {
          elapsed += 5;
          status = 'ML Kit: solicitando $label ($code), $elapsed/75 s. '
              'Se não completar, aparecerá uma mensagem de erro.';
          _update();
        });
        try {
          final downloaded = await _models.downloadModel(
            code, isWifiRequired: !allowMobileDataForModels,
          ).timeout(const Duration(seconds: 75));
          if (!downloaded) {
            throw StateError('O ML Kit não confirmou o download de $label ($code).');
          }
        } finally {
          timer.cancel();
        }
        status = '$label retornou do download; conferindo instalação…';
        _update();
        final confirmed = await _models.isModelDownloaded(code)
            .timeout(const Duration(seconds: 12));
        if (!confirmed) throw StateError('Download de $label retornou, mas o modelo não está instalado.');
      }
      await _verifyModels();
      status = modelsReady ? 'Modelos instalados. Pode iniciar a tradução!' : 'Ainda faltam modelos';
    } on TimeoutException {
      status = 'DOWNLOAD INTERROMPIDO (tempo esgotado)';
      warning = 'O ML Kit não concluiu a operação dentro do limite. '
          'Não é preciso deixar a tela presa: tente verificar modelos novamente mais tarde. '
          'O download interno do Android pode continuar mesmo após esse aviso.';
    } on PlatformException catch (e) {
      status = 'Falha ao baixar modelos';
      warning = 'Erro Android/ML Kit: ${e.code} — ${e.message ?? 'sem mensagem'}. '
          'Envie uma captura deste erro para corrigirmos a causa.';
    } catch (e) {
      status = 'Falha ao baixar modelos';
      warning = 'Problema no ML Kit: $e';
    } finally {
      busy = false;
      _update();
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
      case 'audioLevel':
        final level = event['level'];
        if (tvMode && level is num) {
          tvAudioLevelDb = level.toDouble().clamp(-2.0, 12.0);
          _update();
        }
        break;
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

  Future<void> _displayAndSpeak({
    required String sourceText,
    required String translation,
    required bool fromEnglish,
  }) async {
    if (!running) return;
    if (fromEnglish) {
      portuguese = translation;
    } else {
      english = translation;
    }
    history.insert(0, TranslationTurn(
      source: sourceText, translation: translation, fromEnglish: fromEnglish,
    ));
    final capacity = deviceProfile?.historyCapacity(economyEnabled: economyMode)
        ?? (economyMode ? 8 : 12);
    if (history.length > capacity) history.removeRange(capacity, history.length);
    warning = null;
    status = 'Tradução concluída';
    _update();
    final target = fromEnglish ? 'pt' : 'en';
    if (audioEnabled && _voices.containsKey(target)) {
      speaking = true;
      status = 'Reproduzindo tradução…';
      _update();
      final voice = _voices[target]!;
      await _tts.setLanguage(target == 'pt' ? 'pt-BR' : 'en-US');
      await _tts.setVoice({
        'name': voice['name'].toString(),
        'locale': voice['locale'].toString(),
      });
      await _tts.speak(translation).timeout(const Duration(seconds: 60));
    }
  }

  Future<void> _handleFinal(Map<String, dynamic> event) async {
    try {
      if (!running) return;
      final text = event['text']?.toString().trim() ?? '';
      partial = '';
      if (text.isEmpty) return;
      original = text;
      if (tvMode) tvRecognizedSegments++;
      if (microphoneOnly) {
        status = 'Microfone OK: fala reconhecida! Teste novamente ou encerre.';
        _update();
        return;
      }
      if (phraseOnly) {
        final match = matchSpokenWorkPhrase(text);
        if (match == null) {
          status = 'Frase fora do catalogo offline';
          warning = tvMode
              ? 'O ingles da TV foi reconhecido, mas o tradutor livre '
                  'ainda nao tem os modelos do Google ML Kit. '
                  'O texto original aparece em Ultima fala. '
                  'Somente frases predefinidas do catalogo serao traduzidas.'
              : 'Sem os modelos ML Kit, so posso traduzir as frases '
                  'exibidas no catalogo profissional. Nao foi feita uma traducao inventada.';
          _update();
          return;
        }
        await _displayAndSpeak(
          sourceText: text,
          translation: match.inEnglish ? match.phrase.pt : match.phrase.en,
          fromEnglish: match.inEnglish,
        );
        return;
      }
      status = 'Identificando idioma…';
      _update();

      String language = event['language']?.toString() ?? '';
      if (languageMode == 'auto' &&
          resolveSourceLanguage(mode: 'auto', detectedTag: language) == null) {
        language = await _languageId.identifyLanguage(text)
            .timeout(const Duration(seconds: 8));
      }
      final source = resolveSourceLanguage(
        mode: languageMode, detectedTag: language,
      );
      if (source == null) {
        warning = 'Idioma nao identificado; nenhuma traducao foi inventada. '
            'Use Portugues ou English no seletor manual se necessario.';
        return;
      }
      final isEnglish = source == SourceLanguage.english;

      status = isEnglish ? 'Traduzindo para português…' : 'Traduzindo para inglês…';
      _update();
      final translation = isEnglish
          ? await _enToPt.translateText(text).timeout(const Duration(seconds: 20))
          : await _ptToEn.translateText(text).timeout(const Duration(seconds: 20));
      if (!running) return;
      await _displayAndSpeak(
        sourceText: text, translation: translation, fromEnglish: isEnglish,
      );
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
            status = tvMode
                ? 'TV: ouvindo proxima frase em ingles…'
                : 'Ouvindo português e inglês…';
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

  /// Atalho totalmente offline: textos predefinidos nao dependem dos modelos ML Kit.
  Future<void> playWorkPhrase(WorkPhrase phrase, {required bool inEnglish}) async {
    if (running || busy) {
      warning = 'Encerre a conversa antes de reproduzir uma frase pronta.';
      _update();
      return;
    }
    busy = true;
    warning = null;
    original = phrase.pt;
    english = phrase.en;
    portuguese = phrase.pt;
    status = 'Frase pronta: sem modelo de traducao';
    _update();
    try {
      await _initializeVoices().timeout(const Duration(seconds: 15));
      final target = inEnglish ? 'en' : 'pt';
      final voice = _voices[target];
      if (voice == null) {
        warning = 'Nao existe voz $target offline instalada no celular. '
            'O texto continua disponivel para mostrar ou copiar.';
        return;
      }
      await _tts.setLanguage(inEnglish ? 'en-US' : 'pt-BR');
      await _tts.setVoice({
        'name': voice['name'].toString(),
        'locale': voice['locale'].toString(),
      });
      speaking = true;
      status = inEnglish ? 'Falando em ingles…' : 'Falando em portugues…';
      _update();
      await _tts.speak(inEnglish ? phrase.en : phrase.pt)
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      warning = 'A voz offline nao respondeu em 30 segundos.';
    } catch (e) {
      warning = 'Nao foi possivel falar esta frase: $e';
    } finally {
      speaking = false;
      busy = false;
      status = 'Pronto para iniciar';
      _update();
    }
  }

  Future<void> stop() async {
    running = false;
    busy = false;
    speaking = false;
    partial = '';
    status = 'Sessão encerrada';
    microphoneOnly = false;
    phraseOnly = false;
    tvAudioLevelDb = null;
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
  String phraseCategory = 'Todos';
  String phraseQuery = '';

  @override
  void initState() {
    super.initState();
    controller.addListener(_refresh);
    unawaited(controller.inspectDevice());
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

  Future<void> _toggle({bool microphoneOnly = false}) async {
    if (controller.running) {
      await controller.stop();
    } else if (!consent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Avise as pessoas antes de usar o microfone.')),
      );
    } else {
      await controller.start(microphoneOnly: microphoneOnly);
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = controller.running;
    final accent = const Color(0xFF59DFBE);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('LINGUAFLOW',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w900,
            color: Color(0xFF58F1D0), letterSpacing: 0.4,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Chip(
              side: const BorderSide(color: Color(0xFF24536A)),
              backgroundColor: const Color(0xFF0E1D30),
              avatar: const Icon(Icons.shield_outlined, size: 15,
                  color: Color(0xFF58F1D0)),
              label: const Text('SEM API PAGA',
                  style: TextStyle(fontSize: 10, letterSpacing: 0.2)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF132B43),
                    Color(0xFF0D1A32),
                    Color(0xFF11152A),
                  ],
                ),
                border: Border.all(color: const Color(0xFF25425B)),
              ),
              child: Column(children: [
                const Text('INTERPRETE FUTURISTA · V0.8',
                    style: TextStyle(
                      fontSize: 10, letterSpacing: 2.2,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF69E2DD),
                    )),
                const SizedBox(height: 5),
                Text(controller.tvMode
                    ? 'MODO VÍDEO / TELEVISÃO'
                    : 'CONVERSA SEM BARREIRAS',
                    style: const TextStyle(fontSize: 16, letterSpacing: 0.7,
                        fontWeight: FontWeight.w900)),
                VoiceAura(
                  listening: running,
                  speaking: controller.speaking,
                  hasSpeech: controller.partial.isNotEmpty,
                  economy: controller.economyMode,
                ),
                const SizedBox(height: 13),
                Text(
                  controller.status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFB7CCDC), fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (controller.tvMode) ...[
                  const SizedBox(height: 14),
                  Text(
                    controller.tvAudioLevelDb == null
                        ? 'Sinal de áudio: aguardando dados do reconhecedor'
                        : 'Sinal de áudio informado pelo Android (não calibrado)',
                    style: const TextStyle(fontSize: 11,
                        color: Color(0xFFA5DBE2)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  SizedBox(width: 210,
                    child: LinearProgressIndicator(
                      minHeight: 7,
                      borderRadius: BorderRadius.circular(20),
                      value: controller.tvAudioLevelDb == null
                          ? 0
                          : ((controller.tvAudioLevelDb! + 2) / 14)
                              .clamp(0.0, 1.0),
                      color: const Color(0xFF55EFD0),
                      backgroundColor: const Color(0xFF2B4056),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('Trechos reconhecidos: ${controller.tvRecognizedSegments}',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF9CB0D2))),
                ],
                if (controller.busy) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(minHeight: 3),
                ],
              ]),
            ),
            const SizedBox(height: 15),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: controller.tvMode,
              onChanged: running || controller.busy
                  ? null : controller.setTvMode,
              title: const Text('Modo Vídeo/TV · Inglês → Português',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: const Text(
                  'Ouve o áudio da TV pelo microfone; exibe legendas. '
                  'Desliga voz traduzida para evitar eco. '
                  'Não capta o áudio interno do YouTube.'),
              secondary: const Icon(Icons.tv_rounded,
                  color: Color(0xFF65E6D4)),
            ),
            if (!running) CheckboxListTile(
              value: consent,
              onChanged: controller.busy
                  ? null : (value) => setState(() => consent = value ?? false),
              title: const Text('Todos sabem que o microfone sera usado.',
                  style: TextStyle(fontSize: 12, color: Color(0xFFB8CADC))),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            FilledButton.icon(
              onPressed: controller.busy ? null : () => _toggle(),
              icon: Icon(running ? Icons.stop_circle_rounded
                  : Icons.mic_rounded, size: 23),
              label: Text(controller.busy ? 'PREPARANDO…' :
                  running ? 'ENCERRAR CONVERSA' :
                  controller.tvMode ? 'ESCUTAR TV EM INGLÊS' : 'INICIAR CONVERSA'),
              style: FilledButton.styleFrom(
                backgroundColor: running
                    ? const Color(0xFFFF869E) : accent,
                foregroundColor: const Color(0xFF071520),
                minimumSize: const Size.fromHeight(59),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17)),
                textStyle: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w900,
                    letterSpacing: 1.1),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.memory_rounded, size: 15,
                  color: Color(0xFF7ED5F1)),
              const SizedBox(width: 6),
              Expanded(child: Text(controller.deviceStatus,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Color(0xFF8CAEC7), fontSize: 11))),
            ]),
            const SizedBox(height: 7),
            Text('Modelos de tradução: ${controller.modelsStatus}',
                style: const TextStyle(
                    color: Color(0xFFFFD89A), fontSize: 11)),
            if (controller.deviceNotice != null) ...[
              const SizedBox(height: 10),
              _InfoTile(
                icon: Icons.info_outline,
                title: 'Compatibilidade do Android',
                content: controller.deviceNotice!,
              ),
            ],
            const SizedBox(height: 22),
            const Row(children: [
              Icon(Icons.subtitles_rounded,
                  color: Color(0xFF60EBD0), size: 18),
              SizedBox(width: 7),
              Text('TRADUÇÕES AO VIVO',
                style: TextStyle(fontSize: 12,
                    letterSpacing: 1.6, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 12),
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
            ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 8),
              initiallyExpanded: false,
              leading: const Icon(Icons.work_outline),
              title: const Text('Frases profissionais sem download'),
              subtitle: const Text('Disponiveis mesmo se o ML Kit falhar'),
              children: [
                const Text('Frases prontas nao sao traducao livre. '
                    'Toque no alto-falante para falar pelo celular.',
                    style: TextStyle(color: Color(0xFFB5C4D4), fontSize: 12)),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar em portugues ou ingles',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => phraseQuery = value),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final category in workCategories)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(category),
                            selected: phraseCategory == category,
                            onSelected: (_) => setState(() => phraseCategory = category),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                for (final phrase in findWorkPhrases(
                  phraseQuery, category: phraseCategory,
                ).take(phraseQuery.trim().isEmpty && phraseCategory == 'Todos' ? 8 : 30))
                  Card(
                    color: phrase.priority
                        ? const Color(0xFF422B32)
                        : const Color(0xFF18263A),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(phrase.priority ? '⚠️ ${phrase.pt}' : phrase.pt,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(phrase.en,
                              style: const TextStyle(color: Color(0xFFAAC2DF))),
                          Wrap(spacing: 4, children: [
                            TextButton.icon(
                              onPressed: running || controller.busy
                                  ? null : () => controller.playWorkPhrase(phrase, inEnglish: true),
                              icon: const Icon(Icons.volume_up_outlined, size: 18),
                              label: const Text('Falar inglês'),
                            ),
                            IconButton(
                              tooltip: 'Copiar frase em inglês',
                              onPressed: () => Clipboard.setData(ClipboardData(text: phrase.en)),
                              icon: const Icon(Icons.copy_outlined, size: 19),
                            ),
                            IconButton(
                              tooltip: 'Copiar frase em português',
                              onPressed: () => Clipboard.setData(ClipboardData(text: phrase.pt)),
                              icon: const Icon(Icons.content_copy, size: 19),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ),
                if (phraseQuery.trim().isEmpty && phraseCategory == 'Todos')
                  const Text('Use a busca ou escolha uma categoria para ver todas.',
                      style: TextStyle(color: Color(0xFFAAC2DF), fontSize: 12)),
              ],
            ),
            ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: const Icon(Icons.history_outlined),
              title: Text('Historico desta sessao (${controller.history.length})'),
              subtitle: const Text('Somente na memoria; desaparece ao fechar o app'),
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: controller.history.isEmpty ? null : controller.clearHistory,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Limpar agora'),
                  ),
                ),
                for (final turn in controller.history)
                  ListTile(
                    dense: true,
                    title: Text(turn.source),
                    subtitle: Text(turn.translation),
                    trailing: IconButton(
                      tooltip: 'Copiar traducao',
                      icon: const Icon(Icons.copy),
                      onPressed: () => Clipboard.setData(ClipboardData(text: turn.translation)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            SwitchListTile.adaptive(
              value: controller.allowSystemRecognition,
              onChanged: running || controller.busy
                  ? null : controller.setAllowSystemRecognition,
              title: const Text('Serviço de voz Android (opcional)'),
              subtitle: const Text(
                  'Se não houver voz offline, permite usar o reconhecedor do '
                  'celular. Pode precisar de internet e enviar áudio ao '
                  'serviço configurado. Sem API paga.'),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile.adaptive(
              value: controller.economyMode,
              onChanged: running || controller.busy ? null : controller.setEconomyMode,
              title: const Text('Modo econômico Galaxy A14 4G'),
              subtitle: const Text('Menos atualizacoes na escuta, pausas maiores no silencio '
                  'e historico limitado para economizar recursos.'),
              contentPadding: EdgeInsets.zero,
            ),
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
            if (!running) ...[
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Idioma da pessoa que esta falando'),
                subtitle: const Text('Automatico pode nao funcionar em todos os Samsung'),
                trailing: DropdownButton<String>(
                  value: controller.languageMode,
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('Auto PT/EN')),
                    DropdownMenuItem(value: 'pt', child: Text('Portugues')),
                    DropdownMenuItem(value: 'en', child: Text('English')),
                  ],
                  onChanged: controller.busy ? null : (value) {
                    if (value != null) controller.setLanguageMode(value);
                  },
                ),
              ),
              OutlinedButton.icon(
                onPressed: controller.busy ? null : controller.checkModelStatus,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Verificar modelos instalados'),
              ),
              OutlinedButton.icon(
                onPressed: controller.busy ? null : controller.prepareModels,
                icon: const Icon(Icons.download_rounded),
                label: const Text('Baixar modelos inglês e português'),
              ),
              OutlinedButton.icon(
                onPressed: controller.busy ? null : () => _toggle(microphoneOnly: true),
                icon: const Icon(Icons.hearing),
                label: const Text('Testar microfone SEM tradução'),
              ),
            ],
            const SizedBox(height: 18),
            const Text('Modo TV: microfone escuta o alto-falante da televisao. '
                'Mesmo que o som chegue, o reconhecedor pode nao transcrever. '
                'Ingles e selecionado manualmente e a legenda em portugues '
                'exige modelos de traducao instalados. '
                'O serviço de voz Android alternativo só é usado com autorização '
                'e pode transmitir áudio pela internet. Efeitos de voz não medem volume real. '
                'O perfil A14 4G reduz tentativas e consumo. '
                'Sem modelos, o microfone tenta reconhecer APENAS as frases prontas. '
                'Fala livre ainda exige ML Kit. '
                'O teste de microfone funciona sem modelos. Tradução exige os pacotes PT/EN; Android 14+ '
                'é necessário para troca de idioma no reconhecedor local. Mantenha a tela aberta; '
                'não guarda gravações nem usa APIs pagas. Durante a voz traduzida '
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
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [const Color(0xFF14253D),
              accent.withValues(alpha: 0.065),
              const Color(0xFF0D1A2E)],
          ),
          borderRadius: BorderRadius.circular(21),
          border: Border.all(color: accent.withValues(alpha: 0.30)),
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

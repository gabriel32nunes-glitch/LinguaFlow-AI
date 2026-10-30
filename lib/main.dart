import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'work_phrases.dart';
import 'retail_assistant.dart';
import 'language_direction.dart';
import 'device_profile.dart';
import 'voice_aura.dart';
import 'language_library.dart';
import 'local_whisper_voice.dart';
import 'update_service.dart';

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
  bool audioEnabled = false;
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
  LocalWhisperVoice? _localWhisper;
  LocalWhisperVoice get _whisper => _localWhisper ??= LocalWhisperVoice();
  final WhisperTranscriptDelta _whisperDelta = WhisperTranscriptDelta();
  Timer? _whisperTicker;
  bool useWhisper = true;
  bool autoDetectSpeech = true;
  final List<TranslationTurn> history = [];
  final Map<String, PackState> languagePacks = {
    for (final language in linguaLanguages)
      language.code: PackState.unknown,
  };
  String selectedSource = 'en';
  String selectedTarget = 'pt';
  String packFeedback = 'Gerencie os idiomas sem abrir configuracoes do Android.';
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
      if (useWhisper) {
        // Whisper vem no APK e nao depende da versao Android nem do servico
        // de reconhecimento do Samsung.
        deviceNotice = 'Motor Whisper local incluído no aplicativo; '
            'nenhuma instalação de voz do Samsung é necessária.';
      } else if (safeMode != languageMode) {
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

  void setAutoDetectSpeech(bool value) {
    if (running || busy) return;
    autoDetectSpeech = value;
    _update();
  }

  void selectSource(String code) {
    if (running || busy || getLinguaLanguage(code) == null) return;
    selectedSource = code;
    if (code == selectedTarget) {
      selectedTarget = code == 'pt' ? 'en' : 'pt';
    }
    _update();
  }

  void selectTarget(String code) {
    if (running || busy || getLinguaLanguage(code) == null) return;
    selectedTarget = code;
    if (code == selectedSource) {
      selectedSource = code == 'pt' ? 'en' : 'pt';
    }
    _update();
  }

  Future<void> refreshLanguagePacks() async {
    if (busy || running) return;
    busy = true;
    packFeedback = 'Consultando modelos disponíveis neste aplicativo…';
    _update();
    try {
      for (final language in linguaLanguages) {
        languagePacks[language.code] = PackState.checking;
        _update();
        try {
          final installed = await _models
              .isModelDownloaded(language.translateCode.bcpCode)
              .timeout(const Duration(seconds: 8));
          languagePacks[language.code] =
              installed ? PackState.installed : PackState.absent;
        } catch (_) {
          languagePacks[language.code] = PackState.failed;
        }
        _update();
      }
      packFeedback = 'Verificação concluída. Baixe apenas os idiomas que usar.';
    } finally {
      busy = false;
      _update();
    }
  }

  Future<void> installLanguagePack(String code) async {
    final language = getLinguaLanguage(code);
    if (language == null || busy || running) return;
    busy = true;
    warning = null;
    languagePacks[code] = PackState.installing;
    packFeedback = 'Preparando ${language.name} no aplicativo…';
    _update();
    try {
      final modelCode = language.translateCode.bcpCode;
      final installed = await _models.isModelDownloaded(modelCode)
          .timeout(const Duration(seconds: 12));
      if (!installed) {
        final ok = await _models.downloadModel(modelCode,
          isWifiRequired: !allowMobileDataForModels,
        ).timeout(const Duration(seconds: 180));
        if (!ok) throw StateError('O motor não confirmou a instalação.');
      }
      final confirmed = await _models.isModelDownloaded(modelCode)
          .timeout(const Duration(seconds: 12));
      if (!confirmed) throw StateError('O modelo não foi encontrado após preparar.');
      languagePacks[code] = PackState.installed;
      packFeedback = '${language.name} pronto para tradução offline.';
    } catch (e) {
      languagePacks[code] = PackState.failed;
      packFeedback = 'Não foi possível instalar ${language.name} neste aparelho: $e';
    } finally {
      busy = false;
      _update();
    }
  }

  Future<void> removeLanguagePack(String code) async {
    if (busy || running || (code == 'pt' && selectedTarget == 'pt')) return;
    final language = getLinguaLanguage(code);
    if (language == null) return;
    busy = true;
    packFeedback = 'Liberando espaço de ${language.name}…';
    _update();
    try {
      await _models.deleteModel(language.translateCode.bcpCode)
          .timeout(const Duration(seconds: 20));
      languagePacks[code] = PackState.absent;
      packFeedback = 'Pacote de ${language.name} removido do telefone.';
    } catch (e) {
      languagePacks[code] = PackState.failed;
      packFeedback = 'Não foi possível remover o pacote: $e';
    } finally {
      busy = false;
      _update();
    }
  }

  Future<void> setTextTranslation(String input) async {
    if (busy || running || input.trim().isEmpty) return;
    final source = getLinguaLanguage(selectedSource);
    final target = getLinguaLanguage(selectedTarget);
    if (source == null || target == null || source.code == target.code) return;
    busy = true;
    warning = null;
    status = 'Traduzindo ${source.name} → ${target.name}…';
    _update();
    OnDeviceTranslator? translator;
    try {
      // Valide que OS DOIS modelos estão prontos; nunca force download oculto.
      for (final language in [source, target]) {
        final available = await _models.isModelDownloaded(
          language.translateCode.bcpCode,
        ).timeout(const Duration(seconds: 10));
        if (!available) {
          languagePacks[language.code] = PackState.absent;
          packFeedback = 'Prepare ${language.name} na biblioteca para traduzir.';
          status = 'Modelo de tradução não preparado';
          return;
        }
      }
      translator = OnDeviceTranslator(
        sourceLanguage: source.translateCode,
        targetLanguage: target.translateCode,
      );
      final result = await translator.translateText(input.trim())
          .timeout(const Duration(seconds: 25));
      original = input.trim();
      portuguese = target.code == 'pt' ? result : '';
      english = target.code != 'pt' ? result : '';
      history.insert(0, TranslationTurn(
        source: original, translation: result,
        fromEnglish: source.code == 'en',
      ));
      if (history.length > 8) history.removeRange(8, history.length);
      status = 'Tradução para ${target.name} concluída';
      packFeedback = 'Traduzido localmente, sem API paga.';
    } catch (e) {
      status = 'A tradução não pôde ser concluída';
      packFeedback = 'Erro do motor local: $e';
    } finally {
      translator?.close();
      busy = false;
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
    if (useWhisper) {
      try {
        await _startWhisper(microphoneOnly: microphoneOnly);
      } catch (e) {
        status = 'Não foi possível iniciar o motor de voz integrado';
        warning = 'Falha no mecanismo local do aplicativo: $e';
        running = false;
        await _whisper.stop();
      } finally {
        busy = false;
        _update();
      }
      return;
    }
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

  Future<void> _startWhisper({required bool microphoneOnly}) async {
    final permission = await Permission.microphone.request()
        .timeout(const Duration(seconds: 20));
    if (!permission.isGranted) {
      throw StateError('Permissão do microfone necessária para ouvir.');
    }
    phraseOnly = false;
    _whisperDelta.reset();
    partial = '';
    status = 'Carregando modelo de fala multilíngue incluído no aplicativo…';
    _update();

    // Pacotes de tradução são independentes do reconhecimento Whisper.
    // Mesmo sem pacote, a transcrição local permanece disponível.
    try {
      await _verifyModels();
    } catch (_) {
      modelsReady = false;
      modelsStatus = 'Legendas originais disponíveis; pacotes de tradução '
          'são preparados na biblioteca do aplicativo.';
    }
    if (!microphoneOnly && audioEnabled) {
      try {
        await _initializeVoices().timeout(const Duration(seconds: 8));
      } catch (_) {
        _voices.clear();
      }
    }

    // Não usar o SpeechRecognizer do sistema neste fluxo.
    await _whisper.start(
      language: tvMode ? 'en' : autoDetectSpeech ? 'auto' : selectedSource,
      onPartial: (text) {
        if (!running || _disposed) return;
        _whisperDelta.observe(text);
        partial = text;
        status = tvMode
            ? 'Vídeo/TV: transcrevendo inglês com Whisper local…'
            : 'Reconhecendo idioma e fala no próprio telefone…';
        _update();
      },
      onError: (message) {
        warning = message;
        _update();
      },
    );
    running = true;
    status = 'Reconhecimento Whisper local · idiomas detectados automaticamente';
    unawaited(_preparePreferredTranslationModels());
    _whisperTicker?.cancel();
    _whisperTicker = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!running || _processing) return;
      final delta = _whisperDelta.consume();
      if (delta != null && delta.trim().length > 3) {
        _processing = true;
        unawaited(_handleFinal(<String,dynamic>{
          'text': delta,
          'language': tvMode ? 'en' : (autoDetectSpeech ? 'auto' : selectedSource),
        }));
      }
    });
    _update();
  }

  Future<void> _preparePreferredTranslationModels() async {
    // Preparacao de modelos totalmente pelo app, sem configuracoes do Samsung.
    final requested = <String>{
      selectedTarget,
      tvMode ? 'en' : selectedSource,
    };
    for (final code in requested) {
      if (!running || _disposed) return;
      final language = getLinguaLanguage(code);
      if (language == null) continue;
      try {
        final remoteCode = language.translateCode.bcpCode;
        final present = await _models.isModelDownloaded(remoteCode)
            .timeout(const Duration(seconds: 12));
        if (!present) {
          languagePacks[code] = PackState.installing;
          packFeedback = 'O LinguaFlow esta preparando ${language.name} internamente.';
          _update();
          final ok = await _models.downloadModel(remoteCode,
              isWifiRequired: !allowMobileDataForModels)
              .timeout(const Duration(seconds: 120));
          if (!ok) throw StateError('O download não foi confirmado.');
        }
        languagePacks[code] = PackState.installed;
        packFeedback = '${language.name} preparado para tradução no aplicativo.';
      } catch (_) {
        languagePacks[code] = PackState.failed;
        packFeedback = 'Não foi possível preparar ${language.name} agora. '
            'O reconhecimento e as legendas originais continuam funcionando.';
      }
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
          final language = getLinguaLanguage(locale);
          if (language != null) {
            _voices.putIfAbsent(language.code, () => voice);
          }
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
      if (phraseOnly && !useWhisper) {
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
      if (useWhisper) {
        if (language == 'auto' || language.isEmpty) {
          language = await _languageId.identifyLanguage(text)
              .timeout(const Duration(seconds: 8));
        }
        final source = getLinguaLanguage(language);
        final target = getLinguaLanguage(selectedTarget);
        if (source == null || target == null) {
          status = 'Idioma detectado fora do catálogo; transcrição disponível.';
          _update();
          return;
        }
        if (source.code == target.code) {
          status = 'Fala transcrita em ${source.name}.';
          _update();
          return;
        }
        final sourceAvailable = await _models.isModelDownloaded(
          source.translateCode.bcpCode).timeout(const Duration(seconds: 8));
        final targetAvailable = await _models.isModelDownloaded(
          target.translateCode.bcpCode).timeout(const Duration(seconds: 8));
        if (!sourceAvailable || !targetAvailable) {
          languagePacks[source.code] = sourceAvailable
              ? PackState.installed : PackState.absent;
          languagePacks[target.code] = targetAvailable
              ? PackState.installed : PackState.absent;
          status = 'Legenda transcrita. Tradução para ${target.name} '
              'necessita do pacote de idiomas no aplicativo.';
          _update();
          return;
        }
        final translator = OnDeviceTranslator(
          sourceLanguage: source.translateCode,
          targetLanguage: target.translateCode,
        );
        try {
          status = 'Traduzindo ${source.name} para ${target.name}…';
          _update();
          final translated = await translator.translateText(text)
              .timeout(const Duration(seconds: 25));
          if (!running) return;
          await _displayAndSpeak(sourceText: text, translation: translated,
              fromEnglish: source.code != 'pt');
        } finally {
          translator.close();
        }
      } else {
        if (languageMode == 'auto' &&
            resolveSourceLanguage(mode: 'auto', detectedTag: language) == null) {
          language = await _languageId.identifyLanguage(text)
              .timeout(const Duration(seconds: 8));
        }
        final source = resolveSourceLanguage(
          mode: languageMode, detectedTag: language,
        );
        if (source == null) {
          warning = 'Não foi possível identificar o idioma falado.';
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
            if (!useWhisper) await _speech.invokeMethod<void>('resume');
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

  /// Resposta de atendimento: sempre com microfone parado para evitar eco.
  /// O texto em portugues e confirmado pelo atendente antes da fala.
  /// Ingles pronto funciona mesmo sem modelos ML Kit; outros idiomas
  /// exigem os pacotes instalados e uma voz local disponivel.
  Future<bool> speakRetailResponse(String pt, {String? preparedEnglish}) async {
    final input = pt.trim();
    if (running || busy || input.isEmpty) return false;
    final target = getLinguaLanguage(selectedSource);
    if (target == null || target.code == 'pt') {
      warning = 'Selecione o idioma do cliente para responder.';
      _update();
      return false;
    }
    busy = true;
    warning = null;
    status = 'Preparando resposta para ${target.name}…';
    _update();
    OnDeviceTranslator? translator;
    try {
      String result;
      if (target.code == 'en' && preparedEnglish != null) {
        result = preparedEnglish;
      } else {
        for (final language in [getLinguaLanguage('pt')!, target]) {
          final available = await _models.isModelDownloaded(
            language.translateCode.bcpCode,
          ).timeout(const Duration(seconds: 12));
          if (!available) {
            warning = 'Prepare os modelos de português e ${target.name} '
                'na Biblioteca de idiomas antes de falar uma resposta livre.';
            status = 'Pacote de tradução ausente';
            return false;
          }
        }
        translator = OnDeviceTranslator(
          sourceLanguage: TranslateLanguage.portuguese,
          targetLanguage: target.translateCode,
        );
        result = await translator.translateText(input)
            .timeout(const Duration(seconds: 25));
      }
      original = input;
      portuguese = input;
      english = result; // Campo da resposta, no idioma escolhido pelo cliente.
      history.insert(0, TranslationTurn(
        source: input, translation: result, fromEnglish: false,
      ));
      if (history.length > 8) history.removeRange(8, history.length);
      status = 'Resposta traduzida para ${target.name}';
      _update();

      await _initializeVoices().timeout(const Duration(seconds: 15));
      final voice = _voices[target.code];
      if (voice == null) {
        warning = 'Resposta traduzida, mas não há voz offline '
            'de ${target.name} no celular. Mostre o texto ao cliente.';
        return true;
      }
      speaking = true;
      status = 'Falando com o cliente em ${target.name}…';
      _update();
      final locale = voice['locale'].toString().replaceAll('_', '-');
      await _tts.setLanguage(locale);
      await _tts.setVoice({
        'name': voice['name'].toString(),
        'locale': voice['locale'].toString(),
      });
      await _tts.speak(result).timeout(const Duration(seconds: 45));
      return true;
    } on TimeoutException {
      warning = 'A tradução ou a voz não respondeu a tempo. '
          'Confira a resposta na tela.';
      return false;
    } catch (e) {
      warning = 'Não foi possível preparar a resposta: $e';
      return false;
    } finally {
      translator?.close();
      speaking = false;
      busy = false;
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
      _whisperTicker?.cancel();
      _whisperTicker = null;
      await _whisper.stop();
      if (!useWhisper) await _speech.invokeMethod<void>('stop');
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
    _whisperTicker?.cancel();
    if (_localWhisper != null) unawaited(_localWhisper!.dispose());
    if (!useWhisper) unawaited(_speech.invokeMethod<void>('stop'));
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
  bool _retailMode = true;
  bool _retailReplyBusy = false;
  String? _retailFeedback;
  final TextEditingController _retailInput = TextEditingController();
  final TextEditingController _textInput = TextEditingController();
  final LinguaFlowUpdater _updater = LinguaFlowUpdater();
  LinguaFlowRelease? _newVersion;
  bool _checkingUpdate = false;
  String _updateStatus = 'Verifique atualizações sem sair do LinguaFlow.';

  @override
  void initState() {
    super.initState();
    controller.addListener(_refresh);
    unawaited(controller.inspectDevice());
    // Evita rede em testes de widget; no APK de release checa uma vez
    // apos a tela abrir, sem avisos em caso de ausencia de internet.
    if (kReleaseMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_checkUpdates(silent: true));
      });
    }
  }

  Future<void> _checkUpdates({bool silent = false}) async {
    if (_checkingUpdate) return;
    setState(() {
      _checkingUpdate = true;
      if (!silent) _updateStatus = 'Verificando versão oficial…';
    });
    try {
      final result = await _updater.check();
      if (!mounted) return;
      setState(() {
        _newVersion = result.release;
        if (!silent || result.available) _updateStatus = result.message;
      });
    } catch (_) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _updateStatus = 'Sem conexão com as atualizações agora. '
              'Seu LinguaFlow pode continuar funcionando.';
        });
      }
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _openUpdate() async {
    final release = _newVersion;
    if (release == null) return;
    try {
      await _updater.openDownload(release);
    } catch (_) {
      if (mounted) setState(() =>
        _updateStatus = 'Não foi possível abrir o download oficial.');
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    _textInput.dispose();
    _retailInput.dispose();
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

  Future<void> _sendRetailReply(String pt, {String? preparedEnglish}) async {
    if (_retailReplyBusy || controller.busy) return;
    final wasListening = controller.running;
    setState(() {
      _retailReplyBusy = true;
      _retailFeedback = null;
    });
    try {
      // Interromper a captura antes do TTS impede que o Whisper
      // transcreva a propria voz do aplicativo.
      if (wasListening) await controller.stop();
      final translated = await controller.speakRetailResponse(
        pt, preparedEnglish: preparedEnglish,
      );
      if (!translated) {
        _retailFeedback = controller.warning ??
            'Não foi possível traduzir a resposta.';
      } else if (controller.warning != null) {
        _retailFeedback = controller.warning;
      }
      if (wasListening && consent && mounted) {
        await controller.start();
        if (!controller.running) {
          _retailFeedback = controller.warning ??
              'Não foi possível retomar o microfone.';
        }
      }
    } catch (e) {
      _retailFeedback = 'Erro no atendimento: $e';
    } finally {
      if (mounted) setState(() => _retailReplyBusy = false);
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
                const Text('INTERPRETE FUTURISTA · V0.9',
                    style: TextStyle(
                      fontSize: 10, letterSpacing: 2.2,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF69E2DD),
                    )),
                const SizedBox(height: 5),
                Text(controller.tvMode
                    ? 'MODO VÍDEO / TELEVISÃO'
                    : _retailMode ? 'ATENDIMENTO EM LOJA' : 'CONVERSA SEM BARREIRAS',
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
              value: _retailMode,
              onChanged: running || controller.busy || _retailReplyBusy
                  ? null : (enabled) {
                if (enabled) {
                  controller.setTvMode(false);
                  if (controller.selectedSource == 'pt') {
                    controller.selectSource('en');
                  }
                  controller.selectTarget('pt');
                }
                setState(() {
                  _retailMode = enabled;
                  _retailFeedback = null;
                });
              },
              title: const Text('Modo atendimento em loja',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Escutar o cliente, sugerir respostas '
                  'de vendas e falar no idioma dele.'),
              secondary: const Icon(Icons.storefront_outlined,
                  color: Color(0xFF62F0D2)),
            ),
            if (controller.useWhisper) SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: controller.autoDetectSpeech,
              onChanged: running || controller.busy
                  ? null : controller.setAutoDetectSpeech,
              title: const Text('Reconhecer idioma automaticamente',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Whisper multilíngue embutido no app. '
                  'Sem instalar vozes nas configurações Samsung.'),
              secondary: const Icon(Icons.auto_awesome,
                  color: Color(0xFF62F0D2)),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: controller.tvMode,
              onChanged: running || controller.busy || _retailReplyBusy
                  ? null : (enabled) {
                    if (enabled) setState(() => _retailMode = false);
                    controller.setTvMode(enabled);
                  },
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
              onPressed: controller.busy || _retailReplyBusy
                  ? null : () => _toggle(),
              icon: Icon(running ? Icons.stop_circle_rounded
                  : Icons.mic_rounded, size: 23),
              label: Text(controller.busy ? 'PREPARANDO…' :
                  running ? 'ENCERRAR CONVERSA' :
                  controller.tvMode ? 'ESCUTAR TV EM INGLÊS' :
                  _retailMode ? 'INICIAR ATENDIMENTO' : 'INICIAR CONVERSA'),
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
            if (_retailMode) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF12243A),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF28566A)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.storefront_rounded,
                          color: Color(0xFF58F1D0)),
                      SizedBox(width: 8),
                      Expanded(child: Text('ASSISTENTE DE VENDAS',
                          style: TextStyle(fontWeight: FontWeight.w900))),
                    ]),
                    const SizedBox(height: 8),
                    const Text('Idioma do cliente e das respostas:',
                        style: TextStyle(color: Color(0xFFB7CCDC), fontSize: 12)),
                    DropdownButton<String>(
                      isExpanded: true,
                      value: controller.selectedSource == 'pt'
                          ? 'en' : controller.selectedSource,
                      items: [
                        for (final language in linguaLanguages)
                          if (language.code != 'pt')
                            DropdownMenuItem(
                              value: language.code,
                              child: Text(language.name),
                            ),
                      ],
                      onChanged: running || controller.busy || _retailReplyBusy
                          ? null : (code) {
                            if (code != null) {
                              controller.selectSource(code);
                              controller.selectTarget('pt');
                            }
                          },
                    ),
                    const Text('As sugestões são frases predefinidas: '
                        'não inventam preços, estoque ou descontos.',
                        style: TextStyle(
                            color: Color(0xFFB7CCDC), fontSize: 11)),
                    const SizedBox(height: 12),
                    Text(controller.history.isNotEmpty &&
                            controller.history.first.fromEnglish
                        ? 'Sugestões para a última fala do cliente'
                        : 'Respostas rápidas para começar',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    for (final reply in suggestRetailReplies(
                      controller.history.isNotEmpty &&
                              controller.history.first.fromEnglish
                          ? controller.history.first.translation
                          : controller.original,
                    ))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: OutlinedButton(
                          onPressed: controller.busy || _retailReplyBusy
                              ? null : () => _sendRetailReply(
                                  reply.pt, preparedEnglish: reply.en),
                          style: OutlinedButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            side: const BorderSide(color: Color(0xFF326070)),
                          ),
                          child: Row(children: [
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(reply.pt, style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(reply.en, style: const TextStyle(
                                    fontSize: 11, color: Color(0xFFB6C7D6))),
                              ],
                            )),
                            const Icon(Icons.volume_up_rounded,
                                color: Color(0xFF58F1D0)),
                          ]),
                        ),
                      ),
                    const SizedBox(height: 9),
                    TextField(
                      controller: _retailInput,
                      maxLines: 3,
                      minLines: 1,
                      decoration: const InputDecoration(
                        labelText: 'Sua resposta em português',
                        hintText: 'Ex.: Vou verificar esse produto para você.',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.edit_outlined),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: controller.busy || _retailReplyBusy
                          ? null : () {
                            final text = _retailInput.text.trim();
                            if (text.isNotEmpty) _sendRetailReply(text);
                          },
                      icon: const Icon(Icons.translate_rounded),
                      label: Text(_retailReplyBusy
                          ? 'AGUARDE…' : 'TRADUZIR E FALAR PARA O CLIENTE'),
                    ),
                    if (_retailFeedback != null) ...[
                      const SizedBox(height: 7),
                      Text(_retailFeedback!,
                          style: const TextStyle(
                              color: Color(0xFFFFCF91), fontSize: 12)),
                    ],
                    const SizedBox(height: 8),
                    const Text('Ao responder, o microfone pausa para evitar eco '
                        'e tenta retomar a escuta automaticamente. '
                        'Voz offline depende das vozes instaladas no Android; '
                        'o texto traduzido continua visível.',
                        style: TextStyle(
                            color: Color(0xFF91ABBE), fontSize: 11)),
                    if (!running && !controller.busy)
                      TextButton.icon(
                        onPressed: controller.prepareModels,
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Preparar tradução inglês/português'),
                      ),
                  ],
                ),
              ),
            ],
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
            Text('Tradução: ${controller.packFeedback}',
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
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFF101F32),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _newVersion != null
                      ? const Color(0xFF58F1D0)
                      : const Color(0xFF263C51),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.system_update_alt_rounded,
                        size: 17, color: Color(0xFF58F1D0)),
                    SizedBox(width: 8),
                    Text('ATUALIZAÇÕES',
                        style: TextStyle(
                          fontWeight: FontWeight.bold, letterSpacing: 1.1,
                          fontSize: 12,
                        )),
                  ]),
                  const SizedBox(height: 7),
                  Text(_updateStatus,
                      style: const TextStyle(
                        color: Color(0xFFAFBDD0), fontSize: 12,
                      )),
                  const SizedBox(height: 5),
                  if (_newVersion == null) TextButton.icon(
                    onPressed: _checkingUpdate
                        ? null : () => _checkUpdates(),
                    icon: const Icon(Icons.refresh, size: 17),
                    label: Text(_checkingUpdate
                        ? 'Verificando…' : 'Verificar atualização'),
                  ) else FilledButton.icon(
                    onPressed: _openUpdate,
                    icon: const Icon(Icons.download_rounded, size: 19),
                    label: Text('Atualizar para v${_newVersion!.name}'),
                  ),
                  const Text('A instalação é confirmada pelo Android. '
                      'Não é necessário apagar o app se a assinatura coincidir.',
                      style: TextStyle(
                        fontSize: 10, color: Color(0xFF7E96AB),
                      )),
                ],
              ),
            ),
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
              heading: '🇧🇷 Português → ${getLinguaLanguage(controller.selectedSource)?.name ?? 'Inglês'}',
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
              leading: const Icon(Icons.language_rounded, color: Color(0xFF5CF1D5)),
              title: const Text('Biblioteca de 10 idiomas',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('Instale pacotes sem sair do aplicativo'),
              children: [
                const Padding(
                  padding: EdgeInsets.all(7),
                  child: Text('Os pacotes de tradução são independentes do '
                      'reconhecimento de fala. Instale somente os idiomas '
                      'necessários para economizar espaço.',
                      style: TextStyle(color: Color(0xFFC1CFE0), fontSize: 12)),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: running || controller.busy
                          ? null : controller.refreshLanguagePacks,
                      icon: const Icon(Icons.fact_check),
                      label: const Text('Verificar pacotes'),
                    ),
                    Text(controller.packFeedback,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF97CECB))),
                  ],
                ),
                for (final language in linguaLanguages)
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 3),
                    title: Text('${language.name} · ${language.nativeName}'),
                    subtitle: Text(packStateLabel(
                      controller.languagePacks[language.code] ?? PackState.unknown,
                    ), style: const TextStyle(fontSize: 11)),
                    trailing: controller.languagePacks[language.code] == PackState.installed
                        ? IconButton(
                            onPressed: running || controller.busy
                                ? null : () => controller.removeLanguagePack(language.code),
                            tooltip: 'Remover pacote',
                            icon: const Icon(Icons.delete_outline),
                          )
                        : TextButton(
                            onPressed: running || controller.busy
                                ? null : () => controller.installLanguagePack(language.code),
                            child: const Text('Preparar'),
                          ),
                  ),
                const Divider(),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Traduzir texto com os pacotes instalados',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                Row(children: [
                  Expanded(child: DropdownButton<String>(
                    isExpanded: true,
                    value: controller.selectedSource,
                    items: [
                      for (final language in linguaLanguages)
                        DropdownMenuItem(
                          value: language.code,
                          child: Text(language.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: running || controller.busy
                        ? null : (value) {
                          if (value != null) controller.selectSource(value);
                        },
                  )),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward_rounded, size: 18),
                  ),
                  Expanded(child: DropdownButton<String>(
                    isExpanded: true,
                    value: controller.selectedTarget,
                    items: [
                      for (final language in linguaLanguages)
                        DropdownMenuItem(
                          value: language.code,
                          child: Text(language.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: running || controller.busy
                        ? null : (value) {
                          if (value != null) controller.selectTarget(value);
                        },
                  )),
                ]),
                TextField(
                  controller: _textInput,
                  minLines: 1, maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Escreva aqui para traduzir',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: running || controller.busy
                      ? null : () => controller.setTextTranslation(_textInput.text),
                  icon: const Icon(Icons.translate),
                  label: const Text('Traduzir texto'),
                ),
                const SizedBox(height: 12),
              ],
            ),
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
            if (!controller.useWhisper) SwitchListTile.adaptive(
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
            if (!running && !controller.useWhisper) ...[
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

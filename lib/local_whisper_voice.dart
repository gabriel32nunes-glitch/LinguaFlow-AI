import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

/// Gerencia a fala local sem Android SpeechRecognizer / pacotes de voz Samsung.
/// Um modelo Whisper multilingue incluido no APK reconhece fala por trechos.
/// Em dispositivos lentos, transcrever pode atrasar alguns segundos.
class LocalWhisperVoice {
  final AudioRecorder _recorder = AudioRecorder();
  final WhisperController _controller = WhisperController();
  dynamic _session;
  StreamSubscription<dynamic>? _partials;
  bool _active = false;

  bool get active => _active;

  Future<String> _bundledModelPath() async {
    final directory = await getApplicationSupportDirectory();
    final path = '${directory.path}/ggml-tiny-q5_1.bin';
    final file = File(path);
    if (await file.exists() && await file.length() > 30000000) {
      return file.path;
    }
    // O arquivo e fornecido junto ao APK durante a compilacao.
    // Nao exige Google Speech, configuracao Samsung ou download no celular.
    final bytes = await rootBundle.load('assets/models/ggml-tiny-q5_1.bin');
    if (bytes.lengthInBytes < 30000000) {
      throw StateError('Modelo Whisper integrado esta incompleto.');
    }
    await file.writeAsBytes(bytes.buffer.asUint8List(
      bytes.offsetInBytes, bytes.lengthInBytes,
    ), flush: true);
    return file.path;
  }

  Future<void> start({
    required String language,
    required void Function(String) onPartial,
    required void Function(String) onError,
  }) async {
    if (_active) return;
    if (!await _recorder.hasPermission()) {
      throw StateError('O microfone nao foi autorizado pelo Android.');
    }
    final modelPath = await _bundledModelPath();
    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
      autoGain: true,
      echoCancel: false,
      noiseSuppress: true,
    ));
    try {
      _session = await _controller.transcribeLive(
        modelPath: modelPath,
        pcm16Stream: stream,
        lang: language,
      );
      _active = true;
      _partials = (_session.partials as Stream<dynamic>).listen(
        (text) {
          if (_active && text is String) onPartial(text);
        },
        onError: (Object error) {
          onError('Falha na transcricao Whisper: $error');
        },
      );
    } catch (_) {
      await _recorder.stop();
      rethrow;
    }
  }

  Future<String> stop() async {
    if (!_active && _session == null) return '';
    _active = false;
    await _recorder.stop();
    await _partials?.cancel();
    _partials = null;
    final current = _session;
    _session = null;
    try {
      if (current == null) return '';
      final result = await current.stop();
      return result is String ? result : '';
    } catch (e) {
      debugPrint('Whisper stop: $e');
      return '';
    }
  }

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
    await _controller.releaseModel();
  }
}

/// O streaming Whisper emite a transcricao completa repetidamente.
/// Entrega somente o texto novo para evitar legenda/traducao duplicada.
class WhisperTranscriptDelta {
  String _observed = '';
  String _committed = '';

  void observe(String text) {
    final next = text.trim();
    if (next.isEmpty) return;
    // Descarta atualizacoes que recuam para uma versao anterior.
    if (_committed.isNotEmpty && !next.startsWith(_committed)) return;
    _observed = next;
  }

  String? consume() {
    if (_observed.length <= _committed.length) return null;
    if (!_observed.startsWith(_committed)) return null;
    final delta = _observed.substring(_committed.length).trim();
    if (delta.isEmpty) return null;
    _committed = _observed;
    return delta;
  }

  void reset() {
    _observed = '';
    _committed = '';
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:linguaflow_ai/local_whisper_voice.dart';

void main() {
  test('legendas ao vivo nao repetem trechos ja exibidos', () {
    final parser = WhisperTranscriptDelta();
    parser.observe('Hello, how are you?');
    expect(parser.consume(), 'Hello, how are you?');
    parser.observe('Hello, how are you?');
    expect(parser.consume(), isNull);
    parser.observe('Hello, how are you? I am fine.');
    expect(parser.consume(), 'I am fine.');
  });

  test('atualizacoes anteriores nao voltam para tras', () {
    final parser = WhisperTranscriptDelta();
    parser.observe('First sentence.');
    expect(parser.consume(), 'First sentence.');
    parser.observe('An unrelated older partial');
    expect(parser.consume(), isNull);
    parser.reset();
    parser.observe('New session');
    expect(parser.consume(), 'New session');
  });
}

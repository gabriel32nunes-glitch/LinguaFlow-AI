import 'package:flutter_test/flutter_test.dart';
import 'package:linguaflow_ai/main.dart';

void main() {
  test('Modo TV seleciona ingles e evita eco por voz sintetizada', () {
    final controller = TranslationController();
    addTearDown(controller.dispose);
    expect(controller.languageMode, 'auto');
    expect(controller.audioEnabled, isTrue);
    controller.setTvMode(true);
    expect(controller.tvMode, isTrue);
    expect(controller.languageMode, 'en');
    expect(controller.audioEnabled, isFalse);
    expect(controller.tvAudioLevelDb, isNull);
    expect(controller.tvRecognizedSegments, 0);
    expect(controller.status, contains('Modo TV'));
    controller.setTvMode(false);
    expect(controller.tvMode, isFalse);
  });
}

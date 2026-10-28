import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linguaflow_ai/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('abre sem download automatico e ajusta Android 13', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const channel = MethodChannel('app.linguaflow/offline_speech');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'deviceInfo') {
        return <String, dynamic>{
          'sdkInt': 33,
          'model': 'SM-A145M',
          'manufacturer': 'samsung',
          'memoryClassMb': 192,
          'lowRamDevice': false,
          'onDeviceSpeechAvailable': true,
        };
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await tester.pumpWidget(const LinguaFlowApp());
    await tester.pump();

    expect(find.textContaining('INTERPRETE FUTURISTA · V0.9'), findsOneWidget);
    expect(find.textContaining('Pronto para iniciar'), findsOneWidget);
    // O interruptor de economia fica abaixo da dobra da lista dinamica.
    // Sua logica de limites e validada em device_profile_test.dart.
  });
}

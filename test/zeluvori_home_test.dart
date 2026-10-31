import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linguaflow_ai/main.dart';

void main() {
  testWidgets('Zeluvori abre com interface enxuta e mascote animado',
      (tester) async {
    const channel = MethodChannel('app.linguaflow/offline_speech');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await tester.pumpWidget(const LinguaFlowApp());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('ZELUVORI'), findsOneWidget);
    expect(find.text('TRADUÇÃO EM TEMPO REAL'), findsOneWidget);
    expect(find.text('CLIENTE FALA'), findsOneWidget);
    expect(find.text('INICIAR'), findsOneWidget);
    expect(find.byType(ZeluvoriMascot), findsOneWidget);
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
  });
}

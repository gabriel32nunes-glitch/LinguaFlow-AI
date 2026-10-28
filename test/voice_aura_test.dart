import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linguaflow_ai/voice_aura.dart';

void main() {
  testWidgets('halo futurista renderiza estado parado e ativo', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: VoiceAura(
          listening: false, speaking: false, hasSpeech: false,
        ),
      ),
    ));
    expect(find.text('PRONTO PARA CONVERSAR'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: VoiceAura(
          listening: true, speaking: false, hasSpeech: true,
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('VOZ DETECTADA'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: VoiceAura(
          listening: true, speaking: true, hasSpeech: false,
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('TRANSMITINDO TRADUÇÃO'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

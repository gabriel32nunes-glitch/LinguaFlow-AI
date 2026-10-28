import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linguaflow_ai/main.dart';

void main() {
  testWidgets('a tela abre sem iniciar download automaticamente', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const LinguaFlowApp());

    expect(find.textContaining('VERSÃO 0.6'), findsOneWidget);
    expect(find.textContaining('Modelos ainda não verificados'), findsOneWidget);
    expect(find.textContaining('Pronto para iniciar'), findsOneWidget);
    // O interruptor de economia fica abaixo da dobra da lista lazy;
    // a politica de economia e verificada em device_profile_test.dart.\n  });
}

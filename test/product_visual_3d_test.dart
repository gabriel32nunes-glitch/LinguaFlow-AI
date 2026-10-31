import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linguaflow_ai/main.dart';

void main() {
  group('Vitrine 3D: fala reconhecida', () {
    test('identifica as nove categorias da referencia', () {
      const samples = <String, String>{
        'Quero uma camiseta azul': 'shirt',
        'I would like to try these jeans': 'pants',
        'Vocês vendem boné?': 'cap',
        'Do you have a backpack?': 'backpack',
        'Onde está minha encomenda?': 'parcel',
        'Can I pay by credit card?': 'card',
        'Qual é a medida em centímetros?': 'ruler',
        'Do you have a discount?': 'discount',
        'What is the price?': 'tag',
      };
      for (final entry in samples.entries) {
        expect(ShopVisualCatalog.detect(entry.key)?.id, entry.value,
            reason: entry.key);
      }
    });

    test('produto concreto ganha de preço, tamanho e desconto', () {
      expect(ShopVisualCatalog.detect('Qual o preço dessa camiseta?')?.id,
          'shirt');
      expect(ShopVisualCatalog.detect('Do you have a discount on this cap?')?.id,
          'cap');
      expect(ShopVisualCatalog.detect('What size is this backpack?')?.id,
          'backpack');
      expect(ShopVisualCatalog.detect('Quero saber a medida da calça')?.id,
          'pants');
    });

    test('não inventa item nem encontra termos dentro de outras palavras', () {
      expect(ShopVisualCatalog.detect('Olá, tudo bem?'), isNull);
      expect(ShopVisualCatalog.detect('The captain is here'), isNull);
      expect(ShopVisualCatalog.detect(''), isNull);
    });
  });

  testWidgets('modelo 3D desenha e gira sem falhas', (tester) async {
    final item = ShopVisualCatalog.byId('backpack')!;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 350, height: 290,
          child: ShopVisual3D(item: item),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byType(ShopVisual3D), findsOneWidget);
    await tester.drag(find.byType(ShopVisual3D), const Offset(90, 15));
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.takeException(), isNull);
  });

  testWidgets('galeria manual apresenta os nove modelos',
      (tester) async {
    const channel = MethodChannel('app.linguaflow/offline_speech');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await tester.pumpWidget(const LinguaFlowApp());
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byTooltip('Vitrine 3D'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('VITRINE 3D'), findsOneWidget);
    expect(find.text('Camiseta'), findsOneWidget);
    expect(find.text('Mochila'), findsOneWidget);
    await tester.tap(find.text('Mochila'));
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byType(ShopVisual3D), findsOneWidget);
    expect(find.text('OBJETO 3D · AO VIVO'), findsOneWidget);
  });
}

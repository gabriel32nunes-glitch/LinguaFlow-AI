import 'package:flutter_test/flutter_test.dart';
import 'package:linguaflow_ai/retail_assistant.dart';

void main() {
  test('frases de vendas sao locais, completas e sem IDs repetidos', () {
    expect(retailReplies.length, greaterThanOrEqualTo(18));
    expect(retailReplies.map((r) => r.id).toSet().length, retailReplies.length);
    expect(retailReplies.every((r) =>
        r.pt.trim().isNotEmpty && r.en.trim().isNotEmpty), isTrue);
  });

  test('preco: nunca inventar valor', () {
    final suggestions = suggestRetailReplies('How much does it cost?');
    expect(suggestions.first.id, 'check_price');
    expect(suggestions.every((r) => !r.en.contains('50')), isTrue);
  });

  test('desconto: sugerir verificar sem prometer desconto', () {
    expect(suggestRetailReplies('Do you have a discount?').first.id,
        'check_discount');
  });

  test('tamanho: sugerir conferir tamanho', () {
    expect(suggestRetailReplies('Do you have this size?').first.id,
        'check_size');
    expect(suggestRetailReplies('Qual tamanho?').first.id, 'check_size');
  });

  test('cartao e troca identificados', () {
    expect(suggestRetailReplies('Can I pay by card?').first.id,
        'check_payment');
    expect(suggestRetailReplies('Posso fazer devolução?').first.id,
        'check_exchange');
  });

  test('entrega e estoque identificados', () {
    expect(suggestRetailReplies('Do you offer delivery?').first.id,
        'check_delivery');
    expect(suggestRetailReplies('Is it available?').first.id,
        'check_stock');
  });

  test('texto incompreensivel mostra respostas neutras', () {
    expect(suggestRetailReplies('...').first.id, 'moment');
    expect(suggestRetailReplies('').length, 4);
  });

  test('pesquisa local aceita acentos e categorias', () {
    expect(searchRetailReplies('preço').any((r) => r.id == 'check_price'), isTrue);
    expect(searchRetailReplies('cartao').any((r) => r.id == 'check_payment'), isTrue);
    expect(searchRetailReplies('', category: 'Trocas')
        .every((r) => r.category == 'Trocas'), isTrue);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:linguaflow_ai/work_phrases.dart';

void main() {
  test('biblioteca local nunca fica vazia', () {
    expect(workPhrases.length, greaterThanOrEqualTo(15));
    expect(workPhrases.every((p) => p.pt.isNotEmpty && p.en.isNotEmpty), isTrue);
    expect(workPhrases.map((p) => p.id).toSet().length, workPhrases.length);
  });

  test('busca encontra portugues e ingles sem rede', () {
    expect(findWorkPhrases('máquina').any((p) => p.id == 'stop'), isTrue);
    expect(findWorkPhrases('machine').any((p) => p.id == 'stop'), isTrue);
  });

  test('categoria restringe resultados', () {
    final result = findWorkPhrases('', category: 'Manutenção');
    expect(result, isNotEmpty);
    expect(result.every((p) => p.category == 'Manutenção'), isTrue);
  });

  test('frases prioritarias existem para seguranca', () {
    expect(workPhrases.where((p) => p.category == 'Segurança' && p.priority),
        isNotEmpty);
  });
}

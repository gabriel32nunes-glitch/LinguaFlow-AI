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

  test('reconhecimento local reconhece frase sem acento ou pontuacao', () {
    final matched = matchSpokenWorkPhrase('Pare a maquina imediatamente');
    expect(matched, isNotNull);
    expect(matched!.phrase.id, 'stop');
    expect(matched.inEnglish, isFalse);
  });

  test('reconhecimento bilingue indica a direcao correta', () {
    final matched = matchSpokenWorkPhrase('Stop the machine immediately');
    expect(matched, isNotNull);
    expect(matched!.inEnglish, isTrue);
    expect(matched.phrase.pt, contains('máquina'));
  });

  test('nao inventar traducao para frase desconhecida', () {
    expect(matchSpokenWorkPhrase('A temperatura da prensa agora e 93 graus'), isNull);
  });

  test('frases prioritarias existem para seguranca', () {
    expect(workPhrases.where((p) => p.category == 'Segurança' && p.priority),
        isNotEmpty);
  });
}

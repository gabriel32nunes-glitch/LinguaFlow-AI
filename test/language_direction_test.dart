import 'package:flutter_test/flutter_test.dart';
import 'package:linguaflow_ai/language_direction.dart';

void main() {
  test('troca automaticamente portugues e ingles', () {
    expect(resolveSourceLanguage(mode: 'auto', detectedTag: 'en-US'), SourceLanguage.english);
    expect(resolveSourceLanguage(mode: 'auto', detectedTag: 'pt-BR'), SourceLanguage.portuguese);
  });
  test('selecao manual tem prioridade sobre detector', () {
    expect(resolveSourceLanguage(mode: 'pt', detectedTag: 'en-US'), SourceLanguage.portuguese);
    expect(resolveSourceLanguage(mode: 'en', detectedTag: 'pt-BR'), SourceLanguage.english);
  });
  test('sem idioma confiavel nao produz traducao trocada', () {
    expect(resolveSourceLanguage(mode: 'auto', detectedTag: 'und'), isNull);
    expect(resolveSourceLanguage(mode: 'auto'), isNull);
    expect(resolveSourceLanguage(mode: 'auto', detectedTag: 'es-ES'), isNull);
  });
}

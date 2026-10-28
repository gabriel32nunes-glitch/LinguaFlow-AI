import 'package:flutter_test/flutter_test.dart';
import 'package:linguaflow_ai/language_library.dart';

void main() {
  test('catalogo contem 10 idiomas unicos e inclui portugues/ingles', () {
    expect(linguaLanguages.length, 10);
    expect(linguaLanguages.map((e) => e.code).toSet().length, 10);
    expect(getLinguaLanguage('pt-BR')?.name, 'Português');
    expect(getLinguaLanguage('en-US')?.name, 'Inglês');
  });
  test('reconhece codigos multilíngues e ignora idioma desconhecido', () {
    expect(getLinguaLanguage('zh-CN')?.code, 'zh');
    expect(getLinguaLanguage('HI-in')?.code, 'hi');
    expect(getLinguaLanguage('es-ES')?.code, 'es');
    expect(getLinguaLanguage('xx'), isNull);
  });
  test('catalogo nao chama pacote ausente de pronto', () {
    expect(packStateLabel(PackState.absent), 'Não instalado');
    expect(packStateLabel(PackState.installed), 'Pronto para traduzir');
  });
}

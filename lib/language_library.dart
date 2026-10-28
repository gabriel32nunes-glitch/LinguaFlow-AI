import 'package:google_mlkit_translation/google_mlkit_translation.dart';

/// Idiomas mais falados por total de falantes em 2026.
/// Estar no catalogo NAO significa que o modelo esteja instalado.
/// O reconhecimento de fala pertence ao motor Whisper; traducao ao ML Kit.
class LinguaLanguage {
  const LinguaLanguage(this.code, this.name, this.nativeName, this.translateCode);
  final String code;
  final String name;
  final String nativeName;
  final TranslateLanguage translateCode;
}

const linguaLanguages = <LinguaLanguage>[
  LinguaLanguage('en', 'Inglês', 'English', TranslateLanguage.english),
  LinguaLanguage('zh', 'Mandarim', '中文', TranslateLanguage.chinese),
  LinguaLanguage('hi', 'Hindi', 'हिन्दी', TranslateLanguage.hindi),
  LinguaLanguage('es', 'Espanhol', 'Español', TranslateLanguage.spanish),
  LinguaLanguage('ar', 'Árabe', 'العربية', TranslateLanguage.arabic),
  LinguaLanguage('fr', 'Francês', 'Français', TranslateLanguage.french),
  LinguaLanguage('bn', 'Bengali', 'বাংলা', TranslateLanguage.bengali),
  LinguaLanguage('pt', 'Português', 'Português', TranslateLanguage.portuguese),
  LinguaLanguage('id', 'Indonésio', 'Bahasa Indonesia', TranslateLanguage.indonesian),
  LinguaLanguage('ur', 'Urdu', 'اردو', TranslateLanguage.urdu),
];

LinguaLanguage? getLinguaLanguage(String? detected) {
  if (detected == null || detected.trim().isEmpty) return null;
  final code = detected.toLowerCase().replaceAll('_', '-').split('-').first;
  for (final language in linguaLanguages) {
    if (language.code == code) return language;
  }
  return null;
}

/// Um pacote e somente um modelo neural de traducao ML Kit. Voz e transcricao
/// sao recursos distintos, gerenciados separadamente.
enum PackState { unknown, checking, absent, installing, installed, failed }

String packStateLabel(PackState state) {
  switch (state) {
    case PackState.unknown: return 'Não verificado';
    case PackState.checking: return 'Verificando';
    case PackState.absent: return 'Não instalado';
    case PackState.installing: return 'Preparando pacote';
    case PackState.installed: return 'Pronto para traduzir';
    case PackState.failed: return 'Falha na instalação';
  }
}

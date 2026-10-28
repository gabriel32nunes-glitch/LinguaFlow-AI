enum SourceLanguage { portuguese, english }

/// Respeita a selecao manual. No modo automatico so aceita tags PT/EN.
SourceLanguage? resolveSourceLanguage({
  required String mode,
  String? detectedTag,
}) {
  final tag = (mode == 'pt' || mode == 'en' ? mode : detectedTag ?? '')
      .trim().toLowerCase().replaceAll('_', '-');
  if (tag == 'pt' || tag.startsWith('pt-')) {
    return SourceLanguage.portuguese;
  }
  if (tag == 'en' || tag.startsWith('en-')) {
    return SourceLanguage.english;
  }
  return null;
}

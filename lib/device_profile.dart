/// Configuracao leve para aparelhos como o Samsung Galaxy A14 4G.
/// Dados reais sao coletados no Android; nunca presumimos versao de SO ou RAM.
class DeviceProfile {
  const DeviceProfile({
    required this.sdkInt,
    required this.model,
    required this.manufacturer,
    required this.lowRamDevice,
    required this.memoryClassMb,
    required this.onDeviceSpeechAvailable,
    this.systemSpeechAvailable = false,
  });

  final int sdkInt;
  final String model;
  final String manufacturer;
  final bool lowRamDevice;
  final int memoryClassMb;
  final bool onDeviceSpeechAvailable;
  final bool systemSpeechAvailable;

  factory DeviceProfile.fromPlatform(Map<dynamic, dynamic> info) {
    int number(dynamic value) => value is num ? value.toInt() : 0;
    return DeviceProfile(
      sdkInt: number(info['sdkInt']),
      model: info['model']?.toString() ?? 'Desconhecido',
      manufacturer: info['manufacturer']?.toString() ?? 'Desconhecido',
      lowRamDevice: info['lowRamDevice'] == true,
      memoryClassMb: number(info['memoryClassMb']),
      onDeviceSpeechAvailable: info['onDeviceSpeechAvailable'] == true,
      systemSpeechAvailable: info['systemSpeechAvailable'] == true,
    );
  }

  bool get isGalaxyA14FourG =>
      manufacturer.toLowerCase().contains('samsung') &&
      model.toLowerCase().startsWith('sm-a145');

  /// API 34+ disponibiliza o pedido, mas o fabricante pode ignora-lo.
  bool get canRequestAutomaticLanguageSwitch => sdkInt >= 34;

  /// Em Android 12/13 o modo manual e mais seguro. Nunca rotular
  /// reconhecimento em PT como traducao automatica bilateral.
  String safeLanguageMode(String requested) {
    if (requested == 'auto' && !canRequestAutomaticLanguageSwitch) {
      return 'pt';
    }
    return requested == 'en' ? 'en' : requested == 'pt' ? 'pt' : 'auto';
  }

  int historyCapacity({required bool economyEnabled}) =>
      economyEnabled || lowRamDevice ? 8 : 12;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:linguaflow_ai/device_profile.dart';

void main() {
  test('Galaxy A14 4G Android 13 desativa autodeteccao nao suportada', () {
    final a14 = DeviceProfile.fromPlatform({
      'sdkInt': 33,
      'model': 'SM-A145M',
      'manufacturer': 'samsung',
      'memoryClassMb': 192,
      'lowRamDevice': false,
      'onDeviceSpeechAvailable': true,
    });
    expect(a14.isGalaxyA14FourG, isTrue);
    expect(a14.safeLanguageMode('auto'), 'pt');
    expect(a14.safeLanguageMode('en'), 'en');
    expect(a14.historyCapacity(economyEnabled: true), 8);
  });

  test('Android 14 permite solicitar autodeteccao sem prometer suporte', () {
    final a14 = DeviceProfile.fromPlatform({
      'sdkInt': 34, 'model': 'SM-A145F', 'manufacturer': 'Samsung',
      'onDeviceSpeechAvailable': false,
    });
    expect(a14.canRequestAutomaticLanguageSwitch, isTrue);
    expect(a14.safeLanguageMode('auto'), 'auto');
    expect(a14.onDeviceSpeechAvailable, isFalse);
  });

  test('modo memoria baixa reduz historico mesmo fora do A14', () {
    final phone = DeviceProfile.fromPlatform({
      'sdkInt': 35, 'model': 'Outro', 'manufacturer': 'Outro',
      'lowRamDevice': true, 'memoryClassMb': 96,
    });
    expect(phone.historyCapacity(economyEnabled: false), 8);
  });
}

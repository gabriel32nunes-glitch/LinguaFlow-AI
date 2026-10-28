"""Execute python setup_android.py após flutter create . --platforms android ."""
from pathlib import Path
import re
import shutil

root = Path(__file__).resolve().parent
android = root / 'android'
manifest = android / 'app/src/main/AndroidManifest.xml'
if not manifest.exists():
    raise SystemExit('Pasta Android ausente. Rode: flutter create . --platforms android')

# Preserva outros arquivos do template do Flutter; coloca MainActivity no pacote correto.
kotlin_file = android / 'app/src/main/kotlin/com/example/linguaflow_ai/MainActivity.kt'
kotlin_file.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(root / 'native_android/MainActivity.kt', kotlin_file)
shutil.copy2(root / 'native_android/AndroidManifest.xml', manifest)

# Template do Flutter recente usa Kotlin DSL (build.gradle.kts). Configure SDKs.
for p in (android / 'app/build.gradle.kts', android / 'app/build.gradle'):
    if not p.exists():
        continue
    build = p.read_text(encoding='utf-8')
    if p.suffix == '.kts':
        build = re.sub(r'compileSdk\s*=\s*flutter\.compileSdkVersion', 'compileSdk = 36', build)
        build = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 31', build)
        build = re.sub(r'targetSdk\s*=\s*flutter\.targetSdkVersion', 'targetSdk = 35', build)
    else:
        build = re.sub(r'compileSdkVersion\s+flutter\.compileSdkVersion', 'compileSdkVersion 36', build)
        build = re.sub(r'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 31', build)
        build = re.sub(r'targetSdkVersion\s+flutter\.targetSdkVersion', 'targetSdkVersion 35', build)
    # APKs oficiais usam a mesma chave guardada apenas em GitHub Secrets.
    # APKs experimentais continuam com a chave debug do Flutter.
    if p.suffix == '.kts':
        if 'linguaflowRelease' not in build:
            marker = '    buildTypes {'
            if marker not in build:
                raise SystemExit('Nao foi encontrado buildTypes no Gradle Kotlin DSL.')
            signing = """    signingConfigs {
        val signingPath = System.getenv("LINGUAFLOW_KEYSTORE_PATH")
        if (!signingPath.isNullOrBlank()) {
            create("linguaflowRelease") {
                storeFile = file(signingPath)
                storeType = "JKS"
                storePassword = System.getenv("LINGUAFLOW_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("LINGUAFLOW_KEY_ALIAS")
                keyPassword = System.getenv("LINGUAFLOW_KEY_PASSWORD")
            }
        }
    }

"""
            build = build.replace(marker, signing + marker, 1)
            debug = 'signingConfig = signingConfigs.getByName("debug")'
            if debug not in build:
                raise SystemExit('A configuracao de assinatura do Flutter mudou.')
            release = """signingConfig = if (
                    System.getenv("LINGUAFLOW_KEYSTORE_PATH").isNullOrBlank()
                ) signingConfigs.getByName("debug")
                  else signingConfigs.getByName("linguaflowRelease")"""
            build = build.replace(debug, release, 1)
    else:
        # Exigir Kotlin DSL ao produzir APK oficial.
        if 'LINGUAFLOW_KEYSTORE_PATH' in __import__('os').environ:
            raise SystemExit('Assinatura estavel exige Gradle Kotlin DSL.')

    # Erro explícito se o template padrão mudou (melhor que sobrescrever errado).
    if not re.search(r'(minSdk\s*=\s*31|minSdkVersion\s+31)', build):
        raise SystemExit('Atenção: o template Gradle mudou. Configure manualmente minSdk 31 em ' + str(p))
    p.write_text(build, encoding='utf-8')

# Excluir classe MainActivity criada pelo template em outro namespace, se existir,
# somente quando ela contém exclusivamente o exemplo padrão do Flutter.
for old in (android / 'app/src/main/kotlin').rglob('MainActivity.kt'):
    if old == kotlin_file:
        continue
    content = old.read_text(encoding='utf-8')
    if 'class MainActivity: FlutterActivity()' in content and len(content) < 300:
        old.unlink()

print('Android configurado: SDK 31+ (recursos automáticos 34+), MainActivity e permissões.')
print('Execute: flutter pub get')
print('Depois: flutter run')

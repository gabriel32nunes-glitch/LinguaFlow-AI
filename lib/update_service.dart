import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Uma atualizacao instalavel, publicada como APK em GitHub Releases.
/// O Android so aceita instalacao por cima se package ID e assinatura
/// coincidirem e versionCode nao diminuir.
class LinguaFlowRelease {
  const LinguaFlowRelease({
    required this.name,
    required this.buildNumber,
    required this.apkUrl,
    required this.description,
  });

  final String name;
  final int buildNumber;
  final Uri apkUrl;
  final String description;

  bool isNewerThan(int installedCode) => buildNumber > installedCode;

  /// So aceita release oficial deste repositorio e APK direto, nunca ZIP.
  static LinguaFlowRelease? fromGitHub(Map<String, dynamic> data) {
    if (data['draft'] == true || data['prerelease'] == true) return null;
    final tag = data['tag_name'];
    if (tag is! String) return null;
    final match = RegExp(r'^v?(\d+\.\d+\.\d+)\+(\d+)$')
        .firstMatch(tag);
    if (match == null) return null;
    final code = int.tryParse(match.group(2)!);
    if (code == null || code < 1) return null;

    final assets = data['assets'];
    if (assets is! List) return null;
    for (final asset in assets) {
      if (asset is! Map) continue;
      // A primeira release assinada foi publicada com o nome app-release.apk.
      // As proximas versoes podem usar o nome amigavel ARM64.
      const allowedApks = ['LinguaFlow-A14-arm64.apk', 'app-release.apk'];
      final name = asset['name'];
      if (name is! String || !allowedApks.contains(name)) continue;
      final raw = asset['browser_download_url'];
      if (raw is! String) continue;
      final uri = Uri.tryParse(raw);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'github.com' ||
          !uri.path.startsWith(
              '/gabriel32nunes-glitch/LinguaFlow-AI/releases/download/') ||
          !uri.path.endsWith('/$name')) {
        continue;
      }
      return LinguaFlowRelease(
        name: match.group(1)!,
        buildNumber: code,
        apkUrl: uri,
        description: data['body']?.toString() ?? '',
      );
    }
    return null;
  }
}

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.message,
    this.release,
  });
  final String message;
  final LinguaFlowRelease? release;
  bool get available => release != null;
}

class LinguaFlowUpdater {
  static final Uri _releaseEndpoint = Uri.parse(
    'https://api.github.com/repos/gabriel32nunes-glitch/'
    'LinguaFlow-AI/releases/latest',
  );

  /// A verificacao pode ser silenciosa ao abrir o app.
  /// O download so comeca depois do usuario tocar em Atualizar.
  Future<UpdateCheckResult> check() async {
    final info = await PackageInfo.fromPlatform();
    final installed = int.tryParse(info.buildNumber) ?? 0;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(_releaseEndpoint)
          .timeout(const Duration(seconds: 10));
      request.headers.set(HttpHeaders.userAgentHeader, 'LinguaFlow-A14-updater');
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close()
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 404) {
        return const UpdateCheckResult(
          message: 'Ainda não há atualizações oficiais publicadas.',
        );
      }
      if (response.statusCode != 200) {
        throw HttpException('GitHub retornou HTTP ${response.statusCode}');
      }
      final payload = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 10));
      final data = jsonDecode(payload);
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Resposta inesperada do GitHub.');
      }
      final release = LinguaFlowRelease.fromGitHub(data);
      if (release == null) {
        return const UpdateCheckResult(
          message: 'A versão publicada ainda não contém APK instalável assinado.',
        );
      }
      if (!release.isNewerThan(installed)) {
        return UpdateCheckResult(
          message: 'Você já usa a versão mais recente (build $installed).',
        );
      }
      return UpdateCheckResult(
        message: 'Versão ${release.name} disponível para atualizar.',
        release: release,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> openDownload(LinguaFlowRelease release) async {
    // Evita permissão REQUEST_INSTALL_PACKAGES no app.
    // O navegador baixa; Android mostra confirmação para atualizar.
    final opened = await launchUrl(release.apkUrl,
      mode: LaunchMode.externalApplication);
    if (!opened) {
      throw StateError('Não foi possível abrir o download oficial.');
    }
  }
}

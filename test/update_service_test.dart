import 'package:flutter_test/flutter_test.dart';
import 'package:linguaflow_ai/update_service.dart';

Map<String, dynamic> release({String tag = 'v0.10.0+10242', String? url}) => {
  'tag_name': tag,
  'draft': false,
  'prerelease': false,
  'body': 'Melhorias e correções',
  'assets': [
    {
      'name': 'LinguaFlow-A14-arm64.apk',
      'browser_download_url': url ??
          'https://github.com/gabriel32nunes-glitch/LinguaFlow-AI/'
          'releases/download/$tag/LinguaFlow-A14-arm64.apk',
    },
  ],
};

void main() {
  test('atualiza apenas quando o build for maior', () {
    final item = LinguaFlowRelease.fromGitHub(release())!;
    expect(item.name, '0.10.0');
    expect(item.isNewerThan(10241), isTrue);
    expect(item.isNewerThan(10242), isFalse);
    expect(item.isNewerThan(10243), isFalse);
  });

  test('nao aceita release em rascunho ou prerelease', () {
    expect(LinguaFlowRelease.fromGitHub({
      ...release(), 'draft': true,
    }), isNull);
    expect(LinguaFlowRelease.fromGitHub({
      ...release(), 'prerelease': true,
    }), isNull);
  });

  test('nao aceita URLs que nao sejam o apk oficial', () {
    expect(LinguaFlowRelease.fromGitHub(
      release(url: 'https://example.com/malware.apk')), isNull);
    expect(LinguaFlowRelease.fromGitHub(release(
      tag: 'v0.10.0+9',
      url: 'http://github.com/gabriel32nunes-glitch/LinguaFlow-AI/'
          'releases/download/v0.10.0+9/LinguaFlow-A14-arm64.apk',
    )), isNull);
    final wrong = release();
    (wrong['assets'] as List)[0]['name'] = 'old.zip';
    expect(LinguaFlowRelease.fromGitHub(wrong), isNull);
  });

  test('tag invalida nao e considerada atualizacao', () {
    expect(LinguaFlowRelease.fromGitHub(
      release(tag: 'v0.10.0')), isNull);
  });
}

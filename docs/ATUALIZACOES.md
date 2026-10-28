# Atualizações oficiais do LinguaFlow AI

## O que o usuário verá

O app mostra um cartão **ATUALIZAÇÕES**. Ao abrir uma versão de produção
(*release*), ele consulta as versões publicadas no GitHub, sem enviar o áudio.
Se existir um APK mais recente, aparece **Atualizar para vX.Y.Z**.

Ao tocar, o Android abre o download oficial no navegador e pede confirmação
para instalar. **Não existe instalação silenciosa de APK fora da loja**:
o usuário ainda precisa aceitar a atualização pelo Android.

## Condições para atualizar sem desinstalar

1. O **applicationId** deve permanecer idêntico ao da versão instalada.
2. Todas as versões devem usar o **mesmo certificado de assinatura**.
3. O **versionCode** da atualização deve ser maior que o já instalado.
4. O Android pode pedir uma confirmação do instalador ou da origem do APK.

A troca da assinatura debug temporária das versões experimentais para uma
assinatura oficial permanente **pode exigir uma única reinstalação**.
Depois disso, as versões assinadas com a mesma chave atualizarão por cima.
Não perca a chave oficial nem altere o applicationId!

## Configuração da assinatura (uma única vez)

NUNCA faça commit do arquivo .jks, da senha ou da chave Base64.

1. Crie um keystore Android privado com alias `linguaflow`.
   O Java `keytool` pode ser executado em um ambiente de desenvolvimento
   confiável com `keytool -genkeypair -v -keystore linguaflow-upload.jks
   -alias linguaflow -keyalg RSA -keysize 3072 -validity 10000`.
   Defina e guarde uma senha forte.
2. Converta o arquivo .jks para Base64 em uma máquina confiável:
   no Linux `base64 -w 0 linguaflow-upload.jks`.
   No Windows, use um ambiente Java/PowerShell compatível.
3. No repositório, abra **Settings → Secrets and variables → Actions** e
   configure estes quatro secrets:
   - `LINGUAFLOW_KEYSTORE_BASE64`: conteúdo Base64 do arquivo .jks
   - `LINGUAFLOW_KEYSTORE_PASSWORD`: senha do keystore
   - `LINGUAFLOW_KEY_PASSWORD`: senha da chave (geralmente a mesma)
   - `LINGUAFLOW_KEY_ALIAS`: `linguaflow`
4. Guarde uma cópia privada do .jks e das senhas fora do GitHub.

**Os quatro secrets ainda precisam ser adicionados pelo proprietário.**
O assistente não consegue ler nem configurar secrets desta conexão GitHub.
O workflow falha com segurança se não estiverem configurados.

## Publicar uma nova versão

Depois que o código for testado, revisado e integrado à branch `main`:

1. Acesse **Actions → Publicar atualização assinada LinguaFlow → Run workflow**.
2. Informe a versão, por exemplo `1.0.0`.
3. O workflow testa, usa sempre o MESMO certificado e cria um
   **GitHub Release** com APK ARM64 `LinguaFlow-A14-arm64.apk`.
4. O `versionCode` é calculado automaticamente a partir da execução.
5. O app consulta **Releases/latest** e oferece o APK novo.

Somente versões de produção publicadas em Releases serão oferecidas.
**Artefatos de testes e PRs não serão oferecidos como atualizações.**

## Segurança e privacidade

- O app só abre um link HTTPS do repositório oficial, com nome de APK esperado.
- Não usa a permissão `REQUEST_INSTALL_PACKAGES` nem instala silenciosamente.
- O Android verifica a assinatura do APK antes de atualizar.
- A verificação de versão não contém áudio, legendas ou conversas.
- Sem GitHub Release oficial, o botão apenas informa que não há atualização.
- A atualização NÃO resolve automaticamente bugs de reconhecimento/tradução:
  é somente a distribuição de uma nova versão.

# Testar o LinguaFlow no Samsung Galaxy A14 pelo VS Code (Windows)

**Objetivo:** usar o Galaxy A14 4G como aparelho de testes, espelhando sua tela no PC, sem baixar APKs do GitHub a cada alteração. O Flutter instala a versão de desenvolvimento diretamente pelo cabo USB. A versão **LinguaFlow DEV** tem identificador separado e não desinstala a versão oficial.

## 1. Preparar celular e computador (uma vez)

1. No Galaxy, abra **Configurações → Sobre o telefone → Informações do software → Número de compilação** e toque sete vezes.
2. Volte às configurações, abra **Opções do desenvolvedor** e ative **Depuração USB**.
3. Conecte o celular por **cabo USB de dados** ao Windows; no Galaxy, aceite **Permitir depuração USB**. Faça isso somente em computador confiável.
4. Instale as extensões **Flutter** e **Dart** no VS Code. O Android Studio fornece SDK e ferramentas Android, mas o **Flutter SDK** deve estar instalado e no PATH.
5. Para espelhar a tela, instale o **scrcpy** a partir de https://github.com/Genymobile/scrcpy/releases e abra `scrcpy.exe` com o Galaxy conectado. O scrcpy não é necessário para compilar; serve apenas para ver e controlar a tela.

## 2. Baixar o código (uma vez)

No terminal **PowerShell** do VS Code:

```powershell
git clone --branch feature/atendimento-loja-galaxy-a14 https://github.com/gabriel32nunes-glitch/LinguaFlow-AI.git
cd LinguaFlow-AI
flutter doctor -v
flutter devices
```

Se o comando `git` não existir, instale Git para Windows. Se o Flutter não existir, instale o Flutter SDK e configure o PATH. O comando `flutter doctor -v` mostrará o que falta.

## 3. Preparar o projeto e o modelo offline (uma vez)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\preparar_windows.ps1
```

O script prepara o Android, instala as dependências e baixa o modelo Whisper multilíngue com verificação SHA-256. Não usa a chave privada de assinatura nem os segredos do GitHub. Ele exige **Python 3**, além do Flutter SDK.

Se o download falhar, tente novamente com internet estável. O modelo Whisper não precisa ser baixado a cada execução.

## 4. Executar diretamente no Galaxy

```powershell
flutter devices
flutter run
```

Se aparecer mais de um dispositivo, use o identificador exibido:

```powershell
flutter run -d ID_DO_GALAXY
```

O aplicativo **LinguaFlow DEV** será instalado pelo Flutter e poderá coexistir com o LinguaFlow oficial. **Não desinstale o aplicativo oficial para testar.**

Com `flutter run` aberto:
- **`r`**: Hot Reload para alterações compatíveis de código Flutter/Dart.
- **`R`**: Hot Restart, reinicia a execução Dart.
- **`q`**: encerra a sessão de depuração.

Alterações em código nativo, plugins ou configurações Android podem exigir uma nova compilação com `flutter run`; isso não exige baixar um APK manualmente.

## 5. Teste real de atendimento em loja

1. Abra **LinguaFlow DEV** e permita o microfone.
2. Ative **Modo atendimento em loja**, selecione **Inglês** e confirme que as pessoas sabem que o microfone está ligado.
3. Prepare os modelos de tradução **português/inglês** no próprio aplicativo, com internet na primeira vez.
4. Toque em **Iniciar atendimento** e peça a alguém para falar: **“How much does this cost?”**. Verifique o texto reconhecido e a tradução em português.
5. Toque na sugestão **“Vou confirmar o preço para você.”**. O aplicativo interrompe a escuta antes de falar, tenta reproduzir em inglês e retomar a escuta.
6. Digite em português **“Posso mostrar outras opções.”** e toque em **Traduzir e falar para o cliente**.
7. Repita com barulho de loja e diferentes distâncias do microfone.

**Limitações importantes:** a tradução por trechos não é simultânea sem atraso; o Galaxy A14 pode demorar para transcrever com Whisper. A voz depende de TTS offline instalado no Android. O app não deve inventar preço, estoque, descontos ou prazos. Para outros idiomas, instale o pacote de tradução correspondente; algumas vozes offline podem não existir no celular. O aplicativo não grava áudio para histórico por padrão.

## 6. Quando houver bug

Deixe `flutter run` aberto e copie as linhas do erro do terminal. Informe o que falou, qual idioma selecionou, o que apareceu na tela e qual resposta esperava. Envie esse trecho aqui para corrigirmos o código.

Não compartilhe senhas, `.jks`, Base64 da chave ou segredos de assinatura.

**Estado da branch:** protótipo para testes, não publicado como atualização oficial até a validação no Galaxy A14.

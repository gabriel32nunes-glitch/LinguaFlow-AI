# Zeluvori AI — tradução ao vivo com mascote Zelu

Zeluvori AI é a nova interface do projeto Flutter anteriormente chamado LinguaFlow AI. O código interno e o repositório conservam o nome técnico antigo por compatibilidade com a versão de desenvolvimento, testes e assinatura.

## Interface

- Tela inicial simples: idioma do cliente, mascote holográfico de partículas, fala reconhecida, tradução, microfone, sugestões e teclado.
- O mascote **Zelu** flutua, pisca, acena e reage à escuta e à fala TTS. Desenhado por Flutter CustomPainter, sem imagens ou animações externas.
- O reconhecimento de fala usa Whisper local integrado ao aplicativo.
- O texto é traduzido pelo Google ML Kit no aparelho; modelos podem exigir internet no primeiro download.
- O atendente pode digitar respostas em português ou usar sugestões comerciais seguras. O app tenta falar no idioma do cliente usando uma voz Android marcada como offline.
- As sugestões são frases predefinidas por palavras-chave, **não uma IA generativa**. O aplicativo não consulta preços, estoque ou condições reais.

## Testar no Samsung Galaxy A14 4G

Requer Windows, VS Code, Flutter, Python 3, Android Studio/SDK e Galaxy com depuração USB.

Para quem já clonou o projeto e preparou o Android:

```powershell
cd C:\Users\gabri\LinguaFlow-AI
git pull origin feature/atendimento-loja-galaxy-a14
py -3 setup_android.py
flutter pub get
flutter devices
flutter run
```

Se o terminal não reconhecer o Flutter:

```powershell
$env:Path = "C:\flutter\bin;$env:Path"
```

Se for a primeira preparação, rode `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\preparar_windows.ps1` antes do `flutter run`. Instruções completas em [docs/TESTAR_GALAXY_VSCODE.md](docs/TESTAR_GALAXY_VSCODE.md).

## Como testar

1. Conecte o Galaxy por USB e inicie o app **Zeluvori DEV** pelo `flutter run`.
2. Selecione **Inglês** como idioma do cliente e avise a pessoa sobre o microfone.
3. Toque no microfone e peça: "How much does this cost?".
4. Confira a fala original e a tradução. Se os modelos de tradução não estiverem prontos, use Configurações → Preparar português e inglês.
5. Abra **Sugestões** e selecione "Vou confirmar o preço para você" para testar a voz em inglês.
6. Use **Teclado** para digitar outra resposta em português e traduzi-la/falá-la.

## Limitações atuais

- A tradução ocorre por segmentos; não é interpretação simultânea perfeita.
- A voz exige que o Android tenha uma voz offline disponível para o idioma escolhido.
- O reconhecimento Whisper e a tradução ML Kit são mecanismos diferentes: ter o idioma no catálogo não garante o modelo de tradução ou a voz.
- Não é um agente conversacional com raciocínio livre nem uma IA generativa.
- Os testes automatizados verificam a interface e a instalação Android, mas qualidade do áudio, latência e microfone devem ser testados no Galaxy real.
- O app funciona em primeiro plano e precisa do consentimento das pessoas presentes.

## Arquivos importantes

- `lib/zeluvori_home.dart`: nova interface e mascote animado.
- `lib/main.dart`: controlador de reconhecimento, tradução, voz e tela principal.
- `lib/retail_assistant.dart`: sugestões comerciais determinísticas.
- `native_android/AndroidManifest.xml`: nome do app, permissões e Activity.
- `setup_android.py`: configura o projeto Android e a variante DEV.
- `test/zeluvori_home_test.dart`: teste da nova tela.

**O código está em uma branch de testes. Não publique como versão oficial antes de validar no Galaxy A14.**

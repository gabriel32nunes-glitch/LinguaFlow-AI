# LinguaFlow AI Grátis (V0.2) — Android / Flutter

## O que esta edição faz

Um único botão inicia uma conversa que tenta reconhecer automaticamente PT-BR e EN-US, traduzir em ambas as direções e falar a tradução pela voz local do Android, **sem cadastro, cartão, chave de API, Supabase ou cobrança por minuto**. O texto traduzido fica na tela. Depois de cada frase a escuta reinicia automaticamente; você não toca na tela a cada frase.

**IMPORTANTE — protótipo sem build/teste real:** a troca de idiomas de `SpeechRecognizer` (Android 14+, API 34) é *opcional* para os fornecedores de reconhecimento. Alguns celulares ignoram o pedido. Requer reconhecimento de voz **no aparelho** + modelos de fala em português e inglês. Por isso **não é possível prometer tradução bilateral automática perfeita ou compatibilidade universal**. No Android 12/13 ou sem reconhecedor local compatível, o app informa incompatibilidade, sem ativar serviços pagos.

A captação **é suspensa durante a reprodução** para impedir o áudio de tradução de virar nova entrada. Frases de outras pessoas durante esse intervalo podem ser perdidas. Não há promessa de simultaneidade contínua sem cortes. Com tela bloqueada/navegando fora do app a escuta é interrompida; serviço foreground de microfone será uma etapa posterior.

## Tecnologias e custos

- Áudio → texto: `SpeechRecognizer.createOnDeviceSpeechRecognizer()` do Android, *somente on-device*.
- Idioma: evento de detecção automática do Android 14; fallback por identificação local de texto (`google_mlkit_language_id`).
- Tradução: Google ML Kit `google_mlkit_translation`, SDK gratuito que baixa modelos uma vez e traduz no aparelho.
- Texto → voz: `flutter_tts` via motor Android; o código **seleciona apenas vozes que o Android marca como offline**. Se não houver voz offline, mostra as legendas sem fala.
- Não há OpenAI API, Google Cloud Translation, Supabase, login, servidor ou assinatura.
- O primeiro download dos modelos requer Wi-Fi/Internet e ocupa armazenamento. Após a instalação dos modelos, a tradução de texto ocorre localmente. O reconhecimento on-device depende de idiomas/arquivos de sistema disponíveis.
- Desenvolver é gratuito; publicar na Play Store pode envolver taxa de cadastro da loja.

## Requisitos

- Windows 10/11 + Flutter SDK (Dart >=3.8), Android Studio SDK, VS Code, cabo/depuração USB.
- Android 14 ou superior para a **tentativa** de detecção/troca automática (e aparelho com reconhecedor de fala local instalado). A instalação permite Android 12+ porém a sessão automática será recusada abaixo de 14.
- Modelos de reconhecimento e vozes PT-BR / EN-US instalados em **Configurações > Idiomas / Reconhecimento de fala offline / Conversão de texto em voz**, conforme a marca do aparelho.
- `compileSdk` / `targetSdk` 35 e `minSdk` 31. **Caso plugin ou template exija compileSdk 36, atualize conforme o compilador.**

## Instalação (CMD do Windows no VS Code)

1. Extraia todo o ZIP em uma pasta. Em VS Code, **Arquivo > Abrir pasta**.
2. Abra **Terminal > Novo terminal** e selecione `Command Prompt (CMD)`.
3. Rode na pasta raiz:

```cmd
flutter doctor
flutter create . --platforms android
python setup_android.py
flutter pub get
flutter devices
flutter run
```

> Caso `python` não exista, instale Python 3.12+ ou utilize `py setup_android.py`.
>
> Se `flutter doctor` indicar problemas com Android SDK ou licenças, resolva antes de `flutter run`.

**Não rode `flutter create` depois de `setup_android.py`**, pois ele pode reescrever o projeto Android. Se precisar fazê-lo, rode `python setup_android.py` novamente.

## Primeiro teste

1. No Android 14+, use Wi-Fi para baixar os idiomas de reconhecimento **PT-BR e EN-US** e as vozes de TTS offline. O menu exato varia por marca e serviço do aparelho.
2. Abra o app, marque o consentimento informado dos participantes e pressione **Iniciar tradução automática** uma única vez.
3. A primeira iniciação pode baixar os modelos locais de tradução; sem Wi-Fi os downloads podem falhar.
4. Pessoa A fala **inglês**; veja tradução em português e escute no alto-falante (se houver voz offline).
5. Ao fim do áudio, pessoa B responde em **português**; o aplicativo tentará identificar e traduzir para inglês. Repita alternadamente.
6. Finalize com **Encerrar escuta**. Não use sem avisar os participantes ou para instruções de risco.

### Limitações conhecidas

- Android implementa reconhecimento de fala por segmentos e pode fazer pausas/sons de inicialização. Não é captura realmente ininterrupta; há **reinício automático**, sem intervenção manual por frase.
- O provedor local pode ignorar a alternância PT/EN; o código tenta pedir alternância de idioma mas não controla a compatibilidade.
- Tradução local pode cometer erros, especialmente em frases curtas, nomes próprios, sotaques ou ruído.
- Sem vozes offline instaladas, apenas legendas. Vozes marcadas como remotas nunca são escolhidas pelo projeto.
- Um celular não consegue separar falantes perfeitamente e não consegue ouvir novas falas enquanto reproduz sua própria tradução neste protótipo.
- O estado atual funciona **somente em primeiro plano**. Uso no bolso/tela desligada exige foreground service e testes específicos.
- Não armazena gravações, transcrições nem usa servidor próprio; dados podem ser tratados pelo sistema operacional para fornecer o motor local.

## Arquivos

- `lib/main.dart`: interface, tradução ML Kit, identificação de idioma, TTS e orquestração.
- `native_android/MainActivity.kt`: reconhecimento de voz estritamente on-device Android, troca PT/EN e retomada automática após tradução.
- `native_android/AndroidManifest.xml`: microfone, consultas de fala/TTS e rede somente para download de modelos.
- `setup_android.py`: aplica os arquivos nativos ao template Android gerado pelo Flutter.

## Fontes técnicas

- Android `SpeechRecognizer` (local): https://developer.android.com/reference/android/speech/SpeechRecognizer
- Android `RecognizerIntent` (troca idiomas): https://developer.android.com/reference/android/speech/RecognizerIntent
- ML Kit gratuito: https://developers.google.com/ml-kit/guides
- ML Kit tradução local: https://developers.google.com/ml-kit/language/translation/android
- Flutter ML Kit: https://pub.dev/packages/google_mlkit_translation
- flutter_tts: https://pub.dev/packages/flutter_tts

**Esta versão substitui a variante V0.1 com OpenAI/Supabase, não sendo necessário instalar, configurar ou pagar qualquer API.**

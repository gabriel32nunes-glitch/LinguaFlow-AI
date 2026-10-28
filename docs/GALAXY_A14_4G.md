# LinguaFlow AI V0.6 — Perfil Galaxy A14 4G

## Objetivo

O Galaxy A14 4G pode ter diferentes variantes de processador e atualizacoes
Android. **O aplicativo le as capacidades reais no aparelho**, em vez de
presumir a versao do Android, a RAM total ou a existencia de voz offline.

Esta V0.6 **nao e uma promessa de traducao bilateral continua funcionando**.
Ela melhora estabilidade, economia e diagnostico no hardware de entrada.

## Otimizacoes aplicadas

- Detecta modelo, fabricante, API Android, limite de heap por app e disponibilidade
  do servico de reconhecimento local, sem pedir internet.
- Habilita por padrao **modo economico** (configuravel): eventos parciais do microfone
  no maximo a cada 800 ms; retomadas apos silencio com espera de 1,8–5,7 s,
  evitando requisicoes rapidas e drenagem de bateria.
- Historico temporario limitado a **8 itens** em economia (12 fora dela).
- Se a API Android for menor que 34 e a escolha for Auto, seleciona **portugues
  manual**, com explicacao clara de que a troca PT/EN exige mudar o seletor
  antes da sessao. Nao finge ter detectado ingles.
- Android 14+ apenas **permite solicitar** deteccao/troca; o provedor de voz
  pode ignorar. O modo PT ou EN e recomendado se isso acontecer.
- Erro de limite do reconhecedor (ERROR_TOO_MANY_REQUESTS) encerra a sessao
  e informa o problema em vez de reiniciar em loop.
- Modelos de traducao ML Kit **nao baixam automaticamente**. Se ausentes,
  existe contingencia de frases profissionais predefinidas e botao de microfone
  de diagnostico. As frases prontas escritas funcionam sem reconhecimento de voz.

## Teste real no A14 4G

1. Instale **apenas um APK resultante de workflow verde** da V0.6. Emulados
   API 33 e API 35 verificam instalacao e tela inicial, mas nao o microfone
   nem a traducao real.
2. Abra o app e confirme o modelo mostrado (normalmente SM-A145...).
3. Veja o numero **Android API**: se inferior a 34, a interface selecionara
   Portugues; escolha English manualmente antes de uma conversa nesse idioma.
4. Marque o consentimento e use **Testar microfone SEM traducao**.
5. Veja **Verificar modelos instalados**. Se faltar ingles ou portugues,
   traducoes livres do ML Kit continuam indisponiveis ate download correto.
6. Teste **frases profissionais** no cartao, mesmo sem ML Kit.
7. Para avaliar conversa bilateral, desative o modo economico somente se
   for necessario e monitore bateria/aquecimento. Fale uma pessoa por vez.
8. Se houver erro, registre **texto exato do aviso**, API e modelo mostrados;
   nao e preciso compartilhar gravacoes privadas.

## Limites e seguranca

- Sem API paga, sem registro de conversas em servidor, sem gravacao escondida.
- O reconhecimento local e uma capacidade opcional do provedor do Android.
- A traducao livre PT/EN ainda depende dos pacotes do Google ML Kit. **O problema
  original do download nao esta definitivamente resolvido.**
- A escuta pausa durante o TTS para evitar eco: nao e simultanea e nao continua
  com tela bloqueada.
- Frases criticas de seguranca devem ser confirmadas por pessoas antes de agir.

## Como validar

Em CI, a PR roda testes Flutter, compila o APK e tenta abrir em emuladores
Android 13 e 15. Os arquivos APK sao apenas **experimentais**; um teste verde
nao significa traducao validada no Samsung real.

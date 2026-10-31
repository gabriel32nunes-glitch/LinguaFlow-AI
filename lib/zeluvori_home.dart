part of 'main.dart';

/// Tela principal enxuta: o desenho do mascote e feito em Flutter,
/// sem imagens, videos ou dependencias adicionais.
class ZeluvoriHome extends StatefulWidget {
  const ZeluvoriHome({super.key});

  @override
  State<ZeluvoriHome> createState() => _ZeluvoriHomeState();
}

class _ZeluvoriHomeState extends State<ZeluvoriHome> {
  final TranslationController controller = TranslationController();
  final TextEditingController _replyInput = TextEditingController();
  bool _microphoneConsent = false;
  bool _replyBusy = false;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    controller.addListener(_refresh);
    controller.setAutoDetectSpeech(true);
    controller.setAudioEnabled(false); // Evita que o Whisper escute o TTS.
    unawaited(controller.inspectDevice());
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    _replyInput.dispose();
    controller.dispose();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    if (_replyBusy || controller.busy) return;
    if (controller.running) {
      await controller.stop();
      return;
    }
    if (!_microphoneConsent) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF111D35),
          title: const Text('Ativar a escuta ao vivo?'),
          content: const Text(
            'O microfone capta as pessoas perto do celular. '
            'Avise o cliente antes de começar. '
            'O reconhecimento Whisper funciona no aparelho; '
            'os modelos de tradução podem precisar de download inicial.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Iniciar'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
      _microphoneConsent = true;
    }
    await controller.start();
  }

  Future<void> _sendReply(String pt, {String? preparedEnglish}) async {
    if (_replyBusy || controller.busy || pt.trim().isEmpty) return;
    final wasListening = controller.running;
    setState(() {
      _replyBusy = true;
      _feedback = null;
    });
    try {
      if (wasListening) await controller.stop();
      final success = await controller.speakRetailResponse(
        pt,
        preparedEnglish: preparedEnglish,
      );
      if (!mounted) return;
      _feedback = success
          ? controller.warning
          : (controller.warning ?? 'Nao foi possivel preparar a resposta.');
      if (wasListening && _microphoneConsent) {
        await controller.start();
        if (!controller.running) {
          _feedback = controller.warning ?? 'Nao foi possivel retomar a escuta.';
        }
      }
    } catch (error) {
      _feedback = 'Falha ao responder: $error';
    } finally {
      if (mounted) setState(() => _replyBusy = false);
    }
  }

  TranslationTurn? get _lastCustomer {
    for (final turn in controller.history) {
      if (turn.fromEnglish) return turn;
    }
    return null;
  }

  TranslationTurn? get _lastReply {
    for (final turn in controller.history) {
      if (!turn.fromEnglish) return turn;
    }
    return null;
  }

  void _openLanguages() {
    if (controller.running || controller.busy || _replyBusy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pare a escuta antes de trocar o idioma.')),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0C1830),
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.65,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Idioma do cliente',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text(
                  'A fala em português será traduzida para o idioma escolhido. '
                  'Os pacotes de tradução precisam estar disponíveis.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF9FB7D3), fontSize: 12),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final language in linguaLanguages)
                      if (language.code != 'pt')
                        ListTile(
                          leading: Icon(
                            controller.selectedSource == language.code
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: const Color(0xFF42D9FF),
                          ),
                          title: Text(language.name),
                          onTap: () {
                            controller.selectSource(language.code);
                            controller.selectTarget('pt');
                            Navigator.pop(sheetContext);
                          },
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0C1830),
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Configurações essenciais',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.language_rounded,
                    color: Color(0xFF48D8FF)),
                title: const Text('Preparar português e inglês'),
                subtitle: const Text(
                    'Baixa modelos de tradução no próprio aplicativo.'),
                enabled: !controller.running && !controller.busy,
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(controller.prepareModels());
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.hearing_rounded,
                    color: Color(0xFF48D8FF)),
                title: const Text('Testar somente o microfone'),
                subtitle: const Text('Reconhece a fala sem traduzir.'),
                enabled: !controller.running && !controller.busy,
                onTap: () async {
                  Navigator.pop(sheetContext);
                  if (!_microphoneConsent) {
                    await _toggleListening();
                  } else {
                    await controller.start(microphoneOnly: true);
                  }
                },
              ),
              Text(controller.packFeedback,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF9FB7D3))),
              const SizedBox(height: 12),
              const Text(
                'As respostas sugeridas são frases predefinidas, '
                'não uma IA generativa. Não inventam preços ou estoque.',
                style: TextStyle(fontSize: 12, color: Color(0xFF9FB7D3)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSuggestions() {
    final speech = _lastCustomer?.source ?? controller.original;
    final suggestions = suggestRetailReplies(speech);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0C1830),
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Respostas rápidas',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              for (final reply in suggestions)
                ListTile(
                  leading: const Icon(Icons.volume_up_rounded,
                      color: Color(0xFF51DFFF)),
                  title: Text(reply.pt),
                  subtitle: Text(
                    controller.selectedSource == 'en'
                        ? reply.en
                        : 'Traduzir para o idioma do cliente',
                    style: const TextStyle(color: Color(0xFF92ABC9)),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    unawaited(_sendReply(
                      reply.pt,
                      preparedEnglish: reply.en,
                    ));
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openKeyboard() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0C1830),
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          20, 10, 20, MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Responder em português',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
              controller: _replyInput,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(
                hintText: 'Ex.: Vou verificar o preço para você.',
                filled: true,
                fillColor: const Color(0xFF152740),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  final text = _replyInput.text.trim();
                  if (text.isEmpty) return;
                  Navigator.pop(sheetContext);
                  unawaited(_sendReply(text));
                },
                icon: const Icon(Icons.volume_up_rounded),
                label: const Text('TRADUZIR E FALAR'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _stateLabel {
    if (controller.speaking) return 'FALANDO COM O CLIENTE';
    if (_replyBusy || controller.busy) return 'PROCESSANDO...';
    if (controller.running) return 'OUVINDO...';
    return 'PRONTO PARA CONVERSAR';
  }

  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF47DDFF);
    final customer = _lastCustomer;
    final reply = _lastReply;
    final language = getLinguaLanguage(controller.selectedSource);
    final lastText = controller.partial.trim();
    final statusActive = controller.running || controller.speaking;
    final small = MediaQuery.sizeOf(context).height < 740;
    final mascotHeight = small ? 192.0 : 244.0;

    return Scaffold(
      backgroundColor: const Color(0xFF050C1A),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 13, 15, 10),
              child: Row(
                children: [
                  const Icon(Icons.blur_on_rounded, color: cyan, size: 31),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ZELUVORI',
                            style: TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.4)),
                        Text('TRADUÇÃO EM TEMPO REAL',
                            style: TextStyle(
                                fontSize: 9,
                                color: cyan,
                                letterSpacing: 2.0)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Configurações',
                    onPressed: _openSettings,
                    icon: const Icon(Icons.tune_rounded,
                        color: Color(0xFFBDD5EC)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 17),
              child: Row(
                children: [
                  Expanded(
                    child: _LanguageTile(
                      title: 'VOCÊ FALA',
                      language: 'Português',
                      symbol: '🇧🇷',
                      onTap: null,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 9),
                    child: Icon(Icons.sync_alt_rounded, color: cyan, size: 22),
                  ),
                  Expanded(
                    child: _LanguageTile(
                      title: 'CLIENTE FALA',
                      language: language?.name ?? 'Inglês',
                      symbol: controller.selectedSource == 'en'
                          ? '🇺🇸'
                          : '🌐',
                      onTap: _openLanguages,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(17, 6, 17, 10),
                child: Column(
                  children: [
                    SizedBox(
                      height: mascotHeight,
                      width: double.infinity,
                      child: ZeluvoriMascot(
                        listening: controller.running,
                        speaking: controller.speaking,
                        hasSpeech: lastText.isNotEmpty,
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 15, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D1D37),
                        border: Border.all(
                          color: statusActive
                              ? cyan.withValues(alpha: 0.8)
                              : const Color(0xFF244361),
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            controller.speaking
                                ? Icons.graphic_eq_rounded
                                : controller.running
                                    ? Icons.hearing_rounded
                                    : Icons.circle_outlined,
                            size: 17,
                            color: cyan,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _stateLabel,
                              style: const TextStyle(
                                fontSize: 11,
                                letterSpacing: 1.3,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SpeechPanel(
                      label: 'CLIENTE',
                      symbol: controller.selectedSource == 'en'
                          ? '🇺🇸' : '🌐',
                      text: lastText.isNotEmpty
                          ? lastText
                          : customer?.source ??
                              'A fala do cliente aparece aqui.',
                      highlighted: false,
                    ),
                    const SizedBox(height: 10),
                    _SpeechPanel(
                      label: 'TRADUÇÃO · PORTUGUÊS',
                      symbol: '🇧🇷',
                      text: customer?.translation ??
                          'A tradução aparece aqui automaticamente.',
                      highlighted: true,
                    ),
                    if (reply != null) ...[
                      const SizedBox(height: 10),
                      _SpeechPanel(
                        label: 'SUA ÚLTIMA RESPOSTA',
                        symbol: '🔊',
                        text: reply.translation,
                        highlighted: false,
                      ),
                    ],
                    if (controller.warning != null || _feedback != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _feedback ?? controller.warning!,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFFFC78B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (controller.busy) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(minHeight: 2),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      controller.running
                          ? 'Escuta contínua ativa. Toque no microfone para parar.'
                          : 'Toque no microfone para começar.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Color(0xFF829DBB), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFF081326),
                border: Border(
                    top: BorderSide(color: Color(0xFF1D3D5A))),
              ),
              padding: const EdgeInsets.fromLTRB(19, 11, 19, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _BottomAction(
                    icon: Icons.lightbulb_outline_rounded,
                    label: 'SUGESTÕES',
                    onTap: _replyBusy ? null : _openSuggestions,
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: cyan.withValues(alpha: 0.30),
                              blurRadius: 22,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                        child: IconButton.filled(
                          tooltip: controller.running
                              ? 'Parar escuta' : 'Iniciar escuta',
                          onPressed: controller.busy || _replyBusy
                              ? null : _toggleListening,
                          style: IconButton.styleFrom(
                            backgroundColor: controller.running
                                ? const Color(0xFFED6988) : cyan,
                            foregroundColor: const Color(0xFF071322),
                            fixedSize: const Size(74, 74),
                          ),
                          icon: Icon(
                            controller.running
                                ? Icons.stop_rounded : Icons.mic_rounded,
                            size: 33,
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        controller.running ? 'PARAR' : 'INICIAR',
                        style: const TextStyle(
                          fontSize: 11,
                          color: cyan,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  _BottomAction(
                    icon: Icons.keyboard_rounded,
                    label: 'TECLADO',
                    onTap: _replyBusy ? null : _openKeyboard,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.title,
    required this.language,
    required this.symbol,
    required this.onTap,
  });

  final String title;
  final String language;
  final String symbol;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF0D1E38),
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(17),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF28628D)),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              children: [
                Text(symbol, style: const TextStyle(fontSize: 21)),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: Color(0xFF8AAFCB),
                              fontSize: 9,
                              letterSpacing: 0.7)),
                      Text(language,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                ),
                if (onTap != null)
                  const Icon(Icons.expand_more_rounded,
                      color: Color(0xFF47DDFF), size: 18),
              ],
            ),
          ),
        ),
      );
}

class _SpeechPanel extends StatelessWidget {
  const _SpeechPanel({
    required this.label,
    required this.symbol,
    required this.text,
    required this.highlighted,
  });
  final String label;
  final String symbol;
  final String text;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 15),
        decoration: BoxDecoration(
          color: highlighted
              ? const Color(0xFF0C2541)
              : const Color(0xFF0D192E),
          border: Border.all(
            color: highlighted
                ? const Color(0xFF36CFFF)
                : const Color(0xFF245178),
          ),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(symbol, style: const TextStyle(fontSize: 17)),
                const SizedBox(width: 7),
                Text(label,
                    style: TextStyle(
                      color: highlighted
                          ? const Color(0xFF4BDAFF)
                          : const Color(0xFF9ABAD2),
                      fontSize: 10,
                      letterSpacing: 1.0,
                      fontWeight: FontWeight.w800,
                    )),
              ],
            ),
            const SizedBox(height: 7),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(
                text,
                key: ValueKey(text),
                style: TextStyle(
                  color: highlighted
                      ? const Color(0xFFB8F3FF) : Colors.white,
                  fontSize: 17,
                  height: 1.25,
                  fontWeight: highlighted
                      ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
}

class _BottomAction extends StatelessWidget {
  const _BottomAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 88,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 47,
                height: 47,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF102542),
                  border: Border.all(color: const Color(0xFF3482B6)),
                ),
                child: Icon(icon, color: const Color(0xFF66E2FF), size: 23),
              ),
              const SizedBox(height: 7),
              Text(label,
                  style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFFC1D7EA),
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );
}

/// Mascote Zelu: particulas pintadas por codigo, orbita e rosto expressivo.
/// Movimento de escuta, fala e repouso. Sem asset pesado ou modelo 3D.
class ZeluvoriMascot extends StatefulWidget {
  const ZeluvoriMascot({
    super.key,
    required this.listening,
    required this.speaking,
    required this.hasSpeech,
  });

  final bool listening;
  final bool speaking;
  final bool hasSpeech;

  @override
  State<ZeluvoriMascot> createState() => _ZeluvoriMascotState();
}

class _ZeluvoriMascotState extends State<ZeluvoriMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2300),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: widget.speaking
            ? 'Zelu falando'
            : widget.listening
                ? 'Zelu ouvindo'
                : 'Zelu aguardando',
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) => CustomPaint(
              painter: _ZeluPainter(
                phase: _pulse.value,
                listening: widget.listening,
                speaking: widget.speaking,
                hasSpeech: widget.hasSpeech,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
}

class _ZeluPainter extends CustomPainter {
  _ZeluPainter({
    required this.phase,
    required this.listening,
    required this.speaking,
    required this.hasSpeech,
  });
  final double phase;
  final bool listening;
  final bool speaking;
  final bool hasSpeech;

  static const _cyan = Color(0xFF36D8FF);
  static const _violet = Color(0xFF9B6BFF);

  @override
  void paint(Canvas canvas, Size size) {
    final t = phase * math.pi * 2;
    final center = Offset(size.width / 2, size.height / 2);
    final scale = math.min(size.width / 330, size.height / 270);
    canvas.save();
    canvas.translate(center.dx, center.dy + math.sin(t) * 4 * scale);
    canvas.scale(scale);

    final aura = Paint()
      ..color = _cyan.withValues(alpha: listening ? 0.28 : 0.13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    for (var i = 0; i < 3; i++) {
      final radius = 106.0 + i * 12 +
          (listening ? math.sin(t + i) * 4 : 0);
      canvas.drawCircle(const Offset(0, -8), radius, aura
        ..color = (i.isEven ? _cyan : _violet)
            .withValues(alpha: 0.22 - i * 0.045));
    }

    // A linha horizontal reage ao estado de escuta e fala.
    for (var i = -16; i <= 16; i++) {
      final x = i * 9.4;
      final height = (speaking ? 24 : listening ? 15 : 6) *
          (0.35 + 0.65 * math.sin(i * 1.8 + t * 2).abs());
      canvas.drawLine(
        Offset(x, 104 - height / 2),
        Offset(x, 104 + height / 2),
        Paint()
          ..color = _cyan.withValues(alpha: 0.25 + height / 38)
          ..strokeWidth = 1.7
          ..strokeCap = StrokeCap.round,
      );
    }

    // Corpo pequeno, arredondado, composto por pontos.
    for (var y = 65.0; y <= 121; y += 8.5) {
      for (var x = -62.0; x <= 62; x += 8.5) {
        final ellipse = x * x / (62 * 62) +
            (y - 83) * (y - 83) / (49 * 49);
        if (ellipse > 1) continue;
        _dot(canvas, x, y, 1.6, (x > 0 ? _violet : _cyan)
            .withValues(alpha: 0.64));
      }
    }

    // Cabeca holografica feita de centenas de pontos.
    for (var y = -91.0; y <= 64; y += 8.2) {
      for (var x = -92.0; x <= 92; x += 8.2) {
        final shape = x * x / (94 * 94) +
            (y + 13) * (y + 13) / (84 * 84);
        if (shape > 1) continue;
        if (x.abs() < 69 && y > -42 && y < 42) continue;
        final shimmer = 0.68 + 0.28 * math.sin(t + x * 0.05 + y * 0.04);
        _dot(canvas, x, y, 1.4 + shimmer * 0.5,
            (x > 0 ? _violet : _cyan).withValues(alpha: shimmer));
      }
    }

    // Contorno e laterais do mascote.
    final outline = Paint()
      ..color = _cyan.withValues(alpha: 0.9)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(0, -13), width: 191, height: 171),
        outline);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-110, -26, 20, 47),
        const Radius.circular(11),
      ),
      Paint()..color = _cyan.withValues(alpha: 0.7),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(90, -26, 20, 47),
        const Radius.circular(11),
      ),
      Paint()..color = _violet.withValues(alpha: 0.8),
    );

    // Olhos sorridentes; boca abre e fecha enquanto fala.
    final face = Paint()
      ..color = const Color(0xFFB8F8FF)
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawArc(
      Rect.fromCenter(
          center: const Offset(-34, -14), width: 28, height: 19),
      math.pi, math.pi, false, face,
    );
    canvas.drawArc(
      Rect.fromCenter(
          center: const Offset(34, -14), width: 28, height: 19),
      math.pi, math.pi, false, face,
    );
    if (speaking) {
      canvas.drawOval(
        Rect.fromCenter(
          center: const Offset(0, 25),
          width: 16 + 5 * math.sin(t * 3).abs(),
          height: 9 + 12 * math.sin(t * 3).abs(),
        ),
        face,
      );
    } else {
      canvas.drawArc(
        Rect.fromCenter(
            center: const Offset(0, 13), width: 31, height: 24),
        0, math.pi, false, face,
      );
    }

    // Braco acenando; o aceno fica mais forte durante a fala.
    final hand = Paint()
      ..color = _cyan.withValues(alpha: 0.8)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final wave = math.sin(t * (speaking ? 2 : 1)) *
        (speaking ? 13 : 5);
    final shoulder = const Offset(60, 80);
    final elbow = Offset(102, 52 + wave);
    final fingertip = Offset(126, 18 + wave);
    canvas.drawLine(shoulder, elbow, hand);
    canvas.drawLine(elbow, fingertip, hand);
    canvas.drawCircle(fingertip, 8, Paint()
      ..color = _violet.withValues(alpha: 0.9));
    canvas.restore();
  }

  void _dot(Canvas canvas, double x, double y, double radius, Color color) {
    canvas.drawCircle(Offset(x, y), radius, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ZeluPainter oldDelegate) =>
      phase != oldDelegate.phase ||
      listening != oldDelegate.listening ||
      speaking != oldDelegate.speaking ||
      hasSpeech != oldDelegate.hasSpeech;
}

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
  ShopVisualItem? _activeVisual;
  String? _lastVisualTrigger;
  String? _dismissedVisualId;
  String _seenPartial = '';
  String _seenHeard = '';
  String _seenHistory = '';

  @override
  void initState() {
    super.initState();
    controller.addListener(_refresh);
    // O controlador ja inicia com detecao automatica e audio automatico
    // desligado para impedir eco no microfone.
    unawaited(controller.inspectDevice());
  }

  void _refresh() {
    if (!mounted) return;
    // Processar apenas textos NOVOS: uma fala antiga nao pode substituir
    // o objeto atual quando a legenda parcial some ou muda.
    final changed = <String>[];
    final partial = controller.partial.trim();
    final heard = controller.heardText.trim();
    final history = controller.history.isNotEmpty
        ? controller.history.first.source.trim() : '';
    if (partial != _seenPartial) {
      _seenPartial = partial;
      if (partial.isNotEmpty) changed.add(partial);
    }
    if (heard != _seenHeard) {
      _seenHeard = heard;
      if (heard.isNotEmpty) changed.add(heard);
    }
    if (history != _seenHistory) {
      _seenHistory = history;
      if (history.isNotEmpty) changed.add(history);
    }
    for (final phrase in changed.reversed) {
      final item = ShopVisualCatalog.detect(phrase);
      if (item == null) continue;
      final trigger = item.id + ':' + ShopVisualCatalog.normalize(phrase);
      if (trigger != _lastVisualTrigger &&
          item.id != _dismissedVisualId) {
        _activeVisual = item;
        _lastVisualTrigger = trigger;
      }
      break;
    }
    setState(() {});
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
            'os modelos de tradução podem precisar de download inicial. '
            'Se não houver voz offline, a voz do sistema poderá usar internet.',
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

  void _selectVisual(ShopVisualItem item) {
    setState(() {
      _activeVisual = item;
      _dismissedVisualId = null;
      _lastVisualTrigger = 'manual:' + item.id;
    });
  }

  void _closeVisual() {
    setState(() {
      _dismissedVisualId = _activeVisual?.id;
      _activeVisual = null;
    });
  }

  void _openVisualGallery() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0B1830),
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.78,
          ),
          child: SingleChildScrollView(
            child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('VITRINE 3D',
                  style: TextStyle(fontSize: 19,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 7),
              const Text(
                'Os objetos aparecem automaticamente quando '
                'você ou o cliente mencionam um produto. '
                'Você também pode escolher um modelo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF9FB7D3),fontSize: 12),
              ),
              const SizedBox(height: 17),
              Wrap(
                spacing: 8,
                runSpacing: 9,
                alignment: WrapAlignment.center,
                children: [
                  for (final item in ShopVisualCatalog.items)
                    ActionChip(
                      avatar: const Icon(Icons.view_in_ar_rounded,
                          size: 18, color: Color(0xFF42D9FF)),
                      label: Text(item.title),
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _selectVisual(item);
                      },
                    ),
                ],
              ),
            ],
          ),
            ),
          ),
        ),
      ),
    );
  }

  void _openVisualFullscreen(ShopVisualItem item) {
    final reply = _lastReply;
    final translatedReply = reply != null &&
            ShopVisualCatalog.detect(reply.source)?.id == item.id
        ? reply.translation : null;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: const Color(0xFF040A19),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
                child: Row(
                  children: [
                    const Icon(Icons.view_in_ar_rounded,
                        color: Color(0xFF42D9FF)),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(item.title.toUpperCase() + ' · 3D',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2)),
                    ),
                    IconButton(
                      tooltip: 'Fechar modelo 3D',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(child: ShopVisual3D(item: item)),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                child: Column(
                  children: [
                    Text(item.english,
                        style: const TextStyle(fontSize: 22,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(item.description,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Color(0xFF93B6D5), fontSize: 13)),
                    if (translatedReply != null) ...[
                      const SizedBox(height: 11),
                      const Text('EXPLICAÇÃO TRADUZIDA',
                          style: TextStyle(
                              fontSize: 10,
                              color: Color(0xFF47DDFF),
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 5),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 100),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            translatedReply,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 13),
                    const Text(
                      'ARRASTE PARA GIRAR · TOQUE DUAS VEZES PARA CENTRALIZAR',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Color(0xFF47DDFF), fontSize: 10),
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
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
          ),
          child: SingleChildScrollView(
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
                leading: const Icon(Icons.volume_up_rounded,
                    color: Color(0xFF48D8FF)),
                title: const Text('Testar voz em inglês'),
                subtitle: const Text(
                    'Zelu diz uma frase para conferir o áudio.'),
                enabled: !controller.running && !controller.busy,
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final ok = await controller.testEnglishVoice();
                  if (mounted) {
                    setState(() {
                      _feedback = controller.warning ??
                          (ok ? 'Teste de voz concluído.' :
                              'Não foi possível reproduzir a voz.');
                    });
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.download_rounded,
                    color: Color(0xFF48D8FF)),
                title: const Text('Preparar voz em inglês'),
                subtitle: const Text(
                    'Abre o instalador de vozes do Android, quando disponível.'),
                enabled: !controller.running && !controller.busy,
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await controller.openVoiceInstaller();
                  if (mounted) {
                    setState(() => _feedback = controller.warning);
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

  void _showCustomerText(String message) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: const Color(0xFF050C1A),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(25),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('MOSTRAR AO CLIENTE',
                          style: TextStyle(
                              color: Color(0xFF47DDFF),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2)),
                    ),
                    IconButton(
                      tooltip: 'Fechar',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: SelectableText(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 32,
                          height: 1.3,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const Text(
                  'Mostre esta mensagem ao cliente caso a voz '
                  'nao esteja disponivel.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12, color: Color(0xFF91B2D0)),
                ),
              ],
            ),
          ),
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
    final heardIsCustomer = controller.heardText.trim().isNotEmpty &&
        controller.heardLanguage.isNotEmpty &&
        !controller.heardLanguage.toLowerCase().startsWith('pt');
    final latestCustomerSpeech = heardIsCustomer
        ? controller.heardText : customer?.source;
    final latestTranslation = customer != null &&
            customer.source == latestCustomerSpeech
        ? customer.translation : null;
    final statusActive = controller.running || controller.speaking;
    final small = MediaQuery.sizeOf(context).height < 740;
    final mascotHeight = small ? 216.0 : 264.0;

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
                    tooltip: 'Vitrine 3D',
                    onPressed: _openVisualGallery,
                    icon: const Icon(Icons.view_in_ar_rounded,
                        color: Color(0xFF47DDFF)),
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
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 360),
                        child: _activeVisual == null
                            ? ZeluvoriMascot(
                                key: const ValueKey('zelu'),
                                listening: controller.running,
                                speaking: controller.speaking,
                                hasSpeech: lastText.isNotEmpty,
                              )
                            : Stack(
                                key: ValueKey('visual-' + _activeVisual!.id),
                                children: [
                                  Positioned.fill(
                                    child: ShopVisual3D(
                                      key: ValueKey(_activeVisual!.id),
                                      item: _activeVisual!,
                                    ),
                                  ),
                                  Positioned(
                                    top: 0,
                                    left: 2,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(_activeVisual!.title.toUpperCase(),
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w900,
                                              color: Color(0xFF47DDFF),
                                              letterSpacing: 1.1,
                                            )),
                                        const Text('OBJETO 3D · AO VIVO',
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: Color(0xFF91AFCC),
                                            )),
                                      ],
                                    ),
                                  ),
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: IconButton(
                                      tooltip: 'Fechar objeto 3D',
                                      onPressed: _closeVisual,
                                      icon: const Icon(Icons.close_rounded,
                                          color: Color(0xFFBDD5EC)),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 1,
                                    left: 2,
                                    child: const Text('ARRASTE PARA GIRAR',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: Color(0xFF8AB8D7),
                                          letterSpacing: 1.1,
                                        )),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: IconButton(
                                      tooltip: 'Ampliar modelo 3D',
                                      onPressed: () => _openVisualFullscreen(
                                          _activeVisual!),
                                      icon: const Icon(
                                          Icons.fullscreen_rounded,
                                          color: Color(0xFF47DDFF)),
                                    ),
                                  ),
                                ],
                              ),
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
                          : latestCustomerSpeech ??
                              'A fala do cliente aparece aqui.',
                      highlighted: false,
                    ),
                    const SizedBox(height: 10),
                    _SpeechPanel(
                      label: 'TRADUÇÃO · PORTUGUÊS',
                      symbol: '🇧🇷',
                      text: latestTranslation ??
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
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: _replyBusy
                                  ? null
                                  : () => _showCustomerText(reply.translation),
                              icon: const Icon(Icons.fullscreen_rounded),
                              label: const Text('MOSTRAR AO CLIENTE'),
                            ),
                            TextButton.icon(
                              onPressed: _replyBusy
                                  ? null
                                  : () => unawaited(_sendReply(
                                        reply.source,
                                        preparedEnglish: reply.translation,
                                      )),
                              icon: const Icon(Icons.volume_up_rounded),
                              label: const Text('TENTAR VOZ'),
                            ),
                          ],
                        ),
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
                      controller.running || controller.busy
                          ? controller.status
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


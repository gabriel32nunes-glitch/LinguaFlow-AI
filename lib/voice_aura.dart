import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Animacao de status por renderizacao vetorial (sem video, imagens pesadas
/// ou pacotes adicionais). Ticker funciona somente durante a sessao ativa.
class VoiceAura extends StatefulWidget {
  const VoiceAura({
    super.key,
    required this.listening,
    required this.speaking,
    required this.hasSpeech,
    this.economy = true,
  });
  final bool listening;
  final bool speaking;
  final bool hasSpeech;
  final bool economy;

  @override
  State<VoiceAura> createState() => _VoiceAuraState();
}

class _VoiceAuraState extends State<VoiceAura>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600),
    );
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant VoiceAura oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listening != widget.listening ||
        oldWidget.speaking != widget.speaking ||
        oldWidget.hasSpeech != widget.hasSpeech ||
        oldWidget.economy != widget.economy) {
      _syncMotion();
    }
  }

  void _syncMotion() {
    if (widget.listening || widget.speaking) {
      if (!_motion.isAnimating) _motion.repeat();
    } else {
      _motion.stop();
      _motion.value = 0;
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.listening || widget.speaking;
    final accent = widget.speaking
        ? const Color(0xFFA99CFF)
        : const Color(0xFF50F2CE);
    final name = widget.speaking
        ? 'TRANSMITINDO TRADUÇÃO'
        : widget.listening
            ? (widget.hasSpeech ? 'VOZ DETECTADA' : 'ESCUTANDO')
            : 'PRONTO PARA CONVERSAR';
    final description = widget.speaking
        ? 'Sua tradução está sendo reproduzida'
        : widget.listening
            ? 'Pode falar normalmente'
            : 'Inicie para ativar o intérprete';

    return Semantics(
      label: '$name. $description',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RepaintBoundary(
            child: SizedBox(
              height: 218, width: 300,
              child: AnimatedBuilder(
                animation: _motion,
                builder: (context, _) => CustomPaint(
                  painter: _VoiceAuraPainter(
                    progress: active ? _motion.value : 0,
                    active: active,
                    speaking: widget.speaking,
                    hasSpeech: widget.hasSpeech,
                    economy: widget.economy,
                    accent: accent,
                  ),
                  child: Center(
                    child: Container(
                      width: 86, height: 86,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF1E3853), Color(0xFF0C152A)],
                        ),
                        border: Border.all(color: accent.withValues(alpha: 0.72)),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: active ? 0.22 : 0.10),
                            blurRadius: active ? 32 : 18,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                      child: Icon(
                        widget.speaking
                            ? Icons.graphic_eq_rounded
                            : active ? Icons.mic_rounded : Icons.mic_none_rounded,
                        size: 38,
                        color: accent,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 250),
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.2,
              fontSize: 13,
            ),
            child: Text(name, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 7),
          Text(description, textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFA9BDCF), fontSize: 13,
              )),
        ],
      ),
    );
  }
}

class _VoiceAuraPainter extends CustomPainter {
  const _VoiceAuraPainter({
    required this.progress,
    required this.active,
    required this.speaking,
    required this.hasSpeech,
    required this.economy,
    required this.accent,
  });
  final double progress;
  final bool active;
  final bool speaking;
  final bool hasSpeech;
  final bool economy;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final minDimension = math.min(size.width, size.height);
    final cycle = progress * math.pi * 2;
    final coreRadius = minDimension * 0.32;

    final background = Paint()
      ..shader = RadialGradient(
        colors: [accent.withValues(alpha: active ? 0.15 : 0.08),
                 accent.withValues(alpha: 0.0)],
      ).createShader(Rect.fromCircle(center: center, radius: coreRadius * 1.75));
    canvas.drawCircle(center, coreRadius * 1.75, background);

    for (var i = 0; i < 3; i++) {
      final pulse = active
          ? (progress + i / 3) % 1.0
          : (0.12 + i * 0.22);
      final radius = coreRadius * (0.75 + pulse * 0.80);
      final strength = active ? (1 - pulse) : 0.22;
      final ring = Paint()
        ..color = accent.withValues(alpha: 0.06 + strength * 0.30)
        ..strokeWidth = (active ? 1.8 : 1.0)
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(center, radius, ring);
    }

    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.3
      ..color = accent.withValues(alpha: active ? 0.58 : 0.24);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: coreRadius * 1.15),
      -math.pi / 2 + cycle,
      math.pi * 0.76, false, edge,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: coreRadius * 1.15),
      math.pi / 2 + cycle,
      math.pi * 0.4, false, edge..strokeWidth = 1.0,
    );

    // Onda visual baseada no estado de fala, NAO um medidor real de volume.
    // Evitamos declarar uma amplitude artificial como medicao real do microfone.
    final bars = economy ? 23 : 35;
    final spacing = 5.0;
    final width = (bars - 1) * spacing;
    for (var i = 0; i < bars; i++) {
      final x = center.dx - width / 2 + i * spacing;
      final position = ((i / (bars - 1)) * 2 - 1).abs();
      final envelope = math.pow(math.max(0, 1 - position), 1.8).toDouble();
      final movement = math.sin(cycle * 2 + i * 0.50).abs();
      final height = 3.0 + (active
          ? (speaking ? 30 : hasSpeech ? 24 : 13) *
              envelope * (0.25 + movement * 0.75)
          : 3.0 * envelope);
      final bar = Paint()
        ..color = accent.withValues(alpha: 0.26 + envelope * 0.43)
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(x, center.dy + coreRadius + 20 - height / 2),
        Offset(x, center.dy + coreRadius + 20 + height / 2),
        bar,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceAuraPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.active != active ||
      oldDelegate.speaking != speaking ||
      oldDelegate.hasSpeech != hasSpeech ||
      oldDelegate.economy != economy ||
      oldDelegate.accent != accent;
}

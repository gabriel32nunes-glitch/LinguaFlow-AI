part of 'main.dart';

/// Zelu 2.0: personagem vetorial leve, sem PNG ou dependencias.
/// Inspirado na referencia do app: rosto preto brilhante, olhos em arco,
/// carinha sorridente, antena, fones luminosos e mao acenando.
/// O movimento acompanha os estados de escuta e sintese de voz.
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
    with TickerProviderStateMixin {
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2700),
  )..repeat();
  late final AnimationController _hello = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed) _hello.reverse();
    });

  @override
  void dispose() {
    _idle.dispose();
    _hello.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: widget.speaking
            ? 'Zelu falando. Toque para ele acenar.'
            : widget.listening
                ? 'Zelu ouvindo. Toque para ele acenar.'
                : 'Zelu sorrindo. Toque para ele acenar.',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _hello.forward(from: 0),
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: Listenable.merge([_idle, _hello]),
              builder: (context, _) => CustomPaint(
                painter: _ZeluDeluxePainter(
                  phase: _idle.value,
                  hello: _hello.value,
                  listening: widget.listening,
                  speaking: widget.speaking,
                  hasSpeech: widget.hasSpeech,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
}

class _ZeluDeluxePainter extends CustomPainter {
  const _ZeluDeluxePainter({
    required this.phase,
    required this.hello,
    required this.listening,
    required this.speaking,
    required this.hasSpeech,
  });

  final double phase;
  final double hello;
  final bool listening;
  final bool speaking;
  final bool hasSpeech;

  static const cyan = Color(0xFF38E5FF);
  static const blue = Color(0xFF1B83FF);
  static const violet = Color(0xFF9E6CFF);
  static const lavender = Color(0xFFCEB3FF);

  Paint _glow(Color color, double blur, {double alpha = 1}) => Paint()
    ..color = color.withValues(alpha: alpha)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);

  Paint _gradient(Rect rect, List<Color> colors,
      {Alignment begin = Alignment.topLeft,
      Alignment end = Alignment.bottomRight}) =>
      Paint()
        ..shader = LinearGradient(
          begin: begin,
          end: end,
          colors: colors,
        ).createShader(rect);

  void _stroke(Canvas c, Path p, Color color, double width,
      {double blur = 0, double alpha = 1}) {
    if (blur > 0) {
      c.drawPath(
        p,
        Paint()
          ..color = color.withValues(alpha: alpha * 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width + 4
          ..strokeCap = StrokeCap.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
      );
    }
    c.drawPath(
      p,
      Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _orb(Canvas c, Offset center, double radius, Color color) {
    c.drawCircle(center, radius * 2.2,
        _glow(color, radius * 1.5, alpha: 0.44));
    c.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          colors: [Colors.white, color, blue.withValues(alpha: 0.65)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    c.drawCircle(
      center.translate(-radius * 0.3, -radius * 0.3),
      radius * 0.22,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  void _finger(Canvas c, Offset from, Offset to,
      {Color color = cyan, double width = 4}) {
    final p = Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(
        (from.dx + to.dx) / 2 + 2,
        (from.dy + to.dy) / 2 - 3,
        to.dx,
        to.dy,
      );
    _stroke(c, p, color, width, blur: 4);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final t = phase * 2 * math.pi;
    final bounce = math.sin(t) * (speaking ? 5.0 : 3.2);
    final scale = math.min(size.width / 340, size.height / 276);
    final wave = math.sin(t * (speaking ? 3 : 1)) *
            (speaking ? 10 : listening ? 5 : 3) +
        hello * 17;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2 + 4);
    canvas.scale(scale);

    // Nebulosa discreta: nao precisa de imagem de fundo.
    canvas.drawCircle(
      const Offset(0, -18),
      116,
      Paint()
        ..shader = RadialGradient(colors: [
          blue.withValues(alpha: listening ? 0.19 : 0.12),
          violet.withValues(alpha: 0.055),
          Colors.transparent,
        ]).createShader(
          Rect.fromCircle(center: const Offset(0, -18), radius: 116),
        ),
    );

    // Plataforma holografica de onde o Zelu levita.
    for (var i = 0; i < 4; i++) {
      final w = 112.0 + i * 28;
      final r = Rect.fromCenter(
          center: const Offset(0, 119), width: w, height: 18 + i * 5);
      canvas.drawOval(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = i == 0 ? 2.2 : 1.2
          ..color = (i.isEven ? cyan : violet)
              .withValues(alpha: 0.65 - i * 0.11),
      );
    }
    canvas.drawOval(
      Rect.fromCenter(
          center: const Offset(0, 119), width: 95, height: 12),
      _glow(cyan, 12, alpha: 0.55),
    );

    // Particulas orbitando o personagem.
    for (var i = 0; i < 25; i++) {
      final angle = i * 2.3999632 + t * 0.17;
      final radius = 102 + (i % 4) * 9;
      final x = math.cos(angle) * radius * 1.28;
      final y = math.sin(angle) * radius * 0.72 - 14;
      final color = i % 3 == 0 ? violet : cyan;
      canvas.drawCircle(
        Offset(x, y),
        i % 6 == 0 ? 2.1 : 1.05,
        Paint()
          ..color = color.withValues(alpha: 0.34 + 0.23 * math.sin(t + i).abs()),
      );
    }

    // Aneis de energia atras da cabeca.
    for (var i = 0; i < 2; i++) {
      final orbit = Rect.fromCenter(
          center: const Offset(0, -19),
          width: 253 + i * 18,
          height: 176 + i * 17);
      canvas.drawArc(
        orbit,
        0.35 + t * 0.06 + i * 1.3,
        2.1,
        false,
        Paint()
          ..color = (i == 0 ? cyan : violet).withValues(alpha: 0.28)
          ..strokeWidth = 1.3
          ..style = PaintingStyle.stroke,
      );
    }

    // Corpo e bracos atras da cabeca; o contorno possui profundidade.
    canvas.save();
    canvas.translate(0, bounce);

    final body = Rect.fromCenter(
        center: const Offset(0, 78), width: 79, height: 70);
    canvas.drawOval(body.inflate(7), _glow(blue, 14, alpha: 0.42));
    canvas.drawOval(
      body,
      _gradient(body, [
        const Color(0xFF37D8FF),
        const Color(0xFF124C9B),
        const Color(0xFF311867),
      ]),
    );
    canvas.drawOval(
      body.deflate(6),
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF174577),
            const Color(0xFF080F2A),
            const Color(0xFF170B38),
          ],
        ).createShader(body.deflate(6)),
    );

    // Pontos no corpo, com degradê cyan -> violeta.
    for (var yi = 0; yi < 9; yi++) {
      for (var xi = 0; xi < 10; xi++) {
        final x = -33 + xi * 7.3;
        final y = 48 + yi * 7.2;
        final d = x * x / (35 * 35) + (y - 78) * (y - 78) / (32 * 32);
        if (d >= 0.95) continue;
        canvas.drawCircle(
          Offset(x, y),
          1.05,
          Paint()
            ..color = (x < 0 ? cyan : violet)
                .withValues(alpha: 0.30 + 0.25 * math.sin(t + xi).abs()),
        );
      }
    }
    _orb(canvas, const Offset(0, 78), 7, cyan);

    final leftArm = Path()
      ..moveTo(-37, 67)
      ..quadraticBezierTo(-61, 88, -84, 79)
      ..quadraticBezierTo(-99, 72, -105, 62);
    _stroke(canvas, leftArm, cyan, 6, blur: 7);
    _orb(canvas, const Offset(-105, 62), 5, violet);
    _finger(canvas, const Offset(-105, 62), const Offset(-117, 56), width: 3);
    _finger(canvas, const Offset(-105, 62), const Offset(-115, 67), width: 3);

    final rightArm = Path()
      ..moveTo(39, 68)
      ..quadraticBezierTo(77, 82, 98, 41 + wave * 0.35)
      ..quadraticBezierTo(104, 25 + wave * 0.55, 110, 13 + wave);
    _stroke(canvas, rightArm, cyan, 7, blur: 8);
    // Mao fofa de cinco dedos, em vez de um circulo.
    final palm = Offset(111, 10 + wave);
    canvas.drawCircle(palm, 14, _glow(blue, 10, alpha: 0.6));
    canvas.drawOval(
      Rect.fromCenter(center: palm, width: 25, height: 23),
      _gradient(
        Rect.fromCenter(center: palm, width: 25, height: 23),
        [const Color(0xFF3DE7FF), const Color(0xFF3555CE), violet],
      ),
    );
    for (var i = 0; i < 4; i++) {
      final x = 97 + i * 8.0;
      _finger(
        canvas,
        Offset(x, 5 + wave),
        Offset(x - 2 + i * 1.7, -18 - (i % 2) * 5 + wave),
        width: 4.2,
        color: i.isEven ? cyan : lavender,
      );
    }
    _finger(canvas, Offset(101, 17 + wave),
        Offset(88, 7 + wave), width: 4.3, color: lavender);

    // Antena, com bolinha brilhante no topo.
    final antenna = Path()
      ..moveTo(0, -98)
      ..quadraticBezierTo(0, -123, 15, -126);
    _stroke(canvas, antenna, cyan, 3.2, blur: 5);
    _orb(canvas, const Offset(15, -132), 10, violet);

    // Cabeca grande, arredondada, com contorno em neon e brilho suave.
    final head = Rect.fromCenter(
        center: const Offset(0, -23), width: 205, height: 163);
    canvas.drawOval(head.inflate(7), _glow(cyan, 18, alpha: 0.65));
    canvas.drawOval(
      head,
      _gradient(head, [
        const Color(0xFF46F4FF),
        const Color(0xFF166FE6),
        const Color(0xFF6D42C5),
        const Color(0xFF33C7FF),
      ]),
    );
    final shell = head.deflate(5);
    canvas.drawOval(
      shell,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.7),
          radius: 1.35,
          colors: [
            const Color(0xFF193D8A),
            const Color(0xFF070C27),
            const Color(0xFF110B2B),
          ],
        ).createShader(shell),
    );

    // Dots de luz em volta da moldura, nao sobre o rosto.
    for (var yi = 0; yi < 24; yi++) {
      for (var xi = 0; xi < 32; xi++) {
        final x = -100.0 + xi * 6.45;
        final y = -102.0 + yi * 6.75;
        final outer = x * x / (100 * 100) +
            (y + 23) * (y + 23) / (80 * 80);
        final inner = x * x / (88 * 88) +
            (y + 23) * (y + 23) / (66 * 66);
        if (outer >= 0.99 || inner <= 0.99) continue;
        final light = 0.48 + 0.30 * math.sin(t + xi * 0.21 + yi * 0.31).abs();
        canvas.drawCircle(
          Offset(x, y),
          1.15,
          Paint()
            ..color = (x > 16 ? violet : cyan).withValues(alpha: light),
        );
      }
    }

    // Viseira preta lustrosa (a parte mais marcante da referencia).
    final face = Rect.fromCenter(
        center: const Offset(0, -21), width: 174, height: 125);
    canvas.drawOval(face.inflate(3), _glow(blue, 10, alpha: 0.40));
    canvas.drawOval(
      face,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const [
            Color(0xFF193963),
            Color(0xFF07132C),
            Color(0xFF020510),
            Color(0xFF0B0923),
          ],
          stops: [0, 0.34, 0.67, 1],
        ).createShader(face),
    );
    // Reflexo de vidro no topo.
    final reflection = Path()
      ..moveTo(-70, -57)
      ..quadraticBezierTo(-28, -87, 35, -76)
      ..quadraticBezierTo(56, -72, 68, -61);
    _stroke(canvas, reflection, Colors.white, 1.8, alpha: 0.20);
    canvas.drawOval(
      Rect.fromCenter(
          center: const Offset(-35, -61), width: 63, height: 19),
      _glow(cyan, 13, alpha: 0.11),
    );

    // Fones circulares com aros neon, em frente ao capacete.
    for (final side in [-1, 1]) {
      canvas.save();
      canvas.translate(side * 99.0, -20);
      final cup = Rect.fromCenter(
          center: Offset.zero, width: 28, height: 55);
      canvas.drawOval(cup.inflate(5), _glow(side == -1 ? cyan : violet, 11));
      canvas.drawOval(
        cup,
        _gradient(cup, side == -1
            ? [const Color(0xFF64F7FF), blue, const Color(0xFF192E88)]
            : [lavender, violet, const Color(0xFF243F9D)]),
      );
      canvas.drawOval(
        cup.deflate(5),
        Paint()..color = const Color(0xFF071A40),
      );
      canvas.drawOval(
        cup.deflate(8),
        Paint()
          ..color = side == -1 ? cyan : lavender
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      canvas.restore();
    }

    // Olhos expressivos, suaves, grandes e felizes.
    final blink = !speaking && phase > 0.49 && phase < 0.515;
    final eyeLift = speaking ? math.sin(t * 3).abs() * 2 : 0.0;
    for (final x in [-35.0, 35.0]) {
      final eye = Path();
      if (blink) {
        eye.moveTo(x - 14, -23);
        eye.quadraticBezierTo(x, -22, x + 14, -23);
      } else {
        eye.moveTo(x - 16, -20 + eyeLift);
        eye.cubicTo(x - 14, -48 + eyeLift, x + 12, -49 + eyeLift,
            x + 17, -21 + eyeLift);
      }
      _stroke(canvas, eye, x < 0 ? lavender : cyan, 6.7, blur: 11);
      _stroke(canvas, eye, const Color(0xFFE6D8FF), 4.2);
    }

    // Bochechas rosadas discretas.
    for (final x in [-64.0, 64.0]) {
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(x, 5), width: 22, height: 12),
        _glow(const Color(0xFFFC7DE4), 8, alpha: 0.40),
      );
    }

    // Boquinha sorri ou fala, sincronizada com o estado TTS.
    if (speaking) {
      final openness = 7 + 12 * math.sin(t * 3.4).abs();
      canvas.drawOval(
        Rect.fromCenter(
          center: const Offset(0, 9), width: 17, height: openness,
        ),
        _glow(lavender, 7, alpha: 0.72),
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: const Offset(0, 9), width: 13, height: openness,
        ),
        Paint()..color = const Color(0xFFBF99FF),
      );
    } else {
      final mouth = Path()
        ..moveTo(-11, 7)
        ..quadraticBezierTo(0, 19 + hello * 4, 11, 7);
      _stroke(canvas, mouth, lavender, 2.8, blur: 5);
    }

    canvas.restore();

    // Barras de audio no primeiro plano, sutis durante repouso.
    for (var i = -18; i <= 18; i++) {
      final x = i * 7.2;
      final activity = speaking ? 14.0 : listening ? 9.0 : 2.0;
      final h = 2.5 +
          activity *
              (0.25 + 0.75 * math.sin(i * 1.65 + t * 2.4).abs()) *
              (hasSpeech ? 1.2 : 1);
      canvas.drawLine(
        Offset(x, 113 - h / 2),
        Offset(x, 113 + h / 2),
        Paint()
          ..color = (i.isEven ? cyan : violet)
              .withValues(alpha: 0.28 + math.min(h / 33, 0.52))
          ..strokeWidth = 1.35
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ZeluDeluxePainter old) =>
      old.phase != phase ||
      old.hello != hello ||
      old.listening != listening ||
      old.speaking != speaking ||
      old.hasSpeech != hasSpeech;
}

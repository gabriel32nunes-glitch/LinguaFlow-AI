part of 'main.dart';

/// Vitrine visual offline: nove objetos modelados em geometria 3D leve.
/// Cada modelo e uma silhueta extrudada com faces, profundidade, perspectiva,
/// pontos neon e detalhes desenhados em Flutter. Nao usa WebView nem rede.
@immutable
class ShopVisualItem {
  const ShopVisualItem(this.id, this.title, this.english, this.description,
      this.keywords, {this.priority = 10});

  final String id;
  final String title;
  final String english;
  final String description;
  final List<String> keywords;
  final int priority;
}

class ShopVisualCatalog {
  static const items = <ShopVisualItem>[
    ShopVisualItem('shirt', 'Camiseta', 'T-shirt',
        'Roupa · tecido · modelo',
        ['camiseta', 'camisetas', 'camisa', 'camisas', 'blusa', 'blusas',
         't shirt', 'tshirt', 'shirt', 'shirts', 'tee shirt', 'tee',
         'remera', 'camiseta de manga', 't shirt size', 't shirt color'],
        priority: 90),
    ShopVisualItem('pants', 'Calça', 'Pants',
        'Roupa · tamanho · caimento',
        ['calca', 'calcas', 'calça', 'calças', 'calca jeans', 'calça jeans',
         'jeans', 'pants', 'trousers', 'leggings', 'pantalon', 'pantalones'],
        priority: 90),
    ShopVisualItem('cap', 'Boné', 'Cap',
        'Acessório · aba · ajuste',
        ['bone', 'bones', 'boné', 'bonés', 'gorro', 'cap', 'caps',
         'baseball cap', 'hat', 'hats', 'gorra', 'casquette'],
        priority: 90),
    ShopVisualItem('backpack', 'Mochila', 'Backpack',
        'Acessório · compartimentos',
        ['mochila', 'mochilas', 'backpack', 'backpacks', 'rucksack',
         'school bag', 'mochilas escolares', 'sac a dos'],
        priority: 90),
    ShopVisualItem('parcel', 'Pacote', 'Package',
        'Entrega · caixa · embalagem',
        ['pacote', 'pacotes', 'encomenda', 'encomendas', 'caixa', 'caixas',
         'embalagem', 'embalagens', 'package', 'packages', 'parcel',
         'parcels', 'box', 'boxes', 'delivery box', 'paquete'],
        priority: 80),
    ShopVisualItem('card', 'Cartão', 'Card',
        'Pagamento · aproximação',
        ['cartao', 'cartoes', 'cartão', 'cartões', 'cartao de credito',
         'cartão de crédito', 'credit card', 'debit card', 'card',
         'cards', 'tarjeta', 'tarjeta de credito', 'contactless'],
        priority: 55),
    ShopVisualItem('ruler', 'Medidas', 'Measurements',
        'Tamanho · comprimento',
        ['medida', 'medidas', 'medir', 'medicao', 'medição',
         'comprimento', 'largura', 'altura', 'centimetro', 'centimetros',
         'centímetros', 'tamanho', 'tamanhos', 'measure', 'measurement',
         'measurements', 'length', 'width', 'size', 'sizes', 'ruler',
         'centimeter', 'centimeters', 'talla', 'medidas'],
        priority: 30),
    ShopVisualItem('discount', 'Desconto', 'Discount',
        'Oferta · promoção · percentual',
        ['desconto', 'descontos', 'promocao', 'promoção', 'promocoes',
         'promoções', 'oferta', 'ofertas', 'discount', 'discounts',
         'sale', 'sales', 'percent', 'percentage', 'porcentagem',
         'por cento', 'rebaja', 'descuento', 'off'],
        priority: 20),
    ShopVisualItem('tag', 'Preço', 'Price',
        'Etiqueta · valor do item',
        ['preco', 'preços', 'preco', 'preço', 'valor', 'valores',
         'etiqueta', 'etiquetas', 'price', 'prices', 'price tag',
         'cost', 'costs', 'how much', 'cuanto cuesta', 'precio'],
        priority: 10),
  ];

  static String normalize(String text) {
    var value = text.toLowerCase();
    const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const to =   'aaaaaeeeeiiiiooooouuuucn';
    for (var i = 0; i < from.length; i++) {
      value = value.replaceAll(from[i], to[i]);
    }
    return value.replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static ShopVisualItem? byId(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Produtos concretos ganham de termos genericos: "preco da camiseta"
  /// deve mostrar a camiseta, e nao uma etiqueta de preco.
  /// Somente palavras reconhecidas; nao supoe marca, cor ou estoque.
  static ShopVisualItem? detect(String speech) {
    final normalized = normalize(speech);
    if (normalized.isEmpty) return null;
    final padded = ' ' + normalized + ' ';
    ShopVisualItem? best;
    var score = -1;
    for (final item in items) {
      var longest = 0;
      for (final term in item.keywords) {
        final word = normalize(term);
        if (word.isNotEmpty && padded.contains(' ' + word + ' ')) {
          if (word.length > longest) longest = word.length;
        }
      }
      if (longest == 0) continue;
      final rank = item.priority * 100 + longest;
      if (rank > score) {
        best = item;
        score = rank;
      }
    }
    return best;
  }
}

/// Renderiza um objeto 3D procedimental, com giro por arraste e animacao.
/// Nao confundir com um modelo GLB: e geometria extrudada de baixa complexidade,
/// feita para rodar suavemente no Galaxy A14 sem carregar modelos da internet.
class ShopVisual3D extends StatefulWidget {
  const ShopVisual3D({super.key, required this.item, this.autoRotate = true});

  final ShopVisualItem item;
  final bool autoRotate;

  @override
  State<ShopVisual3D> createState() => _ShopVisual3DState();
}

class _ShopVisual3DState extends State<ShopVisual3D>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this, duration: const Duration(seconds: 9),
  )..repeat();
  double _yaw = 0.25;
  double _pitch = -0.16;

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Modelo 3D de ' + widget.item.title +
            '. Arraste o dedo para girar.',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (details) => setState(() {
            _yaw += details.delta.dx * 0.012;
            _pitch = (_pitch - details.delta.dy * 0.007).clamp(-0.8, 0.8);
          }),
          onDoubleTap: () => setState(() {
            _yaw = 0.25;
            _pitch = -0.16;
          }),
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _clock,
              builder: (context, _) => CustomPaint(
                painter: _NeonProductPainter(
                  id: widget.item.id,
                  yaw: _yaw + (widget.autoRotate
                      ? math.sin(_clock.value * 2 * math.pi) * 0.34 : 0),
                  pitch: _pitch,
                  pulse: _clock.value,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
}

class _Point3 {
  const _Point3(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;
}

class _Screen3 {
  const _Screen3(this.point, this.depth);
  final Offset point;
  final double depth;
}

class _Face3 {
  const _Face3(this.vertices, this.kind, this.depth);
  final List<_Point3> vertices;
  final int kind; // 0 = lado, 1 = frente, 2 = verso
  final double depth;
}

class _NeonProductPainter extends CustomPainter {
  const _NeonProductPainter({
    required this.id,
    required this.yaw,
    required this.pitch,
    required this.pulse,
  });

  final String id;
  final double yaw;
  final double pitch;
  final double pulse;

  static const _cyan = Color(0xFF32F2FF);
  static const _blue = Color(0xFF2375FF);
  static const _purple = Color(0xFFBB5BFF);
  static const _dark = Color(0xFF07132E);

  _Point3 _rotate(_Point3 p) {
    final cy = math.cos(yaw);
    final sy = math.sin(yaw);
    final x = p.x * cy + p.z * sy;
    final z = -p.x * sy + p.z * cy;
    final cp = math.cos(pitch);
    final sp = math.sin(pitch);
    return _Point3(x, p.y * cp - z * sp, p.y * sp + z * cp);
  }

  _Screen3 _project(_Point3 p, Size size) {
    final r = _rotate(p);
    final perspective = 4.2 / (4.7 - r.z);
    final base = math.min(size.width * 0.38, size.height * 0.39);
    return _Screen3(
      Offset(size.width / 2 + r.x * base * perspective,
          size.height / 2 + r.y * base * perspective),
      r.z,
    );
  }

  Path _path(List<_Point3> points, Size size) {
    final p = Path();
    for (var i = 0; i < points.length; i++) {
      final s = _project(points[i], size).point;
      if (i == 0) {
        p.moveTo(s.dx, s.dy);
      } else {
        p.lineTo(s.dx, s.dy);
      }
    }
    return p..close();
  }

  void _stroke(Canvas c, Path p, Color color,
      {double width = 2, double blur = 4}) {
    if (blur > 0) {
      c.drawPath(p, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width + 4
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: 0.48)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur));
    }
    c.drawPath(p, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = color);
  }

  void _line(Canvas c, Size size, List<Offset> coords,
      {double z = 0.18, Color color = _cyan, double width = 2.2}) {
    if (coords.length < 2) return;
    final p = Path();
    for (var i = 0; i < coords.length; i++) {
      final o = _project(_Point3(coords[i].dx, coords[i].dy, z), size).point;
      if (i == 0) {
        p.moveTo(o.dx, o.dy);
      } else {
        p.lineTo(o.dx, o.dy);
      }
    }
    _stroke(c, p, color, width: width);
  }

  void _ring(Canvas c, Size size, Offset center, double rx, double ry,
      {double z = 0.18, Color color = _cyan, double width = 2.2}) {
    final points = <Offset>[];
    for (var i = 0; i <= 32; i++) {
      final t = i * math.pi * 2 / 32;
      points.add(Offset(center.dx + math.cos(t) * rx,
          center.dy + math.sin(t) * ry));
    }
    _line(c, size, points, z: z, color: color, width: width);
  }

  List<Offset> _outline() {
    switch (id) {
      case 'shirt':
        return const [
          Offset(-0.50,-0.82),Offset(-0.22,-0.94),Offset(-0.14,-0.76),
          Offset(0.14,-0.76),Offset(0.22,-0.94),Offset(0.50,-0.82),
          Offset(0.98,-0.43),Offset(0.72,-0.08),Offset(0.51,-0.21),
          Offset(0.55,0.91),Offset(-0.55,0.91),Offset(-0.51,-0.21),
          Offset(-0.72,-0.08),Offset(-0.98,-0.43),
        ];
      case 'pants':
        return const [
          Offset(-0.72,-0.96),Offset(0.72,-0.96),Offset(0.77,-0.46),
          Offset(0.96,0.88),Offset(0.23,0.96),Offset(0.02,-0.12),
          Offset(-0.02,-0.12),Offset(-0.23,0.96),Offset(-0.96,0.88),
          Offset(-0.77,-0.46),
        ];
      case 'cap':
        return const [
          Offset(-0.93,0.24),Offset(-0.89,-0.15),Offset(-0.68,-0.59),
          Offset(-0.33,-0.81),Offset(0.16,-0.83),Offset(0.61,-0.59),
          Offset(0.82,-0.23),Offset(0.83,0.17),Offset(0.99,0.38),
          Offset(0.82,0.57),Offset(0.32,0.63),Offset(-0.19,0.51),
          Offset(-0.72,0.46),
        ];
      case 'backpack':
        return const [
          Offset(-0.63,-0.76),Offset(-0.40,-0.94),Offset(0.36,-0.94),
          Offset(0.63,-0.76),Offset(0.83,-0.30),Offset(0.86,0.65),
          Offset(0.66,0.91),Offset(-0.66,0.91),Offset(-0.86,0.65),
          Offset(-0.83,-0.30),
        ];
      case 'parcel':
        return const [
          Offset(-0.83,-0.80),Offset(0.83,-0.80),
          Offset(0.83,0.80),Offset(-0.83,0.80),
        ];
      case 'card':
        return const [
          Offset(-0.95,-0.61),Offset(0.95,-0.61),
          Offset(0.95,0.61),Offset(-0.95,0.61),
        ];
      case 'ruler':
        return const [
          Offset(-0.97,-0.34),Offset(0.97,-0.34),
          Offset(0.97,0.34),Offset(-0.97,0.34),
        ];
      case 'discount':
        return const [
          Offset(-0.96,-0.61),Offset(0.96,-0.61),
          Offset(0.96,-0.20),Offset(0.78,-0.14),Offset(0.72,0.0),
          Offset(0.78,0.14),Offset(0.96,0.20),Offset(0.96,0.61),
          Offset(-0.96,0.61),Offset(-0.96,0.20),Offset(-0.78,0.14),
          Offset(-0.72,0.0),Offset(-0.78,-0.14),Offset(-0.96,-0.20),
        ];
      case 'tag':
        return const [
          Offset(-0.64,-0.90),Offset(0.74,-0.90),
          Offset(0.91,-0.65),Offset(0.91,0.86),
          Offset(-0.64,0.86),Offset(-0.92,0.56),
          Offset(-0.92,-0.60),
        ];
      default:
        return const [
          Offset(-0.8,-0.8),Offset(0.8,-0.8),
          Offset(0.8,0.8),Offset(-0.8,0.8),
        ];
    }
  }

  double get _front => id == 'parcel' ? 0.40 : 0.17;
  double get _back => id == 'parcel' ? -0.40 : -0.17;

  void _dots(Canvas c, Size size, List<Offset> outline) {
    final polygon = Path()..addPolygon(outline, true);
    final step = id == 'ruler' ? 0.13 : 0.12;
    final scale = math.min(size.width * 0.38, size.height * 0.39);
    for (var y = -0.94; y < 0.96; y += step) {
      for (var x = -0.96; x < 0.97; x += step) {
        final center = Offset(x, y);
        if (!polygon.contains(center)) continue;
        final p = _project(_Point3(x,y,_front + 0.004), size);
        final color = (x + y > 0.5 || x < -0.55) ? _purple : _cyan;
        final alpha = 0.43 + 0.35 * math.sin((x * 5 + y * 3 + pulse * 6));
        c.drawCircle(p.point, math.max(0.65, scale * 0.013),
          Paint()..color = color.withValues(alpha: alpha.clamp(0.2,0.92)));
      }
    }
  }

  void _details(Canvas c, Size size) {
    final z = _front + 0.035;
    switch (id) {
      case 'shirt':
        _line(c,size,const [Offset(-0.20,-0.87),Offset(-0.10,-0.70),
          Offset(0.10,-0.70),Offset(0.20,-0.87)],z:z,color:_purple);
        _line(c,size,const [Offset(-0.51,-0.20),Offset(-0.45,0.85)],z:z);
        _line(c,size,const [Offset(0.51,-0.20),Offset(0.45,0.85)],z:z);
        _line(c,size,const [Offset(-0.56,0.78),Offset(0.56,0.78)],z:z,color:_purple);
        break;
      case 'pants':
        _line(c,size,const [Offset(-0.71,-0.72),Offset(0.71,-0.72)],z:z,color:_purple);
        _ring(c,size,const Offset(0,-0.83),0.045,0.05,z:z);
        _line(c,size,const [Offset(-0.65,-0.60),Offset(-0.31,-0.36),
          Offset(-0.06,-0.38)],z:z);
        _line(c,size,const [Offset(0.65,-0.60),Offset(0.31,-0.36),
          Offset(0.06,-0.38)],z:z);
        _line(c,size,const [Offset(-0.16,-0.31),Offset(-0.35,0.84)],z:z,color:_purple);
        _line(c,size,const [Offset(0.16,-0.31),Offset(0.35,0.84)],z:z,color:_purple);
        break;
      case 'cap':
        _line(c,size,const [Offset(-0.86,0.15),Offset(-0.48,0.27),
          Offset(0.17,0.28),Offset(0.82,0.16)],z:z);
        _line(c,size,const [Offset(-0.38,-0.74),Offset(-0.13,-0.22),
          Offset(-0.12,0.22)],z:z,color:_purple);
        _line(c,size,const [Offset(0.12,-0.77),Offset(0.29,-0.22),
          Offset(0.32,0.20)],z:z);
        _ring(c,size,const Offset(-0.06,-0.79),0.065,0.065,z:z,color:_purple);
        _line(c,size,const [Offset(-0.16,0.41),Offset(0.45,0.54),
          Offset(0.92,0.42)],z:z,color:_purple);
        break;
      case 'backpack':
        _line(c,size,const [Offset(-0.48,-0.69),Offset(-0.48,-0.97),
          Offset(0.48,-0.97),Offset(0.48,-0.69)],z:z,color:_purple);
        _line(c,size,const [Offset(-0.72,-0.33),Offset(-0.72,0.60)],z:z);
        _line(c,size,const [Offset(0.72,-0.33),Offset(0.72,0.60)],z:z);
        _line(c,size,const [Offset(-0.57,0.06),Offset(0.57,0.06),
          Offset(0.63,0.65),Offset(-0.63,0.65),Offset(-0.57,0.06)],
          z:z,color:_purple);
        _ring(c,size,const Offset(-0.54,0.08),0.048,0.048,z:z);
        break;
      case 'parcel':
        _line(c,size,const [Offset(-0.21,-0.80),Offset(0.22,-0.80),
          Offset(0.22,0.80),Offset(-0.21,0.80),Offset(-0.21,-0.80)],
          z:z,color:_purple);
        _line(c,size,const [Offset(-0.21,-0.80),Offset(-0.21,0.80)],z:z);
        break;
      case 'card':
        _line(c,size,const [Offset(-0.67,-0.16),Offset(-0.28,-0.16),
          Offset(-0.28,0.26),Offset(-0.67,0.26),Offset(-0.67,-0.16)],
          z:z,color:_purple);
        _line(c,size,const [Offset(-0.47,-0.16),Offset(-0.47,0.26)],z:z);
        _line(c,size,const [Offset(-0.67,0.04),Offset(-0.28,0.04)],z:z);
        for (var i = 0; i < 3; i++) {
          final x = 0.20 + i * 0.14;
          _line(c,size,[
            Offset(x,-0.24 - i*0.07),
            Offset(x+0.11,-0.08),
            Offset(x+0.11,0.14),
            Offset(x,0.30 + i*0.06),
          ],z:z,color:i.isEven ? _cyan : _purple);
        }
        break;
      case 'ruler':
        for (var i = 0; i <= 16; i++) {
          final x = -0.83 + i * 0.104;
          _line(c,size,[Offset(x,0.26),Offset(x,
              i % 4 == 0 ? -0.16 : i.isEven ? 0.0 : 0.13)],
              z:z,color:i.isEven ? _purple : _cyan,width:1.8);
        }
        break;
      case 'discount':
        _ring(c,size,const Offset(-0.30,-0.25),0.16,0.18,z:z,color:_purple,width:3);
        _ring(c,size,const Offset(0.30,0.25),0.16,0.18,z:z,color:_purple,width:3);
        _line(c,size,const [Offset(0.37,-0.43),Offset(-0.37,0.43)],
            z:z,color:_cyan,width:5);
        break;
      case 'tag':
        _ring(c,size,const Offset(0.55,-0.59),0.12,0.12,z:z,color:_purple,width:3);
        _line(c,size,const [Offset(0.55,-0.59),Offset(0.91,-0.94)],
            z:z,color:_cyan);
        // Cifra estilizada construida com linhas e curvas 3D.
        _line(c,size,const [
          Offset(0.36,-0.18),Offset(0.14,-0.36),Offset(-0.23,-0.30),
          Offset(-0.40,-0.10),Offset(-0.27,0.08),Offset(0.20,0.15),
          Offset(0.39,0.34),Offset(0.25,0.56),Offset(-0.17,0.59),
          Offset(-0.40,0.43),
        ],z:z,color:_purple,width:4);
        _line(c,size,const [Offset(0.0,-0.52),Offset(0.0,0.73)],
            z:z,color:_cyan,width:3);
        break;
    }
  }

  @override
  void paint(Canvas c, Size size) {
    if (size.isEmpty) return;
    final center = Offset(size.width/2, size.height/2);
    final radius = math.min(size.width, size.height) * 0.43;

    c.drawCircle(center, radius*1.2, Paint()
      ..shader = RadialGradient(colors: [
        _blue.withValues(alpha: 0.22),
        _purple.withValues(alpha: 0.06),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center:center,radius:radius*1.2)));

    // Halo e elipses sutis atras do modelo.
    for (var i = 0; i < 3; i++) {
      c.drawOval(
        Rect.fromCenter(center: center.translate(0, radius*0.62),
          width: radius*1.75 + i*18, height: 14.0 + i*8),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = (i.isEven ? _cyan : _purple)
              .withValues(alpha: 0.38 - i*0.09));
    }

    final outline = _outline();
    final faces = <_Face3>[];
    final front = outline.map((p)=>_Point3(p.dx,p.dy,_front)).toList();
    final back = outline.map((p)=>_Point3(p.dx,p.dy,_back)).toList();
    double depth(List<_Point3> points) =>
        points.map((p)=>_rotate(p).z).reduce((a,b)=>a+b) / points.length;
    faces.add(_Face3(front,1,depth(front)));
    faces.add(_Face3(back,2,depth(back)));
    for (var i = 0; i < outline.length; i++) {
      final j = (i+1)%outline.length;
      final side = <_Point3>[front[i],front[j],back[j],back[i]];
      faces.add(_Face3(side,0,depth(side)));
    }
    faces.sort((a,b)=>a.depth.compareTo(b.depth));

    for (final face in faces) {
      final p = _path(face.vertices,size);
      final isFront = face.kind == 1;
      final isBack = face.kind == 2;
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isFront
              ? [const Color(0xFF12356E), _dark, const Color(0xFF121446)]
              : isBack
                  ? [const Color(0xFF101B46), const Color(0xFF030A20)]
                  : [const Color(0xFF07142D), const Color(0xFF16478A)],
        ).createShader(p.getBounds());
      c.drawPath(p,paint);
      _stroke(c,p,isFront ? _cyan : isBack ? _blue : _purple,
          width:isFront ? 2.8 : 1.5,blur:isFront ? 6 : 3);
      if (isFront) {
        _dots(c,size,outline);
        _details(c,size);
      }
    }

    // Particulas de atmosfera, independentes do objeto.
    for (var i = 0; i < 16; i++) {
      final a = i * 2.39996 + pulse * 1.5;
      final r = radius * (0.95 + (i % 3)*0.09);
      final p = center + Offset(math.cos(a)*r,math.sin(a)*r*0.82);
      c.drawCircle(p, i % 4 == 0 ? 1.7 : 0.9,
          Paint()..color=(i.isEven ? _cyan : _purple)
              .withValues(alpha:0.3 + 0.2*math.sin(a).abs()));
    }
  }

  @override
  bool shouldRepaint(covariant _NeonProductPainter old) =>
      old.id != id || old.yaw != yaw ||
      old.pitch != pitch || old.pulse != pulse;
}

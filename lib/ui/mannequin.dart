import 'dart:math';

import 'package:flutter/material.dart';

/// Como desenhar o Manequim numa pose.
class MannequinStyle {
  const MannequinStyle({
    required this.body,
    required this.edge,
    required this.eyes,
    this.armsUp = 0,
    this.headTilt = 0,
    this.glitch = 0,
  });

  /// Na luz: pálido, rachado, olhos fundos.
  static const lit = MannequinStyle(
    body: Color(0xFFCFC6B6),
    edge: Color(0xFF6B6255),
    eyes: Color(0xFF0A0606),
  );

  /// No escuro: só a silhueta e dois pontos de olho.
  static const dark = MannequinStyle(
    body: Color(0xCC060505),
    edge: Color(0x44A8A090),
    eyes: Color(0xFFE8E0D0),
  );

  final Color body;
  final Color edge;
  final Color eyes;

  /// 0 = braços caídos; 1 = estendidos para você (correndo).
  final double armsUp;
  final double headTilt;

  /// 0 a 1: fatias deslocadas, como imagem com defeito.
  final double glitch;

  MannequinStyle copyWith({double? armsUp, double? headTilt, double? glitch}) =>
      MannequinStyle(
        body: body,
        edge: edge,
        eyes: eyes,
        armsUp: armsUp ?? this.armsUp,
        headTilt: headTilt ?? this.headTilt,
        glitch: glitch ?? this.glitch,
      );
}

/// Desenha o Manequim em pé, com os pés em [feet] e altura [h]. Articulações
/// em bola, cabeça oval sem rosto além de dois buracos e uma rachadura.
void drawMannequin(
  Canvas canvas,
  Offset feet,
  double h,
  MannequinStyle s, {
  Random? rng,
}) {
  final x = feet.dx;
  final top = feet.dy - h;
  double y(double f) => top + f * h;
  // Volume: as bordas do corpo mais escuras que o meio.
  final shade = LinearGradient(
    colors: [
      Color.lerp(s.body, Colors.black, 0.5)!,
      s.body,
      s.body,
      Color.lerp(s.body, Colors.black, 0.55)!,
    ],
    stops: const [0, 0.35, 0.6, 1],
  ).createShader(Rect.fromLTRB(x - h * 0.2, top, x + h * 0.2, feet.dy));
  final fill = Paint()..shader = shade;
  final edge = Paint()
    ..color = s.edge
    ..style = PaintingStyle.stroke
    ..strokeWidth = max(1, h * 0.006);

  void limb(Offset a, Offset b, double w) {
    final p = Paint()
      ..shader = shade
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(a, b, p);
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = s.edge
        ..strokeWidth = max(1, h * 0.004)
        ..style = PaintingStyle.stroke,
    );
  }

  void joint(Offset c, double r) {
    canvas
      ..drawCircle(c, r, fill)
      ..drawCircle(c, r, edge);
  }

  final r = rng ?? Random(1);
  if (s.glitch > 0) {
    canvas.save();
    canvas.translate((r.nextDouble() - 0.5) * h * 0.08 * s.glitch, 0);
  }

  // Pernas
  final hipL = Offset(x - h * 0.05, y(0.56));
  final hipR = Offset(x + h * 0.05, y(0.56));
  final kneeL = Offset(x - h * 0.06, y(0.78));
  final kneeR = Offset(x + h * 0.06, y(0.78));
  final footL = Offset(x - h * 0.07, y(1));
  final footR = Offset(x + h * 0.07, y(1));
  limb(hipL, kneeL, h * 0.05);
  limb(kneeL, footL, h * 0.04);
  limb(hipR, kneeR, h * 0.05);
  limb(kneeR, footR, h * 0.04);
  joint(kneeL, h * 0.03);
  joint(kneeR, h * 0.03);

  // Tronco: ombros largos afinando até a cintura
  final torso = Path()
    ..moveTo(x - h * 0.13, y(0.22))
    ..lineTo(x + h * 0.13, y(0.22))
    ..lineTo(x + h * 0.08, y(0.44))
    ..lineTo(x + h * 0.09, y(0.58))
    ..lineTo(x - h * 0.09, y(0.58))
    ..lineTo(x - h * 0.08, y(0.44))
    ..close();
  canvas
    ..drawPath(torso, fill)
    ..drawPath(torso, edge);
  canvas.drawLine(
    Offset(x - h * 0.08, y(0.44)),
    Offset(x + h * 0.08, y(0.44)),
    edge,
  );

  // Braços: caídos, ou estendidos para frente quando corre
  for (final side in const [-1.0, 1.0]) {
    final shoulder = Offset(x + side * h * 0.14, y(0.24));
    final down = Offset(x + side * h * 0.17, y(0.42));
    final up = Offset(x + side * h * 0.24, y(0.26));
    final elbow = Offset.lerp(down, up, s.armsUp)!;
    final handDown = Offset(x + side * h * 0.16, y(0.6));
    final handUp = Offset(x + side * h * 0.2, y(0.12));
    final hand = Offset.lerp(handDown, handUp, s.armsUp)!;
    limb(shoulder, elbow, h * 0.035);
    limb(elbow, hand, h * 0.03);
    joint(shoulder, h * 0.03);
    joint(elbow, h * 0.022);
    // Dedos longos
    for (var k = -1; k <= 1; k++) {
      final dir = (hand - elbow) / (hand - elbow).distance;
      final tip =
          hand + dir.scale(h * 0.05, h * 0.05) + Offset(k * h * 0.012, 0);
      limb(hand, tip, h * 0.008);
    }
  }

  // Pescoço e cabeça
  limb(Offset(x, y(0.2)), Offset(x, y(0.15)), h * 0.035);
  canvas.save();
  final headC = Offset(x, y(0.08));
  canvas.translate(headC.dx, headC.dy);
  canvas.rotate(s.headTilt);
  final head = Rect.fromCenter(
    center: Offset.zero,
    width: h * 0.13,
    height: h * 0.17,
  );
  // O degradê da cabeça nas coordenadas dela (o canvas foi transladado).
  final headFill = Paint()
    ..shader = RadialGradient(
      center: const Alignment(-0.2, -0.3),
      colors: [s.body, Color.lerp(s.body, Colors.black, 0.45)!],
    ).createShader(head);
  canvas
    ..drawOval(head, headFill)
    ..drawOval(head, edge);
  final eye = Paint()..color = s.eyes;
  canvas
    ..drawOval(
      Rect.fromCenter(
        center: Offset(-h * 0.027, -h * 0.01),
        width: h * 0.028,
        height: h * 0.02,
      ),
      eye,
    )
    ..drawOval(
      Rect.fromCenter(
        center: Offset(h * 0.029, -h * 0.008),
        width: h * 0.024,
        height: h * 0.018,
      ),
      eye,
    );
  // A rachadura, da testa até o queixo
  final crack = Path()
    ..moveTo(h * 0.01, -h * 0.085)
    ..lineTo(-h * 0.004, -h * 0.05)
    ..lineTo(h * 0.012, -h * 0.03)
    ..lineTo(-h * 0.002, h * 0.02)
    ..lineTo(h * 0.006, h * 0.06);
  canvas.drawPath(
    crack,
    Paint()
      ..color = s.edge
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1, h * 0.004),
  );
  canvas.restore();

  if (s.glitch > 0) {
    canvas.restore();
    // Fatias da figura deslocadas para o lado
    final slices = (3 + 6 * s.glitch).round();
    final band = Paint()..color = s.body.withValues(alpha: 0.6);
    for (var k = 0; k < slices; k++) {
      final sy = top + r.nextDouble() * h;
      final sh = h * (0.01 + 0.03 * r.nextDouble());
      final dx = (r.nextDouble() - 0.5) * h * 0.3 * s.glitch;
      canvas.drawRect(Rect.fromLTWH(x - h * 0.12 + dx, sy, h * 0.24, sh), band);
    }
  }
}

/// Desenha a Mariposa: corpo escuro e quatro asas pálidas com olhos falsos.
/// [flap] de -1 a 1 abre e fecha as asas.
void drawMoth(Canvas canvas, Offset c, double size, double flap) {
  final wing = Paint()
    ..shader = RadialGradient(
      colors: const [Color(0xFFD9CFBC), Color(0xFF8C8170), Color(0xFF3B342B)],
      stops: const [0, 0.6, 1],
    ).createShader(Rect.fromCircle(center: c, radius: size));
  final edge = Paint()
    ..color = const Color(0xFF2A241D)
    ..style = PaintingStyle.stroke
    ..strokeWidth = max(1, size * 0.02);
  final open = 0.75 + 0.25 * flap;
  for (final side in const [-1.0, 1.0]) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(side * open, 1);
    final upper = Path()
      ..moveTo(0, -size * 0.05)
      ..cubicTo(
        size * 0.4,
        -size * 0.75,
        size * 1.05,
        -size * 0.6,
        size * 0.95,
        -size * 0.05,
      )
      ..cubicTo(size * 0.7, size * 0.1, size * 0.3, size * 0.05, 0, 0)
      ..close();
    final lower = Path()
      ..moveTo(0, size * 0.02)
      ..cubicTo(
        size * 0.35,
        size * 0.1,
        size * 0.75,
        size * 0.3,
        size * 0.55,
        size * 0.7,
      )
      ..cubicTo(size * 0.35, size * 0.8, size * 0.1, size * 0.45, 0, size * 0.1)
      ..close();
    canvas
      ..drawPath(upper, wing)
      ..drawPath(upper, edge)
      ..drawPath(lower, wing)
      ..drawPath(lower, edge);
    // O olho falso na asa: o que faz parecer que ela olha para você.
    canvas
      ..drawCircle(
        Offset(size * 0.55, -size * 0.35),
        size * 0.13,
        Paint()..color = const Color(0xFF1A1511),
      )
      ..drawCircle(
        Offset(size * 0.55, -size * 0.35),
        size * 0.06,
        Paint()..color = const Color(0xFFE8E0D0),
      );
    canvas.restore();
  }
  final body = Rect.fromCenter(
    center: c.translate(0, size * 0.15),
    width: size * 0.16,
    height: size * 0.75,
  );
  canvas.drawOval(body, Paint()..color = const Color(0xFF1A1511));
  final antenna = Paint()
    ..color = const Color(0xFF1A1511)
    ..strokeWidth = max(1, size * 0.015)
    ..style = PaintingStyle.stroke;
  for (final side in const [-1.0, 1.0]) {
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy - size * 0.2)
        ..quadraticBezierTo(
          c.dx + side * size * 0.1,
          c.dy - size * 0.5,
          c.dx + side * size * 0.3,
          c.dy - size * 0.55,
        ),
      antenna,
    );
  }
}

/// O rosto dele de perto, para o susto: porcelana rachada iluminada de
/// baixo, um pedaço do rosto faltando, órbitas fundas com duas pupilas
/// acesas e a boca rasgada de orelha a orelha. [c] é o centro do rosto, [w]
/// a largura, [open] (0 a 1) o quanto a boca abre.
void drawScareFace(
  Canvas canvas,
  Offset c,
  double w,
  double open, {
  bool tint = false,
}) {
  final rx = w / 2, ry = w * 0.66;
  final face = Rect.fromCenter(center: c, width: rx * 2, height: ry * 2);
  Offset at(double fx, double fy) => Offset(c.dx + fx * rx, c.dy + fy * ry);
  Path poly(List<(double, double)> pts) {
    final p = Path()
      ..moveTo(at(pts[0].$1, pts[0].$2).dx, at(pts[0].$1, pts[0].$2).dy);
    for (final (x, y) in pts.skip(1)) {
      final o = at(x, y);
      p.lineTo(o.dx, o.dy);
    }
    return p..close();
  }

  // Porcelana iluminada de baixo (luz de lanterna no queixo).
  canvas.drawOval(
    face,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.15, 0.55),
        radius: 1.05,
        colors: tint
            ? const [Color(0xFFE8C9B8), Color(0xFF9C6E5E), Color(0xFF2A100C)]
            : const [Color(0xFFE9E1D0), Color(0xFF9C9382), Color(0xFF1E1A16)],
        stops: const [0, 0.55, 1],
      ).createShader(face),
  );

  // Fuligem escorrendo dos olhos.
  final soot = Paint()
    ..shader =
        const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xAA0B0806), Color(0x000B0806)],
        ).createShader(
          Rect.fromLTRB(
            face.left,
            c.dy - ry * 0.2,
            face.right,
            c.dy + ry * 0.5,
          ),
        );
  for (final (x, len, wd) in const [
    (-0.42, 0.55, 0.05),
    (-0.3, 0.38, 0.03),
    (0.36, 0.62, 0.06),
    (0.47, 0.3, 0.025),
  ]) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(at(x, 0).dx, at(0, -0.12).dy, wd * rx, len * ry),
        Radius.circular(wd * rx),
      ),
      soot,
    );
  }

  // Órbitas: sombra funda em volta, buraco preto, pupila acesa.
  for (final (x, y, sw, sh) in const [
    (-0.38, -0.16, 0.3, 0.17),
    (0.37, -0.13, 0.26, 0.15),
  ]) {
    final eye = Offset(at(x, y).dx, at(x, y).dy);
    final shadowR = Rect.fromCenter(
      center: eye,
      width: sw * rx * 3.2,
      height: sh * ry * 3.4,
    );
    canvas.drawOval(
      shadowR,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xEE050302), Color(0x00050302)],
        ).createShader(shadowR),
    );
    canvas.drawOval(
      Rect.fromCenter(center: eye, width: sw * rx * 2, height: sh * ry * 2),
      Paint()..color = const Color(0xFF020101),
    );
    final glow = Rect.fromCircle(center: eye, radius: rx * 0.07);
    canvas.drawCircle(
      eye,
      rx * 0.07,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xCCFF3B2A), Color(0x00FF3B2A)],
        ).createShader(glow),
    );
    canvas.drawCircle(
      eye,
      rx * 0.018,
      Paint()..color = const Color(0xFFFFF4E0),
    );
  }

  // O pedaço que falta: buraco escuro com a borda lascada.
  final chunk = poly(const [
    (0.18, -0.92),
    (0.4, -0.86),
    (0.52, -0.66),
    (0.44, -0.55),
    (0.5, -0.43),
    (0.33, -0.47),
    (0.26, -0.62),
    (0.12, -0.7),
  ]);
  canvas.drawPath(chunk, Paint()..color = const Color(0xFF070403));
  canvas.drawPath(
    chunk,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = rx * 0.025
      ..color = const Color(0xFF5A4A3C),
  );

  // Rachaduras.
  final crack = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = const Color(0xFF241A12);
  for (final (pts, wd) in const [
    (
      [(0.3, -0.5), (0.22, -0.32), (0.3, -0.18), (0.18, 0.02), (0.24, 0.2)],
      0.022,
    ),
    ([(-0.05, -0.98), (-0.12, -0.7), (-0.02, -0.52), (-0.16, -0.3)], 0.016),
    ([(-0.38, -0.02), (-0.5, 0.18), (-0.44, 0.3), (-0.62, 0.52)], 0.014),
    ([(0.18, 0.02), (0.42, 0.1), (0.55, 0.06)], 0.01),
    ([(-0.16, -0.3), (-0.3, -0.38), (-0.42, -0.34)], 0.01),
  ]) {
    final path = Path();
    for (final (i, (x, y)) in pts.indexed) {
      final o = at(x, y);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, crack..strokeWidth = wd * rx);
  }

  // A boca rasgada: abre para baixo, com lascas de porcelana como dentes.
  final o = open.clamp(0.0, 1.0);
  final top = <(double, double)>[
    (-0.62, 0.36),
    (-0.45, 0.4),
    (-0.3, 0.36),
    (-0.12, 0.41),
    (0.05, 0.37),
    (0.22, 0.42),
    (0.4, 0.37),
    (0.6, 0.31),
  ];
  final bottom = [
    for (final (x, y) in top.reversed)
      (
        x * (1 - 0.08 * o),
        y + (0.06 + 0.42 * o) * (1 - (x.abs() / 0.62) * (x.abs() / 0.62)),
      ),
  ];
  final mouth = poly([...top, ...bottom]);
  canvas.drawPath(mouth, Paint()..color = const Color(0xFF030101));
  canvas.save();
  canvas.clipPath(mouth);
  final tooth = Paint()..color = const Color(0xFFD9D0BE);
  for (var i = 0; i < top.length - 1; i++) {
    final (x0, y0) = top[i];
    final (x1, y1) = top[i + 1];
    final mx = (x0 + x1) / 2;
    canvas.drawPath(
      poly([
        (x0, y0 - 0.02),
        (x1, y1 - 0.02),
        (mx + 0.01, (y0 + y1) / 2 + 0.07 + 0.04 * (i % 2)),
      ]),
      tooth,
    );
  }
  for (var i = 0; i < bottom.length - 1; i += 2) {
    final (x0, y0) = bottom[i];
    final (x1, y1) = bottom[i + 1];
    canvas.drawPath(
      poly([
        (x0, y0 + 0.02),
        (x1, y1 + 0.02),
        ((x0 + x1) / 2, (y0 + y1) / 2 - 0.06),
      ]),
      tooth,
    );
  }
  canvas.restore();
  canvas.drawPath(
    mouth,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = rx * 0.014
      ..color = const Color(0xFF3A2C20),
  );

  // Bordas no escuro: só o meio do rosto recebe a luz.
  canvas.drawOval(
    face.inflate(rx * 0.02),
    Paint()
      ..shader = const RadialGradient(
        radius: 0.72,
        colors: [Color(0x00000000), Color(0x00000000), Color(0xCC000000)],
        stops: [0, 0.72, 1],
      ).createShader(face),
  );
}

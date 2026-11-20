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

import 'dart:math';
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import '../game/vigil_game.dart';
import 'mannequin.dart';

/// Quanto do quarto cabe na tela, de ponta a ponta.
const fieldOfView = 70 * pi / 180;

/// Desenha a noite por cima da câmera (ou de um quarto escuro, sem câmera):
/// o escuro, o feixe da lanterna, o Manequim e o chiado.
class RoomPainter extends CustomPainter {
  RoomPainter(
    this.game, {
    required this.flash,
    required this.flashPan,
    this.hasCamera = false,
    this.clock = 0,
    this.shadow = -1,
  });

  /// Um vulto passando pela tela (susto falso): de 0 a 1 enquanto atravessa,
  /// negativo quando não há.
  final double shadow;

  final VigilGame game;

  /// Um clarão vermelho na borda do lado do último som (0 a 1).
  final double flash;
  final double flashPan;

  /// Com a câmera, o fundo é o quarto de verdade; sem ela, um quarto desenhado.
  final bool hasCamera;

  /// Tempo da animação (segundos), para o balanço do andar.
  final double clock;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random();
    final cx = size.width / 2;
    final pxPerRad = size.width / fieldOfView;
    final beamR = game.rules.beamHalfWidth * pxPerRad * 1.25;
    final beamC = Offset(cx, size.height * 0.48);
    final lit = game.lit;

    if (!hasCamera) _room(canvas, size, pxPerRad);

    // O escuro, com o buraco do feixe.
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Color.fromRGBO(0, 0, 0, hasCamera ? 0.88 : 0.75),
    );
    if (lit) {
      canvas.drawCircle(
        beamC,
        beamR,
        Paint()
          ..blendMode = BlendMode.dstOut
          ..shader = const RadialGradient(
            colors: [Colors.black, Color(0xCC000000), Colors.transparent],
            stops: [0, 0.6, 1],
          ).createShader(Rect.fromCircle(center: beamC, radius: beamR)),
      );
    }
    canvas.restore();
    if (lit) {
      canvas.drawCircle(
        beamC,
        beamR,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0x30FFE6B0), Colors.transparent],
          ).createShader(Rect.fromCircle(center: beamC, radius: beamR)),
      );
    }

    _mannequin(canvas, size, pxPerRad, beamC, beamR, rng);
    _moth(canvas, size, pxPerRad);
    _passingShadow(canvas, size);
    _static(canvas, size, rng);
    _grain(canvas, size, rng);

    if (flash > 0) {
      final left = flashPan < 0;
      final rect = Offset.zero & size;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: left ? Alignment.centerLeft : Alignment.centerRight,
            end: Alignment.center,
            colors: [
              Color.fromRGBO(150, 0, 0, 0.45 * flash),
              Colors.transparent,
            ],
          ).createShader(rect),
      );
    }
  }

  /// Sem câmera: um quarto desenhado, para dar onde se apoiar ao girar.
  void _room(Canvas canvas, Size size, double pxPerRad) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2A2724), Color(0xFF3A342C), Color(0xFF1C1915)],
          stops: [0, 0.6, 1],
        ).createShader(Offset.zero & size),
    );
    final floorY = size.height * 0.66;
    final line = Paint()
      ..color = const Color(0xFF16130F)
      ..strokeWidth = 3;
    canvas.drawLine(Offset(0, floorY), Offset(size.width, floorY), line);
    double? xOf(double a) {
      final d = angleDiff(a, game.heading);
      if (d.abs() > fieldOfView / 2 + 0.6) return null;
      return size.width / 2 + d * pxPerRad;
    }

    // Cantos a cada 90°, uma porta, uma janela e um armário.
    for (var k = 0; k < 4; k++) {
      final x = xOf(k * pi / 2 + pi / 4);
      if (x != null) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      }
    }
    final dark = Paint()..color = const Color(0xFF14110E);
    for (final (a, w, top, bottom) in const [
      (0.0, 150.0, 0.30, 0.66), // porta
      (pi * 0.75, 170.0, 0.32, 0.5), // janela
      (pi * 1.35, 190.0, 0.22, 0.66), // armário
    ]) {
      final x = xOf(a);
      if (x == null) continue;
      canvas.drawRect(
        Rect.fromLTRB(
          x - w / 2,
          size.height * top,
          x + w / 2,
          size.height * bottom,
        ),
        dark,
      );
    }
  }

  void _mannequin(
    Canvas canvas,
    Size size,
    double pxPerRad,
    Offset beamC,
    double beamR,
    Random rng,
  ) {
    final g = game;
    if (!g.present || !g.visible) return;
    final x = size.width / 2 + g.offset * pxPerRad;
    if ((x - size.width / 2).abs() > size.width) return;
    final near = 1 - g.distance;
    final h = size.height * (0.28 + 0.95 * near * near + 0.25 * near);
    final charging = g.mode == Mode.charging;
    final shake = charging ? (rng.nextDouble() - 0.5) * 14 : 0.0;
    final bob = charging ? 0.0 : sin(clock * 5) * 4;
    // A cabeça sobe na tela conforme ele chega: de perto, o rosto domina.
    final headY = size.height * (0.42 - 0.17 * near);
    final feet = Offset(x + shake, headY + 0.92 * h + bob);

    MannequinStyle pose(MannequinStyle base) => base.copyWith(
      armsUp: charging ? 1 : 0,
      headTilt: charging ? 0 : sin(clock * 0.7) * 0.25,
      glitch: g.revealed ? 0.6 : (charging ? 0.1 : 0),
    );
    // As duas passadas usam o mesmo sorteio, para o defeito coincidir.
    final seed = rng.nextInt(1 << 30);
    // Fora do feixe, silhueta; invisível, só existe onde a luz bate.
    if (!g.revealed) {
      drawMannequin(
        canvas,
        feet,
        h,
        pose(MannequinStyle.dark),
        rng: Random(seed),
      );
    }
    if (g.lit) {
      canvas.save();
      canvas.clipPath(
        Path()..addOval(Rect.fromCircle(center: beamC, radius: beamR * 0.95)),
      );
      drawMannequin(
        canvas,
        feet,
        h,
        pose(MannequinStyle.lit),
        rng: Random(seed),
      );
      canvas.restore();
    }
  }

  void _moth(Canvas canvas, Size size, double pxPerRad) {
    final g = game;
    if (!g.mothVisible) return;
    final x = size.width / 2 + g.mothOffset * pxPerRad;
    final s = size.width * (0.12 + 0.45 * (1 - g.mothDistance));
    final y = size.height * (0.38 + 0.04 * sin(clock * 3));
    drawMoth(canvas, Offset(x, y), s, sin(clock * 38));
  }

  /// O vulto do susto falso: uma silhueta que cruza a tela de um lado a outro.
  void _passingShadow(Canvas canvas, Size size) {
    if (shadow < 0 || shadow > 1) return;
    final x = -size.width * 0.3 + shadow * size.width * 1.6;
    drawMannequin(
      canvas,
      Offset(x, size.height * 0.8),
      size.height * 0.55,
      const MannequinStyle(
        body: Color(0xEE000000),
        edge: Color(0x22FFFFFF),
        eyes: Color(0x00000000),
      ),
    );
  }

  /// O chiado: barras que cortam a tela e um ruído grosso.
  void _static(Canvas canvas, Size size, Random rng) {
    final s = game.staticLevel;
    if (s <= 0.02) return;
    final bar = Paint();
    final bars = (4 + 26 * s).round();
    for (var k = 0; k < bars; k++) {
      final y = rng.nextDouble() * size.height;
      final hgt = 1 + rng.nextDouble() * 10 * s;
      final shade = rng.nextInt(200) + 55;
      bar.color = Color.fromRGBO(shade, shade, shade, 0.12 + 0.35 * s);
      canvas.drawRect(
        Rect.fromLTWH(
          rng.nextDouble() * size.width * 0.3,
          y,
          size.width * (0.4 + 0.6 * rng.nextDouble()),
          hgt,
        ),
        bar,
      );
    }
    final dots = [
      for (var k = 0; k < (1500 * s).round(); k++)
        Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height),
    ];
    canvas.drawPoints(
      PointMode.points,
      dots,
      Paint()
        ..color = Color.fromRGBO(220, 220, 220, 0.5 * s)
        ..strokeWidth = 2.5,
    );
  }

  /// Chuvisco leve, sempre.
  void _grain(Canvas canvas, Size size, Random rng) {
    final dots = [
      for (var k = 0; k < 500; k++)
        Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height),
    ];
    canvas.drawPoints(
      PointMode.points,
      dots,
      Paint()
        ..color = const Color(0x1AFFFFFF)
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(RoomPainter old) => true;
}

/// O susto: o rosto dele ocupa a tela. [t] vai de 1 a 0.
class ScarePainter extends CustomPainter {
  ScarePainter(this.t, {this.moth = false});
  final double t;

  /// Quem pegou: a Mariposa tem o próprio susto.
  final bool moth;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random();
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = rng.nextDouble() < 0.3
            ? const Color(0xFF2A0000)
            : Colors.black,
    );
    final shake = Offset(
      (rng.nextDouble() - 0.5) * 30,
      (rng.nextDouble() - 0.5) * 30,
    );
    if (moth) {
      drawMoth(
        canvas,
        size.center(Offset.zero) + shake,
        size.width * (0.9 + 0.3 * (1 - t)),
        rng.nextDouble() * 2 - 1,
      );
      return;
    }
    final h = size.height * (3.2 + 0.8 * (1 - t));
    // Os pés bem abaixo da tela: só a cabeça e os braços aparecem.
    drawMannequin(
      canvas,
      Offset(size.width / 2, size.height * 0.45 + h * 0.92) + shake,
      h,
      MannequinStyle.lit.copyWith(armsUp: 1, glitch: 0.4),
      rng: rng,
    );
  }

  @override
  bool shouldRepaint(ScarePainter old) => true;
}

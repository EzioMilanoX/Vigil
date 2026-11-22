import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import '../game/vigil_game.dart';
import 'mannequin.dart';

/// Um sorteador só para todos os quadros (criar um por quadro gera lixo).
final _rng = Random();

/// Pontos de ruído sorteados uma vez para o tamanho da tela; cada quadro usa
/// um trecho diferente, deslocado, para o chiado não parecer parado. Assim
/// o chiado não cria milhares de objetos a cada quadro.
Float32List? _noise;
Size? _noiseSize;
const _noisePoints = 4000;

Float32List _noiseFor(Size size) {
  if (_noise != null && _noiseSize == size) return _noise!;
  final r = Random(7);
  final list = Float32List(_noisePoints * 2);
  for (var i = 0; i < _noisePoints; i++) {
    list[2 * i] = r.nextDouble() * size.width;
    list[2 * i + 1] = r.nextDouble() * size.height;
  }
  _noiseSize = size;
  return _noise = list;
}

void _noiseDots(Canvas canvas, Size size, int count, Paint paint) {
  final all = _noiseFor(size);
  final n = min(count, _noisePoints);
  if (n <= 0) return;
  final start = _rng.nextInt(_noisePoints - n + 1);
  canvas.save();
  canvas.translate(
    (_rng.nextDouble() - 0.5) * 60,
    (_rng.nextDouble() - 0.5) * 60,
  );
  canvas.drawRawPoints(
    PointMode.points,
    Float32List.sublistView(all, start * 2, (start + n) * 2),
    paint,
  );
  canvas.restore();
}

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
    final rng = _rng;
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
      Paint()
        ..color = Color.fromRGBO(
          0,
          0,
          0,
          game.blackout ? 0.97 : (hasCamera ? 0.88 : 0.75),
        ),
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
    _eyesInTheDark(canvas, size, pxPerRad, rng);
    _faceInBeam(canvas, beamC, beamR, rng);
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
    final statue = g.tactic == Tactic.statue && !charging;
    final bob = charging || statue ? 0.0 : sin(clock * 5) * 4;
    // A cabeça sobe na tela conforme ele chega: de perto, o rosto domina.
    final headY = size.height * (0.42 - 0.17 * near);
    final feet = Offset(x + shake, headY + 0.92 * h + bob);

    MannequinStyle pose(MannequinStyle base) => base.copyWith(
      armsUp: charging
          ? 1
          : statue
          ? ((g.pose * 37) % 10) / 10 * (0.3 + 0.7 * near)
          : 0,
      headTilt: charging
          ? 0
          : statue
          ? (((g.pose * 53) % 7) - 3) * 0.16
          : sin(clock * 0.7) * 0.25,
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

  /// No apagão: de vez em quando, dois olhos acendem onde ele está.
  void _eyesInTheDark(Canvas canvas, Size size, double pxPerRad, Random rng) {
    final g = game;
    if (!g.blackout || !g.present || g.distance > 0.6) return;
    if (rng.nextDouble() > 0.05) return;
    final x = size.width / 2 + g.offset * pxPerRad;
    if ((x - size.width / 2).abs() > size.width * 0.6) return;
    final near = 1 - g.distance;
    final gap = size.width * (0.02 + 0.09 * near);
    final y = size.height * (0.42 - 0.17 * near) + gap * 0.3;
    final eye = Paint()..color = const Color(0xFFF0E6D2);
    canvas.drawCircle(Offset(x - gap, y), 1.5 + 3 * near, eye);
    canvas.drawCircle(Offset(x + gap, y), 1.5 + 3 * near, eye);
  }

  /// Susto falso: o rosto dele, de perto, pisca dentro do feixe.
  void _faceInBeam(Canvas canvas, Offset beamC, double beamR, Random rng) {
    if (game.faceFlash <= 0 || !game.lit) return;
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: beamC, radius: beamR * 1.05)),
    );
    drawScareFace(
      canvas,
      beamC + Offset((rng.nextDouble() - 0.5) * 16, beamR * 0.25),
      beamR * 2.1,
      0.55,
    );
    canvas.restore();
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
    _noiseDots(
      canvas,
      size,
      (1500 * s).round(),
      Paint()
        ..color = Color.fromRGBO(220, 220, 220, 0.5 * s)
        ..strokeWidth = 2.5,
    );
  }

  static final _grainPaint = Paint()
    ..color = const Color(0x1AFFFFFF)
    ..strokeWidth = 1.5;

  /// Chuvisco leve, sempre.
  void _grain(Canvas canvas, Size size, Random rng) {
    _noiseDots(canvas, size, 500, _grainPaint);
  }

  @override
  bool shouldRepaint(RoomPainter old) => true;
}

/// Quanto dura o susto na tela, em segundos.
const scareSeconds = 1.4;

/// O susto: o rosto dele avança da escuridão e ocupa a tela, com a imagem
/// rasgando, as cores se separando e um clarão. [t] vai de 1 a 0.
class ScarePainter extends CustomPainter {
  ScarePainter(this.t, {this.moth = false});
  final double t;

  /// Quem pegou: a Mariposa tem o próprio susto.
  final bool moth;

  static final _black = Paint()..color = Colors.black;
  static final _grain = Paint()
    ..color = const Color(0x40FFFFFF)
    ..strokeWidth = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = _rng;
    final full = Offset.zero & size;
    final e = (1 - t) * scareSeconds;
    if (moth) {
      canvas.drawRect(
        full,
        Paint()
          ..color = rng.nextDouble() < 0.3
              ? const Color(0xFF2A0000)
              : Colors.black,
      );
      drawMoth(
        canvas,
        size.center(Offset.zero) +
            Offset(
              (rng.nextDouble() - 0.5) * 30,
              (rng.nextDouble() - 0.5) * 30,
            ),
        size.width * (0.9 + 0.3 * (1 - t)),
        rng.nextDouble() * 2 - 1,
      );
      return;
    }

    // Um clarão logo depois do bote; depois, quadros pretos e avermelhados.
    final white = e > 0.13 && e < 0.17;
    canvas.drawRect(
      full,
      Paint()
        ..color = white
            ? const Color(0xFFF4EFE6)
            : rng.nextDouble() < 0.2
            ? const Color(0xFF300000)
            : Colors.black,
    );
    if (white) return;
    if (e > 0.55 && rng.nextDouble() < 0.08) return;

    // O bote: de longe até em cima de você em 0,13 s.
    final lunge = Curves.easeOutCubic.transform((e / 0.13).clamp(0.0, 1.0));
    final breathe = e > 0.13 ? 0.035 * sin(e * 47) : 0.0;
    final w = size.width * 1.2 * (0.28 + 1.0 * lunge + breathe);
    final decay = max(0.25, 1 - e / scareSeconds);
    final c =
        Offset(size.width / 2, size.height * 0.46) +
        Offset(
          (rng.nextDouble() - 0.5) * 44 * decay,
          (rng.nextDouble() - 0.5) * 44 * decay,
        );
    final open = (0.2 + e / 0.4).clamp(0.0, 1.0);

    if (e < 0.13) {
      // Rastro do bote.
      for (var k = 3; k >= 1; k--) {
        canvas.saveLayer(full, Paint()..color = const Color(0x40000000));
        drawScareFace(canvas, c, w * (1 - 0.14 * k), open);
        canvas.restore();
      }
    }

    // As cores se separando nas bordas.
    final split = size.width * (0.01 + 0.035 * rng.nextDouble()) * decay;
    for (final (color, dx) in [
      (const Color(0xFFFF2A2A), split),
      (const Color(0xFF2AFFFF), -split),
    ]) {
      canvas.saveLayer(
        full,
        Paint()
          ..colorFilter = ColorFilter.mode(color, BlendMode.modulate)
          ..blendMode = BlendMode.screen,
      );
      drawScareFace(canvas, c + Offset(dx, 0), w, open);
      canvas.restore();
    }
    drawScareFace(canvas, c, w, open, tint: rng.nextDouble() < 0.25);

    // A imagem rasgando: faixas deslocadas para o lado.
    for (var k = 0; k < 4; k++) {
      if (rng.nextDouble() > 0.55) continue;
      final y = rng.nextDouble() * size.height;
      canvas.save();
      canvas.clipRect(
        Rect.fromLTWH(0, y, size.width, 6 + rng.nextDouble() * 70),
      );
      canvas.drawRect(full, _black);
      drawScareFace(
        canvas,
        c + Offset((rng.nextDouble() - 0.5) * 120 * decay, 0),
        w,
        open,
      );
      canvas.restore();
    }
    _noiseDots(canvas, size, 900, _grain);
  }

  @override
  bool shouldRepaint(ScarePainter old) => true;
}

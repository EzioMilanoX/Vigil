// Mede o custo de desenhar a cena (fora da suíte normal):
//   flutter test telas/desempenho_test.dart
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/game/vigil_game.dart';
import 'package:vigil/ui/room_painter.dart';

void main() {
  test('300 quadros da cena mais pesada', () {
    final g = VigilGame(seed: 1, rules: Rules.forNight(4))
      ..lanternHeld = true
      ..cloaked = true
      ..distance = 0.3
      ..mothDistance = 0.4;
    g.heading = g.angle; // olhando para ele invisível: chiado no máximo
    g.mothAngle = g.heading;
    const size = Size(393, 851);
    void frame(int i) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      RoomPainter(
        g,
        flash: 0.5,
        flashPan: 0.3,
        clock: i / 60,
        shadow: (i % 60) / 60,
      ).paint(canvas, size);
      recorder.endRecording().dispose();
    }

    for (var i = 0; i < 30; i++) {
      frame(i); // aquece
    }
    final sw = Stopwatch()..start();
    for (var i = 0; i < 300; i++) {
      frame(i);
    }
    sw.stop();
    final perFrame = sw.elapsedMicroseconds / 300 / 1000;
    // ignore: avoid_print
    print('cena: ${perFrame.toStringAsFixed(3)} ms por quadro (orçamento: 16,7 ms)');
  });
}

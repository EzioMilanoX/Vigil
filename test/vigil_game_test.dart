import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/game/vigil_game.dart';

void main() {
  const step = 1 / 30;

  /// Avança [seconds] seguindo o Manequim com o olhar (se [follow]).
  void run(VigilGame g, double seconds, {bool follow = false}) {
    for (var t = 0.0; t < seconds; t += step) {
      if (follow) g.heading = g.angle;
      g.update(step);
    }
  }

  /// Roda até ele começar a correr.
  void untilCharge(VigilGame g) {
    for (var i = 0; i < 30 * 120 && g.mode != Mode.charging; i++) {
      g.update(step);
    }
    expect(g.mode, Mode.charging);
  }

  test('ângulos dão a volta', () {
    expect(angleDiff(0.1, tau - 0.1), closeTo(0.2, 1e-9));
    expect(angleDiff(tau - 0.1, 0.1), closeTo(-0.2, 1e-9));
    expect(wrapAngle(-pi / 2), closeTo(3 * pi / 2, 1e-9));
  });

  test('ele nunca começa na sua frente', () {
    for (var seed = 0; seed < 40; seed++) {
      final g = VigilGame(seed: seed);
      expect(g.offset.abs(), greaterThan(1), reason: 'seed $seed');
    }
  });

  test('ele rodeia, chega perto e corre', () {
    final g = VigilGame(seed: 1);
    final start = g.angle;
    run(g, 3);
    expect(g.angle, isNot(closeTo(start, 1e-3)), reason: 'andou em volta');
    expect(g.distance, lessThan(1));
    untilCharge(g);
    expect(g.takeCues().map((c) => c.kind), contains(CueKind.charge));
  });

  test('se ninguém dá o choque, ele chega e a noite acaba', () {
    final g = VigilGame(seed: 2);
    untilCharge(g);
    run(g, 3);
    expect(g.phase, Phase.lost);
  });

  test('choque cedo demais sai no vazio e precisa recarregar', () {
    final g = VigilGame(seed: 3);
    untilCharge(g);
    g.heading = g.angle;
    expect(g.shock(), isFalse, reason: 'ainda longe');
    expect(g.shockReady, greaterThan(0));
    expect(g.shock(), isFalse, reason: 'recarregando');
  });

  test('choque na hora certa, mirando nele, espanta', () {
    final g = VigilGame(seed: 4);
    untilCharge(g);
    while (g.distance > g.rules.shockWindow) {
      g.update(step);
    }
    g.heading = g.angle;
    expect(g.shock(), isTrue);
    expect(g.repels, 1);
    expect(g.mode, Mode.gone);
    run(g, g.rules.goneSeconds + 0.1);
    expect(g.mode, Mode.roaming, reason: 'voltou');
    expect(g.distance, closeTo(1, 0.05), reason: 'longe de novo');
  });

  test('choque na hora certa mas para o lado errado não pega', () {
    final g = VigilGame(seed: 5);
    untilCharge(g);
    while (g.distance > g.rules.shockWindow) {
      g.update(step);
    }
    g.heading = wrapAngle(g.angle + pi / 2);
    expect(g.shock(), isFalse);
  });

  test('espantar as vezes da noite faz amanhecer', () {
    final g = VigilGame(seed: 6, rules: const Rules(repelsToWin: 2));
    for (var k = 0; k < 2; k++) {
      while (g.mode != Mode.charging || g.distance > g.rules.shockWindow) {
        g.update(step);
      }
      g.heading = g.angle;
      expect(g.shock(), isTrue);
    }
    expect(g.phase, Phase.won);
  });

  test('invisível, só o chiado denuncia; a lanterna em cima o mostra', () {
    final g = VigilGame(seed: 7)
      ..cloaked = true
      ..distance = 0.7;
    g.heading = g.angle;
    expect(g.visible, isFalse);
    expect(g.staticLevel, greaterThan(0.5));

    g.lanternHeld = true;
    expect(g.revealed, isTrue);
    expect(g.visible, isTrue);
    expect(g.staticLevel, lessThan(0.01));

    g.lanternHeld = false;
    g.heading = wrapAngle(g.angle + pi);
    expect(g.staticLevel, 0, reason: 'olhando para o outro lado');
  });

  test('a pilha gasta segurando e recarrega apagada', () {
    final g = VigilGame(rules: const Rules(batterySeconds: 2));
    g.lanternHeld = true;
    run(g, 2.5);
    expect(g.battery, 0);
    expect(g.lit, isFalse);
    g.lanternHeld = false;
    run(g, 5);
    expect(g.battery, greaterThan(0));
  });

  test('a lembrança mente: chiado de um lado onde ele não está', () {
    final g = VigilGame(seed: 8, rules: const Rules(fakeStaticPerSecond: 50));
    g.update(step);
    final f = g.fakeStaticAngle!;
    expect(angleDiff(f, g.angle).abs(), greaterThan(1.5));
    g
      ..cloaked = false
      ..heading = f;
    expect(g.staticLevel, greaterThan(0.5));
  });

  test('passos avisam de que lado ele vem', () {
    final g = VigilGame(seed: 9);
    g.heading = wrapAngle(g.angle - pi / 2);
    final cues = <Cue>[];
    for (var i = 0; i < 30 * 10 && cues.isEmpty; i++) {
      g.heading = wrapAngle(g.angle - pi / 2); // ele sempre à direita
      g.update(step);
      cues.addAll(g.takeCues().where((c) => c.kind == CueKind.step));
    }
    expect(cues, isNotEmpty);
    expect(cues.first.pan, greaterThan(0.9));
  });

  test('cada noite é mais difícil', () {
    final n1 = Rules.forNight(1);
    final n4 = Rules.forNight(4);
    expect(n4.repelsToWin, greaterThan(n1.repelsToWin));
    expect(n4.chargeSeconds, lessThan(n1.chargeSeconds));
    expect(n4.batterySeconds, lessThan(n1.batterySeconds));
    expect(n1.repelsToWin, const Rules().repelsToWin);
  });

  test('finta: ele corre, para no meio e volta a rodear', () {
    final g = VigilGame(seed: 10, rules: const Rules(feintChance: 1));
    untilCharge(g);
    g.takeCues();
    run(g, 1.2);
    expect(g.mode, Mode.roaming);
    expect(g.distance, greaterThan(g.rules.chargeAt));
    expect(g.phase, Phase.playing);
    expect(g.takeCues().map((c) => c.kind), contains(CueKind.feint));
  });

  test('da noite 3 em diante, ele pode correr invisível', () {
    final g = VigilGame(seed: 11, rules: Rules.forNight(3))..cloaked = true;
    g.startCharge();
    expect(g.cloaked, isTrue);
    final g1 = VigilGame(seed: 11)..cloaked = true;
    g1.startCharge();
    expect(g1.cloaked, isFalse, reason: 'noite 1: aparece para correr');
  });

  test('a Mariposa vem com a luz e vai embora no escuro', () {
    final g = VigilGame(seed: 12, rules: const Rules(moth: true))
      ..scripted = true
      ..lanternHeld = true;
    run(g, 4);
    final perto = g.mothDistance;
    expect(perto, lessThan(1));
    g.lanternHeld = false;
    run(g, 2);
    expect(g.mothDistance, greaterThan(perto));
  });

  test('luz demais e a Mariposa pega você', () {
    final g = VigilGame(
      seed: 13,
      rules: const Rules(moth: true, batterySeconds: 999),
    )..lanternHeld = true;
    for (var i = 0; i < 30 * 40 && g.phase == Phase.playing; i++) {
      g.heading = g.angle; // e ainda espanta o manequim quando dá
      if (g.mode == Mode.charging && g.distance <= g.rules.shockWindow) {
        g.shock();
      }
      g.update(step);
    }
    expect(g.phase, Phase.lost);
    expect(g.killer, Killer.moth);
  });

  test('no tutorial ele não anda sozinho e não mata', () {
    final g = VigilGame(seed: 14)..scripted = true;
    final (a, d) = (g.angle, g.distance);
    run(g, 5);
    expect((g.angle, g.distance), (a, d));
    g.startCharge();
    run(g, 5);
    expect(g.phase, Phase.playing);
  });

  test('a noite conta o que traz de novo', () {
    expect(Rules.novelty(1), isNull);
    expect(Rules.novelty(4), contains('luz'));
    expect(Rules.forNight(4).moth, isTrue);
    expect(Rules.forNight(3).moth, isFalse);
  });
}

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/game/director.dart';
import 'package:vigil/game/vigil_game.dart';

void main() {
  const step = 1 / 30;

  /// Quantas vezes cada tática sai em 200 sorteios espalhados em [0, 1).
  Map<Tactic, int> sorteios(
    FearDirector d,
    List<Tactic> options, {
    required Tactic last,
  }) {
    final n = <Tactic, int>{};
    for (var i = 0; i < 200; i++) {
      final t = d.nextTactic(options, last: last, roll: (i + 0.5) / 200);
      n[t] = (n[t] ?? 0) + 1;
    }
    return n;
  }

  /// Passa [seconds] olhando sempre para [heading].
  void olhar(
    FearDirector d,
    double heading,
    double seconds, {
    bool lit = false,
  }) {
    for (var t = 0.0; t < seconds; t += step) {
      d.look(step, heading: heading, lit: lit);
    }
  }

  final noite3 = Rules.forNight(3).tactics;

  test('a primeira da noite é rondar e nenhuma se repete seguida', () {
    final d = FearDirector();
    expect(d.nextTactic(noite3, roll: 0.99), Tactic.roam);
    for (final last in noite3) {
      for (var i = 0; i < 50; i++) {
        final t = d.nextTactic(noite3, last: last, roll: i / 50);
        expect(t, isNot(last));
        expect(noite3, contains(t));
      }
    }
  });

  test('com uma tática só, repete (não há outra)', () {
    final d = FearDirector();
    expect(
      d.nextTactic(const [Tactic.roam], last: Tactic.roam, roll: 0.5),
      Tactic.roam,
    );
  });

  test('pesa a tática que mais pegou e alivia a que ele espanta fácil', () {
    final d = FearDirector();
    d.result(Tactic.ambush, Outcome.caught);
    d.result(Tactic.ambush, Outcome.close);
    d.result(Tactic.statue, Outcome.easy);
    d.result(Tactic.statue, Outcome.easy);
    expect(d.weight(Tactic.ambush), greaterThan(d.weight(Tactic.blackout)));
    expect(d.weight(Tactic.blackout), greaterThan(d.weight(Tactic.statue)));
    final n = sorteios(d, noite3, last: Tactic.roam);
    expect(n[Tactic.ambush]!, greaterThan(n[Tactic.blackout]!));
    expect(n[Tactic.ambush]!, greaterThan(n[Tactic.statue]!));
  });

  test('é justo: toda tática possível continua saindo', () {
    final d = FearDirector();
    for (var i = 0; i < 10; i++) {
      d.result(Tactic.ambush, Outcome.caught);
      d.result(Tactic.statue, Outcome.easy);
      d.result(Tactic.blackout, Outcome.easy);
    }
    final n = sorteios(d, noite3, last: Tactic.roam);
    expect(n.keys.toSet(), {Tactic.statue, Tactic.ambush, Tactic.blackout});
    for (final t in Tactic.values) {
      expect(d.weight(t), inInclusiveRange(0.5, 3.0));
    }
  });

  test('aprende o lado negligenciado', () {
    final d = FearDirector();
    // Sem dados: meio a meio.
    expect(d.neglectedChance(0), 0.5);
    // Vive olhando para a direita do quarto (entre 1,2 e 2,8 rad).
    olhar(d, 1.6, 20, lit: true);
    olhar(d, 2.4, 10);
    olhar(d, 0, 5);
    expect(d.watchedOn(0, 1), greaterThan(d.watchedOn(0, -1)));
    expect(d.neglectedChance(0), greaterThan(0.75));
    var esquerda = 0;
    for (var i = 0; i < 100; i++) {
      if (d.side(0, (i + 0.5) / 100) == -1) esquerda++;
    }
    expect(esquerda, greaterThan(70), reason: 'prefere a esquerda esquecida');
    expect(esquerda, lessThan(100), reason: 'mas não sempre');
  });

  test('o que ele lembra vai esquecendo', () {
    final d = FearDirector();
    olhar(d, 1.6, 10);
    final antes = d.watchedOn(0, 1);
    olhar(d, 0, 60);
    expect(d.watchedOn(0, 1), lessThan(antes * 0.5));
  });

  test('lanterna e chiado entram no perfil', () {
    final d = FearDirector();
    olhar(d, 0, 120, lit: true);
    expect(d.lanternShare, greaterThan(0.8));
    expect(d.affinity(Tactic.blackout), greaterThan(0));
    expect(
      d.affinity(Tactic.statue),
      0,
      reason: 'quem usa luz segura a estátua',
    );

    final escuro = FearDirector();
    olhar(escuro, 0, 120);
    expect(escuro.affinity(Tactic.statue), greaterThan(0));

    final lento = FearDirector();
    for (var i = 0; i < 6; i++) {
      lento.staticFound(4, found: false);
    }
    expect(lento.reaction, greaterThan(3));
    expect(lento.affinity(Tactic.roam), greaterThan(0));
  });

  test('depois de um susto forte, um respiro; depois a tensão sobe', () {
    final d = FearDirector();
    d.scared(CueKind.hit);
    expect(d.calm, greaterThan(3));
    expect(d.scareRate, 0);
    expect(d.faceRate, 0);
    olhar(d, 0, d.calm + 0.1);
    expect(d.scareRate, greaterThan(0));
    final cedo = d.scareRate;
    olhar(d, 0, 20);
    expect(d.scareRate, greaterThan(cedo));
    expect(d.scareRate, lessThanOrEqualTo(1.5));
    expect(d.breatherAfter(Outcome.close), greaterThan(0));
    expect(d.breatherAfter(Outcome.easy), 0);
  });

  /// Uma noite com o diretor, olhando sempre para a direita do quarto e
  /// espantando cada aparição. Devolve as táticas e os ângulos de chegada.
  List<(Tactic, double)> noite(int seed, FearDirector d) {
    final g = VigilGame(seed: seed, rules: Rules.forNight(3), director: d);
    final out = <(Tactic, double)>[];
    for (var k = 0; k < 8; k++) {
      out.add((g.tactic, g.angle));
      for (var i = 0; i < 30 * 4; i++) {
        g.heading = 1.6;
        g.update(step);
      }
      g.mode = Mode.gone;
      for (var i = 0; i < 30 * 5 && g.mode == Mode.gone; i++) {
        g.update(step);
      }
    }
    return out;
  }

  test('com o diretor, o jogo continua determinístico pelo seed', () {
    final a = noite(5, FearDirector());
    final b = noite(5, FearDirector());
    expect(a, b);
    expect(a.first.$1, Tactic.roam);
    for (var i = 1; i < a.length; i++) {
      expect(a[i].$1, isNot(a[i - 1].$1), reason: 'sem repetir seguida');
    }
    expect(noite(6, FearDirector()), isNot(a));
  });

  test('no jogo, ele aprende e chega mais pelo lado esquecido', () {
    final d = FearDirector();
    final g = VigilGame(seed: 3, director: d);
    var esquerda = 0;
    var total = 0;
    for (var k = 0; k < 30; k++) {
      // Olha para a direita do quarto quase sempre, e volta à frente.
      for (var i = 0; i < 30 * 3; i++) {
        g.heading = 1.8;
        g.update(step);
      }
      g.heading = 0;
      g.mode = Mode.gone;
      for (var i = 0; i < 30 * 5 && g.mode == Mode.gone; i++) {
        g.update(step);
      }
      if (g.phase != Phase.playing) break;
      total++;
      if (angleDiff(g.angle, 0) < 0) esquerda++;
    }
    expect(total, greaterThan(20));
    expect(esquerda / total, greaterThan(0.6));
  });

  test('quando ele pega, a tática conta como pegou', () {
    final d = FearDirector();
    final g = VigilGame(seed: 2, director: d);
    for (var i = 0; i < 30 * 120 && g.phase == Phase.playing; i++) {
      g.heading = wrapAngle(g.angle + pi);
      g.update(step);
    }
    expect(g.killer, Killer.mannequin);
    expect(d.lastOutcome, Outcome.caught);
    expect(d.pressureOf(Tactic.roam), greaterThan(0.35));
  });

  test('espantar mirando desde o começo conta como fácil e sem respiro', () {
    final d = FearDirector();
    final g = VigilGame(seed: 4, director: d);
    while (g.mode != Mode.charging || g.distance > g.rules.shockWindow) {
      g.heading = g.angle;
      g.update(step);
    }
    expect(g.shock(), isTrue);
    expect(d.lastOutcome, Outcome.easy);
    expect(d.pressureOf(Tactic.roam), lessThan(0.35));
  });

  group('recentralizar', () {
    test('a frente vira o norte e nada muda em relação a você', () {
      final g = VigilGame(seed: 9, rules: const Rules(moth: true))
        ..heading = 2.3
        ..fakeStaticAngle = 1;
      final offset = g.offset;
      final mariposa = g.mothOffset;
      final chiado = angleDiff(g.fakeStaticAngle!, g.heading);
      g.recenter();
      expect(g.heading, 0);
      expect(g.offset, closeTo(offset, 1e-9));
      expect(g.mothOffset, closeTo(mariposa, 1e-9));
      expect(angleDiff(g.fakeStaticAngle!, g.heading), closeTo(chiado, 1e-9));
    });

    test('o que o diretor lembra do quarto gira junto', () {
      final d = FearDirector();
      final g = VigilGame(seed: 1, director: d)..heading = 1;
      // Olhou muito para 2,6 rad (à direita de quem olha para 1).
      olhar(d, 2.6, 20);
      final direita = d.watchedOn(g.heading, 1);
      g.recenter();
      expect(d.watchedOn(0, 1), closeTo(direita, direita * 0.15));
      expect(d.watchedOn(0, 1), greaterThan(d.watchedOn(0, -1)));
    });
  });
}

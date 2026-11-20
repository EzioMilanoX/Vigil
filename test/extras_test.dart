import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/data/save.dart';
import 'package:vigil/game/achievements.dart';
import 'package:vigil/game/vigil_game.dart';
import 'package:vigil/ui/sounds.dart';
import 'package:vigil/ui/title_screen.dart';

void main() {
  test('o som 3D escolhe a direção gravada mais próxima', () {
    expect(Sounds.direction(0), 0);
    expect(Sounds.direction(pi / 2), 90, reason: 'direita');
    expect(Sounds.direction(-pi / 2), 270, reason: 'esquerda');
    expect(Sounds.direction(pi), 180, reason: 'atrás');
    expect(Sounds.direction(0.3), 0);
    expect(Sounds.direction(0.5), 45);
  });

  test('os avisos levam o ângulo de onde vêm', () {
    final g = VigilGame(seed: 1);
    g.heading = wrapAngle(g.angle - pi / 2); // ele à direita
    g.shockReady = 0;
    g.shock(); // erra: aviso de "miss" com o ângulo dele
    final c = g.takeCues().single;
    expect(c.angle, closeTo(pi / 2, 1e-9));
    expect(g.misses, 1);
  });

  test('o jogo conta lanterna e choques perfeitos', () {
    final g = VigilGame(seed: 2)..lanternHeld = true;
    for (var i = 0; i < 60; i++) {
      g.update(1 / 30);
    }
    expect(g.lanternTime, closeTo(2, 0.05));
    g
      ..mode = Mode.charging
      ..distance = 0.05
      ..heading = g.angle
      ..shockReady = 0;
    expect(g.shock(), isTrue);
    expect(g.perfectHits, 1);
  });

  test('conquistas da noite, sem repetir as já ganhas', () async {
    final save = Save(persist: false);
    final novas = await save.finish(
      const NightResult(
        night: 1,
        won: true,
        time: 100,
        repels: 3,
        lanternTime: 8,
        perfectHits: 1,
      ),
    );
    expect(novas.map((a) => a.id).toSet(), {
      'noite1',
      'frio',
      'escuro',
      'perfeito',
    });
    expect(save.unlocked, 2);
    final denovo = await save.finish(
      const NightResult(night: 1, won: true, time: 90, repels: 3),
    );
    expect(denovo, isEmpty, reason: 'nada novo');
    expect(save.recordOf(1).bestTime, 90);
  });

  test('perder também conta espantos para "Ateliê fechado"', () async {
    final save = Save(persist: false)..totalRepels = 28;
    final novas = await save.finish(
      const NightResult(night: 3, won: false, time: 50, repels: 2),
    );
    expect(novas.single.id, 'cacador');
    expect(save.recordOf(3).deaths, 1);
  });

  testWidgets('o diário mostra a história e o achado de cada noite vencida', (
    tester,
  ) async {
    final save = Save(persist: false)
      ..unlocked = 3
      ..unlockedAchievements.add('noite1');
    await tester.pumpWidget(MaterialApp(home: JournalScreen(save: save)));
    expect(find.text('NOITE 1'), findsOneWidget);
    expect(find.text('NOITE 2'), findsOneWidget);
    expect(find.text('NOITE 3'), findsNothing);
    expect(find.textContaining('Prova 1 de 7'), findsOneWidget);
    await tester.tap(find.textContaining('Conquistas 1/'));
    await tester.pumpAndSettle();
    expect(find.text('Primeira vigília'), findsOneWidget);
  });
}

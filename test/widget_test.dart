import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/data/save.dart';
import 'package:vigil/game/tutorial.dart';
import 'package:vigil/game/vigil_game.dart';
import 'package:vigil/ui/game_screen.dart';
import 'package:vigil/ui/title_screen.dart';

void main() {
  Save fresh() => Save(persist: false);

  Future<void> phone(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: home));
  }

  Future<void> frames(WidgetTester tester, int n) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 33));
    }
  }

  testWidgets('a lanterna só fica acesa enquanto segura', (tester) async {
    await phone(tester, GameScreen(save: fresh(), seed: 1, useSensors: false));
    expect(find.byIcon(Icons.flashlight_off), findsOneWidget);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('lanterna'))),
    );
    await tester.pump();
    expect(find.byIcon(Icons.flashlight_on), findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(find.byIcon(Icons.flashlight_off), findsOneWidget);
  });

  testWidgets('o choque precisa recarregar', (tester) async {
    await phone(tester, GameScreen(save: fresh(), seed: 1, useSensors: false));
    await tester.tap(find.byKey(const Key('choque')));
    await tester.pump();
    expect(find.text('Carregando'), findsOneWidget);
    await frames(tester, 60);
    expect(find.text('Choque'), findsOneWidget);
  });

  testWidgets('pausar congela a noite', (tester) async {
    final g = VigilGame(seed: 2);
    await phone(
      tester,
      GameScreen(save: fresh(), debugGame: g, useSensors: false),
    );
    await frames(tester, 5);
    await tester.tap(find.byKey(const Key('pausar')));
    await tester.pump();
    expect(find.text('Pausado'), findsOneWidget);
    final t = g.time;
    await frames(tester, 30);
    expect(g.time, t);
    await tester.tap(find.text('Continuar'));
    await frames(tester, 10);
    expect(g.time, greaterThan(t));
  });

  testWidgets('perder conta no recorde da noite', (tester) async {
    final save = fresh();
    final g = VigilGame(seed: 3)
      ..distance = 0.01
      ..angle = 2;
    g.startCharge();
    await phone(
      tester,
      GameScreen(save: save, debugGame: g, useSensors: false),
    );
    await frames(tester, 90);
    expect(g.phase, Phase.lost);
    expect(save.recordOf(1).deaths, 1);
    expect(find.text('Ele tomou a sua medida.'), findsOneWidget);
  });

  testWidgets('o menu leva ao treino na primeira vez', (tester) async {
    await phone(tester, TitleScreen(save: fresh(), useSensors: false));
    expect(find.text('VIGIL'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'cabe na tela');
    await tester.tap(find.byKey(const Key('jogar')));
    await frames(tester, 20);
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text('Treino   '), findsOneWidget);
  });

  testWidgets('noites mostram recordes e a próxima trancada', (tester) async {
    final save = fresh()
      ..unlocked = 2
      ..tutorialDone = true;
    save.recordOf(1)
      ..wins = 2
      ..bestTime = 95;
    await phone(tester, NightsScreen(save: save, useSensors: false));
    expect(find.textContaining('melhor 1:35'), findsOneWidget);
    expect(find.text('Vença a noite 2 para liberar'), findsOneWidget);
  });

  testWidgets('a história antes da noite e o botão de começar', (tester) async {
    await phone(
      tester,
      StoryScreen(save: fresh(), night: 4, useSensors: false),
    );
    await tester.tap(find.byType(StoryScreen));
    await tester.pump();
    expect(find.textContaining('casulos'), findsOneWidget);
    expect(find.textContaining('vem atrás da luz'), findsOneWidget);
    await tester.tap(find.text('Começar a noite 4'));
    await frames(tester, 20);
    expect(find.byType(GameScreen), findsOneWidget);
  });

  testWidgets('configurações mudam o save', (tester) async {
    final save = fresh();
    await phone(tester, SettingsScreen(save: save));
    await tester.tap(find.text('Inverter o giro'));
    await tester.pump();
    expect(save.settings.invertTurn, isTrue);
  });

  testWidgets('o diretor do medo vem ligado e dá para desligar', (
    tester,
  ) async {
    final save = fresh();
    expect(save.settings.fearDirector, isTrue);
    await phone(tester, SettingsScreen(save: save));
    // Fica no fim da lista: rola até o fim.
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('diretor')));
    await tester.pump();
    expect(save.settings.fearDirector, isFalse);
    expect(save.settings.toJson()['fearDirector'], isFalse);
    final lido = Settings()..load(save.settings.toJson());
    expect(lido.fearDirector, isFalse);
  });

  testWidgets('recentralizar faz da frente de agora o norte', (tester) async {
    final g = VigilGame(seed: 2)..heading = 2;
    final offset = g.offset;
    await phone(
      tester,
      GameScreen(save: fresh(), debugGame: g, useSensors: false),
    );
    await tester.tap(find.byKey(const Key('recentralizar')));
    await tester.pump();
    expect(g.heading, 0);
    expect(g.offset, closeTo(offset, 0.05));
    expect(find.text('frente aqui  '), findsOneWidget);
    await frames(tester, 45);
    expect(find.text('frente aqui  '), findsNothing);
  });

  test('o tutorial avança quando o jogador faz a coisa certa', () {
    final g = VigilGame(seed: 4, rules: const Rules(chargeSeconds: 2.6));
    final coach = TutorialCoach(g);
    expect(coach.step, TutorialStep.find);
    g.heading = g.angle;
    coach.update(0.1);
    expect(coach.step, TutorialStep.light);
    g.lanternHeld = true;
    for (var i = 0; i < 30; i++) {
      g.update(1 / 30);
      coach.update(1 / 30);
    }
    expect(coach.step, TutorialStep.cloaked);
    g.heading = g.angle;
    for (var i = 0; i < 30; i++) {
      g.update(1 / 30);
      coach.update(1 / 30);
    }
    expect(coach.step, TutorialStep.shock);
    while (g.distance > g.rules.shockWindow) {
      g.update(1 / 30);
      coach.update(1 / 30);
    }
    expect(coach.message, 'AGORA!');
    g.heading = g.angle;
    expect(g.shock(), isTrue);
    coach.update(0.1);
    expect(coach.step, TutorialStep.done);
  });

  test('o save guarda recordes e libera a próxima noite', () async {
    final save = fresh();
    await save.won(1, 120, 3);
    await save.won(1, 90, 3);
    expect(save.unlocked, 2);
    expect(save.recordOf(1).bestTime, 90);
    expect(save.totalRepels, 6);
  });
}

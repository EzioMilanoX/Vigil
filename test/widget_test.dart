import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/ui/game_screen.dart';
import 'package:vigil/ui/title_screen.dart';

void main() {
  const screen = GameScreen(
    seed: 1,
    useGyroscope: false,
    useSound: false,
    useCamera: false,
  );

  testWidgets('a lanterna só fica acesa enquanto segura', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: screen));
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
    await tester.pumpWidget(const MaterialApp(home: screen));
    expect(find.text('Choque'), findsOneWidget);
    await tester.tap(find.byKey(const Key('choque')));
    await tester.pump();
    expect(find.text('Carregando'), findsOneWidget);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 33));
    }
    expect(find.text('Choque'), findsOneWidget);
  });

  testWidgets('arrastar gira o quarto', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: screen));
    await tester.drag(find.byType(GameScreen), const Offset(300, 0));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tela de início explica e abre a noite', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: TitleScreen(
          useGyroscope: false,
          useSound: false,
          useCamera: false,
        ),
      ),
    );
    expect(find.text('VIGIL'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'cabe na tela');
    await tester.tap(find.text('Começar'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(GameScreen), findsOneWidget);
  });
}

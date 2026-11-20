// Gera capturas das telas (fora da suíte normal):
//   flutter test telas/telas_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/data/save.dart';
import 'package:vigil/game/vigil_game.dart';
import 'package:vigil/main.dart';
import 'package:vigil/ui/game_screen.dart';
import 'package:vigil/ui/room_painter.dart';
import 'package:vigil/ui/title_screen.dart';

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    final bytes = File(f).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

void main() {
  const fonts = 'C:/flutter/bin/cache/artifacts/material_fonts';
  setUpAll(() async {
    await _font('Roboto', [
      '$fonts/roboto-regular.ttf',
      '$fonts/roboto-light.ttf',
      '$fonts/roboto-medium.ttf',
      '$fonts/roboto-bold.ttf',
    ]);
    await _font('MaterialIcons', ['$fonts/materialicons-regular.otf']);
  });

  Future<void> phone(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: vigilTheme,
        home: child,
      ),
    );
    await tester.pump();
  }

  VigilGame night({
    required double offset,
    required double distance,
    Mode mode = Mode.roaming,
    bool cloaked = false,
    bool lantern = false,
  }) {
    final g = VigilGame(seed: 3, rules: Rules.forNight(2))
      ..repels = 1
      ..battery = 0.7
      ..heading = 0.4
      ..mode = mode
      ..cloaked = cloaked
      ..distance = distance
      ..lanternHeld = lantern;
    g.angle = wrapAngle(g.heading + offset);
    return g;
  }

  Future<void> game(
    WidgetTester tester,
    VigilGame g,
    String file, {
    int nightNo = 2,
  }) async {
    await phone(
      tester,
      GameScreen(
        save: Save(persist: false),
        debugGame: g,
        night: nightNo,
        useSensors: false,
      ),
    );
    await expectLater(find.byType(GameScreen), matchesGoldenFile(file));
  }

  testWidgets('1 início', (tester) async {
    await phone(
      tester,
      TitleScreen(
        save: Save(persist: false)
          ..tutorialDone = true
          ..unlocked = 3
          ..totalRepels = 11,
        useSensors: false,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await expectLater(
      find.byType(TitleScreen),
      matchesGoldenFile('1_inicio.png'),
    );
  });

  testWidgets('2 no escuro, longe', (tester) async {
    await game(tester, night(offset: -0.25, distance: 0.8), '2_no_escuro.png');
  });

  testWidgets('3 a lanterna em cima dele', (tester) async {
    await game(
      tester,
      night(offset: 0.05, distance: 0.6, lantern: true),
      '3_na_luz.png',
    );
  });

  testWidgets('4 invisível: só o chiado', (tester) async {
    await game(
      tester,
      night(offset: 0.1, distance: 0.6, cloaked: true),
      '4_chiado.png',
    );
  });

  testWidgets('5 correndo: hora do choque', (tester) async {
    await game(
      tester,
      night(offset: 0, distance: 0.15, mode: Mode.charging, lantern: true),
      '5_correndo.png',
    );
  });

  testWidgets('7 a Mariposa', (tester) async {
    final g = VigilGame(seed: 3, rules: Rules.forNight(4))
      ..lanternHeld = true
      ..heading = 0.4;
    g.angle = wrapAngle(g.heading + 1.5);
    g
      ..mothDistance = 0.45
      ..mothAngle = g.heading;
    await game(tester, g, '7_mariposa.png', nightNo: 4);
  });

  testWidgets('8 história', (tester) async {
    await phone(
      tester,
      StoryScreen(save: Save(persist: false), night: 4, useSensors: false),
    );
    await tester.tap(find.byType(StoryScreen));
    await tester.pump();
    await expectLater(find.byType(StoryScreen), matchesGoldenFile('8_historia.png'));
  });

  testWidgets('9 noites', (tester) async {
    final save = Save(persist: false)..unlocked = 3;
    save.recordOf(1)
      ..wins = 3
      ..deaths = 2
      ..bestTime = 131;
    save.recordOf(2)
      ..wins = 1
      ..deaths = 5
      ..bestTime = 204;
    await phone(tester, NightsScreen(save: save, useSensors: false));
    await expectLater(find.byType(NightsScreen), matchesGoldenFile('9_noites.png'));
  });

  testWidgets('6 susto', (tester) async {
    await phone(
      tester,
      const Scaffold(
        body: SizedBox.expand(child: CustomPaint(painter: _Scare())),
      ),
    );
    await expectLater(find.byType(Scaffold), matchesGoldenFile('6_susto.png'));
  });
}

class _Scare extends CustomPainter {
  const _Scare();
  @override
  void paint(Canvas canvas, Size size) => ScarePainter(0.6).paint(canvas, size);
  @override
  bool shouldRepaint(_Scare old) => false;
}

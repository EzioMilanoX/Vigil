import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/data/save.dart';
import 'package:vigil/game/achievements.dart';
import 'package:vigil/game/lullaby.dart';
import 'package:vigil/game/vigil_game.dart';
import 'package:vigil/ui/game_screen.dart';
import 'package:vigil/ui/title_screen.dart';

/// 72 por minuto: uma batida a cada 0,8333 s, 48 batidas, 40 s.
final metro = BeatMap.metronome();
final beat = 60 / 72;

/// Sem nada sorteado no meio (nem a música acelerando): dá para fazer conta.
const exact = Rules(
  tempoRise: 0,
  cloakPerSecond: 0,
  fakeStaticPerSecond: 0,
  fakeScarePerSecond: 0,
  faceFlashPerSecond: 0,
);

VigilGame song({int seed = 1, Rules rules = exact}) =>
    VigilGame(seed: seed, rules: rules, song: metro);

void main() {
  group('BeatMap', () {
    test('as batidas continuam através dos loops', () {
      expect(metro.perLoop, 48);
      expect(metro.length, closeTo(40, 1e-9));
      expect(metro.timeOf(0), 0);
      expect(metro.timeOf(48), closeTo(40, 1e-9));
      expect(metro.timeOf(-1), closeTo(-beat, 1e-9));
      expect(metro.indexAt(0), 0);
      expect(metro.indexAt(beat - 0.001), 0);
      expect(metro.indexAt(beat + 0.001), 1);
      expect(metro.indexAt(-0.001), -1);
      expect(metro.indexAt(40.001), 48);
      expect(metro.nearest(0.3), 0);
      expect(metro.nearest(0.5), 1);
      expect(metro.nearest(39.9), 48);
    });

    test('lê o JSON (objeto ou só a lista) e descarta o que passa do fim', () {
      final m = BeatMap.parse('{"length": 2.0, "beats": [1.5, 0.5, 2.5]}');
      expect(m.beats, [0.5, 1.5]);
      expect(m.length, 2.0);
      final l = BeatMap.parse('[0.0, 1.0, 2.0]');
      expect(l.length, closeTo(3, 1e-9));
      expect(() => BeatMap.parse('{"beats": []}'), throwsFormatException);
    });

    test('o JSON da música do jogo bate com a partitura', () {
      final m = BeatMap.parse(
        File('assets/musica/cancao.json').readAsStringSync(),
      );
      expect(m.perLoop, 48);
      expect(m.length, closeTo(40, 1e-6));
      for (var i = 0; i < 48; i++) {
        expect(m.beats[i], closeTo(i * beat, 1e-3));
      }
      expect(File('assets/musica/cancao.wav').existsSync(), isTrue);
      expect(File('assets/musica/cancao_torta.wav').existsSync(), isTrue);
    });
  });

  group('SongClock', () {
    test('devolve cada batida uma vez, quando passa', () {
      final c = SongClock(metro);
      expect(c.advance(0.01), [0]);
      expect(c.advance(0.5), isEmpty);
      expect(c.advance(0.33), [1]);
      expect(c.advance(2 * beat), [2, 3]);
      expect(c.beat, 3);
    });

    test('janela de ±80 ms em volta da batida', () {
      final c = SongClock(metro)..advance(0.079);
      expect(c.inWindow, isTrue);
      c.advance(0.002);
      expect(c.inWindow, isFalse);
      c.advance(beat - 0.081 - 0.079);
      expect(c.offset, closeTo(-0.079, 1e-9));
      expect(c.inWindow, isTrue);
      c.advance(-1); // dt negativo não anda
      c.time = beat - 0.081;
      expect(c.inWindow, isFalse);
    });

    test('a janela é em tempo real: com a música rápida, cabe mais música', () {
      final c = SongClock(metro)..tempo = 2;
      c.advance(0.075); // 0,15 s de música
      expect(c.time, closeTo(0.15, 1e-9));
      expect(c.offset, closeTo(0.075, 1e-9));
      expect(c.inWindow, isTrue);
      expect(c.period, closeTo(beat / 2, 1e-9));
    });

    test('sync: puxa devagar, pula de vez e entende o loop', () {
      final c = SongClock(metro)..advance(1); // passou a batida 1
      c.sync(1.1);
      expect(c.time, closeTo(1.05, 1e-9));
      expect(c.advance(0), isEmpty, reason: 'puxar não repete batida');
      c.sync(5);
      expect(c.time, closeTo(5, 1e-9));
      expect(c.advance(0), isEmpty, reason: 'pular não dispara as do meio');
      expect(c.beat, metro.indexAt(5));
      // No fim do loop, o áudio já voltou ao começo: é para frente.
      final d = SongClock(metro)..time = 39.9;
      d.sync(0.05);
      expect(d.time, closeTo(39.975, 1e-9));
    });
  });

  group('A canção no jogo', () {
    test('as regras: só rondar, mais espantos e o aviso antes da noite', () {
      final r = Rules.lullaby();
      expect(r.tactics, [Tactic.roam]);
      expect(r.repelsToWin, 4);
      expect(r.beatWindow, 0.08);
      expect(r.offbeatPerSecond, greaterThan(0));
      expect(Rules.novelty(songNight), contains('batida'));
    });

    test('ele só avança (e só gira) na batida', () {
      for (final seed in [1, 2, 3]) {
        final g = song(seed: seed, rules: Rules.lullaby())..heading = 3;
        var moves = 0;
        for (var i = 0; i < 60 * 40 && g.phase == Phase.playing; i++) {
          final b = g.song!.beat;
          final d = g.distance;
          final a = g.angle;
          g.update(1 / 60);
          if (g.distance < d - 1e-12 || g.angle != a) {
            moves++;
            expect(g.song!.beat, greaterThan(b), reason: 'seed $seed, $i');
          }
        }
        expect(moves, greaterThan(10));
      }
    });

    test('um passo (som) em cada batida enquanto ronda', () {
      final g = song()..heading = 3;
      g.update(0.01);
      expect(g.takeCues().map((c) => c.kind), [CueKind.step]);
      g.update(0.5);
      expect(g.takeCues(), isEmpty);
      g.update(0.4);
      expect(g.takeCues().map((c) => c.kind), contains(CueKind.step));
    });

    test('choque na batida, mirando, com ele correndo: espanta', () {
      final g = song()..update(0.001);
      g.startCharge();
      g.heading = g.angle;
      g.update(beat - 0.001 - 0.06); // 60 ms antes da batida 1
      expect(g.song!.offset, closeTo(-0.06, 1e-9));
      expect(g.shock(), isTrue);
      expect(g.repels, 1);
      expect(g.offBeatShocks, 0);
    });

    test('choque 60 ms depois da batida também pega; 100 ms não', () {
      final a = song()..update(0.001);
      a.startCharge();
      a.heading = a.angle;
      a.update(0.059);
      expect(a.shock(), isTrue);

      final b = song()..update(0.001);
      b.startCharge();
      b.heading = b.angle;
      b.update(0.099);
      expect(b.shock(), isFalse);
      expect(b.offBeatShocks, 1);
      expect(b.misses, 1);
    });

    test('fora do tempo é erro; no tempo sem mirar também', () {
      final g = song()..update(0.001);
      g.startCharge();
      g.heading = g.angle;
      g.update(0.4);
      expect(g.shock(), isFalse);
      expect(g.offBeatShocks, 1);
      // 10 ms depois da batida 3 (o choque já recarregou).
      g.update(3 * beat - 0.001 - 0.4 + 0.01);
      expect(g.shockReady, 0);
      expect(g.mode, Mode.charging);
      g.heading = g.angle + 1.5;
      expect(g.shock(), isFalse);
      expect(g.offBeatShocks, 1, reason: 'estava no tempo, só não mirou');
      expect(g.misses, 2);
    });

    test('rondando, mesmo no tempo, o choque não pega', () {
      final g = song()..update(0.001);
      g.heading = g.angle;
      expect(g.mode, Mode.roaming);
      expect(g.shock(), isFalse);
    });

    test('a corrida leva 4 batidas e, na última, a janela ainda salva', () {
      final g = song()..update(0.001);
      g.startCharge();
      g.distance = exact.chargeAt;
      g.heading = 2;
      for (var k = 1; k <= 3; k++) {
        g.update(beat);
        expect(g.distance, closeTo(exact.chargeAt * (1 - k / 4), 1e-9));
      }
      g.update(beat); // a 4ª batida: chegou em você
      expect(g.distance, 0);
      expect(g.phase, Phase.playing, reason: 'a janela ainda está aberta');
      g.heading = g.angle;
      g.update(0.05);
      expect(g.shock(), isTrue);
      expect(g.phase, Phase.playing);

      final h = song()..update(0.001);
      h.startCharge();
      h.distance = exact.chargeAt / 4;
      h.update(beat);
      expect(h.phase, Phase.playing);
      h.update(0.09);
      expect(h.phase, Phase.lost);
      expect(h.killer, Killer.mannequin);
    });

    test('a finta da corrida vem fora do tempo', () {
      const r = Rules(
        feintChance: 1,
        tempoRise: 0,
        cloakPerSecond: 0,
        fakeStaticPerSecond: 0,
        fakeScarePerSecond: 0,
        faceFlashPerSecond: 0,
      );
      final g = song(rules: r)..heading = 3;
      var feints = 0;
      for (var i = 0; i < 60 * 60 && g.phase == Phase.playing; i++) {
        final d = g.distance;
        g.update(1 / 60);
        for (final c in g.takeCues()) {
          if (c.kind != CueKind.feint) continue;
          feints++;
          expect(g.song!.inWindow, isFalse);
          expect(g.distance, greaterThan(d));
        }
      }
      expect(feints, greaterThan(0));
    });

    test('passos falsos só fora do tempo', () {
      const r = Rules(
        tempoRise: 0,
        offbeatPerSecond: 3,
        cloakPerSecond: 0,
        fakeStaticPerSecond: 0,
        fakeScarePerSecond: 0,
        faceFlashPerSecond: 0,
      );
      final g = song(rules: r)..heading = 3;
      var fakes = 0;
      for (var i = 0; i < 60 * 20 && g.phase == Phase.playing; i++) {
        g.update(1 / 60);
        for (final c in g.takeCues()) {
          if (c.kind != CueKind.offbeat) continue;
          fakes++;
          expect(g.song!.offset.abs(), greaterThan(0.2));
        }
      }
      expect(fakes, greaterThan(5));
    });

    test('ele volta (depois do choque) numa batida', () {
      final g = song()..update(0.001);
      g.startCharge();
      g.heading = g.angle;
      g.update(beat - 0.001);
      expect(g.shock(), isTrue);
      expect(g.mode, Mode.gone);
      while (g.mode == Mode.gone) {
        final b = g.song!.beat;
        g.update(1 / 60);
        if (g.mode != Mode.gone) expect(g.song!.beat, greaterThan(b));
      }
    });

    test('a música acelera e desafina com ele perto', () {
      final g = song(rules: Rules.lullaby());
      expect(g.songTempo, 1);
      expect(g.songDetune, 0);
      g.distance = 0.2;
      expect(g.songTempo, closeTo(1.24, 1e-9));
      expect(g.songDetune, greaterThan(0.9));
      g.update(1 / 60);
      expect(g.song!.tempo, closeTo(g.songTempo, 0.02));
      g.mode = Mode.gone;
      expect(g.songTempo, 1);
    });

    test('determinístico: mesmo seed e mesmos toques, mesma noite', () {
      List<Object> play() {
        final g = song(seed: 9, rules: Rules.lullaby());
        final log = <Object>[];
        for (var i = 0; i < 60 * 30 && g.phase == Phase.playing; i++) {
          g.heading = wrapAngle(i * 0.01);
          g.lanternHeld = i % 120 < 60;
          if (i % 47 == 0) g.shock();
          g.update(1 / 60);
          log.addAll(g.takeCues().map((c) => '${c.kind}${c.angle}'));
        }
        return [...log, g.distance, g.angle, g.repels, g.offBeatShocks];
      }

      expect(play(), play());
    });

    test(
      'vencer a canção não libera noite e guarda o recorde à parte',
      () async {
        final save = Save(persist: false)..unlocked = 5;
        await save.finish(
          const NightResult(night: songNight, won: true, time: 80, repels: 4),
        );
        expect(save.unlocked, 5);
        expect(save.recordOf(songNight).wins, 1);
        expect(save.recordOf(songNight).bestTime, 80);
      },
    );
  });

  group('Telas', () {
    Future<void> phone(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: home));
    }

    testWidgets('a canção fica trancada até vencer a noite 4', (tester) async {
      final save = Save(persist: false)..unlocked = 4;
      await phone(tester, NightsScreen(save: save, useSensors: false));
      expect(find.text('Extra: vença a noite 4 para liberar'), findsOneWidget);
      save.unlocked = 5;
      save.store();
      await tester.pump();
      await tester.tap(find.byKey(const Key('cancao')));
      await tester.pumpAndSettle();
      expect(find.text('EXTRA · A CANÇÃO'), findsOneWidget);
      await tester.tap(find.byType(StoryScreen));
      await tester.pump();
      expect(find.textContaining('caixinha de música'), findsOneWidget);
      expect(find.text('Dar corda na caixinha'), findsOneWidget);
    });

    testWidgets('na noite da canção, o HUD e o pulso na borda (opcional)', (
      tester,
    ) async {
      final save = Save(persist: false);
      await phone(
        tester,
        GameScreen(
          save: save,
          night: songNight,
          song: metro,
          seed: 1,
          useSensors: false,
        ),
      );
      await tester.pump(const Duration(milliseconds: 33));
      expect(find.text('A canção   '), findsOneWidget);
      expect(find.byKey(const Key('pulso')), findsNothing);
      save.settings.beatPulse = true;
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 33));
      }
      expect(find.byKey(const Key('pulso')), findsOneWidget);
    });

    testWidgets('choque fora do tempo avisa na tela', (tester) async {
      await phone(
        tester,
        GameScreen(
          save: Save(persist: false),
          night: songNight,
          song: metro,
          seed: 1,
          useSensors: false,
        ),
      );
      // ~0,4 s depois da primeira batida: longe de qualquer uma.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 33));
      }
      await tester.tap(find.byKey(const Key('choque')));
      await tester.pump();
      expect(find.text('fora do tempo'), findsOneWidget);
    });

    testWidgets('acessibilidade: pulso e atraso nas configurações', (
      tester,
    ) async {
      final save = Save(persist: false);
      await phone(tester, SettingsScreen(save: save));
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pulso')));
      await tester.pump();
      expect(save.settings.beatPulse, isTrue);
      final lido = Settings()
        ..load({...save.settings.toJson(), 'songDelayMs': 180});
      expect(lido.beatPulse, isTrue);
      expect(lido.songDelayMs, 180);
    });
  });
}

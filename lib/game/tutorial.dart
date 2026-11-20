import 'dart:math';

import 'vigil_game.dart';

/// Os passos do tutorial jogável.
enum TutorialStep { find, light, cloaked, shock, done }

/// Conduz uma noite de treino: monta cada situação no jogo e espera o
/// jogador fazer a coisa certa antes de seguir. O jogo fica em modo
/// [VigilGame.scripted]: ele não anda, não some e não mata sozinho.
class TutorialCoach {
  TutorialCoach(this.game) {
    game.scripted = true;
    _setup();
  }

  final VigilGame game;
  TutorialStep step = TutorialStep.find;
  double _hold = 0;
  double _retryIn = 0;

  /// Para que lado virar, enquanto ele está fora da tela (no jogo de verdade
  /// quem diz isso é o som; no treino, a tela ajuda).
  String get _side {
    final o = game.offset;
    if (o.abs() < 0.6) return '';
    return o > 0 ? '\nEle está à sua direita →' : '\n← Ele está à sua esquerda';
  }

  /// O que mostrar na tela agora.
  String get message => switch (step) {
    TutorialStep.find =>
      'Vire o corpo com o celular (ou arraste) até achar o manequim.$_side',
    TutorialStep.light => 'Segure a lanterna em cima dele.',
    TutorialStep.cloaked =>
      'Ele sumiu. Quando a tela chiar, ele está ali: ache e ilumine.$_side',
    TutorialStep.shock =>
      game.mode == Mode.charging && game.distance <= game.rules.shockWindow
          ? 'AGORA!'
          : _retryIn > 0
          ? 'Cedo demais. De novo...'
          : 'Ele vai correr. Espere chegar bem perto e dê o choque.',
    TutorialStep.done =>
      'Pronto. Na noite de verdade ele não espera você ficar pronto.',
  };

  void update(double dt) {
    final g = game;
    switch (step) {
      case TutorialStep.find:
        if (g.offset.abs() < 0.25) _next();
      case TutorialStep.light:
        _hold = g.lit && g.inBeam ? _hold + dt : 0;
        if (_hold > 0.8) _next();
      case TutorialStep.cloaked:
        _hold = g.revealed ? _hold + dt : 0;
        if (_hold > 0.6) _next();
      case TutorialStep.shock:
        if (g.repels >= 1) {
          _next();
        } else if (g.mode == Mode.roaming) {
          // Errou (ou ele chegou): recomeça a corrida daqui a pouco.
          if (_retryIn <= 0) _retryIn = 1.5;
          _retryIn -= dt;
          if (_retryIn <= 0) {
            g
              ..distance = g.rules.chargeAt
              ..angle = g.heading;
            g.startCharge();
          }
        }
      case TutorialStep.done:
        break;
    }
  }

  void _next() {
    step = TutorialStep.values[step.index + 1];
    _hold = 0;
    _setup();
  }

  void _setup() {
    final g = game;
    switch (step) {
      case TutorialStep.find:
        g
          ..mode = Mode.roaming
          ..cloaked = false
          ..distance = 0.75
          ..angle = wrapAngle(g.heading + 1.6);
      case TutorialStep.light:
        break;
      case TutorialStep.cloaked:
        g
          ..cloaked = true
          ..distance = 0.65
          ..angle = wrapAngle(g.heading - pi * 0.55);
      case TutorialStep.shock:
        g
          ..cloaked = false
          ..distance = g.rules.chargeAt
          ..angle = g.heading
          ..shockReady = 0;
        g.startCharge();
      case TutorialStep.done:
        g.mode = Mode.gone;
    }
  }
}

import 'dart:math';

import 'vigil_game.dart';

/// Como terminou uma aparição do Manequim, do ponto de vista do jogador.
enum Outcome {
  /// Espantou sem errar e já estava mirando quando ele correu.
  easy,

  /// Espantou, sem sufoco nem folga.
  normal,

  /// Espantou por pouco: errou o choque ou virou tarde.
  close,

  /// Ele pegou você.
  caught,
}

/// O diretor do medo: observa como você joga ao longo da noite (para onde
/// olha, quanto segura a lanterna, se acha o chiado rápido, quais táticas te
/// apertam) e usa isso para escolher a próxima tática, o lado de onde ele vem
/// e a dose dos sustos falsos, com respiros depois dos sustos fortes.
///
/// Dart puro e sem sorteio próprio: quem sorteia é o jogo (o `roll` de
/// [nextTactic] e [side] vem do `Random` dele), então tudo continua
/// determinístico pelo `seed`. É justo de propósito: os pesos têm teto e piso
/// (toda tática possível continua possível), o lado esquecido é preferido,
/// não garantido, e nada mexe na velocidade nem na janela do choque.
class FearDirector {
  /// Fatias do quarto para medir para onde você olha (15° cada).
  static const sectors = 24;
  static const _sectorWidth = tau / sectors;

  /// Em quantos segundos o que ele viu de você vai perdendo o peso.
  static const memorySeconds = 60.0;

  /// Tempo olhando para cada fatia do quarto (com a luz acesa conta dobrado).
  final List<double> _watch = List.filled(sectors, 0);

  /// O quanto cada tática apertou você (0 = espanta fácil, 1 = pegou).
  final Map<Tactic, double> _pressure = {};

  /// Fração do tempo com a lanterna acesa (média que esquece devagar).
  double lanternShare = 0.4;

  /// Segundos, em média, até achar o chiado quando ele some.
  double reaction = 1.5;

  /// Respiro: enquanto durar, sem sustos falsos nem rosto no feixe.
  double calm = 0;

  /// Segundos desde o último susto (a tensão sobe com o tempo).
  double sinceScare = 0;

  /// Como terminou a última aparição (para o respiro depois do sufoco).
  Outcome? lastOutcome;

  /// Uma noite nova (ou de novo, depois de morrer): o que ele aprendeu de
  /// você fica, a tensão volta ao começo.
  void startNight() {
    calm = 0;
    sinceScare = 0;
    lastOutcome = null;
  }

  /// A cada quadro: para onde você olha e se a luz está acesa.
  void look(double dt, {required double heading, required bool lit}) {
    if (dt <= 0) return;
    calm = max(0, calm - dt);
    sinceScare += dt;
    final keep = max(0.0, 1 - dt / memorySeconds);
    for (var i = 0; i < sectors; i++) {
      _watch[i] *= keep;
    }
    _watch[_sectorOf(heading)] += dt * (lit ? 2 : 1);
    lanternShare += ((lit ? 1 : 0) - lanternShare) * min(1, dt / memorySeconds);
  }

  /// Ele sumiu e você levou [seconds] para achar o chiado (ou não achou:
  /// [found] falso pesa como demora).
  void staticFound(double seconds, {bool found = true}) {
    final s = found ? seconds : seconds + 1.5;
    reaction += (s.clamp(0.0, 6.0) - reaction) * 0.35;
  }

  /// Como terminou uma aparição da tática [t].
  void result(Tactic t, Outcome o) {
    final score = switch (o) {
      Outcome.easy => 0.0,
      Outcome.normal => 0.35,
      Outcome.close => 0.7,
      Outcome.caught => 1.0,
    };
    _pressure[t] = pressureOf(t) * 0.55 + score * 0.45;
    lastOutcome = o;
  }

  /// O quanto a tática [t] costuma apertar (sem dados: no meio).
  double pressureOf(Tactic t) => _pressure[t] ?? 0.35;

  /// Um susto aconteceu: os fortes pedem um respiro curto depois.
  void scared(CueKind kind) {
    final strength = switch (kind) {
      CueKind.hit => 1.0,
      CueKind.breath => 0.9,
      CueKind.blackout => 0.8,
      CueKind.feint => 0.7,
      CueKind.face => 0.6,
      CueKind.knock || CueKind.shadow => 0.3,
      _ => 0.0,
    };
    if (strength <= 0) return;
    sinceScare = 0;
    if (strength >= 0.6) calm = max(calm, 2 + 3 * strength);
  }

  /// Multiplica a chance dos sustos falsos: zero no respiro, depois sobe
  /// devagar enquanto nada acontece (até 1,5×).
  double get scareRate =>
      calm > 0 ? 0 : (0.5 + sinceScare / 20).clamp(0.5, 1.5);

  /// O rosto no feixe: quem vive de lanterna acesa vê mais.
  double get faceRate => scareRate * (0.6 + 0.8 * lanternShare);

  /// Segundos a mais de sumiço depois de espantá-lo: respira depois do sufoco.
  double breatherAfter(Outcome o) => switch (o) {
    Outcome.close => 1.5,
    Outcome.normal => 0.5,
    _ => 0,
  };

  /// Quanto você se fixa num lado só (0 = olha tudo, 1 = um lugar só).
  double get focus {
    final total = _watch.fold(0.0, (a, b) => a + b);
    if (total < 1e-6) return 0;
    var h = 0.0;
    for (final w in _watch) {
      if (w <= 0) continue;
      final p = w / total;
      h -= p * log(p);
    }
    return (1 - h / log(sectors)).clamp(0.0, 1.0);
  }

  /// O quanto a tática [t] combina com o seu jeito de jogar (0 a 0,6).
  double affinity(Tactic t) => switch (t) {
    // Rondar some e aparece: quem demora no chiado sofre.
    Tactic.roam => ((reaction - 1.5) / 3).clamp(0.0, 0.4),
    // Estátua anda no escuro: quem economiza lanterna sofre.
    Tactic.statue => ((0.35 - lanternShare) * 1.5).clamp(0.0, 0.5),
    // Emboscada vem por trás e sem chiado: quem só olha um lado sofre, e
    // quem acha o chiado rápido perde a vantagem.
    Tactic.ambush =>
      (max(0.0, focus - 0.3) + max(0.0, (1.2 - reaction) * 0.3)).clamp(
        0.0,
        0.6,
      ),
    // Apagão tira a luz: pior para quem vive dela e para quem demora no chiado.
    Tactic.blackout =>
      (max(0.0, (lanternShare - 0.45) * 1.2) + max(0.0, (reaction - 1.5) / 4))
          .clamp(0.0, 0.6),
  };

  /// O peso da tática [t] no sorteio: entre 0,5 e 3 (nenhuma some, nenhuma
  /// domina mais que 6 para 1).
  double weight(Tactic t) =>
      (0.6 + 2 * pressureOf(t) + affinity(t)).clamp(0.5, 3.0);

  /// A próxima tática entre [options]. Sem [last] (a primeira da noite), é a
  /// primeira da lista (rondar); senão, nunca repete [last]. [roll] em [0, 1).
  Tactic nextTactic(
    List<Tactic> options, {
    Tactic? last,
    required double roll,
  }) {
    if (last == null || options.length < 2) return options.first;
    final pool = [
      for (final o in options)
        if (o != last) o,
    ];
    final weights = [for (final t in pool) weight(t)];
    final total = weights.fold(0.0, (a, b) => a + b);
    var r = roll.clamp(0.0, 1.0) * total;
    for (var i = 0; i < pool.length; i++) {
      r -= weights[i];
      if (r < 0) return pool[i];
    }
    return pool.last;
  }

  /// O quanto você olhou para a faixa de um lado ([sign] +1 = direita),
  /// entre 1,2 e 2,8 rad do seu olhar: de onde ele chega.
  double watchedOn(double heading, int sign) {
    var sum = 0.0;
    for (var i = 0; i < sectors; i++) {
      final d = angleDiff((i + 0.5) * _sectorWidth, heading) * sign;
      if (d >= 1.2 - _sectorWidth / 2 && d <= 2.8 + _sectorWidth / 2) {
        sum += _watch[i];
      }
    }
    return sum;
  }

  /// A chance de ele vir pelo lado que você mais esquece (0,5 sem dados,
  /// até 0,85 quando a diferença é grande).
  double neglectedChance(double heading) {
    final r = watchedOn(heading, 1);
    final l = watchedOn(heading, -1);
    if (r + l < 3) return 0.5;
    return 0.5 + 0.35 * (r - l).abs() / (r + l);
  }

  /// De que lado ele chega (+1 = direita, -1 = esquerda). [roll] em [0, 1).
  int side(double heading, double roll) {
    final neglected = watchedOn(heading, 1) <= watchedOn(heading, -1) ? 1 : -1;
    return roll < neglectedChance(heading) ? neglected : -neglected;
  }

  /// O mundo girou [delta] (recentralizar): o que ele lembra gira junto.
  void rotate(double delta) {
    final shift = delta / _sectorWidth;
    final old = List<double>.of(_watch);
    for (var j = 0; j < sectors; j++) {
      final x = j - shift;
      final i0 = x.floor();
      final f = x - i0;
      _watch[j] = (1 - f) * old[i0 % sectors] + f * old[(i0 + 1) % sectors];
    }
  }

  int _sectorOf(double angle) =>
      (wrapAngle(angle) / _sectorWidth).floor() % sectors;
}

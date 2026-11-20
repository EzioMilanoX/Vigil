import 'dart:math';

/// Uma volta inteira, em radianos.
const tau = 2 * pi;

/// Ângulo em [0, 2π).
double wrapAngle(double a) => ((a % tau) + tau) % tau;

/// A menor diferença de [a] para [b], em (-π, π]. Positivo = [a] está à direita.
double angleDiff(double a, double b) {
  var d = wrapAngle(a - b);
  if (d > pi) d -= tau;
  return d;
}

enum Phase { playing, won, lost }

/// O que o Manequim está fazendo.
enum Mode {
  /// Anda em volta de você, chegando perto aos poucos.
  roaming,

  /// Correndo na sua direção: é a hora do choque.
  charging,

  /// Levou o choque e sumiu; volta daqui a pouco, de outro lado.
  gone,
}

enum CueKind {
  /// Ele apareceu de novo, longe.
  arrive,

  /// Um passo.
  step,

  /// Começou a correr.
  charge,

  /// O choque pegou.
  hit,

  /// O choque saiu no vazio.
  miss,
}

/// Um aviso de som vindo de um lado. [pan] vai de -1 (esquerda) a 1 (direita).
class Cue {
  const Cue(this.kind, this.pan, {this.behind = false, this.near = false});
  final CueKind kind;
  final double pan;
  final bool behind;
  final bool near;
}

/// As regras de uma noite. Tempo em segundos, ângulos em radianos, distância
/// de 1 (longe) a 0 (em cima de você).
class Rules {
  const Rules({
    this.repelsToWin = 3,
    this.beamHalfWidth = 0.32,
    this.aimHalfWidth = 0.38,
    this.batterySeconds = 40,
    this.rechargeSeconds = 90,
    this.lowBattery = 0.15,
    this.approachPerSecond = 0.03,
    this.orbitSpeed = 0.45,
    this.cloakPerSecond = 0.1,
    this.cloakSeconds = 5,
    this.chargeAt = 0.4,
    this.chargeSeconds = 1.8,
    this.shockWindow = 0.2,
    this.shockCooldown = 1.4,
    this.goneSeconds = 4,
    this.fakeStaticPerSecond = 0.06,
  });

  /// Quantas vezes é preciso espantá-lo para amanhecer.
  final int repelsToWin;

  /// Metade da largura do feixe da lanterna e da mira do choque.
  final double beamHalfWidth;
  final double aimHalfWidth;

  /// Segurando a lanterna, a pilha dura isso; apagada, recarrega em [rechargeSeconds].
  final double batterySeconds;
  final double rechargeSeconds;
  final double lowBattery;

  final double approachPerSecond;
  final double orbitSpeed;

  /// Chance por segundo de ele ficar invisível, e por quanto tempo fica.
  final double cloakPerSecond;
  final double cloakSeconds;

  /// A essa distância ele para de rodear e corre; leva [chargeSeconds] para chegar.
  final double chargeAt;
  final double chargeSeconds;

  /// O choque só pega quando ele já está mais perto que isso.
  final double shockWindow;
  final double shockCooldown;
  final double goneSeconds;

  /// A lembrança mente: chiado de um lado onde ele não está.
  final double fakeStaticPerSecond;

  /// A noite [night] (1, 2, ...): mais vezes para espantar, ele mais rápido e
  /// mais tempo invisível, a pilha mais curta.
  factory Rules.forNight(int night) {
    final n = max(0, night - 1);
    return Rules(
      repelsToWin: 3 + n,
      approachPerSecond: 0.03 * (1 + 0.15 * n),
      orbitSpeed: 0.45 + 0.08 * n,
      cloakPerSecond: 0.1 + 0.04 * n,
      chargeSeconds: max(1.0, 1.8 - 0.15 * n),
      batterySeconds: max(22, 40 - 3.0 * n),
    );
  }
}

/// Uma noite de V.I.G.I.L.: você parado, o Manequim andando em volta. Ele
/// some (só o chiado denuncia), a lanterna o revela, e quando ele corre você
/// tem um instante para acertar o choque. Determinístico dado o [seed].
class VigilGame {
  VigilGame({int seed = 0, this.rules = const Rules()}) : _rng = Random(seed) {
    _arrive(first: true);
  }

  final Rules rules;
  final Random _rng;

  /// Para onde você (e o celular) está virado.
  double heading = 0;

  /// A lanterna só fica acesa enquanto você segura.
  bool lanternHeld = false;
  double battery = 1;
  double time = 0;
  Phase phase = Phase.playing;
  int repels = 0;

  /// O Manequim.
  double angle = 0;
  double distance = 1;
  Mode mode = Mode.roaming;
  bool cloaked = false;
  double _cloakLeft = 0;
  double _orbitDir = 1;
  double _goneLeft = 0;

  double shockReady = 0;

  /// O chiado falso: um ângulo e quanto tempo ainda dura.
  double? fakeStaticAngle;
  double _fakeLeft = 0;

  /// Pisca quando a pilha está fraca: neste quadro a luz falhou.
  bool flickerOff = false;

  final List<Cue> _cues = [];

  bool get lit => lanternHeld && battery > 0 && !flickerOff;
  bool get present => mode != Mode.gone;

  /// O quanto ele está fora do centro da tela, em radianos.
  double get offset => angleDiff(angle, heading);
  bool get inBeam => offset.abs() <= rules.beamHalfWidth;

  /// Invisível, mas a luz em cima dele o mostra.
  bool get revealed => cloaked && lit && inBeam;

  /// Dá para vê-lo (com ou sem luz)?
  bool get visible => present && (!cloaked || revealed);

  /// O chiado na tela e no som, de 0 a 1: forte quando você olha para onde
  /// ele está invisível (ou para onde a lembrança mente).
  double get staticLevel {
    var s = 0.0;
    if (present && cloaked && !revealed) {
      s = max(0, 1 - offset.abs() / 0.9) * (1.2 - 0.5 * distance);
    }
    if (fakeStaticAngle case final f?) {
      s = max(s, 0.6 * max(0, 1 - angleDiff(f, heading).abs() / 0.6));
    }
    return s.clamp(0.0, 1.0);
  }

  List<Cue> takeCues() {
    final out = List<Cue>.of(_cues);
    _cues.clear();
    return out;
  }

  /// Dispara o choque para onde você está olhando. Devolve se pegou.
  bool shock() {
    if (phase != Phase.playing || shockReady > 0) return false;
    shockReady = rules.shockCooldown;
    final hit =
        mode == Mode.charging &&
        distance <= rules.shockWindow &&
        offset.abs() <= rules.aimHalfWidth;
    if (!hit) {
      _cue(CueKind.miss);
      return false;
    }
    _cue(CueKind.hit, near: true);
    repels++;
    mode = Mode.gone;
    cloaked = false;
    _goneLeft = rules.goneSeconds;
    if (repels >= rules.repelsToWin) phase = Phase.won;
    return true;
  }

  void update(double dt) {
    if (phase != Phase.playing || dt <= 0) return;
    time += dt;
    shockReady = max(0, shockReady - dt);

    if (lanternHeld && battery > 0) {
      battery = max(0, battery - dt / rules.batterySeconds);
    } else if (!lanternHeld) {
      battery = min(1, battery + dt / rules.rechargeSeconds);
    }
    flickerOff =
        lanternHeld &&
        battery > 0 &&
        battery < rules.lowBattery &&
        _rng.nextDouble() < 0.3 * (1 - battery / rules.lowBattery);

    _fakeStatic(dt);

    switch (mode) {
      case Mode.gone:
        _goneLeft -= dt;
        if (_goneLeft <= 0) _arrive();
      case Mode.roaming:
        _roam(dt);
      case Mode.charging:
        distance -= rules.chargeAt / rules.chargeSeconds * dt;
        if (distance <= 0) {
          distance = 0;
          phase = Phase.lost;
        }
    }
  }

  void _roam(double dt) {
    if (_rng.nextDouble() < 0.25 * dt) _orbitDir = -_orbitDir;
    // Olhar para ele (visível) o faz hesitar: anda mais devagar em volta.
    final watched = visible && offset.abs() < 0.6;
    angle = wrapAngle(
      angle + _orbitDir * rules.orbitSpeed * (watched ? 0.4 : 1) * dt,
    );

    final before = distance;
    distance -= rules.approachPerSecond * dt;
    for (final step in const [0.85, 0.7, 0.55]) {
      if (before > step && distance <= step) _cue(CueKind.step);
    }

    if (cloaked) {
      _cloakLeft -= dt;
      if (_cloakLeft <= 0) cloaked = false;
    } else if (_rng.nextDouble() < rules.cloakPerSecond * dt) {
      cloaked = true;
      _cloakLeft = rules.cloakSeconds * (0.6 + 0.8 * _rng.nextDouble());
    }

    if (distance <= rules.chargeAt) {
      mode = Mode.charging;
      _cue(CueKind.charge, near: true);
    }
  }

  void _fakeStatic(double dt) {
    if (fakeStaticAngle != null) {
      _fakeLeft -= dt;
      if (_fakeLeft <= 0) fakeStaticAngle = null;
    } else if (_rng.nextDouble() < rules.fakeStaticPerSecond * dt) {
      // Sempre longe de onde ele está de verdade.
      fakeStaticAngle = wrapAngle(angle + pi * (0.6 + 0.8 * _rng.nextDouble()));
      _fakeLeft = 2 + 2 * _rng.nextDouble();
    }
  }

  void _arrive({bool first = false}) {
    mode = Mode.roaming;
    distance = 1;
    cloaked = false;
    _orbitDir = _rng.nextBool() ? 1 : -1;
    // Nunca aparece na sua frente: de lado ou atrás.
    angle = wrapAngle(
      heading + (_rng.nextBool() ? 1 : -1) * (1.2 + 1.6 * _rng.nextDouble()),
    );
    if (!first) _cue(CueKind.arrive);
  }

  void _cue(CueKind kind, {bool near = false}) {
    final d = offset;
    _cues.add(Cue(kind, sin(d), behind: d.abs() > pi / 2, near: near));
  }
}

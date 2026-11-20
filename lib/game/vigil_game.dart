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

/// Quem pegou você.
enum Killer { mannequin, moth }

/// O que o Manequim está fazendo.
enum Mode {
  /// Anda em volta de você, chegando perto aos poucos.
  roaming,

  /// Correndo na sua direção: é a hora do choque (ou uma finta).
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

  /// Era finta: parou no meio do caminho.
  feint,

  /// O choque pegou.
  hit,

  /// O choque saiu no vazio.
  miss,

  /// Susto falso: batidas em algum lugar do quarto.
  knock,

  /// Susto falso: um vulto passa pela tela.
  shadow,

  /// A Mariposa está perto (o zumbido aumentou).
  buzz,
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
    this.aimHalfWidth = 0.36,
    this.batterySeconds = 36,
    this.rechargeSeconds = 80,
    this.lowBattery = 0.15,
    this.approachPerSecond = 0.042,
    this.orbitSpeed = 0.5,
    this.cloakPerSecond = 0.13,
    this.cloakSeconds = 5,
    this.chargeAt = 0.4,
    this.chargeSeconds = 1.5,
    this.shockWindow = 0.18,
    this.shockCooldown = 1.4,
    this.goneSeconds = 3.5,
    this.feintChance = 0,
    this.cloakedCharge = false,
    this.moth = false,
    this.mothApproachPerSecond = 0.07,
    this.mothRetreatPerSecond = 0.22,
    this.fakeStaticPerSecond = 0.06,
    this.fakeScarePerSecond = 0.035,
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

  /// Chance de uma corrida ser finta: ele para no meio e volta a rodear.
  final double feintChance;

  /// Se invisível, continua invisível correndo (só o chiado e a luz o acham).
  final bool cloakedCharge;

  /// A Mariposa: só avança enquanto a lanterna está acesa.
  final bool moth;
  final double mothApproachPerSecond;
  final double mothRetreatPerSecond;

  /// A lembrança mente: chiado de um lado onde ele não está.
  final double fakeStaticPerSecond;

  /// Batidas e vultos que não são nada.
  final double fakeScarePerSecond;

  /// A noite [night] (1, 2, ...). A 2 traz as fintas; a 3, a corrida
  /// invisível; a 4, a Mariposa. Cada uma pede mais espantos, mais rápido.
  factory Rules.forNight(int night) {
    final n = max(0, night - 1);
    return Rules(
      repelsToWin: 3 + n,
      approachPerSecond: 0.042 * (1 + 0.12 * n),
      orbitSpeed: 0.5 + 0.08 * n,
      cloakPerSecond: 0.13 + 0.04 * n,
      chargeSeconds: max(0.95, 1.5 - 0.12 * n),
      batterySeconds: max(20, 36 - 3.0 * n),
      feintChance: night >= 2 ? min(0.4, 0.2 + 0.05 * n) : 0,
      cloakedCharge: night >= 3,
      moth: night >= 4,
      fakeScarePerSecond: 0.035 + 0.01 * n,
    );
  }

  /// O que a noite traz de novo, para a tela de antes dela.
  static String? novelty(int night) => switch (night) {
    2 => 'Ele aprendeu a fingir: nem toda corrida chega até você.',
    3 => 'Agora ele pode correr invisível. Siga o chiado.',
    4 => 'Tem outra coisa no quarto. Ela vem atrás da luz.',
    _ => null,
  };
}

/// Uma noite de V.I.G.I.L.: você parado, o Manequim andando em volta. Ele
/// some (só o chiado denuncia), a lanterna o revela, e quando ele corre você
/// tem um instante para acertar o choque. Determinístico dado o [seed].
class VigilGame {
  VigilGame({int seed = 0, this.rules = const Rules()}) : _rng = Random(seed) {
    _arrive(first: true);
    mothAngle = wrapAngle(angle + pi);
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
  Killer? killer;
  int repels = 0;

  /// No tutorial: ele não anda, não some e não corre sozinho, e não mata.
  bool scripted = false;

  /// O Manequim.
  double angle = 0;
  double distance = 1;
  Mode mode = Mode.roaming;
  bool cloaked = false;
  double _cloakLeft = 0;
  double _orbitDir = 1;
  double _goneLeft = 0;
  bool _feint = false;

  /// A Mariposa (noite 4+): 1 = longe, 0 = em você.
  double mothDistance = 1;
  double mothAngle = 0;

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

  double get mothOffset => angleDiff(mothAngle, heading);
  bool get mothActive => rules.moth && mothDistance < 1;

  /// A Mariposa só aparece na luz.
  bool get mothVisible =>
      mothActive && lit && mothOffset.abs() <= rules.beamHalfWidth * 1.4;

  /// O zumbido dela, de 0 a 1.
  double get mothLevel => rules.moth ? (1 - mothDistance).clamp(0.0, 1.0) : 0;

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
    if (repels >= rules.repelsToWin && !scripted) phase = Phase.won;
    return true;
  }

  /// Faz ele correr agora (o tutorial usa; o jogo decide sozinho).
  void startCharge({bool feint = false}) {
    mode = Mode.charging;
    _feint = feint;
    if (!rules.cloakedCharge) cloaked = false;
    _cue(CueKind.charge, near: true);
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
    // A pilha falha mais justo quando ele corre.
    final failing =
        (battery < rules.lowBattery
            ? 0.3 * (1 - battery / rules.lowBattery)
            : 0.0) +
        (mode == Mode.charging && battery < 0.5 ? 0.12 : 0.0);
    flickerOff = lanternHeld && battery > 0 && _rng.nextDouble() < failing;

    if (!scripted) {
      _fakeStatic(dt);
      _fakeScares(dt);
    }
    _moth(dt);

    switch (mode) {
      case Mode.gone:
        _goneLeft -= dt;
        if (_goneLeft <= 0) _arrive();
      case Mode.roaming:
        _roam(dt);
      case Mode.charging:
        distance -= rules.chargeAt / rules.chargeSeconds * dt;
        if (_feint && distance <= rules.chargeAt * 0.55) {
          // Finta: para no meio, recua um pouco e volta a rodear.
          mode = Mode.roaming;
          distance = rules.chargeAt + 0.12;
          _feint = false;
          _cue(CueKind.feint);
        } else if (distance <= 0) {
          if (scripted) {
            mode = Mode.roaming;
            distance = rules.chargeAt + 0.1;
            _cue(CueKind.miss);
          } else {
            distance = 0;
            phase = Phase.lost;
            killer = Killer.mannequin;
          }
        }
    }
  }

  void _roam(double dt) {
    if (scripted) return;
    if (_rng.nextDouble() < 0.25 * dt) _orbitDir = -_orbitDir;
    // Olhar para ele (visível) o faz hesitar; sem ninguém olhando, ele anda mais.
    final watched = visible && offset.abs() < 0.6;
    angle = wrapAngle(
      angle + _orbitDir * rules.orbitSpeed * (watched ? 0.35 : 1.15) * dt,
    );

    final before = distance;
    distance -= rules.approachPerSecond * (watched ? 0.7 : 1.15) * dt;
    for (final step in const [0.9, 0.78, 0.66, 0.54]) {
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
      startCharge(feint: _rng.nextDouble() < rules.feintChance);
    }
  }

  void _moth(double dt) {
    if (!rules.moth) return;
    mothAngle = wrapAngle(mothAngle + 0.12 * dt);
    final before = mothDistance;
    if (lit) {
      mothDistance = max(0, mothDistance - rules.mothApproachPerSecond * dt);
    } else {
      mothDistance = min(1, mothDistance + rules.mothRetreatPerSecond * dt);
    }
    for (final step in const [0.6, 0.3]) {
      if (before > step && mothDistance <= step) {
        _cueAt(CueKind.buzz, mothOffset, near: step < 0.5);
      }
    }
    if (mothDistance <= 0 && !scripted) {
      phase = Phase.lost;
      killer = Killer.moth;
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

  void _fakeScares(double dt) {
    if (_rng.nextDouble() >= rules.fakeScarePerSecond * dt) return;
    final kind = _rng.nextBool() ? CueKind.knock : CueKind.shadow;
    _cueAt(kind, (_rng.nextDouble() * 2 - 1) * pi);
  }

  void _arrive({bool first = false}) {
    mode = Mode.roaming;
    distance = 1;
    cloaked = false;
    _feint = false;
    _orbitDir = _rng.nextBool() ? 1 : -1;
    // Nunca aparece na sua frente: de lado ou atrás.
    angle = wrapAngle(
      heading + (_rng.nextBool() ? 1 : -1) * (1.2 + 1.6 * _rng.nextDouble()),
    );
    if (!first) _cue(CueKind.arrive);
  }

  void _cue(CueKind kind, {bool near = false}) =>
      _cueAt(kind, offset, near: near);

  void _cueAt(CueKind kind, double d, {bool near = false}) {
    _cues.add(Cue(kind, sin(d), behind: d.abs() > pi / 2, near: near));
  }
}

import 'dart:math';

import 'director.dart';
import 'lullaby.dart';

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

/// Como ele vem desta vez. Cada aparição sorteia uma, nunca a mesma duas
/// vezes seguidas (a primeira da noite é sempre [roam]).
enum Tactic {
  /// Rodeia e chega perto aos poucos (às vezes invisível), e corre.
  roam,

  /// Estátua: com a luz em cima dele, congela; no escuro, anda depressa.
  statue,

  /// Emboscada: some sem barulho e reaparece atrás de você; só uma
  /// respiração avisa antes de ele correr.
  ambush,

  /// Apagão: quando ele chega perto, a lanterna morre até ele ir embora;
  /// ele corre no escuro e só o som e o chiado o acham.
  blackout,
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

  /// Emboscada: uma respiração bem atrás de você.
  breath,

  /// Apagão: a lanterna morreu.
  blackout,

  /// Susto falso: o rosto dele pisca no feixe.
  face,

  /// A canção: um passo fora do tempo, que não é ele andando (finta).
  offbeat,
}

/// Um aviso de som vindo de um lado. [pan] vai de -1 (esquerda) a 1 (direita).
class Cue {
  const Cue(
    this.kind,
    this.pan, {
    this.behind = false,
    this.near = false,
    this.angle = 0,
  });
  final CueKind kind;
  final double pan;
  final bool behind;
  final bool near;

  /// De onde vem, em relação a para onde você olha (0 = frente, + = direita).
  final double angle;
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
    this.tactics = const [Tactic.roam],
    this.faceFlashPerSecond = 0,
    this.ambushLurkSeconds = 3,
    this.ambushWarnSeconds = 0.8,
    this.ambushChargeFactor = 1.35,
    this.blackoutAt = 0.62,
    this.beatStep = 0.045,
    this.beatOrbit = 0.22,
    this.chargeBeats = 4,
    this.beatWindow = 0.08,
    this.offbeatPerSecond = 0,
    this.tempoRise = 0.3,
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

  /// As táticas que ele pode usar nesta noite.
  final List<Tactic> tactics;

  /// Chance por segundo (com a luz acesa) de o rosto piscar no feixe.
  final double faceFlashPerSecond;

  /// Emboscada: quanto tempo some (mais até o dobro), quanto a respiração
  /// avisa antes, e o quanto a corrida é mais lenta (dá tempo de virar).
  final double ambushLurkSeconds;
  final double ambushWarnSeconds;
  final double ambushChargeFactor;

  /// Apagão: a essa distância a luz morre.
  final double blackoutAt;

  /// A canção: o quanto ele chega perto e gira em volta a cada batida.
  final double beatStep;
  final double beatOrbit;

  /// A canção: em quantas batidas a corrida chega em você.
  final int chargeBeats;

  /// A canção: meia janela do choque em volta da batida (s reais).
  final double beatWindow;

  /// A canção: chance por segundo de um passo falso fora do tempo.
  final double offbeatPerSecond;

  /// A canção: o quanto a música acelera com ele em cima de você.
  final double tempoRise;

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
      tactics: [
        Tactic.roam,
        Tactic.statue,
        if (night >= 2) Tactic.ambush,
        if (night >= 3) Tactic.blackout,
      ],
      faceFlashPerSecond: 0.035 + 0.01 * n,
    );
  }

  /// A noite extra "A canção": ele só anda na batida da música, e o choque
  /// só pega no tempo. Só rondar (as outras táticas brigam com o ritmo); as
  /// fintas, o chiado e os sumiços vêm fora do tempo.
  factory Rules.lullaby() => const Rules(
    repelsToWin: 4,
    cloakPerSecond: 0.15,
    feintChance: 0.3,
    shockCooldown: 1,
    fakeScarePerSecond: 0.04,
    faceFlashPerSecond: 0.04,
    offbeatPerSecond: 0.18,
  );

  /// O que a noite traz de novo, para a tela de antes dela.
  static String? novelty(int night) => switch (night) {
    songNight =>
      'Ele só anda na batida da música. Quando ele correr, choque no tempo '
          'da batida, mirando nele. Fora do tempo, o choque se perde. E nem '
          'todo passo é dele.',
    1 =>
      'Às vezes ele congela quando a luz bate. Não solte: no escuro, '
          'ele anda depressa.',
    2 =>
      'Ele aprendeu a fingir e a sumir sem barulho. Se ouvir uma '
          'respiração atrás de você, vire.',
    3 =>
      'Agora ele corre invisível e apaga a sua luz. No escuro, siga o '
          'som e o chiado.',
    4 => 'Tem outra coisa no quarto. Ela vem atrás da luz.',
    _ => null,
  };
}

/// Uma noite de V.I.G.I.L.: você parado, o Manequim andando em volta. Ele
/// some (só o chiado denuncia), a lanterna o revela, e quando ele corre você
/// tem um instante para acertar o choque. Determinístico dado o [seed] (e,
/// com [director], dado o que o jogador faz).
class VigilGame {
  VigilGame({
    int seed = 0,
    this.rules = const Rules(),
    this.director,
    BeatMap? song,
  }) : _rng = Random(seed),
       song = song == null ? null : SongClock(song, window: rules.beatWindow) {
    director?.startNight();
    _arrive(first: true);
    mothAngle = wrapAngle(angle + pi);
  }

  final Rules rules;
  final Random _rng;

  /// O diretor do medo: sem ele, tática e lado são puro sorteio.
  final FearDirector? director;

  /// A canção (noite extra): com ela, ele só anda na batida.
  final SongClock? song;

  /// A canção: a corrida chegou em você na batida; ainda dá para acertar o
  /// choque até a janela fechar ([Rules.beatWindow] depois da batida).
  bool _arrived = false;

  /// A canção: choques fora do tempo (também contam em [misses]).
  int offBeatShocks = 0;

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

  /// A tática desta aparição.
  Tactic tactic = Tactic.roam;

  /// Apagão: a lanterna não acende até ele ir embora.
  bool blackout = false;

  /// Estátua: muda a cada vez que a luz o pega (o desenho troca de pose).
  int pose = 0;
  bool _frozen = false;

  /// Emboscada: sumido, e depois a respiração atrás de você.
  double _lurkLeft = 0;
  double _warnLeft = 0;
  double _chargeFactor = 1;
  double _stepClock = 0;

  /// O rosto piscando no feixe (susto falso): segundos que ainda faltam.
  double faceFlash = 0;

  /// Para o diretor: erros nesta aparição, tempo correndo sem você mirar
  /// nele, e há quanto tempo ele está invisível sem você achar o chiado
  /// (negativo = já achou).
  int _missesHere = 0;
  double _lateAim = 0;
  double _hiddenFor = 0;

  /// Para o recorde e as conquistas.
  double lanternTime = 0;
  int misses = 0;
  int perfectHits = 0;

  /// O chiado falso: um ângulo e quanto tempo ainda dura.
  double? fakeStaticAngle;
  double _fakeLeft = 0;

  /// Pisca quando a pilha está fraca: neste quadro a luz falhou.
  bool flickerOff = false;

  final List<Cue> _cues = [];

  bool get lit => lanternHeld && battery > 0 && !flickerOff && !blackout;

  /// Emboscada: sumido, sem barulho nem chiado.
  bool get lurking => tactic == Tactic.ambush && _lurkLeft > 0;

  /// Estátua parada na luz.
  bool get frozen => _frozen;
  bool get present => mode != Mode.gone;

  /// O quanto ele está fora do centro da tela, em radianos.
  double get offset => angleDiff(angle, heading);
  bool get inBeam => offset.abs() <= rules.beamHalfWidth;

  /// Invisível, mas a luz em cima dele o mostra.
  bool get revealed => cloaked && lit && inBeam && !lurking;

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
    if (present && cloaked && !revealed && !lurking) {
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
    final aimed = offset.abs() <= rules.aimHalfWidth * (blackout ? 1.3 : 1);
    final s = song;
    // Com a canção, a janela é o tempo (±80 ms da batida), não a distância.
    final hit = s != null
        ? mode == Mode.charging && s.inWindow && aimed
        : mode == Mode.charging && distance <= rules.shockWindow && aimed;
    if (!hit) {
      if (s != null && !s.inWindow) offBeatShocks++;
      misses++;
      if (present) _missesHere++;
      _cue(CueKind.miss);
      return false;
    }
    final perfect = s != null
        ? s.offset.abs() <= 0.03
        : distance <= rules.shockWindow * 0.5;
    if (perfect) perfectHits++;
    _arrived = false;
    _cue(CueKind.hit, near: true);
    repels++;
    mode = Mode.gone;
    cloaked = false;
    blackout = false;
    _chargeFactor = 1;
    _goneLeft = rules.goneSeconds;
    if (director case final d? when !scripted) {
      final o = _missesHere > 0 || _lateAim > 0.5
          ? Outcome.close
          : _lateAim < 0.2
          ? Outcome.easy
          : Outcome.normal;
      d.result(tactic, o);
      _goneLeft += d.breatherAfter(o);
    }
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
      lanternTime += dt;
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

    final d = scripted ? null : director;
    if (d != null) {
      d.look(dt, heading: heading, lit: lit);
      _watchStatic(d, dt);
    }

    if (!scripted) {
      _fakeStatic(dt);
      _fakeScares(dt);
      _faceFlashes(dt);
    }
    _moth(dt);

    if (song case final s?) return _rhythm(s, dt);

    switch (mode) {
      case Mode.gone:
        _goneLeft -= dt;
        if (_goneLeft <= 0) _arrive();
      case Mode.roaming:
        _roam(dt);
      case Mode.charging:
        if (offset.abs() > rules.aimHalfWidth * (blackout ? 1.3 : 1)) {
          _lateAim += dt;
        }
        distance -= rules.chargeAt / (rules.chargeSeconds * _chargeFactor) * dt;
        if (_feint && distance <= rules.chargeAt * 0.55) {
          // Finta: para no meio, recua um pouco e volta a rodear.
          mode = Mode.roaming;
          blackout = false;
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
            director?.result(tactic, Outcome.caught);
          }
        }
    }
  }

  void _roam(double dt) {
    if (scripted) return;
    switch (tactic) {
      case Tactic.statue:
        return _statue(dt);
      case Tactic.ambush:
        if (_ambush(dt)) return;
      case Tactic.blackout:
        if (!blackout && distance <= rules.blackoutAt) {
          blackout = true;
          cloaked = true;
          _stepClock = 0;
          _cue(CueKind.blackout, near: true);
        }
        if (blackout) return _inTheDark(dt);
      case Tactic.roam:
        break;
    }
    if (_rng.nextDouble() < 0.25 * dt) _orbitDir = -_orbitDir;
    // Olhar para ele (visível) o faz hesitar; sem ninguém olhando, ele anda mais.
    final watched = visible && offset.abs() < 0.6;
    angle = wrapAngle(
      angle + _orbitDir * rules.orbitSpeed * (watched ? 0.35 : 1.15) * dt,
    );

    final before = distance;
    distance -= rules.approachPerSecond * (watched ? 0.7 : 1.15) * dt;
    _steps(before);

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

  void _steps(double before) {
    for (final step in const [0.9, 0.78, 0.66, 0.54]) {
      if (before > step && distance <= step) _cue(CueKind.step);
    }
  }

  /// Estátua: a luz em cima dele o congela (e ele troca de pose quando você
  /// não está vendo); no escuro, anda depressa direto para você.
  void _statue(double dt) {
    cloaked = false;
    if (lit && inBeam) {
      _frozen = true;
      return;
    }
    if (_frozen) {
      _frozen = false;
      pose++;
    }
    final before = distance;
    distance -= rules.approachPerSecond * 1.8 * dt;
    angle = wrapAngle(angle + _orbitDir * rules.orbitSpeed * 0.35 * dt);
    _steps(before);
    if (distance <= rules.chargeAt) startCharge();
  }

  /// Emboscada: sumido e calado; depois respira atrás de você e corre.
  /// Devolve se ainda está na emboscada (sem andar como de costume).
  bool _ambush(double dt) {
    if (_lurkLeft > 0) {
      _lurkLeft -= dt;
      if (_lurkLeft <= 0) {
        angle = wrapAngle(heading + pi + (_rng.nextDouble() - 0.5) * 0.7);
        distance = rules.chargeAt + 0.04;
        cloaked = false;
        _warnLeft = rules.ambushWarnSeconds;
        _cue(CueKind.breath, near: true);
      }
      return true;
    }
    if (_warnLeft > 0) {
      _warnLeft -= dt;
      if (_warnLeft <= 0) {
        _chargeFactor = rules.ambushChargeFactor;
        startCharge();
      }
      return true;
    }
    return false;
  }

  /// Apagão: invisível e rápido em volta de você, com passos frequentes (o
  /// som 3D é a pista), até correr. Nunca é finta.
  void _inTheDark(double dt) {
    cloaked = true;
    if (_rng.nextDouble() < 0.5 * dt) _orbitDir = -_orbitDir;
    angle = wrapAngle(angle + _orbitDir * rules.orbitSpeed * 1.6 * dt);
    distance -= rules.approachPerSecond * 1.1 * dt;
    _stepClock -= dt;
    if (_stepClock <= 0) {
      _stepClock = 0.55;
      _cue(CueKind.step);
    }
    if (distance <= rules.chargeAt) startCharge();
  }

  /// O quanto ele está perto (0 = longe ou sumido, 1 = em você).
  double get closeness => present ? (1 - distance).clamp(0.0, 1.0) : 0;

  /// A canção: o andamento (acelera com ele perto).
  double get songTempo => 1 + rules.tempoRise * closeness;

  /// A canção: o quanto a versão desafinada toma conta (0 a 1).
  double get songDetune {
    final x = ((closeness - 0.15) / 0.65).clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  /// A canção: tudo o que ele faz de verdade acontece na batida; entre
  /// elas, fica parado. Sumir, o chiado, a finta da corrida e os passos
  /// falsos vêm fora do tempo (para o ritmo não virar previsão).
  void _rhythm(SongClock s, double dt) {
    s.tempo = songTempo;
    for (final _ in s.advance(dt)) {
      _onBeat();
      if (phase != Phase.playing) return;
    }
    // A janela conta da batida em que ele chegou, não do começo do quadro.
    if (_arrived && s.sinceBeat > rules.beatWindow) {
      _arrived = false;
      phase = Phase.lost;
      killer = Killer.mannequin;
      director?.result(tactic, Outcome.caught);
      return;
    }
    switch (mode) {
      case Mode.gone:
        _goneLeft -= dt;
      case Mode.roaming:
        if (scripted) break;
        if (cloaked) {
          _cloakLeft -= dt;
          if (_cloakLeft <= 0) cloaked = false;
        } else if (_rng.nextDouble() < rules.cloakPerSecond * dt) {
          cloaked = true;
          _cloakLeft = rules.cloakSeconds * (0.6 + 0.8 * _rng.nextDouble());
        }
      case Mode.charging:
        if (offset.abs() > rules.aimHalfWidth) _lateAim += dt;
        // Finta: no meio do caminho e no meio entre duas batidas, ele para
        // e recua (recuar não é avançar: pode fora do tempo).
        if (_feint &&
            distance <= rules.chargeAt * 0.55 &&
            s.sinceBeat >= s.period * 0.5) {
          mode = Mode.roaming;
          distance = rules.chargeAt + 0.12;
          _feint = false;
          _cue(CueKind.feint);
        }
    }
    if (!scripted &&
        present &&
        rules.offbeatPerSecond > 0 &&
        _rng.nextDouble() < rules.offbeatPerSecond * dt &&
        s.offset.abs() > 0.2) {
      _cueAt(CueKind.offbeat, offset + (_rng.nextDouble() - 0.5) * 0.8);
    }
  }

  /// Uma batida da canção: o único momento em que ele avança.
  void _onBeat() {
    switch (mode) {
      case Mode.gone:
        if (_goneLeft <= 0) _arrive();
      case Mode.roaming:
        if (scripted) return;
        if (_rng.nextDouble() < 0.2) _orbitDir = -_orbitDir;
        final watched = visible && offset.abs() < 0.6;
        angle = wrapAngle(
          angle + _orbitDir * rules.beatOrbit * (watched ? 0.4 : 1),
        );
        distance -= rules.beatStep * (watched ? 0.6 : 1);
        _cue(CueKind.step);
        if (distance <= rules.chargeAt) {
          startCharge(feint: _rng.nextDouble() < rules.feintChance);
        }
      case Mode.charging:
        if (_arrived) return;
        distance -= rules.chargeAt / rules.chargeBeats;
        _cue(CueKind.step, near: true);
        if (distance <= 1e-9) {
          if (scripted) {
            mode = Mode.roaming;
            distance = rules.chargeAt + 0.1;
            return;
          }
          // Chegou na batida: a janela do choque ainda fica aberta depois.
          distance = 0;
          _arrived = true;
        }
    }
  }

  /// Para o diretor: quanto tempo você leva para achar o chiado quando ele
  /// some (achar = olhar para onde ele está).
  void _watchStatic(FearDirector d, double dt) {
    final hidden = present && cloaked && !lurking && !blackout;
    if (!hidden) {
      if (_hiddenFor > 0.5) d.staticFound(_hiddenFor, found: false);
      _hiddenFor = 0;
      return;
    }
    if (_hiddenFor < 0) return;
    if (offset.abs() < 0.5) {
      if (_hiddenFor > 0) d.staticFound(_hiddenFor);
      _hiddenFor = -1;
    } else {
      _hiddenFor += dt;
    }
  }

  void _faceFlashes(double dt) {
    if (faceFlash > 0) {
      faceFlash = max(0, faceFlash - dt);
      return;
    }
    if (!lit || mode == Mode.charging || (visible && inBeam)) return;
    final rate = rules.faceFlashPerSecond * (director?.faceRate ?? 1);
    if (_rng.nextDouble() < rate * dt) {
      faceFlash = 0.16;
      _cueAt(CueKind.face, 0, near: true);
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
    final rate = rules.fakeScarePerSecond * (director?.scareRate ?? 1);
    if (_rng.nextDouble() >= rate * dt) return;
    final kind = _rng.nextBool() ? CueKind.knock : CueKind.shadow;
    _cueAt(kind, (_rng.nextDouble() * 2 - 1) * pi);
  }

  void _arrive({bool first = false}) {
    final options = rules.tactics;
    final d = director;
    if (first || options.length < 2) {
      tactic = options.first;
    } else if (d != null) {
      // O diretor pesa a que mais surpreende você (nunca a mesma seguida).
      tactic = d.nextTactic(options, last: tactic, roll: _rng.nextDouble());
    } else {
      final pool = [
        for (final o in options)
          if (o != tactic) o,
      ];
      tactic = pool[_rng.nextInt(pool.length)];
    }
    mode = Mode.roaming;
    distance = 1;
    blackout = false;
    _arrived = false;
    _frozen = false;
    _warnLeft = 0;
    _chargeFactor = 1;
    _lurkLeft = tactic == Tactic.ambush
        ? rules.ambushLurkSeconds * (1 + _rng.nextDouble())
        : 0;
    cloaked = tactic == Tactic.ambush;
    _feint = false;
    _missesHere = 0;
    _lateAim = 0;
    _hiddenFor = 0;
    _orbitDir = _rng.nextBool() ? 1 : -1;
    // Nunca aparece na sua frente: de lado ou atrás. O diretor prefere o
    // lado do quarto que você mais esquece.
    final side = d != null
        ? d.side(heading, _rng.nextDouble())
        : (_rng.nextBool() ? 1 : -1);
    angle = wrapAngle(heading + side * (1.2 + 1.6 * _rng.nextDouble()));
    if (!first && tactic != Tactic.ambush) _cue(CueKind.arrive);
  }

  /// Recentralizar: a frente de agora vira o "norte" do quarto (corrige a
  /// deriva do giroscópio). Gira o mundo inteiro junto, então nada muda em
  /// relação a você: ele, a Mariposa e o chiado falso continuam onde estavam.
  void recenter() {
    final delta = -heading;
    heading = 0;
    angle = wrapAngle(angle + delta);
    mothAngle = wrapAngle(mothAngle + delta);
    if (fakeStaticAngle case final f?) fakeStaticAngle = wrapAngle(f + delta);
    director?.rotate(delta);
  }

  void _cue(CueKind kind, {bool near = false}) =>
      _cueAt(kind, offset, near: near);

  void _cueAt(CueKind kind, double d, {bool near = false}) {
    _cues.add(
      Cue(kind, sin(d), behind: d.abs() > pi / 2, near: near, angle: d),
    );
    if (!scripted) director?.scared(kind);
  }
}

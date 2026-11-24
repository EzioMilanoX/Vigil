import 'dart:async';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../data/save.dart';
import '../game/achievements.dart';
import '../game/director.dart';
import '../game/lullaby.dart';
import '../game/tutorial.dart';
import '../game/vigil_game.dart';
import 'room_painter.dart';
import 'sounds.dart';
import 'title_screen.dart' show StoryScreen;

/// Uma noite (ou o tutorial). O fundo é o seu quarto pela câmera; gire o corpo
/// com o celular (ou arraste). Segure a lanterna; toque no choque quando ele correr.
class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.save,
    this.night = 1,
    this.tutorial = false,
    this.seed,
    this.useSensors = true,
    this.song,
    @visibleForTesting this.debugGame,
  });

  final Save save;

  /// Qual noite (1, 2, ...): cada uma mais difícil.
  final int night;

  /// A noite de treino guiada.
  final bool tutorial;
  final int? seed;

  /// Giroscópio, câmera e som (desligados nos testes).
  final bool useSensors;

  /// A canção (noite [songNight]): as batidas. Sem elas, lê
  /// `assets/musica/cancao.json` (e, se falhar, um metrônomo a 72).
  final BeatMap? song;

  /// Uma noite já montada, para testes e capturas de tela.
  final VigilGame? debugGame;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

/// Só numa versão de teste (--dart-define=VIGIL_PERF=true): tempo de cada
/// quadro na tela, para medir no celular.
const _perf = bool.fromEnvironment('VIGIL_PERF');

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late VigilGame _game;
  TutorialCoach? _coach;

  /// O diretor do medo desta noite: lembra de você também no "De novo".
  FearDirector? _director;

  /// "Frente aqui": segundos que o aviso de recentralizar ainda fica.
  double _recentered = 0;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _clock = 0;
  StreamSubscription<GyroscopeEvent>? _gyro;
  StreamSubscription<AccelerometerEvent>? _accel;
  double _turnRate = 0;

  /// Para onde é "para cima" no referencial do celular (gravidade filtrada).
  var _up = (0.0, 1.0, 0.0);
  Sounds? _sounds;
  CameraController? _camera;
  bool _torch = false;
  bool _paused = false;
  bool _recorded = false;
  double _heartIn = 0;
  double _flash = 0;
  double _flashPan = 0;
  double _shadow = -1;

  // Medição (VIGIL_PERF): média e pior quadro, de pintura e de montagem
  final _raster = <double>[];
  final _build = <double>[];
  var _perfText = '';

  void _onTimings(List<FrameTiming> timings) {
    for (final f in timings) {
      _raster.add(f.rasterDuration.inMicroseconds / 1000);
      _build.add(f.buildDuration.inMicroseconds / 1000);
    }
    while (_raster.length > 300) {
      _raster.removeAt(0);
      _build.removeAt(0);
    }
    double avg(List<double> v) => v.reduce((a, b) => a + b) / v.length;
    double p95(List<double> v) => ([...v]..sort())[(v.length * 0.95).floor()];
    final slow = _raster.where((r) => r > 16.7).length;
    _perfText =
        'pintura  média ${avg(_raster).toStringAsFixed(1)} ms  p95 ${p95(_raster).toStringAsFixed(1)} ms\n'
        'montagem média ${avg(_build).toStringAsFixed(1)} ms  p95 ${p95(_build).toStringAsFixed(1)} ms\n'
        'quadros lentos $slow/${_raster.length}';
  }

  /// O susto quando algo pega você: segundos que ainda faltam na tela.
  double _scare = 0;

  /// Antes do susto: a luz morre e tudo fica em silêncio por um instante.
  double _doom = 0;

  /// O quarto treme com um som perto (0 a 1).
  double _shake = 0;

  /// Conquistas ganhas nesta noite, para a tela do fim.
  var _newAchievements = <Achievement>[];

  /// A canção: as batidas, a música, e se ela já começou (antes disso, a
  /// noite espera: o relógio dele é a música).
  BeatMap? _beats;
  SongPlayer? _music;
  bool _ready = true;
  double _syncIn = 0;

  /// "fora do tempo": segundos que o aviso ainda fica.
  double _offBeat = 0;

  bool get _isSong => widget.night == songNight && !widget.tutorial;
  String get _nightName => _isSong ? 'A canção' : 'Noite ${widget.night}';

  Settings get _settings => widget.save.settings;

  @override
  void initState() {
    if (_perf) SchedulerBinding.instance.addTimingsCallback(_onTimings);
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!widget.tutorial && _settings.fearDirector) _director = FearDirector();
    if (_isSong) {
      _beats = widget.song;
      if (widget.useSensors) _music = SongPlayer(volume: _settings.volume);
    }
    _newNight();
    if (_isSong && _beats == null) _loadSong();
    if (widget.debugGame case final g?) _game = g;
    _ticker = createTicker(_tick)..start();
    if (widget.useSensors && !_settings.dragOnly) {
      try {
        // Virar o corpo = girar em volta da vertical do mundo. Projetar o
        // giroscópio na direção "para cima" funciona em pé ou inclinado.
        _accel = accelerometerEventStream().listen(_onAccel, onError: (_) {});
        _gyro = gyroscopeEventStream().listen(
          (e) => _turnRate = e.x * _up.$1 + e.y * _up.$2 + e.z * _up.$3,
          onError: (_) {},
          cancelOnError: true,
        );
      } catch (_) {
        // Sem giroscópio (Windows): fica só o arrastar.
      }
    }
    if (widget.useSensors) {
      _sounds = Sounds(volume: _settings.volume, binaural: _settings.sound3d);
      if (_settings.camera) _openCamera();
    }
  }

  /// Lê as batidas da música; sem elas, um metrônomo (o jogo não trava).
  Future<void> _loadSong() async {
    _ready = false;
    BeatMap map;
    try {
      map = BeatMap.parse(
        await rootBundle.loadString('assets/musica/cancao.json'),
      );
    } catch (_) {
      map = BeatMap.metronome();
    }
    if (!mounted) return;
    _beats = map;
    setState(_newNight);
  }

  /// A música começa do zero junto com a noite. Até ela tocar, a noite
  /// espera; sem áudio (testes, volume zero), anda pelo relógio do jogo.
  Future<void> _startMusic() async {
    final m = _music;
    if (m == null || _beats == null) {
      _ready = _beats != null;
      return;
    }
    _ready = false;
    final ok = await m.start();
    if (!mounted) return;
    setState(() {
      _ready = true;
      _last = Duration.zero;
      _syncIn = ok ? 0.5 : double.infinity;
    });
  }

  /// O som manda: puxa o relógio da canção para onde a música está (menos o
  /// atraso do som até o ouvido, das configurações).
  Future<void> _syncSong() async {
    final pos = await _music?.position();
    final s = _game.song;
    if (pos == null || s == null || !mounted) return;
    if (_paused || !_ready || _game.phase != Phase.playing) return;
    s.sync(pos - _settings.songDelayMs / 1000 * s.tempo);
  }

  Future<void> _openCamera() async {
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final c = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _camera = c);
    } catch (_) {
      // Sem câmera ou sem permissão: o quarto desenhado.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // O celular tocou, ou você saiu do app: a noite espera.
    if (state != AppLifecycleState.resumed) _pause(true);
  }

  void _pause(bool on) {
    if (_game.phase != Phase.playing) return;
    setState(() => _paused = on);
    if (on) {
      _game.lanternHeld = false;
      _sounds?.silence();
      _music?.pause();
      _syncTorch();
    } else if (_ready) {
      _music?.resume();
      _syncIn = 0.3;
    }
  }

  /// A lanterna do próprio celular acompanha a do jogo.
  void _syncTorch() {
    final c = _camera;
    final want = _game.lit && _game.phase == Phase.playing && !_paused;
    if (c == null || want == _torch) return;
    _torch = want;
    c.setFlashMode(want ? FlashMode.torch : FlashMode.off).catchError((_) {});
  }

  void _onAccel(AccelerometerEvent e) {
    final n = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if (n < 1) return;
    const k = 0.1;
    final (x, y, z) = _up;
    final nx = x + k * (e.x / n - x);
    final ny = y + k * (e.y / n - y);
    final nz = z + k * (e.z / n - z);
    final m = sqrt(nx * nx + ny * ny + nz * nz);
    _up = (nx / m, ny / m, nz / m);
  }

  void _newNight() {
    _game = VigilGame(
      seed: widget.seed ?? DateTime.now().millisecondsSinceEpoch,
      rules: widget.tutorial
          ? const Rules(chargeSeconds: 2.6, batterySeconds: 600)
          : _isSong
          ? Rules.lullaby()
          : Rules.forNight(widget.night),
      director: _director,
      song: _isSong ? _beats ?? BeatMap.metronome() : null,
    );
    _coach = widget.tutorial ? TutorialCoach(_game) : null;
    _last = Duration.zero;
    _scare = 0;
    _doom = 0;
    _shake = 0;
    _paused = false;
    _recorded = false;
    _newAchievements = [];
    _offBeat = 0;
    if (_isSong) _startMusic();
  }

  @override
  void dispose() {
    if (_perf) SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    WidgetsBinding.instance.removeObserver(this);
    _gyro?.cancel();
    _accel?.cancel();
    _sounds?.dispose();
    _music?.dispose();
    _camera?.dispose();
    _ticker.dispose();
    super.dispose();
  }

  void _haptic(bool strong) {
    if (!_settings.vibration) return;
    strong ? HapticFeedback.heavyImpact() : HapticFeedback.lightImpact();
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero
        ? 0.0
        : (now - _last).inMicroseconds / 1e6;
    _last = now;
    if (dt <= 0 || dt > 0.25) return;
    _clock += dt;
    _scare = max(0, _scare - dt);
    _shake = max(0, _shake - dt * 2.5);
    _recentered = max(0, _recentered - dt);
    _offBeat = max(0, _offBeat - dt);
    if (_doom > 0) {
      _doom -= dt;
      if (_doom <= 0) {
        _scare = scareSeconds;
        _sounds?.scream();
        if (_settings.vibration) {
          HapticFeedback.vibrate();
          Future.delayed(
            const Duration(milliseconds: 180),
            HapticFeedback.heavyImpact,
          );
          Future.delayed(
            const Duration(milliseconds: 420),
            HapticFeedback.vibrate,
          );
        }
      }
    }
    if (_paused || !_ready) {
      setState(() {});
      return;
    }
    final turn = _turnRate * _settings.sensitivity;
    _game.heading = wrapAngle(
      _game.heading + (_settings.invertTurn ? turn : -turn) * dt,
    );
    final before = _game.phase;
    _game.update(dt);
    _coach?.update(dt);
    if (before == Phase.playing && _game.phase != Phase.playing) _ended();
    for (final cue in _game.takeCues()) {
      // Na canção, ele dá um passo a cada batida: sem clarão nem vibração em
      // cada um (entregaria o lado e a batida); só o som e os passos perto.
      final quietStep =
          _game.song != null &&
          !cue.near &&
          (cue.kind == CueKind.step || cue.kind == CueKind.offbeat);
      if (quietStep) {
        _sounds?.cue(cue);
        continue;
      }
      switch (cue.kind) {
        case CueKind.shadow:
          _shadow = 0;
        case CueKind.face:
          _shake = 0.7;
        case CueKind.breath || CueKind.blackout:
          _shake = 1;
          _flash = 1;
          _flashPan = cue.pan;
        case CueKind.miss || CueKind.knock:
          break;
        default:
          _flash = cue.near ? 1 : 0.5;
          _flashPan = cue.pan;
      }
      if (cue.kind != CueKind.shadow) _haptic(cue.near);
      _sounds?.cue(cue);
    }
    if (_shadow >= 0) _shadow = _shadow > 1 ? -1 : _shadow + dt * 2.2;
    final playing = _game.phase == Phase.playing;
    _sounds?.staticLevel(playing ? _game.staticLevel : 0);
    _sounds?.mothLevel(playing ? _game.mothLevel : 0, sin(_game.mothOffset));
    _heartbeat(dt);
    if (_game.song != null && playing) {
      _music?.mix(_game.songTempo, _game.songDetune);
      _syncIn -= dt;
      if (_syncIn <= 0) {
        _syncIn = 1;
        _syncSong();
      }
    }
    _syncTorch();
    _flash = max(0, _flash - dt * 1.5);
    setState(() {});
  }

  void _ended() {
    final g = _game;
    _sounds?.silence();
    _music?.stop();
    if (g.phase == Phase.lost) {
      // Um instante de escuro e silêncio, e então ele.
      _sounds?.hush();
      _doom = g.killer == Killer.moth ? 0.25 : 0.55;
    }
    if (_recorded || widget.tutorial) return;
    _recorded = true;
    widget.save
        .finish(
          NightResult(
            night: widget.night,
            won: g.phase == Phase.won,
            time: g.time,
            repels: g.repels,
            lanternTime: g.lanternTime,
            misses: g.misses,
            perfectHits: g.perfectHits,
          ),
        )
        .then((novas) {
          if (mounted) setState(() => _newAchievements = novas);
        });
  }

  /// Com ele perto, o coração bate, mais rápido quanto mais perto.
  void _heartbeat(double dt) {
    final g = _game;
    final p = g.present && g.phase == Phase.playing ? 1 - g.distance : 0.0;
    if (p < 0.4) {
      _heartIn = 0;
      return;
    }
    _heartIn -= dt;
    if (_heartIn > 0) return;
    _heartIn = 1.1 - 0.7 * p;
    _sounds?.heartbeat(p);
  }

  /// Arrastar move o quarto junto com o dedo, como num panorama.
  void _drag(DragUpdateDetails d) {
    if (_paused) return;
    final width = context.size?.width ?? 400;
    final dx = d.delta.dx * (_settings.invertTurn ? -1 : 1);
    _game.heading = wrapAngle(_game.heading - dx * fieldOfView / width);
  }

  /// A frente de agora vira o "norte" do quarto (corrige a deriva do giro).
  void _recenter() {
    if (_paused || _game.phase != Phase.playing) return;
    _game.recenter();
    if (_settings.vibration) HapticFeedback.selectionClick();
    setState(() => _recentered = 1.2);
  }

  void _shock() {
    if (_paused) return;
    final before = _game.offBeatShocks;
    final hit = _game.shock();
    if (_settings.vibration) HapticFeedback.mediumImpact();
    if (hit) _flash = 0;
    if (_game.offBeatShocks > before) _offBeat = 0.9;
    setState(() {});
  }

  void _lantern(bool on) {
    if (_paused) return;
    setState(() => _game.lanternHeld = on);
  }

  void _toStory(int night) => Navigator.pushReplacement(
    context,
    MaterialPageRoute(
      builder: (_) => StoryScreen(save: widget.save, night: night),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final g = _game;
    final cam = _camera;
    final coach = _coach;
    return PopScope(
      canPop: _paused || g.phase != Phase.playing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _pause(true);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: _drag,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (cam != null && cam.value.isInitialized)
                FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: cam.value.previewSize?.height ?? 1,
                    height: cam.value.previewSize?.width ?? 1,
                    child: CameraPreview(cam),
                  ),
                ),
              Positioned.fill(
                child: Transform.translate(
                  offset: Offset(
                    sin(_clock * 93) * 12 * _shake,
                    cos(_clock * 71) * 7 * _shake,
                  ),
                  child: CustomPaint(
                    painter: RoomPainter(
                      g,
                      flash: _flash,
                      flashPan: _flashPan,
                      hasCamera: cam != null,
                      clock: _clock,
                      shadow: _shadow,
                    ),
                  ),
                ),
              ),
              if (g.song case final s?
                  when _settings.beatPulse && g.phase == Phase.playing)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      key: const Key('pulso'),
                      painter: _BeatPulse(exp(-s.sinceBeat * 7)),
                    ),
                  ),
                ),
              Positioned(top: 0, left: 0, right: 0, child: _hud(g)),
              if (_offBeat > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: MediaQuery.paddingOf(context).bottom + 150,
                  child: IgnorePointer(
                    child: Text(
                      'fora do tempo',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(
                          0xFFE8DFC8,
                        ).withValues(alpha: min(1, _offBeat * 1.5)),
                        letterSpacing: 3,
                      ),
                    ),
                  ),
                ),
              if (_perf)
                Positioned(
                  left: 12,
                  bottom: 140,
                  child: Text(
                    _perfText,
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              if (coach != null) _coachBanner(coach),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(child: _controls(g)),
              ),
              if (!_ready && !_paused)
                const ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: Text(
                      'dando corda na caixinha...',
                      style: TextStyle(color: Colors.white38, letterSpacing: 2),
                    ),
                  ),
                ),
              if (_paused) _pauseMenu(),
              if (_doom > 0)
                const Positioned.fill(child: ColoredBox(color: Colors.black))
              else if (_scare > 0)
                Positioned.fill(
                  child: CustomPaint(
                    painter: ScarePainter(
                      _scare / scareSeconds,
                      moth: g.killer == Killer.moth,
                    ),
                  ),
                )
              else if (g.phase != Phase.playing)
                _end(g),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hud(VigilGame g) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
      child: Row(
        children: [
          IconButton(
            key: const Key('pausar'),
            tooltip: 'Pausar',
            onPressed: () => _pause(true),
            icon: const Icon(Icons.pause, color: Colors.white54),
          ),
          // Discreto: a frente de agora vira a frente do quarto.
          IconButton(
            key: const Key('recentralizar'),
            tooltip: 'Recentralizar: a frente é aqui',
            onPressed: _recenter,
            icon: Icon(
              Icons.explore_outlined,
              color: _recentered > 0 ? const Color(0xFFE8DFC8) : Colors.white24,
              size: 20,
            ),
          ),
          if (_recentered > 0)
            const Text(
              'frente aqui  ',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          Icon(
            Icons.battery_std,
            color: g.battery < g.rules.lowBattery
                ? Colors.red.shade700
                : Colors.white54,
            size: 18,
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 64,
            child: LinearProgressIndicator(
              key: const Key('pilha'),
              value: g.battery,
              color: g.battery < g.rules.lowBattery
                  ? Colors.red.shade900
                  : Colors.white54,
              backgroundColor: Colors.white10,
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.tutorial ? 'Treino   ' : '$_nightName   ',
                      style: const TextStyle(color: Colors.white38),
                    ),
                    if (!widget.tutorial)
                      for (var k = 0; k < g.rules.repelsToWin; k++)
                        Padding(
                          padding: const EdgeInsets.only(left: 3),
                          child: Icon(
                            k < g.repels ? Icons.bolt : Icons.bolt_outlined,
                            size: 18,
                            color: k < g.repels
                                ? const Color(0xFFE8DFC8)
                                : Colors.white24,
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _coachBanner(TutorialCoach coach) {
    final done = coach.step == TutorialStep.done;
    final now = coach.message == 'AGORA!';
    return Positioned(
      left: 20,
      right: 20,
      // Embaixo, acima dos botões: em cima ficaria na frente do rosto dele.
      bottom: MediaQuery.paddingOf(context).bottom + 140,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          border: Border.all(color: const Color(0x55E8DFC8)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${coach.step.index + 1 > 4 ? 4 : coach.step.index + 1}/4',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              coach.message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: now ? const Color(0xFFFFD27A) : Colors.white,
                fontSize: now ? 28 : 16,
                fontWeight: now ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (done) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  widget.save.tutorialDone = true;
                  widget.save.unlock(['treino']);
                  widget.save.store();
                  _toStory(1);
                },
                child: const Text('Ir para a noite 1'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _controls(VigilGame g) {
    final ready = g.shockReady <= 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Segurar: a lanterna só fica acesa enquanto o dedo está aqui.
          Listener(
            key: const Key('lanterna'),
            onPointerDown: (_) => _lantern(true),
            onPointerUp: (_) => _lantern(false),
            onPointerCancel: (_) => _lantern(false),
            child: _RoundButton(
              icon: g.lanternHeld ? Icons.flashlight_on : Icons.flashlight_off,
              label: 'Segure',
              active: g.lanternHeld,
            ),
          ),
          GestureDetector(
            key: const Key('choque'),
            onTap: _shock,
            child: _RoundButton(
              icon: Icons.bolt,
              label: ready ? 'Choque' : 'Carregando',
              active: false,
              progress: ready ? 1 : 1 - g.shockReady / g.rules.shockCooldown,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pauseMenu() => ColoredBox(
    color: Colors.black.withValues(alpha: 0.85),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Pausado',
            style: TextStyle(color: Colors.white, fontSize: 28),
          ),
          const SizedBox(height: 6),
          const Text(
            'Ele também espera. Por enquanto.',
            style: TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => _pause(false),
            child: const Text('Continuar'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => setState(_newNight),
            child: const Text('Recomeçar a noite'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.maybePop(context),
            child: const Text('Sair para o menu'),
          ),
        ],
      ),
    ),
  );

  Widget _end(VigilGame g) {
    final won = g.phase == Phase.won;
    final rec = widget.save.recordOf(widget.night);
    final minutes = g.time ~/ 60;
    final seconds = (g.time % 60).floor().toString().padLeft(2, '0');
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                won
                    ? 'Amanheceu.'
                    : g.killer == Killer.moth
                    ? 'A luz chamou a Mariposa.'
                    : 'Ele tomou a sua medida.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 26),
              ),
              const SizedBox(height: 8),
              Text(
                won
                    ? '$_nightName em $minutes:$seconds.'
                          '${rec.bestTime == g.time ? ' Recorde!' : ''}'
                    : '$_nightName: espantou ${g.repels} de '
                          '${g.rules.repelsToWin}.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54),
              ),
              if (g.song != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Choques fora do tempo: ${g.offBeatShocks}.',
                    style: const TextStyle(color: Colors.white38),
                  ),
                ),
              if (won && widget.night == songUnlockedAfter)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Chip(
                    avatar: Icon(Icons.music_note, size: 18),
                    label: Text('Liberou a noite extra: A canção'),
                  ),
                ),
              for (final a in _newAchievements)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Chip(
                    avatar: const Icon(Icons.military_tech, size: 18),
                    label: Text('Conquista: ${a.title}'),
                  ),
                ),
              const SizedBox(height: 24),
              if (won && !_isSong)
                FilledButton(
                  onPressed: () => _toStory(widget.night + 1),
                  child: Text('Noite ${widget.night + 1}'),
                )
              else
                FilledButton(
                  onPressed: () => setState(_newNight),
                  child: const Text('De novo'),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.maybePop(context),
                child: const Text('Menu'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A canção (acessibilidade): a borda da tela acende na batida e apaga.
class _BeatPulse extends CustomPainter {
  _BeatPulse(this.strength);
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    if (strength < 0.02) return;
    canvas.drawRect(
      (Offset.zero & size).deflate(4),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = const Color(0xFFE8DFC8).withValues(alpha: 0.55 * strength)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  @override
  bool shouldRepaint(_BeatPulse old) => old.strength != strength;
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.active,
    this.progress = 1,
  });

  final IconData icon;
  final String label;
  final bool active;
  final double progress;

  @override
  Widget build(BuildContext context) {
    const bone = Color(0xFFE8DFC8);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 76,
          height: 76,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: progress,
                strokeWidth: 3,
                color: bone.withValues(alpha: 0.7),
                backgroundColor: Colors.white10,
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active
                      ? bone.withValues(alpha: 0.85)
                      : Colors.black.withValues(alpha: 0.45),
                ),
                child: Icon(
                  icon,
                  size: 34,
                  color: active ? Colors.black : bone,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }
}

import 'dart:async';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../data/save.dart';
import '../game/achievements.dart';
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

  /// Conquistas ganhas nesta noite, para a tela do fim.
  var _newAchievements = <Achievement>[];

  Settings get _settings => widget.save.settings;

  @override
  void initState() {
    if (_perf) SchedulerBinding.instance.addTimingsCallback(_onTimings);
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _newNight();
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
      _syncTorch();
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
          : Rules.forNight(widget.night),
    );
    _coach = widget.tutorial ? TutorialCoach(_game) : null;
    _last = Duration.zero;
    _scare = 0;
    _paused = false;
    _recorded = false;
    _newAchievements = [];
  }

  @override
  void dispose() {
    if (_perf) SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    WidgetsBinding.instance.removeObserver(this);
    _gyro?.cancel();
    _accel?.cancel();
    _sounds?.dispose();
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
    if (_paused) {
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
      switch (cue.kind) {
        case CueKind.shadow:
          _shadow = 0;
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
    _syncTorch();
    _flash = max(0, _flash - dt * 1.5);
    setState(() {});
  }

  void _ended() {
    final g = _game;
    if (g.phase == Phase.lost) {
      _scare = 1.1;
      if (_settings.vibration) HapticFeedback.vibrate();
      _sounds?.scream();
    }
    _sounds?.silence();
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

  void _shock() {
    if (_paused) return;
    final hit = _game.shock();
    if (_settings.vibration) HapticFeedback.mediumImpact();
    if (hit) _flash = 0;
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
              Positioned(top: 0, left: 0, right: 0, child: _hud(g)),
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
              if (_paused) _pauseMenu(),
              if (_scare > 0)
                Positioned.fill(
                  child: CustomPaint(
                    painter: ScarePainter(
                      _scare / 1.1,
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
                      widget.tutorial
                          ? 'Treino   '
                          : 'Noite ${widget.night}   ',
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
                    ? 'Noite ${widget.night} em $minutes:$seconds.'
                          '${rec.bestTime == g.time ? ' Recorde!' : ''}'
                    : 'Noite ${widget.night}: espantou ${g.repels} de '
                          '${g.rules.repelsToWin}.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54),
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
              if (won)
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

import 'dart:async';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../game/vigil_game.dart';
import 'room_painter.dart';
import 'sounds.dart';

/// Uma noite. O fundo é o seu quarto pela câmera; gire o corpo com o celular
/// (ou arraste). Segure a lanterna para ver; toque no choque quando ele correr.
class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    this.seed,
    this.useGyroscope = true,
    this.useSound = true,
    this.useCamera = true,
    this.night = 1,
    this.onWon,
    @visibleForTesting this.debugGame,
  });

  final int? seed;
  final bool useGyroscope;
  final bool useSound;
  final bool useCamera;

  /// Qual noite (1, 2, ...): cada uma mais difícil.
  final int night;

  /// Chamado ao sobreviver, para guardar o progresso.
  final ValueChanged<int>? onWon;

  /// Uma noite já montada, para testes e capturas de tela.
  final VigilGame? debugGame;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late VigilGame _game;
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
  double _heartIn = 0;
  double _flash = 0;
  double _flashPan = 0;

  /// O susto quando ele chega: segundos que ainda faltam na tela.
  double _scare = 0;

  @override
  void initState() {
    super.initState();
    _newNight();
    if (widget.debugGame case final g?) _game = g;
    _ticker = createTicker(_tick)..start();
    if (widget.useGyroscope) {
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
    if (widget.useSound) _sounds = Sounds();
    if (widget.useCamera) _openCamera();
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

  /// A lanterna do próprio celular acompanha a do jogo.
  void _syncTorch() {
    final c = _camera;
    final want = _game.lit && _game.phase == Phase.playing;
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
      rules: Rules.forNight(widget.night),
    );
    _last = Duration.zero;
    _scare = 0;
  }

  @override
  void dispose() {
    _gyro?.cancel();
    _accel?.cancel();
    _sounds?.dispose();
    _camera?.dispose();
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero
        ? 0.0
        : (now - _last).inMicroseconds / 1e6;
    _last = now;
    if (dt <= 0 || dt > 0.25) return;
    _clock += dt;
    _game.heading = wrapAngle(_game.heading - _turnRate * dt);
    final before = _game.phase;
    _game.update(dt);
    if (before == Phase.playing && _game.phase == Phase.lost) {
      _scare = 1.1;
      HapticFeedback.vibrate();
      _sounds?.scream();
    } else if (before == Phase.playing && _game.phase == Phase.won) {
      widget.onWon?.call(widget.night);
    }
    _scare = max(0, _scare - dt);
    for (final cue in _game.takeCues()) {
      if (cue.kind != CueKind.miss) {
        _flash = cue.near ? 1 : 0.5;
        _flashPan = cue.pan;
      }
      if (cue.near) {
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.lightImpact();
      }
      _sounds?.cue(cue);
    }
    _sounds?.staticLevel(_game.phase == Phase.playing ? _game.staticLevel : 0);
    _heartbeat(dt);
    _syncTorch();
    _flash = max(0, _flash - dt * 1.5);
    setState(() {});
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
    final width = context.size?.width ?? 400;
    _game.heading = wrapAngle(_game.heading - d.delta.dx * fieldOfView / width);
  }

  void _shock() {
    final hit = _game.shock();
    HapticFeedback.mediumImpact();
    if (hit) _flash = 0;
    setState(() {});
  }

  void _lantern(bool on) => setState(() => _game.lanternHeld = on);

  @override
  Widget build(BuildContext context) {
    final g = _game;
    final cam = _camera;
    return Scaffold(
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
                ),
              ),
            ),
            Positioned(top: 0, left: 0, right: 0, child: _hud(g)),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(child: _controls(g)),
            ),
            if (_scare > 0)
              Positioned.fill(
                child: CustomPaint(painter: ScarePainter(_scare / 1.1)),
              )
            else if (g.phase != Phase.playing)
              _end(g),
          ],
        ),
      ),
    );
  }

  Widget _hud(VigilGame g) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(
            Icons.battery_std,
            color: g.battery < g.rules.lowBattery
                ? Colors.red.shade700
                : Colors.white54,
            size: 18,
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 70,
            child: LinearProgressIndicator(
              key: const Key('pilha'),
              value: g.battery,
              color: g.battery < g.rules.lowBattery
                  ? Colors.red.shade900
                  : Colors.white54,
              backgroundColor: Colors.white10,
            ),
          ),
          const Spacer(),
          Text(
            'Noite ${widget.night}   ',
            style: const TextStyle(color: Colors.white38),
          ),
          for (var k = 0; k < g.rules.repelsToWin; k++)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                k < g.repels ? Icons.bolt : Icons.bolt_outlined,
                size: 18,
                color: k < g.repels ? const Color(0xFFE8DFC8) : Colors.white24,
              ),
            ),
        ],
      ),
    ),
  );

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

  Widget _end(VigilGame g) {
    final won = g.phase == Phase.won;
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              won ? 'Amanheceu.' : 'Ele chegou.',
              style: const TextStyle(color: Colors.white, fontSize: 28),
            ),
            const SizedBox(height: 8),
            Text(
              won
                  ? 'Você passou a noite ${widget.night}.'
                  : 'Noite ${widget.night}: espantou ${g.repels} de '
                        '${g.rules.repelsToWin}.',
              style: const TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 24),
            if (won)
              FilledButton(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GameScreen(
                      night: widget.night + 1,
                      onWon: widget.onWon,
                      useGyroscope: widget.useGyroscope,
                      useSound: widget.useSound,
                      useCamera: widget.useCamera,
                    ),
                  ),
                ),
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

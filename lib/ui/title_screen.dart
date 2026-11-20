import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../data/save.dart';
import '../game/achievements.dart';
import '../game/story.dart';
import '../game/vigil_game.dart';
import 'game_screen.dart';
import 'mannequin.dart';

const bone = Color(0xFFE8DFC8);

/// O menu: o manequim no escuro ao fundo, e as opções.
class TitleScreen extends StatefulWidget {
  const TitleScreen({super.key, required this.save, this.useSensors = true});

  final Save save;
  final bool useSensors;

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) {
      _t = d.inMicroseconds / 1e6;
      setState(() {});
    })..start();
    widget.save.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    widget.save.removeListener(_changed);
    _ticker.dispose();
    super.dispose();
  }

  void _open(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final save = widget.save;
    final night = save.unlocked;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _MenuBackdrop(_t)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  const Text(
                    'VIGIL',
                    style: TextStyle(
                      color: bone,
                      fontSize: 52,
                      letterSpacing: 14,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const Text(
                    'não olhe para ele no escuro',
                    style: TextStyle(color: Colors.white38, letterSpacing: 2),
                  ),
                  const Spacer(),
                  _MenuButton(
                    key: const Key('jogar'),
                    label: save.tutorialDone
                        ? 'Continuar · noite $night'
                        : 'Começar',
                    primary: true,
                    onTap: () => _open(
                      save.tutorialDone
                          ? StoryScreen(
                              save: save,
                              night: night,
                              useSensors: widget.useSensors,
                            )
                          : GameScreen(
                              save: save,
                              tutorial: true,
                              useSensors: widget.useSensors,
                            ),
                    ),
                  ),
                  _MenuButton(
                    label: 'Noites e recordes',
                    onTap: () => _open(
                      NightsScreen(save: save, useSensors: widget.useSensors),
                    ),
                  ),
                  _MenuButton(
                    label: 'Como jogar (treino)',
                    onTap: () => _open(
                      GameScreen(
                        save: save,
                        tutorial: true,
                        useSensors: widget.useSensors,
                      ),
                    ),
                  ),
                  _MenuButton(
                    label: 'Diário e conquistas',
                    onTap: () => _open(JournalScreen(save: save)),
                  ),
                  _MenuButton(
                    label: 'Configurações',
                    onTap: () => _open(SettingsScreen(save: save)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    save.totalRepels == 0
                        ? 'Use fone. Fique em pé.'
                        : 'Espantou o manequim ${save.totalRepels} vezes.',
                    style: const TextStyle(color: Colors.white30),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Atrás do menu: o manequim parado no escuro, a lanterna que falha às vezes.
class _MenuBackdrop extends CustomPainter {
  _MenuBackdrop(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    // A luz pisca de vez em quando, sem padrão fácil.
    final flicker = sin(t * 7.3) * sin(t * 2.1) > 0.85;
    final lit = !flicker;
    final c = Offset(size.width * 0.72, size.height * 0.42);
    if (lit) {
      canvas.drawCircle(
        c,
        size.width * 0.55,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0x26FFE6B0), Colors.transparent],
          ).createShader(Rect.fromCircle(center: c, radius: size.width * 0.55)),
      );
    }
    final h = size.height * 0.62;
    drawMannequin(
      canvas,
      Offset(c.dx, c.dy + h * 0.55),
      h,
      (lit ? MannequinStyle.dark : MannequinStyle.dark).copyWith(
        headTilt: sin(t * 0.4) * 0.18,
      ),
    );
    // Um véu por cima, para o texto ler bem.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xCC000000), Color(0x22000000)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_MenuBackdrop old) => true;
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: SizedBox(
      width: double.infinity,
      height: 52,
      child: primary
          ? FilledButton(
              onPressed: onTap,
              child: Text(label, style: const TextStyle(fontSize: 16)),
            )
          : OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: bone,
                side: const BorderSide(color: Color(0x55E8DFC8)),
              ),
              onPressed: onTap,
              child: Text(label, style: const TextStyle(fontSize: 16)),
            ),
    ),
  );
}

/// As noites liberadas, com os recordes de cada uma.
class NightsScreen extends StatelessWidget {
  const NightsScreen({super.key, required this.save, this.useSensors = true});

  final Save save;
  final bool useSensors;

  static String clock(double s) =>
      '${s ~/ 60}:${(s % 60).floor().toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: save,
      builder: (context, _) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text('Noites e recordes'),
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (var n = 1; n <= save.unlocked + 1; n++)
              _tile(context, n, locked: n > save.unlocked),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, int n, {required bool locked}) {
    final r = save.records[n];
    final rules = Rules.forNight(n);
    final parts = [
      'espantar ${rules.repelsToWin}×',
      if (r != null && r.wins > 0) '${r.wins} vitória${r.wins > 1 ? 's' : ''}',
      if (r?.bestTime case final b?) 'melhor ${clock(b)}',
      if (r != null && r.deaths > 0)
        '${r.deaths} morte${r.deaths > 1 ? 's' : ''}',
    ];
    return ListTile(
      enabled: !locked,
      leading: CircleAvatar(
        backgroundColor: locked ? Colors.white10 : const Color(0x33E8DFC8),
        child: locked
            ? const Icon(Icons.lock, size: 18, color: Colors.white38)
            : Text('$n', style: const TextStyle(color: bone)),
      ),
      title: Text('Noite $n'),
      subtitle: Text(
        locked ? 'Vença a noite ${n - 1} para liberar' : parts.join(' · '),
      ),
      trailing: Rules.novelty(n) != null && !locked
          ? const Icon(Icons.new_releases_outlined, color: Colors.white38)
          : null,
      onTap: locked
          ? null
          : () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    StoryScreen(save: save, night: n, useSensors: useSensors),
              ),
            ),
    );
  }
}

/// O trecho da história antes da noite, escrito aos poucos.
class StoryScreen extends StatefulWidget {
  const StoryScreen({
    super.key,
    required this.save,
    required this.night,
    this.useSensors = true,
  });

  final Save save;
  final int night;
  final bool useSensors;

  @override
  State<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends State<StoryScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final String _text = storyFor(widget.night);
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) {
      final n = max(_shown, min(_text.length, d.inMilliseconds ~/ 28));
      if (n != _shown) setState(() => _shown = n);
      if (n >= _text.length) _ticker.stop();
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _start() => Navigator.pushReplacement(
    context,
    MaterialPageRoute(
      builder: (_) => GameScreen(
        save: widget.save,
        night: widget.night,
        useSensors: widget.useSensors,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final novelty = Rules.novelty(widget.night);
    final done = _shown >= _text.length;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Tocar mostra o texto inteiro de uma vez.
        onTap: () => setState(() => _shown = _text.length),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                Text(
                  'NOITE ${widget.night}',
                  style: const TextStyle(
                    color: Colors.white38,
                    letterSpacing: 6,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _text.substring(0, _shown),
                  style: const TextStyle(
                    color: bone,
                    fontSize: 18,
                    height: 1.5,
                  ),
                ),
                if (novelty != null && done) ...[
                  const SizedBox(height: 24),
                  Text(
                    novelty,
                    style: const TextStyle(
                      color: Color(0xFFFFB35C),
                      height: 1.4,
                    ),
                  ),
                ],
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _start,
                    child: Text('Começar a noite ${widget.night}'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Som, vibração, câmera e giro.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.save});

  final Save save;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: save,
      builder: (context, _) {
        final s = save.settings;
        void set(void Function() change) {
          change();
          save.store();
        }

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            title: const Text('Configurações'),
          ),
          body: ListView(
            children: [
              const _Header('Som'),
              ListTile(
                title: const Text('Volume'),
                subtitle: Slider(
                  value: s.volume,
                  onChanged: (v) => set(() => s.volume = v),
                ),
              ),
              SwitchListTile(
                title: const Text('Som 3D (com fone)'),
                subtitle: const Text(
                  'Dá para ouvir se ele está na frente ou atrás. '
                  'Sem fone, desligue: fica só esquerda e direita.',
                ),
                value: s.sound3d,
                onChanged: (v) => set(() => s.sound3d = v),
              ),
              SwitchListTile(
                title: const Text('Vibração'),
                subtitle: const Text('Passos, corrida e choque no corpo.'),
                value: s.vibration,
                onChanged: (v) => set(() => s.vibration = v),
              ),
              const _Header('Câmera'),
              SwitchListTile(
                title: const Text('Ver o quarto pela câmera'),
                subtitle: const Text(
                  'E a lanterna do celular acende junto. Desligado, '
                  'o quarto é desenhado.',
                ),
                value: s.camera,
                onChanged: (v) => set(() => s.camera = v),
              ),
              const _Header('Giro'),
              ListTile(
                title: const Text('Sensibilidade'),
                subtitle: Slider(
                  value: s.sensitivity,
                  min: 0.5,
                  max: 2,
                  divisions: 6,
                  label: '${s.sensitivity.toStringAsFixed(2)}×',
                  onChanged: (v) => set(() => s.sensitivity = v),
                ),
              ),
              SwitchListTile(
                title: const Text('Inverter o giro'),
                subtitle: const Text(
                  'Se virar para a esquerda leva a imagem para o lado errado.',
                ),
                value: s.invertTurn,
                onChanged: (v) => set(() => s.invertTurn = v),
              ),
              SwitchListTile(
                title: const Text('Jogar sentado'),
                subtitle: const Text(
                  'Sem giroscópio: arraste na tela para olhar em volta.',
                ),
                value: s.dragOnly,
                onChanged: (v) => set(() => s.dragOnly = v),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(color: Colors.white38, letterSpacing: 2),
    ),
  );
}

/// O diário (a história e o que se achou a cada manhã) e as conquistas.
class JournalScreen extends StatelessWidget {
  const JournalScreen({super.key, required this.save});

  final Save save;

  @override
  Widget build(BuildContext context) {
    // Noites vencidas: as anteriores à liberada.
    final won = [for (var n = 1; n < save.unlocked; n++) n];
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text('Diário e conquistas'),
          bottom: TabBar(
            tabs: [
              const Tab(text: 'Diário'),
              Tab(
                text:
                    'Conquistas ${save.unlockedAchievements.length}/'
                    '${achievements.length}',
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            won.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Ainda nada. Sobreviva a uma noite e veja o que '
                        'aparece de manhã.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      for (final n in won) ...[
                        Text(
                          'NOITE $n',
                          style: const TextStyle(
                            color: Colors.white38,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          storyFor(n),
                          style: const TextStyle(color: bone, height: 1.5),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0x44E8DFC8)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.push_pin_outlined,
                                size: 18,
                                color: Colors.white38,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  foundAfter(n),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontStyle: FontStyle.italic,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                      ],
                    ],
                  ),
            ListView(
              children: [
                for (final a in achievements)
                  Builder(
                    builder: (context) {
                      final got = save.unlockedAchievements.contains(a.id);
                      return ListTile(
                        leading: Icon(
                          got ? Icons.military_tech : Icons.lock_outline,
                          color: got ? bone : Colors.white24,
                        ),
                        title: Text(
                          a.title,
                          style: TextStyle(
                            color: got ? Colors.white : Colors.white38,
                          ),
                        ),
                        subtitle: Text(a.description),
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

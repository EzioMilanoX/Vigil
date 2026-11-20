import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_screen.dart';

/// A tela de início: como jogar e de qual noite começar.
class TitleScreen extends StatefulWidget {
  const TitleScreen({
    super.key,
    this.useGyroscope = true,
    this.useSound = true,
    this.useCamera = true,
  });

  final bool useGyroscope;
  final bool useSound;
  final bool useCamera;

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen> {
  static const _key = 'noite_liberada';

  /// A maior noite que já dá para jogar (a seguinte à última vencida).
  var _unlocked = 1;
  var _night = 1;
  late var _useCamera = widget.useCamera;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final n = prefs.getInt(_key) ?? 1;
      if (mounted) setState(() => _unlocked = _night = n);
    } catch (_) {
      // Sem onde guardar: começa da noite 1.
    }
  }

  Future<void> _won(int night) async {
    if (night + 1 <= _unlocked) return;
    setState(() => _unlocked = _night = night + 1);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, _unlocked);
    } catch (_) {}
  }

  void _start() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => GameScreen(
        night: _night,
        onWon: _won,
        useGyroscope: widget.useGyroscope,
        useSound: widget.useSound,
        useCamera: _useCamera,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    const dim = TextStyle(color: Colors.white54, height: 1.5);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              const Text(
                'VIGIL',
                style: TextStyle(
                  color: Color(0xFFE8DFC8),
                  fontSize: 48,
                  letterSpacing: 12,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tem um manequim no seu quarto. Ele anda em volta de você.',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 20),
              const _Hint(
                Icons.headphones,
                'Use fone. Os passos dizem de que lado ele vem.',
              ),
              const _Hint(
                Icons.screen_rotation,
                'Fique em pé e vire o corpo com o celular para procurá-lo.',
              ),
              const _Hint(
                Icons.blur_on,
                'Às vezes ele some. Se a tela chiar, ele está ali: segure a lanterna em cima.',
              ),
              const _Hint(
                Icons.bolt,
                'Quando ele correr, espere chegar perto e dê o choque. Cedo demais não pega.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Espante-o algumas vezes e ele desiste até amanhecer. Mas nem todo chiado é ele.',
                style: dim,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _useCamera,
                onChanged: (v) => setState(() => _useCamera = v),
                title: const Text(
                  'Ver o quarto pela câmera',
                  style: TextStyle(color: Colors.white70),
                ),
                subtitle: const Text(
                  'E a lanterna do celular acende junto.',
                  style: TextStyle(color: Colors.white38),
                ),
              ),
              const Spacer(),
              if (_unlocked > 1)
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Noite anterior',
                      onPressed: _night > 1
                          ? () => setState(() => _night--)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text(
                      'Noite $_night',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    IconButton(
                      tooltip: 'Próxima noite',
                      onPressed: _night < _unlocked
                          ? () => setState(() => _night++)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _start,
                  child: Text(
                    _night == 1 ? 'Começar' : 'Começar a noite $_night',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.white38, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.white54, height: 1.4),
          ),
        ),
      ],
    ),
  );
}

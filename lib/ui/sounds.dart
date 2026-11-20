import 'package:audioplayers/audioplayers.dart';

import '../game/vigil_game.dart';

/// Os sons da noite, com o lado (pan) de onde vêm. Com fone, é a pista principal.
class Sounds {
  final _vivos = <AudioPlayer>{};
  AudioPlayer? _chiado;
  double _chiadoVol = -1;

  Future<void> cue(Cue c) {
    final (asset, volume) = switch (c.kind) {
      CueKind.arrive => ('sons/rangido.wav', 0.7),
      CueKind.step => ('sons/passo.wav', 0.6),
      CueKind.charge => ('sons/grito.wav', 0.45),
      CueKind.hit => ('sons/choque.wav', 1.0),
      CueKind.miss => ('sons/choque.wav', 0.35),
    };
    final centered = c.kind == CueKind.hit || c.kind == CueKind.miss;
    return _play(
      asset,
      balance: centered ? 0 : c.pan,
      volume: volume,
      // Atrás de você soa mais grave, para distinguir de "na frente".
      rate: c.behind && !centered ? 0.85 : 1,
    );
  }

  Future<void> heartbeat(double loudness) =>
      _play('sons/coracao.wav', volume: loudness.clamp(0.1, 1.0));

  Future<void> scream() => _play('sons/grito.wav', volume: 1, rate: 0.9);

  /// O chiado contínuo, no volume do quanto você olha para ele invisível.
  Future<void> staticLevel(double level) async {
    final v = (level * 0.7).clamp(0.0, 0.7);
    if ((v - _chiadoVol).abs() < 0.04) return;
    _chiadoVol = v;
    try {
      if (_chiado == null) {
        if (v <= 0) return;
        final p = _chiado = AudioPlayer();
        await p.setReleaseMode(ReleaseMode.loop);
        await p.setVolume(v);
        await p.play(AssetSource('sons/chiado.wav'));
      } else {
        await _chiado!.setVolume(v);
      }
    } catch (_) {}
  }

  Future<void> _play(
    String asset, {
    double balance = 0,
    double volume = 1,
    double rate = 1,
  }) async {
    final p = AudioPlayer();
    _vivos.add(p);
    p.onPlayerComplete.listen((_) => _soltar(p));
    try {
      await p.setReleaseMode(ReleaseMode.stop);
      await p.setVolume(volume);
      await p.setBalance(balance);
      if (rate != 1) await p.setPlaybackRate(rate);
      await p.play(AssetSource(asset));
    } catch (_) {
      // Sem áudio (ou sem pan nesta plataforma): o jogo segue com a vibração.
      _soltar(p);
    }
  }

  void _soltar(AudioPlayer p) {
    if (_vivos.remove(p)) p.dispose();
  }

  void dispose() {
    _chiado?.dispose();
    _chiado = null;
    for (final p in _vivos) {
      p.dispose();
    }
    _vivos.clear();
  }
}

import 'dart:math';

import 'package:audioplayers/audioplayers.dart';

import '../game/vigil_game.dart';

/// Um som em loop (chiado, zumbido) cujo volume e lado mudam a cada quadro.
class _Loop {
  _Loop(this.asset);
  final String asset;
  AudioPlayer? _p;
  double _vol = -1;
  double _pan = 9;

  Future<void> set(double volume, {double pan = 0}) async {
    if ((volume - _vol).abs() < 0.04 && (pan - _pan).abs() < 0.08) return;
    _vol = volume;
    _pan = pan;
    try {
      if (_p == null) {
        if (volume <= 0) return;
        final p = _p = AudioPlayer();
        await p.setReleaseMode(ReleaseMode.loop);
        await p.setVolume(volume);
        await p.setBalance(pan);
        await p.play(AssetSource(asset));
      } else {
        await _p!.setVolume(volume);
        await _p!.setBalance(pan);
      }
    } catch (_) {}
  }

  void dispose() {
    _p?.dispose();
    _p = null;
  }
}

/// Os sons da noite, com o lado (pan) de onde vêm. Com fone, é a pista principal.
class Sounds {
  Sounds({this.volume = 1, this.binaural = true});

  /// O volume geral (configurações).
  final double volume;

  /// Som 3D (fone): toca a versão já espacializada da direção mais próxima,
  /// que diz também se é na frente ou atrás. Desligado: só esquerda/direita.
  final bool binaural;

  /// Os sons que têm versão 3D em assets/sons/3d (8 direções).
  static const _with3d = {'passo', 'rangido', 'grito', 'batida', 'zumbido'};

  /// A direção mais próxima, em graus, entre as 8 gravadas.
  static int direction(double angle) {
    final a = ((angle % tau) + tau) % tau;
    return ((a / (pi / 4)).round() % 8) * 45;
  }

  final _vivos = <AudioPlayer>{};
  final _chiado = _Loop('sons/chiado.wav');
  final _zumbido = _Loop('sons/zumbido.wav');

  Future<void> cue(Cue c) {
    final (asset, vol, centered) = switch (c.kind) {
      CueKind.arrive => ('sons/rangido.wav', 0.7, false),
      CueKind.step => ('sons/passo.wav', 0.6, false),
      CueKind.charge => ('sons/grito.wav', 0.45, false),
      CueKind.feint => ('sons/rangido.wav', 0.5, false),
      CueKind.hit => ('sons/choque.wav', 1.0, true),
      CueKind.miss => ('sons/choque.wav', 0.35, true),
      CueKind.knock => ('sons/batida.wav', 0.8, false),
      CueKind.shadow => ('sons/passo.wav', 0.3, false),
      CueKind.buzz => ('sons/zumbido.wav', c.near ? 0.9 : 0.5, false),
    };
    final name = asset.substring(5, asset.length - 4);
    if (binaural && !centered && _with3d.contains(name)) {
      final g = direction(c.angle).toString().padLeft(3, '0');
      return _play('sons/3d/${name}_$g.wav', volume: vol);
    }
    return _play(
      asset,
      balance: centered ? 0 : c.pan,
      volume: vol,
      // Atrás de você soa mais grave, para distinguir de "na frente".
      rate: c.behind && !centered ? 0.85 : 1,
    );
  }

  Future<void> heartbeat(double loudness) =>
      _play('sons/coracao.wav', volume: loudness.clamp(0.1, 1.0));

  Future<void> scream() => _play('sons/grito.wav', volume: 1, rate: 0.9);

  /// O chiado contínuo, no volume do quanto você olha para ele invisível.
  void staticLevel(double level) =>
      _chiado.set((level * 0.7 * volume).clamp(0.0, 1.0));

  /// O zumbido da Mariposa, do lado em que ela está.
  void mothLevel(double level, double pan) =>
      _zumbido.set((level * level * 0.8 * volume).clamp(0.0, 1.0), pan: pan);

  void silence() {
    staticLevel(0);
    mothLevel(0, 0);
  }

  Future<void> _play(
    String asset, {
    double balance = 0,
    double volume = 1,
    double rate = 1,
  }) async {
    if (this.volume <= 0) return;
    final p = AudioPlayer();
    _vivos.add(p);
    p.onPlayerComplete.listen((_) => _soltar(p));
    try {
      await p.setReleaseMode(ReleaseMode.stop);
      await p.setVolume((volume * this.volume).clamp(0.0, 1.0));
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
    _chiado.dispose();
    _zumbido.dispose();
    for (final p in _vivos) {
      p.dispose();
    }
    _vivos.clear();
  }
}

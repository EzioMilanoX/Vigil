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
  static const _with3d = {
    'passo',
    'rangido',
    'grito',
    'batida',
    'zumbido',
    'respiro',
  };

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
      CueKind.breath => ('sons/respiro.wav', 1.0, false),
      CueKind.blackout => ('sons/apagao.wav', 0.9, true),
      CueKind.face => ('sons/rosto.wav', 0.75, true),
      CueKind.offbeat => ('sons/passo.wav', 0.5, false),
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

  /// O susto de quando ele pega (o grito em camadas, alto).
  Future<void> scream() => _play('sons/susto.wav', volume: 1);

  /// O chiado contínuo, no volume do quanto você olha para ele invisível.
  void staticLevel(double level) =>
      _chiado.set((level * 0.7 * volume).clamp(0.0, 1.0));

  /// O zumbido da Mariposa, do lado em que ela está.
  void mothLevel(double level, double pan) =>
      _zumbido.set((level * level * 0.8 * volume).clamp(0.0, 1.0), pan: pan);

  /// Corta tudo o que está tocando (o silêncio antes do susto).
  void hush() {
    silence();
    for (final p in _vivos) {
      p.dispose();
    }
    _vivos.clear();
  }

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

/// A música da noite "A canção": duas faixas com as mesmas notas nos mesmos
/// tempos (a caixinha e a versão desafinada) tocando juntas em loop. Ele
/// perto: mais rápida e mais torta.
class SongPlayer {
  SongPlayer({this.volume = 1});

  /// O volume geral (configurações). A música fica baixa: as pistas de som
  /// do jogo vêm primeiro.
  final double volume;

  static const clean = 'musica/cancao.wav';
  static const bent = 'musica/cancao_torta.wav';

  final _clean = AudioPlayer();
  final _bent = AudioPlayer();
  double _rate = 1;
  double _detune = -1;
  bool _started = false;
  bool _loaded = false;

  /// Prepara e começa as duas juntas, do começo (também no "De novo").
  /// Devolve se tocou.
  Future<bool> start() async {
    if (volume <= 0) return false;
    try {
      if (_loaded) {
        await Future.wait([
          _clean.seek(Duration.zero),
          _bent.seek(Duration.zero),
        ]);
      } else {
        for (final (p, asset) in [(_clean, clean), (_bent, bent)]) {
          await p.setReleaseMode(ReleaseMode.loop);
          await p.setSource(AssetSource(asset));
        }
        _loaded = true;
      }
      await mix(1, 0);
      await Future.wait([_clean.resume(), _bent.resume()]);
      _started = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// O andamento ([rate], 1 = normal) e o quanto a torta toma conta (0 a 1).
  Future<void> mix(double rate, double detune) async {
    try {
      if ((rate - _rate).abs() >= 0.01) {
        _rate = rate;
        await Future.wait([
          _clean.setPlaybackRate(rate),
          _bent.setPlaybackRate(rate),
        ]);
      }
      if ((detune - _detune).abs() >= 0.03) {
        _detune = detune;
        final v = 0.45 * volume;
        await Future.wait([
          _clean.setVolume((v * (1 - detune)).clamp(0.0, 1.0)),
          _bent.setVolume((v * (0.08 + 0.92 * detune)).clamp(0.0, 1.0)),
        ]);
      }
    } catch (_) {}
  }

  /// Onde a música está, em segundos (null: sem áudio). Se a torta escorregou
  /// mais de 60 ms, puxa ela de volta para a limpa.
  Future<double?> position() async {
    if (!_started) return null;
    try {
      final a = await _clean.getCurrentPosition();
      if (a == null) return null;
      final b = await _bent.getCurrentPosition();
      if (b != null && (a - b).inMilliseconds.abs() > 60) await _bent.seek(a);
      return a.inMicroseconds / 1e6;
    } catch (_) {
      return null;
    }
  }

  Future<void> pause() async {
    try {
      await Future.wait([_clean.pause(), _bent.pause()]);
    } catch (_) {}
  }

  Future<void> resume() async {
    if (!_started) return;
    try {
      await Future.wait([_clean.resume(), _bent.resume()]);
    } catch (_) {}
  }

  Future<void> stop() async {
    _started = false;
    try {
      await Future.wait([_clean.stop(), _bent.stop()]);
    } catch (_) {}
  }

  void dispose() {
    _started = false;
    _clean.dispose();
    _bent.dispose();
  }
}

import 'dart:convert';
import 'dart:math';

/// O número da noite extra "A canção" (SEN-06 L.U.L.L.A.B.Y.). Fica fora da
/// contagem: vencê-la não libera noite nenhuma.
const songNight = 0;

/// Liberada depois de vencer esta noite.
const songUnlockedAfter = 4;

/// As batidas de uma música que toca em loop: tempos em segundos dentro de
/// `[0, length)`. A batida `i` (global, conta através dos loops) cai em
/// [timeOf]. Feita a partir do JSON de `tools/gerar_batidas.py`.
class BeatMap {
  BeatMap(Iterable<double> beats, {required this.length})
    : beats = List.unmodifiable(
        beats.where((b) => b >= 0 && b < length).toList()..sort(),
      ) {
    if (this.beats.isEmpty || length <= 0) {
      throw const FormatException('A música precisa de batidas e duração.');
    }
  }

  /// Uma batida a cada `60 / bpm` s: o reserva quando o JSON não carrega.
  factory BeatMap.metronome({double bpm = 72, int count = 48}) {
    final beat = 60 / bpm;
    return BeatMap([
      for (var i = 0; i < count; i++) i * beat,
    ], length: count * beat);
  }

  /// `{"length": 40.0, "beats": [0.0, 0.83, ...]}` (ou só a lista; aí a
  /// duração é a última batida mais o intervalo médio).
  factory BeatMap.parse(String source) {
    final j = jsonDecode(source);
    final list = j is Map ? j['beats'] : j;
    if (list is! List || list.isEmpty) {
      throw const FormatException('Sem a lista "beats".');
    }
    final beats = [for (final b in list) (b as num).toDouble()]..sort();
    var length = j is Map ? (j['length'] as num?)?.toDouble() : null;
    if (length == null) {
      final gap = beats.length > 1
          ? (beats.last - beats.first) / (beats.length - 1)
          : 1.0;
      length = beats.last + gap;
    }
    return BeatMap(beats, length: length);
  }

  final List<double> beats;

  /// A duração do loop, em segundos.
  final double length;

  int get perLoop => beats.length;

  /// Quando cai a batida global [i] (pode ser negativa: loops antes do 0).
  double timeOf(int i) {
    final loop = (i / perLoop).floor();
    return loop * length + beats[i - loop * perLoop];
  }

  /// A última batida em [t] ou antes.
  int indexAt(double t) {
    final loop = (t / length).floor();
    final local = t - loop * length;
    var count = 0;
    while (count < perLoop && beats[count] <= local) {
      count++;
    }
    return loop * perLoop + count - 1;
  }

  /// A batida mais perto de [t].
  int nearest(double t) {
    final i = indexAt(t);
    return t - timeOf(i) <= timeOf(i + 1) - t ? i : i + 1;
  }
}

/// O relógio da canção. Anda com o tempo do jogo vezes o [tempo] (a música
/// acelera com ele perto) e é puxado para a posição real do áudio por
/// [sync]: quem manda é o som. Tudo em Dart puro e determinístico.
class SongClock {
  SongClock(this.map, {this.window = 0.08})
    : _last = map.indexAt(-1e-9),
      _lastAt = 0;

  final BeatMap map;

  /// Meia janela do "no tempo", em segundos reais (±80 ms).
  final double window;

  /// Onde a música está, em segundos da música (não volta no loop).
  double time = 0;

  /// O andamento: 1 = normal, 1,3 = 30% mais rápida.
  double tempo = 1;

  int _last;
  double _lastAt;

  /// A última batida que já passou (global).
  int get beat => _last;

  /// Segundos reais desde a última batida (para o pulso na borda).
  double get sinceBeat => max(0, (time - _lastAt) / tempo);

  /// Segundos reais entre a última batida e a próxima.
  double get period => (map.timeOf(_last + 1) - map.timeOf(_last)) / tempo;

  /// Segundos reais até (negativo) ou desde (positivo) a batida mais perto.
  double get offset {
    final i = map.nearest(time);
    return (time - map.timeOf(i)) / tempo;
  }

  /// Agora está dentro da janela de uma batida?
  bool get inWindow => offset.abs() <= window;

  /// Anda [dt] segundos reais. Devolve as batidas que passaram (normalmente
  /// nenhuma ou uma).
  List<int> advance(double dt) {
    if (dt > 0) time += dt * tempo;
    final now = map.indexAt(time);
    if (now <= _last) return const [];
    final crossed = [for (var i = _last + 1; i <= now; i++) i];
    _last = now;
    _lastAt = map.timeOf(now);
    return crossed;
  }

  /// O áudio está em [position] (segundos dentro do loop, já descontado o
  /// atraso do som). Diferença pequena: puxa metade do caminho (sem pular
  /// batida nem repetir). Grande (travou, voltou do pause): pula direto, sem
  /// disparar as batidas do meio.
  void sync(double position) {
    final l = map.length;
    final local = time - (time / l).floor() * l;
    var d = (position - local) % l;
    if (d > l / 2) d -= l;
    if (d.abs() > 0.25) {
      time += d;
      _last = map.indexAt(time);
      _lastAt = map.timeOf(_last);
    } else {
      time += d * 0.5;
    }
  }
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/achievements.dart';

/// O que dá para ajustar no menu de configurações.
class Settings {
  double volume = 1;
  bool vibration = true;
  bool camera = true;

  /// Multiplica o giro (1 = o corpo vira o mesmo que a tela).
  double sensitivity = 1;
  bool invertTurn = false;

  /// Jogar sentado: sem giroscópio, só arrastando.
  bool dragOnly = false;

  /// Som 3D para fone (frente e trás, não só esquerda e direita).
  bool sound3d = true;

  Map<String, Object> toJson() => {
    'volume': volume,
    'vibration': vibration,
    'camera': camera,
    'sensitivity': sensitivity,
    'invertTurn': invertTurn,
    'dragOnly': dragOnly,
    'sound3d': sound3d,
  };

  void load(Map<String, dynamic> j) {
    volume = (j['volume'] as num?)?.toDouble() ?? volume;
    vibration = j['vibration'] as bool? ?? vibration;
    camera = j['camera'] as bool? ?? camera;
    sensitivity = (j['sensitivity'] as num?)?.toDouble() ?? sensitivity;
    invertTurn = j['invertTurn'] as bool? ?? invertTurn;
    dragOnly = j['dragOnly'] as bool? ?? dragOnly;
    sound3d = j['sound3d'] as bool? ?? sound3d;
  }
}

/// O histórico de uma noite.
class NightRecord {
  int wins = 0;
  int deaths = 0;

  /// O amanhecer mais rápido, em segundos.
  double? bestTime;

  Map<String, Object?> toJson() => {
    'wins': wins,
    'deaths': deaths,
    'bestTime': bestTime,
  };

  static NightRecord fromJson(Map<String, dynamic> j) => NightRecord()
    ..wins = j['wins'] as int? ?? 0
    ..deaths = j['deaths'] as int? ?? 0
    ..bestTime = (j['bestTime'] as num?)?.toDouble();
}

/// O progresso do jogador: noite liberada, recordes, configurações. Guarda
/// tudo num JSON só; sem onde guardar (testes), fica só na memória.
class Save extends ChangeNotifier {
  Save({this.persist = true});

  static const _key = 'vigil_save_v1';
  final bool persist;

  int unlocked = 1;
  int totalRepels = 0;
  bool tutorialDone = false;
  final unlockedAchievements = <String>{};
  final settings = Settings();
  final records = <int, NightRecord>{};

  NightRecord recordOf(int night) =>
      records.putIfAbsent(night, NightRecord.new);

  Future<void> load() async {
    if (!persist) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) {
        // A 0.1.0 só guardava a noite liberada.
        unlocked = prefs.getInt('noite_liberada') ?? 1;
        return;
      }
      final j = jsonDecode(raw) as Map<String, dynamic>;
      unlocked = j['unlocked'] as int? ?? 1;
      totalRepels = j['totalRepels'] as int? ?? 0;
      tutorialDone = j['tutorialDone'] as bool? ?? false;
      unlockedAchievements.addAll([
        for (final a in j['achievements'] as List? ?? const []) '$a',
      ]);
      settings.load(j['settings'] as Map<String, dynamic>? ?? const {});
      final recs = j['records'] as Map<String, dynamic>? ?? const {};
      for (final e in recs.entries) {
        records[int.parse(e.key)] = NightRecord.fromJson(
          e.value as Map<String, dynamic>,
        );
      }
    } catch (_) {
      // Save corrompido: começa do zero, sem travar o jogo.
    }
    notifyListeners();
  }

  Future<void> store() async {
    notifyListeners();
    if (!persist) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'unlocked': unlocked,
          'totalRepels': totalRepels,
          'tutorialDone': tutorialDone,
          'achievements': unlockedAchievements.toList()..sort(),
          'settings': settings.toJson(),
          'records': {
            for (final e in records.entries) '${e.key}': e.value.toJson(),
          },
        }),
      );
    } catch (_) {}
  }

  /// Guarda o fim de uma noite e devolve as conquistas novas.
  Future<List<Achievement>> finish(NightResult r) async {
    if (r.won) {
      final rec = recordOf(r.night);
      rec.wins++;
      if (rec.bestTime == null || r.time < rec.bestTime!) rec.bestTime = r.time;
      if (r.night + 1 > unlocked) unlocked = r.night + 1;
    } else {
      recordOf(r.night).deaths++;
    }
    totalRepels += r.repels;
    final novas = unlock(earnedBy(r, totalRepels: totalRepels));
    await store();
    return novas;
  }

  /// Marca conquistas; devolve só as que ainda não tinha.
  List<Achievement> unlock(Iterable<String> ids) => [
    for (final id in ids)
      if (unlockedAchievements.add(id)) ?achievementById(id),
  ];

  Future<void> won(int night, double time, int repels) {
    final r = recordOf(night);
    r.wins++;
    if (r.bestTime == null || time < r.bestTime!) r.bestTime = time;
    totalRepels += repels;
    if (night + 1 > unlocked) unlocked = night + 1;
    return store();
  }

  Future<void> lost(int night, int repels) {
    recordOf(night).deaths++;
    totalRepels += repels;
    return store();
  }
}

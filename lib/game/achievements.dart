/// Uma conquista: o id fica no save; título e descrição aparecem no diário.
class Achievement {
  const Achievement(this.id, this.title, this.description);
  final String id;
  final String title;
  final String description;
}

const achievements = [
  Achievement('treino', 'Aprendiz', 'Terminar o treino.'),
  Achievement('noite1', 'Primeira vigília', 'Sobreviver à noite 1.'),
  Achievement(
    'perfeito',
    'Choque perfeito',
    'Acertar o choque com ele quase encostando em você.',
  ),
  Achievement(
    'frio',
    'Sangue frio',
    'Sobreviver a uma noite sem errar nenhum choque.',
  ),
  Achievement(
    'escuro',
    'Olhos fechados',
    'Sobreviver a uma noite com menos de 12 segundos de lanterna.',
  ),
  Achievement('mariposa', 'Apaga a luz', 'Sobreviver à noite 4.'),
  Achievement('cacador', 'Ateliê fechado', 'Espantar o manequim 30 vezes.'),
  Achievement('semana', 'Uma semana em claro', 'Sobreviver à noite 7.'),
];

Achievement? achievementById(String id) {
  for (final a in achievements) {
    if (a.id == id) return a;
  }
  return null;
}

/// O que aconteceu numa noite, para o recorde e as conquistas.
class NightResult {
  const NightResult({
    required this.night,
    required this.won,
    required this.time,
    required this.repels,
    this.lanternTime = 0,
    this.misses = 0,
    this.perfectHits = 0,
  });

  final int night;
  final bool won;
  final double time;
  final int repels;

  /// Segundos de lanterna acesa.
  final double lanternTime;

  /// Choques que saíram no vazio.
  final int misses;

  /// Choques com ele quase encostando.
  final int perfectHits;
}

/// As conquistas que esta noite garante (as já ganhas o save filtra).
Set<String> earnedBy(NightResult r, {required int totalRepels}) => {
  if (r.perfectHits > 0) 'perfeito',
  if (r.won && r.night == 1) 'noite1',
  if (r.won && r.misses == 0) 'frio',
  if (r.won && r.lanternTime < 12) 'escuro',
  if (r.won && r.night == 4) 'mariposa',
  if (r.won && r.night == 7) 'semana',
  if (totalRepels >= 30) 'cacador',
};

import 'route_models.dart';

enum DifficultyLevel { easy, moderate, challenging, demanding }

extension DifficultyLevelX on DifficultyLevel {
  String get label => switch (this) {
        DifficultyLevel.easy => 'Enkel',
        DifficultyLevel.moderate => 'Middels',
        DifficultyLevel.challenging => 'Krevende',
        DifficultyLevel.demanding => 'Svært krevende',
      };
}

/// Transparent, explainable difficulty analysis for one stage.
class StageDifficulty {
  final DifficultyLevel level;

  /// 0-100 composite score from the documented scoring method.
  final double score;

  /// Human-readable factors that produced the rating.
  final List<String> factors;

  const StageDifficulty({
    required this.level,
    required this.score,
    this.factors = const [],
  });

  Map<String, dynamic> toJson() => {
        'level': level.name,
        'score': score,
        'factors': factors,
      };

  factory StageDifficulty.fromJson(Map<String, dynamic> j) => StageDifficulty(
        level: DifficultyLevel.values.asNameMap()[j['level']] ??
            DifficultyLevel.moderate,
        score: (j['score'] as num?)?.toDouble() ?? 0,
        factors:
            (j['factors'] as List? ?? []).map((e) => e.toString()).toList(),
      );
}

/// One day/stage of a multi-day trip.
class Stage {
  final String id;
  int number;
  DateTime? date;
  String startName;
  String endName;
  List<RoutePoint> points;
  double distanceMeters;
  double ascent;
  double descent;
  double? highestPoint;
  double estimatedMinutes;
  StageDifficulty? difficulty;
  List<String> challenges;

  Stage({
    required this.id,
    required this.number,
    this.date,
    this.startName = '',
    this.endName = '',
    this.points = const [],
    this.distanceMeters = 0,
    this.ascent = 0,
    this.descent = 0,
    this.highestPoint,
    this.estimatedMinutes = 0,
    this.difficulty,
    this.challenges = const [],
  });

  double get distanceKm => distanceMeters / 1000;

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'date': date?.toIso8601String(),
        'startName': startName,
        'endName': endName,
        'points': points.map((p) => p.toJson()).toList(),
        'distanceMeters': distanceMeters,
        'ascent': ascent,
        'descent': descent,
        'highestPoint': highestPoint,
        'estimatedMinutes': estimatedMinutes,
        'difficulty': difficulty?.toJson(),
        'challenges': challenges,
      };

  factory Stage.fromJson(Map<String, dynamic> j) => Stage(
        id: j['id'] as String,
        number: j['number'] as int? ?? 1,
        date: j['date'] != null ? DateTime.tryParse(j['date']) : null,
        startName: j['startName'] as String? ?? '',
        endName: j['endName'] as String? ?? '',
        points: (j['points'] as List? ?? [])
            .map((p) => RoutePoint.fromJson(Map<String, dynamic>.from(p)))
            .toList(),
        distanceMeters: (j['distanceMeters'] as num?)?.toDouble() ?? 0,
        ascent: (j['ascent'] as num?)?.toDouble() ?? 0,
        descent: (j['descent'] as num?)?.toDouble() ?? 0,
        highestPoint: (j['highestPoint'] as num?)?.toDouble(),
        estimatedMinutes: (j['estimatedMinutes'] as num?)?.toDouble() ?? 0,
        difficulty: j['difficulty'] != null
            ? StageDifficulty.fromJson(
                Map<String, dynamic>.from(j['difficulty']))
            : null,
        challenges: (j['challenges'] as List? ?? [])
            .map((e) => e.toString())
            .toList(),
      );
}

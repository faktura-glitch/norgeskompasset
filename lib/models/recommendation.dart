enum RecommendationLevel { info, caution, serious }

extension RecommendationLevelX on RecommendationLevel {
  String get label => switch (this) {
    RecommendationLevel.info => 'Informasjon',
    RecommendationLevel.caution => 'Vær oppmerksom',
    RecommendationLevel.serious => 'Alvorlig – vurder tiltak',
  };
}

enum RecommendationStatus { active, dismissed, resolved }

/// A safety/prep recommendation tied to real trip data.
class Recommendation {
  final String id;
  final RecommendationLevel level;
  final String title;

  /// The observed condition that triggered this recommendation.
  final String observation;

  /// Why it matters for this trip.
  final String why;

  /// Practical action the user can take.
  final String action;

  /// Affected stage number, when identifiable.
  final int? stageNumber;

  /// Data source/freshness note, e.g. 'MET Norway, hentet 12:30'.
  final String? sourceNote;

  final DateTime createdAt;
  RecommendationStatus status;

  Recommendation({
    required this.id,
    required this.level,
    required this.title,
    required this.observation,
    required this.why,
    required this.action,
    this.stageNumber,
    this.sourceNote,
    DateTime? createdAt,
    this.status = RecommendationStatus.active,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'level': level.name,
    'title': title,
    'observation': observation,
    'why': why,
    'action': action,
    'stage': stageNumber,
    'sourceNote': sourceNote,
    'createdAt': createdAt.toIso8601String(),
    'status': status.name,
  };

  factory Recommendation.fromJson(Map<String, dynamic> j) => Recommendation(
    id: j['id'] as String,
    level:
        RecommendationLevel.values.asNameMap()[j['level']] ??
        RecommendationLevel.info,
    title: j['title'] as String? ?? '',
    observation: j['observation'] as String? ?? '',
    why: j['why'] as String? ?? '',
    action: j['action'] as String? ?? '',
    stageNumber: j['stage'] as int?,
    sourceNote: j['sourceNote'] as String?,
    createdAt: j['createdAt'] != null
        ? DateTime.tryParse(j['createdAt']) ?? DateTime.now()
        : DateTime.now(),
    status:
        RecommendationStatus.values.asNameMap()[j['status']] ??
        RecommendationStatus.active,
  );
}

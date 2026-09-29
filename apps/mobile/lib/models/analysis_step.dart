/// Status satu langkah analisis.
enum AnalysisStepState { waiting, process, done }

/// Fase real flow Hari 2B. Tidak ada fake progress/ETA.
enum AnalysisPhase {
  idle,
  validating,
  submitting,
  persisting,
  ready,
  requestError,
  persistenceError,
}

/// Satu langkah presentation untuk state yang benar-benar diketahui client.
class AnalysisStep {
  const AnalysisStep({
    required this.title,
    this.detail = '',
    this.state = AnalysisStepState.waiting,
  });

  final String title;
  final String detail;
  final AnalysisStepState state;

  AnalysisStep copyWith({
    String? title,
    String? detail,
    AnalysisStepState? state,
  }) =>
      AnalysisStep(
        title: title ?? this.title,
        detail: detail ?? this.detail,
        state: state ?? this.state,
      );

  factory AnalysisStep.fromMap(Map<String, Object?> m) => AnalysisStep(
        title: m['title']! as String,
        detail: (m['detail'] as String?) ?? '',
        state: AnalysisStepState.values.byName(
          (m['state'] as String?) ?? 'waiting',
        ),
      );

  Map<String, Object?> toMap() => {
        'title': title,
        'detail': detail,
        'state': state.name,
      };
}

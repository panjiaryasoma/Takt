/// Status satu langkah analisis.
enum AnalysisStepState { waiting, process, done }

/// Fase keseluruhan proses analisis AI.
enum AnalysisPhase { idle, running, done, error }

/// Satu langkah dalam pipeline analisis AI (mis. "Membaca sumber resmi").
/// Nanti diisi dari progress event AI model temanmu; sekarang bisa diisi
/// simulasi.
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

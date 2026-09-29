import '../../models/analysis_snapshot.dart';
import '../../models/competition_analysis_wire.dart';

abstract class AnalysisRepository {
  Future<void> initialize();

  Future<AnalysisSnapshot?> latestSnapshot(String competitionId);

  Future<List<AnalysisSnapshot>> snapshotsForCompetition(
    String competitionId,
  );

  Future<AnalysisSnapshot> persistResponse({
    required String originalBody,
    required CompetitionAnalyzeResponseWire response,
  });

  Future<void> close();
}

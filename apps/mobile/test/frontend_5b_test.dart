import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:takt_mobile/data/repositories/saved_plan_repository.dart';
import 'package:takt_mobile/models/active_accepted_block.dart';
import 'package:takt_mobile/models/enums.dart';
import 'package:takt_mobile/models/saved_plan.dart';
import 'package:takt_mobile/models/saved_plan_revision.dart';
import 'package:takt_mobile/screens/rencana_screen.dart';
import 'package:takt_mobile/screens/saved_plan_detail_screen.dart';
import 'package:takt_mobile/theme/app_theme.dart';
import 'package:takt_mobile/viewmodels/saved_plan_detail_view_model.dart';
import 'package:takt_mobile/viewmodels/saved_plans_view_model.dart';

void main() {
  testWidgets('persisted stale is presented as superseded, not session outdated',
      (tester) async {
    final summary = _summary(stale: true);
    final repository = _SavedPlanRepository(summary: summary);
    final vm = SavedPlansViewModel(repository, closeRepositoryOnDispose: false);
    addTearDown(vm.dispose);
    await vm.initialize();
    await Future<void>.delayed(Duration.zero);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: vm,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: RencanaScreen()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Accepted plan'), findsOneWidget);
    expect(find.text('SUPERSEDED'), findsOneWidget);
    expect(find.byKey(const Key('persisted-stale-summary')), findsOneWidget);
    expect(find.text('SESSION OUTDATED'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved plan detail separates persisted decision from stale source evaluation',
      (tester) async {
    final summary = _summary(stale: true);
    final repository = _SavedPlanRepository(
      summary: summary,
      detail: SavedPlanDetail(
        summary: summary,
        revisions: [summary.currentRevision],
        tasks: const [],
        acceptedCommitments: const [],
      ),
    );
    final vm = SavedPlanDetailViewModel(repository);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SavedPlanDetailScreen(
            savedPlanId: summary.plan.id,
            viewModel: vm,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('accepted-plan-label')), findsOneWidget);
    expect(find.byKey(const Key('persisted-evaluation-stale')), findsOneWidget);
    expect(find.textContaining('is not rewritten'), findsOneWidget);
    expect(find.text('SUPERSEDED'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Decision Report presentation does not parse raw request JSON', () {
    final source =
        File('lib/screens/rekomendasi_jadwal_screen.dart').readAsStringSync();
    expect(source, isNot(contains('jsonDecode(')));
    expect(source, isNot(contains('evaluationRequestJson')));
    expect(source, contains('Traceability & evaluation details'));
  });
}

SavedPlanSummary _summary({required bool stale}) {
  const now = 1790766000000;
  final plan = SavedPlan(
    id: 'plan-5b',
    competitionId: 'competition-5b',
    createdAtEpochMs: now,
    updatedAtEpochMs: now,
  );
  final revision = SavedPlanRevision(
    id: 'revision-5b',
    savedPlanId: plan.id,
    revisionNumber: 1,
    evaluationId: 'evaluation-5b',
    selectedCandidateId: 'candidate-001',
    selectionSource: SelectionSource.primary,
    acceptedAtEpochMs: now,
  );
  return SavedPlanSummary(
    plan: plan,
    currentRevision: revision,
    title: 'Shipaton',
    deadline: DateTime.fromMillisecondsSinceEpoch(now + 86400000),
    stale: stale,
  );
}

final class _SavedPlanRepository implements SavedPlanRepository {
  _SavedPlanRepository({
    required this.summary,
    this.detail,
  });

  final SavedPlanSummary summary;
  final SavedPlanDetail? detail;

  @override
  Future<void> initialize() async {}

  @override
  Stream<List<SavedPlanSummary>> watchSummaries() =>
      Stream.value([summary]);

  @override
  Future<List<SavedPlanSummary>> listSummaries() async => [summary];

  @override
  Future<SavedPlanDetail?> loadDetail(String savedPlanId) async => detail;

  @override
  Future<SavedPlan?> planForCompetition(String competitionId) async =>
      summary.plan;

  @override
  Future<List<ActiveAcceptedBlock>> activeAcceptedBlocks({
    String? excludingSavedPlanId,
  }) async =>
      const [];

  @override
  Future<SavedPlanRevision> acceptEvaluation({
    required String evaluationId,
    required String candidateId,
    required SelectionSource selectionSource,
  }) {
    throw UnsupportedError('write not expected');
  }

  @override
  Future<void> updateTaskProgress({
    required String savedPlanTaskId,
    required int progressPercent,
    int? actualMinutes,
    bool clearActualMinutes = false,
  }) {
    throw UnsupportedError('write not expected');
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<void> close() async {}
}

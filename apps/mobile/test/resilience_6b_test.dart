import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takt_mobile/data/repositories/saved_plan_repository.dart';
import 'package:takt_mobile/models/recovery_policy.dart';
import 'package:takt_mobile/theme/app_theme.dart';
import 'package:takt_mobile/viewmodels/saved_plans_view_model.dart';
import 'package:takt_mobile/widgets/recovery_panel.dart';

void main() {
  testWidgets('RecoveryPanel stays actionable at 320px and 2x text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var retried = false;
    var secondary = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: RecoveryPanel(
                  descriptor: const RecoveryDescriptor(
                    title:
                        'A deliberately long recovery title that still has to remain usable',
                    message:
                        'The operation could not complete safely. Existing durable data remains unchanged while you choose an explicit recovery path.',
                    recoveryClass: RecoveryClass.retrySameInput,
                    technicalCode: 'CLIENT_CONNECTION_FAILED',
                    stage: 'transport',
                  ),
                  primaryLabel: 'Retry request',
                  onPrimary: () => retried = true,
                  secondaryLabel: 'Edit source',
                  onSecondary: () => secondary = true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('recovery-panel')), findsOneWidget);
    expect(find.text('Retry request'), findsOneWidget);
    expect(find.text('Edit source'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Retry request'));
    await tester.tap(find.text('Edit source'));
    expect(retried, isTrue);
    expect(secondary, isTrue);
  });

  test('unknown backend failure has no automatic recovery', () {
    const failure = FailureIdentity(
      code: 'FUTURE_BACKEND_CODE',
      stage: 'internal',
      statusCode: 503,
      origin: FailureOrigin.backend,
    );

    expect(
      RecoveryPolicy.classify(failure),
      RecoveryClass.noAutomaticRecovery,
    );
  });

  test('source and extraction failures map without inventing domain MISSING', () {
    const sourceUnavailable = FailureIdentity(
      code: 'SOURCE_FETCH_FAILED',
      stage: 'ingestion',
      statusCode: 502,
      origin: FailureOrigin.backend,
    );
    const invalidSource = FailureIdentity(
      code: 'INVALID_SOURCE',
      stage: 'ingestion',
      statusCode: 400,
      origin: FailureOrigin.backend,
    );
    const corruptPdf = FailureIdentity(
      code: 'NATIVE_EXTRACTION_FAILED',
      stage: 'extraction',
      statusCode: 422,
      origin: FailureOrigin.backend,
    );
    const ocrTimeout = FailureIdentity(
      code: 'OCR_TIMEOUT',
      stage: 'extraction',
      statusCode: 504,
      origin: FailureOrigin.backend,
    );

    expect(
      RecoveryPolicy.classify(sourceUnavailable),
      RecoveryClass.retrySameInput,
    );
    expect(
      RecoveryPolicy.classify(invalidSource),
      RecoveryClass.fixInput,
    );
    expect(
      RecoveryPolicy.classify(corruptPdf),
      RecoveryClass.reuploadSource,
    );
    expect(
      RecoveryPolicy.classify(ocrTimeout),
      RecoveryClass.retrySameInput,
    );
  });

  test('client transport timeout is retryable without becoming backend code', () {
    const failure = FailureIdentity(
      code: 'CLIENT_TIMEOUT',
      stage: 'transport',
      origin: FailureOrigin.clientTransport,
    );

    expect(
      RecoveryPolicy.classify(failure),
      RecoveryClass.retrySameInput,
    );
  });

  test('accepted read-model handoff refresh exposes failure without clearing state',
      () async {
    final repository = _ThrowingSavedPlanRepository();
    final vm = SavedPlansViewModel(
      repository,
      closeRepositoryOnDispose: false,
    );

    await expectLater(vm.refreshForHandoff(), throwsStateError);

    expect(vm.error, 'Saved plans could not be refreshed.');
    expect(vm.loading, isFalse);
    vm.dispose();
  });
}

final class _ThrowingSavedPlanRepository implements SavedPlanRepository {
  @override
  Future<List<SavedPlanSummary>> listSummaries() {
    throw StateError('simulated accepted read-model refresh failure');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'config/api_config.dart';
import 'data/database/app_database.dart';
import 'data/remote/competition_api_client.dart';
import 'data/remote/plan_api_client.dart';
import 'data/repositories/analysis_repository.dart';
import 'data/repositories/drift_analysis_repository.dart';
import 'data/repositories/drift_evaluation_repository.dart';
import 'data/repositories/drift_saved_plan_repository.dart';
import 'data/repositories/drift_schedule_repository.dart';
import 'data/repositories/evaluation_repository.dart';
import 'data/repositories/saved_plan_repository.dart';
import 'data/repositories/schedule_repository.dart';
import 'models/commitment.dart';
import 'models/analysis_step.dart';
import 'models/decision_intent.dart';
import 'models/evaluation_session.dart';
import 'models/recovery_policy.dart';
import 'widgets/recovery_panel.dart';
import 'monetization/revenuecat_bootstrap.dart';
import 'monetization/revenuecat_service.dart';
import 'screens/analisis_kompetisi_screen.dart';
import 'screens/home_screen.dart';
import 'screens/jadwal_harian_screen.dart';
import 'screens/jadwal_ringkasan_screen.dart';
import 'screens/planning_setup_screen.dart';
import 'screens/premium_access_screen.dart';
import 'screens/progres_analisis_screen.dart';
import 'screens/rencana_screen.dart';
import 'screens/rekomendasi_jadwal_screen.dart';
import 'screens/review_brief_screen.dart';
import 'screens/saved_plan_detail_screen.dart';
import 'screens/tambah_jadwal_screen.dart';
import 'theme/app_theme.dart';
import 'viewmodels/analisis_view_model.dart';
import 'viewmodels/jadwal_view_model.dart';
import 'viewmodels/planning_host_view_model.dart';
import 'viewmodels/saved_plan_detail_view_model.dart';
import 'viewmodels/saved_plans_view_model.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: C.bg,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: C.bg,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  final monetization = await bootstrapRevenueCat();
  if (monetization.configurationError != null) {
    debugPrint('RevenueCat disabled: ${monetization.configurationError}');
  }
  runApp(TaktApp(revenueCatService: monetization.service));
}

class TaktApp extends StatefulWidget {
  const TaktApp({
    super.key,
    this.database,
    this.scheduleRepository,
    this.analysisRepository,
    this.apiClient,
    this.planApiClient,
    this.evaluationRepository,
    this.savedPlanRepository,
    this.revenueCatService,
    this.decisionSession,
    this.currentInputRevision = 0,
    this.onAcceptCandidate,
    this.onEditConstraints,
    this.onIgnoreRecommendation,
  });

  final AppDatabase? database;
  final ScheduleRepository? scheduleRepository;
  final AnalysisRepository? analysisRepository;
  final CompetitionApiClient? apiClient;
  final PlanApiClient? planApiClient;
  final EvaluationRepository? evaluationRepository;
  final SavedPlanRepository? savedPlanRepository;
  final RevenueCatService? revenueCatService;

  /// Legacy 3B injection remains available for isolated component tests.
  /// Production navigation uses [PlanningHostViewModel].
  final EvaluationSession? decisionSession;
  final int currentInputRevision;
  final AcceptCandidateHandler? onAcceptCandidate;
  final ValueChanged<EditConstraintsIntent>? onEditConstraints;
  final ValueChanged<IgnoreRecommendationIntent>? onIgnoreRecommendation;

  @override
  State<TaktApp> createState() => _TaktAppState();
}

class _TaktAppState extends State<TaktApp> {
  AppDatabase? _ownedDatabase;
  late final ScheduleRepository _scheduleRepository;
  late final AnalysisRepository _analysisRepository;
  late final EvaluationRepository _evaluationRepository;
  late final SavedPlanRepository _savedPlanRepository;

  @override
  void initState() {
    super.initState();
    final needsDatabase = widget.scheduleRepository == null ||
        widget.analysisRepository == null ||
        widget.evaluationRepository == null ||
        widget.savedPlanRepository == null;
    if (needsDatabase && widget.database == null) {
      _ownedDatabase = AppDatabase.open();
    }
    final database = widget.database ?? _ownedDatabase;

    _scheduleRepository = widget.scheduleRepository ??
        DriftScheduleRepository(
          database!,
          closeDatabaseOnDispose: false,
        );
    _analysisRepository = widget.analysisRepository ??
        DriftAnalysisRepository(
          database!,
          closeDatabaseOnDispose: false,
        );
    _evaluationRepository = widget.evaluationRepository ??
        DriftEvaluationRepository(
          database!,
          closeDatabaseOnDispose: false,
        );
    _savedPlanRepository = widget.savedPlanRepository ??
        DriftSavedPlanRepository(
          database!,
          closeDatabaseOnDispose: false,
        );
  }

  @override
  void dispose() {
    final database = _ownedDatabase;
    if (database != null) {
      unawaited(database.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        if (widget.revenueCatService != null)
          ChangeNotifierProvider<RevenueCatService>.value(
            value: widget.revenueCatService!,
          ),
        ChangeNotifierProvider(
          create: (_) => JadwalViewModel(
            _scheduleRepository,
            savedPlanRepository: _savedPlanRepository,
            closeScheduleRepositoryOnDispose:
                widget.scheduleRepository == null,
            closeSavedPlanRepositoryOnDispose: false,
          )..initialize(),
        ),
        ChangeNotifierProvider(
          create: (_) => AnalisisViewModel(
            apiClient: widget.apiClient ??
                HttpCompetitionApiClient(baseUrl: ApiConfig.baseUrl),
            repository: _analysisRepository,
            closeRepositoryOnDispose: widget.analysisRepository == null,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => SavedPlansViewModel(
            _savedPlanRepository,
            closeRepositoryOnDispose: widget.savedPlanRepository == null,
          )..initialize(),
        ),
        ChangeNotifierProvider(
          create: (_) => SavedPlanDetailViewModel(_savedPlanRepository),
        ),
        ChangeNotifierProvider(
          create: (_) => PlanningHostViewModel(
            apiClient: widget.planApiClient ??
                HttpPlanApiClient(baseUrl: ApiConfig.baseUrl),
            scheduleRepository: _scheduleRepository,
            evaluationRepository: _evaluationRepository,
            savedPlanRepository: _savedPlanRepository,
            closeScheduleRepositoryOnDispose: false,
            closeEvaluationRepositoryOnDispose:
                widget.evaluationRepository == null,
            closeSavedPlanRepositoryOnDispose: false,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Takt',
        locale: const Locale('en'),
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: RootShell(
          revenueCatEnabled: widget.revenueCatService != null,
          decisionSession: widget.decisionSession,
          currentInputRevision: widget.currentInputRevision,
          onAcceptCandidate: widget.onAcceptCandidate,
          onEditConstraints: widget.onEditConstraints,
          onIgnoreRecommendation: widget.onIgnoreRecommendation,
        ),
      ),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({
    super.key,
    this.revenueCatEnabled = false,
    this.decisionSession,
    this.currentInputRevision = 0,
    this.onAcceptCandidate,
    this.onEditConstraints,
    this.onIgnoreRecommendation,
  });

  final bool revenueCatEnabled;
  final EvaluationSession? decisionSession;
  final int currentInputRevision;
  final AcceptCandidateHandler? onAcceptCandidate;
  final ValueChanged<EditConstraintsIntent>? onEditConstraints;
  final ValueChanged<IgnoreRecommendationIntent>? onIgnoreRecommendation;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _navIndex = 0;
  int _jadwalTab = 0;
  bool _showTambahJadwal = false;
  Commitment? _editingCommitment;
  int _analisisStep = 0;
  bool _addingSource = false;
  String? _selectedSavedPlanId;

  @override
  void initState() {
    super.initState();
    if (widget.decisionSession != null) {
      _navIndex = 2;
      _analisisStep = 3;
    }
  }

  @override
  void didUpdateWidget(covariant RootShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.decisionSession, widget.decisionSession)) {
      if (widget.decisionSession != null) {
        _navIndex = 2;
        _analisisStep = 3;
      } else if (_analisisStep == 3) {
        _analisisStep =
            context.read<AnalisisViewModel>().response == null ? 0 : 2;
      }
    }
  }

  void _backFromPlanningSetup() {
    final host = context.read<PlanningHostViewModel>();
    if (host.navigationLockedByPersistence || host.canRetryPersistence ||
        host.canRetryPublication) {
      return;
    }
    if (host.phase == PlanningHostPhase.requesting) {
      host.abandonRequest();
    }
    setState(() => _analisisStep = 2);
  }

  void _closeDecision() {
    if (widget.decisionSession == null) {
      context.read<PlanningHostViewModel>().leaveDecision();
    }
    setState(() {
      _analisisStep =
          context.read<AnalisisViewModel>().response == null ? 0 : 2;
    });
  }

  int _effectiveAnalysisStepFor(PlanningHostViewModel host) {
    final injected = widget.decisionSession != null;
    if (!injected &&
        host.phase == PlanningHostPhase.decision &&
        host.activeSession != null) {
      return 3;
    }
    return _analisisStep;
  }

  bool _hasSemanticBackTarget() {
    final analysis = context.watch<AnalisisViewModel>();
    final host = context.watch<PlanningHostViewModel>();
    if (analysis.canRetryPersistence || analysis.phase == AnalysisPhase.persisting ||
        host.canRetryPersistence || host.canRetryPublication ||
        host.hasPendingAcceptance || host.navigationLockedByPersistence) {
      return true;
    }
    if (_navIndex == 1 && _showTambahJadwal) return true;
    if (_navIndex == 3 && _selectedSavedPlanId != null) return true;
    if (_navIndex != 2) return false;

    final step = _effectiveAnalysisStepFor(host);
    if (step == 4 || step == 3 || step == 1) return true;
    if (step == 2) return analysis.response != null;
    return step == 0 && _addingSource && analysis.response != null;
  }

  void _handleSemanticBack() {
    final pendingAnalysis = context.read<AnalisisViewModel>();
    if (pendingAnalysis.canRetryPersistence ||
        pendingAnalysis.phase == AnalysisPhase.persisting) {
      setState(() { _navIndex = 2; _analisisStep = 1; });
      return;
    }
    final pendingHost = context.read<PlanningHostViewModel>();
    if (pendingHost.canRetryPersistence || pendingHost.canRetryPublication ||
        pendingHost.hasPendingAcceptance || pendingHost.navigationLockedByPersistence) {
      setState(() { _navIndex = 2; _analisisStep = pendingHost.hasPendingAcceptance ? 3 : 4; });
      return;
    }
    if (_navIndex == 1 && _showTambahJadwal) {
      setState(() {
        _showTambahJadwal = false;
        _editingCommitment = null;
      });
      return;
    }
    if (_navIndex == 3 && _selectedSavedPlanId != null) {
      setState(() => _selectedSavedPlanId = null);
      return;
    }
    if (_navIndex != 2) return;

    final host = context.read<PlanningHostViewModel>();
    final analysis = context.read<AnalisisViewModel>();
    switch (_effectiveAnalysisStepFor(host)) {
      case 4:
        _backFromPlanningSetup();
        return;
      case 3:
        _closeDecision();
        return;
      case 2:
        if (analysis.response != null) setState(() => _analisisStep = 1);
        return;
      case 1:
        if (!analysis.canLeaveProgress) return;
        analysis.beginSourceEdit();
        setState(() => _analisisStep = 0);
        return;
      case 0:
        if (_addingSource && analysis.response != null) {
          setState(() {
            _addingSource = false;
            _analisisStep = 2;
          });
        }
        return;
    }
  }

  Future<void> _openPremiumAccess() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PremiumAccessScreen(),
      ),
    );
  }

  Future<void> _refreshAcceptedProjections() async {
    final savedPlans = context.read<SavedPlansViewModel>();
    final schedule = context.read<JadwalViewModel>();
    var failed = false;
    try {
      await savedPlans.refreshForHandoff();
    } on Object {
      failed = true;
    }
    try {
      await schedule.refreshAcceptedPlans();
    } on Object {
      failed = true;
    }
    if (!failed || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Plan accepted. Some local views could not refresh yet.',
        ),
      ),
    );
  }

  Future<void> _retryAcceptanceSave() async {
    final host = context.read<PlanningHostViewModel>();
    try {
      await host.retryAcceptancePersistence();
    } on AcceptancePersistenceExceptionProxy {
      return;
    }
    if (!mounted || host.phase != PlanningHostPhase.accepted) return;
    await _refreshAcceptedProjections();
    if (!mounted) return;
    setState(() {
      _selectedSavedPlanId = host.savedPlan?.id;
      _navIndex = 3;
      _analisisStep = 2;
    });
  }

  void _cancelPendingAcceptance() {
    context.read<PlanningHostViewModel>().cancelPendingAcceptance();
  }

  Future<void> _openPlanningFromCurrentAnalysis() async {
    final analysis = context.read<AnalisisViewModel>();
    final snapshot = analysis.activeSnapshot;
    if (snapshot == null) return;
    final host = context.read<PlanningHostViewModel>();
    await host.startPlanning(snapshot);
    if (!mounted) return;
    setState(() {
      _navIndex = 2;
      _analisisStep = 4;
    });
  }

  Future<void> _reevaluateSavedPlan(SavedPlanSummary summary) async {
    final analysis = context.read<AnalisisViewModel>();
    final host = context.read<PlanningHostViewModel>();
    final snapshot = await analysis.latestSnapshotForCompetition(
      summary.plan.competitionId,
    );
    if (!mounted) return;
    if (snapshot == null) {
      throw StateError('The latest persisted analysis is unavailable.');
    }
    if (!await analysis.loadSnapshot(snapshot)) {
      throw StateError('The persisted analysis context cannot be opened.');
    }
    await host.startPlanning(snapshot);
    if (!mounted) return;
    if (host.phase != PlanningHostPhase.setup) {
      throw StateError('The planning context could not be loaded.');
    }
    setState(() {
      _selectedSavedPlanId = null;
      _navIndex = 2;
      _analisisStep = 4;
    });
  }

  void _viewSavedPlanSchedule(SavedPlanSummary summary) {
    context
        .read<JadwalViewModel>()
        .fokusKompetisi(summary.plan.competitionId);
    setState(() {
      _selectedSavedPlanId = null;
      _navIndex = 1;
      _jadwalTab = 0;
      _showTambahJadwal = false;
      _editingCommitment = null;
    });
  }

  Widget _analysisBody() {
    final vm = context.watch<AnalisisViewModel>();
    final host = context.watch<PlanningHostViewModel>();
    final injected = widget.decisionSession != null;
    final effectiveStep = _effectiveAnalysisStepFor(host);

    switch (effectiveStep) {
      case 4:
        final draft = host.draft;
        if (draft == null) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                AppHeader(title: 'Planning Setup', onBack: _backFromPlanningSetup),
                if (host.busy) const LinearProgressIndicator(),
                if (host.failure != null)
                  RecoveryPanel(
                    descriptor: RecoveryDescriptor(
                      title: 'Planning context is unavailable',
                      message: host.failure!.message,
                      recoveryClass: host.failure!.recoveryClass,
                      technicalCode: host.failure!.code,
                      stage: host.failure!.stage,
                    ),
                    primaryLabel: host.canReloadContext ? 'Reload context' : null,
                    onPrimary: host.canReloadContext ? host.reloadContext : null,
                  ),
              ],
            ),
          );
        }
        return PlanningSetupScreen(
          host: host,
          onBack: _backFromPlanningSetup,
          onDecisionReady: () => setState(() => _analisisStep = 3),
        );
      case 3:
        final session = widget.decisionSession ?? host.activeSession;
        final revision =
            injected ? widget.currentInputRevision : host.inputRevision;
        return RekomendasiJadwalScreen(
          session: session,
          currentInputRevision: revision,
          revenueCatService: widget.revenueCatEnabled
              ? context.watch<RevenueCatService>()
              : null,
          onOpenPro: widget.revenueCatEnabled ? _openPremiumAccess : null,
          onAccept: widget.onAcceptCandidate ??
              (session, intent) async {
                await host.accept(session, intent);
                await _refreshAcceptedProjections();
                if (!mounted) return;
                setState(() {
                  _selectedSavedPlanId = host.savedPlan?.id;
                  _navIndex = 3;
                  _analisisStep = 2;
                });
              },
          onEditConstraints: widget.onEditConstraints ??
              (intent) {
                host.beginEditConstraints(intent);
                setState(() => _analisisStep = 4);
              },
          onIgnore: (intent) {
            if (widget.onIgnoreRecommendation != null) {
              widget.onIgnoreRecommendation!.call(intent);
            } else {
              host.ignore(intent);
            }
            _closeDecision();
          },
          acceptancePersistencePending: host.hasPendingAcceptance,
          acceptancePersistenceMessage: host.hasPendingAcceptance
              ? host.failure?.message
              : null,
          onRetryAcceptanceSave:
              host.hasPendingAcceptance ? _retryAcceptanceSave : null,
          onCancelPendingAcceptance:
              host.hasPendingAcceptance ? _cancelPendingAcceptance : null,
          onBack: _closeDecision,
        );
      case 1:
        return ProgresAnalisisScreen(
          onReadResult: () => setState(() => _analisisStep = 2),
          onBackToInput: () {
            if (!vm.canLeaveProgress) return;
            vm.beginSourceEdit();
            setState(() => _analisisStep = 0);
          },
          onStartNewAnalysis: () {
            if (!vm.canLeaveProgress) return;
            vm.resetForNewCompetition();
            setState(() {
              _addingSource = false;
              _analisisStep = 0;
            });
          },
        );
      case 2:
        final response = vm.response;
        if (response == null) {
          return AnalisisKompetisiScreen(
            continuation: false,
            onSubmitted: () => setState(() => _analisisStep = 1),
          );
        }
        return ReviewBriefScreen(
          response: response,
          onBack: () => setState(() => _analisisStep = 1),
          onAddSource: () {
            vm.ensureSourceDraft(continuation: true);
            setState(() {
              _addingSource = true;
              _analisisStep = 0;
            });
          },
          onNewAnalysis: () {
            if (!vm.canLeaveProgress) return;
            vm.resetForNewCompetition();
            setState(() {
              _addingSource = false;
              _analisisStep = 0;
            });
          },
          onPlan: vm.activeSnapshot == null
              ? null
              : _openPlanningFromCurrentAnalysis,
        );
      case 0:
      default:
        return AnalisisKompetisiScreen(
          continuation: _addingSource,
          onSubmitted: () => setState(() => _analisisStep = 1),
          onBack: _addingSource && vm.response != null
              ? () {
                  setState(() {
                    _addingSource = false;
                    _analisisStep = 2;
                  });
                }
              : null,
        );
    }
  }

  Widget _plansBody() {
    final selected = _selectedSavedPlanId;
    if (selected != null) {
      return SavedPlanDetailScreen(
        savedPlanId: selected,
        viewModel: context.read<SavedPlanDetailViewModel>(),
        onBack: () => setState(() => _selectedSavedPlanId = null),
        onReevaluate: _reevaluateSavedPlan,
        onViewSchedule: _viewSavedPlanSchedule,
      );
    }
    return RencanaScreen(
      onOpen: (summary) =>
          setState(() => _selectedSavedPlanId = summary.plan.id),
    );
  }

  void _selectRootTab(int index) {
    if (index < 0 || index > 3) return;
    if (index == 3) {
      unawaited(context.read<SavedPlansViewModel>().refresh());
    }
    setState(() {
      _navIndex = index;
      if (index != 3) _selectedSavedPlanId = null;
      if (index == 1) {
        _showTambahJadwal = false;
        _editingCommitment = null;
      }
    });
  }

  Widget _body() {
    switch (_navIndex) {
      case 1:
        if (_showTambahJadwal) {
          final editing = _editingCommitment;
          final recurrence = editing == null
              ? null
              : context.read<JadwalViewModel>().recurrenceFor(editing.id);
          return TambahJadwalScreen(
            commitment: editing,
            recurrenceRule: recurrence,
            onBack: () => setState(() {
              _showTambahJadwal = false;
              _editingCommitment = null;
            }),
            onSave: () => setState(() {
              _showTambahJadwal = false;
              _editingCommitment = null;
            }),
          );
        }
        return _jadwalTab == 0
            ? JadwalHarianScreen(
                onSwitchTab: (index) =>
                    setState(() => _jadwalTab = index),
                onAdd: () => setState(() {
                  _editingCommitment = null;
                  _showTambahJadwal = true;
                }),
                onEdit: (commitment) => setState(() {
                  _editingCommitment = commitment;
                  _showTambahJadwal = true;
                }),
                onOpenSavedPlan: (savedPlanId) => setState(() {
                  _selectedSavedPlanId = savedPlanId;
                  _navIndex = 3;
                }),
              )
            : JadwalRingkasanScreen(
                onSwitchTab: (index) =>
                    setState(() => _jadwalTab = index),
              );
      case 2:
        return _analysisBody();
      case 3:
        return _plansBody();
      case 0:
      default:
        return HomeScreen(
          onOpenPro: widget.revenueCatEnabled ? _openPremiumAccess : null,
          onLihatJadwal: () => setState(() {
            _navIndex = 1;
            _jadwalTab = 0;
            _showTambahJadwal = false;
            _editingCommitment = null;
          }),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSemanticBackTarget = _hasSemanticBackTarget();
    return PopScope<void>(
      canPop: !hasSemanticBackTarget,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleSemanticBack();
      },
      child: Scaffold(
        backgroundColor: C.bg,
      body: SafeArea(
        bottom: false,
        child: HorizontalSwipeSurface(
          key: const Key('root-tab-swipe-area'),
          onSwipeLeft: () => _selectRootTab(_navIndex + 1),
          onSwipeRight: () => _selectRootTab(_navIndex - 1),
          child: _body(),
        ),
      ),
        bottomNavigationBar: _BottomNav(
          activeIndex: _navIndex,
          onTap: _selectRootTab,
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.activeIndex,
    required this.onTap,
  });

  final int activeIndex;
  final ValueChanged<int> onTap;

  static const _items = <(IconData, String)>[
    (Icons.home_rounded, 'Home'),
    (Icons.calendar_today_rounded, 'Schedule'),
    (Icons.auto_awesome_rounded, 'Analysis'),
    (Icons.bookmark_rounded, 'Plans'),
  ];

  @override
  Widget build(BuildContext context) {
    return HorizontalSwipeSurface(
      key: const Key('bottom-nav-swipe-area'),
      behavior: HitTestBehavior.opaque,
      onSwipeLeft: () {
        final target = activeIndex + 1;
        if (target < _items.length) onTap(target);
      },
      onSwipeRight: () {
        final target = activeIndex - 1;
        if (target >= 0) onTap(target);
      },
      child: Container(
        color: C.card,
        padding: EdgeInsets.only(
          top: 10,
          bottom: 8 + MediaQuery.of(context).padding.bottom,
          left: 10,
          right: 10,
        ),
        child: Row(
          children: List.generate(_items.length, (index) {
            final active = index == activeIndex;
            return Expanded(
              child: Semantics(
                button: true,
                selected: active,
                label: _items[index].$2,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: InkWell(
                    onTap: () => onTap(index),
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    Icon(
                      _items[index].$1,
                      size: 20,
                      color: active ? C.accent : C.navInactive,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _items[index].$2,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: active ? C.accent : C.navInactive,
                      ),
                    ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

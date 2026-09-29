import 'dart:async';

import 'package:flutter/material.dart';
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
import 'models/decision_intent.dart';
import 'models/evaluation_session.dart';
import 'screens/analisis_kompetisi_screen.dart';
import 'screens/home_screen.dart';
import 'screens/jadwal_harian_screen.dart';
import 'screens/jadwal_ringkasan_screen.dart';
import 'screens/planning_setup_screen.dart';
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

void main() {
  runApp(const TaktApp());
}

class TaktApp extends StatelessWidget {
  const TaktApp({
    super.key,
    this.scheduleRepository,
    this.analysisRepository,
    this.apiClient,
    this.planApiClient,
    this.evaluationRepository,
    this.savedPlanRepository,
    this.decisionSession,
    this.currentInputRevision = 0,
    this.onAcceptCandidate,
    this.onEditConstraints,
    this.onIgnoreRecommendation,
  });

  final ScheduleRepository? scheduleRepository;
  final AnalysisRepository? analysisRepository;
  final CompetitionApiClient? apiClient;
  final PlanApiClient? planApiClient;
  final EvaluationRepository? evaluationRepository;
  final SavedPlanRepository? savedPlanRepository;

  /// Legacy 3B injection remains available for isolated component tests.
  /// Production navigation uses [PlanningHostViewModel].
  final EvaluationSession? decisionSession;
  final int currentInputRevision;
  final AcceptCandidateHandler? onAcceptCandidate;
  final ValueChanged<EditConstraintsIntent>? onEditConstraints;
  final ValueChanged<IgnoreRecommendationIntent>? onIgnoreRecommendation;

  @override
  Widget build(BuildContext context) {
    final calendarScheduleRepository =
        scheduleRepository ?? DriftScheduleRepository(AppDatabase.open());
    final calendarSavedPlanRepository = scheduleRepository == null
        ? DriftSavedPlanRepository(AppDatabase.open())
        : null;

    final analysisRepo =
        analysisRepository ?? DriftAnalysisRepository(AppDatabase.open());

    final savedPlansUiRepository =
        savedPlanRepository ?? DriftSavedPlanRepository(AppDatabase.open());

    final hostScheduleRepository =
        scheduleRepository ?? DriftScheduleRepository(AppDatabase.open());
    final hostEvaluationRepository =
        evaluationRepository ?? DriftEvaluationRepository(AppDatabase.open());
    final hostSavedPlanRepository =
        savedPlanRepository ?? DriftSavedPlanRepository(AppDatabase.open());

    final hostOwnsRepositories = scheduleRepository == null &&
        evaluationRepository == null &&
        savedPlanRepository == null;

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => JadwalViewModel(
            calendarScheduleRepository,
            savedPlanRepository: calendarSavedPlanRepository,
          )..initialize(),
        ),
        ChangeNotifierProvider(
          create: (_) => AnalisisViewModel(
            apiClient: apiClient ??
                HttpCompetitionApiClient(baseUrl: ApiConfig.baseUrl),
            repository: analysisRepo,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              SavedPlansViewModel(savedPlansUiRepository)..initialize(),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              SavedPlanDetailViewModel(savedPlansUiRepository),
        ),
        ChangeNotifierProvider(
          create: (_) => PlanningHostViewModel(
            apiClient: planApiClient ??
                HttpPlanApiClient(baseUrl: ApiConfig.baseUrl),
            scheduleRepository: hostScheduleRepository,
            evaluationRepository: hostEvaluationRepository,
            savedPlanRepository: hostSavedPlanRepository,
            closeRepositoriesOnDispose: hostOwnsRepositories,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Takt',
        locale: const Locale('en'),
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: RootShell(
          decisionSession: decisionSession,
          currentInputRevision: currentInputRevision,
          onAcceptCandidate: onAcceptCandidate,
          onEditConstraints: onEditConstraints,
          onIgnoreRecommendation: onIgnoreRecommendation,
        ),
      ),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({
    super.key,
    this.decisionSession,
    this.currentInputRevision = 0,
    this.onAcceptCandidate,
    this.onEditConstraints,
    this.onIgnoreRecommendation,
  });

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

  void _closeDecision() => setState(() {
        _analisisStep =
            context.read<AnalisisViewModel>().response == null ? 0 : 2;
      });

  Future<void> _refreshAcceptedProjections() async {
    await Future.wait([
      context.read<SavedPlansViewModel>().refresh(),
      context.read<JadwalViewModel>().refreshAcceptedPlans(),
    ]);
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The latest persisted analysis for this competition is unavailable.',
          ),
        ),
      );
      return;
    }
    await analysis.loadSnapshot(snapshot);
    await host.startPlanning(snapshot);
    if (!mounted) return;
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

    switch (_analisisStep) {
      case 4:
        final draft = host.draft;
        if (draft == null) {
          return ReviewBriefScreen(
            response: vm.response!,
            onBack: () => setState(() => _analisisStep = 2),
            onPlan: _openPlanningFromCurrentAnalysis,
          );
        }
        return PlanningSetupScreen(
          host: host,
          onBack: () => setState(() => _analisisStep = 2),
          onDecisionReady: () => setState(() => _analisisStep = 3),
        );
      case 3:
        final session = widget.decisionSession ?? host.activeSession;
        final revision =
            injected ? widget.currentInputRevision : host.inputRevision;
        return RekomendasiJadwalScreen(
          session: session,
          currentInputRevision: revision,
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
          onBack: _closeDecision,
        );
      case 1:
        return ProgresAnalisisScreen(
          onReadResult: () => setState(() => _analisisStep = 2),
          onBackToInput: () => setState(() => _analisisStep = 0),
          onStartNewAnalysis: () {
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
            onBack: () => setState(() => _navIndex = 0),
          );
        }
        return ReviewBriefScreen(
          response: response,
          onBack: () => setState(() => _analisisStep = 1),
          onAddSource: () => setState(() {
            _addingSource = true;
            _analisisStep = 0;
          }),
          onNewAnalysis: () {
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
          onBack: () {
            if (_addingSource && vm.response != null) {
              setState(() {
                _addingSource = false;
                _analisisStep = 2;
              });
            } else {
              setState(() => _navIndex = 0);
            }
          },
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
                onBack: () => setState(() => _navIndex = 0),
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
    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const StatusBarMock(),
            Expanded(child: _body()),
          ],
        ),
      ),
      bottomNavigationBar: _BottomNav(
        activeIndex: _navIndex,
        onTap: (index) {
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
        },
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
    return Container(
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
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(index),
              child: Column(
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
          );
        }),
      ),
    );
  }
}

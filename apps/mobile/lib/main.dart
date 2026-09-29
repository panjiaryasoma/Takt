import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/api_config.dart';
import 'data/database/app_database.dart';
import 'data/remote/competition_api_client.dart';
import 'data/repositories/analysis_repository.dart';
import 'data/repositories/drift_analysis_repository.dart';
import 'data/repositories/drift_schedule_repository.dart';
import 'data/repositories/schedule_repository.dart';
import 'models/commitment.dart';
import 'models/decision_intent.dart';
import 'models/evaluation_session.dart';
import 'screens/analisis_kompetisi_screen.dart';
import 'screens/home_screen.dart';
import 'screens/jadwal_harian_screen.dart';
import 'screens/jadwal_ringkasan_screen.dart';
import 'screens/progres_analisis_screen.dart';
import 'screens/rencana_screen.dart';
import 'screens/rekomendasi_jadwal_screen.dart';
import 'screens/review_brief_screen.dart';
import 'screens/tambah_jadwal_screen.dart';
import 'theme/app_theme.dart';
import 'viewmodels/analisis_view_model.dart';
import 'viewmodels/jadwal_view_model.dart';
import 'viewmodels/rencana_view_model.dart';
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
    this.decisionSession,
    this.currentInputRevision = 0,
    this.onAcceptCandidate,
    this.onEditConstraints,
    this.onIgnoreRecommendation,
  });

  final ScheduleRepository? scheduleRepository;
  final AnalysisRepository? analysisRepository;
  final CompetitionApiClient? apiClient;
  final EvaluationSession? decisionSession;
  final int currentInputRevision;
  final AcceptCandidateHandler? onAcceptCandidate;
  final ValueChanged<EditConstraintsIntent>? onEditConstraints;
  final ValueChanged<IgnoreRecommendationIntent>? onIgnoreRecommendation;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) {
            final repository = scheduleRepository ??
                DriftScheduleRepository(AppDatabase.open());
            return JadwalViewModel(repository)..initialize();
          },
        ),
        ChangeNotifierProvider(
          create: (_) => AnalisisViewModel(
            apiClient: apiClient ?? HttpCompetitionApiClient(baseUrl: ApiConfig.baseUrl),
            repository: analysisRepository ?? DriftAnalysisRepository(AppDatabase.open()),
          ),
        ),
        ChangeNotifierProvider(create: (_) => RencanaViewModel()),
      ],
      child: MaterialApp(
        title: 'Takt',
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
  const RootShell({super.key, this.decisionSession, this.currentInputRevision = 0,
    this.onAcceptCandidate, this.onEditConstraints, this.onIgnoreRecommendation});

  /// 4B publishes its active, paired session; navigation does not build inputs.
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
        _analisisStep = context.read<AnalisisViewModel>().response == null ? 0 : 2;
      }
    }
  }

  void _closeDecision() => setState(() {
    _analisisStep = context.read<AnalisisViewModel>().response == null ? 0 : 2;
  });

  Widget _analysisBody() {
    final vm = context.read<AnalisisViewModel>();
    switch (_analisisStep) {
      case 3:
        return RekomendasiJadwalScreen(
          session: widget.decisionSession,
          currentInputRevision: widget.currentInputRevision,
          onAccept: widget.onAcceptCandidate,
          onEditConstraints: widget.onEditConstraints,
          onIgnore: (intent) {
            widget.onIgnoreRecommendation?.call(intent);
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
                onBack: () => setState(() => _navIndex = 0),
              )
            : JadwalRingkasanScreen(
                onSwitchTab: (index) =>
                    setState(() => _jadwalTab = index),
              );
      case 2:
        return _analysisBody();
      case 3:
        return RencanaScreen(
          onTinjau: null,
          onCekJadwal: (entry) {
            context
                .read<JadwalViewModel>()
                .fokusKompetisi(entry.competitionId);
            setState(() {
              _navIndex = 1;
              _jadwalTab = 0;
              _showTambahJadwal = false;
              _editingCommitment = null;
            });
          },
        );
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
        onTap: (index) => setState(() {
          _navIndex = index;
          if (index == 1) {
            _showTambahJadwal = false;
            _editingCommitment = null;
          }
        }),
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
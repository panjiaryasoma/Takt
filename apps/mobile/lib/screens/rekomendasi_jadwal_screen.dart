import 'package:flutter/material.dart';

import '../models/decision_intent.dart';
import '../models/decision_report_view_data.dart';
import '../models/enums.dart';
import '../models/evaluation_session.dart';
import '../monetization/revenuecat_contract.dart';
import '../monetization/revenuecat_service.dart';
import '../theme/app_theme.dart';
import '../viewmodels/decision_report_view_model.dart';

/// Host-injected Decision Report; no repositories, input generation or HTTP.
class RekomendasiJadwalScreen extends StatefulWidget {
  const RekomendasiJadwalScreen({super.key, required this.session,
    required this.currentInputRevision, this.revenueCatService, this.onOpenPro,
    this.onAccept, this.onEditConstraints, this.onIgnore, this.onBack});
  final EvaluationSession? session;
  final int currentInputRevision;
  final RevenueCatService? revenueCatService;
  final VoidCallback? onOpenPro;
  final AcceptCandidateHandler? onAccept;
  final ValueChanged<EditConstraintsIntent>? onEditConstraints;
  final ValueChanged<IgnoreRecommendationIntent>? onIgnore;
  final VoidCallback? onBack;
  @override
  State<RekomendasiJadwalScreen> createState() => _RekomendasiJadwalScreenState();
}

class _RekomendasiJadwalScreenState extends State<RekomendasiJadwalScreen> {
  late final DecisionReportViewModel _vm;
  ModalRoute<dynamic>? _sheetRoute;
  bool _openingConfirmation = false;

  @override
  void initState() {
    super.initState();
    _vm = DecisionReportViewModel(session: widget.session,
        currentInputRevision: widget.currentInputRevision)
      ..addListener(_cancelInvalidSheet);
  }

  @override
  void didUpdateWidget(covariant RekomendasiJadwalScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _vm.updateHost(session: widget.session, currentInputRevision: widget.currentInputRevision);
    if (widget.onAccept == null && _vm.pendingConfirmation != null) {
      _vm.cancelConfirmation(_vm.pendingConfirmation!);
    }
  }

  void _removeOwnSheet() {
    final route = _sheetRoute;
    if (route == null) return;
    _sheetRoute = null;
    // Remove only the owned sheet, never pop an unrelated host route.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route.isActive) route.navigator?.removeRoute(route);
    });
  }

  void _cancelInvalidSheet() {
    if (_vm.pendingConfirmation == null) _removeOwnSheet();
  }

  @override
  void dispose() {
    _removeOwnSheet();
    _vm.removeListener(_cancelInvalidSheet);
    _vm.dispose();
    super.dispose();
  }

  bool get _canAccessAlternatives =>
      widget.revenueCatService?.canAccess(PremiumFeature.alternativeCandidates) ?? false;

  bool _prepareAccessibleSelection() {
    if (_canAccessAlternatives) return true;
    final primary = _vm.systemPrimaryCandidateId;
    if (primary == null) return false;
    if (_vm.selectedCandidateId == primary) return true;
    if (_vm.handoffPending) return false;
    return _vm.chooseCandidate(primary);
  }

  Future<void> _accept() async {
    if (_openingConfirmation || widget.onAccept == null) return;
    if (!_prepareAccessibleSelection()) return;
    final token = _vm.beginAccept();
    if (token == null) return;
    _openingConfirmation = true;
    final candidate = token.session.parsedResponse.planning!.candidate(token.candidateId)!;
    final confirmed = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true, backgroundColor: C.card,
      builder: (sheetContext) {
        _sheetRoute = ModalRoute.of(sheetContext);
        _cancelInvalidSheet();
        return SafeArea(child: FractionallySizedBox(heightFactor: 0.85,
          child: SingleChildScrollView(padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Accept this option?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              const Text('Review all suggested work windows before confirming your choice.'),
              const SizedBox(height: 12),
              Text(token.selectionSource == SelectionSource.primary
                  ? 'System primary recommendation' : 'Your selected alternative'),
              Text('Remaining buffer: ${candidate.bufferMinutes} min'),
              const SizedBox(height: 12),
              const Text('Suggested schedule · Not added to calendar', style: TextStyle(color: C.accent)),
              const Text('Times are shown in your device time zone.'),
              ...candidate.workBlocks.map((b) => _WindowText(taskId: b.taskId,
                  start: b.start, end: b.end, minutes: b.allocatedMinutes)),
              if (candidate.workBlocks.isEmpty) const Text('No work blocks in this candidate.'),
              _TextList(title: 'Candidate assumptions', lines: candidate.assumptions),
              const SizedBox(height: 16),
              FilledButton(key: const Key('confirm-accept'),
                onPressed: () => Navigator.of(sheetContext).pop(true),
                child: const Text('Confirm choice')),
              TextButton(onPressed: () => Navigator.of(sheetContext).pop(false), child: const Text('Cancel')),
            ]),
          ),
        ));
      },
    );
    _sheetRoute = null;
    _openingConfirmation = false;
    if (!mounted) return;
    final handler = widget.onAccept;
    if (confirmed != true || handler == null) {
      _vm.cancelConfirmation(token);
      return;
    }
    if (!_canAccessAlternatives &&
        token.selectionSource == SelectionSource.alternative) {
      _vm.cancelConfirmation(token);
      return;
    }
    final intent = _vm.confirmAccept(token);
    if (intent == null) return;
    try {
      await handler(token.session, intent);
      if (mounted) _vm.finishHandoff(token);
    } catch (_) {
      if (mounted) _vm.finishHandoff(token, failed: true);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: _vm,
    builder: (context, _) {
      final session = _vm.session;
      final view = session == null ? null : DecisionReportViewData(session.parsedResponse);
      final planning = _vm.planning;
      final payload = planning?.recommendation?.recommendation;
      return SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Align(alignment: Alignment.centerLeft, child: Container(
            decoration: BoxDecoration(color: C.card, shape: BoxShape.circle,
                border: Border.all(color: C.accent.withValues(alpha: 0.6))),
            child: IconButton(tooltip: 'Back', onPressed: widget.onBack,
                icon: const Icon(Icons.chevron_left, color: C.accent)),
          )),
          const SizedBox(height: 14),
          const Text('Decision Report', style: TextStyle(color: C.white, fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (view == null)
            const _ReportCard(child: Text('Recommendation is not available yet. Complete the evaluation to view schedule suggestions.'))
          else if (_vm.isDismissed)
            const _ReportCard(child: Text('Recommendation ignored. Your schedule has not changed.'))
          else ...[
            const Text('Suggested schedule · Not added to calendar', style: TextStyle(color: C.accent)),
            const SizedBox(height: 8),
            Text('Evaluated ${_instant(view.response.evaluatedAt)}', style: const TextStyle(color: C.detailMuted)),
            if (_vm.isStale) const _ReportCard(highlight: true, child: Text(
              'Inputs have changed. Go back for a new evaluation before accepting a suggested schedule.',
              key: Key('stale-notice'))),
            _ReportCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const _Heading('Readiness'),
              Text(view.readinessLabel, style: const TextStyle(fontSize: 17, color: C.accent)),
              _TextList(title: 'Blockers', lines: view.response.readiness.blockingReasons.map(DecisionReportViewData.explain).toList()),
              _TextList(title: 'Review items', lines: view.response.readiness.reviewItems.map(DecisionReportViewData.explain).toList()),
              _TextList(title: 'Passed checks', lines: view.response.readiness.passedChecks.map(DecisionReportViewData.explain).toList()),
            ])),
            _ReportCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const _Heading('Feasibility'),
              Text(view.feasibilityLabel, style: const TextStyle(fontSize: 17, color: C.accent)),
              const SizedBox(height: 8),
              Text(view.feasibilityExplanation),
              if (planning != null) ...[
                const SizedBox(height: 8),
                const Text('Likely is the most probable work-time estimate. This result describes modeled constraints and estimates, not your ability.', style: TextStyle(color: C.detailMuted)),
                _TextList(title: 'Evaluation basis', lines: planning.reasonCodes.map(DecisionReportViewData.explain).toList()),
                _TextList(title: 'Sensitivities', lines: planning.sensitivityCodes.map(DecisionReportViewData.explain).toList()),
                _TextList(title: 'Scope tradeoffs', lines: planning.tradeoffCodes.map(DecisionReportViewData.explain).toList()),
              ],
            ])),
            if (planning != null && payload != null) ...[
              const Text('Times are shown in your device time zone.', style: TextStyle(color: C.detailMuted)),
              for (var i = 0; i < planning.candidates.length; i++)
                if (planning.candidates[i].ref.candidateId ==
                        _vm.systemPrimaryCandidateId ||
                    _canAccessAlternatives)
                  _CandidateCard(
                    key: Key(
                      'candidate-${planning.candidates[i].ref.candidateId}',
                    ),
                    data: view.candidate(planning.candidates[i]),
                    label: planning.candidates[i].ref.candidateId ==
                            _vm.systemPrimaryCandidateId
                        ? 'System primary recommendation'
                        : 'Alternative $i',
                    selected: _canAccessAlternatives
                        ? _vm.selectedCandidateId ==
                            planning.candidates[i].ref.candidateId
                        : planning.candidates[i].ref.candidateId ==
                            _vm.systemPrimaryCandidateId,
                    showChoose: _canAccessAlternatives &&
                        planning.candidates[i].ref.candidateId !=
                            _vm.systemPrimaryCandidateId &&
                        planning.allowedActions.contains(
                          RecommendationAction.chooseAlternative,
                        ),
                    onChoose: _canAccessAlternatives &&
                            _vm.can(RecommendationAction.chooseAlternative)
                        ? () => _vm.chooseCandidate(
                              planning.candidates[i].ref.candidateId,
                            )
                        : null,
                  ),
              if (!_canAccessAlternatives &&
                  planning.candidates.any(
                    (candidate) =>
                        candidate.ref.candidateId !=
                        _vm.systemPrimaryCandidateId,
                  ))
                _PremiumAlternativesCard(onOpenPro: widget.onOpenPro),
              _ReportCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _TextList(title: 'Primary recommendation rationale', lines: payload.rationale),
                _TextList(title: 'Evaluation assumptions', lines: payload.assumptions.map((item) =>
                    item.taskId == null ? item.description : '${item.description} (Task ${item.taskId})').toList()),
              ])),
            ],
            if (_vm.handoffPending) const _ReportCard(child: Text('Sending your choice…', key: Key('handoff-pending'))),
            if (_vm.handoffComplete) const _ReportCard(child: Text('Your choice was handed off. Wait for persistence confirmation.', key: Key('handoff-complete'))),
            if (_vm.handoffFailed) const _ReportCard(highlight: true, child: Text('Your choice could not be handed off. Review it before trying again.', key: Key('handoff-failed'))),
            if (planning != null) ...[
              if (planning.allowedActions.contains(RecommendationAction.accept)) ...[
                FilledButton(key: const Key('accept-candidate'),
                    onPressed: widget.onAccept != null &&
                            _vm.can(RecommendationAction.accept) &&
                            (_canAccessAlternatives ||
                                _vm.systemPrimaryCandidateId != null)
                        ? _accept
                        : null,
                    child: const Text('Accept this option')),
                if (widget.onAccept == null) const Text('Plan acceptance is not available yet.', style: TextStyle(color: C.detailMuted)),
              ],
              if (planning.allowedActions.contains(RecommendationAction.editConstraints)) ...[
                OutlinedButton(key: const Key('edit-constraints'),
                  onPressed: widget.onEditConstraints != null && _vm.can(RecommendationAction.editConstraints)
                      ? () { final intent = _vm.editConstraints(); if (intent != null) widget.onEditConstraints!(intent); }
                      : null, child: const Text('Edit constraints')),
                if (widget.onEditConstraints == null) const Text('Constraint editing is not available yet.', style: TextStyle(color: C.detailMuted)),
              ],
              if (planning.allowedActions.contains(RecommendationAction.ignore))
                TextButton(key: const Key('ignore-recommendation'),
                  onPressed: _vm.can(RecommendationAction.ignore) ? () {
                    final intent = _vm.ignore();
                    if (intent == null) return;
                    if (widget.onIgnore != null) { widget.onIgnore!(intent); } else { widget.onBack?.call(); }
                  } : null, child: const Text('Ignore recommendation')),
            ],
            _ReportCard(child: ExpansionTile(tilePadding: EdgeInsets.zero,
              title: const Text('Evaluation details'), children: [
                Align(alignment: Alignment.centerLeft, child: SelectableText([
                  'Evaluation: ${view.response.evaluationId}',
                  'Competition: ${view.response.basis.report.competitionId}',
                  'Report: v${view.response.basis.report.reportVersion}',
                  'Basis: ${view.response.basis.fingerprint}',
                  ...view.response.readiness.blockingReasons,
                  ...view.response.readiness.reviewItems,
                  ...view.response.readiness.passedChecks,
                  ...?planning?.reasonCodes, ...?planning?.tradeoffCodes, ...?planning?.sensitivityCodes,
                ].join('\n'))),
              ])),
          ],
        ]),
      );
    },
  );
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({super.key, required this.data, required this.label,
      required this.selected, required this.showChoose, this.onChoose});
  final DecisionCandidateViewData data;
  final String label;
  final bool selected;
  final bool showChoose;
  final VoidCallback? onChoose;
  @override
  Widget build(BuildContext context) {
    final next = data.nextWork;
    return _ReportCard(highlight: selected,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _Heading(label),
        if (selected) const Text('Your selected option', style: TextStyle(color: C.accent, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Remaining buffer: ${data.bufferMinutes} min'),
        const SizedBox(height: 12),
        const Text('Suggested schedule · Not added to calendar', style: TextStyle(color: C.accent)),
        if (next != null) ...[
          const SizedBox(height: 8),
          Text('Next work: ${next.taskName}', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('${_instant(next.start)} · ${next.allocatedMinutes} min'),
        ],
        ...data.windows.map((w) => _WindowText(taskId: w.taskId, start: w.start, end: w.end, minutes: w.allocatedMinutes)),
        if (data.windows.isEmpty) const Text('No suggested work blocks in this candidate.'),
        _TextList(title: 'Option tradeoffs', lines: data.tradeoffs),
        _TextList(title: 'Candidate assumptions', lines: data.candidate.assumptions),
        if (showChoose) OutlinedButton(key: Key('choose-${data.candidate.ref.candidateId}'),
          onPressed: selected ? null : onChoose, child: Text(selected ? 'Selected' : 'Choose this option')),
        ExpansionTile(tilePadding: EdgeInsets.zero, title: const Text('Candidate and work-block details'), children: [
          Align(alignment: Alignment.centerLeft, child: SelectableText('Candidate: ${data.candidate.ref.candidateId}')),
          for (final b in data.candidate.workBlocks) ...[
            _WindowText(taskId: b.taskId, start: b.start, end: b.end, minutes: b.allocatedMinutes),
            Text('Time source: ${b.availabilitySource}', style: const TextStyle(color: C.detailMuted)),
          ],
        ]),
      ]),
    );
  }
}

class _PremiumAlternativesCard extends StatelessWidget {
  const _PremiumAlternativesCard({this.onOpenPro});

  final VoidCallback? onOpenPro;

  @override
  Widget build(BuildContext context) {
    return _ReportCard(
      child: Column(
        key: const Key('alternatives-locked'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Heading('Alternative Candidate Explorer · Takt Pro'),
          const Text(
            'Your primary recommendation stays available. Takt Pro unlocks '
            'the additional valid candidate schedules returned by the same '
            'backend evaluation.',
            style: TextStyle(color: C.detailMuted),
          ),
          if (onOpenPro != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('open-pro-alternatives'),
              onPressed: onOpenPro,
              icon: const Icon(Icons.workspace_premium_outlined),
              label: const Text('View Takt Pro'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.child, this.highlight = false});
  final Widget child;
  final bool highlight;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Material(
      color: C.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: highlight ? const BorderSide(color: C.accent) : BorderSide.none,
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)));
}

class _TextList extends StatelessWidget {
  const _TextList({required this.title, required this.lines});
  final String title;
  final List<String> lines;
  @override
  Widget build(BuildContext context) => lines.isEmpty ? const SizedBox.shrink()
      : Padding(padding: const EdgeInsets.only(top: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            for (final line in lines) Padding(padding: const EdgeInsets.only(top: 4), child: Text(line)),
          ]));
}

class _WindowText extends StatelessWidget {
  const _WindowText({required this.taskId, required this.start, required this.end, required this.minutes});
  final String taskId;
  final DateTime start;
  final DateTime end;
  final int minutes;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 8),
      child: Align(alignment: Alignment.centerLeft,
          child: Text('Task $taskId · $minutes min\n${_instant(start)}\nto ${_instant(end)}')));
}

String _instant(DateTime instant) {
  final local = instant.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  final offset = local.timeZoneOffset.inMinutes;
  final zone = 'UTC${offset < 0 ? '-' : '+'}${two(offset.abs() ~/ 60)}:${two(offset.abs() % 60)}';
  return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)} ($zone)';
}
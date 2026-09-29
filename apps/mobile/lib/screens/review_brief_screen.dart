import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/competition_analysis_wire.dart';
import '../theme/app_theme.dart';

class ReviewBriefScreen extends StatelessWidget {
  const ReviewBriefScreen({
    super.key,
    required this.response,
    this.onBack,
    this.onAddSource,
    this.onNewAnalysis,
  });

  final CompetitionAnalyzeResponseWire response;
  final VoidCallback? onBack;
  final VoidCallback? onAddSource;
  final VoidCallback? onNewAnalysis;

  @override
  Widget build(BuildContext context) {
    final report = response.report;
    final nameField = report.canonicalFields['competition_name'];
    final displayName = nameField != null &&
            (nameField.state == CanonicalFieldState.verified ||
                nameField.state == CanonicalFieldState.singleSource)
        ? _displayValue(nameField.value)
        : 'Competition not fully identified yet';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: C.card,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.chevron_left,
                color: C.accent,
                size: 22,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'REVIEW SUMBER',
            style: TextStyle(
              color: C.accent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Review sumber kompetisi',
            style: TextStyle(
              color: C.white,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            displayName,
            style: const TextStyle(
              color: C.detailMuted,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _MetaChip(
                label: 'Report v${report.reportVersion}',
              ),
              const SizedBox(width: 8),
              _MetaChip(
                label: '${report.sourceIds.length} sumber',
              ),
              const SizedBox(width: 8),
              _MetaChip(
                label: response.reportChanged
                    ? 'Berubah'
                    : 'Tidak berubah',
              ),
            ],
          ),
          if (report.unresolvedCriticalFields.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: C.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: C.sibuk),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: C.sibuk,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${report.unresolvedCriticalFields.length} field kritis masih perlu ditinjau. Ini bukan verdict readiness.',
                      style: const TextStyle(
                        color: C.white,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Text(
            'Field canonical',
            style: TextStyle(
              color: C.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          for (final name in coreCanonicalFieldNames) ...[
            _CanonicalFieldCard(
              label: _fieldLabel(name),
              field: report.canonicalFields[name]!,
              provenance: response.provenance,
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: 'Add Source',
                  filled: true,
                  onTap: onAddSource,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionButton(
                  label: 'New Analysis',
                  filled: false,
                  onTap: onNewAnalysis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Adding a source keeps the existing competition_id, report bundle, and source artifacts for the next reconciliation.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: C.navInactive,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _CanonicalFieldCard extends StatelessWidget {
  const _CanonicalFieldCard({
    required this.label,
    required this.field,
    required this.provenance,
  });

  final String label;
  final CanonicalFieldWire field;
  final AnalysisProvenanceWire provenance;

  @override
  Widget build(BuildContext context) {
    final color = _stateColor(field.state);
    return Container(
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: C.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _StateBadge(
                      label: _stateLabel(field.state),
                      color: color,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _FieldBody(
                  field: field,
                  provenance: provenance,
                ),
              ],
            ),
          ),
          if (field.evidenceIds.isNotEmpty)
            Material(
              color: Colors.transparent,
              child: Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: Colors.transparent,
                ),
                child: ExpansionTile(
                  dense: true,
                  iconColor: C.accent,
                  collapsedIconColor: C.navInactive,
                  title: const Text(
                    'Lihat sumber',
                    style: TextStyle(
                      color: C.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  children: [
                    for (final evidenceId in field.evidenceIds)
                      _EvidenceRow(
                        evidence: provenance.evidenceById(evidenceId),
                        provenance: provenance,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FieldBody extends StatelessWidget {
  const _FieldBody({
    required this.field,
    required this.provenance,
  });

  final CanonicalFieldWire field;
  final AnalysisProvenanceWire provenance;

  @override
  Widget build(BuildContext context) {
    switch (field.state) {
      case CanonicalFieldState.verified:
        return _ValueBlock(
          text: _displayValue(field.value),
          helper: 'Didukung evidence yang sudah direkonsiliasi.',
        );
      case CanonicalFieldState.singleSource:
        return _ValueBlock(
          text: _displayValue(field.value),
          helper: 'Nilai ini baru didukung satu sumber.',
        );
      case CanonicalFieldState.missing:
        return const _ValueBlock(
          text: 'Not found yet',
          helper: 'The backend did not return a candidate value for this field.',
        );
      case CanonicalFieldState.conflict:
        return _CandidateList(
          candidates: field.candidates,
          provenance: provenance,
          helper: 'Sources provide conflicting values. No canonical value was selected.',
        );
      case CanonicalFieldState.unverified:
        return _CandidateList(
          candidates: field.candidates,
          provenance: provenance,
          helper: 'Candidate tersedia, tetapi belum boleh dianggap canonical value.',
        );
    }
  }
}

class _CandidateList extends StatelessWidget {
  const _CandidateList({
    required this.candidates,
    required this.provenance,
    required this.helper,
  });

  final List<CandidateFieldWire> candidates;
  final AnalysisProvenanceWire provenance;
  final String helper;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          helper,
          style: const TextStyle(
            color: C.detailMuted,
            fontSize: 11,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        for (var index = 0; index < candidates.length; index++) ...[
          _CandidateBlock(
            index: index,
            candidate: candidates[index],
            provenance: provenance,
          ),
          if (index != candidates.length - 1)
            const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _CandidateBlock extends StatelessWidget {
  const _CandidateBlock({
    required this.index,
    required this.candidate,
    required this.provenance,
  });

  final int index;
  final CandidateFieldWire candidate;
  final AnalysisProvenanceWire provenance;

  @override
  Widget build(BuildContext context) {
    EvidenceSpanWire? evidence;
    SourceRecordWire? source;
    if (candidate.evidenceIds.isNotEmpty) {
      evidence =
          provenance.evidenceById(candidate.evidenceIds.first);
      if (evidence != null) {
        source = provenance.sourceById(evidence.sourceId);
      }
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: C.bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Candidate ${index + 1}',
            style: const TextStyle(
              color: C.accent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _displayValue(
              candidate.normalizedValue ?? candidate.rawValue,
            ),
            style: const TextStyle(
              color: C.white,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (source != null) ...[
            const SizedBox(height: 5),
            Text(
              '${_sourceTypeLabel(source.sourceType)} · ${source.urlOrDocumentId}',
              style: const TextStyle(
                color: C.navInactive,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({
    required this.evidence,
    required this.provenance,
  });

  final EvidenceSpanWire? evidence;
  final AnalysisProvenanceWire provenance;

  @override
  Widget build(BuildContext context) {
    final item = evidence;
    if (item == null) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: Text(
          'Evidence reference tidak tersedia.',
          style: TextStyle(
            color: C.padat,
            fontSize: 11,
          ),
        ),
      );
    }
    final source = provenance.sourceById(item.sourceId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: C.bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              source == null
                  ? item.sourceId
                  : '${_sourceTypeLabel(source.sourceType)} · ${source.urlOrDocumentId}',
              style: const TextStyle(
                color: C.accent,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (source != null) ...[
              const SizedBox(height: 3),
              Text(
                source.retrievedAt,
                style: const TextStyle(
                  color: C.navInactive,
                  fontSize: 10,
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              '${item.extractionPath} · locator: ${_displayValue(item.pageOrLocator)}',
              style: const TextStyle(
                color: C.detailMuted,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 6),
            _ExpandableEvidenceText(
              text: _displayValue(item.rawReference),
            ),
          ],
        ),
      ),
    );
  }
}


class _ExpandableEvidenceText extends StatefulWidget {
  const _ExpandableEvidenceText({required this.text});

  final String text;

  @override
  State<_ExpandableEvidenceText> createState() =>
      _ExpandableEvidenceTextState();
}

class _ExpandableEvidenceTextState
    extends State<_ExpandableEvidenceText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final canExpand = widget.text.length > 220;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          maxLines: _expanded ? null : 8,
          overflow:
              _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: const TextStyle(
            color: C.white,
            fontSize: 11,
            height: 1.45,
          ),
        ),
        if (canExpand) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Text(
              _expanded ? 'Tutup' : 'Lihat selengkapnya',
              style: const TextStyle(
                color: C.accent,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ValueBlock extends StatelessWidget {
  const _ValueBlock({
    required this.text,
    required this.helper,
  });

  final String text;
  final String helper;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: const TextStyle(
            color: C.white,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          helper,
          style: const TextStyle(
            color: C.detailMuted,
            fontSize: 10,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: C.card,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: C.detailMuted,
            fontSize: 10,
          ),
        ),
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? C.accent : C.card,
          borderRadius: BorderRadius.circular(12),
          border: filled
              ? null
              : Border.all(
                  color: C.accent,
                  width: 1.3,
                ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: filled ? C.bg : C.accent,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

String _fieldLabel(String name) {
  return switch (name) {
    'competition_name' => 'Nama kompetisi',
    'organizer' => 'Penyelenggara',
    'submission_deadline' => 'Deadline submission',
    'registration_deadline' => 'Deadline registrasi',
    'eligibility' => 'Eligibility',
    'team_size' => 'Ukuran tim',
    'format' => 'Format',
    'location' => 'Lokasi',
    'tracks_or_categories' => 'Track / kategori',
    'deliverables' => 'Deliverables',
    'required_technologies' => 'Teknologi wajib',
    'judging_criteria' => 'Kriteria penilaian',
    'prizes_or_benefits' => 'Hadiah / benefit',
    _ => name,
  };
}

String _stateLabel(CanonicalFieldState state) {
  return switch (state) {
    CanonicalFieldState.verified => 'Terverifikasi',
    CanonicalFieldState.singleSource => 'Satu sumber',
    CanonicalFieldState.conflict => 'Konflik',
    CanonicalFieldState.missing => 'Not found yet',
    CanonicalFieldState.unverified => 'Belum terverifikasi',
  };
}

Color _stateColor(CanonicalFieldState state) {
  return switch (state) {
    CanonicalFieldState.verified => C.kosong,
    CanonicalFieldState.singleSource => C.accent,
    CanonicalFieldState.conflict => C.padat,
    CanonicalFieldState.missing => C.navInactive,
    CanonicalFieldState.unverified => C.sibuk,
  };
}

String _sourceTypeLabel(SourceTypeWire type) {
  return switch (type) {
    SourceTypeWire.officialRules => 'Peraturan resmi',
    SourceTypeWire.officialOrganizer => 'Situs penyelenggara',
    SourceTypeWire.officialFaq => 'FAQ resmi',
    SourceTypeWire.platform => 'Platform',
    SourceTypeWire.secondary => 'Sumber sekunder',
    SourceTypeWire.derivedFixture => 'Fixture internal',
  };
}

String _displayValue(Object? value) {
  if (value == null) return 'Belum tersedia';
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } on Object {
    return value.toString();
  }
}
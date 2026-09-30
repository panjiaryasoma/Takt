import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/remote/competition_api_client.dart';
import '../models/competition_analysis_wire.dart';
import '../theme/app_theme.dart';
import '../viewmodels/analisis_view_model.dart';
import '../widgets/common.dart';

class AnalisisKompetisiScreen extends StatefulWidget {
  const AnalisisKompetisiScreen({
    super.key,
    required this.continuation,
    this.onSubmitted,
    this.onBack,
  });

  final bool continuation;
  final VoidCallback? onSubmitted;
  final VoidCallback? onBack;

  @override
  State<AnalisisKompetisiScreen> createState() =>
      _AnalisisKompetisiScreenState();
}

class _AnalisisKompetisiScreenState
    extends State<AnalisisKompetisiScreen> {
  final TextEditingController _urlController = TextEditingController();
  int _mode = 0;
  PlatformFile? _picked;
  SourceTypeWire? _sourceType;
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }
  bool get _urlIsValid {
    final uri = Uri.tryParse(_urlController.text.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  bool get _pdfIsValid {
    final file = _picked;
    final bytes = file?.bytes;
    return file != null &&
        bytes != null &&
        bytes.isNotEmpty &&
        file.size > 0 &&
        file.size <= maxAnalysisSourceBytes;
  }

  bool get _canSubmit {
    if (_submitting || _sourceType == null) return false;
    return _mode == 0 ? _pdfIsValid : _urlIsValid;
  }


  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (!mounted || result == null || result.files.isEmpty) return;
    final file = result.files.single;
    if (file.size <= 0 || file.size > maxAnalysisSourceBytes) {
      setState(() {
        _picked = null;
        _error = 'The PDF must contain data and be no larger than 20 MiB.';
      });
      return;
    }
    setState(() {
      _picked = file;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final sourceType = _sourceType;
    if (sourceType == null) {
      setState(() => _error = 'Select a source type.');
      return;
    }

    final vm = context.read<AnalisisViewModel>();
    Future<void> request;

    if (_mode == 0) {
      final file = _picked;
      final bytes = file?.bytes;
      if (file == null || bytes == null || bytes.isEmpty) {
        setState(() => _error = 'Select a PDF file first.');
        return;
      }
      if (file.size > maxAnalysisSourceBytes) {
        setState(
          () => _error = 'The PDF exceeds the 20 MiB limit.',
        );
        return;
      }
      request = vm.analyzePdf(
        filename: file.name,
        bytes: Uint8List.fromList(bytes),
        sourceType: sourceType,
        continuation: widget.continuation,
      );
    } else {
      final url = _urlController.text.trim();
      final uri = Uri.tryParse(url);
      if (uri == null ||
          (uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.host.isEmpty) {
        setState(
          () => _error = 'Enter a valid http/https URL.',
        );
        return;
      }
      request = vm.analyzeUrl(
        url: url,
        sourceType: sourceType,
        continuation: widget.continuation,
      );
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    widget.onSubmitted?.call();
    await request;
    if (mounted) {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.continuation
        ? 'Add Source'
        : 'Analyze Competition';
    final subtitle = widget.continuation
        ? 'Add new evidence to the same competition.'
        : 'Add one competition source to start the analysis.';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.onBack != null) ...[
                  Material(
                    color: C.card,
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Back',
                      onPressed: widget.onBack,
                      icon: const Icon(
                        Icons.chevron_left,
                        color: C.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  widget.continuation
                      ? 'ADDITIONAL SOURCE'
                      : 'NEW ANALYSIS',
                  style: const TextStyle(
                    color: C.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(
                    color: C.white,
                    fontSize: 22,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const HeaderDivider(),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              subtitle,
              style: const TextStyle(
                color: C.muted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(child: _segment('Upload PDF', 0)),
                const SizedBox(width: 12),
                Expanded(child: _segment('Enter Link', 1)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_mode == 0) _dropzone() else _linkInput(),
          const SizedBox(height: 14),
          _sourceTypeInput(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: C.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: C.padat),
              ),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: C.white,
                  fontSize: 12,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              height: 52,
              child: FilledButton.icon(
                key: const Key('submit-analysis'),
                onPressed: _canSubmit ? _submit : null,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_rounded),
                label: Text(
                  widget.continuation
                      ? 'Add & Re-analyze'
                      : 'Submit & Start Analysis',
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Flutter only sends the source. Extraction and reconciliation remain backend authority.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: C.navInactive,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _segment(String label, int index) {
    final active = index == _mode;
    return GestureDetector(
      onTap: _submitting
          ? null
          : () => setState(() {
                _mode = index;
                _error = null;
              }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? C.accent : C.card,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: active ? C.bg : C.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _dropzone() {
    final file = _picked;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(
        vertical: 26,
        horizontal: 16,
      ),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: DottedBorderBox(
        child: file == null
            ? Column(
                children: [
                  const Icon(
                    Icons.picture_as_pdf_outlined,
                    color: C.white,
                    size: 28,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Select PDF document',
                    style: TextStyle(
                      color: C.white,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Max. 20 MiB · application/pdf',
                    style: TextStyle(
                      color: C.navInactive,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _outlineButton('Choose File', _pickFile),
                ],
              )
            : Column(
                children: [
                  const Icon(
                    Icons.picture_as_pdf_outlined,
                    color: C.accent,
                    size: 28,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    file.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: C.white,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _fmtSize(file.size),
                    style: const TextStyle(
                      color: C.navInactive,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _outlineButton('Replace', _pickFile),
                      const SizedBox(width: 10),
                      _outlineButton(
                        'Remove',
                        () => setState(() => _picked = null),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _linkInput() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: _urlController,
        enabled: !_submitting,
        keyboardType: TextInputType.url,
        autocorrect: false,
        onChanged: (_) => setState(() {
          _error = null;
        }),
        style: const TextStyle(
          color: C.white,
          fontSize: 13,
        ),
        cursorColor: C.accent,
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: 'https://... competition page link',
          hintStyle: TextStyle(
            color: C.navInactive,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _sourceTypeInput() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<SourceTypeWire>(
          value: _sourceType,
          isExpanded: true,
          dropdownColor: C.card,
          hint: const Text(
            'Select source type',
            style: TextStyle(
              color: C.navInactive,
              fontSize: 13,
            ),
          ),
          style: const TextStyle(
            color: C.white,
            fontSize: 13,
          ),
          items: [
            for (final type in SourceTypeWire.runtimeOptions)
              DropdownMenuItem(
                value: type,
                child: Text(_sourceLabel(type)),
              ),
          ],
          onChanged: _submitting
              ? null
              : (value) => setState(() {
                    _sourceType = value;
                    _error = null;
                  }),
        ),
      ),
    );
  }

  Widget _outlineButton(String label, VoidCallback action) {
    return GestureDetector(
      onTap: _submitting ? null : action,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: C.accent),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: C.accent,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  String _sourceLabel(SourceTypeWire type) {
    return switch (type) {
      SourceTypeWire.officialRules => 'Official rules',
      SourceTypeWire.officialOrganizer => 'Organizer website',
      SourceTypeWire.officialFaq => 'Official FAQ',
      SourceTypeWire.platform => 'Competition platform',
      SourceTypeWire.secondary => 'Secondary source',
      SourceTypeWire.derivedFixture => 'Internal fixture',
    };
  }

  String _fmtSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KiB';
  }
}
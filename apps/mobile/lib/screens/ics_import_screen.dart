import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../calendar/ics_import.dart';
import '../theme/app_theme.dart';
import '../viewmodels/jadwal_view_model.dart';
import '../widgets/common.dart';

typedef IcsTextPicker = Future<({String name, String content})?> Function();

class IcsImportScreen extends StatefulWidget {
  const IcsImportScreen({
    super.key,
    this.pickText,
  });

  final IcsTextPicker? pickText;

  @override
  State<IcsImportScreen> createState() => _IcsImportScreenState();
}

class _IcsImportScreenState extends State<IcsImportScreen> {
  final _parser = IcsCalendarParser();
  List<IcsImportEvent> _events = const [];
  final Set<String> _selected = {};
  String? _fileName;
  String? _error;
  bool _picking = false;
  bool _importing = false;

  Future<({String name, String content})?> _pickFromDevice() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['ics'],
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    var bytes = file.bytes;
    final path = file.path;
    if (bytes == null && path != null) {
      bytes = await File(path).readAsBytes();
    }
    if (bytes == null) {
      throw const FormatException(
        'The selected calendar file could not be read.',
      );
    }
    return (name: file.name, content: utf8.decode(bytes));
  }

  Future<void> _pick() async {
    if (_picking || _importing) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final picked = await (widget.pickText ?? _pickFromDevice)();
      if (!mounted || picked == null) return;
      final parsed = _parser.parse(picked.content);
      setState(() {
        _fileName = picked.name;
        _events = parsed.events;
        _selected.clear();
        _error = parsed.skippedCancelled == 0
            ? null
            : '${parsed.skippedCancelled} cancelled event(s) were ignored.';
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _events = const [];
        _selected.clear();
        _error = error.message.toString();
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _events = const [];
        _selected.clear();
        _error = 'The calendar file could not be opened.';
      });
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _importSelected() async {
    if (_selected.isEmpty || _importing) return;
    setState(() => _importing = true);
    final selectedEvents = _events
        .where((event) => _selected.contains(event.commitmentId))
        .toList(growable: false);
    final result =
        await context.read<JadwalViewModel>().importIcsEvents(selectedEvents);
    if (!mounted) return;
    setState(() => _importing = false);

    final messenger = ScaffoldMessenger.of(context);
    if (!result.success) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Calendar import could not be saved.')),
      );
      return;
    }

    final parts = <String>['${result.imported} imported'];
    if (result.skippedDuplicates > 0) {
      parts.add('${result.skippedDuplicates} duplicate(s) skipped');
    }
    if (result.rejected > 0) {
      parts.add('${result.rejected} unsupported event(s) skipped');
    }
    messenger.showSnackBar(SnackBar(content: Text(parts.join(' · '))));
    if (result.imported > 0) {
      Navigator.of(context).pop();
    }
  }

  String _when(IcsImportEvent event) {
    final start = DateTime.fromMillisecondsSinceEpoch(event.startAtEpochMs);
    final end = DateTime.fromMillisecondsSinceEpoch(event.endAtEpochMs);
    String two(int value) => value.toString().padLeft(2, '0');
    final date = '${two(start.day)}/${two(start.month)}/${start.year}';
    final time =
        '${two(start.hour)}:${two(start.minute)}–${two(end.hour)}:${two(end.minute)}';
    return '$date · $time · ${event.timezone}';
  }

  @override
  Widget build(BuildContext context) {
    final supportedCount = _events.where((event) => event.supported).length;
    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppHeader(
                title: 'Import Calendar',
                onBack: _importing ? null : () => Navigator.of(context).pop(),
              ),
              const HeaderDivider(),
              const SizedBox(height: 20),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: C.card,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Google Calendar export',
                      style: TextStyle(
                        color: C.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Export your Google Calendar as an .ics file, then choose it here. '
                      'Nothing is written until you review and select events below.',
                      style: TextStyle(color: C.detailMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      key: const Key('choose-ics-file'),
                      onPressed: _picking ? null : _pick,
                      icon: const Icon(Icons.upload_file_rounded),
                      label: Text(
                        _picking
                            ? 'Reading calendar…'
                            : (_fileName == null
                                ? 'Choose .ics file'
                                : 'Choose another .ics file'),
                      ),
                    ),
                    if (_fileName != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _fileName!,
                        style: const TextStyle(
                          color: C.accent,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        key: const Key('ics-import-message'),
                        style: const TextStyle(
                          color: C.accent,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_events.isNotEmpty) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_events.length} event(s) found · $supportedCount supported',
                          style: const TextStyle(
                            color: C.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        key: const Key('select-supported-ics'),
                        onPressed: _importing
                            ? null
                            : () => setState(() {
                                  _selected
                                    ..clear()
                                    ..addAll(
                                      _events
                                          .where((event) => event.supported)
                                          .map((event) => event.commitmentId),
                                    );
                                }),
                        child: const Text('Select supported'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                for (final event in _events)
                  Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    decoration: BoxDecoration(
                      color: C.card,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: CheckboxListTile(
                      key: Key('ics-event-${event.commitmentId}'),
                      value: event.supported &&
                          _selected.contains(event.commitmentId),
                      onChanged: !event.supported || _importing
                          ? null
                          : (selected) => setState(() {
                                if (selected == true) {
                                  _selected.add(event.commitmentId);
                                } else {
                                  _selected.remove(event.commitmentId);
                                }
                              }),
                      activeColor: C.accent,
                      checkColor: C.bg,
                      title: Text(
                        event.title,
                        style: const TextStyle(
                          color: C.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        event.supported
                            ? _when(event)
                            : (event.unsupportedReason ??
                                'This event cannot be imported safely.'),
                        style: const TextStyle(
                          color: C.detailMuted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: FilledButton(
                    key: const Key('import-selected-ics'),
                    onPressed:
                        _selected.isEmpty || _importing ? null : _importSelected,
                    child: Text(
                      _importing
                          ? 'Importing…'
                          : 'Import selected (${_selected.length})',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

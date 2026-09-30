import 'dart:typed_data';

import 'competition_analysis_wire.dart';

enum AnalysisSourceMode {
  pdf,
  url,
}

/// Ephemeral client draft used only to survive recoverable navigation.
///
/// PDF bytes intentionally remain in memory for the active lifecycle and are
/// never written to Drift merely to support recovery.
final class AnalysisSourceDraft {
  const AnalysisSourceDraft({
    required this.mode,
    required this.continuation,
    this.url = '',
    this.filename,
    this.bytes,
    this.sourceType,
  });

  final AnalysisSourceMode mode;
  final bool continuation;
  final String url;
  final String? filename;
  final Uint8List? bytes;
  final SourceTypeWire? sourceType;

  AnalysisSourceDraft copyWith({
    AnalysisSourceMode? mode,
    bool? continuation,
    String? url,
    String? filename,
    Uint8List? bytes,
    SourceTypeWire? sourceType,
    bool clearFile = false,
    bool clearSourceType = false,
  }) {
    return AnalysisSourceDraft(
      mode: mode ?? this.mode,
      continuation: continuation ?? this.continuation,
      url: url ?? this.url,
      filename: clearFile ? null : (filename ?? this.filename),
      bytes: clearFile ? null : (bytes ?? this.bytes),
      sourceType: clearSourceType ? null : (sourceType ?? this.sourceType),
    );
  }
}

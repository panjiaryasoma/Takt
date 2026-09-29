import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../models/analysis_failure.dart';
import '../../models/competition_analysis_wire.dart';

const maxAnalysisSourceBytes = 20 * 1024 * 1024;

class AnalysisSourceMetadata {
  const AnalysisSourceMetadata({
    required this.sourceId,
    required this.sourceType,
  });

  final String sourceId;
  final SourceTypeWire sourceType;

  Map<String, Object?> toJson() => {
        'source_id': sourceId,
        'source_type': sourceType.wire,
        'authority_rank': {'basis': sourceType.wire},
        'scope': <String, Object?>{},
        'freshness_metadata': <String, Object?>{},
      };
}

class AnalysisContinuationContext {
  const AnalysisContinuationContext({
    required this.reportBundle,
    required this.sourceArtifacts,
  });

  final Map<String, dynamic> reportBundle;
  final List<dynamic> sourceArtifacts;

  factory AnalysisContinuationContext.fromOriginalBody(
    String originalBody,
  ) {
    CompetitionAnalyzeResponseWire.parse(originalBody);
    final raw = decodeOriginalResponseMap(originalBody);
    final bundle = raw['report_bundle'];
    final artifacts = raw['source_artifacts'];
    if (bundle is! Map || artifacts is! List) {
      throw const FormatException(
        'Cached response lacks continuation context',
      );
    }
    return AnalysisContinuationContext(
      reportBundle: Map<String, dynamic>.from(bundle),
      sourceArtifacts: List<dynamic>.from(artifacts),
    );
  }
}

class CompetitionAnalysisTransportResult {
  const CompetitionAnalysisTransportResult({
    required this.originalBody,
    required this.response,
  });

  final String originalBody;
  final CompetitionAnalyzeResponseWire response;
}

abstract class CompetitionApiClient {
  Future<CompetitionAnalysisTransportResult> analyzeUrl({
    required String competitionId,
    required String url,
    required AnalysisSourceMetadata source,
    AnalysisContinuationContext? continuation,
  });

  Future<CompetitionAnalysisTransportResult> analyzePdf({
    required String competitionId,
    required String documentId,
    required String filename,
    required Uint8List bytes,
    required AnalysisSourceMetadata source,
    AnalysisContinuationContext? continuation,
  });
}

class HttpCompetitionApiClient implements CompetitionApiClient {
  HttpCompetitionApiClient({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 120),
  })  : _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  @override
  Future<CompetitionAnalysisTransportResult> analyzeUrl({
    required String competitionId,
    required String url,
    required AnalysisSourceMetadata source,
    AnalysisContinuationContext? continuation,
  }) async {
    final clean = url.trim();
    final uri = Uri.tryParse(clean);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const AnalysisFailure(
        code: 'CLIENT_VALIDATION_ERROR',
        stage: 'validation',
        message: 'URL must be absolute http/https.',
        userMessage: 'Masukkan URL http/https yang valid.',
        retryable: false,
      );
    }

    final request = http.Request(
      'POST',
      Uri.parse('$_baseUrl/api/v1/competitions/analyze/url'),
    )
      ..headers['Accept'] = 'application/json'
      ..headers['Content-Type'] = 'application/json; charset=utf-8'
      ..bodyBytes = utf8.encode(
        jsonEncode(
          buildUrlAnalysisPayload(
            competitionId: competitionId,
            url: clean,
            source: source,
            continuation: continuation,
          ),
        ),
      );

    final result = await _send(request);
    return _validateResponseIdentity(
      result,
      competitionId: competitionId,
      sourceId: source.sourceId,
    );
  }

  @override
  Future<CompetitionAnalysisTransportResult> analyzePdf({
    required String competitionId,
    required String documentId,
    required String filename,
    required Uint8List bytes,
    required AnalysisSourceMetadata source,
    AnalysisContinuationContext? continuation,
  }) async {
    if (bytes.isEmpty || bytes.length > maxAnalysisSourceBytes) {
      throw const AnalysisFailure(
        code: 'CLIENT_SOURCE_LIMIT',
        stage: 'validation',
        message: 'PDF bytes are empty or exceed 20 MiB.',
        userMessage: 'PDF harus berisi data dan maksimal 20 MiB.',
        retryable: false,
      );
    }
    if (!filename.toLowerCase().endsWith('.pdf')) {
      throw const AnalysisFailure(
        code: 'CLIENT_MEDIA_TYPE',
        stage: 'validation',
        message: 'Only PDF upload is supported.',
        userMessage: 'Upload hanya menerima file PDF.',
        retryable: false,
      );
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/api/v1/competitions/analyze/pdf'),
    )
      ..headers['Accept'] = 'application/json'
      ..fields['metadata'] = jsonEncode(
        buildPdfAnalysisMetadata(
          competitionId: competitionId,
          documentId: documentId,
          source: source,
          continuation: continuation,
        ),
      )
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: _safeFilename(filename),
          contentType: http.MediaType('application', 'pdf'),
        ),
      );

    final result = await _send(request);
    return _validateResponseIdentity(
      result,
      competitionId: competitionId,
      sourceId: source.sourceId,
    );
  }

  CompetitionAnalysisTransportResult _validateResponseIdentity(
    CompetitionAnalysisTransportResult result, {
    required String competitionId,
    required String sourceId,
  }) {
    if (result.response.report.competitionId != competitionId) {
      throw AnalysisFailure.contract(
        const FormatException(
          'Response competition_id does not match request.',
        ),
      );
    }
    if (!result.response.report.sourceIds.contains(sourceId)) {
      throw AnalysisFailure.contract(
        const FormatException(
          'Response source set does not contain submitted source.',
        ),
      );
    }
    return result;
  }

  Future<CompetitionAnalysisTransportResult> _send(
    http.BaseRequest request,
  ) async {
    try {
      final response = await _client.send(request).timeout(timeout);
      final responseBytes =
          await response.stream.toBytes().timeout(timeout);
      final originalBody = utf8.decode(responseBytes);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _backendFailure(originalBody);
      }

      try {
        return CompetitionAnalysisTransportResult(
          originalBody: originalBody,
          response:
              CompetitionAnalyzeResponseWire.parse(originalBody),
        );
      } on FormatException catch (error) {
        throw AnalysisFailure.contract(error);
      }
    } on AnalysisFailure {
      rethrow;
    } on TimeoutException catch (error) {
      throw AnalysisFailure.network(error);
    } on http.ClientException catch (error) {
      throw AnalysisFailure.network(error);
    }
  }

  AnalysisFailure _backendFailure(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map || decoded['error'] is! Map) {
        throw const FormatException('missing error envelope');
      }
      final error = decoded['error'] as Map;
      final code = error['code'];
      final stage = error['stage'];
      final message = error['message'];
      if (code is! String ||
          code.isEmpty ||
          stage is! String ||
          stage.isEmpty ||
          message is! String ||
          message.isEmpty) {
        throw const FormatException('invalid error envelope');
      }
      return AnalysisFailure.fromBackend(
        code: code,
        stage: stage,
        message: message,
      );
    } on FormatException {
      return const AnalysisFailure(
        code: 'UNKNOWN_BACKEND_ERROR',
        stage: 'unknown',
        message: 'Backend returned an unrecognized error envelope.',
        userMessage:
            'Server mengembalikan error yang belum dikenali aplikasi.',
        retryable: false,
      );
    }
  }

  static String _safeFilename(String value) {
    return value
        .replaceAll('"', '_')
        .replaceAll('\r', '_')
        .replaceAll('\n', '_');
  }

  void close() => _client.close();
}

Map<String, Object?> buildUrlAnalysisPayload({
  required String competitionId,
  required String url,
  required AnalysisSourceMetadata source,
  AnalysisContinuationContext? continuation,
}) {
  return {
    'competition_id': competitionId,
    'url': url,
    'source': source.toJson(),
    'previous_report_bundle': continuation?.reportBundle,
    'prior_source_artifacts':
        continuation?.sourceArtifacts ?? const [],
  };
}

Map<String, Object?> buildPdfAnalysisMetadata({
  required String competitionId,
  required String documentId,
  required AnalysisSourceMetadata source,
  AnalysisContinuationContext? continuation,
}) {
  return {
    'competition_id': competitionId,
    'document_id': documentId,
    'source': source.toJson(),
    'previous_report_bundle': continuation?.reportBundle,
    'prior_source_artifacts':
        continuation?.sourceArtifacts ?? const [],
  };
}

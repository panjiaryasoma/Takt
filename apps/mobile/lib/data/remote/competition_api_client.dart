import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

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
    HttpClient? httpClient,
    this.timeout = const Duration(seconds: 120),
  })  : _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
        _client = httpClient ?? HttpClient();

  final String _baseUrl;
  final HttpClient _client;
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

    final payload = <String, Object?>{
      'competition_id': competitionId,
      'url': clean,
      'source': source.toJson(),
      'previous_report_bundle': continuation?.reportBundle,
      'prior_source_artifacts':
          continuation?.sourceArtifacts ?? const [],
    };
    return _postJson(
      '/api/v1/competitions/analyze/url',
      payload,
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

    final metadata = <String, Object?>{
      'competition_id': competitionId,
      'document_id': documentId,
      'source': source.toJson(),
      'previous_report_bundle': continuation?.reportBundle,
      'prior_source_artifacts':
          continuation?.sourceArtifacts ?? const [],
    };

    final boundary =
        '----takt-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
    final body = BytesBuilder(copy: false)
      ..add(utf8.encode('--$boundary\r\n'))
      ..add(
        utf8.encode(
          'Content-Disposition: form-data; name="metadata"\r\n',
        ),
      )
      ..add(
        utf8.encode(
          'Content-Type: application/json; charset=utf-8\r\n\r\n',
        ),
      )
      ..add(utf8.encode(jsonEncode(metadata)))
      ..add(utf8.encode('\r\n--$boundary\r\n'))
      ..add(
        utf8.encode(
          'Content-Disposition: form-data; name="file"; '
          'filename="${_escapeFilename(filename)}"\r\n',
        ),
      )
      ..add(utf8.encode('Content-Type: application/pdf\r\n\r\n'))
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));

    return _postBytes(
      '/api/v1/competitions/analyze/pdf',
      body.takeBytes(),
      contentType: 'multipart/form-data; boundary=$boundary',
    );
  }

  Future<CompetitionAnalysisTransportResult> _postJson(
    String path,
    Map<String, Object?> payload,
  ) {
    return _postBytes(
      path,
      Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      contentType: 'application/json; charset=utf-8',
    );
  }

  Future<CompetitionAnalysisTransportResult> _postBytes(
    String path,
    Uint8List body, {
    required String contentType,
  }) async {
    try {
      final request = await _client
          .postUrl(Uri.parse('$_baseUrl$path'))
          .timeout(timeout);
      request.headers.set(HttpHeaders.contentTypeHeader, contentType);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.contentLength = body.length;
      request.add(body);

      final response = await request.close().timeout(timeout);
      final responseBytes = await response
          .fold<List<int>>(
            <int>[],
            (buffer, chunk) => buffer..addAll(chunk),
          )
          .timeout(timeout);
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
    } on SocketException catch (error) {
      throw AnalysisFailure.network(error);
    } on TimeoutException catch (error) {
      throw AnalysisFailure.network(error);
    } on HttpException catch (error) {
      throw AnalysisFailure.network(error);
    } on HandshakeException catch (error) {
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

  static String _escapeFilename(String value) {
    return value
        .replaceAll('"', '_')
        .replaceAll('\r', '_')
        .replaceAll('\n', '_');
  }

  void close() => _client.close(force: true);
}

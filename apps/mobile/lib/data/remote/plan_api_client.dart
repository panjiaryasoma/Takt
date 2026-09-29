import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/plan_evaluation_wire.dart';
import '../../models/reevaluation_wire.dart';
import '../../utils/deterministic_json.dart';

final class PlanApiFailure implements Exception {
  const PlanApiFailure({
    required this.code,
    required this.stage,
    required this.message,
    required this.retryable,
    this.statusCode,
    this.transportRequestJson,
    this.transportResponseJson,
    this.transition,
    this.errorJson,
  });

  final String code;
  final String stage;
  final String message;
  final bool retryable;
  final int? statusCode;
  final String? transportRequestJson;
  final String? transportResponseJson;
  final ReevaluationTransitionWire? transition;
  final String? errorJson;

  @override
  String toString() => '$code: $message';
}

final class PlanEvaluateTransportResult {
  const PlanEvaluateTransportResult({
    required this.evaluationRequestJson,
    required this.evaluationResponseJson,
    required this.response,
  });

  final String evaluationRequestJson;
  final String evaluationResponseJson;
  final PlanEvaluateResponseV1 response;
}

final class PlanReevaluateTransportResult {
  const PlanReevaluateTransportResult({
    required this.transportRequestJson,
    required this.transportResponseJson,
    required this.evaluationRequestJson,
    required this.success,
  });

  final String transportRequestJson;
  final String transportResponseJson;
  final String evaluationRequestJson;
  final PlanReevaluateSuccessWire success;
}

abstract class PlanApiClient {
  Future<PlanEvaluateTransportResult> evaluate({
    required String evaluationRequestJson,
  });

  Future<PlanReevaluateTransportResult> reevaluate({
    required String priorEvaluationId,
    required String priorEvaluationResponseJson,
    required String currentEvaluationRequestJson,
  });

  void close();
}

final class HttpPlanApiClient implements PlanApiClient {
  HttpPlanApiClient({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 45),
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  final Duration timeout;

  @override
  Future<PlanEvaluateTransportResult> evaluate({
    required String evaluationRequestJson,
  }) async {
    _requireJsonObject(evaluationRequestJson, 'evaluation request');
    final response = await _send(
      '/api/v1/plans/evaluate',
      evaluationRequestJson,
      reevaluate: false,
    );
    try {
      return PlanEvaluateTransportResult(
        evaluationRequestJson: evaluationRequestJson,
        evaluationResponseJson: response,
        response: PlanEvaluateResponseV1.parse(response),
      );
    } on FormatException catch (error) {
      throw PlanApiFailure(
        code: 'RESPONSE_CONTRACT_INVALID',
        stage: 'response',
        message: error.message,
        retryable: false,
        transportResponseJson: response,
      );
    }
  }

  @override
  Future<PlanReevaluateTransportResult> reevaluate({
    required String priorEvaluationId,
    required String priorEvaluationResponseJson,
    required String currentEvaluationRequestJson,
  }) async {
    final priorResponse =
        _requireJsonObject(priorEvaluationResponseJson, 'prior evaluation response');
    final basis = priorResponse['basis'];
    if (basis is! Map) {
      throw const PlanApiFailure(
        code: 'LOCAL_CONTEXT_INVALID',
        stage: 'reevaluation',
        message: 'Prior persisted evaluation has no valid basis.',
        retryable: false,
      );
    }
    final current =
        _requireJsonObject(currentEvaluationRequestJson, 'current evaluation request');
    final wrapper = <String, Object?>{
      'prior': {
        'evaluation_id': priorEvaluationId,
        'basis': basis,
      },
      'current': current,
    };
    final transportRequestJson = deterministicJsonEncode(wrapper);
    late final String response;
    try {
      response = await _send(
        '/api/v1/plans/re-evaluate',
        transportRequestJson,
        reevaluate: true,
      );
    } on PlanApiFailure catch (error) {
      throw PlanApiFailure(
        code: error.code,
        stage: error.stage,
        message: error.message,
        retryable: error.retryable,
        statusCode: error.statusCode,
        transportRequestJson: transportRequestJson,
        transportResponseJson: error.transportResponseJson,
        transition: error.transition,
        errorJson: error.errorJson,
      );
    }
    try {
      return PlanReevaluateTransportResult(
        transportRequestJson: transportRequestJson,
        transportResponseJson: response,
        evaluationRequestJson: currentEvaluationRequestJson,
        success: PlanReevaluateSuccessWire.parse(response),
      );
    } on FormatException catch (error) {
      throw PlanApiFailure(
        code: 'RESPONSE_CONTRACT_INVALID',
        stage: 'reevaluation',
        message: error.message,
        retryable: false,
        transportResponseJson: response,
      );
    }
  }

  Future<String> _send(
    String path,
    String body, {
    required bool reevaluate,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse(baseUrl + path),
            headers: const {'content-type': 'application/json'},
            body: body,
          )
          .timeout(timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.body;
      }
      throw _backendFailure(
        response.body,
        response.statusCode,
        reevaluate: reevaluate,
      );
    } on PlanApiFailure {
      rethrow;
    } on TimeoutException catch (error) {
      throw PlanApiFailure(
        code: 'TIMEOUT',
        stage: 'network',
        message: error.toString(),
        retryable: true,
      );
    } on http.ClientException catch (error) {
      throw PlanApiFailure(
        code: 'NETWORK',
        stage: 'network',
        message: error.toString(),
        retryable: true,
      );
    }
  }

  PlanApiFailure _backendFailure(
    String body,
    int statusCode, {
    required bool reevaluate,
  }) {
    if (reevaluate) {
      try {
        final parsed = PlanReevaluateErrorWire.parse(body);
        return PlanApiFailure(
          code: parsed.code,
          stage: parsed.stage,
          message: parsed.message,
          retryable: _retryable(parsed.code, statusCode),
          statusCode: statusCode,
          transportResponseJson: body,
          transition: parsed.transition,
          errorJson: parsed.errorJson,
        );
      } on FormatException {
        return PlanApiFailure(
          code: 'UNKNOWN_BACKEND_ERROR',
          stage: 'unknown',
          message: 'Backend returned an unrecognized re-evaluation error.',
          retryable: false,
          statusCode: statusCode,
          transportResponseJson: body,
        );
      }
    }

    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map || decoded['error'] is! Map) {
        throw const FormatException('missing error envelope');
      }
      final error = Map<String, dynamic>.from(decoded['error'] as Map);
      final code = error['code'];
      final stage = error['stage'];
      final message = error['message'];
      if (code is! String ||
          code.trim().isEmpty ||
          stage is! String ||
          stage.trim().isEmpty ||
          message is! String ||
          message.trim().isEmpty) {
        throw const FormatException('invalid error envelope');
      }
      return PlanApiFailure(
        code: code,
        stage: stage,
        message: message,
        retryable: _retryable(code, statusCode),
        statusCode: statusCode,
        transportResponseJson: body,
        errorJson: deterministicJsonEncode(error),
      );
    } on FormatException {
      return PlanApiFailure(
        code: 'UNKNOWN_BACKEND_ERROR',
        stage: 'unknown',
        message: 'Backend returned an unrecognized planning error.',
        retryable: false,
        statusCode: statusCode,
        transportResponseJson: body,
      );
    }
  }

  static bool _retryable(String code, int statusCode) {
    if (code == 'VALIDATION_ERROR' ||
        code == 'PLANNING_INPUT_INVALID' ||
        code == 'REPORT_BUNDLE_INVALID' ||
        code == 'UNSUPPORTED_REPORT_CONTRACT' ||
        code == 'REEVALUATION_CONTEXT_INVALID' ||
        code == 'UNSUPPORTED_REEVALUATION_CONTRACT') {
      return false;
    }
    return statusCode >= 500;
  }

  static Map<String, dynamic> _requireJsonObject(
    String raw,
    String field,
  ) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('not object');
      }
      return Map<String, dynamic>.from(decoded);
    } on Object {
      throw PlanApiFailure(
        code: 'LOCAL_CONTEXT_INVALID',
        stage: 'local',
        message: '$field is not valid JSON.',
        retryable: false,
      );
    }
  }

  @override
  void close() => _client.close();
}

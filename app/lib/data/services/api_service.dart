/// The app's ONLY outbound HTTP dependency: our own proxy.
///
/// No LLM SDK, no provider URL, no API key — that is the whole point of the
/// proxy architecture (research 07 §2) and it is what makes AC6 checkable.
library;

import 'package:dio/dio.dart';

import '../../core/app_config.dart';
import '../checks/rubric_config.dart';
import '../models/review_models.dart';
import 'review_api.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.isRetryable = false});

  /// Message written for the person in front of the screen, not for a log file.
  final String message;
  final int? statusCode;
  final bool isRetryable;

  @override
  String toString() => message;
}

class ApiService implements ReviewApi {
  ApiService({Dio? dio, String? baseUrl, String? appToken, String? userId})
    : effectiveBaseUrl = baseUrl ?? AppConfig.apiBaseUrl,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl ?? AppConfig.apiBaseUrl,
              connectTimeout: AppConfig.connectTimeout,
              receiveTimeout: AppConfig.requestTimeout,
              sendTimeout: AppConfig.requestTimeout,
              contentType: Headers.jsonContentType,
            ),
          ) {
    // Identity headers. The proxy's `require_app_token` and per-user rate
    // limiter read these; without them the server can only fall back to the
    // caller's IP, which is neither a user nor a secret. Both are optional so
    // a localhost demo with APP_TOKEN unset keeps working untouched.
    final token = appToken?.trim() ?? '';
    if (token.isNotEmpty) _dio.options.headers['X-App-Token'] = token;
    final user = userId?.trim() ?? '';
    if (user.isNotEmpty) _dio.options.headers['X-User-Id'] = user;
  }

  /// The base this instance actually talks to — surfaced in error messages
  /// and useful in tests asserting the Settings override took effect.
  final String effectiveBaseUrl;

  final Dio _dio;

  @override
  Future<bool> isProxyUp() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/health');
      return response.data?['status'] == 'ok';
    } on DioException {
      return false;
    }
  }

  @override
  Future<RubricConfig> fetchRubric() async {
    final data = await _get('/rubric');
    return RubricConfig.fromJson(data);
  }

  @override
  Future<ReviewResult> review({
    required String requirementId,
    required String text,
    String? section,
    int? pageIndex,
    CancelToken? cancelToken,
  }) async {
    final data = await _post('/review', {
      'requirement_id': requirementId,
      'text': text,
      'section': ?section,
      'page_index': ?pageIndex,
    }, cancelToken: cancelToken);
    return ReviewResult.fromJson(data);
  }

  @override
  Future<AskResponse> ask({
    required String question,
    required String context,
    int? pageIndex,
    CancelToken? cancelToken,
  }) async {
    final data = await _post('/ask', {
      'question': question,
      'context': context,
      'page_index': ?pageIndex,
    }, cancelToken: cancelToken);
    return AskResponse.fromJson(data);
  }

  Future<Map<String, dynamic>> _get(String path) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(path);
      return response.data ??
          (throw ApiException('The proxy returned an empty body.'));
    } on DioException catch (error) {
      throw _translate(error, effectiveBaseUrl);
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        path,
        data: body,
        cancelToken: cancelToken,
      );
      return response.data ??
          (throw ApiException('The proxy returned an empty body.'));
    } on DioException catch (error) {
      throw _translate(error, effectiveBaseUrl);
    }
  }

  /// Turns transport failures into sentences a student can act on. Takes the
  /// effective base URL because the useful message names the endpoint the
  /// user actually configured (Settings override or build-time default).
  static ApiException _translate(DioException error, String baseUrl) {
    final status = error.response?.statusCode;
    return switch (error.type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout => ApiException(
        'Cannot reach the review proxy at $baseUrl. '
        'Start it with "uvicorn app.main:app --reload" in server/, or switch on mock mode.',
        isRetryable: true,
      ),
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout => ApiException(
        'The review took longer than ${AppConfig.requestTimeout.inSeconds}s and timed out.',
        isRetryable: true,
      ),
      DioExceptionType.cancel => ApiException('Review cancelled.'),
      _ => switch (status) {
        401 => ApiException(
          'The proxy rejected the app token.',
          statusCode: 401,
        ),
        422 => ApiException(
          'The proxy rejected the request payload — the app and proxy contracts disagree.',
          statusCode: 422,
        ),
        429 => ApiException(
          'Daily review quota reached. Reuse a cached result or try again tomorrow.',
          statusCode: 429,
        ),
        502 || 503 => ApiException(
          'The AI provider is unavailable right now. Retry, or run in mock mode for the demo.',
          statusCode: status,
          isRetryable: true,
        ),
        _ => ApiException(
          'Unexpected proxy error${status == null ? '' : ' (HTTP $status)'}.',
          statusCode: status,
        ),
      },
    };
  }
}

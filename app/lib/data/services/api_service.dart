/// The app's ONLY outbound HTTP dependency: our own proxy.
///
/// No LLM SDK, no provider URL, no API key — that is the whole point of the
/// proxy architecture (research 07 §2) and it is what makes AC6 checkable.
library;

import 'package:dio/dio.dart';

import '../../core/app_config.dart';
import '../checks/rubric_config.dart';
import '../models/ai_criterion.dart';
import '../models/diagram_audit.dart';
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

  // ---------------------------------------------------------------- criteria
  //
  // The editable evaluation checklist (2026-09-25). Read through `_get` so a
  // flaky connection is retried; written through `_write` so it is NOT — a
  // repeated POST would create the row twice and a repeated PUT would fight the
  // user who is editing the same row in another window.

  /// The proxy's live criteria, or an empty list when it cannot be reached.
  Future<List<AiCriterion>> fetchCriteria() async {
    final data = await _get('/criteria');
    final rows = (data['criteria'] as List<dynamic>? ?? const []);
    return rows
        .map((row) => AiCriterion.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<CriteriaStats> fetchCriteriaStats() async {
    final data = await _get('/criteria');
    return CriteriaStats.fromJson(data['stats'] as Map<String, dynamic>?);
  }

  Future<AiCriterion> createCriterion(AiCriterion criterion) async {
    final data = await _write('POST', '/criteria', criterion.toJson());
    return AiCriterion.fromJson(data['criterion'] as Map<String, dynamic>);
  }

  /// Partial update: only the keys in [patch] change. The id itself is not
  /// patchable — it is what every existing finding's `type` points at.
  Future<AiCriterion> updateCriterion(
    String id,
    Map<String, dynamic> patch,
  ) async {
    final data = await _write('PUT', '/criteria/$id', patch);
    return AiCriterion.fromJson(data['criterion'] as Map<String, dynamic>);
  }

  Future<void> deleteCriterion(String id) async {
    await _write('DELETE', '/criteria/$id');
  }

  Future<List<AiCriterion>> resetCriteria() async {
    final data = await _write('POST', '/criteria/reset');
    final rows = (data['criteria'] as List<dynamic>? ?? const []);
    return rows
        .map((row) => AiCriterion.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// One entry point for the three write verbs. No retry, on purpose: a criteria
  /// edit is a human decision, and repeating it behind their back is worse than
  /// showing the error.
  Future<Map<String, dynamic>> _write(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    try {
      final response = switch (method) {
        'POST' => await _dio.post<Map<String, dynamic>>(path, data: body),
        'PUT' => await _dio.put<Map<String, dynamic>>(path, data: body),
        _ => await _dio.delete<Map<String, dynamic>>(path),
      };
      return response.data ??
          (throw ApiException('The proxy returned an empty body.'));
    } on DioException catch (error) {
      throw _translate(error, effectiveBaseUrl);
    }
  }

  @override
  Future<ReviewResult> review({
    required String requirementId,
    required String text,
    String? section,
    int? pageIndex,
    String? imageB64,
    CancelToken? cancelToken,
  }) async {
    final body = <String, dynamic>{
      'requirement_id': requirementId,
      'text': text,
      'section': ?section,
      'page_index': ?pageIndex,
    };
    if (imageB64 != null) {
      body['image_b64'] = imageB64;
    }
    final data = await _post('/review', body, cancelToken: cancelToken);
    return ReviewResult.fromJson(data);
  }

  @override
  Future<BatchReviewOutcome> reviewBatch(
    List<BatchReviewUnit> units, {
    CancelToken? cancelToken,
  }) async {
    final data = await _post('/review/batch', {
      'units': [for (final unit in units) unit.toJson()],
    }, cancelToken: cancelToken);
    return BatchReviewOutcome.fromJson(data, requestedUnits: units.length);
  }

  @override
  Future<DiagramAuditResult> diagramAudit(
    DiagramAuditRequest request, {
    CancelToken? cancelToken,
  }) async {
    final data = await _post(
      '/diagram',
      request.toJson(),
      cancelToken: cancelToken,
    );
    return DiagramAuditResult.fromJson(data);
  }

  @override
  Future<String> shareReport({
    required String html,
    required String fileName,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/share',
      data: {'html': html, 'file_name': fileName},
    );
    final url = response.data?['url'] as String?;
    if (url == null || response.statusCode != 200) {
      throw StateError('share response carried no url');
    }
    // The server answers with a path; the user gets a link. resolve()
    // against the configured proxy base so the result is absolute on any
    // deployment (localhost demo or https://proxy).
    return Uri.parse(_dio.options.baseUrl).resolve(url).toString();
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

  /// Extra attempts after the first for a retryable failure (so up to three
  /// round trips), and the pause before each, doubled every attempt.
  static const int _maxRetries = 2;
  static const Duration _retryBaseDelay = Duration(milliseconds: 400);

  /// Re-runs [call] when it fails with a retryable [ApiException].
  ///
  /// Phone networks drop packets. A request that failed on a flaky connection
  /// is worth another attempt, and the cost is a few hundred milliseconds
  /// against a review that already takes seconds per requirement.
  ///
  /// What is NEVER retried:
  /// * **final answers** — a quota rejection (429) or a contract mismatch
  ///   (422) fails identically next time, so retrying only delays the message
  ///   the user needs to read. [_translate] marks only transient failures
  ///   `isRetryable`, which is what this decision hangs on.
  /// * **a cancelled run** — a cancelled [cancelToken] means the user asked to
  ///   stop; retrying would ignore them and burn quota.
  /// * **anything that is not an [ApiException]** — a contract violation, say.
  ///
  /// Safe because every call in this class is idempotent: `/health` and
  /// `/rubric` are reads, and `/review` is keyed by requirement and answered
  /// from the proxy's cache on a repeat.
  ///
  /// Deliberately NOT applied to [isProxyUp]: that probe drives the
  /// connection pill and must answer immediately, not after backoff.
  Future<T> _withRetry<T>(
    Future<T> Function() call, {
    CancelToken? cancelToken,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        return await call();
      } on ApiException catch (error) {
        if (!error.isRetryable ||
            attempt >= _maxRetries ||
            (cancelToken?.isCancelled ?? false)) {
          rethrow;
        }
        attempt++;
        await Future<void>.delayed(_retryBaseDelay * (1 << (attempt - 1)));
      }
    }
  }

  Future<Map<String, dynamic>> _get(String path) =>
      _withRetry(() => _getOnce(path));

  Future<Map<String, dynamic>> _getOnce(String path) async {
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
  }) => _withRetry(
    () => _postOnce(path, body, cancelToken: cancelToken),
    cancelToken: cancelToken,
  );

  Future<Map<String, dynamic>> _postOnce(
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

  /// 429 message reporting the truthful retry window (M3 gate: báo cửa sổ
  /// có thể gọi lại). The proxy sends Retry-After seconds when the daily
  /// quota is exhausted; without one, fall back to the day-scale hint.
  static String quotaMessage({int? retryAfterSeconds}) {
    final seconds = retryAfterSeconds;
    if (seconds == null || seconds <= 0) {
      return 'Daily review quota reached. '
          'Reuse a cached result or try again tomorrow.';
    }
    if (seconds >= 5400) {
      return 'Daily review quota reached. '
          'Retry in about ${(seconds / 3600).ceil()} h.';
    }
    return 'Daily review quota reached. '
        'Retry in about ${(seconds / 60).ceil()} min.';
  }

  static int? _retryAfterSeconds(Response<dynamic>? response) {
    final raw = response?.headers.value('retry-after')?.trim();
    return raw == null || raw.isEmpty ? null : int.tryParse(raw);
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
          quotaMessage(retryAfterSeconds: _retryAfterSeconds(error.response)),
          statusCode: 429,
        ),
        // 502 means the PROXY already retried the provider and gave up (it
        // paces its own calls and honours the provider's retry window).
        // Retrying the same unit here would multiply that load by the client
        // attempt count — measured 2026-09-22: 414 app requests for 238
        // reviewed units, 176 of them a 502, each one triggering 2-6 upstream
        // calls the proxy had already decided were hopeless. Fail fast and let
        // the run report the unit as failed.
        502 => ApiException(
          'The AI provider is throttled or unavailable. The proxy already retried; '
          'wait a moment and re-run the failed requirements.',
          statusCode: 502,
        ),
        // 503 comes from the platform in front of the proxy (cold start,
        // deploy) and is worth one more attempt — nothing was reviewed yet.
        503 => ApiException(
          'The review proxy is temporarily unavailable. Retrying…',
          statusCode: 503,
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

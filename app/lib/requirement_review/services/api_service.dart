/// The app's ONLY outbound HTTP dependency: our own proxy.
///
/// No LLM SDK, no provider URL, no API key — that is the whole point of the
/// proxy architecture (research 07 §2) and it is what makes AC6 checkable.
library;

import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/app_config.dart';
import '../../deterministic_checks/checks/rubric_config.dart';
import '../../deterministic_checks/models/ai_criterion.dart';
import '../../diagram_audit/models/diagram_audit.dart';
import '../models/review_models.dart';
import 'review_api.dart';

class ApiException implements Exception {
  ApiException(
    this.message, {
    this.statusCode,
    this.isRetryable = false,
    this.detail,
  });

  /// Message written for the person in front of the screen, not for a log file.
  final String message;
  final int? statusCode;
  final bool isRetryable;

  /// The proxy's own machine-readable reason (`detail` in its error body),
  /// when it sent one. The client uses this to pick between DIFFERENT user
  /// actions — WP5: the two 409 reasons of `POST /submissions/{id}/decision`
  /// (`not_in_class` → file the submission; `class_missing` → recreate the
  /// class) are two different sentences on screen, and only this field can
  /// carry which one happened. `null` when the body named no reason.
  final String? detail;

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

    // The session cookie is attached in an INTERCEPTOR rather than only in
    // `setSessionCookie`, for one concrete reason: a token can arrive after an
    // ApiService already exists (sign-in happens on a screen the service was
    // built before), and setting a header on an instance nobody re-reads is how
    // the next request goes out unauthenticated while looking configured.
    //
    // `/auth/login` and `/auth/register` are skipped deliberately. Sending a
    // stale cookie to login means a server that reads it before the body signs
    // the request in as the OLD user — change-account flows fail in a way that
    // looks like the password being wrong.
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final path = options.path;
          final isSignIn =
              path.endsWith('/auth/login') || path.endsWith('/auth/register');
          final cookie = _sessionCookie;
          // The interceptor is the ONLY writer of this header, and it both
          // sets and REMOVES. An earlier version also assigned the header on
          // the Dio options and let the interceptor merely overwrite it — which
          // sent the stale cookie to `/auth/login` (the interceptor skipped the
          // assignment, but the options-level header was already on the
          // request). A test caught it; a request-scoped decision has to be
          // made in one place, per request.
          if (!isSignIn && cookie != null && cookie.isNotEmpty) {
            options.headers['Cookie'] = cookie;
          } else {
            options.headers.remove('Cookie');
          }
          handler.next(options);
        },
      ),
    );
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

  /// Writes the syllabus thresholds and the grading weights (2026-09-25).
  ///
  /// Through `_write`, so a failed PUT is NOT retried behind the user's back:
  /// re-sending a reweighting could land on top of an edit they made in another
  /// window since the first attempt. The returned rubric is the one the proxy now
  /// serves, which is what the UI must render — not the values it sent.
  Future<RubricConfig> updateRubric(Map<String, dynamic> patch) async {
    final data = await _write('PUT', '/rubric', patch);
    return RubricConfig.fromJson(data['rubric'] as Map<String, dynamic>);
  }

  /// Back to the committed seed rubric, discarding every override.
  Future<RubricConfig> resetRubric() async {
    final data = await _write('POST', '/rubric/reset');
    return RubricConfig.fromJson(data['rubric'] as Map<String, dynamic>);
  }

  /// Public write entry for feature repositories that own their own routes
  /// (the teacher feature, WP5). Same no-retry rule as [_write]: a repeat of
  /// a human decision or a filing is a SECOND write, not a retry.
  Future<Map<String, dynamic>> write(
    String path, {
    String method = 'POST',
    Map<String, dynamic>? body,
    String? writeKey,
  }) => _write(method, path, body, writeKey);

  /// The RAW response of a write, headers included.
  ///
  /// Exists for exactly one caller: signing in. `POST /auth/login` answers the
  /// session in a `Set-Cookie` HEADER and a body that does not carry it, and
  /// every other method here returns `response.data`, which throws the headers
  /// away. Returning the whole response is narrower than teaching `write` about
  /// cookies, and it keeps the knowledge of "which route answers with a cookie"
  /// in the auth service rather than in the transport.
  ///
  /// Note what is returned: the value only. A session token must never reach a
  /// log line, and the cheapest way to guarantee that is to not have code whose
  /// job is to format one.
  Future<Response<Map<String, dynamic>>> rawWrite(
    String path, {
    String method = 'POST',
    Map<String, dynamic>? body,
  }) async {
    try {
      return await _dio.request<Map<String, dynamic>>(
        path,
        data: body,
        options: Options(method: method),
      );
    } on DioException catch (error) {
      throw _translate(error, effectiveBaseUrl);
    }
  }

  /// Attaches the session cookie to EVERY later request, or removes it.
  ///
  /// Set on the Dio instance rather than passed per call, because a route that
  /// forgot it would look like a permissions bug ("you are not signed in") when
  /// the real fault is one missing header — and every authenticated route the
  /// app grows would have to remember. Passing `null` clears the header, which
  /// is what sign-out does.
  void setSessionCookie(String? cookieHeader) {
    if (cookieHeader == null || cookieHeader.isEmpty) {
      // Clearing means the interceptor's `else` branch removes the header, so
      // nothing empty is ever sent. An empty `Cookie:` is still a header, and a
      // proxy that logs it sees a request carrying an empty credential rather
      // than one carrying none.
      _sessionCookie = null;
      return;
    }
    // Deliberately NOT set on `_dio.options.headers`: that header rides on
    // every request including `/auth/login`, and the per-request decision
    // belongs to the interceptor above. This field is the single source it
    // reads.
    _sessionCookie = cookieHeader;
  }

  String? _sessionCookie;

  /// Public read entry for feature repositories. Config-read semantics: the
  /// screen's own 4s deadline and no hidden retry, so a dead proxy answers
  /// fast instead of hanging the screen.
  Future<Map<String, dynamic>> get(String path) => _get(path);

  /// One entry point for the four write verbs. No retry, on purpose: a criteria
  /// edit is a human decision, and repeating it behind their back is worse than
  /// showing the error.
  Future<Map<String, dynamic>> _write(
    String method,
    String path, [
    Map<String, dynamic>? body,
    String? writeKey,
  ]) async {
    try {
      // The class key rides on EVERY verb that can carry it — the decision
      // route and filing are POSTs, and forgetting the key there would turn
      // every decision into a 401 while PATCH worked. `_keyOptions` returns
      // null when no key is given, so ordinary writes stay byte-identical.
      final response = switch (method) {
        'POST' => await _dio.post<Map<String, dynamic>>(
          path,
          data: body,
          options: _keyOptions(writeKey),
        ),
        'PUT' => await _dio.put<Map<String, dynamic>>(
          path,
          data: body,
          options: _keyOptions(writeKey),
        ),
        'PATCH' => await _dio.patch<Map<String, dynamic>>(
          path,
          data: body,
          options: _keyOptions(writeKey),
        ),
        'DELETE' => await _dio.delete<Map<String, dynamic>>(
          path,
          options: _keyOptions(writeKey),
        ),
        _ => throw ArgumentError.value(
          method,
          'method',
          'unsupported write verb',
        ),
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

  /// Config reads — `/rubric`, `/criteria` — with the screen's own deadline and
  /// NO hidden retry.
  ///
  /// The retry in [_withRetry] exists for work that was going to cost the user
  /// real time or quota: a dropped connection mid-review should be re-sent. A
  /// config read is neither. Retrying it only delayed the message, and measured on
  /// 2026-09-26 a dead proxy kept the criteria screen on a spinner for 7.4s
  /// (refused port) to ~31s (unreachable host) before the user learned anything.
  /// The screen already has a "Thử lại" button, so one click is strictly better
  /// than a retry the user cannot see and cannot cancel.
  /// Config reads — `/rubric`, `/criteria` — with the screen's own deadline and
  /// NO hidden retry.
  ///
  /// The retry in [_withRetry] exists for work that was going to cost the user
  /// real time or quota: a dropped connection mid-review should be re-sent. A
  /// config read is neither. Retrying it only delayed the message, and measured on
  /// 2026-09-26 a dead proxy kept the criteria screen on a spinner for 7.4s
  /// (refused port) to ~31s (unreachable host) before the user learned anything.
  /// The screen already has a "Thử lại" button, so one click is strictly better
  /// than a retry the user cannot see and cannot cancel.
  Future<Map<String, dynamic>> _get(String path) async {
    try {
      return await _getOnce(path).timeout(AppConfig.configReadTimeout);
    } on TimeoutException {
      throw ApiException(
        'The review proxy at $effectiveBaseUrl did not answer in '
        '${AppConfig.configReadTimeout.inSeconds}s. '
        'Start it with "uvicorn app.main:app --reload" in server/, '
        'or switch on mock mode.',
      );
    }
  }

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

  /// Header options carrying the class's own `write_key` in `X-Class-Key` —
  /// the credential ADR-0017 assigns to PATCH/DELETE/filing/decisions. `null`
  /// when the verb needs no class key, so ordinary writes stay byte-identical
  /// on the wire.
  Options? _keyOptions(String? writeKey) {
    final key = writeKey?.trim() ?? '';
    if (key.isEmpty) return null;
    return Options(headers: {'X-Class-Key': key});
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

  /// The proxy's machine-readable reason for this failure, when the body
  /// carried one (`{"detail": "not_in_class"}`). Read once here so every
  /// branch below inherits it — including the generic one, which is where an
  /// unfamiliar status with a named detail lands.
  static String? _detailOf(Response<dynamic>? response) {
    final data = response?.data;
    if (data is Map<String, dynamic>) {
      final detail = data['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
    }
    return null;
  }

  /// Turns transport failures into sentences a student can act on. Takes the
  /// effective base URL because the useful message names the endpoint the
  /// user actually configured (Settings override or build-time default).
  static ApiException _translate(DioException error, String baseUrl) {
    final status = error.response?.statusCode;
    final detail = _detailOf(error.response);
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
          detail: detail,
        ),
        422 => ApiException(
          'The proxy rejected the request payload — the app and proxy contracts disagree.',
          statusCode: 422,
          detail: detail,
        ),
        429 => ApiException(
          quotaMessage(retryAfterSeconds: _retryAfterSeconds(error.response)),
          statusCode: 429,
          detail: detail,
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
          detail: detail,
        ),
        // 503 comes from the platform in front of the proxy (cold start,
        // deploy) and is worth one more attempt — nothing was reviewed yet.
        503 => ApiException(
          'The review proxy is temporarily unavailable. Retrying…',
          statusCode: 503,
          isRetryable: true,
          detail: detail,
        ),
        _ => ApiException(
          'Unexpected proxy error${status == null ? '' : ' (HTTP $status)'}.',
          statusCode: status,
          detail: detail,
        ),
      },
    };
  }
}

/// The seam between "real proxy" and "offline demo".
///
/// Repositories depend on this interface only, so mock mode is a constructor
/// argument rather than an `if` scattered through the app (AC4).
library;

import 'package:dio/dio.dart';

import '../../deterministic_checks/checks/rubric_config.dart';
import '../../diagram_audit/models/diagram_audit.dart';
import '../models/review_models.dart';

abstract interface class ReviewApi {
  Future<bool> isProxyUp();

  Future<RubricConfig> fetchRubric();

  Future<ReviewResult> review({
    required String requirementId,
    required String text,
    String? section,
    int? pageIndex,
    String? imageB64,
    CancelToken? cancelToken,
  });

  /// Review several text-only units in one provider call (`/review/batch`).
  ///
  /// Returns an outcome keyed by each unit's index in [units], so a partial
  /// failure can never shift a score onto the wrong requirement. Callers that
  /// hold a page image must use [review] instead.
  Future<BatchReviewOutcome> reviewBatch(
    List<BatchReviewUnit> units, {
    CancelToken? cancelToken,
  });

  /// Two-call vision audit of one diagram page (`/diagram`).
  Future<DiagramAuditResult> diagramAudit(
    DiagramAuditRequest request, {
    CancelToken? cancelToken,
  });

  /// Upload a finished HTML report to the proxy's share store and return
  /// the absolute, unguessable URL (`/share/<id>`). The link IS the read
  /// credential — plan 6. Throws on transport/HTTP failure; callers decide
  /// how honestly to report it.
  Future<String> shareReport({required String html, required String fileName});

  Future<AskResponse> ask({
    required String question,
    required String context,
    int? pageIndex,
    CancelToken? cancelToken,
  });
}

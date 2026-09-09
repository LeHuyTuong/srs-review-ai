/// The seam between "real proxy" and "offline demo".
///
/// Repositories depend on this interface only, so mock mode is a constructor
/// argument rather than an `if` scattered through the app (AC4).
library;

import 'package:dio/dio.dart';

import '../checks/rubric_config.dart';
import '../models/review_models.dart';

abstract interface class ReviewApi {
  Future<bool> isProxyUp();

  Future<RubricConfig> fetchRubric();

  Future<ReviewResult> review({
    required String requirementId,
    required String text,
    String? section,
    int? pageIndex,
    CancelToken? cancelToken,
  });

  Future<AskResponse> ask({
    required String question,
    required String context,
    int? pageIndex,
    CancelToken? cancelToken,
  });
}

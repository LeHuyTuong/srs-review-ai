/// ViewModel for the document screen. Holds UI state, exposes commands, and
/// never imports a widget library (enforced by tools/check_guardrails.py).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/models/srs_document.dart';
import '../../../data/repositories/document_repository.dart';

enum DocumentStatus { empty, loading, ready, error }

class DocumentState {
  const DocumentState({
    this.status = DocumentStatus.empty,
    this.document,
    this.errorMessage,
    this.isScannedPdf = false,
  });

  final DocumentStatus status;
  final LoadedDocument? document;
  final String? errorMessage;

  /// Distinguishes "we cannot read this" from "this is a scan, OCR is out of
  /// scope" — the second deserves its own message (research 06).
  final bool isScannedPdf;

  bool get hasDocument => document != null;

  DocumentState copyWith({
    DocumentStatus? status,
    LoadedDocument? document,
    String? errorMessage,
    bool? isScannedPdf,
  }) => DocumentState(
    status: status ?? this.status,
    document: document ?? this.document,
    errorMessage: errorMessage,
    isScannedPdf: isScannedPdf ?? false,
  );
}

class DocumentViewModel extends Notifier<DocumentState> {
  @override
  DocumentState build() => const DocumentState();

  Future<void> pickDocument() async {
    state = const DocumentState(status: DocumentStatus.loading);
    final repository = ref.read(documentRepositoryProvider);
    try {
      final loaded = await repository.pickAndParse();
      if (loaded == null) {
        state = const DocumentState();
        return;
      }
      state = DocumentState(status: DocumentStatus.ready, document: loaded);
    } on ParseException catch (error) {
      state = DocumentState(
        status: DocumentStatus.error,
        errorMessage: error.message,
        isScannedPdf: error.isScannedPdf,
      );
    } on Object catch (error) {
      state = DocumentState(
        status: DocumentStatus.error,
        errorMessage: 'Could not read the file: $error',
      );
    }
  }

  void clear() {
    ref.read(documentRepositoryProvider).clear();
    state = const DocumentState();
  }
}

final documentViewModelProvider =
    NotifierProvider<DocumentViewModel, DocumentState>(DocumentViewModel.new);

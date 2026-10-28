/// The "ask the document" path: a question is matched against the units the
/// import produced, and only a question with no local match goes to the proxy.
part of '../workspace_view_model.dart';

final class AskController extends WorkspaceController {
  AskController(super.vm);

  /// Offline keyword search — kept because it is the fallback engine and the
  /// only one available in mock mode.
  List<WorkspaceUnit> askDocument(String question) =>
      AskDocument.search(question, state.units);

  /// Answers one question about the loaded document.
  ///
  /// Prefers the proxy and falls back to the local search, and — critically —
  /// reports which one answered. Before this existed the modal could only ever
  /// call [askDocument], so the proxy's `/ask`, its citation verification and
  /// its "not found" guard were all unreachable code while the app advertised
  /// grounded Q&A as a feature.
  Future<AskOutcome> askQuestion(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty) {
      return const AskOutcome(
        engine: AskEngine.offlineSearch,
        answer: '',
        grounded: false,
      );
    }

    final offline = AskDocument.search(trimmed, state.units);
    if (offline.isEmpty) {
      // Nothing in the inventory mentions it. Asking the model anyway would be
      // paying for a guess, and the honest answer is that the document says
      // nothing — so no engine runs and no token is spent.
      return const AskOutcome(
        engine: AskEngine.offlineSearch,
        answer: 'Not found in the document.',
        grounded: false,
      );
    }

    if (ref.read(mockModeProvider)) {
      return AskOutcome(
        engine: AskEngine.offlineSearch,
        answer: '',
        grounded: true,
        units: offline,
      );
    }

    final context = AskDocument.contextFor(trimmed, state.units);
    final repository = ref.read(reviewRepositoryProvider);
    try {
      final response = await repository.ask(
        question: trimmed,
        context: context,
      );
      return AskOutcome(
        engine: AskEngine.model,
        answer: response.answer,
        grounded: response.grounded,
        citations: response.citations,
        model: response.model,
      );
    } on Object catch (error) {
      // A dead proxy used to surface as an empty answer and no explanation.
      // Fall back to what this device can answer and say that is what happened,
      // labelling the engine so the fallback is never mistaken for the model.
      return AskOutcome(
        engine: AskEngine.offlineSearch,
        answer: '',
        grounded: true,
        units: offline,
        note:
            'The proxy could not answer (${_shortError(error)}). These are '
            'the matching passages from your document instead — no model was '
            'involved.',
      );
    }
  }

  static String _shortError(Object error) {
    final text = '$error';
    return text.length <= 120 ? text : '${text.substring(0, 117)}…';
  }
}

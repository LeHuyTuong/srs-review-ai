/// The three sub-tabs of the Document review destination.
///
/// This enum lives in `models/` and not in `view/` for one concrete reason:
/// `tools/check_guardrails.py` bans `features/**/view_model/**` from importing
/// anything under `/view/`. The sub-tab has to be driven from a shortcut
/// command, so it has to be reachable from a controller — and a controller
/// cannot import a widget file. Moving the enum one directory down is what
/// makes `⌘⇧I` possible without weakening the layering rule.
///
/// It imports nothing at all, which is the correct amount of dependency for a
/// three-value enum.
library;

enum WorkspaceTab { inventory, findings, syllabus }

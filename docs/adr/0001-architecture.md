# ADR 0001 — Architecture and scope

Status: accepted · 2026-09-09

## Context

FPTU SEP490 capstone. The app reviews the SRS (Report 3) only. Targets are
Android and Windows desktop. Three weeks, a team of four to five, and a defense
where a broken demo costs more than a missing feature.

## Decisions

| # | Decision | Chosen | Why |
|---|---|---|---|
| D1 | MVP scope | Upload SRS → parse → review each requirement → cited feedback → export | This is the spine; everything else is polish |
| D2 | Platforms | Android + Windows (macOS added for local dev) | One codebase; desktop is the assignment's highlight |
| D3 | Architecture | MVVM per the Flutter app architecture guide: UI layer (View + ViewModel) / data layer (Repository + Service). **No domain layer** | The guide says add use-cases only when logic repeats; it does not here |
| D4 | Roles | One role: the student reviewing their own SRS | A supervisor dashboard is the biggest scope risk available and adds no marks |
| D5 | Parsing | Client-side in Dart | No parsing infrastructure to run; the proxy stays ~300 lines |
| D6 | LLM access | Thin FastAPI proxy holding the key | See below |
| D7 | Model | `gemini-2.5-flash-lite`, falling back to `gemini-2.5-flash` | Free tier is enough; one env var switches quality |
| D8 | Anti-hallucination | Every issue must quote the source; the proxy verifies the quote and drops unverifiable issues | The core technical claim of the project |

## Why a proxy instead of calling the LLM from the app (D6)

Two facts verified on pub.dev on 2026-09-09:

- `google_generative_ai` is **officially deprecated** — the README states there
  are no plans for further changes.
- `firebase_ai` 4.0.0, its successor, declares **Android/iOS/macOS/web only —
  no Windows**. Windows is half of this project's target, so the
  call-from-the-app architecture dies on arrival.

Plus the reason that would apply anyway: a key shipped inside an app is not a
secret. `jadx` on an APK or `strings` on a Windows `.exe` recovers it in
minutes, and no amount of `--dart-define`, base64 or obfuscation changes that.

The proxy also buys three things worth marks: quote verification, per-user rate
limiting, and swapping models without republishing the app.

## Consequences

- The Flutter app needs **no LLM package at all** — just `dio` against our own
  REST API. `tools/check_guardrails.py` enforces this.
- The proxy must be running for a live review. Offline mock mode
  (`MOCK_MODE=true`, or the switch in the app bar) covers the demo case where
  it is not.
- One extra process to start at the demo. Documented in the README quickstart.

## Explicitly out of scope

Supervisor dashboard, submission diffing, peer review, RAG over IEEE/ISO
standards, i18n, iOS builds, full CD. Written into the report as future work —
not built.

## Sources

- Flutter — [Guide to app architecture](https://docs.flutter.dev/app-architecture/guide)
- pub.dev — [google_generative_ai](https://pub.dev/packages/google_generative_ai) (deprecated), [firebase_ai](https://pub.dev/packages/firebase_ai) (platform list)
- [Gemini structured outputs](https://ai.google.dev/gemini-api/docs/structured-output)

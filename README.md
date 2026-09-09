# SRS Review AI

An AI reviewer for the **Software Requirements Specification** — the document
that FPTU's SEP490 capstone calls *Report 3*. Upload your SRS, get scored
feedback where **every issue quotes your own document verbatim**, plus
rule-based checks taken straight from the syllabus.

Flutter app (Android + Windows) → thin FastAPI proxy → Gemini.

## Why this exists

Two numbers from the SEP490 syllabus (ID 14065, QĐ 377/QĐ-ĐHFPT, 04/09/2026):

- The SRS is worth **16% of the on-going assessment and 15% of the defense** —
  roughly **15.5% of the course grade**, the second heaviest document after
  Implementation. Any report part below **2/10** means retaking the capstone.
- The SRS is also a **gate**, not just a grade. A team must wait for the second
  defense round if it completes *"less than 75% use cases functions/screens as
  submitted (as mentioned in the submitted Report 3)"* or has *"less than 20
  average (3-7 transactions) use cases completed"*.

So a vague or miscounted SRS is not a small deduction — it is a scope contract
the whole team is measured against months later. This app makes that contract
measurable in seconds, without waiting for supervisor feedback.

## What it does

| | Feature |
|---|---|
| **F1** | Parse PDF/DOCX into sections + requirement items + pages holding diagrams |
| **F2** | Review each requirement → issue card (type, severity, verified quote, suggestion) |
| **F3** | Summary: overall score, issue counts by severity, requirement and diagram counts |
| **F4** | Tap an issue → see the quote in context, jump to its page |
| **F5** | Free-form Q&A grounded in the document ("what does section 3.2 say?") |
| **F6** | Offline mock mode — the full flow with no network and no quota |
| **F7** | Count use cases, warn outside the syllabus range of 20–25 |
| **F8** | Flag requirements not written in English (the syllabus requires English) |
| **F9** | Estimate transactions per use case, warn outside 3–7 |

F7–F9 are pure rules: offline, instant, zero tokens. F2/F5 use an LLM.

### The one thing that makes this more than a ChatGPT wrapper

Every issue the model produces must carry a `quote`. The proxy searches for
that quote in your actual requirement text before the app ever sees it:

- found verbatim → `exact`, green badge
- found with ≥92% similarity → `fuzzy`, amber badge, original shown next to it
- not found → **the issue is dropped**, and counted in `dropped_issue_count`

The app cannot display a quote that does not exist in your document. The
dropped count is shown in the UI as evidence the filter is working.

## Architecture

```
┌────────────────────────────┐          ┌──────────────────────────────────┐        ┌──────────────┐
│ Flutter app                │  HTTPS   │ FastAPI proxy (this repo)        │ HTTPS  │ Gemini API   │
│ Android · Windows · macOS  │ ───────► │ 1. holds the API key             │ ─────► │ 2.5 Flash    │
│                            │          │ 2. builds the rubric prompt      │        │ Lite / Flash │
│ MVVM: View ⇄ ViewModel     │ ◄─────── │ 3. forces structured JSON output │ ◄───── │ responseSchema│
│ ⇄ Repository ⇄ Service     │   JSON   │ 4. VERIFIES EVERY QUOTE ★        │  JSON  └──────────────┘
│ dio only — no LLM SDK      │          │ 5. rate limit + cache            │
└────────────────────────────┘          └──────────────────────────────────┘
```

The app holds **no API key and no provider URL**. That is enforced by a CI
guardrail, not by good intentions — see [Guardrails](#guardrails).

Full reasoning: [docs/adr/](docs/adr/).

## Quickstart

Requires Flutter 3.44+ and Python 3.11+.

### 1. Proxy

```bash
cd server
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env          # paste a free key from https://aistudio.google.com/apikey
uvicorn app.main:app --reload # http://localhost:8000/docs
```

No key yet? Leave `GEMINI_API_KEY` empty — the proxy automatically serves the
deterministic offline provider, and the whole flow still works.

### 2. App

```bash
cd app
flutter pub get
flutter run                                  # macOS/Android/Windows
flutter run --dart-define=MOCK_MODE=true     # start in offline mode
```

Android emulators reach the host at `10.0.2.2`, which is the default. On a
physical device pass your machine's LAN address:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000
```

### 3. Verify everything

```bash
python3 tools/check_guardrails.py            # architecture + secret rules
cd server && ruff check . && pytest          # 33 tests
cd app && flutter analyze && flutter test    # 33 tests
./tools/install-hooks.sh                     # run the guardrails on every commit
```

## Guardrails

`tools/check_guardrails.py` fails the build on five classes of mistake. It runs
in CI and (once installed) on every commit.

| Rule | What it prevents |
|---|---|
| **secrets** | An API key or a tracked `.env` entering git history |
| **no-direct-llm** | The app calling a provider directly, or knowing a key at all |
| **layering** | Views importing services, ViewModels importing widgets, the data layer importing the UI |
| **pins** | Silent major upgrades of the five packages whose v-next broke every tutorial |
| **contract** | The JSON schema, the Pydantic models and the Dart models drifting apart |

Try it: break a rule on purpose and watch it fail. The rules are code, so
change them in their own PR when they are genuinely wrong.

## Project layout

```
srs-review-ai/
├── app/                     Flutter app
│   └── lib/
│       ├── core/            config, theme, router, DI
│       ├── data/
│       │   ├── models/      domain + wire models (strict parsing)
│       │   ├── parsing/     requirement splitter
│       │   ├── checks/      F7/F8/F9 syllabus rules + rubric config
│       │   ├── services/    picker, PDF/DOCX parser, API, offline mock
│       │   └── repositories/ document + review orchestration
│       └── features/        <feature>/view + <feature>/view_model
├── server/                  FastAPI proxy (key lives here, nowhere else)
│   └── app/rubric.json      ← the rubric is DATA; edit this, not the code
├── contracts/               wire schema + fixtures both test suites parse
├── tools/                   guardrails + git hooks
└── docs/adr/                why each decision was made
```

## Rubric

Quality scoring uses four ISO/IEC/IEEE 29148 criteria — clear (30%), testable
(30%), complete (25%), consistent (15%) — configured in
[`server/app/rubric.json`](server/app/rubric.json) together with the syllabus
thresholds (20–25 use cases, 3–7 transactions, pass 5.0, minimum 2.0 per part).

**These weights are a proposal, not the official marking sheet.** The syllabus
publishes per-report weights but not the per-item criteria graders use, which
stay internal. Ask your supervisor for the real rubric and drop it into that
one JSON file — no code changes needed.

## Privacy note

Gemini's **free tier** may use submitted content to improve Google's products,
and human reviewers can read it. That is acceptable for an academic exercise;
do not upload a real client's confidential SRS. Say so in your own app's
privacy section too.

## Status

Day-1 skeleton: parsing, F7–F9 checks, the review pipeline, quote verification,
offline mode, contract tests and guardrails all work end to end. Still to come:
PDF viewer with highlight-in-place, the adaptive two-pane desktop layout,
accept/dismiss per issue, report export and persistence. See
[docs/roadmap.md](docs/roadmap.md).

## Licence

MIT — see [LICENSE](LICENSE). `syncfusion_flutter_pdf` is a commercial package
used here under Syncfusion's free **Community Licence**; register for one
before shipping ([docs/adr/0003](docs/adr/0003-syncfusion-licence.md)).

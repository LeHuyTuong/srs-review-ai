# Working on this repo

A four-to-five person capstone team on a three-week clock. The rules below are
the minimum that keeps `main` demoable at any moment.

## Branches

```
main   always runs, always demoable — the committee could ask at any time
 └─ dev            integration branch
     └─ feat/...   one person, one slice of work
```

- Branch names: `feat/parse-docx`, `fix/quote-fuzzy-unicode`, `docs/adr-router`.
- **Never push to `main`.** It is protected: PR + one approval + green CI.
- Rebase or merge `dev` into your branch before opening the PR; do not merge
  `main` into a feature branch.

## Commits

Conventional and short:

```
feat: split requirements by FR/UC id
fix: normalise whitespace before fuzzy quote match
test: cover use case count boundary at exactly 20
docs: record why freezed was skipped
chore: pin file_picker to 12.x
```

Commit **as you work**, several times a day. The syllabus lets a team fail the
defense if it *"can't prove the fact that they prepare any of the project
reports or the output software package by themselves"* — a steady git history
across all members is the cheapest proof there is. One giant commit the night
before is the opposite of that.

## Before you open a PR

```bash
python3 tools/check_guardrails.py
cd server && ruff check . && ruff format --check . && pytest
cd app && dart format . && flutter analyze --fatal-infos && flutter test
```

CI runs exactly these. Install the pre-commit hook once and the guardrails run
themselves: `./tools/install-hooks.sh`

## Rules that are not negotiable

1. **No API key or provider URL under `app/`.** The key lives in `server/.env`
   and nowhere else. A leaked key in a public repo is scraped by bots within
   minutes.
2. **Every issue must carry a verified quote.** Do not add a code path that
   renders an unverified quote, and do not weaken `verify.py` to make a test
   pass.
3. **Changing the wire format touches four things in one PR:**
   `contracts/review.schema.json`, `server/app/schemas.py`,
   `app/lib/data/models/review_models.dart`, and the contract version in all
   three. The guardrail checks the version; the fixtures check the shape.
4. **Rubric numbers live in `server/app/rubric.json`.** If you find yourself
   typing `20` or `0.92` into Dart or Python, stop.
5. **Layering** (from the Flutter architecture guide):
   - `View` — widgets and layout only; reads state, calls ViewModel commands.
   - `ViewModel` — UI state and commands; no widget imports.
   - `Repository` — the source of truth; caching, retry, error translation.
   - `Service` — wraps exactly one external thing; holds no state.

   Views do not talk to services. The data layer does not import `features/`.
6. **New dependency?** Say why in the PR, and check the platform table covers
   Windows. Several popular AI packages do not.

## Issues and the board

One GitHub issue per use case, using the *Use case* template. Move it across
the board as you go. That board **is** your Project Plan evidence for Report 2
and your weekly meeting material — do not maintain a separate spreadsheet.

## Testing expectations

- Anything rule-based (parsing, the F7–F9 checks, quote verification) gets unit
  tests. These are the parts that must not silently regress.
- Test behaviour, not implementation. A test that cannot fail is worse than no
  test.
- Do not chase a coverage number.

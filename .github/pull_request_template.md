## What and why

<!-- One or two sentences. Link the issue: Closes #123 -->

## Screenshots / output

<!-- Any UI change needs a screenshot on at least one platform. -->

## Checklist

- [ ] `python3 tools/check_guardrails.py` passes
- [ ] `cd app && flutter analyze && flutter test` passes
- [ ] `cd server && pytest && ruff check .` passes
- [ ] No API key, `.env` file, or provider URL added to `app/`
- [ ] Wire-format change? Updated `contracts/`, the Pydantic models, the Dart
      models and the contract version — all in this PR
- [ ] Rubric/threshold change? Edited `server/app/rubric.json`, not Dart or
      Python constants

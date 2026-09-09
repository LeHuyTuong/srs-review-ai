# ADR 0002 — Hand-written models instead of freezed/json_serializable

Status: accepted · 2026-09-09 · supersedes the tooling note in the build plan

## Context

The build plan called for `freezed` + `json_serializable` for the domain
models. The app has five wire types: `ReviewIssue`, `ReviewResult`, `Citation`,
`AskResponse`, plus small value objects.

## Decision

Write the models and their `fromJson` by hand. No `build_runner` in this repo.

## Why

- Five small types do not repay a code generation step. `build_runner` adds a
  watch process, generated files to gitignore, one more thing that can fail in
  CI, and a rebuild between "edit model" and "compile".
- Hand-written parsing lets us be **stricter than a generator**. Unknown enum
  values and a mismatched `contract_version` throw `ContractException` rather
  than degrading quietly. A generator would either accept an unknown string or
  need custom converters anyway.
- The thing worth guaranteeing is not `copyWith` — it is that Dart and Python
  agree on the wire. That is covered by `contracts/fixtures/*.json`, which both
  test suites parse (`app/test/contract_test.dart`,
  `server/tests/test_contract.py`), and by the contract-version guardrail.

## Consequences

- No `copyWith`/`==`/`hashCode` for free. `DocumentState` writes its own
  `copyWith`; the wire models are immutable and compared through their fields
  in tests, which is enough.
- Adding a field means editing three places: the schema, the Pydantic model and
  the Dart model. The guardrail forces the contract version to move with them,
  so the cost is visible rather than silent.
- Revisit if the model count roughly triples or unions/sealed states appear.

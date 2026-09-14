# Plan 6 — F1 share-by-link (2026-09-14, own round as plan 3 demanded)

## Understanding

The promise on the feature map: a student produces a review report and sends
the supervisor a LINK — no app install, no file attachments, opens in any
browser. The self-contained HTML twin (plan round 32) was built exactly so a
report is one file; this feature puts it behind a URL.

## Requirements

- R1: `POST /share` (app-token) with the finished HTML report → server stores
  it and returns a URL containing an unguessable capability id.
- R2: `GET /share/{id}` needs no token — the id IS the credential, like the
  presigned-upload PUT. Anyone with the link sees the report; nobody can
  enumerate links (128-bit ids).
- R3: Stored HTML is untrusted content (a caller can POST anything): served
  `text/html` with `Content-Security-Policy: sandbox` + nosniff, so a share
  page can never execute against the server's origin.
- R4: Size cap + storage discipline identical to uploads: path-traversal-safe
  keys, per-file metadata, 413 beyond the cap.
- R5: Client: export sheet gains "Tạo link chia sẻ" (online mode only); the
  VM calls the api, a dialog shows the URL with a copy button. Mock/offline
  hides the button — the link would be a lie there.
- R6 (explicitly PARKED, not skipped silently): server-side PDF parsing to
  let a stranger upload a document without the app. That is parse-parity
  with 217 pages of Syncfusion extraction (the whole M0/R13/R14 effort) —
  a milestone with its own verification needs, not an endpoint. The share
  link shares a finished report; the document itself never leaves the phone.

## Assumptions

- The existing single-user proxy is the deployment target; no auth beyond
  capability ids and the app token (same threat model as /uploads).
- Reports are small (a few hundred KB with no images embedded — the HTML
  twin embeds no raster). 4 MiB cap is generous.

## Plan

1. `server/app/share.py` — store: id mint (secrets.token_urlsafe(16)), write
   under `<data>/shares/`, read, traversal guard; mirrors uploads.py style.
2. main.py: POST /share (require_app_token, body {html, filename}, cap
   enforced) → {id, url}; GET /share/{id} → HTMLResponse with sandbox CSP,
   404 unknown, `nosniff`.
3. Tests server: round-trip, wrong-token 401/403, oversized 413, traversal
   id (../) 404 not crash, CSP header present, ids high-entropy distinct.
4. Client: `ReviewApi.shareReport` + ApiService impl + MockReviewApi fake +
   VM action `shareReport()` + export-sheet button + result dialog with
   Clipboard copy. Widget test for gating (hidden offline).
5. Gates: pytest, flutter test, analyze; commit; rebuild APK.

## Risks

- Link = public read of the report content: acceptable and documented
  (capability URL model, same as the upload PUT tokens). Users who want
  privacy delete… — no delete endpoint planned this round: flag it.
- CSP `sandbox` without allow-scripts: our own HTML twin is static so it
  renders fully; anything fancier a caller injects stays inert.

## Acceptance Criteria

- AC1: POST/GET round-trip test green; fetched body equals posted body.
- AC2: GET sends `Content-Security-Policy: sandbox`; 404 on unknown id.
- AC3: Oversized (>4 MiB) rejected 413; missing app token rejected.
- AC4: Offline/mock export sheet shows no share button; online shows it.
- AC5: All prior suites stay green (80 server / 561 app / analyze 0).

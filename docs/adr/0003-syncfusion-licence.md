# ADR 0003 — Syncfusion for PDF text, and what its licence actually requires

Status: accepted · 2026-09-09

## Context

The plan flagged a demo risk: forgetting to call
`SyncfusionLicenseProvider.registerLicense()` would show a trial banner in
front of the defense committee.

## What we found in the installed package

`syncfusion_flutter_core` **34.2.7** contains no `registerLicense` API at all.
Its CHANGELOG states:

> The license key is not required now to run the application with our widgets.
> However, you need to still have either a Syncfusion commercial license or
> community license to use our widgets and libraries.

So on 34.x:

- **There is no runtime banner risk** and no key to register. The
  `SYNCFUSION_LICENSE_KEY` build flag was removed from `AppConfig` as dead
  configuration.
- The **legal** obligation stands: register for the free
  [Community Licence](https://www.syncfusion.com/products/communitylicense)
  (eligibility: ≤5 developers, <$1M revenue — a student team qualifies) before
  distributing anything. It is free but it is not optional.

Also verified in `syncfusion_flutter_pdf` 34.2.7:

- available: `extractText`, `extractTextLines`, `findText` (returns
  `List<MatchedItem>` with bounds and page index — this is what makes
  jump-to-page and highlight-in-place cheap later)
- **not available: any image-extraction API.** Unlike the .NET build, the
  Flutter package cannot enumerate embedded images. `PdfParser` therefore
  infers diagram pages from text density and says so in a comment. Real image
  extraction would need `pdfrx`/`pdfrx_engine` page rendering, which is week-3
  work at best.

## Decision

Keep `syncfusion_flutter_pdf ^34.2.7` for text extraction and citation
locating. Register for the Community Licence. Treat diagram-page detection as a
documented heuristic, not a promise.

## Fallback

If the licence turns out to be a problem, `pdfrx` (MIT) plus `pdfrx_engine`
text extraction replaces it in about a day. Note the Windows trap: `pdfrx`
requires Developer Mode enabled before it will build.

# UI/UX tour: walk the app in a phone viewport in headless Chromium and record
# MEASURED numbers (timings, tap-target geometry, console errors, screenshots)
# instead of opinions.
#
#   python3 tool/uiux_tour.py            -> prints JSON, writes PNGs to /tmp/uiux/
#
# Flutter web renders to canvas, so clicks go to real viewport coordinates
# resolved from the semantics DOM (enabled by '?smoke=semantics' in main.dart).

import json
import os
import re
import time

from playwright.sync_api import sync_playwright

BASE = "http://127.0.0.1:8443"
URL = f"{BASE}/?smoke=semantics"
DOCX = "/Volumes/SSD/Dev/active/PRM392_FlutterMobile/sample_srs.docx"
SHOTS = "/tmp/uiux"
VIEWPORT = {"width": 393, "height": 852}  # iPhone 14 Pro logical px

BODY = (
    "() => (document.body.innerText || '') + ' ' + "
    "Array.from(document.querySelectorAll('[aria-label]'))"
    ".map(e => e.getAttribute('aria-label')).join(' ')"
)

# Find the smallest clickable semantics node whose text matches `needle`.
FIND = """
([needle, mode]) => {
  const all = Array.from(document.querySelectorAll('flt-semantics'));
  const cand = [];
  for (const e of all) {
    const t = (e.textContent || '').trim().replace(/\\s+/g, ' ');
    const a = (e.getAttribute('aria-label') || '').trim();
    const hay = t || a;
    if (!hay) continue;
    let score = -1;
    if (mode === 'exact') { if (t === needle) score = 0; }
    else if (mode === 'start') { if (t.startsWith(needle)) score = 1; }
    else { if (t.includes(needle) || a.includes(needle)) score = 2; }
    if (score < 0) continue;
    const r = e.getBoundingClientRect();
    if (r.width < 4 || r.height < 4) continue;
    cand.push({score, area: r.width * r.height, x: r.x + r.width / 2,
               y: r.y + r.height / 2, w: Math.round(r.width),
               h: Math.round(r.height), text: t.slice(0, 60),
               role: e.getAttribute('role')});
  }
  cand.sort((a, b) => a.score - b.score || a.area - b.area);
  return cand.slice(0, 8);
}
"""

RECTS = """
() => {
  const out = [];
  document.querySelectorAll('flt-semantics').forEach(n => {
    const t = (n.textContent || '').trim().replace(/\\s+/g, ' ');
    const a = n.getAttribute('aria-label') || '';
    if (!t && !a) return;
    const r = n.getBoundingClientRect();
    if (r.width < 4 || r.height < 4) return;
    out.push({text: (t || a).slice(0, 48), role: n.getAttribute('role'),
              x: Math.round(r.x), y: Math.round(r.y),
              w: Math.round(r.width), h: Math.round(r.height)});
  });
  return out;
}
"""


def rects(page):
    return page.evaluate(RECTS)


def body(page):
    return page.evaluate(BODY) or ""


def tap(page, needle, mode="start", timeout=30000):
    """Click the centre of the best semantics node matching `needle`."""
    deadline = time.time() + timeout / 1000
    while time.time() < deadline:
        cand = page.evaluate(FIND, [needle, mode])
        if cand:
            c = cand[0]
            page.mouse.click(c["x"], c["y"])
            return c
        time.sleep(0.2)
    raise TimeoutError(f"no semantics node matching {needle!r} ({mode})")


def wait_text(page, needle, timeout=90_000):
    page.wait_for_function(
        "(n) => { const t = (document.body.innerText||'') + ' ' + "
        "Array.from(document.querySelectorAll('[aria-label]'))"
        ".map(e => e.getAttribute('aria-label')).join(' ');"
        " return t.includes(n); }",
        arg=needle, timeout=timeout)


def step(page, name, fn, expect=None, timeout=90_000):
    t0 = time.time()
    fn()
    ok = True
    if expect:
        try:
            wait_text(page, expect, timeout=timeout)
        except Exception:
            ok = False
    return {"ms": round((time.time() - t0) * 1000), "found": ok}


def shot(page, out, name):
    page.screenshot(path=f"{SHOTS}/{name}.png")
    out["shots"].append(name + ".png")


def main():
    os.makedirs(SHOTS, exist_ok=True)
    out = {"timings": {}, "rects": {}, "console_errors": [], "requests": {},
           "shots": []}
    t_all = time.time()
    with sync_playwright() as p:
        b = p.chromium.launch(headless=True)
        ctx = b.new_context(viewport=VIEWPORT, device_scale_factor=2,
                            is_mobile=True, has_touch=True)
        page = ctx.new_page()
        page.on("console", lambda m: out["console_errors"].append(m.text[:160])
                if m.type == "error" else None)
        page.on("pageerror", lambda e: out["console_errors"].append(str(e)[:160]))

        def on_resp(r):
            u = r.url.replace(BASE, "")
            k = u.split("?")[0].split("/")[-1] or u
            out["requests"][k] = {"status": r.status,
                                  "type": r.request.resource_type}
        page.on("response", on_resp)

        # 1. COLD LOAD
        t0 = time.time()
        page.goto(URL, wait_until="commit")
        page.wait_for_selector("canvas", timeout=60_000)
        out["timings"]["cold_canvas_ms"] = round((time.time() - t0) * 1000)
        wait_text(page, "A second look")
        out["timings"]["cold_shell_ms"] = round((time.time() - t0) * 1000)
        out["timings"]["paint"] = page.evaluate(
            "() => performance.getEntriesByType('paint')"
            ".map(e => ({n: e.name, ms: Math.round(e.startTime)}))")
        out["timings"]["heaviest_resources"] = page.evaluate(
            "() => performance.getEntriesByType('resource')"
            ".map(r => ({n: r.name.split('/').pop().slice(0,40),"
            " dur: Math.round(r.duration), kb: Math.round(r.transferSize/1024)}))"
            ".sort((a,b) => b.dur - a.dur).slice(0, 10)")
        shot(page, out, "01-empty")
        out["rects"]["01-empty"] = rects(page)

        # 2. DEMO LOAD (the "no file needed" path)
        out["timings"]["demo_load"] = step(
            page, "demo", lambda: tap(page, "Load the sample document", "contains"),
            expect="UC01")
        time.sleep(1.2)
        shot(page, out, "02-inventory")
        out["rects"]["02-inventory"] = rects(page)
        out["timings"]["inventory_paint_ms"] = out["timings"]["demo_load"]["ms"]

        # 3. NAV COST — bottom tabs
        for tab in ["Findings", "Syllabus checks", "Inventory"]:
            out["timings"][f"tab_{tab.split()[0].lower()}"] = step(
                page, tab, lambda t=tab: tap(page, t, "start"))
            time.sleep(0.8)
        shot(page, out, "03-export-empty")
        out["rects"]["03-tabs"] = rects(page)

        # 4. IMPORT MODAL, then a REAL .docx, watching for progress feedback
        out["timings"]["import_modal"] = step(
            page, "import", lambda: tap(page, "Import document", "exact"),
            expect="A fresh set of requirements", timeout=20_000)
        shot(page, out, "04-import-modal")
        out["rects"]["04-import-modal"] = rects(page)

        t0 = time.time()
        with page.expect_file_chooser() as fc:
            tap(page, "Browse files", "exact")
        fc.value.set_files(DOCX)
        samples = []
        for _ in range(20):
            time.sleep(0.2)
            bd = body(page)
            samples.append({
                "t": round((time.time() - t0) * 1000),
                "feedback": next((k for k in ("Importing", "Parsing", "Reading",
                                              "Extracting", "Loading", "%")
                                  if k in bd), None),
                "progressbar": page.locator('[role="progressbar"]').count(),
                "filename": "sample_srs.docx" in bd,
            })
            if samples[-1]["progressbar"] and samples[-1]["filename"]:
                break
        out["timings"]["import_watch"] = samples
        out["timings"]["import_total_ms"] = step(
            page, "importdone", lambda: None, expect="sample_srs.docx")
        time.sleep(1.5)
        out["timings"]["import_total_ms"]["ms"] = round((time.time() - t0) * 1000)
        shot(page, out, "05-after-import")
        out["rects"]["05-after-import"] = rects(page)
        out["import_text"] = body(page)[:900]

        # 5. REVIEW RUN — the long wait
        out["timings"]["review_modal"] = step(
            page, "reviewmodal", lambda: tap(page, "Run review", "exact"),
            expect="selected", timeout=20_000)
        shot(page, out, "06-review-modal")
        out["rects"]["06-review-modal"] = rects(page)

        t0 = time.time()
        tap(page, re.compile("Review ").pattern if False else "Review ", "start")
        samples = []
        while time.time() - t0 < 150:
            time.sleep(0.4)
            bd = body(page)
            samples.append({
                "t": round((time.time() - t0) * 1000),
                "progressbar": page.locator('[role="progressbar"]').count(),
                "stage_word": next((k for k in ("Reviewing", "Analysing",
                                                "Analyzing", "Verifying",
                                                "Checking", "Working",
                                                "elapsed", "remaining")
                                    if k in bd), None),
                "pct": (re.search(r"(\d{1,3})\s?%", bd).group(1)
                        if re.search(r"(\d{1,3})\s?%", bd) else None),
                "done": ("verified findings" in bd or "No findings" in bd
                         or "Review complete" in bd),
            })
            if samples[-1]["done"]:
                break
        out["timings"]["review_ms"] = round((time.time() - t0) * 1000)
        out["timings"]["review_done"] = samples[-1]["done"] if samples else False
        comp = []
        for s in samples:
            key = (s["progressbar"] > 0, s["stage_word"], s["pct"])
            if not comp or comp[-1]["_k"] != key:
                s["_k"] = key
                comp.append(s)
        for s in comp:
            s.pop("_k", None)
        out["timings"]["review_watch"] = comp
        shot(page, out, "07-findings")
        out["rects"]["07-findings"] = rects(page)
        out["post_review_text"] = body(page)[:900]

        # 6. ASK THE DOCUMENT
        if "Ask document" in body(page):
            out["timings"]["ask_open"] = step(
                page, "ask", lambda: tap(page, "Ask document", "start"),
                expect="Ask", timeout=15_000)
            time.sleep(0.8)
            shot(page, out, "08-ask")
            out["rects"]["08-ask"] = rects(page)
            out["ask_text"] = body(page)[:700]

        b.close()
    out["timings"]["tour_total_ms"] = round((time.time() - t_all) * 1000)
    print(json.dumps(out, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()

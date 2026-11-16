# Decisive measurement: start the review through its REAL button and sample
# what the user sees while it runs.
#
#   python3 tool/uiux_review_probe.py
#
# Flutter web renders to canvas and exposes the semantics tree as absolutely
# positioned DOM, so a raw mouse click at (x, y) misses any control that is
# outside the viewport. We therefore tag the target node with a known id and
# let Playwright scroll it into view before clicking — the same treatment a
# human thumb gets.

import json
import re
import time

from playwright.sync_api import sync_playwright

URL = "http://127.0.0.1:8443/?smoke=semantics"
DOCX = "/Volumes/SSD/Dev/active/PRM392_FlutterMobile/sample_srs.docx"
SHOTS = "/tmp/uiux"

BODY = (
    "() => (document.body.innerText || '') + ' ' + "
    "Array.from(document.querySelectorAll('[aria-label]'))"
    ".map(e => e.getAttribute('aria-label')).join(' ')"
)

TAG = """
([needle, mode]) => {
  document.querySelectorAll('#dshTap').forEach(n => n.id = '');
  const cand = [];
  for (const e of document.querySelectorAll('flt-semantics')) {
    const t = (e.textContent || '').trim().replace(/\\s+/g, ' ');
    if (!t) continue;
    let ok;
    if (mode === 'exact') ok = t === needle;
    else if (mode === 'button') ok = e.getAttribute('role') === 'button'
                                     && t.startsWith(needle);
    else ok = t.startsWith(needle);
    if (!ok) continue;
    const r = e.getBoundingClientRect();
    if (r.width < 4 || r.height < 4) continue;
    cand.push({e, area: r.width * r.height, t, w: Math.round(r.width),
               h: Math.round(r.height)});
  }
  if (!cand.length) return null;
  cand.sort((a, b) => a.area - b.area);
  cand[0].e.id = 'dshTap';
  return {text: cand[0].t, w: cand[0].w, h: cand[0].h};
}
"""


def tap(page, needle, mode="button", timeout=20000):
    end = time.time() + timeout / 1000
    last = None
    while time.time() < end:
        last = page.evaluate(TAG, [needle, mode])
        if last:
            break
        time.sleep(0.15)
    if not last:
        raise TimeoutError(f"no node matching {needle!r} ({mode})")
    page.locator("#dshTap").click(timeout=15000)
    return last


def wait_text(page, n, timeout=90000):
    page.wait_for_function(
        "(n) => { const t = (document.body.innerText||'') + ' ' "
        "+ Array.from(document.querySelectorAll('[aria-label]'))"
        ".map(e => e.getAttribute('aria-label')).join(' ');"
        " return t.includes(n); }", arg=n, timeout=timeout)


def has(page, n):
    return n in (page.evaluate(BODY) or "")


def main():
    import sys
    demo = "--demo" in sys.argv
    out = {"mode": "demo-65" if demo else "real-docx-8",
           "steps": [], "modal_buttons": [], "during_run": []}
    with sync_playwright() as p:
        b = p.chromium.launch(headless=True)
        page = b.new_page(viewport={"width": 393, "height": 852})
        errs = []
        page.on("console", lambda m: errs.append(m.text[:120])
                if m.type == "error" else None)
        page.goto(URL)
        wait_text(page, "A second look")

        if demo:
            # 65-unit synthetic document: the long-wait path the user complains about
            tap(page, "Load the sample document", "start")
            wait_text(page, "UC01", timeout=90000)
            time.sleep(1.5)
            out["steps"].append("demo loaded (65 units)")
        else:
            tap(page, "Import document", "exact")
            wait_text(page, "A fresh set of requirements", timeout=20000)
            with page.expect_file_chooser() as fc:
                tap(page, "Browse files", "exact")
            fc.value.set_files(DOCX)
            wait_text(page, "sample_srs.docx", timeout=90000)
            time.sleep(1.5)
            out["steps"].append("real docx imported (8 units)")

        # open the review modal; assert it really opened
        tap(page, "Run review", "button")
        time.sleep(1.2)
        out["modal_open"] = has(page, "Close dialog")
        out["modal_buttons"] = page.evaluate(
            "() => Array.from(document.querySelectorAll('flt-semantics'))"
            ".filter(e => e.getAttribute('role') === 'button')"
            ".map(e => ({t: (e.textContent||'').trim().replace(/\\s+/g,' ').slice(0,34),"
            " w: Math.round(e.getBoundingClientRect().width),"
            " h: Math.round(e.getBoundingClientRect().height)}))")

        # press the real run button and watch what the user is shown
        btn = tap(page, "Review ")
        out["run_button"] = btn
        t0 = time.time()
        while time.time() - t0 < 120:
            time.sleep(0.15)
            body = page.evaluate(BODY) or ""
            out["during_run"].append({
                "t": round((time.time() - t0) * 1000),
                "progressbars": page.locator('[role="progressbar"]').count(),
                "sheet_open": "Close dialog" in body,
                "stage": next((k for k in ("Reviewing…", "Reviewing", "Verifying",
                                           "Parsing", "Analysing", "Cancel")
                               if k in body), None),
                "done": bool(re.search(r"units reviewed|verified findings", body)),
            })
            if out["during_run"][-1]["done"]:
                break
        out["review_total_ms"] = round((time.time() - t0) * 1000)
        page.screenshot(path=f"{SHOTS}/09-during-review.png")
        time.sleep(0.4)
        page.screenshot(path=f"{SHOTS}/10-after-review.png")

        # how long until the progressbar count changes at all
        first = next((s["t"] for s in out["during_run"] if s["progressbars"] > 0),
                     None)
        out["first_visible_progress_ms"] = first
        out["blank_wait_ms"] = first
        out["final_text"] = (page.evaluate(BODY) or "")[:500]
        out["console_errors"] = errs
        b.close()

    comp = []
    for s in out["during_run"]:
        k = (s["progressbars"] > 0, s["sheet_open"], s["stage"], s["done"])
        if not comp or comp[-1]["_k"] != k:
            s["_k"] = k
            comp.append(s)
    for s in comp:
        s.pop("_k", None)
    out["during_run_transitions"] = comp
    out.pop("during_run")
    print(json.dumps(out, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()

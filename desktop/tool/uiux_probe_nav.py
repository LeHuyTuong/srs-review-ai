# Probe: how does the Flutter semantics DOM expose the nav bar and buttons?
# Prints the candidate nodes for a set of needles so click helpers can be
# written against reality.
import json
import time

from playwright.sync_api import sync_playwright

URL = "http://127.0.0.1:8443/?smoke=semantics"
NEEDLES = ["Export", "Findings", "Inventory", "Syllabus", "Ask document",
           "Run review", "Import document", "Load the sample"]

PROBE = """
(needles) => {
  const res = {};
  const all = Array.from(document.querySelectorAll('*'));
  for (const n of needles) {
    const hits = all.filter(e => {
      const t = (e.textContent || '').trim();
      const a = e.getAttribute('aria-label') || '';
      return (t === n || a === n) ||
             (a && a.includes(n)) ||
             (t && t.startsWith(n) && t.length < n.length + 12);
    }).slice(0, 6).map(e => {
      const r = e.getBoundingClientRect();
      return {tag: e.tagName, role: e.getAttribute('role'),
              aria: e.getAttribute('aria-label'),
              text: (e.textContent||'').trim().slice(0,50),
              cls: (e.getAttribute('class')||'').slice(0,40),
              w: Math.round(r.width), h: Math.round(r.height),
              x: Math.round(r.x), y: Math.round(r.y)};
    });
    res[n] = hits;
  }
  res['__hosts'] = Array.from(document.querySelectorAll('flt-semantics-host,flt-glass-pane,flt-semantics'))
    .length;
  return res;
}
"""

with sync_playwright() as p:
    b = p.chromium.launch(headless=True)
    pg = b.new_page(viewport={"width": 393, "height": 852})
    pg.goto(URL)
    pg.wait_for_function(
        "() => (document.body.innerText||'').includes('A second look')",
        timeout=60_000)
    pg.get_by_text("Load the sample document").first.click()
    pg.wait_for_function(
        "() => (document.body.innerText||'').includes('UC01')", timeout=60_000)
    time.sleep(1.5)
    print(json.dumps(pg.evaluate(PROBE, NEEDLES), ensure_ascii=False, indent=1))
    b.close()

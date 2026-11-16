# UI/UX recon: dump everything the accessibility DOM exposes at each major
# state of the Flutter web build, so a tour script can be written against
# real labels instead of guesses.
#
#   python3 tool/uiux_recon.py            -> prints JSON to stdout
#
# Flutter web renders to canvas; the dev-only '?smoke=semantics' hook in
# lib/main.dart turns on the semantics tree, which is what we read here.

import json
import time

from playwright.sync_api import sync_playwright

BASE = "http://127.0.0.1:8443"
URL = f"{BASE}/?smoke=semantics"
VIEWPORT = {"width": 414, "height": 896}  # iPhone-14-Pro-ish

DUMP = """
() => {
  const labels = Array.from(document.querySelectorAll('[aria-label]'))
    .map(n => ({label: n.getAttribute('aria-label'), role: n.getAttribute('role')}));
  return {
    text: (document.body.innerText || '').slice(0, 2000),
    labels: labels,
    canvases: Array.from(document.querySelectorAll('canvas'))
      .map(c => ({w: c.width, h: c.height, rect: c.getBoundingClientRect().toJSON()})),
  };
}
"""


def dump(page, name, out):
    data = page.evaluate(DUMP)
    data["name"] = name
    out.append(data)
    return data


def click(page, needle):
    loc = page.locator(f'[aria-label*="{needle}"]')
    if loc.count() > 0:
        loc.first.click()
        return "aria"
    page.get_by_text(needle).first.click()
    return "text"


def wait_text(page, needle, timeout=45_000):
    page.wait_for_function(
        "(n) => ((document.body.innerText||'') + ' ' + "
        "Array.from(document.querySelectorAll('[aria-label]')).map(e=>e.getAttribute('aria-label')).join(' ')"
        ").includes(n)",
        arg=needle,
        timeout=timeout,
    )


def main():
    states = []
    t0 = time.time()
    with sync_playwright() as p:
        b = p.chromium.launch(headless=True)
        page = b.new_page(viewport=VIEWPORT)
        page.goto(URL)
        wait_text(page, "A second look")
        dump(page, "01-shell", states)

        click(page, "Load the sample document")
        wait_text(page, "UC01")
        time.sleep(1)
        dump(page, "02-demo-loaded", states)

        # What does the shell offer once a document exists?
        click(page, "Import document")
        time.sleep(1.2)
        dump(page, "03-import-modal", states)
        page.keyboard.press("Escape")
        time.sleep(0.6)

        click(page, "Run review")
        time.sleep(0.8)
        dump(page, "04-review-textbox", states)

        b.close()
    print(json.dumps({"states": states, "elapsed": round(time.time() - t0, 2)},
                     ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()

# E2E smoke for the Flutter web build in headless Chromium.
#
# Exercises the real user journey:
#   render shell -> load sample -> import a REAL .docx via the browser file
#   picker -> parsed inventory -> mock review run -> findings.
#
# Flutter web renders to canvas, so the script drives the accessibility DOM
# (enabled by the dev-only '#semantics' URL fragment hook in lib/main.dart):
# text is matched against textContent AND aria-labels; buttons are clicked
# through their labelled semantics nodes. Run with:
#
#   cd app && python3 tool/web_smoke.py
#
# Prerequisite: python3 tool/web_server.py serving build/web on 8443.

import json
import re
import time

from playwright.sync_api import sync_playwright

BASE = "http://127.0.0.1:8443"
URL = f"{BASE}/?smoke=semantics"
DOCX = "/Volumes/SSD/Dev/active/PRM392_FlutterMobile/sample_srs.docx"

HAS_TEXT = (
    "(needle) => {"
    " const t = (document.body.innerText || '') + ' ' +"
    " Array.from(document.querySelectorAll('[aria-label]'))"
    " .map(n => n.getAttribute('aria-label')).join(' ');"
    " return t.includes(needle); }"
)


def wait_text(page, needle, timeout=45_000):
    page.wait_for_function(HAS_TEXT, arg=needle, timeout=timeout)


def click_label(page, needle):
    loc = page.locator(f'[aria-label*="{needle}"]')
    if loc.count() > 0:
        loc.first.click()
    else:
        page.get_by_text(needle).first.click()


def main():
    report = {
        "checks": {},
        "console_errors": [],
        "page_errors": [],
        "ids_found": [],
        "after_import_excerpt": "",
    }
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1280, "height": 800})
        page.on(
            "console",
            lambda m: report["console_errors"].append(m.text)
            if m.type == "error"
            else None,
        )
        page.on("pageerror", lambda e: report["page_errors"].append(str(e)))

        # AC2 — shell renders with zero console errors.
        page.goto(URL)
        wait_text(page, "A second look")
        report["checks"]["AC2_shell_rendered"] = True
        report["checks"]["AC2_load_console_errors"] = len(
            report["console_errors"]
        )

        # AC3 — bundled demo populates the inventory.
        click_label(page, "Load the sample document")
        wait_text(page, "UC01")
        report["checks"]["AC3_demo_uc01"] = True

        # AC4 — real .docx through the browser file picker.
        click_label(page, "Import document")
        wait_text(page, "A fresh set of requirements")
        with page.expect_file_chooser() as fc_info:
            click_label(page, "Browse files")
        fc_info.value.set_files(DOCX)
        wait_text(page, "sample_srs.docx")
        report["checks"]["AC4_filename"] = True
        time.sleep(2)  # let the inventory + toast settle
        body = page.evaluate("document.body.innerText") or ""
        labels = page.evaluate(
            "Array.from(document.querySelectorAll('[aria-label]'))"
            ".map(n => n.getAttribute('aria-label')).join(' ')"
        )
        everything = f"{body} {labels}"
        report["after_import_excerpt"] = everything[:1500]
        report["checks"]["AC4_error_banner"] = bool(
            re.search(r"Unable to read|Only PDF|could not", everything)
        )
        report["ids_found"] = sorted(
            set(re.findall(r"\b(?:UC|BR|NFR|FR|SR)[- ]?\d+\b", everything))
        )[:24]
        report["checks"]["AC4_units_found"] = len(report["ids_found"])

        # AC5 — mock review run over the imported document.
        click_label(page, "Run review")
        wait_text(page, "Review ")
        page.get_by_text(re.compile(r"Review \d+ units")).first.click()
        wait_text(page, "verified findings", timeout=90_000)
        report["checks"]["AC5_findings"] = True

        browser.close()

    print(json.dumps(report, ensure_ascii=False, indent=1))
    ok = (
        report["checks"].get("AC2_shell_rendered")
        and report["checks"].get("AC2_load_console_errors") == 0
        and report["checks"].get("AC3_demo_uc01")
        and report["checks"].get("AC4_filename")
        and report["checks"].get("AC4_units_found", 0) > 0
        and not report["checks"].get("AC4_error_banner")
        and report["checks"].get("AC5_findings")
    )
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()

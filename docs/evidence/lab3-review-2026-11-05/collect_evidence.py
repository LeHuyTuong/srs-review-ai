"""Collect local Lab 3 evidence. This is an inventory, not an acceptance test.

Run with Python 3.12 and PyMuPDF installed:
  python docs/evidence/lab3-review-2026-11-05/collect_evidence.py
No Firebase calls, source edits, credentials, or cloud writes.
"""

import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    import fitz

    output = Path(__file__).resolve().parent
    root = output.parents[2]
    sources = Path(sys.argv[1]) if len(sys.argv) > 1 else root.parent / "LAB3"
    names = {
        "preparation": "PRM393_Lab3_Preparation_Guide_v5_ToiUu.pdf",
        "assignment": "PRM393 - Lab 3 From Design to Working App with Flutter and Firebase.pdf",
    }
    result = {"kind": "static inventory, NOT test pass", "pdfs": {}, "symbols": {}}
    result["head"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=root, text=True
    ).strip()
    for key, name in names.items():
        path = sources / name
        raw = path.read_bytes()
        with fitz.open(path) as document:
            result["pdfs"][key] = {
                "path": str(path), "pages": len(document),
                "sha256": hashlib.sha256(raw).hexdigest(),
            }
            text = "\n".join(
                f"\n=== PDF PAGE {i + 1} ===\n{page.get_text()}"
                for i, page in enumerate(document)
            )
        (output / f"{key}-pages.txt").write_text(text, encoding="utf-8")

    tracked = subprocess.check_output(
        ["git", "ls-files", "-z"], cwd=root
    ).decode("utf-8").split("\0")
    tracked = [name for name in tracked if name]
    if not tracked:
        raise RuntimeError("No tracked files: inventory unavailable")
    mobile = [name for name in tracked if name.startswith("mobile/lib/") and name.endswith(".dart")]
    if not mobile:
        raise RuntimeError("No mobile Dart sources: inventory unavailable")
    result["counts"] = {
        "mobile_lib_dart": len(mobile),
        "mobile_unit_widget_test_files": sum(
            name.startswith("mobile/test/") and name.endswith("_test.dart") for name in tracked
        ),
        "mobile_integration_test_files": sum(
            name.startswith("mobile/integration_test/") and name.endswith("_test.dart") for name in tracked
        ),
    }
    patterns = [
        "uploadSrs", "srsServiceProvider", "logViewSrsDetail", "logUploadSrsStart",
        "logUploadSrsSuccess", "logExportReport", "FirebaseRemoteConfig",
        "fetchAndActivate", "requestPermission", "getInitialMessage", "onMessageOpenedApp",
    ]
    for symbol in patterns:
        hits = []
        for name in mobile:
            for line, text in enumerate((root / name).read_text(encoding="utf-8-sig").splitlines(), 1):
                if re.search(r"\b" + re.escape(symbol) + r"\b", text):
                    hits.append({"file": name, "line": line, "text": text.strip()})
        result["symbols"][symbol] = hits
    docs = [
        "handoff-gaps.md", "design-change-log.md", "fidelity-check.md",
        "analytics-plan.md", "implementation-ai-log.md", "test-report.md", "code-review.md",
    ]
    result["required_doc_paths"] = {
        name: [path for path in tracked if Path(path).name == name] for name in docs
    }
    result["mob_scripts"] = [path for path in tracked if path.endswith(".mob")]
    result["rules_and_config"] = [
        path for path in tracked if path.endswith(".rules") or Path(path).name == "firebase.json"
    ]
    (output / "inventory.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps({"head": result["head"], "counts": result["counts"],
                      "pdfs": result["pdfs"]}, ensure_ascii=False, indent=2))
    print("Inventory written. No claim of runtime acceptance or passing tests.")


if __name__ == "__main__":
    main()

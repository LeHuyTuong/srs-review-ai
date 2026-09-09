"""Verify that every factual claim in docs/workflow-v2-plan.md still matches the
code and the saved probe evidence. Run from anywhere:

    python3 srs-review-ai/docs/evidence/verify_plan_claims.py

Exit 1 = the plan has drifted from reality (fix the plan or the code, not this script
unless a citation genuinely moved).
"""
from __future__ import annotations

import json
import pathlib
import re
import subprocess
import sys

EV = pathlib.Path(__file__).resolve().parent          # docs/evidence
DOCS = EV.parent                                      # docs
ROOT = DOCS.parent                                    # srs-review-ai
FAILS: list[str] = []


def chk(name: str, cond: bool, note: str = "") -> None:
    print(("PASS  " if cond else "FAIL  ") + name + (("  <- " + note) if not cond and note else ""))
    if not cond:
        FAILS.append(name)


def rng(lines: list[str], a: int, b: int) -> str:
    return "\n".join(lines[a - 1 : b])


plan = (DOCS / "workflow-v2-plan.md").read_text(encoding="utf-8")
baseline = json.loads((EV / "otes-workflow-baseline.json").read_text(encoding="utf-8"))
probe = json.loads((EV / "otes-pdfplumber-probe.json").read_text(encoding="utf-8"))

# A — saved evidence is intact and says what the plan quotes it as saying
inv = (
    baseline["source_use_case_headers"],
    baseline["source_literal_unique_ids"],
    baseline["source_numeric_unique_ids"],
)
chk("baseline: source inventory is 63/52/51", inv == (63, 52, 51), str(inv))
chk("baseline: splitter found 0 use-case items", baseline["splitter_use_case_items"] == 0)
chk("baseline: duplicate UC code silently merged", baseline["synthetic_duplicate"]["preserves_both"] is False)
chk("baseline: numbered flow steps lost", baseline["synthetic_numbered_flow"]["preserves_submit_step"] is False)
p83 = next(p for p in probe["pages"] if p["pdf_page"] == 83)
chk("pdfplumber: one UC split into 3 tables", p83["default_table_count"] == 3)
chk("pdfplumber: whole page collapsed to one 51x4 table by text strategy",
    p83["table_shapes_text_strategy"] == [[51, 4]])

# B — every line-number citation in the plan still points at the cited code
spl = (ROOT / "app/lib/data/parsing/requirement_splitter.dart").read_text(encoding="utf-8").splitlines()
chk("cite splitter:38-41 = _ucNameRow matches name|id only",
    "_ucNameRow" in rng(spl, 38, 41) and "name|id" in rng(spl, 38, 41))
chk("cite splitter:113-118 = section heading flushes and eats steps",
    "_sectionHeading" in rng(spl, 113, 118) and "flush()" in rng(spl, 113, 118))
chk("cite splitter:48-59 = map keyed by id, longer text wins",
    "collected[item.id]" in rng(spl, 48, 59) and "existing.text.length" in rng(spl, 48, 59))
# Root cause 1 only holds while no 'Use Case No.' header pattern exists. If someone fixes it,
# this check must go red so the plan gets rewritten instead of quietly rotting.
chk("splitter still has no 'Use Case No.' header pattern (root cause 1 open)",
    not any("Use Case No" in l for l in spl))

ps = (ROOT / "app/lib/data/services/parse_service.dart").read_text(encoding="utf-8").splitlines()
chk("cite parse_service:62 = diagram page threshold 120", "_diagramPageTextThreshold = 120" in ps[61])
chk("cite parse_service:5-6 = 'NO image-extraction API'",
    "NO image-extraction API" in "\n".join(ps[:8]))
chk("cite parse_service:109 = heuristic stand-in", "Heuristic stand-in" in ps[108])

doc_model = (ROOT / "app/lib/data/models/srs_document.dart").read_text(encoding="utf-8")
chk("srs_document still claims 'embedded image' for imagePageIndexes", "embedded image" in doc_model)
chk("SrsDocument.useCaseCount still counts post-merge items (Phase 2 premise)",
    "requirements.where((r) => r.isUseCase).length" in doc_model.replace("\n", ""))

checks = (ROOT / "app/lib/data/checks/syllabus_checks.dart").read_text(encoding="utf-8")
chk("SyllabusChecks present + F7 message template as quoted",
    "below the $min required to defend in round 1" in checks)
appdart = "".join(p.read_text(encoding="utf-8") for p in (ROOT / "app/lib").rglob("*.dart"))
chk("app still never sends image_b64 (§2.4 premise)", "image_b64" not in appdart and "imageB64" not in appdart)
chk("maxRequirementsPerRun still 40 (AC-5 premise)",
    "maxRequirementsPerRun = 40" in (ROOT / "app/lib/core/app_config.dart").read_text(encoding="utf-8"))

# C — the plan must agree with the decisions recorded in it
chk("decision 'stop at plan' recorded", "Dừng ở plan" in plan)
chk("decision 'auto-select diagram pages' recorded with a budget",
    "App tự chọn trang có sơ đồ" in plan and "imageBudgetPages" in plan)
chk("no leftover 'opt-in mặc định tắt' as the chosen path", "mặc định tắt" not in plan)
chk("all relative markdown links resolve",
    all((DOCS / t).exists() for t in re.findall(r"\]\((?!http)([^)]+\.md)\)", plan)))
chk("every file named in evidence/README.md exists",
    all((EV / f).exists() for f in re.findall(r"`(otes-[\w.-]+\.(?:dart|py|json))`",
                                              (EV / "README.md").read_text(encoding="utf-8"))))

# D — this is a docs-only change set
status = subprocess.run(["git", "status", "--short"], cwd=ROOT, capture_output=True, text=True).stdout
dirty = [l.split()[-1] for l in status.splitlines() if l.strip()]
chk("nothing outside docs/ modified", all(p.startswith("docs/") for p in dirty), str(dirty))

print()
print(f"{len(FAILS)} failure(s)" if FAILS else "ALL PASS — plan claims match code + evidence")
sys.exit(1 if FAILS else 0)

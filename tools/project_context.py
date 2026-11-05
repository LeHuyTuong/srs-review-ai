"""Print checkout context without reading credentials or contacting services."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
START_FILES = (
    "AGENTS.md",
    "docs/README.md",
    "docs/project-status.md",
    "docs/adr/README.md",
    "docs/adr/0013-component-boundaries-flutter-server.md",
    "docs/adr/0016-class-roster-and-teacher-decisions.md",
    "docs/adr/0017-class-crud-and-write-key.md",
    "docs/adr/0019-firebase-identity-and-data-ownership.md",
    "mobile/docs/mobile-grading-compliance.md",
    "mobile/docs/firebase-data-model.md",
    "docs/local-environment.md",
    "promt.txt",
)


def git(*args: str) -> str:
    executable = shutil.which("git")
    if executable is None:
        raise RuntimeError("git executable is unavailable")
    # Only fixed read-only Git arguments from main() reach this call; no shell.
    result = subprocess.run(  # noqa: S603
        [executable, *args],
        cwd=ROOT,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if result.returncode:
        raise RuntimeError(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout.rstrip("\r\n")


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    try:
        print(f"Workspace: {ROOT}")
        print(f"HEAD: {git('rev-parse', 'HEAD')}")
        print(f"Branch: {git('rev-parse', '--abbrev-ref', 'HEAD')}")
        changes = git("status", "--short", "--untracked-files=normal")
        print("Working tree:")
        print(changes if changes else "Clean")
        print("\nStart files:")
        missing = []
        for relative in START_FILES:
            path = ROOT / relative
            # Read the documents too: existence alone does not prove availability.
            try:
                content = path.read_text(encoding="utf-8-sig")
                if not content.strip():
                    raise ValueError("empty document")
            except (OSError, UnicodeError, ValueError) as exc:
                missing.append(relative)
                print(f"UNAVAILABLE {relative}: {exc}")
            else:
                print(f"OK {relative}")
        if missing:
            print("Context incomplete. Fix unavailable start files before relying on the guide.")
            return 1
        print("\nRead docs/README.md in order. This output is not a test or cloud verification.")
        return 0
    except (OSError, RuntimeError) as exc:
        print(f"Context unavailable: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Repository guardrails — the rules that must never be broken by accident.

Run locally:      python3 tools/check_guardrails.py
Runs in CI:       .github/workflows/ci.yml
Runs pre-commit:  tools/install-hooks.sh

Five families of rule plus one for design tokens:
  1. SECRETS   — no API key ever enters git history.
  2. NO DIRECT LLM — the Flutter app may only talk to our own proxy (AC6).
  3. LAYERING  — MVVM boundaries from the Flutter architecture guide.
  4. PINS      — dependency versions whose majors are known traps.
  5. CONTRACT  — schema, Python and Dart agree on one contract version.
  6. DESIGN TOKENS — colors and radii live only in core/theme/.

This file is excluded from its own scans; keep example keys out of it anyway.
"""

from __future__ import annotations

import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

SKIP_DIRS = {
    ".git",
    ".venv",
    "venv",
    "build",
    ".dart_tool",
    "__pycache__",
    ".pytest_cache",
    ".ruff_cache",
    "ephemeral",
    "Pods",
    "tools",  # this script and its neighbours describe the rules
}

TEXT_SUFFIXES = {
    ".dart",
    ".py",
    ".json",
    ".yaml",
    ".yml",
    ".md",
    ".sh",
    ".toml",
    ".gradle",
    ".kts",
    ".xml",
    ".plist",
    ".example",
    ".txt",
}


@dataclass
class Violation:
    rule: str
    path: str
    line: int
    detail: str

    def __str__(self) -> str:
        return f"  [{self.rule}] {self.path}:{self.line}\n      {self.detail}"


# --------------------------------------------------------------------------
# 1. SECRETS
# --------------------------------------------------------------------------
# Provider key shapes. Written as split patterns so this file never contains a
# string that looks like a real key.
SECRET_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("google-api-key", re.compile(r"AIza" + r"[0-9A-Za-z_\-]{35}")),
    ("openai-key", re.compile(r"\bsk-" + r"[A-Za-z0-9]{32,}")),
    ("groq-key", re.compile(r"\bgsk_" + r"[A-Za-z0-9]{40,}")),
    ("openrouter-key", re.compile(r"\bsk-or-v1-" + r"[A-Za-z0-9]{32,}")),
    ("private-key-block", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
]

# `NAME=value` where value is non-empty: fine in .env.example only if empty.
ASSIGNED_SECRET = re.compile(
    r"\b(GEMINI_API_KEY|OPENAI_API_KEY|GROQ_API_KEY|APP_TOKEN|SYNCFUSION_LICENSE_KEY)\s*=\s*(\S+)"
)
ENV_EXAMPLE_ALLOWED = {"server/.env.example"}


def check_secrets(files: list[Path]) -> list[Violation]:
    violations: list[Violation] = []
    for path in files:
        rel = path.relative_to(REPO).as_posix()
        for number, line in read_lines(path):
            for name, pattern in SECRET_PATTERNS:
                if pattern.search(line):
                    violations.append(
                        Violation("secrets", rel, number, f"looks like a {name} — move it to server/.env")
                    )
            match = ASSIGNED_SECRET.search(line)
            if match and not line.lstrip().startswith("#"):
                value = match.group(2)
                placeholder = value.startswith(("$", "<", "your", "xxx", '"', "'"))
                if rel in ENV_EXAMPLE_ALLOWED or placeholder:
                    continue
                violations.append(
                    Violation(
                        "secrets",
                        rel,
                        number,
                        f"{match.group(1)} is assigned a literal value; read it from the environment",
                    )
                )

    tracked = git_tracked_files()
    for rel in tracked:
        if rel.endswith(".env") or "/.env." in rel and not rel.endswith(".env.example"):
            violations.append(Violation("secrets", rel, 0, "a .env file is tracked by git — untrack it"))
    return violations


# --------------------------------------------------------------------------
# 2. NO DIRECT LLM ACCESS FROM THE APP
# --------------------------------------------------------------------------
FORBIDDEN_IN_APP = [
    ("generativelanguage.googleapis.com", "call the proxy, not Gemini directly"),
    ("api.openai.com", "call the proxy, not OpenAI directly"),
    ("api.anthropic.com", "call the proxy, not Anthropic directly"),
    ("api.groq.com", "call the proxy, not Groq directly"),
    ("openrouter.ai/api", "call the proxy, not OpenRouter directly"),
    ("package:firebase_ai", "firebase_ai has no Windows support and bypasses the proxy"),
    ("package:google_generative_ai", "that SDK is deprecated and would embed a key in the app"),
    ("GEMINI_API_KEY", "the app must never know a provider key"),
]


def check_no_direct_llm(files: list[Path]) -> list[Violation]:
    violations: list[Violation] = []
    app_lib = REPO / "app" / "lib"
    for path in files:
        if not path.is_relative_to(app_lib):
            continue
        rel = path.relative_to(REPO).as_posix()
        for number, line in read_lines(path):
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("///"):
                continue  # documentation may name what is forbidden
            for needle, reason in FORBIDDEN_IN_APP:
                if needle in line:
                    violations.append(Violation("no-direct-llm", rel, number, f"'{needle}': {reason}"))
    return violations


# --------------------------------------------------------------------------
# 3. LAYERING (MVVM, per the Flutter app architecture guide)
# --------------------------------------------------------------------------
IMPORT = re.compile(r"""^\s*import\s+['"]([^'"]+)['"]""")


@dataclass
class LayerRule:
    name: str
    # a file is in scope when every fragment of `applies_to` appears in its path
    applies_to: tuple[str, ...]
    forbidden: tuple[str, ...]
    reason: str


LAYER_RULES = [
    LayerRule(
        name="view-no-services",
        applies_to=("app/lib/features/", "/view/"),
        forbidden=("data/services/", "package:dio/"),
        reason="Views must go through a ViewModel; only repositories/services may touch transport",
    ),
    LayerRule(
        name="viewmodel-no-widgets",
        applies_to=("app/lib/features/", "/view_model/"),
        forbidden=("package:flutter/material.dart", "package:flutter/cupertino.dart", "/view/"),
        reason="ViewModels hold UI state, not widgets — keep them testable without a widget tree",
    ),
    LayerRule(
        name="data-no-features",
        applies_to=("app/lib/data/",),
        forbidden=("features/",),
        reason="the data layer must not depend on the UI layer",
    ),
    LayerRule(
        name="data-no-material",
        applies_to=("app/lib/data/",),
        forbidden=("package:flutter/material.dart",),
        reason="models/services/repositories must stay widget-free",
    ),
    LayerRule(
        name="repository-no-picker-ui",
        applies_to=("app/lib/data/models/",),
        forbidden=("package:dio/", "data/services/"),
        reason="models are plain values; they must not know about transport",
    ),
]


def check_layering(files: list[Path]) -> list[Violation]:
    violations: list[Violation] = []
    for path in files:
        if path.suffix != ".dart":
            continue
        rel = path.relative_to(REPO).as_posix()
        for rule in LAYER_RULES:
            if not all(fragment in rel for fragment in rule.applies_to):
                continue
            for number, line in read_lines(path):
                match = IMPORT.match(line)
                if not match:
                    continue
                target = match.group(1)
                for banned in rule.forbidden:
                    if banned in target:
                        violations.append(
                            Violation(
                                f"layering/{rule.name}",
                                rel,
                                number,
                                f"imports '{target}' — {rule.reason}",
                            )
                        )
    return violations


# --------------------------------------------------------------------------
# 4. DEPENDENCY PINS
# --------------------------------------------------------------------------
# Each of these had a breaking major change that silently invalidates most
# tutorials and StackOverflow answers. Pinning the major is the guardrail.
REQUIRED_PINS = {
    "file_picker": "^12.",
    "dio": "^5.",
    "syncfusion_flutter_pdf": "^34.",
    "archive": "^4.",
    "xml": "^7.",
    "flutter_riverpod": "^3.",
}


def check_pins() -> list[Violation]:
    pubspec = REPO / "app" / "pubspec.yaml"
    if not pubspec.exists():
        return [Violation("pins", "app/pubspec.yaml", 0, "file is missing")]
    violations: list[Violation] = []
    lines = pubspec.read_text(encoding="utf-8").splitlines()
    found: dict[str, tuple[int, str]] = {}
    for number, line in enumerate(lines, start=1):
        match = re.match(r"^\s{2}([a-z_0-9]+):\s*(\S+)\s*$", line)
        if match:
            found[match.group(1)] = (number, match.group(2))
    for package, expected in REQUIRED_PINS.items():
        if package not in found:
            violations.append(
                Violation("pins", "app/pubspec.yaml", 0, f"{package} is not declared but is required")
            )
            continue
        number, constraint = found[package]
        if not constraint.startswith(expected):
            violations.append(
                Violation(
                    "pins",
                    "app/pubspec.yaml",
                    number,
                    f"{package} is '{constraint}' but must stay on '{expected}x' "
                    "(major upgrades break the documented API)",
                )
            )
    return violations


# --------------------------------------------------------------------------
# 5. CONTRACT VERSION AGREEMENT
# --------------------------------------------------------------------------
def check_contract_version() -> list[Violation]:
    violations: list[Violation] = []
    schema = REPO / "contracts" / "review.schema.json"
    server = REPO / "server" / "app" / "schemas.py"
    dart = REPO / "app" / "lib" / "data" / "models" / "review_models.dart"

    versions: dict[str, str | None] = {}
    versions["schema"] = extract(schema, r'"x-contract-version":\s*"([^"]+)"')
    versions["server"] = extract(server, r'CONTRACT_VERSION\s*=\s*"([^"]+)"')
    versions["app"] = extract(dart, r"kContractVersion\s*=\s*'([^']+)'")

    missing = [name for name, value in versions.items() if value is None]
    if missing:
        return [
            Violation("contract", "contracts/review.schema.json", 0, f"could not read version from: {missing}")
        ]
    if len(set(versions.values())) != 1:
        violations.append(
            Violation(
                "contract",
                "contracts/review.schema.json",
                0,
                f"contract versions disagree: {versions} — update all three in the same PR",
            )
        )
    return violations


def extract(path: Path, pattern: str) -> str | None:
    if not path.exists():
        return None
    match = re.search(pattern, path.read_text(encoding="utf-8"))
    return match.group(1) if match else None


# --------------------------------------------------------------------------
# 6. DESIGN TOKENS — colors/radii only in core/theme/
# --------------------------------------------------------------------------
# Components must consume the ColorScheme / SeverityColors / AppRadius tokens.
# A raw Color(0x...) or an ad-hoc BorderRadius.circular outside core/theme/ is
# how a theme silently forks. Spacing is deliberately NOT enforced here: too
# many legitimate one-off sizes (icons, indicator heights) would make the rule
# noise. It is handled by the AppSpacing/AppInsets tokens + review.
RAW_COLOR = re.compile(r"\bColor\(\s*0x")
RAW_RADIUS = re.compile(r"\bBorderRadius\.circular\(")
THEME_DIR_FRAGMENT = "core/theme/"


def check_design_tokens(files: list[Path]) -> list[Violation]:
    violations: list[Violation] = []
    app_lib = REPO / "app" / "lib"
    for path in files:
        if path.suffix != ".dart" or not path.is_relative_to(app_lib):
            continue
        rel = path.relative_to(REPO).as_posix()
        if THEME_DIR_FRAGMENT in rel:
            continue  # the only home of raw values
        for number, line in read_lines(path):
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("///"):
                continue  # documentation may name the rule
            if RAW_COLOR.search(line):
                violations.append(
                    Violation(
                        "design-tokens",
                        rel,
                        number,
                        "raw Color(0x...) outside core/theme/ — use the ColorScheme "
                        "or SeverityColors from app_theme.dart",
                    )
                )
            if RAW_RADIUS.search(line):
                violations.append(
                    Violation(
                        "design-tokens",
                        rel,
                        number,
                        "ad-hoc BorderRadius.circular outside core/theme/ — use "
                        "AppRadius (sm/md/lg) from app_tokens.dart",
                    )
                )
    return violations


# --------------------------------------------------------------------------
# plumbing
# --------------------------------------------------------------------------
def read_lines(path: Path) -> list[tuple[int, str]]:
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return []
    return list(enumerate(text.splitlines(), start=1))


def collect_files() -> list[Path]:
    files: list[Path] = []
    for path in REPO.rglob("*"):
        if not path.is_file():
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        if path.suffix not in TEXT_SUFFIXES:
            continue
        files.append(path)
    return files


def git_tracked_files() -> list[str]:
    try:
        output = subprocess.run(
            ["git", "-C", str(REPO), "ls-files"],
            capture_output=True,
            text=True,
            check=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []
    return output.stdout.splitlines()


def main() -> int:
    files = collect_files()
    checks = {
        "secrets": lambda: check_secrets(files),
        "no direct LLM access from the app": lambda: check_no_direct_llm(files),
        "MVVM layering": lambda: check_layering(files),
        "dependency pins": check_pins,
        "contract version agreement": check_contract_version,
        "design tokens (colors/radii in core/theme/)": lambda: check_design_tokens(files),
    }

    total: list[Violation] = []
    for label, run in checks.items():
        violations = run()
        status = "FAIL" if violations else "ok"
        print(f"[{status:>4}] {label}")
        total.extend(violations)

    if total:
        print(f"\n{len(total)} guardrail violation(s):\n")
        for violation in total:
            print(violation)
        print("\nThese rules exist to stop a whole class of bug. Fix the code, not the rule —")
        print("and if a rule is genuinely wrong, change it in tools/check_guardrails.py in its own PR.")
        return 1

    print(f"\nAll guardrails passed across {len(files)} files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

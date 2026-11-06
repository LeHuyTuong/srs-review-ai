"""WP0 baseline: measure every local data source Plan 13 must migrate, and back up
the uncommitted work already sitting in the checkout.

Why a tool instead of ad-hoc commands: Plan 13 WP0 has to be repeatable and has
to fail closed. An inventory that quietly reports "0 records" when a directory
is unreadable is worse than no inventory, because WP10 would then migrate
nothing and call it complete. So:

* every source is measured (present / absent / unreadable / not measured),
* a required source that is absent, and any unreadable source, makes the command
  exit 1 instead of printing a happy summary,
* hashes are recorded so a later pass can prove the bytes did not move,
* absolute user paths are redacted (repo, APPDATA, LOCALAPPDATA, TEMP) so a
  manifest can be committed without leaking a home directory or a username.

The tool is read-only against application data: no sockets, no credentials, no
writes outside the output paths the caller names. A backup is written outside
the repository on purpose.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Iterable, Mapping, Sequence

REPO = Path(__file__).resolve().parents[1]
MANIFEST_VERSION = 1
CHUNK_BYTES = 1 << 20


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(CHUNK_BYTES), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_redactor(repo: Path, env: Mapping[str, str]) -> Callable[[str], str]:
    """Map machine-specific prefixes to stable placeholders.

    Longest prefix first: TEMP lives under LOCALAPPDATA, so replacing the
    shorter prefix first would hide the more specific one.
    """
    pairs: list[tuple[str, str]] = [(str(repo), "<repo>")]
    for name in ("USERPROFILE", "LOCALAPPDATA", "APPDATA", "TEMP"):
        value = (env.get(name) or "").rstrip("\\/")
        if value:
            pairs.append((value, "<" + name + ">"))
    pairs.sort(key=lambda pair: len(pair[0]), reverse=True)
    compiled = [
        (re.compile(re.escape(value), re.IGNORECASE), token)
        for value, token in pairs
        if value
    ]

    def redact(text: str) -> str:
        for pattern, token in compiled:
            text = pattern.sub(token, text)
        return text

    return redact


def _raise(error: OSError) -> None:
    raise error


def measure_files(root: Path) -> list[dict]:
    """Every file under root with size and hash; raises on unreadable dirs."""
    entries: list[dict] = []
    for current, directories, names in os.walk(root, onerror=_raise):
        directories.sort()
        names.sort()
        for name in names:
            path = Path(current) / name
            entries.append(
                {
                    "rel": path.relative_to(root).as_posix(),
                    "bytes": path.stat().st_size,
                    "sha256": sha256_file(path),
                }
            )
    return entries


def measure_chrome_profiles(base: Path) -> list[dict]:
    """Only browser storage under each throwaway flutter profile.

    A Chrome profile also carries caches and code caches; scanning all of it
    would report hundreds of megabytes of browser cache as review history.
    """
    entries: list[dict] = []
    for profile in sorted(item for item in base.glob("flutter_tools*") if item.is_dir()):
        for current, directories, _names in os.walk(profile, onerror=_raise):
            path = Path(current)
            if path.name in {"IndexedDB", "Local Storage"}:
                for item in measure_files(path):
                    item["rel"] = (path.relative_to(base) / item["rel"]).as_posix()
                    entries.append(item)
                directories[:] = []
    entries.sort(key=lambda item: item["rel"])
    return entries


def sqlite_row_counts(path: Path) -> dict:
    """Row counts per table, opened read-only. Never writes to the database."""
    uri = "file:" + path.as_posix() + "?mode=ro"
    counts: dict[str, int] = {}
    connection = sqlite3.connect(uri, uri=True, timeout=5)
    try:
        connection.execute("PRAGMA query_only = ON")
        tables = [
            row[0]
            for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
            )
        ]
        for table in tables:
            quoted = table.replace('"', '""')
            counts[table] = int(
                connection.execute('SELECT COUNT(*) FROM "' + quoted + '"').fetchone()[0]
            )
    finally:
        # Closing matters on Windows: an open handle blocks the temp dir cleanup.
        connection.close()
    return counts


def measure_source(spec: Mapping, redact: Callable[[str], str]) -> dict:
    """Measure one source; the returned record is what lands in the manifest."""
    record = {
        "key": spec["key"],
        "label": spec["label"],
        "kind": spec["kind"],
        "required": bool(spec.get("required", False)),
        "location": redact(str(spec["path"])) if spec.get("path") else "",
        "note": spec.get("note", ""),
        "status": "absent",
        "fileCount": 0,
        "bytes": 0,
        "files": [],
        "error": "",
    }
    if spec["kind"] == "cloud":
        record["status"] = "not_measured"
        return record

    path = spec.get("path")
    if path is None:
        record["status"] = "not_measured"
        return record
    path = Path(path)
    if not path.exists():
        return record
    try:
        if spec["kind"] == "chrome-pattern":
            if not path.is_dir():
                raise NotADirectoryError(str(path) + " is not a directory")
            files = measure_chrome_profiles(path)
        elif spec["kind"] == "dir":
            if not path.is_dir():
                raise NotADirectoryError(str(path) + " is not a directory")
            files = measure_files(path)
        elif spec["kind"] == "file":
            if not path.is_file():
                raise IsADirectoryError(str(path) + " is not a file")
            files = [
                {
                    "rel": path.name,
                    "bytes": path.stat().st_size,
                    "sha256": sha256_file(path),
                }
            ]
        else:
            raise ValueError("unknown source kind " + repr(spec["kind"]))
    except (OSError, ValueError) as exc:
        record["status"] = "unreadable"
        record["error"] = redact(str(exc))
        return record

    record["status"] = "present"
    record["files"] = files
    record["fileCount"] = len(files)
    record["bytes"] = sum(item["bytes"] for item in files)
    if spec["kind"] == "dir" and spec.get("count_rows"):
        counts: dict[str, dict] = {}
        for item in files:
            if not item["rel"].endswith((".sqlite3", ".db")):
                continue
            try:
                counts[item["rel"]] = sqlite_row_counts(path / item["rel"])
            except sqlite3.Error as exc:
                # Bytes are readable but rows are not counted: say so instead of
                # reporting an empty database, which is a different fact.
                counts[item["rel"]] = {"error": str(exc)}
        record["rowCounts"] = counts
    return record


def default_sources(repo: Path, env: Mapping[str, str]) -> list[dict]:
    temp = Path(env["TEMP"]) if env.get("TEMP") else None
    return [
        {
            "key": "server-uploads",
            "label": "Document bytes uploaded to the proxy",
            "kind": "dir",
            "path": repo / "server" / ".uploads",
            "required": True,
            "note": "presigned-upload store; bytes + meta sidecars",
        },
        {
            "key": "server-cache",
            "label": "Engine cache and config (SQLite)",
            "kind": "dir",
            "path": repo / "server" / ".cache",
            "required": True,
            "count_rows": True,
            "note": "paid-for review results; row counts only, no payload",
        },
        {
            "key": "server-shares",
            "label": "Shared HTML reports",
            "kind": "dir",
            "path": repo / "server" / ".shares",
            "required": True,
            "note": "share-by-link reports",
        },
        {
            "key": "server-classes",
            "label": "Class records (JSON store)",
            "kind": "dir",
            "path": repo / "server" / ".classes",
            "note": "one JSON file per class",
        },
        {
            "key": "server-submissions",
            "label": "Submission records (JSON store)",
            "kind": "dir",
            "path": repo / "server" / ".submissions",
            "note": "one JSON file per submission",
        },
        {
            "key": "desktop-sembast",
            "label": "Desktop local history (Sembast)",
            "kind": "file",
            "path": Path(env["APPDATA"]) / "co.resonancetech" / "srs_review_ai" / "srs_review_ai.db"
            if env.get("APPDATA")
            else None,
            "note": "path_provider app-support dir on Windows",
        },
        {
            "key": "web-fixed-profile",
            "label": "Fixed Chrome profile (web history)",
            "kind": "dir",
            "path": Path(env["LOCALAPPDATA"]) / "srs-review-ai" / "chrome-profile"
            if env.get("LOCALAPPDATA")
            else None,
            "note": "dev_web.ps1 origin; IndexedDB history lives here",
        },
        {
            "key": "web-temp-profile",
            "label": "Throwaway flutter run profile (web)",
            "kind": "chrome-pattern",
            "path": temp / "flutter_tools.3427e008" if temp else None,
            "note": "temp profile found on this machine; origin http://localhost:56119",
        },
        {
            "key": "firestore",
            "label": "Firestore: grants, personal projects, reports, crash mirror",
            "kind": "cloud",
            "path": None,
            "note": "needs Admin credential + project; see WP0 evidence for the exact ask",
        },
    ]


def build_report(
    sources: Sequence[Mapping],
    repo: Path,
    env: Mapping[str, str],
    require: Iterable[str] = (),
) -> tuple[dict, int]:
    redact = build_redactor(repo, env)
    required = {str(key) for key in require}
    records = []
    for spec in sources:
        spec = dict(spec)
        if spec["key"] in required:
            spec["required"] = True
        records.append(measure_source(spec, redact))

    totals = {"present": 0, "absent": 0, "unreadable": 0, "not_measured": 0}
    for record in records:
        totals[record["status"]] += 1
    broken = [
        record["key"]
        for record in records
        if record["status"] == "unreadable"
        or (record["required"] and record["status"] != "present")
    ]
    report = {
        "manifestVersion": MANIFEST_VERSION,
        "generatedAt": utc_now(),
        "git": git_snapshot(repo),
        "sources": records,
        "totals": totals,
        "failedSources": broken,
    }
    return report, 1 if broken else 0


def git_snapshot(repo: Path) -> dict:
    try:
        head = git("rev-parse", "HEAD", repo=repo)
        branch = git("rev-parse", "--abbrev-ref", "HEAD", repo=repo)
        status = status_entries(repo)
    except RuntimeError as exc:
        return {"head": "", "branch": "", "status": [], "error": str(exc)}
    return {
        "head": head,
        "branch": branch,
        "status": [entry["status"] + " " + entry["path"] for entry in status],
    }


def git(*args: str, repo: Path = REPO) -> str:
    executable = shutil.which("git")
    if executable is None:
        raise RuntimeError("git executable is unavailable")
    result = subprocess.run(  # noqa: S603 - fixed read-only arguments
        [executable, *args],
        cwd=repo,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if result.returncode:
        raise RuntimeError("git " + " ".join(args) + " failed: " + result.stderr.strip())
    return result.stdout


def status_entries(repo: Path = REPO) -> list[dict]:
    """Porcelain NUL records; -z avoids Git's non-ASCII path quoting."""
    raw = git("status", "--porcelain=v1", "-z", "--untracked-files=all", repo=repo)
    fields = [field for field in raw.split("\0") if field]
    entries: list[dict] = []
    index = 0
    while index < len(fields):
        record = fields[index]
        code = record[:2].strip() or "?"
        path = record[3:]
        entries.append({"status": code, "path": path})
        index += 1
        if code[0] in {"R", "C"}:
            # A rename prints the new path in this record and the old one next.
            index += 1
    return entries


def print_report(report: Mapping, out_path: Path | None, redact: Callable[[str], str]) -> None:
    for record in report["sources"]:
        flag = {
            "present": "present",
            "absent": "absent",
            "unreadable": "UNREADABLE",
            "not_measured": "not measured",
        }[record["status"]]
        detail = "{:>4} files {:>12,} B".format(record["fileCount"], record["bytes"])
        if record.get("error"):
            detail = redact(record["error"])
        if record["required"]:
            detail += "  [required]"
        print("[{:12}] {:22} {:40} {}".format(flag, record["key"], detail, record["location"]))
        counts = record.get("rowCounts") or {}
        for name, value in counts.items():
            if "error" in value:
                print("{:14} rows {}: unavailable ({})".format("", name, value["error"]))
            else:
                joined = ", ".join(table + "=" + str(rows) for table, rows in sorted(value.items()))
                print("{:14} rows {}: {}".format("", name, joined or "no tables"))
    totals = report["totals"]
    print(
        "\nTotals: "
        + ", ".join(name + "=" + str(totals[name]) for name in sorted(totals))
        + "; git HEAD="
        + report["git"].get("head", "")[:12]
        + "; dirty="
        + str(len(report["git"].get("status", [])))
    )
    if report["failedSources"]:
        print("FAILED sources: " + ", ".join(report["failedSources"]))
    if out_path is not None:
        print("Manifest: " + str(out_path))


def write_json(path: Path, payload: Mapping) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(payload, indent=2, ensure_ascii=False) + "\n"
    path.write_text(text, encoding="utf-8", newline="\n")


def command_inventory(args: argparse.Namespace) -> int:
    repo = Path(args.repo).resolve() if args.repo else REPO
    env = dict(os.environ)
    if args.apdata:
        env["APPDATA"] = args.apdata
    if args.localapdata:
        env["LOCALAPPDATA"] = args.localapdata
    if args.temp:
        env["TEMP"] = args.temp
    sources = default_sources(repo, env)
    report, code = build_report(sources, repo, env, require=args.require or ())
    redact = build_redactor(repo, env)
    out_path = Path(args.out).resolve() if args.out else None
    if out_path is not None:
        write_json(out_path, report)
    print_report(report, out_path, redact)
    return code


def command_backup(args: argparse.Namespace) -> int:
    repo = Path(args.repo).resolve() if args.repo else REPO
    dest = Path(args.dest).expanduser().resolve() if args.dest else Path.home() / "srs-review-ai-backups"
    try:
        target, manifest = create_backup(dest, repo=repo)
    except (OSError, RuntimeError) as exc:
        print("Backup failed: " + str(exc))
        return 1
    print("Backup: " + str(target))
    print("  files copied: " + str(len(manifest["files"])))
    print("  working-tree diff: " + str(manifest["diff"]["bytes"]) + " B")
    print("  manifest: " + str(target / "manifest.json"))
    return 0


def create_backup(
    dest: Path,
    repo: Path = REPO,
    entries: Sequence[Mapping] | None = None,
) -> tuple[Path, dict]:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    target = dest / ("wp0-backup-" + stamp)
    suffix = 2
    while target.exists():
        target = dest / ("wp0-backup-" + stamp + "-" + str(suffix))
        suffix += 1
    target.mkdir(parents=True)
    entries = list(entries) if entries is not None else status_entries(repo)
    files = []
    for entry in entries:
        source = repo / entry["path"]
        record = {
            "path": entry["path"],
            "status": entry["status"],
            "sourceSha256": None,
            "copySha256": None,
            "bytes": 0,
            "note": "",
        }
        if source.is_file():
            copy = target / "files" / entry["path"]
            copy.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, copy)
            record["sourceSha256"] = sha256_file(source)
            record["copySha256"] = sha256_file(copy)
            record["bytes"] = copy.stat().st_size
        elif source.exists():
            record["note"] = "not a regular file; not copied"
        else:
            record["note"] = "deleted in worktree; nothing to copy"
        files.append(record)

    diff = git("diff", "--binary", "--no-color", repo=repo).encode("utf-8")
    diff_path = target / "working-tree.diff"
    diff_path.write_bytes(diff)
    manifest = {
        "manifestVersion": MANIFEST_VERSION,
        "createdAt": utc_now(),
        "head": git("rev-parse", "HEAD", repo=repo),
        "branch": git("rev-parse", "--abbrev-ref", "HEAD", repo=repo),
        "status": [item["status"] + " " + item["path"] for item in entries],
        "diff": {
            "path": "working-tree.diff",
            "bytes": len(diff),
            "sha256": hashlib.sha256(diff).hexdigest(),
        },
        "files": files,
    }
    write_json(target / "manifest.json", manifest)
    return target, manifest


def verify_backup(path: Path, repo: Path = REPO) -> int:
    manifest_path = path / "manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print("Cannot read manifest: " + str(exc))
        return 1
    failures: list[str] = []
    drift: list[str] = []
    for entry in manifest.get("files", []):
        if not entry.get("copySha256"):
            # Deleted in the worktree or not a regular file: there is no copy to
            # check, and the manifest note says why.
            continue
        copy = path / "files" / entry["path"]
        if not copy.is_file():
            failures.append("missing copy: " + entry["path"])
            continue
        if sha256_file(copy) != entry["copySha256"]:
            failures.append("copy hash mismatch: " + entry["path"])
        source = repo / entry["path"]
        if entry.get("sourceSha256") and source.is_file():
            if sha256_file(source) != entry["sourceSha256"]:
                drift.append(entry["path"])
    diff_rel = manifest.get("diff", {}).get("path", "working-tree.diff")
    diff_path = path / diff_rel
    if diff_path.is_file():
        if hashlib.sha256(diff_path.read_bytes()).hexdigest() != manifest["diff"]["sha256"]:
            failures.append("working-tree diff hash mismatch")
    else:
        failures.append("working-tree diff missing")
    print("Backup: " + str(path))
    print("  checked " + str(len(manifest.get("files", []))) + " file(s)")
    print("  worktree drift since backup: " + str(len(drift)))
    for item in drift:
        print("    DRIFT " + item)
    if failures:
        for item in failures:
            print("    FAIL " + item)
        return 1
    print("  all hashes match")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)

    inventory = sub.add_parser("inventory", help="measure local data sources")
    inventory.add_argument("--out", help="write the JSON manifest here")
    inventory.add_argument("--require", action="append", help="source key that must exist")
    inventory.add_argument("--repo", help="measure a different checkout (tests)")
    inventory.add_argument("--apdata", help="override APPDATA")
    inventory.add_argument("--localapdata", help="override LOCALAPPDATA")
    inventory.add_argument("--temp", help="override TEMP")
    inventory.set_defaults(func=command_inventory)

    backup = sub.add_parser("backup", help="copy uncommitted work outside the repo")
    backup.add_argument("--dest", help="parent directory for the backup")
    backup.add_argument("--repo", help="back up a different checkout (tests)")
    backup.set_defaults(func=command_backup)

    verify = sub.add_parser("verify", help="re-hash a backup directory")
    verify.add_argument("path")
    verify.add_argument("--repo", help="compare against a different checkout (tests)")
    verify.set_defaults(func=command_verify)
    return parser


def command_verify(args: argparse.Namespace) -> int:
    repo = Path(args.repo).resolve() if args.repo else REPO
    return verify_backup(Path(args.path).resolve(), repo=repo)


def main(argv: Sequence[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    args = build_parser().parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Audit the local stashes against HEAD -- what is in them that HEAD does not have.

Run:  python tools/audit_stashes.py              # every entry in `git stash list`
      python tools/audit_stashes.py stash@{0}    # one entry (any stash-shaped ref)

Why it exists: the two 2026-09-26 stashes were audited by hand, one git command
at a time, and the two questions that decided everything were "does HEAD have
every file this stash has" and "would it even apply". Both are printed here,
plus the measurements that took the longest to get right: how many blobs are
byte-identical, how many lines carry the failed-bulk-rewrite signature, and the
CR bytes on each side of every differing file.

The per-file table ends in two CR columns, stash side then HEAD side:

  CR     every 0x0D byte. A blob that carries CR makes every later one-line edit
to that file a whole-file diff, and `git diff --numstat` counts each line as
deleted + added -- the 416-line phantom in AGENTS.md.
  bare   CR bytes NOT followed by LF. One bare CR is enough for git to read the
file as `-text`, and autocrlf never normalises a `-text` file; that is how 445
CRLF lines plus 4 bare CR survived in a tracked blob for weeks. A file whose CR
and bare counts are equal is pure CRLF: ordinary, and invisible after a checkout
on a clone with core.autocrlf=true.

Two notes from that audit (details: docs/evidence/stash-audit-2026-09-30.md):

  * `git diff --diff-filter=D <stash> HEAD` is the load-bearing check -- it lists
    the files the stash has and HEAD does not, the only result that means "look
    before you drop". Everything else on the page is context for that.
  * The output is ASCII by design. stdout on this machine is cp1258, so a
    Vietnamese string printed here raises UnicodeEncodeError halfway through a
    run and the table above it is lost (AGENTS.md).

Exit code 1 when a stash holds a file HEAD does not have, when it was captured
with untracked files, and when the audit itself cannot run (git missing, the
stash list unreadable, a partial `cat-file --batch` parse). It never exits 0 for
"could not look", and never exits 0 for "there was nothing to look at" unless
the stash list really is empty -- an empty list and an unreadable one used to
print the same line.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PATH_WIDTH = 76

# The signature of the failed bulk import rewrite found in stash@{1} on
# 2026-09-30: lines like `iiiiimimport 'package:...'`, `ort 'package:...'`,
# `port 'package:...'` -- a script that rewrote import blocks by injecting text
# instead of replacing it. Seven test files carried 92 of them; HEAD never did.
BROKEN_IMPORT = re.compile(r"^(i+im.*import|ort\s+[\"']|port\s+[\"'])", re.MULTILINE)


class CannotAudit(RuntimeError):
    """The audit could not be taken. Never report that as a pass."""


def git(*args: str, stdin: bytes | None = None) -> subprocess.CompletedProcess[bytes]:
    try:
        return subprocess.run(
            ["git", "-C", str(REPO), *args],
            input=stdin,
            capture_output=True,
        )
    except FileNotFoundError as exc:
        raise CannotAudit(f"git not found: {exc}") from exc


def git_required(*args: str, stdin: bytes | None = None) -> bytes:
    """For calls whose silence would turn into a false verdict.

    `git diff --diff-filter=D <stash> HEAD` is the load-bearing check here; if it
    fails and returns nothing, the verdict reads "CONTAINED" while nothing was
    compared. Same for the stash list: empty and unreadable must not look alike.
    """
    result = git(*args, stdin=stdin)
    if result.returncode != 0:
        message = result.stderr.decode("utf-8", "replace").strip().splitlines()
        raise CannotAudit(
            f"git {' '.join(args)} failed ({result.returncode}): "
            f"{message[0] if message else 'no output'}"
        )
    return result.stdout


def git_text(*args: str) -> str:
    return git(*args).stdout.decode("utf-8", "replace")


def git_text_required(*args: str) -> str:
    return git_required(*args).decode("utf-8", "replace")


def cr_bytes(blob: bytes) -> tuple[int, int]:
    """(CR bytes, bare CR bytes) where bare = CR not followed by LF."""
    cr = blob.count(b"\r")
    return cr, cr - blob.count(b"\r\n")


def tree_blobs(rev: str) -> dict[str, str]:
    """path -> blob sha for one revision, from a single `ls-tree -r -z`."""
    blobs: dict[str, str] = {}
    for record in git_required("ls-tree", "-r", "-z", rev).split(b"\0"):
        if not record:
            continue
        meta, _, raw_path = record.partition(b"\t")
        fields = meta.split()
        if len(fields) >= 3:
            blobs[raw_path.decode("utf-8", "replace")] = fields[2].decode("ascii")
    return blobs


def blob_contents(shas: list[str]) -> dict[str, bytes]:
    """sha -> content for many blobs, through one `git cat-file --batch`."""
    wanted = sorted({sha for sha in shas if sha})
    if not wanted:
        return {}
    request = b"".join(sha.encode("ascii") + b"\n" for sha in wanted)
    output = git_required("cat-file", "--batch", stdin=request)
    contents: dict[str, bytes] = {}
    offset = 0
    while offset < len(output):
        end = output.find(b"\n", offset)
        if end < 0:
            raise CannotAudit("cat-file --batch output ended mid-header")
        header = output[offset:end].split()
        if len(header) < 3:
            raise CannotAudit(f"cat-file --batch header unparsable: {header!r}")
        start = end + 1
        size = int(header[2])
        contents[header[0].decode("ascii")] = output[start : start + size]
        offset = start + size + 1
    if len(contents) != len(wanted):
        raise CannotAudit(
            f"cat-file --batch returned {len(contents)} of {len(wanted)} blobs -- "
            "a partial read must not be reported as a clean comparison"
        )
    return contents


def content_of(blobs: dict[str, str], contents: dict[str, bytes], path: str) -> bytes:
    return contents.get(blobs.get(path, ""), b"")


def numstat(rev_a: str, rev_b: str, ignore_whitespace: bool = False) -> dict[str, str]:
    """path -> "added/deleted", as git diff reports it, optionally ignoring -w."""
    flags = ["-w"] if ignore_whitespace else []
    stats: dict[str, str] = {}
    for line in git_text_required(
        "diff", *flags, "--numstat", rev_a, rev_b
    ).splitlines():
        parts = line.split("\t")
        if len(parts) == 3:
            stats[parts[2]] = f"{parts[0]}/{parts[1]}"
    return stats


def stash_paths(ref: str) -> list[str]:
    return [
        line.split("\t")[-1]
        for line in git_text_required(
            "stash", "show", "--name-status", ref
        ).splitlines()
        if line.strip()
    ]


def stash_entries() -> list[tuple[str, str]]:
    entries: list[tuple[str, str]] = []
    for line in git_text_required("stash", "list", "--format=%gd%x09%gs").splitlines():
        ref, _, title = line.partition("\t")
        if ref.strip():
            entries.append((ref.strip(), title.strip()))
    return entries


def describe(ref: str, title: str, head_blobs: dict[str, str]) -> tuple[int, str]:
    """Render one stash. The returned weight is 1 when HEAD lacks one of its files."""
    parents = git_text("log", "-1", "--format=%P", ref).split()
    base = parents[0] if parents else ""
    ancestor = git("merge-base", "--is-ancestor", base, "HEAD").returncode == 0
    has_untracked = len(parents) > 2
    delta = (
        git_text_required("diff", "--shortstat", f"{ref}^1", ref).strip() or "no change"
    )

    paths = stash_paths(ref)
    blobs = tree_blobs(ref)
    stash_contents = blob_contents([blobs[path] for path in paths if path in blobs])

    identical: list[str] = []
    differing: list[str] = []
    for path in paths:
        if path not in head_blobs:
            continue
        if head_blobs[path] == blobs.get(path):
            identical.append(path)
        else:
            differing.append(path)

    missing = [
        line
        for line in git_text_required(
            "diff", "--diff-filter=D", "--name-only", ref, "HEAD"
        ).splitlines()
        if line.strip()
    ]

    broken_files: dict[str, int] = {}
    for path in paths:
        hits = len(
            BROKEN_IMPORT.findall(
                content_of(blobs, stash_contents, path).decode("utf-8", "replace")
            )
        )
        if hits:
            broken_files[path] = hits

    raw = numstat(ref, "HEAD")
    content = numstat(ref, "HEAD", ignore_whitespace=True)
    churn_only = [path for path in differing if content.get(path, "0/0") == "0/0"]
    head_contents = blob_contents([head_blobs[path] for path in differing])

    patch = git_required("stash", "show", "-p", ref)
    applied = subprocess.run(
        ["git", "-C", str(REPO), "apply", "--check"],
        input=patch,
        capture_output=True,
    )
    applies = applied.returncode == 0
    errors = [
        line.removeprefix("error: ")
        for line in applied.stderr.decode("utf-8", "replace").splitlines()
        if line.startswith("error:")
    ]
    if applies:
        apply_note = ""
    elif errors:
        apply_note = f"{len(errors)} error(s), first: {errors[0]}"
    else:
        apply_note = "patch does not apply"

    lines = [
        f"[{ref}] {title}",
        f"  base {base[:7]} (ancestor of HEAD: {'yes' if ancestor else 'NO'})"
        f" | own delta: {delta}",
        f"  untracked parent: {'yes' if has_untracked else 'none'}"
        f" | files HEAD lacks: {len(missing)}",
        f"  blobs: {len(identical)} identical, {len(differing)} differ"
        f" ({len(churn_only)} differ only by line endings)",
        f"  broken import lines: {sum(broken_files.values())} in {len(broken_files)} file(s)",
        f"  applies to working tree: {'yes' if applies else 'no -- ' + apply_note}",
    ]

    if differing:
        width = min(PATH_WIDTH, max(len("file"), max(len(path) for path in differing)))
        lines.append("")
        lines.append(
            f"  {'file':<{width}}  raw +/-  content +/-  CR st/HEAD  bare st/HEAD"
        )
        for path in sorted(differing):
            cr_stash, bare_stash = cr_bytes(content_of(blobs, stash_contents, path))
            cr_head, bare_head = cr_bytes(content_of(head_blobs, head_contents, path))
            lines.append(
                f"  {path:<{width}}  {raw.get(path, '-'):<9}"
                f"{content.get(path, '-'):<13}{cr_stash}/{cr_head:<11}"
                f"{bare_stash}/{bare_head}"
            )
        lines.append("")

    if missing or has_untracked:
        verdict = (
            f"NOT CONTAINED -- {len(missing)} file(s) exist only in this stash; "
            "extract them before dropping"
        )
        weight = 1
    elif not differing:
        verdict = "CONTAINED -- every blob is byte-identical to HEAD"
        weight = 0
    elif len(churn_only) == len(differing):
        verdict = (
            f"CONTAINED (line endings only) -- {len(differing)} file(s) identical after"
            " `git diff -w`"
        )
        weight = 0
    else:
        verdict = (
            f"STALE -- differs from HEAD in {len(differing) - len(churn_only)} file(s) of"
            " content; HEAD may have moved past it, so read the diffs before dropping"
        )
        weight = 0

    lines.append(f"  VERDICT: {verdict}")
    for path in sorted(missing):
        lines.append(f"    missing in HEAD: {path}")
    lines.append("")
    return weight, "\n".join(lines)


def run(argv_refs: list[str]) -> int:
    entries = [(ref, "") for ref in argv_refs] or stash_entries()
    if not entries:
        print("no stashes to audit (git stash list is empty)")
        return 0

    print(f"repo  {REPO}")
    print(f"HEAD  {git_text_required('log', '-1', '--format=%h %s', 'HEAD').strip()}")

    head_blobs = tree_blobs("HEAD")
    weight = 0
    for ref, title in entries:
        if (
            git("rev-parse", "--verify", "--quiet", f"{ref}^1").returncode != 0
        ):  # tolerant: existence check
            print(f"\n[{ref}] cannot be read as a stash-shaped commit -- skipped")
            weight = 1
            continue
        print()
        entry_weight, text = describe(ref, title, head_blobs)
        weight = max(weight, entry_weight)
        print(text)
    return weight


def main() -> int:
    if sys.stdout.encoding and sys.stdout.encoding.lower() not in {"utf-8", "utf8"}:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    try:
        return run(sys.argv[1:])
    except CannotAudit as exc:
        print(f"stash audit NOT MEASURED: {exc}")
        return 1


if __name__ == "__main__":
    sys.exit(main())

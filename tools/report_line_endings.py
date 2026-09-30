#!/usr/bin/env python3
"""Print the line-ending numbers for the files a push changes.

Why this exists next to rule 9 of check_guardrails.py: the rule says "no stored
text blob carries CR", but a bare count does not show *why* it matters. This
prints, per changed file, the CR bytes on each side of the push -- worktree file,
base blob, revision blob -- plus the churn those bytes cause (raw diff lines vs
`-w` diff lines). That is the difference between "a rule fired" and "this file
will turn every later one-line edit into a whole-file diff".

It separates two mechanisms, because only one of them is obvious:

  blob-cr          the stored blob carries CR. Every later diff of the file is a
                   whole-file diff and `git diff --numstat` counts each line as
                   both deleted and added.
  worktree-bare-cr CR bytes NOT followed by LF. A single bare CR is enough to
                   make git read the whole file as `-text`, and a `-text` file is
                   never normalised by core.autocrlf=true -- which is how 445
                   CRLF lines plus 4 bare CR survived in one file for weeks
                   (measured 2026-09-30; AGENTS.md has the story).

A worktree that is pure CRLF with an LF blob is NOT a defect: with
core.autocrlf=true that is the normal state on Windows, so it is reported as a
note, never as a failure.

Usage (from anywhere inside the repo):
    python tools/report_line_endings.py                   # HEAD vs HEAD^
    python tools/report_line_endings.py --base origin/dev
    python tools/report_line_endings.py --rev 6f85c23^    # judge an older revision
    LINE_ENDINGS_BASE=<sha> python tools/report_line_endings.py

Exit codes: 1 when a changed text blob carries CR (or the worktree does, through
a bare CR), and 1 when the measurement cannot be taken at all -- never 0 for
"could not look", never 0 for "looked at nothing".
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

# Console guard (AGENTS.md): a cp1258 console kills this script mid-table, and
# the rows already printed are all the reader would have seen.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_guardrails import is_text_blob  # noqa: E402


class CannotMeasure(RuntimeError):
    """The measurement could not be taken. Never report that as a pass."""


REPO: Path | None = None


def git(*args: str, input_bytes: bytes | None = None) -> bytes:
    if REPO is None:
        raise CannotMeasure("repository root was never resolved")
    try:
        return subprocess.run(
            ["git", "-C", str(REPO), *args],
            input=input_bytes,
            capture_output=True,
            check=True,
        ).stdout
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        raise CannotMeasure(f"git {' '.join(args)} failed: {exc}") from exc


def repo_root() -> Path:
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=Path.cwd(),
            capture_output=True,
            check=True,
            text=True,
        ).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        raise CannotMeasure(f"not inside a git work tree: {exc}") from exc
    if not out:
        raise CannotMeasure("git rev-parse --show-toplevel returned nothing")
    return Path(out)


def resolve(rev: str) -> str | None:
    if REPO is None:
        raise CannotMeasure("repository root was never resolved")
    try:
        out = subprocess.run(
            [
                "git",
                "-C",
                str(REPO),
                "rev-parse",
                "--verify",
                "--quiet",
                f"{rev}^{{commit}}",
            ],
            capture_output=True,
            check=True,
            text=True,
        ).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    return out or None


def changed_paths(base: str, rev: str) -> list[str]:
    """The files this range touches -- NOT the union of the two trees, which is
    the whole repository and would report every file as changed."""
    out = git("diff", "--name-only", "-z", base, rev)
    return sorted({p.decode("utf-8", "replace") for p in out.split(b"\0") if p})


def tree_paths(rev: str) -> dict[str, str]:
    """path -> blob sha for every file in `rev`."""
    out: dict[str, str] = {}
    for record in git("ls-tree", "-r", "-z", rev).split(b"\0"):
        if not record:
            continue
        meta, _, raw_path = record.partition(b"\t")
        fields = meta.split()
        if len(fields) < 3 or fields[1] != b"blob":
            continue
        out[raw_path.decode("utf-8", "replace")] = fields[2].decode("ascii")
    return out


def read_blobs(shas: set[str]) -> dict[str, bytes]:
    """sha -> content straight from the object store, in one `cat-file --batch`.

    No checkout filter in between: this is the byte sequence git actually stores,
    which is the only version of "does this file carry CR" that travels between
    clones.
    """
    if not shas:
        return {}
    ordered = sorted(shas)
    request = b"".join(sha.encode("ascii") + b"\n" for sha in ordered)
    output = git("cat-file", "--batch", input_bytes=request)
    blobs: dict[str, bytes] = {}
    offset = 0
    for sha in ordered:
        end = output.find(b"\n", offset)
        header = output[offset:end].split() if end >= 0 else []
        if len(header) < 3:
            raise CannotMeasure(f"cat-file --batch stopped early at {sha}")
        start = end + 1
        size = int(header[2])
        blobs[sha] = output[start : start + size]
        offset = start + size + 1
    if len(blobs) != len(ordered):
        raise CannotMeasure("cat-file --batch returned fewer blobs than asked")
    return blobs


def numstat(
    base: str, rev: str, paths: list[str], *, ignore_whitespace: bool
) -> dict[str, tuple[int, int]]:
    """path -> (added, deleted), `-z` so a space in a path cannot shift fields."""
    args = ["diff", "--numstat"]
    if ignore_whitespace:
        args.append("-w")
    args += ["-z", base, rev, "--", *paths]
    rows: dict[str, tuple[int, int]] = {}
    fields = git(*args).split(b"\0")
    index = 0
    while index < len(fields):
        record = fields[index]
        index += 1
        if not record:
            continue
        head = record.split(b"\t")
        if len(head) < 2:
            continue
        path = ""
        if len(head) > 2:
            path = head[2].decode("utf-8", "replace")
        else:
            # rename form: the path fields follow as their own NUL-separated ones.
            path = (
                fields[index + 1].decode("utf-8", "replace")
                if index + 1 < len(fields)
                else ""
            )
            index += 2
        try:
            rows[path] = (int(head[0]), int(head[1]))
        except ValueError:
            rows[path] = (-1, -1)  # binary: git prints "-" for both counts
    return rows


def count_cr(blob: bytes) -> tuple[int, int]:
    """(CR bytes, CRLF pairs). CR > CRLF means there are bare CR bytes."""
    return blob.count(b"\r"), blob.count(b"\r\n")


def shorten(path: str, width: int = 50) -> str:
    if len(path) <= width:
        return path
    return path[:14] + "..." + path[-(width - 17) :]


def cell(value: int | None) -> str:
    return "-" if value is None else str(value)


def pair(value: tuple[int, int] | None) -> str:
    return "-" if value is None else f"{value[0]}/{value[1]}"


def main() -> int:
    global REPO

    argv = sys.argv[1:]
    rev = "HEAD"
    base = os.environ.get("LINE_ENDINGS_BASE") or None
    while argv:
        flag = argv.pop(0)
        if flag == "--rev" and argv:
            rev = argv.pop(0)
        elif flag == "--base" and argv:
            base = argv.pop(0)
        else:
            print(f"unknown argument: {flag}")
            print("usage: report_line_endings.py [--rev REV] [--base REV]")
            return 1

    REPO = repo_root()

    rev_sha = resolve(rev)
    if rev_sha is None:
        print(f"line endings NOT MEASURED: '{rev}' is not a commit in this clone")
        return 1

    wanted_base = base if base is not None else f"{rev}^"
    base_sha = resolve(wanted_base)

    rev_paths = tree_paths(rev_sha)
    base_paths = tree_paths(base_sha) if base_sha else {}

    if base_sha is None:
        changed = sorted(rev_paths)
    else:
        changed = changed_paths(base_sha, rev_sha)

    if not changed:
        print(
            f"line endings: {wanted_base}..{rev} touches no file (nothing to measure)"
        )
        return 0

    raw = (
        numstat(base_sha, rev_sha, changed, ignore_whitespace=False) if base_sha else {}
    )
    content = (
        numstat(base_sha, rev_sha, changed, ignore_whitespace=True) if base_sha else {}
    )

    wanted_shas = {rev_paths[p] for p in changed if p in rev_paths}
    wanted_shas |= {base_paths[p] for p in changed if p in base_paths}
    blobs = read_blobs(wanted_shas)

    print(f"repo     {REPO}")
    print(f"range    {(base_sha or wanted_base)[:9]} .. {rev} ({rev_sha[:9]})")
    if base_sha is None:
        print(
            f"         base '{wanted_base}' is not a commit in this clone (shallow\n"
            f"         clone, or the first commit of a branch), so every tracked\n"
            f"         file at {rev} is measured instead of just the changed ones\n"
            f"         -- and this is stated rather than passed off as a push range"
        )
    print(f"changed  {len(changed)} file(s)")
    print()

    header = (
        f"{'file':<50} {'wt_cr':>7} {'base_cr':>7} {'rev_cr':>6} {'wt_bare':>7} "
        f"{'raw+/-':>11} {'content+/-':>12}  verdict"
    )
    print(header)
    print("-" * len(header))

    failures: list[str] = []
    notes: list[str] = []
    measured = 0
    skipped_binary = 0
    hidden = 0
    # A whole-tree fallback (no base) can be hundreds of rows of the same note.
    # Print everything for a normal push-sized diff, and only the rows that need
    # a decision when the set is large -- the totals below always count them all.
    show_all = len(changed) <= 40

    for path in changed:
        disk = REPO / path
        try:
            worktree = disk.read_bytes() if disk.is_file() else None
        except OSError:
            worktree = None

        rev_blob = blobs.get(rev_paths[path]) if path in rev_paths else None
        base_blob = blobs.get(base_paths[path]) if path in base_paths else None

        wt_cr, wt_crlf = count_cr(worktree) if worktree is not None else (None, None)
        rev_cr, rev_crlf = count_cr(rev_blob) if rev_blob is not None else (None, None)
        base_cr = count_cr(base_blob)[0] if base_blob is not None else None
        bare_wt = (wt_cr - wt_crlf) if wt_cr is not None else None

        if rev_blob is None:
            verdict = "deleted in this range"
        elif not is_text_blob(rev_blob):
            skipped_binary += 1
            verdict = "skip: not a text blob"
        else:
            measured += 1
            bare_blob = rev_cr - rev_crlf
            if rev_cr and bare_blob:
                verdict = (
                    f"FAIL blob-cr + {bare_blob} bare CR in the blob: git stores it "
                    f"as -text and autocrlf never normalises it"
                )
                failures.append(path)
            elif rev_cr:
                verdict = (
                    f"FAIL blob-cr: {rev_cr} CR in the blob, so every later "
                    f"one-line edit is a whole-file diff"
                )
                failures.append(path)
            elif bare_wt:
                verdict = (
                    f"FAIL worktree-bare-cr: {bare_wt} CR not followed by LF, so this "
                    f"file is -text and the next `git add` can store CRLF"
                )
                failures.append(path)
            elif wt_cr:
                verdict = (
                    "note: worktree CRLF, blob LF (normal with core.autocrlf=true)"
                )
                notes.append(path)
            else:
                verdict = "ok"

        interesting = verdict.startswith("FAIL") or verdict.startswith("deleted")
        if show_all or interesting:
            print(
                f"{shorten(path):<50} {cell(wt_cr):>9} {cell(base_cr):>6} "
                f"{cell(rev_cr):>5} {cell(bare_wt):>5} "
                f"{pair(raw.get(path)):>11} {pair(content.get(path)):>12}  {verdict}"
            )
        else:
            hidden += 1

    print()
    if hidden:
        print(f"{hidden} clean row(s) not shown (all {len(changed)} were measured).")
    print(
        f"text blobs measured: {measured} of {len(changed)} file(s)"
        f"{f' ({skipped_binary} skipped as binary)' if skipped_binary else ''}"
    )
    print("columns  wt_cr/base_cr/rev_cr = CR bytes in the worktree file, the base")
    print("         blob and the rev blob; wt_bare = worktree CR not followed by LF")
    print("         (the verdict column reports the same count for the blob); then")
    print("         raw diff lines vs `-w` (whitespace-blind) lines -- raw >> content")
    print("         is what whole-file churn looks like from outside")
    if notes:
        print(
            f"{len(notes)} file(s) are worktree-CRLF with an LF blob: normal on a "
            f"core.autocrlf=true clone, nothing to fix."
        )
    if failures:
        print()
        print(f"{len(failures)} file(s) will churn: {', '.join(failures)}")
        print("Fix: write the file with LF, or `git add --renormalize <path>`.")
        return 1
    print()
    print("No CR in any changed text blob.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CannotMeasure as exc:
        print(f"line endings NOT MEASURED: {exc}")
        sys.exit(1)

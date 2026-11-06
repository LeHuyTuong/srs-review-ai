from contextlib import redirect_stdout
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import wp0_baseline as wp0


class InventoryTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.env = {
            "APPDATA": str(self.root / "appdata"),
            "LOCALAPPDATA": str(self.root / "localappdata"),
            "TEMP": str(self.root / "temp"),
            "USERPROFILE": str(self.root / "home"),
        }
        self.redact = wp0.build_redactor(self.repo, self.env)

    def tearDown(self):
        self.tempdir.cleanup()

    def test_dir_source_counts_bytes_and_hashes_every_file(self):
        store = self.repo / "server" / ".uploads"
        store.mkdir(parents=True)
        (store / "a.pdf").write_bytes(b"abc")
        (store / "b.meta.json").write_bytes(b"{}")
        spec = {
            "key": "uploads",
            "label": "uploads",
            "kind": "dir",
            "path": store,
            "required": True,
        }
        record = wp0.measure_source(spec, self.redact)
        self.assertEqual(record["status"], "present")
        self.assertEqual(record["fileCount"], 2)
        self.assertEqual(record["bytes"], 5)
        hashes = {item["rel"]: item["sha256"] for item in record["files"]}
        self.assertEqual(hashes["a.pdf"], wp0.sha256_file(store / "a.pdf"))
        self.assertEqual(hashes["b.meta.json"], wp0.sha256_file(store / "b.meta.json"))

    def test_absent_source_is_measured_not_invented(self):
        spec = {
            "key": "classes",
            "label": "classes",
            "kind": "dir",
            "path": self.repo / "server" / ".classes",
        }
        record = wp0.measure_source(spec, self.redact)
        self.assertEqual(record["status"], "absent")
        self.assertEqual(record["fileCount"], 0)
        self.assertEqual(record["files"], [])

    def test_required_missing_source_fails_the_run(self):
        sources = [
            {
                "key": "uploads",
                "label": "uploads",
                "kind": "dir",
                "path": self.repo / "missing",
                "required": True,
            }
        ]
        report, code = wp0.build_report(sources, self.repo, self.env)
        self.assertEqual(code, 1)
        self.assertEqual(report["failedSources"], ["uploads"])

    def test_optional_missing_source_does_not_fail_the_run(self):
        sources = [
            {
                "key": "classes",
                "label": "classes",
                "kind": "dir",
                "path": self.repo / "missing",
            }
        ]
        _report, code = wp0.build_report(sources, self.repo, self.env)
        self.assertEqual(code, 0)

    def test_require_flag_promotes_a_source_to_required(self):
        sources = [
            {
                "key": "classes",
                "label": "classes",
                "kind": "dir",
                "path": self.repo / "missing",
            }
        ]
        report, code = wp0.build_report(sources, self.repo, self.env, require=["classes"])
        self.assertEqual(code, 1)
        self.assertEqual(report["failedSources"], ["classes"])

    def test_a_file_where_a_directory_belongs_is_unreadable_not_absent(self):
        wrong = self.repo / "server" / ".uploads"
        wrong.parent.mkdir(parents=True)
        wrong.write_text("not a directory", encoding="utf-8")
        spec = {"key": "uploads", "label": "uploads", "kind": "dir", "path": wrong}
        record = wp0.measure_source(spec, self.redact)
        self.assertEqual(record["status"], "unreadable")
        self.assertTrue(record["error"])

    def test_sqlite_row_counts_are_read_without_writing(self):
        database = self.repo / "cache.sqlite3"
        connection = __import__("sqlite3").connect(database)
        connection.execute("CREATE TABLE cache_entries (k TEXT)")
        connection.executemany("INSERT INTO cache_entries VALUES (?)", [("a",), ("b",)])
        connection.commit()
        connection.close()
        before = wp0.sha256_file(database)
        counts = wp0.sqlite_row_counts(database)
        self.assertEqual(counts, {"cache_entries": 2})
        self.assertEqual(wp0.sha256_file(database), before)

    def test_manifest_redacts_absolute_user_paths(self):
        sources = [
            {
                "key": "sembast",
                "label": "sembast",
                "kind": "file",
                "path": Path(self.env["APPDATA"]) / "co.resonancetech" / "srs_review_ai.db",
            }
        ]
        report, _code = wp0.build_report(sources, self.repo, self.env)
        location = report["sources"][0]["location"]
        self.assertEqual(location, "<APPDATA>" + os.sep + "co.resonancetech" + os.sep + "srs_review_ai.db")
        self.assertNotIn(str(self.root), json.dumps(report))

    def test_redactor_prefers_the_longest_prefix(self):
        inner = Path(self.env["LOCALAPPDATA"]) / "Temp" / "x.log"
        self.assertEqual(self.redact(str(inner)), "<LOCALAPPDATA>" + os.sep + "Temp" + os.sep + "x.log")

    def test_chrome_scan_ignores_browser_cache(self):
        base = Path(self.env["TEMP"])
        profile = base / "flutter_tools.aaaa" / "chrome_device" / "Default"
        origin = profile / "IndexedDB" / "http_localhost_5000.indexeddb.leveldb"
        origin.mkdir(parents=True)
        (origin / "000003.log").write_bytes(b"data")
        cache = profile / "Cache"
        cache.mkdir(parents=True)
        (cache / "big.bin").write_bytes(b"x" * 1024)
        spec = {
            "key": "web",
            "label": "web",
            "kind": "chrome-pattern",
            "path": base,
        }
        record = wp0.measure_source(spec, self.redact)
        self.assertEqual(record["status"], "present")
        self.assertEqual(record["fileCount"], 1)
        self.assertTrue(record["files"][0]["rel"].endswith("000003.log"))
        self.assertNotIn("Cache", record["files"][0]["rel"])


class StatusTests(unittest.TestCase):
    def test_porcelain_keeps_non_ascii_paths_intact(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            subprocess.run(["git", "init", "-q", str(repo)], check=True)
            (repo / "Chương 1.pdf").write_bytes(b"x")
            entries = wp0.status_entries(repo)
        self.assertEqual(entries, [{"status": "??", "path": "Chương 1.pdf"}])


class BackupTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        self.repo = self.root / "repo"
        (self.repo / "docs").mkdir(parents=True)
        (self.repo / "docs" / "a.md").write_text("changed\n", encoding="utf-8")
        self.entries = [
            {"status": "M", "path": "docs/a.md"},
            {"status": "D", "path": "docs/gone.md"},
        ]
        self.original_git = wp0.git
        wp0.git = lambda *args, **kwargs: ""  # type: ignore[assignment]

    def tearDown(self):
        wp0.git = self.original_git  # type: ignore[assignment]
        self.tempdir.cleanup()

    def _backup(self):
        return wp0.create_backup(self.root / "backups", repo=self.repo, entries=self.entries)

    def test_backup_copies_work_and_verify_matches_hashes(self):
        target, manifest = self._backup()
        self.assertEqual(manifest["files"][0]["path"], "docs/a.md")
        self.assertEqual(
            manifest["files"][0]["copySha256"], manifest["files"][0]["sourceSha256"]
        )
        self.assertEqual((target / "files" / "docs" / "a.md").read_text(encoding="utf-8"), "changed\n")
        self.assertEqual(manifest["files"][1]["note"], "deleted in worktree; nothing to copy")
        with redirect_stdout(io.StringIO()) as output:
            self.assertEqual(wp0.verify_backup(target, repo=self.repo), 0)
        self.assertIn("all hashes match", output.getvalue())

    def test_verify_fails_when_a_copy_is_tampered_with(self):
        target, _manifest = self._backup()
        (target / "files" / "docs" / "a.md").write_text("tampered\n", encoding="utf-8")
        with redirect_stdout(io.StringIO()) as output:
            self.assertEqual(wp0.verify_backup(target, repo=self.repo), 1)
        self.assertIn("copy hash mismatch", output.getvalue())

    def test_verify_fails_when_a_copy_is_missing(self):
        target, _manifest = self._backup()
        (target / "files" / "docs" / "a.md").unlink()
        with redirect_stdout(io.StringIO()) as output:
            self.assertEqual(wp0.verify_backup(target, repo=self.repo), 1)
        self.assertIn("missing copy", output.getvalue())

    def test_verify_reports_drift_but_still_passes_the_copy_check(self):
        target, _manifest = self._backup()
        (self.repo / "docs" / "a.md").write_text("edited after backup\n", encoding="utf-8")
        with redirect_stdout(io.StringIO()) as output:
            self.assertEqual(wp0.verify_backup(target, repo=self.repo), 0)
        self.assertIn("worktree drift since backup: 1", output.getvalue())

    def test_verify_fails_without_a_manifest(self):
        empty = self.root / "empty"
        empty.mkdir()
        with redirect_stdout(io.StringIO()) as output:
            self.assertEqual(wp0.verify_backup(empty, repo=self.repo), 1)
        self.assertIn("Cannot read manifest", output.getvalue())


if __name__ == "__main__":
    unittest.main()

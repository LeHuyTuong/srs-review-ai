from contextlib import redirect_stdout
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_guardrails as guardrails


class GuardrailInputTests(unittest.TestCase):
    def test_ignored_generated_config_is_skipped_but_source_is_scanned(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            (root / ".gitignore").write_text(
                "local.json\ntracked.json\n", encoding="utf-8"
            )
            for name in ["local.json", "tracked.json", "source.dart"]:
                (root / name).write_text("{}", encoding="utf-8")
            subprocess.run(
                ["git", "-C", str(root), "add", "-f", "tracked.json"], check=True
            )
            with patch.object(guardrails, "REPO", root):
                actual = {p.name for p in guardrails.collect_files()}
            self.assertEqual(actual, {"source.dart", "tracked.json"})

    def test_git_unavailable_fails_closed_without_a_pass_message(self):
        output = io.StringIO()
        with (
            patch.object(guardrails.subprocess, "run", side_effect=FileNotFoundError),
            redirect_stdout(output),
        ):
            self.assertEqual(guardrails.main(), 1)
        self.assertNotIn("All guardrails passed", output.getvalue())

    def test_empty_input_never_passes(self):
        output = io.StringIO()
        with (
            patch.object(guardrails, "collect_files", return_value=[]),
            redirect_stdout(output),
        ):
            self.assertEqual(guardrails.main(), 1)
        self.assertNotIn("All guardrails passed", output.getvalue())

    def test_truncated_git_output_is_rejected(self):
        result = subprocess.CompletedProcess(
            args=["git"], returncode=0, stdout=b"source.dart"
        )
        with patch.object(guardrails.subprocess, "run", return_value=result):
            with self.assertRaises(guardrails.InputUnavailable):
                guardrails.collect_files()

    def test_regex_anchor_is_not_a_secret_assignment_but_real_assignment_is(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / "deploy.sh"
            script.write_text(
                "grep -qE '^APP_TOKEN=.+$' .env\n"
                "APP_TOKEN=not-a-real-token\n"
                "export GEMINI_API_KEY=not-a-real-key\n",
                encoding="utf-8",
            )
            with (
                patch.object(guardrails, "REPO", root),
                patch.object(guardrails, "git_tracked_files", return_value=[]),
            ):
                violations = guardrails.check_secrets([script])
            self.assertEqual([violation.line for violation in violations], [2, 3])


if __name__ == "__main__":
    unittest.main()

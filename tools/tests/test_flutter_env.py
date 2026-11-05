from contextlib import redirect_stderr, redirect_stdout
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import flutter_env


class FlutterEnvironmentTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.addCleanup(patch.stopall)
        patch.dict(os.environ, {}, clear=True).start()
        template = self.root / "mobile/android/app/google-services.json.example"
        template.parent.mkdir(parents=True)
        template.write_text(
            '{"api_key":"${MOBILE_FIREBASE_ANDROID_API_KEY}"}', encoding="utf-8"
        )
        (self.root / ".env").write_text(
            "GEMINI_API_KEY=server-only-sentinel\n"
            "APP_TOKEN=private-server-token\n"
            "MOBILE_FIREBASE_WEB_API_KEY=web-client-value\n"
            "MOBILE_FIREBASE_ANDROID_API_KEY=android-client-value\n"
            "ADMIN_WEB_FIREBASE_WEB_API_KEY=other-app-value\n",
            encoding="utf-8",
        )

    def test_only_selected_client_values_reach_defines_and_native_json(self):
        defines = flutter_env.prepare("mobile", self.root)
        values = json.loads(defines.read_text(encoding="utf-8"))
        self.assertEqual(
            values,
            {
                "MOBILE_FIREBASE_WEB_API_KEY": "web-client-value",
                "MOBILE_FIREBASE_ANDROID_API_KEY": "android-client-value",
            },
        )
        native = self.root / "mobile/android/app/google-services.json"
        self.assertEqual(
            json.loads(native.read_text(encoding="utf-8")),
            {"api_key": "android-client-value"},
        )
        self.assertNotIn("server-only-sentinel", defines.read_text(encoding="utf-8"))

    def test_prepare_is_idempotent_and_environment_overrides_dotenv(self):
        os.environ["MOBILE_FIREBASE_WEB_API_KEY"] = "ci-client-value"
        path = flutter_env.prepare("mobile", self.root)
        first = path.read_bytes()
        flutter_env.prepare("mobile", self.root)
        self.assertEqual(path.read_bytes(), first)
        self.assertEqual(
            json.loads(first)["MOBILE_FIREBASE_WEB_API_KEY"], "ci-client-value"
        )

    def test_missing_variables_do_not_replace_existing_native_config(self):
        os.environ["MOBILE_FIREBASE_ANDROID_API_KEY"] = ""
        native = self.root / "mobile/android/app/google-services.json"
        native.write_text("original", encoding="utf-8")
        with self.assertRaises(flutter_env.ConfigError):
            flutter_env.prepare("mobile", self.root)
        self.assertEqual(native.read_text(encoding="utf-8"), "original")

    def test_template_cannot_request_a_server_secret(self):
        template = self.root / "mobile/android/app/google-services.json.example"
        template.write_text('{"key":"${GEMINI_API_KEY}"}', encoding="utf-8")
        with self.assertRaises(flutter_env.ConfigError):
            flutter_env.prepare("mobile", self.root)
        self.assertFalse(
            (self.root / "mobile/android/app/google-services.json").exists()
        )

    def test_env_parser_preserves_values_without_executing_or_expanding_them(self):
        path = self.root / ".env"
        path.write_text(
            "# comment\nexport A='value=with spaces'\nA=last-value # comment\n"
            'B="$(never-execute)${A}"\nC=\n',
            encoding="utf-8",
        )
        self.assertEqual(
            flutter_env.read_env(path),
            {"A": "last-value", "B": "$(never-execute)${A}", "C": ""},
        )

    def test_error_messages_do_not_print_env_contents(self):
        path = self.root / ".env"
        path.write_text("private-value-without-assignment", encoding="utf-8")
        output = io.StringIO()
        with (
            patch.object(flutter_env, "REPO_ROOT", self.root),
            patch.object(
                flutter_env, "prepare", side_effect=lambda _: flutter_env.read_env(path)
            ),
            patch.object(sys, "argv", ["flutter_env.py", "mobile", "prepare"]),
            redirect_stdout(output),
            redirect_stderr(output),
        ):
            self.assertEqual(flutter_env.main(), 1)
        self.assertNotIn("private-value-without-assignment", output.getvalue())


if __name__ == "__main__":
    unittest.main()

"""Run Flutter with only its Firebase client configuration from the root .env."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

REPO_ROOT = Path(__file__).resolve().parent.parent
CLIENT_KEYS = {
    "mobile": ("MOBILE_FIREBASE_WEB_API_KEY", "MOBILE_FIREBASE_ANDROID_API_KEY"),
    "admin_web": ("ADMIN_WEB_FIREBASE_WEB_API_KEY",),
    "desktop": ("DESKTOP_FIREBASE_ANDROID_API_KEY",),
}
NATIVE_CONFIGS = {
    "mobile": ("android/app/google-services.json",),
    "desktop": ("android/app/google-services.json",),
    "admin_web": (),
}
# Client key web được đọc lúc chạy từ file JS cục bộ (Git ignore), để
# "flutter run" trần vẫn khởi động được mà key không nằm trong source.
WEB_CONFIGS = {
    "mobile": (
        (
            "web/firebase-config.js",
            "MOBILE_FIREBASE_WEB_API_KEY",
            "MOBILE_GOOGLE_SIGN_IN_WEB_CLIENT_ID",
        ),
    ),
    "admin_web": (("web/firebase-config.js", "ADMIN_WEB_FIREBASE_WEB_API_KEY"),),
}
# Biến tuỳ chọn: không bắt buộc có, dùng để ghi đè giá trị suy ra từ template.
OPTIONAL_CLIENT_KEYS = {
    "mobile": ("MOBILE_GOOGLE_SIGN_IN_WEB_CLIENT_ID",),
}
WEB_CONFIG_HEADER = """// Sinh bởi tools/flutter_env.py — file cục bộ, Git ignore.
// Chỉ chứa cấu hình client cho web; client key không phải secret.
"""


def render_web_config(api_key: str, client_id: str) -> str:
    """Sinh file JS cấu hình web, chỉ chứa client key và client id công khai."""

    lines = [WEB_CONFIG_HEADER.rstrip("\n")]
    lines.append(f"window.firebaseApiKey = {json.dumps(api_key)};")
    if client_id:
        lines.append(f"window.googleSignInClientId = {json.dumps(client_id)};")
    return "\n".join(lines) + "\n"


PLACEHOLDER = re.compile(r"\$\{([A-Z][A-Z0-9_]*)\}")


class ConfigError(Exception):
    """A configuration problem whose message is safe to print."""


def read_env(path: Path) -> dict[str, str]:
    """Read single-line dotenv values without evaluating or expanding them."""
    try:
        lines = path.read_text(encoding="utf-8-sig").splitlines()
    except (OSError, UnicodeError) as exc:
        raise ConfigError(
            "Cannot read the root .env; copy .env.example and fill it in."
        ) from exc
    values: dict[str, str] = {}
    for number, line in enumerate(lines, 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        match = re.fullmatch(r"(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)", line)
        if not match:
            raise ConfigError(f"Invalid .env assignment on line {number}.")
        name, value = match.groups()
        if value.startswith(("'", '"')):
            quoted = re.fullmatch(r"(['\"])(.*?)\1\s*(?:#.*)?", value)
            if not quoted:
                raise ConfigError(f"Invalid quoted .env value on line {number}.")
            value = quoted.group(2)
        else:
            value = re.split(r"\s+#", value, maxsplit=1)[0].rstrip()
        values[name] = value
    return values


def render_native(template: str, client_values: dict[str, str]) -> str:
    def replace(match: re.Match[str]) -> str:
        name = match.group(1)
        if name not in client_values:
            raise ConfigError(
                f"Native template requests a disallowed variable: {name}."
            )
        # Templates are JSON: escape values rather than interpolating raw text.
        return json.dumps(client_values[name])[1:-1]

    rendered = PLACEHOLDER.sub(replace, template)
    try:
        json.loads(rendered)
    except json.JSONDecodeError as exc:
        raise ConfigError("Invalid native Firebase JSON template.") from exc
    return rendered


def web_oauth_client_id(app_root: Path) -> str:
    """Lấy OAuth client id loại Web (client_type 3) từ template native.

    google_sign_in_web cần một OAuth client loại Web; client đó đã nằm trong
    template google-services.json nên không cần thêm biến môi trường.
    """

    template = app_root / "android/app/google-services.json.example"
    try:
        data = json.loads(template.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        return ""
    for client in data.get("client", []):
        for oauth in client.get("oauth_client", []):
            if oauth.get("client_type") == 3:
                return str(oauth.get("client_id", ""))
    return ""


def prepare(app: str, root: Path = REPO_ROOT) -> Path:
    env_path = root / ".env"
    values = read_env(env_path) if env_path.exists() else {}
    # Explicit allowlist: LLM keys, APP_TOKEN and every other server variable
    # stay out of the Flutter defines file, even when they share this .env.
    client_values = {
        name: os.environ.get(name, values.get(name, "")) for name in CLIENT_KEYS[app]
    }
    optional_values = {
        name: os.environ.get(name, values.get(name, ""))
        for name in OPTIONAL_CLIENT_KEYS.get(app, ())
    }
    missing = [name for name, value in client_values.items() if not value]
    if missing:
        raise ConfigError("Missing root .env variables: " + ", ".join(missing))

    app_root = root / app
    writes: list[tuple[Path, str]] = []
    for relative in NATIVE_CONFIGS[app]:
        output = app_root / relative
        template = Path(str(output) + ".example")
        try:
            contents = template.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as exc:
            raise ConfigError(f"Cannot read Firebase template for {app}.") from exc
        writes.append((output, render_native(contents, client_values)))

    for entry in WEB_CONFIGS.get(app, ()):
        relative, key_name = entry[0], entry[1]
        client_id_key = entry[2] if len(entry) > 2 else ""
        client_id = optional_values.get(client_id_key, "") if client_id_key else ""
        if not client_id:
            client_id = web_oauth_client_id(app_root)
        writes.append(
            (
                app_root / relative,
                render_web_config(client_values[key_name], client_id),
            )
        )

    defines = app_root / ".dart_tool" / "firebase-defines.json"
    writes.append((defines, json.dumps(client_values, indent=2) + "\n"))
    # Validate every input before replacing any generated file.
    for output, contents in writes:
        output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            newline="\n",
            dir=output.parent,
            prefix=output.name + ".",
            suffix=".tmp",
            delete=False,
        ) as handle:
            temporary = Path(handle.name)
            handle.write(contents)
        try:
            temporary.replace(output)
        finally:
            temporary.unlink(missing_ok=True)
    return defines


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", choices=CLIENT_KEYS)
    parser.add_argument("flutter_args", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not args.flutter_args:
        parser.error(
            "provide 'prepare', 'run', 'test', 'build', or another Flutter command"
        )
    try:
        defines = prepare(args.app)
    except ConfigError as exc:
        print(f"Configuration error: {exc}", file=sys.stderr)
        return 1
    print(
        f"Prepared Firebase client configuration for {args.app} (values hidden).",
        flush=True,
    )
    if args.flutter_args == ["prepare"]:
        return 0
    flutter = shutil.which("flutter.bat" if os.name == "nt" else "flutter")
    if not flutter:
        print("Flutter is not on PATH.", file=sys.stderr)
        return 1
    command = [flutter, *args.flutter_args]
    if args.flutter_args[0] in {"run", "test", "build", "drive"}:
        command.append(f"--dart-define-from-file={defines}")
    # Never invoke a shell or expand environment values into command text.
    return subprocess.run(command, cwd=REPO_ROOT / args.app, check=False).returncode


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    raise SystemExit(main())

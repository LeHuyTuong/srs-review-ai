"""Kiểm hợp đồng Firestore: danh mục collection, schema và fixture.

Bốn nhóm kiểm:
  (a) collection "implemented" có match tương ứng trong mobile/firestore.rules, và
      mọi match trong rules (trừ catch-all) đều có trong danh mục;
  (b) mọi hằng số collection khai trong hai file firestore_collections.dart và
      mọi literal .collection('x') / COLLECTION = "x" còn lại trong mobile/lib,
      admin_web/lib và server/app đều là collection đã biết;
  (c) mỗi file schema là JSON hợp lệ, có "x-contract-version" và
      "additionalProperties: false";
  (d) mỗi fixture chỉ dùng key có trong "properties" của schema tương ứng và
      đủ các key bắt buộc.

Chỉ dùng thư viện chuẩn; không cần dependency ngoài.
"""

from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCHEMA_DIR = REPO_ROOT / "contracts" / "firestore"
FIXTURE_DIR = REPO_ROOT / "contracts" / "fixtures" / "firestore"
CATALOGUE_PATH = SCHEMA_DIR / "collections.json"
RULES_PATH = REPO_ROOT / "mobile" / "firestore.rules"

# Cây source được rà; mọi tên collection Firestore nằm trong đây.
SOURCE_ROOTS = (
    REPO_ROOT / "mobile" / "lib",
    REPO_ROOT / "admin_web" / "lib",
    REPO_ROOT / "server" / "app",
)

COLLECTION_CALL = re.compile(r"\.collection\(\s*['\"]([A-Za-z0-9_]+)['\"]")
COLLECTION_CONSTANT = re.compile(
    r"\b[A-Z0-9_]*COLLECTION[A-Z0-9_]*\s*=\s*['\"]([A-Za-z0-9_]+)['\"]"
)
# Hằng số collection của app: static const String <tên> = '<collection>';
COLLECTION_CONSTANT_VALUE = re.compile(
    r"static\s+const\s+String\s+(\w+)\s*=\s*['\"]([A-Za-z0-9_]+)['\"]"
)
COLLECTION_CONSTANT_FILES = (
    REPO_ROOT / "mobile" / "lib" / "core" / "firestore" / "firestore_collections.dart",
    REPO_ROOT / "admin_web" / "lib" / "core" / "firestore" / "firestore_collections.dart",
)
RULES_MATCH = re.compile(r"^(\s*)match\s+/([^/]+(?:/[^/]+)*)\s*\{\s*$")


def normalize_path(path: str) -> str:
    """So hai path bằng cách gộp mọi phần trong ngoặc về một dạng."""

    return re.sub(r"\{[^}]*\}", "{}", path)


def load_catalogue() -> dict:
    with CATALOGUE_PATH.open(encoding="utf-8") as handle:
        return json.load(handle)


def catalogue_entries() -> list[dict]:
    return list(load_catalogue()["collections"])


def catalogue_paths() -> set[str]:
    return {normalize_path(entry["path"]) for entry in catalogue_entries()}


def catalogue_segments() -> set[str]:
    """Tên collection xuất hiện trong path (bỏ phần {placeholder})."""

    segments: set[str] = set()
    for entry in catalogue_entries():
        for part in entry["path"].split("/"):
            if part and not part.startswith("{"):
                segments.add(part)
    return segments


def rules_match_paths() -> set[str]:
    """Các path có match trong rules, bỏ catch-all và match cấp service."""

    text = RULES_PATH.read_text(encoding="utf-8")
    stack: list[tuple[int, str]] = []
    paths: set[str] = set()
    for line in text.splitlines():
        match = RULES_MATCH.match(line)
        if not match:
            continue
        indent, path = len(match.group(1)), match.group(2)
        if "{database}" in path or "{document=**}" in path:
            continue
        while stack and stack[-1][0] >= indent:
            stack.pop()
        full = "/".join(
            [part.strip() for _, part in stack] + [path.strip()]
        )
        paths.add(normalize_path(full))
        stack.append((indent, path))
    return paths


def declared_collection_constants() -> dict[str, str]:
    """Tên collection khai trong hai file hằng số: "<path>:<tên hằng>" -> "<collection>"."""

    declared: dict[str, str] = {}
    for path in COLLECTION_CONSTANT_FILES:
        text = path.read_text(encoding="utf-8")
        for match in COLLECTION_CONSTANT_VALUE.finditer(text):
            where = f"{path.relative_to(REPO_ROOT).as_posix()}:{match.group(1)}"
            declared[where] = match.group(2)
    return declared


def source_collection_literals() -> set[str]:
    """Tên collection được gọi trong code (client và server)."""

    literals: set[str] = set()
    for root in SOURCE_ROOTS:
        for path in sorted(root.rglob("*")):
            if path.suffix not in {".dart", ".py"} or not path.is_file():
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            literals.update(COLLECTION_CALL.findall(text))
            literals.update(COLLECTION_CONSTANT.findall(text))
    return literals


class FirestoreContractTests(unittest.TestCase):
    def setUp(self):
        self.catalogue = load_catalogue()
        self.entries = catalogue_entries()
        self.rules = rules_match_paths()

    def test_catalogue_has_the_expected_shape(self):
        self.assertIn("x-contract-version", self.catalogue)
        self.assertTrue(self.entries)
        for entry in self.entries:
            for key in (
                "path",
                "status",
                "writers",
                "readers",
                "schemaVersion",
                "schema",
                "notes",
            ):
                self.assertIn(key, entry, f"thiếu {key} trong {entry.get('path')}")
            self.assertIn(entry["status"], {"implemented", "planned"}, entry["path"])
            self.assertTrue(entry["path"].startswith("/") is False)
            self.assertIsInstance(entry["writers"], list)
            self.assertIsInstance(entry["readers"], list)

    def test_implemented_collections_have_a_rules_match(self):
        implemented = {
            normalize_path(entry["path"])
            for entry in self.entries
            if entry["status"] == "implemented"
        }
        self.assertTrue(implemented, "danh mục không có collection nào implemented")
        missing = sorted(implemented - self.rules)
        self.assertEqual(missing, [], f"collection implemented chưa có match trong rules: {missing}")

    def test_every_rules_match_is_catalogued(self):
        missing = sorted(self.rules - catalogue_paths())
        self.assertEqual(missing, [], f"match trong rules chưa có trong danh mục: {missing}")

    def test_declared_collection_constants_are_catalogued(self):
        declared = declared_collection_constants()
        self.assertTrue(declared, "không tìm thấy hằng số collection nào")
        known = catalogue_segments()
        unknown = sorted(
            f"{where} = {value}"
            for where, value in declared.items()
            if value not in known
        )
        self.assertEqual(
            unknown,
            [],
            "hằng số collection không có trong danh mục: " + ", ".join(unknown),
        )

    def test_source_collection_literals_are_catalogued(self):
        known = catalogue_segments()
        literals = source_collection_literals()
        # Luật "không pass rỗng": phải quét được ít nhất một tên collection.
        declared = declared_collection_constants()
        self.assertTrue(
            literals or declared,
            "không tìm thấy tên collection nào trong source",
        )
        unknown = sorted(literals - known)
        self.assertEqual(
            unknown,
            [],
            "literal collection trong code chưa có trong danh mục: " + ", ".join(unknown),
        )

    def test_schema_files_are_valid_and_closed(self):
        schema_files = sorted(SCHEMA_DIR.glob("*.schema.json"))
        self.assertTrue(schema_files, "chưa có file schema nào")
        for path in schema_files:
            with self.subTest(schema=path.name):
                with path.open(encoding="utf-8") as handle:
                    schema = json.load(handle)
                self.assertIn("x-contract-version", schema)
                self.assertIs(schema.get("additionalProperties"), False)
                self.assertEqual(schema.get("type"), "object")
                self.assertIsInstance(schema.get("properties"), dict)
                self.assertIsInstance(schema.get("required"), list)

    def test_fixtures_match_their_schema(self):
        schema_files = sorted(SCHEMA_DIR.glob("*.schema.json"))
        fixture_files = sorted(FIXTURE_DIR.glob("*.json"))
        self.assertTrue(fixture_files, "chưa có fixture nào")
        for path in schema_files:
            fixture = FIXTURE_DIR / (path.name[: -len(".schema.json")] + ".json")
            with self.subTest(schema=path.name):
                self.assertTrue(fixture.exists(), f"thiếu fixture cho {path.name}")
                with path.open(encoding="utf-8") as handle:
                    schema = json.load(handle)
                with fixture.open(encoding="utf-8") as handle:
                    document = json.load(handle)
                properties = schema["properties"]
                extra = sorted(set(document) - set(properties))
                self.assertEqual(extra, [], f"fixture {fixture.name} có key ngoài schema: {extra}")
                missing = sorted(set(schema["required"]) - set(document))
                self.assertEqual(
                    missing,
                    [],
                    f"fixture {fixture.name} thiếu field bắt buộc: {missing}",
                )

    def test_every_fixture_has_a_schema(self):
        for fixture in sorted(FIXTURE_DIR.glob("*.json")):
            schema = SCHEMA_DIR / (fixture.stem + ".schema.json")
            with self.subTest(fixture=fixture.name):
                self.assertTrue(schema.exists(), f"fixture {fixture.name} không có schema")


if __name__ == "__main__":
    unittest.main()

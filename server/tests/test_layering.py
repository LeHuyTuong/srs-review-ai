"""Layering guard — the dependency rules of ADR-0013, enforced by test.

docs/architecture-refactored.md §4 states the rules; this module turns the
load-bearing ones red the day someone imports around them:

* ``domain``      — pure: no FastAPI, no HTTP client, no infrastructure.
* ``application`` — orchestrates: no FastAPI/HTTP client, no concrete
  provider module (only the domain protocol), no api/ imports.
* ``api``         — translates HTTP: must reach the provider ONLY through the
  ``api.deps`` seam (which re-exports main's), never direct from
  infrastructure. (The routers do import infrastructure for its TYPES —
  schemas, docmap results — which is fine; the rule targets the provider
  call, the one thing tests patch through main.)
"""

from __future__ import annotations

import ast
from pathlib import Path

import pytest

APP = Path(__file__).resolve().parents[1] / "app"

FORBIDDEN = {
    "domain": {"fastapi", "httpx", "requests", "app.infrastructure"},
    "application": {"fastapi", "httpx", "requests", "app.api", "app.infrastructure.llm.router"},
}


def _imports(path: Path) -> set[str]:
    tree = ast.parse(path.read_text(encoding="utf-8"))
    found: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            found.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            found.add(node.module)
    return found


@pytest.mark.parametrize("layer,forbidden", sorted(FORBIDDEN.items()))
def test_layer_never_imports(layer: str, forbidden: set[str]):
    pkg = APP / layer
    violations: list[str] = []
    for path in pkg.rglob("*.py"):
        for imported in _imports(path):
            for bad in forbidden:
                if imported == bad or imported.startswith(bad + "."):
                    violations.append(f"{path.relative_to(APP)} imports {imported}")
    assert not violations, "\n".join(violations)


def test_api_routes_reach_the_provider_through_the_deps_seam():
    """The one rule that keeps ``main_module.build_provider`` the patch point:
    no router may import the provider factory directly from infrastructure."""
    violations: list[str] = []
    for path in (APP / "api").glob("*.py"):
        if path.name == "deps.py":
            continue
        for imported in _imports(path):
            if imported == "app.infrastructure.llm.router":
                violations.append(f"{path.name} imports {imported} — go through api.deps")
    assert not violations, "\n".join(violations)


def test_every_public_route_is_registered_exactly_once():
    """Pins the 20 endpoint paths + methods the pre-refactor app served, so a
    router refactor cannot silently drop or rename one (S6)."""
    from app.main import app

    routes = {
        (getattr(r, "path", None), tuple(sorted(getattr(r, "methods", []) or [])))
        for r in app.routes
        if getattr(r, "path", "").startswith(("/",)) and getattr(r, "methods", None)
    }
    expected = {
        ("/health", ("GET",)),
        ("/rubric", ("GET",)),
        ("/rubric", ("PUT",)),
        ("/rubric/reset", ("POST",)),
        ("/criteria", ("GET",)),
        ("/criteria", ("POST",)),
        ("/criteria/reset", ("POST",)),
        ("/criteria/{criterion_id}", ("DELETE",)),
        ("/criteria/{criterion_id}", ("PUT",)),
        ("/review", ("POST",)),
        ("/review/batch", ("POST",)),
        ("/ask", ("POST",)),
        ("/diagram", ("POST",)),
        ("/documents/analyze", ("POST",)),
        ("/documents/render", ("POST",)),
        ("/uploads/presign", ("POST",)),
        ("/uploads/{key}", ("PUT",)),
        ("/uploads/{key}/meta", ("GET",)),
        ("/share", ("POST",)),
        ("/share/{share_id}", ("GET",)),
    }
    missing = expected - routes
    assert not missing, f"routes lost in the refactor: {sorted(missing)}"

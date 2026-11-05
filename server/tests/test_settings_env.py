from app.config.settings import REPO_ROOT, SERVER_ROOT, Settings


def test_root_env_overrides_legacy_server_env_and_process_env_wins(tmp_path, monkeypatch):
    legacy = tmp_path / "server.env"
    root = tmp_path / "root.env"
    legacy.write_text("GEMINI_API_KEY='legacy-test-value'\nREQUEST_TIMEOUT_S=12\n", encoding="utf-8")
    root.write_text(
        "GEMINI_API_KEY='root-test-value'\nMOBILE_FIREBASE_WEB_API_KEY=client-test-value\n", encoding="utf-8"
    )
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    monkeypatch.delenv("REQUEST_TIMEOUT_S", raising=False)
    monkeypatch.setitem(Settings.model_config, "env_file", (legacy, root))
    settings = Settings()
    assert settings.gemini_api_key == "root-test-value"
    assert settings.request_timeout_s == 12
    monkeypatch.setenv("GEMINI_API_KEY", "deployment-test-value")
    assert Settings().gemini_api_key == "deployment-test-value"


def test_settings_find_repo_env_independently_of_working_directory(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    configured = Settings.model_config["env_file"]
    assert configured == (SERVER_ROOT / ".env", REPO_ROOT / ".env")
    assert all(path.is_absolute() for path in configured)

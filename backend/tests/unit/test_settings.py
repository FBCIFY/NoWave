import pytest

from app.config.settings import ConfigurationError, Settings, get_settings


def test_settings_read_current_environment(monkeypatch):
    monkeypatch.delenv("DATABASE_URL_FILE", raising=False)
    monkeypatch.delenv("DATABASE_URL", raising=False)
    assert get_settings().database_url is None
    url = "postgresql://localhost/test"
    monkeypatch.setenv("DATABASE_URL", url)
    assert get_settings().require_database_url() == url
    assert url not in repr(get_settings())


@pytest.mark.parametrize("url", [None, "", "   "])
def test_database_operations_require_configuration(url):
    with pytest.raises(ConfigurationError, match="DATABASE_URL must be set"):
        Settings(database_url=url).require_database_url()


def test_database_secret_file(monkeypatch, tmp_path):
    secret = tmp_path / "database_url"
    secret.write_text("postgresql://runtime:private@database/nowave\n")
    monkeypatch.delenv("DATABASE_URL", raising=False)
    monkeypatch.setenv("DATABASE_URL_FILE", str(secret))
    settings = get_settings()
    assert settings.require_database_url() == secret.read_text().strip()
    assert "private" not in repr(settings)
    monkeypatch.setenv("DATABASE_URL", "postgresql://other")
    with pytest.raises(ConfigurationError, match="not both"):
        get_settings()


def test_missing_secret_does_not_leak_path(monkeypatch):
    monkeypatch.delenv("DATABASE_URL", raising=False)
    monkeypatch.setenv("DATABASE_URL_FILE", "/private/secret/location")
    with pytest.raises(ConfigurationError, match="^DATABASE_URL_FILE cannot be read$"):
        get_settings()

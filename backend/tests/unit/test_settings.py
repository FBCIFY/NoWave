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


def test_photo_operations_require_bucket(monkeypatch):
    monkeypatch.delenv("PHOTO_STORAGE_BUCKET", raising=False)

    with pytest.raises(
        ConfigurationError,
        match="PHOTO_STORAGE_BUCKET must be set",
    ):
        get_settings().require_photo_storage_bucket()

    monkeypatch.setenv(
        "PHOTO_STORAGE_BUCKET",
        "  photos.test  ",
    )
    assert get_settings().require_photo_storage_bucket() == "photos.test"


def test_scaleway_secrets_can_be_loaded_from_files(monkeypatch, tmp_path):
    for name, value in (
        ("SCW_ACCESS_KEY", "private-access"),
        ("SCW_SECRET_KEY", "private-secret"),
    ):
        path = tmp_path / name
        path.write_text(value + "\n")
        monkeypatch.delenv(name, raising=False)
        monkeypatch.setenv(name + "_FILE", str(path))
    monkeypatch.setenv("PHOTO_STORAGE_BUCKET", "photos-test")
    monkeypatch.setenv("PHOTO_STORAGE_REGION", "fr-par")
    settings = get_settings()
    photo = settings.require_photo_storage()
    assert photo.endpoint_url == "https://s3.fr-par.scw.cloud"
    assert photo.secret_key == "private-secret"
    assert "private" not in repr(settings) + repr(photo)


@pytest.mark.parametrize(
    "change",
    [
        {"scaleway_access_key": None},
        {"scaleway_secret_key": None},
        {"photo_storage_region": "bad-region"},
    ],
)
def test_photo_settings_require_complete_scaleway_configuration(change):
    values = {
        "photo_storage_bucket": "photos-test",
        "scaleway_access_key": "access",
        "scaleway_secret_key": "secret",
    }
    with pytest.raises(ConfigurationError):
        Settings(**(values | change)).require_photo_storage()

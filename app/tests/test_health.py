from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.main import app


def test_health_returns_ok() -> None:
    with TestClient(app) as client:
        response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_ready_without_vault_credentials_returns_not_ready() -> None:
    with TestClient(app) as client:
        response = client.get("/ready")

    assert response.status_code == 503
    assert response.json() == {"status": "not_ready", "database": "disconnected"}


@patch("app.routes.health.ping", return_value=True)
@patch("app.main.VaultClient")
@patch("app.main.connect")
@patch("app.main.ping", return_value=True)
def test_ready_with_vault_credentials_returns_connected(
    mock_main_ping: MagicMock,
    mock_connect: MagicMock,
    mock_vault_client_cls: MagicMock,
    mock_health_ping: MagicMock,
) -> None:
    mock_vault = MagicMock()
    mock_vault.get_database_credentials.return_value = MagicMock(
        username="v-user",
        password="v-pass",
        lease_id="database/creds/app-role/abc",
    )
    mock_vault_client_cls.return_value = mock_vault
    mock_connect.return_value = MagicMock()

    with patch("app.main.settings") as mock_settings:
        mock_settings.vault_addr = "http://vault:8200"
        mock_settings.vault_role_id = "role-id"
        mock_settings.vault_secret_id = "secret-id"
        mock_settings.db_host = "postgres"
        mock_settings.db_port = 5432
        mock_settings.db_name = "appdb"
        mock_settings.app_name = "zero-trust-demo"

        with TestClient(app) as client:
            response = client.get("/ready")

    assert response.status_code == 200
    assert response.json() == {"status": "ready", "database": "connected"}
    mock_vault.revoke_lease.assert_called_once_with("database/creds/app-role/abc")

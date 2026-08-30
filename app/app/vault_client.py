"""HashiCorp Vault client: AppRole auth and dynamic database credentials."""

from dataclasses import dataclass

import hvac


class VaultError(Exception):
    """Raised when Vault authentication or secret retrieval fails."""


@dataclass(frozen=True)
class DatabaseCredentials:
    username: str
    password: str
    lease_id: str


class VaultClient:
    """Authenticate via AppRole and fetch short-lived database credentials."""

    def __init__(self, addr: str, role_id: str, secret_id: str) -> None:
        if not role_id or not secret_id:
            raise VaultError("VAULT_ROLE_ID and VAULT_SECRET_ID are required")

        self._client = hvac.Client(url=addr)

        try:
            login = self._client.auth.approle.login(
                role_id=role_id,
                secret_id=secret_id,
            )
        except hvac.exceptions.VaultError as exc:
            raise VaultError(f"AppRole login failed: {exc}") from exc

        self._client.token = login["auth"]["client_token"]

    def get_database_credentials(self, role: str = "app-role") -> DatabaseCredentials:
        try:
            response = self._client.read(f"database/creds/{role}")
        except hvac.exceptions.VaultError as exc:
            raise VaultError(f"Failed to read database credentials: {exc}") from exc

        if not response or "data" not in response:
            raise VaultError(f"No credentials returned for database role '{role}'")

        data = response["data"]
        return DatabaseCredentials(
            username=data["username"],
            password=data["password"],
            lease_id=response["lease_id"],
        )

    def revoke_lease(self, lease_id: str) -> None:
        if not lease_id:
            return

        try:
            self._client.sys.revoke_lease(lease_id)
        except hvac.exceptions.VaultError as exc:
            raise VaultError(f"Failed to revoke lease: {exc}") from exc

    # Async helpers: lightweight wrappers that run the blocking hvac calls in a thread.
    # Use these from async code instead of calling the blocking methods directly.
    async def async_get_database_credentials(self, role: str = "app-role") -> DatabaseCredentials:
        import asyncio

        return await asyncio.to_thread(self.get_database_credentials, role)

    async def async_revoke_lease(self, lease_id: str) -> None:
        import asyncio

        await asyncio.to_thread(self.revoke_lease, lease_id)

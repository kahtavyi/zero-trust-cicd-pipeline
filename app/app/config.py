from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application configuration loaded from environment variables."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = "zero-trust-demo"
    vault_addr: str = "http://vault:8200"

    # Used in Stage 2 when Vault dynamic secrets are wired into the app.
    vault_role_id: str = ""
    vault_secret_id: str = ""
    db_host: str = "postgres"
    db_port: int = 5432
    db_name: str = "appdb"


settings = Settings()

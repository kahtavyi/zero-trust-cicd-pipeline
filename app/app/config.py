from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application configuration loaded exclusively from environment variables."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = "ajax-telemetry-gateway"
    vault_addr: str = "http://vault:8200"

    vault_role_id: str = ""
    vault_secret_id: str = ""
    db_host: str = "postgres"
    db_port: int = 5432
    db_name: str = "appdb"
    enable_docs: bool = False


settings = Settings()

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file='.env', extra='ignore')

    service_name: str = 'auth-service'
    postgres_dsn: str = 'postgresql://whispre:whispre@postgres:5432/whispre'
    jwt_secret: str = 'change-me'
    jwt_algorithm: str = 'HS256'
    access_token_ttl_seconds: int = 900
    refresh_token_ttl_seconds: int = 2592000


settings = Settings()

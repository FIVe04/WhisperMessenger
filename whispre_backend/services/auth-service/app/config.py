from whispre_common.settings import DatabaseSettings


class Settings(DatabaseSettings):
    service_name: str = 'auth-service'
    access_token_ttl_seconds: int = 900
    refresh_token_ttl_seconds: int = 2592000


settings = Settings()

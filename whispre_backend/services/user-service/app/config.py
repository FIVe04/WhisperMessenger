from whispre_common.settings import DatabaseSettings


class Settings(DatabaseSettings):
    service_name: str = 'user-service'


settings = Settings()

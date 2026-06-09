from whispre_common.settings import DatabaseSettings


class Settings(DatabaseSettings):
    service_name: str = 'conversation-service'


settings = Settings()

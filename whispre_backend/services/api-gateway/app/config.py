from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file='.env', extra='ignore')

    service_name: str = 'api-gateway'
    auth_service_url: str = 'http://auth-service:8000'
    user_service_url: str = 'http://user-service:8000'
    key_service_url: str = 'http://key-service:8000'
    conversation_service_url: str = 'http://conversation-service:8000'
    message_service_url: str = 'http://message-service:8000'
    realtime_service_url: str = 'http://realtime-service:8000'
    notification_service_url: str = 'http://notification-service:8000'

    jwt_secret: str = 'change-me'
    jwt_algorithm: str = 'HS256'

    rate_limit_requests_per_minute: int = 240


settings = Settings()

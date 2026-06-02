from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file='.env', extra='ignore')

    service_name: str = 'notification-service'
    postgres_dsn: str = 'postgresql://whispre:whispre@postgres:5432/whispre'
    jwt_secret: str = 'change-me'
    jwt_algorithm: str = 'HS256'

    kafka_broker: str = 'kafka:9092'
    kafka_topic_envelope_accepted: str = 'message.envelope.accepted.v1'
    kafka_consumer_group: str = 'notification-service-v1'

    queue_max_per_device: int = 500


settings = Settings()

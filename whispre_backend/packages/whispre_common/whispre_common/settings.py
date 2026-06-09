from pydantic_settings import BaseSettings, SettingsConfigDict


class ServiceSettings(BaseSettings):
    model_config = SettingsConfigDict(env_file='.env', extra='ignore')

    service_name: str
    jwt_secret: str = 'change-me'
    jwt_algorithm: str = 'HS256'


class DatabaseSettings(ServiceSettings):
    postgres_dsn: str = 'postgresql://whispre:whispre@postgres:5432/whispre'


class KafkaDatabaseSettings(DatabaseSettings):
    kafka_broker: str = 'kafka:9092'

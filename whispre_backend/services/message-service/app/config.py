from whispre_common.settings import KafkaDatabaseSettings


class Settings(KafkaDatabaseSettings):
    service_name: str = 'message-service'
    kafka_topic_envelope_accepted: str = 'message.envelope.accepted.v1'


settings = Settings()

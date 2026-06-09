from whispre_common.settings import KafkaDatabaseSettings


class Settings(KafkaDatabaseSettings):
    service_name: str = 'realtime-service'
    kafka_topic_envelope_accepted: str = 'message.envelope.accepted.v1'
    kafka_consumer_group: str = 'realtime-service-v1'


settings = Settings()

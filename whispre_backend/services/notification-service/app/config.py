from whispre_common.settings import KafkaDatabaseSettings


class Settings(KafkaDatabaseSettings):
    service_name: str = 'notification-service'
    kafka_topic_envelope_accepted: str = 'message.envelope.accepted.v1'
    kafka_consumer_group: str = 'notification-service-v1'

    queue_max_per_device: int = 500


settings = Settings()

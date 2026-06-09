import asyncio
import json
import logging

from aiokafka import AIOKafkaProducer
from whispre_common.logging import log_event
from whispre_common.observability import record_kafka_event

from .config import settings

logger = logging.getLogger(settings.service_name)


class EnvelopeEventProducer:
    def __init__(self) -> None:
        self._producer: AIOKafkaProducer | None = None

    async def start(self) -> None:
        producer = AIOKafkaProducer(
            bootstrap_servers=settings.kafka_broker,
            value_serializer=lambda value: json.dumps(value).encode('utf-8'),
        )
        while True:
            try:
                await producer.start()
                log_event(
                    logger,
                    logging.INFO,
                    'kafka_producer_started',
                    broker=settings.kafka_broker,
                    topic=settings.kafka_topic_envelope_accepted,
                )
                self._producer = producer
                return
            except asyncio.CancelledError:
                raise
            except Exception:
                log_event(
                    logger,
                    logging.WARNING,
                    'kafka_producer_start_failed',
                    retry_in_seconds=2,
                    exc_info=True,
                )
                await asyncio.sleep(2)

    async def stop(self) -> None:
        if self._producer is not None:
            await self._producer.stop()
            self._producer = None
            log_event(logger, logging.INFO, 'kafka_producer_stopped')

    async def publish(self, events: list[dict]) -> None:
        if self._producer is None:
            raise RuntimeError('Kafka producer is not started')
        for event in events:
            event_name = str(event.get('event', 'unknown'))
            try:
                await self._producer.send_and_wait(settings.kafka_topic_envelope_accepted, event)
                record_kafka_event(settings.service_name, 'produced', event_name, 'success')
                log_event(
                    logger,
                    logging.INFO,
                    'kafka_event_published',
                    kafka_event=event_name,
                    topic=settings.kafka_topic_envelope_accepted,
                    envelope_id=event.get('envelope_id'),
                    recipient_device_id=event.get('recipient_device_id'),
                )
            except Exception:
                record_kafka_event(settings.service_name, 'produced', event_name, 'error')
                log_event(
                    logger,
                    logging.ERROR,
                    'kafka_event_publish_failed',
                    kafka_event=event_name,
                    topic=settings.kafka_topic_envelope_accepted,
                    envelope_id=event.get('envelope_id'),
                    exc_info=True,
                )
                raise


envelope_event_producer = EnvelopeEventProducer()

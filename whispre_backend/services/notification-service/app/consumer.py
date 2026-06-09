import asyncio
import contextlib
import json
import logging
import uuid
from datetime import UTC, datetime

from aiokafka import AIOKafkaConsumer
from whispre_common.logging import log_event
from whispre_common.observability import record_kafka_event

from .config import settings
from .queue import notification_queue

logger = logging.getLogger(settings.service_name)


async def consume_events() -> None:
    while True:
        consumer = AIOKafkaConsumer(
            settings.kafka_topic_envelope_accepted,
            bootstrap_servers=settings.kafka_broker,
            group_id=settings.kafka_consumer_group,
            enable_auto_commit=True,
            auto_offset_reset='latest',
        )
        try:
            await consumer.start()
            log_event(
                logger,
                logging.INFO,
                'kafka_consumer_started',
                broker=settings.kafka_broker,
                topic=settings.kafka_topic_envelope_accepted,
                consumer_group=settings.kafka_consumer_group,
            )
            async for message in consumer:
                try:
                    payload = json.loads(message.value.decode('utf-8'))
                except (UnicodeDecodeError, json.JSONDecodeError):
                    log_event(
                        logger,
                        logging.WARNING,
                        'kafka_event_rejected',
                        reason='malformed_payload',
                        partition=message.partition,
                        offset=message.offset,
                    )
                    record_kafka_event(settings.service_name, 'consumed', 'unknown', 'invalid')
                    continue

                recipient_device_id = payload.get('recipient_device_id')
                if not recipient_device_id:
                    log_event(
                        logger,
                        logging.WARNING,
                        'kafka_event_rejected',
                        reason='missing_recipient_device_id',
                        partition=message.partition,
                        offset=message.offset,
                    )
                    continue

                notification = {
                    'notification_id': str(uuid.uuid4()),
                    'type': 'new_envelope',
                    'envelope_id': payload.get('envelope_id', ''),
                    'conversation_id': payload.get('conversation_id', ''),
                    'sender_user_id': payload.get('sender_user_id', ''),
                    'recipient_device_id': recipient_device_id,
                    'created_at': datetime.now(UTC),
                }
                await notification_queue.push(recipient_device_id, notification)
                record_kafka_event(
                    settings.service_name,
                    'consumed',
                    str(payload.get('event', 'message.envelope.accepted.v1')),
                    'success',
                )
                log_event(
                    logger,
                    logging.INFO,
                    'notification_queued',
                    kafka_event=str(payload.get('event', 'message.envelope.accepted.v1')),
                    notification_id=notification['notification_id'],
                    envelope_id=notification['envelope_id'],
                    recipient_device_id=recipient_device_id,
                )
        except asyncio.CancelledError:
            raise
        except Exception:
            log_event(
                logger,
                logging.WARNING,
                'kafka_consumer_failed',
                retry_in_seconds=2,
                exc_info=True,
            )
            await asyncio.sleep(2)
        finally:
            with contextlib.suppress(Exception):
                await consumer.stop()

import os
import time

from alembic import command
from alembic.config import Config
from sqlalchemy import inspect
from sqlalchemy.exc import OperationalError
from whispre_common.database import create_db_engine

EXPECTED_COLUMNS = {
    'users': {'id', 'username', 'email', 'password_hash', 'created_at', 'deleted_at'},
    'devices': {'id', 'user_id', 'name', 'platform', 'is_active', 'last_seen_at', 'created_at'},
    'refresh_tokens': {
        'id',
        'user_id',
        'device_id',
        'token_hash',
        'expires_at',
        'revoked_at',
        'created_at',
    },
    'device_key_bundles': {
        'device_id',
        'identity_key_pub',
        'identity_signing_key_pub',
        'signed_prekey_id',
        'signed_prekey_pub',
        'signed_prekey_signature',
        'updated_at',
    },
    'one_time_prekeys': {
        'id',
        'device_id',
        'prekey_id',
        'prekey_pub',
        'is_claimed',
        'claimed_at',
        'created_at',
    },
    'conversations': {'id', 'type', 'created_by', 'created_at'},
    'conversation_participants': {'conversation_id', 'user_id', 'role', 'joined_at'},
    'direct_conversation_pairs': {'user_low', 'user_high', 'conversation_id'},
    'envelopes': {
        'id',
        'conversation_id',
        'sender_user_id',
        'sender_device_id',
        'recipient_user_id',
        'recipient_device_id',
        'ciphertext',
        'header_json',
        'sent_at_client',
        'accepted_at_server',
        'delivered_at',
        'acked_at',
    },
    'message_send_requests': {
        'id',
        'sender_user_id',
        'sender_device_id',
        'idempotency_key',
        'created_at',
    },
}


def wait_for_database(postgres_dsn: str, attempts: int = 30) -> None:
    engine = create_db_engine(postgres_dsn)
    for attempt in range(1, attempts + 1):
        try:
            with engine.connect():
                return
        except OperationalError:
            if attempt == attempts:
                raise
            time.sleep(1)


def validate_legacy_schema(inspector) -> None:
    tables = set(inspector.get_table_names())
    domain_tables = set(EXPECTED_COLUMNS)
    present_tables = domain_tables.intersection(tables)

    if not present_tables:
        return
    if present_tables != domain_tables:
        missing = ', '.join(sorted(domain_tables - present_tables))
        raise RuntimeError(f'Legacy database schema is incomplete; missing tables: {missing}')

    for table_name, expected_columns in EXPECTED_COLUMNS.items():
        actual_columns = {column['name'] for column in inspector.get_columns(table_name)}
        missing_columns = expected_columns - actual_columns
        if missing_columns:
            missing = ', '.join(sorted(missing_columns))
            raise RuntimeError(f'Legacy table {table_name} is missing columns: {missing}')


def main() -> None:
    postgres_dsn = os.environ.get('POSTGRES_DSN')
    if not postgres_dsn:
        raise RuntimeError('POSTGRES_DSN is required')

    wait_for_database(postgres_dsn)
    config = Config('/app/alembic.ini')
    engine = create_db_engine(postgres_dsn)

    with engine.connect() as connection:
        inspector = inspect(connection)
        tables = set(inspector.get_table_names())
        has_version_table = 'alembic_version' in tables
        has_domain_tables = bool(set(EXPECTED_COLUMNS).intersection(tables))

        if not has_version_table and has_domain_tables:
            validate_legacy_schema(inspector)
            print('Existing Whispre schema detected; stamping Alembic baseline.')
            command.stamp(config, 'head')

    command.upgrade(config, 'head')
    print('Database is at Alembic head.')


if __name__ == '__main__':
    main()

"""Create the initial Whispre schema.

Revision ID: 0001_initial_schema
Revises:
Create Date: 2026-06-10
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = '0001_initial_schema'
down_revision: str | Sequence[str] | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        'users',
        sa.Column('id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('username', sa.Text(), nullable=False),
        sa.Column('email', sa.Text(), nullable=False),
        sa.Column('password_hash', sa.Text(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('email', name='users_email_key'),
        sa.UniqueConstraint('username', name='users_username_key'),
    )

    op.create_table(
        'devices',
        sa.Column('id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('name', sa.Text(), nullable=False),
        sa.Column('platform', sa.Text(), nullable=False),
        sa.Column('is_active', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('last_seen_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('idx_devices_user_name', 'devices', ['user_id', 'name'])

    op.create_table(
        'refresh_tokens',
        sa.Column('id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('device_id', postgresql.UUID(as_uuid=False), nullable=True),
        sa.Column('token_hash', sa.Text(), nullable=False),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('revoked_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(['device_id'], ['devices.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('idx_refresh_tokens_user_device', 'refresh_tokens', ['user_id', 'device_id'])

    op.create_table(
        'device_key_bundles',
        sa.Column('device_id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('identity_key_pub', sa.Text(), nullable=False),
        sa.Column('identity_signing_key_pub', sa.Text(), server_default='', nullable=False),
        sa.Column('signed_prekey_id', sa.BigInteger(), nullable=False),
        sa.Column('signed_prekey_pub', sa.Text(), nullable=False),
        sa.Column('signed_prekey_signature', sa.Text(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(['device_id'], ['devices.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('device_id'),
    )

    op.create_table(
        'one_time_prekeys',
        sa.Column('id', sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column('device_id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('prekey_id', sa.BigInteger(), nullable=False),
        sa.Column('prekey_pub', sa.Text(), nullable=False),
        sa.Column('is_claimed', sa.Boolean(), server_default=sa.text('false'), nullable=False),
        sa.Column('claimed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(['device_id'], ['devices.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint(
            'device_id',
            'prekey_id',
            name='one_time_prekeys_device_id_prekey_id_key',
        ),
    )
    op.create_index('idx_one_time_prekeys_claim', 'one_time_prekeys', ['device_id', 'is_claimed'])

    op.create_table(
        'conversations',
        sa.Column('id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('type', sa.Text(), nullable=False),
        sa.Column('created_by', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("type in ('direct','group')", name='conversations_type_check'),
        sa.ForeignKeyConstraint(['created_by'], ['users.id']),
        sa.PrimaryKeyConstraint('id'),
    )

    op.create_table(
        'conversation_participants',
        sa.Column('conversation_id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('role', sa.Text(), server_default='member', nullable=False),
        sa.Column('joined_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(['conversation_id'], ['conversations.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('conversation_id', 'user_id'),
    )

    op.create_table(
        'direct_conversation_pairs',
        sa.Column('user_low', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('user_high', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('conversation_id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.CheckConstraint('user_low <> user_high', name='direct_conversation_pairs_check'),
        sa.ForeignKeyConstraint(['conversation_id'], ['conversations.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['user_high'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['user_low'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('user_low', 'user_high'),
        sa.UniqueConstraint(
            'conversation_id',
            name='direct_conversation_pairs_conversation_id_key',
        ),
    )

    op.create_table(
        'envelopes',
        sa.Column('id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('conversation_id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('sender_user_id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('sender_device_id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('recipient_user_id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('recipient_device_id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('ciphertext', sa.Text(), nullable=False),
        sa.Column('header_json', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column('sent_at_client', sa.DateTime(timezone=True), nullable=False),
        sa.Column('accepted_at_server', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('delivered_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('acked_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['conversation_id'], ['conversations.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['recipient_device_id'], ['devices.id']),
        sa.ForeignKeyConstraint(['recipient_user_id'], ['users.id']),
        sa.ForeignKeyConstraint(['sender_device_id'], ['devices.id']),
        sa.ForeignKeyConstraint(['sender_user_id'], ['users.id']),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(
        'idx_envelopes_pending',
        'envelopes',
        ['recipient_device_id', 'acked_at', 'accepted_at_server'],
    )
    op.create_index(
        'idx_envelopes_conversation',
        'envelopes',
        ['conversation_id', 'accepted_at_server'],
    )

    op.create_table(
        'message_send_requests',
        sa.Column('id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('sender_user_id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('sender_device_id', postgresql.UUID(as_uuid=False), nullable=False),
        sa.Column('idempotency_key', sa.Text(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(['sender_device_id'], ['devices.id']),
        sa.ForeignKeyConstraint(['sender_user_id'], ['users.id']),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint(
            'sender_device_id',
            'idempotency_key',
            name='message_send_requests_sender_device_id_idempotency_key_key',
        ),
    )


def downgrade() -> None:
    op.drop_table('message_send_requests')
    op.drop_index('idx_envelopes_conversation', table_name='envelopes')
    op.drop_index('idx_envelopes_pending', table_name='envelopes')
    op.drop_table('envelopes')
    op.drop_table('direct_conversation_pairs')
    op.drop_table('conversation_participants')
    op.drop_table('conversations')
    op.drop_index('idx_one_time_prekeys_claim', table_name='one_time_prekeys')
    op.drop_table('one_time_prekeys')
    op.drop_table('device_key_bundles')
    op.drop_index('idx_refresh_tokens_user_device', table_name='refresh_tokens')
    op.drop_table('refresh_tokens')
    op.drop_index('idx_devices_user_name', table_name='devices')
    op.drop_table('devices')
    op.drop_table('users')

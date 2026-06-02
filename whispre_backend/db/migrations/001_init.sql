create table if not exists users (
  id uuid primary key,
  username text not null unique,
  email text not null unique,
  password_hash text not null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists devices (
  id uuid primary key,
  user_id uuid not null references users(id) on delete cascade,
  name text not null,
  platform text not null,
  is_active boolean not null default true,
  last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, name)
);

create table if not exists refresh_tokens (
  id uuid primary key,
  user_id uuid not null references users(id) on delete cascade,
  device_id uuid references devices(id) on delete cascade,
  token_hash text not null,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_refresh_tokens_user_device on refresh_tokens(user_id, device_id);

create table if not exists device_key_bundles (
  device_id uuid primary key references devices(id) on delete cascade,
  identity_key_pub text not null,
  signed_prekey_id bigint not null,
  signed_prekey_pub text not null,
  signed_prekey_signature text not null,
  updated_at timestamptz not null default now()
);

create table if not exists one_time_prekeys (
  id bigserial primary key,
  device_id uuid not null references devices(id) on delete cascade,
  prekey_id bigint not null,
  prekey_pub text not null,
  is_claimed boolean not null default false,
  claimed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(device_id, prekey_id)
);

create index if not exists idx_one_time_prekeys_claim on one_time_prekeys(device_id, is_claimed);

create table if not exists conversations (
  id uuid primary key,
  type text not null check (type in ('direct','group')),
  created_by uuid not null references users(id),
  created_at timestamptz not null default now()
);

create table if not exists conversation_participants (
  conversation_id uuid not null references conversations(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  role text not null default 'member',
  joined_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create table if not exists direct_conversation_pairs (
  user_low uuid not null references users(id) on delete cascade,
  user_high uuid not null references users(id) on delete cascade,
  conversation_id uuid not null unique references conversations(id) on delete cascade,
  primary key (user_low, user_high),
  check (user_low <> user_high)
);

create table if not exists envelopes (
  id uuid primary key,
  conversation_id uuid not null references conversations(id) on delete cascade,
  sender_user_id uuid not null references users(id),
  sender_device_id uuid not null references devices(id),
  recipient_user_id uuid not null references users(id),
  recipient_device_id uuid not null references devices(id),
  ciphertext text not null,
  header_json jsonb not null,
  sent_at_client timestamptz not null,
  accepted_at_server timestamptz not null default now(),
  delivered_at timestamptz,
  acked_at timestamptz
);

create index if not exists idx_envelopes_pending on envelopes(recipient_device_id, acked_at, accepted_at_server);
create index if not exists idx_envelopes_conversation on envelopes(conversation_id, accepted_at_server);

create table if not exists message_send_requests (
  id uuid primary key,
  sender_user_id uuid not null references users(id),
  sender_device_id uuid not null references devices(id),
  idempotency_key text not null,
  created_at timestamptz not null default now(),
  unique(sender_device_id, idempotency_key)
);

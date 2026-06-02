alter table if exists devices
  drop constraint if exists devices_user_id_name_key;

create index if not exists idx_devices_user_name on devices(user_id, name);

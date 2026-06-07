alter table if exists device_key_bundles
  add column if not exists identity_signing_key_pub text not null default '';

-- +goose Up
ALTER TABLE auth_identities DROP CONSTRAINT auth_identities_provider_check;
ALTER TABLE auth_identities ADD CONSTRAINT auth_identities_provider_check
  CHECK(provider IN ('apple','phone','email','wechat','google'));

-- +goose Down
-- Refuse to roll back once Google identities exist rather than orphan their accounts.
ALTER TABLE auth_identities DROP CONSTRAINT auth_identities_provider_check;
ALTER TABLE auth_identities ADD CONSTRAINT auth_identities_provider_check
  CHECK(provider IN ('apple','phone','email','wechat'));

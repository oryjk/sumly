-- +goose Up
-- 微信身份以 appid + openid 编码为 subject，禁止跨 appid 误绑定。
-- 旧版本 /auth/wechat/login 以裸 openid 作 subject；仅当 legacy appid
-- 与当前 appid 明确一致时才允许迁移，避免猜测归属造成错误关联。
ALTER TABLE auth_identities DROP CONSTRAINT auth_identities_provider_check;
ALTER TABLE auth_identities ADD CONSTRAINT auth_identities_provider_check
  CHECK(provider IN ('apple','phone','email','wechat'));

-- 旧微信用户可能已关联手机号或邮箱账户；记录迁移来源便于排查，
-- 不改变原用户 ID，也不复制持仓。
ALTER TABLE auth_identities ADD COLUMN IF NOT EXISTS migrated_from TEXT NOT NULL DEFAULT '';

-- +goose Down
ALTER TABLE auth_identities DROP COLUMN IF EXISTS migrated_from;
ALTER TABLE auth_identities DROP CONSTRAINT auth_identities_provider_check;
ALTER TABLE auth_identities ADD CONSTRAINT auth_identities_provider_check
  CHECK(provider IN ('apple','phone','email'));

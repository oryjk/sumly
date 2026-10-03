-- +goose Up
-- 持仓提醒的微信订阅消息送达状态。
-- 设备基线与幂等事件单独存表，与配置云文档分离：配置随账户同步，
-- 基线是设备状态，不应跨设备。
CREATE TABLE notification_device_baselines (
  device_id UUID NOT NULL,
  workspace TEXT NOT NULL,
  config_hash TEXT NOT NULL,
  previous_price DOUBLE PRECISION NOT NULL,
  previous_as_of TIMESTAMPTZ NOT NULL,
  armed BOOLEAN NOT NULL DEFAULT false,
  last_triggered_at TIMESTAMPTZ,
  PRIMARY KEY(device_id, workspace, config_hash)
);
CREATE INDEX notification_baselines_expiry ON notification_device_baselines(previous_as_of);

-- 发送事件：同一 request_id 只产生一条，重复请求据此幂等。
-- status 取 delivered/failed/unknown；unknown 保留以便按ID 查询，
-- 不盲目重发。
CREATE TABLE notification_events (
  id UUID PRIMARY KEY,
  device_id UUID NOT NULL,
  workspace TEXT NOT NULL,
  request_id TEXT NOT NULL,
  alert_id TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('delivered','failed','unknown','skipped')),
  detail TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  UNIQUE(device_id, request_id, alert_id)
);
CREATE INDEX notification_events_expiry ON notification_events(expires_at);
CREATE INDEX notification_events_device ON notification_events(device_id);

-- 授予的短期令牌：只存 hash，不存明文。15 分钟到期。
CREATE TABLE notification_grants (
  hash TEXT PRIMARY KEY,
  device_id UUID NOT NULL,
  workspace TEXT NOT NULL,
  user_id BIGINT REFERENCES users(id) ON DELETE CASCADE,
  template_id TEXT NOT NULL,
  openid TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX notification_grants_expiry ON notification_grants(expires_at);

-- +goose Down
DROP TABLE notification_grants, notification_events, notification_device_baselines;

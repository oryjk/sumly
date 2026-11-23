import type {
  ApiEnvelope,
  AppConfigItem,
  AuditLogItem,
  AuthLoginPayload,
  AuthLoginResult,
  AuthLogoutResult,
  AuthVerifyResult,
  ChangePasswordPayload,
  ChangePasswordResult,
  UpdateConfigPayload,
} from '../types/config';
import { isRecord } from '../types/config';
import {
  EMPTY_FEEDBACK_COUNTS,
  type AdminFeedbackCounts,
  type AdminFeedbackItem,
  type AdminFeedbackListResponse,
  type AdminFeedbackQuery,
  type FeedbackAttachment,
  type FeedbackCategory,
  type FeedbackStatus,
  type UpdateAdminFeedbackPayload,
} from '../types/feedback';
import { normalizeApiBase } from '../utils/storage';

const REQUEST_TIMEOUT_MS = 12_000;
export const MUST_CHANGE_PASSWORD_ERROR_CODE = 40301;

export class AdminApiError extends Error {
  readonly status: number;
  readonly code?: number;
  readonly isUnauthorized: boolean;
  readonly isForbidden: boolean;
  readonly isMustChangePassword: boolean;
  readonly isUnprocessableEntity: boolean;
  readonly isServiceUnavailable: boolean;

  constructor(
    message: string,
    options: {
      status: number;
      code?: number;
    },
  ) {
    super(message);
    this.name = 'AdminApiError';
    this.status = options.status;
    this.code = options.code;
    this.isUnauthorized = options.status === 401;
    this.isForbidden = options.status === 403;
    this.isMustChangePassword =
      options.status === 403 && options.code === MUST_CHANGE_PASSWORD_ERROR_CODE;
    this.isUnprocessableEntity = options.status === 422;
    this.isServiceUnavailable = options.status === 503;
  }
}

async function adminRequest<T>(
  apiBase: string,
  token: string | null,
  path: string,
  init: RequestInit = {},
): Promise<T> {
  const base = normalizeApiBase(apiBase);
  const url = `${base}${path}`;
  const controller = new AbortController();
  const timeoutId = window.setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  const headers = new Headers(init.headers);
  if (token && token.trim()) {
    headers.set('Authorization', `Bearer ${token.trim()}`);
  }
  headers.set('Accept', 'application/json');
  if (init.body && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }

  try {
    const response = await fetch(url, {
      ...init,
      headers,
      cache: 'no-store',
      signal: controller.signal,
    });

    const contentType = response.headers.get('content-type') ?? '';
    let parsed: unknown = null;

    if (contentType.includes('application/json')) {
      try {
        parsed = await response.json();
      } catch {
        parsed = null;
      }
    } else {
      const text = await response.text().catch(() => '');
      try {
        parsed = text ? JSON.parse(text) : null;
      } catch {
        parsed = text;
      }
    }

    const envelope = isRecord(parsed) ? (parsed as unknown as ApiEnvelope<T>) : null;
    const serverCode = typeof envelope?.code === 'number' ? envelope.code : undefined;
    const serverMessage =
      (typeof envelope?.message === 'string' && envelope.message.trim()) ||
      (typeof envelope?.error === 'string' && envelope.error.trim()) ||
      '';

    if (!response.ok) {
      let friendly = serverMessage;
      if (response.status === 401) {
        friendly =
          serverMessage ||
          (token
            ? '登录会话无效或已过期，请重新登录'
            : '管理员账号或密码错误，请核对后重试');
      } else if (response.status === 403 && serverCode === MUST_CHANGE_PASSWORD_ERROR_CODE) {
        friendly = serverMessage || '请先修改初始密码后再变更配置';
      } else if (response.status === 422) {
        friendly = serverMessage || '输入内容不符合校验要求，请检查后重试';
      } else if (response.status === 503) {
        friendly = serverMessage || '服务端管理员认证暂不可用，请检查服务端配置（503）';
      } else if (!friendly) {
        friendly = `请求失败（HTTP ${response.status}）`;
      }
      throw new AdminApiError(friendly, {
        status: response.status,
        code: serverCode,
      });
    }

    if (envelope && typeof envelope.code === 'number') {
      if (envelope.code !== 0) {
        throw new AdminApiError(
          serverMessage || `服务返回业务异常（code=${envelope.code}）`,
          {
            status: response.status,
            code: envelope.code,
          },
        );
      }
      return envelope.data as T;
    }

    throw new AdminApiError('服务端响应格式异常，请确认 API 地址是否正确', {
      status: response.status,
    });
  } catch (error) {
    if (error instanceof AdminApiError) {
      throw error;
    }
    if (error instanceof DOMException && error.name === 'AbortError') {
      throw new AdminApiError('请求超时，请检查后端服务是否正常运行', { status: 0 });
    }
    throw new AdminApiError('无法连接后端接口，请检查网络、代理或 API 地址', { status: 0 });
  } finally {
    window.clearTimeout(timeoutId);
  }
}

export async function loginAdmin(
  apiBase: string,
  payload: AuthLoginPayload,
): Promise<AuthLoginResult> {
  const data = await adminRequest<AuthLoginResult>(apiBase, null, '/admin/auth/login', {
    method: 'POST',
    body: JSON.stringify({
      username: payload.username.trim(),
      password: payload.password,
    }),
  });
  if (!data || typeof data.token !== 'string' || !data.token.trim()) {
    throw new AdminApiError('登录响应缺少会话令牌，请联系服务端排查', { status: 500 });
  }
  return {
    token: data.token.trim(),
    username:
      typeof data.username === 'string' && data.username.trim()
        ? data.username.trim()
        : payload.username.trim() || 'admin',
    must_change_password: Boolean(data.must_change_password),
    expires_at: typeof data.expires_at === 'string' ? data.expires_at : undefined,
  };
}

export async function verifyAdminSession(
  apiBase: string,
  token: string,
): Promise<AuthVerifyResult> {
  const data = await adminRequest<AuthVerifyResult>(apiBase, token, '/admin/auth/verify', {
    method: 'GET',
  });
  if (!data || data.valid !== true) {
    throw new AdminApiError('登录会话校验未通过，请重新登录', { status: 401 });
  }
  return {
    valid: true,
    username:
      typeof data.username === 'string' && data.username.trim() ? data.username.trim() : 'admin',
    must_change_password: Boolean(data.must_change_password),
  };
}

export async function changeAdminPassword(
  apiBase: string,
  token: string,
  payload: ChangePasswordPayload,
): Promise<ChangePasswordResult> {
  const data = await adminRequest<ChangePasswordResult>(
    apiBase,
    token,
    '/admin/auth/change-password',
    {
      method: 'POST',
      body: JSON.stringify({
        current_password: payload.current_password,
        new_password: payload.new_password,
      }),
    },
  );
  return {
    username:
      typeof data?.username === 'string' && data.username.trim() ? data.username.trim() : '',
    must_change_password: Boolean(data?.must_change_password),
  };
}

export async function logoutAdmin(apiBase: string, token: string): Promise<AuthLogoutResult> {
  const data = await adminRequest<AuthLogoutResult>(apiBase, token, '/admin/auth/logout', {
    method: 'POST',
  });
  return {
    logged_out: Boolean(data?.logged_out ?? true),
  };
}

export async function fetchConfigs(apiBase: string, token: string): Promise<AppConfigItem[]> {
  const data = await adminRequest<AppConfigItem[] | { items?: AppConfigItem[] }>(
    apiBase,
    token,
    '/admin/configs',
    { method: 'GET' },
  );
  if (Array.isArray(data)) {
    return data;
  }
  if (isRecord(data) && Array.isArray(data.items)) {
    return data.items;
  }
  return [];
}

export async function updateConfig(
  apiBase: string,
  token: string,
  key: string,
  payload: UpdateConfigPayload,
): Promise<AppConfigItem> {
  return adminRequest<AppConfigItem>(
    apiBase,
    token,
    `/admin/configs/${encodeURIComponent(key)}`,
    {
      method: 'PUT',
      body: JSON.stringify(payload),
    },
  );
}

export async function fetchAuditLogs(
  apiBase: string,
  token: string,
  limit = 30,
): Promise<AuditLogItem[]> {
  const safeLimit = Math.min(100, Math.max(1, Math.floor(limit)));
  const data = await adminRequest<AuditLogItem[] | { items?: AuditLogItem[] }>(
    apiBase,
    token,
    `/admin/configs/audit-logs?limit=${safeLimit}`,
    { method: 'GET' },
  );
  if (Array.isArray(data)) {
    return data;
  }
  if (isRecord(data) && Array.isArray(data.items)) {
    return data.items;
  }
  return [];
}

function normalizeFeedbackCategory(value: unknown): FeedbackCategory {
  if (value === 'suggestion' || value === 'bug' || value === 'data' || value === 'other') {
    return value;
  }
  return 'other';
}

function normalizeFeedbackStatus(value: unknown): FeedbackStatus {
  if (value === 'new' || value === 'in_progress' || value === 'resolved' || value === 'archived') {
    return value;
  }
  return 'new';
}

function normalizeAttachments(raw: unknown): FeedbackAttachment[] {
  if (!Array.isArray(raw)) {
    return [];
  }
  return raw
    .filter((item): item is Record<string, unknown> => isRecord(item))
    .map((item) => ({
      object_key: typeof item.object_key === 'string' ? item.object_key : '',
      url: typeof item.url === 'string' ? item.url : '',
    }))
    .filter((item) => Boolean(item.url || item.object_key));
}

function normalizeFeedbackItem(raw: AdminFeedbackItem): AdminFeedbackItem {
  return {
    id: typeof raw.id === 'number' ? raw.id : Number(raw.id) || 0,
    user_id: typeof raw.user_id === 'number' ? raw.user_id : null,
    device_hash: typeof raw.device_hash === 'string' ? raw.device_hash : '',
    category: normalizeFeedbackCategory(raw.category),
    content: typeof raw.content === 'string' ? raw.content : '',
    contact: typeof raw.contact === 'string' ? raw.contact : '',
    attachments: normalizeAttachments(raw.attachments),
    app_version: typeof raw.app_version === 'string' ? raw.app_version : '',
    build_number: typeof raw.build_number === 'string' ? raw.build_number : '',
    ios_version: typeof raw.ios_version === 'string' ? raw.ios_version : '',
    device_model: typeof raw.device_model === 'string' ? raw.device_model : '',
    market_mode: typeof raw.market_mode === 'string' ? raw.market_mode : '',
    cloud_sync_enabled: Boolean(raw.cloud_sync_enabled),
    status: normalizeFeedbackStatus(raw.status),
    admin_note: typeof raw.admin_note === 'string' ? raw.admin_note : '',
    admin_reply: typeof raw.admin_reply === 'string' ? raw.admin_reply : '',
    replied_at: typeof raw.replied_at === 'string' && raw.replied_at ? raw.replied_at : null,
    updated_by: typeof raw.updated_by === 'string' ? raw.updated_by : '',
    created_at: typeof raw.created_at === 'string' ? raw.created_at : '',
    updated_at: typeof raw.updated_at === 'string' ? raw.updated_at : '',
  };
}

function normalizeFeedbackCounts(raw: unknown): AdminFeedbackCounts {
  if (!isRecord(raw)) {
    return { ...EMPTY_FEEDBACK_COUNTS };
  }
  const toCount = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) && v >= 0 ? v : 0);
  return {
    all: toCount(raw.all),
    new: toCount(raw.new),
    in_progress: toCount(raw.in_progress),
    resolved: toCount(raw.resolved),
    archived: toCount(raw.archived),
  };
}

export async function fetchAdminFeedbacks(
  apiBase: string,
  token: string,
  query: AdminFeedbackQuery = {},
): Promise<AdminFeedbackListResponse> {
  const params = new URLSearchParams();
  params.set('status', query.status ?? 'all');
  params.set('category', query.category ?? 'all');
  params.set('q', (query.q ?? '').trim());
  const safeLimit = Math.min(100, Math.max(1, Math.floor(query.limit ?? 50)));
  const safeOffset = Math.max(0, Math.floor(query.offset ?? 0));
  params.set('limit', String(safeLimit));
  params.set('offset', String(safeOffset));

  const data = await adminRequest<AdminFeedbackListResponse>(
    apiBase,
    token,
    `/admin/feedbacks?${params.toString()}`,
    { method: 'GET' },
  );

  const items = Array.isArray(data?.items) ? data.items.map(normalizeFeedbackItem) : [];
  const total =
    typeof data?.total === 'number' && Number.isFinite(data.total) ? data.total : items.length;
  const counts = normalizeFeedbackCounts(data?.counts);

  return { items, total, counts };
}

export async function updateAdminFeedback(
  apiBase: string,
  token: string,
  id: number,
  payload: UpdateAdminFeedbackPayload,
): Promise<AdminFeedbackItem> {
  const data = await adminRequest<AdminFeedbackItem>(
    apiBase,
    token,
    `/admin/feedbacks/${encodeURIComponent(String(id))}`,
    {
      method: 'PATCH',
      body: JSON.stringify(payload),
    },
  );
  return normalizeFeedbackItem(data);
}

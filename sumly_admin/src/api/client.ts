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

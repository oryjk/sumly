import type {
  ApiEnvelope,
  AppConfigItem,
  AuditLogItem,
  AuthVerifyResult,
  UpdateConfigPayload,
} from '../types/config';
import { isRecord } from '../types/config';
import { normalizeApiBase } from '../utils/storage';

const REQUEST_TIMEOUT_MS = 12_000;

export class AdminApiError extends Error {
  readonly status: number;
  readonly code?: number;
  readonly isUnauthorized: boolean;
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
    this.isServiceUnavailable = options.status === 503;
  }
}

async function adminRequest<T>(
  apiBase: string,
  token: string,
  path: string,
  init: RequestInit = {},
): Promise<T> {
  const base = normalizeApiBase(apiBase);
  const url = `${base}${path}`;
  const controller = new AbortController();
  const timeoutId = window.setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  const headers = new Headers(init.headers);
  headers.set('Authorization', `Bearer ${token.trim()}`);
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
    const serverMessage =
      (typeof envelope?.message === 'string' && envelope.message.trim()) ||
      (typeof envelope?.error === 'string' && envelope.error.trim()) ||
      '';

    if (!response.ok) {
      let friendly = serverMessage;
      if (response.status === 401) {
        friendly = serverMessage || '管理员令牌无效或已过期，请核对后重试';
      } else if (response.status === 503) {
        friendly =
          serverMessage || '服务端未配置 ADMIN_API_TOKEN，管理接口处于安全锁定状态（503）';
      } else if (!friendly) {
        friendly = `请求失败（HTTP ${response.status}）`;
      }
      throw new AdminApiError(friendly, {
        status: response.status,
        code: typeof envelope?.code === 'number' ? envelope.code : undefined,
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

export async function verifyAdminToken(
  apiBase: string,
  token: string,
): Promise<AuthVerifyResult> {
  const data = await adminRequest<AuthVerifyResult>(apiBase, token, '/admin/auth/verify', {
    method: 'GET',
  });
  if (!data || data.valid !== true) {
    throw new AdminApiError('令牌校验未通过', { status: 401 });
  }
  return data;
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

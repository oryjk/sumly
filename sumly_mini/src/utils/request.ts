/**
 * HTTP 请求封装。
 *
 * 认证要点：
 * - 受保护请求在 401 时做**一次**刷新并重试，不无限重试；
 * - 请求绑定发起时的会话捕获，刷新或换号后旧响应不得写入任何缓存；
 * - 凭据只从会话 store 取，页面不直接操作存储。
 */
import { buildAppApiUrl, getApiBaseUrl } from "@/config/apiBase";
import { isMockEnabled, tryMockRequest } from "@/mock";
import { getSession, refreshSessionForRequest } from "@/utils/sessionBridge";
import type { BackendApiResponse } from "@/types/backend";

type RequestMethod = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";
type RequestPayload = string | Record<string, unknown> | ArrayBuffer | undefined;

interface RequestOptions<TBody extends RequestPayload> {
  url: string;
  method?: RequestMethod;
  data?: TBody;
  auth?: boolean;
  /**
   * 订阅消息授权令牌。走专属 header，**不复用登录 token**——
   * 它只允许发消息，不授予任何账户访问权。携带时按匿名请求处理。
   */
  grant?: string;
}

/** 授权 header 名，与后端保持一致。 */
const GRANT_HEADER = "X-Holding-Notification-Grant";

export class ApiRequestError extends Error {
  statusCode: number;

  constructor(message: string, statusCode = 0) {
    super(message);
    this.name = "ApiRequestError";
    this.statusCode = statusCode;
  }
}

export function isUnauthorizedError(error: unknown): boolean {
  return error instanceof ApiRequestError && error.statusCode === 401;
}

/** 发送一次请求。 */
function send<TResponse, TBody extends RequestPayload>(
  requestUrl: string,
  method: RequestMethod,
  data: TBody | undefined,
  token: string,
  grant?: string,
): Promise<TResponse> {
  return new Promise<TResponse>((resolve, reject) => {
    uni.request({
      url: requestUrl,
      method: method as never,
      data: data,
      header: {
        "Content-Type": "application/json",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...(grant ? { [GRANT_HEADER]: grant } : {}),
      },
      success: (response) => {
        const { statusCode, data: body } = response;
        if (statusCode >= 200 && statusCode < 300) {
          resolve(body as TResponse);
          return;
        }
        const message =
          typeof body === "object" && body && "message" in body
            ? String((body as { message?: string }).message || "请求失败")
            : `请求失败(${statusCode})`;
        reject(new ApiRequestError(message, statusCode));
      },
      fail: (error) => {
        reject(new ApiRequestError(error.errMsg || "网络请求失败"));
      },
    });
  });
}

export async function requestRaw<TResponse, TBody extends RequestPayload = Record<string, unknown>>(
  options: RequestOptions<TBody>,
): Promise<TResponse> {
  const method = options.method ?? "GET";
  const requestUrl = /^https?:\/\//i.test(options.url)
    ? options.url
    : buildAppApiUrl(getApiBaseUrl(), options.url);

  // Mock 拦截：开发环境下通过 VITE_USE_MOCK 开启。
  // 开启后必须“全有或全无”：未覆盖的接口直接报错，不允许回落到真实后端，
  // 否则页面会混显 mock 数据和真实数据，误导联调判断。
  if (isMockEnabled()) {
    const mockResult = tryMockRequest(method, requestUrl, options.data);
    if (mockResult === null) {
      return Promise.reject(new ApiRequestError(`mock 模式未覆盖该接口: ${method} ${options.url}`, 0));
    }
    return mockResult as Promise<TResponse>;
  }

  if (!options.auth) {
    return send<TResponse, TBody>(requestUrl, method, options.data, "", options.grant);
  }

  // 受保护请求：绑定发起时的会话，换号后旧响应直接丢弃
  const capture = getSession().captureSession();
  const token = getSession().accessToken.value;
  try {
    return await send<TResponse, TBody>(requestUrl, method, options.data, token, options.grant);
  } catch (error) {
    if (!isUnauthorizedError(error)) {
      throw error;
    }
    // 只刷新一次；仍失败则要求重新登录
    await refreshSessionForRequest();
    // 刷新期间可能已退出或换号，此时不得用新凭据重放旧请求
    if (!getSession().isCurrentSession(capture)) {
      throw error;
    }
    return send<TResponse, TBody>(requestUrl, method, options.data, getSession().accessToken.value, options.grant);
  }
}

export async function requestApi<TResponse, TBody extends RequestPayload = Record<string, unknown>>(
  options: RequestOptions<TBody>,
): Promise<TResponse> {
  const response = await requestRaw<BackendApiResponse<TResponse>, TBody>(options);
  if (response.code !== 0) {
    throw new ApiRequestError(response.message || "请求失败", response.code || 0);
  }
  return (response.data ?? null) as TResponse;
}

export const request = requestRaw;

import { getMockUser, setMockNickname, type MockUser } from "@/mock/appData";
import { mockMarketSync, mockQuote, mockRealtime } from "@/mock/marketData";
import type { MarketSeries } from "@/types/market";
import type { AuthProvider } from "@/types/auth";
import type { BackendApiResponse } from "@/types/backend";

type RequestMethod = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";

function appPath(url: string): string {
  // 不使用浏览器 URL API：mock 也要能在微信小程序运行时工作
  const withoutQuery = url.split("?")[0];
  const withoutOrigin = /^https?:\/\//i.test(withoutQuery)
    ? withoutQuery.replace(/^https?:\/\/[^/]+/i, "")
    : withoutQuery;
  const marker = "/api/v1/app";
  const index = withoutOrigin.indexOf(marker);
  if (index === -1) {
    return withoutOrigin;
  }
  return withoutOrigin.slice(index + marker.length);
}

function success<T>(data: T): BackendApiResponse<T> {
  return { code: 0, message: "ok", data };
}

function failure(message: string, code: number): BackendApiResponse<never> {
  return { code, message, data: null };
}

/** mock 会话状态：切换账号可验证跨账户隔离。 */
let mockProvider: AuthProvider = "wechat";
let mockSessionActive = false;

export function resetMockSession(): void {
  mockSessionActive = false;
}

function asAuthUser(user: MockUser) {
  return {
    id: user.id,
    nickname: user.nickname,
    avatar_url: user.avatar_url,
    real_name: user.real_name,
    phone_number: user.phone_number,
    email: user.email,
    status: user.status,
    provider: mockProvider,
  };
}

function loginResult() {
  mockSessionActive = true;
  return success({
    token: "mock-access-token",
    refresh_token: "mock-refresh-token",
    expires_in: 900,
    user: asAuthUser(getMockUser()),
  });
}

export function tryMockHandler(method: RequestMethod, url: string, data: unknown): unknown | null {
  const path = appPath(url);
  const body = (data ?? {}) as Record<string, unknown>;

  // ---- 认证 ----
  if (path === "/auth/capabilities" && method === "GET") {
    return success({ apple: false, wechat: true, phone: true, email: true });
  }
  if (path === "/auth/wechat/session" && method === "POST") {
    if (typeof body.js_code !== "string" || !body.js_code.trim()) {
      return failure("微信登录 code 不能为空", 422);
    }
    mockProvider = "wechat";
    return loginResult();
  }
  if (path === "/auth/wechat/login" && method === "POST") {
    // 旧契约保持可用
    return success({ token: "mock-token", user: getMockUser() });
  }
  if (path === "/auth/phone/code" && method === "POST") {
    if (typeof body.phone_number !== "string") return failure("手机号无效", 422);
    return success({ retry_after: 60, expires_in: 300 });
  }
  if (path === "/auth/phone/login" && method === "POST") {
    if (typeof body.code !== "string" || body.code.length !== 6) {
      return failure("验证码无效", 401);
    }
    mockProvider = "phone";
    return loginResult();
  }
  if (path === "/auth/email/code" && method === "POST") {
    const purpose = body.purpose;
    if (purpose !== "register" && purpose !== "reset_password") {
      return failure("验证码用途无效", 422);
    }
    return success({ retry_after: 60, expires_in: 300 });
  }
  if (path === "/auth/email/register" && method === "POST") {
    if (typeof body.code !== "string" || body.code.length !== 6) {
      return failure("验证码无效", 401);
    }
    if (typeof body.password === "string" && body.password.length >= 12) {
      const nickname = typeof body.email === "string" ? body.email.split("@")[0] : "邮箱用户";
      setMockNickname(nickname || "邮箱用户");
    }
    mockProvider = "email";
    return loginResult();
  }
  if (path === "/auth/email/login" && method === "POST") {
    if (typeof body.password !== "string" || body.password.length < 12) {
      return failure("邮箱或密码不正确", 401);
    }
    mockProvider = "email";
    return loginResult();
  }
  if (path === "/auth/email/reset-password" && method === "POST") {
    if (typeof body.new_password !== "string" || body.new_password.length < 12) {
      return failure("密码不符合要求", 422);
    }
    return success({});
  }
  if (path === "/auth/refresh" && method === "POST") {
    if (!mockSessionActive) return failure("会话已失效", 401);
    return loginResult();
  }
  if (path === "/auth/logout" && method === "POST") {
    mockSessionActive = false;
    return success({});
  }
  if (path === "/auth/me" && method === "GET") {
    if (!mockSessionActive) return failure("未登录", 401);
    return success(asAuthUser(getMockUser()));
  }
  if (path === "/auth/account" && method === "DELETE") {
    if (body.confirmation !== "DELETE") return failure("需要确认", 422);
    mockSessionActive = false;
    return success({});
  }

  // ---- 旧用户接口（保留兼容） ----
  if (path === "/users/me" && method === "GET") {
    return success(getMockUser());
  }
  if (path === "/users/me" && method === "PATCH") {
    if (typeof body.nickname === "string" && body.nickname.trim()) {
      setMockNickname(body.nickname.trim());
    }
    return success(getMockUser());
  }

  // ---- 行情 ----
  if (path === "/market/gold/quote" && method === "GET") {
    return success(mockQuote("xauusd"));
  }
  if (path === "/market/gold/realtime" && method === "GET") {
    return success(mockRealtime("xauusd"));
  }
  if (path === "/market/gold/instruments/au9999/quote" && method === "GET") {
    return success(mockQuote("au9999"));
  }
  if (path === "/market/gold/instruments/au9999/realtime" && method === "GET") {
    return success(mockRealtime("au9999"));
  }
  if (path === "/market/gold/sync" && method === "GET") {
    const query = url.split("?")[1] ?? "";
    const series = queryValue(query, "series") ?? "xauusd";
    const cursor = queryValue(query, "cursor");
    return success(mockMarketSync(series as MarketSeries, cursor ?? undefined));
  }
  return null;
}

/** 从 query 串中取值，不依赖 URLSearchParams 以兼容小程序运行时。 */
function queryValue(query: string, key: string): string | null {
  for (const pair of query.split("&")) {
    if (!pair) continue;
    const separator = pair.indexOf("=");
    const name = separator === -1 ? pair : pair.slice(0, separator);
    if (name !== key) continue;
    const raw = separator === -1 ? "" : pair.slice(separator + 1);
    return decodeURIComponent(raw);
  }
  return null;
}

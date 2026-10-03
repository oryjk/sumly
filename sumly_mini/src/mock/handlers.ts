import { getMockUser, setMockNickname } from "@/mock/appData";
import { mockMarketSync, mockQuote, mockRealtime } from "@/mock/marketData";
import type { MarketSeries } from "@/types/market";
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

export function tryMockHandler(method: RequestMethod, url: string, data: unknown): unknown | null {
  const path = appPath(url);
  if (path === "/auth/wechat/login" && method === "POST") {
    return success({ token: "mock-token", user: getMockUser() });
  }
  if (path === "/users/me" && method === "GET") {
    return success(getMockUser());
  }
  if (path === "/users/me" && method === "PATCH") {
    const body = (data ?? {}) as { nickname?: unknown; real_name?: unknown };
    if (typeof body.nickname === "string" && body.nickname.trim()) {
      setMockNickname(body.nickname.trim());
    }
    return success(getMockUser());
  }
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

/** 从 query串中取值，不依赖 URLSearchParams 以兼容小程序运行时。 */
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

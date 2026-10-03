/**
 * mock 行情数据。
 * 仅在 VITE_USE_MOCK=true 时使用，字段与真实后端契约一致，
 * 不得回落真实服务器。
 */
import type { GoldQuote, GoldRealtime, MarketSeries, MarketSyncPage } from "@/types/market";

/** 固定基准时间，保证 mock 输出可重复。 */
const MOCK_NOW = Date.UTC(2026, 0, 2, 8, 0, 0);
const MOCK_USD_CNY = 7.1084;

const MOCK_PRICE: Record<MarketSeries, number> = {
  xauusd: 4288.66,
  au9999: 968.42,
};

function iso(ms: number): string {
  return new Date(ms).toISOString();
}

export function mockQuote(series: MarketSeries): GoldQuote {
  const price = MOCK_PRICE[series];
  const prevClose = price * 0.994;
  return {
    symbol: series === "au9999" ? "AU9999" : "XAUUSD",
    price,
    open: price * 0.996,
    high: price * 1.007,
    low: price * 0.993,
    prev_close: prevClose,
    change: price - prevClose,
    change_percent: ((price - prevClose) / prevClose) * 100,
    usd_cny: MOCK_USD_CNY,
    cny_per_gram: series === "au9999" ? price : (price * MOCK_USD_CNY) / 31.1034768,
    source_time: iso(MOCK_NOW - 60_000),
  };
}

export function mockRealtime(series: MarketSeries): GoldRealtime {
  const base = MOCK_PRICE[series];
  // 五秒采样，覆盖二十分钟窗口
  const points = [];
  for (let secondsAgo = 1200; secondsAgo >= 0; secondsAgo -= 5) {
    const time = MOCK_NOW - secondsAgo * 1000;
    const drift = Math.sin(secondsAgo / 90) * base * 0.002;
    points.push({
      time: iso(time),
      source_time: iso(time - 60_000),
      price: series === "au9999" ? base + drift : (base + drift) * (MOCK_USD_CNY / 31.1034768),
    });
  }
  return {
    symbol: series === "au9999" ? "AU9999" : "XAUUSD",
    unit: "CNY/g",
    interval_seconds: 5,
    window_seconds: 1200,
    points,
  };
}

/** 增量同步 mock：首次返回完整快照，之后按 cursor 返回空增量。 */
const mockCursors = new Map<MarketSeries, string>();

export function mockMarketSync(series: MarketSeries, cursor: string | undefined): MarketSyncPage {
  const unit = series === "au9999" ? "CNY/g" : "USD/troy_oz";
  const nextCursor = `mock-${series}-1`;
  if (!cursor) {
    mockCursors.set(series, nextCursor);
    const points =
      series === "xauusd"
        ? [
            { date: "2015-07-01", granularity: "annual" as const, open: 1, high: 1, low: 1, close: 1160.5, source: "usgs", deleted: false },
            { date: "2026-01-02", granularity: "daily" as const, open: 1, high: 1, low: 1, close: 4288.66, source: "sina", deleted: false },
          ]
        : [
            { date: "2026-01-02", granularity: "daily" as const, open: 1, high: 1, low: 1, close: 968.42, source: "sge", deleted: false },
          ];
    return { series, unit, cursor: nextCursor, reset: true, points };
  }
  return { series, unit, cursor: nextCursor, reset: false, points: [] };
}

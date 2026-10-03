import { describe, expect, it } from "bun:test";
import { toCnyPoints } from "../src/domain/market/conversion";
import type { GoldQuote } from "../src/types/market";
import type { MarketCache } from "../src/domain/market/sync";

const NOW = 1_757_000_000_000;

function quote(overrides: Partial<GoldQuote> = {}): GoldQuote {
  return {
    symbol: "XAUUSD",
    price: 4288.66,
    open: 4288.66,
    high: 4318.02,
    low: 4257.4,
    prev_close: 4263.94,
    change: 24.72,
    change_percent: 0.58,
    usd_cny: 6.7084,
    cny_per_gram: 924.63,
    source_time: new Date(NOW).toISOString(),
    ...overrides,
  };
}

const cache: MarketCache = {
  series: "xauusd",
  unit: "USD/troy_oz",
  cursor: "c1",
  points: [
    { date: "1900-07-01", granularity: "annual", open: 1, high: 2, low: 0.5, close: 20.67, source: "usgs" },
    { date: "2024-01-02", granularity: "daily", open: 1, high: 2, low: 0.5, close: 2050.5, source: "sina" },
  ],
};

describe("人民币折算", () => {
  it("国内品种原值即为元/克，不做换算", () => {
    const domestic: MarketCache = {
      series: "au9999",
      unit: "CNY/g",
      cursor: "c",
      points: [{ date: "2024-01-02", granularity: "daily", open: 1, high: 2, low: 0.5, close: 560.5, source: "sge" }],
    };
    const points = toCnyPoints(domestic, null);
    expect(points).toHaveLength(1);
    expect(points[0].price).toBe(560.5);
  });

  it("国际按 USD * usd_cny / 31.1034768 折算", () => {
    const points = toCnyPoints(cache, quote());
    const daily = points.find((p) => p.source === "sina");
    expect(daily?.price).toBeCloseTo((2050.5 * 6.7084) / 31.1034768, 6);
  });

  it("无有效汇率时国际历史为空", () => {
    expect(toCnyPoints(cache, quote({ usd_cny: 0 }))).toEqual([]);
  });

  it("汇率为负或非有限视为无有效汇率", () => {
    expect(toCnyPoints(cache, quote({ usd_cny: -1 }))).toEqual([]);
    expect(toCnyPoints(cache, quote({ usd_cny: Number.NaN }))).toEqual([]);
  });

  it("点按时间升序，粒度与来源保留", () => {
    const points = toCnyPoints(cache, quote());
    expect(points).toHaveLength(2);
    expect(points[0].granularity).toBe("annual");
    expect(points[0].source).toBe("usgs");
    expect(points[1].granularity).toBe("daily");
    expect(points[0].time).toBeLessThan(points[1].time);
  });

  it("时间戳由日期键严格解析为 UTC 正午之前不漂移", () => {
    const points = toCnyPoints(cache, quote());
    const annual = points[0];
    // 1900-07-01 解析为 UTC 零点时刻
    expect(new Date(annual.time).toISOString().slice(0, 10)).toBe("1900-07-01");
  });

  it("缓存为空时返回空数组", () => {
    const empty: MarketCache = { series: "xauusd", unit: "USD/troy_oz", cursor: "", points: [] };
    expect(toCnyPoints(empty, quote())).toEqual([]);
  });
});

import { describe, expect, it } from "bun:test";
import { mergeMarketSync, validateSyncPage, type MarketCache, type MarketSyncPage } from "../src/domain/market/sync";

const CACHE: MarketCache = {
  series: "xauusd",
  unit: "USD/troy_oz",
  cursor: "cursor-1",
  points: [
    { date: "2024-01-02", granularity: "daily", open: 1, high: 2, low: 0.5, close: 1.5, source: "sina" },
    { date: "1900-07-01", granularity: "annual", open: 1, high: 2, low: 0.5, close: 1.2, source: "usgs" },
  ],
};

function page(overrides: Partial<MarketSyncPage> = {}): MarketSyncPage {
  return {
    series: "xauusd",
    unit: "USD/troy_oz",
    cursor: "cursor-2",
    reset: false,
    points: [],
    ...overrides,
  };
}

describe("增量合并", () => {
  it("reset 替换整个快照", () => {
    const merged = mergeMarketSync(CACHE, page({ reset: true, cursor: "fresh" }));
    expect(merged.points).toHaveLength(0);
    expect(merged.cursor).toBe("fresh");
  });

  it("新增记录按 granularity+date 追加并保持时间序", () => {
    const merged = mergeMarketSync(
      CACHE,
      page({
        points: [
          { date: "2024-01-03", granularity: "daily", open: 2, high: 3, low: 1, close: 2.5, source: "sina" },
        ],
      }),
    );
    expect(merged.points.map((p) => p.date)).toEqual(["1900-07-01", "2024-01-02", "2024-01-03"]);
  });

  it("修正记录覆盖同键旧值", () => {
    const merged = mergeMarketSync(
      CACHE,
      page({
        points: [
          { date: "2024-01-02", granularity: "daily", open: 9, high: 9, low: 9, close: 8.8, source: "sina" },
        ],
      }),
    );
    expect(merged.points).toHaveLength(2);
    expect(merged.points.find((p) => p.date === "2024-01-02")?.close).toBe(8.8);
  });

  it("删除标记的记录不保留在缓存中", () => {
    const merged = mergeMarketSync(
      CACHE,
      page({
        points: [
          {
            date: "2024-01-02",
            granularity: "daily",
            open: 0,
            high: 0,
            low: 0,
            close: 0,
            source: "sina",
            deleted: true,
          },
        ],
      }),
    );
    expect(merged.points.map((p) => p.date)).toEqual(["1900-07-01"]);
  });

  it("空增量仍推进 cursor", () => {
    const merged = mergeMarketSync(CACHE, page({ cursor: "cursor-3" }));
    expect(merged.points).toHaveLength(2);
    expect(merged.cursor).toBe("cursor-3");
  });

  it("首次同步（无本地缓存）建立新快照", () => {
    const merged = mergeMarketSync(
      null,
      page({
        reset: true,
        points: [
          { date: "2024-01-02", granularity: "daily", open: 1, high: 2, low: 0.5, close: 1.5, source: "sina" },
        ],
      }),
    );
    expect(merged.series).toBe("xauusd");
    expect(merged.points).toHaveLength(1);
  });
});

describe("契约校验", () => {
  it("请求品种与响应品种错配拒绝", () => {
    // 调用方按 xauusd 发起请求，服务端却返回 au9999 的页
    expect(() =>
      validateSyncPage(page({ series: "au9999", unit: "CNY/g" }), "xauusd"),
    ).toThrow();
  });

  it("单位与品种不匹配拒绝", () => {
    expect(() => mergeMarketSync(CACHE, page({ unit: "CNY/g" }))).toThrow();
  });

  it("国内品种只接受 CNY/g", () => {
    const domestic: MarketCache = { series: "au9999", unit: "CNY/g", cursor: "c", points: [] };
    expect(() => mergeMarketSync(domestic, page({ series: "au9999", unit: "CNY/g" }))).not.toThrow();
    expect(() => mergeMarketSync(domestic, page({ series: "au9999", unit: "USD/troy_oz" }))).toThrow();
  });

  it("年度记录只允许国际 1900-2015", () => {
    expect(() =>
      mergeMarketSync(
        CACHE,
        page({
          points: [
            { date: "1899-07-01", granularity: "annual", open: 1, high: 2, low: 0.5, close: 1.2, source: "usgs" },
          ],
        }),
      ),
    ).toThrow();

    expect(() =>
      mergeMarketSync(
        CACHE,
        page({
          points: [
            { date: "2016-07-01", granularity: "annual", open: 1, high: 2, low: 0.5, close: 1.2, source: "usgs" },
          ],
        }),
      ),
    ).toThrow();
  });

  it("国内品种不接受年度记录", () => {
    const domestic: MarketCache = { series: "au9999", unit: "CNY/g", cursor: "c", points: [] };
    expect(() =>
      mergeMarketSync(
        domestic,
        page({
          series: "au9999",
          unit: "CNY/g",
          points: [
            { date: "1900-07-01", granularity: "annual", open: 1, high: 2, low: 0.5, close: 1.2, source: "usgs" },
          ],
        }),
      ),
    ).toThrow();
  });

  it("非法日期键拒绝（不存在的2 月 30 日）", () => {
    expect(() =>
      mergeMarketSync(
        CACHE,
        page({
          points: [
            { date: "2024-02-30", granularity: "daily", open: 1, high: 2, low: 0.5, close: 1.5, source: "sina" },
          ],
        }),
      ),
    ).toThrow();
  });

  it("非删除记录必须为正有限值", () => {
    expect(() =>
      mergeMarketSync(
        CACHE,
        page({
          points: [
            { date: "2024-01-04", granularity: "daily", open: 1, high: 2, low: 0.5, close: Number.NaN, source: "sina" },
          ],
        }),
      ),
    ).toThrow();

    expect(() =>
      mergeMarketSync(
        CACHE,
        page({
          points: [
            { date: "2024-01-04", granularity: "daily", open: 1, high: 2, low: 0.5, close: 0, source: "sina" },
          ],
        }),
      ),
    ).toThrow();
  });

  it("空来源拒绝", () => {
    expect(() =>
      mergeMarketSync(
        CACHE,
        page({
          points: [
            { date: "2024-01-04", granularity: "daily", open: 1, high: 2, low: 0.5, close: 1.5, source: "" },
          ],
        }),
      ),
    ).toThrow();
  });

  it("重复键拒绝", () => {
    expect(() =>
      mergeMarketSync(
        CACHE,
        page({
          points: [
            { date: "2024-01-05", granularity: "daily", open: 1, high: 2, low: 0.5, close: 1.5, source: "sina" },
            { date: "2024-01-05", granularity: "daily", open: 1, high: 2, low: 0.5, close: 1.6, source: "sina" },
          ],
        }),
      ),
    ).toThrow();
  });

  it("实时粒度不属于历史同步", () => {
    expect(() =>
      mergeMarketSync(
        CACHE,
        page({
          points: [
            { date: "2024-01-05", granularity: "realtime" as never, open: 1, high: 2, low: 0.5, close: 1.5, source: "sina" },
          ],
        }),
      ),
    ).toThrow();
  });

  it("空cursor 拒绝", () => {
    expect(() => mergeMarketSync(CACHE, page({ cursor: "" }))).toThrow();
  });
});

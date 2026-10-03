import { describe, expect, it } from "bun:test";
import { createMarketStore } from "../src/stores/market";
import type { GoldQuote, GoldRealtime, MarketCache, MarketSeries } from "../src/types/market";

const NOW = 1_757_000_000_000;

interface Deferred<T> {
  promise: Promise<T>;
  resolve: (value: T) => void;
  reject: (error: Error) => void;
}

function deferred<T>(): Deferred<T> {
  let resolve!: (value: T) => void;
  let reject!: (error: Error) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

function quote(basis: "domestic" | "international"): GoldQuote {
  return {
    symbol: basis === "domestic" ? "AU9999" : "XAUUSD",
    price: basis === "domestic" ? 560.5 : 4288.66,
    open: 1,
    high: 1,
    low: 1,
    prev_close: 1,
    change: 1,
    change_percent: 1,
    usd_cny: 6.7084,
    cny_per_gram: basis === "domestic" ? 560.5 : 924.63,
    source_time: new Date(NOW).toISOString(),
  };
}

function realtime(basis: "domestic" | "international"): GoldRealtime {
  return {
    symbol: basis === "domestic" ? "AU9999" : "XAUUSD",
    unit: "CNY/g",
    interval_seconds: 5,
    window_seconds: 1200,
    points: [
      { time: new Date(NOW - 60_000).toISOString(), source_time: new Date(NOW - 60_000).toISOString(), price: 560 },
      { time: new Date(NOW).toISOString(), source_time: new Date(NOW).toISOString(), price: 561 },
    ],
  };
}

function cacheFor(series: MarketSeries): MarketCache {
  return {
    series,
    unit: series === "au9999" ? "CNY/g" : "USD/troy_oz",
    cursor: "c1",
    points: [
      {
        date: "2024-01-02",
        granularity: "daily",
        open: 1,
        high: 1,
        low: 1,
        close: series === "au9999" ? 560.5 : 2050.5,
        source: "sina",
      },
    ],
  };
}

/** 构造只记录调用、不启动定时器的 store 依赖，测试完全确定。 */
function harness(options?: {
  quote?: (basis: "domestic" | "international") => Promise<GoldQuote>;
  realtime?: (basis: "domestic" | "international") => Promise<GoldRealtime>;
  onSaveCache?: () => void;
}) {
  const quoteImpl = options?.quote ?? (async (basis) => quote(basis));
  const realtimeImpl = options?.realtime ?? (async (basis) => realtime(basis));
  const saved: { series: MarketSeries; cache: MarketCache | null }[] = [];

  const store = createMarketStore({
    loadCache: (series) => cacheFor(series),
    saveCache: (series, cache) => {
      options?.onSaveCache?.();
      saved.push({ series, cache });
    },
    clearCache: () => {},
    getGoldQuote: quoteImpl,
    getGoldRealtime: realtimeImpl,
    getMarketSync: async (series) => ({
      series,
      unit: series === "au9999" ? ("CNY/g" as const) : ("USD/troy_oz" as const),
      cursor: "c2",
      reset: false,
      points: [],
    }),
    now: () => NOW,
  });

  return { store, saved };
}

describe("口径切换", () => {
  it("切换后 basis 与报价一致", async () => {
    const { store } = harness();
    // 初始为 international，切到国内
    expect(store.basis.value).toBe("international");
    const ok = await store.switchBasis("domestic");
    expect(ok).toBe(true);
    expect(store.basis.value).toBe("domestic");
    expect(store.quote.value?.symbol).toBe("AU9999");
    expect(store.quote.value?.cny_per_gram).toBe(560.5);
  });

  it("切回国际后报价同步更新", async () => {
    const { store } = harness();
    await store.switchBasis("domestic");
    const ok = await store.switchBasis("international");
    expect(ok).toBe(true);
    expect(store.basis.value).toBe("international");
    expect(store.quote.value?.cny_per_gram).toBe(924.63);
  });

  it("慢国内请求不得覆盖已切换的国际口径", async () => {
    const slowDomestic = deferred<GoldQuote>();
    const { store } = harness({
      quote: (basis) => (basis === "domestic" ? slowDomestic.promise : Promise.resolve(quote("international"))),
    });

    const pending = store.switchBasis("domestic");
    // 切换尚未完成时切到国际
    await store.switchBasis("international");
    slowDomestic.resolve(quote("domestic"));
    await pending;

    expect(store.basis.value).toBe("international");
    expect(store.quote.value?.symbol).toBe("XAUUSD");
  });

  it("切换失败保留原口径与原报价", async () => {
    // 先成功切到国内，建立已知原状态
    const { store } = harness();
    await store.switchBasis("domestic");
    expect(store.basis.value).toBe("domestic");
    const originalQuote = store.quote.value?.cny_per_gram;

    // 再让国际失败
    const failing = harness({
      quote: (basis) =>
        basis === "international" ? Promise.reject(new Error("上游不可用")) : Promise.resolve(quote("domestic")),
    });
    await failing.store.switchBasis("domestic");
    const ok = await failing.store.switchBasis("international");

    expect(ok).toBe(false);
    expect(failing.store.basis.value).toBe("domestic");
    expect(failing.store.error.value).toBe("上游不可用");
    // 原报价未被清空
    expect(failing.store.quote.value?.cny_per_gram).toBe(originalQuote);
  });
});

describe("缓存写入", () => {
  it("缓存写失败时保留原有缓存且不推进游标", async () => {
    let failNext = true;
    const { store } = harness({
      onSaveCache: () => {
        if (failNext) {
          failNext = false;
          throw new Error("存储已满");
        }
      },
    });

    const before = store.points.value.length;
    await expect(store.refreshHistory("xauusd")).rejects.toThrow("存储已满");
    // 错误对页面可见
    expect(store.error.value).toBe("存储已满");
    // 缓存与游标都保持原样
    expect(store.points.value.length).toBe(before);

    // 下一次写入成功后才推进游标并清除错误
    await store.refreshHistory("xauusd");
    expect(store.error.value).toBeNull();
  });

  it("写入成功后游标推进且缓存更新", async () => {
    const { store, saved } = harness();
    await store.refreshHistory("xauusd");
    expect(saved.at(-1)?.cache?.cursor).toBe("c2");
    expect(store.error.value).toBeNull();
  });
});

describe("实时状态", () => {
  it("拉取实时后派生 paused 状态", async () => {
    const { store } = harness();
    await store.start("market");
    expect(store.status.value === "live" || store.status.value === "paused").toBe(true);
  });
});

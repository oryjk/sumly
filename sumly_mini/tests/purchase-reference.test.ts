import { describe, expect, it } from "bun:test";
import { createPurchaseReference } from "../src/stores/purchaseReference";
import type { MarketBasis } from "../src/types/market";

const DAY = 86_400_000;
const NOW = Date.UTC(2026, 0, 10, 8, 0, 0);
const TODAY = Date.UTC(2026, 0, 10);
const YESTERDAY = Date.UTC(2026, 0, 9);
const LAST_MONTH = Date.UTC(2025, 11, 20);

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

/** 构造只依赖注入的参考价模型，完全确定无副作用。 */
function harness(options?: {
  quote?: () => Promise<{ cny_per_gram: number; usd_cny: number }>;
  daily?: () => Promise<{ date: string; close: number }[]>;
  cachedDaily?: () => Promise<{ date: string; close: number }[]>;
  cachedQuote?: () => Promise<{ cny_per_gram: number; usd_cny: number }>;
  initialDay?: number;
}) {
  const daily = options?.daily ?? (async () => [{ date: "2026-01-09", close: 555.5 }]);
  const quote = options?.quote ?? (async () => ({ cny_per_gram: 600, usd_cny: 7.1 }));
  return createPurchaseReference({
    basis: "domestic" as MarketBasis,
    now: () => NOW,
    initialDay: options?.initialDay,
    getCachedDaily: options?.cachedDaily ?? (async () => null),
    getDaily: daily,
    getQuote: quote,
    getCachedQuote: options?.cachedQuote ?? (async () => null),
  });
}

describe("当日参考价", () => {
  it("当日使用当前报价", async () => {
    const model = harness();
    await model.load(NOW);
    expect(model.reference.value?.price).toBe(600);
    expect(model.reference.value?.historical).toBe(false);
    expect(model.issue.value).toBeNull();
    expect(model.priceText.value).toBe("600.00");
  });

  it("当日无有效报价时报unavailable", async () => {
    const model = harness({ quote: async () => ({ cny_per_gram: 0, usd_cny: 7.1 }) });
    await model.load(NOW);
    expect(model.issue.value).toBe("unavailable");
    expect(model.reference.value).toBeNull();
  });

  it("初始价格为当日时可预填", () => {
    const model = createPurchaseReference({
      basis: "domestic",
      now: () => NOW,
      getCachedDaily: async () => null,
      getDaily: async () => [],
      getQuote: async () => ({ cny_per_gram: 600, usd_cny: 7.1 }),
      getCachedQuote: async () => null,
    });
    model.selectDate(TODAY);
    model.editPrice("600.00");
    expect(model.priceText.value).toBe("600.00");
  });
});

describe("历史参考价", () => {
  it("历史日期只用当日收盘价，不取现价", async () => {
    const model = harness({ initialDay: TODAY });
    await model.selectDate(YESTERDAY);
    await model.load(NOW);
    expect(model.reference.value?.price).toBe(555.5);
    expect(model.reference.value?.historical).toBe(true);
    expect(model.priceText.value).toBe("555.50");
  });

  it("休市日无收盘价时报missingDay", async () => {
    const model = harness({ initialDay: TODAY, daily: async () => [] });
    await model.selectDate(LAST_MONTH);
    await model.load(NOW);
    expect(model.issue.value).toBe("missingDay");
    expect(model.reference.value).toBeNull();
  });

  it("国际历史价按当前汇率折算并标注", async () => {
    const model = createPurchaseReference({
      basis: "international",
      now: () => NOW,
      initialDay: TODAY,
      getCachedDaily: async () => null,
      getDaily: async () => [{ date: "2026-01-09", close: 2000 }],
      getQuote: async () => ({ cny_per_gram: 600, usd_cny: 7.1 }),
      getCachedQuote: async () => null,
    });
    await model.selectDate(YESTERDAY);
    await model.load(NOW);
    // 2000 USD/oz × 7.1 ÷ 31.1034768
    expect(model.reference.value?.price).toBeCloseTo((2000 * 7.1) / 31.1034768, 6);
    expect(model.reference.value?.exchangeRate).toBe(7.1);
    expect(model.reference.value?.historical).toBe(true);
  });

  it("国际缺汇率时报missingExchangeRate", async () => {
    const model = createPurchaseReference({
      basis: "international",
      now: () => NOW,
      initialDay: TODAY,
      getCachedDaily: async () => null,
      getDaily: async () => [{ date: "2026-01-09", close: 2000 }],
      getQuote: async () => ({ cny_per_gram: 600, usd_cny: 0 }),
      getCachedQuote: async () => null,
    });
    await model.selectDate(YESTERDAY);
    await model.load(NOW);
    expect(model.issue.value).toBe("missingExchangeRate");
  });

  it("汇率请求失败时回退到缓存报价", async () => {
    const model = createPurchaseReference({
      basis: "international",
      now: () => NOW,
      initialDay: TODAY,
      getCachedDaily: async () => null,
      getDaily: async () => [{ date: "2026-01-09", close: 2000 }],
      getQuote: async () => {
        throw new Error("上游不可用");
      },
      getCachedQuote: async () => ({ cny_per_gram: 590, usd_cny: 7.0 }),
    });
    await model.selectDate(YESTERDAY);
    await model.load(NOW);
    expect(model.reference.value?.exchangeRate).toBe(7.0);
  });

  it("已缓存的历史价命中时不重复请求日线", async () => {
    let dailyCalls = 0;
    const model = harness({
      initialDay: TODAY,
      cachedDaily: async () => [{ date: "2026-01-09", close: 555.5 }],
      daily: async () => {
        dailyCalls += 1;
        return [];
      },
    });
    await model.selectDate(YESTERDAY);
    await model.load(NOW);
    expect(dailyCalls).toBe(0);
    expect(model.reference.value?.price).toBe(555.5);
  });
});

describe("手动输入保护", () => {
  it("手动编辑后晚响应不覆盖", async () => {
    const slow = deferred<{ cny_per_gram: number; usd_cny: number }>();
    const model = createPurchaseReference({
      basis: "domestic",
      now: () => NOW,
      getCachedDaily: async () => null,
      getDaily: async () => [],
      getQuote: () => slow.promise,
      getCachedQuote: async () => null,
    });

    await model.selectDate(TODAY);
    const pending = model.load(NOW);
    // 用户在请求返回前手动输入
    model.editPrice("888.88");
    slow.resolve({ cny_per_gram: 600, usd_cny: 7.1 });
    await pending;

    expect(model.priceText.value).toBe("888.88");
    expect(model.manual.value).toBe(true);
    // 参考价仍然更新，供用户比对
    expect(model.reference.value?.price).toBe(600);
  });

  it("快速切日期只提交最后一次", async () => {
    const first = deferred<{ date: string; close: number }[]>();
    const second = deferred<{ date: string; close: number }[]>();
    let call = 0;
    const model = createPurchaseReference({
      basis: "domestic",
      now: () => NOW,
      getCachedDaily: async () => null,
      getDaily: () => {
        call += 1;
        return call === 1 ? first.promise : second.promise;
      },
      getQuote: async () => ({ cny_per_gram: 600, usd_cny: 7.1 }),
      getCachedQuote: async () => null,
    });

    await model.selectDate(YESTERDAY);
    const firstLoad = model.load(NOW);
    await model.selectDate(LAST_MONTH);
    const secondLoad = model.load(NOW);

    // 先返回旧请求的响应，必须被丢弃
    first.resolve([{ date: "2026-01-09", close: 555.5 }]);
    second.resolve([{ date: "2025-12-20", close: 611.1 }]);
    await Promise.all([firstLoad, secondLoad]);

    expect(model.reference.value?.price).toBe(611.1);
  });

  it("useReference 用回参考价并退出手动态", async () => {
    const model = harness({ initialDay: TODAY });
    await model.selectDate(YESTERDAY);
    await model.load(NOW);
    model.editPrice("999");
    expect(model.manual.value).toBe(true);
    model.useReference();
    expect(model.priceText.value).toBe("555.50");
    expect(model.manual.value).toBe(false);
  });

  it("无参考价时 useReference 不改变输入", () => {
    const model = harness();
    model.editPrice("123");
    model.useReference();
    expect(model.priceText.value).toBe("123");
  });

  it("切日期时手动输入保留", async () => {
    const model = harness();
    model.editPrice("777.77");
    await model.selectDate(YESTERDAY);
    expect(model.priceText.value).toBe("777.77");
  });

  it("未手动时切日期清空价格文本", async () => {
    const model = harness();
    await model.load(NOW);
    expect(model.priceText.value).toBe("600.00");
    await model.selectDate(YESTERDAY);
    expect(model.priceText.value).toBe("");
  });
});

describe("价格解析", () => {
  it("有效价格可解析", async () => {
    const model = harness();
    model.editPrice("  555.5 ");
    expect(model.validPrice.value).toBe(555.5);
  });

  it("非法价格返回 null", async () => {
    const model = harness();
    for (const text of ["", "abc", "-1", "0", "2000000"]) {
      model.editPrice(text);
      expect(model.validPrice.value).toBeNull();
    }
  });
});

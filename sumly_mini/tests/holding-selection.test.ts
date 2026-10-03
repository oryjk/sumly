import { describe, expect, it } from "bun:test";
import { selectHoldings } from "../src/domain/holdings/selection";
import type { HoldingRecord } from "../src/types/holdings";

const T0 = 1_757_000_000_000;
const DAY = 86_400_000;
const QUOTE = 600;

function record(overrides: Partial<HoldingRecord> = {}): HoldingRecord {
  return {
    id: "11111111-1111-1111-1111-111111111111",
    grams: 10,
    unitPriceCNY: 500,
    timestamp: T0,
    note: "",
    createdAt: T0,
    brand: "",
    bookName: "默认账本",
    disposition: "holding",
    disposedAt: null,
    disposalAmount: 0,
    purchaseID: null,
    extraFee: 0,
    purchaseChannel: "",
    counterparty: "",
    assetType: "投资金条",
    purity: 1,
    laborFee: 0,
    purchaseTotalOverride: null,
    recoveryDeduction: 0,
    recoveryDiscount: 0,
    recoveryFixedFee: 0,
    alerts: [],
    ...overrides,
  };
}

const ALL = { book: "默认账本", search: "", filter: "all", sort: "newest", price: null } as const;

describe("筛选", () => {
  it("只返回指定账本的持有中记录", () => {
    const records = [
      record({ id: "11111111-1111-1111-1111-111111111111" }),
      record({ id: "22222222-2222-2222-2222-222222222222", bookName: "收藏" }),
      record({ id: "33333333-3333-3333-3333-333333333333", disposition: "sold", disposedAt: T0 + DAY }),
    ];
    const result = selectHoldings(records, ALL);
    expect(result.map((r) => r.id)).toEqual(["11111111-1111-1111-1111-111111111111"]);
  });

  it("空搜索返回全部持有记录", () => {
    const records = [
      record({ id: "11111111-1111-1111-1111-111111111111" }),
      record({ id: "22222222-2222-2222-2222-222222222222" }),
    ];
    expect(selectHoldings(records, ALL)).toHaveLength(2);
  });

  it("搜索匹配品牌（大小写与空白不敏感）", () => {
    const records = [
      record({ id: "11111111-1111-1111-1111-111111111111", brand: " Chow Tai Fook " }),
      record({ id: "22222222-2222-2222-2222-222222222222", brand: "老铺" }),
    ];
    expect(selectHoldings(records, { ...ALL, search: "chow" })).toHaveLength(1);
    expect(selectHoldings(records, { ...ALL, search: "  CHOW  " })).toHaveLength(1);
  });

  it("搜索匹配备注", () => {
    const records = [
      record({ id: "11111111-1111-1111-1111-111111111111", note: "春节买入" }),
      record({ id: "22222222-2222-2222-2222-222222222222", note: "定投" }),
    ];
    expect(selectHoldings(records, { ...ALL, search: "春节" })).toHaveLength(1);
  });

  it("空白品牌按「未知」参与搜索", () => {
    const records = [record({ id: "11111111-1111-1111-1111-111111111111", brand: "" })];
    expect(selectHoldings(records, { ...ALL, search: "未知" })).toHaveLength(1);
  });

  it("盈利筛选含零利润", () => {
    // 买入 600/g、回收规则为零，报价 600 → 到手 6000，成本 6000，利润 0
    const records = [
      record({ id: "11111111-1111-1111-1111-111111111111", unitPriceCNY: 600 }),
      record({ id: "22222222-2222-2222-2222-222222222222", unitPriceCNY: 700 }),
    ];
    const result = selectHoldings(records, { ...ALL, filter: "profit", price: QUOTE });
    expect(result.map((r) => r.unitPriceCNY)).toEqual([600]);
  });

  it("亏损筛选不含零利润", () => {
    const records = [
      record({ id: "11111111-1111-1111-1111-111111111111", unitPriceCNY: 600 }),
      record({ id: "22222222-2222-2222-2222-222222222222", unitPriceCNY: 700 }),
    ];
    const result = selectHoldings(records, { ...ALL, filter: "loss", price: QUOTE });
    expect(result.map((r) => r.unitPriceCNY)).toEqual([700]);
  });

  it("无有效报价时盈亏筛选返回空", () => {
    const records = [record()];
    expect(selectHoldings(records, { ...ALL, filter: "profit", price: null })).toHaveLength(0);
    expect(selectHoldings(records, { ...ALL, filter: "loss", price: 0 })).toHaveLength(0);
  });
});

describe("排序", () => {
  const records = [
    record({ id: "11111111-1111-1111-1111-111111111111", grams: 5, unitPriceCNY: 500, timestamp: T0 + 2 * DAY }),
    record({ id: "22222222-2222-2222-2222-222222222222", grams: 20, unitPriceCNY: 100, timestamp: T0 }),
    record({ id: "33333333-3333-3333-3333-333333333333", grams: 10, unitPriceCNY: 900, timestamp: T0 + DAY }),
  ];

  it("时间从新到旧", () => {
    const result = selectHoldings(records, { ...ALL, sort: "newest" });
    expect(result.map((r) => r.grams)).toEqual([5, 10, 20]);
  });

  it("时间从旧到新", () => {
    const result = selectHoldings(records, { ...ALL, sort: "oldest" });
    expect(result.map((r) => r.grams)).toEqual([20, 10, 5]);
  });

  it("重量从多到少，同重量按时间新到旧", () => {
    const tied = [
      record({ id: "11111111-1111-1111-1111-111111111111", grams: 10, timestamp: T0 }),
      record({ id: "22222222-2222-2222-2222-222222222222", grams: 10, timestamp: T0 + DAY }),
    ];
    expect(selectHoldings(records, { ...ALL, sort: "heaviest" }).map((r) => r.grams)).toEqual([20, 10, 5]);
    expect(selectHoldings(tied, { ...ALL, sort: "heaviest" }).map((r) => r.timestamp)).toEqual([
      T0 + DAY,
      T0,
    ]);
  });

  it("购入总价从高到低", () => {
    // 5×500=2500、20×100=2000、10×900=9000
    const result = selectHoldings(records, { ...ALL, sort: "costliest" });
    expect(result.map((r) => r.unitPriceCNY * r.grams)).toEqual([9000, 2500, 2000]);
  });
});

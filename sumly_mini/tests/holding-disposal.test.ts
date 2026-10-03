import { describe, expect, it } from "bun:test";
import { disposeHolding, totalPurchaseCost } from "../src/domain/holdings/disposal";
import { emptyDocument, type HoldingDocument, type HoldingRecord } from "../src/types/holdings";

const UUID_A = "11111111-1111-1111-1111-111111111111";
const UUID_B = "22222222-2222-2222-2222-222222222222";
const UUID_C = "33333333-3333-3333-3333-333333333333";

const T0 = 1_757_000_000_000;
const DAY = 86_400_000;

/** 计划固定样例：10g / 单价 500 / 工费 100 / 其他 20 → 总成本 5120 */
function record(overrides: Partial<HoldingRecord> = {}): HoldingRecord {
  return {
    id: UUID_A,
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
    extraFee: 20,
    purchaseChannel: "",
    counterparty: "",
    assetType: "投资金条",
    purity: 0.99,
    laborFee: 100,
    purchaseTotalOverride: null,
    recoveryDeduction: 0,
    recoveryDiscount: 0,
    recoveryFixedFee: 0,
    alerts: [],
    ...overrides,
  };
}

function doc(records: HoldingRecord[]): HoldingDocument {
  return { schemaVersion: 1, books: ["默认账本"], records };
}

describe("成本守恒", () => {
  it("计划样例：卖 4g 后剩余成本 3072、已售成本 2048", () => {
    const next = disposeHolding(doc([record()]), UUID_A, 4, 3000, "sold", T0 + DAY, "买家甲", T0 + DAY);
    const remaining = next.records.find((r) => r.id === UUID_A)!;
    const disposed = next.records.find((r) => r.disposition === "sold")!;

    expect(remaining.grams).toBeCloseTo(6, 9);
    expect(totalPurchaseCost(remaining)).toBeCloseTo(3072, 9);
    expect(totalPurchaseCost(disposed)).toBeCloseTo(2048, 9);
    // 总克数与总成本都不变
    expect(remaining.grams + disposed.grams).toBeCloseTo(10, 9);
    expect(totalPurchaseCost(remaining) + totalPurchaseCost(disposed)).toBeCloseTo(5120, 9);
  });

  it("再次拆分仍属同一购入族且总成本不变", () => {
    const first = disposeHolding(doc([record()]), UUID_A, 4, 3000, "sold", T0 + DAY, "买家甲", T0 + DAY);
    const second = disposeHolding(first, UUID_A, 2, 1500, "sold", T0 + 2 * DAY, "买家乙", T0 + 2 * DAY);

    const remaining = second.records.find((r) => r.id === UUID_A)!;
    const sold = second.records.filter((r) => r.disposition === "sold");
    const firstSold = sold.find((r) => r.grams === 4)!;
    const secondSold = sold.find((r) => r.grams === 2)!;

    // 剩余 4g，成本 4×500 + 40 + 8 = 2048
    expect(remaining.grams).toBeCloseTo(4, 9);
    expect(totalPurchaseCost(remaining)).toBeCloseTo(2048, 9);
    // 两笔处置都关联同一购入编号
    expect(firstSold.purchaseID).toBe(UUID_A);
    expect(secondSold.purchaseID).toBe(UUID_A);
    // 三份成本合计仍为 5120
    const total = [remaining, firstSold, secondSold].reduce((sum, r) => sum + totalPurchaseCost(r), 0);
    expect(total).toBeCloseTo(5120, 9);
  });

  it("实付总额按比例分摊且总额守恒", () => {
    const next = disposeHolding(doc([record({ purchaseTotalOverride: 5200 })]), UUID_A, 4, 3000, "sold", T0 + DAY, "", T0 + DAY);
    const remaining = next.records.find((r) => r.id === UUID_A)!;
    const disposed = next.records.find((r) => r.disposition === "sold")!;
    expect(remaining.purchaseTotalOverride).toBeCloseTo(3120, 9);
    expect(disposed.purchaseTotalOverride).toBeCloseTo(2080, 9);
    expect(remaining.purchaseTotalOverride! + disposed.purchaseTotalOverride!).toBeCloseTo(5200, 9);
  });

  it("回收参数原样带到处置记录，固定费不按比例分摊", () => {
    const next = disposeHolding(
      doc([record({ recoveryDeduction: 10, recoveryDiscount: 0.02, recoveryFixedFee: 30 })]),
      UUID_A, 4, 3000, "sold", T0 + DAY, "", T0 + DAY,
    );
    const disposed = next.records.find((r) => r.disposition === "sold")!;
    expect(disposed.recoveryDeduction).toBe(10);
    expect(disposed.recoveryDiscount).toBe(0.02);
    // 固定费属于整笔回收规则，不随克数切分
    expect(disposed.recoveryFixedFee).toBe(30);
  });

  it("纯度与黄金类型原样保留", () => {
    const next = disposeHolding(doc([record({ purity: 0.9999, assetType: "纪念金章" })]), UUID_A, 4, 3000, "sold", T0 + DAY, "", T0 + DAY);
    const disposed = next.records.find((r) => r.disposition === "sold")!;
    expect(disposed.purity).toBe(0.9999);
    expect(disposed.assetType).toBe("纪念金章");
  });

  it("处置记录保留原购入时间与单价", () => {
    const next = disposeHolding(doc([record()]), UUID_A, 4, 3000, "sold", T0 + DAY, "", T0 + DAY);
    const disposed = next.records.find((r) => r.disposition === "sold")!;
    expect(disposed.timestamp).toBe(T0);
    expect(disposed.unitPriceCNY).toBe(500);
    expect(disposed.disposedAt).toBe(T0 + DAY);
  });
});

describe("全额处置", () => {
  it("全部卖出时复用原记录 id，不新增记录", () => {
    const next = disposeHolding(doc([record()]), UUID_A, 10, 6000, "sold", T0 + DAY, "买家甲", T0 + DAY);
    expect(next.records).toHaveLength(1);
    const only = next.records[0];
    expect(only.id).toBe(UUID_A);
    expect(only.disposition).toBe("sold");
    expect(only.disposalAmount).toBe(6000);
  });

  it("赠送时实收记为 0", () => {
    const next = disposeHolding(doc([record()]), UUID_A, 10, 9999, "gift", T0 + DAY, "朋友", T0 + DAY);
    expect(next.records[0].disposalAmount).toBe(0);
    expect(next.records[0].counterparty).toBe("朋友");
  });
});

describe("处置约束", () => {
  const base = () => doc([record()]);

  it("克数为 0 或负数拒绝", () => {
    expect(() => disposeHolding(base(), UUID_A, 0, 0, "sold", T0 + DAY, "", T0 + DAY)).toThrow();
    expect(() => disposeHolding(base(), UUID_A, -1, 0, "sold", T0 + DAY, "", T0 + DAY)).toThrow();
  });

  it("超过剩余克数拒绝", () => {
    expect(() => disposeHolding(base(), UUID_A, 10.5, 0, "sold", T0 + DAY, "", T0 + DAY)).toThrow();
  });

  it("实收为负或非有限拒绝", () => {
    expect(() => disposeHolding(base(), UUID_A, 4, -1, "sold", T0 + DAY, "", T0 + DAY)).toThrow();
    expect(() => disposeHolding(base(), UUID_A, 4, Number.NaN, "sold", T0 + DAY, "", T0 + DAY)).toThrow();
  });

  it("非法处置类型拒绝", () => {
    expect(() => disposeHolding(base(), UUID_A, 4, 0, "lost" as never, T0 + DAY, "", T0 + DAY)).toThrow();
  });

  it("处置时间早于购入时间拒绝", () => {
    expect(() => disposeHolding(base(), UUID_A, 4, 0, "sold", T0 - DAY, "", T0 + DAY)).toThrow();
  });

  it("处置时间晚于当前时刻拒绝", () => {
    expect(() => disposeHolding(base(), UUID_A, 4, 0, "sold", T0 + 10 * DAY, "", T0 + DAY)).toThrow();
  });

  it("已处置记录不可再处置", () => {
    const sold = doc([record({ disposition: "sold", disposedAt: T0 + DAY })]);
    expect(() => disposeHolding(sold, UUID_A, 4, 0, "sold", T0 + 2 * DAY, "", T0 + 2 * DAY)).toThrow();
  });

  it("目标不存在时拒绝", () => {
    expect(() => disposeHolding(base(), UUID_C, 4, 0, "sold", T0 + DAY, "", T0 + DAY)).toThrow();
  });
});

describe("处置与提醒", () => {
  it("卖出清空自身提醒", () => {
    const withAlerts = record({
      alerts: [{ id: UUID_B, kind: "price", threshold: 600, enabled: true, basis: "international" }],
    });
    const next = disposeHolding(doc([withAlerts]), UUID_A, 10, 6000, "sold", T0 + DAY, "", T0 + DAY);
    expect(next.records[0].alerts).toEqual([]);
  });

  it("部分处置后剩余记录保留提醒", () => {
    const withAlerts = record({
      alerts: [{ id: UUID_B, kind: "price", threshold: 600, enabled: true, basis: "international" }],
    });
    const next = disposeHolding(doc([withAlerts]), UUID_A, 4, 3000, "sold", T0 + DAY, "", T0 + DAY);
    const remaining = next.records.find((r) => r.id === UUID_A)!;
    expect(remaining.alerts).toHaveLength(1);
    // 处置记录不带提醒
    const disposed = next.records.find((r) => r.disposition === "sold")!;
    expect(disposed.alerts).toEqual([]);
  });
});

describe("文档不变性", () => {
  it("不修改传入的文档", () => {
    const original = doc([record()]);
    const snapshot = JSON.stringify(original);
    disposeHolding(original, UUID_A, 4, 3000, "sold", T0 + DAY, "", T0 + DAY);
    expect(JSON.stringify(original)).toBe(snapshot);
  });

  it("其他记录不受影响", () => {
    const other = record({ id: UUID_C, grams: 5, unitPriceCNY: 480, extraFee: 0, laborFee: 0 });
    const next = disposeHolding(doc([record(), other]), UUID_A, 4, 3000, "sold", T0 + DAY, "", T0 + DAY);
    const untouched = next.records.find((r) => r.id === UUID_C)!;
    expect(untouched.grams).toBe(5);
    expect(untouched.disposition).toBe("holding");
  });

  it("赠送记录使用独立 id 且可被识别", () => {
    const next = disposeHolding(doc([record()]), UUID_A, 4, 0, "gift", T0 + DAY, "朋友", T0 + DAY);
    const disposed = next.records.find((r) => r.disposition === "gift")!;
    expect(disposed.disposition).toBe("gift");
    expect(disposed.disposalAmount).toBe(0);
  });
});

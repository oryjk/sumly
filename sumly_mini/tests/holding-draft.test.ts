import { describe, expect, it } from "bun:test";
import { createDraft, draftFromRecord, draftToRecord } from "../src/domain/holdings/draft";
import type { HoldingRecord } from "../src/types/holdings";

const UUID_A = "11111111-1111-1111-1111-111111111111";
const UUID_B = "22222222-2222-2222-2222-222222222222";
const T0 = 1_757_000_000_000;

/** 计划样例：10g、单价 500、工费 100（总额）、其他 20、纯度 99.99 */
function filled(overrides: Partial<Record<string, string>> = {}) {
  return createDraft({
    gramsText: "10",
    priceText: "500",
    laborText: "100",
    laborPerGram: false,
    otherText: "20",
    purityText: "99.99",
    ...overrides,
  });
}

describe("工费换算", () => {
  it("按克工费换算为总额", () => {
    const draft = filled({ laborText: "12", laborPerGram: true });
    expect(draft.input()?.laborFee).toBeCloseTo(120, 9);
  });

  it("总额工费直接使用", () => {
    expect(filled().input()?.laborFee).toBeCloseTo(100, 9);
  });

  it("克数变化时按克工费同步变化", () => {
    const base = createDraft({ gramsText: "10", priceText: "500", laborText: "12", laborPerGram: true });
    expect(base.input()?.laborFee).toBeCloseTo(120, 9);
    base.gramsText = "20";
    expect(base.input()?.laborFee).toBeCloseTo(240, 9);
  });
});

describe("输入校验", () => {
  it("克数为 0 或非数字时无输入", () => {
    expect(filled({ gramsText: "0" }).input()).toBeNull();
    expect(filled({ gramsText: "abc" }).input()).toBeNull();
    expect(filled({ gramsText: "-1" }).input()).toBeNull();
  });

  it("单价为 0 或非数字时无输入", () => {
    expect(filled({ priceText: "0" }).input()).toBeNull();
    expect(filled({ priceText: "" }).input()).toBeNull();
  });

  it("纯度超出 (0,100] 时无输入", () => {
    expect(filled({ purityText: "0" }).input()).toBeNull();
    expect(filled({ purityText: "101" }).input()).toBeNull();
    expect(filled({ purityText: "100" }).input()).not.toBeNull();
  });

  it("折价率必须小于 100", () => {
    expect(filled({ discountText: "100" }).input()).toBeNull();
    expect(filled({ discountText: "99.99" }).input()).not.toBeNull();
  });

  it("负数费用无输入", () => {
    expect(filled({ otherText: "-1" }).input()).toBeNull();
  });

  it("空的可选字段按 0 处理", () => {
    const draft = filled({ laborText: "", otherText: "", deductionText: "", discountText: "", fixedFeeText: "" });
    const input = draft.input();
    expect(input).not.toBeNull();
    expect(input?.laborFee).toBe(0);
    expect(input?.otherCost).toBe(0);
    expect(input?.rule.perGramDeduction).toBe(0);
  });
});

describe("总价模式", () => {
  it("总价模式使用总价作为最终成本", () => {
    const draft = filled({ costMode: "total", totalText: "5200" });
    const input = draft.input();
    expect(input?.totalCostOverride).toBe(5200);
  });

  it("仅知总价时以综合单价推算裸金价", () => {
    // 5200 − 100 − 20 = 5080；5080 / 10g = 508
    const draft = createDraft({
      gramsText: "10",
      priceText: "",
      totalText: "5200",
      laborText: "100",
      laborPerGram: false,
      otherText: "20",
      purityText: "99.99",
      costMode: "total",
    });
    expect(draft.input()?.unitPrice).toBeCloseTo(508, 6);
  });

  it("已有裸金价时保留而不被总价覆盖", () => {
    const draft = filled({ costMode: "total", totalText: "5200", priceText: "500" });
    expect(draft.input()?.unitPrice).toBe(500);
    expect(draft.input()?.totalCostOverride).toBe(5200);
  });

  it("总价模式下克数为 0 时无输入", () => {
    const draft = createDraft({
      gramsText: "0", priceText: "", totalText: "5200",
      laborText: "", otherText: "", purityText: "99.99", costMode: "total",
    });
    expect(draft.input()).toBeNull();
  });
});

describe("生成记录", () => {
  it("新建记录生成新的 id 与创建时间", () => {
    const draft = filled({ brand: " 周大福 ", channel: " 门店 ", note: " 春节买入 " });
    const record = draftToRecord(draft, null, T0 + 1000);
    expect(record.id).not.toBe(UUID_A);
    expect(record.createdAt).toBe(T0 + 1000);
    // 文本字段去除首尾空白
    expect(record.brand).toBe("周大福");
    expect(record.purchaseChannel).toBe("门店");
    expect(record.note).toBe("春节买入");
  });

  it("编辑时保留 id、创建时间与处置关联", () => {
    const existing: HoldingRecord = {
      id: UUID_A, grams: 10, unitPriceCNY: 500, timestamp: T0, note: "原备注",
      createdAt: T0 - 5000, brand: "旧品牌", bookName: "收藏", disposition: "holding",
      disposedAt: null, disposalAmount: 0, purchaseID: UUID_B, extraFee: 20,
      purchaseChannel: "", counterparty: "", assetType: "金条", purity: 0.9999,
      laborFee: 100, purchaseTotalOverride: null, recoveryDeduction: 0,
      recoveryDiscount: 0, recoveryFixedFee: 0,
      alerts: [{ id: UUID_B, kind: "price", threshold: 600, enabled: true, basis: "domestic" }],
    };
    const draft = filled({ brand: "新品牌" });
    const record = draftToRecord(draft, existing, T0);

    expect(record.id).toBe(UUID_A);
    expect(record.createdAt).toBe(T0 - 5000);
    expect(record.bookName).toBe("收藏");
    expect(record.purchaseID).toBe(UUID_B);
    expect(record.brand).toBe("新品牌");
    // 处置状态与时间不被草稿覆盖
    expect(record.disposition).toBe("holding");
  });

  it("黄金类型未知时回退为其他", () => {
    const draft = filled({ assetType: "纪念金章" });
    const record = draftToRecord(draft, null, T0);
    // 未知类型原样保留，不被强行归类
    expect(record.assetType).toBe("纪念金章");
  });

  it("编辑不影响收益输入的提醒被清空（待D1 重置基线）", () => {
    const existing: HoldingRecord = {
      id: UUID_A, grams: 10, unitPriceCNY: 500, timestamp: T0, note: "",
      createdAt: T0, brand: "", bookName: "默认账本", disposition: "holding",
      disposedAt: null, disposalAmount: 0, purchaseID: null, extraFee: 20,
      purchaseChannel: "", counterparty: "", assetType: "金条", purity: 0.9999,
      laborFee: 100, purchaseTotalOverride: null, recoveryDeduction: 0,
      recoveryDiscount: 0, recoveryFixedFee: 0,
      alerts: [{ id: UUID_B, kind: "price", threshold: 600, enabled: true, basis: "domestic" }],
    };
    const record = draftToRecord(filled(), existing, T0);
    // 收益输入未变时提醒配置保留
    expect(record.alerts).toHaveLength(1);
  });

  it("非法草稿不能生成记录", () => {
    const draft = filled({ gramsText: "0" });
    expect(() => draftToRecord(draft, null, T0)).toThrow();
  });
});

describe("回填草稿", () => {
  it("从记录读取时工费按总额处理", () => {
    const record: HoldingRecord = {
      id: UUID_A, grams: 10, unitPriceCNY: 500, timestamp: T0, note: "",
      createdAt: T0, brand: "周大福", bookName: "默认账本", disposition: "holding",
      disposedAt: null, disposalAmount: 0, purchaseID: null, extraFee: 20,
      purchaseChannel: "门店", counterparty: "", assetType: "金条", purity: 0.9999,
      laborFee: 100, purchaseTotalOverride: null, recoveryDeduction: 5,
      recoveryDiscount: 0.02, recoveryFixedFee: 30, alerts: [],
    };
    const draft = draftFromRecord(record);
    expect(draft.laborPerGram).toBe(false);
    expect(draft.purityText).toBe("99.99");
    expect(draft.discountText).toBe("2");
    expect(draft.input()?.grams).toBe(10);
  });

  it("实付总额记录回填为总价模式", () => {
    const record: HoldingRecord = {
      id: UUID_A, grams: 10, unitPriceCNY: 500, timestamp: T0, note: "",
      createdAt: T0, brand: "", bookName: "默认账本", disposition: "holding",
      disposedAt: null, disposalAmount: 0, purchaseID: null, extraFee: 0,
      purchaseChannel: "", counterparty: "", assetType: "金条", purity: 0.9999,
      laborFee: 0, purchaseTotalOverride: 5200, recoveryDeduction: 0,
      recoveryDiscount: 0, recoveryFixedFee: 0, alerts: [],
    };
    const draft = draftFromRecord(record);
    expect(draft.costMode).toBe("total");
    expect(draft.input()?.totalCostOverride).toBe(5200);
  });
});

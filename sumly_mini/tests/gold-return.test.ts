import { describe, expect, it } from "bun:test";
import {
  aggregateReturn,
  calculateReturn,
  referencePrice,
  returnInput,
  type GoldReturnInput,
} from "../src/domain/holdings/returns";
import type { HoldingRecord } from "../src/types/holdings";

/** 计划固定样例：10g/500(纯度99%)/0.99/工费100/其他20/扣减10/折价0.02/固定费30/报价600 */
const BASE: GoldReturnInput = {
  grams: 10,
  purity: 0.99,
  unitPrice: 500,
  laborFee: 100,
  otherCost: 20,
  totalCostOverride: null,
  rule: { perGramDeduction: 10, discountRate: 0.02, fixedFee: 30 },
};

describe("单笔收益", () => {
  it("固定样例：成本 5120、到手 5694.18、利润 574.18", () => {
    const result = calculateReturn(BASE, 600);
    expect(result).not.toBeNull();
    // 成本 = 10 × 500 + 100 + 20
    expect(result?.totalCost).toBeCloseTo(5120, 6);
    // 有效克数 = 10 × 0.99
    expect(result?.effectiveGrams).toBeCloseTo(9.9, 6);
    // 回收单价 = (600 − 10) × (1 − 0.02) = 578.2
    expect(result?.recoveryUnitPrice).toBeCloseTo(578.2, 6);
    // 到手 = 9.9 × 578.2 − 30 = 5694.18
    expect(result?.proceeds).toBeCloseTo(5694.18, 2);
    expect(result?.profit).toBeCloseTo(574.18, 2);
  });

  it("实付总额覆盖成本，工费与其他费用不重复叠加", () => {
    const result = calculateReturn({ ...BASE, totalCostOverride: 5200 }, 600);
    expect(result?.totalCost).toBe(5200);
  });

  it("缺报价时利润为 null，成本仍然可算", () => {
    const result = calculateReturn(BASE, null);
    expect(result).not.toBeNull();
    expect(result?.totalCost).toBeCloseTo(5120, 6);
    expect(result?.profit).toBeNull();
    expect(result?.proceeds).toBeNull();
  });

  it("非法报价（0、负数、NaN）视同缺报价", () => {
    expect(calculateReturn(BASE, 0)?.profit).toBeNull();
    expect(calculateReturn(BASE, -1)?.profit).toBeNull();
    expect(calculateReturn(BASE, Number.NaN)?.profit).toBeNull();
  });

  it("零裸金价且正实付合法，成本来自实付", () => {
    const result = calculateReturn({ ...BASE, unitPrice: 0, totalCostOverride: 1000 }, 600);
    expect(result).not.toBeNull();
    expect(result?.totalCost).toBe(1000);
  });

  it("零裸金价但有工费与其他费用时成本仍可算", () => {
    // 计算内核允许成本为正即可；「买入价需为正或有正实付」是文档层约束
    const result = calculateReturn({ ...BASE, unitPrice: 0 }, 600);
    expect(result).not.toBeNull();
    expect(result?.totalCost).toBeCloseTo(120, 6);
  });

  it("零裸金价且无任何成本时收益率无定义但结构有效", () => {
    const result = calculateReturn(
      { ...BASE, unitPrice: 0, laborFee: 0, otherCost: 0 },
      600,
    );
    expect(result).not.toBeNull();
    expect(result?.totalCost).toBe(0);
    expect(result?.profitPercent).toBeNull();
  });

  it("克数为 0 或负数拒绝", () => {
    expect(calculateReturn({ ...BASE, grams: 0 }, 600)).toBeNull();
    expect(calculateReturn({ ...BASE, grams: -1 }, 600)).toBeNull();
  });

  it("纯度超出 (0,1] 拒绝", () => {
    expect(calculateReturn({ ...BASE, purity: 0 }, 600)).toBeNull();
    expect(calculateReturn({ ...BASE, purity: 1.01 }, 600)).toBeNull();
    expect(calculateReturn({ ...BASE, purity: 1 }, 600)).not.toBeNull();
  });

  it("折价率必须小于 1", () => {
    expect(calculateReturn({ ...BASE, rule: { ...BASE.rule, discountRate: 1 } }, 600)).toBeNull();
    expect(calculateReturn({ ...BASE, rule: { ...BASE.rule, discountRate: 0.99 } }, 600)).not.toBeNull();
  });

  it("非有限输入拒绝", () => {
    expect(calculateReturn({ ...BASE, grams: Number.NaN }, 600)).toBeNull();
    expect(calculateReturn({ ...BASE, unitPrice: Number.POSITIVE_INFINITY }, 600)).toBeNull();
  });

  it("到手有零下限：报价极低时不出现负数", () => {
    const result = calculateReturn(BASE, 1);
    expect(result?.proceeds).toBe(0);
    expect(result?.profit).toBeCloseTo(-5120, 6);
  });

  it("零成本时收益率为 null", () => {
    const result = calculateReturn({ ...BASE, laborFee: 0, otherCost: 0, unitPrice: 0, totalCostOverride: 0 }, 600);
    expect(result?.profitPercent).toBeNull();
  });

  it("负成本不可由负实付构造", () => {
    expect(calculateReturn({ ...BASE, totalCostOverride: -1 }, 600)).toBeNull();
  });
});

describe("保本反推", () => {
  it("反推价格使到手恰等于成本", () => {
    const breakEven = referencePrice(BASE, 5120);
    expect(breakEven).not.toBeNull();
    const checked = calculateReturn(BASE, breakEven);
    expect(checked?.proceeds).toBeCloseTo(5120, 6);
  });

  it("目标到手为 0 时价格为 0 即满足下限", () => {
    expect(referencePrice(BASE, 0)).toBe(0);
  });

  it("负目标拒绝", () => {
    expect(referencePrice(BASE, -1)).toBeNull();
  });

  it("非法输入拒绝", () => {
    expect(referencePrice({ ...BASE, grams: 0 }, 1000)).toBeNull();
  });
});

describe("组合收益", () => {
  const second: GoldReturnInput = {
    grams: 5,
    purity: 0.99,
    unitPrice: 480,
    laborFee: 0,
    otherCost: 0,
    totalCostOverride: null,
    rule: { perGramDeduction: 0, discountRate: 0, fixedFee: 0 },
  };

  it("总克数与总成本为各笔之和", () => {
    const result = aggregateReturn([BASE, second], 600);
    expect(result?.grams).toBeCloseTo(15, 6);
    expect(result?.totalCost).toBeCloseTo(5120 + 2400, 6);
  });

  it("异质回收规则下保本需二分，不能用单笔均值", () => {
    const result = aggregateReturn([BASE, second], 600);
    const breakEven = result?.breakEvenPrice;
    expect(breakEven).not.toBeNull();
    // 保本价下组合到手应约等于总成本
    const atBreakEven = aggregateReturn([BASE, second], breakEven ?? 0);
    expect(atBreakEven?.proceeds).toBeCloseTo(5120 + 2400, 4);
  });

  it("无报价时保本仍可算，收益为 null", () => {
    const result = aggregateReturn([BASE, second], null);
    expect(result?.breakEvenPrice).not.toBeNull();
    expect(result?.profit).toBeNull();
    expect(result?.totalCost).toBeCloseTo(7520, 6);
  });

  it("提供前一日价格时计算今日价格变化影响", () => {
    // 当前 600、前一日 590：价格上涨，今日变化为正
    const up = aggregateReturn([BASE, second], 600, 590);
    expect(up?.todayChange).not.toBeNull();
    expect(up!.todayChange!).toBeGreaterThan(0);

    // 当前 600、前一日 610：价格下跌，今日变化为负
    const down = aggregateReturn([BASE, second], 600, 610);
    expect(down?.todayChange!).toBeLessThan(0);

    // 两次价格相同时变化为零
    expect(aggregateReturn([BASE, second], 600, 600)?.todayChange).toBe(0);
  });

  it("前一日价格非法时今日变化为 null", () => {
    expect(aggregateReturn([BASE, second], 600, 0)?.todayChange).toBeNull();
    expect(aggregateReturn([BASE, second], 600, -1)?.todayChange).toBeNull();
  });

  it("无前一日价格时今日变化为 null", () => {
    expect(aggregateReturn([BASE, second], 600)?.todayChange).toBeNull();
  });

  it("任一笔非法则整体为 null", () => {
    expect(aggregateReturn([BASE, { ...second, grams: 0 }], 600)).toBeNull();
  });

  it("空组合为 null", () => {
    expect(aggregateReturn([], 600)).toBeNull();
  });
});

describe("从记录构造输入", () => {
  const record: HoldingRecord = {
    id: "11111111-1111-1111-1111-111111111111",
    grams: 10,
    unitPriceCNY: 500,
    timestamp: 1_757_000_000_000,
    note: "",
    createdAt: 1_757_000_000_000,
    brand: "周大福",
    bookName: "默认账本",
    disposition: "holding",
    disposedAt: null,
    disposalAmount: 0,
    purchaseID: null,
    extraFee: 20,
    purchaseChannel: "品牌门店",
    counterparty: "",
    assetType: "投资金条",
    purity: 0.99,
    laborFee: 100,
    purchaseTotalOverride: null,
    recoveryDeduction: 10,
    recoveryDiscount: 0.02,
    recoveryFixedFee: 30,
    alerts: [],
  };

  it("字段映射到收益输入", () => {
    const input = returnInput(record);
    expect(input.grams).toBe(10);
    expect(input.purity).toBe(0.99);
    expect(input.unitPrice).toBe(500);
    expect(input.laborFee).toBe(100);
    expect(input.otherCost).toBe(20);
    expect(input.totalCostOverride).toBeNull();
    expect(input.rule).toEqual({ perGramDeduction: 10, discountRate: 0.02, fixedFee: 30 });
  });

  it("实付总额作为最终成本", () => {
    const input = returnInput({ ...record, purchaseTotalOverride: 5200 });
    expect(input.totalCostOverride).toBe(5200);
    expect(calculateReturn(input, 600)?.totalCost).toBe(5200);
  });
});

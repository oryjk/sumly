import { describe, expect, it } from "bun:test";
import { estimateBreakdown, saleBreakdown, type GoldProfitBreakdown } from "../src/domain/holdings/breakdown";
import { compareCents, addCents, moneyCents } from "../src/utils/moneyCents";
import type { GoldReturnInput } from "../src/domain/holdings/returns";

/** 零回收规则，等价于 Swift 的 GoldReturnInput(grams:unitPrice:)。 */
const ZERO_RULE = { perGramDeduction: 0, discountRate: 0, fixedFee: 0 };

/** 计划固定样例：49478 分的详细费用拆解。 */
const DETAILED: GoldReturnInput = {
  grams: 10,
  purity: 0.99,
  unitPrice: 800,
  laborFee: 100,
  otherCost: 20,
  totalCostOverride: null,
  rule: { perGramDeduction: 10, discountRate: 0.02, fixedFee: 20 },
};

function sumCents(breakdown: GoldProfitBreakdown): bigint {
  return breakdown.components.reduce((sum, c) => sum + BigInt(c.cents), 0n);
}

describe("分值换算", () => {
  it("常规两位小数", () => {
    expect(moneyCents(12.34)).toBe("1234");
    expect(moneyCents(0)).toBe("0");
    expect(moneyCents(-12.34)).toBe("-1234");
  });

  it("半偶舍入（对齐 Foundation）", () => {
    // 0.125 元 = 12.5 分 -> 12（偶数优先）
    expect(moneyCents(0.125)).toBe("12");
    expect(moneyCents(-0.125)).toBe("-12");
    // 0.135 -> 13.5 分 -> 14
    expect(moneyCents(0.135)).toBe("14");
  });

  it("非有限值返回 null", () => {
    expect(moneyCents(Number.NaN)).toBeNull();
    expect(moneyCents(Number.POSITIVE_INFINITY)).toBeNull();
  });

  it("超出 Int64 范围返回 null 而非错误展示", () => {
    expect(moneyCents(1e30)).toBeNull();
    expect(moneyCents(-1e30)).toBeNull();
  });

  it("大额但仍在 Int64 内", () => {
    // 注意：double 无法精确表示 ...58.07，边界附近应被拒绝而非给出错误金额
    expect(moneyCents(1e15)).toBe("100000000000000000");
    expect(moneyCents(123456789.25)).toBe("12345678925");
  });

  it("Int64 边界附近被拒绝而非错误展示", () => {
    // 该值在 double 中已溢出为 ...760，超出 Int64 上界
    expect(moneyCents(92233720368547758.07)).toBeNull();
  });
});

describe("分值运算", () => {
  it("加法不丢精度", () => {
    expect(addCents("9223372036854775807", "1")).toBe("9223372036854775808");
  });

  it("加法处理负数", () => {
    expect(addCents("-100", "50")).toBe("-50");
  });

  it("比较", () => {
    expect(compareCents("100", "200")).toBe(-1);
    expect(compareCents("200", "100")).toBe(1);
    expect(compareCents("100", "100")).toBe(0);
  });
});

describe("详细费用拆解", () => {
  const result = estimateBreakdown([DETAILED], 900)!;

  it("计划样例：每个分项金额正确", () => {
    expect(result.amountFor("price")).toBeCloseTo(1000, 6);
    expect(result.amountFor("purity")).toBeCloseTo(-90, 6);
    expect(result.amountFor("labor")).toBeCloseTo(-100, 6);
    expect(result.amountFor("other")).toBeCloseTo(-20, 6);
    expect(result.amountFor("deduction")).toBeCloseTo(-99, 6);
    expect(result.amountFor("discount")).toBeCloseTo(-176.22, 2);
    expect(result.amountFor("fixed")).toBeCloseTo(-20, 6);
  });

  it("总盈亏为 49478 分", () => {
    expect(result.profitCents).toBe("49478");
  });

  it("分项之和精确等于总盈亏", () => {
    expect(sumCents(result)).toBe(BigInt(result.profitCents));
  });

  it("成本与金值正确", () => {
    expect(result.totalCost).toBeCloseTo(8120, 6);
    expect(result.goldValue).toBeCloseTo(8910, 6);
  });
});

describe("累计边界舍入", () => {
  it("半分样例：买入 899.875 得 12 分", () => {
    const result = estimateBreakdown(
      [{ ...DETAILED, grams: 1, unitPrice: 899.875, purity: 1, laborFee: 0, otherCost: 0, rule: ZERO_RULE }],
      900,
    )!;
    expect(result.profitCents).toBe("12");
    expect(sumCents(result)).toBe(12n);
  });

  it("半分样例：买入 900.125 得 -12 分", () => {
    const result = estimateBreakdown(
      [{ ...DETAILED, grams: 1, unitPrice: 900.125, purity: 1, laborFee: 0, otherCost: 0, rule: ZERO_RULE }],
      900,
    )!;
    expect(result.profitCents).toBe("-12");
    expect(sumCents(result)).toBe(-12n);
  });

  it("多分位组合仍精确对账", () => {
    const inputs: GoldReturnInput[] = Array.from({ length: 40 }, (_, index) => ({
      grams: 1.2345 + index / 1000,
      purity: 0.9999,
      unitPrice: 812.34 + index,
      laborFee: 12.345,
      otherCost: 0.005,
      totalCostOverride: null,
      rule: { perGramDeduction: 7.23, discountRate: 0.0123, fixedFee: 1.235 },
    }));
    const result = estimateBreakdown(inputs, 923.456)!;
    for (const component of result.components) {
      // 每项的贡献之和必须等于该项金额
      const contributionSum = component.contributions.reduce((sum, c) => sum + BigInt(c.cents), 0n);
      expect(contributionSum).toBe(BigInt(component.cents));
    }
    expect(sumCents(result)).toBe(BigInt(result.profitCents));
  });

  it("十进制边界与展示一致", () => {
    for (const delta of [0.575, 0.125, 0.135, 1.005, -0.575, -0.125, -1.005, 12.3456]) {
      const input: GoldReturnInput = {
        ...DETAILED,
        grams: 1,
        purity: 1,
        unitPrice: 0,
        totalCostOverride: 900 - delta,
        rule: ZERO_RULE,
      };
      const result = estimateBreakdown([input], 900)!;
      expect(sumCents(result)).toBe(BigInt(result.profitCents));
    }
  });
});

describe("贡献下钻", () => {
  it("同名记录按索引区分，抵消后仍可查", () => {
    const inputs: GoldReturnInput[] = [
      { ...DETAILED, grams: 1, purity: 1, unitPrice: 800, laborFee: 10, otherCost: 0, rule: ZERO_RULE },
      { ...DETAILED, grams: 1, purity: 1, unitPrice: 1000, laborFee: 0, otherCost: 0, rule: ZERO_RULE },
    ];
    const result = estimateBreakdown(inputs, 900)!;
    const price = result.components.find((c) => c.kind === "price")!;
    expect(price.cents).toBe("0");
    expect(price.contributions.map((c) => c.recordIndex)).toEqual([0, 1]);
    expect(price.contributions.map((c) => c.cents)).toEqual(["10000", "-10000"]);
    expect(result.profitCents).toBe("-1000");
  });

  it("手动总价记录的贡献仍挂在自身记录上", () => {
    const inputs: GoldReturnInput[] = [
      { ...DETAILED, grams: 1, purity: 1, unitPrice: 800, laborFee: 10, otherCost: 0, rule: ZERO_RULE },
      { ...DETAILED, grams: 1, purity: 1, unitPrice: 100, laborFee: 20, otherCost: 30, totalCostOverride: 950, rule: ZERO_RULE },
    ];
    const result = estimateBreakdown(inputs, 900)!;
    for (const component of result.components) {
      const expected = component.kind === "unitemized" ? [1] : [0];
      expect(component.contributions.map((c) => c.recordIndex)).toEqual(expected);
    }
    expect(result.amountFor("unitemized")).toBeCloseTo(-50, 6);
    expect(result.amountFor("labor")).toBeCloseTo(-10, 6);
  });
});

describe("手动总价", () => {
  it("只列未分项项，不虚构成本归因", () => {
    const input: GoldReturnInput = {
      ...DETAILED, grams: 10, purity: 1, unitPrice: 300, laborFee: 100, otherCost: 20, totalCostOverride: 8500,
      rule: ZERO_RULE,
    };
    const result = estimateBreakdown([input], 900)!;
    expect(result.components.map((c) => c.kind)).toEqual(["unitemized"]);
    expect(result.profitCents).toBe("50000");
    expect(result.hasUnitemizedCost).toBe(true);
    expect(result.hasUnconfiguredRecovery).toBe(true);
  });

  it("工费不重复计入总投入", () => {
    const withFee: GoldReturnInput = {
      ...DETAILED, grams: 10, purity: 1, unitPrice: 300, laborFee: 100, otherCost: 20, totalCostOverride: 8500,
      rule: ZERO_RULE,
    };
    // 总成本就是实付 8500，不再叠加工费与其他费用
    expect(estimateBreakdown([withFee], 900)!.totalCost).toBe(8500);
  });
});

describe("回收零下限", () => {
  it("扣减超过金价时不出现负数", () => {
    for (const rule of [
      { perGramDeduction: 1000, discountRate: 0.5, fixedFee: 500 },
      { perGramDeduction: 5, discountRate: 0.2, fixedFee: 10000 },
    ]) {
      const result = estimateBreakdown([{ ...DETAILED, grams: 1, purity: 1, unitPrice: 800, laborFee: 0, otherCost: 0, rule }], 900)!;
      expect(result.profitCents).toBe("-80000");
      expect(sumCents(result)).toBe(-80000n);
    }
  });

  it("固定费用贡献按每笔独立估算", () => {
    const input: GoldReturnInput = {
      ...DETAILED, grams: 1, purity: 1, unitPrice: 800, laborFee: 0, otherCost: 0,
      rule: { perGramDeduction: 5, discountRate: 0.2, fixedFee: 10000 },
    };
    const result = estimateBreakdown([input, input], 900)!;
    const fixed = result.components.find((c) => c.kind === "fixed")!;
    expect(fixed.contributions.map((c) => c.cents)).toEqual(["-71600", "-71600"]);
  });
});

describe("缺报价与非法输入", () => {
  it("缺报价或非法报价不产生零盈亏", () => {
    for (const price of [null, Number.NaN, 0, Number.POSITIVE_INFINITY]) {
      expect(estimateBreakdown([{ ...DETAILED, grams: 10, purity: 1, unitPrice: 800, laborFee: 0, otherCost: 0, rule: ZERO_RULE }], price as number | null)).toBeNull();
    }
  });

  it("空输入或非法输入返回 null", () => {
    expect(estimateBreakdown([], 900)).toBeNull();
    expect(estimateBreakdown([{ ...DETAILED, grams: -1, purity: 1, unitPrice: 800, laborFee: 0, otherCost: 0, rule: ZERO_RULE }], 900)).toBeNull();
  });
});

describe("卖出拆解", () => {
  it("只用实际实收，不做市场归因", () => {
    const result = saleBreakdown(8120, 9000)!;
    expect(result.components.map((c) => c.kind)).toEqual(["sale"]);
    expect(result.profitCents).toBe("88000");
    expect(result.hasUnconfiguredRecovery).toBe(false);
    expect(result.goldValue).toBeNull();
  });

  it("保本时进入无盈亏分组", () => {
    const result = saleBreakdown(800, 800)!;
    expect(result.profitCents).toBe("0");
    expect(result.groups.map((g) => g.direction)).toEqual(["unchanged"]);
  });

  it("非法金额返回 null", () => {
    expect(saleBreakdown(Number.POSITIVE_INFINITY, 9)).toBeNull();
    expect(saleBreakdown(-1, 9)).toBeNull();
    expect(saleBreakdown(0, 1e30)).toBeNull();
  });
});

describe("来源分组", () => {
  it("组合拆解分组解释展示金额且不改变盈亏", () => {
    const manual: GoldReturnInput = {
      ...DETAILED, grams: 10, purity: 1, unitPrice: 800, laborFee: 0, otherCost: 0, totalCostOverride: 9500,
      rule: ZERO_RULE,
    };
    // detailed 保持 App 样例的 99.99 纯度与非零回收规则
    // manual 保持 App 样例的默认纯度 1
    const result = estimateBreakdown([DETAILED, { ...manual, purity: 1 }], 942.27)!;
    expect(result.groups.map((g) => g.direction)).toEqual(["increase", "decrease"]);
    expect(result.groups[0].totalCents).toBe("142270");
    expect(result.groups[1].totalCents).toBe("-59512");
    expect(result.groups[1].components.some((c) => c.kind === "unitemized")).toBe(true);
    // 分组不重不漏
    expect(result.groups.flatMap((g) => g.components).length).toBe(result.components.length);
    // 分组合计仍等于总盈亏
    const groupSum = result.groups.reduce((sum, g) => sum + BigInt(g.totalCents), 0n);
    expect(groupSum).toBe(BigInt(result.profitCents));
  });

  it("亏损组合只进减少分组", () => {
    const result = estimateBreakdown(
      [{ ...DETAILED, grams: 10, purity: 1, unitPrice: 800, laborFee: 0, otherCost: 0, totalCostOverride: 9500, rule: ZERO_RULE }],
      900,
    )!;
    expect(result.groups.map((g) => g.direction)).toEqual(["decrease"]);
    expect(result.groups[0].totalCents).toBe("-50000");
  });

  it("大额正负相抵时分组求和仍精确", () => {
    // 一笔大幅盈利、一笔大幅亏损，合计接近持平
    const result = estimateBreakdown(
      [
        { ...DETAILED, grams: 10, purity: 1, unitPrice: 100, laborFee: 0, otherCost: 0, rule: ZERO_RULE },
        { ...DETAILED, grams: 10, purity: 1, unitPrice: 5000, laborFee: 0, otherCost: 0, rule: ZERO_RULE },
      ],
      900,
    )!;
    expect(sumCents(result)).toBe(BigInt(result.profitCents));
    // 分组合计同样精确，不因大额抵消而溢出
    const groupSum = result.groups!.reduce((sum, g) => sum + BigInt(g.totalCents), 0n);
    expect(groupSum).toBe(BigInt(result.profitCents));
  });
});

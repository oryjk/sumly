import { describe, expect, it } from "bun:test";
import { scenarioReturn, SCENARIO_STEPS } from "../src/domain/holdings/scenario";
import type { GoldReturnInput } from "../src/domain/holdings/returns";

const BASE: GoldReturnInput = {
  grams: 10,
  purity: 0.99,
  unitPrice: 500,
  laborFee: 100,
  otherCost: 20,
  totalCostOverride: null,
  rule: { perGramDeduction: 10, discountRate: 0.02, fixedFee: 30 },
};

describe("情景测算", () => {
  it("按自定义参考价计算，不改实际记录", () => {
    const result = scenarioReturn(BASE, 700);
    expect(result?.proceeds).not.toBeNull();
    // 输入对象未被修改
    expect(BASE.unitPrice).toBe(500);
    expect(BASE.grams).toBe(10);
  });

  it("快捷涨跌幅档位", () => {
    expect(SCENARIO_STEPS).toEqual([-0.1, -0.05, 0.05, 0.1]);
  });

  it("按基准价应用涨跌幅", () => {
    const base = 600;
    for (const step of SCENARIO_STEPS) {
      const price = base * (1 + step);
      const result = scenarioReturn(BASE, price);
      expect(result).not.toBeNull();
    }
  });

  it("价格单调：涨则盈亏增，跌则盈亏减", () => {
    const low = scenarioReturn(BASE, 500);
    const mid = scenarioReturn(BASE, 600);
    const high = scenarioReturn(BASE, 700);
    expect(low!.profit!).toBeLessThan(mid!.profit!);
    expect(mid!.profit!).toBeLessThan(high!.profit!);
  });

  it("缺参考价时结构有效但收益为 null", () => {
    // 与收益内核一致：缺报价不算错误，只是算不出盈亏
    for (const price of [null, 0, Number.NaN, Number.POSITIVE_INFINITY]) {
      const result = scenarioReturn(BASE, price);
      expect(result).not.toBeNull();
      expect(result?.profit).toBeNull();
      expect(result?.proceeds).toBeNull();
    }
  });

  it("非法输入返回 null", () => {
    expect(scenarioReturn({ ...BASE, grams: 0 }, 600)).toBeNull();
  });

  it("复用收益内核口径：与 calculateReturn 一致", () => {
    const result = scenarioReturn(BASE, 600);
    expect(result?.totalCost).toBeCloseTo(5120, 6);
    expect(result?.proceeds).toBeCloseTo(5694.18, 2);
  });
});

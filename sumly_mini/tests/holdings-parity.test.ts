import { describe, expect, it } from "bun:test";
import fixture from "./fixtures/holdings-parity.json";
import { aggregateReturn, calculateReturn, type GoldReturnInput } from "../src/domain/holdings/returns";

/**
 * 跨端一致性测试。
 *
 * 同一份样例也用于 Swift 端 GoldReturnCalculatorTests（见
 * sumly_ios/Tests/GoldReturnTests.swift）。若本文件失败，需要同步修正两端；
 * 不要只改期望值让它通过——那会掩盖真实的跨端差异。
 */

interface ParityCase {
  name: string;
  input: GoldReturnInput;
  referencePrice: number | null;
  expected: {
    totalCost?: number;
    effectiveGrams?: number;
    recoveryUnitPrice?: number;
    proceeds?: number | null;
    profit?: number | null;
  };
}

describe("单笔收益跨端一致", () => {
  const cases = fixture.cases as ParityCase[];

  for (const testCase of cases) {
    it(testCase.name, () => {
      const result = calculateReturn(testCase.input, testCase.referencePrice);
      const expected = testCase.expected;

      if (expected.totalCost !== undefined) {
        expect(result?.totalCost).toBeCloseTo(expected.totalCost, 2);
      }
      if (expected.effectiveGrams !== undefined) {
        expect(result?.effectiveGrams).toBeCloseTo(expected.effectiveGrams, 6);
      }
      if (expected.recoveryUnitPrice !== undefined) {
        expect(result?.recoveryUnitPrice).toBeCloseTo(expected.recoveryUnitPrice, 2);
      }
      if (expected.proceeds !== undefined) {
        if (expected.proceeds === null) {
          expect(result?.proceeds).toBeNull();
        } else {
          expect(result?.proceeds).toBeCloseTo(expected.proceeds, 2);
        }
      }
      if (expected.profit !== undefined) {
        if (expected.profit === null) {
          expect(result?.profit).toBeNull();
        } else {
          expect(result?.profit).toBeCloseTo(expected.profit, 2);
        }
      }
    });
  }

  it("样例集覆盖计划要求的全部边界", () => {
    expect(cases.length).toBeGreaterThanOrEqual(5);
    const names = cases.map((c) => c.name);
    expect(names).toContain("实付总额覆盖成本");
    expect(names).toContain("缺报价时利润为 null");
    expect(names).toContain("报价极低时到手有零下限");
  });
});

describe("组合收益跨端一致", () => {
  interface ParityPortfolio {
    name: string;
    inputs: GoldReturnInput[];
    referencePrice: number | null;
    expected: { grams?: number; totalCost?: number };
  }

  const cases = fixture.portfolio as ParityPortfolio[];

  for (const testCase of cases) {
    it(testCase.name, () => {
      const result = aggregateReturn(testCase.inputs, testCase.referencePrice);
      if (testCase.expected.grams !== undefined) {
        expect(result?.grams).toBeCloseTo(testCase.expected.grams, 6);
      }
      if (testCase.expected.totalCost !== undefined) {
        expect(result?.totalCost).toBeCloseTo(testCase.expected.totalCost, 2);
      }
    });
  }
});

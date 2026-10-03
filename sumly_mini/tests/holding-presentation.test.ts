import { describe, expect, it } from "bun:test";
import {
  formatGrams,
  formatMoney,
  formatPercent,
  formatSignedMoney,
} from "../src/domain/holdings/presentation";

describe("金额格式化", () => {
  it("隐藏时统一显示占位符", () => {
    expect(formatMoney(1234.56, true)).toBe("****");
    expect(formatMoney(null, true)).toBe("****");
  });

  it("默认保留两位小数并加千分位", () => {
    expect(formatMoney(1234.5, false)).toBe("1,234.50");
    expect(formatMoney(0, false)).toBe("0.00");
    expect(formatMoney(null, false)).toBe("--");
  });

  it("负值显示负号", () => {
    expect(formatMoney(-88.8, false)).toBe("-88.80");
  });

  it("带符号模式区分正负", () => {
    expect(formatSignedMoney(88.8, false)).toBe("+88.80");
    expect(formatSignedMoney(-88.8, false)).toBe("-88.80");
    expect(formatSignedMoney(0, false)).toBe("0.00");
  });

  it("隐藏优先于符号", () => {
    expect(formatSignedMoney(88.8, true)).toBe("****");
  });

  it("非有限值不参与展示", () => {
    expect(formatMoney(Number.NaN, false)).toBe("--");
    expect(formatMoney(Number.POSITIVE_INFINITY, false)).toBe("--");
  });

  it("百分比格式化", () => {
    expect(formatPercent(5.678, false)).toBe("+5.68%");
    expect(formatPercent(-5.678, false)).toBe("-5.68%");
    expect(formatPercent(0, false)).toBe("0.00%");
    expect(formatPercent(null, false)).toBe("--");
    expect(formatPercent(5.678, true)).toBe("****");
  });

  it("克数格式化不带货币符号", () => {
    expect(formatMoney(9.9, false, false, { unit: "g" })).toBe("9.90g");
    expect(formatGrams(9.9, false)).toBe("9.90g");
    expect(formatGrams(9.9, true)).toBe("****");
  });

  it("千分位按三位分组", () => {
    expect(formatMoney(1234567.89, false)).toBe("1,234,567.89");
    expect(formatMoney(999.99, false)).toBe("999.99");
    expect(formatMoney(1000, false)).toBe("1,000.00");
  });
});

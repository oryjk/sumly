import { describe, expect, it } from "bun:test";
import { windowStatistics } from "../src/domain/market/statistics";
import type { ChartPoint } from "../src/types/market";

const DAY = 86_400_000;

function point(time: number, price: number): ChartPoint {
  return { time, price, granularity: "daily", source: "sina" };
}

describe("窗口统计", () => {
  it("首尾取时间最早与最晚", () => {
    const result = windowStatistics([point(2 * DAY, 110), point(0, 100), point(DAY, 105)]);
    expect(result?.first?.time).toBe(0);
    expect(result?.last?.time).toBe(2 * DAY);
  });

  it("最高最低价正确", () => {
    const result = windowStatistics([point(0, 100), point(DAY, 130), point(2 * DAY, 90)]);
    expect(result?.high?.price).toBe(130);
    expect(result?.low?.price).toBe(90);
  });

  it("同价时最高最低取最早真实时间", () => {
    const result = windowStatistics([point(0, 120), point(DAY, 120), point(2 * DAY, 100)]);
    expect(result?.high?.time).toBe(0);
  });

  it("至少两个有效点才计算涨跌", () => {
    expect(windowStatistics([point(0, 100)])?.change).toBeNull();
    expect(windowStatistics([])).toBeNull();
  });

  it("涨跌额与涨跌幅按首尾计算", () => {
    const result = windowStatistics([point(0, 100), point(DAY, 110)]);
    expect(result?.change).toBeCloseTo(10, 6);
    expect(result?.percent).toBeCloseTo(10, 6);
  });

  it("非法价格不参与统计", () => {
    const result = windowStatistics([
      point(0, 100),
      point(DAY, Number.NaN),
      point(2 * DAY, 120),
    ]);
    expect(result?.last?.time).toBe(2 * DAY);
    expect(result?.change).toBeCloseTo(20, 6);
  });

  it("负价格与零价被忽略", () => {
    const result = windowStatistics([point(0, 100), point(DAY, 0), point(2 * DAY, -5), point(3 * DAY, 120)]);
    expect(result?.change).toBeCloseTo(20, 6);
  });

  it("休市日不补点，只统计真实观测", () => {
    // 三月一日到三日，只有三二日一个真实观测
    const result = windowStatistics([point(Date.UTC(2026, 2, 2), 500)]);
    expect(result?.first?.time).toBe(Date.UTC(2026, 2, 2));
    expect(result?.change).toBeNull();
  });
});

import { describe, expect, it } from "bun:test";
import { compactRealtime, sampleForDrawing } from "../src/domain/market/sampling";
import { priceScale } from "../src/domain/market/scale";
import { windowStatistics } from "../src/domain/market/statistics";
import type { ChartPoint } from "../src/types/market";

const DAY = 86_400_000;

function daily(time: number, price: number): ChartPoint {
  return { time, price, granularity: "daily", source: "sina" };
}

function realtime(time: number, price: number): ChartPoint {
  return { time, price, granularity: "realtime", source: "sina" };
}

describe("绘制抽样", () => {
  it("超过上限时按步长抽样并保留末点", () => {
    const series = Array.from({ length: 1200 }, (_, i) => daily(i * DAY, 100 + i));
    const drawn = sampleForDrawing(series, 500);
    expect(drawn.length).toBeLessThanOrEqual(501);
    expect(drawn.at(-1)?.time).toBe(series.at(-1)?.time);
    expect(drawn[0].time).toBe(series[0].time);
  });

  it("点数少于上限时原样返回", () => {
    const series = Array.from({ length: 10 }, (_, i) => daily(i * DAY, 100 + i));
    expect(sampleForDrawing(series, 500)).toHaveLength(10);
  });

  it("抽样只影响绘制，查价与统计仍按原数据", () => {
    const series = Array.from({ length: 1000 }, (_, i) => daily(i * DAY, 100 + i));
    const drawn = sampleForDrawing(series, 100);
    // 统计走原始数据，变化完整
    const full = windowStatistics(series);
    expect(full?.change).toBeCloseTo(999, 6);
    // 抽样后首尾仍在
    expect(drawn[0].price).toBe(series[0].price);
    expect(drawn.at(-1)?.price).toBe(series.at(-1)?.price);
  });
});

describe("实时压缩", () => {
  it("平坦段内部点被移除但保留两端", () => {
    const series = [realtime(0, 100), realtime(5000, 100), realtime(10_000, 100), realtime(15_000, 101)];
    const compacted = compactRealtime(series);
    expect(compacted[0].price).toBe(100);
    expect(compacted.at(-1)?.price).toBe(101);
    // 平台内部点被压缩
    expect(compacted.length).toBeLessThan(series.length);
  });

  it("长间隔两端的观测被保留", () => {
    const series = [realtime(0, 100), realtime(120_000, 100), realtime(125_000, 100), realtime(130_000, 100)];
    const compacted = compactRealtime(series);
    // 缺口边界不能被抹平，否则平台会被画成提前爬升
    expect(compacted.some((p) => p.time === 0)).toBe(true);
    expect(compacted.some((p) => p.time === 120_000)).toBe(true);
  });

  it("点数不足三个时原样返回", () => {
    const series = [realtime(0, 100), realtime(5000, 100)];
    expect(compactRealtime(series)).toHaveLength(2);
  });
});

describe("价格刻度", () => {
  it("微小波动不会被放大成整图", () => {
    // 固定微小波动：价格几乎不变，刻度不应被拉到巨大范围
    const narrow = priceScale([daily(0, 500.0), daily(DAY, 500.05)]);
    const wide = priceScale([daily(0, 100), daily(DAY, 200)]);
    const narrowSpan = narrow.max - narrow.min;
    const wideSpan = wide.max - wide.min;
    expect(narrowSpan).toBeLessThan(wideSpan);
  });

  it("刻度至少留出最小 padding", () => {
    const scale = priceScale([daily(0, 100), daily(DAY, 100)]);
    expect(scale.max).toBeGreaterThan(scale.min);
  });

  it("非法价格不参与刻度", () => {
    const scale = priceScale([daily(0, 100), daily(DAY, Number.NaN), daily(2 * DAY, 110)]);
    expect(scale.min).toBeLessThanOrEqual(100);
    expect(scale.max).toBeGreaterThanOrEqual(110);
  });

  it("空数据返回安全刻度", () => {
    const scale = priceScale([]);
    expect(Number.isFinite(scale.min)).toBe(true);
    expect(scale.max).toBeGreaterThan(scale.min);
  });
});

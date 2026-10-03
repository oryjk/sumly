import { describe, expect, it } from "bun:test";
import { moveWindow, nearestPoint, zoomWindow, type ChartWindow } from "../src/domain/market/viewport";
import type { ChartPoint } from "../src/types/market";

const DAY = 86_400_000;

/** 构造从 base 开始、间隔 stepMs、长度 count 的点序列。 */
function points(count: number, stepMs = DAY, base = 0): ChartPoint[] {
  return Array.from({ length: count }, (_, index) => ({
    time: base + index * stepMs,
    price: 100 + index,
    granularity: "daily" as const,
    source: "sina",
  }));
}

const BOUNDS: ChartWindow = { start: 0, end: 100 * DAY };
const WINDOW: ChartWindow = { start: 20 * DAY, end: 40 * DAY };

describe("缩放", () => {
  it("放大后窗口收缩且不越界", () => {
    const next = zoomWindow(BOUNDS, WINDOW, 0.5, 2);
    expect(next.end - next.start).toBeLessThan(WINDOW.end - WINDOW.start);
    expect(next.start).toBeGreaterThanOrEqual(BOUNDS.start);
    expect(next.end).toBeLessThanOrEqual(BOUNDS.end);
  });

  it("缩小不超过完整范围", () => {
    const next = zoomWindow(BOUNDS, WINDOW, 0.5, 0.1);
    expect(next.end - next.start).toBe(BOUNDS.end - BOUNDS.start);
  });

  it("非法缩放系数返回原窗口", () => {
    expect(zoomWindow(BOUNDS, WINDOW, 0.5, 0)).toEqual(WINDOW);
    expect(zoomWindow(BOUNDS, WINDOW, 0.5, -1)).toEqual(WINDOW);
    expect(zoomWindow(BOUNDS, WINDOW, Number.NaN, 2)).toEqual(WINDOW);
  });

  it("窄窗口仍可操作，不塌缩为零", () => {
    const narrow: ChartWindow = { start: 0, end: 2 * DAY };
    const next = zoomWindow(BOUNDS, narrow, 0.5, 4);
    expect(next.end - next.start).toBeGreaterThan(0);
    expect(next.end).toBeGreaterThan(next.start);
  });
});

describe("拖动", () => {
  it("按比例平移且不越界", () => {
    const next = moveWindow(BOUNDS, WINDOW, "window", 0.5);
    expect(next.end - next.start).toBe(WINDOW.end - WINDOW.start);
    expect(next.start).toBeGreaterThanOrEqual(BOUNDS.start);
    expect(next.end).toBeLessThanOrEqual(BOUNDS.end);
  });

  it("拖到边界被夹紧且不反转", () => {
    const next = moveWindow(BOUNDS, WINDOW, "window", 5);
    expect(next.start).toBeLessThanOrEqual(next.end);
    expect(next.start).toBe(BOUNDS.start);
  });

  it("非法比例返回原窗口", () => {
    expect(moveWindow(BOUNDS, WINDOW, "window", Number.NaN)).toEqual(WINDOW);
  });
});

describe("最近点匹配", () => {
  const series = points(5);

  it("取时间最近的有效点", () => {
    expect(nearestPoint(series, 2 * DAY + DAY / 2)?.time).toBe(2 * DAY);
  });

  it("超出范围取端点", () => {
    expect(nearestPoint(series, -100)?.time).toBe(0);
    expect(nearestPoint(series, 999 * DAY)?.time).toBe(4 * DAY);
  });

  it("空序列返回 null", () => {
    expect(nearestPoint([], 0)).toBeNull();
  });

  it("稀疏数据仍返回真实时间，不补点", () => {
    const sparse: ChartPoint[] = [
      { time: 0, price: 100, granularity: "daily", source: "sina" },
      { time: 5 * DAY, price: 110, granularity: "daily", source: "sina" },
    ];
    // 中间没有休市日的数据，查价应命中真实存在的点
    expect(nearestPoint(sparse, 2 * DAY)?.time).toBe(0);
    expect(nearestPoint(sparse, 4 * DAY)?.time).toBe(5 * DAY);
  });
});

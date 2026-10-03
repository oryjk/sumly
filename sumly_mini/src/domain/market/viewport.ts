/**
 * 图表视窗与查价的纯逻辑。
 * 对应 iOS 端 ChartViewport：缩放与平移都夹紧在数据范围内，
 * 窗口永不越界、永不反转；查价只命中真实存在的观测点，不补点。
 */
import type { ChartPoint } from "@/types/market";

/** 时间窗口（毫秒时间戳闭区间）。 */
export interface ChartWindow {
  start: number;
  end: number;
}

/** 一天毫秒数。 */
export const DAY_MS = 86_400_000;

/** 把窗口夹紧到边界内，宽度不变。 */
function clampWindow(window: ChartWindow, bounds: ChartWindow): ChartWindow {
  const boundsSpan = Math.max(0, bounds.end - bounds.start);
  const span = Math.min(Math.max(0, window.end - window.start), boundsSpan);
  const start = Math.min(Math.max(window.start, bounds.start), bounds.end - span);
  return { start, end: start + span };
}

/**
 * 以 anchor（0–1 的窗口内相对位置）为锚点缩放。
 * scale > 1 放大（窗口收缩），scale < 1 缩小；宽度不小于 minimumSpan。
 */
export function zoomWindow(
  bounds: ChartWindow,
  window: ChartWindow,
  anchor: number,
  scale: number,
  minimumSpan = DAY_MS,
): ChartWindow {
  if (!Number.isFinite(scale) || scale <= 0 || !Number.isFinite(anchor)) {
    return window;
  }
  const boundsSpan = bounds.end - bounds.start;
  if (boundsSpan <= 0) {
    return bounds;
  }
  const oldSpan = window.end - window.start;
  const span = Math.min(boundsSpan, Math.max(minimumSpan, oldSpan / scale));
  const position = Math.min(1, Math.max(0, anchor));
  const start = window.start + (oldSpan - span) * position;
  return clampWindow({ start, end: start + span }, bounds);
}

/**
 * 按 fraction 拖动窗口。
 * part 为 window 时整体平移；start/end 时调整对应手柄，且不越过另一端。
 * 与 Swift ChartViewport 一致：正 fraction 向历史方向（时间轴左侧）移动。
 */
export function moveWindow(
  bounds: ChartWindow,
  window: ChartWindow,
  part: "start" | "end" | "window",
  fraction: number,
): ChartWindow {
  if (!Number.isFinite(fraction)) {
    return window;
  }
  const boundsSpan = bounds.end - bounds.start;
  if (boundsSpan <= 0) {
    return bounds;
  }
  const span = window.end - window.start;
  const delta = -fraction * boundsSpan;

  if (part === "window") {
    return clampWindow({ start: window.start + delta, end: window.end + delta }, bounds);
  }

  const handleSpan = Math.min(boundsSpan, DAY_MS);
  if (part === "start") {
    // 起点手柄最多拖到终点前一最小跨度，且不越出左边界
    const limit = Math.min(window.end - handleSpan, bounds.end - handleSpan);
    const start = Math.min(limit, Math.max(bounds.start, window.start + delta));
    return clampWindow({ start, end: window.end }, bounds);
  }
  const limit = Math.max(window.start + handleSpan, bounds.start + handleSpan);
  const end = Math.max(limit, Math.min(bounds.end, window.end + delta));
  return clampWindow({ start: window.start, end }, bounds);
}

/**
 * 查找时间上最近的有效点。
 * 稀疏或休市数据不会插值，只会命中真实观测。
 */
export function nearestPoint(points: readonly ChartPoint[], time: number): ChartPoint | null {
  if (points.length === 0) return null;
  let best: ChartPoint | null = null;
  let bestDistance = Number.POSITIVE_INFINITY;
  for (const point of points) {
    if (!Number.isFinite(point.price) || point.price <= 0) continue;
    const distance = Math.abs(point.time - time);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = point;
    }
  }
  return best;
}

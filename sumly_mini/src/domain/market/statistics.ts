/**
 * 窗口统计：只依据视窗内的真实观测，与绘制抽样无关。
 * 对应 iOS 端 ChartWindowStatistics：至少两个有效点才计算涨跌，
 * 同价时最高/最低取最早的真实时间。
 */
import type { ChartPoint } from "@/types/market";

export interface ChartStatistics {
  first: ChartPoint | null;
  last: ChartPoint | null;
  high: ChartPoint | null;
  low: ChartPoint | null;
  change: number | null;
  percent: number | null;
}

const EMPTY: ChartStatistics = {
  first: null,
  last: null,
  high: null,
  low: null,
  change: null,
  percent: null,
};

/** 统计视窗内的首尾、极值与涨跌。 */
export function windowStatistics(points: readonly ChartPoint[]): ChartStatistics | null {
  let first: ChartPoint | null = null;
  let last: ChartPoint | null = null;
  let high: ChartPoint | null = null;
  let low: ChartPoint | null = null;
  let count = 0;

  for (const point of points) {
    // 非法价格不进入统计，也不参与涨跌
    if (!Number.isFinite(point.price) || point.price <= 0) continue;
    count += 1;
    if (first === null || point.time < first.time) first = point;
    if (last === null || point.time > last.time) last = point;
    if (high === null || point.price > high.price || (point.price === high.price && point.time < high.time)) {
      high = point;
    }
    if (low === null || point.price < low.price || (point.price === low.price && point.time < low.time)) {
      low = point;
    }
  }

  if (count === 0) {
    return null;
  }

  let change: number | null = null;
  let percent: number | null = null;
  if (count >= 2 && first !== null && last !== null) {
    const amount = last.price - first.price;
    const percentage = (amount / first.price) * 100;
    if (Number.isFinite(amount) && Number.isFinite(percentage)) {
      change = amount;
      percent = percentage;
    }
  }

  return { first, last, high, low, change, percent };
}

/** 数据不足时返回空统计，便于页面直接渲染而无需判空。 */
export function emptyStatistics(): ChartStatistics {
  return { ...EMPTY };
}

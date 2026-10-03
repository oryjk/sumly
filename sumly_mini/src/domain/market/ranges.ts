/**
 * 走势图时间范围。
 * 对应 App 的分段选择器：实时、近一月、近三月、今年以来、近一年、
 * 近两年、近三年、近五年、近十年、1900 年至今。
 * 窗口按各品种真实可用范围裁剪——国内没有百年数据，不合成。
 */
import type { ChartPoint } from "@/types/market";
import { DAY_MS, type ChartWindow } from "./viewport";

export type MarketRange =
  | "realtime"
  | "month"
  | "quarter"
  | "yearToDate"
  | "year"
  | "twoYears"
  | "threeYears"
  | "fiveYears"
  | "tenYears"
  | "history";

/** 分段选择器的展示顺序与文案。 */
export const MARKET_RANGES: { key: MarketRange; label: string }[] = [
  { key: "realtime", label: "实时" },
  { key: "month", label: "近一月" },
  { key: "quarter", label: "近三月" },
  { key: "yearToDate", label: "今年以来" },
  { key: "year", label: "近一年" },
  { key: "twoYears", label: "近两年" },
  { key: "threeYears", label: "近三年" },
  { key: "fiveYears", label: "近五年" },
  { key: "tenYears", label: "近十年" },
  { key: "history", label: "1900年至今" },
];

/** 范围对应的回溯时长（毫秒）；今年以来按年计算，history 为 null 表示全部。 */
const RANGE_SPAN: Record<MarketRange, number | null> = {
  realtime: null,
  month: 30 * DAY_MS,
  quarter: 91 * DAY_MS,
  yearToDate: null,
  year: 365 * DAY_MS,
  twoYears: 2 * 365 * DAY_MS,
  threeYears: 3 * 365 * DAY_MS,
  fiveYears: 5 * 365 * DAY_MS,
  tenYears: 10 * 365 * DAY_MS,
  history: null,
};

/** 数据整体时间范围，实时窗口为 null。 */
export function dataBounds(points: readonly ChartPoint[]): ChartWindow | null {
  if (points.length === 0) return null;
  let min = Number.POSITIVE_INFINITY;
  let max = Number.NEGATIVE_INFINITY;
  for (const point of points) {
    if (point.time < min) min = point.time;
    if (point.time > max) max = point.time;
  }
  return { start: min, end: max };
}

/**
 * 计算某个范围对应的视窗。
 * realtime 与 history 取全部数据；今年以来从当年 1 月 1 日起；
 * 固定时长范围按now 回溯，并与真实数据范围取交集。
 */
export function rangeWindow(
  range: MarketRange,
  points: readonly ChartPoint[],
  now: number,
): ChartWindow | null {
  const bounds = dataBounds(points);
  if (!bounds) return null;

  if (range === "realtime" || range === "history") {
    return bounds;
  }

  if (range === "yearToDate") {
    const yearStart = Date.UTC(new Date(now).getUTCFullYear(), 0, 1);
    const start = Math.max(bounds.start, yearStart);
    // 当年还没有数据时回退到真实可用起点，不补未来区间
    return start > bounds.end ? bounds : { start, end: bounds.end };
  }

  const span = RANGE_SPAN[range];
  if (span === null) return bounds;

  const start = Math.max(bounds.start, now - span);
  return start > bounds.end ? bounds : { start, end: bounds.end };
}

/** 当前范围是否为按日粒度绘制（决定抽样策略）。 */
export function isDailyRange(range: MarketRange): boolean {
  return range !== "realtime";
}

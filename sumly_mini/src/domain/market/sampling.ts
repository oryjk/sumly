/**
 * 绘制抽样：只影响画面，不改变查价与统计使用的原始数据。
 * 对应 iOS 端 ChartOverviewSampling 与 RealtimeChartCompaction。
 */
import type { ChartPoint } from "@/types/market";

/** 日线绘制的目标点数上限。 */
export const DAILY_DRAW_LIMIT = 500;

/** 缺口判定阈值（毫秒）：五秒采样与真实分钟回退都在此范围内。 */
const MAX_RUN_GAP_MS = 60_000;

/**
 * 实时窗口压缩：移除平坦段的内部点，但保留每个水平段的两端。
 * 抹掉平台末端会把平台画成提前爬升；抹掉缺口边界会拉长下一段价格变化。
 */
export function compactRealtime(samples: readonly ChartPoint[]): ChartPoint[] {
  if (samples.length <= 2) {
    return [...samples];
  }
  const result: ChartPoint[] = [samples[0]];
  for (let index = 1; index < samples.length - 1; index += 1) {
    const previous = samples[index - 1];
    const point = samples[index];
    const next = samples[index + 1];
    const before = point.time - previous.time;
    const after = next.time - point.time;
    const isFlat =
      point.price === previous.price &&
      point.price === next.price &&
      point.granularity === "realtime" &&
      previous.granularity === "realtime" &&
      next.granularity === "realtime";
    // 缺口两端的观测必须保留
    const insideShortGap = before > 0 && before <= MAX_RUN_GAP_MS && after > 0 && after <= MAX_RUN_GAP_MS;
    if (!(isFlat && insideShortGap)) {
      result.push(point);
    }
  }
  result.push(samples[samples.length - 1]);
  return result;
}

/**
 * 按上限抽样绘制。始终保留首尾，末点若未被步长命中则补入，
 * 避免最后一段价格变化被丢掉。
 */
export function sampleForDrawing(points: readonly ChartPoint[], maxPoints: number): ChartPoint[] {
  if (maxPoints <= 0 || points.length <= maxPoints) {
    return [...points];
  }
  // ceil 保证步长足够大，最终点数不超过 maxPoints + 1（末点可能额外补入）
  const step = Math.ceil(points.length / maxPoints);
  const result: ChartPoint[] = [];
  for (let index = 0; index < points.length; index += step) {
    result.push(points[index]);
  }
  const last = points[points.length - 1];
  if (result[result.length - 1] !== last) {
    result.push(last);
  }
  return result;
}

/** 实时窗口走压缩，日线走步长抽样。 */
export function pointsForDrawing(points: readonly ChartPoint[], daily: boolean): ChartPoint[] {
  if (daily) {
    return sampleForDrawing(points, DAILY_DRAW_LIMIT);
  }
  return compactRealtime(points);
}

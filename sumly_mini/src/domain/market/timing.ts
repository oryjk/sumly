/**
 * 实时窗口状态判定。
 * 规则与 iOS 端 RealtimeChartTiming.state 一致：
 * 样本容差取 max(20 秒, 采样周期 × 2)；报价超过 180 秒同样视为暂停。
 */
import { QUOTE_STALE_SECONDS, type RealtimeState } from "@/types/market";

/** 样本容差下限（秒）。 */
const MIN_SAMPLE_TOLERANCE_SECONDS = 20;

/**
 * 判定实时窗口状态。
 * @param sampleMs 最后样本时间戳，无样本为 null
 * @param quoteMs 最后报价时间戳，无报价为 null
 * @param intervalSeconds 采样周期（5 或 60）
 * @param nowMs 当前时间戳
 */
export function realtimeState(
  sampleMs: number | null,
  quoteMs: number | null,
  intervalSeconds: number,
  nowMs: number,
): RealtimeState {
  if (sampleMs === null || !Number.isFinite(sampleMs)) {
    return "empty";
  }
  const toleranceMs = Math.max(MIN_SAMPLE_TOLERANCE_SECONDS, intervalSeconds * 2) * 1000;
  if (nowMs - sampleMs > toleranceMs) {
    return "paused";
  }
  if (quoteMs !== null && Number.isFinite(quoteMs) && nowMs - quoteMs > QUOTE_STALE_SECONDS * 1000) {
    return "paused";
  }
  return "live";
}

/** 状态对应的窗口说明文案。 */
export function realtimeCaption(state: RealtimeState): string {
  switch (state) {
    case "live":
      return "最近 20 分钟";
    case "paused":
      return "更新暂停 · 最近可用 20 分钟";
    default:
      return "暂无实时走势";
  }
}

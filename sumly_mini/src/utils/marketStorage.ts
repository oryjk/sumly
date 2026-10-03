/**
 * 行情缓存持久化。
 * 按品种分别保存 points/cursor/unit/series；写入失败必须抛给调用方，
 * 由store 决定是否推进游标，不在这里静默吞掉错误。
 */
import type { MarketSeries } from "@/types/market";
import type { MarketCache } from "@/domain/market/sync";

const PREFIX = "sumly:market:";

/** 缓存读写键。 */
function storageKey(series: MarketSeries): string {
  return `${PREFIX}${series}`;
}

/** 读取指定品种的缓存；不存在或损坏时返回 null。 */
export function loadMarketCache(series: MarketSeries): MarketCache | null {
  try {
    const raw = uni.getStorageSync(storageKey(series));
    if (!raw || typeof raw !== "string") return null;
    const parsed = JSON.parse(raw) as MarketCache;
    if (!parsed || !Array.isArray(parsed.points) || typeof parsed.cursor !== "string") {
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
}

/** 保存缓存；失败时抛错，调用方不得据此推进游标。 */
export function saveMarketCache(series: MarketSeries, cache: MarketCache): void {
  uni.setStorageSync(storageKey(series), JSON.stringify(cache));
}

/** 清除全部行情缓存，不影响持仓数据。 */
export function clearMarketCaches(): void {
  for (const series of ["au9999", "xauusd"] as MarketSeries[]) {
    try {
      uni.removeStorageSync(storageKey(series));
    } catch {
      // 缓存清理失败不应阻断业务流程
    }
  }
}

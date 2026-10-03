/**
 * 行情增量同步：校验服务端快照并合并到本地缓存。
 * 校验规则与 iOS 端 MarketSyncService.MarketSyncPage.validate 保持一致，
 * 缓存中不保留 deleted 墓碑。
 */
import type { MarketSeries, MarketSyncPage, MarketSyncPoint, MarketUnit } from "@/types/market";

/** 本地历史缓存。 */
export interface MarketCache {
  series: MarketSeries;
  unit: MarketUnit;
  cursor: string;
  points: MarketSyncPoint[];
}

/** 记录唯一键，与 Swift 的 granularity.rawValue + ":" + date 一致。 */
export function pointKey(point: MarketSyncPoint): string {
  return `${point.granularity}:${point.date}`;
}

/** 品种对应的期望单位。 */
export function expectedUnit(series: MarketSeries): MarketUnit {
  return series === "au9999" ? "CNY/g" : "USD/troy_oz";
}

/**
 * 严格解析 YYYY-MM-DD 并校验是真实存在的日历日。
 * 用 UTC 构造避免本地时区把日期漂移到前一天。
 */
function isValidDateKey(date: string): boolean {
  if (date.length !== 10) return false;
  const parts = date.split("-");
  if (parts.length !== 3) return false;
  const [y, m, d] = parts.map((part) => Number(part));
  if (!Number.isInteger(y) || !Number.isInteger(m) || !Number.isInteger(d)) return false;
  if (m < 1 || m > 12 || d < 1 || d > 31) return false;
  const utc = new Date(Date.UTC(y, m - 1, d));
  // 反向核对可排除 2 月 30 日这类溢出日期
  return utc.getUTCFullYear() === y && utc.getUTCMonth() === m - 1 && utc.getUTCDate() === d;
}

/** 年度记录只用于国际品种，范围 1900–2015。 */
function isAllowedAnnual(series: string, date: string): boolean {
  if (series !== "xauusd") return false;
  const year = Number(date.slice(0, 4));
  return year >= 1900 && year <= 2015;
}

/**
 * 校验一页同步数据是否可用于指定品种。
 * 任何不合规都拒绝整页，避免把脏数据写入缓存。
 */
export function validateSyncPage(page: MarketSyncPage, requested: MarketSeries): void {
  if (page.series !== requested) {
    throw new Error("行情品种错配");
  }
  if (page.unit !== expectedUnit(requested)) {
    throw new Error("行情单位与品种不匹配");
  }
  if (!page.cursor || page.cursor.length > 160) {
    throw new Error("行情游标无效");
  }

  const keys = new Set<string>();
  for (const point of page.points) {
    if (!isValidDateKey(point.date)) {
      throw new Error(`行情日期键非法：${point.date}`);
    }
    if (point.granularity === ("realtime" as never)) {
      throw new Error("历史同步不接受实时粒度");
    }
    if (point.granularity === "annual" && !isAllowedAnnual(page.series, point.date)) {
      throw new Error(`年度记录范围非法：${point.date}`);
    }
    if (!point.source) {
      throw new Error("行情来源为空");
    }
    const key = pointKey(point);
    if (keys.has(key)) {
      throw new Error(`行情记录重复：${key}`);
    }
    keys.add(key);

    if (!point.deleted) {
      const prices = [point.open, point.high, point.low, point.close];
      if (!prices.every((value) => Number.isFinite(value) && value > 0)) {
        throw new Error(`行情价格非法：${key}`);
      }
    }
  }
}

/** 按 granularity+date 建立索引，年度在前、日线按日期升序。 */
function sortPoints(points: Map<string, MarketSyncPoint>): MarketSyncPoint[] {
  return [...points.values()].sort((a, b) => {
    if (a.granularity !== b.granularity) {
      return a.granularity === "annual" ? -1 : 1;
    }
    return a.date < b.date ? -1 : a.date > b.date ? 1 : 0;
  });
}

/**
 * 把一页增量合并进已有缓存。
 * reset 时替换整个快照；否则按 granularity+date 覆盖合并，
 * 墓碑记录直接移除。空增量仍推进 cursor。
 */
export function mergeMarketSync(previous: MarketCache | null, page: MarketSyncPage): MarketCache {
  const series = (page.series ?? previous?.series) as MarketSeries;
  validateSyncPage(page, series);

  if (page.reset || !previous) {
    const next = new Map<string, MarketSyncPoint>();
    for (const point of page.points) {
      if (!point.deleted) next.set(pointKey(point), { ...point, deleted: false });
    }
    return { series, unit: page.unit as MarketUnit, cursor: page.cursor, points: sortPoints(next) };
  }

  const next = new Map<string, MarketSyncPoint>();
  for (const point of previous.points) {
    next.set(pointKey(point), point);
  }
  for (const point of page.points) {
    const key = pointKey(point);
    if (point.deleted) {
      next.delete(key);
    } else {
      next.set(key, { ...point, deleted: false });
    }
  }
  return { series, unit: page.unit as MarketUnit, cursor: page.cursor, points: sortPoints(next) };
}

/**
 * 历史价格折算为人民币元/克。
 * 国内 Au99.99 已是 CNY/g 原值；国际 xauusd 按 USD × usd_cny ÷ 31.1034768
 * 折算，使用当前有效汇率——这不是历史人民币成交价，展示需明确标注。
 */
import { GRAMS_PER_TROY_OUNCE, type ChartPoint, type GoldQuote } from "@/types/market";
import type { MarketCache } from "./sync";

/** 汇率是否可用于折算。 */
function hasValidRate(quote: GoldQuote | null): quote is GoldQuote {
  return quote !== null && Number.isFinite(quote.usd_cny) && quote.usd_cny > 0;
}

/** 把 YYYY-MM-DD 严格解析为 UTC 时间戳，避免跨端日期漂移。 */
export function parseDateKey(date: string): number {
  return Date.UTC(
    Number(date.slice(0, 4)),
    Number(date.slice(5, 7)) - 1,
    Number(date.slice(8, 10)),
  );
}

/**
 * 把缓存的历史点折算为图表点。
 * 国内直接取收盘价；国际需有效汇率，否则返回空数组。
 */
export function toCnyPoints(cache: MarketCache, quote: GoldQuote | null): ChartPoint[] {
  if (cache.points.length === 0) {
    return [];
  }
  if (cache.series === "au9999") {
    return cache.points.map((point) => ({
      time: parseDateKey(point.date),
      price: point.close,
      granularity: point.granularity,
      source: point.source,
    }));
  }
  if (!hasValidRate(quote)) {
    return [];
  }
  const rate = quote.usd_cny / GRAMS_PER_TROY_OUNCE;
  return cache.points.map((point) => ({
    time: parseDateKey(point.date),
    price: point.close * rate,
    granularity: point.granularity,
    source: point.source,
  }));
}

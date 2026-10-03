/**
 * 行情类型定义。
 * DTO 字段按 sumly_go OpenAPI 的原始 snake_case 声明，
 * 不在传输层改���，避免与后端契约漂移。
 */

/** 行情口径：国内 Au99.99 / 国际伦敦金。 */
export type MarketBasis = "domestic" | "international";

/** 历史序列品种，与后端 sync 的 series 取值一致。 */
export type MarketSeries = "au9999" | "xauusd";

/** 原始单位：国内元/克，国际美元/金衡盎司。 */
export type MarketUnit = "CNY/g" | "USD/troy_oz";

/** 金衡盎司换算：1 盎司 = 31.1034768 克（与后端 domain.GramsPerTroyOunce 一致）。 */
export const GRAMS_PER_TROY_OUNCE = 31.1034768;

/** 报价超过该秒数视为过期，图表进入暂停。 */
export const QUOTE_STALE_SECONDS = 180;

/** 行情品种元数据（后端 GoldInstrument）。 */
export interface GoldInstrument {
  id: string;
  name: string;
  symbol: string;
  kind: "spot" | "future";
  currency: "CNY" | "USD";
  unit: MarketUnit;
  quote_source: string;
  daily_source: string;
  delay_seconds: number;
  exchange?: string;
  contract?: string;
}

/** 报价响应 data。 */
export interface GoldQuote {
  symbol: string;
  price: number;
  open: number;
  high: number;
  low: number;
  prev_close: number;
  change: number;
  change_percent: number;
  /** 美元兑人民币中间价；0 表示不可用 */
  usd_cny: number;
  cny_per_gram: number;
  /** 上游报价时间，分钟精度 */
  source_time: string;
  instrument?: GoldInstrument;
}

/** 实时走势的一个采样点。 */
export interface RealtimePoint {
  /** 服务端采样时间 */
  time: string;
  /** 上游报价时间（分钟精度） */
  source_time: string;
  price: number;
}

/** 实时走势响应 data。 */
export interface GoldRealtime {
  symbol: string;
  unit: string;
  /** 5 为五秒采样；60 为秒级历史缺失时的真实分钟记录回退 */
  interval_seconds: 5 | 60;
  window_seconds: number;
  points: RealtimePoint[];
}

/** 历史记录粒度。 */
export type Granularity = "annual" | "daily";

/** 一条历史记录或删除墓碑（后端 HistoryChange）。 */
export interface MarketSyncPoint {
  date: string;
  granularity: Granularity;
  open: number;
  high: number;
  low: number;
  close: number;
  source: string;
  deleted: boolean;
}

/** 增量同步响应 data（后端 HistorySync）。 */
export interface MarketSyncPage {
  series: string;
  unit: string;
  cursor: string;
  reset: boolean;
  points: MarketSyncPoint[];
}

/** 图表点的统一粒度标记，含实时。 */
export type ChartGranularity = "annual" | "daily" | "realtime";

/** 折算为人民币元/克后的图表点。 */
export interface ChartPoint {
  time: number;
  price: number;
  granularity: ChartGranularity;
  source: string;
}

/** 实时窗口状态。 */
export type RealtimeState = "live" | "paused" | "empty";

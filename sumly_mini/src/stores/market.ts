/**
 * 行情 store：口径、报价、历史缓存与实时窗口的单一数据源。
 *
 * 关键约束：
 * - 切换口径期间原数据保留，目标口径完整就绪后原子替换，不混显不同单位；
 * - 每次请求绑定发起时的口径与代��，晚到的旧口径响应不得覆盖新口径；
 * - 缓存写入失败不推进游标，也不误报同步成功；
 * - 生命周期只持有一个轮询器，多个 owner 共享，没有 owner 时暂停。
 */
import { computed, ref, shallowRef } from "vue";
import { getGoldQuote, getGoldRealtime, getMarketSync } from "@/api/market";
import { toCnyPoints } from "@/domain/market/conversion";
import { mergeMarketSync, type MarketCache } from "@/domain/market/sync";
import { realtimeState } from "@/domain/market/timing";
import { clearMarketCaches, loadMarketCache, saveMarketCache } from "@/utils/marketStorage";
import type {
  ChartPoint,
  GoldQuote,
  GoldRealtime,
  MarketBasis,
  MarketSeries,
  MarketSyncPage,
  RealtimeState,
} from "@/types/market";

/** 行情轮询间隔（毫秒），与 iOS 端 MarketHomeViewModel 保持一致。 */
export const QUOTE_INTERVAL_MS = 5_000;
export const REALTIME_INTERVAL_MS = 5_000;
export const HOLDINGS_QUOTE_INTERVAL_MS = 3_000;
export const HISTORY_INTERVAL_MS = 60_000;

const BASIS_STORAGE_KEY = "sumly:market:basis";

/** store 依赖，便于测试注入确定实现。 */
export interface MarketStoreDeps {
  loadCache: (series: MarketSeries) => MarketCache | null;
  saveCache: (series: MarketSeries, cache: MarketCache) => void;
  clearCache: () => void;
  getGoldQuote: (basis: MarketBasis) => Promise<GoldQuote>;
  getGoldRealtime: (basis: MarketBasis) => Promise<GoldRealtime>;
  getMarketSync: (series: MarketSeries, cursor?: string) => Promise<MarketSyncPage>;
  now: () => number;
  /** 记住用户选择的口径；失败不影响本次切换。 */
  rememberBasis?: (basis: MarketBasis) => void;
}

/** 默认依赖：真实 API 与 uni 存储。 */
function defaultDeps(): MarketStoreDeps {
  return {
    loadCache: loadMarketCache,
    saveCache: saveMarketCache,
    clearCache: clearMarketCaches,
    getGoldQuote,
    getGoldRealtime,
    getMarketSync,
    now: () => Date.now(),
    rememberBasis: (value) => {
      try {
        uni.setStorageSync(BASIS_STORAGE_KEY, value);
      } catch {
        // 口径记忆失败不影响本次切换
      }
    },
  };
}

export function createMarketStore(deps: MarketStoreDeps) {
  const basis = ref<MarketBasis>("international");
  const quote = shallowRef<GoldQuote | null>(null);
  const realtime = shallowRef<GoldRealtime | null>(null);
  const caches = shallowRef<Record<string, MarketCache | null>>({});
  const error = ref<string | null>(null);
  const loading = ref(false);

  /** 口径代��：每次切换自增，用于丢弃晚到的旧响应。 */
  let basisGeneration = 0;
  const timers = new Set<ReturnType<typeof setTimeout>>();
  const owners = new Set<"market" | "holdings">();

  function seriesOf(basisValue: MarketBasis): MarketSeries {
    return basisValue === "domestic" ? "au9999" : "xauusd";
  }

  function cacheOf(basisValue: MarketBasis): MarketCache | null {
    const series = seriesOf(basisValue);
    if (series in caches.value) return caches.value[series];
    const loaded = deps.loadCache(series);
    caches.value = { ...caches.value, [series]: loaded };
    return loaded;
  }

  /** 把报价与实时点折算为统一的人民币图表点。 */
  const historyPoints = computed<ChartPoint[]>(() => {
    const cache = cacheOf(basis.value);
    return cache ? toCnyPoints(cache, quote.value) : [];
  });

  const realtimePoints = computed<ChartPoint[]>(() => {
    const window = realtime.value;
    if (!window || window.points.length === 0) return [];
    return window.points.map((point) => ({
      time: new Date(point.time).getTime(),
      price: point.price,
      granularity: "realtime" as const,
      source: point.source_time,
    }));
  });

  /** 实时窗口状态，随轮询刷新。 */
  const status = computed<RealtimeState>(() => {
    const window = realtime.value;
    const lastSample = window?.points.length ? new Date(window.points[window.points.length - 1].time).getTime() : null;
    const lastQuote = quote.value?.source_time ? new Date(quote.value.source_time).getTime() : null;
    return realtimeState(lastSample, lastQuote, window?.interval_seconds ?? 5, deps.now());
  });

  /** 拉取当前口径报价；代际不匹配时丢弃结果。 */
  async function refreshQuote(target: MarketBasis = basis.value): Promise<void> {
    const generation = basisGeneration;
    const result = await deps.getGoldQuote(target);
    if (generation !== basisGeneration) return;
    quote.value = result;
  }

  /** 拉取实时窗口；代际不匹配时丢弃结果。 */
  async function refreshRealtime(target: MarketBasis = basis.value): Promise<void> {
    const generation = basisGeneration;
    const result = await deps.getGoldRealtime(target);
    if (generation !== basisGeneration) return;
    realtime.value = result;
  }

  /**
   * 增量同步历史。缓存写入成功后才推进游标并发布新状态；
   * 写入失败保留原有缓存，把错误暴露给页面，不误报同步成功。
   */
  async function refreshHistory(target: MarketBasis = basis.value): Promise<void> {
    const generation = basisGeneration;
    const series = seriesOf(target);
    const previous = cacheOf(target);
    const page = await deps.getMarketSync(series, previous?.cursor);
    if (generation !== basisGeneration) return;

    const merged = mergeMarketSync(previous, page);
    try {
      deps.saveCache(series, merged);
    } catch (cause) {
      // 存储已满等失败：缓存与游标都保持原样，页面可见错误
      error.value = cause instanceof Error ? cause.message : "行情缓存写入失败";
      throw cause;
    }
    caches.value = { ...caches.value, [series]: merged };
    error.value = null;
  }

  /** 切换口径：等待目标数据就绪后原子提交，失败保留原口径。 */
  async function switchBasis(next: MarketBasis): Promise<boolean> {
    if (next === basis.value) {
      return true;
    }
    const previousBasis = basis.value;
    const previousQuote = quote.value;
    const previousRealtime = realtime.value;
    basisGeneration += 1;
    const generation = basisGeneration;
    basis.value = next;
    error.value = null;
    loading.value = true;

    try {
      const [nextQuote, nextRealtime] = await Promise.all([
        deps.getGoldQuote(next),
        deps.getGoldRealtime(next),
      ]);
      if (generation !== basisGeneration) return false;
      quote.value = nextQuote;
      realtime.value = nextRealtime;
      deps.rememberBasis?.(next);
      return true;
    } catch (cause) {
      if (generation !== basisGeneration) return false;
      // 保留原口径与原数据，不混显不同单位
      basis.value = previousBasis;
      quote.value = previousQuote;
      realtime.value = previousRealtime;
      error.value = cause instanceof Error ? cause.message : "行情切换失败";
      return false;
    } finally {
      if (generation === basisGeneration) {
        loading.value = false;
      }
    }
  }

  /** 注册生命周期 owner；首个 owner 立即拉取一次并启动轮询。 */
  function start(owner: "market" | "holdings"): void {
    const isFirstOwner = owners.size === 0;
    owners.add(owner);
    if (!isFirstOwner) return;
    // 首帧立即取数，避免页面等待一个完整轮询周期才显示内容
    void tickQuote();
    schedule();
  }

  /** 注销 owner；没有 owner 时停止全部定时器。 */
  function stop(owner: "market" | "holdings"): void {
    owners.delete(owner);
    if (owners.size > 0) return;
    for (const timer of timers) clearTimeout(timer);
    timers.clear();
  }

  /**
   * 单一轮询器：报价/实时与历史各自独立调度，
   * 慢历史请求不阻塞实时刷新。回调结束后各自排下一轮。
   */
  function scheduleQuote(): void {
    if (owners.size === 0) return;
    const timer = setTimeout(() => {
      timers.delete(timer);
      void tickQuote().finally(scheduleQuote);
    }, quoteIntervalMs());
    timers.add(timer);
  }

  function scheduleHistory(): void {
    if (owners.size === 0) return;
    const timer = setTimeout(() => {
      timers.delete(timer);
      void tickHistory().finally(scheduleHistory);
    }, HISTORY_INTERVAL_MS);
    timers.add(timer);
  }

  function schedule(): void {
    scheduleQuote();
    scheduleHistory();
  }

  function quoteIntervalMs(): number {
    // 持仓页需要更快的报价以跟上盈亏计算
    return owners.has("holdings") ? HOLDINGS_QUOTE_INTERVAL_MS : QUOTE_INTERVAL_MS;
  }

  async function tickQuote(): Promise<void> {
    try {
      await Promise.all([refreshQuote(), refreshRealtime()]);
      error.value = null;
    } catch (cause) {
      // 网络故障保留缓存，只标记错误，不清空已有数据
      error.value = cause instanceof Error ? cause.message : "行情更新失败";
    }
  }

  async function tickHistory(): Promise<void> {
    try {
      await refreshHistory();
    } catch {
      // 历史同步失败不覆盖实时错误，也不影响轮询继续
    }
  }

  /** 清除行情缓存，不影响持仓数据。 */
  function clearCache(): void {
    deps.clearCache();
    caches.value = {};
  }

  return {
    basis,
    quote,
    realtime,
    points: historyPoints,
    realtimePoints,
    error,
    loading,
    status,
    switchBasis,
    refreshQuote,
    refreshRealtime,
    refreshHistory,
    start,
    stop,
    clearCache,
  };
}

/** 全局单例，供页面与组件共享。 */
let shared: ReturnType<typeof createMarketStore> | null = null;

export function useMarketStore() {
  if (!shared) {
    shared = createMarketStore(defaultDeps());
  }
  return shared;
}

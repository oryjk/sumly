/**
 * 购入日期参考价。
 *
 * 移植自 iOS 端 HoldingPurchasePriceModel，核心约束有两条：
 *
 * 1. **历史日期绝不预填当前报价**。当日用实时报价，历史日只用该交易日
 *    收盘价；休市无收盘数据显示缺失，不用现价或最近价顶替。
 * 2. **手动输入不被异步响应覆盖**。用户手填价格后，晚到的请求结果
 *    只能更新参考价供比对，不能改写用户已输入的价格。
 *
 * 代际（generation）机制保证快速切换日期时只有最后一次请求能落地。
 */
import { computed, ref, shallowRef } from "vue";
import { GRAMS_PER_TROY_OUNCE, type MarketBasis } from "@/types/market";

/** 参考价。 */
export interface PurchaseReference {
  /** 元/克。 */
  price: number;
  /** Unix 毫秒，当日零点。 */
  day: number;
  /** 是否为历史交易日收盘价。 */
  historical: boolean;
  /** 国际口径折算所用汇率；国内为 null。 */
  exchangeRate: number | null;
}

/** 参考价缺失原因。 */
export type ReferenceIssue = "missingDay" | "missingExchangeRate" | "unavailable";

/** 一条日线记录。 */
export interface DailyPrice {
  /** YYYY-MM-DD。 */
  date: string;
  close: number;
}

/** 报价。 */
export interface QuoteSnapshot {
  cny_per_gram: number;
  usd_cny: number;
}

/** 依赖注入，便于测试完全确定。 */
export interface PurchaseReferenceDeps {
  basis: MarketBasis;
  now: () => number;
  /** 初始选中日；不传时取当前时刻。便于测试构造确定起点。 */
  initialDay?: number;
  getCachedDaily: () => Promise<DailyPrice[] | null>;
  getDaily: () => Promise<DailyPrice[]>;
  getQuote: () => Promise<QuoteSnapshot>;
  getCachedQuote: () => Promise<QuoteSnapshot | null>;
}

/** 有效价格上界，与 App 一致。 */
const MAX_PRICE = 1_000_000;

function isValidPrice(value: number | unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value > 0 && value <= MAX_PRICE;
}

function formatPrice(value: number): string {
  return value.toFixed(2);
}

/** 取指定日期的收盘价；日期键严格匹配，不做时区漂移。 */
function closeOn(prices: readonly DailyPrice[], day: number): number | null {
  const key = new Date(day).toISOString().slice(0, 10);
  const found = prices.find((price) => price.date === key);
  return found && isValidPrice(found.close) ? found.close : null;
}

export function createPurchaseReference(deps: PurchaseReferenceDeps) {
  const reference = shallowRef<PurchaseReference | null>(null);
  const priceText = ref("");
  const manual = ref(false);
  const loading = ref(false);
  const issue = ref<ReferenceIssue | null>(null);
  const selectedDay = ref(dayStart(deps.initialDay ?? deps.now()));

  /** 代际：每次选日或加载都自增，晚到的旧响应据此丢弃。 */
  let generation = 0;

  function dayStart(ms: number): number {
    const parsed = new Date(ms);
    return Date.UTC(parsed.getUTCFullYear(), parsed.getUTCMonth(), parsed.getUTCDate());
  }

  const validPrice = computed(() => {
    const parsed = Number(priceText.value.trim());
    return isValidPrice(parsed) ? parsed : null;
  });

  /** 切换日期：清空参考价与问题；手动输入时保留用户已填的价格。 */
  function selectDate(ms: number): Promise<void> {
    const day = dayStart(ms);
    if (day === selectedDay.value) {
      return Promise.resolve();
    }
    generation += 1;
    selectedDay.value = day;
    reference.value = null;
    issue.value = null;
    loading.value = false;
    if (!manual.value) {
      priceText.value = "";
    }
    return Promise.resolve();
  }

  /** 手动编辑价格。此后异步响应不得覆盖。 */
  function editPrice(text: string): void {
    manual.value = true;
    priceText.value = text;
  }

  /** 回到参考价。 */
  function useReference(): void {
    const current = reference.value;
    if (!current) return;
    manual.value = false;
    priceText.value = formatPrice(current.price);
  }

  /** 加载参考价。 */
  async function load(nowMs: number = deps.now()): Promise<void> {
    generation += 1;
    const request = generation;
    const day = selectedDay.value;
    loading.value = true;
    issue.value = null;

    try {
      let result: PurchaseReference;
      if (dayStart(nowMs) === day) {
        // 当日用实时报价
        const quote = await deps.getQuote();
        if (!isValidPrice(quote.cny_per_gram)) {
          throw "unavailable";
        }
        result = { price: quote.cny_per_gram, day, historical: false, exchangeRate: null };
      } else {
        // 历史日：缓存命中就不重复请求
        const cached = await deps.getCachedDaily();
        let prices = cached;
        if (!prices || closeOn(prices, day) === null) {
          prices = await deps.getDaily();
        }
        const close = closeOn(prices, day);
        if (close === null) {
          throw "missingDay";
        }
        if (deps.basis === "domestic") {
          result = { price: close, day, historical: true, exchangeRate: null };
        } else {
          // 国际日线是 USD/oz，当前数据源没有历史汇率，必须标为参考折算价
          let quote: QuoteSnapshot;
          try {
            quote = await deps.getQuote();
          } catch {
            const cachedQuote = await deps.getCachedQuote();
            if (!cachedQuote) throw "missingExchangeRate";
            quote = cachedQuote;
          }
          if (!Number.isFinite(quote.usd_cny) || quote.usd_cny <= 0) {
            throw "missingExchangeRate";
          }
          const price = (close * quote.usd_cny) / GRAMS_PER_TROY_OUNCE;
          if (!isValidPrice(price)) {
            throw "unavailable";
          }
          result = { price, day, historical: true, exchangeRate: quote.usd_cny };
        }
      }

      // 代际不匹配说明用户又切了日期或又发了请求，丢弃本次结果
      if (generation !== request) return;
      reference.value = result;
      // 手动输入优先，绝不被异步响应覆盖
      if (!manual.value) {
        priceText.value = formatPrice(result.price);
      }
      issue.value = null;
    } catch (cause) {
      if (generation !== request) return;
      issue.value =
        cause === "missingDay" || cause === "missingExchangeRate" || cause === "unavailable"
          ? cause
          : "unavailable";
    } finally {
      if (generation === request) {
        loading.value = false;
      }
    }
  }

  return { reference, priceText, manual, loading, issue, selectedDay, validPrice, selectDate, editPrice, useReference, load };
}

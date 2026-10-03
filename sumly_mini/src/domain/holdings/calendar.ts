/**
 * 记金日历的事件与周期筛选。
 *
 * 移植自 iOS 端 HoldingCalendarLogic：
 * - 拆分持仓共享 purchaseID，**购入件数不会因赠卖而增加**；
 * - 卖出/赠送事件按各自的处置日期归属，不落在购入日；
 * - 赠送给按成本记录，实收为 0。
 */
import { totalPurchaseCost } from "./disposal";
import type { HoldingRecord } from "@/types/holdings";

/** 日历周期。 */
export type CalendarPeriod = "day" | "month" | "year" | "all";

/** 事件筛选条件。 */
export interface CalendarFilter {
  keyword: string;
  /** all | holding | sold | gift */
  kind: string;
  /** null 表示全部账本。 */
  book: string | null;
}

/** 一个日历事件。 */
export interface CalendarEvent {
  id: string;
  /** 购入编号；拆分后共享，用于件数去重。 */
  purchaseID: string;
  date: number;
  /** buy | sold | gift */
  kind: string;
  grams: number;
  cost: number;
  fees: number;
  proceeds: number;
  title: string;
}

/** 按事件日期倒序生成日历事件。 */
export function calendarEvents(
  records: readonly HoldingRecord[],
  filter: CalendarFilter,
): CalendarEvent[] {
  const keyword = filter.keyword.trim().toLowerCase();
  const result: CalendarEvent[] = [];

  for (const record of records) {
    if (filter.book !== null && record.bookName !== filter.book) continue;
    if (keyword) {
      const fields = [record.brand, record.note, record.purchaseChannel, record.counterparty];
      const hit = fields.some((field) => field.toLowerCase().includes(keyword));
      if (!hit) continue;
    }

    // 部分处置的记录指向同一购入族；没有则用自身 id
    const purchaseID = (record.purchaseID ?? record.id).toLowerCase();
    const title = record.brand.trim() ? record.brand : "未知";
    const cost = totalPurchaseCost(record);
    const fees = record.extraFee + record.laborFee;

    if (filter.kind === "all" || (filter.kind === "holding" && record.disposition === "holding")) {
      result.push({
        id: `buy-${record.id}`,
        purchaseID,
        date: record.timestamp,
        kind: "buy",
        grams: record.grams,
        cost,
        fees,
        proceeds: 0,
        title,
      });
    }

    const disposedAt = record.disposedAt;
    if (record.disposition !== "holding" && disposedAt !== null) {
      if (filter.kind === "all" || filter.kind === record.disposition) {
        result.push({
          id: `dispose-${record.id}`,
          purchaseID,
          date: disposedAt,
          kind: record.disposition,
          grams: record.grams,
          cost,
          fees,
          // 赠送不计实收
          proceeds: record.disposalAmount,
          title,
        });
      }
    }
  }

  // 购入事件按购入编号去重：拆分持仓不应让件数虚增
  const seenPurchases = new Set<string>();
  const deduped = result.filter((event) => {
    if (event.kind !== "buy") return true;
    if (seenPurchases.has(event.purchaseID)) return false;
    seenPurchases.add(event.purchaseID);
    return true;
  });

  return deduped.sort((a, b) => b.date - a.date);
}

/** 按周期筛选事件。 */
export function selectCalendarEvents(
  events: readonly CalendarEvent[],
  period: CalendarPeriod,
  dateMs: number,
): CalendarEvent[] {
  if (period === "all") {
    return [...events];
  }
  const anchor = new Date(dateMs);
  const year = anchor.getUTCFullYear();
  const month = anchor.getUTCMonth();

  let start: number;
  let end: number;
  if (period === "day") {
    start = Date.UTC(year, month, anchor.getUTCDate());
    end = Date.UTC(year, month, anchor.getUTCDate() + 1);
  } else if (period === "month") {
    start = Date.UTC(year, month, 1);
    end = Date.UTC(year, month + 1, 1);
  } else {
    start = Date.UTC(year, 0, 1);
    end = Date.UTC(year + 1, 0, 1);
  }

  return events.filter((event) => event.date >= start && event.date < end);
}

/** 某类事件的汇总。 */
export interface CalendarCategorySummary {
  count: number;
  grams: number;
  fees: number;
  cost: number;
  average: number;
  proceeds: number;
  saleAverage: number;
  /** 历史估值口径下的价值；无报价时为 null。 */
  value: number | null;
  profit: number | null;
  profitPercent: number | null;
}

export interface CalendarSummary {
  purchases: CalendarCategorySummary;
  sales: CalendarCategorySummary;
  gifts: CalendarCategorySummary;
}

function summarize(events: readonly CalendarEvent[], kind: string, grams: number, price: number | null): CalendarCategorySummary {
  const matched = events.filter((event) => event.kind === kind);
  const count = matched.length;
  const totalGrams = matched.reduce((sum, event) => sum + event.grams, 0);
  const fees = matched.reduce((sum, event) => sum + event.fees, 0);
  const cost = matched.reduce((sum, event) => sum + event.cost, 0);
  const proceeds = matched.reduce((sum, event) => sum + event.proceeds, 0);
  const validPrice = price !== null && Number.isFinite(price) && price > 0 ? price : null;
  const value = validPrice === null ? null : validPrice * grams;
  const profit = value === null ? null : proceeds - cost;
  return {
    count,
    grams: totalGrams,
    fees,
    cost,
    average: count === 0 ? 0 : cost / count,
    proceeds,
    saleAverage: proceeds === 0 ? 0 : proceeds / count,
    value,
    profit,
    profitPercent: profit === null || cost === 0 ? null : (profit / cost) * 100,
  };
}

/** 汇总统计。price 为空时历史估值相关字段为 null，不伪造。 */
export function calendarSummary(
  events: readonly CalendarEvent[],
  grams: number,
  price: number | null,
): CalendarSummary {
  return {
    purchases: summarize(events, "buy", grams, price),
    sales: summarize(events, "sold", grams, price),
    gifts: summarize(events, "gift", grams, price),
  };
}

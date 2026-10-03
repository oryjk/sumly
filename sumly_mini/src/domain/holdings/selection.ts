/**
 * 持仓列表的筛选、搜索与排序。
 * 移植自 iOS 端 HoldingsSelection.records：
 * 只在指定账本内筛选持有中记录，盈亏筛选依赖有效报价。
 */
import { calculateReturn, returnInput } from "./returns";
import type { HoldingRecord } from "@/types/holdings";

export type HoldingFilter = "all" | "profit" | "loss";
export type HoldingSort = "newest" | "oldest" | "heaviest" | "costliest";

export interface HoldingQuery {
  /** 账本名；空字符串表示全部账本。 */
  book: string;
  search: string;
  filter: HoldingFilter;
  sort: HoldingSort;
  /** 当前报价（元/克）；缺失时盈亏筛选无结果。 */
  price: number | null;
}

/** 总成本，实付总额优先。 */
function totalCost(record: HoldingRecord): number {
  return record.purchaseTotalOverride ?? record.grams * record.unitPriceCNY + record.laborFee + record.extraFee;
}

/** 列表展示名：品牌优先，其次类型，最后兜底。 */
export function displayName(record: HoldingRecord): string {
  const brand = record.brand.trim();
  if (brand) return brand;
  const type = record.assetType.trim();
  return !type || type === "其他" ? "黄金记录" : type;
}

/** 按条件筛选并排序持有中记录。 */
export function selectHoldings(records: readonly HoldingRecord[], query: HoldingQuery): HoldingRecord[] {
  const keyword = query.search.trim();

  return records
    .filter((record) => {
      // 空账本表示不过滤账本
      if (query.book && record.bookName !== query.book) return false;
      if (record.disposition !== "holding") return false;

      if (keyword) {
        const brand = record.brand.trim() ? record.brand : "未知";
        const hitBrand = brand.toLocaleLowerCase().includes(keyword.toLocaleLowerCase());
        const hitNote = record.note.toLocaleLowerCase().includes(keyword.toLocaleLowerCase());
        if (!hitBrand && !hitNote) return false;
      }

      if (query.filter !== "all") {
        // 没有有效报价就无法判断盈亏，此时不返回任何记录
        if (query.price === null || !Number.isFinite(query.price) || query.price <= 0) return false;
        const profit = calculateReturn(returnInput(record), query.price)?.profit;
        if (profit === null || profit === undefined) return false;
        if (query.filter === "profit" && profit < 0) return false;
        if (query.filter === "loss" && profit >= 0) return false;
      }

      return true;
    })
    .sort((a, b) => {
      switch (query.sort) {
        case "newest":
          return b.timestamp - a.timestamp;
        case "oldest":
          return a.timestamp - b.timestamp;
        case "heaviest":
          // 同重量时以时间新的在前，保证顺序稳定
          return a.grams === b.grams ? b.timestamp - a.timestamp : b.grams - a.grams;
        case "costliest":
          return totalCost(b) - totalCost(a);
        default:
          return 0;
      }
    });
}

/** 批量操作的全选：只选当前可见记录，不跨过滤条件。 */
export function selectAllVisible(records: readonly HoldingRecord[], query: HoldingQuery): string[] {
  return selectHoldings(records, query).map((record) => record.id);
}

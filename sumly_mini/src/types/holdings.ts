/**
 * 持仓文档类型。
 *
 * 与服务端 sumly_go internal/holdings/domain.Document 共享同一份契约
 * （schemaVersion 1），字段名保持一致以便直接序列化。
 * 约定：
 * - 日期一律为 Unix 毫秒数字，不使用字符串，保留小数毫秒；
 * - id 为规范化小写 UUID，比较时大小写无关；
 * - assetType 是开放字符串，未知历史类型原样保留。
 */

/** 处置状态。 */
export type HoldingDisposition = "holding" | "sold" | "gift";

/** 提醒目标类型。 */
export type HoldingAlertKind = "breakeven" | "profitPercent" | "profitAmount" | "price";

/** 提醒所用行情口径。 */
export type HoldingAlertBasis = "domestic" | "international";

/** 持仓目标提醒配置。设备基线不随云文档同步。 */
export interface HoldingAlert {
  id: string;
  kind: HoldingAlertKind;
  threshold: number;
  enabled: boolean;
  basis: HoldingAlertBasis;
}

/** 一条黄金持仓记录。 */
export interface HoldingRecord {
  id: string;
  /** 买入克数。 */
  grams: number;
  /** 购入单价，元/克。 */
  unitPriceCNY: number;
  /** 购入时间点（Unix 毫秒，用户可指定过去时间补录）。 */
  timestamp: number;
  note: string;
  /** 创建时间（Unix 毫秒）。 */
  createdAt: number;
  brand: string;
  bookName: string;
  disposition: HoldingDisposition;
  /** 处置时间（Unix 毫秒）；持有中为 null。 */
  disposedAt: number | null;
  /** 处置实收金额；赠送为 0。 */
  disposalAmount: number;
  /** 部分处置时关联的购入编号。 */
  purchaseID: string | null;
  /** 其他费用。 */
  extraFee: number;
  purchaseChannel: string;
  /** 买家或受赠人。 */
  counterparty: string;
  /** 黄金类型；未知历史类型原样保留。 */
  assetType: string;
  /** 纯度，(0, 1]。 */
  purity: number;
  /** 工费总额。 */
  laborFee: number;
  /** 实付总额；填写后作为最终成本，不再叠加工费与其他费用。 */
  purchaseTotalOverride: number | null;
  /** 回收每克扣减（元/克）。 */
  recoveryDeduction: number;
  /** 回收折价率，[0, 1)，在扣减后再折扣。 */
  recoveryDiscount: number;
  /** 回收固定费用。 */
  recoveryFixedFee: number;
  /** 目标提醒配置，至多 4 条。 */
  alerts: HoldingAlert[];
}

/** 账本文档，云同步的唯一载荷。 */
export interface HoldingDocument {
  schemaVersion: 1;
  books: string[];
  records: HoldingRecord[];
}

/** 文档上限，与服务端一致。 */
export const MAX_BOOKS = 100;
export const MAX_RECORDS = 1000;
export const MAX_ALERTS_PER_RECORD = 4;
export const DEFAULT_BOOK = "默认账本";

/** 可表示的日期范围（Unix 毫秒），与 Swift/Go 保持一致。 */
export const MIN_DATE_MS = -62_135_596_800_000;
export const MAX_DATE_MS = 253_402_300_799_999;

/** 空文档。 */
export function emptyDocument(): HoldingDocument {
  return { schemaVersion: 1, books: [DEFAULT_BOOK], records: [] };
}

/**
 * 部分处置：卖出与赠送。
 *
 * 移植自 iOS 端 HoldingDisposal.apply。核心约束是**守恒**：
 * 拆出的处置记录与剩余记录合计必须等于原记录的克数与总成本，
 * 否则用户看到的持仓成本会凭空漂移。
 *
 * 费用按处置比例分摊；回收参数属于整笔规则，原样带到处置记录，
 * 固定回收费不按克数切分（与 App 一致）。
 */
import type { HoldingDisposition, HoldingDocument, HoldingRecord } from "@/types/holdings";

/** 记录总成本：实付总额优先，否则按克数与费用推算。 */
export function totalPurchaseCost(record: HoldingRecord): number {
  return record.purchaseTotalOverride ?? record.grams * record.unitPriceCNY + record.laborFee + record.extraFee;
}

/** 处置类型限定 sold / gift。 */
const DISPOSAL_KINDS: HoldingDisposition[] = ["sold", "gift"];

/**
 * 浮点相减后可能残留 -1e-15 这类噪声，
 * 落在「本应为零」的字段上会让校验失败或显示 -0.00g。
 */
function normalizeZero(value: number): number {
  return value === 0 || Math.abs(value) < 1e-9 ? 0 : value;
}

/** 生成确定性 UUID v4 形式的占位 id，避免依赖随机源导致测试不可复现。 */
function derivedId(seed: string): string {
  // 用简单散列从种子派生 32 位十六进制，保证同一操作产生同一 id
  let hash = 0x811c9dc5;
  for (let index = 0; index < seed.length; index += 1) {
    hash ^= seed.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  const hex = hash.toString(16).padStart(8, "0");
  return `${hex}-0000-4000-8000-${hex}${hex.slice(0, 4)}`;
}

/**
 * 对一条持有记录执行处置，返回新的文档；不修改传入的文档。
 *
 * @param grams 处置克数，须大于 0 且不超过剩余克数
 * @param proceeds 实际总实收；赠送时忽略并记 0
 * @param kind sold | gift
 * @param disposedAt 处置时间，须在购入时间之后且不超过 now
 * @param counterparty 买家或受赠人
 * @param now 当前时刻
 */
export function disposeHolding(
  document: HoldingDocument,
  recordId: string,
  grams: number,
  proceeds: number,
  kind: HoldingDisposition,
  disposedAt: number,
  counterparty: string,
  now: number,
): HoldingDocument {
  const source = document.records.find((item) => item.id.toLowerCase() === recordId.toLowerCase());
  if (!source) {
    throw new Error("持仓记录不存在");
  }
  if (source.disposition !== "holding") {
    throw new Error("已处置的记录不可再次处置");
  }
  if (!Number.isFinite(grams) || grams <= 0 || grams > source.grams) {
    throw new Error("处置克数无效");
  }
  if (!Number.isFinite(proceeds) || proceeds < 0) {
    throw new Error("处置实收无效");
  }
  if (kind !== "sold" && kind !== "gift") {
    throw new Error("处置类型无效");
  }
  if (!Number.isFinite(disposedAt) || disposedAt < source.timestamp || disposedAt > now) {
    throw new Error("处置时间无效");
  }

  const records = document.records.map((item) => ({ ...item, alerts: [...item.alerts] }));
  const index = records.findIndex((item) => item.id === source.id);
  const target = records[index];

  const applyDisposalMark = (item: HoldingRecord): HoldingRecord => ({
    ...item,
    disposition: kind,
    disposedAt,
    // 赠送不计实收
    disposalAmount: kind === "gift" ? 0 : proceeds,
    counterparty: counterparty || item.counterparty,
    // 处置完成即不再监测，清空该记录上的提醒
    alerts: [],
  });

  if (grams >= source.grams) {
    // 全额处置：直接改写原记录，不新增
    records[index] = applyDisposalMark(target);
    return { schemaVersion: 1, books: [...document.books], records };
  }

  // 部分处置：拆出处置记录，剩余记录保留购入日期与单价
  const fraction = grams / source.grams;
  const disposedLaborFee = source.laborFee * fraction;
  const disposedExtraFee = source.extraFee * fraction;
  const disposedTotalOverride = source.purchaseTotalOverride === null ? null : source.purchaseTotalOverride * fraction;

  const disposed: HoldingRecord = applyDisposalMark({
    ...target,
    id: derivedId(`${source.id}:${grams}:${disposedAt}:${kind}`),
    grams,
    // 购入时间与单价沿用原记录，日历事件才能归入同一购入族
    timestamp: source.timestamp,
    createdAt: source.createdAt,
    note: source.note,
    brand: source.brand,
    bookName: source.bookName,
    // 关联购入编号：首次处置时指向原记录，之后沿用
    purchaseID: source.purchaseID ?? source.id,
    extraFee: disposedExtraFee,
    purchaseChannel: source.purchaseChannel,
    counterparty: source.counterparty,
    assetType: source.assetType,
    purity: source.purity,
    laborFee: disposedLaborFee,
    purchaseTotalOverride: disposedTotalOverride,
    recoveryDeduction: source.recoveryDeduction,
    recoveryDiscount: source.recoveryDiscount,
    // 固定回收费属于整笔规则，不随克数切分
    recoveryFixedFee: source.recoveryFixedFee,
  });

  // 剩余记录扣减对应份额，成本随之下降
  target.grams = normalizeZero(source.grams - grams);
  target.laborFee = normalizeZero(source.laborFee - disposedLaborFee);
  target.extraFee = normalizeZero(source.extraFee - disposedExtraFee);
  if (source.purchaseTotalOverride !== null) {
    target.purchaseTotalOverride = normalizeZero(
      source.purchaseTotalOverride - (disposedTotalOverride ?? 0),
    );
  }

  records.splice(index + 1, 0, disposed);
  return { schemaVersion: 1, books: [...document.books], records };
}

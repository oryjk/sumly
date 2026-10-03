/**
 * 持仓表单草稿。
 *
 * 移植自 iOS 端 HoldingDraft：新增、编辑与买前计算器共用同一份草稿。
 * 表单里全是文本，非法中间输入不参与计算——`input` 返回 null，
 * 由调用方决定是禁用提交还是提示。
 */
import { isValidInput, type GoldReturnInput } from "./returns";
import type { HoldingRecord } from "@/types/holdings";

/** 黄金类型。未知历史类型在编辑时原样保留。 */
export const ASSET_TYPES = ["金饰", "金条", "积存金", "其他"] as const;
export type GoldAssetType = (typeof ASSET_TYPES)[number];

/** 成本录入方式。 */
export type CostMode = "unit" | "total";

/** 草稿初始值。 */
export interface DraftInit {
  assetType?: string;
  gramsText?: string;
  priceText?: string;
  totalText?: string;
  costMode?: CostMode;
  laborText?: string;
  laborPerGram?: boolean;
  otherText?: string;
  purityText?: string;
  channel?: string;
  brand?: string;
  note?: string;
  deductionText?: string;
  discountText?: string;
  fixedFeeText?: string;
}

/** 单价输入上限。 */
const MAX_PRICE = 1_000_000;
/** 克数上限。 */
const MAX_GRAMS = 1_000_000;
/** 通用数值上限。 */
const MAX_AMOUNT = 1_000_000_000;

/** 生成 RFC 4122 v4 UUID。crypto 在 H5 与微信小程序均可用。 */
export function newUUID(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  // 版本 4 与变体位
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex: string[] = [];
  for (let index = 0; index < 16; index += 1) {
    hex.push(bytes[index].toString(16).padStart(2, "0"));
  }
  return [
    hex.slice(0, 4).join(""),
    hex.slice(4, 6).join(""),
    hex.slice(6, 8).join(""),
    hex.slice(8, 10).join(""),
    hex.slice(10, 16).join(""),
  ].join("-");
}

function trim(value: string): string {
  return value.trim();
}

/** 解析表单数值：空的可选字段按 0，非法返回 null。 */
function parseNumber(text: string, optional = false): number | null {
  const value = trim(text);
  if (value === "" && optional) return 0;
  if (value === "") return null;
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0 || parsed > MAX_AMOUNT) return null;
  return parsed;
}

export function createDraft(init: DraftInit = {}) {
  const draft = {
    assetType: init.assetType ?? "金条",
    gramsText: init.gramsText ?? "",
    priceText: init.priceText ?? "",
    totalText: init.totalText ?? "",
    costMode: init.costMode ?? ("unit" as CostMode),
    laborText: init.laborText ?? "",
    laborPerGram: init.laborPerGram ?? true,
    otherText: init.otherText ?? "",
    purityText: init.purityText ?? "99.99",
    channel: init.channel ?? "",
    brand: init.brand ?? "",
    note: init.note ?? "",
    deductionText: init.deductionText ?? "",
    discountText: init.discountText ?? "",
    fixedFeeText: init.fixedFeeText ?? "",
  };

  /** 从草稿解析收益输入；任一字段非法则返回 null。 */
  function input(): GoldReturnInput | null {
    const grams = parseNumber(draft.gramsText);
    if (grams === null || grams <= 0 || grams > MAX_GRAMS) return null;

    const labor = parseNumber(draft.laborText, true);
    const other = parseNumber(draft.otherText, true);
    const purity = parseNumber(draft.purityText);
    const deduction = parseNumber(draft.deductionText, true);
    const discount = parseNumber(draft.discountText, true);
    const fixed = parseNumber(draft.fixedFeeText, true);
    if (labor === null || other === null || purity === null) return null;
    if (deduction === null || discount === null || fixed === null) return null;
    if (purity <= 0 || purity > 100) return null;
    // 折价率按百分数录入，必须小于 100
    if (discount >= 100) return null;

    const laborFee = draft.laborPerGram ? labor * grams : labor;

    let total: number | null = null;
    let price: number;
    if (draft.costMode === "total") {
      const value = parseNumber(draft.totalText);
      if (value === null || value <= 0) return null;
      total = value;
      // 保留已有裸金单价；仅知总价时反推综合单价作为基础参考
      const existing = parseNumber(draft.priceText);
      price = existing !== null && existing > 0
        ? existing
        : Math.max(0, (value - laborFee - other) / grams);
    } else {
      const value = parseNumber(draft.priceText);
      if (value === null || value <= 0 || value > MAX_PRICE) return null;
      price = value;
    }

    const result: GoldReturnInput = {
      grams,
      purity: purity / 100,
      unitPrice: price,
      laborFee,
      otherCost: other,
      totalCostOverride: total,
      rule: {
        perGramDeduction: deduction,
        discountRate: discount / 100,
        fixedFee: fixed,
      },
    };
    return isValidInput(result) ? result : null;
  }

  return {
    get assetType() { return draft.assetType; },
    set assetType(v: string) { draft.assetType = v; },
    get gramsText() { return draft.gramsText; },
    set gramsText(v: string) { draft.gramsText = v; },
    get priceText() { return draft.priceText; },
    set priceText(v: string) { draft.priceText = v; },
    get totalText() { return draft.totalText; },
    set totalText(v: string) { draft.totalText = v; },
    get costMode() { return draft.costMode; },
    set costMode(v: CostMode) { draft.costMode = v; },
    get laborText() { return draft.laborText; },
    set laborText(v: string) { draft.laborText = v; },
    get laborPerGram() { return draft.laborPerGram; },
    set laborPerGram(v: boolean) { draft.laborPerGram = v; },
    get otherText() { return draft.otherText; },
    set otherText(v: string) { draft.otherText = v; },
    get purityText() { return draft.purityText; },
    set purityText(v: string) { draft.purityText = v; },
    get channel() { return draft.channel; },
    set channel(v: string) { draft.channel = v; },
    get brand() { return draft.brand; },
    set brand(v: string) { draft.brand = v; },
    get note() { return draft.note; },
    set note(v: string) { draft.note = v; },
    get deductionText() { return draft.deductionText; },
    set deductionText(v: string) { draft.deductionText = v; },
    get discountText() { return draft.discountText; },
    set discountText(v: string) { draft.discountText = v; },
    get fixedFeeText() { return draft.fixedFeeText; },
    set fixedFeeText(v: string) { draft.fixedFeeText = v; },
    input,
  };
}

/** 由草稿新建的草稿（默认值）。 */
export function newDraft(): ReturnType<typeof createDraft> {
  return createDraft();
}

/** 从已有记录回填草稿。未知黄金类型原样保留，不强行归类。 */
export function draftFromRecord(record: HoldingRecord): ReturnType<typeof createDraft> {
  return createDraft({
    assetType: record.assetType,
    gramsText: String(record.grams),
    priceText: String(record.unitPriceCNY),
    totalText: record.purchaseTotalOverride === null ? "" : String(record.purchaseTotalOverride),
    costMode: record.purchaseTotalOverride === null ? "unit" : "total",
    laborText: String(record.laborFee),
    // 记录里存的是总额
    laborPerGram: false,
    otherText: String(record.extraFee),
    purityText: String(record.purity * 100),
    channel: record.purchaseChannel,
    brand: record.brand,
    note: record.note,
    deductionText: String(record.recoveryDeduction),
    discountText: String(record.recoveryDiscount * 100),
    fixedFeeText: String(record.recoveryFixedFee),
  });
}

/** 浮点相等：草稿的百分数来回换算会引入舍入误差。 */
function nearlyEqual(a: number, b: number): boolean {
  return Math.abs(a - b) < 1e-9;
}

/** 判断两个收益输入是否等价，用于判断编辑是否影响提醒基线。 */
export function sameReturnInput(a: GoldReturnInput | null, b: GoldReturnInput | null): boolean {
  if (a === null || b === null) return a === b;
  return (
    nearlyEqual(a.grams, b.grams) &&
    nearlyEqual(a.purity, b.purity) &&
    nearlyEqual(a.unitPrice, b.unitPrice) &&
    nearlyEqual(a.laborFee, b.laborFee) &&
    nearlyEqual(a.otherCost, b.otherCost) &&
    nearlyEqual(a.totalCostOverride ?? 0, b.totalCostOverride ?? 0) &&
    (a.totalCostOverride === null) === (b.totalCostOverride === null) &&
    nearlyEqual(a.rule.perGramDeduction, b.rule.perGramDeduction) &&
    nearlyEqual(a.rule.discountRate, b.rule.discountRate) &&
    nearlyEqual(a.rule.fixedFee, b.rule.fixedFee)
  );
}

/**
 * 把草稿落成记录。
 * @param existing 编辑时传入原记录，保留 id、创建时间、账本与处置关联
 * @param now 创建时间，仅新建时使用
 */
export function draftToRecord(
  draft: ReturnType<typeof createDraft>,
  existing: HoldingRecord | null,
  now: number,
): HoldingRecord {
  const input = draft.input();
  if (!input) {
    throw new Error("表单填写无效");
  }

  // 收益输入是否变化：影响提醒的运行基线需要在 D1 重置
  const previousInput = existing
    ? {
        grams: existing.grams,
        purity: existing.purity,
        unitPrice: existing.unitPriceCNY,
        laborFee: existing.laborFee,
        otherCost: existing.extraFee,
        totalCostOverride: existing.purchaseTotalOverride,
        rule: {
          perGramDeduction: existing.recoveryDeduction,
          discountRate: existing.recoveryDiscount,
          fixedFee: existing.recoveryFixedFee,
        },
      }
    : null;
  const unchanged = sameReturnInput(previousInput, input);

  const base: HoldingRecord = existing
    ? { ...existing, alerts: [...existing.alerts] }
    : {
        id: newUUID(),
        grams: input.grams,
        unitPriceCNY: input.unitPrice,
        timestamp: now,
        note: "",
        createdAt: now,
        brand: "",
        bookName: "默认账本",
        disposition: "holding",
        disposedAt: null,
        disposalAmount: 0,
        purchaseID: null,
        extraFee: 0,
        purchaseChannel: "",
        counterparty: "",
        assetType: "金条",
        purity: 1,
        laborFee: 0,
        purchaseTotalOverride: null,
        recoveryDeduction: 0,
        recoveryDiscount: 0,
        recoveryFixedFee: 0,
        alerts: [],
      };

  return {
    ...base,
    grams: input.grams,
    unitPriceCNY: input.unitPrice,
    purity: input.purity,
    laborFee: input.laborFee,
    extraFee: input.otherCost,
    purchaseTotalOverride: input.totalCostOverride,
    recoveryDeduction: input.rule.perGramDeduction,
    recoveryDiscount: input.rule.discountRate,
    recoveryFixedFee: input.rule.fixedFee,
    // 未知类型原样保留
    assetType: draft.assetType,
    brand: trim(draft.brand),
    purchaseChannel: trim(draft.channel),
    note: trim(draft.note),
    // 收益输入变了就不再保留旧提醒配置，避免用旧阈值监测新成本
    alerts: unchanged ? base.alerts : [],
  };
}

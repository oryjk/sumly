/**
 * 盈亏拆解。
 *
 * 移植自 iOS 端 GoldProfitBreakdown.swift。核心是**累计边界舍入**：
 * 逐项独立舍入会让分项之和与总盈亏差一分，因此对累计值取整，
 * 用相邻边界之差作为该项金额——最后一项直接采用总盈亏目标值，
 * 保证分项之和精确等于总盈亏，组合场景同样成立。
 *
 * 归因口径与收益内核一致：手动总价记录不虚构成本拆分，
 * 只以「金值与总投入差额」单列。
 */
import { aggregateReturn, calculateReturn, validPrice, type GoldReturnInput } from "./returns";
import { addCents, moneyCents } from "@/utils/moneyCents";

/** 拆解分项类型。 */
export type BreakdownKind =
  | "price"
  | "purity"
  | "labor"
  | "other"
  | "unitemized"
  | "deduction"
  | "discount"
  | "fixed"
  | "sale";

const KIND_ORDER: BreakdownKind[] = [
  "price",
  "purity",
  "labor",
  "other",
  "unitemized",
  "deduction",
  "discount",
  "fixed",
  "sale",
];

/** 分项标题。 */
export const KIND_TITLES: Record<BreakdownKind, string> = {
  price: "金价变化",
  purity: "纯度折算",
  labor: "购入工费",
  other: "其他购入成本",
  unitemized: "金值与总投入差额",
  deduction: "每克回收扣减",
  discount: "回收比例折价",
  fixed: "固定卖出费用",
  sale: "实际到手与总投入差额",
};

/** 分项说明。 */
export const KIND_EXPLANATIONS: Record<BreakdownKind, string> = {
  price: "当前参考金价与录入的裸金单价之差，按购入克重计算；不代表今天一天的涨跌。",
  purity: "按录入纯度折算有效含金量。它是估值调整，不是一笔额外收费。",
  labor: "购入时支付的工费已计入总投入，回收估值不包含这部分工费。",
  other: "购入时录入的其他成本已计入总投入。",
  unitemized: "这部分记录以手动总价为准。只比较当前含金价值与总投入，不推断其中的裸金价格、工费或其他成本。",
  deduction: "按有效克重扣减，扣减后的金价最低为零。",
  discount: "先扣除每克回收扣减，再按录入比例折价。",
  fixed: "从折价后的金额扣除固定费用；预计到手最低为零，因此此处显示实际影响金额。组合按每笔独立卖出估算。",
  sale: "仅用已记录的实际卖出到手金额减去总投入。未记录成交明细，不能拆分金价与回收费用的贡献。",
};

/** 单条记录在某分项下的贡献。recordIndex 指向原输入数组下标。 */
export interface Contribution {
  recordIndex: number;
  cents: string;
}

/** 一个拆解分项。 */
export interface BreakdownComponent {
  kind: BreakdownKind;
  cents: string;
  contributions: Contribution[];
}

/** 分组方向。 */
export type BreakdownDirection = "increase" | "decrease" | "unchanged";

export const DIRECTION_TITLES: Record<BreakdownDirection, string> = {
  increase: "收益从哪里来",
  decrease: "哪些因素拉低收益",
  unchanged: "无盈亏影响",
};

/** 一个分组。 */
export interface BreakdownGroup {
  direction: BreakdownDirection;
  components: BreakdownComponent[];
  /** 以字符串保存分值，避免大额抵消时溢出。 */
  totalCents: string;
}

export interface GoldProfitBreakdown {
  components: BreakdownComponent[];
  /** 总盈亏分值字符串。 */
  profitCents: string;
  totalCost: number;
  /** 账面金值；卖出拆解为 null。 */
  goldValue: number | null;
  proceeds: number;
  hasUnitemizedCost: boolean;
  hasUnconfiguredRecovery: boolean;
  /** 来源分组；收益来源、影响因素与无影响项。 */
  groups?: BreakdownGroup[];
  /** 取分项金额（元）。 */
  amountFor?: (kind: BreakdownKind) => number;
}

/** 取分项金额。 */
export function amountFor(breakdown: GoldProfitBreakdown, kind: BreakdownKind): number {
  const found = breakdown.components.find((item) => item.kind === kind);
  return found ? Number(found.cents) / 100 : 0;
}

/** 回收规则是否全为默认值。 */
function isDefaultRule(input: GoldReturnInput): boolean {
  const rule = input.rule;
  return rule.perGramDeduction === 0 && rule.discountRate === 0 && rule.fixedFee === 0;
}

/** 按方向分组；组内合计用 BigInt 累加。 */
export function groupBreakdown(components: BreakdownComponent[]): BreakdownGroup[] {
  const buckets: Record<BreakdownDirection, BreakdownComponent[]> = {
    increase: [],
    decrease: [],
    unchanged: [],
  };
  for (const component of components) {
    const value = BigInt(component.cents);
    if (value > 0n) buckets.increase.push(component);
    else if (value < 0n) buckets.decrease.push(component);
    else buckets.unchanged.push(component);
  }
  return (["increase", "decrease", "unchanged"] as BreakdownDirection[])
    .filter((direction) => buckets[direction].length > 0)
    .map((direction) => {
      let total = 0n;
      for (const component of buckets[direction]) {
        total += BigInt(component.cents);
      }
      return { direction, components: buckets[direction], totalCents: total.toString() };
    });
}

/**
 * 估算持仓的盈亏拆解。
 * @param inputs 各笔收益输入，下标用于贡献归属
 * @param referencePrice 参考价（元/克）；缺失或非法返回 null
 */
export function estimateBreakdown(
  inputs: readonly GoldReturnInput[],
  referencePrice: number | null,
): GoldProfitBreakdown | null {
  if (inputs.length === 0) return null;
  const price = validPrice(referencePrice);
  if (price === null) return null;

  const aggregate = aggregateReturn(inputs, price);
  if (!aggregate || aggregate.proceeds === null) return null;
  const target = moneyCents(aggregate.profit ?? Number.NaN);
  if (target === null || aggregate.proceeds === null) return null;

  const values = new Map<BreakdownKind, number>();
  const sources = new Map<BreakdownKind, { recordIndex: number; value: number }[]>();
  let unitemized = false;

  function append(kind: BreakdownKind, value: number, recordIndex: number) {
    values.set(kind, (values.get(kind) ?? 0) + value);
    const list = sources.get(kind) ?? [];
    list.push({ recordIndex, value });
    sources.set(kind, list);
  }

  for (let recordIndex = 0; recordIndex < inputs.length; recordIndex += 1) {
    const input = inputs[recordIndex];
    const result = calculateReturn(input, price);
    if (!result || result.bookValue === null || result.proceeds === null) return null;
    const goldValue = result.bookValue;
    const payout = result.proceeds;
    const nominalValue = price * input.grams;

    if (input.totalCostOverride !== null || !Number.isFinite(nominalValue)) {
      // 手动总价：只比较金值与总投入，不推断成本构成
      unitemized = true;
      append("unitemized", goldValue - result.totalCost, recordIndex);
    } else {
      append("price", nominalValue - input.unitPrice * input.grams, recordIndex);
      append("purity", goldValue - nominalValue, recordIndex);
      append("labor", -input.laborFee, recordIndex);
      append("other", -input.otherCost, recordIndex);
    }

    const deducted = Math.max(0, price - input.rule.perGramDeduction) * result.effectiveGrams;
    const discounted = deducted * (1 - input.rule.discountRate);
    append("deduction", deducted - goldValue, recordIndex);
    append("discount", discounted - deducted, recordIndex);
    append("fixed", payout - discounted, recordIndex);
  }

  // 只保留有实际贡献的分项；全为零时保留一项以免出现空拆解
  let kinds = KIND_ORDER.filter((kind) => (sources.get(kind) ?? []).some((entry) => entry.value !== 0));
  if (kinds.length === 0) {
    kinds = [unitemized ? "unitemized" : "price"];
  }

  // 累计边界舍入：每项取累计值的分，末项直接用总盈亏目标
  const components: BreakdownComponent[] = [];
  let running = 0;
  let previous = "0";

  for (let index = 0; index < kinds.length; index += 1) {
    const kind = kinds[index];
    let recordRunning = running;
    running += values.get(kind) ?? 0;
    const isLast = index === kinds.length - 1;
    const boundary = isLast ? target : moneyCents(running);
    if (boundary === null) return null;
    const delta = (BigInt(boundary) - BigInt(previous)).toString();

    const allSources = sources.get(kind) ?? [];
    const nonzero = allSources.filter((entry) => entry.value !== 0);
    const entries = nonzero.length === 0 ? allSources : nonzero;

    const contributions: Contribution[] = [];
    let recordPrevious = previous;
    for (let entryIndex = 0; entryIndex < entries.length; entryIndex += 1) {
      const entry = entries[entryIndex];
      recordRunning += entry.value;
      const isLastEntry = entryIndex === entries.length - 1;
      const recordBoundary = isLastEntry ? boundary : moneyCents(recordRunning);
      if (recordBoundary === null) return null;
      const recordDelta = (BigInt(recordBoundary) - BigInt(recordPrevious)).toString();
      contributions.push({ recordIndex: entry.recordIndex, cents: recordDelta });
      recordPrevious = recordBoundary;
    }

    components.push({ kind, cents: delta, contributions });
    previous = boundary;
  }

  return withGroups({
    components,
    profitCents: target,
    totalCost: aggregate.totalCost,
    goldValue: aggregate.bookValue,
    proceeds: aggregate.proceeds,
    hasUnitemizedCost: unitemized,
    hasUnconfiguredRecovery: inputs.some(isDefaultRule),
  });
}

/**
 * 附上派生视图：来源分组与分项金额查询。
 * 分组不改变盈亏，只做展示归类。
 */
function withGroups(breakdown: GoldProfitBreakdown): GoldProfitBreakdown {
  return {
    ...breakdown,
    groups: groupBreakdown(breakdown.components),
    amountFor: (kind: BreakdownKind) => amountFor(breakdown, kind),
  };
}

/**
 * 卖出拆解：只用已记录的实际实收，不做市场归因。
 */
export function saleBreakdown(totalCost: number, proceeds: number): GoldProfitBreakdown | null {
  if (!Number.isFinite(totalCost) || totalCost < 0) return null;
  if (!Number.isFinite(proceeds) || proceeds < 0) return null;
  const target = moneyCents(proceeds - totalCost);
  if (target === null) return null;

  return withGroups({
    components: [{ kind: "sale", cents: target, contributions: [{ recordIndex: 0, cents: target }] }],
    profitCents: target,
    totalCost,
    goldValue: null,
    proceeds,
    hasUnitemizedCost: true,
    hasUnconfiguredRecovery: false,
  });
}

/**
 * 黄金收益计算内核。
 *
 * 移植自 iOS 端 GoldReturnCalculator.swift，不依赖任何 UI 与存储：
 * 情景测算、买前计算器、保本反推与目标提醒共用这一份算法。
 *
 * 口径：
 * - 有效克数 = 克数 × 纯度；
 * - 成本 = 实付总额（若填写）或 克数 × 单价 + 总工费 + 其他费用；
 * - 预计回收单价 = max(0, 参考价 − 每克扣减) × (1 − 折价率)；
 * - 预计到手 = max(0, 有效克数 × 回收单价 − 固定费用)；
 * - 真实盈亏 = 到手 − 成本。
 */
import type { HoldingRecord } from "@/types/holdings";

/** 回收参数：折价为「扣减后再折扣」的比例，不是保留比例。 */
export interface GoldRecoveryRule {
  perGramDeduction: number;
  discountRate: number;
  fixedFee: number;
}

/** 单笔计算的输入。 */
export interface GoldReturnInput {
  grams: number;
  purity: number;
  unitPrice: number;
  /** 工费总额；表单负责把按克工费转换成总额。 */
  laborFee: number;
  otherCost: number;
  /** 已支付总额是最终成本，工费与其他费用不再次相加。 */
  totalCostOverride: number | null;
  rule: GoldRecoveryRule;
}

export interface GoldReturnResult {
  totalCost: number;
  effectiveGrams: number;
  /** 账面价值 = 参考价 × 有效克数。 */
  bookValue: number | null;
  recoveryUnitPrice: number | null;
  /** 预计到手。 */
  proceeds: number | null;
  /** 真实盈亏 = 到手 − 成本。 */
  profit: number | null;
  profitPercent: number | null;
  breakEvenPrice: number;
  /** 距保本价的差额。 */
  priceDistance: number | null;
  /** 还需涨幅（保本 / 现价 − 1），已过保本时为 0。 */
  requiredRisePercent: number | null;
  /** 综合单价 = 成本 / 克数。 */
  comprehensiveUnitCost: number;
  premiumPerGram: number | null;
}

export interface GoldPortfolioReturn {
  grams: number;
  totalCost: number;
  bookValue: number | null;
  proceeds: number | null;
  profit: number | null;
  profitPercent: number | null;
  breakEvenPrice: number | null;
  /** 相对前一日价格的影响。 */
  todayChange: number | null;
}

/** 回收规则是否有效。 */
function isValidRule(rule: GoldRecoveryRule): boolean {
  return (
    Number.isFinite(rule.perGramDeduction) &&
    rule.perGramDeduction >= 0 &&
    Number.isFinite(rule.discountRate) &&
    rule.discountRate >= 0 &&
    rule.discountRate < 1 &&
    Number.isFinite(rule.fixedFee) &&
    rule.fixedFee >= 0
  );
}

/** 总成本：实付总额优先，否则按克数推算。 */
function totalCostOf(input: GoldReturnInput): number {
  return input.totalCostOverride ?? input.grams * input.unitPrice + input.laborFee + input.otherCost;
}

/** 输入是否有效。 */
export function isValidInput(input: GoldReturnInput): boolean {
  const effectiveGrams = input.grams * input.purity;
  return (
    Number.isFinite(input.grams) &&
    input.grams > 0 &&
    Number.isFinite(input.purity) &&
    input.purity > 0 &&
    input.purity <= 1 &&
    Number.isFinite(input.unitPrice) &&
    input.unitPrice >= 0 &&
    Number.isFinite(input.laborFee) &&
    input.laborFee >= 0 &&
    Number.isFinite(input.otherCost) &&
    input.otherCost >= 0 &&
    Number.isFinite(totalCostOf(input)) &&
    totalCostOf(input) >= 0 &&
    Number.isFinite(effectiveGrams) &&
    effectiveGrams > 0 &&
    isValidRule(input.rule)
  );
}

/** 规范化参考价：非正或非有限视为无报价。 */
export function validPrice(price: number | null | undefined): number | null {
  if (price === null || price === undefined || !Number.isFinite(price) || price <= 0) {
    return null;
  }
  return price;
}

/**
 * 保本反推：使预计到手恰等于目标金额所需的参考价。
 * 提醒目标与保本共用此反函数；目标为 0 时价格 0 即满足下限。
 */
export function referencePrice(input: GoldReturnInput, targetProceeds: number): number | null {
  if (!isValidInput(input) || !Number.isFinite(targetProceeds) || targetProceeds < 0) {
    return null;
  }
  if (targetProceeds === 0) {
    return 0;
  }
  const effectiveGrams = input.grams * input.purity;
  const price =
    (targetProceeds + input.rule.fixedFee) / (effectiveGrams * (1 - input.rule.discountRate)) +
    input.rule.perGramDeduction;
  return Number.isFinite(price) ? price : null;
}

/** 计算单笔收益。输入非法返回 null。 */
export function calculateReturn(
  input: GoldReturnInput,
  reference: number | null,
): GoldReturnResult | null {
  if (!isValidInput(input)) {
    return null;
  }
  const cost = totalCostOf(input);
  const weight = input.grams * input.purity;
  const rule = input.rule;

  const breakEven = referencePrice(input, cost);
  if (breakEven === null) {
    return null;
  }

  const price = validPrice(reference);
  const bookValue = price === null ? null : price * weight;
  const unit = price === null ? null : Math.max(0, price - rule.perGramDeduction) * (1 - rule.discountRate);
  const proceeds = unit === null ? null : Math.max(0, unit * weight - rule.fixedFee);

  if (proceeds !== null && !Number.isFinite(proceeds)) return null;
  if (bookValue !== null && !Number.isFinite(bookValue)) return null;

  const profit = proceeds === null ? null : proceeds - cost;
  // 零成本时收益率无定义
  const percent = cost > 0 && profit !== null ? (profit / cost) * 100 : null;
  const distance = price === null ? null : price - breakEven;
  const rise = price === null ? null : Math.max(0, breakEven / price - 1) * 100;
  const unitCost = cost / input.grams;
  const premium = price === null ? null : unitCost - price;

  for (const value of [percent, distance, rise, premium, unitCost]) {
    if (value !== null && !Number.isFinite(value)) return null;
  }

  return {
    totalCost: cost,
    effectiveGrams: weight,
    bookValue,
    recoveryUnitPrice: unit,
    proceeds,
    profit,
    profitPercent: percent,
    breakEvenPrice: breakEven,
    priceDistance: distance,
    requiredRisePercent: rise,
    comprehensiveUnitCost: unitCost,
    premiumPerGram: premium,
  };
}

/**
 * 组合收益。
 * 保本价用二分求解：每笔到手都有 0 下限且回收规则可能不同，
 * 不能用单笔保本的均值代替。
 */
export function aggregateReturn(
  inputs: readonly GoldReturnInput[],
  reference: number | null,
  previousPrice: number | null = null,
): GoldPortfolioReturn | null {
  if (inputs.length === 0 || !inputs.every(isValidInput)) {
    return null;
  }
  const results = inputs.map((input) => calculateReturn(input, reference));
  if (results.some((result) => result === null)) {
    return null;
  }
  const valid = results as GoldReturnResult[];

  const cost = valid.reduce((sum, result) => sum + result.totalCost, 0);
  const grams = inputs.reduce((sum, input) => sum + input.grams, 0);
  if (!Number.isFinite(cost) || !Number.isFinite(grams)) {
    return null;
  }

  const hasQuote = validPrice(reference) !== null;
  const proceeds = hasQuote ? valid.reduce((sum, result) => sum + (result.proceeds ?? 0), 0) : null;
  const value = hasQuote ? valid.reduce((sum, result) => sum + (result.bookValue ?? 0), 0) : null;
  const profit = proceeds === null ? null : proceeds - cost;

  // 组合保本：80 轮二分，容差远低于分厘级显示需求
  let breakEven: number | null = null;
  {
    let low = 0;
    let high = valid.reduce((max, result) => Math.max(max, result.breakEvenPrice), 0);
    for (let round = 0; round < 80; round += 1) {
      const middle = low + (high - low) / 2;
      const total = inputs.reduce(
        (sum, input) => sum + (calculateReturn(input, middle)?.proceeds ?? 0),
        0,
      );
      if (total >= cost) {
        high = middle;
      } else {
        low = middle;
      }
    }
    breakEven = high;
  }

  const previous = validPrice(previousPrice);
  const previousProceeds =
    previous === null || !hasQuote
      ? null
      : inputs.reduce((sum, input) => sum + (calculateReturn(input, previous)?.proceeds ?? 0), 0);
  const percent = cost > 0 && profit !== null ? (profit / cost) * 100 : null;
  const change = proceeds !== null && previousProceeds !== null ? proceeds - previousProceeds : null;

  for (const value2 of [proceeds, value, profit, percent, change]) {
    if (value2 !== null && !Number.isFinite(value2)) return null;
  }

  return {
    grams,
    totalCost: cost,
    bookValue: value,
    proceeds,
    profit,
    profitPercent: percent,
    breakEvenPrice: breakEven,
    todayChange: change,
  };
}

/** 从持仓记录构造收益输入。 */
export function returnInput(record: HoldingRecord): GoldReturnInput {
  return {
    grams: record.grams,
    purity: record.purity,
    unitPrice: record.unitPriceCNY,
    laborFee: record.laborFee,
    otherCost: record.extraFee,
    totalCostOverride: record.purchaseTotalOverride,
    rule: {
      perGramDeduction: record.recoveryDeduction,
      discountRate: record.recoveryDiscount,
      fixedFee: record.recoveryFixedFee,
    },
  };
}

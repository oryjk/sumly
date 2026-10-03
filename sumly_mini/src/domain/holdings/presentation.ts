/**
 * 持仓金额与比例的展示格式化。
 *
 * 约定：
 * - 金额隐藏时统一显示占位符，不泄露真实数值；
 * - 展示才舍入，核心计算与云文档保留原精度；
 * - 非有限值不进展示，避免 NaN 出现在界面上。
 */

/** 金额隐藏时的占位符。 */
export const HIDDEN_PLACEHOLDER = "****";

/** 缺失值的占位符。 */
export const EMPTY_PLACEHOLDER = "--";

/** 金额千分位分隔。 */
const GROUP_SEPARATOR = ",";

function groupDigits(digits: string): string {
  let result = "";
  for (let index = 0; index < digits.length; index += 1) {
    const positionFromRight = digits.length - index;
    result += digits[index];
    if (positionFromRight > 1 && (positionFromRight - 1) % 3 === 0) {
      result += GROUP_SEPARATOR;
    }
  }
  return result;
}

export interface MoneyFormatOptions {
  /** 小数位数，默认 2。 */
  digits?: number;
  /** 单位后缀，如 "g"。 */
  unit?: string;
}

/**
 * 格式化金额。
 * @param value 数值；null / 非有限显示为 "--"
 * @param hidden 为 true 时显示占位符
 * @param signed 为 true 时正数带 "+" 前缀
 */
export function formatMoney(
  value: number | null | undefined,
  hidden: boolean,
  signed = false,
  options: MoneyFormatOptions = {},
): string {
  if (hidden) {
    return HIDDEN_PLACEHOLDER;
  }
  if (value === null || value === undefined || !Number.isFinite(value)) {
    return EMPTY_PLACEHOLDER;
  }
  const digits = options.digits ?? 2;
  const text = Math.abs(value).toFixed(digits);
  const [integer, fraction] = text.split(".");
  const grouped = groupDigits(integer);
  const body = fraction ? `${grouped}.${fraction}` : grouped;
  const sign = value < 0 ? "-" : signed && value > 0 ? "+" : "";
  return `${sign}${body}${options.unit ?? ""}`;
}

/** 带符号的金额，用于涨跌展示。 */
export function formatSignedMoney(
  value: number | null | undefined,
  hidden: boolean,
  options: MoneyFormatOptions = {},
): string {
  return formatMoney(value, hidden, true, options);
}

/** 格式化百分比，固定带 % 与符号。 */
export function formatPercent(value: number | null | undefined, hidden: boolean, digits = 2): string {
  if (hidden) {
    return HIDDEN_PLACEHOLDER;
  }
  if (value === null || value === undefined || !Number.isFinite(value)) {
    return EMPTY_PLACEHOLDER;
  }
  const sign = value < 0 ? "-" : value > 0 ? "+" : "";
  return `${sign}${Math.abs(value).toFixed(digits)}%`;
}

/** 格式化克数，带单位后缀。 */
export function formatGrams(value: number | null | undefined, hidden: boolean, digits = 2): string {
  return formatMoney(value, hidden, false, { digits, unit: "g" });
}

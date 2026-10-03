/**
 * 金额分值运算。
 *
 * 拆解的分项之和必须**精确等于**总盈亏，若用 JS 浮点累加会出现
 * 「明细加起来和总额差一分钱」。因此以十进制整数字符串保存分值，
 * 运算走 BigInt，舍入采用 Foundation 的十进制半偶舍入
 * （0.125 元 = 12.5 分 -> 12 分，与 Swift 展示一致）。
 *
 * 元→分的换算全程走字符串，避免 `value * 100` 在大额时先丢精度：
 * 92233720368547758.07 乘 100 超出 Number 安全整数，直接用浮点会得到null。
 *
 * 超出 Int64 范围返回 null，由调用方拒绝展示，而不是给出错误金额。
 */

/** Int64 上界。 */
const INT64_MAX = 9223372036854775807n;
/** Int64 下界。 */
const INT64_MIN = -9223372036854775808n;

/**
 * 把元金额转为分值字符串；非法或越界返回 null。
 *
 * 用十进制字符串拆分整数与小数：小数部分左移两位即得分的绝对值，
 * 再按半偶舍入决定进位。整个过程不经过浮点乘法。
 */
export function moneyCents(value: number): string | null {
  if (!Number.isFinite(value)) return null;

  const negative = value < 0;
  const text = Math.abs(value).toString();

  // 指数形式（如 1e-7）交给浮点路径，量级极小不会造成精度问题
  if (text.includes("e") || text.includes("E")) {
    return fromScaled(value * 100);
  }

  const [integerPart = "0", fractionPart = ""] = text.split(".");
  // 分 = 整数部分 × 100 + 小数部分左移两位
  const scaledInteger = BigInt(integerPart) * 100n;
  // 不足两位的补零，超过两位的按第三位做半偶舍入
  const padded = (fractionPart + "000").slice(0, 3);
  const centsFromFraction = BigInt(padded.slice(0, 2));
  const roundDigit = Number(padded.charAt(2) || "0");
  const restNonZero = padded.slice(2).replace(/^0+$/, "").length > 0 && fractionPart.length > 3
    ? /[1-9]/.test(fractionPart.slice(3))
    : false;

  let cents = scaledInteger + centsFromFraction;
  if (roundDigit > 5 || (roundDigit === 5 && (restNonZero || centsFromFraction % 2n === 1n))) {
    cents += 1n;
  }

  const signed = negative ? -cents : cents;
  if (signed > INT64_MAX || signed < INT64_MIN) return null;
  return signed.toString();
}

/** 浮点兜底路径：小数位足够时结果可靠。 */
function fromScaled(scaled: number): string | null {
  if (!Number.isFinite(scaled)) return null;
  const rounded = roundHalfEven(scaled);
  const cents = BigInt(Math.trunc(rounded));
  if (cents > INT64_MAX || cents < INT64_MIN) return null;
  return cents.toString();
}

/** 银行家舍入：正好一半时取偶数。 */
function roundHalfEven(value: number): number {
  const floor = Math.floor(value);
  const diff = value - floor;
  if (diff > 0.5) return floor + 1;
  if (diff < 0.5) return floor;
  return floor % 2 === 0 ? floor : floor + 1;
}

/** 分值求和。 */
export function addCents(a: string, b: string): string {
  return (BigInt(a) + BigInt(b)).toString();
}

/** 分值比较。 */
export function compareCents(a: string, b: string): -1 | 0 | 1 {
  const left = BigInt(a);
  const right = BigInt(b);
  if (left < right) return -1;
  if (left > right) return 1;
  return 0;
}

/** 分值减法。 */
export function subtractCents(a: string, b: string): string {
  return (BigInt(a) - BigInt(b)).toString();
}

/** 分值求和，越界返回 null。 */
export function sumCents(values: readonly string[]): string | null {
  let total = 0n;
  for (const value of values) {
    total += BigInt(value);
  }
  if (total > INT64_MAX || total < INT64_MIN) return null;
  return total.toString();
}

/** 分值转元金额。 */
export function centsToMoney(cents: string): number {
  return Number(cents) / 100;
}

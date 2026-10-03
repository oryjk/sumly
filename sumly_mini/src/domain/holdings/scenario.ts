/**
 * 情景测算。
 *
 * 沿用持仓参数，只替换参考价做「如果金价变成 X 会怎样」的推演，
 * **不修改任何实际记录**。与 App 的 GoldScenarioSheet 同口径。
 */
import { calculateReturn, type GoldReturnInput, type GoldReturnResult } from "./returns";

/** 快捷涨跌幅档位，与 App 一致。 */
export const SCENARIO_STEPS = [-0.1, -0.05, 0.05, 0.1] as const;

/** 按给定参考价计算收益；参考价或输入非法时返回 null。 */
export function scenarioReturn(input: GoldReturnInput, price: number | null): GoldReturnResult | null {
  return calculateReturn(input, price);
}

/** 生成各档位的参考价，便于页面直接展示。 */
export function scenarioPrices(base: number, steps: readonly number[] = SCENARIO_STEPS): { label: string; price: number }[] {
  return steps.map((step) => ({
    label: `${step > 0 ? "+" : ""}${Math.round(step * 100)}%`,
    price: base * (1 + step),
  }));
}

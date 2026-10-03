/**
 * 价格刻度：对数与线性两种标度。
 * 对应 iOS 端 ChartPriceScale。padding 取波幅的 25% 并保底，
 * 避免固定微小波动把整图放大。
 */
import type { ChartPoint } from "@/types/market";

export type PriceScaleKind = "linear" | "logarithmic";

export interface PriceDomain {
  min: number;
  max: number;
}

/** 线性标度下最小 padding，保证零波动时也有可视区间。 */
const MIN_LINEAR_PADDING = 0.5;
/** 对数标度下最小 padding。 */
const MIN_LOG_PADDING = 0.01;

/** 标度变换：非法或非正价格不参与。 */
export function scaleValue(price: number, kind: PriceScaleKind): number | null {
  if (!Number.isFinite(price) || price <= 0) return null;
  return kind === "linear" ? price : Math.log10(price);
}

/** 反向变换，用于把标度值还原成真实价格。 */
export function unscaleValue(value: number, kind: PriceScaleKind): number {
  return kind === "linear" ? value : 10 ** value;
}

/** 计算价格域。非法价格被忽略；空数据返回安全区间。 */
export function priceScale(
  points: readonly ChartPoint[],
  kind: PriceScaleKind = "linear",
): PriceDomain {
  const values: number[] = [];
  for (const point of points) {
    const value = scaleValue(point.price, kind);
    if (value !== null) values.push(value);
  }
  if (values.length === 0) {
    return { min: 0, max: 1 };
  }
  const low = Math.min(...values);
  const high = Math.max(...values);
  const center = low / 2 + high / 2;
  const padding = Math.max(
    (high - low) * 0.25,
    kind === "linear" ? MIN_LINEAR_PADDING : MIN_LOG_PADDING,
  );
  return { min: low - padding, max: Math.max(high + padding, center + padding) };
}

/** 在价格域内生成稳定的刻度值，避免微小波动产生跳变标签。 */
export function priceTicks(domain: PriceDomain, count = 4): number[] {
  if (domain.max <= domain.min) {
    return [domain.min];
  }
  const step = (domain.max - domain.min) / count;
  const ticks: number[] = [];
  for (let index = 0; index <= count; index += 1) {
    ticks.push(domain.min + step * index);
  }
  return ticks;
}

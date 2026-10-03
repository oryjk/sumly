/**
 * 行情接口封装。
 * 路径与后端 sumly_go 路由一致；响应统一消费 { code, message, data } envelope。
 * 国际与国内走不同端点：国内使用 instruments 路径。
 */
import { requestRaw } from "@/utils/request";
import type { GoldQuote, GoldRealtime, MarketBasis, MarketSeries, MarketSyncPage } from "@/types/market";
import type { BackendApiResponse } from "@/types/backend";

/** 口径对应的历史序列品种。 */
export function seriesOf(basis: MarketBasis): MarketSeries {
  return basis === "domestic" ? "au9999" : "xauusd";
}

/** 国内 Au99.99 走 instruments 端点，国际伦敦金走根路径。 */
function quotePath(basis: MarketBasis, suffix: "quote" | "realtime"): string {
  return basis === "domestic"
    ? `/market/gold/instruments/au9999/${suffix}`
    : `/market/gold/${suffix}`;
}

/** 取出 envelope 的 data；缺失时抛出可读错误，不返回空壳对象。 */
function unwrap<T>(response: BackendApiResponse<T>, context: string): T {
  if (response.data === null || response.data === undefined) {
    throw new Error(`${context}响应缺少数据`);
  }
  return response.data;
}

/** 拉取当前口径的报价。 */
export async function getGoldQuote(basis: MarketBasis): Promise<GoldQuote> {
  const response = await requestRaw<BackendApiResponse<GoldQuote>>({ url: quotePath(basis, "quote") });
  return unwrap(response, "报价");
}

/** 拉取以最后有效行情为终点的二十分钟走势。 */
export async function getGoldRealtime(basis: MarketBasis): Promise<GoldRealtime> {
  const response = await requestRaw<BackendApiResponse<GoldRealtime>>({
    url: quotePath(basis, "realtime"),
  });
  return unwrap(response, "实时走势");
}

/** 拉取增量历史。首次省略 cursor，服务端返回完整快照。 */
export async function getMarketSync(series: MarketSeries, cursor?: string): Promise<MarketSyncPage> {
  const query = cursor ? `?series=${series}&cursor=${encodeURIComponent(cursor)}` : `?series=${series}`;
  const response = await requestRaw<BackendApiResponse<MarketSyncPage>>({
    url: `/market/gold/sync${query}`,
  });
  return unwrap(response, "历史同步");
}

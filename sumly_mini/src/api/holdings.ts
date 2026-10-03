/**
 * 持仓云同步接口。
 *
 * GET 走**原始文本**响应：revision 是 int64，超过 2^53 的值无法用
 * JS number精确表示，先 JSON.parse 会静默舍入导致 CAS 失效。
 */
import { requestRaw } from "@/utils/request";
import { decodeHoldingSnapshot, encodeHoldingPut, type HoldingSnapshot } from "@/utils/holdingWire";
import type { HoldingDocument } from "@/types/holdings";

/** 拉取云端快照。 */
export async function getHoldings(): Promise<HoldingSnapshot> {
  const raw = await requestRawText({ url: "/holdings", method: "GET", auth: true });
  return decodeHoldingSnapshot(raw);
}

/**
 * 以指定 revision 提交文档。
 * 成功返回新的快照；revision 不匹配时服务端返回 409，由调用方重取并合并。
 */
export async function putHoldings(
  expectedRevision: string,
  document: HoldingDocument,
): Promise<HoldingSnapshot> {
  const body = encodeHoldingPut(expectedRevision, document);
  const raw = await requestRawText({
    url: "/holdings",
    method: "PUT",
    data: body,
    auth: true,
  });
  return decodeHoldingSnapshot(raw);
}

/** 读取原始文本响应，供需要保留词法值的场景使用。 */
async function requestRawText(options: {
  url: string;
  method: "GET" | "PUT";
  data?: string;
  auth: boolean;
}): Promise<string> {
  const { buildAppApiUrl, getApiBaseUrl } = await import("@/config/apiBase");
  const { isMockEnabled, tryMockRequest } = await import("@/mock");
  const { getSession } = await import("@/utils/sessionBridge");

  const requestUrl = buildAppApiUrl(getApiBaseUrl(), options.url);
  if (isMockEnabled()) {
    const mocked = tryMockRequest(options.method, requestUrl, options.data);
    if (mocked === null) {
      throw new Error(`mock 模式未覆盖该接口: ${options.method} ${options.url}`);
    }
    return JSON.stringify(mocked);
  }

  return new Promise<string>((resolve, reject) => {
    const session = getSession();
    const token = session.accessToken.value;
    uni.request({
      url: requestUrl,
      method: options.method as never,
      data: options.data,
      header: {
        "Content-Type": "application/json",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      success: (response) => {
        const { statusCode, data } = response;
        if (statusCode >= 200 && statusCode < 300) {
          // 保留原始文本，不做 parse
          resolve(typeof data === "string" ? data : JSON.stringify(data));
          return;
        }
        const message =
          typeof data === "object" && data && "message" in data
            ? String((data as { message?: string }).message || "同步失败")
            : `同步失败(${statusCode})`;
        const error = new Error(message) as Error & { statusCode: number };
        error.statusCode = statusCode;
        reject(error);
      },
      fail: (error) => {
        reject(new Error(error.errMsg || "网络请求失败"));
      },
    });
  });
}

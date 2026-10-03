/**
 * 持仓快照的线上编解码。
 *
 * revision 是 int64，JS number 无法精确表示超过 2^53 的值。
 * 因此 GET 响应按**原始文本**解析：用一个只关心结构的 JSON 扫描器
 * 定位 `data.revision` 的词法值，而不是先 JSON.parse 再取值——
 * 后者会把大revision 静默舍入成另一个数，CAS 就会失效。
 *
 * PUT 仍以 JSON 整数输出，与服务端契约一致。
 */
import { validateDocument } from "@/domain/holdings/document";
import type { HoldingDocument } from "@/types/holdings";

/** Int64 上界的十进制字符串。 */
export const MAX_REVISION = "9223372036854775807";

/** 服务端快照。 */
export interface HoldingSnapshot {
  /** 十进制字符串，范围 [0, 2^63)。 */
  revision: string;
  document: HoldingDocument;
}

/** 校验 revision 词法值：非负十进制整数且在 Int64 内。 */
function isValidRevision(value: string): boolean {
  if (!/^(0|[1-9][0-9]*)$/.test(value)) return false;
  return BigInt(value) <= BigInt(MAX_REVISION);
}

/**
 * 从 JSON 文本中定位指定路径的词法值（字符串内容或数字原文）。
 * 只做结构扫描，不构造 JS 值，因此大整数不会被舍入。
 */
function scanToken(text: string, path: readonly string[]): string | null {
  let index = 0;

  function skipWhitespace(): void {
    while (index < text.length && /\s/.test(text[index])) index += 1;
  }

  /** 跳过一个 JSON 字符串（含转义），结束时 index 指向结束引号之后。 */
  function skipString(): void {
    index += 1;
    while (index < text.length) {
      const char = text[index];
      if (char === "\\") {
        index += 2;
        continue;
      }
      index += 1;
      if (char === '"') return;
    }
  }

  /** 读取一个字符串的解码后内容，index 需指向起始引号。 */
  function readString(): string {
    const start = index;
    skipString();
    return JSON.parse(text.slice(start, index)) as string;
  }

  /** 跳过一个值。 */
  function skipValue(): void {
    skipWhitespace();
    const char = text[index];
    if (char === '"') {
      skipString();
      return;
    }
    if (char === "{" || char === "[") {
      const open = char;
      const close = open === "{" ? "}" : "]";
      index += 1;
      let depth = 1;
      while (index < text.length && depth > 0) {
        const current = text[index];
        if (current === '"') {
          skipString();
          continue;
        }
        if (current === open) depth += 1;
        else if (current === close) depth -= 1;
        index += 1;
      }
      return;
    }
    while (index < text.length && !/[,}\]\s]/.test(text[index])) index += 1;
  }

  function seekObject(key: string, depth: number): string | null {
    skipWhitespace();
    if (text[index] !== "{") return null;
    index += 1;
    for (;;) {
      skipWhitespace();
      if (index >= text.length) return null;
      if (text[index] === "}") {
        index += 1;
        return null;
      }
      if (text[index] === ",") {
        index += 1;
        continue;
      }
      if (text[index] !== '"') return null;
      const name = readString();
      skipWhitespace();
      if (text[index] !== ":") return null;
      index += 1;

      if (name === key) {
        if (depth === 0) {
          // 命中目标：读原始词法值
          skipWhitespace();
          if (text[index] === '"') return readString();
          const start = index;
          while (index < text.length && !/[,}\s]/.test(text[index])) index += 1;
          return text.slice(start, index);
        }
        return seekObject(path[depth], depth - 1);
      }
      skipValue();
    }
  }

  if (path.length === 0) return null;
  return seekObject(path[0], path.length - 1);
}

/** 读取 envelope 的 code。 */
function scanCode(text: string): number {
  const match = /"code"\s*:\s*(-?\d+)/.exec(text);
  return match ? Number(match[1]) : 0;
}

/**
 * 解析 GET 响应原文。
 * 保留 revision 的完整词法值，document 走标准 JSON.parse 后按服务端规则校验。
 */
export function decodeHoldingSnapshot(rawJson: string): HoldingSnapshot {
  let envelope: { code: number; message?: string; data?: unknown };
  try {
    envelope = JSON.parse(rawJson) as typeof envelope;
  } catch {
    throw new Error("持仓响应不是合法 JSON");
  }
  if (!envelope || typeof envelope !== "object") {
    throw new Error("持仓响应格式无效");
  }
  if (envelope.code !== 0) {
    throw new Error(envelope.message || "持仓读取失败");
  }
  if (!envelope.data || typeof envelope.data !== "object") {
    throw new Error("持仓响应缺少数据");
  }

  // 从原文取 revision，避免 JSON.parse 舍入
  const rawRevision = scanToken(rawJson, ["data", "revision"]);
  if (rawRevision === null) {
    throw new Error("持仓响应缺少 revision");
  }
  if (!isValidRevision(rawRevision)) {
    throw new Error("持仓 revision 非法");
  }

  const data = envelope.data as { document?: unknown };
  if (!data.document || typeof data.document !== "object") {
    throw new Error("持仓响应缺少文档");
  }
  const document = validateDocument(data.document);
  return { revision: rawRevision, document };
}

/** 从已解析的响应对象取 revision（用于无法拿到原文的场景）。 */
export function readRevisionFromText(rawJson: string): string | null {
  const value = scanToken(rawJson, ["data", "revision"]);
  return value !== null && isValidRevision(value) ? value : null;
}

/**
 * 编码 PUT 请求体。
 * expectedRevision 以 JSON 整数输出，但不能经过 Number()——
 * 那会把超过 2^53 的 revision 舍入成另一个值，服务端 CAS 随即失效。
 * 这里先序列化文档，再把 revision 的十进制词法值直接拼进 JSON。
 */
export function encodeHoldingPut(expectedRevision: string, document: HoldingDocument): string {
  if (!isValidRevision(expectedRevision)) {
    throw new Error("expectedRevision 非法");
  }
  const payload = JSON.stringify({
    document: {
      schemaVersion: document.schemaVersion,
      books: document.books,
      records: document.records,
    },
  });
  // 去掉外层 {} 后拼入整数形式的 expectedRevision
  const inner = payload.slice(1, -1);
  return `{"expectedRevision":${expectedRevision},${inner}}`;
}

export { scanCode };

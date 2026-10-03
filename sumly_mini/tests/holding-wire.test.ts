import { describe, expect, it } from "bun:test";
import { decodeHoldingSnapshot, encodeHoldingPut, MAX_REVISION } from "../src/utils/holdingWire";
import { emptyDocument, type HoldingDocument } from "../src/types/holdings";

const UUID_A = "11111111-1111-1111-1111-111111111111";

function envelope(revision: string, extra = ""): string {
  return `{"code":0,"message":"ok","data":{"revision":${revision},"document":{"schemaVersion":1,"books":["默认账本"],"records":[]}${extra}}}`;
}

describe("revision 精度", () => {
  it("保留超出安全整数的 revision", () => {
    // 9007199254740993 = 2^53 + 1，JS number 无法精确表示
    const snapshot = decodeHoldingSnapshot(envelope("9007199254740993"));
    expect(snapshot.revision).toBe("9007199254740993");
  });

  it("普通 revision 保持字符串形态", () => {
    expect(decodeHoldingSnapshot(envelope("42")).revision).toBe("42");
  });

  it("不接受超出 Int64 上界的 revision", () => {
    expect(() => decodeHoldingSnapshot(envelope("9223372036854775808"))).toThrow();
  });

  it("接受 Int64 上界", () => {
    expect(decodeHoldingSnapshot(envelope(MAX_REVISION)).revision).toBe(MAX_REVISION);
  });

  it("拒绝负数与非数字", () => {
    expect(() => decodeHoldingSnapshot(envelope("-1"))).toThrow();
    expect(() => decodeHoldingSnapshot(envelope('"abc"'))).toThrow();
  });
});

describe("结构化解析", () => {
  it("字符串中出现 revision 不影响解码", () => {
    const json = `{"code":0,"message":"ok","data":{"revision":7,"document":{"schemaVersion":1,"books":["默认账本"],"records":[
      {"id":"${UUID_A}","grams":10,"unitPriceCNY":500,"timestamp":1757000000000,"note":"revision: 999 的备注","createdAt":1757000000000,"brand":"","bookName":"默认账本","disposition":"holding","disposedAt":null,"disposalAmount":0,"purchaseID":null,"extraFee":0,"purchaseChannel":"","counterparty":"","assetType":"金条","purity":1,"laborFee":0,"purchaseTotalOverride":null,"recoveryDeduction":0,"recoveryDiscount":0,"recoveryFixedFee":0,"alerts":[]}
    ]}}}`;
    const snapshot = decodeHoldingSnapshot(json);
    expect(snapshot.revision).toBe("7");
    expect(snapshot.document.records[0].note).toBe("revision: 999 的备注");
  });

  it("缺少 data 时报错", () => {
    expect(() => decodeHoldingSnapshot('{"code":0,"message":"ok"}')).toThrow();
  });

  it("缺少 document 时报错", () => {
    expect(() => decodeHoldingSnapshot('{"code":0,"message":"ok","data":{"revision":1}}')).toThrow();
  });

  it("非零 code 视为失败", () => {
    expect(() => decodeHoldingSnapshot('{"code":401,"message":"未登录","data":null}')).toThrow();
  });
});

describe("日期精度", () => {
  it("小数毫秒原样保留", () => {
    const json = `{"code":0,"message":"ok","data":{"revision":1,"document":{"schemaVersion":1,"books":["默认账本"],"records":[
      {"id":"${UUID_A}","grams":10,"unitPriceCNY":500,"timestamp":1757000000123.456,"note":"","createdAt":1757000000123.456,"brand":"","bookName":"默认账本","disposition":"holding","disposedAt":null,"disposalAmount":0,"purchaseID":null,"extraFee":0,"purchaseChannel":"","counterparty":"","assetType":"金条","purity":1,"laborFee":0,"purchaseTotalOverride":null,"recoveryDeduction":0,"recoveryDiscount":0,"recoveryFixedFee":0,"alerts":[]}
    ]}}}`;
    const snapshot = decodeHoldingSnapshot(json);
    expect(snapshot.document.records[0].timestamp).toBe(1757000000123.456);
  });
});

describe("PUT 编码", () => {
  it("revision 以整数而非字符串输出", () => {
    const body = encodeHoldingPut("9007199254740993", emptyDocument());
    expect(body).toContain('"expectedRevision":9007199254740993');
    expect(body).not.toContain('"expectedRevision":"');
  });

  it("包含文档", () => {
    const document: HoldingDocument = {
      schemaVersion: 1,
      books: ["默认账本"],
      records: [],
    };
    const body = encodeHoldingPut("1", document);
    expect(body).toContain('"schemaVersion":1');
  });
});

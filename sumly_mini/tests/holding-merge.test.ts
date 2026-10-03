import { describe, expect, it } from "bun:test";
import { mergeDocuments } from "../src/domain/holdings/merge";
import { emptyDocument, type HoldingDocument, type HoldingRecord } from "../src/types/holdings";

const A = "11111111-1111-1111-1111-111111111111";
const B = "22222222-2222-2222-2222-222222222222";
const C = "33333333-3333-3333-3333-333333333333";
const T0 = 1_757_000_000_000;

function record(overrides: Partial<HoldingRecord> = {}): HoldingRecord {
  return {
    id: A, grams: 10, unitPriceCNY: 500, timestamp: T0, note: "",
    createdAt: T0, brand: "", bookName: "默认账本", disposition: "holding",
    disposedAt: null, disposalAmount: 0, purchaseID: null, extraFee: 0,
    purchaseChannel: "", counterparty: "", assetType: "金条", purity: 1,
    laborFee: 0, purchaseTotalOverride: null, recoveryDeduction: 0,
    recoveryDiscount: 0, recoveryFixedFee: 0, alerts: [],
    ...overrides,
  };
}

function doc(records: HoldingRecord[]): HoldingDocument {
  return { schemaVersion: 1, books: ["默认账本"], records };
}

describe("无冲突合并", () => {
  it("两端相同则无冲突", () => {
    const base = doc([record()]);
    const result = mergeDocuments(base, base, base);
    expect(result.conflicts).toEqual([]);
    expect(result.document.records).toHaveLength(1);
  });

  it("本地新增保留", () => {
    const base = doc([]);
    const local = doc([record({ id: A })]);
    const remote = doc([]);
    const result = mergeDocuments(base, local, remote);
    expect(result.document.records).toHaveLength(1);
    expect(result.conflicts).toEqual([]);
  });

  it("远端新增保留", () => {
    const base = doc([]);
    const local = doc([]);
    const remote = doc([record({ id: A })]);
    const result = mergeDocuments(base, local, remote);
    expect(result.document.records).toHaveLength(1);
  });

  it("仅一端编辑时取该端", () => {
    const base = doc([record({ id: A, note: "原" })]);
    const local = doc([record({ id: A, note: "本地改" })]);
    const remote = base;
    expect(mergeDocuments(base, local, remote).document.records[0].note).toBe("本地改");
    expect(mergeDocuments(base, remote, local).document.records[0].note).toBe("本地改");
  });

  it("一端删除、另一端未改时采用删除", () => {
    // 与 Swift HoldingCloudMerge 一致：nil 表示删除。
    // 远端等于 base 说明它没动过，因此采纳本地的删除。
    const base = doc([record({ id: A })]);
    const local = doc([]);
    const remote = base;
    const result = mergeDocuments(base, local, remote);
    expect(result.document.records).toHaveLength(0);
    expect(result.conflicts).toEqual([]);
  });

  it("一端删除、另一端同时编辑才算冲突", () => {
    const base = doc([record({ id: A, note: "原" })]);
    const local = doc([]);
    const remote = doc([record({ id: A, note: "远端改了" })]);
    const result = mergeDocuments(base, local, remote);
    expect(result.conflicts).toContain(A);
  });
});

describe("真冲突", () => {
  it("两端都改同一记录则标记冲突", () => {
    const base = doc([record({ id: A, note: "原" })]);
    const local = doc([record({ id: A, note: "本地" })]);
    const remote = doc([record({ id: A, note: "远端" })]);
    const result = mergeDocuments(base, local, remote);
    expect(result.conflicts).toContain(A);
  });

  it("默认取本地", () => {
    const base = doc([record({ id: A, note: "原" })]);
    const local = doc([record({ id: A, note: "本地" })]);
    const remote = doc([record({ id: A, note: "远端" })]);
    expect(mergeDocuments(base, local, remote).document.records[0].note).toBe("本地");
  });

  it("指定远端时取远端", () => {
    const base = doc([record({ id: A, note: "原" })]);
    const local = doc([record({ id: A, note: "本地" })]);
    const remote = doc([record({ id: A, note: "远端" })]);
    expect(mergeDocuments(base, local, remote, "remote").document.records[0].note).toBe("远端");
  });

  it("编辑对删除也是冲突", () => {
    const base = doc([record({ id: A, note: "原" })]);
    const local = doc([]);
    const remote = doc([record({ id: A, note: "远端改了" })]);
    const result = mergeDocuments(base, local, remote);
    expect(result.conflicts).toContain(A);
  });
});

describe("UUID 大小写", () => {
  it("大小写不同视为同一条记录", () => {
    const base = doc([record({ id: A })]);
    const local = doc([record({ id: A.toUpperCase() })]);
    const result = mergeDocuments(base, local, base);
    expect(result.conflicts).toEqual([]);
    expect(result.document.records).toHaveLength(1);
  });

  it("合并结果统一小写", () => {
    const base = doc([record({ id: A })]);
    const local = doc([record({ id: A.toUpperCase() })]);
    expect(mergeDocuments(base, local, base).document.records[0].id).toBe(A);
  });
});

describe("购入族作为合并单元", () => {
  it("同族记录跨版本链接形成一组", () => {
    // base 里购入与处置都已存在；两端各自新增一笔处置
    const base = doc([
      record({ id: A, grams: 10 }),
      record({ id: B, grams: 4, purchaseID: A, disposition: "sold", disposedAt: T0 + 1000, disposalAmount: 2500 }),
    ]);
    const local = doc([
      record({ id: A, grams: 6 }),
      record({ id: B, grams: 4, purchaseID: A, disposition: "sold", disposedAt: T0 + 1000, disposalAmount: 2500 }),
      record({ id: C, grams: 2, purchaseID: A, disposition: "sold", disposedAt: T0 + 3000, disposalAmount: 1200 }),
    ]);
    const remote = doc([
      record({ id: A, grams: 6 }),
      record({ id: B, grams: 4, purchaseID: A, disposition: "sold", disposedAt: T0 + 1000, disposalAmount: 2500 }),
    ]);

    const result = mergeDocuments(base, local, remote);
    // 本地新增的处置与远端对购入的改动都在同一族内，按本地一侧解决
    const ids = result.document.records.map((r) => r.id).sort();
    expect(ids).toEqual([A, B, C].sort());
  });

  it("购入族内冲突整体标记", () => {
    const base = doc([
      record({ id: A, grams: 10 }),
      record({ id: B, grams: 4, purchaseID: A, disposition: "sold", disposedAt: T0 + 1000 }),
    ]);
    const local = doc([
      record({ id: A, grams: 6 }),
      record({ id: B, grams: 4, purchaseID: A, disposition: "sold", disposedAt: T0 + 1000 }),
    ]);
    const remote = doc([
      record({ id: A, grams: 5, note: "远端改" }),
      record({ id: B, grams: 5, purchaseID: A, disposition: "sold", disposedAt: T0 + 2000 }),
    ]);

    const result = mergeDocuments(base, local, remote);
    // 族内任一记录冲突，整族都算冲突
    expect(result.conflicts).toContain(A);
  });
});

describe("结果规范化", () => {
  it("合并双方账本并排序", () => {
    const base = doc([]);
    const local = { schemaVersion: 1 as const, books: ["默认账本", "收藏"], records: [] };
    const remote = { schemaVersion: 1 as const, books: ["默认账本", "投资"], records: [] };
    const result = mergeDocuments(base, local, remote);
    expect(result.document.books).toEqual(["收藏", "投资", "默认账本"].sort());
  });

  it("记录按 id 排序", () => {
    const base = doc([]);
    const local = doc([record({ id: C }), record({ id: A })]);
    const result = mergeDocuments(base, local, base);
    expect(result.document.records.map((r) => r.id)).toEqual([A, C]);
  });

  it("空文档合并不报错", () => {
    const result = mergeDocuments(emptyDocument(), emptyDocument(), emptyDocument());
    expect(result.document.records).toEqual([]);
    expect(result.document.books).toEqual(["默认账本"]);
  });
});

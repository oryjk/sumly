import { describe, expect, it } from "bun:test";
import { createHoldingsStore } from "../src/stores/holdings";
import { emptyWorkspace, type HoldingWorkspace, type WorkspaceKey } from "../src/utils/holdingStorage";
import { emptyDocument, type HoldingDocument, type HoldingRecord } from "../src/types/holdings";

const UUID_A = "11111111-1111-1111-1111-111111111111";
const UUID_B = "22222222-2222-2222-2222-222222222222";
const T0 = 1_757_000_000_000;
const DAY = 86_400_000;

function record(overrides: Partial<HoldingRecord> = {}): HoldingRecord {
  return {
    id: UUID_A,
    grams: 10,
    unitPriceCNY: 500,
    timestamp: T0,
    note: "",
    createdAt: T0,
    brand: "",
    bookName: "默认账本",
    disposition: "holding",
    disposedAt: null,
    disposalAmount: 0,
    purchaseID: null,
    extraFee: 20,
    purchaseChannel: "",
    counterparty: "",
    assetType: "投资金条",
    purity: 0.99,
    laborFee: 100,
    purchaseTotalOverride: null,
    recoveryDeduction: 0,
    recoveryDiscount: 0,
    recoveryFixedFee: 0,
    alerts: [],
    ...overrides,
  };
}

function harness(options?: { failSave?: () => boolean; initial?: HoldingDocument }) {
  const data = new Map<string, HoldingWorkspace>();
  data.set("guest", { ...emptyWorkspace("guest"), document: options?.initial ?? emptyDocument() });
  const store = createHoldingsStore({
    load: (key) => data.get(key) ?? emptyWorkspace(key),
    save: (workspace) => {
      if (options?.failSave?.()) throw new Error("存储已满");
      data.set(workspace.key, workspace);
    },
  });
  return { store, data };
}

describe("工作区切换", () => {
  it("切换后读取对应工作区", () => {
    const { store, data } = harness();
    data.set("user:1", {
      ...emptyWorkspace("user:1"),
      document: { schemaVersion: 1, books: ["默认账本"], records: [record({ id: UUID_B })] },
    });
    store.openWorkspace("guest");
    expect(store.document.value.records).toHaveLength(0);
    store.openWorkspace("user:1");
    expect(store.document.value.records[0].id).toBe(UUID_B);
  });
});

describe("变更发布", () => {
  it("落盘成功后发布新状态", () => {
    const { store } = harness();
    const ok = store.mutate((current) => ({ ...current, records: [record()] }));
    expect(ok).toBe(true);
    expect(store.document.value.records).toHaveLength(1);
    expect(store.pendingSync.value).toBe(true);
    expect(store.saveError.value).toBeNull();
  });

  it("落盘失败不发布新状态且错误可见", () => {
    let fail = true;
    const { store } = harness({ failSave: () => fail });
    const before = store.document.value;
    const ok = store.mutate((current) => ({ ...current, records: [record()] }));
    expect(ok).toBe(false);
    expect(store.document.value).toBe(before);
    expect(store.document.value.records).toHaveLength(0);
    expect(store.saveError.value).toBe("存储已满");
    expect(store.pendingSync.value).toBe(false);

    // 存储恢复后可继续保存
    fail = false;
    expect(store.mutate((current) => ({ ...current, records: [record()] }))).toBe(true);
    expect(store.saveError.value).toBeNull();
  });

  it("非法文档被拒绝且不落盘", () => {
    const { store, data } = harness();
    const ok = store.mutate((current) => ({ ...current, records: [record({ grams: -1 })] }));
    expect(ok).toBe(false);
    expect(store.saveError.value).not.toBeNull();
    expect(store.document.value.records).toHaveLength(0);
    expect(data.get("guest")?.document.records).toHaveLength(0);
  });
});

describe("账本", () => {
  it("新建账本", () => {
    const { store } = harness();
    expect(store.addBook("收藏")).toBe(true);
    expect(store.document.value.books).toContain("收藏");
  });

  it("重复账本名不新增", () => {
    const { store } = harness();
    store.addBook("收藏");
    store.addBook("收藏");
    expect(store.document.value.books.filter((b) => b === "收藏")).toHaveLength(1);
  });

  it("空白账本名拒绝", () => {
    const { store } = harness();
    expect(store.addBook("   ")).toBe(false);
  });

  it("迁移记录到新账本时自动补入账本", () => {
    const { store } = harness();
    store.mutate((current) => ({ ...current, records: [record()] }));
    expect(store.moveRecords([UUID_A], "收藏")).toBe(true);
    expect(store.document.value.books).toContain("收藏");
    expect(store.document.value.records[0].bookName).toBe("收藏");
  });

  it("UUID 大小写无关迁移", () => {
    const { store } = harness();
    store.mutate((current) => ({ ...current, records: [record()] }));
    expect(store.moveRecords([UUID_A.toUpperCase()], "收藏")).toBe(true);
    expect(store.document.value.records[0].bookName).toBe("收藏");
  });
});

describe("删除", () => {
  it("删除记录", () => {
    const { store } = harness();
    store.mutate((current) => ({ ...current, records: [record()] }));
    expect(store.deleteRecords([UUID_A])).toBe(true);
    expect(store.document.value.records).toHaveLength(0);
  });

  it("删除购入时连带删除其处置记录", () => {
    const { store } = harness();
    store.mutate((current) => ({ ...current, records: [record()] }));
    store.dispose(UUID_A, 4, 3000, "sold", T0 + DAY, "", T0 + DAY);
    expect(store.document.value.records).toHaveLength(2);
    store.deleteRecords([UUID_A]);
    // 处置记录也一并清除，不留孤儿子记录
    expect(store.document.value.records).toHaveLength(0);
  });

  it("删除处置记录时连带删除所属购入", () => {
    const { store } = harness();
    store.mutate((current) => ({ ...current, records: [record()] }));
    store.dispose(UUID_A, 4, 3000, "sold", T0 + DAY, "", T0 + DAY);
    const soldId = store.document.value.records.find((r) => r.disposition === "sold")!.id;
    store.deleteRecords([soldId]);
    expect(store.document.value.records).toHaveLength(0);
  });

  it("空列表返回 false", () => {
    const { store } = harness();
    expect(store.deleteRecords([])).toBe(false);
    expect(store.moveRecords([], "收藏")).toBe(false);
  });
});

describe("处置", () => {
  it("部分卖出后成本守恒", () => {
    const { store } = harness();
    store.mutate((current) => ({ ...current, records: [record()] }));
    expect(store.dispose(UUID_A, 4, 3000, "sold", T0 + DAY, "买家", T0 + DAY)).toBe(true);

    const remaining = store.document.value.records.find((r) => r.id === UUID_A)!;
    const sold = store.document.value.records.find((r) => r.disposition === "sold")!;
    const cost = (r: HoldingRecord) =>
      r.purchaseTotalOverride ?? r.grams * r.unitPriceCNY + r.laborFee + r.extraFee;
    expect(remaining.grams).toBeCloseTo(6, 9);
    expect(cost(remaining) + cost(sold)).toBeCloseTo(5120, 9);
  });

  it("非法处置不改变文档", () => {
    const { store } = harness();
    store.mutate((current) => ({ ...current, records: [record()] }));
    const before = JSON.stringify(store.document.value);
    expect(store.dispose(UUID_A, 99, 0, "sold", T0 + DAY, "", T0 + DAY)).toBe(false);
    expect(JSON.stringify(store.document.value)).toBe(before);
    expect(store.saveError.value).not.toBeNull();
    // 失败的处置不产生未同步标记
    expect(store.pendingSync.value).toBe(true);
  });
});

describe("同步状态", () => {
  it("标记已同步后清除待同步标记", () => {
    const { store } = harness();
    store.mutate((current) => ({ ...current, records: [record()] }));
    expect(store.pendingSync.value).toBe(true);
    store.markSynced("3", store.document.value);
    expect(store.pendingSync.value).toBe(false);
    expect(store.workspace.value.sync?.revision).toBe("3");
  });

  it("同步状态保存失败时报错", () => {
    let fail = false;
    const { store } = harness({ failSave: () => fail });
    store.mutate((current) => ({ ...current, records: [record()] }));
    fail = true;
    store.markSynced("3", emptyDocument());
    expect(store.saveError.value).toBe("存储已满");
    // 状态未被误报为已同步
    expect(store.pendingSync.value).toBe(true);
  });
});

import { describe, expect, it } from "bun:test";
import { createHoldingsSync } from "../src/stores/holdingsSync";
import { emptyWorkspace, type HoldingWorkspace, type WorkspaceKey } from "../src/utils/holdingStorage";
import { emptyDocument, type HoldingDocument, type HoldingRecord } from "../src/types/holdings";

const A = "11111111-1111-1111-1111-111111111111";
const B = "22222222-2222-2222-2222-222222222222";
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

interface Options {
  remote?: { revision: string; document: HoldingDocument };
  onPush?: (revision: string, document: HoldingDocument) => Promise<{ revision: string; document: HoldingDocument }>;
  pushConflictOnce?: boolean;
  userID?: number | null;
  initialAccount?: HoldingWorkspace;
  initialGuest?: HoldingWorkspace;
  failSave?: boolean;
}

function harness(options: Options = {}) {
  const store = new Map<string, HoldingWorkspace>();
  store.set("guest", options.initialGuest ?? emptyWorkspace("guest"));
  store.set("user:1", options.initialAccount ?? emptyWorkspace("user:1"));
  let pushCalls = 0;
  let pushedConflict = false;
  const saveError = ref<string | null>(null);
  let generation = 1;
  let loggedIn = true;

  const sync = createHoldingsSync({
    fetchSnapshot: async () => options.remote ?? { revision: "1", document: emptyDocument() },
    pushSnapshot: async (revision, document) => {
      pushCalls += 1;
      if (options.pushConflictOnce && !pushedConflict) {
        pushedConflict = true;
        const error = new Error("revision 不匹配") as Error & { statusCode: number };
        error.statusCode = 409;
        throw error;
      }
      return options.onPush ? options.onPush(revision, document) : { revision: String(Number(revision) + 1), document };
    },
    loadWorkspace: (key: WorkspaceKey) => store.get(key) ?? emptyWorkspace(key),
    saveWorkspace: (workspace) => {
      if (options.failSave) {
        saveError.value = "存储已满";
        throw new Error("存储已满");
      }
      store.set(workspace.key, workspace);
    },
    removeWorkspace: (key) => {
      store.delete(key);
    },
    sessionUserID: () => (options.userID === undefined ? 1 : options.userID),
    sessionGeneration: () => generation,
    isCurrentSession: () => loggedIn,
  });

  return {
    sync,
    store,
    saveError,
    pushCount: () => pushCalls,
    bumpGeneration: () => {
      generation += 1;
    },
    setLoggedOut: () => {
      loggedIn = false;
    },
  };
}

function ref<T>(value: T) {
  return { value };
}

describe("正常同步", () => {
  it("无本地修改时提交云端文档", async () => {
    const { sync, store } = harness({ remote: { revision: "5", document: doc([record()]) } });
    await sync.sync();
    expect(sync.status.value).toBe("idle");
    expect(store.get("user:1")?.document.records).toHaveLength(1);
    expect(store.get("user:1")?.sync?.revision).toBe("6");
  });

  it("本地新增被推送", async () => {
    const account = emptyWorkspace("user:1");
    account.document = doc([record({ id: A })]);
    const { sync, pushCount } = harness({
      remote: { revision: "1", document: emptyDocument() },
      initialAccount: account,
    });
    await sync.sync();
    expect(pushCount()).toBe(1);
    expect(sync.status.value).toBe("idle");
  });

  it("未登录时报错", async () => {
    const { sync } = harness({ userID: null });
    await sync.sync();
    expect(sync.status.value).toBe("error");
    expect(sync.lastError.value).toContain("未登录");
  });
});

describe("409 冲突", () => {
  it("重取后无冲突则重试成功", async () => {
    const { sync, pushCount, store } = harness({
      remote: { revision: "1", document: emptyDocument() },
      pushConflictOnce: true,
    });
    await sync.sync();
    expect(pushCount()).toBe(2);
    expect(sync.status.value).toBe("idle");
    expect(store.get("user:1")?.sync?.revision).toBeTruthy();
  });

  it("真冲突时停在冲突状态不推送", async () => {
    const base = emptyWorkspace("user:1");
    base.document = doc([record({ id: A, note: "基线" })]);
    base.sync = { revision: "1", base: doc([record({ id: A, note: "基线" })]) };

    const local = emptyWorkspace("user:1");
    local.document = doc([record({ id: A, note: "本地改" })]);

    const { sync, pushCount } = harness({
      remote: { revision: "2", document: doc([record({ id: A, note: "远端改" })]) },
      initialAccount: local,
    });
    await sync.sync();

    expect(sync.status.value).toBe("conflict");
    expect(sync.conflicts.value).toContain(A);
    expect(pushCount()).toBe(0);
  });

  it("用户选择后继续", async () => {
    const local = emptyWorkspace("user:1");
    local.document = doc([record({ id: A, note: "本地改" })]);
    const base = doc([record({ id: A, note: "基线" })]);

    const { sync, pushCount } = harness({
      remote: { revision: "2", document: doc([record({ id: A, note: "远端改" })]) },
      initialAccount: local,
    });
    // 第一次：无 choice，停在冲突
    await sync.sync();
    expect(sync.status.value).toBe("conflict");

    // 第二次：选本机
    await sync.sync("local");
    expect(pushCount()).toBe(1);
    expect(sync.status.value).toBe("idle");
    expect(base.records).toHaveLength(1);
  });
});

describe("会话隔离", () => {
  it("换号后的旧响应不写入缓存", async () => {
    const { sync, store, bumpGeneration } = harness({
      remote: { revision: "1", document: doc([record()]) },
    });
    // 在 fetch 期间模拟换号
    const original = sync.sync;
    const pending = original();
    bumpGeneration();
    await pending;
    // 代际变化后不应写入
    expect(store.get("user:1")?.document.records).toHaveLength(0);
  });

  it("注销后不同步", async () => {
    const { sync, setLoggedOut, pushCount } = harness({
      remote: { revision: "1", document: doc([record()]) },
    });
    setLoggedOut();
    await sync.sync();
    expect(pushCount()).toBe(0);
  });
});

describe("落盘失败", () => {
  it("保存失败时报错且保持未同步", async () => {
    const { sync } = harness({
      remote: { revision: "1", document: doc([record()]) },
      failSave: true,
    });
    await sync.sync();
    expect(sync.status.value).toBe("error");
    expect(sync.lastError.value).toBe("存储已满");
  });
});

describe("游客导入", () => {
  it("导入后不重复且保留原记录", () => {
    const guest = emptyWorkspace("guest");
    guest.document = doc([record({ id: A }), record({ id: B })]);
    const account = emptyWorkspace("user:1");
    account.document = doc([record({ id: A })]);

    const { sync, store } = harness({ initialGuest: guest, initialAccount: account });
    expect(sync.importGuest()).toBe(true);
    // A 已存在，只导入 B
    expect(store.get("user:1")?.document.records.map((r) => r.id)).toEqual([A, B]);
  });

  it("游客无记录时提示", () => {
    const { sync } = harness();
    expect(sync.importGuest()).toBe(false);
    expect(sync.lastError.value).toContain("没有可导入");
  });

  it("全部已存在时不重复导入", () => {
    const guest = emptyWorkspace("guest");
    guest.document = doc([record({ id: A })]);
    const account = emptyWorkspace("user:1");
    account.document = doc([record({ id: A })]);

    const { sync } = harness({ initialGuest: guest, initialAccount: account });
    expect(sync.importGuest()).toBe(false);
    expect(sync.lastError.value).toContain("已全部存在");
  });

  it("未登录时不能导入", () => {
    const { sync } = harness({ userID: null });
    expect(sync.importGuest()).toBe(false);
  });

  it("注销清除账户缓存但保留游客数据", () => {
    const guest = emptyWorkspace("guest");
    guest.document = doc([record()]);
    const { sync, store } = harness({ initialGuest: guest });
    store.set("user:1", { ...emptyWorkspace("user:1"), document: doc([record({ id: B })]) });

    sync.eraseAccountCache(1);
    expect(store.get("user:1")).toBeUndefined();
    expect(store.get("guest")?.document.records).toHaveLength(1);
  });
});

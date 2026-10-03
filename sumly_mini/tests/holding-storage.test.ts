import { describe, expect, it } from "bun:test";
import {
  createWorkspaceStorage,
  type HoldingWorkspace,
  type WorkspaceKey,
} from "../src/utils/holdingStorage";
import { emptyDocument, type HoldingDocument, type HoldingRecord } from "../src/types/holdings";

const UUID_A = "11111111-1111-1111-1111-111111111111";
const UUID_B = "22222222-2222-2222-2222-222222222222";
const T0 = 1_757_000_000_000;

function record(overrides: Partial<HoldingRecord> = {}): HoldingRecord {
  return {
    id: UUID_A,
    grams: 10,
    unitPriceCNY: 500,
    timestamp: T0,
    note: "",
    createdAt: T0,
    brand: "周大福",
    bookName: "默认账本",
    disposition: "holding",
    disposedAt: null,
    disposalAmount: 0,
    purchaseID: null,
    extraFee: 0,
    purchaseChannel: "",
    counterparty: "",
    assetType: "投资金条",
    purity: 0.9999,
    laborFee: 0,
    purchaseTotalOverride: null,
    recoveryDeduction: 0,
    recoveryDiscount: 0,
    recoveryFixedFee: 0,
    alerts: [],
    ...overrides,
  };
}

/** 内存版存储，行为对齐 uni.setStorageSync 的同步语义。 */
function memoryStorage(initial: Record<string, string> = {}) {
  const data = new Map<string, string>(Object.entries(initial));
  return {
    getItem: (key: string) => data.get(key) ?? null,
    setItem: (key: string, value: string) => {
      data.set(key, value);
    },
    removeItem: (key: string) => {
      data.delete(key);
    },
    snapshot: () => Object.fromEntries(data),
  };
}

describe("工作区键", () => {
  it("游客与账户工作区互不相同", () => {
    expect("guest" satisfies WorkspaceKey).toBe("guest");
    expect("user:7" satisfies WorkspaceKey).toBe("user:7");
  });
});

describe("保存与读取", () => {
  it("新键返回空工作区", () => {
    const storage = createWorkspaceStorage(memoryStorage());
    const workspace = storage.load("guest");
    expect(workspace.key).toBe("guest");
    expect(workspace.document).toEqual(emptyDocument());
    expect(workspace.sync).toBeNull();
  });

  it("保存后能原样读回", () => {
    const storage = createWorkspaceStorage(memoryStorage());
    const document: HoldingDocument = { schemaVersion: 1, books: ["默认账本", "收藏"], records: [record()] };
    storage.save({ schemaVersion: 1, key: "guest", document, sync: null });
    expect(storage.load("guest").document).toEqual(document);
  });

  it("不同键互相隔离", () => {
    const storage = createWorkspaceStorage(memoryStorage());
    storage.save({
      schemaVersion: 1,
      key: "guest",
      document: { schemaVersion: 1, books: ["默认账本"], records: [record()] },
      sync: null,
    });
    storage.save({
      schemaVersion: 1,
      key: "user:1",
      document: { schemaVersion: 1, books: ["默认账本"], records: [record({ id: UUID_B })] },
      sync: null,
    });
    expect(storage.load("guest").document.records[0].id).toBe(UUID_A);
    expect(storage.load("user:1").document.records[0].id).toBe(UUID_B);
  });

  it("同步基线与 revision 一并保存", () => {
    const storage = createWorkspaceStorage(memoryStorage());
    const base = { schemaVersion: 1, books: ["默认账本"], records: [] } as HoldingDocument;
    storage.save({
      schemaVersion: 1,
      key: "user:1",
      document: { schemaVersion: 1, books: ["默认账本"], records: [record()] },
      sync: { revision: "7", base },
    });
    const loaded = storage.load("user:1");
    expect(loaded.sync?.revision).toBe("7");
    expect(loaded.sync?.base).toEqual(base);
  });

  it("小数毫秒时间戳不被截断", () => {
    const storage = createWorkspaceStorage(memoryStorage());
    const fractional = T0 + 123.456;
    storage.save({
      schemaVersion: 1,
      key: "guest",
      document: { schemaVersion: 1, books: ["默认账本"], records: [record({ timestamp: fractional })] },
      sync: null,
    });
    expect(storage.load("guest").document.records[0].timestamp).toBe(fractional);
  });
});

describe("写入失败", () => {
  it("保存抛错时不留下半份数据", () => {
    const inner = memoryStorage();
    const failing = {
      ...inner,
      setItem: (key: string, value: string) => {
        if (key.includes("user:1")) throw new Error("存储已满");
        inner.setItem(key, value);
      },
    };
    const storage = createWorkspaceStorage(failing);
    expect(() =>
      storage.save({
        schemaVersion: 1,
        key: "user:1",
        document: emptyDocument(),
        sync: null,
      }),
    ).toThrow("存储已满");
    // 失败的键不应留下可读数据
    expect(inner.snapshot()["sumly:holdings:user:1"]).toBeUndefined();
  });
});

describe("损坏数据", () => {
  it("非法JSON 回退为空工作区", () => {
    const storage = createWorkspaceStorage(memoryStorage({ "sumly:holdings:guest": "{broken" }));
    expect(storage.load("guest").document).toEqual(emptyDocument());
  });

  it("结构不对时回退为空工作区", () => {
    const storage = createWorkspaceStorage(memoryStorage({ "sumly:holdings:guest": '{"foo":1}' }));
    expect(storage.load("guest").document).toEqual(emptyDocument());
  });

  it("读取失败不抛异常", () => {
    const throwing = {
      getItem: () => {
        throw new Error("存储不可用");
      },
      setItem: () => undefined,
      removeItem: () => undefined,
    };
    const storage = createWorkspaceStorage(throwing);
    expect(storage.load("guest").document).toEqual(emptyDocument());
  });
});

describe("删除", () => {
  it("删除指定工作区", () => {
    const storage = createWorkspaceStorage(memoryStorage());
    storage.save({ schemaVersion: 1, key: "user:1", document: emptyDocument(), sync: null });
    storage.remove("user:1");
    expect(storage.load("user:1").document).toEqual(emptyDocument());
  });

  it("删除不存在的键不抛异常", () => {
    const storage = createWorkspaceStorage(memoryStorage());
    expect(() => storage.remove("user:99")).not.toThrow();
  });
});

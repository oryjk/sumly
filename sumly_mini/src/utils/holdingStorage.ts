/**
 * 持仓工作区持久化。
 *
 * 游客与各账户使用独立存储槽，互不串数据。base 与 revision 必须
 * 同一提交单元写入——否则崩溃后会出现「本地文档已更新但基线还是旧的」，
 * 下次三方合并会把它当成两台设备的改动而制造假冲突。
 */
import { emptyDocument, type HoldingDocument } from "@/types/holdings";

/** 工作区键：游客固定为 guest，账户为 user:<id>。 */
export type WorkspaceKey = "guest" | `user:${number}`;

/** 云端同步基线；未同步时为 null。 */
export interface HoldingSyncBase {
  /** 服务端 revision 的十进制字符串，避免 int64 精度丢失。 */
  revision: string;
  base: HoldingDocument;
}

/** 单个持仓工作区。 */
export interface HoldingWorkspace {
  schemaVersion: 1;
  key: WorkspaceKey;
  document: HoldingDocument;
  sync: HoldingSyncBase | null;
}

/** 存储后端接口，对齐 uni.setStorageSync 的同步语义。 */
export interface StorageBackend {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

const PREFIX = "sumly:holdings:";

/** 存储键。 */
export function workspaceKey(key: WorkspaceKey): string {
  return `${PREFIX}${key}`;
}

/** 结构守卫：只接受形状正确的文档。 */
function isDocument(value: unknown): value is HoldingDocument {
  if (typeof value !== "object" || value === null) return false;
  const doc = value as Record<string, unknown>;
  return (
    doc.schemaVersion === 1 &&
    Array.isArray(doc.books) &&
    Array.isArray(doc.records) &&
    doc.books.every((book) => typeof book === "string") &&
    doc.records.every(
      (record) =>
        typeof record === "object" &&
        record !== null &&
        typeof (record as { id?: unknown }).id === "string",
    )
  );
}

function isSyncBase(value: unknown): value is HoldingSyncBase {
  if (typeof value !== "object" || value === null) return false;
  const sync = value as Record<string, unknown>;
  return typeof sync.revision === "string" && isDocument(sync.base);
}

/** 组装工作区存储。 */
export function createWorkspaceStorage(backend: StorageBackend) {
  /** 读取工作区；缺失、损坏或读取失败都回退为空工作区，不抛异常。 */
  function load(key: WorkspaceKey): HoldingWorkspace {
    let raw: string | null = null;
    try {
      raw = backend.getItem(workspaceKey(key));
    } catch {
      return emptyWorkspace(key);
    }
    if (!raw) {
      return emptyWorkspace(key);
    }
    try {
      const parsed = JSON.parse(raw) as Record<string, unknown>;
      if (!isDocument(parsed.document)) {
        return emptyWorkspace(key);
      }
      return {
        schemaVersion: 1,
        key,
        document: parsed.document,
        sync: isSyncBase(parsed.sync) ? parsed.sync : null,
      };
    } catch {
      return emptyWorkspace(key);
    }
  }

  /**
   * 保存工作区。document 与 sync 一起序列化写入，
   * 保证 base 与 revision 不会跨提交单元。
   * 失败时向上抛错，调用方不得据此发布新状态。
   */
  function save(workspace: HoldingWorkspace): void {
    const payload = JSON.stringify({
      schemaVersion: 1,
      key: workspace.key,
      document: workspace.document,
      sync: workspace.sync,
    });
    backend.setItem(workspaceKey(workspace.key), payload);
  }

  /** 删除工作区；不存在时静默返回。 */
  function remove(key: WorkspaceKey): void {
    try {
      backend.removeItem(workspaceKey(key));
    } catch {
      // 删除失败不应阻断流程
    }
  }

  return { load, save, remove };
}

/** 空工作区。 */
export function emptyWorkspace(key: WorkspaceKey): HoldingWorkspace {
  return { schemaVersion: 1, key, document: emptyDocument(), sync: null };
}

/** 基于 uni 存储的默认实现。 */
function uniBackend(): StorageBackend {
  return {
    getItem: (key) => {
      const value = uni.getStorageSync(key);
      return typeof value === "string" && value ? value : null;
    },
    setItem: (key, value) => uni.setStorageSync(key, value),
    removeItem: (key) => uni.removeStorageSync(key),
  };
}

let shared: ReturnType<typeof createWorkspaceStorage> | null = null;

/** 全局单例，页面与 store 共享。 */
export function useHoldingStorage() {
  if (!shared) {
    shared = createWorkspaceStorage(uniBackend());
  }
  return shared;
}

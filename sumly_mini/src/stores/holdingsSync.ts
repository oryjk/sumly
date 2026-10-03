/**
 * 持仓同步 store。
 *
 * 关键约束：
 * - 每次同步绑定用户 ID 与会话代际，换号/注销后的旧响应不写入任何缓存；
 * - 409 后重取快照并三方合并，**不直接覆盖**；
 * - 冲突未解决时停止，不按旧配置继续推送；
 * - base 与 revision 同一提交单元落盘，写入失败保持 dirty。
 */
import { computed, ref, shallowRef } from "vue";
import { getHoldings, putHoldings } from "@/api/holdings";
import { mergeDocuments, type MergeChoice } from "@/domain/holdings/merge";
import { emptyWorkspace, useHoldingStorage, type WorkspaceKey } from "@/utils/holdingStorage";
import { getSession } from "@/utils/sessionBridge";
import { emptyDocument, type HoldingDocument } from "@/types/holdings";

/** 同步状态。 */
export type SyncStatus = "idle" | "syncing" | "conflict" | "error";

export interface HoldingSyncDeps {
  fetchSnapshot: () => Promise<{ revision: string; document: HoldingDocument }>;
  pushSnapshot: (revision: string, document: HoldingDocument) => Promise<{ revision: string; document: HoldingDocument }>;
  loadWorkspace: (key: WorkspaceKey) => ReturnType<typeof emptyWorkspace>;
  saveWorkspace: (workspace: ReturnType<typeof emptyWorkspace>) => void;
  removeWorkspace: (key: WorkspaceKey) => void;
  sessionUserID: () => number | null;
  sessionGeneration: () => number;
  isCurrentSession: () => boolean;
}

function defaultDeps(): HoldingSyncDeps {
  const storage = useHoldingStorage();
  return {
    fetchSnapshot: getHoldings,
    pushSnapshot: putHoldings,
    loadWorkspace: storage.load,
    saveWorkspace: storage.save,
    removeWorkspace: storage.remove,
    sessionUserID: () => getSession().currentUser.value?.id ?? null,
    sessionGeneration: () => getSession().sessionGeneration.value,
    isCurrentSession: () => getSession().isLoggedIn.value,
  };
}

export function createHoldingsSync(deps: HoldingSyncDeps) {
  const status = ref<SyncStatus>("idle");
  const conflicts = ref<string[]>([]);
  const lastError = ref<string | null>(null);

  /** 冲突期间暂存的远端文档，用于用户选择后继续。 */
  const pendingRemote = shallowRef<HoldingDocument | null>(null);

  const isSyncing = computed(() => status.value === "syncing");

  /** 账户工作区键。 */
  function workspaceKey(): WorkspaceKey | null {
    const id = deps.sessionUserID();
    return id === null ? null : `user:${id}`;
  }

  /** PUT 抛出的 409。 */
  function isConflictError(error: unknown): boolean {
    return (
      typeof error === "object" &&
      error !== null &&
      (error as { statusCode?: number }).statusCode === 409
    );
  }

  /** 合并并落盘。 */
  function commit(document: HoldingDocument, revision: string, key: WorkspaceKey): boolean {
    const workspace = deps.loadWorkspace(key);
    const candidate = { ...workspace, document, sync: { revision, base: document } };
    try {
      deps.saveWorkspace(candidate);
    } catch (cause) {
      lastError.value = cause instanceof Error ? cause.message : "同步结果保存失败";
      return false;
    }
    return true;
  }

  /**
   * 同步一次。
   * @param choice 冲突时用户的选择；不给则停在冲突状态等待
   */
  async function sync(choice?: MergeChoice): Promise<void> {
    const key = workspaceKey();
    if (key === null) {
      lastError.value = "未登录，无法同步";
      status.value = "error";
      return;
    }

    // 绑定发起时的账户与代际
    const generation = deps.sessionGeneration();
    const stillCurrent = (): boolean =>
      deps.sessionGeneration() === generation && deps.isCurrentSession();

    status.value = "syncing";
    lastError.value = null;

    try {
      const workspace = deps.loadWorkspace(key);
      const remote = await deps.fetchSnapshot();
      // 换号或注销后到达的响应直接丢弃
      if (!stillCurrent()) return;

      // 没有基线时不能用远端当基线——那会让本地改动看起来「等于 base」，
      // 真冲突被静默吞掉。此时以空文档为基线，本地新增/编辑都会被识别。
      const base = workspace.sync?.base ?? emptyDocument();
      const local = workspace.document;

      const merged = mergeDocuments(base, local, remote.document, choice);
      if (!stillCurrent()) return;

      if (merged.conflicts.length > 0 && choice === undefined) {
        // 冲突未解决：停在冲突状态，不按旧配置继续推送
        conflicts.value = merged.conflicts;
        pendingRemote.value = remote.document;
        status.value = "conflict";
        return;
      }

      conflicts.value = [];
      pendingRemote.value = null;

      // 先尝试直接提交合并结果；revision 又被推进时重取再合并
      let revision = remote.revision;
      for (let attempt = 0; attempt < 2; attempt += 1) {
        try {
          const saved = await deps.pushSnapshot(revision, merged.document);
          if (!stillCurrent()) return;
          if (!commit(saved.document, saved.revision, key)) {
            status.value = "error";
            return;
          }
          status.value = "idle";
          return;
        } catch (error) {
          if (!isConflictError(error) || attempt === 1) {
            lastError.value = error instanceof Error ? error.message : "同步失败";
            status.value = "error";
            return;
          }
          // 409：重取最新快照后再合并一次
          const latest = await deps.fetchSnapshot();
          if (!stillCurrent()) return;
          const retry = mergeDocuments(remote.document, merged.document, latest.document, choice);
          if (!stillCurrent()) return;
          if (retry.conflicts.length > 0 && choice === undefined) {
            conflicts.value = retry.conflicts;
            pendingRemote.value = latest.document;
            status.value = "conflict";
            return;
          }
          merged.document = retry.document;
          revision = latest.revision;
        }
      }
    } catch (cause) {
      if (!stillCurrent()) return;
      lastError.value = cause instanceof Error ? cause.message : "同步失败";
      status.value = "error";
    }
  }

  /**
   * 显式导入游客数据。
   * 用原 UUID 去重，已存在的记录不重复导入，且**不重新归属**已有记录。
   */
  function importGuest(): boolean {
    const key = workspaceKey();
    if (key === null) {
      lastError.value = "未登录，无法导入";
      status.value = "error";
      return false;
    }
    const guest = deps.loadWorkspace("guest");
    const account = deps.loadWorkspace(key);
    if (guest.document.records.length === 0) {
      lastError.value = "没有可导入的游客记录";
      return false;
    }

    const existing = new Set(account.document.records.map((record) => record.id.toLowerCase()));
    const additions = guest.document.records.filter((record) => !existing.has(record.id.toLowerCase()));
    if (additions.length === 0) {
      lastError.value = "游客记录已全部存在";
      return false;
    }

    const books = new Set([...account.document.books, ...additions.map((record) => record.bookName)]);
    const document: HoldingDocument = {
      schemaVersion: 1,
      books: [...books],
      records: [...account.document.records, ...additions],
    };
    // 导入后仍是 dirty，需要推送
    const candidate = { ...account, document };
    try {
      deps.saveWorkspace(candidate);
    } catch (cause) {
      lastError.value = cause instanceof Error ? cause.message : "导入保存失败";
      status.value = "error";
      return false;
    }
    return true;
  }

  /** 清除指定账户的本地缓存。注销后调用，游客数据不受影响。 */
  function eraseAccountCache(userID: number): void {
    deps.removeWorkspace(`user:${userID}`);
  }

  /** 解除冲突状态，回到未同步。 */
  function markDirty(): void {
    conflicts.value = [];
    pendingRemote.value = null;
    status.value = "idle";
  }

  return {
    status,
    conflicts,
    lastError,
    pendingRemote,
    isSyncing,
    sync,
    importGuest,
    eraseAccountCache,
    markDirty,
  };
}

let shared: ReturnType<typeof createHoldingsSync> | null = null;

export function useHoldingsSync() {
  if (!shared) {
    shared = createHoldingsSync(defaultDeps());
  }
  return shared;
}

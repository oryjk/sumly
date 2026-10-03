/**
 * 持仓工作区 store。
 *
 * 关键约束：**只有落盘成功才发布新状态**。存储满或写入失败时，
 * 页面继续显示旧数据并暴露错误，不能让用户以为改动已保存。
 */
import { computed, ref, shallowRef } from "vue";
import { disposeHolding } from "@/domain/holdings/disposal";
import { normalizeDocument, validateDocument } from "@/domain/holdings/document";
import { DEFAULT_BOOK, type HoldingDisposition, type HoldingDocument } from "@/types/holdings";
import {
  emptyWorkspace,
  useHoldingStorage,
  type HoldingWorkspace,
  type WorkspaceKey,
} from "@/utils/holdingStorage";

/** store 依赖，便于测试注入。 */
export interface HoldingsStoreDeps {
  load: (key: WorkspaceKey) => HoldingWorkspace;
  save: (workspace: HoldingWorkspace) => void;
}

export function createHoldingsStore(deps: HoldingsStoreDeps) {
  const workspace = shallowRef<HoldingWorkspace>(emptyWorkspace("guest"));
  /** 待同步：有本地修改但尚未成功推送到云端。 */
  const pendingSync = ref(false);
  /** 最近一次落盘失败原因，成功后清空。 */
  const saveError = ref<string | null>(null);

  const document = computed(() => workspace.value.document);

  /** 切换工作区。游客与账户缓存互不干扰。 */
  function openWorkspace(key: WorkspaceKey): void {
    workspace.value = deps.load(key);
    pendingSync.value = false;
    saveError.value = null;
  }

  /**
   * 以纯函数方式更新文档。
   * 落盘成功后才发布；失败时保留旧状态并记录错误。
   */
  function mutate(update: (current: HoldingDocument) => HoldingDocument): boolean {
    let next: HoldingDocument;
    try {
      next = normalizeDocument(update(workspace.value.document));
      // 落盘前先过一遍服务端同等校验，避免非法数据进入持久化
      validateDocument(next);
    } catch (cause) {
      saveError.value = cause instanceof Error ? cause.message : "持仓数据无效";
      return false;
    }

    const candidate: HoldingWorkspace = { ...workspace.value, document: next };
    try {
      deps.save(candidate);
    } catch (cause) {
      saveError.value = cause instanceof Error ? cause.message : "持仓保存失败";
      return false;
    }
    workspace.value = candidate;
    saveError.value = null;
    pendingSync.value = true;
    return true;
  }

  /** 新建账本。 */
  function addBook(name: string): boolean {
    const trimmed = name.trim();
    if (!trimmed) return false;
    return mutate((current) => {
      if (current.books.includes(trimmed)) return current;
      return { ...current, books: [...current.books, trimmed] };
    });
  }

  /** 把记录迁移到目标账本；目标账本不存在时自动补入。 */
  function moveRecords(ids: readonly string[], book: string): boolean {
    if (ids.length === 0) return false;
    const targets = new Set(ids.map((id) => id.toLowerCase()));
    return mutate((current) => {
      const books = current.books.includes(book) ? current.books : [...current.books, book];
      return {
        ...current,
        books,
        records: current.records.map((record) =>
          targets.has(record.id.toLowerCase()) ? { ...record, bookName: book } : record,
        ),
      };
    });
  }

  /** 删除记录。关联的购入族一起删除，避免留下孤立的处置记录。 */
  function deleteRecords(ids: readonly string[]): boolean {
    if (ids.length === 0) return false;
    const targets = new Set(ids.map((id) => id.toLowerCase()));
    return mutate((current) => {
      // 连带 purchaseID 指向被删记录的处置记录
      const removing = new Set(targets);
      for (const record of current.records) {
        if (targets.has(record.id.toLowerCase()) && record.purchaseID) {
          removing.add(record.purchaseID.toLowerCase());
        }
        if (record.purchaseID && targets.has(record.purchaseID.toLowerCase())) {
          removing.add(record.id.toLowerCase());
        }
      }
      return {
        ...current,
        records: current.records.filter((record) => !removing.has(record.id.toLowerCase())),
      };
    });
  }

  /**
   * 执行处置（卖出/赠送）。
   * 非法克数、时间或状态时文档保持原样，错误通过 saveError 暴露。
   */
  function dispose(
    recordId: string,
    grams: number,
    proceeds: number,
    kind: HoldingDisposition,
    disposedAt: number,
    counterparty: string,
    now: number,
  ): boolean {
    return mutate((current) =>
      disposeHolding(
        { schemaVersion: 1, books: current.books, records: current.records },
        recordId,
        grams,
        proceeds,
        kind,
        disposedAt,
        counterparty,
        now,
      ),
    );
  }

  /** 标记同步状态。 */
  function markSynced(revision: string, base: HoldingDocument): void {
    const candidate: HoldingWorkspace = {
      ...workspace.value,
      sync: { revision, base },
    };
    try {
      deps.save(candidate);
    } catch (cause) {
      saveError.value = cause instanceof Error ? cause.message : "同步状态保存失败";
      return;
    }
    workspace.value = candidate;
    pendingSync.value = false;
    saveError.value = null;
  }

  /** 标记仍有未同步修改。 */
  function markDirty(): void {
    pendingSync.value = true;
  }

  return {
    workspace,
    document,
    pendingSync,
    saveError,
    defaultBook: DEFAULT_BOOK,
    openWorkspace,
    mutate,
    addBook,
    moveRecords,
    deleteRecords,
    dispose,
    markSynced,
    markDirty,
  };
}

let shared: ReturnType<typeof createHoldingsStore> | null = null;

export function useHoldingsStore() {
  if (!shared) {
    const storage = useHoldingStorage();
    shared = createHoldingsStore({ load: storage.load, save: storage.save });
  }
  return shared;
}

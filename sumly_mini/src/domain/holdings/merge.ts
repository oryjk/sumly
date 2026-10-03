/**
 * 持仓三方合并。
 *
 * 购入与其部分处置记录属于**同一个合并单元**：只取一侧的剩余记录
 * 而丢掉另一侧的处置副本，会让总重量虚增。因此用并查集把跨版本的
 * 购入族链接成一个分组，任一记录冲突则整族一起判定。
 *
 * base / local / remote 三方：两端一致直接取；一端等于 base 取另一端；
 * 都不等才是真冲突，由用户显式选择。
 */
import { normalizeDocument } from "./document";
import { normalizeUUID } from "./document";
import type { HoldingDocument, HoldingRecord } from "@/types/holdings";

/** 冲突时的用户选择。 */
export type MergeChoice = "local" | "remote";

export interface MergeResult {
  document: HoldingDocument;
  /** 冲突记录的规范化 id 列表。 */
  conflicts: string[];
}

/** 记录是否等价（日期按毫秒比较，其余严格相等）。 */
function sameRecord(a: HoldingRecord, b: HoldingRecord): boolean {
  if (a.id.toLowerCase() !== b.id.toLowerCase()) return false;
  if (a.timestamp !== b.timestamp) return false;
  if (a.createdAt !== b.createdAt) return false;
  if (a.disposedAt !== b.disposedAt) return false;
  if (a.alerts.length !== b.alerts.length) return false;
  for (let index = 0; index < a.alerts.length; index += 1) {
    const left = a.alerts[index];
    const right = b.alerts[index];
    if (
      left.id !== right.id ||
      left.kind !== right.kind ||
      left.threshold !== right.threshold ||
      left.enabled !== right.enabled ||
      left.basis !== right.basis
    ) {
      return false;
    }
  }
  return (
    a.grams === b.grams &&
    a.unitPriceCNY === b.unitPriceCNY &&
    a.note === b.note &&
    a.brand === b.brand &&
    a.bookName === b.bookName &&
    a.disposition === b.disposition &&
    a.disposalAmount === b.disposalAmount &&
    a.purchaseID === b.purchaseID &&
    a.extraFee === b.extraFee &&
    a.purchaseChannel === b.purchaseChannel &&
    a.counterparty === b.counterparty &&
    a.assetType === b.assetType &&
    a.purity === b.purity &&
    a.laborFee === b.laborFee &&
    a.purchaseTotalOverride === b.purchaseTotalOverride &&
    a.recoveryDeduction === b.recoveryDeduction &&
    a.recoveryDiscount === b.recoveryDiscount &&
    a.recoveryFixedFee === b.recoveryFixedFee
  );
}

/** 数组等价（顺序无关，UUID 大小写无关）。 */
function sameSet(a: readonly string[], b: readonly string[]): boolean {
  if (a.length !== b.length) return false;
  const left = new Set(a.map(normalizeUUID));
  for (const item of b) {
    if (!left.has(normalizeUUID(item))) return false;
  }
  return true;
}

/** 一组记录是否等价。 */
function sameGroup(a: HoldingRecord[], b: HoldingRecord[]): boolean {
  if (a.length !== b.length) return false;
  const left = new Map(a.map((record) => [normalizeUUID(record.id), record]));
  for (const record of b) {
    const counterpart = left.get(normalizeUUID(record.id));
    if (!counterpart || !sameRecord(counterpart, record)) return false;
  }
  return true;
}

/**
 * 三方合并。
 * @param choice 仅在存在真冲突时生效；不给则默认取本地
 */
export function mergeDocuments(
  base: HoldingDocument,
  local: HoldingDocument,
  remote: HoldingDocument,
  choice?: MergeChoice,
): MergeResult {
  const all = [...base.records, ...local.records, ...remote.records];

  // 并查集：把购入与所有指向它的处置记录连成一个分量
  const parent = new Map<string, string>();
  const find = (id: string): string => {
    let current = normalizeUUID(id);
    while (parent.get(current) !== current) {
      const next = parent.get(current)!;
      const grand = parent.get(next);
      parent.set(current, grand ?? next);
      current = grand ?? next;
    }
    return current;
  };
  const union = (a: string, b: string): void => {
    const rootA = find(a);
    const rootB = find(b);
    if (rootA !== rootB) {
      // 固定以字典序较小者为根，保证结果与输入顺序无关
      if (rootA < rootB) parent.set(rootB, rootA);
      else parent.set(rootA, rootB);
    }
  };

  for (const record of all) {
    const id = normalizeUUID(record.id);
    if (!parent.has(id)) parent.set(id, id);
    if (record.purchaseID) {
      const purchase = normalizeUUID(record.purchaseID);
      if (!parent.has(purchase)) parent.set(purchase, purchase);
    }
  }
  for (const record of all) {
    if (record.purchaseID) {
      union(record.purchaseID, record.id);
    }
  }

  const families = (records: readonly HoldingRecord[]): Map<string, HoldingRecord[]> => {
    const grouped = new Map<string, HoldingRecord[]>();
    for (const record of records) {
      const root = find(record.id);
      const list = grouped.get(root) ?? [];
      list.push(record);
      grouped.set(root, list);
    }
    for (const list of grouped.values()) {
      list.sort((a, b) => normalizeUUID(a.id).localeCompare(normalizeUUID(b.id)));
    }
    return grouped;
  };

  const original = families(base.records);
  const ours = families(local.records);
  const theirs = families(remote.records);

  const roots = new Set<string>([...original.keys(), ...ours.keys(), ...theirs.keys()]);
  const records: HoldingRecord[] = [];
  const conflicts = new Set<string>();

  for (const root of [...roots].sort()) {
    const b = original.get(root);
    const l = ours.get(root);
    const r = theirs.get(root);

    const localSide = l ?? [];
    const remoteSide = r ?? [];
    const baseSide = b ?? [];

    let resolved: HoldingRecord[] | undefined;
    if (sameGroup(localSide, remoteSide)) {
      // 两端一致（含同时新增或同时删除）
      resolved = l ?? r;
    } else if (sameGroup(baseSide, remoteSide)) {
      // 远端等于 base：本地这一侧说了算（含本地删除）
      resolved = l;
    } else if (sameGroup(baseSide, localSide)) {
      // 本地等于 base：远端这一侧说了算（含远端删除）
      resolved = r;
    } else {
      // 两端都偏离 base：真冲突，整族标记
      for (const record of [...baseSide, ...localSide, ...remoteSide]) {
        conflicts.add(normalizeUUID(record.id));
      }
      resolved = choice === "remote" ? r : l;
    }
    if (resolved) {
      records.push(...resolved);
    }
  }

  const document = normalizeDocument({
    schemaVersion: 1,
    books: [...new Set([...local.books, ...remote.books])],
    records,
  });

  return { document, conflicts: [...conflicts].sort() };
}

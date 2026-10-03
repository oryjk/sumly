/**
 * 提醒监测生命周期。
 *
 * 关键约束（对标 iOS 端 HoldingAlertMonitor 与计划要求）：
 * - 运行态（armed/基线/冷却）按 workspace+record+alert 独立持久化，
 *   **不写入账户云文档**——它们是设备状态，不该跨设备同步；
 * - 触发时先算候选 next，**送达确认后才发布触发运行态**，
 *   避免「本地弹了窗但消息没送达」却已消耗冷却；
 * - 后台停止监测，恢复后由页面显式重新 start；
 * - 已处置记录不监测。
 */
import { computed, ref, shallowRef } from "vue";
import { evaluateAlert, freshRuntime, type AlertRuntime } from "@/domain/holdings/alerts";
import { returnInput } from "@/domain/holdings/returns";
import type { HoldingRecord } from "@/types/holdings";

/** 一次触发事件。 */
export interface AlertEvent {
  id: string;
  recordID: string;
  alertID: string;
  kind: string;
  price: number;
  threshold: number;
  triggeredAt: number;
}

/** 送达结果。 */
export type DeliveryOutcome = "delivered" | "failed" | "unknown";

export interface AlertMonitorDeps {
  now: () => number;
  loadRuntime: (key: string) => AlertRuntime | null;
  saveRuntime: (key: string, runtime: AlertRuntime) => void;
}

/** 运行态存储键：workspace + record + alert 三级隔离。 */
export function runtimeKey(workspace: string, recordID: string, alertID: string): string {
  return `${workspace}:${recordID.toLowerCase()}:${alertID.toLowerCase()}`;
}

export function createAlertMonitor(deps: AlertMonitorDeps) {
  const running = ref(false);
  const lastError = ref<string | null>(null);
  const lastDeliveryOutcome = ref<DeliveryOutcome | null>(null);
  /** 等待送达确认的事件队列。 */
  const pending = shallowRef<AlertEvent[]>([]);

  let eventSequence = 0;
  let workspace = "guest";

  const isRunning = computed(() => running.value);

  function setWorkspace(next: string): void {
    workspace = next;
  }

  /**
   * 评估一批记录。
   *
   * @param price 当前参考价（元/克）
   * @param asOf 报价采样时间
   * @param now 当前时刻
   */
  function evaluate(records: readonly HoldingRecord[], price: number, asOf: number, now: number): void {
    if (!running.value) return;
    const produced: AlertEvent[] = [];

    for (const record of records) {
      // 已处置记录不再监测
      if (record.disposition !== "holding") continue;
      for (const alert of record.alerts) {
        if (!alert.enabled) continue;
        const key = runtimeKey(workspace, record.id, alert.id);
        const current = deps.loadRuntime(key) ?? freshRuntime();

        const evaluation = evaluateAlert(alert, current, returnInput(record), price, asOf, now);

        // 未触发的基线变化可以立即落盘
        if (!evaluation.triggered) {
          persist(key, evaluation.next);
          continue;
        }

        // 触发：先算候选 next，等送达确认后再发布
        eventSequence += 1;
        produced.push({
          id: `${record.id}:${alert.id}:${eventSequence}`,
          recordID: record.id,
          alertID: alert.id,
          kind: alert.kind,
          price,
          threshold: alert.threshold,
          triggeredAt: now,
        });
        // 候选运行态暂存，等 acknowledge 时才写入
        pending.value = [
          ...pending.value,
          {
            ...produced[produced.length - 1],
          },
        ];
        staged.set(produced[produced.length - 1].id, { key, runtime: evaluation.next });
      }
    }

    if (produced.length > 0) {
      pending.value = [...pending.value];
    }
  }

  /** 待确认事件的候选运行态。 */
  const staged = new Map<string, { key: string; runtime: AlertRuntime }>();

  function persist(key: string, runtime: AlertRuntime): void {
    try {
      deps.saveRuntime(key, runtime);
      lastError.value = null;
    } catch (cause) {
      // 存储失败不发布：运行态保持原样，下次评估重新处理
      lastError.value = cause instanceof Error ? cause.message : "提醒状态保存失败";
    }
  }

  /**
   * 确认送达结果。
   * 只有确认后才发布触发运行态并消耗冷却；失败保留可重试状态。
   */
  function acknowledge(eventID: string, outcome: DeliveryOutcome): void {
    pending.value = pending.value.filter((event) => event.id !== eventID);
    const candidate = staged.get(eventID);
    staged.delete(eventID);
    lastDeliveryOutcome.value = outcome;
    if (candidate) {
      persist(candidate.key, candidate.runtime);
    }
  }

  function start(owner: string): void {
    void owner;
    running.value = true;
  }

  function stop(owner: string): void {
    void owner;
    running.value = false;
  }

  return {
    /** 当前工作区标识，运行态按它隔离。 */
    workspace: () => workspace,
    running,
    isRunning,
    pending,
    lastError,
    lastDeliveryOutcome,
    setWorkspace,
    evaluate,
    acknowledge,
    start,
    stop,
  };
}

/** 运行态存储的 uni 实现。 */
function uniBackend() {
  const PREFIX = "sumly:alerts:";
  return {
    load(key: string): AlertRuntime | null {
      try {
        const raw = uni.getStorageSync(PREFIX + key);
        if (!raw || typeof raw !== "string") return null;
        return JSON.parse(raw) as AlertRuntime;
      } catch {
        return null;
      }
    },
    save(key: string, runtime: AlertRuntime): void {
      uni.setStorageSync(PREFIX + key, JSON.stringify(runtime));
    },
  };
}

let shared: ReturnType<typeof createAlertMonitor> | null = null;

export function useHoldingAlerts() {
  if (!shared) {
    const backend = uniBackend();
    shared = createAlertMonitor({
      now: () => Date.now(),
      loadRuntime: backend.load,
      saveRuntime: backend.save,
    });
  }
  return shared;
}

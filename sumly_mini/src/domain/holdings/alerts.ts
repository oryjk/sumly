/**
 * 持仓目标提醒引擎。
 *
 * 移植自 iOS 端 HoldingAlertEngine，规则逐条对齐：
 * - **穿越触发**：首次报价超过目标不触发，必须先低于目标建立 armed，
 *   再达到目标才触发——否则用户刚设置提醒就会被历史高价误报；
 * - **报价有效期 300 秒**，未来 60 秒内的报价也接受（时钟偏差）；
 * - **异常跳变过滤**：单次跳变超过 20% 视为数据异常，不更新基线；
 * - **24 小时冷却**：同一目标每天最多触发一次；
 * - **armed/基线/冷却不随云文档同步**，只存在本地运行态。
 */
import { calculateReturn, referencePrice, type GoldReturnInput } from "./returns";
import type { HoldingAlert, HoldingAlertBasis } from "@/types/holdings";

/** 提醒目标类型。 */
export type AlertKind = HoldingAlert["kind"];

/** 设备运行态，不随账户云文档同步。 */
export interface AlertRuntime {
  /** 上一次有效报价。 */
  previousPrice: number | null;
  /** 上一次报价的采样时间。 */
  previousAsOf: number | null;
  /** 是否已低于目标、等待穿越。 */
  armed: boolean;
  /** 上次触发时间。 */
  lastTriggeredAt: number | null;
}

export interface AlertEvaluation {
  next: AlertRuntime;
  triggered: boolean;
}

/** 空运行态。 */
export function freshRuntime(): AlertRuntime {
  return { previousPrice: null, previousAsOf: null, armed: false, lastTriggeredAt: null };
}

/** 报价有效期（毫秒）。 */
export const QUOTE_VALID_MS = 300_000;
/** 允许的时钟超前（毫秒）。 */
export const QUOTE_FUTURE_TOLERANCE_MS = 60_000;
/** 断档阈值（毫秒）：超过则重置基线。 */
export const GAP_RESET_MS = 300_000;
/** 跳变过滤阈值。 */
export const JUMP_RATIO = 0.2;
/** 冷却时长（毫秒）。 */
export const COOLDOWN_MS = 86_400_000;

export const ALERT_TITLES: Record<AlertKind, string> = {
  breakEven: "达到真实保本",
  profitPercent: "真实收益率目标",
  profitAmount: "预计盈利金额目标",
  price: "参考金价目标",
};

/** 配置是否有效。 */
export function isValidAlert(alert: HoldingAlert): boolean {
  if (!Number.isFinite(alert.threshold) || alert.threshold < 0) return false;
  // 金价目标必须为正，否则无法定义穿越方向
  if (alert.kind === "price" && alert.threshold <= 0) return false;
  return true;
}

/** 重置基线与 armed。 */
function resetBaseline(runtime: AlertRuntime): AlertRuntime {
  return { ...runtime, previousPrice: null, previousAsOf: null, armed: false };
}

/**
 * 评估单个提醒。
 *
 * @param asOf 报价的采样时间；用于断档与重复判定
 * @param now 当前时刻；用于报价有效期与冷却
 */
export function evaluateAlert(
  alert: HoldingAlert,
  runtime: AlertRuntime,
  input: GoldReturnInput,
  price: number,
  asOf: number,
  now: number,
): AlertEvaluation {
  const skip = (): AlertEvaluation => ({ next: runtime, triggered: false });

  if (!alert.enabled || !isValidAlert(alert)) return skip();
  if (!Number.isFinite(price) || price <= 0) return skip();

  // 报价必须新鲜；未来 60 秒内接受，超出说明时钟不可信
  const age = now - asOf;
  if (age < -QUOTE_FUTURE_TOLERANCE_MS || age > QUOTE_VALID_MS) return skip();

  const result = calculateReturn(input, price);
  if (!result) return skip();

  // 同一采样时间不重复处理
  if (runtime.previousAsOf !== null && asOf <= runtime.previousAsOf) return skip();

  let next = runtime;
  // 长断档后重新建立基线，避免用陈旧基线判断穿越
  if (runtime.previousAsOf !== null && asOf - runtime.previousAsOf > GAP_RESET_MS) {
    next = resetBaseline(next);
  }

  // 异常跳变：不更新基线也不触发
  if (next.previousPrice !== null && Math.abs(price / next.previousPrice - 1) > JUMP_RATIO) {
    return { next, triggered: false };
  }

  // 目标价：保本与金额/收益率目标都用反推，金价目标直接用阈值
  let target: number;
  switch (alert.kind) {
    case "breakEven":
      target = result.breakEvenPrice;
      break;
    case "price":
      target = alert.threshold;
      break;
    case "profitAmount": {
      const totalCost = result.totalCost;
      const value = referencePrice(input, totalCost + alert.threshold);
      if (value === null) return skip();
      target = value;
      break;
    }
    case "profitPercent": {
      const totalCost = result.totalCost;
      if (totalCost <= 0) return skip();
      const value = referencePrice(input, totalCost * (1 + alert.threshold / 100));
      if (value === null) return skip();
      target = value;
      break;
    }
    default:
      return skip();
  }
  if (!Number.isFinite(target)) return skip();

  const wasArmed = next.armed;
  next = {
    ...next,
    previousPrice: price,
    previousAsOf: asOf,
  };

  // 先低于目标才 armed；用 max(0.01, target×0.001) 作为容差避免边界抖动
  if (price < target - Math.max(0.01, target * 0.001)) {
    next = { ...next, armed: true };
  }

  if (!wasArmed || price < target) {
    return { next, triggered: false };
  }

  // 穿越成立，清 armed
  next = { ...next, armed: false };

  if (next.lastTriggeredAt !== null && now - next.lastTriggeredAt < COOLDOWN_MS) {
    return { next, triggered: false };
  }
  return { next: { ...next, lastTriggeredAt: now }, triggered: true };
}

/** 表单合并结果。 */
export interface AlertFormMerge {
  alerts: HoldingAlert[];
  /** 配置发生变化、需要重置基线的提醒 id。 */
  resetIDs: string[];
}

/**
 * 合并表单编辑与最新配置。
 *
 * 表单只编辑配置（阈值、开关、口径）。运行态（armed/基线/冷却）独立
 * 持久化，不随云文档走，因此这里不返回运行态——配置变化时通过
 * resetIDs 通知调用方重置对应运行态，避免把正在更新的冷却倒退。
 *
 * @returns 合并结果；输入非法时返回 null
 */
export function mergeAlertForm(
  edited: readonly HoldingAlert[],
  values: readonly string[],
  latest: readonly HoldingAlert[],
  basis: HoldingAlertBasis,
): AlertFormMerge | null {
  if (edited.length !== values.length) return null;
  const alerts: HoldingAlert[] = [];
  const resetIDs: string[] = [];

  for (let index = 0; index < edited.length; index += 1) {
    const desired = edited[index];
    const current = latest.find((item) => item.id === desired.id) ?? desired;

    let threshold = current.threshold;
    if (desired.kind !== "breakEven") {
      const parsed = Number(values[index].trim());
      const usable =
        Number.isFinite(parsed) &&
        parsed >= 0 &&
        (desired.kind !== "price" || parsed > 0);
      if (usable) {
        threshold = parsed;
      } else if (desired.enabled) {
        // 启用的提醒必须有有效阈值
        return null;
      }
    } else {
      // 保本目标没有可编辑阈值
      threshold = 0;
    }

    const merged: HoldingAlert = {
      ...current,
      enabled: desired.enabled,
      threshold,
      basis,
    };
    if (merged.enabled && !isValidAlert(merged)) {
      return null;
    }
    // 配置变了，旧的基线与 armed 不再适用
    if (current.enabled !== merged.enabled || current.threshold !== threshold || current.basis !== basis) {
      resetIDs.push(merged.id);
    }
    alerts.push(merged);
  }
  return { alerts, resetIDs };
}

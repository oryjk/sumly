/**
 * 持仓提醒的订阅消息类型。
 * 与后端 /notifications/holding/* 的 envelope 对齐。
 */

/** 能力检测结果。模板未配置时 available 为 false。 */
export interface NotificationCapability {
  available: boolean;
  template_id: string | null;
}

/** 发码响应。 */
export interface NotificationGrant {
  grant: string;
  expires_in: number;
}

/** 单次发送状态。unknown 表示结果未知，须按 ID 查询恢复，不得自动重发。 */
export type NotificationEventStatus = "delivered" | "failed" | "unknown" | "skipped";

/** 一个发送事件。 */
export interface NotificationEvent {
  id: string;
  status: NotificationEventStatus;
}

/** 评估响应。 */
export interface NotificationEventResult {
  events: NotificationEvent[];
}

/** 游客提交的一条待评估配置；只含 UUID、数值与固定枚举。 */
export interface GuestAlertInput {
  record_id: string;
  input: {
    grams: number;
    purity: number;
    unit_price: number;
    labor_fee: number;
    other_cost: number;
    total_cost_override: number | null;
    per_gram_deduction: number;
    discount_rate: number;
    fixed_fee: number;
  };
  alerts: {
    id: string;
    kind: string;
    threshold: number;
  }[];
}

/** 发码请求体。 */
export interface GrantRequest {
  js_code: string;
  device_id: string;
  template_id: string;
}

/** 评估请求体。 */
export interface EvaluateRequest {
  device_id: string;
  request_id: string;
  guest_configuration?: GuestAlertInput[];
}

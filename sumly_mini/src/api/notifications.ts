/**
 * 持仓提醒的订阅消息接口。
 *
 * 授权令牌走专属 header（X-Holding-Notification-Grant），
 * 不复用登录 token——它只允许发消息，不授予任何账户访问权。
 */
import { requestRaw } from "@/utils/request";
import type {
  EvaluateRequest,
  GuestAlertInput,
  NotificationCapability,
  NotificationEvent,
  NotificationEventResult,
  NotificationGrant,
} from "@/types/notifications";
import type { BackendApiResponse } from "@/types/backend";

function unwrap<T>(response: BackendApiResponse<T>, context: string): T {
  if (response.data === null || response.data === undefined) {
    throw new Error(`${context}响应缺少数据`);
  }
  return response.data;
}

/** 能力检测。 */
export async function getHoldingCapabilities(): Promise<NotificationCapability> {
  const response = await requestRaw<BackendApiResponse<NotificationCapability>>({
    url: "/notifications/holding/capabilities",
  });
  return unwrap(response, "提醒能力检测");
}

/** 用服务端验证过的 code 换取 grant。 */
export async function createNotificationGrant(
  jsCode: string,
  deviceID: string,
  templateID: string,
): Promise<NotificationGrant> {
  const response = await requestRaw<BackendApiResponse<NotificationGrant>>({
    url: "/notifications/holding/grants",
    method: "POST",
    data: { js_code: jsCode, device_id: deviceID, template_id: templateID },
  });
  return unwrap(response, "提醒授权");
}

/** 提交评估请求。grant 通过专属 header 传递。 */
export async function evaluateHoldingNotifications(
  grant: string,
  deviceID: string,
  requestID: string,
  guestConfiguration?: GuestAlertInput[],
): Promise<NotificationEventResult> {
  const body: EvaluateRequest = {
    device_id: deviceID,
    request_id: requestID,
    ...(guestConfiguration && guestConfiguration.length > 0
      ? { guest_configuration: guestConfiguration }
      : {}),
  };
  const response = await requestRaw<BackendApiResponse<NotificationEventResult>, Record<string, unknown>>({
    url: "/notifications/holding/evaluate",
    method: "POST",
    data: body as unknown as Record<string, unknown>,
    grant,
  });
  return unwrap(response, "提醒评估");
}

/** 按ID 查询单次发送结果。 */
export async function getNotificationEvent(
  grant: string,
  deviceID: string,
  eventID: string,
): Promise<NotificationEvent> {
  const query = `?device_id=${encodeURIComponent(deviceID)}`;
  const response = await requestRaw<BackendApiResponse<NotificationEvent>>({
    url: `/notifications/holding/events/${encodeURIComponent(eventID)}${query}`,
    grant,
  });
  return unwrap(response, "提醒事件");
}

/**
 * 微信订阅消息的前端适配。
 *
 * 平台约束（已按官方文档核对）：
 * - H5 不支持 `uni.requestSubscribeMessage`，只在 MP-WEIXIN 编译；
 * - 必须由用户点击或支付后调起，不能在轮询里自动弹授权；
 * - 一次最多 3 个模板；本功能复用一个真实模板覆盖四类目标；
 * - success 回调里还必须检查每个模板的 accept/reject/ban——
 *   success 只代表「弹窗完成」，不代表用户同意。
 */
import { getHoldingCapabilities, createNotificationGrant, evaluateHoldingNotifications, getNotificationEvent } from "@/api/notifications";
import type { NotificationCapability, NotificationEventResult, NotificationEventStatus } from "@/types/notifications";

/** 单模板授权结果。ban 表示用户曾拒绝过该类消息，需引导去设置页开启。 */
export type SubscriptionOutcome = "accept" | "reject" | "ban";

/**
 * 请求订阅授权。**只能由用户点击触发**，不允许在定时器里调用。
 * @returns 授权结果；不支持订阅的平台返回 "reject"
 */
export function requestHoldingSubscription(templateID: string): Promise<SubscriptionOutcome> {
  // #ifdef H5
  // H5 没有订阅消息通道，如实返回不可用而不是假装成功
  void templateID;
  return Promise.resolve("reject");
  // #endif

  // #ifdef MP-WEIXIN
  return new Promise<SubscriptionOutcome>((resolve) => {
    uni.requestSubscribeMessage({
      tmplIds: [templateID],
      success: (result) => {
        // success 只表示弹窗流程结束，必须逐个模板检查实际结果
        const outcome = (result as unknown as Record<string, string>)[templateID];
        if (outcome === "accept") {
          resolve("accept");
          return;
        }
        if (outcome === "ban") {
          resolve("ban");
          return;
        }
        resolve("reject");
      },
      fail: () => {
        resolve("reject");
      },
    });
  });
  // #endif
}

/** 能力检测：模板未配置时不可用，前端据此不请求授权。 */
export async function holdingNotificationCapability(): Promise<NotificationCapability> {
  const capability = await getHoldingCapabilities();
  if (!capability.available) {
    return { available: false, template_id: null };
  }
  return capability;
}

/**
 * 创建授权并返回 grant。
 * grant 存专属存储，切换账户即失效；它只允许发消息，不授予账户访问权。
 */
export async function authorizeHoldingNotification(
  code: string,
  deviceID: string,
  templateID: string,
): Promise<string> {
  const result = await createNotificationGrant(code, deviceID, templateID);
  return result.grant;
}

export { evaluateHoldingNotifications, getNotificationEvent };
export type { NotificationEventResult, NotificationEventStatus };

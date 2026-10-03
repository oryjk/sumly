/**
 * 认证接口。
 *
 * 全部走原生认证契约：微信会话、手机号与邮箱验证码、刷新、退出与注销。
 * 统一消费 { code, message, data } envelope。
 *
 * 旧的 /auth/wechat/login 与 /auth/dev/login 契约保持不变，
 * 供未迁移的客户端继续使用。
 */
import { requestRaw } from "@/utils/request";
import type {
  AuthCapabilities,
  AuthUser,
  CodeSendResult,
  EmailPurpose,
  NativeLoginResult,
} from "@/types/auth";
import type { BackendApiResponse } from "@/types/backend";

/** 取出 data；缺失时抛出可读错误，不返回空壳。 */
function unwrap<T>(response: BackendApiResponse<T>, context: string): T {
  if (response.data === null || response.data === undefined) {
    throw new Error(`${context}响应缺少数据`);
  }
  return response.data;
}

/** 服务端能力检测。apple 字段保留兼容，小程序不使用。 */
export async function getCapabilities(): Promise<AuthCapabilities> {
  const response = await requestRaw<BackendApiResponse<AuthCapabilities>>({ url: "/auth/capabilities" });
  return unwrap(response, "能力检测");
}

/** 微信小程序会话登录。 */
export async function loginWithSession(jsCode: string): Promise<NativeLoginResult> {
  const response = await requestRaw<BackendApiResponse<NativeLoginResult>>({
    url: "/auth/wechat/session",
    method: "POST",
    data: { js_code: jsCode },
  });
  return unwrap(response, "微信登录");
}

/** 发送手机号验证码。 */
export async function sendPhoneCode(phone: string): Promise<CodeSendResult> {
  const response = await requestRaw<BackendApiResponse<CodeSendResult>>({
    url: "/auth/phone/code",
    method: "POST",
    data: { phone_number: phone },
  });
  return unwrap(response, "短信验证码");
}

/** 手机号验证码登录。 */
export async function loginWithPhone(phone: string, code: string): Promise<NativeLoginResult> {
  const response = await requestRaw<BackendApiResponse<NativeLoginResult>>({
    url: "/auth/phone/login",
    method: "POST",
    data: { phone_number: phone, code },
  });
  return unwrap(response, "手机号登录");
}

/** 发送邮箱验证码。purpose 只能是 register 或 reset_password。 */
export async function sendEmailCode(email: string, purpose: EmailPurpose): Promise<CodeSendResult> {
  const response = await requestRaw<BackendApiResponse<CodeSendResult>>({
    url: "/auth/email/code",
    method: "POST",
    data: { email, purpose },
  });
  return unwrap(response, "邮箱验证码");
}

/** 邮箱注册（需验证码）。 */
export async function registerWithEmail(
  email: string,
  password: string,
  code: string,
): Promise<NativeLoginResult> {
  const response = await requestRaw<BackendApiResponse<NativeLoginResult>>({
    url: "/auth/email/register",
    method: "POST",
    data: { email, password, code },
  });
  return unwrap(response, "邮箱注册");
}

/** 邮箱密码登录。 */
export async function loginWithEmail(email: string, password: string): Promise<NativeLoginResult> {
  const response = await requestRaw<BackendApiResponse<NativeLoginResult>>({
    url: "/auth/email/login",
    method: "POST",
    data: { email, password },
  });
  return unwrap(response, "邮箱登录");
}

/** 重置密码（需邮箱验证码）。 */
export async function resetPassword(
  email: string,
  code: string,
  newPassword: string,
): Promise<void> {
  await requestRaw<BackendApiResponse<unknown>>({
    url: "/auth/email/reset-password",
    method: "POST",
    data: { email, code, new_password: newPassword },
  });
}

/** 刷新会话。 */
export async function refreshSession(refreshToken: string): Promise<NativeLoginResult> {
  const response = await requestRaw<BackendApiResponse<NativeLoginResult>>({
    url: "/auth/refresh",
    method: "POST",
    data: { refresh_token: refreshToken },
  });
  return unwrap(response, "会话刷新");
}

/** 服务端吊销会话。 */
export async function logoutSession(refreshToken: string): Promise<void> {
  await requestRaw<BackendApiResponse<unknown>>({
    url: "/auth/logout",
    method: "POST",
    data: { refresh_token: refreshToken },
  });
}

/** 读取当前用户。 */
export async function getCurrentUser(): Promise<AuthUser> {
  const response = await requestRaw<BackendApiResponse<AuthUser>>({ url: "/auth/me", auth: true });
  return unwrap(response, "用户信息");
}

/** 注销账户。confirmation 固定为 DELETE。 */
export async function deleteAccount(): Promise<void> {
  await requestRaw<BackendApiResponse<unknown>>({
    url: "/auth/account",
    method: "DELETE",
    data: { confirmation: "DELETE" },
  });
}

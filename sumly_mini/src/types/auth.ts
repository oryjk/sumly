/**
 * 认证类型。
 *
 * 与 sumly_go 原生认证契约（NativeUser / NativeLoginResult）一一对应，
 * 不在此层改名字段，避免与后端漂移。
 */

/** 登录方式。微信替代 Apple，手机号与邮箱保留。 */
export type AuthProvider = "wechat" | "phone" | "email";

/** 账户资料。 */
export interface AuthUser {
  id: number;
  nickname: string;
  avatar_url: string | null;
  real_name: string | null;
  phone_number: string | null;
  email: string | null;
  status: "active" | "frozen";
  provider: AuthProvider;
}

/** 完整凭据。access 短期有效，refresh 用于续期。 */
export interface AuthCredentials {
  accessToken: string;
  refreshToken: string;
  /** access 过期时间（Unix 毫秒）。 */
  expiresAt: number;
  user: AuthUser;
}

/** 后端登录响应 data。 */
export interface NativeLoginResult {
  token: string;
  refresh_token: string;
  expires_in: number;
  user: AuthUser;
}

/** 服务端能力。字段与 OpenAPI NativeCapabilities 一致。 */
export interface AuthCapabilities {
  apple: boolean;
  wechat: boolean;
  phone: boolean;
  email: boolean;
}

/** 发码响应。 */
export interface CodeSendResult {
  retry_after: number;
  expires_in: number;
}

/** 删除账户意图，绑定发起时的账户与代际。 */
export interface DeletionIntent {
  userID: number;
  provider: AuthProvider;
  generation: number;
}

/**
 * 邮箱验证码用途。
 * login 仅用于前端区分「已有账号去登录」这条不需要发码的路径；
 * 发码请求只允许 register 与 reset_password（与服务端一致）。
 */
export type EmailPurpose = "register" | "reset_password" | "login";

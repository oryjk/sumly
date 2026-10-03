/**
 * 凭据持久化。
 *
 * 凭据作为一个**专属存储单元**保存——不存密码、验证码或微信 code。
 * 手动退出标记阻止启动时静默重登。
 */
import type { AuthCredentials } from "@/types/auth";

const CREDENTIALS_KEY = "sumly:auth:credentials";
const MANUAL_LOGOUT_KEY = "sumly:auth:manual-logout";

/** 读取凭据；不存在或损坏时返回 null。 */
export function loadCredentials(): AuthCredentials | null {
  try {
    const raw = uni.getStorageSync(CREDENTIALS_KEY);
    if (!raw || typeof raw !== "string") return null;
    const parsed = JSON.parse(raw) as Partial<AuthCredentials>;
    if (
      typeof parsed.accessToken !== "string" ||
      typeof parsed.refreshToken !== "string" ||
      typeof parsed.expiresAt !== "number" ||
      !parsed.user ||
      typeof parsed.user.id !== "number"
    ) {
      return null;
    }
    return parsed as AuthCredentials;
  } catch {
    return null;
  }
}

/** 保存凭据；失败时抛给调用方，由它决定不发布状态。 */
export function saveCredentials(credentials: AuthCredentials): void {
  uni.setStorageSync(CREDENTIALS_KEY, JSON.stringify(credentials));
  uni.removeStorageSync(MANUAL_LOGOUT_KEY);
}

/** 清除凭据。 */
export function clearCredentials(): void {
  uni.removeStorageSync(CREDENTIALS_KEY);
}

export function hasManualLogout(): boolean {
  try {
    return uni.getStorageSync(MANUAL_LOGOUT_KEY) === "1";
  } catch {
    return false;
  }
}

export function setManualLogout(): void {
  try {
    uni.setStorageSync(MANUAL_LOGOUT_KEY, "1");
  } catch {
    // 标记失败不应阻断退出流程
  }
}

export function clearManualLogout(): void {
  try {
    uni.removeStorageSync(MANUAL_LOGOUT_KEY);
  } catch {
    // 忽略
  }
}

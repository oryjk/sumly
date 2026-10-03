/**
 * 会话桥接。
 *
 * request.ts 需要读会话与触发刷新，但会话 store 又依赖 api/auth.ts，
 * 直接互相 import 会形成循环。这里用一个独立模块持有单例，
 * 两侧都只依赖它。
 */
import { createSessionStore, type SessionStore } from "@/stores/appSession";
import {
  clearCredentials,
  hasManualLogout,
  loadCredentials,
  saveCredentials,
  setManualLogout,
  clearManualLogout,
} from "@/utils/authStorage";
import { loginWithSession, logoutSession, refreshSession } from "@/api/auth";
import type { AuthCredentials } from "@/types/auth";

let shared: SessionStore | null = null;

/** 构造使用真实 API 与存储的会话 store。 */
function createDefaultSession(): SessionStore {
  return createSessionStore({
    now: () => Date.now(),
    load: () => {
      if (hasManualLogout()) return null;
      return loadCredentials();
    },
    save: (credentials: AuthCredentials) => saveCredentials(credentials),
    clear: () => {
      clearCredentials();
      clearManualLogout();
    },
    refreshSession: async (token: string) => {
      const result = await refreshSession(token);
      return {
        accessToken: result.token,
        refreshToken: result.refresh_token,
        expiresAt: Date.now() + result.expires_in * 1000,
        user: result.user,
      };
    },
    logoutRemote: async (token: string) => {
      await logoutSession(token);
    },
  });
}

/** 全局会话单例。 */
export function getSession(): SessionStore {
  if (!shared) {
    shared = createDefaultSession();
  }
  return shared;
}

/** 供请求层触发刷新。 */
export function refreshSessionForRequest(): Promise<void> {
  return getSession().refreshAccess();
}

/** 微信登录：仅小程序编译环境可用 uni.login。 */
export function requestWechatCode(): Promise<string> {
  return new Promise((resolve, reject) => {
    uni.login({
      provider: "weixin",
      success: (result) => {
        if (!result.code) {
          reject(new Error("微信登录未返回 code"));
          return;
        }
        resolve(result.code);
      },
      fail: (error) => {
        reject(new Error(error.errMsg || "微信登录失败"));
      },
    });
  });
}

/** 微信登录并建立会话。 */
export async function loginWithWechat(): Promise<void> {
  const code = await requestWechatCode();
  const result = await loginWithSession(code);
  getSession().applyLoginResult(result);
}

export { setManualLogout };

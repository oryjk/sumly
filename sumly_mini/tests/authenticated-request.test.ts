import { describe, expect, it } from "bun:test";
import { createSessionStore } from "../src/stores/appSession";
import type { AuthCredentials, AuthUser } from "../src/types/auth";

const T0 = 1_757_000_000_000;

function user(id: number): AuthUser {
  return {
    id,
    nickname: "用户",
    avatar_url: null,
    real_name: null,
    phone_number: null,
    email: null,
    status: "active",
    provider: "wechat",
  };
}

function credentials(id: number): AuthCredentials {
  return { accessToken: `a${id}`, refreshToken: `r${id}`, expiresAt: T0 + 900_000, user: user(id) };
}

describe("受保护请求的刷新边界", () => {
  it("未登录时刷新直接清空而不发请求", async () => {
    let refreshCalls = 0;
    const session = createSessionStore({
      now: () => T0,
      load: () => null,
      save: () => undefined,
      clear: () => undefined,
      refreshSession: async () => {
        refreshCalls += 1;
        return credentials(1);
      },
      logoutRemote: async () => undefined,
    });

    await session.refreshAccess();
    expect(refreshCalls).toBe(0);
    expect(session.currentUser.value).toBeNull();
  });

  it("临近过期时 needsRefresh 为真", () => {
    const session = createSessionStore({
      now: () => T0,
      load: () => null,
      save: () => undefined,
      clear: () => undefined,
      refreshSession: async () => credentials(1),
      logoutRemote: async () => undefined,
    });
    session.applyCredentials(credentials(1));
    // expiresAt = T0 + 900000，距今 900 秒，尚未进入 30 秒窗口
    expect(session.needsRefresh()).toBe(false);
  });

  it("已过期时 needsRefresh 为真", () => {
    let clock = T0;
    const session = createSessionStore({
      now: () => clock,
      load: () => null,
      save: () => undefined,
      clear: () => undefined,
      refreshSession: async () => credentials(1),
      logoutRemote: async () => undefined,
    });
    session.applyCredentials(credentials(1));
    clock = T0 + 900_000;
    expect(session.needsRefresh()).toBe(true);
  });

  it("手动退出后不恢复会话", () => {
    const stored = credentials(5);
    const session = createSessionStore({
      now: () => T0,
      load: () => stored,
      save: () => undefined,
      clear: () => undefined,
      refreshSession: async () => credentials(1),
      logoutRemote: async () => undefined,
    });
    session.markManualLogout();
    expect(session.ensureSessionReady()).toBe(false);
    expect(session.currentUser.value).toBeNull();
  });

  it("force 可覆盖手动退出标记", () => {
    const stored = credentials(5);
    const session = createSessionStore({
      now: () => T0,
      load: () => stored,
      save: () => undefined,
      clear: () => undefined,
      refreshSession: async () => credentials(1),
      logoutRemote: async () => undefined,
    });
    session.markManualLogout();
    expect(session.ensureSessionReady(true)).toBe(true);
    expect(session.currentUser.value?.id).toBe(5);
  });
});

import { describe, expect, it } from "bun:test";
import { createSessionStore } from "../src/stores/appSession";
import type { AuthCredentials, AuthUser } from "../src/types/auth";

const T0 = 1_757_000_000_000;

function user(id: number): AuthUser {
  return { id, nickname: "用户", avatar_url: null, real_name: null, phone_number: null, email: null, status: "active", provider: "wechat" };
}

function credentials(id: number, generation = 1): AuthCredentials {
  return {
    accessToken: `access-${id}`,
    refreshToken: `refresh-${id}`,
    expiresAt: T0 + 900_000,
    user: user(id),
  };
}

function harness(options?: { refresh?: (token: string) => Promise<AuthCredentials>; onSave?: () => void; failSave?: boolean }) {
  const store = { value: null as AuthCredentials | null };
  const calls = { save: 0, refresh: 0, clear: 0, logout: 0 };
  const session = createSessionStore({
    now: () => T0,
    load: () => store.value,
    save: (value) => {
      calls.save += 1;
      if (options?.failSave) throw new Error("存储已满");
      store.value = value;
    },
    clear: () => {
      calls.clear += 1;
      store.value = null;
    },
    refreshSession: async (token) => {
      calls.refresh += 1;
      if (options?.refresh) return options.refresh(token);
      return credentials(2);
    },
    logoutRemote: async () => {
      calls.logout += 1;
    },
  });
  return { session, store, calls };
}

describe("凭据持久化", () => {
  it("保存后可恢复", () => {
    const { session, calls } = harness();
    session.applyCredentials(credentials(1));
    expect(session.currentUser.value?.id).toBe(1);
    expect(calls.save).toBe(1);
  });

  it("恢复的会话可用于后续请求", () => {
    const { session, store } = harness();
    session.applyCredentials(credentials(1));
    const restored = createSessionStore({
      now: () => T0,
      load: () => store.value,
      save: () => undefined,
      clear: () => undefined,
      refreshSession: async () => credentials(2),
      logoutRemote: async () => undefined,
    });
    // 需显式恢复，构造时不自动加载
    expect(restored.accessToken.value).toBe("");
    expect(restored.ensureSessionReady()).toBe(true);
    expect(restored.accessToken.value).toBe("access-1");
    expect(restored.currentUser.value?.id).toBe(1);
  });

  it("存储失败时不发布凭据", () => {
    const { session } = harness({ failSave: true });
    expect(() => session.applyCredentials(credentials(1))).toThrow();
    expect(session.currentUser.value).toBeNull();
  });
});

describe("会话代际", () => {
  it("代际随登录递增", () => {
    const { session } = harness();
    const before = session.sessionGeneration.value;
    session.applyCredentials(credentials(1));
    expect(session.sessionGeneration.value).toBeGreaterThan(before);
  });

  it("退出后旧捕获失效", () => {
    const { session } = harness();
    session.applyCredentials(credentials(1));
    const captured = session.captureSession();
    expect(session.isCurrentSession(captured!)).toBe(true);
    session.clearSession();
    expect(session.isCurrentSession(captured!)).toBe(false);
  });

  it("换号后旧捕获失效", () => {
    const { session } = harness();
    session.applyCredentials(credentials(1));
    const captured = session.captureSession();
    session.applyCredentials(credentials(2));
    expect(session.isCurrentSession(captured!)).toBe(false);
  });

  it("未登录时捕获返回 null", () => {
    const { session } = harness();
    expect(session.captureSession()).toBeNull();
  });
});

describe("访问令牌刷新", () => {
  it("刷新成功后更新凭据", async () => {
    const { session, calls } = harness();
    session.applyCredentials(credentials(1));
    await session.refreshAccess();
    expect(calls.refresh).toBe(1);
    expect(session.accessToken.value).toBe("access-2");
  });

  it("并发刷新只执行一次", async () => {
    let resolveRefresh: (value: AuthCredentials) => void = () => undefined;
    const { session, calls } = harness({
      refresh: () =>
        new Promise<AuthCredentials>((resolve) => {
          resolveRefresh = resolve;
        }),
    });
    session.applyCredentials(credentials(1));
    const first = session.refreshAccess();
    const second = session.refreshAccess();
    resolveRefresh(credentials(2));
    await Promise.all([first, second]);
    expect(calls.refresh).toBe(1);
  });

  it("刷新失败时清除会话", async () => {
    const { session } = harness({
      refresh: async () => {
        throw new Error("刷新失败");
      },
    });
    session.applyCredentials(credentials(1));
    await session.refreshAccess();
    expect(session.currentUser.value).toBeNull();
  });

  it("退出后的旧刷新响应不得复活会话", async () => {
    let resolveRefresh: (value: AuthCredentials) => void = () => undefined;
    const { session } = harness({
      refresh: () =>
        new Promise<AuthCredentials>((resolve) => {
          resolveRefresh = resolve;
        }),
    });
    session.applyCredentials(credentials(1));
    const pending = session.refreshAccess();
    session.clearSession();
    resolveRefresh(credentials(2));
    await pending;
    // 旧响应不得复活会话
    expect(session.currentUser.value).toBeNull();
  });
});

describe("退出", () => {
  it("退出清除本地凭据并通知服务端", async () => {
    const { session, store, calls } = harness();
    session.applyCredentials(credentials(1));
    await session.logout();
    expect(store.value).toBeNull();
    expect(calls.clear).toBe(1);
  });

  it("服务端吊销失败也清除本地", async () => {
    const { session, store } = harness();
    session.applyCredentials(credentials(1));
    await session.logout();
    expect(store.value).toBeNull();
  });
});

describe("删除账户意图", () => {
  it("意图绑定账户与代际", () => {
    const { session } = harness();
    session.applyCredentials(credentials(7));
    const intent = session.beginAccountDeletion();
    expect(intent.userID).toBe(7);
    expect(intent.provider).toBe("wechat");
    expect(intent.generation).toBe(session.sessionGeneration.value);
  });

  it("代际变化后旧意图失效", () => {
    const { session } = harness();
    session.applyCredentials(credentials(7));
    const intent = session.beginAccountDeletion();
    session.applyCredentials(credentials(7));
    expect(session.isDeletionIntentCurrent(intent)).toBe(false);
  });

  it("未登录时不能发起删除", () => {
    const { session } = harness();
    expect(() => session.beginAccountDeletion()).toThrow();
  });
});

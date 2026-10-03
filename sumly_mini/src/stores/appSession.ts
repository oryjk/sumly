/**
 * 会话 store。
 *
 * 核心是**代际（generation）**：每次登录、退出、换号都自增，
 * 异步响应落地前先比对代际，旧响应不得复活会话、清掉新凭据
 * 或改写其它账户的缓存。
 *
 * 存储失败不发布凭据——宁可让用户重试，也不能出现「界面显示已登录
 * 但刷新后掉线」。
 */
import { computed, ref, shallowRef } from "vue";
import type { AuthCredentials, AuthUser, DeletionIntent } from "@/types/auth";

/** 会话捕获：把某次请求绑定到发起时的账户与代际。 */
export interface SessionCapture {
  userID: number;
  generation: number;
}

/** store 依赖，便于测试注入确定实现。 */
export interface SessionStoreDeps {
  now: () => number;
  load: () => AuthCredentials | null;
  save: (credentials: AuthCredentials) => void;
  clear: () => void;
  refreshSession: (refreshToken: string) => Promise<AuthCredentials>;
  logoutRemote: (refreshToken: string) => Promise<void>;
}

export function createSessionStore(deps: SessionStoreDeps) {
  const currentUser = shallowRef<AuthUser | null>(null);
  const accessToken = ref("");
  const refreshToken = ref("");
  const expiresAt = ref(0);
  const sessionGeneration = ref(0);
  const error = ref<string | null>(null);
  const loading = ref(false);
  /** 手动退出标记：阻止启动时静默恢复会话。 */
  const manualLogout = ref(false);

  /** 正在进行的刷新 Promise，保证并发 401 只刷新一次。 */
  let inflightRefresh: Promise<void> | null = null;

  const isLoggedIn = computed(() => currentUser.value !== null);

  /** 把后端登录响应转换为本地凭据。 */
  function toCredentials(result: {
    token: string;
    refresh_token: string;
    expires_in: number;
    user: AuthUser;
  }): AuthCredentials {
    return {
      accessToken: result.token,
      refreshToken: result.refresh_token,
      expiresAt: deps.now() + result.expires_in * 1000,
      user: result.user,
    };
  }

  /**
   * 应用凭据。落盘失败时抛错且不发布，
   * 避免界面显示已登录但刷新后掉线。
   */
  function applyCredentials(credentials: AuthCredentials): void {
    deps.save(credentials);
    accessToken.value = credentials.accessToken;
    refreshToken.value = credentials.refreshToken;
    expiresAt.value = credentials.expiresAt;
    currentUser.value = credentials.user;
    manualLogout.value = false;
    sessionGeneration.value += 1;
    error.value = null;
  }

  /** 应用后端登录响应。 */
  function applyLoginResult(result: {
    token: string;
    refresh_token: string;
    expires_in: number;
    user: AuthUser;
  }): void {
    applyCredentials(toCredentials(result));
  }

  /** 清除本地会话并自增代际，使所有在途请求失效。 */
  function clearSession(): void {
    deps.clear();
    accessToken.value = "";
    refreshToken.value = "";
    expiresAt.value = 0;
    currentUser.value = null;
    sessionGeneration.value += 1;
    inflightRefresh = null;
  }

  /** 捕获当前会话身份。 */
  function captureSession(): SessionCapture | null {
    const user = currentUser.value;
    if (!user) return null;
    return { userID: user.id, generation: sessionGeneration.value };
  }

  /** 捕获是否仍指向当前会话。 */
  function isCurrentSession(capture: SessionCapture | null): boolean {
    if (!capture) return false;
    const user = currentUser.value;
    if (!user) return false;
    return user.id === capture.userID && sessionGeneration.value === capture.generation;
  }

  /**
   * 刷新访问令牌。并发调用共享同一次请求。
   * 刷新期间若发生退出或换号，响应落地前会因代际不匹配而被丢弃。
   */
  function refreshAccess(): Promise<void> {
    if (inflightRefresh) return inflightRefresh;
    const generation = sessionGeneration.value;
    const token = refreshToken.value;
    if (!token) {
      clearSession();
      return Promise.resolve();
    }

    inflightRefresh = (async () => {
      try {
        const renewed = await deps.refreshSession(token);
        // 退出或换号后到达的响应不得复活会话
        if (generation !== sessionGeneration.value) return;
        applyCredentials(renewed);
      } catch (cause) {
        if (generation !== sessionGeneration.value) return;
        clearSession();
        error.value = cause instanceof Error ? cause.message : "登录已过期";
      } finally {
        inflightRefresh = null;
      }
    })();
    return inflightRefresh;
  }

  /** access 是否已过期或即将过期。 */
  function needsRefresh(skewMs = 30_000): boolean {
    if (!accessToken.value) return false;
    return deps.now() >= expiresAt.value - skewMs;
  }

  /** 启动时恢复会话。手动退出过则不恢复。 */
  function ensureSessionReady(force = false): boolean {
    if (currentUser.value) return true;
    if (manualLogout.value && !force) return false;
    const stored = deps.load();
    if (!stored) return false;
    accessToken.value = stored.accessToken;
    refreshToken.value = stored.refreshToken;
    expiresAt.value = stored.expiresAt;
    currentUser.value = stored.user;
    sessionGeneration.value += 1;
    return true;
  }

  /** 标记手动退出，阻止静默重登。 */
  function markManualLogout(): void {
    manualLogout.value = true;
  }

  function setManualLogout(value: boolean): void {
    manualLogout.value = value;
  }

  /** 退出：清本地并通知服务端吊销会话。 */
  async function logout(): Promise<void> {
    const token = refreshToken.value;
    const generation = sessionGeneration.value;
    try {
      if (token) {
        await deps.logoutRemote(token);
      }
    } catch {
      // 服务端吊销失败也要清本地，不能让用户困在已退出的界面
    }
    // 期间发生换号时不要清掉新会话
    if (generation === sessionGeneration.value) {
      manualLogout.value = true;
      clearSession();
    }
  }

  /** 发起删除意图，绑定当前账户与代际。 */
  function beginAccountDeletion(): DeletionIntent {
    const user = currentUser.value;
    if (!user) {
      throw new Error("未登录，无法注销");
    }
    return {
      userID: user.id,
      provider: user.provider,
      generation: sessionGeneration.value,
    };
  }

  /** 意图是否仍指向当前会话（防止重验成另一个用户后误删）。 */
  function isDeletionIntentCurrent(intent: DeletionIntent): boolean {
    const user = currentUser.value;
    if (!user) return false;
    return user.id === intent.userID && sessionGeneration.value === intent.generation;
  }

  return {
    currentUser,
    accessToken,
    refreshToken,
    expiresAt,
    sessionGeneration,
    error,
    loading,
    manualLogout,
    isLoggedIn,
    applyCredentials,
    applyLoginResult,
    clearSession,
    captureSession,
    isCurrentSession,
    refreshAccess,
    needsRefresh,
    ensureSessionReady,
    markManualLogout,
    setManualLogout,
    logout,
    beginAccountDeletion,
    isDeletionIntentCurrent,
  };
}

export type SessionStore = ReturnType<typeof createSessionStore>;

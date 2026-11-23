import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  AlertCircle,
  History,
  KeyRound,
  Layers,
  Loader2,
  LogOut,
  MessageSquareText,
  RefreshCw,
  ShieldCheck,
  SlidersHorizontal,
  User,
  UserCheck,
} from 'lucide-react';
import {
  AdminApiError,
  fetchAdminFeedbacks,
  fetchAuditLogs,
  fetchConfigs,
  logoutAdmin,
  updateConfig,
  verifyAdminSession,
} from './api/client';
import { AllConfigsPanel } from './components/AllConfigsPanel';
import { AppPreviewCard } from './components/AppPreviewCard';
import { AuditLogPanel } from './components/AuditLogPanel';
import { ChangePasswordModal } from './components/ChangePasswordModal';
import { FeedbackPanel } from './components/FeedbackPanel';
import { ForceChangePasswordView } from './components/ForceChangePasswordView';
import { LoginScreen } from './components/LoginScreen';
import { PaywallControlCard } from './components/PaywallControlCard';
import { ToastStack, type ToastItem, type ToastType } from './components/Toast';
import {
  arePaywallConfigsEqual,
  DEFAULT_MEMBERSHIP_PAYWALL_CONFIG,
  MEMBERSHIP_PAYWALL_KEY,
  parseMembershipPaywallConfig,
  type AppConfigItem,
  type AuditLogItem,
  type MembershipPaywallConfig,
} from './types/config';
import { EMPTY_FEEDBACK_COUNTS, type AdminFeedbackCounts } from './types/feedback';
import {
  clearAdminSession,
  loadAdminSession,
  saveAdminSession,
  updateSavedOperator,
  type AdminSession,
} from './utils/storage';

type WorkspaceMode = 'remote_config' | 'feedback';
type ActiveTab = 'paywall' | 'audit' | 'configs';
type SessionCheckState = 'idle' | 'verifying' | 'ready' | 'error';

const DEFAULT_PAYWALL_DESCRIPTION = '会员订阅与功能付费开关配置';

export default function App() {
  const initialStoredRef = useRef<AdminSession | null | undefined>(undefined);
  if (initialStoredRef.current === undefined) {
    initialStoredRef.current = loadAdminSession();
  }

  const [session, setSession] = useState<AdminSession | null>(null);
  const [pendingVerifySession, setPendingVerifySession] = useState<AdminSession | null>(
    initialStoredRef.current,
  );
  const [sessionCheckState, setSessionCheckState] = useState<SessionCheckState>(
    initialStoredRef.current ? 'verifying' : 'idle',
  );
  const [verifyError, setVerifyError] = useState<string | null>(null);
  const [verifyAttempt, setVerifyAttempt] = useState(0);

  const [workspace, setWorkspace] = useState<WorkspaceMode>('remote_config');
  const [activeTab, setActiveTab] = useState<ActiveTab>('paywall');
  const [showChangePasswordModal, setShowChangePasswordModal] = useState(false);
  const [loggingOut, setLoggingOut] = useState(false);

  const [feedbackCounts, setFeedbackCounts] = useState<AdminFeedbackCounts>({
    ...EMPTY_FEEDBACK_COUNTS,
  });
  const [feedbackRefreshSignal, setFeedbackRefreshSignal] = useState(0);

  const [configs, setConfigs] = useState<AppConfigItem[]>([]);
  const [auditLogs, setAuditLogs] = useState<AuditLogItem[]>([]);
  const [loadingConfigs, setLoadingConfigs] = useState(false);
  const [loadingLogs, setLoadingLogs] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);

  const [draftPaywall, setDraftPaywall] = useState<MembershipPaywallConfig>({
    ...DEFAULT_MEMBERSHIP_PAYWALL_CONFIG,
  });
  const [paywallNote, setPaywallNote] = useState('');
  const [savingPaywall, setSavingPaywall] = useState(false);

  const [toasts, setToasts] = useState<ToastItem[]>([]);
  const toastSeqRef = useRef(1);

  const pushToast = useCallback((type: ToastType, title: string, description?: string) => {
    const id = toastSeqRef.current++;
    setToasts((prev) => [...prev.slice(-3), { id, type, title, description }]);
    window.setTimeout(() => {
      setToasts((prev) => prev.filter((item) => item.id !== id));
    }, 4200);
  }, []);

  const dismissToast = useCallback((id: number) => {
    setToasts((prev) => prev.filter((item) => item.id !== id));
  }, []);

  const paywallItem = useMemo(
    () => configs.find((item) => item.key === MEMBERSHIP_PAYWALL_KEY) ?? null,
    [configs],
  );

  const livePaywall = useMemo<MembershipPaywallConfig>(
    () =>
      paywallItem
        ? parseMembershipPaywallConfig(paywallItem.value)
        : { ...DEFAULT_MEMBERSHIP_PAYWALL_CONFIG },
    [paywallItem],
  );

  const extraConfigCount = useMemo(
    () => configs.filter((item) => item.key !== MEMBERSHIP_PAYWALL_KEY).length,
    [configs],
  );

  const resetLocalSessionState = useCallback(() => {
    clearAdminSession();
    setSession(null);
    setPendingVerifySession(null);
    setSessionCheckState('idle');
    setVerifyError(null);
    setShowChangePasswordModal(false);
    setConfigs([]);
    setAuditLogs([]);
    setFeedbackCounts({ ...EMPTY_FEEDBACK_COUNTS });
    setWorkspace('remote_config');
    setLoadError(null);
    setPaywallNote('');
  }, []);

  const handleUnauthorized = useCallback(
    (message?: string) => {
      resetLocalSessionState();
      pushToast('error', '会话已过期，请重新登录', message || '登录凭证已失效或已在其他终端注销');
    },
    [pushToast, resetLocalSessionState],
  );

  const handleMustChangePasswordRequired = useCallback(
    (message?: string) => {
      setShowChangePasswordModal(false);
      setSession((prev) => {
        if (!prev) {
          return prev;
        }
        const updated: AdminSession = { ...prev, mustChangePassword: true };
        saveAdminSession(updated);
        return updated;
      });
      pushToast(
        'error',
        '请先完成首次修改密码',
        message || '当前账号仍在使用初始密码，设置永久密码后方可修改配置',
      );
    },
    [pushToast],
  );

  // Restore and validate existing session on page reload via GET /admin/auth/verify
  useEffect(() => {
    if (!pendingVerifySession || sessionCheckState !== 'verifying') {
      return;
    }

    let cancelled = false;
    setVerifyError(null);

    void verifyAdminSession(pendingVerifySession.apiBase, pendingVerifySession.token)
      .then((result) => {
        if (cancelled) {
          return;
        }
        const restored: AdminSession = {
          ...pendingVerifySession,
          username: result.username || pendingVerifySession.username || 'admin',
          mustChangePassword: result.must_change_password,
          operator: pendingVerifySession.operator || result.username || 'admin',
        };
        saveAdminSession(restored);
        setSession(restored);
        setPendingVerifySession(null);
        setSessionCheckState('ready');
      })
      .catch((error: unknown) => {
        if (cancelled) {
          return;
        }
        if (error instanceof AdminApiError && error.isUnauthorized) {
          resetLocalSessionState();
          pushToast('info', '登录会话已失效', error.message || '请使用管理员账号重新登录');
          return;
        }
        const message = error instanceof Error ? error.message : '无法验证当前登录会话';
        setVerifyError(message);
        setSessionCheckState('error');
      });

    return () => {
      cancelled = true;
    };
  }, [pendingVerifySession, sessionCheckState, verifyAttempt, pushToast, resetLocalSessionState]);

  const refreshLogs = useCallback(
    async (apiBase: string, token: string, silent = false) => {
      setLoadingLogs(true);
      try {
        const list = await fetchAuditLogs(apiBase, token, 30);
        setAuditLogs(list);
      } catch (error) {
        if (error instanceof AdminApiError && error.isUnauthorized) {
          handleUnauthorized(error.message);
          return;
        }
        if (!silent) {
          pushToast(
            'error',
            '刷新审计日志失败',
            error instanceof Error ? error.message : '请稍后重试',
          );
        }
      } finally {
        setLoadingLogs(false);
      }
    },
    [handleUnauthorized, pushToast],
  );

  const refreshFeedbackCounts = useCallback(
    async (apiBase: string, token: string) => {
      try {
        const res = await fetchAdminFeedbacks(apiBase, token, {
          status: 'all',
          category: 'all',
          q: '',
          limit: 1,
          offset: 0,
        });
        setFeedbackCounts(res.counts);
      } catch (error) {
        if (error instanceof AdminApiError && error.isUnauthorized) {
          handleUnauthorized(error.message);
          return;
        }
        if (error instanceof AdminApiError && error.isMustChangePassword) {
          handleMustChangePasswordRequired(error.message);
        }
        // Silently ignore non-auth badge fetch errors so remote config workspace stays usable.
      }
    },
    [handleMustChangePasswordRequired, handleUnauthorized],
  );

  const loadWorkspaceData = useCallback(
    async (
      apiBase: string,
      token: string,
      options: { syncDraft?: boolean; notify?: boolean } = {},
    ) => {
      const { syncDraft = true, notify = false } = options;
      setLoadingConfigs(true);
      setLoadingLogs(true);
      setLoadError(null);

      try {
        const [configList, logList] = await Promise.all([
          fetchConfigs(apiBase, token),
          fetchAuditLogs(apiBase, token, 30),
        ]);

        setConfigs(configList);
        setAuditLogs(logList);

        if (syncDraft) {
          const serverPaywall = configList.find((item) => item.key === MEMBERSHIP_PAYWALL_KEY);
          setDraftPaywall(
            serverPaywall
              ? parseMembershipPaywallConfig(serverPaywall.value)
              : { ...DEFAULT_MEMBERSHIP_PAYWALL_CONFIG },
          );
        }

        if (notify) {
          pushToast('info', '已同步服务端最新配置');
        }
      } catch (error) {
        if (error instanceof AdminApiError && error.isUnauthorized) {
          handleUnauthorized(error.message);
          return;
        }
        if (error instanceof AdminApiError && error.isMustChangePassword) {
          handleMustChangePasswordRequired(error.message);
          return;
        }
        const message = error instanceof Error ? error.message : '拉取远程配置失败';
        setLoadError(message);
        pushToast('error', '拉取配置失败', message);
      } finally {
        setLoadingConfigs(false);
        setLoadingLogs(false);
      }
    },
    [handleMustChangePasswordRequired, handleUnauthorized, pushToast],
  );

  const activeToken = session?.token ?? null;
  const activeApiBase = session?.apiBase ?? null;
  const activeMustChangePassword = session?.mustChangePassword ?? false;

  useEffect(() => {
    if (
      sessionCheckState !== 'ready' ||
      !activeToken ||
      !activeApiBase ||
      activeMustChangePassword
    ) {
      return;
    }
    void loadWorkspaceData(activeApiBase, activeToken, { syncDraft: true, notify: false });
    void refreshFeedbackCounts(activeApiBase, activeToken);
  }, [
    sessionCheckState,
    activeApiBase,
    activeToken,
    activeMustChangePassword,
    loadWorkspaceData,
    refreshFeedbackCounts,
  ]);

  function handleAuthenticated(nextSession: AdminSession) {
    saveAdminSession(nextSession);
    setSession(nextSession);
    setPendingVerifySession(null);
    setSessionCheckState('ready');
    if (nextSession.mustChangePassword) {
      pushToast('info', '首次登录安全提示', '请先设置永久密码后再进入控制台');
    } else {
      pushToast(
        'success',
        `欢迎回来，${nextSession.username}`,
        `已连接 ${nextSession.apiBase}`,
      );
    }
  }

  function handleForcePasswordChanged(username: string) {
    setSession((prev) => {
      if (!prev) {
        return prev;
      }
      const normalizedUsername = username.trim() || prev.username;
      const updated: AdminSession = {
        ...prev,
        username: normalizedUsername,
        mustChangePassword: false,
        operator: prev.operator.trim() || normalizedUsername,
      };
      saveAdminSession(updated);
      return updated;
    });
    pushToast('success', '永久密码设置成功', '已加密持久化保存，正在进入配置工作台');
  }

  function handleModalPasswordChanged(username: string) {
    setShowChangePasswordModal(false);
    setSession((prev) => {
      if (!prev) {
        return prev;
      }
      const normalizedUsername = username.trim() || prev.username;
      const updated: AdminSession = {
        ...prev,
        username: normalizedUsername,
        mustChangePassword: false,
      };
      saveAdminSession(updated);
      return updated;
    });
    pushToast('success', '管理员密码已更新', '新密码已加密保存，其他终端会话已自动失效');
  }

  async function handleLogout() {
    if (loggingOut) {
      return;
    }
    setLoggingOut(true);
    const active = session ?? pendingVerifySession;
    try {
      if (active) {
        await logoutAdmin(active.apiBase, active.token);
      }
    } catch {
      // Even if remote logout fails or session already expired, always clear local credentials.
    } finally {
      resetLocalSessionState();
      setLoggingOut(false);
      pushToast('info', '已安全退出登录', '当前会话与标签页凭据已清除');
    }
  }

  function handleOperatorChange(nextOperator: string) {
    if (!session) {
      return;
    }
    const updated: AdminSession = { ...session, operator: nextOperator };
    setSession(updated);
    updateSavedOperator(nextOperator);
  }

  async function handleSavePaywall(): Promise<boolean> {
    if (!session) {
      return false;
    }

    setSavingPaywall(true);
    const cleanedConfig: MembershipPaywallConfig = {
      chanlun_requires_membership: draftPaywall.chanlun_requires_membership,
      membership_entry_visible: draftPaywall.membership_entry_visible,
      free_access_notice: draftPaywall.free_access_notice.trim(),
    };

    try {
      const updatedItem = await updateConfig(
        session.apiBase,
        session.token,
        MEMBERSHIP_PAYWALL_KEY,
        {
          value: { ...cleanedConfig },
          description: paywallItem?.description || DEFAULT_PAYWALL_DESCRIPTION,
          operator: session.operator.trim() || session.username || 'admin',
          note: paywallNote.trim(),
        },
      );

      setConfigs((prev) => {
        const exists = prev.some((item) => item.key === updatedItem.key);
        if (exists) {
          return prev.map((item) => (item.key === updatedItem.key ? updatedItem : item));
        }
        return [updatedItem, ...prev];
      });
      setDraftPaywall(parseMembershipPaywallConfig(updatedItem.value));
      setPaywallNote('');

      pushToast(
        'success',
        '配置已保存并立即生效',
        cleanedConfig.chanlun_requires_membership
          ? '禅观当前处于「收费中 · 需订阅会员解锁」状态'
          : '禅观当前处于「免费开放中 · 无需订阅直开」状态',
      );

      void refreshLogs(session.apiBase, session.token, true);
      return true;
    } catch (error) {
      if (error instanceof AdminApiError && error.isUnauthorized) {
        handleUnauthorized(error.message);
        return false;
      }
      if (error instanceof AdminApiError && error.isMustChangePassword) {
        handleMustChangePasswordRequired(error.message);
        return false;
      }
      pushToast(
        'error',
        '保存配置失败',
        error instanceof Error ? error.message : '请检查网络或配置格式后重试',
      );
      return false;
    } finally {
      setSavingPaywall(false);
    }
  }

  async function handleSaveExtensionConfig(
    key: string,
    value: Record<string, unknown>,
    description: string,
    note: string,
  ): Promise<boolean> {
    if (!session) {
      return false;
    }
    try {
      const updatedItem = await updateConfig(session.apiBase, session.token, key, {
        value,
        description,
        operator: session.operator.trim() || session.username || 'admin',
        note,
      });

      setConfigs((prev) => {
        const exists = prev.some((item) => item.key === updatedItem.key);
        if (exists) {
          return prev.map((item) => (item.key === updatedItem.key ? updatedItem : item));
        }
        return [...prev, updatedItem];
      });

      if (key === MEMBERSHIP_PAYWALL_KEY) {
        setDraftPaywall(parseMembershipPaywallConfig(updatedItem.value));
      }

      pushToast('success', `配置 ${key} 已保存`, '审计日志已同步记录');
      void refreshLogs(session.apiBase, session.token, true);
      return true;
    } catch (error) {
      if (error instanceof AdminApiError && error.isUnauthorized) {
        handleUnauthorized(error.message);
        return false;
      }
      if (error instanceof AdminApiError && error.isMustChangePassword) {
        handleMustChangePasswordRequired(error.message);
        return false;
      }
      pushToast(
        'error',
        `保存配置 ${key} 失败`,
        error instanceof Error ? error.message : '请检查配置内容后重试',
      );
      return false;
    }
  }

  // 1. Session verification screen on page refresh
  if (sessionCheckState === 'verifying' || sessionCheckState === 'error') {
    return (
      <div className="sumly-backdrop flex min-h-screen items-center justify-center px-4 text-[#F5F2EB]">
        <ToastStack toasts={toasts} onDismiss={dismissToast} />
        <div className="gold-card w-full max-w-md rounded-2xl p-7 text-center">
          <div className="mx-auto mb-4 flex h-13 w-13 items-center justify-center rounded-2xl border border-[#F2C512]/35 bg-gradient-to-br from-[#2B2619] to-[#1A1917]">
            {sessionCheckState === 'verifying' ? (
              <Loader2 className="h-6 w-6 animate-spin text-[#F2C512]" />
            ) : (
              <AlertCircle className="h-6 w-6 text-[#FF5D5D]" />
            )}
          </div>
          <h1 className="text-lg font-semibold text-[#F8F5EE]">
            {sessionCheckState === 'verifying' ? '正在验证管理员会话' : '会话恢复失败'}
          </h1>
          <p className="mt-1.5 text-xs leading-relaxed text-[#A39C90]">
            {sessionCheckState === 'verifying'
              ? '正在同步账号权限与密码安全状态，请稍候...'
              : verifyError || '无法连接服务端验证会话状态，请检查网络后重试'}
          </p>

          {sessionCheckState === 'error' ? (
            <div className="mt-5 flex items-center justify-center gap-3">
              <button
                type="button"
                onClick={() => {
                  setSessionCheckState('verifying');
                  setVerifyAttempt((prev) => prev + 1);
                }}
                className="gold-btn inline-flex cursor-pointer items-center gap-1.5 rounded-xl px-4 py-2.5 text-xs font-semibold transition"
              >
                <RefreshCw className="h-3.5 w-3.5" />
                重新验证
              </button>
              <button
                type="button"
                onClick={() => resetLocalSessionState()}
                className="cursor-pointer rounded-xl border border-white/10 bg-[#141416] px-4 py-2.5 text-xs font-medium text-[#CBC4B7] transition hover:border-white/20 hover:text-[#F5F2EB]"
              >
                返回登录页
              </button>
            </div>
          ) : null}
        </div>
      </div>
    );
  }

  // 2. Unauthenticated login screen
  if (!session) {
    return (
      <>
        <ToastStack toasts={toasts} onDismiss={dismissToast} />
        <LoginScreen onAuthenticated={handleAuthenticated} />
      </>
    );
  }

  // 3. Mandatory first-login password change gate
  if (session.mustChangePassword) {
    return (
      <>
        <ToastStack toasts={toasts} onDismiss={dismissToast} />
        <ForceChangePasswordView
          session={session}
          loggingOut={loggingOut}
          onPasswordChanged={handleForcePasswordChanged}
          onLogout={handleLogout}
        />
      </>
    );
  }

  const isDraftModified = !arePaywallConfigsEqual(livePaywall, draftPaywall);

  // 4. Main console workspace
  return (
    <div className="sumly-backdrop min-h-screen text-[#F5F2EB]">
      <ToastStack toasts={toasts} onDismiss={dismissToast} />

      <ChangePasswordModal
        open={showChangePasswordModal}
        session={session}
        onClose={() => setShowChangePasswordModal(false)}
        onSuccess={handleModalPasswordChanged}
      />

      {/* Top Sticky Glass Header */}
      <header className="sticky top-0 z-30 border-b border-white/8 bg-[#141416]/85 backdrop-blur-xl">
        <div className="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-3 px-4 py-3.5 sm:px-6 lg:px-8">
          {/* Brand + Primary Dual-Workspace Switcher */}
          <div className="flex flex-wrap items-center gap-3 sm:gap-5">
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 items-center justify-center rounded-xl border border-[#F2C512]/35 bg-gradient-to-br from-[#2B2516] to-[#191816] shadow-[0_8px_24px_-10px_rgba(242,197,18,0.5)]">
                <ShieldCheck className="h-5 w-5 text-[#F2C512]" />
              </div>
              <div>
                <div className="flex items-center gap-2">
                  <h1 className="text-base font-semibold tracking-tight text-[#F8F5EE]">
                    记金 Sumly 控制台
                  </h1>
                  <span className="hidden rounded-full border border-[#3DD68C]/30 bg-[#3DD68C]/10 px-2 py-0.5 text-[10px] font-medium text-[#5AE2A0] sm:inline-flex">
                    已认证
                  </span>
                </div>
                <p className="font-mono text-[11px] text-[#8A8377]">{session.apiBase}</p>
              </div>
            </div>

            {/* Dual-Workspace Segmented Switcher */}
            <div
              role="tablist"
              aria-label="主工作台切换"
              className="inline-flex items-center rounded-xl border border-white/10 bg-[#1B1A18] p-1"
            >
              <button
                type="button"
                role="tab"
                aria-selected={workspace === 'remote_config'}
                onClick={() => setWorkspace('remote_config')}
                className={`inline-flex cursor-pointer items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-semibold transition ${
                  workspace === 'remote_config'
                    ? 'border border-[#F2C512]/35 bg-[#F2C512]/16 text-[#FFE066] shadow-[0_4px_14px_-6px_rgba(242,197,18,0.55)]'
                    : 'border border-transparent text-[#9E978B] hover:text-[#EAE4D8]'
                }`}
              >
                <SlidersHorizontal className="h-3.5 w-3.5" />
                <span>远程配置</span>
              </button>

              <button
                type="button"
                role="tab"
                aria-selected={workspace === 'feedback'}
                onClick={() => setWorkspace('feedback')}
                className={`inline-flex cursor-pointer items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-semibold transition ${
                  workspace === 'feedback'
                    ? 'border border-[#F2C512]/35 bg-[#F2C512]/16 text-[#FFE066] shadow-[0_4px_14px_-6px_rgba(242,197,18,0.55)]'
                    : 'border border-transparent text-[#9E978B] hover:text-[#EAE4D8]'
                }`}
              >
                <MessageSquareText className="h-3.5 w-3.5" />
                <span>用户反馈</span>
                {feedbackCounts.new > 0 ? (
                  <span
                    title={`${feedbackCounts.new} 条待处理反馈`}
                    className="inline-flex min-w-[18px] items-center justify-center rounded-full bg-[#FF5D5D] px-1.5 py-0.5 font-mono text-[10px] font-bold leading-none text-white shadow-[0_0_12px_rgba(255,93,93,0.55)] tabular-nums"
                  >
                    {feedbackCounts.new > 99 ? '99+' : feedbackCounts.new}
                  </span>
                ) : feedbackCounts.all > 0 ? (
                  <span className="inline-flex min-w-[18px] items-center justify-center rounded-full bg-[#F2C512]/18 px-1.5 py-0.5 font-mono text-[10px] font-semibold leading-none text-[#FFE066] tabular-nums">
                    0
                  </span>
                ) : null}
              </button>
            </div>
          </div>

          {/* Right Utilities */}
          <div className="flex flex-wrap items-center gap-2 sm:gap-2.5">
            {/* Logged-in Account Badge */}
            <div
              title={`当前登录账号：${session.username}`}
              className="inline-flex items-center gap-1.5 rounded-xl border border-[#F2C512]/25 bg-[#F2C512]/8 px-3 py-2 text-xs font-medium text-[#FFE066]"
            >
              <User className="h-3.5 w-3.5 text-[#F2C512]" />
              <span className="max-w-[110px] truncate font-mono">{session.username}</span>
            </div>

            {/* Inline Operator Chip */}
            <label className="hidden items-center gap-1.5 rounded-xl border border-white/8 bg-[#1B1A18] px-2.5 py-2 text-xs text-[#A39C90] xl:inline-flex">
              <UserCheck className="h-3.5 w-3.5 text-[#F2C512]/80" />
              <span>审计人</span>
              <input
                type="text"
                maxLength={32}
                value={session.operator}
                onChange={(e) => handleOperatorChange(e.target.value)}
                aria-label="当前审计操作人"
                className="w-20 bg-transparent font-medium text-[#F5F2EB] focus:outline-none"
              />
            </label>

            <button
              type="button"
              onClick={() => {
                if (workspace === 'feedback') {
                  setFeedbackRefreshSignal((prev) => prev + 1);
                  return;
                }
                void loadWorkspaceData(session.apiBase, session.token, {
                  syncDraft: !isDraftModified,
                  notify: true,
                });
                void refreshFeedbackCounts(session.apiBase, session.token);
              }}
              disabled={workspace === 'remote_config' && (loadingConfigs || loadingLogs)}
              className="inline-flex cursor-pointer items-center gap-1.5 rounded-xl border border-white/10 bg-[#1B1A18] px-3 py-2 text-xs font-medium text-[#DDD6C9] transition hover:border-[#F2C512]/40 hover:text-[#F2C512] disabled:opacity-50"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 ${
                  workspace === 'remote_config' && (loadingConfigs || loadingLogs)
                    ? 'animate-spin text-[#F2C512]'
                    : ''
                }`}
              />
              <span className="hidden sm:inline">同步状态</span>
            </button>

            <button
              type="button"
              onClick={() => setShowChangePasswordModal(true)}
              className="inline-flex cursor-pointer items-center gap-1.5 rounded-xl border border-[#F2C512]/30 bg-[#F2C512]/10 px-3 py-2 text-xs font-medium text-[#FFE066] transition hover:border-[#F2C512]/55 hover:bg-[#F2C512]/18"
            >
              <KeyRound className="h-3.5 w-3.5 text-[#F2C512]" />
              <span>修改密码</span>
            </button>

            <button
              type="button"
              onClick={() => void handleLogout()}
              disabled={loggingOut}
              className="inline-flex cursor-pointer items-center gap-1.5 rounded-xl border border-[#FF5D5D]/25 bg-[#FF5D5D]/10 px-3 py-2 text-xs font-medium text-[#FF9B9B] transition hover:border-[#FF5D5D]/50 hover:bg-[#FF5D5D]/18 disabled:cursor-not-allowed disabled:opacity-50"
            >
              {loggingOut ? (
                <Loader2 className="h-3.5 w-3.5 animate-spin" />
              ) : (
                <LogOut className="h-3.5 w-3.5" />
              )}
              <span>退出登录</span>
            </button>
          </div>
        </div>

        {/* Remote Config Sub-navigation Tabs */}
        {workspace === 'remote_config' ? (
          <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
            <nav aria-label="远程配置子视图切换" className="-mb-px flex gap-1 overflow-x-auto">
              {(
                [
                  {
                    id: 'paywall',
                    label: '功能开关工作台',
                    icon: SlidersHorizontal,
                    badge: livePaywall.chanlun_requires_membership ? '收费中' : '免费中',
                    badgeTone: livePaywall.chanlun_requires_membership
                      ? 'bg-[#FF5D5D]/15 text-[#FF8E8E]'
                      : 'bg-[#3DD68C]/15 text-[#5AE2A0]',
                  },
                  {
                    id: 'audit',
                    label: '变更审计日志',
                    icon: History,
                    badge: `${auditLogs.length}`,
                    badgeTone: 'bg-white/8 text-[#C5BEB2]',
                  },
                  {
                    id: 'configs',
                    label: '扩展配置管理',
                    icon: Layers,
                    badge: `${extraConfigCount}`,
                    badgeTone: 'bg-white/8 text-[#C5BEB2]',
                  },
                ] as const
              ).map((tab) => {
                const Icon = tab.icon;
                const active = activeTab === tab.id;
                return (
                  <button
                    key={tab.id}
                    type="button"
                    onClick={() => setActiveTab(tab.id)}
                    className={`inline-flex shrink-0 cursor-pointer items-center gap-2 border-b-2 px-4 py-3 text-sm font-medium transition ${
                      active
                        ? 'border-[#F2C512] text-[#FFE066]'
                        : 'border-transparent text-[#989185] hover:border-white/15 hover:text-[#E5DFD3]'
                    }`}
                  >
                    <Icon className="h-4 w-4" />
                    <span>{tab.label}</span>
                    <span
                      className={`rounded-full px-2 py-0.5 text-[10px] font-semibold ${tab.badgeTone}`}
                    >
                      {tab.badge}
                    </span>
                  </button>
                );
              })}
            </nav>
          </div>
        ) : null}
      </header>

      {/* Main Content */}
      <main className="mx-auto max-w-7xl px-4 py-6 sm:px-6 sm:py-8 lg:px-8">
        {workspace === 'feedback' ? (
          <FeedbackPanel
            apiBase={session.apiBase}
            token={session.token}
            initialCounts={feedbackCounts}
            refreshSignal={feedbackRefreshSignal}
            onCountsChange={setFeedbackCounts}
            onToast={pushToast}
            onUnauthorized={handleUnauthorized}
            onMustChangePassword={handleMustChangePasswordRequired}
          />
        ) : (
          <>
            {loadError ? (
              <div className="mb-6 flex flex-col gap-3 rounded-2xl border border-[#FF5D5D]/35 bg-[#261919] px-5 py-4 sm:flex-row sm:items-center sm:justify-between">
                <div className="flex items-start gap-3">
                  <AlertCircle className="mt-0.5 h-5 w-5 shrink-0 text-[#FF5D5D]" />
                  <div>
                    <p className="text-sm font-semibold text-[#FFD2D2]">远程配置同步遇到异常</p>
                    <p className="mt-0.5 text-xs text-[#E8AAAA]">{loadError}</p>
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() =>
                    void loadWorkspaceData(session.apiBase, session.token, {
                      syncDraft: true,
                      notify: true,
                    })
                  }
                  className="shrink-0 cursor-pointer rounded-xl border border-[#FF5D5D]/35 bg-[#FF5D5D]/15 px-4 py-2 text-xs font-medium text-[#FFD2D2] transition hover:bg-[#FF5D5D]/25"
                >
                  立即重试
                </button>
              </div>
            ) : null}

            {activeTab === 'paywall' ? (
              <div className="space-y-6">
                <div className="grid gap-6 lg:grid-cols-12 lg:items-start">
                  <div className="lg:col-span-7">
                    <PaywallControlCard
                      liveConfig={livePaywall}
                      draftConfig={draftPaywall}
                      onDraftChange={setDraftPaywall}
                      note={paywallNote}
                      onNoteChange={setPaywallNote}
                      updatedBy={paywallItem?.updated_by ?? ''}
                      updatedAt={paywallItem?.updated_at ?? ''}
                      usingFallbackDefault={!paywallItem && !loadingConfigs}
                      saving={savingPaywall}
                      onSave={handleSavePaywall}
                      onReset={() => {
                        setDraftPaywall({ ...livePaywall });
                        setPaywallNote('');
                      }}
                    />
                  </div>

                  <div className="lg:col-span-5">
                    <AppPreviewCard config={draftPaywall} isDraftModified={isDraftModified} />
                  </div>
                </div>

                {/* Compact Recent Audit Trail right below workspace */}
                <AuditLogPanel
                  logs={auditLogs}
                  loading={loadingLogs}
                  onRefresh={() => void refreshLogs(session.apiBase, session.token)}
                  compactLimit={5}
                  onViewAll={() => setActiveTab('audit')}
                />
              </div>
            ) : null}

            {activeTab === 'audit' ? (
              <AuditLogPanel
                logs={auditLogs}
                loading={loadingLogs}
                onRefresh={() => void refreshLogs(session.apiBase, session.token)}
              />
            ) : null}

            {activeTab === 'configs' ? (
              <AllConfigsPanel configs={configs} onSaveConfig={handleSaveExtensionConfig} />
            ) : null}
          </>
        )}
      </main>
    </div>
  );
}

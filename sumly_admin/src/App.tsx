import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  AlertCircle,
  History,
  Layers,
  LogOut,
  RefreshCw,
  ShieldCheck,
  SlidersHorizontal,
  UserCheck,
} from 'lucide-react';
import {
  AdminApiError,
  fetchAuditLogs,
  fetchConfigs,
  updateConfig,
} from './api/client';
import { AllConfigsPanel } from './components/AllConfigsPanel';
import { AppPreviewCard } from './components/AppPreviewCard';
import { AuditLogPanel } from './components/AuditLogPanel';
import { PaywallControlCard } from './components/PaywallControlCard';
import { ToastStack, type ToastItem, type ToastType } from './components/Toast';
import { TokenGate } from './components/TokenGate';
import {
  arePaywallConfigsEqual,
  DEFAULT_MEMBERSHIP_PAYWALL_CONFIG,
  MEMBERSHIP_PAYWALL_KEY,
  parseMembershipPaywallConfig,
  type AppConfigItem,
  type AuditLogItem,
  type MembershipPaywallConfig,
} from './types/config';
import {
  clearAdminSession,
  loadAdminSession,
  saveAdminSession,
  updateSavedOperator,
  type AdminSession,
} from './utils/storage';

type ActiveTab = 'paywall' | 'audit' | 'configs';

const DEFAULT_PAYWALL_DESCRIPTION = '会员订阅与功能付费开关配置';

export default function App() {
  const [session, setSession] = useState<AdminSession | null>(() => loadAdminSession());
  const [activeTab, setActiveTab] = useState<ActiveTab>('paywall');

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

  const handleUnauthorized = useCallback(
    (message?: string) => {
      clearAdminSession();
      setSession(null);
      setConfigs([]);
      setAuditLogs([]);
      pushToast('error', '会话已过期，请重新验证', message || '管理员令牌失效或已变更');
    },
    [pushToast],
  );

  const refreshLogs = useCallback(
    async (currentSession: AdminSession, silent = false) => {
      setLoadingLogs(true);
      try {
        const list = await fetchAuditLogs(currentSession.apiBase, currentSession.token, 30);
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

  const loadWorkspaceData = useCallback(
    async (currentSession: AdminSession, options: { syncDraft?: boolean; notify?: boolean } = {}) => {
      const { syncDraft = true, notify = false } = options;
      setLoadingConfigs(true);
      setLoadingLogs(true);
      setLoadError(null);

      try {
        const [configList, logList] = await Promise.all([
          fetchConfigs(currentSession.apiBase, currentSession.token),
          fetchAuditLogs(currentSession.apiBase, currentSession.token, 30),
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
        const message = error instanceof Error ? error.message : '拉取远程配置失败';
        setLoadError(message);
        pushToast('error', '拉取配置失败', message);
      } finally {
        setLoadingConfigs(false);
        setLoadingLogs(false);
      }
    },
    [handleUnauthorized, pushToast],
  );

  useEffect(() => {
    if (!session) {
      return;
    }
    void loadWorkspaceData(session, { syncDraft: true, notify: false });
  }, [session, loadWorkspaceData]);

  function handleAuthenticated(nextSession: AdminSession) {
    saveAdminSession(nextSession);
    setSession(nextSession);
    pushToast('success', '管理员身份验证通过', `已连接 ${nextSession.apiBase}`);
  }

  function handleLogout() {
    clearAdminSession();
    setSession(null);
    setConfigs([]);
    setAuditLogs([]);
    setPaywallNote('');
    pushToast('info', '已安全退出登录', '当前标签页令牌已清除');
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
          operator: session.operator.trim() || 'admin',
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

      void refreshLogs(session, true);
      return true;
    } catch (error) {
      if (error instanceof AdminApiError && error.isUnauthorized) {
        handleUnauthorized(error.message);
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
        operator: session.operator.trim() || 'admin',
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
      void refreshLogs(session, true);
      return true;
    } catch (error) {
      if (error instanceof AdminApiError && error.isUnauthorized) {
        handleUnauthorized(error.message);
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

  if (!session) {
    return (
      <>
        <ToastStack toasts={toasts} onDismiss={dismissToast} />
        <TokenGate onAuthenticated={handleAuthenticated} />
      </>
    );
  }

  const isDraftModified = !arePaywallConfigsEqual(livePaywall, draftPaywall);

  return (
    <div className="sumly-backdrop min-h-screen text-[#F5F2EB]">
      <ToastStack toasts={toasts} onDismiss={dismissToast} />

      {/* Top Sticky Glass Header */}
      <header className="sticky top-0 z-30 border-b border-white/8 bg-[#141416]/85 backdrop-blur-xl">
        <div className="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-3 px-4 py-3.5 sm:px-6 lg:px-8">
          {/* Brand */}
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
                  已鉴权
                </span>
              </div>
              <p className="font-mono text-[11px] text-[#8A8377]">{session.apiBase}</p>
            </div>
          </div>

          {/* Right Utilities */}
          <div className="flex items-center gap-2 sm:gap-2.5">
            {/* Inline Operator Chip */}
            <label className="hidden items-center gap-1.5 rounded-xl border border-white/8 bg-[#1B1A18] px-2.5 py-1.5 text-xs text-[#A39C90] md:inline-flex">
              <UserCheck className="h-3.5 w-3.5 text-[#F2C512]/80" />
              <span>操作人</span>
              <input
                type="text"
                maxLength={32}
                value={session.operator}
                onChange={(e) => handleOperatorChange(e.target.value)}
                aria-label="当前操作人"
                className="w-20 bg-transparent font-medium text-[#F5F2EB] focus:outline-none"
              />
            </label>

            <button
              type="button"
              onClick={() => void loadWorkspaceData(session, { syncDraft: !isDraftModified, notify: true })}
              disabled={loadingConfigs || loadingLogs}
              className="inline-flex cursor-pointer items-center gap-1.5 rounded-xl border border-white/10 bg-[#1B1A18] px-3 py-2 text-xs font-medium text-[#DDD6C9] transition hover:border-[#F2C512]/40 hover:text-[#F2C512] disabled:opacity-50"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 ${
                  loadingConfigs || loadingLogs ? 'animate-spin text-[#F2C512]' : ''
                }`}
              />
              <span className="hidden sm:inline">同步状态</span>
            </button>

            <button
              type="button"
              onClick={handleLogout}
              className="inline-flex cursor-pointer items-center gap-1.5 rounded-xl border border-[#FF5D5D]/25 bg-[#FF5D5D]/10 px-3 py-2 text-xs font-medium text-[#FF9B9B] transition hover:border-[#FF5D5D]/50 hover:bg-[#FF5D5D]/18"
            >
              <LogOut className="h-3.5 w-3.5" />
              <span>退出登录</span>
            </button>
          </div>
        </div>

        {/* Sub-navigation Tabs */}
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <nav aria-label="控制台工作区切换" className="-mb-px flex gap-1 overflow-x-auto">
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
                  <span className={`rounded-full px-2 py-0.5 text-[10px] font-semibold ${tab.badgeTone}`}>
                    {tab.badge}
                  </span>
                </button>
              );
            })}
          </nav>
        </div>
      </header>

      {/* Main Content */}
      <main className="mx-auto max-w-7xl px-4 py-6 sm:px-6 sm:py-8 lg:px-8">
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
              onClick={() => void loadWorkspaceData(session, { syncDraft: true, notify: true })}
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
              onRefresh={() => void refreshLogs(session)}
              compactLimit={5}
              onViewAll={() => setActiveTab('audit')}
            />
          </div>
        ) : null}

        {activeTab === 'audit' ? (
          <AuditLogPanel
            logs={auditLogs}
            loading={loadingLogs}
            onRefresh={() => void refreshLogs(session)}
          />
        ) : null}

        {activeTab === 'configs' ? (
          <AllConfigsPanel configs={configs} onSaveConfig={handleSaveExtensionConfig} />
        ) : null}
      </main>
    </div>
  );
}

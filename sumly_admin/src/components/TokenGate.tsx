import { useState, type FormEvent } from 'react';
import {
  AlertCircle,
  ChevronDown,
  ChevronUp,
  Eye,
  EyeOff,
  KeyRound,
  Loader2,
  Server,
  ShieldCheck,
  UserCheck,
} from 'lucide-react';
import { AdminApiError, verifyAdminToken } from '../api/client';
import { DEFAULT_API_BASE, getSavedApiBase, normalizeApiBase, type AdminSession } from '../utils/storage';

interface TokenGateProps {
  onAuthenticated: (session: AdminSession) => void;
}

export function TokenGate({ onAuthenticated }: TokenGateProps) {
  const [token, setToken] = useState('');
  const [showToken, setShowToken] = useState(false);
  const [operator, setOperator] = useState('admin');
  const [apiBase, setApiBase] = useState(() => getSavedApiBase());
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [errorDetailCode, setErrorDetailCode] = useState<number | null>(null);

  const normalizedBase = normalizeApiBase(apiBase);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const trimmedToken = token.trim();
    if (!trimmedToken) {
      setErrorMessage('请输入管理员令牌后再验证进入');
      setErrorDetailCode(null);
      return;
    }

    setSubmitting(true);
    setErrorMessage(null);
    setErrorDetailCode(null);

    try {
      await verifyAdminToken(normalizedBase, trimmedToken);
      onAuthenticated({
        token: trimmedToken,
        apiBase: normalizedBase,
        operator: operator.trim() || 'admin',
      });
    } catch (error) {
      if (error instanceof AdminApiError) {
        setErrorMessage(error.message);
        setErrorDetailCode(error.status || null);
      } else {
        setErrorMessage('令牌验证失败，请稍后重试');
        setErrorDetailCode(null);
      }
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="sumly-backdrop relative flex min-h-screen flex-col items-center justify-center overflow-hidden px-4 py-10">
      {/* Subtle geometric gold ring accents */}
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -top-32 left-1/2 h-[420px] w-[420px] -translate-x-1/2 rounded-full border border-[#F2C512]/10 bg-[radial-gradient(circle,rgba(242,197,18,0.08)_0%,transparent_70%)] blur-2xl"
      />

      <div className="relative z-10 w-full max-w-[440px]">
        {/* Brand Header */}
        <div className="mb-7 text-center">
          <div className="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-2xl border border-[#F2C512]/30 bg-gradient-to-br from-[#2B2619] to-[#1A1917] shadow-[0_12px_36px_-10px_rgba(242,197,18,0.38)]">
            <ShieldCheck className="h-7 w-7 text-[#F2C512]" />
          </div>
          <div className="inline-flex items-center gap-2 rounded-full border border-[#F2C512]/20 bg-[#F2C512]/8 px-3 py-1 text-[11px] font-medium tracking-[0.14em] text-[#F2C512] uppercase">
            <span>Sumly Console</span>
            <span className="h-1 w-1 rounded-full bg-[#F2C512]" />
            <span>Remote Config</span>
          </div>
          <h1 className="mt-3 text-2xl font-semibold tracking-tight text-[#F5F2EB]">
            记金远程配置管理后台
          </h1>
          <p className="mt-1.5 text-sm text-[#9D968A]">
            实时管控禅观付费门禁、会员入口与配置审计日志
          </p>
        </div>

        {/* Auth Card */}
        <form onSubmit={handleSubmit} className="gold-card rounded-2xl p-6 sm:p-7">
          <div className="space-y-5">
            {/* Token Field */}
            <div>
              <label
                htmlFor="admin-token-input"
                className="mb-2 flex items-center justify-between text-xs font-medium text-[#CBC4B7]"
              >
                <span className="flex items-center gap-1.5">
                  <KeyRound className="h-3.5 w-3.5 text-[#F2C512]" />
                  管理员令牌（Bearer Token）
                </span>
                <span className="font-mono text-[11px] text-[#7D776D]">ADMIN_API_TOKEN</span>
              </label>

              <div className="relative">
                <input
                  id="admin-token-input"
                  type={showToken ? 'text' : 'password'}
                  autoComplete="current-password"
                  autoFocus
                  value={token}
                  onChange={(e) => setToken(e.target.value)}
                  placeholder="请输入服务端配置的管理员令牌"
                  disabled={submitting}
                  className="w-full rounded-xl border border-white/10 bg-[#141416] py-3 pl-4 pr-11 font-mono text-sm text-[#F5F2EB] placeholder:font-sans placeholder:text-[#655F56] transition focus:border-[#F2C512]/60 focus:outline-none focus:ring-2 focus:ring-[#F2C512]/20 disabled:opacity-60"
                />
                <button
                  type="button"
                  onClick={() => setShowToken((prev) => !prev)}
                  aria-label={showToken ? '隐藏管理员令牌' : '显示管理员令牌'}
                  className="absolute right-2.5 top-1/2 -translate-y-1/2 rounded-lg p-1.5 text-[#8A8377] transition hover:bg-white/5 hover:text-[#F2C512]"
                >
                  {showToken ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                </button>
              </div>
            </div>

            {/* Operator Name Field */}
            <div>
              <label
                htmlFor="admin-operator-input"
                className="mb-2 flex items-center justify-between text-xs font-medium text-[#CBC4B7]"
              >
                <span className="flex items-center gap-1.5">
                  <UserCheck className="h-3.5 w-3.5 text-[#F2C512]/80" />
                  操作人标识（写入审计日志）
                </span>
                <span className="text-[11px] text-[#7D776D]">可选</span>
              </label>
              <input
                id="admin-operator-input"
                type="text"
                maxLength={40}
                value={operator}
                onChange={(e) => setOperator(e.target.value)}
                placeholder="如：carl / ops-admin"
                disabled={submitting}
                className="w-full rounded-xl border border-white/10 bg-[#141416] px-4 py-2.5 text-sm text-[#F5F2EB] placeholder:text-[#655F56] transition focus:border-[#F2C512]/60 focus:outline-none focus:ring-2 focus:ring-[#F2C512]/20 disabled:opacity-60"
              />
            </div>

            {/* Collapsible API Base Config */}
            <div className="rounded-xl border border-white/6 bg-[#141416]/70">
              <button
                type="button"
                onClick={() => setShowAdvanced((prev) => !prev)}
                className="flex w-full items-center justify-between px-3.5 py-2.5 text-left text-xs text-[#A7A094] transition hover:text-[#F5F2EB]"
              >
                <span className="flex items-center gap-2">
                  <Server className="h-3.5 w-3.5 text-[#F2C512]/80" />
                  <span>API 地址</span>
                  <code className="max-w-[190px] truncate rounded bg-white/5 px-1.5 py-0.5 font-mono text-[11px] text-[#D8D2C7]">
                    {normalizedBase}
                  </code>
                </span>
                {showAdvanced ? (
                  <ChevronUp className="h-4 w-4 text-[#7D776D]" />
                ) : (
                  <ChevronDown className="h-4 w-4 text-[#7D776D]" />
                )}
              </button>

              {showAdvanced ? (
                <div className="border-t border-white/6 px-3.5 pb-3.5 pt-3">
                  <label
                    htmlFor="admin-api-base-input"
                    className="mb-1.5 block text-[11px] text-[#9D968A]"
                  >
                    自定义管理接口前缀（留空默认同源 <code className="font-mono text-[#D8D2C7]">{DEFAULT_API_BASE}</code>）
                  </label>
                  <input
                    id="admin-api-base-input"
                    type="text"
                    value={apiBase}
                    onChange={(e) => setApiBase(e.target.value)}
                    placeholder={DEFAULT_API_BASE}
                    disabled={submitting}
                    className="w-full rounded-lg border border-white/10 bg-[#1B1A18] px-3 py-2 font-mono text-xs text-[#F5F2EB] placeholder:text-[#655F56] focus:border-[#F2C512]/60 focus:outline-none"
                  />
                  <div className="mt-2 flex items-center justify-between text-[11px] text-[#7D776D]">
                    <span>验证端点：{normalizedBase}/admin/auth/verify</span>
                    {apiBase !== DEFAULT_API_BASE ? (
                      <button
                        type="button"
                        onClick={() => setApiBase(DEFAULT_API_BASE)}
                        className="text-[#F2C512] hover:underline"
                      >
                        恢复默认
                      </button>
                    ) : null}
                  </div>
                </div>
              ) : null}
            </div>

            {/* Error Alert */}
            {errorMessage ? (
              <div
                role="alert"
                className="flex items-start gap-2.5 rounded-xl border border-[#FF5D5D]/35 bg-[#FF5D5D]/10 px-3.5 py-3 text-xs leading-relaxed text-[#FFB4B4]"
              >
                <AlertCircle className="mt-0.5 h-4 w-4 shrink-0 text-[#FF5D5D]" />
                <div>
                  <p className="font-medium text-[#FFD0D0]">
                    {errorDetailCode === 503
                      ? '管理接口未启用（HTTP 503）'
                      : errorDetailCode === 401
                        ? '身份验证未通过（HTTP 401）'
                        : '无法完成验证'}
                  </p>
                  <p className="mt-0.5 text-[#F4A9A9]/90">{errorMessage}</p>
                </div>
              </div>
            ) : null}

            {/* Submit CTA */}
            <button
              type="submit"
              disabled={submitting}
              className="gold-btn flex w-full cursor-pointer items-center justify-center gap-2 rounded-xl px-4 py-3 text-sm font-semibold tracking-wide transition disabled:cursor-not-allowed disabled:opacity-60"
            >
              {submitting ? (
                <>
                  <Loader2 className="h-4 w-4 animate-spin" />
                  正在校验令牌...
                </>
              ) : (
                '验证并进入'
              )}
            </button>
          </div>
        </form>

        {/* Security Footnote */}
        <p className="mt-5 text-center text-xs leading-relaxed text-[#7D776D]">
          令牌仅保存在当前浏览器标签页的 <span className="font-mono text-[#9E978B]">sessionStorage</span> 中，
          关闭标签页后自动清除，不会持久化写入本地磁盘。
        </p>
      </div>
    </div>
  );
}

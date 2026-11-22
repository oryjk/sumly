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
  User,
} from 'lucide-react';
import { AdminApiError, loginAdmin } from '../api/client';
import {
  DEFAULT_API_BASE,
  getSavedApiBase,
  normalizeApiBase,
  type AdminSession,
} from '../utils/storage';

interface LoginScreenProps {
  onAuthenticated: (session: AdminSession) => void;
}

export function LoginScreen({ onAuthenticated }: LoginScreenProps) {
  const [username, setUsername] = useState('admin');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [apiBase, setApiBase] = useState(() => getSavedApiBase());
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [errorStatus, setErrorStatus] = useState<number | null>(null);

  const normalizedBase = normalizeApiBase(apiBase);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const trimmedUsername = username.trim();
    if (!trimmedUsername) {
      setErrorMessage('请输入管理员账号');
      setErrorStatus(null);
      return;
    }
    if (!password) {
      setErrorMessage('请输入登录密码');
      setErrorStatus(null);
      return;
    }

    setSubmitting(true);
    setErrorMessage(null);
    setErrorStatus(null);

    try {
      const result = await loginAdmin(normalizedBase, {
        username: trimmedUsername,
        password,
      });

      onAuthenticated({
        token: result.token,
        username: result.username,
        mustChangePassword: result.must_change_password,
        expiresAt: result.expires_at,
        apiBase: normalizedBase,
        operator: result.username,
      });
    } catch (error) {
      if (error instanceof AdminApiError) {
        setErrorMessage(error.message);
        setErrorStatus(error.status || null);
      } else {
        setErrorMessage('登录失败，请检查网络连接后重试');
        setErrorStatus(null);
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
            <span>Admin Auth</span>
          </div>
          <h1 className="mt-3 text-2xl font-semibold tracking-tight text-[#F5F2EB]">
            记金远程配置管理后台
          </h1>
          <p className="mt-1.5 text-sm text-[#9D968A]">
            使用管理员账号登录，实时管控禅观付费门禁与配置审计
          </p>
        </div>

        {/* Auth Card */}
        <form onSubmit={handleSubmit} className="gold-card rounded-2xl p-6 sm:p-7">
          <div className="space-y-5">
            {/* Username Field */}
            <div>
              <label
                htmlFor="admin-username-input"
                className="mb-2 flex items-center justify-between text-xs font-medium text-[#CBC4B7]"
              >
                <span className="flex items-center gap-1.5">
                  <User className="h-3.5 w-3.5 text-[#F2C512]" />
                  管理员账号
                </span>
                <span className="font-mono text-[11px] text-[#7D776D]">Username</span>
              </label>
              <input
                id="admin-username-input"
                type="text"
                autoComplete="username"
                maxLength={64}
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                placeholder="请输入管理员账号（默认 admin）"
                disabled={submitting}
                className="w-full rounded-xl border border-white/10 bg-[#141416] px-4 py-3 text-sm text-[#F5F2EB] placeholder:text-[#655F56] transition focus:border-[#F2C512]/60 focus:outline-none focus:ring-2 focus:ring-[#F2C512]/20 disabled:opacity-60"
              />
            </div>

            {/* Password Field */}
            <div>
              <label
                htmlFor="admin-password-input"
                className="mb-2 flex items-center justify-between text-xs font-medium text-[#CBC4B7]"
              >
                <span className="flex items-center gap-1.5">
                  <KeyRound className="h-3.5 w-3.5 text-[#F2C512]" />
                  登录密码
                </span>
                <span className="font-mono text-[11px] text-[#7D776D]">Password</span>
              </label>

              <div className="relative">
                <input
                  id="admin-password-input"
                  type={showPassword ? 'text' : 'password'}
                  autoComplete="current-password"
                  autoFocus
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="请输入管理员密码"
                  disabled={submitting}
                  className="w-full rounded-xl border border-white/10 bg-[#141416] py-3 pl-4 pr-11 text-sm text-[#F5F2EB] placeholder:text-[#655F56] transition focus:border-[#F2C512]/60 focus:outline-none focus:ring-2 focus:ring-[#F2C512]/20 disabled:opacity-60"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword((prev) => !prev)}
                  aria-label={showPassword ? '隐藏密码' : '显示密码'}
                  className="absolute right-2.5 top-1/2 -translate-y-1/2 cursor-pointer rounded-lg p-1.5 text-[#8A8377] transition hover:bg-white/5 hover:text-[#F2C512]"
                >
                  {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                </button>
              </div>
            </div>

            {/* Collapsible Advanced API Base Config */}
            <div className="rounded-xl border border-white/6 bg-[#141416]/70">
              <button
                type="button"
                onClick={() => setShowAdvanced((prev) => !prev)}
                className="flex w-full cursor-pointer items-center justify-between px-3.5 py-2.5 text-left text-xs text-[#A7A094] transition hover:text-[#F5F2EB]"
              >
                <span className="flex items-center gap-2">
                  <Server className="h-3.5 w-3.5 text-[#F2C512]/80" />
                  <span>高级设置 · API 地址</span>
                  <code className="max-w-[165px] truncate rounded bg-white/5 px-1.5 py-0.5 font-mono text-[11px] text-[#D8D2C7]">
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
                    自定义管理接口前缀（默认同源{' '}
                    <code className="font-mono text-[#D8D2C7]">{DEFAULT_API_BASE}</code>）
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
                  <div className="mt-2 flex items-center justify-between gap-2 text-[11px] text-[#7D776D]">
                    <span className="truncate font-mono">
                      POST {normalizedBase}/admin/auth/login
                    </span>
                    {apiBase !== DEFAULT_API_BASE ? (
                      <button
                        type="button"
                        onClick={() => setApiBase(DEFAULT_API_BASE)}
                        className="shrink-0 cursor-pointer text-[#F2C512] hover:underline"
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
                    {errorStatus === 503
                      ? '管理认证服务未就绪（HTTP 503）'
                      : errorStatus === 401
                        ? '账号或密码校验未通过（HTTP 401）'
                        : '无法完成登录'}
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
                  正在登录控制台...
                </>
              ) : (
                '登录控制台'
              )}
            </button>
          </div>
        </form>

        {/* Security Footnote */}
        <p className="mt-5 text-center text-xs leading-relaxed text-[#7D776D]">
          会话令牌仅保存在当前浏览器标签页的{' '}
          <span className="font-mono text-[#9E978B]">sessionStorage</span>{' '}
          中；首次使用初始密码登录后将引导设置永久密码。
        </p>
      </div>
    </div>
  );
}

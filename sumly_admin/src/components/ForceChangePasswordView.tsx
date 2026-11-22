import { useState, type FormEvent } from 'react';
import {
  AlertCircle,
  Check,
  Database,
  Eye,
  EyeOff,
  KeyRound,
  Loader2,
  Lock,
  LogOut,
  ShieldAlert,
  User,
} from 'lucide-react';
import { AdminApiError, changeAdminPassword } from '../api/client';
import { PASSWORD_MAX_BYTES, PASSWORD_MIN_LENGTH } from '../types/config';
import { validatePasswordChange } from '../utils/password';
import type { AdminSession } from '../utils/storage';

interface ForceChangePasswordViewProps {
  session: AdminSession;
  loggingOut: boolean;
  onPasswordChanged: (username: string) => void;
  onLogout: () => Promise<void> | void;
}

export function ForceChangePasswordView({
  session,
  loggingOut,
  onPasswordChanged,
  onLogout,
}: ForceChangePasswordViewProps) {
  const [currentPassword, setCurrentPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');

  const [showCurrent, setShowCurrent] = useState(false);
  const [showNew, setShowNew] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);

  const [submitting, setSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [errorStatus, setErrorStatus] = useState<number | null>(null);

  const validation = validatePasswordChange(currentPassword, newPassword, confirmPassword);
  const busy = submitting || loggingOut;

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!validation.canSubmit) {
      setErrorMessage(validation.blockingMessage ?? '请完整核对密码输入');
      setErrorStatus(null);
      return;
    }

    setSubmitting(true);
    setErrorMessage(null);
    setErrorStatus(null);

    try {
      const result = await changeAdminPassword(session.apiBase, session.token, {
        current_password: currentPassword,
        new_password: newPassword,
      });
      onPasswordChanged(result.username || session.username);
    } catch (error) {
      if (error instanceof AdminApiError) {
        setErrorMessage(error.message);
        setErrorStatus(error.status || null);
      } else {
        setErrorMessage('修改密码失败，请检查网络连接后重试');
        setErrorStatus(null);
      }
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="sumly-backdrop relative flex min-h-screen flex-col overflow-hidden">
      {/* Subtle atmospheric glow */}
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -top-36 left-1/2 h-[440px] w-[440px] -translate-x-1/2 rounded-full border border-[#F2C512]/12 bg-[radial-gradient(circle,rgba(242,197,18,0.1)_0%,transparent_70%)] blur-2xl"
      />

      {/* Top Navigation Bar with Logout */}
      <header className="relative z-10 border-b border-white/8 bg-[#141416]/75 backdrop-blur-xl">
        <div className="mx-auto flex max-w-5xl items-center justify-between gap-3 px-4 py-3.5 sm:px-6">
          <div className="flex items-center gap-2.5">
            <div className="flex h-9 w-9 items-center justify-center rounded-xl border border-[#F2C512]/35 bg-gradient-to-br from-[#2B2516] to-[#191816]">
              <ShieldAlert className="h-4.5 w-4.5 text-[#F2C512]" />
            </div>
            <div>
              <p className="text-sm font-semibold text-[#F8F5EE]">记金 Sumly 控制台</p>
              <p className="font-mono text-[11px] text-[#8A8377]">{session.apiBase}</p>
            </div>
          </div>

          <div className="flex items-center gap-2.5">
            <span className="inline-flex items-center gap-1.5 rounded-xl border border-[#F2C512]/25 bg-[#F2C512]/8 px-3 py-1.5 text-xs font-medium text-[#FFE066]">
              <User className="h-3.5 w-3.5 text-[#F2C512]" />
              <span>{session.username}</span>
            </span>

            <button
              type="button"
              onClick={() => void onLogout()}
              disabled={busy}
              className="inline-flex cursor-pointer items-center gap-1.5 rounded-xl border border-[#FF5D5D]/25 bg-[#FF5D5D]/10 px-3 py-1.5 text-xs font-medium text-[#FF9B9B] transition hover:border-[#FF5D5D]/50 hover:bg-[#FF5D5D]/18 disabled:cursor-not-allowed disabled:opacity-50"
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
      </header>

      {/* Center Force Change Password Card */}
      <main className="relative z-10 flex flex-1 items-center justify-center px-4 py-10">
        <div className="w-full max-w-[480px]">
          <div className="mb-6 text-center">
            <div className="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-2xl border border-[#F2C512]/40 bg-gradient-to-br from-[#302714] to-[#1A1917] shadow-[0_12px_36px_-10px_rgba(242,197,18,0.45)]">
              <KeyRound className="h-7 w-7 text-[#F2C512]" />
            </div>
            <div className="inline-flex items-center gap-2 rounded-full border border-[#F2C512]/30 bg-[#F2C512]/10 px-3 py-1 text-[11px] font-medium tracking-[0.12em] text-[#FFE066]">
              <span>首次登录安全拦截</span>
            </div>
            <h1 className="mt-3 text-2xl font-semibold tracking-tight text-[#F5F2EB]">
              首次登录请设置永久密码
            </h1>
            <p className="mt-1.5 text-sm text-[#A39C90]">
              完成初始密码更换后，即可立即进入配置工作台
            </p>
          </div>

          <form onSubmit={handleSubmit} className="gold-card rounded-2xl p-6 sm:p-7">
            {/* Persistent Storage Explanation Banner */}
            <div className="mb-5 flex items-start gap-3 rounded-xl border border-[#F2C512]/25 bg-[#F2C512]/8 px-3.5 py-3 text-xs leading-relaxed text-[#E7DEC9]">
              <Database className="mt-0.5 h-4 w-4 shrink-0 text-[#F2C512]" />
              <div>
                <p className="font-medium text-[#FFE680]">新密码将加密持久化保存至数据库</p>
                <p className="mt-0.5 text-[#C9C1B2]">
                  密码使用 bcrypt 哈希安全持久化，服务重启不会被重置；修改完成后，以后均请使用此永久密码登录。
                </p>
              </div>
            </div>

            <div className="space-y-4">
              {/* Current Initial Password */}
              <div>
                <label
                  htmlFor="force-current-password"
                  className="mb-1.5 flex items-center justify-between text-xs font-medium text-[#CBC4B7]"
                >
                  <span className="flex items-center gap-1.5">
                    <Lock className="h-3.5 w-3.5 text-[#F2C512]" />
                    当前初始密码
                  </span>
                  <span className="font-mono text-[11px] text-[#7D776D]">
                    账号：{session.username}
                  </span>
                </label>
                <div className="relative">
                  <input
                    id="force-current-password"
                    type={showCurrent ? 'text' : 'password'}
                    autoComplete="current-password"
                    autoFocus
                    value={currentPassword}
                    onChange={(e) => setCurrentPassword(e.target.value)}
                    placeholder="请输入当前登录使用的初始密码"
                    disabled={busy}
                    className="w-full rounded-xl border border-white/10 bg-[#141416] py-2.5 pl-4 pr-11 text-sm text-[#F5F2EB] placeholder:text-[#655F56] transition focus:border-[#F2C512]/60 focus:outline-none focus:ring-2 focus:ring-[#F2C512]/20 disabled:opacity-60"
                  />
                  <button
                    type="button"
                    onClick={() => setShowCurrent((prev) => !prev)}
                    aria-label={showCurrent ? '隐藏当前初始密码' : '显示当前初始密码'}
                    className="absolute right-2.5 top-1/2 -translate-y-1/2 cursor-pointer rounded-lg p-1.5 text-[#8A8377] transition hover:bg-white/5 hover:text-[#F2C512]"
                  >
                    {showCurrent ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                  </button>
                </div>
              </div>

              {/* New Password */}
              <div>
                <label
                  htmlFor="force-new-password"
                  className="mb-1.5 flex items-center justify-between text-xs font-medium text-[#CBC4B7]"
                >
                  <span className="flex items-center gap-1.5">
                    <KeyRound className="h-3.5 w-3.5 text-[#F2C512]" />
                    设置新永久密码
                  </span>
                  <span className={`text-[11px] font-medium ${validation.strength.textClass}`}>
                    {validation.strength.label} · {newPassword.length} 位
                  </span>
                </label>
                <div className="relative">
                  <input
                    id="force-new-password"
                    type={showNew ? 'text' : 'password'}
                    autoComplete="new-password"
                    value={newPassword}
                    onChange={(e) => setNewPassword(e.target.value)}
                    placeholder={`请输入至少 ${PASSWORD_MIN_LENGTH} 位新密码`}
                    disabled={busy}
                    className="w-full rounded-xl border border-white/10 bg-[#141416] py-2.5 pl-4 pr-11 text-sm text-[#F5F2EB] placeholder:text-[#655F56] transition focus:border-[#F2C512]/60 focus:outline-none focus:ring-2 focus:ring-[#F2C512]/20 disabled:opacity-60"
                  />
                  <button
                    type="button"
                    onClick={() => setShowNew((prev) => !prev)}
                    aria-label={showNew ? '隐藏新密码' : '显示新密码'}
                    className="absolute right-2.5 top-1/2 -translate-y-1/2 cursor-pointer rounded-lg p-1.5 text-[#8A8377] transition hover:bg-white/5 hover:text-[#F2C512]"
                  >
                    {showNew ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                  </button>
                </div>

                {/* Live Strength Meter */}
                <div className="mt-2.5">
                  <div className="grid grid-cols-4 gap-1.5" aria-hidden="true">
                    {[1, 2, 3, 4].map((step) => (
                      <div
                        key={step}
                        className={`h-1.5 rounded-full transition-colors ${
                          validation.strength.level >= step
                            ? validation.strength.barClass
                            : 'bg-white/10'
                        }`}
                      />
                    ))}
                  </div>
                  <p className="mt-1.5 text-[11px] text-[#9A9387]">{validation.strength.hint}</p>
                </div>

                {/* Real-time Rules Checklist */}
                <div className="mt-2.5 grid gap-1.5 rounded-xl border border-white/6 bg-[#141416]/75 px-3 py-2.5 text-[11px]">
                  <RuleRow
                    passed={validation.lengthOk && validation.maxBytesOk}
                    active={newPassword.length > 0}
                    label={`长度 ≥ ${PASSWORD_MIN_LENGTH} 位且不超过 ${PASSWORD_MAX_BYTES} 字节（当前 ${newPassword.length} 位 / ${validation.byteLength} 字节）`}
                  />
                  <RuleRow
                    passed={validation.differentFromCurrent}
                    active={newPassword.length > 0 && currentPassword.length > 0}
                    label="新密码不能与当前初始密码相同"
                  />
                </div>
              </div>

              {/* Confirm New Password */}
              <div>
                <label
                  htmlFor="force-confirm-password"
                  className="mb-1.5 flex items-center justify-between text-xs font-medium text-[#CBC4B7]"
                >
                  <span className="flex items-center gap-1.5">
                    <KeyRound className="h-3.5 w-3.5 text-[#F2C512]/80" />
                    确认新密码
                  </span>
                  {confirmPassword.length > 0 ? (
                    <span
                      className={`text-[11px] font-medium ${
                        validation.confirmMatches ? 'text-[#5AE2A0]' : 'text-[#FF8585]'
                      }`}
                    >
                      {validation.confirmMatches ? '两次输入一致' : '两次输入不一致'}
                    </span>
                  ) : null}
                </label>
                <div className="relative">
                  <input
                    id="force-confirm-password"
                    type={showConfirm ? 'text' : 'password'}
                    autoComplete="new-password"
                    value={confirmPassword}
                    onChange={(e) => setConfirmPassword(e.target.value)}
                    placeholder="请再次输入新密码以确认"
                    disabled={busy}
                    className={`w-full rounded-xl border bg-[#141416] py-2.5 pl-4 pr-11 text-sm text-[#F5F2EB] placeholder:text-[#655F56] transition focus:outline-none focus:ring-2 disabled:opacity-60 ${
                      confirmPassword.length > 0 && !validation.confirmMatches
                        ? 'border-[#FF5D5D]/50 focus:border-[#FF5D5D]/70 focus:ring-[#FF5D5D]/20'
                        : confirmPassword.length > 0 && validation.confirmMatches
                          ? 'border-[#3DD68C]/45 focus:border-[#3DD68C]/65 focus:ring-[#3DD68C]/15'
                          : 'border-white/10 focus:border-[#F2C512]/60 focus:ring-[#F2C512]/20'
                    }`}
                  />
                  <button
                    type="button"
                    onClick={() => setShowConfirm((prev) => !prev)}
                    aria-label={showConfirm ? '隐藏确认密码' : '显示确认密码'}
                    className="absolute right-2.5 top-1/2 -translate-y-1/2 cursor-pointer rounded-lg p-1.5 text-[#8A8377] transition hover:bg-white/5 hover:text-[#F2C512]"
                  >
                    {showConfirm ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                  </button>
                </div>
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
                      {errorStatus === 401
                        ? '原密码验证失败或会话已过期（HTTP 401）'
                        : errorStatus === 422
                          ? '新密码不符合安全规则（HTTP 422）'
                          : '无法完成密码修改'}
                    </p>
                    <p className="mt-0.5 text-[#F4A9A9]/90">{errorMessage}</p>
                  </div>
                </div>
              ) : null}

              {/* Submit CTA */}
              <button
                type="submit"
                disabled={busy || !validation.canSubmit}
                className="gold-btn mt-1 flex w-full cursor-pointer items-center justify-center gap-2 rounded-xl px-4 py-3 text-sm font-semibold tracking-wide transition disabled:cursor-not-allowed disabled:opacity-50"
              >
                {submitting ? (
                  <>
                    <Loader2 className="h-4 w-4 animate-spin" />
                    正在加密保存并进入...
                  </>
                ) : (
                  '确认修改并进入控制台'
                )}
              </button>

              {/* Secondary Bottom Logout */}
              <button
                type="button"
                onClick={() => void onLogout()}
                disabled={busy}
                className="flex w-full cursor-pointer items-center justify-center gap-1.5 rounded-xl border border-white/10 bg-[#141416] px-4 py-2.5 text-xs font-medium text-[#A8A195] transition hover:border-[#FF5D5D]/40 hover:text-[#FF9B9B] disabled:cursor-not-allowed disabled:opacity-50"
              >
                <LogOut className="h-3.5 w-3.5" />
                <span>暂不修改，退出登录</span>
              </button>
            </div>
          </form>
        </div>
      </main>
    </div>
  );
}

function RuleRow({
  passed,
  active,
  label,
}: {
  passed: boolean;
  active: boolean;
  label: string;
}) {
  return (
    <div className="flex items-center gap-2">
      <span
        className={`flex h-4 w-4 shrink-0 items-center justify-center rounded-full border text-[10px] ${
          passed
            ? 'border-[#3DD68C]/50 bg-[#3DD68C]/15 text-[#5AE2A0]'
            : active
              ? 'border-[#FF5D5D]/45 bg-[#FF5D5D]/12 text-[#FF8585]'
              : 'border-white/15 bg-white/5 text-[#7D776D]'
        }`}
      >
        {passed ? <Check className="h-2.5 w-2.5" /> : '•'}
      </span>
      <span
        className={
          passed ? 'text-[#5AE2A0]' : active ? 'text-[#FFB4B4]' : 'text-[#8F887D]'
        }
      >
        {label}
      </span>
    </div>
  );
}

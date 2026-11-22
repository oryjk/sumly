import { useEffect, useState, type FormEvent } from 'react';
import {
  AlertCircle,
  Check,
  CheckCircle2,
  Eye,
  EyeOff,
  KeyRound,
  Loader2,
  Lock,
  ShieldCheck,
  X,
} from 'lucide-react';
import { AdminApiError, changeAdminPassword } from '../api/client';
import { PASSWORD_MAX_BYTES, PASSWORD_MIN_LENGTH } from '../types/config';
import { validatePasswordChange } from '../utils/password';
import type { AdminSession } from '../utils/storage';

interface ChangePasswordModalProps {
  open: boolean;
  session: AdminSession;
  onClose: () => void;
  onSuccess: (username: string) => void;
}

export function ChangePasswordModal({
  open,
  session,
  onClose,
  onSuccess,
}: ChangePasswordModalProps) {
  const [currentPassword, setCurrentPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');

  const [showCurrent, setShowCurrent] = useState(false);
  const [showNew, setShowNew] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);

  const [submitting, setSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [errorStatus, setErrorStatus] = useState<number | null>(null);

  useEffect(() => {
    if (!open) {
      setCurrentPassword('');
      setNewPassword('');
      setConfirmPassword('');
      setShowCurrent(false);
      setShowNew(false);
      setShowConfirm(false);
      setErrorMessage(null);
      setErrorStatus(null);
      return;
    }

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape' && !submitting) {
        onClose();
      }
    }

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [open, submitting, onClose]);

  if (!open) {
    return null;
  }

  const validation = validatePasswordChange(currentPassword, newPassword, confirmPassword);

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
      onSuccess(result.username || session.username);
    } catch (error) {
      if (error instanceof AdminApiError) {
        setErrorMessage(error.message);
        setErrorStatus(error.status || null);
      } else {
        setErrorMessage('修改密码失败，请稍后重试');
        setErrorStatus(null);
      }
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="change-password-modal-title"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 p-4 backdrop-blur-sm"
      onClick={(e) => {
        if (e.target === e.currentTarget && !submitting) {
          onClose();
        }
      }}
    >
      <div className="gold-card animate-modal-in w-full max-w-md rounded-2xl p-6">
        {/* Header */}
        <div className="flex items-start justify-between gap-3">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-xl border border-[#F2C512]/35 bg-[#F2C512]/10">
              <KeyRound className="h-5 w-5 text-[#F2C512]" />
            </div>
            <div>
              <h2
                id="change-password-modal-title"
                className="text-base font-semibold text-[#F8F5EE]"
              >
                修改管理员密码
              </h2>
              <p className="mt-0.5 text-xs text-[#9A9387]">
                当前账号：<span className="font-mono text-[#FFE066]">{session.username}</span>
              </p>
            </div>
          </div>

          <button
            type="button"
            onClick={onClose}
            disabled={submitting}
            aria-label="关闭修改密码弹窗"
            className="cursor-pointer rounded-lg p-1.5 text-[#8A8377] transition hover:bg-white/5 hover:text-[#F5F2EB] disabled:opacity-40"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {/* Security Note */}
        <div className="mt-4 flex items-start gap-2.5 rounded-xl border border-[#F2C512]/20 bg-[#141416]/85 px-3.5 py-2.5 text-xs leading-relaxed text-[#BEB7AA]">
          <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-[#F2C512]" />
          <p>
            新密码将加密持久化保存至数据库。修改成功后，当前登录会话保持有效，其他设备或标签页的旧会话将自动注销。
          </p>
        </div>

        <form onSubmit={handleSubmit} className="mt-5 space-y-4">
          {/* Current Password */}
          <div>
            <label
              htmlFor="modal-current-password"
              className="mb-1.5 flex items-center gap-1.5 text-xs font-medium text-[#CBC4B7]"
            >
              <Lock className="h-3.5 w-3.5 text-[#F2C512]" />
              当前密码
            </label>
            <div className="relative">
              <input
                id="modal-current-password"
                type={showCurrent ? 'text' : 'password'}
                autoComplete="current-password"
                autoFocus
                value={currentPassword}
                onChange={(e) => setCurrentPassword(e.target.value)}
                placeholder="请输入当前正在使用的密码"
                disabled={submitting}
                className="w-full rounded-xl border border-white/10 bg-[#141416] py-2.5 pl-4 pr-11 text-sm text-[#F5F2EB] placeholder:text-[#655F56] transition focus:border-[#F2C512]/60 focus:outline-none focus:ring-2 focus:ring-[#F2C512]/20 disabled:opacity-60"
              />
              <button
                type="button"
                onClick={() => setShowCurrent((prev) => !prev)}
                aria-label={showCurrent ? '隐藏当前密码' : '显示当前密码'}
                className="absolute right-2.5 top-1/2 -translate-y-1/2 cursor-pointer rounded-lg p-1.5 text-[#8A8377] transition hover:bg-white/5 hover:text-[#F2C512]"
              >
                {showCurrent ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
              </button>
            </div>
          </div>

          {/* New Password */}
          <div>
            <label
              htmlFor="modal-new-password"
              className="mb-1.5 flex items-center justify-between text-xs font-medium text-[#CBC4B7]"
            >
              <span className="flex items-center gap-1.5">
                <KeyRound className="h-3.5 w-3.5 text-[#F2C512]" />
                新密码
              </span>
              <span className={`text-[11px] font-medium ${validation.strength.textClass}`}>
                {validation.strength.label} · {newPassword.length} 位
              </span>
            </label>
            <div className="relative">
              <input
                id="modal-new-password"
                type={showNew ? 'text' : 'password'}
                autoComplete="new-password"
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
                placeholder={`请输入至少 ${PASSWORD_MIN_LENGTH} 位新密码`}
                disabled={submitting}
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

            <div className="mt-2 grid grid-cols-4 gap-1.5" aria-hidden="true">
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

            <div className="mt-2 space-y-1 text-[11px]">
              <ModalRuleRow
                passed={validation.lengthOk && validation.maxBytesOk}
                active={newPassword.length > 0}
                label={`至少 ${PASSWORD_MIN_LENGTH} 位且 ≤ ${PASSWORD_MAX_BYTES} 字节（当前 ${newPassword.length} 位 / ${validation.byteLength} 字节）`}
              />
              <ModalRuleRow
                passed={validation.differentFromCurrent}
                active={newPassword.length > 0 && currentPassword.length > 0}
                label="不能与当前密码相同"
              />
            </div>
          </div>

          {/* Confirm Password */}
          <div>
            <label
              htmlFor="modal-confirm-password"
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
                id="modal-confirm-password"
                type={showConfirm ? 'text' : 'password'}
                autoComplete="new-password"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                placeholder="请再次输入新密码"
                disabled={submitting}
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
                    ? '当前密码错误或会话失效（HTTP 401）'
                    : errorStatus === 422
                      ? '密码校验未通过（HTTP 422）'
                      : '修改密码失败'}
                </p>
                <p className="mt-0.5 text-[#F4A9A9]/90">{errorMessage}</p>
              </div>
            </div>
          ) : null}

          {/* Actions */}
          <div className="flex items-center justify-end gap-3 pt-1">
            <button
              type="button"
              onClick={onClose}
              disabled={submitting}
              className="cursor-pointer rounded-xl border border-white/10 bg-[#141416] px-4 py-2.5 text-sm font-medium text-[#CBC4B7] transition hover:border-white/20 hover:text-[#F5F2EB] disabled:opacity-50"
            >
              取消
            </button>
            <button
              type="submit"
              disabled={submitting || !validation.canSubmit}
              className="gold-btn inline-flex cursor-pointer items-center gap-2 rounded-xl px-5 py-2.5 text-sm font-semibold transition disabled:cursor-not-allowed disabled:opacity-50"
            >
              {submitting ? (
                <>
                  <Loader2 className="h-4 w-4 animate-spin" />
                  保存中...
                </>
              ) : (
                <>
                  <CheckCircle2 className="h-4 w-4" />
                  确认修改密码
                </>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

function ModalRuleRow({
  passed,
  active,
  label,
}: {
  passed: boolean;
  active: boolean;
  label: string;
}) {
  return (
    <div className="flex items-center gap-1.5">
      <span
        className={`flex h-3.5 w-3.5 shrink-0 items-center justify-center rounded-full ${
          passed
            ? 'bg-[#3DD68C]/20 text-[#5AE2A0]'
            : active
              ? 'bg-[#FF5D5D]/15 text-[#FF8585]'
              : 'bg-white/8 text-[#7D776D]'
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

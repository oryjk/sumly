import { useState } from 'react';
import {
  AlertTriangle,
  ArrowRight,
  CheckCircle2,
  Clock,
  Crown,
  Loader2,
  Lock,
  Megaphone,
  RotateCcw,
  Save,
  ShieldAlert,
  Sparkles,
  Unlock,
  User,
  X,
} from 'lucide-react';
import {
  arePaywallConfigsEqual,
  FREE_ACCESS_NOTICE_MAX_LENGTH,
  type MembershipPaywallConfig,
} from '../types/config';
import { formatBeijingTime, formatRelativeTime } from '../utils/format';
import { ToggleSwitch } from './ToggleSwitch';

interface PaywallControlCardProps {
  liveConfig: MembershipPaywallConfig;
  draftConfig: MembershipPaywallConfig;
  onDraftChange: (next: MembershipPaywallConfig) => void;
  note: string;
  onNoteChange: (note: string) => void;
  updatedBy: string;
  updatedAt: string;
  usingFallbackDefault: boolean;
  saving: boolean;
  onSave: () => Promise<boolean>;
  onReset: () => void;
}

const NOTICE_PRESETS = ['限时免费', '限时免费体验中', '回馈用户 · 限时免费开放'];
const NOTE_PRESETS = ['限时免费测试', '恢复正式收费', '调整免费公告文案', '临时隐藏新客会员入口'];

export function PaywallControlCard({
  liveConfig,
  draftConfig,
  onDraftChange,
  note,
  onNoteChange,
  updatedBy,
  updatedAt,
  usingFallbackDefault,
  saving,
  onSave,
  onReset,
}: PaywallControlCardProps) {
  const [showConfirmModal, setShowConfirmModal] = useState(false);

  const isDirty = !arePaywallConfigsEqual(liveConfig, draftConfig);
  const paywallModeChanged =
    liveConfig.chanlun_requires_membership !== draftConfig.chanlun_requires_membership;
  const entryVisibilityChanged =
    liveConfig.membership_entry_visible !== draftConfig.membership_entry_visible;
  const noticeChanged =
    liveConfig.free_access_notice.trim() !== draftConfig.free_access_notice.trim();

  const noticeLength = draftConfig.free_access_notice.length;
  const noticeTooLong = noticeLength > FREE_ACCESS_NOTICE_MAX_LENGTH;
  const canSave = isDirty && !saving && !noticeTooLong;

  const isLivePaid = liveConfig.chanlun_requires_membership;

  async function handlePrimarySaveClick() {
    if (!canSave) {
      return;
    }
    if (paywallModeChanged) {
      setShowConfirmModal(true);
      return;
    }
    await onSave();
  }

  async function handleConfirmedSave() {
    const ok = await onSave();
    if (ok) {
      setShowConfirmModal(false);
    }
  }

  return (
    <>
      <section className="gold-card overflow-hidden rounded-2xl">
        {/* Live Status Hero Banner */}
        <div
          className={`relative overflow-hidden border-b px-5 py-5 sm:px-7 sm:py-6 ${
            isLivePaid
              ? 'border-[#FF5D5D]/25 bg-gradient-to-r from-[#2D1A1A] via-[#261D19] to-[#231F18]'
              : 'border-[#3DD68C]/25 bg-gradient-to-r from-[#162920] via-[#18251E] to-[#1C211D]'
          }`}
        >
          <div
            aria-hidden="true"
            className={`pointer-events-none absolute -right-12 -top-12 h-44 w-44 rounded-full blur-3xl ${
              isLivePaid ? 'bg-[#FF5D5D]/18' : 'bg-[#3DD68C]/18'
            }`}
          />

          <div className="relative flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
            <div className="flex items-start gap-3.5">
              <div
                className={`flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl border ${
                  isLivePaid
                    ? 'border-[#FF5D5D]/40 bg-[#FF5D5D]/15 text-[#FF7B7B]'
                    : 'border-[#3DD68C]/40 bg-[#3DD68C]/15 text-[#3DD68C]'
                }`}
              >
                {isLivePaid ? <Lock className="h-6 w-6" /> : <Unlock className="h-6 w-6" />}
              </div>
              <div>
                <div className="flex flex-wrap items-center gap-2">
                  <span
                    className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-[11px] font-semibold tracking-wide ${
                      isLivePaid
                        ? 'border-[#FF5D5D]/40 bg-[#FF5D5D]/15 text-[#FF8C8C]'
                        : 'border-[#3DD68C]/40 bg-[#3DD68C]/15 text-[#5AE2A0]'
                    }`}
                  >
                    <span
                      className={`h-1.5 w-1.5 rounded-full ${
                        isLivePaid ? 'bg-[#FF5D5D]' : 'bg-[#3DD68C] animate-pulse'
                      }`}
                    />
                    线上实时生效态
                  </span>
                  {usingFallbackDefault ? (
                    <span className="rounded-full border border-[#F2C512]/30 bg-[#F2C512]/10 px-2 py-0.5 text-[11px] text-[#F2C512]">
                      安全默认兜底
                    </span>
                  ) : null}
                  {isDirty ? (
                    <span className="rounded-full border border-[#F2C512]/45 bg-[#F2C512]/18 px-2.5 py-0.5 text-[11px] font-medium text-[#FFE066]">
                      有未保存修改
                    </span>
                  ) : null}
                </div>

                <h2 className="mt-2 text-lg font-semibold tracking-tight text-[#F8F5EE] sm:text-xl">
                  {isLivePaid
                    ? '当前收费中 · 需订阅会员解锁'
                    : '当前免费开放中 · 无需订阅直开'}
                </h2>
                <p className="mt-1 text-xs text-[#B6AFA3]">
                  配置键 <code className="font-mono text-[#F2C512]">membership_paywall</code> ·
                  客户端在前台激活与冷启动时自动拉取最新策略
                </p>
              </div>
            </div>

            <div className="flex flex-wrap items-center gap-x-4 gap-y-1.5 rounded-xl border border-white/8 bg-[#141416]/65 px-3.5 py-2.5 text-xs text-[#A9A296] sm:flex-col sm:items-end sm:gap-1">
              <span className="flex items-center gap-1.5 font-mono text-[11px] text-[#D8D1C5]">
                <Clock className="h-3.5 w-3.5 text-[#F2C512]/80" />
                {formatBeijingTime(updatedAt)}
                {updatedAt ? (
                  <span className="font-sans text-[#857E73]">
                    （{formatRelativeTime(updatedAt)}）
                  </span>
                ) : null}
              </span>
              <span className="flex items-center gap-1.5 text-[11px] text-[#9A9387]">
                <User className="h-3.5 w-3.5 text-[#8A8377]" />
                最近操作人：<span className="text-[#E3DDD2]">{updatedBy || '系统默认'}</span>
              </span>
            </div>
          </div>
        </div>

        {/* Controls Body */}
        <div className="space-y-5 p-5 sm:p-7">
          {/* Switch 1: Chanlun Requires Membership */}
          <div
            className={`rounded-2xl border p-4 transition sm:p-5 ${
              draftConfig.chanlun_requires_membership
                ? 'border-[#F2C512]/25 bg-[#191815]'
                : 'border-[#3DD68C]/28 bg-[#161E19]'
            }`}
          >
            <div className="flex items-start justify-between gap-4">
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-center gap-2">
                  <Crown
                    className={`h-4 w-4 shrink-0 ${
                      draftConfig.chanlun_requires_membership
                        ? 'text-[#F2C512]'
                        : 'text-[#3DD68C]'
                    }`}
                  />
                  <label
                    htmlFor="switch-chanlun-paywall"
                    className="cursor-pointer text-base font-semibold text-[#F5F2EB]"
                  >
                    禅观需要会员订阅
                  </label>
                  <span
                    className={`rounded-md px-2 py-0.5 text-[11px] font-medium ${
                      draftConfig.chanlun_requires_membership
                        ? 'bg-[#FF5D5D]/15 text-[#FF8B8B]'
                        : 'bg-[#3DD68C]/15 text-[#4CE099]'
                    }`}
                  >
                    {draftConfig.chanlun_requires_membership ? '开启 · 收费拦截' : '关闭 · 免费直开'}
                  </span>
                </div>

                <p className="mt-2 text-xs leading-relaxed text-[#A7A094]">
                  {draftConfig.chanlun_requires_membership ? (
                    <>
                      <strong className="font-medium text-[#E8E2D6]">开启效果：</strong>
                      未订阅用户点击「禅观」时弹出记金会员订阅页（¥99/年 · ¥39/月），首页顶部胶囊显示金色皇冠锁标，订阅后自动进入禅观。
                    </>
                  ) : (
                    <>
                      <strong className="font-medium text-[#5AE2A0]">关闭效果：</strong>
                      全量用户点击「禅观」直接放行进入，首页皇冠锁标与「我的」页会员专属标自动隐藏，无需订阅即可免费体验。
                    </>
                  )}
                </p>
              </div>

              <ToggleSwitch
                id="switch-chanlun-paywall"
                checked={draftConfig.chanlun_requires_membership}
                onChange={(checked) =>
                  onDraftChange({ ...draftConfig, chanlun_requires_membership: checked })
                }
                disabled={saving}
                tone="gold"
                ariaLabel="切换禅观是否需要会员订阅"
              />
            </div>
          </div>

          {/* Switch 2: Membership Entry Visible */}
          <div className="rounded-2xl border border-white/8 bg-[#181715] p-4 transition hover:border-white/12 sm:p-5">
            <div className="flex items-start justify-between gap-4">
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-center gap-2">
                  <Sparkles className="h-4 w-4 shrink-0 text-[#F2C512]/85" />
                  <label
                    htmlFor="switch-membership-entry"
                    className="cursor-pointer text-base font-semibold text-[#F5F2EB]"
                  >
                    「我的」页显示记金会员入口
                  </label>
                  <span
                    className={`rounded-md px-2 py-0.5 text-[11px] font-medium ${
                      draftConfig.membership_entry_visible
                        ? 'bg-[#F2C512]/15 text-[#F2C512]'
                        : 'bg-white/8 text-[#ABA498]'
                    }`}
                  >
                    {draftConfig.membership_entry_visible ? '显示入口' : '隐藏新客入口'}
                  </span>
                </div>

                <p className="mt-2 text-xs leading-relaxed text-[#A7A094]">
                  控制「我的」页面是否向未订阅用户展示「记金会员」开通入口。
                  <span className="text-[#D8D1C4]">
                    已购有效会员始终保留入口查看有效期与管理订阅
                  </span>
                  ，确保完全符合 Apple App Store 订阅合规要求。
                </p>
              </div>

              <ToggleSwitch
                id="switch-membership-entry"
                checked={draftConfig.membership_entry_visible}
                onChange={(checked) =>
                  onDraftChange({ ...draftConfig, membership_entry_visible: checked })
                }
                disabled={saving}
                tone="gold"
                ariaLabel="切换我的页面是否显示记金会员入口"
              />
            </div>
          </div>

          {/* Free Access Notice Input */}
          <div className="rounded-2xl border border-white/8 bg-[#181715] p-4 sm:p-5">
            <div className="mb-2.5 flex items-center justify-between gap-2">
              <label
                htmlFor="free-access-notice-input"
                className="flex items-center gap-2 text-sm font-semibold text-[#F5F2EB]"
              >
                <Megaphone className="h-4 w-4 text-[#F2C512]/85" />
                限时免费公告文案
                <span className="text-xs font-normal text-[#8B8478]">（可选，最多 120 字）</span>
              </label>
              <span
                className={`font-mono text-xs tabular-nums ${
                  noticeTooLong
                    ? 'font-semibold text-[#FF5D5D]'
                    : noticeLength > 100
                      ? 'text-[#F2C512]'
                      : 'text-[#8B8478]'
                }`}
              >
                {noticeLength} / {FREE_ACCESS_NOTICE_MAX_LENGTH}
              </span>
            </div>

            <textarea
              id="free-access-notice-input"
              rows={2}
              maxLength={FREE_ACCESS_NOTICE_MAX_LENGTH + 20}
              value={draftConfig.free_access_notice}
              onChange={(e) =>
                onDraftChange({ ...draftConfig, free_access_notice: e.target.value })
              }
              disabled={saving}
              placeholder="例如：限时免费 / 限时免费体验中（关闭收费后在 App 禅观入口展示暗金胶囊）"
              className={`w-full resize-none rounded-xl border bg-[#141416] px-3.5 py-2.5 text-sm text-[#F5F2EB] placeholder:text-[#655F56] transition focus:outline-none focus:ring-2 ${
                noticeTooLong
                  ? 'border-[#FF5D5D]/60 focus:border-[#FF5D5D] focus:ring-[#FF5D5D]/20'
                  : 'border-white/10 focus:border-[#F2C512]/60 focus:ring-[#F2C512]/20'
              }`}
            />

            <div className="mt-2.5 flex flex-wrap items-center gap-1.5">
              <span className="mr-1 text-[11px] text-[#7D776D]">快捷填入：</span>
              {NOTICE_PRESETS.map((preset) => (
                <button
                  key={preset}
                  type="button"
                  disabled={saving}
                  onClick={() => onDraftChange({ ...draftConfig, free_access_notice: preset })}
                  className="cursor-pointer rounded-lg border border-white/8 bg-[#1E1D1B] px-2.5 py-1 text-[11px] text-[#CBC4B7] transition hover:border-[#F2C512]/40 hover:text-[#F2C512]"
                >
                  {preset}
                </button>
              ))}
              {draftConfig.free_access_notice ? (
                <button
                  type="button"
                  disabled={saving}
                  onClick={() => onDraftChange({ ...draftConfig, free_access_notice: '' })}
                  className="cursor-pointer rounded-lg border border-white/6 px-2.5 py-1 text-[11px] text-[#968F83] transition hover:border-[#FF5D5D]/35 hover:text-[#FF8B8B]"
                >
                  清空
                </button>
              ) : null}
            </div>
          </div>

          {/* Pending Diff Inline Preview */}
          {isDirty ? (
            <div className="rounded-xl border border-[#F2C512]/30 bg-[#F2C512]/8 px-4 py-3">
              <div className="flex items-center gap-2 text-xs font-semibold text-[#FFE066]">
                <AlertTriangle className="h-4 w-4 shrink-0 text-[#F2C512]" />
                待发布变更摘要
              </div>
              <ul className="mt-2 space-y-1.5 text-xs text-[#DFD8CB]">
                {paywallModeChanged ? (
                  <li className="flex flex-wrap items-center gap-1.5">
                    <span className="text-[#A39C90]">禅观收费门禁：</span>
                    <span className="rounded bg-white/8 px-1.5 py-0.5 font-medium">
                      {liveConfig.chanlun_requires_membership ? '收费中' : '免费开放'}
                    </span>
                    <ArrowRight className="h-3.5 w-3.5 text-[#F2C512]" />
                    <span
                      className={`rounded px-1.5 py-0.5 font-semibold ${
                        draftConfig.chanlun_requires_membership
                          ? 'bg-[#FF5D5D]/20 text-[#FF8E8E]'
                          : 'bg-[#3DD68C]/20 text-[#5AE2A0]'
                      }`}
                    >
                      {draftConfig.chanlun_requires_membership ? '恢复收费' : '切换为免费开放'}
                    </span>
                  </li>
                ) : null}
                {entryVisibilityChanged ? (
                  <li className="flex flex-wrap items-center gap-1.5">
                    <span className="text-[#A39C90]">会员入口展示：</span>
                    <span className="rounded bg-white/8 px-1.5 py-0.5">
                      {liveConfig.membership_entry_visible ? '显示' : '隐藏'}
                    </span>
                    <ArrowRight className="h-3.5 w-3.5 text-[#F2C512]" />
                    <span className="rounded bg-[#F2C512]/20 px-1.5 py-0.5 font-semibold text-[#FFE066]">
                      {draftConfig.membership_entry_visible ? '显示' : '隐藏'}
                    </span>
                  </li>
                ) : null}
                {noticeChanged ? (
                  <li className="flex flex-wrap items-center gap-1.5">
                    <span className="text-[#A39C90]">免费公告文案：</span>
                    <span className="truncate text-[#F2C512]">
                      {draftConfig.free_access_notice.trim()
                        ? `「${draftConfig.free_access_notice.trim()}」`
                        : '（清空公告）'}
                    </span>
                  </li>
                ) : null}
              </ul>
            </div>
          ) : null}

          {/* Change Note + Action Footer */}
          <div className="border-t border-white/8 pt-5">
            <label
              htmlFor="change-note-input"
              className="mb-2 block text-xs font-medium text-[#CBC4B7]"
            >
              变更备注（记录至审计日志，便于团队回溯）
            </label>
            <input
              id="change-note-input"
              type="text"
              maxLength={120}
              value={note}
              onChange={(e) => onNoteChange(e.target.value)}
              disabled={saving}
              placeholder="例如：限时免费测试 / 恢复正式收费 / 审核期间隐藏新客入口"
              className="w-full rounded-xl border border-white/10 bg-[#141416] px-3.5 py-2.5 text-sm text-[#F5F2EB] placeholder:text-[#655F56] transition focus:border-[#F2C512]/60 focus:outline-none focus:ring-2 focus:ring-[#F2C512]/20"
            />

            <div className="mt-2 flex flex-wrap gap-1.5">
              {NOTE_PRESETS.map((preset) => (
                <button
                  key={preset}
                  type="button"
                  disabled={saving}
                  onClick={() => onNoteChange(preset)}
                  className="cursor-pointer rounded-md border border-white/6 bg-white/[0.03] px-2 py-0.5 text-[11px] text-[#9E978B] transition hover:border-[#F2C512]/35 hover:text-[#F2C512]"
                >
                  + {preset}
                </button>
              ))}
            </div>

            <div className="mt-5 flex flex-col-reverse gap-3 sm:flex-row sm:items-center sm:justify-between">
              <button
                type="button"
                onClick={onReset}
                disabled={!isDirty || saving}
                className="inline-flex cursor-pointer items-center justify-center gap-2 rounded-xl border border-white/10 bg-[#141416] px-4 py-2.5 text-sm font-medium text-[#CBC4B7] transition hover:border-white/20 hover:text-[#F5F2EB] disabled:cursor-not-allowed disabled:opacity-40"
              >
                <RotateCcw className="h-4 w-4" />
                还原修改
              </button>

              <button
                type="button"
                onClick={handlePrimarySaveClick}
                disabled={!canSave}
                className={`inline-flex items-center justify-center gap-2 rounded-xl px-6 py-3 text-sm font-semibold transition ${
                  canSave
                    ? 'gold-btn cursor-pointer'
                    : 'cursor-not-allowed border border-white/8 bg-white/5 text-[#756F65]'
                }`}
              >
                {saving ? (
                  <>
                    <Loader2 className="h-4 w-4 animate-spin" />
                    正在保存并生效...
                  </>
                ) : (
                  <>
                    <Save className="h-4 w-4" />
                    保存并立即生效
                  </>
                )}
              </button>
            </div>
          </div>
        </div>
      </section>

      {/* Paywall State Change Confirmation Modal */}
      {showConfirmModal ? (
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="confirm-paywall-title"
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 p-4 backdrop-blur-sm"
        >
          <div className="animate-modal-in gold-card w-full max-w-md rounded-2xl p-6">
            <div className="flex items-start justify-between gap-3">
              <div className="flex items-center gap-3">
                <div
                  className={`flex h-10 w-10 items-center justify-center rounded-xl border ${
                    draftConfig.chanlun_requires_membership
                      ? 'border-[#FF5D5D]/35 bg-[#FF5D5D]/15 text-[#FF7B7B]'
                      : 'border-[#3DD68C]/35 bg-[#3DD68C]/15 text-[#3DD68C]'
                  }`}
                >
                  <ShieldAlert className="h-5 w-5" />
                </div>
                <div>
                  <h3 id="confirm-paywall-title" className="text-base font-semibold text-[#F5F2EB]">
                    确认切换禅观付费状态
                  </h3>
                  <p className="text-xs text-[#9D968A]">保存后将立即对线上全量客户端生效</p>
                </div>
              </div>

              <button
                type="button"
                onClick={() => setShowConfirmModal(false)}
                disabled={saving}
                aria-label="关闭确认弹窗"
                className="rounded-lg p-1.5 text-[#8A8377] transition hover:bg-white/5 hover:text-[#F5F2EB]"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            <div className="mt-5 space-y-3 rounded-xl border border-white/8 bg-[#141416] p-4 text-xs">
              <div className="flex items-center justify-between">
                <span className="text-[#9A9387]">禅观付费门禁</span>
                <span className="flex items-center gap-2 font-semibold">
                  <span className="text-[#B8B1A5]">
                    {liveConfig.chanlun_requires_membership ? '收费中' : '免费开放'}
                  </span>
                  <ArrowRight className="h-3.5 w-3.5 text-[#F2C512]" />
                  <span
                    className={
                      draftConfig.chanlun_requires_membership
                        ? 'text-[#FF7B7B]'
                        : 'text-[#3DD68C]'
                    }
                  >
                    {draftConfig.chanlun_requires_membership
                      ? '开启收费（需订阅解锁）'
                      : '免费开放（无需订阅直开）'}
                  </span>
                </span>
              </div>

              <div className="flex items-center justify-between border-t border-white/6 pt-2.5">
                <span className="text-[#9A9387]">「我的」会员入口</span>
                <span className="font-medium text-[#E8E2D6]">
                  {draftConfig.membership_entry_visible ? '显示入口' : '隐藏新客入口（老会员保留）'}
                </span>
              </div>

              {draftConfig.free_access_notice.trim() ? (
                <div className="flex items-start justify-between gap-4 border-t border-white/6 pt-2.5">
                  <span className="shrink-0 text-[#9A9387]">免费公告文案</span>
                  <span className="text-right text-[#F2C512]">
                    {draftConfig.free_access_notice.trim()}
                  </span>
                </div>
              ) : null}

              <div className="flex items-start justify-between gap-4 border-t border-white/6 pt-2.5">
                <span className="shrink-0 text-[#9A9387]">变更备注</span>
                <span className="text-right text-[#D8D2C6]">
                  {note.trim() || '（未填写备注）'}
                </span>
              </div>
            </div>

            <div className="mt-5 flex items-center justify-end gap-3">
              <button
                type="button"
                onClick={() => setShowConfirmModal(false)}
                disabled={saving}
                className="cursor-pointer rounded-xl border border-white/10 bg-[#141416] px-4 py-2.5 text-sm font-medium text-[#CBC4B7] transition hover:border-white/20 hover:text-[#F5F2EB]"
              >
                再检查一下
              </button>
              <button
                type="button"
                onClick={handleConfirmedSave}
                disabled={saving}
                className="gold-btn inline-flex cursor-pointer items-center gap-2 rounded-xl px-5 py-2.5 text-sm font-semibold transition disabled:opacity-60"
              >
                {saving ? (
                  <>
                    <Loader2 className="h-4 w-4 animate-spin" />
                    提交中...
                  </>
                ) : (
                  <>
                    <CheckCircle2 className="h-4 w-4" />
                    确认并立即生效
                  </>
                )}
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </>
  );
}

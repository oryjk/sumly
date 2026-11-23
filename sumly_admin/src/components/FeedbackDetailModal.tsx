import { useEffect, useMemo, useState, type FormEvent } from 'react';
import {
  AlertCircle,
  Check,
  ChevronLeft,
  ChevronRight,
  Clock,
  Cloud,
  CloudOff,
  Copy,
  ExternalLink,
  Globe,
  Hash,
  Image as ImageIcon,
  Loader2,
  Lock,
  Mail,
  MessageSquareReply,
  RotateCcw,
  Save,
  Smartphone,
  StickyNote,
  User,
  UserX,
  X,
  ZoomIn,
} from 'lucide-react';
import { AdminApiError, updateAdminFeedback } from '../api/client';
import {
  FEEDBACK_STATUS_OPTIONS,
  formatAppVersionLabel,
  formatMarketMode,
  getFeedbackCategoryMeta,
  getFeedbackStatusMeta,
  resolveFeedbackAttachmentUrl,
  type AdminFeedbackItem,
  type FeedbackStatus,
} from '../types/feedback';
import { formatBeijingTime, formatRelativeTime } from '../utils/format';
import type { ToastType } from './Toast';

interface FeedbackDetailModalProps {
  feedback: AdminFeedbackItem | null;
  apiBase: string;
  token: string;
  onClose: () => void;
  onSaved: (updated: AdminFeedbackItem) => void;
  onToast: (type: ToastType, title: string, description?: string) => void;
  onUnauthorized: (message?: string) => void;
  onMustChangePassword: (message?: string) => void;
}

const REPLY_MAX_LENGTH = 1000;
const NOTE_MAX_LENGTH = 1000;

const QUICK_REPLIES = [
  '感谢您的宝贵建议！我们已记录需求，将在后续版本迭代中评估优化。',
  '感谢反馈！该问题已定位排查，预计将在下个版本修复，届时请留意更新。',
  '您好，我们已核对相关数据并完成处理。如仍有异常欢迎随时补充截图反馈。',
];

async function copyTextToClipboard(text: string): Promise<boolean> {
  try {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
      return true;
    }
  } catch {
    // Fallback to textarea copy below.
  }

  try {
    const textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.style.position = 'fixed';
    textarea.style.left = '-9999px';
    textarea.style.opacity = '0';
    document.body.appendChild(textarea);
    textarea.focus();
    textarea.select();
    const ok = document.execCommand('copy');
    document.body.removeChild(textarea);
    return ok;
  } catch {
    return false;
  }
}

export function FeedbackDetailModal({
  feedback,
  apiBase,
  token,
  onClose,
  onSaved,
  onToast,
  onUnauthorized,
  onMustChangePassword,
}: FeedbackDetailModalProps) {
  const [status, setStatus] = useState<FeedbackStatus>('new');
  const [adminReply, setAdminReply] = useState('');
  const [adminNote, setAdminNote] = useState('');
  const [saving, setSaving] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const [copiedKey, setCopiedKey] = useState<'contact' | 'device' | null>(null);
  const [lightboxIndex, setLightboxIndex] = useState<number | null>(null);
  const [brokenImages, setBrokenImages] = useState<Record<number, boolean>>({});

  useEffect(() => {
    if (!feedback) {
      setLightboxIndex(null);
      setErrorMessage(null);
      setCopiedKey(null);
      setBrokenImages({});
      return;
    }
    setStatus(feedback.status);
    setAdminReply(feedback.admin_reply);
    setAdminNote(feedback.admin_note);
    setErrorMessage(null);
    setLightboxIndex(null);
    setCopiedKey(null);
    setBrokenImages({});
  }, [feedback]);

  const resolvedAttachments = useMemo(() => {
    if (!feedback) {
      return [];
    }
    return feedback.attachments
      .map((item, idx) => ({
        key: item.object_key || `att-${idx}`,
        objectKey: item.object_key,
        url: resolveFeedbackAttachmentUrl(apiBase, item.url),
      }))
      .filter((item) => Boolean(item.url));
  }, [feedback, apiBase]);

  // Keyboard handling: ESC closes lightbox first, then modal; arrows navigate lightbox
  useEffect(() => {
    if (!feedback) {
      return;
    }

    function handleKeyDown(event: KeyboardEvent) {
      if (lightboxIndex !== null) {
        if (event.key === 'Escape') {
          event.preventDefault();
          setLightboxIndex(null);
          return;
        }
        if (event.key === 'ArrowLeft' && resolvedAttachments.length > 1) {
          event.preventDefault();
          setLightboxIndex((prev) =>
            prev === null
              ? null
              : (prev - 1 + resolvedAttachments.length) % resolvedAttachments.length,
          );
          return;
        }
        if (event.key === 'ArrowRight' && resolvedAttachments.length > 1) {
          event.preventDefault();
          setLightboxIndex((prev) =>
            prev === null ? null : (prev + 1) % resolvedAttachments.length,
          );
          return;
        }
        return;
      }

      if (event.key === 'Escape' && !saving) {
        event.preventDefault();
        onClose();
      }
    }

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [feedback, lightboxIndex, resolvedAttachments.length, saving, onClose]);

  // Lock body scroll while modal is open
  useEffect(() => {
    if (!feedback) {
      return;
    }
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      document.body.style.overflow = previousOverflow;
    };
  }, [feedback]);

  if (!feedback) {
    return null;
  }

  const categoryMeta = getFeedbackCategoryMeta(feedback.category);
  const currentStatusMeta = getFeedbackStatusMeta(feedback.status);
  const isDirty =
    status !== feedback.status ||
    adminReply.trim() !== feedback.admin_reply.trim() ||
    adminNote.trim() !== feedback.admin_note.trim();

  const replyTooLong = adminReply.length > REPLY_MAX_LENGTH;
  const noteTooLong = adminNote.length > NOTE_MAX_LENGTH;
  const canSubmit = isDirty && !saving && !replyTooLong && !noteTooLong;

  async function handleCopy(target: 'contact' | 'device', value: string, label: string) {
    if (!value.trim()) {
      return;
    }
    const ok = await copyTextToClipboard(value.trim());
    if (ok) {
      setCopiedKey(target);
      onToast('success', `已复制${label}`, value.trim());
      window.setTimeout(() => {
        setCopiedKey((current) => (current === target ? null : current));
      }, 2000);
    } else {
      onToast('error', `复制${label}失败`, '请手动选中后复制');
    }
  }

  function handleReset() {
    if (!feedback) {
      return;
    }
    setStatus(feedback.status);
    setAdminReply(feedback.admin_reply);
    setAdminNote(feedback.admin_note);
    setErrorMessage(null);
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!feedback || !canSubmit) {
      return;
    }

    setSaving(true);
    setErrorMessage(null);

    try {
      const updated = await updateAdminFeedback(apiBase, token, feedback.id, {
        status,
        admin_note: adminNote.trim(),
        admin_reply: adminReply.trim(),
      });

      const nextStatusLabel = getFeedbackStatusMeta(updated.status).label;
      const replySummary = updated.admin_reply.trim()
        ? '用户可在 App「我的反馈」中看到最新回复'
        : `当前状态已更新为「${nextStatusLabel}」`;

      onToast('success', `反馈 #${updated.id} 处理结果已保存`, replySummary);
      onSaved(updated);
    } catch (error) {
      if (error instanceof AdminApiError && error.isUnauthorized) {
        onUnauthorized(error.message);
        return;
      }
      if (error instanceof AdminApiError && error.isMustChangePassword) {
        onMustChangePassword(error.message);
        return;
      }
      const message = error instanceof Error ? error.message : '保存处理结果失败，请稍后重试';
      setErrorMessage(message);
      onToast('error', '保存反馈处理结果失败', message);
    } finally {
      setSaving(false);
    }
  }

  const activeLightboxItem =
    lightboxIndex !== null ? resolvedAttachments[lightboxIndex] ?? null : null;

  return (
    <>
      {/* Main Detail Drawer / Modal Backdrop */}
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="feedback-detail-title"
        className="fixed inset-0 z-40 flex items-stretch justify-end bg-black/75 backdrop-blur-sm sm:p-4"
        onClick={(e) => {
          if (e.target === e.currentTarget && !saving) {
            onClose();
          }
        }}
      >
        <div className="gold-card animate-modal-in flex h-full w-full max-w-3xl flex-col overflow-hidden sm:rounded-2xl">
          {/* Sticky Modal Header */}
          <div className="flex items-start justify-between gap-3 border-b border-white/8 bg-[#1A1917]/95 px-5 py-4 sm:px-6">
            <div className="min-w-0">
              <div className="flex flex-wrap items-center gap-2">
                <h2
                  id="feedback-detail-title"
                  className="font-mono text-base font-semibold text-[#F8F5EE]"
                >
                  反馈 #{feedback.id}
                </h2>
                <span
                  className={`inline-flex items-center rounded-full border px-2.5 py-0.5 text-[11px] font-medium ${categoryMeta.badgeClass}`}
                >
                  {categoryMeta.label}
                </span>
                <span
                  className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-[11px] font-medium ${currentStatusMeta.badgeClass}`}
                >
                  <span className={`h-1.5 w-1.5 rounded-full ${currentStatusMeta.dotClass}`} />
                  {currentStatusMeta.label}
                </span>
                {feedback.admin_reply.trim() ? (
                  <span className="inline-flex items-center gap-1 rounded-full border border-[#3DD68C]/30 bg-[#3DD68C]/10 px-2 py-0.5 text-[11px] font-medium text-[#5AE2A0]">
                    <MessageSquareReply className="h-3 w-3" />
                    已回复
                  </span>
                ) : null}
              </div>

              <div className="mt-1.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-[#9A9387]">
                <span className="inline-flex items-center gap-1 font-mono text-[11px] tabular-nums text-[#C8C1B4]">
                  <Clock className="h-3.5 w-3.5 text-[#F2C512]/80" />
                  提交于 {formatBeijingTime(feedback.created_at)}
                </span>
                {feedback.created_at ? (
                  <span className="text-[11px] text-[#837C71]">
                    （{formatRelativeTime(feedback.created_at)}）
                  </span>
                ) : null}
              </div>
            </div>

            <button
              type="button"
              onClick={onClose}
              disabled={saving}
              aria-label="关闭反馈详情"
              className="cursor-pointer rounded-xl border border-white/8 bg-[#141416] p-2 text-[#9B9488] transition hover:border-white/20 hover:text-[#F5F2EB] disabled:opacity-40"
            >
              <X className="h-4 w-4" />
            </button>
          </div>

          {/* Scrollable Body */}
          <form onSubmit={handleSubmit} className="flex min-h-0 flex-1 flex-col">
            <div className="flex-1 space-y-5 overflow-y-auto px-5 py-5 sm:px-6">
              {/* Full Feedback Content */}
              <section className="rounded-2xl border border-white/8 bg-[#151412] p-4 sm:p-5">
                <div className="mb-2.5 flex items-center justify-between gap-2">
                  <h3 className="text-xs font-semibold uppercase tracking-wider text-[#B6AFA3]">
                    反馈正文
                  </h3>
                  <span className="font-mono text-[11px] text-[#7D776D]">
                    {feedback.content.length} 字
                  </span>
                </div>
                <p className="whitespace-pre-wrap break-words text-sm leading-relaxed text-[#F5F2EB]">
                  {feedback.content || '（无正文内容）'}
                </p>

                {/* Contact Info Bar */}
                <div className="mt-4 flex flex-wrap items-center justify-between gap-2 rounded-xl border border-white/8 bg-[#1B1A18] px-3.5 py-2.5">
                  <div className="flex min-w-0 items-center gap-2 text-xs">
                    <Mail className="h-3.5 w-3.5 shrink-0 text-[#F2C512]" />
                    <span className="shrink-0 text-[#968F83]">联系方式：</span>
                    {feedback.contact.trim() ? (
                      <span className="truncate font-mono text-[#F5F2EB] select-all">
                        {feedback.contact.trim()}
                      </span>
                    ) : (
                      <span className="italic text-[#756F65]">用户未填写联系方式</span>
                    )}
                  </div>

                  {feedback.contact.trim() ? (
                    <button
                      type="button"
                      onClick={() =>
                        void handleCopy('contact', feedback.contact, '联系方式')
                      }
                      className="inline-flex shrink-0 cursor-pointer items-center gap-1 rounded-lg border border-[#F2C512]/30 bg-[#F2C512]/10 px-2.5 py-1 text-[11px] font-medium text-[#FFE066] transition hover:bg-[#F2C512]/18"
                    >
                      {copiedKey === 'contact' ? (
                        <>
                          <Check className="h-3 w-3 text-[#5AE2A0]" />
                          <span className="text-[#5AE2A0]">已复制</span>
                        </>
                      ) : (
                        <>
                          <Copy className="h-3 w-3" />
                          一键复制
                        </>
                      )}
                    </button>
                  ) : null}
                </div>
              </section>

              {/* Screenshot Gallery */}
              {resolvedAttachments.length > 0 ? (
                <section className="rounded-2xl border border-white/8 bg-[#151412] p-4 sm:p-5">
                  <div className="mb-3 flex items-center justify-between">
                    <h3 className="flex items-center gap-2 text-xs font-semibold uppercase tracking-wider text-[#B6AFA3]">
                      <ImageIcon className="h-3.5 w-3.5 text-[#F2C512]" />
                      附图画廊（{resolvedAttachments.length} 张）
                    </h3>
                    <span className="text-[11px] text-[#837C71]">点击缩略图放大预览</span>
                  </div>

                  <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
                    {resolvedAttachments.map((att, index) => {
                      const isBroken = Boolean(brokenImages[index]);
                      return (
                        <div
                          key={att.key}
                          className="group relative overflow-hidden rounded-xl border border-white/10 bg-[#101012]"
                        >
                          {isBroken ? (
                            <div className="flex aspect-[4/3] flex-col items-center justify-center gap-2 p-3 text-center">
                              <ImageIcon className="h-5 w-5 text-[#6D675E]" />
                              <span className="text-[11px] text-[#8D867B]">图片加载失败</span>
                              <a
                                href={att.url}
                                target="_blank"
                                rel="noreferrer"
                                className="inline-flex items-center gap-1 text-[11px] text-[#F2C512] hover:underline"
                              >
                                新窗口查看
                                <ExternalLink className="h-3 w-3" />
                              </a>
                            </div>
                          ) : (
                            <button
                              type="button"
                              onClick={() => setLightboxIndex(index)}
                              className="relative block aspect-[4/3] w-full cursor-zoom-in overflow-hidden focus:outline-none focus:ring-2 focus:ring-[#F2C512]/50"
                            >
                              <img
                                src={att.url}
                                alt={`反馈 #${feedback.id} 截图 ${index + 1}`}
                                loading="lazy"
                                onError={() =>
                                  setBrokenImages((prev) => ({ ...prev, [index]: true }))
                                }
                                className="h-full w-full object-cover transition duration-200 group-hover:scale-[1.03]"
                              />
                              <div className="pointer-events-none absolute inset-0 flex items-center justify-center bg-black/0 transition group-hover:bg-black/45">
                                <span className="inline-flex items-center gap-1 rounded-full border border-[#F2C512]/40 bg-[#141416]/85 px-2.5 py-1 text-[11px] font-medium text-[#FFE066] opacity-0 shadow-lg transition group-hover:opacity-100">
                                  <ZoomIn className="h-3.5 w-3.5" />
                                  查看大图
                                </span>
                              </div>
                              <span className="absolute bottom-2 left-2 rounded-md bg-black/65 px-1.5 py-0.5 font-mono text-[10px] text-[#E5DFD3] backdrop-blur-sm">
                                #{index + 1}
                              </span>
                            </button>
                          )}
                        </div>
                      );
                    })}
                  </div>
                </section>
              ) : null}

              {/* Device & Environment Metadata */}
              <section className="rounded-2xl border border-white/8 bg-[#151412] p-4 sm:p-5">
                <h3 className="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-wider text-[#B6AFA3]">
                  <Smartphone className="h-3.5 w-3.5 text-[#F2C512]" />
                  设备与诊断环境
                </h3>

                <div className="grid grid-cols-2 gap-2.5 sm:grid-cols-3">
                  <MetaCell
                    label="App 版本 / Build"
                    value={formatAppVersionLabel(feedback.app_version, feedback.build_number)}
                    mono
                  />
                  <MetaCell
                    label="系统版本"
                    value={feedback.ios_version.trim() || '未上报'}
                    mono
                  />
                  <MetaCell
                    label="设备机型"
                    value={feedback.device_model.trim() || '未上报'}
                    mono
                  />
                  <MetaCell
                    label="市场模式"
                    value={formatMarketMode(feedback.market_mode)}
                    icon={<Globe className="h-3.5 w-3.5 text-[#8A8377]" />}
                  />
                  <MetaCell
                    label="云同步开关"
                    value={feedback.cloud_sync_enabled ? '已开启' : '未开启'}
                    tone={feedback.cloud_sync_enabled ? 'emerald' : 'muted'}
                    icon={
                      feedback.cloud_sync_enabled ? (
                        <Cloud className="h-3.5 w-3.5 text-[#5AE2A0]" />
                      ) : (
                        <CloudOff className="h-3.5 w-3.5 text-[#8A8377]" />
                      )
                    }
                  />
                  <MetaCell
                    label="用户身份"
                    value={
                      feedback.user_id !== null && feedback.user_id !== undefined
                        ? `注册用户 #${feedback.user_id}`
                        : '游客用户'
                    }
                    tone={
                      feedback.user_id !== null && feedback.user_id !== undefined ? 'gold' : 'muted'
                    }
                    icon={
                      feedback.user_id !== null && feedback.user_id !== undefined ? (
                        <User className="h-3.5 w-3.5 text-[#F2C512]" />
                      ) : (
                        <UserX className="h-3.5 w-3.5 text-[#8A8377]" />
                      )
                    }
                  />
                </div>

                {/* Device Hash Footer */}
                <div className="mt-2.5 flex flex-wrap items-center justify-between gap-2 rounded-xl border border-white/6 bg-[#1B1A18] px-3 py-2 text-xs">
                  <div className="flex min-w-0 items-center gap-1.5 text-[#968F83]">
                    <Hash className="h-3.5 w-3.5 shrink-0 text-[#7D776D]" />
                    <span className="shrink-0">设备标识：</span>
                    <code className="truncate font-mono text-[11px] text-[#D8D1C5]">
                      {feedback.device_hash || '—'}
                    </code>
                  </div>
                  {feedback.device_hash ? (
                    <button
                      type="button"
                      onClick={() =>
                        void handleCopy('device', feedback.device_hash, '设备标识')
                      }
                      className="inline-flex shrink-0 cursor-pointer items-center gap-1 rounded-md border border-white/10 bg-[#141416] px-2 py-0.5 text-[11px] text-[#CBC4B7] transition hover:border-[#F2C512]/40 hover:text-[#F2C512]"
                    >
                      {copiedKey === 'device' ? (
                        <>
                          <Check className="h-3 w-3 text-[#5AE2A0]" />
                          <span className="text-[#5AE2A0]">已复制</span>
                        </>
                      ) : (
                        <>
                          <Copy className="h-3 w-3" />
                          复制
                        </>
                      )}
                    </button>
                  ) : null}
                </div>
              </section>

              {/* Processing & Reply Section */}
              <section className="space-y-4 rounded-2xl border border-[#F2C512]/22 bg-[#181714] p-4 sm:p-5">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <h3 className="text-sm font-semibold text-[#F8F5EE]">反馈处理与回复</h3>
                  {feedback.updated_by || feedback.updated_at ? (
                    <span className="text-[11px] text-[#8E877B]">
                      最近处理：
                      <span className="text-[#CBC4B7]">{feedback.updated_by || '系统'}</span>
                      {feedback.updated_at ? (
                        <span className="ml-1.5 font-mono tabular-nums">
                          {formatBeijingTime(feedback.updated_at)}
                        </span>
                      ) : null}
                    </span>
                  ) : null}
                </div>

                {/* Status Selector */}
                <div>
                  <label className="mb-2 block text-xs font-medium text-[#CBC4B7]">处理状态</label>
                  <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                    {FEEDBACK_STATUS_OPTIONS.map((option) => {
                      const selected = status === option.value;
                      return (
                        <button
                          key={option.value}
                          type="button"
                          disabled={saving}
                          onClick={() => setStatus(option.value)}
                          className={`flex cursor-pointer flex-col items-start rounded-xl border px-3 py-2.5 text-left transition disabled:cursor-not-allowed disabled:opacity-60 ${
                            selected
                              ? option.activeButtonClass
                              : 'border-white/8 bg-[#141416] text-[#A8A195] hover:border-white/18 hover:text-[#E5DFD3]'
                          }`}
                        >
                          <span className="inline-flex items-center gap-1.5 text-xs font-semibold">
                            <span className={`h-2 w-2 rounded-full ${option.dotClass}`} />
                            {option.label}
                          </span>
                          <span className="mt-0.5 text-[10px] opacity-75">{option.shortDesc}</span>
                        </button>
                      );
                    })}
                  </div>
                </div>

                {/* User-facing Admin Reply */}
                <div>
                  <div className="mb-1.5 flex flex-wrap items-center justify-between gap-2">
                    <label
                      htmlFor="feedback-admin-reply"
                      className="flex items-center gap-1.5 text-xs font-semibold text-[#F5F2EB]"
                    >
                      <MessageSquareReply className="h-3.5 w-3.5 text-[#F2C512]" />
                      开发者回复（面向用户）
                    </label>
                    <span
                      className={`font-mono text-[11px] tabular-nums ${
                        replyTooLong ? 'font-semibold text-[#FF5D5D]' : 'text-[#8D867B]'
                      }`}
                    >
                      {adminReply.length} / {REPLY_MAX_LENGTH}
                    </span>
                  </div>

                  <div className="mb-2 flex items-center gap-1.5 rounded-lg border border-[#F2C512]/25 bg-[#F2C512]/8 px-3 py-1.5 text-[11px] text-[#FFE066]">
                    <MessageSquareReply className="h-3.5 w-3.5 shrink-0 text-[#F2C512]" />
                    <span>保存后用户可在 App「我的反馈」中看到此回复，请使用友善、清晰的文案。</span>
                  </div>

                  <textarea
                    id="feedback-admin-reply"
                    rows={4}
                    maxLength={REPLY_MAX_LENGTH + 50}
                    value={adminReply}
                    disabled={saving}
                    onChange={(e) => setAdminReply(e.target.value)}
                    placeholder="填写给用户的正式回复（例如问题排查进度、版本修复说明或致谢）..."
                    className={`w-full rounded-xl border bg-[#121214] px-3.5 py-2.5 text-sm leading-relaxed text-[#F5F2EB] placeholder:text-[#655F56] transition focus:outline-none focus:ring-2 disabled:opacity-60 ${
                      replyTooLong
                        ? 'border-[#FF5D5D]/60 focus:border-[#FF5D5D] focus:ring-[#FF5D5D]/20'
                        : 'border-white/10 focus:border-[#F2C512]/60 focus:ring-[#F2C512]/20'
                    }`}
                  />

                  <div className="mt-2 flex flex-wrap items-center gap-1.5">
                    <span className="text-[11px] text-[#7D776D]">常用模板：</span>
                    {QUICK_REPLIES.map((preset, idx) => (
                      <button
                        key={idx}
                        type="button"
                        disabled={saving}
                        onClick={() => setAdminReply(preset)}
                        className="cursor-pointer rounded-md border border-white/8 bg-[#1E1D1B] px-2 py-0.5 text-[11px] text-[#CBC4B7] transition hover:border-[#F2C512]/40 hover:text-[#F2C512]"
                      >
                        {idx === 0 ? '采纳建议' : idx === 1 ? '已定位待修复' : '数据已核对'}
                      </button>
                    ))}
                    {adminReply ? (
                      <button
                        type="button"
                        disabled={saving}
                        onClick={() => setAdminReply('')}
                        className="cursor-pointer rounded-md border border-white/6 px-2 py-0.5 text-[11px] text-[#968F83] transition hover:border-[#FF5D5D]/35 hover:text-[#FF8B8B]"
                      >
                        清空
                      </button>
                    ) : null}
                  </div>

                  {feedback.replied_at ? (
                    <p className="mt-1.5 font-mono text-[11px] text-[#5AE2A0]/85">
                      上次回复时间：{formatBeijingTime(feedback.replied_at)}
                    </p>
                  ) : null}
                </div>

                {/* Internal Admin Note */}
                <div>
                  <div className="mb-1.5 flex flex-wrap items-center justify-between gap-2">
                    <label
                      htmlFor="feedback-admin-note"
                      className="flex items-center gap-1.5 text-xs font-semibold text-[#D6D0C4]"
                    >
                      <StickyNote className="h-3.5 w-3.5 text-[#A8A195]" />
                      内部处理备注
                      <span className="inline-flex items-center gap-1 rounded-md border border-white/10 bg-white/5 px-1.5 py-0.5 text-[10px] font-normal text-[#A8A195]">
                        <Lock className="h-2.5 w-2.5" />
                        仅后台可见
                      </span>
                    </label>
                    <span
                      className={`font-mono text-[11px] tabular-nums ${
                        noteTooLong ? 'font-semibold text-[#FF5D5D]' : 'text-[#8D867B]'
                      }`}
                    >
                      {adminNote.length} / {NOTE_MAX_LENGTH}
                    </span>
                  </div>

                  <textarea
                    id="feedback-admin-note"
                    rows={3}
                    maxLength={NOTE_MAX_LENGTH + 50}
                    value={adminNote}
                    disabled={saving}
                    onChange={(e) => setAdminNote(e.target.value)}
                    placeholder="记录排查日志、关联版本号、复现步骤或交接备忘（仅后台管理员可见，不会展示给用户）..."
                    className={`w-full rounded-xl border bg-[#121214] px-3.5 py-2.5 text-sm leading-relaxed text-[#F5F2EB] placeholder:text-[#655F56] transition focus:outline-none focus:ring-2 disabled:opacity-60 ${
                      noteTooLong
                        ? 'border-[#FF5D5D]/60 focus:border-[#FF5D5D] focus:ring-[#FF5D5D]/20'
                        : 'border-white/10 focus:border-[#F2C512]/50 focus:ring-[#F2C512]/15'
                    }`}
                  />
                </div>

                {/* Inline Error Message */}
                {errorMessage ? (
                  <div
                    role="alert"
                    className="flex items-start gap-2.5 rounded-xl border border-[#FF5D5D]/35 bg-[#FF5D5D]/10 px-3.5 py-3 text-xs leading-relaxed text-[#FFB4B4]"
                  >
                    <AlertCircle className="mt-0.5 h-4 w-4 shrink-0 text-[#FF5D5D]" />
                    <p>{errorMessage}</p>
                  </div>
                ) : null}
              </section>
            </div>

            {/* Sticky Footer Actions */}
            <div className="flex flex-wrap items-center justify-between gap-3 border-t border-white/8 bg-[#181715]/95 px-5 py-3.5 sm:px-6">
              <div className="flex items-center gap-2 text-xs">
                {isDirty ? (
                  <span className="inline-flex items-center gap-1.5 rounded-full border border-[#F2C512]/35 bg-[#F2C512]/12 px-2.5 py-1 text-[11px] font-medium text-[#FFE066]">
                    <span className="h-1.5 w-1.5 rounded-full bg-[#F2C512]" />
                    有未保存修改
                  </span>
                ) : (
                  <span className="text-[#7D776D]">修改状态、回复或内部备注后即可保存</span>
                )}
              </div>

              <div className="flex items-center gap-2.5">
                {isDirty ? (
                  <button
                    type="button"
                    onClick={handleReset}
                    disabled={saving}
                    className="inline-flex cursor-pointer items-center gap-1.5 rounded-xl border border-white/10 bg-[#141416] px-3.5 py-2 text-xs font-medium text-[#CBC4B7] transition hover:border-white/20 hover:text-[#F5F2EB] disabled:opacity-40"
                  >
                    <RotateCcw className="h-3.5 w-3.5" />
                    还原
                  </button>
                ) : null}

                <button
                  type="button"
                  onClick={onClose}
                  disabled={saving}
                  className="cursor-pointer rounded-xl border border-white/10 bg-[#141416] px-4 py-2 text-xs font-medium text-[#CBC4B7] transition hover:border-white/20 hover:text-[#F5F2EB] disabled:opacity-40"
                >
                  关闭
                </button>

                <button
                  type="submit"
                  disabled={!canSubmit}
                  className={`inline-flex items-center gap-1.5 rounded-xl px-5 py-2 text-xs font-semibold transition ${
                    canSubmit
                      ? 'gold-btn cursor-pointer'
                      : 'cursor-not-allowed border border-white/8 bg-white/5 text-[#756F65]'
                  }`}
                >
                  {saving ? (
                    <>
                      <Loader2 className="h-3.5 w-3.5 animate-spin" />
                      保存中...
                    </>
                  ) : (
                    <>
                      <Save className="h-3.5 w-3.5" />
                      保存处理结果
                    </>
                  )}
                </button>
              </div>
            </div>
          </form>
        </div>
      </div>

      {/* Fullscreen Image Lightbox */}
      {activeLightboxItem && lightboxIndex !== null ? (
        <div
          role="dialog"
          aria-modal="true"
          aria-label="截图放大预览"
          className="fixed inset-0 z-50 flex flex-col items-center justify-center bg-black/90 p-4 backdrop-blur-md"
          onClick={(e) => {
            if (e.target === e.currentTarget) {
              setLightboxIndex(null);
            }
          }}
        >
          {/* Top Bar */}
          <div className="mb-3 flex w-full max-w-5xl items-center justify-between gap-3 text-xs text-[#D8D1C5]">
            <div className="flex items-center gap-2">
              <span className="rounded-full border border-white/15 bg-white/10 px-2.5 py-1 font-mono">
                {lightboxIndex + 1} / {resolvedAttachments.length}
              </span>
              {activeLightboxItem.objectKey ? (
                <span className="hidden max-w-md truncate font-mono text-[11px] text-[#9A9387] sm:inline">
                  {activeLightboxItem.objectKey}
                </span>
              ) : null}
            </div>

            <div className="flex items-center gap-2">
              <a
                href={activeLightboxItem.url}
                target="_blank"
                rel="noreferrer"
                className="inline-flex items-center gap-1.5 rounded-xl border border-white/15 bg-white/8 px-3 py-1.5 text-xs font-medium text-[#F5F2EB] transition hover:border-[#F2C512]/50 hover:text-[#FFE066]"
              >
                <ExternalLink className="h-3.5 w-3.5" />
                新窗口查看原图
              </a>
              <button
                type="button"
                onClick={() => setLightboxIndex(null)}
                aria-label="关闭大图预览"
                className="inline-flex cursor-pointer items-center gap-1 rounded-xl border border-white/15 bg-white/10 px-3 py-1.5 text-xs font-medium text-[#F5F2EB] transition hover:bg-white/20"
              >
                <X className="h-4 w-4" />
                关闭 (ESC)
              </button>
            </div>
          </div>

          {/* Image Stage */}
          <div
            className="relative flex max-h-[82vh] w-full max-w-5xl flex-1 items-center justify-center"
            onClick={(e) => {
              if (e.target === e.currentTarget) {
                setLightboxIndex(null);
              }
            }}
          >
            {resolvedAttachments.length > 1 ? (
              <button
                type="button"
                onClick={() =>
                  setLightboxIndex(
                    (lightboxIndex - 1 + resolvedAttachments.length) % resolvedAttachments.length,
                  )
                }
                aria-label="上一张截图"
                className="absolute left-2 z-10 cursor-pointer rounded-full border border-white/15 bg-black/70 p-2.5 text-[#F5F2EB] transition hover:border-[#F2C512]/50 hover:text-[#FFE066]"
              >
                <ChevronLeft className="h-5 w-5" />
              </button>
            ) : null}

            <img
              src={activeLightboxItem.url}
              alt={`反馈 #${feedback.id} 截图大图 ${lightboxIndex + 1}`}
              className="max-h-[80vh] max-w-full rounded-xl border border-white/15 bg-[#0D0D0F] object-contain shadow-2xl"
            />

            {resolvedAttachments.length > 1 ? (
              <button
                type="button"
                onClick={() =>
                  setLightboxIndex((lightboxIndex + 1) % resolvedAttachments.length)
                }
                aria-label="下一张截图"
                className="absolute right-2 z-10 cursor-pointer rounded-full border border-white/15 bg-black/70 p-2.5 text-[#F5F2EB] transition hover:border-[#F2C512]/50 hover:text-[#FFE066]"
              >
                <ChevronRight className="h-5 w-5" />
              </button>
            ) : null}
          </div>
        </div>
      ) : null}
    </>
  );
}

function MetaCell({
  label,
  value,
  mono = false,
  tone = 'default',
  icon,
}: {
  label: string;
  value: string;
  mono?: boolean;
  tone?: 'default' | 'emerald' | 'gold' | 'muted';
  icon?: React.ReactNode;
}) {
  const toneClass =
    tone === 'emerald'
      ? 'text-[#5AE2A0]'
      : tone === 'gold'
        ? 'text-[#FFE066]'
        : tone === 'muted'
          ? 'text-[#A9A296]'
          : 'text-[#EFE9DC]';

  return (
    <div className="rounded-xl border border-white/6 bg-[#1B1A18] px-3 py-2.5">
      <p className="text-[11px] text-[#888176]">{label}</p>
      <div className={`mt-1 flex items-center gap-1.5 text-xs font-medium ${toneClass}`}>
        {icon}
        <span className={`truncate ${mono ? 'font-mono text-[11px]' : ''}`}>{value}</span>
      </div>
    </div>
  );
}

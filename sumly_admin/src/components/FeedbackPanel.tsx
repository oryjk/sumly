import { useCallback, useEffect, useRef, useState } from 'react';
import {
  AlertCircle,
  ChevronLeft,
  ChevronRight,
  Clock,
  Filter,
  Image as ImageIcon,
  Inbox,
  Mail,
  MessageSquareReply,
  MessageSquareText,
  RefreshCw,
  RotateCcw,
  Search,
  Smartphone,
  StickyNote,
  User,
  UserX,
  X,
} from 'lucide-react';
import { AdminApiError, fetchAdminFeedbacks } from '../api/client';
import {
  EMPTY_FEEDBACK_COUNTS,
  FEEDBACK_CATEGORY_OPTIONS,
  formatAppVersionLabel,
  getFeedbackCategoryMeta,
  getFeedbackStatusMeta,
  type AdminFeedbackCounts,
  type AdminFeedbackItem,
  type FeedbackCategory,
  type FeedbackStatus,
} from '../types/feedback';
import { formatBeijingTime, formatRelativeTime } from '../utils/format';
import { FeedbackDetailModal } from './FeedbackDetailModal';
import type { ToastType } from './Toast';

interface FeedbackPanelProps {
  apiBase: string;
  token: string;
  initialCounts?: AdminFeedbackCounts;
  refreshSignal?: number;
  onCountsChange: (counts: AdminFeedbackCounts) => void;
  onToast: (type: ToastType, title: string, description?: string) => void;
  onUnauthorized: (message?: string) => void;
  onMustChangePassword: (message?: string) => void;
}

const PAGE_SIZE = 50;

const STATUS_PILLS: ReadonlyArray<{
  key: FeedbackStatus | 'all';
  label: string;
  dotClass: string;
  activeClass: string;
}> = [
  {
    key: 'all',
    label: '全部',
    dotClass: 'bg-[#D8D1C5]',
    activeClass: 'border-[#F2C512]/45 bg-[#F2C512]/14 text-[#FFE066]',
  },
  {
    key: 'new',
    label: '待处理',
    dotClass: 'bg-[#FF5D5D]',
    activeClass: 'border-[#FF5D5D]/50 bg-[#FF5D5D]/14 text-[#FFA3A3]',
  },
  {
    key: 'in_progress',
    label: '处理中',
    dotClass: 'bg-[#F2C512]',
    activeClass: 'border-[#F2C512]/50 bg-[#F2C512]/14 text-[#FFE066]',
  },
  {
    key: 'resolved',
    label: '已解决',
    dotClass: 'bg-[#3DD68C]',
    activeClass: 'border-[#3DD68C]/50 bg-[#3DD68C]/14 text-[#5AE2A0]',
  },
  {
    key: 'archived',
    label: '已归档',
    dotClass: 'bg-[#8E877B]',
    activeClass: 'border-white/25 bg-white/10 text-[#E5DFD3]',
  },
];

export function FeedbackPanel({
  apiBase,
  token,
  initialCounts,
  refreshSignal = 0,
  onCountsChange,
  onToast,
  onUnauthorized,
  onMustChangePassword,
}: FeedbackPanelProps) {
  const [statusFilter, setStatusFilter] = useState<FeedbackStatus | 'all'>('all');
  const [categoryFilter, setCategoryFilter] = useState<FeedbackCategory | 'all'>('all');
  const [searchInput, setSearchInput] = useState('');
  const [debouncedQuery, setDebouncedQuery] = useState('');
  const [offset, setOffset] = useState(0);

  const [items, setItems] = useState<AdminFeedbackItem[]>([]);
  const [total, setTotal] = useState(0);
  const [counts, setCounts] = useState<AdminFeedbackCounts>(
    initialCounts ?? { ...EMPTY_FEEDBACK_COUNTS },
  );
  const [loading, setLoading] = useState(true);
  const [hasLoadedOnce, setHasLoadedOnce] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);

  const [selectedFeedback, setSelectedFeedback] = useState<AdminFeedbackItem | null>(null);

  const requestSeqRef = useRef(0);

  // Sync external initial counts before first fetch resolves
  useEffect(() => {
    if (initialCounts && !hasLoadedOnce) {
      setCounts(initialCounts);
    }
  }, [initialCounts, hasLoadedOnce]);

  // Debounce keyword search input
  useEffect(() => {
    const timer = window.setTimeout(() => {
      const normalized = searchInput.trim();
      setDebouncedQuery((prev) => {
        if (prev !== normalized) {
          setOffset(0);
        }
        return normalized;
      });
    }, 300);
    return () => window.clearTimeout(timer);
  }, [searchInput]);

  const loadFeedbacks = useCallback(
    async (options: { notify?: boolean } = {}) => {
      const { notify = false } = options;
      const seq = ++requestSeqRef.current;
      setLoading(true);
      setLoadError(null);

      try {
        const res = await fetchAdminFeedbacks(apiBase, token, {
          status: statusFilter,
          category: categoryFilter,
          q: debouncedQuery,
          limit: PAGE_SIZE,
          offset,
        });

        if (seq !== requestSeqRef.current) {
          return;
        }

        setItems(res.items);
        setTotal(res.total);
        setCounts(res.counts);
        setHasLoadedOnce(true);
        onCountsChange(res.counts);

        if (notify) {
          onToast('info', '已刷新用户反馈列表');
        }
      } catch (error) {
        if (seq !== requestSeqRef.current) {
          return;
        }
        if (error instanceof AdminApiError && error.isUnauthorized) {
          onUnauthorized(error.message);
          return;
        }
        if (error instanceof AdminApiError && error.isMustChangePassword) {
          onMustChangePassword(error.message);
          return;
        }
        const message = error instanceof Error ? error.message : '加载用户反馈失败，请稍后重试';
        setLoadError(message);
        if (notify) {
          onToast('error', '刷新用户反馈失败', message);
        }
      } finally {
        if (seq === requestSeqRef.current) {
          setLoading(false);
        }
      }
    },
    [
      apiBase,
      token,
      statusFilter,
      categoryFilter,
      debouncedQuery,
      offset,
      onCountsChange,
      onToast,
      onUnauthorized,
      onMustChangePassword,
    ],
  );

  useEffect(() => {
    void loadFeedbacks({ notify: false });
  }, [loadFeedbacks, refreshSignal]);

  function handleSelectStatus(next: FeedbackStatus | 'all') {
    setStatusFilter(next);
    setOffset(0);
  }

  function handleSelectCategory(next: FeedbackCategory | 'all') {
    setCategoryFilter(next);
    setOffset(0);
  }

  function handleClearSearch() {
    setSearchInput('');
    setDebouncedQuery('');
    setOffset(0);
  }

  function handleResetFilters() {
    setStatusFilter('all');
    setCategoryFilter('all');
    setSearchInput('');
    setDebouncedQuery('');
    setOffset(0);
  }

  function handleSearchKeyDown(event: React.KeyboardEvent<HTMLInputElement>) {
    if (event.key === 'Enter') {
      const normalized = searchInput.trim();
      setOffset(0);
      setDebouncedQuery(normalized);
    }
  }

  function handleFeedbackSaved(updated: AdminFeedbackItem) {
    setSelectedFeedback(null);
    setItems((prev) => prev.map((item) => (item.id === updated.id ? updated : item)));
    void loadFeedbacks({ notify: false });
  }

  const hasActiveFilter =
    statusFilter !== 'all' || categoryFilter !== 'all' || Boolean(debouncedQuery);

  const rangeStart = total === 0 ? 0 : offset + 1;
  const rangeEnd = Math.min(offset + items.length, total);
  const canPrevPage = offset > 0;
  const canNextPage = offset + PAGE_SIZE < total;

  return (
    <>
      <FeedbackDetailModal
        feedback={selectedFeedback}
        apiBase={apiBase}
        token={token}
        onClose={() => setSelectedFeedback(null)}
        onSaved={handleFeedbackSaved}
        onToast={onToast}
        onUnauthorized={onUnauthorized}
        onMustChangePassword={onMustChangePassword}
      />

      <section className="gold-card rounded-2xl p-5 sm:p-6">
        {/* Header */}
        <div className="flex flex-col gap-3 border-b border-white/8 pb-4 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-xl border border-[#F2C512]/30 bg-[#F2C512]/10 text-[#F2C512]">
              <MessageSquareText className="h-5 w-5" />
            </div>
            <div>
              <div className="flex flex-wrap items-center gap-2">
                <h2 className="text-base font-semibold text-[#F8F5EE]">用户反馈管理</h2>
                <span className="rounded-full border border-white/10 bg-white/5 px-2.5 py-0.5 font-mono text-[11px] text-[#C5BEB2]">
                  共 {counts.all} 条
                </span>
                {counts.new > 0 ? (
                  <span className="inline-flex items-center gap-1 rounded-full border border-[#FF5D5D]/35 bg-[#FF5D5D]/14 px-2.5 py-0.5 text-[11px] font-semibold text-[#FF9292]">
                    <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-[#FF5D5D]" />
                    {counts.new} 条待处理
                  </span>
                ) : null}
              </div>
              <p className="mt-0.5 text-xs text-[#958E82]">
                集中查看 App 用户提交的建议与问题、预览截图、跟进状态并直接回复至客户端
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2">
            {hasActiveFilter ? (
              <button
                type="button"
                onClick={handleResetFilters}
                className="inline-flex cursor-pointer items-center gap-1.5 rounded-xl border border-white/10 bg-[#141416] px-3 py-2 text-xs font-medium text-[#B8B1A5] transition hover:border-white/20 hover:text-[#F5F2EB]"
              >
                <RotateCcw className="h-3.5 w-3.5" />
                重置筛选
              </button>
            ) : null}

            <button
              type="button"
              onClick={() => void loadFeedbacks({ notify: true })}
              disabled={loading}
              className="inline-flex cursor-pointer items-center gap-1.5 rounded-xl border border-white/10 bg-[#141416] px-3.5 py-2 text-xs font-medium text-[#DDD6C9] transition hover:border-[#F2C512]/40 hover:text-[#F2C512] disabled:opacity-50"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 ${loading ? 'animate-spin text-[#F2C512]' : ''}`}
              />
              刷新列表
            </button>
          </div>
        </div>

        {/* Status Quick Filter Pills */}
        <div className="mt-4 flex flex-wrap items-center gap-2" role="tablist" aria-label="按处理状态筛选">
          {STATUS_PILLS.map((pill) => {
            const active = statusFilter === pill.key;
            const count = counts[pill.key];
            return (
              <button
                key={pill.key}
                type="button"
                role="tab"
                aria-selected={active}
                onClick={() => handleSelectStatus(pill.key)}
                className={`inline-flex cursor-pointer items-center gap-2 rounded-xl border px-3 py-2 text-xs font-medium transition ${
                  active
                    ? pill.activeClass
                    : 'border-white/8 bg-[#151412] text-[#A8A195] hover:border-white/16 hover:text-[#EAE4D8]'
                }`}
              >
                <span className={`h-2 w-2 rounded-full ${pill.dotClass}`} />
                <span>{pill.label}</span>
                <span
                  className={`rounded-full px-1.5 py-0.5 font-mono text-[10px] tabular-nums ${
                    active ? 'bg-black/25 text-current' : 'bg-white/6 text-[#B6AFA3]'
                  }`}
                >
                  {count}
                </span>
              </button>
            );
          })}
        </div>

        {/* Category Select + Keyword Search Toolbar */}
        <div className="mt-4 flex flex-col gap-3 sm:flex-row sm:items-center">
          {/* Category Dropdown */}
          <div className="relative sm:w-48">
            <Filter className="pointer-events-none absolute left-3 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-[#8D867B]" />
            <select
              aria-label="按反馈分类筛选"
              value={categoryFilter}
              onChange={(e) => handleSelectCategory(e.target.value as FeedbackCategory | 'all')}
              className="w-full cursor-pointer appearance-none rounded-xl border border-white/10 bg-[#141416] py-2.5 pl-9 pr-8 text-xs font-medium text-[#EFE9DC] transition focus:border-[#F2C512]/60 focus:outline-none focus:ring-2 focus:ring-[#F2C512]/20"
            >
              <option value="all">全部分类</option>
              {FEEDBACK_CATEGORY_OPTIONS.map((cat) => (
                <option key={cat.value} value={cat.value}>
                  {cat.label}
                </option>
              ))}
            </select>
            <span className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-[10px] text-[#8D867B]">
              ▾
            </span>
          </div>

          {/* Keyword Search */}
          <div className="relative flex-1">
            <Search className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-[#8D867B]" />
            <input
              type="text"
              value={searchInput}
              onChange={(e) => setSearchInput(e.target.value)}
              onKeyDown={handleSearchKeyDown}
              placeholder="搜索反馈正文、联系方式、设备机型或设备标识..."
              aria-label="搜索反馈关键词"
              className="w-full rounded-xl border border-white/10 bg-[#141416] py-2.5 pl-10 pr-9 text-xs text-[#F5F2EB] placeholder:text-[#686259] transition focus:border-[#F2C512]/60 focus:outline-none focus:ring-2 focus:ring-[#F2C512]/20"
            />
            {searchInput ? (
              <button
                type="button"
                onClick={handleClearSearch}
                aria-label="清空搜索关键词"
                className="absolute right-2.5 top-1/2 -translate-y-1/2 cursor-pointer rounded-md p-1 text-[#8D867B] transition hover:bg-white/5 hover:text-[#F5F2EB]"
              >
                <X className="h-3.5 w-3.5" />
              </button>
            ) : null}
          </div>
        </div>

        {/* Error Alert */}
        {loadError ? (
          <div className="mt-5 flex flex-col gap-3 rounded-2xl border border-[#FF5D5D]/35 bg-[#261919] px-5 py-4 sm:flex-row sm:items-center sm:justify-between">
            <div className="flex items-start gap-3">
              <AlertCircle className="mt-0.5 h-5 w-5 shrink-0 text-[#FF5D5D]" />
              <div>
                <p className="text-sm font-semibold text-[#FFD2D2]">加载用户反馈列表失败</p>
                <p className="mt-0.5 text-xs text-[#E8AAAA]">{loadError}</p>
              </div>
            </div>
            <button
              type="button"
              onClick={() => void loadFeedbacks({ notify: false })}
              className="shrink-0 cursor-pointer rounded-xl border border-[#FF5D5D]/35 bg-[#FF5D5D]/15 px-4 py-2 text-xs font-medium text-[#FFD2D2] transition hover:bg-[#FF5D5D]/25"
            >
              立即重试
            </button>
          </div>
        ) : null}

        {/* List Area */}
        {loading && !hasLoadedOnce ? (
          <div className="mt-5 space-y-3" aria-label="正在加载反馈列表">
            {[1, 2, 3, 4].map((skeleton) => (
              <div
                key={skeleton}
                className="rounded-xl border border-white/6 bg-[#161513] p-4"
              >
                <div className="flex items-center justify-between gap-3">
                  <div className="flex items-center gap-2">
                    <div className="h-5 w-12 animate-pulse rounded bg-white/8" />
                    <div className="h-5 w-16 animate-pulse rounded-full bg-white/8" />
                    <div className="h-5 w-16 animate-pulse rounded-full bg-white/8" />
                  </div>
                  <div className="h-4 w-32 animate-pulse rounded bg-white/6" />
                </div>
                <div className="mt-3 space-y-2">
                  <div className="h-4 w-11/12 animate-pulse rounded bg-white/6" />
                  <div className="h-4 w-2/3 animate-pulse rounded bg-white/5" />
                </div>
                <div className="mt-3.5 flex items-center gap-3">
                  <div className="h-4 w-24 animate-pulse rounded bg-white/5" />
                  <div className="h-4 w-28 animate-pulse rounded bg-white/5" />
                </div>
              </div>
            ))}
          </div>
        ) : !loadError && items.length === 0 ? (
          <div className="mt-5 flex flex-col items-center justify-center rounded-2xl border border-dashed border-white/10 bg-[#141416]/60 px-4 py-14 text-center">
            <div className="flex h-12 w-12 items-center justify-center rounded-2xl border border-white/8 bg-[#1B1A18] text-[#787166]">
              <Inbox className="h-6 w-6" />
            </div>
            <p className="mt-3.5 text-sm font-medium text-[#CFC8BC]">
              {hasActiveFilter ? '未找到符合筛选条件的用户反馈' : '暂无用户反馈记录'}
            </p>
            <p className="mt-1 max-w-md text-xs leading-relaxed text-[#847D72]">
              {hasActiveFilter
                ? '可以尝试调整状态、分类或清空搜索关键词后重新查看。'
                : '当用户在 App「设置 → 意见与反馈」提交建议或问题后，会实时同步展示在此工作台。'}
            </p>
            {hasActiveFilter ? (
              <button
                type="button"
                onClick={handleResetFilters}
                className="mt-4 inline-flex cursor-pointer items-center gap-1.5 rounded-xl border border-[#F2C512]/35 bg-[#F2C512]/12 px-4 py-2 text-xs font-medium text-[#FFE066] transition hover:bg-[#F2C512]/20"
              >
                <RotateCcw className="h-3.5 w-3.5" />
                清除全部筛选
              </button>
            ) : null}
          </div>
        ) : (
          <div className={`mt-5 space-y-3 transition-opacity ${loading ? 'opacity-65' : 'opacity-100'}`}>
            {items.map((item) => {
              const statusMeta = getFeedbackStatusMeta(item.status);
              const categoryMeta = getFeedbackCategoryMeta(item.category);
              const hasReply = Boolean(item.admin_reply.trim());
              const hasNote = Boolean(item.admin_note.trim());
              const attachmentCount = item.attachments.length;
              const isNew = item.status === 'new';

              return (
                <article
                  key={item.id}
                  onClick={() => setSelectedFeedback(item)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' || e.key === ' ') {
                      e.preventDefault();
                      setSelectedFeedback(item);
                    }
                  }}
                  role="button"
                  tabIndex={0}
                  className={`group cursor-pointer rounded-xl border p-4 transition focus:outline-none focus:ring-2 focus:ring-[#F2C512]/40 ${
                    isNew
                      ? 'border-[#FF5D5D]/22 bg-[#181515] hover:border-[#F2C512]/40 hover:bg-[#1C1917]'
                      : 'border-white/8 bg-[#161513] hover:border-[#F2C512]/35 hover:bg-[#1A1917]'
                  }`}
                >
                  {/* Top Row: ID + Category + Status + Reply/Note Badges + Timestamp */}
                  <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="rounded-md border border-white/8 bg-[#1E1D1B] px-2 py-0.5 font-mono text-[11px] font-semibold text-[#F2C512]">
                        #{item.id}
                      </span>

                      <span
                        className={`inline-flex items-center rounded-full border px-2.5 py-0.5 text-[11px] font-medium ${categoryMeta.badgeClass}`}
                      >
                        {categoryMeta.label}
                      </span>

                      <span
                        className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-[11px] font-medium ${statusMeta.badgeClass}`}
                      >
                        <span
                          className={`h-1.5 w-1.5 rounded-full ${statusMeta.dotClass} ${
                            isNew ? 'animate-pulse' : ''
                          }`}
                        />
                        {statusMeta.label}
                      </span>

                      {hasReply ? (
                        <span className="inline-flex items-center gap-1 rounded-full border border-[#3DD68C]/30 bg-[#3DD68C]/10 px-2 py-0.5 text-[11px] font-medium text-[#5AE2A0]">
                          <MessageSquareReply className="h-3 w-3" />
                          已回复
                        </span>
                      ) : (
                        <span className="inline-flex items-center rounded-full border border-white/8 bg-white/[0.03] px-2 py-0.5 text-[10px] text-[#837C71]">
                          未回复
                        </span>
                      )}

                      {hasNote ? (
                        <span
                          title={`内部备注：${item.admin_note}`}
                          className="inline-flex items-center gap-1 rounded-full border border-white/10 bg-white/5 px-2 py-0.5 text-[10px] text-[#B8B1A5]"
                        >
                          <StickyNote className="h-3 w-3 text-[#F2C512]/80" />
                          有备注
                        </span>
                      ) : null}
                    </div>

                    <div className="flex items-center gap-2 font-mono text-[11px] text-[#B8B1A5] tabular-nums">
                      <Clock className="h-3.5 w-3.5 text-[#F2C512]/70" />
                      <span>{formatBeijingTime(item.created_at)}</span>
                      {item.created_at ? (
                        <span className="font-sans text-[#7D776D]">
                          · {formatRelativeTime(item.created_at)}
                        </span>
                      ) : null}
                    </div>
                  </div>

                  {/* Middle Row: 2-line Content Excerpt */}
                  <p className="mt-2.5 line-clamp-2 whitespace-pre-wrap break-words text-sm leading-relaxed text-[#EFE9DC] group-hover:text-[#FAF7F0]">
                    {item.content || '（无反馈正文）'}
                  </p>

                  {/* Bottom Metadata Row */}
                  <div className="mt-3 flex flex-wrap items-center justify-between gap-2 border-t border-white/6 pt-2.5 text-[11px] text-[#9A9387]">
                    <div className="flex flex-wrap items-center gap-x-3.5 gap-y-1.5">
                      {attachmentCount > 0 ? (
                        <span className="inline-flex items-center gap-1 rounded-md border border-[#F2C512]/25 bg-[#F2C512]/10 px-2 py-0.5 font-medium text-[#FFE066]">
                          <ImageIcon className="h-3 w-3 text-[#F2C512]" />
                          {attachmentCount} 张截图
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1 text-[#706A60]">
                          <ImageIcon className="h-3 w-3" />
                          无附图
                        </span>
                      )}

                      <span className="inline-flex items-center gap-1 font-mono text-[#C5BEB2]">
                        <Smartphone className="h-3 w-3 text-[#8A8377]" />
                        {formatAppVersionLabel(item.app_version, item.build_number)}
                        {item.device_model.trim() ? ` · ${item.device_model.trim()}` : ''}
                        {item.ios_version.trim() ? ` · ${item.ios_version.trim()}` : ''}
                      </span>

                      <span className="inline-flex items-center gap-1">
                        {item.user_id !== null && item.user_id !== undefined ? (
                          <>
                            <User className="h-3 w-3 text-[#F2C512]/80" />
                            <span className="text-[#DCD5C8]">用户 #{item.user_id}</span>
                          </>
                        ) : (
                          <>
                            <UserX className="h-3 w-3 text-[#7D776D]" />
                            <span>游客</span>
                          </>
                        )}
                      </span>

                      {item.contact.trim() ? (
                        <span className="inline-flex max-w-[200px] items-center gap-1 truncate text-[#C5BEB2]">
                          <Mail className="h-3 w-3 shrink-0 text-[#8A8377]" />
                          <span className="truncate font-mono">{item.contact.trim()}</span>
                        </span>
                      ) : null}
                    </div>

                    <span className="inline-flex items-center gap-0.5 text-xs font-medium text-[#F2C512]/85 transition group-hover:translate-x-0.5 group-hover:text-[#FFE066]">
                      查看与处理
                      <ChevronRight className="h-3.5 w-3.5" />
                    </span>
                  </div>
                </article>
              );
            })}
          </div>
        )}

        {/* Pagination Footer */}
        {total > 0 ? (
          <div className="mt-5 flex flex-wrap items-center justify-between gap-3 border-t border-white/8 pt-4 text-xs text-[#9A9387]">
            <span className="font-mono tabular-nums">
              当前显示第 {rangeStart} - {rangeEnd} 条，共 {total} 条匹配结果
            </span>

            {total > PAGE_SIZE ? (
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  disabled={!canPrevPage || loading}
                  onClick={() => setOffset((prev) => Math.max(0, prev - PAGE_SIZE))}
                  className="inline-flex cursor-pointer items-center gap-1 rounded-xl border border-white/10 bg-[#141416] px-3 py-1.5 text-xs font-medium text-[#D8D1C5] transition hover:border-[#F2C512]/40 hover:text-[#F2C512] disabled:cursor-not-allowed disabled:opacity-40"
                >
                  <ChevronLeft className="h-3.5 w-3.5" />
                  上一页
                </button>
                <span className="px-1 font-mono text-[11px] text-[#B8B1A5] tabular-nums">
                  {Math.floor(offset / PAGE_SIZE) + 1} / {Math.max(1, Math.ceil(total / PAGE_SIZE))}
                </span>
                <button
                  type="button"
                  disabled={!canNextPage || loading}
                  onClick={() => setOffset((prev) => prev + PAGE_SIZE)}
                  className="inline-flex cursor-pointer items-center gap-1 rounded-xl border border-white/10 bg-[#141416] px-3 py-1.5 text-xs font-medium text-[#D8D1C5] transition hover:border-[#F2C512]/40 hover:text-[#F2C512] disabled:cursor-not-allowed disabled:opacity-40"
                >
                  下一页
                  <ChevronRight className="h-3.5 w-3.5" />
                </button>
              </div>
            ) : null}
          </div>
        ) : null}
      </section>
    </>
  );
}

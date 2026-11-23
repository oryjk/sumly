import { normalizeApiBase } from '../utils/storage';

export type FeedbackCategory = 'suggestion' | 'bug' | 'data' | 'other';
export type FeedbackStatus = 'new' | 'in_progress' | 'resolved' | 'archived';

export interface FeedbackAttachment {
  object_key: string;
  url: string;
}

export interface AdminFeedbackItem {
  id: number;
  user_id?: number | null;
  device_hash: string;
  category: FeedbackCategory;
  content: string;
  contact: string;
  attachments: FeedbackAttachment[];
  app_version: string;
  build_number: string;
  ios_version: string;
  device_model: string;
  market_mode: string;
  cloud_sync_enabled: boolean;
  status: FeedbackStatus;
  admin_note: string;
  admin_reply: string;
  replied_at?: string | null;
  updated_by: string;
  created_at: string;
  updated_at: string;
}

export interface AdminFeedbackCounts {
  all: number;
  new: number;
  in_progress: number;
  resolved: number;
  archived: number;
}

export interface AdminFeedbackListResponse {
  items: AdminFeedbackItem[];
  total: number;
  counts: AdminFeedbackCounts;
}

export interface AdminFeedbackQuery {
  status?: FeedbackStatus | 'all';
  category?: FeedbackCategory | 'all';
  q?: string;
  limit?: number;
  offset?: number;
}

export interface UpdateAdminFeedbackPayload {
  status?: FeedbackStatus;
  admin_note?: string;
  admin_reply?: string;
}

export const EMPTY_FEEDBACK_COUNTS: AdminFeedbackCounts = {
  all: 0,
  new: 0,
  in_progress: 0,
  resolved: 0,
  archived: 0,
};

export const FEEDBACK_STATUS_OPTIONS: ReadonlyArray<{
  value: FeedbackStatus;
  label: string;
  shortDesc: string;
  dotClass: string;
  badgeClass: string;
  activeButtonClass: string;
}> = [
  {
    value: 'new',
    label: '待处理',
    shortDesc: '新提交，等待跟进',
    dotClass: 'bg-[#FF5D5D]',
    badgeClass: 'border-[#FF5D5D]/35 bg-[#FF5D5D]/14 text-[#FF9292]',
    activeButtonClass: 'border-[#FF5D5D]/55 bg-[#FF5D5D]/15 text-[#FFB4B4]',
  },
  {
    value: 'in_progress',
    label: '处理中',
    shortDesc: '已确认，排查或排期中',
    dotClass: 'bg-[#F2C512]',
    badgeClass: 'border-[#F2C512]/35 bg-[#F2C512]/14 text-[#FFE066]',
    activeButtonClass: 'border-[#F2C512]/55 bg-[#F2C512]/15 text-[#FFE066]',
  },
  {
    value: 'resolved',
    label: '已解决',
    shortDesc: '已回复或已完成处理',
    dotClass: 'bg-[#3DD68C]',
    badgeClass: 'border-[#3DD68C]/35 bg-[#3DD68C]/14 text-[#5AE2A0]',
    activeButtonClass: 'border-[#3DD68C]/55 bg-[#3DD68C]/15 text-[#5AE2A0]',
  },
  {
    value: 'archived',
    label: '已归档',
    shortDesc: '留档备查，无需再跟进',
    dotClass: 'bg-[#8E877B]',
    badgeClass: 'border-white/12 bg-white/6 text-[#B6AFA3]',
    activeButtonClass: 'border-white/25 bg-white/10 text-[#E5DFD3]',
  },
];

export const FEEDBACK_CATEGORY_OPTIONS: ReadonlyArray<{
  value: FeedbackCategory;
  label: string;
  badgeClass: string;
}> = [
  {
    value: 'suggestion',
    label: '功能建议',
    badgeClass: 'border-[#F2C512]/30 bg-[#F2C512]/10 text-[#FFE066]',
  },
  {
    value: 'bug',
    label: '问题报错',
    badgeClass: 'border-[#FF5D5D]/30 bg-[#FF5D5D]/10 text-[#FF9696]',
  },
  {
    value: 'data',
    label: '数据核对',
    badgeClass: 'border-[#5AB2FF]/30 bg-[#5AB2FF]/10 text-[#8ECBFF]',
  },
  {
    value: 'other',
    label: '其他',
    badgeClass: 'border-white/12 bg-white/6 text-[#C7C0B4]',
  },
];

export function getFeedbackStatusMeta(status: FeedbackStatus) {
  return (
    FEEDBACK_STATUS_OPTIONS.find((item) => item.value === status) ?? FEEDBACK_STATUS_OPTIONS[0]
  );
}

export function getFeedbackCategoryMeta(category: FeedbackCategory) {
  return (
    FEEDBACK_CATEGORY_OPTIONS.find((item) => item.value === category) ??
    FEEDBACK_CATEGORY_OPTIONS[FEEDBACK_CATEGORY_OPTIONS.length - 1]
  );
}

export function formatMarketMode(marketMode: string | null | undefined): string {
  const normalized = (marketMode ?? '').trim().toLowerCase();
  if (!normalized) {
    return '未上报';
  }
  if (normalized === 'domestic' || normalized === 'cn') {
    return `国内市场 (${marketMode})`;
  }
  if (normalized === 'international' || normalized === 'global' || normalized === 'overseas') {
    return `国际市场 (${marketMode})`;
  }
  return marketMode ?? '未上报';
}

export function formatAppVersionLabel(appVersion: string, buildNumber: string): string {
  const ver = appVersion.trim();
  const build = buildNumber.trim();
  if (ver && build) {
    return `v${ver} (${build})`;
  }
  if (ver) {
    return `v${ver}`;
  }
  if (build) {
    return `Build ${build}`;
  }
  return '版本未知';
}

/**
 * Resolve attachment URLs returned by the backend.
 * - Full http(s)/data/blob URLs are returned as-is.
 * - Relative `/api/v1/...` paths are rebased onto the active admin `apiBase`
 *   (e.g. `/sumly/api/v1` -> `/sumly/api/v1/...`) so proxy prefixes are preserved.
 */
export function resolveFeedbackAttachmentUrl(apiBase: string, rawUrl: string): string {
  const trimmed = (rawUrl ?? '').trim();
  if (!trimmed) {
    return '';
  }
  if (/^(?:https?:)?\/\//i.test(trimmed) || trimmed.startsWith('data:') || trimmed.startsWith('blob:')) {
    return trimmed;
  }

  const normalizedBase = normalizeApiBase(apiBase);
  if (trimmed.startsWith('/api/v1/')) {
    return `${normalizedBase}${trimmed.slice('/api/v1'.length)}`;
  }

  if (trimmed.startsWith('/')) {
    try {
      const parsed = new URL(normalizedBase);
      return `${parsed.origin}${trimmed}`;
    } catch {
      return trimmed;
    }
  }

  return `${normalizedBase}/${trimmed.replace(/^\/+/, '')}`;
}

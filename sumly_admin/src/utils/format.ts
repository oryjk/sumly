import { isRecord, MEMBERSHIP_PAYWALL_KEY, parseMembershipPaywallConfig } from '../types/config';

const BEIJING_DATETIME_FORMATTER = new Intl.DateTimeFormat('zh-CN', {
  timeZone: 'Asia/Shanghai',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
  hour12: false,
});

export function formatBeijingTime(isoString: string | null | undefined): string {
  if (!isoString) {
    return '—';
  }
  const date = new Date(isoString);
  if (Number.isNaN(date.getTime())) {
    return isoString;
  }
  return BEIJING_DATETIME_FORMATTER.format(date).replace(/\//g, '-');
}

export function formatRelativeTime(isoString: string | null | undefined): string {
  if (!isoString) {
    return '';
  }
  const date = new Date(isoString);
  if (Number.isNaN(date.getTime())) {
    return '';
  }
  const diffSeconds = Math.floor((Date.now() - date.getTime()) / 1000);
  if (diffSeconds < 10) {
    return '刚刚';
  }
  if (diffSeconds < 60) {
    return `${diffSeconds} 秒前`;
  }
  const diffMinutes = Math.floor(diffSeconds / 60);
  if (diffMinutes < 60) {
    return `${diffMinutes} 分钟前`;
  }
  const diffHours = Math.floor(diffMinutes / 60);
  if (diffHours < 24) {
    return `${diffHours} 小时前`;
  }
  const diffDays = Math.floor(diffHours / 24);
  if (diffDays < 30) {
    return `${diffDays} 天前`;
  }
  return `${Math.floor(diffDays / 30)} 个月前`;
}

export interface AuditChangeBadge {
  label: string;
  fromText?: string;
  toText: string;
  tone: 'free' | 'paid' | 'gold' | 'neutral';
}

export function buildAuditChangeBadges(
  configKey: string,
  oldValue: Record<string, unknown> | null,
  newValue: Record<string, unknown>,
): AuditChangeBadge[] {
  if (configKey !== MEMBERSHIP_PAYWALL_KEY) {
    return [
      {
        label: oldValue ? '配置已更新' : '首次创建配置',
        toText: `${Object.keys(newValue).length} 个字段`,
        tone: 'neutral',
      },
    ];
  }

  const next = parseMembershipPaywallConfig(newValue);
  const prev = oldValue && isRecord(oldValue) ? parseMembershipPaywallConfig(oldValue) : null;
  const badges: AuditChangeBadge[] = [];

  if (!prev) {
    badges.push({
      label: '禅观门禁',
      toText: next.chanlun_requires_membership ? '收费' : '免费',
      tone: next.chanlun_requires_membership ? 'paid' : 'free',
    });
    badges.push({
      label: '会员入口',
      toText: next.membership_entry_visible ? '显示' : '隐藏',
      tone: next.membership_entry_visible ? 'gold' : 'neutral',
    });
    if (next.free_access_notice.trim()) {
      badges.push({
        label: '公告文案',
        toText: '已设置',
        tone: 'gold',
      });
    }
    return badges;
  }

  if (prev.chanlun_requires_membership !== next.chanlun_requires_membership) {
    badges.push({
      label: '禅观门禁',
      fromText: prev.chanlun_requires_membership ? '收费' : '免费',
      toText: next.chanlun_requires_membership ? '收费' : '免费',
      tone: next.chanlun_requires_membership ? 'paid' : 'free',
    });
  }

  if (prev.membership_entry_visible !== next.membership_entry_visible) {
    badges.push({
      label: '会员入口',
      fromText: prev.membership_entry_visible ? '显示' : '隐藏',
      toText: next.membership_entry_visible ? '显示' : '隐藏',
      tone: next.membership_entry_visible ? 'gold' : 'neutral',
    });
  }

  if (prev.free_access_notice.trim() !== next.free_access_notice.trim()) {
    badges.push({
      label: '免费公告',
      fromText: prev.free_access_notice.trim() ? '有文案' : '空',
      toText: next.free_access_notice.trim() ? '已更新' : '已清空',
      tone: 'gold',
    });
  }

  if (badges.length === 0) {
    badges.push({
      label: '配置重申',
      toText: next.chanlun_requires_membership ? '维持收费' : '维持免费',
      tone: next.chanlun_requires_membership ? 'paid' : 'free',
    });
  }

  return badges;
}

export function getUtf8ByteLength(text: string): number {
  return new TextEncoder().encode(text).length;
}

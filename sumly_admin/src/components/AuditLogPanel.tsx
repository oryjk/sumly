import { useState } from 'react';
import {
  ArrowRight,
  ChevronDown,
  ChevronUp,
  Clock,
  FileCode2,
  History,
  MessageSquareText,
  RefreshCw,
  User,
} from 'lucide-react';
import { MEMBERSHIP_PAYWALL_KEY, type AuditLogItem } from '../types/config';
import {
  buildAuditChangeBadges,
  formatBeijingTime,
  formatRelativeTime,
  type AuditChangeBadge,
} from '../utils/format';

interface AuditLogPanelProps {
  logs: AuditLogItem[];
  loading: boolean;
  onRefresh: () => void;
  compactLimit?: number;
  onViewAll?: () => void;
}

function getBadgeStyle(tone: AuditChangeBadge['tone']): string {
  switch (tone) {
    case 'free':
      return 'border-[#3DD68C]/35 bg-[#3DD68C]/12 text-[#5AE2A0]';
    case 'paid':
      return 'border-[#FF5D5D]/35 bg-[#FF5D5D]/12 text-[#FF8C8C]';
    case 'gold':
      return 'border-[#F2C512]/35 bg-[#F2C512]/12 text-[#FFE066]';
    default:
      return 'border-white/12 bg-white/6 text-[#CBC4B7]';
  }
}

export function AuditLogPanel({
  logs,
  loading,
  onRefresh,
  compactLimit,
  onViewAll,
}: AuditLogPanelProps) {
  const [filter, setFilter] = useState<'all' | 'paywall' | 'other'>('all');
  const [expandedId, setExpandedId] = useState<number | null>(null);

  const filteredLogs = compactLimit
    ? logs.slice(0, compactLimit)
    : logs.filter((item) => {
        if (filter === 'paywall') {
          return item.config_key === MEMBERSHIP_PAYWALL_KEY;
        }
        if (filter === 'other') {
          return item.config_key !== MEMBERSHIP_PAYWALL_KEY;
        }
        return true;
      });

  return (
    <section className="gold-card rounded-2xl p-5 sm:p-6">
      {/* Header */}
      <div className="flex flex-col gap-3 border-b border-white/8 pb-4 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex items-center gap-3">
          <div className="flex h-9 w-9 items-center justify-center rounded-xl border border-[#F2C512]/25 bg-[#F2C512]/10 text-[#F2C512]">
            <History className="h-4 w-4" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h3 className="text-base font-semibold text-[#F5F2EB]">
                {compactLimit ? '最近配置变更记录' : '变更审计日志（Audit Trail）'}
              </h3>
              <span className="rounded-full border border-white/10 bg-white/5 px-2 py-0.5 font-mono text-[11px] text-[#B8B1A5]">
                {logs.length} 条
              </span>
            </div>
            <p className="text-xs text-[#958E82]">
              {compactLimit
                ? '保存配置后自动刷新最新审计记录，完整保留操作人与变更前后对比'
                : '展示最近 30 条远程配置变更记录（北京时间 Asia/Shanghai）'}
            </p>
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          {!compactLimit ? (
            <div className="inline-flex rounded-xl border border-white/8 bg-[#141416] p-1 text-xs">
              {(
                [
                  { key: 'all', label: '全部' },
                  { key: 'paywall', label: '禅观门禁' },
                  { key: 'other', label: '扩展配置' },
                ] as const
              ).map((tab) => (
                <button
                  key={tab.key}
                  type="button"
                  onClick={() => setFilter(tab.key)}
                  className={`cursor-pointer rounded-lg px-2.5 py-1 transition ${
                    filter === tab.key
                      ? 'bg-[#F2C512]/18 font-medium text-[#FFE066]'
                      : 'text-[#968F83] hover:text-[#E5DFD3]'
                  }`}
                >
                  {tab.label}
                </button>
              ))}
            </div>
          ) : null}

          <button
            type="button"
            onClick={onRefresh}
            disabled={loading}
            className="inline-flex cursor-pointer items-center gap-1.5 rounded-xl border border-white/10 bg-[#141416] px-3 py-1.5 text-xs font-medium text-[#D8D1C5] transition hover:border-[#F2C512]/40 hover:text-[#F2C512] disabled:opacity-50"
          >
            <RefreshCw className={`h-3.5 w-3.5 ${loading ? 'animate-spin text-[#F2C512]' : ''}`} />
            刷新
          </button>

          {compactLimit && onViewAll ? (
            <button
              type="button"
              onClick={onViewAll}
              className="inline-flex cursor-pointer items-center gap-1 rounded-xl border border-[#F2C512]/25 bg-[#F2C512]/10 px-3 py-1.5 text-xs font-medium text-[#F2C512] transition hover:bg-[#F2C512]/18"
            >
              全部日志
              <ArrowRight className="h-3.5 w-3.5" />
            </button>
          ) : null}
        </div>
      </div>

      {/* Content */}
      {loading && logs.length === 0 ? (
        <div className="space-y-3 py-6">
          {[1, 2, 3].map((item) => (
            <div
              key={item}
              className="h-20 animate-pulse rounded-xl border border-white/6 bg-white/[0.03]"
            />
          ))}
        </div>
      ) : filteredLogs.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-12 text-center">
          <History className="h-8 w-8 text-[#59534A]" />
          <p className="mt-3 text-sm font-medium text-[#B8B1A5]">暂无符合条件的变更记录</p>
          <p className="mt-1 text-xs text-[#7D776D]">
            每次通过控制台保存配置，都会在此生成不可篡改的审计日志
          </p>
        </div>
      ) : (
        <div className="relative mt-5 space-y-3">
          {/* Vertical timeline guide on wider screens */}
          <div
            aria-hidden="true"
            className="pointer-events-none absolute bottom-4 left-[15px] top-4 hidden w-px bg-gradient-to-b from-[#F2C512]/35 via-white/10 to-transparent sm:block"
          />

          {filteredLogs.map((item) => {
            const badges = buildAuditChangeBadges(
              item.config_key,
              item.old_value,
              item.new_value,
            );
            const isExpanded = expandedId === item.id;

            return (
              <article
                key={item.id}
                className="relative rounded-xl border border-white/8 bg-[#161513] p-4 transition hover:border-white/14 sm:pl-10"
              >
                {/* Timeline Dot */}
                <span
                  aria-hidden="true"
                  className={`absolute left-[11px] top-5 hidden h-2.5 w-2.5 rounded-full border-2 border-[#161513] sm:block ${
                    badges[0]?.tone === 'free'
                      ? 'bg-[#3DD68C]'
                      : badges[0]?.tone === 'paid'
                        ? 'bg-[#FF5D5D]'
                        : 'bg-[#F2C512]'
                  }`}
                />

                <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                  <div className="min-w-0 flex-1 space-y-2">
                    {/* Top row: key + state badges */}
                    <div className="flex flex-wrap items-center gap-2">
                      <code className="rounded-md border border-white/8 bg-[#1E1D1B] px-2 py-0.5 font-mono text-[11px] text-[#E5DFD3]">
                        {item.config_key}
                      </code>

                      {badges.map((badge, index) => (
                        <span
                          key={`${item.id}-${index}`}
                          className={`inline-flex items-center gap-1 rounded-full border px-2.5 py-0.5 text-[11px] font-medium ${getBadgeStyle(badge.tone)}`}
                        >
                          <span className="opacity-80">{badge.label}</span>
                          {badge.fromText ? (
                            <>
                              <span>{badge.fromText}</span>
                              <ArrowRight className="h-3 w-3" />
                              <span className="font-semibold">{badge.toText}</span>
                            </>
                          ) : (
                            <span className="font-semibold">{badge.toText}</span>
                          )}
                        </span>
                      ))}
                    </div>

                    {/* Note + operator metadata */}
                    <div className="flex flex-wrap items-center gap-x-4 gap-y-1.5 text-xs text-[#A39C90]">
                      <span className="inline-flex items-center gap-1.5">
                        <User className="h-3.5 w-3.5 text-[#7F786D]" />
                        <span className="text-[#E3DDD2]">{item.operator || 'admin'}</span>
                      </span>

                      <span className="inline-flex items-center gap-1.5">
                        <MessageSquareText className="h-3.5 w-3.5 text-[#7F786D]" />
                        <span className={item.note ? 'text-[#D6D0C4]' : 'italic text-[#6E685E]'}>
                          {item.note || '无变更备注'}
                        </span>
                      </span>
                    </div>
                  </div>

                  {/* Right timestamp + expand */}
                  <div className="flex items-center justify-between gap-3 sm:flex-col sm:items-end sm:gap-1.5">
                    <div className="flex items-center gap-1.5 font-mono text-[11px] text-[#C5BEB2] tabular-nums">
                      <Clock className="h-3.5 w-3.5 text-[#F2C512]/75" />
                      <span>{formatBeijingTime(item.created_at)}</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <span className="text-[11px] text-[#7D776D]">
                        {formatRelativeTime(item.created_at)} · #{item.id}
                      </span>
                      <button
                        type="button"
                        onClick={() => setExpandedId(isExpanded ? null : item.id)}
                        className="inline-flex cursor-pointer items-center gap-1 rounded-md border border-white/8 bg-white/[0.03] px-2 py-0.5 text-[11px] text-[#B8B1A5] transition hover:border-[#F2C512]/35 hover:text-[#F2C512]"
                      >
                        <FileCode2 className="h-3 w-3" />
                        JSON
                        {isExpanded ? (
                          <ChevronUp className="h-3 w-3" />
                        ) : (
                          <ChevronDown className="h-3 w-3" />
                        )}
                      </button>
                    </div>
                  </div>
                </div>

                {/* Expanded JSON Snapshot */}
                {isExpanded ? (
                  <div className="mt-3.5 grid gap-3 border-t border-white/8 pt-3.5 md:grid-cols-2">
                    <div>
                      <p className="mb-1.5 text-[11px] font-medium text-[#9A9387]">
                        变更前（old_value）
                      </p>
                      <pre className="max-h-56 overflow-auto rounded-lg border border-white/6 bg-[#111113] p-3 font-mono text-[11px] leading-relaxed text-[#B2ABA0]">
                        {item.old_value ? JSON.stringify(item.old_value, null, 2) : 'null（首次创建）'}
                      </pre>
                    </div>
                    <div>
                      <p className="mb-1.5 text-[11px] font-medium text-[#F2C512]">
                        变更后（new_value）
                      </p>
                      <pre className="max-h-56 overflow-auto rounded-lg border border-[#F2C512]/20 bg-[#111113] p-3 font-mono text-[11px] leading-relaxed text-[#EDE7DB]">
                        {JSON.stringify(item.new_value, null, 2)}
                      </pre>
                    </div>
                  </div>
                ) : null}
              </article>
            );
          })}
        </div>
      )}
    </section>
  );
}

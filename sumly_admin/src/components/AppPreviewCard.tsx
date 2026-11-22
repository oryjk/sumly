import {
  ArrowDown,
  ChevronRight,
  Crown,
  Eye,
  EyeOff,
  Lock,
  ShieldCheck,
  Smartphone,
  Sparkles,
  Unlock,
} from 'lucide-react';
import type { MembershipPaywallConfig } from '../types/config';

interface AppPreviewCardProps {
  config: MembershipPaywallConfig;
  isDraftModified: boolean;
}

export function AppPreviewCard({ config, isDraftModified }: AppPreviewCardProps) {
  const requiresPaywall = config.chanlun_requires_membership;
  const entryVisible = config.membership_entry_visible;
  const notice = config.free_access_notice.trim();

  return (
    <aside className="gold-card rounded-2xl p-5 sm:p-6 lg:sticky lg:top-24">
      {/* Header */}
      <div className="flex items-start justify-between gap-3 border-b border-white/8 pb-4">
        <div className="flex items-center gap-2.5">
          <div className="flex h-9 w-9 items-center justify-center rounded-xl border border-[#F2C512]/25 bg-[#F2C512]/10 text-[#F2C512]">
            <Smartphone className="h-4 w-4" />
          </div>
          <div>
            <h3 className="text-sm font-semibold text-[#F5F2EB]">App 行为实时预览</h3>
            <p className="text-[11px] text-[#958E82]">
              根据左侧开关状态实时模拟 iOS / Android 客户端路径
            </p>
          </div>
        </div>

        <span
          className={`shrink-0 rounded-full border px-2.5 py-0.5 text-[11px] font-medium ${
            isDraftModified
              ? 'border-[#F2C512]/40 bg-[#F2C512]/15 text-[#FFE066]'
              : 'border-[#3DD68C]/30 bg-[#3DD68C]/10 text-[#5AE2A0]'
          }`}
        >
          {isDraftModified ? '草稿预览' : '线上同步'}
        </span>
      </div>

      {/* Path 1: Non-subscribed user taps Chanlun */}
      <div className="mt-5">
        <div className="mb-2.5 flex items-center justify-between">
          <span className="text-xs font-semibold text-[#DFD8CB]">
            路径 1 · 未订阅用户点击「禅观」
          </span>
          <span
            className={`text-[11px] font-medium ${
              requiresPaywall ? 'text-[#FF8C8C]' : 'text-[#3DD68C]'
            }`}
          >
            {requiresPaywall ? '触发付费拦截' : '零门槛直达'}
          </span>
        </div>

        {/* Simulated Top Bar Pill */}
        <div className="rounded-xl border border-white/8 bg-[#141416] p-3.5">
          <div className="flex items-center justify-between">
            <span className="text-[11px] text-[#7D776D]">首页顶部胶囊预览</span>
            <div className="inline-flex items-center gap-1.5 rounded-full border border-[#F2C512]/30 bg-[#211E17] px-3 py-1 text-xs font-medium text-[#F5F2EB]">
              {requiresPaywall ? (
                <Crown className="h-3.5 w-3.5 text-[#F2C512]" />
              ) : (
                <Sparkles className="h-3.5 w-3.5 text-[#3DD68C]" />
              )}
              <span>禅观</span>
              {!requiresPaywall && notice ? (
                <span className="ml-0.5 max-w-[110px] truncate rounded-full bg-[#F2C512]/18 px-1.5 py-0.5 text-[10px] font-medium text-[#F2C512]">
                  {notice}
                </span>
              ) : null}
            </div>
          </div>

          {/* Flow Arrow */}
          <div className="my-2.5 flex justify-center">
            <div className="flex items-center gap-1.5 text-[11px] text-[#8A8377]">
              <ArrowDown className="h-3.5 w-3.5 text-[#F2C512]/80" />
              <span>用户点击入口后</span>
            </div>
          </div>

          {/* Outcome Box */}
          {requiresPaywall ? (
            <div className="rounded-xl border border-[#FF5D5D]/30 bg-gradient-to-br from-[#2A1919] to-[#211A17] p-3.5">
              <div className="flex items-center gap-2 text-xs font-semibold text-[#FF9B9B]">
                <Lock className="h-4 w-4 text-[#FF5D5D]" />
                弹出 ¥99/年 记金会员订阅页
              </div>
              <p className="mt-1.5 text-[11px] leading-relaxed text-[#C9B9B6]">
                未订阅用户被拦截在 <code className="font-mono text-[#FFD58A]">MembershipPaywallSheet</code>，
                展示年卡 ¥99 / 月卡 ¥39，完成订阅后自动打开禅观。
              </p>
            </div>
          ) : (
            <div className="rounded-xl border border-[#3DD68C]/30 bg-gradient-to-br from-[#15281F] to-[#17211C] p-3.5">
              <div className="flex items-center gap-2 text-xs font-semibold text-[#5AE2A0]">
                <Unlock className="h-4 w-4 text-[#3DD68C]" />
                直接打开禅观页面（免费直通）
              </div>
              <p className="mt-1.5 text-[11px] leading-relaxed text-[#B2D3C1]">
                跳过付费墙直接放行，已登录用户直达禅观分析页面；首页皇冠锁标与「会员专属」徽标自动隐藏。
              </p>
              {notice ? (
                <div className="mt-2.5 inline-flex items-center gap-1.5 rounded-lg border border-[#F2C512]/30 bg-[#F2C512]/12 px-2.5 py-1 text-[11px] text-[#FFE066]">
                  <Sparkles className="h-3 w-3 text-[#F2C512]" />
                  <span>公告胶囊：{notice}</span>
                </div>
              ) : null}
            </div>
          )}
        </div>
      </div>

      {/* Path 2: Account Page Membership Entry */}
      <div className="mt-5">
        <div className="mb-2.5 flex items-center justify-between">
          <span className="text-xs font-semibold text-[#DFD8CB]">
            路径 2 · 「我的」页会员入口
          </span>
          <span
            className={`inline-flex items-center gap-1 text-[11px] font-medium ${
              entryVisible ? 'text-[#F2C512]' : 'text-[#9B9488]'
            }`}
          >
            {entryVisible ? <Eye className="h-3.5 w-3.5" /> : <EyeOff className="h-3.5 w-3.5" />}
            {entryVisible ? '展示入口' : '隐藏新客入口'}
          </span>
        </div>

        <div className="space-y-2 rounded-xl border border-white/8 bg-[#141416] p-3.5">
          {/* Chanlun row preview */}
          <div className="flex items-center justify-between rounded-lg border border-white/6 bg-[#1C1B19] px-3 py-2.5">
            <div className="flex items-center gap-2">
              <Sparkles className="h-3.5 w-3.5 text-[#F2C512]" />
              <span className="text-xs font-medium text-[#EFECE4]">禅观</span>
            </div>
            <div className="flex items-center gap-1.5">
              {requiresPaywall ? (
                <span className="rounded-full bg-[#F2C512]/15 px-2 py-0.5 text-[10px] font-medium text-[#F2C512]">
                  会员专属
                </span>
              ) : notice ? (
                <span className="max-w-[120px] truncate rounded-full bg-[#F2C512]/15 px-2 py-0.5 text-[10px] font-medium text-[#FFE066]">
                  {notice}
                </span>
              ) : (
                <span className="rounded-full bg-[#3DD68C]/15 px-2 py-0.5 text-[10px] font-medium text-[#3DD68C]">
                  免费开放
                </span>
              )}
              <ChevronRight className="h-3.5 w-3.5 text-[#6F695F]" />
            </div>
          </div>

          {/* Membership row preview */}
          {entryVisible ? (
            <div className="flex items-center justify-between rounded-lg border border-[#F2C512]/25 bg-gradient-to-r from-[#242016] to-[#1D1B18] px-3 py-2.5">
              <div className="flex items-center gap-2">
                <Crown className="h-3.5 w-3.5 text-[#F2C512]" />
                <span className="text-xs font-medium text-[#F8F4EA]">记金会员</span>
              </div>
              <div className="flex items-center gap-1.5">
                <span className="text-[11px] text-[#F2C512]">立即开通</span>
                <ChevronRight className="h-3.5 w-3.5 text-[#F2C512]/70" />
              </div>
            </div>
          ) : (
            <div className="flex items-center justify-between rounded-lg border border-dashed border-white/12 bg-white/[0.02] px-3 py-2.5">
              <div className="flex items-center gap-2 text-[#7C756A]">
                <EyeOff className="h-3.5 w-3.5" />
                <span className="text-xs">「记金会员」入口已对未订阅用户隐藏</span>
              </div>
            </div>
          )}

          {/* Apple compliance guarantee */}
          <div className="flex items-start gap-2 rounded-lg border border-[#3DD68C]/18 bg-[#3DD68C]/6 px-3 py-2 text-[11px] leading-relaxed text-[#A7CEB8]">
            <ShieldCheck className="mt-0.5 h-3.5 w-3.5 shrink-0 text-[#3DD68C]" />
            <span>
              <strong>老会员合规兜底：</strong>
              已付费有效会员无论入口开关是否关闭，始终可见「记金会员」行以查看有效期及管理订阅。
            </span>
          </div>
        </div>
      </div>
    </aside>
  );
}

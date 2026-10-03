<script setup lang="ts">
/**
 * QuoteHeader —— 报价区：口径切换、真实报价时间与涨跌。
 * 口径切换失败时保留原口径，不混显不同单位的数据。
 */
import type { GoldQuote, MarketBasis, RealtimeState } from "@/types/market";
import { realtimeCaption } from "@/domain/market/timing";

const props = defineProps<{
  quote: GoldQuote | null;
  basis: MarketBasis;
  status: RealtimeState;
  switching: boolean;
  error: string | null;
}>();

const emit = defineEmits<{
  (e: "switch-basis", basis: MarketBasis): void;
}>();

function formatPrice(value: number | undefined): string {
  if (value === undefined || !Number.isFinite(value)) return "--";
  return value.toFixed(2);
}

function trendClass(value: number | undefined): string {
  if (value === undefined || !Number.isFinite(value) || value === 0) return "";
  return value > 0 ? "gold-up" : "gold-down";
}

/** 上游报价时间是分钟精度，展示到分钟即可。 */
function formatSourceTime(value: string | undefined): string {
  if (!value) return "";
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return "";
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${parsed.getFullYear()}.${pad(parsed.getMonth() + 1)}.${pad(parsed.getDate())} ${pad(parsed.getHours())}:${pad(parsed.getMinutes())}`;
}
</script>

<template>
  <view class="quote-header">
    <view class="quote-header-switch">
      <view
        class="gold-capsule"
        :class="{ 'gold-capsule-active': basis === 'domestic' }"
        @tap="emit('switch-basis', 'domestic')"
      >
        国内 Au99.99
      </view>
      <view
        class="gold-capsule"
        :class="{ 'gold-capsule-active': basis === 'international' }"
        @tap="emit('switch-basis', 'international')"
      >
        国际伦敦金
      </view>
    </view>

    <view class="quote-header-price-row">
      <text class="quote-header-price">¥{{ formatPrice(quote?.cny_per_gram) }}</text>
      <text class="quote-header-unit">元/克</text>
    </view>

    <view v-if="quote" class="quote-header-change">
      <text class="quote-header-change-item" :class="trendClass(quote.change)">
        {{ quote.change >= 0 ? "+" : "" }}{{ formatPrice(quote.change) }}
      </text>
      <text class="quote-header-change-item" :class="trendClass(quote.change_percent)">
        {{ quote.change_percent >= 0 ? "+" : "" }}{{ formatPrice(quote.change_percent) }}%
      </text>
    </view>

    <view class="quote-header-meta">
      <text class="quote-header-status" :class="{ 'quote-header-status-paused': status === 'paused' }">
        {{ realtimeCaption(status) }}
      </text>
      <text v-if="quote?.source_time" class="quote-header-time">报价时间 {{ formatSourceTime(quote.source_time) }}</text>
    </view>

    <text v-if="switching" class="gold-hint">正在切换行情口径…</text>
    <text v-else-if="error" class="gold-hint gold-error">{{ error }}</text>
  </view>
</template>

<style scoped>
.quote-header {
  padding: 32rpx 0 24rpx;
}

.quote-header-switch {
  display: flex;
  gap: 16rpx;
  margin-bottom: 32rpx;
}

.quote-header-price-row {
  display: flex;
  align-items: baseline;
  gap: 12rpx;
}

.quote-header-price {
  font-size: 76rpx;
  font-weight: 800;
  color: var(--gold-ink);
  line-height: 1.1;
}

.quote-header-unit {
  font-size: 26rpx;
  color: var(--gold-muted);
}

.quote-header-change {
  display: flex;
  gap: 24rpx;
  margin-top: 12rpx;
}

.quote-header-change-item {
  font-size: 28rpx;
  font-weight: 600;
}

.quote-header-meta {
  display: flex;
  flex-direction: column;
  gap: 6rpx;
  margin-top: 20rpx;
}

.quote-header-status {
  font-size: 24rpx;
  color: var(--gold-accent);
}

.quote-header-status-paused {
  color: var(--gold-faint);
}

.quote-header-time {
  font-size: 22rpx;
  color: var(--gold-faint);
}

.gold-up {
  color: var(--gold-up);
}

.gold-down {
  color: var(--gold-down);
}

.gold-error {
  color: var(--gold-up);
}
</style>

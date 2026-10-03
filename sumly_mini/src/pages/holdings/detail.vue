<script setup lang="ts">
/**
 * 持仓详情：真实盈亏、成本与保本、盈亏拆解与计算说明。
 * 已卖出/赠送的记录展示实际结果而非当前估值。
 */
import { computed, ref } from "vue";
import { onLoad } from "@dcloudio/uni-app";
import { useHoldingsStore } from "@/stores/holdings";
import { useMarketStore } from "@/stores/market";
import { calculateReturn, returnInput } from "@/domain/holdings/returns";
import { estimateBreakdown, saleBreakdown } from "@/domain/holdings/breakdown";
import { totalPurchaseCost } from "@/domain/holdings/disposal";
import { displayName } from "@/domain/holdings/selection";
import { formatGrams, formatMoney, formatPercent } from "@/domain/holdings/presentation";
import type { HoldingRecord } from "@/types/holdings";
import ProfitBreakdown from "./components/ProfitBreakdown.vue";

const holdings = useHoldingsStore();
const market = useMarketStore();

const record = ref<HoldingRecord | null>(null);
const expanded = ref<string | null>(null);
const hidden = ref(false);

const price = computed(() => market.quote.value?.cny_per_gram ?? null);

const isDisposed = computed(() => record.value !== null && record.value.disposition !== "holding");

/** 持有中按当前估值拆解；已处置按实际实收拆解。 */
const breakdown = computed(() => {
  const current = record.value;
  if (!current) return null;
  if (isDisposed.value) {
    return saleBreakdown(totalPurchaseCost(current), current.disposalAmount);
  }
  return estimateBreakdown([returnInput(current)], price.value);
});

const result = computed(() => {
  const current = record.value;
  if (!current || isDisposed.value) return null;
  return calculateReturn(returnInput(current), price.value);
});

const trendClass = computed(() => {
  const profit = isDisposed.value ? breakdown.value?.profitCents : result.value?.profit;
  if (profit === null || profit === undefined || Number(profit) === 0) return "";
  return Number(profit) > 0 ? "gold-up" : "gold-down";
});

function dateText(ms: number | null): string {
  if (ms === null) return "--";
  const parsed = new Date(ms);
  if (Number.isNaN(parsed.getTime())) return "--";
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${parsed.getFullYear()}.${pad(parsed.getMonth() + 1)}.${pad(parsed.getDate())} ${pad(parsed.getHours())}:${pad(parsed.getMinutes())}`;
}

onLoad((options) => {
  holdings.openWorkspace("guest");
  market.start("market");
  const id = options?.id;
  if (typeof id === "string" && id) {
    record.value = holdings.document.value.records.find((item) => item.id === id) ?? null;
  }
});
</script>

<template>
  <view class="page-container detail-page">
    <view v-if="!record" class="detail-empty">
      <text class="gold-hint">记录不存在或已删除。</text>
    </view>

    <template v-else>
      <view class="gold-card">
        <view class="detail-head">
          <text class="detail-name">{{ displayName(record) }}</text>
          <text class="detail-type">{{ record.assetType }}</text>
        </view>
        <view class="gold-field-row">
          <text class="gold-field-label">克数</text>
          <text class="gold-field-value">{{ formatGrams(record.grams, hidden) }}</text>
        </view>
        <view class="gold-field-row">
          <text class="gold-field-label">购入单价</text>
          <text class="gold-field-value">{{ formatMoney(record.unitPriceCNY, hidden) }} 元/克</text>
        </view>
        <view class="gold-field-row">
          <text class="gold-field-label">购入时间</text>
          <text class="gold-field-value">{{ dateText(record.timestamp) }}</text>
        </view>
        <view v-if="record.brand" class="gold-field-row">
          <text class="gold-field-label">品牌</text>
          <text class="gold-field-value">{{ record.brand }}</text>
        </view>
        <view v-if="record.note" class="gold-field-row">
          <text class="gold-field-label">备注</text>
          <text class="gold-field-value">{{ record.note }}</text>
        </view>
        <view v-if="isDisposed" class="gold-field-row">
          <text class="gold-field-label">{{ record.disposition === "gift" ? "赠送时间" : "卖出时间" }}</text>
          <text class="gold-field-value">{{ dateText(record.disposedAt) }}</text>
        </view>
        <view v-if="isDisposed" class="gold-field-row">
          <text class="gold-field-label">实际{{ record.disposition === "gift" ? "受赠" : "到手" }}</text>
          <text class="gold-field-value">{{ formatMoney(record.disposalAmount, hidden) }}</text>
        </view>
        <view v-if="record.counterparty" class="gold-field-row">
          <text class="gold-field-label">{{ record.disposition === "gift" ? "受赠人" : "买家" }}</text>
          <text class="gold-field-value">{{ record.counterparty }}</text>
        </view>
      </view>

      <view class="gold-card">
        <text class="gold-card-title">{{ isDisposed ? "实际结果" : "收益" }}</text>
        <view class="gold-field-row">
          <text class="gold-field-label">总投入</text>
          <text class="gold-field-value">{{ formatMoney(totalPurchaseCost(record), hidden) }}</text>
        </view>
        <template v-if="isDisposed">
          <view class="gold-field-row">
            <text class="gold-field-label">真实盈亏</text>
            <text class="detail-profit" :class="trendClass">
              {{ formatMoney(Number(breakdown?.profitCents ?? 0) / 100, hidden, true) }}
            </text>
          </view>
        </template>
        <template v-else>
          <view class="gold-field-row">
            <text class="gold-field-label">账面价值</text>
            <text class="gold-field-value">{{ formatMoney(result?.bookValue ?? null, hidden) }}</text>
          </view>
          <view class="gold-field-row">
            <text class="gold-field-label">预计到手</text>
            <text class="gold-field-value">{{ formatMoney(result?.proceeds ?? null, hidden) }}</text>
          </view>
          <view class="gold-field-row">
            <text class="gold-field-label">真实盈亏</text>
            <text class="detail-profit" :class="trendClass">
              {{ formatMoney(result?.profit ?? null, hidden, true) }}
              <text class="detail-percent">{{ formatPercent(result?.profitPercent, hidden) }}</text>
            </text>
          </view>
          <view class="gold-field-row">
            <text class="gold-field-label">保本价</text>
            <text class="gold-field-value">{{ formatMoney(result?.breakEvenPrice ?? null, hidden) }} 元/克</text>
          </view>
          <view v-if="result?.requiredRisePercent !== null && result?.requiredRisePercent !== undefined" class="gold-field-row">
            <text class="gold-field-label">还需涨幅</text>
            <text class="gold-field-value">{{ formatPercent(result?.requiredRisePercent, hidden) }}</text>
          </view>
        </template>
      </view>

      <view class="gold-card">
        <view class="detail-breakdown-head">
          <text class="gold-card-title">盈亏拆解</text>
          <text class="gold-capsule" @tap="hidden = !hidden">
            {{ hidden ? "显示金额" : "隐藏金额" }}
          </text>
        </view>
        <ProfitBreakdown :breakdown="breakdown" :hidden="hidden" :expanded="expanded" @toggle="expanded = expanded === $event ? null : $event" />
      </view>
    </template>
  </view>
</template>

<style scoped>
.detail-page {
  padding-bottom: 64rpx;
}

.detail-head {
  display: flex;
  align-items: baseline;
  gap: 16rpx;
  margin-bottom: 16rpx;
}

.detail-name {
  font-size: 36rpx;
  font-weight: 700;
  color: var(--gold-ink);
}

.detail-type {
  font-size: 24rpx;
  color: var(--gold-faint);
}

.detail-profit {
  font-size: 32rpx;
  font-weight: 700;
}

.detail-percent {
  font-size: 22rpx;
  font-weight: 400;
  margin-left: 10rpx;
}

.detail-breakdown-head {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 12rpx;
}

.detail-empty {
  padding: 120rpx 0;
  text-align: center;
}

.gold-up {
  color: var(--gold-up);
}

.gold-down {
  color: var(--gold-down);
}
</style>

<script setup lang="ts">
/**
 * 持仓卡片：单条记录的品牌、克数、成本与盈亏。
 * 金额隐藏时统一显示占位符，盈亏按红涨绿跌。
 */
import { computed } from "vue";
import { calculateReturn, returnInput } from "@/domain/holdings/returns";
import { displayName } from "@/domain/holdings/selection";
import { formatGrams, formatMoney, formatPercent } from "@/domain/holdings/presentation";
import type { HoldingRecord } from "@/types/holdings";

const props = defineProps<{
  record: HoldingRecord;
  price: number | null;
  hidden: boolean;
  selected?: boolean;
}>();

const emit = defineEmits<{
  (e: "select", id: string): void;
  (e: "detail", id: string): void;
  (e: "dispose", id: string): void;
}>();

const result = computed(() => calculateReturn(returnInput(props.record), props.price));

/** 已买入总成本（未处置部分）。 */
const cost = computed(
  () => props.record.purchaseTotalOverride ?? props.record.grams * props.record.unitPriceCNY +
    props.record.laborFee + props.record.extraFee,
);

const trendClass = computed(() => {
  const profit = result.value?.profit;
  if (profit === null || profit === undefined || profit === 0) return "";
  return profit > 0 ? "gold-up" : "gold-down";
});

const dateText = computed(() => {
  const parsed = new Date(props.record.timestamp);
  if (Number.isNaN(parsed.getTime())) return "--";
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${parsed.getFullYear()}.${pad(parsed.getMonth() + 1)}.${pad(parsed.getDate())}`;
});
</script>

<template>
  <view class="holding-card" :class="{ 'holding-card-selected': selected }" @tap="emit('detail', record.id)">
    <view v-if="selected" class="holding-card-check" @tap.stop="emit('select', record.id)">
      <text class="holding-card-check-mark">✓</text>
    </view>

    <view class="holding-card-actions" @tap.stop>
      <view class="holding-card-action" @tap="emit('dispose', record.id)">
        <text class="holding-card-action-text">赠卖</text>
      </view>
    </view>

    <view class="holding-card-main">
      <text class="holding-card-name">{{ displayName(record) }}</text>
      <text class="holding-card-date">{{ dateText }} · {{ formatGrams(record.grams, hidden) }}</text>
    </view>

    <view class="holding-card-figures">
      <text class="holding-card-cost">{{ formatMoney(cost, hidden) }}</text>
      <text class="holding-card-profit" :class="trendClass">
        <template v-if="result?.profit !== null && result?.profit !== undefined">
          {{ formatMoney(result.profit, hidden, true) }}
          <text class="holding-card-percent">{{ formatPercent(result.profitPercent, hidden) }}</text>
        </template>
        <template v-else>暂无报价</template>
      </text>
    </view>
  </view>
</template>

<style scoped>
.holding-card {
  display: flex;
  align-items: center;
  gap: 20rpx;
  background: var(--gold-card);
  border: var(--gold-hairline) solid var(--gold-stroke);
  border-radius: var(--gold-radius-holding);
  padding: 28rpx;
  margin-bottom: 16rpx;
}

.holding-card-selected {
  border-color: var(--gold-accent);
}

.holding-card-check {
  width: 40rpx;
  height: 40rpx;
  border-radius: 50%;
  border: var(--gold-hairline) solid var(--gold-accent);
  display: flex;
  align-items: center;
  justify-content: center;
}

.holding-card-check-mark {
  color: var(--gold-accent);
  font-size: 24rpx;
  line-height: 1;
}

.holding-card-actions {
  display: flex;
  align-items: center;
}

.holding-card-action {
  padding: 12rpx 20rpx;
  border-radius: var(--gold-radius-range);
  background: var(--gold-cell);
  border: var(--gold-hairline) solid var(--gold-stroke);
}

.holding-card-action-text {
  font-size: 22rpx;
  color: var(--gold-accent);
  line-height: 1.2;
}

.holding-card-main {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 6rpx;
}

.holding-card-name {
  font-size: 30rpx;
  font-weight: 600;
  color: var(--gold-ink);
}

.holding-card-date {
  font-size: 22rpx;
  color: var(--gold-faint);
}

.holding-card-figures {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 6rpx;
}

.holding-card-cost {
  font-size: 26rpx;
  color: var(--gold-muted);
}

.holding-card-profit {
  font-size: 28rpx;
  font-weight: 700;
}

.holding-card-percent {
  font-size: 22rpx;
  margin-left: 8rpx;
  font-weight: 400;
}

.gold-up {
  color: var(--gold-up);
}

.gold-down {
  color: var(--gold-down);
}
</style>

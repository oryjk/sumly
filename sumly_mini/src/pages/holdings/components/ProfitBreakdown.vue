<script setup lang="ts">
/**
 * 盈亏拆解组件。
 *
 * 按「收益从哪里来/ 哪些因素拉低收益 / 无盈亏影响」分组展示，
 * 分项金额直接来自分值字符串，保证与总盈亏精确对账。
 */
import { computed } from "vue";
import {
  DIRECTION_TITLES,
  KIND_EXPLANATIONS,
  KIND_TITLES,
  type GoldProfitBreakdown,
} from "@/domain/holdings/breakdown";

const props = defineProps<{
  breakdown: GoldProfitBreakdown | null;
  hidden?: boolean;
  expanded?: string | null;
}>();

const emit = defineEmits<{
  (e: "toggle", kind: string): void;
}>();

/** 分值转元字符串。 */
function centsText(cents: string, hidden = false): string {
  if (hidden) return "****";
  const negative = cents.startsWith("-");
  const digits = (negative ? cents.slice(1) : cents).padStart(3, "0");
  const yuan = digits.slice(0, -2);
  const fraction = digits.slice(-2);
  const sign = negative ? "-" : "";
  return `${sign}${yuan}.${fraction}`;
}

const groups = computed(() => props.breakdown?.groups ?? []);
</script>

<template>
  <view class="profit-breakdown">
    <view v-if="!breakdown" class="profit-breakdown-empty">
      <text class="gold-hint">暂无报价，无法拆解盈亏构成。</text>
    </view>

    <template v-else>
      <view v-for="group in groups" :key="group.direction" class="profit-breakdown-group">
        <view class="profit-breakdown-group-head">
          <text class="profit-breakdown-group-title">{{ DIRECTION_TITLES[group.direction] }}</text>
          <text class="profit-breakdown-group-total" :class="hidden ? '' : 'profit-breakdown-signed'">
            {{ centsText(group.totalCents, hidden) }}
          </text>
        </view>

        <view
          v-for="component in group.components"
          :key="component.kind"
          class="profit-breakdown-item"
          @tap="emit('toggle', component.kind)"
        >
          <view class="profit-breakdown-item-head">
            <text class="profit-breakdown-item-title">{{ KIND_TITLES[component.kind] }}</text>
            <text class="profit-breakdown-item-amount">{{ centsText(component.cents, hidden) }}</text>
          </view>
          <text v-if="expanded === component.kind" class="profit-breakdown-item-explain">
            {{ KIND_EXPLANATIONS[component.kind] }}
          </text>
          <text
            v-if="expanded === component.kind && component.contributions.length > 1"
            class="profit-breakdown-contributions"
          >
            含 {{ component.contributions.length }} 笔记录，可在持仓列表逐条查看
          </text>
        </view>
      </view>

      <view class="profit-breakdown-total">
        <text class="profit-breakdown-total-label">总盈亏</text>
        <text class="profit-breakdown-total-value">
          {{ centsText(breakdown.profitCents, hidden) }}
        </text>
      </view>

      <text v-if="breakdown.hasUnitemizedCost" class="gold-hint">
        含手动总价记录：其成本构成未拆分，只比较当前含金价值与总投入。
      </text>
      <text v-if="breakdown.hasUnconfiguredRecovery" class="gold-hint">
        部分记录未配置回收参数，拆解按零扣减、零折价、零固定费估算。
      </text>
    </template>
  </view>
</template>

<style scoped>
.profit-breakdown-group {
  margin-bottom: 20rpx;
}

.profit-breakdown-group-head {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  padding-bottom: 10rpx;
  border-bottom: var(--gold-hairline) solid var(--gold-stroke);
}

.profit-breakdown-group-title {
  font-size: 24rpx;
  color: var(--gold-muted);
}

.profit-breakdown-group-total {
  font-size: 26rpx;
  font-weight: 700;
  color: var(--gold-ink);
}

.profit-breakdown-item {
  padding: 16rpx 0;
}

.profit-breakdown-item-head {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
}

.profit-breakdown-item-title {
  font-size: 27rpx;
  color: var(--gold-ink);
}

.profit-breakdown-item-amount {
  font-size: 27rpx;
  color: var(--gold-muted);
}

.profit-breakdown-item-explain {
  display: block;
  margin-top: 10rpx;
  font-size: 22rpx;
  color: var(--gold-faint);
  line-height: 1.6;
}

.profit-breakdown-contributions {
  display: block;
  margin-top: 6rpx;
  font-size: 21rpx;
  color: var(--gold-faint);
}

.profit-breakdown-total {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  margin-top: 16rpx;
  padding-top: 16rpx;
  border-top: var(--gold-hairline) solid var(--gold-stroke);
}

.profit-breakdown-total-label {
  font-size: 26rpx;
  color: var(--gold-muted);
}

.profit-breakdown-total-value {
  font-size: 32rpx;
  font-weight: 800;
  color: var(--gold-accent);
}

.profit-breakdown-empty {
  padding: 32rpx 0;
  text-align: center;
}
</style>

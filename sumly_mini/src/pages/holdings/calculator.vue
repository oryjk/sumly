<script setup lang="ts">
/**
 * 买前计算器与情景测算。
 * 沿用持仓的收益内核，可在测算结果保存为持仓；
 * 情景测算只替换参考价，不修改任何实际记录。
 */
import { computed, ref } from "vue";
import { createDraft, draftToRecord } from "@/domain/holdings/draft";
import { scenarioReturn, scenarioPrices } from "@/domain/holdings/scenario";
import { estimateBreakdown } from "@/domain/holdings/breakdown";
import { returnInput } from "@/domain/holdings/returns";
import { formatMoney, formatPercent } from "@/domain/holdings/presentation";
import { useHoldingsStore } from "@/stores/holdings";
import { useMarketStore } from "@/stores/market";
import PurchaseFields from "./components/PurchaseFields.vue";
import RecoveryFields from "./components/RecoveryFields.vue";
import ProfitBreakdown from "./components/ProfitBreakdown.vue";

const holdings = useHoldingsStore();
const market = useMarketStore();

const draft = ref(createDraft());
const customPrice = ref("");
const expanded = ref<string | null>(null);
const saving = ref(false);

const marketPrice = computed(() => market.quote.value?.cny_per_gram ?? null);

/** 用户输入的参考价；未填时用当前报价。 */
const activePrice = computed(() => {
  const typed = Number(customPrice.value.trim());
  if (customPrice.value.trim() !== "" && Number.isFinite(typed) && typed > 0) return typed;
  return marketPrice.value;
});

const result = computed(() => {
  const input = draft.value.input();
  if (!input) return null;
  return scenarioReturn(input, activePrice.value);
});

const breakdown = computed(() => {
  const input = draft.value.input();
  if (!input || activePrice.value === null) return null;
  return estimateBreakdown([input], activePrice.value);
});

const scenarios = computed(() => {
  const base = activePrice.value;
  if (base === null) return [];
  return scenarioPrices(base).map((item) => ({
    ...item,
    result: (() => {
      const input = draft.value.input();
      return input ? scenarioReturn(input, item.price) : null;
    })(),
  }));
});

const trendClass = computed(() => {
  const profit = result.value?.profit;
  if (profit === null || profit === undefined || profit === 0) return "";
  return profit > 0 ? "gold-up" : "gold-down";
});

function readValue(event: unknown): string {
  return (event as { detail?: { value?: string } })?.detail?.value ?? "";
}

function onPriceInput(event: unknown) {
  customPrice.value = readValue(event);
}

/** 把测算结果保存为一条持仓记录。 */
function saveAsHolding() {
  if (saving.value) return;
  const input = draft.value.input();
  if (!input) {
    uni.showToast({ title: "请检查表单填写", icon: "none" });
    return;
  }
  saving.value = true;
  try {
    const record = draftToRecord(draft.value, null, Date.now());
    record.unitPriceCNY = input.unitPrice;
    const ok = holdings.mutate((current) => ({
      ...current,
      books: current.books.includes(record.bookName) ? current.books : [...current.books, record.bookName],
      records: [...current.records, record],
    }));
    if (!ok) {
      uni.showToast({ title: holdings.saveError.value ?? "保存失败", icon: "none" });
      return;
    }
    uni.showToast({ title: "已添加为持仓", icon: "success" });
  } finally {
    saving.value = false;
  }
}
</script>

<template>
  <view class="page-container calculator-page">
    <text class="calculator-title">买前计算器</text>

    <view class="gold-card">
      <text class="gold-card-title">参考价</text>
      <view class="calculator-price-row">
        <text class="calculator-price-label">自定义（元/克）</text>
        <input
          class="calculator-price-input"
          type="digit"
          :value="customPrice"
          placeholder="留空用当前报价"
          placeholder-class="calculator-placeholder"
          @input="onPriceInput"
        />
      </view>
      <text class="gold-hint">
        当前行情 {{ marketPrice === null ? "暂无报价" : `${formatMoney(marketPrice, false)} 元/克` }}
      </text>
    </view>

    <view class="gold-card">
      <text class="gold-card-title">购入参数</text>
      <PurchaseFields :draft="draft" />
    </view>

    <view class="gold-card">
      <text class="gold-card-title">回收参数</text>
      <RecoveryFields :draft="draft" />
    </view>

    <view v-if="result" class="gold-card">
      <text class="gold-card-title">测算结果</text>
      <view class="gold-field-row">
        <text class="gold-field-label">总投入</text>
        <text class="gold-field-value">{{ formatMoney(result.totalCost, false) }}</text>
      </view>
      <view class="gold-field-row">
        <text class="gold-field-label">预计到手</text>
        <text class="gold-field-value">{{ formatMoney(result.proceeds, false) }}</text>
      </view>
      <view class="gold-field-row">
        <text class="gold-field-label">真实盈亏</text>
        <text class="calculator-profit" :class="trendClass">
          {{ formatMoney(result.profit, false, true) }}
          <text class="calculator-percent">{{ formatPercent(result.profitPercent, false) }}</text>
        </text>
      </view>
      <view class="gold-field-row">
        <text class="gold-field-label">保本价</text>
        <text class="gold-field-value">{{ formatMoney(result.breakEvenPrice, false) }} 元/克</text>
      </view>
    </view>

    <view v-if="scenarios.length > 0" class="gold-card">
      <text class="gold-card-title">情景测算</text>
      <text class="gold-hint">仅按不同金价推演，不会修改已有记录。</text>
      <view v-for="item in scenarios" :key="item.label" class="calculator-scenario">
        <text class="calculator-scenario-label">{{ item.label }}</text>
        <text class="calculator-scenario-price">{{ formatMoney(item.price, false) }} 元/克</text>
        <text class="calculator-scenario-profit" :class="item.result?.profit && item.result.profit > 0 ? 'gold-up' : 'gold-down'">
          {{ item.result ? formatMoney(item.result.profit, false, true) : "--" }}
        </text>
      </view>
    </view>

    <view v-if="breakdown" class="gold-card">
      <text class="gold-card-title">盈亏拆解</text>
      <ProfitBreakdown :breakdown="breakdown" :expanded="expanded" @toggle="expanded = expanded === $event ? null : $event" />
    </view>

    <button class="gold-primary-button calculator-save" :disabled="saving || draft.input() === null" @tap="saveAsHolding">
      {{ saving ? "保存中…" : "添加为持仓" }}
    </button>
  </view>
</template>

<style scoped>
.calculator-page {
  padding-bottom: 64rpx;
}

.calculator-title {
  display: block;
  font-size: 40rpx;
  font-weight: 800;
  color: var(--gold-ink);
  padding: 32rpx 0 24rpx;
}

.calculator-price-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.calculator-price-label {
  font-size: 28rpx;
  color: var(--gold-muted);
}

.calculator-price-input {
  width: 240rpx;
  height: var(--gold-input-h);
  background: var(--gold-cell);
  border: var(--gold-hairline) solid var(--gold-stroke);
  border-radius: var(--gold-radius-input);
  padding: 0 20rpx;
  font-size: 28rpx;
  color: var(--gold-ink);
  text-align: right;
}

.calculator-placeholder {
  color: var(--gold-faint);
}

.calculator-profit {
  font-size: 32rpx;
  font-weight: 700;
}

.calculator-percent {
  font-size: 22rpx;
  font-weight: 400;
  margin-left: 10rpx;
}

.calculator-scenario {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  padding: 14rpx 0;
  border-bottom: var(--gold-hairline) solid var(--gold-stroke);
}

.calculator-scenario-label {
  font-size: 24rpx;
  color: var(--gold-muted);
  width: 100rpx;
}

.calculator-scenario-price {
  flex: 1;
  font-size: 26rpx;
  color: var(--gold-ink);
}

.calculator-scenario-profit {
  font-size: 27rpx;
  font-weight: 700;
}

.calculator-save {
  margin-top: 32rpx;
}

.gold-up {
  color: var(--gold-up);
}

.gold-down {
  color: var(--gold-down);
}
</style>

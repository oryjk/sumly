<script setup lang="ts">
/**
 * 处置弹窗：卖出或赠送部分克数。
 * 展示本次拆出的克数与成本、剩余持仓，提交前不实际改动数据。
 */
import { computed, ref } from "vue";
import { totalPurchaseCost } from "@/domain/holdings/disposal";
import { formatGrams, formatMoney } from "@/domain/holdings/presentation";
import type { HoldingDisposition, HoldingRecord } from "@/types/holdings";

const props = defineProps<{
  record: HoldingRecord | null;
  now: number;
}>();

const emit = defineEmits<{
  (e: "cancel"): void;
  (e: "submit", payload: {
    grams: number;
    proceeds: number;
    kind: HoldingDisposition;
    disposedAt: number;
    counterparty: string;
  }): void;
}>();

const gramsText = ref("");
const proceedsText = ref("");
const counterparty = ref("");
const kind = ref<HoldingDisposition>("sold");

const grams = computed(() => Number(gramsText.value));
const proceeds = computed(() => Number(proceedsText.value));

/** 本次拆出的成本 = 总成本 × 比例，与处置算法口径一致。 */
const disposedCost = computed(() => {
  if (!props.record || !Number.isFinite(grams.value) || grams.value <= 0) return null;
  return (totalPurchaseCost(props.record) * grams.value) / props.record.grams;
});

const remaining = computed(() => {
  if (!props.record) return null;
  return props.record.grams - grams.value;
});

const problem = computed(() => {
  if (!props.record) return "记录不可用";
  if (!gramsText.value.trim()) return "";
  if (!Number.isFinite(grams.value) || grams.value <= 0) return "请输入有效克数";
  if (grams.value > props.record.grams) return "不能超过剩余克数";
  if (kind.value === "sold") {
    if (!proceedsText.value.trim()) return "";
    if (!Number.isFinite(proceeds.value) || proceeds.value < 0) return "请输入有效实收";
  }
  return "";
});

const canSubmit = computed(() => Boolean(props.record) && !problem.value && gramsText.value.trim().length > 0);

function readValue(event: unknown): string {
  return (event as { detail?: { value?: string } })?.detail?.value ?? "";
}

function onGramsInput(event: unknown) {
  gramsText.value = readValue(event);
}

function onProceedsInput(event: unknown) {
  proceedsText.value = readValue(event);
}

function onCounterpartyInput(event: unknown) {
  counterparty.value = readValue(event);
}

function submit() {
  if (!canSubmit.value || !props.record) return;
  emit("submit", {
    grams: grams.value,
    proceeds: kind.value === "gift" ? 0 : proceeds.value || 0,
    kind: kind.value,
    disposedAt: props.now,
    counterparty: counterparty.value.trim(),
  });
}
</script>

<template>
  <view v-if="record" class="disposal-sheet">
    <view class="disposal-sheet-mask" @tap="emit('cancel')" />
    <view class="disposal-sheet-body">
      <text class="disposal-sheet-title">处置持仓</text>

      <view class="disposal-kind">
        <view
          class="gold-capsule"
          :class="{ 'gold-capsule-active': kind === 'sold' }"
          @tap="kind = 'sold'"
        >
          卖出
        </view>
        <view
          class="gold-capsule"
          :class="{ 'gold-capsule-active': kind === 'gift' }"
          @tap="kind = 'gift'"
        >
          赠送
        </view>
      </view>

      <view class="gold-field-row">
        <text class="gold-field-label">剩余克数</text>
        <text class="gold-field-value">{{ formatGrams(record.grams, false) }}</text>
      </view>

      <view class="disposal-input">
        <text class="disposal-input-label">处置克数</text>
        <input
          class="disposal-input-field"
          type="digit"
          :value="gramsText"
          placeholder="0.00"
          placeholder-class="disposal-placeholder"
          @input="onGramsInput"
        />
      </view>

      <view v-if="kind === 'sold'" class="disposal-input">
        <text class="disposal-input-label">实际总实收</text>
        <input
          class="disposal-input-field"
          type="digit"
          :value="proceedsText"
          placeholder="0.00"
          placeholder-class="disposal-placeholder"
          @input="onProceedsInput"
        />
      </view>

      <view class="disposal-input">
        <text class="disposal-input-label">{{ kind === "sold" ? "买家" : "受赠人" }}</text>
        <input
          class="disposal-input-field"
          :value="counterparty"
          placeholder="选填"
          placeholder-class="disposal-placeholder"
          @input="onCounterpartyInput"
        />
      </view>

      <view v-if="disposedCost !== null" class="disposal-summary">
        <view class="gold-field-row">
          <text class="gold-field-label">本次拆出成本</text>
          <text class="gold-field-value">{{ formatMoney(disposedCost, false) }}</text>
        </view>
        <view class="gold-field-row">
          <text class="gold-field-label">处置后剩余</text>
          <text class="gold-field-value">{{ formatGrams(remaining, false) }}</text>
        </view>
      </view>

      <text v-if="problem" class="gold-hint gold-error">{{ problem }}</text>
      <text v-else class="gold-hint">
        部分处置会按克数比例分摊成本，剩余持仓的总成本随之下降。
      </text>

      <view class="disposal-actions">
        <button class="gold-plain-button disposal-action" @tap="emit('cancel')">取消</button>
        <button class="gold-primary-button disposal-action" :disabled="!canSubmit" @tap="submit">
          确认{{ kind === "sold" ? "卖出" : "赠送" }}
        </button>
      </view>
    </view>
  </view>
</template>

<style scoped>
.disposal-sheet {
  position: fixed;
  inset: 0;
  z-index: 200;
  display: flex;
  flex-direction: column;
  justify-content: flex-end;
}

.disposal-sheet-mask {
  position: absolute;
  inset: 0;
  background: rgba(0, 0, 0, 0.6);
}

.disposal-sheet-body {
  position: relative;
  background: var(--gold-card);
  border-top-left-radius: var(--gold-radius-card);
  border-top-right-radius: var(--gold-radius-card);
  padding: 32rpx;
  padding-bottom: calc(32rpx + var(--gold-safe-bottom));
}

.disposal-sheet-title {
  display: block;
  font-size: 32rpx;
  font-weight: 700;
  color: var(--gold-ink);
  margin-bottom: 24rpx;
}

.disposal-kind {
  display: flex;
  gap: 16rpx;
  margin-bottom: 16rpx;
}

.disposal-input {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 16rpx 0;
}

.disposal-input-label {
  font-size: 28rpx;
  color: var(--gold-muted);
}

.disposal-input-field {
  flex: 1;
  margin-left: 24rpx;
  height: var(--gold-input-h);
  background: var(--gold-cell);
  border: var(--gold-hairline) solid var(--gold-stroke);
  border-radius: var(--gold-radius-input);
  padding: 0 20rpx;
  font-size: 28rpx;
  color: var(--gold-ink);
  text-align: right;
}

.disposal-summary {
  margin-top: 16rpx;
  padding-top: 8rpx;
  border-top: var(--gold-hairline) solid var(--gold-stroke);
}

.disposal-actions {
  display: flex;
  gap: 16rpx;
  margin-top: 24rpx;
}

.disposal-action {
  flex: 1;
  margin: 0;
}

.gold-error {
  color: var(--gold-up);
}
</style>

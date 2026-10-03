<script setup lang="ts">
/**
 * 回收参数：每克扣减、折价率与固定费用。
 * 折价是「扣减后再折扣」的比例，不是保留比例。
 */
import { computed } from "vue";
import type { createDraft } from "@/domain/holdings/draft";

const props = defineProps<{
  draft: ReturnType<typeof createDraft>;
}>();

const emit = defineEmits<{
  (e: "change"): void;
}>();

const discountError = computed(() => {
  const value = Number(props.draft.discountText.trim());
  if (props.draft.discountText.trim() === "") return "";
  if (!Number.isFinite(value) || value < 0) return "折价率不能为负";
  if (value >= 100) return "折价率须小于 100";
  return "";
});

function readValue(event: unknown): string {
  return (event as { detail?: { value?: string } })?.detail?.value ?? "";
}

function onDeductionInput(event: unknown) {
  props.draft.deductionText = readValue(event);
  emit("change");
}

function onDiscountInput(event: unknown) {
  props.draft.discountText = readValue(event);
  emit("change");
}

function onFixedFeeInput(event: unknown) {
  props.draft.fixedFeeText = readValue(event);
  emit("change");
}
</script>

<template>
  <view class="recovery-fields">
    <view class="draft-row">
      <text class="draft-label">每克扣减</text>
      <view class="draft-input-group">
        <input
          class="draft-input draft-input-narrow"
          type="digit"
          :value="draft.deductionText"
          placeholder="0.00"
          placeholder-class="draft-placeholder"
          @input="onDeductionInput"
        />
        <text class="draft-suffix">元/克</text>
      </view>
    </view>

    <view class="draft-row">
      <text class="draft-label">折价率</text>
      <view class="draft-input-group">
        <input
          class="draft-input draft-input-narrow"
          type="digit"
          :value="draft.discountText"
          placeholder="0.00"
          placeholder-class="draft-placeholder"
          @input="onDiscountInput"
        />
        <text class="draft-suffix">%</text>
      </view>
    </view>
    <text v-if="discountError" class="draft-error">{{ discountError }}</text>

    <view class="draft-row">
      <text class="draft-label">固定费用</text>
      <view class="draft-input-group">
        <input
          class="draft-input draft-input-narrow"
          type="digit"
          :value="draft.fixedFeeText"
          placeholder="0.00"
          placeholder-class="draft-placeholder"
          @input="onFixedFeeInput"
        />
        <text class="draft-suffix">元</text>
      </view>
    </view>

    <text class="gold-hint">
      预计回收单价 = max(0, 参考价 − 每克扣减) × (1 − 折价率)，固定费用在到手时一次性扣除。
    </text>
  </view>
</template>

<style scoped>
.draft-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 14rpx 0;
}

.draft-label {
  font-size: 28rpx;
  color: var(--gold-muted);
  flex-shrink: 0;
  margin-right: 20rpx;
}

.draft-input {
  flex: 1;
  height: var(--gold-input-h);
  background: var(--gold-cell);
  border: var(--gold-hairline) solid var(--gold-stroke);
  border-radius: var(--gold-radius-input);
  padding: 0 20rpx;
  font-size: 28rpx;
  color: var(--gold-ink);
  text-align: right;
}

.draft-input-narrow {
  max-width: 200rpx;
}

.draft-input-group {
  display: flex;
  align-items: center;
  gap: 12rpx;
  flex: 1;
  justify-content: flex-end;
}

.draft-suffix {
  font-size: 24rpx;
  color: var(--gold-faint);
  flex-shrink: 0;
}

.draft-placeholder {
  color: var(--gold-faint);
}

.draft-error {
  display: block;
  font-size: 22rpx;
  color: var(--gold-up);
  margin: -8rpx 0 8rpx;
}
</style>

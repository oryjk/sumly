<script setup lang="ts">
/**
 * 购入字段：克数、纯度、价格与工费。
 * 工费支持按克与按总额两种录入，换算在 domain 层完成。
 */
import { computed } from "vue";
import type { createDraft } from "@/domain/holdings/draft";

const props = defineProps<{
  draft: ReturnType<typeof createDraft>;
}>();

const emit = defineEmits<{
  (e: "change"): void;
}>();

const LABOR_MODES = [
  { key: true, label: "按克" },
  { key: false, label: "按总额" },
] as const;

const gramsError = computed(() => {
  const value = Number(props.draft.gramsText.trim());
  if (props.draft.gramsText.trim() === "") return "";
  if (!Number.isFinite(value) || value <= 0) return "克数须大于 0";
  return "";
});

function readValue(event: unknown): string {
  return (event as { detail?: { value?: string } })?.detail?.value ?? "";
}

function onGramsInput(event: unknown) {
  props.draft.gramsText = readValue(event);
  emit("change");
}

function onPriceInput(event: unknown) {
  props.draft.priceText = readValue(event);
  emit("change");
}

function onLaborInput(event: unknown) {
  props.draft.laborText = readValue(event);
  emit("change");
}

function onPurityInput(event: unknown) {
  props.draft.purityText = readValue(event);
  emit("change");
}

function onOtherInput(event: unknown) {
  props.draft.otherText = readValue(event);
  emit("change");
}

function setLaborMode(perGram: boolean) {
  props.draft.laborPerGram = perGram;
  emit("change");
}
</script>

<template>
  <view class="purchase-fields">
    <view class="draft-row">
      <text class="draft-label">克数</text>
      <input
        class="draft-input"
        type="digit"
        :value="draft.gramsText"
        placeholder="0.00"
        placeholder-class="draft-placeholder"
        @input="onGramsInput"
      />
    </view>
    <text v-if="gramsError" class="draft-error">{{ gramsError }}</text>

    <view class="draft-row">
      <text class="draft-label">纯度</text>
      <view class="draft-input-group">
        <input
          class="draft-input draft-input-narrow"
          type="digit"
          :value="draft.purityText"
          placeholder="99.99"
          placeholder-class="draft-placeholder"
          @input="onPurityInput"
        />
        <text class="draft-suffix">%</text>
      </view>
    </view>

    <view v-if="draft.costMode === 'unit'" class="draft-row">
      <text class="draft-label">购入单价</text>
      <view class="draft-input-group">
        <input
          class="draft-input draft-input-narrow"
          type="digit"
          :value="draft.priceText"
          placeholder="0.00"
          placeholder-class="draft-placeholder"
          @input="onPriceInput"
        />
        <text class="draft-suffix">元/克</text>
      </view>
    </view>

    <view class="draft-row">
      <text class="draft-label">工费</text>
      <view class="draft-labor">
        <view class="draft-labor-modes">
          <view
            v-for="mode in LABOR_MODES"
            :key="String(mode.key)"
            class="gold-capsule draft-labor-mode"
            :class="{ 'gold-capsule-active': draft.laborPerGram === mode.key }"
            @tap="setLaborMode(mode.key)"
          >
            {{ mode.label }}
          </view>
        </view>
        <view class="draft-input-group">
          <input
            class="draft-input draft-input-narrow"
            type="digit"
            :value="draft.laborText"
            placeholder="0.00"
            placeholder-class="draft-placeholder"
            @input="onLaborInput"
          />
          <text class="draft-suffix">元{{ draft.laborPerGram ? "/克" : "" }}</text>
        </view>
      </view>
    </view>

    <view class="draft-row">
      <text class="draft-label">其他费用</text>
      <view class="draft-input-group">
        <input
          class="draft-input draft-input-narrow"
          type="digit"
          :value="draft.otherText"
          placeholder="0.00"
          placeholder-class="draft-placeholder"
          @input="onOtherInput"
        />
        <text class="draft-suffix">元</text>
      </view>
    </view>
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

.draft-labor {
  flex: 1;
  display: flex;
  align-items: center;
  gap: 16rpx;
}

.draft-labor-modes {
  display: flex;
  gap: 8rpx;
  flex-shrink: 0;
}

.draft-labor-mode {
  padding: 8rpx 18rpx;
  font-size: 22rpx;
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

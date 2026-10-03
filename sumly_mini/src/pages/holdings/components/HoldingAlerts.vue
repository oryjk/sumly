<script setup lang="ts">
/**
 * 持仓目标提醒编辑：四种目标的开关与阈值、口径选择。
 *
 * 表单只改配置；保存时与最新配置合并，配置变化会重置对应运行态
 * （armed/基线/冷却），避免用旧阈值监测新成本。
 */
import { computed, ref } from "vue";
import { ALERT_TITLES, mergeAlertForm, isValidAlert, type AlertKind } from "@/domain/holdings/alerts";
import { newUUID } from "@/domain/holdings/draft";
import type { HoldingAlert, HoldingAlertBasis, HoldingRecord } from "@/types/holdings";

const props = defineProps<{
  record: HoldingRecord;
  basis: HoldingAlertBasis;
}>();

const emit = defineEmits<{
  (e: "save", payload: { alerts: HoldingAlert[]; resetIDs: string[] }): void;
}>();

const KINDS: AlertKind[] = ["breakEven", "profitPercent", "profitAmount", "price"];

const UNITS: Record<AlertKind, string> = {
  breakEven: "",
  profitPercent: "%",
  profitAmount: "元",
  price: "元/克",
};

const PLACEHOLDERS: Record<AlertKind, string> = {
  breakEven: "按成本自动计算",
  profitPercent: "例如 10",
  profitAmount: "例如 500",
  price: "例如 600",
};

interface Row {
  alert: HoldingAlert;
  thresholdText: string;
}

const rows = ref<Row[]>([]);
/** 已存在的提醒按原 id 保留，避免每次保存都生成新 id。 */
const existing = new Map(props.record.alerts.map((alert) => [alert.kind, alert]));

for (const kind of KINDS) {
  const found = existing.get(kind);
  rows.value.push({
    alert: found ?? {
      id: newUUID(),
      kind,
      threshold: 0,
      enabled: false,
      basis: props.basis,
    },
    thresholdText: found ? String(found.threshold) : "",
  });
}

const visibleRows = computed(() => rows.value.filter((row) => row.alert.kind !== "breakEven" || row.alert.enabled));

function toggle(index: number) {
  rows.value[index].alert.enabled = !rows.value[index].alert.enabled;
}

function onThresholdInput(index: number, event: unknown) {
  const value = (event as { detail?: { value?: string } })?.detail?.value ?? "";
  rows.value[index].thresholdText = value;
}

function readValue(event: unknown): string {
  return (event as { detail?: { value?: string } })?.detail?.value ?? "";
}

function save() {
  const edited = rows.value.map((row) => row.alert);
  const values = rows.value.map((row) => row.thresholdText);
  const merged = mergeAlertForm(edited, values, props.record.alerts, props.basis);
  if (!merged) {
    uni.showToast({ title: "请检查提醒设置", icon: "none" });
    return;
  }
  // 至少保留有效配置，不允许全部无效
  if (!merged.alerts.some((alert) => !alert.enabled || isValidAlert(alert))) {
    uni.showToast({ title: "至少需要一个有效提醒", icon: "none" });
    return;
  }
  emit("save", merged);
}
</script>

<template>
  <view class="holding-alerts">
    <view v-for="(row, index) in visibleRows" :key="row.alert.id" class="alert-row">
      <view class="alert-row-head">
        <text class="alert-row-title">{{ ALERT_TITLES[row.alert.kind] }}</text>
        <view
          class="alert-switch"
          :class="{ 'alert-switch-on': row.alert.enabled }"
          @tap="toggle(index)"
        >
          <text class="alert-switch-text">{{ row.alert.enabled ? "已开启" : "已关闭" }}</text>
        </view>
      </view>

      <view v-if="row.alert.kind !== 'breakEven'" class="alert-row-input">
        <input
          class="alert-input"
          type="digit"
          :value="row.thresholdText"
          :placeholder="PLACEHOLDERS[row.alert.kind]"
          placeholder-class="alert-placeholder"
          :disabled="!row.alert.enabled"
          @input="onThresholdInput(index, $event)"
        />
        <text class="alert-unit">{{ UNITS[row.alert.kind] }}</text>
      </view>
      <text v-else class="gold-hint">
        开启后按当前成本与回收参数自动反推保本价，无需填写阈值。
      </text>
    </view>

    <view class="alert-basis">
      <text class="gold-field-label">提醒口径</text>
      <view class="alert-basis-options">
        <text class="alert-basis-option" :class="{ 'alert-basis-on': basis === 'domestic' }">国内</text>
        <text class="alert-basis-option" :class="{ 'alert-basis-on': basis === 'international' }">国际</text>
      </view>
    </view>

    <button class="gold-primary-button alert-save" @tap="save">保存提醒设置</button>
  </view>
</template>

<style scoped>
.alert-row {
  padding: 20rpx 0;
  border-bottom: var(--gold-hairline) solid var(--gold-stroke);
}

.alert-row-head {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.alert-row-title {
  font-size: 28rpx;
  color: var(--gold-ink);
}

.alert-switch {
  padding: 8rpx 20rpx;
  border-radius: 999rpx;
  background: var(--gold-cell);
  border: var(--gold-hairline) solid var(--gold-stroke);
}

.alert-switch-on {
  background: var(--gold-accent);
  border-color: var(--gold-accent);
}

.alert-switch-text {
  font-size: 22rpx;
  color: var(--gold-muted);
}

.alert-switch-on .alert-switch-text {
  color: var(--gold-on-accent);
  font-weight: 700;
}

.alert-row-input {
  display: flex;
  align-items: center;
  gap: 12rpx;
  margin-top: 16rpx;
}

.alert-input {
  flex: 1;
  height: var(--gold-input-h);
  background: var(--gold-cell);
  border: var(--gold-hairline) solid var(--gold-stroke);
  border-radius: var(--gold-radius-input);
  padding: 0 20rpx;
  font-size: 27rpx;
  color: var(--gold-ink);
}

.alert-placeholder {
  color: var(--gold-faint);
}

.alert-unit {
  font-size: 24rpx;
  color: var(--gold-faint);
  width: 80rpx;
}

.alert-basis {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 20rpx 0;
}

.alert-basis-options {
  display: flex;
  gap: 12rpx;
}

.alert-basis-option {
  font-size: 24rpx;
  color: var(--gold-muted);
  padding: 8rpx 20rpx;
  border-radius: 999rpx;
  background: var(--gold-cell);
}

.alert-basis-on {
  background: var(--gold-accent);
  color: var(--gold-on-accent);
  font-weight: 700;
}

.alert-save {
  margin-top: 24rpx;
}
</style>

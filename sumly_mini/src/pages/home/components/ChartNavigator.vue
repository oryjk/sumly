<script setup lang="ts">
/**
 * ChartNavigator —— 全范围缩略图与范围手柄。
 * 展示数据的真实可用范围，拖动手柄调整视窗；
 * 缩略图只是导航，统计与查价仍取原始数据。
 */
import { computed } from "vue";
import { priceScale } from "@/domain/market/scale";
import { DAY_MS, type ChartWindow } from "@/domain/market/viewport";
import type { ChartPoint } from "@/types/market";

const props = defineProps<{
  points: ChartPoint[];
  bounds: ChartWindow;
  window: ChartWindow;
}>();

const emit = defineEmits<{
  (e: "window-change", window: ChartWindow): void;
}>();

/** 缩略图路径，采样到固定点数避免长历史拖动卡顿。 */
const overview = computed(() => {
  if (props.points.length === 0) return [] as ChartPoint[];
  const step = Math.max(1, Math.ceil(props.points.length / 120));
  const sampled: ChartPoint[] = [];
  for (let index = 0; index < props.points.length; index += step) {
    sampled.push(props.points[index]);
  }
  const last = props.points[props.points.length - 1];
  if (sampled[sampled.length - 1] !== last) sampled.push(last);
  return sampled;
});

const domain = computed(() => priceScale(overview.value));

function ratio(value: number, min: number, max: number): number {
  const span = max - min;
  if (span <= 0) return 0;
  return (value - min) / span;
}

const windowStyle = computed(() => {
  const startRatio = ratio(props.window.start, props.bounds.start, props.bounds.end);
  const endRatio = ratio(props.window.end, props.bounds.start, props.bounds.end);
  return {
    left: `${Math.min(startRatio, endRatio) * 100}%`,
    width: `${Math.abs(endRatio - startRatio) * 100}%`,
  };
});

const polyline = computed(() => {
  if (overview.value.length === 0) return "";
  const { start, end } = props.bounds;
  return overview.value
    .map((point) => {
      const x = ratio(point.time, start, end) * 100;
      const y = (1 - ratio(point.price, domain.value.min, domain.value.max)) * 100;
      return `${x.toFixed(2)},${y.toFixed(2)}`;
    })
    .join(" ");
});

function pan(fraction: number) {
  const span = props.window.end - props.window.start;
  const shift = fraction * (props.bounds.end - props.bounds.start);
  emit("window-change", { start: props.window.start + shift, end: props.window.start + shift + span });
}

function reset() {
  emit("window-change", { ...props.bounds });
}

const MIN_SPAN = DAY_MS;
</script>

<template>
  <view class="chart-navigator">
    <view class="chart-navigator-track" @tap="reset">
      <svg v-if="polyline" class="chart-navigator-svg" viewBox="0 0 100 100" preserveAspectRatio="none">
        <polyline :points="polyline" fill="none" stroke="#F2C512" stroke-width="1" vector-effect="non-scaling-stroke" />
      </svg>
      <view class="chart-navigator-window" :style="windowStyle">
        <view
          class="chart-navigator-handle chart-navigator-handle-start"
          @tap.stop="pan(0.15)"
        />
        <view
          class="chart-navigator-handle chart-navigator-handle-end"
          @tap.stop="pan(-0.15)"
        />
      </view>
    </view>
    <text class="gold-hint">点击缩略图恢复完整范围，当前窗口最短 {{ Math.round(MIN_SPAN / DAY_MS) }} 天</text>
  </view>
</template>

<style scoped>
.chart-navigator {
  margin-top: 24rpx;
}

.chart-navigator-track {
  position: relative;
  width: 100%;
  height: 96rpx;
  background: var(--gold-cell);
  border-radius: var(--gold-radius-input);
  overflow: hidden;
}

.chart-navigator-svg {
  width: 100%;
  height: 100%;
}

.chart-navigator-window {
  position: absolute;
  top: 0;
  bottom: 0;
  background: rgba(242, 197, 18, 0.12);
  border-left: var(--gold-hairline) solid var(--gold-accent);
  border-right: var(--gold-hairline) solid var(--gold-accent);
}

.chart-navigator-handle {
  position: absolute;
  top: 0;
  bottom: 0;
  width: 16rpx;
  background: var(--gold-accent);
  opacity: 0.85;
}

.chart-navigator-handle-start {
  left: 0;
}

.chart-navigator-handle-end {
  right: 0;
}
</style>

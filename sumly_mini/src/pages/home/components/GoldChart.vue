<script setup lang="ts">
/**
 * GoldChart —— 走势图绘制与手势交互。
 *
 * 绘制通过 uni canvas 上下文完成，不依赖浏览器 DOM；
 * 坐标变换、选点与视窗计算都在纯逻辑模块中，这里只做渲染与事件编排。
 * 抽样只影响绘制，查价与统计始终使用原始数据。
 */
import { computed, onMounted, ref, watch } from "vue";
import { pointsForDrawing } from "@/domain/market/sampling";
import { priceScale, unscaleValue, type PriceScaleKind } from "@/domain/market/scale";
import { nearestPoint, type ChartWindow } from "@/domain/market/viewport";
import type { ChartPoint } from "@/types/market";

const props = withDefaults(
  defineProps<{
    points: ChartPoint[];
    window: ChartWindow;
    daily?: boolean;
    scaleKind?: PriceScaleKind;
    height?: number;
  }>(),
  { daily: false, scaleKind: "linear", height: 420 },
);

const emit = defineEmits<{
  (e: "select", point: ChartPoint | null): void;
  (e: "window-change", window: ChartWindow): void;
}>();

const canvasId = "gold-chart";
const selected = ref<ChartPoint | null>(null);
const gestureStart = ref<{ x: number; y: number; window: ChartWindow } | null>(null);

const drawn = computed(() => pointsForDrawing(props.points, props.daily));

/** 视窗内的原始点，统计与选点都基于它，不基于抽样结果。 */
const visible = computed(() =>
  props.points.filter((point) => point.time >= props.window.start && point.time <= props.window.end),
);

const domain = computed(() => priceScale(drawn.value, props.scaleKind));

/** 时间轴与价格轴的映射比例。 */
function timeRatio(time: number): number {
  const span = props.window.end - props.window.start;
  if (span <= 0) return 0;
  return (time - props.window.start) / span;
}

function priceRatio(price: number): number {
  const span = domain.value.max - domain.value.min;
  if (span <= 0) return 0.5;
  const value = props.scaleKind === "linear" ? price : Math.log10(price);
  return (value - domain.value.min) / span;
}

function draw() {
  const context = uni.createCanvasContext(canvasId);
  const width = uni.getSystemInfoSync().windowWidth;
  const height = props.height;
  const points = drawn.value;

  context.clearRect(0, 0, width, height);
  if (points.length < 2) {
    context.draw();
    return;
  }

  // 折线
  context.beginPath();
  context.setLineWidth(2);
  context.setStrokeStyle("#F2C512");
  points.forEach((point, index) => {
    const x = timeRatio(point.time) * width;
    const y = (1 - priceRatio(point.price)) * height;
    if (index === 0) {
      context.moveTo(x, y);
    } else {
      context.lineTo(x, y);
    }
  });
  context.stroke();

  // 选点标记
  if (selected.value) {
    const x = timeRatio(selected.value.time) * width;
    const y = (1 - priceRatio(selected.value.price)) * height;
    context.beginPath();
    context.setLineWidth(1);
    context.setStrokeStyle("rgba(255,255,255,0.35)");
    context.moveTo(x, 0);
    context.lineTo(x, height);
    context.stroke();

    context.beginPath();
    context.setFillStyle("#F2C512");
    context.arc(x, y, 6, 0, Math.PI * 2);
    context.fill();
  }

  context.draw();
}

function handleTouchStart(event: unknown) {
  const touch = (event as { touches?: { clientX: number; clientY: number }[] }).touches?.[0];
  if (!touch) return;
  gestureStart.value = { x: touch.clientX, y: touch.clientY, window: { ...props.window } };
}

function handleTouchMove(event: unknown) {
  const touch = (event as { touches?: { clientX: number; clientY: number }[] }).touches?.[0];
  const start = gestureStart.value;
  if (!touch || !start) return;
  const width = uni.getSystemInfoSync().windowWidth || 1;
  // 横向拖动平移视窗，窗口宽度保持不变
  const span = start.window.end - start.window.start;
  const shift = ((start.x - touch.clientX) / width) * (props.window.end - props.window.start);
  const next = {
    start: start.window.start + shift,
    end: start.window.start + shift + span,
  };
  emit("window-change", next);
}

function handleTouchEnd() {
  gestureStart.value = null;
}

function handleTap(event: unknown) {
  const touch = (event as { changedTouches?: { clientX: number }[]; detail?: { x?: number } }).changedTouches?.[0];
  const detail = (event as { detail?: { x?: number } }).detail;
  const x = touch?.clientX ?? detail?.x;
  if (x === undefined) {
    selected.value = null;
    emit("select", null);
    return;
  }
  const width = uni.getSystemInfoSync().windowWidth || 1;
  const targetTime = props.window.start + (x / width) * (props.window.end - props.window.start);
  // 查价使用原始数据，休市与稀疏日期不插值
  const point = nearestPoint(visible.value, targetTime);
  selected.value = point;
  emit("select", point);
}

function formatPrice(price: number): string {
  const value = unscaleValue(price, props.scaleKind);
  return value.toFixed(2);
}

onMounted(draw);
watch([drawn, props.window, selected], draw, { deep: true });
</script>

<template>
  <view class="gold-chart">
    <canvas
      :canvas-id="canvasId"
      :id="canvasId"
      class="gold-chart-canvas"
      :style="{ height: `${height}px` }"
      @touchstart="handleTouchStart"
      @touchmove.stop.prevent="handleTouchMove"
      @touchend="handleTouchEnd"
      @touchcancel="handleTouchEnd"
      @tap="handleTap"
    />
    <view v-if="selected" class="gold-chart-readout">
      <text class="gold-chart-readout-price">¥{{ formatPrice(selected.price) }}</text>
      <text class="gold-chart-readout-time">{{ selected.time }}</text>
    </view>
    <text v-else class="gold-hint">轻点图表查看该时点真实报价</text>
  </view>
</template>

<style scoped>
.gold-chart {
  position: relative;
}

.gold-chart-canvas {
  width: 100%;
  display: block;
}

.gold-chart-readout {
  position: absolute;
  top: 16rpx;
  left: 16rpx;
  display: flex;
  flex-direction: column;
  gap: 4rpx;
  background: var(--gold-card);
  border: var(--gold-hairline) solid var(--gold-stroke);
  border-radius: var(--gold-radius-input);
  padding: 12rpx 20rpx;
}

.gold-chart-readout-price {
  font-size: 30rpx;
  font-weight: 700;
  color: var(--gold-accent);
}

.gold-chart-readout-time {
  font-size: 20rpx;
  color: var(--gold-muted);
}
</style>

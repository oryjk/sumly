<script setup lang="ts">
/**
 * 首页 —— 行情仪表盘。
 * 只做生命周期与事件编排，坐标变换、统计与抽样都在纯逻辑模块中。
 */
import { computed, onUnmounted, ref, watch } from "vue";
import { onHide, onShow } from "@dcloudio/uni-app";
import { useMarketStore } from "@/stores/market";
import {
  MARKET_RANGES,
  dataBounds,
  isDailyRange,
  rangeWindow,
  type MarketRange,
} from "@/domain/market/ranges";
import { windowStatistics, emptyStatistics } from "@/domain/market/statistics";
import type { ChartWindow } from "@/domain/market/viewport";
import type { ChartPoint } from "@/types/market";
import GoldTabBar from "@/components/GoldTabBar/GoldTabBar.vue";
import ChartNavigator from "./components/ChartNavigator.vue";
import GoldChart from "./components/GoldChart.vue";
import MarketSources from "./components/MarketSources.vue";
import QuoteHeader from "./components/QuoteHeader.vue";

const market = useMarketStore();

const selectedRange = ref<MarketRange>("realtime");
const manualWindow = ref<ChartWindow | null>(null);
const selectedPoint = ref<ChartPoint | null>(null);

/** 实时范围用实时窗口，其余范围用历史缓存。 */
const activePoints = computed<ChartPoint[]>(() =>
  selectedRange.value === "realtime" ? market.realtimePoints.value : market.points.value,
);

const bounds = computed(() => dataBounds(activePoints.value));

/** 视窗：用户拖动后优先用手动的，否则按范围计算。 */
const activeWindow = computed<ChartWindow | null>(() => {
  if (manualWindow.value) return manualWindow.value;
  return rangeWindow(selectedRange.value, activePoints.value, Date.now());
});

const statistics = computed(() => {
  const window = activeWindow.value;
  if (!window) return emptyStatistics();
  const visible = activePoints.value.filter(
    (point) => point.time >= window.start && point.time <= window.end,
  );
  return windowStatistics(visible) ?? emptyStatistics();
});

const statisticsRows = computed(() => {
  const stats = statistics.value;
  if (!stats.high) return [];
  return [
    { label: "最高", price: stats.high.price, time: stats.high.time },
    { label: "最低", price: stats.low?.price ?? null, time: stats.low?.time ?? null },
  ];
});

function formatPrice(value: number | null | undefined): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return "--";
  return value.toFixed(2);
}

function formatTime(value: number | null | undefined): string {
  if (value === null || value === undefined) return "";
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return "";
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${pad(parsed.getMonth() + 1)}.${pad(parsed.getDate())} ${pad(parsed.getHours())}:${pad(parsed.getMinutes())}`;
}

function trendClass(value: number | null | undefined): string {
  if (value === null || value === undefined || !Number.isFinite(value) || value === 0) return "";
  return value > 0 ? "gold-up" : "gold-down";
}

function onSelectRange(range: MarketRange) {
  selectedRange.value = range;
  // 切换范围时重置手动窗口，避免沿用上一范围的越界视窗
  manualWindow.value = null;
  selectedPoint.value = null;
}

function onWindowChange(next: ChartWindow) {
  manualWindow.value = next;
}

function onSelectPoint(point: ChartPoint | null) {
  selectedPoint.value = point;
}

function onSwitchBasis(basis: "domestic" | "international") {
  void market.switchBasis(basis);
}

function onRetry() {
  void market.refreshQuote().then(() => market.refreshRealtime());
}

// 范围或口径变化后，若手动窗口已越界则丢弃
watch([activePoints, selectedRange], () => {
  const window = manualWindow.value;
  const limit = bounds.value;
  if (!window || !limit) return;
  if (window.start < limit.start - 1 || window.end > limit.end + 1) {
    manualWindow.value = null;
  }
});

onShow(() => {
  market.start("market");
});

onHide(() => {
  market.stop("market");
});

onUnmounted(() => {
  market.stop("market");
});
</script>

<template>
  <view class="page-container page-body">
    <view class="home-header">
      <text class="home-title">记金</text>
      <text class="home-subtitle">记录你的黄金资产</text>
    </view>

    <QuoteHeader
      :quote="market.quote.value"
      :basis="market.basis.value"
      :status="market.status.value"
      :switching="market.loading.value"
      :error="market.error.value"
      @switch-basis="onSwitchBasis"
    />

    <view class="gold-card">
      <view class="range-picker">
        <scroll-view scroll-x class="range-picker-scroll" :show-scrollbar="false">
          <view class="range-picker-inner">
            <view
              v-for="item in MARKET_RANGES"
              :key="item.key"
              class="gold-capsule"
              :class="{ 'gold-capsule-active': selectedRange === item.key }"
              @tap="onSelectRange(item.key)"
            >
              {{ item.label }}
            </view>
          </view>
        </scroll-view>
      </view>

      <view v-if="!bounds" class="chart-empty">
        <text class="gold-hint">
          {{
            market.error.value
              ? `${market.error.value}`
              : selectedRange === "realtime"
                ? "暂无实时走势，请稍候或下拉重试"
                : "该品种暂无历史数据"
          }}
        </text>
        <button v-if="market.error.value" class="gold-plain-button chart-retry" @click="onRetry">
          重试
        </button>
      </view>

      <template v-else-if="activeWindow">
        <GoldChart
          :points="activePoints"
          :window="activeWindow"
          :daily="isDailyRange(selectedRange)"
          @select="onSelectPoint"
          @window-change="onWindowChange"
        />

        <view class="chart-statistics">
          <view class="chart-statistics-row">
            <text class="gold-field-label">区间涨跌</text>
            <view class="chart-statistics-values">
              <text class="chart-statistics-change" :class="trendClass(statistics.change)">
                {{ statistics.change === null ? "--" : `${statistics.change >= 0 ? "+" : ""}${formatPrice(statistics.change)}` }}
              </text>
              <text class="chart-statistics-change" :class="trendClass(statistics.percent)">
                {{ statistics.percent === null ? "--" : `${statistics.percent >= 0 ? "+" : ""}${formatPrice(statistics.percent)}%` }}
              </text>
            </view>
          </view>
          <view v-for="row in statisticsRows" :key="row.label" class="chart-statistics-row">
            <text class="gold-field-label">{{ row.label }}</text>
            <text class="chart-statistics-extreme">
              {{ formatPrice(row.price) }}
              <text class="chart-statistics-time">{{ formatTime(row.time) }}</text>
            </text>
          </view>
        </view>

        <ChartNavigator
          :points="activePoints"
          :bounds="bounds"
          :window="activeWindow"
          @window-change="onWindowChange"
        />
      </template>
    </view>

    <view class="gold-card">
      <text class="gold-card-title">数据说明</text>
      <MarketSources :basis="market.basis.value" :quote="market.quote.value" />
    </view>

    <view class="gold-card">
      <text class="gold-card-title">首页订阅</text>
      <text class="gold-hint">金价订阅提醒暂未开放，请到持仓详情页设置持仓目标提醒。</text>
    </view>

    <GoldTabBar active="market" />
  </view>
</template>

<style scoped>
.home-header {
  padding: 48rpx 0 8rpx;
}

.home-title {
  display: block;
  font-size: 52rpx;
  font-weight: 800;
  color: var(--gold-ink);
  letter-spacing: 2rpx;
}

.home-subtitle {
  display: block;
  margin-top: 8rpx;
  font-size: 26rpx;
  color: var(--gold-muted);
}

.range-picker {
  margin-bottom: 24rpx;
}

.range-picker-scroll {
  white-space: nowrap;
}

.range-picker-inner {
  display: inline-flex;
  gap: 12rpx;
  padding-bottom: 8rpx;
}

.chart-empty {
  padding: 64rpx 0;
  text-align: center;
}

.chart-retry {
  margin-top: 24rpx;
}

.chart-statistics {
  margin-top: 24rpx;
  border-top: var(--gold-hairline) solid var(--gold-stroke);
  padding-top: 16rpx;
}

.chart-statistics-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 10rpx 0;
}

.chart-statistics-values {
  display: flex;
  gap: 20rpx;
}

.chart-statistics-change {
  font-size: 28rpx;
  font-weight: 700;
}

.chart-statistics-extreme {
  font-size: 26rpx;
  color: var(--gold-ink);
  font-weight: 600;
}

.chart-statistics-time {
  font-size: 20rpx;
  color: var(--gold-faint);
  margin-left: 12rpx;
  font-weight: 400;
}

.gold-up {
  color: var(--gold-up);
}

.gold-down {
  color: var(--gold-down);
}
</style>

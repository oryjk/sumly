<script setup lang="ts">
/**
 * 记金日历：日/月/年/全部切换，购入与赠卖事件按各���日期归属。
 * 拆分持仓共享购入编号，购入件数不会因赠卖而增加。
 */
import { computed, ref } from "vue";
import { onShow as onPageShow } from "@dcloudio/uni-app";
import { useHoldingsStore } from "@/stores/holdings";
import { calendarEvents, calendarSummary, selectCalendarEvents, type CalendarPeriod } from "@/domain/holdings/calendar";
import { formatGrams, formatMoney } from "@/domain/holdings/presentation";
import GoldTabBar from "@/components/GoldTabBar/GoldTabBar.vue";

const holdings = useHoldingsStore();

const period = ref<CalendarPeriod>("month");
const anchor = ref(Date.now());
const keyword = ref("");
const kind = ref("all");
const book = ref<string | null>(null);
const hidden = ref(false);

const PERIODS: { key: CalendarPeriod; label: string }[] = [
  { key: "day", label: "日" },
  { key: "month", label: "月" },
  { key: "year", label: "年" },
  { key: "all", label: "全部" },
];

const allEvents = computed(() =>
  calendarEvents(holdings.document.value.records, {
    keyword: keyword.value,
    kind: kind.value,
    book: book.value,
  }),
);

const events = computed(() => selectCalendarEvents(allEvents.value, period.value, anchor.value));

const holdingGrams = computed(() =>
  holdings.document.value.records
    .filter((record) => record.disposition === "holding")
    .reduce((sum, record) => sum + record.grams, 0),
);

const summary = computed(() => calendarSummary(allEvents.value, holdingGrams.value, null));

const periodText = computed(() => {
  const date = new Date(anchor.value);
  const pad = (n: number) => String(n).padStart(2, "0");
  if (period.value === "year") return `${date.getFullYear()}年`;
  if (period.value === "all") return "全部时间";
  return `${date.getFullYear()}.${pad(date.getMonth() + 1)}`;
});

/** 当月每一天，按当前周期的锚点定位。 */
const dayMarks = computed(() => {
  if (period.value !== "month") return [];
  const date = new Date(anchor.value);
  const year = date.getFullYear();
  const month = date.getMonth();
  const days = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
  const marks: { day: number; count: number }[] = [];
  for (let day = 1; day <= days; day += 1) {
    const start = Date.UTC(year, month, day);
    const end = Date.UTC(year, month, day + 1);
    const count = allEvents.value.filter((event) => event.date >= start && event.date < end).length;
    marks.push({ day, count });
  }
  return marks;
});

const KINDS = [
  { key: "all", label: "全部" },
  { key: "holding", label: "购入" },
  { key: "sold", label: "卖出" },
  { key: "gift", label: "赠送" },
];

function shiftPeriod(step: number) {
  const date = new Date(anchor.value);
  if (period.value === "month") {
    date.setUTCMonth(date.getUTCMonth() + step);
  } else if (period.value === "year") {
    date.setUTCFullYear(date.getUTCFullYear() + step);
  } else {
    return;
  }
  anchor.value = date.getTime();
}

function onDaySelect(day: number) {
  const date = new Date(anchor.value);
  anchor.value = Date.UTC(date.getFullYear(), date.getMonth(), day).valueOf();
  period.value = "day";
}

function readValue(event: unknown): string {
  return (event as { detail?: { value?: string } })?.detail?.value ?? "";
}

function eventLabel(kindValue: string): string {
  return kindValue === "buy" ? "购入" : kindValue === "sold" ? "卖出" : "赠送";
}

onPageShow(() => {
  holdings.openWorkspace("guest");
});
</script>

<template>
  <view class="page-container page-body">
    <view class="gold-card">
      <view class="calendar-head">
        <text class="calendar-period" @tap="shiftPeriod(-1)">‹</text>
        <text class="calendar-period-title">{{ periodText }}</text>
        <text class="calendar-period" @tap="shiftPeriod(1)">›</text>
      </view>
      <view class="calendar-periods">
        <view
          v-for="item in PERIODS"
          :key="item.key"
          class="gold-capsule"
          :class="{ 'gold-capsule-active': period === item.key }"
          @tap="period = item.key"
        >
          {{ item.label }}
        </view>
      </view>
    </view>

    <view v-if="period === 'month'" class="gold-card">
      <view class="calendar-days">
        <view
          v-for="mark in dayMarks"
          :key="mark.day"
          class="calendar-day"
          :class="{ 'calendar-day-active': new Date(anchor).getDate() === mark.day }"
          @tap="onDaySelect(mark.day)"
        >
          <text class="calendar-day-text">{{ mark.day }}</text>
          <view v-if="mark.count > 0" class="calendar-day-dot" />
        </view>
      </view>
    </view>

    <view class="gold-card">
      <input
        class="calendar-search"
        :value="keyword"
        placeholder="搜索品牌、备注或交易方"
        placeholder-class="calendar-placeholder"
        @input="keyword = readValue($event)"
      />
      <view class="calendar-kinds">
        <view
          v-for="item in KINDS"
          :key="item.key"
          class="gold-capsule"
          :class="{ 'gold-capsule-active': kind === item.key }"
          @tap="kind = item.key"
        >
          {{ item.label }}
        </view>
        <text class="gold-capsule" @tap="hidden = !hidden">{{ hidden ? "显示" : "隐藏" }}</text>
      </view>
    </view>

    <view class="gold-card">
      <text class="gold-card-title">区间统计</text>
      <view class="gold-field-row">
        <text class="gold-field-label">购入 {{ summary.purchases.count }} 笔</text>
        <text class="gold-field-value">{{ formatMoney(summary.purchases.cost, hidden) }}</text>
      </view>
      <view class="gold-field-row">
        <text class="gold-field-label">卖出 {{ summary.sales.count }} 笔</text>
        <text class="gold-field-value">{{ formatMoney(summary.sales.proceeds, hidden) }}</text>
      </view>
      <view class="gold-field-row">
        <text class="gold-field-label">赠送 {{ summary.gifts.count }} 笔</text>
        <text class="gold-field-value">{{ formatGrams(summary.gifts.grams, hidden) }}</text>
      </view>
    </view>

    <view v-if="events.length === 0" class="calendar-empty">
      <text class="gold-hint">该区间没有记录。</text>
    </view>

    <view v-else class="gold-card">
      <text class="gold-card-title">记录 {{ events.length }} 条</text>
      <view v-for="event in events" :key="event.id" class="calendar-event">
        <view class="calendar-event-head">
          <text class="calendar-event-kind">{{ eventLabel(event.kind) }}</text>
          <text class="calendar-event-title">{{ event.title }}</text>
        </view>
        <view class="gold-field-row">
          <text class="gold-field-label">克数</text>
          <text class="gold-field-value">{{ formatGrams(event.grams, hidden) }}</text>
        </view>
        <view class="gold-field-row">
          <text class="gold-field-label">{{ event.kind === "buy" ? "总投入" : "实际到手" }}</text>
          <text class="gold-field-value">
            {{ formatMoney(event.kind === "buy" ? event.cost : event.proceeds, hidden) }}
          </text>
        </view>
      </view>
    </view>

    <GoldTabBar active="holdings" add-enabled />
  </view>
</template>

<style scoped>
.calendar-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 16rpx;
}

.calendar-period {
  font-size: 40rpx;
  color: var(--gold-accent);
  padding: 0 24rpx;
}

.calendar-period-title {
  font-size: 32rpx;
  font-weight: 700;
  color: var(--gold-ink);
}

.calendar-periods {
  display: flex;
  gap: 12rpx;
}

.calendar-days {
  display: flex;
  flex-wrap: wrap;
}

.calendar-day {
  width: 14.28%;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4rpx;
  padding: 10rpx 0;
  border-radius: var(--gold-radius-range);
}

.calendar-day-active {
  background: var(--gold-cell);
}

.calendar-day-text {
  font-size: 22rpx;
  color: var(--gold-muted);
}

.calendar-day-dot {
  width: 8rpx;
  height: 8rpx;
  border-radius: 50%;
  background: var(--gold-accent);
}

.calendar-search {
  height: var(--gold-input-h);
  background: var(--gold-cell);
  border: var(--gold-hairline) solid var(--gold-stroke);
  border-radius: var(--gold-radius-input);
  padding: 0 24rpx;
  font-size: 28rpx;
  color: var(--gold-ink);
}

.calendar-placeholder {
  color: var(--gold-faint);
}

.calendar-kinds {
  display: flex;
  flex-wrap: wrap;
  gap: 12rpx;
  margin-top: 16rpx;
}

.calendar-event {
  padding: 16rpx 0;
  border-bottom: var(--gold-hairline) solid var(--gold-stroke);
}

.calendar-event-head {
  display: flex;
  align-items: baseline;
  gap: 12rpx;
  margin-bottom: 8rpx;
}

.calendar-event-kind {
  font-size: 22rpx;
  color: var(--gold-accent);
  padding: 2rpx 12rpx;
  border-radius: var(--gold-radius-range);
  background: var(--gold-cell);
}

.calendar-event-title {
  font-size: 28rpx;
  font-weight: 600;
  color: var(--gold-ink);
}

.calendar-empty {
  padding: 80rpx 0;
  text-align: center;
}
</style>

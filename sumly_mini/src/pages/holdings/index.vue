<script setup lang="ts">
/**
 * 持仓页 —— 总览、账本切换、搜索筛选排序、批量操作与部分赠卖。
 * 页面只做编排；成本与盈亏计算都在 domain 层，持久化由 store 负责。
 */
import { computed, ref } from "vue";
import { onHide, onShow } from "@dcloudio/uni-app";
import { useHoldingsStore } from "@/stores/holdings";
import { useMarketStore } from "@/stores/market";
import { useHoldingAlerts } from "@/stores/holdingAlerts";
import { getSession } from "@/utils/sessionBridge";
import { selectHoldings, type HoldingFilter, type HoldingSort } from "@/domain/holdings/selection";
import { returnInput } from "@/domain/holdings/returns";
import { aggregateReturn } from "@/domain/holdings/returns";
import { formatGrams, formatMoney, formatPercent, formatSignedMoney } from "@/domain/holdings/presentation";
import type { HoldingDisposition, HoldingRecord } from "@/types/holdings";
import GoldTabBar from "@/components/GoldTabBar/GoldTabBar.vue";
import DisposeHolding from "./components/DisposeHolding.vue";
import HoldingCard from "./components/HoldingCard.vue";

const holdings = useHoldingsStore();
const market = useMarketStore();
const alerts = useHoldingAlerts();
const session = getSession();

const book = ref("");
const search = ref("");
const filter = ref<HoldingFilter>("all");
const sort = ref<HoldingSort>("newest");
const hidden = ref(false);
const selectionMode = ref(false);
const selectedIds = ref<string[]>([]);
const disposalTarget = ref<HoldingRecord | null>(null);
const newBookName = ref("");
const showBookInput = ref(false);

/** 当前报价（元/克），与收益计算共用同一口径。 */
const price = computed(() => market.quote.value?.cny_per_gram ?? null);

const FILTERS: { key: HoldingFilter; label: string }[] = [
  { key: "all", label: "全部" },
  { key: "profit", label: "盈利" },
  { key: "loss", label: "亏损" },
];

const SORTS: { key: HoldingSort; label: string }[] = [
  { key: "newest", label: "时间↓" },
  { key: "oldest", label: "时间↑" },
  { key: "heaviest", label: "重量↓" },
  { key: "costliest", label: "总价↓" },
];

const visible = computed(() =>
  selectHoldings(holdings.document.value.records, {
    book: book.value,
    search: search.value,
    filter: filter.value,
    sort: sort.value,
    price: price.value,
  }),
);

/** 总览基于当前账本的持有记录，隐藏时金额用占位符。 */
const overview = computed(() => {
  const holding = holdings.document.value.records.filter(
    (record) => record.disposition === "holding" && (!book.value || record.bookName === book.value),
  );
  return aggregateReturn(holding.map(returnInput), price.value);
});

const books = computed(() => holdings.document.value.books);

const trendClass = computed(() => {
  const profit = overview.value?.profit;
  if (profit === null || profit === undefined || profit === 0) return "";
  return profit > 0 ? "gold-up" : "gold-down";
});

function readValue(event: unknown): string {
  return (event as { detail?: { value?: string } })?.detail?.value ?? "";
}

function onBookNameInput(event: unknown) {
  newBookName.value = readValue(event);
}

function onSearchInput(event: unknown) {
  search.value = readValue(event);
}

function openDisposal(id: string) {
  if (selectionMode.value) {
    toggleSelect(id);
    return;
  }
  disposalTarget.value =
    holdings.document.value.records.find((record) => record.id === id) ?? null;
}

function openCalendar() {
  uni.navigateTo({ url: "/pages/holdings/calendar" });
}

function openCalculator() {
  uni.navigateTo({ url: "/pages/holdings/calculator" });
}

function openDetail(id: string) {
  uni.navigateTo({ url: `/pages/holdings/detail?id=${id}` });
}

function isSelected(id: string): boolean {
  return selectedIds.value.some((item) => item.toLowerCase() === id.toLowerCase());
}

function toggleSelect(id: string) {
  selectedIds.value = isSelected(id)
    ? selectedIds.value.filter((item) => item.toLowerCase() !== id.toLowerCase())
    : [...selectedIds.value, id];
}

function toggleSelectAll() {
  const ids = visible.value.map((record) => record.id);
  const allSelected = ids.every(isSelected);
  selectedIds.value = allSelected ? [] : ids;
}

function exitSelection() {
  selectionMode.value = false;
  selectedIds.value = [];
}

function confirmDelete() {
  if (selectedIds.value.length === 0) return;
  const count = selectedIds.value.length;
  uni.showModal({
    title: "删除持仓",
    content: `将删除 ${count} 条记录，关联的赠卖记录也会一并删除。`,
    confirmText: "删除",
    confirmColor: "#FF5D5D",
    success: (result) => {
      if (!result.confirm) return;
      if (!holdings.deleteRecords(selectedIds.value)) {
        uni.showToast({ title: holdings.saveError.value ?? "删除失败", icon: "none" });
        return;
      }
      exitSelection();
      uni.showToast({ title: "已删除", icon: "success" });
    },
  });
}

function moveSelected() {
  if (selectedIds.value.length === 0 || !book.value) return;
  if (holdings.moveRecords(selectedIds.value, book.value)) {
    exitSelection();
    uni.showToast({ title: "已迁移", icon: "success" });
  } else {
    uni.showToast({ title: holdings.saveError.value ?? "迁移失败", icon: "none" });
  }
}

function createBook() {
  const name = newBookName.value.trim();
  if (!name) return;
  if (holdings.addBook(name)) {
    book.value = name;
    newBookName.value = "";
    showBookInput.value = false;
  } else {
    uni.showToast({ title: holdings.saveError.value ?? "创建失败", icon: "none" });
  }
}

function submitDisposal(payload: {
  grams: number;
  proceeds: number;
  kind: HoldingDisposition;
  disposedAt: number;
  counterparty: string;
}) {
  const target = disposalTarget.value;
  if (!target) return;
  const ok = holdings.dispose(
    target.id,
    payload.grams,
    payload.proceeds,
    payload.kind,
    payload.disposedAt,
    payload.counterparty,
    Date.now(),
  );
  if (!ok) {
    uni.showToast({ title: holdings.saveError.value ?? "处置失败", icon: "none" });
    return;
  }
  disposalTarget.value = null;
  uni.showToast({ title: payload.kind === "sold" ? "已记录卖出" : "已记录赠送", icon: "success" });
}

/** 提醒只在持仓页前台监测，与 App 保持一致。 */
function runAlertMonitor() {
  const quote = market.quote.value;
  if (!quote) return;
  const now = Date.now();
  alerts.setWorkspace(holdings.workspace.value.key);
  alerts.evaluate(holdings.document.value.records, quote.cny_per_gram, now, now);
  // 送达确认：前台反馈已展示即视为本地已送达
  for (const event of alerts.pending.value) {
    alerts.acknowledge(event.id, "delivered");
  }
}

let alertTimer: ReturnType<typeof setInterval> | null = null;

onShow(() => {
  const userID = session.currentUser.value?.id;
  holdings.openWorkspace(userID === undefined ? "guest" : `user:${userID}`);
  market.start("holdings");
  alerts.setWorkspace(holdings.workspace.value.key);
  alerts.start("holdings");
  // 前台每 3 秒检查一次
  if (alertTimer) clearInterval(alertTimer);
  runAlertMonitor();
  alertTimer = setInterval(runAlertMonitor, 3000);
});

onHide(() => {
  market.stop("holdings");
  alerts.stop("holdings");
  if (alertTimer) {
    clearInterval(alertTimer);
    alertTimer = null;
  }
});
</script>

<template>
  <view class="page-container page-body">
    <view class="gold-card holdings-overview">
      <text class="gold-card-title">持仓总览</text>
      <view class="holdings-overview-row">
        <text class="holdings-overview-label">预计到手</text>
        <text class="holdings-overview-value">
          {{ formatMoney(overview?.proceeds ?? null, hidden) }}
        </text>
      </view>
      <view class="holdings-overview-row">
        <text class="holdings-overview-label">真实盈亏</text>
        <text class="holdings-overview-profit" :class="trendClass">
          {{ formatSignedMoney(overview?.profit ?? null, hidden) }}
          <text class="holdings-overview-percent">{{ formatPercent(overview?.profitPercent, hidden) }}</text>
        </text>
      </view>
      <view class="holdings-overview-row">
        <text class="holdings-overview-label">总重量 / 投入</text>
        <text class="holdings-overview-value">
          {{ formatGrams(overview?.grams ?? null, hidden) }} ·
          {{ formatMoney(overview?.totalCost ?? null, hidden) }}
        </text>
      </view>
      <view v-if="overview?.breakEvenPrice" class="holdings-overview-row">
        <text class="holdings-overview-label">保本价</text>
        <text class="holdings-overview-value">{{ formatMoney(overview.breakEvenPrice, hidden) }} 元/克</text>
      </view>
    </view>

    <view class="holdings-toolbar">
      <scroll-view scroll-x class="holdings-books" :show-scrollbar="false">
        <view class="holdings-books-inner">
          <view
            class="gold-capsule"
            :class="{ 'gold-capsule-active': book === '' }"
            @tap="book = ''"
          >
            全部
          </view>
          <view
            v-for="item in books"
            :key="item"
            class="gold-capsule"
            :class="{ 'gold-capsule-active': book === item }"
            @tap="book = item"
          >
            {{ item }}
          </view>
          <view class="gold-capsule holdings-book-add" @tap="showBookInput = true">＋ 新建</view>
        </view>
      </scroll-view>
    </view>

    <view v-if="showBookInput" class="gold-card holdings-book-create">
      <input
        class="holdings-book-input"
        :value="newBookName"
        placeholder="账本名称"
        placeholder-class="holdings-book-placeholder"
        @input="onBookNameInput"
      />
      <view class="holdings-book-actions">
        <button class="gold-plain-button holdings-book-action" @tap="showBookInput = false">取消</button>
        <button class="gold-primary-button holdings-book-action" @tap="createBook">创建</button>
      </view>
    </view>

    <view class="gold-card">
      <view class="holdings-search">
        <input
          class="holdings-search-field"
          :value="search"
          placeholder="搜索品牌或备注"
          placeholder-class="holdings-book-placeholder"
          @input="onSearchInput"
        />
        <view class="holdings-hide" @tap="hidden = !hidden">
          <text class="gold-capsule" :class="{ 'gold-capsule-active': hidden }">
            {{ hidden ? "已隐藏" : "隐藏金额" }}
          </text>
        </view>
      </view>

      <view class="holdings-filters">
        <view
          v-for="item in FILTERS"
          :key="item.key"
          class="gold-capsule"
          :class="{ 'gold-capsule-active': filter === item.key }"
          @tap="filter = item.key"
        >
          {{ item.label }}
        </view>
        <view
          v-for="item in SORTS"
          :key="item.key"
          class="gold-capsule holdings-sort"
          :class="{ 'gold-capsule-active': sort === item.key }"
          @tap="sort = item.key"
        >
          {{ item.label }}
        </view>
      </view>
    </view>

    <view v-if="selectionMode" class="gold-card holdings-batch">
      <view class="holdings-batch-row">
        <text class="gold-field-label">已选 {{ selectedIds.length }} 条</text>
        <text class="holdings-batch-all" @tap="toggleSelectAll">全选可见</text>
      </view>
      <view class="holdings-batch-actions">
        <button class="gold-plain-button holdings-batch-action" @tap="moveSelected">迁移到当前账本</button>
        <button class="gold-plain-button holdings-batch-action" @tap="confirmDelete">删除</button>
      </view>
    </view>

    <view class="holdings-entries">
      <view class="gold-capsule" @tap="openCalendar">记金日历</view>
      <view class="gold-capsule" @tap="openCalculator">买前计算器</view>
    </view>

    <view v-if="holdings.saveError.value" class="holdings-error">
      <text class="gold-hint gold-error">{{ holdings.saveError.value }}</text>
    </view>

    <view v-if="visible.length === 0" class="holdings-empty">
      <text class="gold-hint">
        {{
          holdings.document.value.records.length === 0
            ? "还没有持仓记录，点击下方加号开始记金。"
            : "当前筛选条件下没有记录。"
        }}
      </text>
    </view>

    <view v-else>
      <view v-if="!selectionMode" class="holdings-select-hint" @tap="selectionMode = true">
        <text class="gold-hint">轻点卡片查看详情，长按可进入批量操作</text>
      </view>
      <HoldingCard
        v-for="record in visible"
        :key="record.id"
        :record="record"
        :price="price"
        :hidden="hidden"
        :selected="isSelected(record.id)"
        @select="toggleSelect"
        @detail="selectionMode ? toggleSelect($event) : openDetail($event)"
        @dispose="openDisposal"
      />
    </view>

    <DisposeHolding
      :record="disposalTarget"
      :now="Date.now()"
      @cancel="disposalTarget = null"
      @submit="submitDisposal"
    />

    <GoldTabBar active="holdings" add-enabled />
  </view>
</template>

<style scoped>
.holdings-overview-row {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  padding: 12rpx 0;
}

.holdings-overview-label {
  font-size: 26rpx;
  color: var(--gold-muted);
}

.holdings-overview-value {
  font-size: 30rpx;
  font-weight: 600;
  color: var(--gold-ink);
}

.holdings-overview-profit {
  font-size: 32rpx;
  font-weight: 700;
}

.holdings-overview-percent {
  font-size: 22rpx;
  font-weight: 400;
  margin-left: 10rpx;
}

.holdings-entries {
  display: flex;
  gap: 12rpx;
  margin-bottom: 16rpx;
}

.holdings-toolbar {
  margin-bottom: 16rpx;
}

.holdings-books-inner {
  display: inline-flex;
  gap: 12rpx;
  padding-bottom: 8rpx;
}

.holdings-book-create {
  display: flex;
  flex-direction: column;
  gap: 16rpx;
}

.holdings-book-input,
.holdings-search-field {
  height: var(--gold-input-h);
  background: var(--gold-cell);
  border: var(--gold-hairline) solid var(--gold-stroke);
  border-radius: var(--gold-radius-input);
  padding: 0 24rpx;
  font-size: 28rpx;
  color: var(--gold-ink);
}

.holdings-book-placeholder {
  color: var(--gold-faint);
}

.holdings-book-actions {
  display: flex;
  gap: 16rpx;
}

.holdings-book-action {
  flex: 1;
  margin: 0;
  padding: 18rpx 0;
  font-size: 28rpx;
}

.holdings-search {
  display: flex;
  align-items: center;
  gap: 16rpx;
}

.holdings-search-field {
  flex: 1;
}

.holdings-filters {
  display: flex;
  flex-wrap: wrap;
  gap: 12rpx;
  margin-top: 20rpx;
}

.holdings-sort {
  margin-left: auto;
}

.holdings-batch-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.holdings-batch-all {
  font-size: 26rpx;
  color: var(--gold-accent);
}

.holdings-batch-actions {
  display: flex;
  gap: 16rpx;
  margin-top: 20rpx;
}

.holdings-batch-action {
  flex: 1;
  margin: 0;
  padding: 18rpx 0;
  font-size: 26rpx;
}

.holdings-select-hint {
  margin-bottom: 8rpx;
}

.holdings-empty {
  padding: 80rpx 0;
  text-align: center;
}

.holdings-error {
  margin-bottom: 16rpx;
}

.gold-up {
  color: var(--gold-up);
}

.gold-down {
  color: var(--gold-down);
}

.gold-error {
  color: var(--gold-up);
}
</style>

<script setup lang="ts">
/**
 * 添加 / 编辑持仓。
 *
 * 关键约束：
 * - 选历史日期只用该交易日收盘价，休市显示缺失，不用现价顶替；
 * - 用户手动输入价格后，晚到的异步响应不得覆盖（由 purchaseReference 代际保护）；
 * - 编辑保留原 id、创建时间、账本与处置关联。
 */
import { computed, ref } from "vue";
import { onLoad } from "@dcloudio/uni-app";
import { createDraft, draftFromRecord, draftToRecord } from "@/domain/holdings/draft";
import { calculateReturn } from "@/domain/holdings/returns";
import { formatMoney } from "@/domain/holdings/presentation";
import { useHoldingsStore } from "@/stores/holdings";
import { useMarketStore } from "@/stores/market";
import { createPurchaseReference } from "@/stores/purchaseReference";
import { GRAMS_PER_TROY_OUNCE } from "@/types/market";
import type { HoldingRecord } from "@/types/holdings";
import PurchaseFields from "./components/PurchaseFields.vue";
import RecoveryFields from "./components/RecoveryFields.vue";

const holdings = useHoldingsStore();
const market = useMarketStore();

const draft = ref(createDraft());
const existing = ref<HoldingRecord | null>(null);
const selectedDay = ref(Date.now());
const showDayPicker = ref(false);
const saving = ref(false);

const ASSET_TYPES = ["金饰", "金条", "积存金", "其他"];

const price = computed(() => market.quote.value?.cny_per_gram ?? null);

/** 参考价模型：手动输入与异步响应隔离由它内部保证。 */
const reference = createPurchaseReference({
  basis: "international",
  now: () => Date.now(),
  getCachedDaily: async () => null,
  getDaily: async () => {
    // 从已折算的历史点反推原始 USD/oz 收盘价，保持与 App 相同的折算口径
    const rate = market.quote.value?.usd_cny ?? 0;
    if (rate <= 0) return [];
    const factor = GRAMS_PER_TROY_OUNCE / rate;
    return market.points.value
      .filter((point) => point.source !== "usgs")
      .map((point) => ({
        date: new Date(point.time).toISOString().slice(0, 10),
        close: point.price * factor,
      }));
  },
  getQuote: async () => {
    const quote = market.quote.value;
    if (!quote) throw new Error("暂无报价");
    return { cny_per_gram: quote.cny_per_gram, usd_cny: quote.usd_cny };
  },
  getCachedQuote: async () => {
    const quote = market.quote.value;
    return quote ? { cny_per_gram: quote.cny_per_gram, usd_cny: quote.usd_cny } : null;
  },
});

/** 收益试算，输入非法时为 null。 */
const preview = computed(() => {
  const input = draft.value.input();
  if (!input) return null;
  return calculateReturn(input, price.value);
});

const canSave = computed(() => draft.value.input() !== null && !saving.value);

const referenceHint = computed(() => {
  if (reference.issue.value === "missingDay") return "该日期休市或无收盘价，请手动填写买入价";
  if (reference.issue.value === "missingExchangeRate") return "缺少有效汇率，无法折算国际历史价，请手动填写";
  if (reference.issue.value === "unavailable") return "参考价暂不可用，可手动填写";
  if (reference.loading.value) return "正在获取参考价…";
  const value = reference.reference.value;
  if (!value) return "";
  return value.historical
    ? `参考价 ${formatMoney(value.price, false)} 元/克（${value.historical ? "该交易日收盘价折算" : ""}）`
    : `参考价 ${formatMoney(value.price, false)} 元/克（当前报价）`;
});

function readValue(event: unknown): string {
  return (event as { detail?: { value?: string } })?.detail?.value ?? "";
}

function onPriceInput(event: unknown) {
  reference.editPrice(readValue(event));
}

function onBrandInput(event: unknown) {
  draft.value.brand = readValue(event);
}

function onChannelInput(event: unknown) {
  draft.value.channel = readValue(event);
}

function onNoteInput(event: unknown) {
  draft.value.note = readValue(event);
}

function setAssetType(value: string) {
  draft.value.assetType = value;
}

function onDayChange(event: unknown) {
  const value = Number(readValue(event));
  if (!Number.isFinite(value)) return;
  selectedDay.value = value;
  void reference.selectDate(value);
  showDayPicker.value = false;
  void reference.load(Date.now());
}

function loadReference() {
  void reference.selectDate(selectedDay.value);
  void reference.load(Date.now());
}

function useReferencePrice() {
  reference.useReference();
  draft.value.priceText = reference.priceText.value;
}

function save() {
  if (saving.value) return;
  const input = draft.value.input();
  if (!input) {
    uni.showToast({ title: "请检查表单填写", icon: "none" });
    return;
  }
  saving.value = true;
  try {
    const record = draftToRecord(draft.value, existing.value, Date.now());
    record.timestamp = selectedDay.value;
    const ok = holdings.mutate((current) => {
      const exists = current.records.some((item) => item.id === record.id);
      return {
        ...current,
        books: current.books.includes(record.bookName) ? current.books : [...current.books, record.bookName],
        records: exists
          ? current.records.map((item) => (item.id === record.id ? record : item))
          : [...current.records, record],
      };
    });
    if (!ok) {
      uni.showToast({ title: holdings.saveError.value ?? "保存失败", icon: "none" });
      return;
    }
    uni.showToast({ title: "已保存", icon: "success" });
    setTimeout(() => uni.navigateBack(), 600);
  } finally {
    saving.value = false;
  }
}

onLoad((options) => {
  holdings.openWorkspace("guest");
  market.start("market");

  const id = options?.id;
  if (typeof id === "string" && id) {
    const found = holdings.document.value.records.find((item) => item.id === id);
    if (found) {
      existing.value = found;
      draft.value = draftFromRecord(found);
      selectedDay.value = found.timestamp;
      reference.editPrice(String(found.unitPriceCNY));
    }
  } else {
    loadReference();
  }
});
</script>

<template>
  <view class="page-container edit-page">
    <text class="edit-page-title">{{ existing ? "编辑持仓" : "添加黄金" }}</text>

    <view class="gold-card">
      <text class="gold-card-title">基本信息</text>
      <view class="edit-types">
        <view
          v-for="item in ASSET_TYPES"
          :key="item"
          class="gold-capsule"
          :class="{ 'gold-capsule-active': draft.assetType === item }"
          @tap="setAssetType(item)"
        >
          {{ item }}
        </view>
      </view>

      <view class="edit-row">
        <text class="edit-label">品牌</text>
        <input
          class="edit-input"
          :value="draft.brand"
          placeholder="选填"
          placeholder-class="edit-placeholder"
          @input="onBrandInput"
        />
      </view>
      <view class="edit-row">
        <text class="edit-label">渠道</text>
        <input
          class="edit-input"
          :value="draft.channel"
          placeholder="选填"
          placeholder-class="edit-placeholder"
          @input="onChannelInput"
        />
      </view>
      <view class="edit-row">
        <text class="edit-label">备注</text>
        <input
          class="edit-input"
          :value="draft.note"
          placeholder="选填"
          placeholder-class="edit-placeholder"
          @input="onNoteInput"
        />
      </view>
    </view>

    <view class="gold-card">
      <text class="gold-card-title">购入信息</text>
      <view class="edit-row" @tap="showDayPicker = true">
        <text class="edit-label">购入日期</text>
        <text class="edit-value">{{ new Date(selectedDay).toISOString().slice(0, 10) }}</text>
      </view>
      <picker v-if="showDayPicker" mode="date" :value="new Date(selectedDay).toISOString().slice(0, 10)" @change="onDayChange">
        <view class="edit-picker">选择日期</view>
      </picker>

      <view class="edit-row">
        <text class="edit-label">买入价</text>
        <view class="edit-input-group">
          <input
            class="edit-input edit-input-narrow"
            type="digit"
            :value="draft.priceText"
            placeholder="0.00"
            placeholder-class="edit-placeholder"
            @input="onPriceInput"
          />
          <text class="edit-suffix">元/克</text>
        </view>
      </view>
      <text v-if="referenceHint" class="gold-hint">{{ referenceHint }}</text>
      <button
        v-if="reference.reference.value"
        class="edit-reference-button"
        @click="useReferencePrice"
      >
        使用参考价
      </button>

      <PurchaseFields :draft="draft" />
    </view>

    <view class="gold-card">
      <text class="gold-card-title">回收参数</text>
      <RecoveryFields :draft="draft" />
    </view>

    <view v-if="preview" class="gold-card">
      <text class="gold-card-title">收益试算</text>
      <view class="edit-row">
        <text class="edit-label">预计到手</text>
        <text class="edit-value">{{ formatMoney(preview.proceeds, false) }}</text>
      </view>
      <view class="edit-row">
        <text class="edit-label">真实盈亏</text>
        <text class="edit-value">{{ formatMoney(preview.profit, false, true) }}</text>
      </view>
      <view class="edit-row">
        <text class="edit-label">保本价</text>
        <text class="edit-value">{{ formatMoney(preview.breakEvenPrice, false) }} 元/克</text>
      </view>
    </view>

    <button class="gold-primary-button edit-save" :disabled="!canSave" @tap="save">
      {{ saving ? "保存中…" : "保存" }}
    </button>
  </view>
</template>

<style scoped>
.edit-page {
  padding-bottom: 64rpx;
}

.edit-page-title {
  display: block;
  font-size: 40rpx;
  font-weight: 800;
  color: var(--gold-ink);
  padding: 32rpx 0 24rpx;
}

.edit-types {
  display: flex;
  flex-wrap: wrap;
  gap: 12rpx;
  margin-bottom: 16rpx;
}

.edit-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 14rpx 0;
}

.edit-label {
  font-size: 28rpx;
  color: var(--gold-muted);
  flex-shrink: 0;
  margin-right: 20rpx;
}

.edit-input {
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

.edit-input-narrow {
  max-width: 200rpx;
}

.edit-input-group {
  display: flex;
  align-items: center;
  gap: 12rpx;
  flex: 1;
  justify-content: flex-end;
}

.edit-value {
  font-size: 28rpx;
  color: var(--gold-ink);
  font-weight: 600;
}

.edit-suffix {
  font-size: 24rpx;
  color: var(--gold-faint);
}

.edit-placeholder {
  color: var(--gold-faint);
}

.edit-picker {
  font-size: 26rpx;
  color: var(--gold-accent);
  padding: 12rpx 0;
}

.edit-reference-button {
  display: inline-block;
  font-size: 24rpx;
  color: var(--gold-accent);
  padding: 12rpx 0;
  margin: 0;
  background: transparent;
  line-height: 1.4;
}

.edit-save {
  margin-top: 32rpx;
}
</style>

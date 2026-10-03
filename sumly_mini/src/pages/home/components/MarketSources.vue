<script setup lang="ts">
/**
 * MarketSources —— 行情来源与换算说明。
 * 国际历史价按最新有效汇率折算，不是历史人民币成交价，必须明确标注。
 */
import { computed } from "vue";
import type { GoldQuote, MarketBasis } from "@/types/market";

const props = defineProps<{
  basis: MarketBasis;
  quote: GoldQuote | null;
}>();

const sourceName = computed(() => {
  const instrument = props.quote?.instrument;
  if (instrument) return instrument.name;
  return props.basis === "domestic" ? "上海黄金交易所 Au99.99" : "伦敦金（XAU/USD）";
});
</script>

<template>
  <view class="market-sources">
    <view class="gold-field-row">
      <text class="gold-field-label">数据来源</text>
      <text class="gold-field-value">{{ sourceName }}</text>
    </view>
    <view v-if="quote?.instrument" class="gold-field-row">
      <text class="gold-field-label">报价源</text>
      <text class="gold-field-value">{{ quote.instrument.quote_source }}</text>
    </view>
    <view v-if="quote && quote.usd_cny > 0" class="gold-field-row">
      <text class="gold-field-label">美元汇率</text>
      <text class="gold-field-value">{{ quote.usd_cny.toFixed(4) }}</text>
    </view>
    <text class="gold-hint">
      {{
        basis === "domestic"
          ? "国内金价以上海金交所 Au99.99 元/克计价。"
          : "国际金价原始单位为美元/金衡盎司，历史价格按当前有效汇率折算为人民币元/克，不是历史人民币成交价。"
      }}
    </text>
  </view>
</template>

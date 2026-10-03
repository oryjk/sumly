<script setup lang="ts">
/**
 * 首页 —— A1 阶段只承载深色金主题与底部导航。
 * A3 会用 QuoteHeader / GoldChart 等组件充实为完整行情页。
 */
import GoldTabBar from "@/components/GoldTabBar/GoldTabBar.vue";
</script>

<template>
  <view class="page-container page-body">
    <view class="home-header">
      <text class="home-title">记金</text>
      <text class="home-subtitle">记录你的黄金资产</text>
    </view>

    <view class="gold-card">
      <text class="gold-card-title">行情</text>
      <text class="gold-hint">国内与国际金价行情建设中。</text>
    </view>

    <GoldTabBar active="market" />
  </view>
</template>

<style scoped>
.home-header {
  padding: 48rpx 0 32rpx;
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
</style>

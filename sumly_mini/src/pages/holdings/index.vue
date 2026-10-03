<script setup lang="ts">
/**
 * 持仓页 —— A1 阶段的导航空状态页。
 * B2 会替换为真实持仓编排（总览、账本、列表、筛选与处置）。
 */
import GoldTabBar from "@/components/GoldTabBar/GoldTabBar.vue";
</script>

<template>
  <view class="page-container page-body">
    <view class="gold-card">
      <text class="gold-card-title">持仓</text>
      <text class="gold-hint">持仓记录与分析功能建设中。</text>
    </view>
    <GoldTabBar active="holdings" />
  </view>
</template>

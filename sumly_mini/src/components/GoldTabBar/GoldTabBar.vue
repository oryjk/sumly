<script setup lang="ts">
/**
 * GoldTabBar —— 深色金底部导航，中央为独立添加黄金按钮。
 * 三个 Tab 走 stores/navigation 的注册路径，添加按钮复用同一添加表单。
 * 高度与安全区由 --gold-tabbar-h / --gold-safe-bottom 令牌控制。
 */
import { openAddHolding, switchTab, type TabKey } from "@/stores/navigation";

const props = defineProps<{
  active: TabKey;
  /** 添加页尚未注册时为false，点击提示功能建设状态而不跳转到不存在的页面 */
  addEnabled?: boolean;
}>();

const TABS: { key: TabKey; label: string }[] = [
  { key: "market", label: "行情" },
  { key: "holdings", label: "持仓" },
  { key: "account", label: "我的" },
];

function onSelect(tab: TabKey) {
  if (tab === props.active) return;
  switchTab(tab);
}

function onAdd() {
  if (!props.addEnabled) {
    uni.showToast({ title: "记金功能建设中", icon: "none" });
    return;
  }
  uni.navigateTo({ url: openAddHolding() });
}
</script>

<template>
  <view class="gold-tabbar">
    <view class="gold-tabbar-inner">
      <view
        v-for="tab in TABS"
        :key="tab.key"
        class="gold-tabbar-item"
        :class="{ 'gold-tabbar-item-active': tab.key === active }"
        @tap="onSelect(tab.key)"
      >
        <text class="gold-tabbar-label">{{ tab.label }}</text>
        <view class="gold-tabbar-dot" />
      </view>

      <!-- 中央添加按钮占据中间格，视觉上凸出于底栏之上 -->
      <view class="gold-tabbar-add" @tap="onAdd">
        <text class="gold-tabbar-add-icon">＋</text>
      </view>
    </view>
  </view>
</template>

<style scoped>
.gold-tabbar {
  position: fixed;
  left: 0;
  right: 0;
  bottom: 0;
  z-index: 100;
  background: var(--gold-card);
  border-top: var(--gold-hairline) solid var(--gold-stroke);
  padding-bottom: var(--gold-safe-bottom);
}

.gold-tabbar-inner {
  display: flex;
  align-items: center;
  justify-content: space-around;
  height: var(--gold-tabbar-h);
}

.gold-tabbar-item {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 8rpx;
}

.gold-tabbar-label {
  font-size: 22rpx;
  color: var(--gold-muted);
  line-height: 1.2;
}

.gold-tabbar-item-active .gold-tabbar-label {
  color: var(--gold-accent);
  font-weight: 700;
}

.gold-tabbar-dot {
  width: 8rpx;
  height: 8rpx;
  border-radius: 50%;
  background: transparent;
}

.gold-tabbar-item-active .gold-tabbar-dot {
  background: var(--gold-accent);
}

.gold-tabbar-add {
  position: absolute;
  left: 50%;
  transform: translateX(-50%);
  bottom: calc(var(--gold-safe-bottom) + 24rpx);
  width: 104rpx;
  height: 104rpx;
  border-radius: 50%;
  background: var(--gold-accent);
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 8rpx 24rpx rgba(0, 0, 0, 0.45);
}

.gold-tabbar-add-icon {
  font-size: 52rpx;
  color: var(--gold-on-accent);
  line-height: 1;
  margin-top: -4rpx;
}
</style>

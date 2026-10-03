<script setup lang="ts">
/**
 * 同步状态：展示当前同步状态、冲突提示与游客数据导入。
 * 未同步时如实告知，不声称已上云。
 */
import { useHoldingsSync } from "@/stores/holdingsSync";
import { useHoldingsStore } from "@/stores/holdings";
import { getSession } from "@/utils/sessionBridge";

const emit = defineEmits<{
  (e: "resolved"): void;
}>();

const sync = useHoldingsSync();
const holdings = useHoldingsStore();
const session = getSession();

function onSync() {
  void sync.sync();
}

function resolveConflict(choice: "local" | "remote") {
  void sync.sync(choice).then(() => emit("resolved"));
}

function importGuest() {
  if (sync.importGuest()) {
    uni.showToast({ title: "已导入游客记录", icon: "success" });
    // 导入后仍是未同步状态，需要主动推送
    void sync.sync();
  } else {
    uni.showToast({ title: sync.lastError.value ?? "导入失败", icon: "none" });
  }
}

function onUnmounted() {
  // 组件离开时把冲突状态清掉，避免下次进入仍显示旧冲突
  sync.markDirty();
}
</script>

<template>
  <view v-if="session.isLoggedIn.value" class="sync-status">
    <view class="gold-field-row">
      <text class="gold-field-label">云端同步</text>
      <text class="gold-field-value" :class="{ 'sync-pending': holdings.pendingSync.value }">
        <template v-if="sync.status.value === 'syncing'">同步中…</template>
        <template v-else-if="sync.status.value === 'conflict'">需要确认</template>
        <template v-else-if="sync.status.value === 'error'">同步失败</template>
        <template v-else-if="holdings.pendingSync.value">有未同步修改</template>
        <template v-else>已同步</template>
      </text>
    </view>

    <text v-if="sync.status.value === 'error' && sync.lastError.value" class="sync-error">
      {{ sync.lastError.value }}
    </text>
    <text v-if="holdings.pendingSync.value && sync.status.value !== 'syncing'" class="gold-hint">
      本地修改尚未推送到云端，卸载小程序存储会丢失。
    </text>

    <view v-if="sync.status.value === 'conflict'" class="sync-conflict">
      <text class="sync-conflict-text">
        {{ sync.conflicts.value.length }} 条记录在其它设备上也被修改，请选择保留哪一份。
      </text>
      <view class="sync-conflict-actions">
        <button class="gold-plain-button sync-action" @tap="resolveConflict('local')">保留本机</button>
        <button class="gold-plain-button sync-action" @tap="resolveConflict('remote')">使用云端</button>
      </view>
    </view>

    <view class="sync-actions">
      <button
        class="gold-primary-button sync-action"
        :disabled="sync.isSyncing.value"
        @tap="onSync"
      >
        {{ sync.isSyncing.value ? "同步中…" : "立即同步" }}
      </button>
      <button class="gold-plain-button sync-action" @tap="importGuest">导入游客记录</button>
    </view>
  </view>
</template>

<style scoped>
.sync-pending {
  color: var(--gold-accent);
}

.sync-error {
  display: block;
  font-size: 22rpx;
  color: var(--gold-up);
  margin: -6rpx 0 8rpx;
}

.sync-conflict {
  margin-top: 16rpx;
  padding: 16rpx;
  border-radius: var(--gold-radius-input);
  background: var(--gold-cell);
}

.sync-conflict-text {
  display: block;
  font-size: 24rpx;
  color: var(--gold-ink);
  line-height: 1.6;
}

.sync-conflict-actions {
  display: flex;
  gap: 16rpx;
  margin-top: 16rpx;
}

.sync-actions {
  display: flex;
  gap: 16rpx;
  margin-top: 20rpx;
}

.sync-action {
  flex: 1;
  margin: 0;
  padding: 20rpx 0;
  font-size: 26rpx;
}
</style>

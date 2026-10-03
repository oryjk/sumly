<script setup lang="ts">
/**
 * 我的 —— 账户身份、认证入口与账户生命周期。
 *
 * 登录为**显式操作**：无 token 时保持游客态，不在启动时自动登录。
 * 微信登录替代 Apple，手机号与邮箱认证保留。
 */
import { computed, ref } from "vue";
import { onShow } from "@dcloudio/uni-app";
import { getCapabilities } from "@/api/auth";
import { getSession } from "@/utils/sessionBridge";
import { isMockEnabled } from "@/mock";
import type { AuthCapabilities } from "@/types/auth";
import GoldTabBar from "@/components/GoldTabBar/GoldTabBar.vue";
import AccountActions from "./components/AccountActions.vue";
import AuthenticationForm from "./components/AuthenticationForm.vue";

const session = getSession();

const capabilities = ref<AuthCapabilities | null>(null);
const loadingCapabilities = ref(false);

const currentUser = session.currentUser;
const isLoggedIn = computed(() => currentUser.value !== null);

const fieldRows = computed(() => {
  const user = currentUser.value;
  if (!user) return [];
  return [
    { label: "用户 ID", value: String(user.id) },
    { label: "昵称", value: user.nickname || "（未设置）" },
    { label: "手机号", value: user.phone_number || "（未绑定）" },
    { label: "邮箱", value: user.email || "（未绑定）" },
    { label: "状态", value: user.status === "active" ? "正常" : "已冻结" },
  ];
});

async function loadCapabilities() {
  if (capabilities.value) return;
  loadingCapabilities.value = true;
  try {
    capabilities.value = await getCapabilities();
  } catch {
    // 能力检测失败不阻断登录入口，退回按需显示
    capabilities.value = { apple: false, wechat: true, phone: true, email: true };
  } finally {
    loadingCapabilities.value = false;
  }
}

onShow(() => {
  // 恢复已保存的会话；手动退出过则保持游客态
  session.ensureSessionReady();
  void loadCapabilities();
});
</script>

<template>
  <view class="page-container page-body">
    <view v-if="!isLoggedIn" class="gold-card">
      <text class="gold-card-title">登录记金</text>
      <text class="gold-hint">登录后可跨设备同步持仓记录；未登录时也可离线使用。</text>
      <view v-if="loadingCapabilities" class="auth-loading">
        <text class="gold-hint">正在检测可用登录方式…</text>
      </view>
      <AuthenticationForm
        v-else
        :capabilities="capabilities"
        @authenticated="loadCapabilities"
      />
    </view>

    <template v-else>
      <view class="gold-card">
        <text class="gold-card-title">我的账户</text>
        <view v-for="row in fieldRows" :key="row.label" class="gold-field-row">
          <text class="gold-field-label">{{ row.label }}</text>
          <text class="gold-field-value">{{ row.value }}</text>
        </view>
      </view>

      <view class="gold-card">
        <text class="gold-card-title">账户操作</text>
        <AccountActions />
      </view>
    </template>

    <view v-if="isMockEnabled()" class="gold-card">
      <text class="gold-hint">当前为 mock 模式（VITE_USE_MOCK=true），登录不请求真实后端。</text>
    </view>

    <GoldTabBar active="account" add-enabled />
  </view>
</template>

<style scoped>
.auth-loading {
  padding: 48rpx 0;
  text-align: center;
}
</style>

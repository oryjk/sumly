<script setup lang="ts">
/**
 * 我的 —— 账户身份、资料编辑与登录入口。
 * 登录/登出与资料编辑都在这里，A1 沿用既有 appSession，
 * C2 会替换为微信/手机/邮箱的显式登录与账户生命周期。
 */
import { computed, ref } from "vue";
import { onShow } from "@dcloudio/uni-app";
import { updateMyProfile } from "@/api/user";
import {
  applyCurrentUser,
  clearSession,
  ensureSessionReady,
  loginWithDevIdentifier,
  useAppSession,
} from "@/stores/appSession";
import { isMockEnabled } from "@/mock";
import GoldInput from "@/components/GoldInput/GoldInput.vue";
import GoldTabBar from "@/components/GoldTabBar/GoldTabBar.vue";

const { currentUser, isBootstrapping } = useAppSession();

const nicknameDraft = ref("");
const isSaving = ref(false);
const hasLoadedDraft = ref(false);
const devIdentifier = ref("");
const isDevLoggingIn = ref(false);

const isLoggedIn = computed(() => currentUser.value !== null);

const fieldRows = computed(() => {
  const user = currentUser.value;
  if (!user) {
    return [];
  }
  return [
    { label: "用户 ID", value: String(user.id) },
    { label: "昵称", value: user.nickname || "（未设置）" },
    { label: "真实姓名", value: user.real_name || "（未填写）" },
    { label: "手机号", value: user.phone_number || "（未绑定）" },
    { label: "状态", value: user.status },
  ];
});

async function loadPageData() {
  try {
    await ensureSessionReady();
  } catch (error) {
    uni.showToast({ title: error instanceof Error ? error.message : "会话初始化失败", icon: "none" });
    return;
  }
  if (currentUser.value && !hasLoadedDraft.value) {
    nicknameDraft.value = currentUser.value.nickname;
    hasLoadedDraft.value = true;
  }
}

async function handleSaveNickname() {
  if (isSaving.value) {
    return;
  }
  const nickname = nicknameDraft.value.trim();
  if (!nickname) {
    uni.showToast({ title: "昵称不能为空", icon: "none" });
    return;
  }
  isSaving.value = true;
  try {
    const updated = await updateMyProfile({ nickname });
    applyCurrentUser(updated);
    nicknameDraft.value = updated.nickname;
    uni.showToast({ title: "已保存", icon: "success" });
  } catch (error) {
    uni.showToast({ title: error instanceof Error ? error.message : "保存失败", icon: "none" });
  } finally {
    isSaving.value = false;
  }
}

async function handleWechatLogin() {
  try {
    await ensureSessionReady(true);
  } catch (error) {
    uni.showToast({ title: error instanceof Error ? error.message : "登录失败", icon: "none" });
  }
}

async function handleDevLogin() {
  const identifier = devIdentifier.value.trim();
  if (!identifier) {
    uni.showToast({ title: "请输入测试标识", icon: "none" });
    return;
  }
  if (isDevLoggingIn.value) {
    return;
  }
  isDevLoggingIn.value = true;
  try {
    await loginWithDevIdentifier(identifier);
  } catch (error) {
    uni.showToast({ title: error instanceof Error ? error.message : "登录失败", icon: "none" });
  } finally {
    isDevLoggingIn.value = false;
  }
}

function handleLogout() {
  clearSession();
  hasLoadedDraft.value = false;
  uni.showToast({ title: "已退出登录", icon: "none" });
}

onShow(() => {
  void loadPageData();
});
</script>

<template>
  <view class="page-container page-body">
    <view v-if="isBootstrapping" class="gold-card">
      <text class="gold-hint">正在加载...</text>
    </view>

    <template v-else-if="!isLoggedIn">
      <view class="gold-card">
        <text class="gold-card-title">登录记金</text>
        <text class="gold-hint">登录后可跨设备同步持仓记录。</text>

        <!-- #ifndef H5 -->
        <button v-if="!isMockEnabled()" class="gold-primary-button profile-action" @click="handleWechatLogin">
          微信登录
        </button>
        <button v-else class="gold-primary-button profile-action" @click="handleWechatLogin">
          登录（mock）
        </button>
        <!-- #endif -->

        <!-- #ifdef H5 -->
        <button v-if="isMockEnabled()" class="gold-primary-button profile-action" @click="handleWechatLogin">
          登录（mock）
        </button>
        <view v-else class="profile-dev-login">
          <GoldInput v-model="devIdentifier" placeholder="测试标识，如 test-user-01" :maxlength="120" />
          <button class="gold-plain-button profile-action" :disabled="isDevLoggingIn" @click="handleDevLogin">
            {{ isDevLoggingIn ? "登录中..." : "开发登录" }}
          </button>
        </view>
        <!-- #endif -->
      </view>
    </template>

    <template v-else>
      <view class="gold-card">
        <text class="gold-card-title">我的资料</text>
        <view v-for="row in fieldRows" :key="row.label" class="gold-field-row">
          <text class="gold-field-label">{{ row.label }}</text>
          <text class="gold-field-value">{{ row.value }}</text>
        </view>
      </view>

      <view class="gold-card">
        <text class="gold-card-title">修改昵称</text>
        <GoldInput v-model="nicknameDraft" placeholder="输入新昵称" :maxlength="120" />
        <button class="gold-primary-button profile-action" :disabled="isSaving" @click="handleSaveNickname">
          {{ isSaving ? "保存中..." : "保存" }}
        </button>
      </view>

      <view class="gold-card">
        <button class="gold-plain-button" @click="handleLogout">退出登录</button>
      </view>
    </template>

    <GoldTabBar active="account" add-enabled />
  </view>
</template>

<style scoped>
.profile-action {
  margin-top: 24rpx;
}

.profile-dev-login {
  margin-top: 24rpx;
}
</style>

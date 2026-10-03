<script setup lang="ts">
/**
 * 账户操作：清除行情缓存、退出登录与注销账户。
 *
 * 注销绑定发起时的账户与代际：重验成另一个用户时不能删除原用户或新用户。
 */
import { ref } from "vue";
import { deleteAccount } from "@/api/auth";
import { getSession } from "@/utils/sessionBridge";
import { useMarketStore } from "@/stores/market";
import type { AuthUser } from "@/types/auth";

const emit = defineEmits<{
  (e: "deleted"): void;
  (e: "logged-out"): void;
}>();

const session = getSession();
const market = useMarketStore();

const busy = ref(false);

function clearMarketCache() {
  market.clearCache();
  uni.showToast({ title: "行情缓存已清除", icon: "none" });
}

async function logout() {
  if (busy.value) return;
  busy.value = true;
  try {
    await session.logout();
    emit("logged-out");
    uni.showToast({ title: "已退出登录", icon: "none" });
  } finally {
    busy.value = false;
  }
}

function confirmDeletion() {
  if (busy.value) return;
  const user = session.currentUser.value;
  if (!user) return;

  uni.showModal({
    title: "注销账户",
    content: "将永久删除该账户及其云端持仓记录，且无法恢复。游客数据不受影响。",
    confirmText: "注销",
    confirmColor: "#FF5D5D",
    success: async (result) => {
      if (!result.confirm) return;
      // 意图绑定当前账户与代际
      const intent = session.beginAccountDeletion();
      busy.value = true;
      try {
        await deleteAccount();
        // 请求返回时若已换号或代际变化，不得继续清理新账户状态
        if (!session.isDeletionIntentCurrent(intent)) {
          uni.showToast({ title: "账户已变化，请重新确认", icon: "none" });
          return;
        }
        // 只清对应账户缓存，保留独立游客数据
        uni.removeStorageSync(`sumly:holdings:user:${intent.userID}`);
        session.clearSession();
        emit("deleted");
        uni.showToast({ title: "账户已注销", icon: "success" });
      } catch (error) {
        uni.showToast({
          title: error instanceof Error ? error.message : "注销失败",
          icon: "none",
        });
      } finally {
        busy.value = false;
      }
    },
  });
}

function providerLabel(user: AuthUser): string {
  switch (user.provider) {
    case "wechat":
      return "微信";
    case "phone":
      return "手机号";
    case "email":
      return "邮箱";
    default:
      return "未知";
  }
}
</script>

<template>
  <view class="account-actions">
    <view class="gold-field-row">
      <text class="gold-field-label">登录方式</text>
      <text class="gold-field-value">{{ session.currentUser.value ? providerLabel(session.currentUser.value) : "--" }}</text>
    </view>

    <button class="gold-plain-button account-action" :disabled="busy" @tap="clearMarketCache">
      清除行情缓存
    </button>
    <button class="gold-plain-button account-action" :disabled="busy" @tap="logout">
      退出登录
    </button>
    <button class="gold-plain-button account-action account-action-danger" :disabled="busy" @tap="confirmDeletion">
      注销账户
    </button>

    <text class="gold-hint">
      退出后本地保留游客工作区，未同步的修改不会丢失；注销会删除云端账户与该账户的持仓缓存，游客数据不受影响。
    </text>
  </view>
</template>

<style scoped>
.account-action {
  margin-top: 16rpx;
  font-size: 27rpx;
  padding: 22rpx 0;
}

.account-action-danger {
  color: var(--gold-up);
}
</style>

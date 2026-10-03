<script setup lang="ts">
import { onHide, onLaunch, onPageNotFound, onShow } from "@dcloudio/uni-app";
import { getSession } from "@/utils/sessionBridge";

const HOME_PAGE_PATH = "/pages/home/index";

onLaunch(() => {
  // 只恢复已保存的会话，不在启动时自动登录。
  // 手动退出过（hasManualLogout）时保持游客态。
  getSession().ensureSessionReady();
});

onShow(() => {
  // 返回前台时若access 已过期，做一次静默刷新
  const session = getSession();
  if (session.isLoggedIn.value && session.needsRefresh()) {
    void session.refreshAccess();
  }
});

onHide(() => {
  // 后台暂停行情轮询由各页面自行处理
});

onPageNotFound(() => {
  uni.reLaunch({
    url: HOME_PAGE_PATH,
  });
});
</script>

<style>
/* 全局样式与设计令牌统一收敛在 uni.css */
@import "./uni.css";
</style>

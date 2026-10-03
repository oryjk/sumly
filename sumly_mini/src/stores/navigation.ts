/**
 * 全局导航：底部 Tab 与中央添加入口的唯一路径来源。
 * 页面不硬编码跳转地址，避免注册路径与实际跳转不一致。
 */

export type TabKey = "market" | "holdings" | "account";

/** 底部三个 Tab 对应的已注册页面。 */
const TAB_PATHS: Record<TabKey, string> = {
  market: "/pages/home/index",
  holdings: "/pages/holdings/index",
  account: "/pages/user/index",
};

/** 添加黄金表单路径，由 B3 注册后启用。 */
const ADD_HOLDING_PATH = "/pages/holdings/edit";

/** 取 Tab 对应页面路径；未知 Tab 返回 null，由调用方决定降级行为。 */
export function tabPath(tab: TabKey): string | null {
  return TAB_PATHS[tab] ?? null;
}

/** 打开添加黄金表单，返回目标路径供调用方导航。 */
export function openAddHolding(): string {
  return ADD_HOLDING_PATH;
}

/**
 * 切换底部 Tab。首页是 Tab 页，reLaunch 可避免页面栈里堆积同页实例。
 */
export function switchTab(tab: TabKey): void {
  const path = tabPath(tab);
  if (!path) return;
  uni.reLaunch({ url: path });
}

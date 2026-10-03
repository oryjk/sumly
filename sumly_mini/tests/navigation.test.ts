import { describe, expect, it } from "bun:test";
import { openAddHolding, tabPath, type TabKey } from "../src/stores/navigation";

const TABS: TabKey[] = ["market", "holdings", "account"];

describe("底部导航", () => {
  it("三个 Tab 映射到已注册的页面路径", () => {
    expect(tabPath("market")).toBe("/pages/home/index");
    expect(tabPath("holdings")).toBe("/pages/holdings/index");
    expect(tabPath("account")).toBe("/pages/user/index");
  });

  it("未知 Tab 不返回路径", () => {
    expect(tabPath("unknown" as TabKey)).toBeNull();
  });
});

describe("添加黄金入口", () => {
  it("复用同一添加表单路径", () => {
    expect(openAddHolding()).toBe("/pages/holdings/edit");
  });
});

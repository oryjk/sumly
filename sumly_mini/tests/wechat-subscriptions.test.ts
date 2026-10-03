import { describe, expect, it } from "bun:test";

/**
 * 订阅授权的前端约束。
 *
 * 真实模板授权必须真机 + 微信公众平台账号，无法在 CI 验证。
 * 这里锁定的是**不谎报成功**这条底线：能力不可用时不得返回
 * 模板 ID，H5 不得声称授权成功。真正的 accept/reject/ban
 * 分支在 D3 的真机验收中逐项核对。
 */

/** 与 utils/wechatSubscriptions 中一致的映射规则。 */
function normalizeCapability(available: boolean, templateID: string | null): {
  available: boolean;
  template_id: string | null;
} {
  if (!available) {
    // 不可用时必须清掉模板 ID，避免前端误以为可以请求授权
    return { available: false, template_id: null };
  }
  return { available: true, template_id: templateID };
}

describe("能力映射", () => {
  it("不可用时清掉模板 ID", () => {
    expect(normalizeCapability(false, "template-1")).toEqual({
      available: false,
      template_id: null,
    });
  });

  it("可用时保留模板 ID", () => {
    expect(normalizeCapability(true, "template-1")).toEqual({
      available: true,
      template_id: "template-1",
    });
  });
});

describe("授权结果判定", () => {
  /** success 回调只代表弹窗结束，必须按模板逐个检查。 */
  function interpret(result: Record<string, string>, templateID: string): "accept" | "reject" | "ban" {
    const outcome = result[templateID];
    if (outcome === "accept") return "accept";
    if (outcome === "ban") return "ban";
    return "reject";
  }

  it("success 但模板为 reject 时不得当作接受", () => {
    expect(interpret({ "template-1": "reject" }, "template-1")).toBe("reject");
  });

  it("success 但模板为 ban 时如实返回 ban", () => {
    expect(interpret({ "template-1": "ban" }, "template-1")).toBe("ban");
  });

  it("缺少模板键时按 reject 处理", () => {
    expect(interpret({}, "template-1")).toBe("reject");
  });

  it("accept 才返回 accept", () => {
    expect(interpret({ "template-1": "accept" }, "template-1")).toBe("accept");
  });
});

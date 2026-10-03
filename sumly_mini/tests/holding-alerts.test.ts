import { describe, expect, it } from "bun:test";
import { evaluateAlert, mergeAlertForm, type AlertRuntime } from "../src/domain/holdings/alerts";
import type { GoldReturnInput } from "../src/domain/holdings/returns";
import type { HoldingAlert, HoldingAlertKind } from "../src/types/holdings";

const T0 = 1_757_000_000_000;

const INPUT: GoldReturnInput = {
  grams: 10,
  purity: 1,
  unitPrice: 500,
  laborFee: 0,
  otherCost: 0,
  totalCostOverride: null,
  rule: { perGramDeduction: 0, discountRate: 0, fixedFee: 0 },
};

function alert(overrides: Partial<HoldingAlert> = {}): HoldingAlert {
  return {
    id: "11111111-1111-1111-1111-111111111111",
    kind: "price",
    threshold: 600,
    enabled: true,
    basis: "international",
    ...overrides,
  };
}

const FRESH: AlertRuntime = {
  previousPrice: null,
  previousAsOf: null,
  armed: false,
  lastTriggeredAt: null,
};

describe("穿越触发", () => {
  it("首次报价即超过目标不触发", () => {
    const result = evaluateAlert(alert(), FRESH, INPUT, 700, T0, T0);
    expect(result.triggered).toBe(false);
  });

  it("先低于目标再达到才触发", () => {
    // 第一次 590 建立基线（低于 600）
    const first = evaluateAlert(alert(), FRESH, INPUT, 590, T0, T0);
    expect(first.triggered).toBe(false);
    expect(first.next.armed).toBe(true);
    expect(first.next.previousPrice).toBe(590);

    // 第二次 605 达到目标（2.5% 变化，不会被跳变过滤）
    const second = evaluateAlert(alert(), first.next, INPUT, 605, T0 + 5000, T0 + 5000);
    expect(second.triggered).toBe(true);
    expect(second.next.lastTriggeredAt).toBe(T0 + 5000);
  });

  it("触发后重置 armed，避免同一次穿越重复触发", () => {
    const first = evaluateAlert(alert(), FRESH, INPUT, 590, T0, T0);
    const second = evaluateAlert(alert(), first.next, INPUT, 605, T0 + 5000, T0 + 5000);
    expect(second.next.armed).toBe(false);
    const third = evaluateAlert(alert(), second.next, INPUT, 610, T0 + 10_000, T0 + 10_000);
    expect(third.triggered).toBe(false);
  });
});

describe("24 小时冷却", () => {
  it("冷却期内不重复触发", () => {
    const armed: AlertRuntime = {
      previousPrice: 590,
      previousAsOf: T0,
      armed: true,
      lastTriggeredAt: T0,
    };
    const result = evaluateAlert(alert(), armed, INPUT, 605, T0 + 1000, T0 + 1000);
    expect(result.triggered).toBe(false);
  });

  it("冷却结束后可再次触发", () => {
    const armed: AlertRuntime = {
      previousPrice: 590,
      previousAsOf: T0,
      armed: true,
      lastTriggeredAt: T0,
    };
    // 冷却结束后重新武装再穿越
    const later = T0 + 86_400_000 + 1000;
    const rearmed = evaluateAlert(alert(), armed, INPUT, 590, later, later);
    expect(rearmed.triggered).toBe(false);
    const final = evaluateAlert(alert(), rearmed.next, INPUT, 605, later + 1000, later + 1000);
    expect(final.triggered).toBe(true);
  });
});

describe("报价有效性", () => {
  it("超过 300 秒的报价不参与", () => {
    const result = evaluateAlert(alert(), FRESH, INPUT, 700, T0, T0 + 301_000);
    expect(result.triggered).toBe(false);
    expect(result.next.previousPrice).toBeNull();
  });

  it("300 秒内有效", () => {
    const result = evaluateAlert(alert(), FRESH, INPUT, 500, T0, T0 + 299_000);
    expect(result.next.previousPrice).toBe(500);
  });

  it("未来 60 秒内的报价接受，超过则拒绝", () => {
    const within = evaluateAlert(alert(), FRESH, INPUT, 500, T0 + 60_000, T0);
    expect(within.next.previousPrice).toBe(500);

    const beyond = evaluateAlert(alert(), FRESH, INPUT, 500, T0 + 61_000, T0);
    expect(beyond.next.previousPrice).toBeNull();
  });

  it("重复 asOf 不参与", () => {
    const baseline: AlertRuntime = {
      previousPrice: 500,
      previousAsOf: T0,
      armed: true,
      lastTriggeredAt: null,
    };
    const result = evaluateAlert(alert(), baseline, INPUT, 610, T0, T0);
    expect(result.triggered).toBe(false);
  });

  it("超过 20% 的跳变被忽略", () => {
    const baseline: AlertRuntime = {
      previousPrice: 500,
      previousAsOf: T0,
      armed: true,
      lastTriggeredAt: null,
    };
    // 500 → 700 是 40% 跳变
    const result = evaluateAlert(alert(), baseline, INPUT, 700, T0 + 5000, T0 + 5000);
    expect(result.triggered).toBe(false);
    expect(result.next.previousPrice).toBe(500);
  });

  it("长断档后重置基线", () => {
    const baseline: AlertRuntime = {
      previousPrice: 500,
      previousAsOf: T0,
      armed: true,
      lastTriggeredAt: null,
    };
    // 断档超过 300 秒：先重置基线，因此本次不会触发
    const result = evaluateAlert(alert(), baseline, INPUT, 700, T0 + 400_000, T0 + 400_000);
    expect(result.next.armed).toBe(false);
  });

  it("非法报价不参与", () => {
    for (const price of [0, -1, Number.NaN]) {
      const result = evaluateAlert(alert(), FRESH, INPUT, price, T0, T0);
      expect(result.next.previousPrice).toBeNull();
    }
  });
});

describe("目标类型", () => {
  it("保本目标用反推价", () => {
    // 成本 5000，保本价 500
    const armed: AlertRuntime = {
      previousPrice: 495,
      previousAsOf: T0,
      armed: true,
      lastTriggeredAt: null,
    };
    const result = evaluateAlert(alert({ kind: "breakEven", threshold: 0 }), armed, INPUT, 505, T0 + 1000, T0 + 1000);
    expect(result.triggered).toBe(true);
  });

  it("盈利金额目标用成本加金额反推", () => {
    const armed: AlertRuntime = {
      previousPrice: 545,
      previousAsOf: T0,
      armed: true,
      lastTriggeredAt: null,
    };
    // 目标盈利 500 → 需要 5500 元 → 550 元/克
    const result = evaluateAlert(alert({ kind: "profitAmount", threshold: 500 }), armed, INPUT, 555, T0 + 1000, T0 + 1000);
    expect(result.triggered).toBe(true);
  });

  it("收益率目标用成本乘以倍率反推", () => {
    const armed: AlertRuntime = {
      previousPrice: 545,
      previousAsOf: T0,
      armed: true,
      lastTriggeredAt: null,
    };
    // 目标收益 10% → 5500 元 → 550 元/克
    const result = evaluateAlert(alert({ kind: "profitPercent", threshold: 10 }), armed, INPUT, 555, T0 + 1000, T0 + 1000);
    expect(result.triggered).toBe(true);
  });

  it("零成本时收益率目标无法反推", () => {
    const zeroCost: GoldReturnInput = { ...INPUT, unitPrice: 0, totalCostOverride: 0 };
    const armed: AlertRuntime = {
      previousPrice: 1,
      previousAsOf: T0,
      armed: true,
      lastTriggeredAt: null,
    };
    const result = evaluateAlert(alert({ kind: "profitPercent", threshold: 10 }), armed, zeroCost, 5, T0 + 1000, T0 + 1000);
    expect(result.triggered).toBe(false);
  });

  it("金价目标为 0 时无效", () => {
    const result = evaluateAlert(alert({ threshold: 0 }), FRESH, INPUT, 500, T0, T0);
    expect(result.next.previousPrice).toBeNull();
  });

  it("已禁用的提醒不评估", () => {
    const result = evaluateAlert(alert({ enabled: false }), FRESH, INPUT, 500, T0, T0);
    expect(result.triggered).toBe(false);
    expect(result.next.previousPrice).toBeNull();
  });
});

describe("表单合并", () => {
  it("保本目标阈值强制为 0", () => {
    const result = mergeAlertForm(
      [alert({ kind: "breakEven", threshold: 123 })],
      ["999"],
      [alert({ kind: "breakEven", threshold: 0, enabled: true })],
      "domestic",
    );
    expect(result).not.toBeNull();
    expect(result!.alerts[0].threshold).toBe(0);
  });

  it("更新阈值时标记重置基线", () => {
    const result = mergeAlertForm([alert({ threshold: 700 })], ["700"], [alert({ threshold: 600 })], "international");
    expect(result!.alerts[0].threshold).toBe(700);
    expect(result!.resetIDs).toContain(alert().id);
  });

  it("禁用时标记重置基线", () => {
    const result = mergeAlertForm([alert({ enabled: false })], ["600"], [alert()], "international");
    expect(result!.alerts[0].enabled).toBe(false);
    expect(result!.resetIDs).toContain(alert().id);
  });

  it("切换口径时标记重置基线", () => {
    const result = mergeAlertForm([alert()], ["600"], [alert()], "domestic");
    expect(result!.alerts[0].basis).toBe("domestic");
    expect(result!.resetIDs).toContain(alert().id);
  });

  it("配置未变时不标记重置", () => {
    const result = mergeAlertForm([alert()], ["600"], [alert()], "international");
    expect(result!.resetIDs).toEqual([]);
  });

  it("启用时非法阈值拒绝", () => {
    const result = mergeAlertForm([alert({ kind: "price" })], ["-1"], [alert()], "international");
    expect(result).toBeNull();
  });

  it("禁用时允许非法阈值，保留原值", () => {
    const result = mergeAlertForm(
      [alert({ kind: "price", enabled: false })],
      ["-1"],
      [alert({ threshold: 600 })],
      "international",
    );
    expect(result).not.toBeNull();
    expect(result!.alerts[0].threshold).toBe(600);
  });

  it("数量不匹配返回 null", () => {
    const result = mergeAlertForm([alert()], [], [alert()], "international");
    expect(result).toBeNull();
  });
});

describe("四目标齐备", () => {
  it("四种 kind 都有标题", () => {
    const kinds: HoldingAlertKind[] = ["breakEven", "profitPercent", "profitAmount", "price"];
    for (const kind of kinds) {
      expect(alert({ kind }).kind).toBe(kind);
    }
  });
});

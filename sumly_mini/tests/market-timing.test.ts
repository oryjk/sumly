import { describe, expect, it } from "bun:test";
import { realtimeState } from "../src/domain/market/timing";

const NOW = 1_757_000_000_000;

describe("实时状态判定", () => {
  it("无样本为 empty", () => {
    expect(realtimeState(null, NOW, 5, NOW)).toBe("empty");
  });

  it("五秒采样 19 秒内为 live", () => {
    expect(realtimeState(NOW - 19_000, NOW, 5, NOW)).toBe("live");
  });

  it("五秒采样超过 20 秒容差为 paused", () => {
    expect(realtimeState(NOW - 21_000, NOW, 5, NOW)).toBe("paused");
  });

  it("分钟回退采样 119 秒仍 live", () => {
    expect(realtimeState(NOW - 119_000, NOW, 60, NOW)).toBe("live");
  });

  it("分钟回退采样 121 秒为 paused", () => {
    expect(realtimeState(NOW - 121_000, NOW, 60, NOW)).toBe("paused");
  });

  it("样本新鲜但报价超过 180 秒为 paused", () => {
    expect(realtimeState(NOW - 5_000, NOW - 181_000, 5, NOW)).toBe("paused");
  });

  it("报价恰好 180 秒不算过期", () => {
    expect(realtimeState(NOW - 5_000, NOW - 180_000, 5, NOW)).toBe("live");
  });

  it("无报价时间时只看样本容差", () => {
    expect(realtimeState(NOW - 5_000, null, 5, NOW)).toBe("live");
  });
});

import { describe, expect, it } from "bun:test";
import { calendarEvents, selectCalendarEvents } from "../src/domain/holdings/calendar";
import type { HoldingRecord } from "../src/types/holdings";

const UUID_A = "11111111-1111-1111-1111-111111111111";
const UUID_B = "22222222-2222-2222-2222-222222222222";
const UUID_C = "33333333-3333-3333-3333-333333333333";
const T0 = Date.UTC(2026, 0, 15, 3, 0, 0);
const DAY = 86_400_000;

function record(overrides: Partial<HoldingRecord> = {}): HoldingRecord {
  return {
    id: UUID_A, grams: 10, unitPriceCNY: 500, timestamp: T0, note: "",
    createdAt: T0, brand: "周大福", bookName: "默认账本", disposition: "holding",
    disposedAt: null, disposalAmount: 0, purchaseID: null, extraFee: 20,
    purchaseChannel: "门店", counterparty: "", assetType: "金条", purity: 0.9999,
    laborFee: 100, purchaseTotalOverride: null, recoveryDeduction: 0,
    recoveryDiscount: 0, recoveryFixedFee: 0, alerts: [],
    ...overrides,
  };
}

const NO_FILTER = { keyword: "", kind: "all", book: null } as const;

describe("事件生成", () => {
  it("持有记录生成购入事件", () => {
    const events = calendarEvents([record()], NO_FILTER);
    expect(events).toHaveLength(1);
    expect(events[0].kind).toBe("buy");
    expect(events[0].cost).toBeCloseTo(5120, 6);
    expect(events[0].fees).toBeCloseTo(120, 6);
  });

  it("已处置记录同时生成购入与处置事件", () => {
    const events = calendarEvents(
      [record({ disposition: "sold", disposedAt: T0 + 10 * DAY, disposalAmount: 6000 })],
      NO_FILTER,
    );
    expect(events).toHaveLength(2);
    expect(events.map((e) => e.kind).sort()).toEqual(["buy", "sold"]);
  });

  it("按处置事件日期而非购入日期归属", () => {
    const events = calendarEvents(
      [record({ disposition: "gift", disposedAt: T0 + 10 * DAY, disposalAmount: 0 })],
      { ...NO_FILTER, kind: "gift" },
    );
    expect(events).toHaveLength(1);
    expect(events[0].date).toBe(T0 + 10 * DAY);
  });

  it("拆分后购入件数仍按购入编号去重", () => {
    // 同一购入拆成三条：剩余 + 两笔卖出
    const events = calendarEvents(
      [
        record({ id: UUID_A, grams: 6 }),
        record({ id: UUID_B, grams: 2, purchaseID: UUID_A, disposition: "sold", disposedAt: T0 + DAY, disposalAmount: 1500 }),
        record({ id: UUID_C, grams: 2, purchaseID: UUID_A, disposition: "sold", disposedAt: T0 + 2 * DAY, disposalAmount: 1600 }),
      ],
      { ...NO_FILTER, kind: "holding" },
    );
    // 购入事件按 purchaseID 去重，只有一条
    expect(events).toHaveLength(1);
    expect(events[0].purchaseID).toBe(UUID_A);
  });

  it("品牌为空时标题为未知", () => {
    const events = calendarEvents([record({ brand: "" })], NO_FILTER);
    expect(events[0].title).toBe("未知");
  });

  it("按账本筛选", () => {
    const records = [record(), record({ id: UUID_B, bookName: "收藏" })];
    expect(calendarEvents(records, { ...NO_FILTER, book: "收藏" })).toHaveLength(1);
    expect(calendarEvents(records, { ...NO_FILTER, book: null })).toHaveLength(2);
  });

  it("关键词匹配品牌、备注、渠道与交易方", () => {
    const records = [record({ brand: "周大福" }), record({ id: UUID_B, brand: "", note: "春节买入" })];
    expect(calendarEvents(records, { ...NO_FILTER, keyword: "周大" })).toHaveLength(1);
    expect(calendarEvents(records, { ...NO_FILTER, keyword: "春节" })).toHaveLength(1);
    expect(calendarEvents(records, { ...NO_FILTER, keyword: "门店" })).toHaveLength(2);
  });

  it("已处置但缺处置时间不生成处置事件", () => {
    const events = calendarEvents([record({ disposition: "sold", disposedAt: null })], NO_FILTER);
    expect(events).toHaveLength(1);
  });

  it("事件按日期倒序", () => {
    const records = [
      record({ id: UUID_A, timestamp: T0 }),
      record({ id: UUID_B, timestamp: T0 + 5 * DAY }),
    ];
    const events = calendarEvents(records, NO_FILTER);
    expect(events[0].date).toBeGreaterThan(events[1].date);
  });
});

describe("周期筛选", () => {
  const records = [
    record({ id: UUID_A, timestamp: Date.UTC(2026, 0, 20, 3) }),
    record({ id: UUID_B, timestamp: Date.UTC(2026, 1, 20, 3) }),
    record({ id: UUID_C, timestamp: Date.UTC(2025, 5, 10, 3) }),
  ];
  const events = calendarEvents(records, NO_FILTER);
  const anchor = Date.UTC(2026, 0, 20);

  it("按日筛选只含当日", () => {
    expect(selectCalendarEvents(events, "day", anchor)).toHaveLength(1);
  });

  it("按月筛选含整月", () => {
    // anchor 为 1 月 20 日，该月只有一条
    expect(selectCalendarEvents(events, "month", anchor)).toHaveLength(1);
    // 换到 2 月则命中 2 月那条
    expect(selectCalendarEvents(events, "month", Date.UTC(2026, 1, 20))).toHaveLength(1);
  });

  it("按年筛选含整年", () => {
    expect(selectCalendarEvents(events, "year", Date.UTC(2026, 5, 1))).toHaveLength(2);
  });

  it("全部返回所有事件", () => {
    expect(selectCalendarEvents(events, "all", anchor)).toHaveLength(3);
  });

  it("跨年边界不串月", () => {
    const result = selectCalendarEvents(events, "month", Date.UTC(2026, 11, 31));
    expect(result).toHaveLength(0);
  });

  it("闰年 2 月 29 日落在正确月份", () => {
    const leap = [record({ id: UUID_A, timestamp: Date.UTC(2028, 1, 29, 5) })];
    const result = selectCalendarEvents(calendarEvents(leap, NO_FILTER), "month", Date.UTC(2028, 1, 15));
    expect(result).toHaveLength(1);
  });
});

import { describe, expect, it } from "bun:test";
import { createAlertMonitor } from "../src/stores/holdingAlerts";
import type { AlertRuntime } from "../src/domain/holdings/alerts";
import type { HoldingRecord } from "../src/types/holdings";

const UUID_A = "11111111-1111-1111-1111-111111111111";
const ALERT = "22222222-2222-2222-2222-222222222222";
const T0 = 1_757_000_000_000;

function record(overrides: Partial<HoldingRecord> = {}): HoldingRecord {
  return {
    id: UUID_A, grams: 10, unitPriceCNY: 500, timestamp: T0, note: "",
    createdAt: T0, brand: "", bookName: "默认账本", disposition: "holding",
    disposedAt: null, disposalAmount: 0, purchaseID: null, extraFee: 0,
    purchaseChannel: "", counterparty: "", assetType: "金条", purity: 1,
    laborFee: 0, purchaseTotalOverride: null, recoveryDeduction: 0,
    recoveryDiscount: 0, recoveryFixedFee: 0,
    alerts: [{ id: ALERT, kind: "price", threshold: 600, enabled: true, basis: "international" }],
    ...overrides,
  };
}

function harness(options?: { failSave?: boolean }) {
  const saved = new Map<string, AlertRuntime>();
  let clock = T0;
  const monitor = createAlertMonitor({
    now: () => clock,
    loadRuntime: (key) => saved.get(key) ?? null,
    saveRuntime: (key, runtime) => {
      if (options?.failSave) throw new Error("存储已满");
      saved.set(key, runtime);
    },
  });
  // 默认处于运行态；生命周期用例会自行 start/stop
  monitor.start("test");

  return {
    monitor,
    events: () => monitor.pending.value,
    saved,
    setClock: (value: number) => {
      clock = value;
    },
    keys: () => [...saved.keys()],
  };
}

describe("运行态持久化", () => {
  it("按 workspace+record+alert 独立保存", () => {
    const { monitor, keys } = harness();
    monitor.evaluate([record()], 500, T0, T0);
    expect(keys()[0]).toContain(UUID_A);
    expect(keys()[0]).toContain(ALERT);
  });

  it("不同记录的提醒互不干扰", () => {
    const { monitor, saved } = harness();
    monitor.evaluate([record()], 500, T0, T0);
    const other = record({ id: "33333333-3333-3333-3333-333333333333" });
    monitor.evaluate([other], 500, T0, T0);
    expect(saved.size).toBe(2);
  });

  it("保存失败时不发布新运行态", () => {
    const { monitor } = harness({ failSave: true });
    // 不抛错，但状态不落盘
    monitor.evaluate([record()], 500, T0, T0);
    expect(monitor.lastError.value).toBe("存储已满");
  });
});

describe("触发事件", () => {
  it("穿越时产生事件", () => {
    const { monitor, events, setClock } = harness();
    monitor.evaluate([record()], 590, T0, T0);
    expect(events()).toHaveLength(0);

    setClock(T0 + 5000);
    monitor.evaluate([record()], 605, T0 + 5000, T0 + 5000);
    expect(events()).toHaveLength(1);
    expect(events()[0].alertID).toBe(ALERT);
  });

  it("已处置记录不监测", () => {
    const { monitor, events } = harness();
    monitor.evaluate([record({ disposition: "sold", disposedAt: T0 + 1000 })], 590, T0, T0);
    monitor.evaluate([record({ disposition: "sold", disposedAt: T0 + 1000 })], 605, T0 + 5000, T0 + 5000);
    expect(events()).toHaveLength(0);
  });

  it("禁用的提醒不产生事件", () => {
    const { monitor, events, setClock } = harness();
    const off = record({
      alerts: [{ id: ALERT, kind: "price", threshold: 600, enabled: false, basis: "international" }],
    });
    monitor.evaluate([off], 590, T0, T0);
    setClock(T0 + 5000);
    monitor.evaluate([off], 605, T0 + 5000, T0 + 5000);
    expect(events()).toHaveLength(0);
  });

  it("没有提醒的记录不产生事件", () => {
    const { monitor, events } = harness();
    monitor.evaluate([record({ alerts: [] })], 590, T0, T0);
    monitor.evaluate([record({ alerts: [] })], 605, T0 + 5000, T0 + 5000);
    expect(events()).toHaveLength(0);
  });
});

describe("送达确认", () => {
  it("未确认的事件保留在队列中", () => {
    const { monitor, setClock } = harness();
    monitor.evaluate([record()], 590, T0, T0);
    setClock(T0 + 5000);
    monitor.evaluate([record()], 605, T0 + 5000, T0 + 5000);
    expect(monitor.pending.value).toHaveLength(1);
  });

  it("确认送达后移出队列", () => {
    const { monitor, setClock } = harness();
    monitor.evaluate([record()], 590, T0, T0);
    setClock(T0 + 5000);
    monitor.evaluate([record()], 605, T0 + 5000, T0 + 5000);
    const eventID = monitor.pending.value[0].id;
    monitor.acknowledge(eventID, "delivered");
    expect(monitor.pending.value).toHaveLength(0);
  });

  it("送达失败仍移出队列但记录失败状态", () => {
    const { monitor, setClock } = harness();
    monitor.evaluate([record()], 590, T0, T0);
    setClock(T0 + 5000);
    monitor.evaluate([record()], 605, T0 + 5000, T0 + 5000);
    const eventID = monitor.pending.value[0].id;
    monitor.acknowledge(eventID, "failed");
    expect(monitor.pending.value).toHaveLength(0);
    expect(monitor.lastDeliveryOutcome.value).toBe("failed");
  });

  it("未知事件确认不抛错", () => {
    const { monitor } = harness();
    expect(() => monitor.acknowledge("not-exist", "delivered")).not.toThrow();
  });
});

describe("生命周期", () => {
  it("停止后不评估", () => {
    const { monitor, events, setClock } = harness();
    monitor.stop("holdings");
    setClock(T0 + 5000);
    monitor.evaluate([record()], 605, T0 + 5000, T0 + 5000);
    expect(events()).toHaveLength(0);
  });

  it("运行中才评估", () => {
    const { monitor, events, setClock } = harness();
    monitor.start("holdings");
    monitor.evaluate([record()], 590, T0, T0);
    setClock(T0 + 5000);
    monitor.evaluate([record()], 605, T0 + 5000, T0 + 5000);
    expect(events()).toHaveLength(1);
  });
});

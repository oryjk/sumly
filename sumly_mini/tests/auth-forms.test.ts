import { describe, expect, it } from "bun:test";
import {
  normalizeEmail,
  normalizePhone,
  passwordProblem,
  sendCodeProblem,
} from "../src/domain/auth/forms";

describe("手机号", () => {
  it("接受 +86 与裸号", () => {
    expect(normalizePhone("13800138000")).toBe("+8613800138000");
    expect(normalizePhone("+8613800138000")).toBe("+8613800138000");
    expect(normalizePhone("  13800138000  ")).toBe("+8613800138000");
  });

  it("拒绝非法号段", () => {
    for (const value of ["", "1380013800", "12800138000", "138001380001", "abcdefghijk"]) {
      expect(normalizePhone(value)).toBeNull();
    }
  });
});

describe("邮箱", () => {
  it("转小写并去空白", () => {
    expect(normalizeEmail("User@Example.COM")).toBe("user@example.com");
    expect(normalizeEmail("  a@b.com ")).toBe("a@b.com");
  });

  it("拒绝非法邮箱", () => {
    for (const value of ["", "a@b", "a b@example.com", "a@@b.com", "not-an-email"]) {
      expect(normalizeEmail(value)).toBeNull();
    }
  });
});

describe("密码", () => {
  it("接受 12-128 个字符", () => {
    expect(passwordProblem("abcdefghijkl")).toBeNull();
  });

  it("拒绝过短", () => {
    expect(passwordProblem("abcdefghijk")).not.toBeNull();
  });

  it("拒绝超过 128 字符", () => {
    expect(passwordProblem("a".repeat(129))).not.toBeNull();
  });

  it("同时受字符数与字节数限制", () => {
    // 120 个汉字 = 120 字符、360 字节，两者都在限制内
    expect(passwordProblem("汉".repeat(120))).toBeNull();
    // 128 个 emoji = 128 字符，但 512 字节恰好达上限
    expect(passwordProblem("😀".repeat(128))).toBeNull();
    // 129 个 emoji 超过字符上限
    expect(passwordProblem("😀".repeat(129))).not.toBeNull();
  });
});

describe("验证码发送", () => {
  it("冷却期内不可重发", () => {
    const last = Date.now();
    expect(sendCodeProblem(13800138000, last)).not.toBeNull();
  });

  it("冷却结束后可重发", () => {
    const last = Date.now() - 61_000;
    expect(sendCodeProblem(13800138000, last)).toBeNull();
  });

  it("从未发送过则可发", () => {
    expect(sendCodeProblem(13800138000, null)).toBeNull();
  });
});

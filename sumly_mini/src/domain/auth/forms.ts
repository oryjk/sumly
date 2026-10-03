/**
 * 认证表单校验。
 *
 * 规则与服务端 domain.ValidatePassword / NormalizePhone / NormalizeEmail
 * 保持一致：前端先挡一次，服务端仍然独立校验，不信任客户端。
 * 服务不可用时不得返回「已发送」之类的假成功。
 */

/** +86 手机号。 */
const MOBILE = /^1[3-9][0-9]{9}$/;

/** 归一化手机号；非法返回 null。 */
export function normalizePhone(value: string): string | null {
  const trimmed = value.trim().replace(/^\+86/, "");
  if (!MOBILE.test(trimmed)) return null;
  return `+86${trimmed}`;
}

/** 归一化邮箱（转小写去空白）；非法返回 null。 */
export function normalizeEmail(value: string): string | null {
  const trimmed = value.trim().toLowerCase();
  if (trimmed.length === 0 || trimmed.length > 254) return null;
  // 与服务端一致：需要域名点，且不允许显示名形式
  if (trimmed.includes(" ") || trimmed.includes("\r") || trimmed.includes("\n")) return null;
  if (!/^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$/.test(trimmed)) return null;
  return trimmed;
}

/** 密码问题提示；通过返回 null。 */
export function passwordProblem(value: string): string | null {
  const characters = [...value].length;
  if (characters < 12) return "密码至少 12 个字符";
  if (characters > 128) return "密码最多 128 个字符";
  // 服务端按字节限制，这里同样按 UTF-8 字节校验
  const bytes = new TextEncoder().encode(value).length;
  if (bytes > 512) return "密码过长";
  return null;
}

/** 验证码 6 位数字。 */
export function codeProblem(value: string): string | null {
  const trimmed = value.trim();
  if (!/^\d{6}$/.test(trimmed)) return "验证码为 6 位数字";
  return null;
}

/** 重发冷却（毫秒），与服务端 retry_after 一致。 */
export const CODE_COOLDOWN_MS = 60_000;

/**
 * 发码按钮是否可用。
 * @param target 目标（手机号或邮箱）
 * @param lastSentAt 上次发送时间；null 表示从未发送
 */
export function sendCodeProblem(target: string, lastSentAt: number | null, now = Date.now()): string | null {
  if (!target) return "请先填写联系方式";
  if (lastSentAt === null) return null;
  const elapsed = now - lastSentAt;
  if (elapsed < CODE_COOLDOWN_MS) {
    const remain = Math.ceil((CODE_COOLDOWN_MS - elapsed) / 1000);
    return `${remain} 秒后可重发`;
  }
  return null;
}

import { PASSWORD_MAX_BYTES, PASSWORD_MIN_LENGTH } from '../types/config';
import { getUtf8ByteLength } from './format';

export type PasswordStrengthLevel = 0 | 1 | 2 | 3 | 4;

export interface PasswordStrengthInfo {
  level: PasswordStrengthLevel;
  label: string;
  barClass: string;
  textClass: string;
  hint: string;
}

export interface PasswordValidationState {
  lengthOk: boolean;
  maxBytesOk: boolean;
  differentFromCurrent: boolean;
  confirmMatches: boolean;
  byteLength: number;
  strength: PasswordStrengthInfo;
  canSubmit: boolean;
  blockingMessage: string | null;
}

export function evaluatePasswordStrength(password: string): PasswordStrengthInfo {
  if (!password) {
    return {
      level: 0,
      label: '待输入',
      barClass: 'bg-white/10',
      textClass: 'text-[#7D776D]',
      hint: `建议至少 ${PASSWORD_MIN_LENGTH} 位，组合大小写字母、数字与符号`,
    };
  }

  let score = 0;
  if (password.length >= PASSWORD_MIN_LENGTH) score += 1;
  if (password.length >= 12) score += 1;

  let categories = 0;
  if (/[a-z]/.test(password)) categories += 1;
  if (/[A-Z]/.test(password)) categories += 1;
  if (/\d/.test(password)) categories += 1;
  if (/[^a-zA-Z0-9]/.test(password)) categories += 1;

  if (categories >= 2) score += 1;
  if (categories >= 3) score += 1;

  if (password.length < PASSWORD_MIN_LENGTH) {
    return {
      level: 1,
      label: '长度不足',
      barClass: 'bg-[#FF5D5D]',
      textClass: 'text-[#FF8585]',
      hint: `还差 ${PASSWORD_MIN_LENGTH - password.length} 位即可达到最低安全长度`,
    };
  }

  if (score <= 1) {
    return {
      level: 1,
      label: '较弱',
      barClass: 'bg-[#FF5D5D]',
      textClass: 'text-[#FF8585]',
      hint: '建议增加大小写字母、数字或特殊字符提升安全性',
    };
  }

  if (score === 2) {
    return {
      level: 2,
      label: '中等',
      barClass: 'bg-[#F2C512]',
      textClass: 'text-[#F2C512]',
      hint: '可使用，增加到 12 位以上或加入符号会更安全',
    };
  }

  if (score === 3) {
    return {
      level: 3,
      label: '良好',
      barClass: 'bg-[#FFE066]',
      textClass: 'text-[#FFE066]',
      hint: '密码复杂度良好，适合作为后台永久密码',
    };
  }

  return {
    level: 4,
    label: '高强度',
    barClass: 'bg-[#3DD68C]',
    textClass: 'text-[#5AE2A0]',
    hint: '安全强度优秀，可安心作为管理员永久密码',
  };
}

export function validatePasswordChange(
  currentPassword: string,
  newPassword: string,
  confirmPassword: string,
): PasswordValidationState {
  const byteLength = getUtf8ByteLength(newPassword);
  const lengthOk = newPassword.length >= PASSWORD_MIN_LENGTH;
  const maxBytesOk = byteLength <= PASSWORD_MAX_BYTES;
  const differentFromCurrent =
    newPassword.length > 0 && currentPassword.length > 0 && newPassword !== currentPassword;
  const confirmMatches = confirmPassword.length > 0 && newPassword === confirmPassword;
  const strength = evaluatePasswordStrength(newPassword);

  let blockingMessage: string | null = null;
  if (!currentPassword) {
    blockingMessage = '请输入当前密码';
  } else if (!lengthOk) {
    blockingMessage = `新密码长度不能少于 ${PASSWORD_MIN_LENGTH} 位`;
  } else if (!maxBytesOk) {
    blockingMessage = `新密码 UTF-8 字节长度不能超过 ${PASSWORD_MAX_BYTES} 字节（当前 ${byteLength} 字节）`;
  } else if (!differentFromCurrent) {
    blockingMessage = '新密码不能与当前密码相同';
  } else if (!confirmMatches) {
    blockingMessage = '两次输入的新密码不一致';
  }

  return {
    lengthOk,
    maxBytesOk,
    differentFromCurrent,
    confirmMatches,
    byteLength,
    strength,
    canSubmit: blockingMessage === null,
    blockingMessage,
  };
}

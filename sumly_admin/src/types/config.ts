export const MEMBERSHIP_PAYWALL_KEY = 'membership_paywall' as const;
export const FREE_ACCESS_NOTICE_MAX_LENGTH = 120;
export const EXTENSION_JSON_MAX_BYTES = 16 * 1024;
export const PASSWORD_MIN_LENGTH = 8;
export const PASSWORD_MAX_BYTES = 72;

export interface MembershipPaywallConfig {
  chanlun_requires_membership: boolean;
  membership_entry_visible: boolean;
  free_access_notice: string;
}

export const DEFAULT_MEMBERSHIP_PAYWALL_CONFIG: MembershipPaywallConfig = {
  chanlun_requires_membership: true,
  membership_entry_visible: true,
  free_access_notice: '',
};

export interface AppConfigItem {
  key: string;
  value: Record<string, unknown>;
  description: string;
  updated_by: string;
  updated_at: string;
}

export interface AuditLogItem {
  id: number;
  config_key: string;
  old_value: Record<string, unknown> | null;
  new_value: Record<string, unknown>;
  operator: string;
  note: string;
  created_at: string;
}

export interface UpdateConfigPayload {
  value: Record<string, unknown>;
  description?: string;
  operator?: string;
  note?: string;
}

export interface ApiEnvelope<T> {
  code: number;
  data?: T;
  message?: string;
  error?: string;
}

export interface AuthLoginPayload {
  username: string;
  password: string;
}

export interface AuthLoginResult {
  token: string;
  username: string;
  must_change_password: boolean;
  expires_at?: string;
}

export interface AuthVerifyResult {
  valid: boolean;
  username: string;
  must_change_password: boolean;
}

export interface ChangePasswordPayload {
  current_password: string;
  new_password: string;
}

export interface ChangePasswordResult {
  username: string;
  must_change_password: boolean;
}

export interface AuthLogoutResult {
  logged_out: boolean;
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

export function parseMembershipPaywallConfig(value: unknown): MembershipPaywallConfig {
  if (!isRecord(value)) {
    return { ...DEFAULT_MEMBERSHIP_PAYWALL_CONFIG };
  }

  return {
    chanlun_requires_membership:
      typeof value.chanlun_requires_membership === 'boolean'
        ? value.chanlun_requires_membership
        : DEFAULT_MEMBERSHIP_PAYWALL_CONFIG.chanlun_requires_membership,
    membership_entry_visible:
      typeof value.membership_entry_visible === 'boolean'
        ? value.membership_entry_visible
        : DEFAULT_MEMBERSHIP_PAYWALL_CONFIG.membership_entry_visible,
    free_access_notice:
      typeof value.free_access_notice === 'string'
        ? value.free_access_notice
        : DEFAULT_MEMBERSHIP_PAYWALL_CONFIG.free_access_notice,
  };
}

export function arePaywallConfigsEqual(
  a: MembershipPaywallConfig,
  b: MembershipPaywallConfig,
): boolean {
  return (
    a.chanlun_requires_membership === b.chanlun_requires_membership &&
    a.membership_entry_visible === b.membership_entry_visible &&
    a.free_access_notice.trim() === b.free_access_notice.trim()
  );
}

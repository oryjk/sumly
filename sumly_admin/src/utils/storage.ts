export const DEFAULT_API_BASE = '/sumly/api/v1';

const TOKEN_KEY = 'sumly_admin_session_token';
const USERNAME_KEY = 'sumly_admin_username';
const MUST_CHANGE_PASSWORD_KEY = 'sumly_admin_must_change_password';
const EXPIRES_AT_KEY = 'sumly_admin_expires_at';
const API_BASE_KEY = 'sumly_admin_api_base';
const OPERATOR_KEY = 'sumly_admin_operator';

export interface AdminSession {
  token: string;
  username: string;
  mustChangePassword: boolean;
  expiresAt?: string;
  apiBase: string;
  operator: string;
}

export function normalizeApiBase(raw: string): string {
  const trimmed = raw.trim();
  if (!trimmed) {
    return DEFAULT_API_BASE;
  }
  return trimmed.replace(/\/+$/, '');
}

export function loadAdminSession(): AdminSession | null {
  try {
    const token = sessionStorage.getItem(TOKEN_KEY)?.trim() ?? '';
    if (!token) {
      return null;
    }
    const username = sessionStorage.getItem(USERNAME_KEY)?.trim() || 'admin';
    const mustChangePassword = sessionStorage.getItem(MUST_CHANGE_PASSWORD_KEY) === 'true';
    const expiresAt = sessionStorage.getItem(EXPIRES_AT_KEY)?.trim() || undefined;
    const apiBase = normalizeApiBase(sessionStorage.getItem(API_BASE_KEY) ?? DEFAULT_API_BASE);
    const operator = sessionStorage.getItem(OPERATOR_KEY)?.trim() || username;
    return { token, username, mustChangePassword, expiresAt, apiBase, operator };
  } catch {
    return null;
  }
}

export function saveAdminSession(session: AdminSession): void {
  try {
    const normalizedUsername = session.username.trim() || 'admin';
    sessionStorage.setItem(TOKEN_KEY, session.token.trim());
    sessionStorage.setItem(USERNAME_KEY, normalizedUsername);
    sessionStorage.setItem(
      MUST_CHANGE_PASSWORD_KEY,
      session.mustChangePassword ? 'true' : 'false',
    );
    if (session.expiresAt?.trim()) {
      sessionStorage.setItem(EXPIRES_AT_KEY, session.expiresAt.trim());
    } else {
      sessionStorage.removeItem(EXPIRES_AT_KEY);
    }
    sessionStorage.setItem(API_BASE_KEY, normalizeApiBase(session.apiBase));
    sessionStorage.setItem(OPERATOR_KEY, session.operator.trim() || normalizedUsername);
  } catch {
    // Ignore storage quota or privacy-mode failures.
  }
}

export function updateSavedOperator(operator: string): void {
  try {
    const fallback = sessionStorage.getItem(USERNAME_KEY)?.trim() || 'admin';
    sessionStorage.setItem(OPERATOR_KEY, operator.trim() || fallback);
  } catch {
    // Ignore storage failures.
  }
}

export function clearAdminSession(): void {
  try {
    sessionStorage.removeItem(TOKEN_KEY);
    sessionStorage.removeItem(USERNAME_KEY);
    sessionStorage.removeItem(MUST_CHANGE_PASSWORD_KEY);
    sessionStorage.removeItem(EXPIRES_AT_KEY);
    sessionStorage.removeItem(API_BASE_KEY);
    sessionStorage.removeItem(OPERATOR_KEY);
  } catch {
    // Ignore storage failures.
  }
}

export function getSavedApiBase(): string {
  try {
    return normalizeApiBase(sessionStorage.getItem(API_BASE_KEY) ?? DEFAULT_API_BASE);
  } catch {
    return DEFAULT_API_BASE;
  }
}

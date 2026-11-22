export const DEFAULT_API_BASE = '/sumly/api/v1';

const TOKEN_KEY = 'sumly_admin_session_token';
const API_BASE_KEY = 'sumly_admin_api_base';
const OPERATOR_KEY = 'sumly_admin_operator';

export interface AdminSession {
  token: string;
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
    const apiBase = normalizeApiBase(sessionStorage.getItem(API_BASE_KEY) ?? DEFAULT_API_BASE);
    const operator = sessionStorage.getItem(OPERATOR_KEY)?.trim() || 'admin';
    return { token, apiBase, operator };
  } catch {
    return null;
  }
}

export function saveAdminSession(session: AdminSession): void {
  try {
    sessionStorage.setItem(TOKEN_KEY, session.token.trim());
    sessionStorage.setItem(API_BASE_KEY, normalizeApiBase(session.apiBase));
    sessionStorage.setItem(OPERATOR_KEY, session.operator.trim() || 'admin');
  } catch {
    // Ignore storage quota or privacy-mode failures.
  }
}

export function updateSavedOperator(operator: string): void {
  try {
    sessionStorage.setItem(OPERATOR_KEY, operator.trim() || 'admin');
  } catch {
    // Ignore storage failures.
  }
}

export function clearAdminSession(): void {
  try {
    sessionStorage.removeItem(TOKEN_KEY);
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

/** mock 用户数据，供 mock 模式下的接口返回。 */

export interface MockUser {
  id: number;
  nickname: string;
  avatar_url: string | null;
  real_name: string | null;
  phone_number: string | null;
  email: string | null;
  status: "active" | "frozen";
}

let mockNickname = "Mock 用户";
let mockEmail: string | null = null;
let mockPhone: string | null = null;

export function getMockUser(): MockUser {
  return {
    id: 1,
    nickname: mockNickname,
    avatar_url: null,
    real_name: "测试用户",
    phone_number: mockPhone,
    email: mockEmail,
    status: "active",
  };
}

export function setMockNickname(nickname: string): void {
  mockNickname = nickname;
}

export function setMockEmail(email: string | null): void {
  mockEmail = email;
}

export function setMockPhone(phone: string | null): void {
  mockPhone = phone;
}

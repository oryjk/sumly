<script setup lang="ts">
/**
 * 认证表单：微信 / 手机号 / 邮箱三种方式，含验证码与密码重置。
 *
 * 服务不可用时显示真实错误，不返回「已发送」之类的假成功；
 * 能力检测不可用的方式不渲染入口。
 */
import { computed, ref } from "vue";
import {
  loginWithEmail,
  loginWithPhone,
  registerWithEmail,
  resetPassword,
  sendEmailCode,
  sendPhoneCode,
} from "@/api/auth";
import {
  codeProblem,
  normalizeEmail,
  normalizePhone,
  passwordProblem,
  sendCodeProblem,
} from "@/domain/auth/forms";
import { getSession } from "@/utils/sessionBridge";
import type { AuthCapabilities, EmailPurpose } from "@/types/auth";

const props = defineProps<{
  capabilities: AuthCapabilities | null;
}>();

const emit = defineEmits<{
  (e: "authenticated"): void;
}>();

type Mode = "wechat" | "phone" | "email";

const session = getSession();

const mode = ref<Mode>("wechat");
const phone = ref("");
const email = ref("");
const code = ref("");
const password = ref("");
const newPassword = ref("");
const emailPurpose = ref<EmailPurpose>("register");
const busy = ref(false);
const formError = ref<string | null>(null);
const notice = ref<string | null>(null);
const lastPhoneSentAt = ref<number | null>(null);
const lastEmailSentAt = ref<number | null>(null);

const phoneNumber = computed(() => normalizePhone(phone.value));
const emailAddress = computed(() => normalizeEmail(email.value));

const phoneProblem = computed(() =>
  phone.value.trim() && !phoneNumber.value ? "请输入有效的 +86 手机号" : "",
);
const emailProblem = computed(() =>
  email.value.trim() && !emailAddress.value ? "请输入有效的邮箱地址" : "",
);
const codeFieldProblem = computed(() => (code.value.trim() ? codeProblem(code.value) : ""));
const passwordFieldProblem = computed(() =>
  password.value ? passwordProblem(password.value) : "",
);
const newPasswordProblem = computed(() =>
  newPassword.value ? passwordProblem(newPassword.value) : "",
);

/** 各方式的可用性由服务端能力决定。 */
const canWechat = computed(() => props.capabilities?.wechat !== false);
const canPhone = computed(() => props.capabilities?.phone !== false);
const canEmail = computed(() => props.capabilities?.email !== false);

/** 重发冷却提示。 */
const phoneCooldown = computed(() => sendCodeProblem(phoneNumber.value ?? "", lastPhoneSentAt.value));
const emailCooldown = computed(() => sendCodeProblem(emailAddress.value ?? "", lastEmailSentAt.value));

const canSubmit = computed(() => {
  if (busy.value) return false;
  if (mode.value === "wechat") return canWechat.value;
  if (mode.value === "phone") {
    return Boolean(phoneNumber.value) && !codeFieldProblem.value && !phoneProblem.value;
  }
  if (emailPurpose.value === "reset_password") {
    return (
      Boolean(emailAddress.value) &&
      !codeFieldProblem.value &&
      !newPasswordProblem.value &&
      Boolean(newPassword.value)
    );
  }
  if (props.capabilities === null) return false;
  return (
    Boolean(emailAddress.value) &&
    !codeFieldProblem.value &&
    !passwordFieldProblem.value &&
    Boolean(password.value)
  );
});

function readValue(event: unknown): string {
  return (event as { detail?: { value?: string } })?.detail?.value ?? "";
}

function onPhoneInput(event: unknown) {
  phone.value = readValue(event);
}
function onEmailInput(event: unknown) {
  email.value = readValue(event);
}
function onCodeInput(event: unknown) {
  code.value = readValue(event);
}
function onPasswordInput(event: unknown) {
  password.value = readValue(event);
}
function onNewPasswordInput(event: unknown) {
  newPassword.value = readValue(event);
}

function resetFeedback() {
  formError.value = null;
  notice.value = null;
}

async function run(action: () => Promise<void>, failure: string) {
  if (busy.value) return;
  busy.value = true;
  resetFeedback();
  try {
    await action();
    emit("authenticated");
  } catch (error) {
    formError.value = error instanceof Error ? error.message : failure;
  } finally {
    busy.value = false;
  }
}

async function submitWechat() {
  const { loginWithWechat } = await import("@/utils/sessionBridge");
  await run(async () => {
    await loginWithWechat();
    notice.value = "已登录";
  }, "微信登录失败");
}

async function sendPhone() {
  if (!phoneNumber.value || phoneCooldown.value) return;
  await run(async () => {
    await sendPhoneCode(phoneNumber.value!);
    lastPhoneSentAt.value = Date.now();
    notice.value = "验证码已发送";
  }, "验证码发送失败");
}

async function sendEmail() {
  if (!emailAddress.value || emailCooldown.value) return;
  // 登录不需要验证码，服务端也不接受该用途
  if (emailPurpose.value === "login") {
    notice.value = "登录无需验证码";
    return;
  }
  await run(async () => {
    await sendEmailCode(emailAddress.value!, emailPurpose.value);
    lastEmailSentAt.value = Date.now();
    notice.value = "验证码已发送";
  }, "验证码发送失败");
}

async function submitPhone() {
  await run(async () => {
    const result = await loginWithPhone(phoneNumber.value!, code.value.trim());
    session.applyLoginResult(result);
    notice.value = "已登录";
  }, "手机号登录失败");
}

async function submitEmail() {
  if (emailPurpose.value === "reset_password") {
    await run(async () => {
      await resetPassword(emailAddress.value!, code.value.trim(), newPassword.value);
      notice.value = "密码已重置，请重新登录";
      emailPurpose.value = "register";
      code.value = "";
      newPassword.value = "";
    }, "密码重置失败");
    return;
  }
  await run(async () => {
    const result =
      emailPurpose.value === "register"
        ? await registerWithEmail(emailAddress.value!, password.value, code.value.trim())
        : await loginWithEmail(emailAddress.value!, password.value);
    session.applyLoginResult(result);
    notice.value = "已登录";
  }, "邮箱操作失败");
}
</script>

<template>
  <view class="auth-form">
    <view class="auth-modes">
      <view v-if="canWechat" class="gold-capsule" :class="{ 'gold-capsule-active': mode === 'wechat' }" @tap="mode = 'wechat'; resetFeedback()">
        微信
      </view>
      <view v-if="canPhone" class="gold-capsule" :class="{ 'gold-capsule-active': mode === 'phone' }" @tap="mode = 'phone'; resetFeedback()">
        手机号
      </view>
      <view v-if="canEmail" class="gold-capsule" :class="{ 'gold-capsule-active': mode === 'email' }" @tap="mode = 'email'; resetFeedback()">
        邮箱
      </view>
    </view>

    <view v-if="mode === 'wechat'" class="auth-wechat">
      <text class="gold-hint">使用微信身份登录，可跨设备同步持仓记录。</text>
      <button class="gold-primary-button auth-action" :disabled="busy" @tap="submitWechat">
        {{ busy ? "登录中…" : "微信登录" }}
      </button>
    </view>

    <view v-else-if="mode === 'phone'" class="auth-fields">
      <view class="auth-row">
        <text class="auth-label">手机号</text>
        <input
          class="auth-input"
          type="number"
          :value="phone"
          placeholder="+86 手机号"
          placeholder-class="auth-placeholder"
          @input="onPhoneInput"
        />
      </view>
      <text v-if="phoneProblem" class="auth-problem">{{ phoneProblem }}</text>

      <view class="auth-row">
        <text class="auth-label">验证码</text>
        <input
          class="auth-input auth-input-narrow"
          type="number"
          :value="code"
          placeholder="6 位"
          placeholder-class="auth-placeholder"
          @input="onCodeInput"
        />
        <text class="auth-send" :class="{ 'auth-send-disabled': phoneCooldown }" @tap="sendPhone">
          {{ phoneCooldown || "获取验证码" }}
        </text>
      </view>
      <text v-if="codeFieldProblem" class="auth-problem">{{ codeFieldProblem }}</text>

      <button class="gold-primary-button auth-action" :disabled="!canSubmit" @tap="submitPhone">
        {{ busy ? "登录中…" : "登录" }}
      </button>
    </view>

    <view v-else class="auth-fields">
      <view class="auth-row">
        <text class="auth-label">邮箱</text>
        <input
          class="auth-input"
          :value="email"
          placeholder="name@example.com"
          placeholder-class="auth-placeholder"
          @input="onEmailInput"
        />
      </view>
      <text v-if="emailProblem" class="auth-problem">{{ emailProblem }}</text>

      <view class="auth-row">
        <text class="auth-label">验证码</text>
        <input
          class="auth-input auth-input-narrow"
          type="number"
          :value="code"
          placeholder="6 位"
          placeholder-class="auth-placeholder"
          @input="onCodeInput"
        />
        <text class="auth-send" :class="{ 'auth-send-disabled': emailCooldown }" @tap="sendEmail">
          {{ emailCooldown || "获取验证码" }}
        </text>
      </view>
      <text v-if="codeFieldProblem" class="auth-problem">{{ codeFieldProblem }}</text>

      <view v-if="emailPurpose === 'reset_password'" class="auth-row">
        <text class="auth-label">新密码</text>
        <input
          class="auth-input"
          :value="newPassword"
          placeholder="至少 12 个字符"
          placeholder-class="auth-placeholder"
          @input="onNewPasswordInput"
        />
      </view>
      <text v-if="newPasswordProblem" class="auth-problem">{{ newPasswordProblem }}</text>

      <view v-else class="auth-row">
        <text class="auth-label">密码</text>
        <input
          class="auth-input"
          :value="password"
          placeholder="至少 12 个字符"
          placeholder-class="auth-placeholder"
          @input="onPasswordInput"
        />
      </view>
      <text v-if="passwordFieldProblem" class="auth-problem">{{ passwordFieldProblem }}</text>

      <button class="gold-primary-button auth-action" :disabled="!canSubmit" @tap="submitEmail">
        {{
          busy
            ? "处理中…"
            : emailPurpose === "reset_password"
              ? "重置密码"
              : emailPurpose === "register"
                ? "注册并登录"
                : "登录"
        }}
      </button>

      <view class="auth-switch">
        <text
          v-if="emailPurpose === 'register'"
          class="auth-link"
          @tap="emailPurpose = 'login'; resetFeedback()"
        >
          已有账号？去登录
        </text>
        <text
          v-else-if="emailPurpose === 'login'"
          class="auth-link"
          @tap="emailPurpose = 'register'; resetFeedback()"
        >
          没有账号？去注册
        </text>
        <text class="auth-link" @tap="emailPurpose = 'reset_password'; resetFeedback()">
          忘记密码
        </text>
      </view>
    </view>

    <text v-if="formError" class="auth-feedback auth-feedback-error">{{ formError }}</text>
    <text v-else-if="notice" class="auth-feedback">{{ notice }}</text>
  </view>
</template>

<style scoped>
.auth-modes {
  display: flex;
  gap: 12rpx;
  margin-bottom: 24rpx;
}

.auth-row {
  display: flex;
  align-items: center;
  gap: 16rpx;
  padding: 12rpx 0;
}

.auth-label {
  width: 120rpx;
  font-size: 26rpx;
  color: var(--gold-muted);
  flex-shrink: 0;
}

.auth-input {
  flex: 1;
  height: var(--gold-input-h);
  background: var(--gold-cell);
  border: var(--gold-hairline) solid var(--gold-stroke);
  border-radius: var(--gold-radius-input);
  padding: 0 20rpx;
  font-size: 27rpx;
  color: var(--gold-ink);
}

.auth-input-narrow {
  max-width: 180rpx;
}

.auth-placeholder {
  color: var(--gold-faint);
}

.auth-send {
  font-size: 24rpx;
  color: var(--gold-accent);
  flex-shrink: 0;
  padding: 0 8rpx;
}

.auth-send-disabled {
  color: var(--gold-faint);
}

.auth-problem {
  display: block;
  font-size: 22rpx;
  color: var(--gold-up);
  margin: -6rpx 0 8rpx;
}

.auth-action {
  margin-top: 24rpx;
}

.auth-switch {
  display: flex;
  justify-content: space-between;
  margin-top: 20rpx;
}

.auth-link {
  font-size: 24rpx;
  color: var(--gold-accent);
}

.auth-feedback {
  display: block;
  margin-top: 16rpx;
  font-size: 24rpx;
  color: var(--gold-muted);
}

.auth-feedback-error {
  color: var(--gold-up);
}
</style>

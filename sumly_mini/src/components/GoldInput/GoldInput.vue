<script setup lang="ts">
/**
 * GoldInput —— 深色金主题的统一文本输入框。
 * 视觉值只引用 uni.css 的 --gold-* 令牌，禁止硬编码。
 * 用法：<GoldInput v-model="value" placeholder="..." :maxlength="120" />
 */
withDefaults(
  defineProps<{
    modelValue: string;
    placeholder?: string;
    maxlength?: number;
    type?: string;
  }>(),
  { placeholder: "", maxlength: 140, type: "text" },
);

const emit = defineEmits<{
  (e: "update:modelValue", value: string): void;
}>();

function handleInput(event: unknown) {
  const detail = (event as { detail?: { value?: string } }).detail;
  emit("update:modelValue", detail?.value ?? "");
}
</script>

<template>
  <input
    class="gold-input"
    :value="modelValue"
    :type="type"
    :placeholder="placeholder"
    placeholder-class="gold-input-placeholder"
    :maxlength="maxlength"
    @input="handleInput"
  />
</template>

<style scoped>
.gold-input {
  background: var(--gold-cell);
  border: var(--gold-hairline) solid var(--gold-stroke);
  border-radius: var(--gold-radius-input);
  /* uni-input 默认 height 固定 1.4em 且overflow:hidden，
     必须显式给定高度，否则边框会把内部 input 压到不可点 */
  height: var(--gold-input-h);
  padding: 0 24rpx;
  font-size: 28rpx;
  color: var(--gold-ink);
}
</style>

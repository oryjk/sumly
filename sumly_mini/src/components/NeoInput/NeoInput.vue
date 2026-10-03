<script setup lang="ts">
/**
 * NeoInput —— 已废弃，请改用 GoldInput。
 * 保留仅为过渡期兼容既有调用，样式已切到深色金令牌。
 */
import GoldInput from "@/components/GoldInput/GoldInput.vue";

defineProps<{
  modelValue: string;
  placeholder?: string;
  maxlength?: number;
}>();

const emit = defineEmits<{
  (e: "update:modelValue", value: string): void;
}>();
</script>

<template>
  <GoldInput
    :model-value="modelValue"
    :placeholder="placeholder"
    :maxlength="maxlength"
    @update:model-value="emit('update:modelValue', $event)"
  />
</template>

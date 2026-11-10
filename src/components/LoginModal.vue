<template>
  <div v-if="open" class="login-modal" @click.self="close" @keydown.esc.prevent.stop="close">
    <div
      class="login-modal-card"
      role="dialog"
      aria-modal="true"
      aria-labelledby="loginModalTitle"
      aria-describedby="loginModalDescription"
    >
      <h3 id="loginModalTitle">需要登录账号</h3>
      <p id="loginModalDescription">{{ message }}</p>
      <div class="login-modal-actions">
        <button ref="cancelButton" type="button" @click="close">稍后再说</button>
        <RouterLink to="/account" @click="close">前往登录 / Account</RouterLink>
      </div>
    </div>
  </div>
</template>

<script setup>
import { nextTick, onBeforeUnmount, ref, watch } from "vue";
import { RouterLink } from "vue-router";

const props = defineProps({
  open: { type: Boolean, default: false },
  message: { type: String, default: "请先登录账号，再发布评论或点赞。" },
});

const emit = defineEmits(["close"]);

let previousBodyOverflow = "";
let previousActiveElement = null;
const cancelButton = ref(null);

function close() {
  emit("close");
}

watch(
  () => props.open,
  (open) => {
    if (open) {
      previousActiveElement = document.activeElement;
      previousBodyOverflow = document.body.style.overflow;
      document.body.style.overflow = "hidden";
      nextTick(() => cancelButton.value?.focus());
    } else {
      document.body.style.overflow = previousBodyOverflow;
      if (previousActiveElement instanceof HTMLElement) {
        nextTick(() => previousActiveElement?.focus());
      }
    }
  },
  { immediate: true },
);

onBeforeUnmount(() => {
  document.body.style.overflow = previousBodyOverflow;
  if (previousActiveElement instanceof HTMLElement) {
    previousActiveElement.focus();
  }
});
</script>

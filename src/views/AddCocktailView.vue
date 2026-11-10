<template>
  <main class="cocktail-create-page">
    <header class="cocktail-create-nav">
      <RouterLink to="/cocktails">← 返回调酒菜单</RouterLink>
      <RouterLink to="/menu">功能菜单</RouterLink>
    </header>

    <section class="cocktail-create-hero">
      <p class="eyebrow">{{ isEditMode ? "Edit Cocktail" : "Create a Cocktail" }}</p>
      <h1>{{ isEditMode ? "编辑调酒" : "新增调酒" }}<span>{{ isEditMode ? "更新你的酒款档案" : "完整填写酒款档案" }}</span></h1>
      <p>
        {{
          isEditMode
            ? "可更新中文名、故事、命名、基酒与风味、图片和调酒配方；英文名称用于关联评论，发布后不可修改。"
            : "所有字段将严格对应酒款详情页中的名称、故事、命名、基酒与风味、图片和调酒配方。"
        }}
      </p>
    </section>

    <section class="cocktail-create-layout">
      <form class="cocktail-create-form" :aria-busy="working || loadingExisting" @submit.prevent="submitCocktail">
        <div class="cocktail-create-section">
          <div class="cocktail-create-section-title">
            <span>01</span>
            <h2>基本资料</h2>
          </div>
          <div class="cocktail-create-fields cocktail-create-fields--two">
            <label>
              英文名称 / Name
              <input
                v-model.trim="form.name"
                type="text"
                minlength="2"
                maxlength="60"
                placeholder="Whiskey Sour"
                :readonly="isEditMode"
                required
              />
              <small v-if="isEditMode">英文名称用于关联评论，编辑时保持不变。</small>
            </label>
            <label>
              中文名称 / Chinese Name
              <input v-model.trim="form.zhName" type="text" minlength="1" maxlength="40" placeholder="威士忌酸" required />
            </label>
            <label>
              酒单分类 / Category
              <select v-model="form.category" required>
                <option value="classic">Classic / 经典</option>
                <option value="signature">Signature / 特调</option>
                <option value="nonalcoholic">No Alcohol / 无酒精</option>
              </select>
            </label>
            <label>
              基酒分类 / Base Spirit
              <select v-model="form.base" required>
                <option value="whiskey">Whiskey / 威士忌</option>
                <option value="gin">Gin / 金酒</option>
                <option value="rum">Rum / 朗姆</option>
                <option value="tequila">Tequila / 龙舌兰</option>
                <option value="vodka">Vodka / 伏特加</option>
                <option value="none">No Base / 无基酒</option>
              </select>
            </label>
          </div>
          <label>
            {{ isEditMode ? "更换酒款图片（可选）/ Replace Image" : "本地酒款图片 / Image File" }}
            <input
              type="file"
              accept=".jpg,.jpeg,.png,image/jpeg,image/png"
              :required="!isEditMode"
              @change="selectImage"
            />
            <small>支持 JPG、JPEG、PNG，最大 5MB。{{ isEditMode ? "不选择则保留原图。" : "建议使用竖版图片。" }}</small>
            <small v-if="selectedImageFile">{{ selectedImageFile.name }} · {{ formatFileSize(selectedImageFile.size) }}</small>
          </label>
        </div>

        <div class="cocktail-create-section">
          <div class="cocktail-create-section-title">
            <span>02</span>
            <h2>酒款介绍</h2>
          </div>
          <label>
            酒款故事 / Story
            <textarea
              v-model.trim="form.story"
              rows="5"
              minlength="20"
              maxlength="800"
              placeholder="介绍酒款的诞生背景、文化来源与饮用场景……"
              required
            ></textarea>
            <small>{{ form.story.length }} / 800，至少 20 字。</small>
          </label>
          <label>
            命名 / Naming
            <textarea
              v-model.trim="form.naming"
              rows="3"
              minlength="10"
              maxlength="300"
              placeholder="说明中英文名称的来源与含义……"
              required
            ></textarea>
          </label>
          <label>
            基酒与风味 / Flavor Profile
            <input
              v-model.trim="form.profile"
              type="text"
              minlength="5"
              maxlength="200"
              placeholder="Bourbon / 柠檬 / 甜酸 / 酒体饱满"
              required
            />
          </label>
        </div>

        <div class="cocktail-create-section">
          <div class="cocktail-create-section-title">
            <span>03</span>
            <h2>调酒配方</h2>
          </div>
          <label>
            调制方式 / Method
            <input v-model.trim="form.method" type="text" minlength="2" maxlength="80" placeholder="摇和 Shake" required />
          </label>
          <label>
            配方材料 / Ingredients
            <textarea
              v-model="form.ingredients"
              rows="7"
              maxlength="1000"
              placeholder="波本威士忌 45 ml&#10;新鲜柠檬汁 25 ml&#10;糖浆 20 ml&#10;蛋清 20 ml（可选）"
              required
            ></textarea>
            <small>每行一种材料，必须填写 2–12 行，并写明用量或“适量”等说明。</small>
          </label>
        </div>

        <p class="cocktail-create-notice" :data-type="noticeType" role="status">{{ notice }}</p>
        <button class="cocktail-create-submit" type="submit" :disabled="working || loadingExisting">
          {{ working ? "正在保存酒款…" : isEditMode ? "保存酒款修改" : "发布到调酒菜单" }}
        </button>
      </form>

      <aside class="cocktail-create-preview">
        <p class="eyebrow">Detail Format Preview</p>
        <img
          v-if="displayImageUrl"
          class="cocktail-create-preview-image"
          :src="displayImageUrl"
          :alt="isEditMode ? '当前酒款图片预览' : '待上传酒款图片预览'"
        />
        <h3>{{ form.name || "Cocktail Name" }}<span>{{ form.zhName || "酒款中文名" }}</span></h3>
        <p class="cocktail-create-preview-story">{{ form.story || "酒款故事会显示在这里。" }}</p>
        <div>
          <section>
            <h4>命名</h4>
            <p>{{ form.naming || "名称来源与含义。" }}</p>
          </section>
          <section>
            <h4>基酒与风味</h4>
            <p>{{ form.profile || "基酒 / 香气 / 酸甜 / 口感" }}</p>
          </section>
        </div>
        <section class="cocktail-create-preview-recipe">
          <h4>调酒配方 <span>{{ form.method || "调制方式" }}</span></h4>
          <ul>
            <li v-for="item in previewIngredients" :key="item">{{ item }}</li>
          </ul>
        </section>
      </aside>
    </section>

    <LoginModal
      :open="loginModalOpen"
      :message="isEditMode ? '请先登录账号，再编辑酒款。' : '请先登录账号，再新增调酒。'"
      @close="loginModalOpen = false"
    />
  </main>
</template>

<script setup>
import { computed, onBeforeUnmount, onMounted, reactive, ref } from "vue";
import { RouterLink, useRoute, useRouter } from "vue-router";
import LoginModal from "@/components/LoginModal.vue";
import { cocktails as staticCocktails } from "@/data/cocktails";
import { supabase } from "@/lib/supabase";
import {
  canEditCocktail,
  fetchUserCocktailById,
  parseIngredients,
  removeCocktailImage,
  updateUserCocktail,
  uploadCocktailImage,
  validateCocktailForm,
  validateImageFile,
} from "@/lib/user-cocktails";
import { useAuthStore } from "@/stores/auth";

const route = useRoute();
const router = useRouter();
const auth = useAuthStore();
const working = ref(false);
const loadingExisting = ref(false);
const notice = ref("");
const noticeType = ref("info");
const loginModalOpen = ref(false);
const selectedImageFile = ref(null);
const imagePreviewUrl = ref("");
const existingCocktail = ref(null);
const existingImageUrl = ref("");
const editId = computed(() => String(route.params.id || ""));
const isEditMode = computed(() => route.name === "cocktail-edit" && Boolean(editId.value));
const displayImageUrl = computed(() => imagePreviewUrl.value || existingImageUrl.value);

const form = reactive({
  name: "",
  zhName: "",
  category: "signature",
  base: "gin",
  story: "",
  naming: "",
  profile: "",
  method: "",
  ingredients: "",
});

const parsedIngredients = computed(() => parseIngredients(form.ingredients));

const previewIngredients = computed(() =>
  parsedIngredients.value.length ? parsedIngredients.value : ["材料名称与用量", "装饰或辅料"],
);

onBeforeUnmount(clearImagePreview);
onMounted(async () => {
  notice.value = isEditMode.value
    ? "正在读取酒款资料…"
    : "登录后即可把完整酒款资料发布到菜单。";
  if (isEditMode.value) await loadExistingCocktail();
});

function clearImagePreview() {
  if (imagePreviewUrl.value) URL.revokeObjectURL(imagePreviewUrl.value);
  imagePreviewUrl.value = "";
}

function selectImage(event) {
  const file = event.target?.files?.[0] || null;
  clearImagePreview();
  selectedImageFile.value = null;

  if (!file) return;
  const imageError = validateImageFile(file);
  if (imageError) {
    notice.value = imageError;
    noticeType.value = "error";
    event.target.value = "";
    return;
  }

  selectedImageFile.value = file;
  imagePreviewUrl.value = URL.createObjectURL(file);
  notice.value = isEditMode.value ? "新图片已选择，保存时会替换原图。" : "图片已选择，发布时会自动上传。";
  noticeType.value = "success";
}

function formatFileSize(bytes) {
  return `${(bytes / 1024 / 1024).toFixed(2)} MB`;
}

async function submitCocktail() {
  if (!supabase) {
    notice.value = `Supabase 未配置，暂时无法${isEditMode.value ? "编辑" : "发布"}酒款。`;
    noticeType.value = "error";
    return;
  }

  await auth.refreshSession();
  if (!auth.user) {
    loginModalOpen.value = true;
    notice.value = `请先登录账号，再${isEditMode.value ? "编辑" : "新增"}调酒。`;
    noticeType.value = "error";
    return;
  }

  if (isEditMode.value && !canEditCocktail(existingCocktail.value, auth.user)) {
    notice.value = "只有酒款作者可以编辑这条酒款资料。";
    noticeType.value = "error";
    return;
  }

  const validationError = validateCocktailForm({
    form,
    ingredients: parsedIngredients.value,
    staticCocktails,
    imageFile: selectedImageFile.value,
    requireImage: !isEditMode.value,
  });
  if (validationError) {
    notice.value = validationError;
    noticeType.value = "error";
    return;
  }

  working.value = true;
  notice.value = selectedImageFile.value ? "正在上传酒款图片…" : "正在保存酒款资料…";
  noticeType.value = "info";
  let uploadedImage = null;
  try {
    if (selectedImageFile.value) {
      uploadedImage = await uploadCocktailImage(supabase, selectedImageFile.value, auth.user.id);
    }
  } catch (error) {
    working.value = false;
    notice.value = error.message;
    noticeType.value = "error";
    return;
  }

  const payload = {
    name: form.name,
    zh_name: form.zhName,
    category: form.category,
    base: form.base,
    image: uploadedImage?.imageUrl || existingImageUrl.value,
    naming: form.naming,
    story: form.story,
    profile: form.profile,
    method: form.method,
    ingredients: parsedIngredients.value,
  };
  notice.value = "正在保存酒款资料…";

  const { data, error } = isEditMode.value
    ? await updateUserCocktail(supabase, editId.value, auth.user.id, payload)
    : await supabase
        .from("user_cocktails")
        .insert({
          ...payload,
          user_id: auth.user.id,
          user_name: auth.profile.name,
        })
        .select("id")
        .single();
  working.value = false;

  if (error) {
    if (uploadedImage) await removeCocktailImage(supabase, uploadedImage.storagePath);
    notice.value =
      error.code === "23505"
        ? "该英文名称已被使用，请更换后重试。"
        : `酒款${isEditMode.value ? "更新" : "发布"}失败：${error.message}`;
    noticeType.value = "error";
    return;
  }

  if (isEditMode.value && uploadedImage && existingImageUrl.value) {
    await removeCocktailImage(supabase, existingImageUrl.value);
  }
  await router.push({
    name: "cocktails",
    query: isEditMode.value ? { updated: data.id } : { created: data.id },
  });
}

async function loadExistingCocktail() {
  if (!supabase) {
    notice.value = "Supabase 未配置，无法读取待编辑酒款。";
    noticeType.value = "error";
    return;
  }

  loadingExisting.value = true;
  await auth.refreshSession();
  if (!auth.user) {
    loadingExisting.value = false;
    loginModalOpen.value = true;
    notice.value = "请先登录作者账号，再编辑酒款。";
    noticeType.value = "error";
    return;
  }

  const { cocktail, error } = await fetchUserCocktailById(supabase, editId.value);
  loadingExisting.value = false;
  if (error || !cocktail) {
    notice.value = `无法读取酒款：${error?.message || "记录不存在"}`;
    noticeType.value = "error";
    return;
  }
  if (!canEditCocktail(cocktail, auth.user)) {
    notice.value = "只有酒款作者可以编辑这条酒款资料。";
    noticeType.value = "error";
    return;
  }

  existingCocktail.value = cocktail;
  existingImageUrl.value = cocktail.image;
  Object.assign(form, {
    name: cocktail.name,
    zhName: cocktail.zhName,
    category: cocktail.category,
    base: cocktail.base,
    story: cocktail.story,
    naming: cocktail.naming,
    profile: cocktail.profile,
    method: cocktail.method,
    ingredients: cocktail.ingredients.join("\n"),
  });
  notice.value = "酒款资料已载入，修改后点击保存。";
  noticeType.value = "success";
}
</script>

<style scoped>
.cocktail-create-page {
  min-height: 100vh;
  padding: clamp(18px, 3vw, 42px);
  color: var(--ink);
  background:
    linear-gradient(rgba(251, 242, 223, 0.94), rgba(244, 229, 196, 0.96)),
    url("/assets/parchment-scroll.webp") center / cover fixed;
}

.cocktail-create-nav,
.cocktail-create-hero,
.cocktail-create-layout {
  width: min(1180px, 100%);
  margin-inline: auto;
}

.cocktail-create-nav {
  display: flex;
  justify-content: space-between;
  gap: 16px;
}

.cocktail-create-nav a {
  color: var(--olive);
  font-weight: 700;
  text-decoration: none;
}

.cocktail-create-hero {
  padding: clamp(36px, 6vw, 72px) 0 30px;
}

.cocktail-create-hero h1 {
  color: var(--coffee);
  font-size: clamp(3.2rem, 7vw, 6.8rem);
}

.cocktail-create-hero h1 span {
  display: block;
  margin-top: 12px;
  color: var(--garlic);
  font-family: "Noto Serif SC", serif;
  font-size: clamp(1rem, 2vw, 1.5rem);
  letter-spacing: 0.12em;
}

.cocktail-create-hero > p:last-child {
  max-width: 760px;
  color: var(--muted);
  line-height: 1.8;
}

.cocktail-create-layout {
  display: grid;
  grid-template-columns: minmax(0, 1.35fr) minmax(300px, 0.65fr);
  gap: 22px;
  align-items: start;
}

.cocktail-create-form,
.cocktail-create-preview {
  border: 1px solid var(--line);
  background: rgba(255, 248, 234, 0.88);
  box-shadow: var(--shadow);
}

.cocktail-create-form {
  display: grid;
  gap: 0;
}

.cocktail-create-section {
  display: grid;
  gap: 16px;
  padding: clamp(20px, 3vw, 34px);
  border-bottom: 1px solid var(--line);
}

.cocktail-create-section-title {
  display: flex;
  align-items: center;
  gap: 12px;
}

.cocktail-create-section-title span {
  color: var(--garlic);
  font-size: 0.72rem;
  letter-spacing: 0.16em;
}

.cocktail-create-section-title h2 {
  color: var(--coffee);
  font-size: 2rem;
}

.cocktail-create-fields {
  display: grid;
  gap: 14px;
}

.cocktail-create-fields--two {
  grid-template-columns: repeat(2, minmax(0, 1fr));
}

.cocktail-create-form label {
  display: grid;
  gap: 7px;
  color: var(--muted);
  font-family: "Noto Serif SC", serif;
  line-height: 1.5;
}

.cocktail-create-form input,
.cocktail-create-form select,
.cocktail-create-form textarea {
  width: 100%;
  min-width: 0;
  box-sizing: border-box;
  border: 1px solid rgba(52, 21, 15, 0.22);
  padding: 11px 13px;
  color: var(--ink);
  background: rgba(255, 252, 242, 0.8);
}

.cocktail-create-form textarea {
  resize: vertical;
  line-height: 1.7;
}

.cocktail-create-form small {
  color: var(--garlic);
  font-size: 0.72rem;
}

.cocktail-create-notice {
  margin: 22px 28px 0;
  border: 1px solid var(--line);
  padding: 11px 13px;
  color: var(--muted);
  background: rgba(245, 232, 203, 0.64);
}

.cocktail-create-notice[data-type="error"] {
  color: #9b261b;
  border-color: rgba(155, 38, 27, 0.35);
}

.cocktail-create-submit {
  margin: 16px 28px 28px;
  border: 1px solid var(--olive);
  padding: 14px 18px;
  color: var(--cream);
  font-weight: 800;
  letter-spacing: 0.1em;
  background: var(--olive);
}

.cocktail-create-submit:disabled {
  opacity: 0.55;
}

.cocktail-create-preview {
  position: sticky;
  top: 22px;
  display: grid;
  gap: 24px;
  padding: clamp(24px, 3vw, 38px);
}

.cocktail-create-preview h3 {
  color: var(--coffee);
  font-size: clamp(2.4rem, 4vw, 4rem);
}

.cocktail-create-preview-image {
  width: min(240px, 100%);
  aspect-ratio: 682 / 1024;
  object-fit: cover;
  object-position: center top;
  border: 1px solid var(--line);
  justify-self: center;
}

.cocktail-create-preview h3 span {
  display: block;
  margin-top: 8px;
  color: var(--garlic);
  font-size: 1rem;
  letter-spacing: 0.08em;
}

.cocktail-create-preview-story,
.cocktail-create-preview p {
  color: var(--muted);
  line-height: 1.8;
  white-space: pre-wrap;
}

.cocktail-create-preview > div {
  display: grid;
  gap: 18px;
  grid-template-columns: repeat(2, minmax(0, 1fr));
}

.cocktail-create-preview h4 {
  margin-bottom: 8px;
  color: var(--coffee);
  font-size: 1.35rem;
}

.cocktail-create-preview-recipe {
  border-top: 1px solid var(--line);
  padding-top: 20px;
}

.cocktail-create-preview-recipe h4 {
  display: flex;
  justify-content: space-between;
  gap: 12px;
}

.cocktail-create-preview-recipe h4 span {
  color: var(--garlic);
  font-family: sans-serif;
  font-size: 0.72rem;
  letter-spacing: 0.08em;
}

.cocktail-create-preview-recipe ul {
  display: grid;
  gap: 8px;
  margin: 0;
  padding: 0;
  list-style: none;
}

.cocktail-create-preview-recipe li {
  border-bottom: 1px solid rgba(52, 21, 15, 0.12);
  padding: 7px 0;
  color: var(--muted);
}

@media (max-width: 900px) {
  .cocktail-create-layout {
    grid-template-columns: 1fr;
  }

  .cocktail-create-preview {
    position: relative;
    top: 0;
    order: 0;
  }
}

@media (max-width: 720px) {
  .cocktail-create-page {
    min-height: 100dvh;
    padding:
      max(16px, env(safe-area-inset-top))
      max(14px, env(safe-area-inset-right))
      calc(88px + env(safe-area-inset-bottom))
      max(14px, env(safe-area-inset-left));
    background-attachment: scroll;
  }

  .cocktail-create-nav a {
    min-height: 44px;
    display: inline-flex;
    align-items: center;
  }

  .cocktail-create-fields--two,
  .cocktail-create-preview > div {
    grid-template-columns: 1fr;
  }

  .cocktail-create-form input,
  .cocktail-create-form select,
  .cocktail-create-form textarea {
    min-height: 44px;
    font-size: 16px;
  }

  .cocktail-create-submit {
    min-height: 48px;
  }
}

@media (max-width: 620px) {
  .cocktail-create-fields--two,
  .cocktail-create-preview > div {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 480px) {
  .cocktail-create-page {
    min-height: 100dvh;
    padding:
      max(14px, env(safe-area-inset-top))
      max(12px, env(safe-area-inset-right))
      calc(76px + env(safe-area-inset-bottom))
      max(12px, env(safe-area-inset-left));
    background-attachment: scroll;
  }

  .cocktail-create-nav {
    align-items: stretch;
    flex-direction: column;
  }

  .cocktail-create-nav a {
    min-height: 44px;
    display: inline-flex;
    align-items: center;
  }

  .cocktail-create-hero {
    padding: 24px 0 18px;
  }

  .cocktail-create-hero h1 {
    font-size: clamp(2rem, 12vw, 2.8rem);
    line-height: 1;
  }

  .cocktail-create-section {
    padding: 18px 14px;
  }

  .cocktail-create-section-title {
    align-items: flex-start;
    flex-direction: column;
    gap: 5px;
  }

  .cocktail-create-section-title h2 {
    font-size: clamp(1.25rem, 6vw, 1.6rem);
  }

  .cocktail-create-form input,
  .cocktail-create-form select,
  .cocktail-create-form textarea {
    min-height: 44px;
    font-size: 16px;
  }

  .cocktail-create-form input[type="file"] {
    max-width: 100%;
  }

  .cocktail-create-form small {
    overflow-wrap: anywhere;
  }

  .cocktail-create-notice {
    margin: 16px 14px 0;
  }

  .cocktail-create-submit {
    min-height: 48px;
    margin: 14px;
  }

  .cocktail-create-preview {
    order: 0;
    gap: 16px;
    padding: 18px 14px;
  }

  .cocktail-create-preview h3 {
    font-size: clamp(1.8rem, 10vw, 2.5rem);
  }
}
</style>

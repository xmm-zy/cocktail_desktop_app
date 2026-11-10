<template>
  <main class="app-shell">
    <CocktailSidebar
      v-model:search-query="searchQuery"
      v-model:category-filter="categoryFilter"
      v-model:base-filter="baseFilter"
    />

    <section class="content-area">
      <header class="topbar">
        <div>
          <p class="eyebrow">Cocktail Library</p>
          <h2>Classic Cocktail Collection</h2>
          <p v-if="loadNotice" class="cocktail-load-notice">{{ loadNotice }}</p>
        </div>
        <button class="ghost-button" type="button" @click="resetFilters">重置筛选</button>
      </header>

      <section class="layout-grid">
        <CocktailList
          :cocktails="filteredCocktails"
          :selected-key="cocktailKey(activeCocktail)"
          @select="selectCocktail"
        />
        <CocktailDetail
          ref="detailRef"
          :cocktail="activeCocktail"
          @deleted="handleCocktailDeleted"
          @need-login="openLoginModal"
        />
      </section>
    </section>

    <LoginModal :open="loginModalOpen" :message="loginModalMessage" @close="loginModalOpen = false" />
  </main>
</template>

<script setup>
import { computed, nextTick, onMounted, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import CocktailSidebar from "@/components/CocktailSidebar.vue";
import CocktailList from "@/components/CocktailList.vue";
import CocktailDetail from "@/components/CocktailDetail.vue";
import LoginModal from "@/components/LoginModal.vue";
import { baseSpiritLabels, categoryLabels, cocktails as staticCocktails } from "@/data/cocktails";
import { supabase } from "@/lib/supabase";
import { cocktailKey, mapUserCocktailRow, USER_COCKTAIL_SELECT } from "@/lib/user-cocktails";

const route = useRoute();
const router = useRouter();
const searchQuery = ref("");
const categoryFilter = ref("all");
const baseFilter = ref("all");
const allCocktails = ref([...staticCocktails]);
const activeCocktail = ref(staticCocktails[0]);
const loadNotice = ref("");
const loginModalOpen = ref(false);
const loginModalMessage = ref("请先登录账号，再发布评论或点赞。");
const detailRef = ref(null);

const filteredCocktails = computed(() => {
  const query = searchQuery.value.trim().toLowerCase();

  return allCocktails.value.filter((cocktail) => {
    const matchesCategory = categoryFilter.value === "all" || cocktail.category === categoryFilter.value;
    const matchesBase = baseFilter.value === "all" || cocktail.base === baseFilter.value;
    const categoryLabel = categoryLabels[cocktail.category];
    const baseLabel = baseSpiritLabels[cocktail.base];
    const searchable = [
      cocktail.name,
      cocktail.zhName,
      categoryLabel.en,
      categoryLabel.zh,
      baseLabel.en,
      baseLabel.zh,
      cocktail.naming,
      cocktail.story,
      cocktail.profile,
      cocktail.method,
      ...cocktail.ingredients,
    ]
      .join(" ")
      .toLowerCase();

    return matchesCategory && matchesBase && searchable.includes(query);
  });
});

watch(filteredCocktails, (list) => {
  if (!list.length) {
    activeCocktail.value = null;
    return;
  }
  if (!list.some((item) => cocktailKey(item) === cocktailKey(activeCocktail.value))) {
    activeCocktail.value = list[0];
  }
});

onMounted(loadUserCocktails);

async function loadUserCocktails() {
  if (!supabase) return;
  const { data, error } = await supabase
    .from("user_cocktails")
    .select(USER_COCKTAIL_SELECT)
    .order("created_at", { ascending: false });

  if (error) {
    loadNotice.value = "自定义酒款暂时无法加载。";
    return;
  }

  const customCocktails = (data || []).map(mapUserCocktailRow);
  allCocktails.value = [...customCocktails, ...staticCocktails];

  const focusId = String(route.query.updated || route.query.created || "");
  activeCocktail.value =
    customCocktails.find((item) => item.id === focusId) ||
    allCocktails.value.find((item) => cocktailKey(item) === cocktailKey(activeCocktail.value)) ||
    allCocktails.value[0];
  loadNotice.value = route.query.updated ? "酒款资料已更新。" : "";
}

function resetFilters() {
  searchQuery.value = "";
  categoryFilter.value = "all";
  baseFilter.value = "all";
  activeCocktail.value = allCocktails.value[0] || null;
}

function selectCocktail(cocktail) {
  activeCocktail.value = cocktail;
  if (!window.matchMedia("(max-width: 720px)").matches) return;
  nextTick(() => {
    detailRef.value?.$el?.scrollIntoView({ behavior: "smooth", block: "start" });
  });
}

async function handleCocktailDeleted({ id, warning }) {
  allCocktails.value = allCocktails.value.filter((cocktail) => cocktail.id !== id);
  activeCocktail.value = filteredCocktails.value[0] || null;
  loadNotice.value = warning || "酒款已删除。";
  await router.replace({ name: "cocktails" });
}

function openLoginModal(message) {
  loginModalMessage.value = message || "请先登录账号，再发布评论或点赞。";
  loginModalOpen.value = true;
}
</script>

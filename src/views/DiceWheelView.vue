<template>
  <div class="dice-wheel-page">
    <main class="dice-wheel-shell">
      <header class="dice-wheel-header">
        <RouterLink to="/menu">返回功能菜单</RouterLink>
        <RouterLink to="/account">账号中心</RouterLink>
      </header>

      <section class="dice-wheel-hero">
        <p class="eyebrow">Lucky Utilities</p>
        <h1>摇骰子 · 转转盘<span>设定内容、抽取并保存结果</span></h1>
      </section>

      <section class="dice-wheel-grid">
        <article class="dice-card">
          <img
            class="tool-card-decoration dice-card-decoration"
            src="/assets/dice-cats-cutout.png"
            alt=""
            aria-hidden="true"
          />
          <header>
            <h3>摇骰子</h3>
          </header>

          <label>
            骰子数量
            <input v-model.number="diceCount" type="number" min="1" max="20" />
          </label>

          <button type="button" class="primary" @click="rollDice">摇一摇</button>

          <div v-if="lastDiceRoll" class="dice-result">
            <p>本次结果</p>
            <div class="dice-counts">
              <span v-for="face in 6" :key="face">
                <strong>{{ face }}</strong>
                <em>{{ diceCounts(lastDiceRoll)[face - 1] }} 个</em>
              </span>
            </div>
            <time>{{ formatTime(lastDiceRoll.at) }}</time>
          </div>
        </article>

        <article class="wheel-card">
          <img
            class="tool-card-decoration wheel-card-decoration"
            src="/assets/wheel-guitar-cat-cutout.png"
            alt=""
            aria-hidden="true"
          />
          <header>
            <h3>转转盘</h3>
            <button type="button" @click="clearWheelHistory">清空记录</button>
          </header>

          <div class="wheel-stage">
            <span class="wheel-pointer" aria-hidden="true"></span>
            <div class="roulette-wheel" :style="wheelStyle">
              <span
                v-for="(option, index) in wheelOptions"
                :key="`${option}-${index}`"
                class="wheel-label"
                :style="wheelLabelStyle(index)"
              >
                {{ option }}
              </span>
              <button
                type="button"
                class="wheel-hub"
                :disabled="!wheelOptions.length || isSpinning"
                @click="spinWheel"
              >
                {{ isSpinning ? "转动中" : "开始" }}
              </button>
            </div>
          </div>

          <label>
            转盘内容（每行一个）
            <textarea
              v-model="wheelInput"
              rows="8"
              placeholder="例如：&#10;真心话&#10;大冒险&#10;喝一口"
            ></textarea>
          </label>

          <div class="wheel-inline">
            <label>
              指定结果（可选）
              <select v-model="forcedWheelResult">
                <option value="">随机</option>
                <option v-for="option in wheelOptions" :key="option" :value="option">{{ option }}</option>
              </select>
            </label>
            <button type="button" @click="saveWheelOptions">保存转盘内容</button>
          </div>

          <div v-if="lastWheelResult" class="wheel-result">
            <p>本次结果：{{ lastWheelResult.result }}</p>
            <time>{{ formatTime(lastWheelResult.at) }}</time>
          </div>

          <ul class="history-list">
            <li v-for="item in wheelHistory" :key="item.id">
              <strong>{{ item.result }}</strong>
              <time>{{ formatTime(item.at) }}</time>
            </li>
            <li v-if="!wheelHistory.length" class="empty">暂无记录</li>
          </ul>
        </article>
      </section>
    </main>
  </div>
</template>

<script setup>
import { computed, ref } from "vue";
import { RouterLink } from "vue-router";

const DICE_HISTORY_KEY = "drink_dice_history_v1";
const WHEEL_OPTIONS_KEY = "drink_wheel_options_v1";
const WHEEL_HISTORY_KEY = "drink_wheel_history_v1";

function safeRead(key, fallback) {
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return fallback;
    const parsed = JSON.parse(raw);
    return Array.isArray(fallback) ? (Array.isArray(parsed) ? parsed : fallback) : parsed ?? fallback;
  } catch {
    return fallback;
  }
}

function safeWrite(key, value) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // ignore storage write failure
  }
}

function uid(prefix) {
  return `${prefix}-${Math.random().toString(36).slice(2, 9)}-${Date.now()}`;
}

const diceCount = ref(2);
const diceHistory = ref(safeRead(DICE_HISTORY_KEY, []));

const wheelOptions = ref(safeRead(WHEEL_OPTIONS_KEY, ["真心话", "大冒险", "喝一口"]));
const wheelInput = ref(wheelOptions.value.join("\n"));
const forcedWheelResult = ref("");
const wheelHistory = ref(safeRead(WHEEL_HISTORY_KEY, []));
const wheelRotation = ref(0);
const isSpinning = ref(false);
const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

const lastDiceRoll = computed(() => diceHistory.value[0] || null);
const lastWheelResult = computed(() => wheelHistory.value[0] || null);
const wheelColors = ["#1d3217", "#d39858", "#85431e", "#304728", "#eaceaa", "#b98a45"];
const wheelStyle = computed(() => {
  const count = wheelOptions.value.length;
  if (!count) {
    return {
      background: "var(--paper)",
      transform: `rotate(${wheelRotation.value}deg)`,
    };
  }
  const step = 360 / count;
  const stops = wheelOptions.value.map((_, index) => {
    const start = index * step;
    const end = (index + 1) * step;
    return `${wheelColors[index % wheelColors.length]} ${start}deg ${end}deg`;
  });
  return {
    background: `conic-gradient(from -90deg, ${stops.join(", ")})`,
    transform: `rotate(${wheelRotation.value}deg)`,
  };
});

function normalizeCount(count) {
  const n = Number(count);
  if (!Number.isFinite(n)) return 2;
  return Math.max(1, Math.min(20, Math.floor(n)));
}

function rollDice() {
  diceCount.value = normalizeCount(diceCount.value);
  const values = Array.from({ length: diceCount.value }, () => Math.floor(Math.random() * 6) + 1);
  const counts = Array(6).fill(0);
  values.forEach((value) => {
    counts[value - 1] += 1;
  });
  const item = { id: uid("dice"), counts, at: new Date().toISOString() };
  diceHistory.value = [item];
  safeWrite(DICE_HISTORY_KEY, diceHistory.value);
}

function diceCounts(item) {
  if (Array.isArray(item?.counts) && item.counts.length === 6) return item.counts;
  const counts = Array(6).fill(0);
  if (Array.isArray(item?.values)) {
    item.values.forEach((value) => {
      if (value >= 1 && value <= 6) counts[value - 1] += 1;
    });
  }
  return counts;
}

function parseWheelInput(value) {
  return value
    .split(/\r?\n|,/g)
    .map((s) => s.trim())
    .filter(Boolean)
    .slice(0, 100);
}

function saveWheelOptions() {
  const parsed = parseWheelInput(wheelInput.value);
  wheelOptions.value = parsed;
  if (forcedWheelResult.value && !parsed.includes(forcedWheelResult.value)) {
    forcedWheelResult.value = "";
  }
  safeWrite(WHEEL_OPTIONS_KEY, wheelOptions.value);
}

function wheelLabelStyle(index) {
  const count = Math.max(wheelOptions.value.length, 1);
  const angle = index * (360 / count) + 180 / count;
  const radians = (angle * Math.PI) / 180;
  const left = 50 + Math.sin(radians) * 33;
  const top = 50 - Math.cos(radians) * 33;
  let textAngle = ((angle - 90) % 360 + 360) % 360;
  if (textAngle > 90 && textAngle < 270) textAngle += 180;
  return {
    left: `${left}%`,
    top: `${top}%`,
    transform: `translate(-50%, -50%) rotate(${textAngle}deg)`,
  };
}

function spinWheel() {
  if (!wheelOptions.value.length || isSpinning.value) return;
  saveWheelOptions();
  if (!wheelOptions.value.length) return;

  const result =
    forcedWheelResult.value && wheelOptions.value.includes(forcedWheelResult.value)
      ? forcedWheelResult.value
      : wheelOptions.value[Math.floor(Math.random() * wheelOptions.value.length)];
  const resultIndex = wheelOptions.value.indexOf(result);
  const segment = 360 / wheelOptions.value.length;
  const target = -(resultIndex * segment + segment / 2);
  const currentNormalized = ((wheelRotation.value % 360) + 360) % 360;
  const targetNormalized = ((target % 360) + 360) % 360;
  const forward = (targetNormalized - currentNormalized + 360) % 360;
  const spinDuration = prefersReducedMotion ? 0 : 3600;

  isSpinning.value = true;
  wheelRotation.value += (prefersReducedMotion ? 0 : 360 * 6) + forward;

  window.setTimeout(() => {
    const item = { id: uid("wheel"), result, at: new Date().toISOString() };
    wheelHistory.value = [item, ...wheelHistory.value].slice(0, 100);
    safeWrite(WHEEL_HISTORY_KEY, wheelHistory.value);
    isSpinning.value = false;
  }, spinDuration);
}

function clearWheelHistory() {
  wheelHistory.value = [];
  safeWrite(WHEEL_HISTORY_KEY, []);
}

function formatTime(value) {
  return new Intl.DateTimeFormat("zh-CN", {
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).format(new Date(value));
}
</script>

<style scoped>
.dice-wheel-page {
  height: 100vh;
  height: 100dvh;
  margin: 0;
  overflow: hidden;
  color: var(--ink);
  background:
    linear-gradient(rgba(255, 248, 234, 0.72), rgba(241, 223, 189, 0.76)),
    url("/assets/green-flowers.webp") center / cover no-repeat,
    linear-gradient(135deg, #173d20 0%, #3b672d 48%, #092c1d 100%);
}

.dice-wheel-shell {
  width: min(1240px, calc(100vw - 32px));
  height: 100%;
  margin: 0 auto;
  padding: clamp(12px, 2vw, 24px);
  display: flex;
  flex-direction: column;
}

.dice-wheel-header {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
}

.dice-wheel-header a {
  color: var(--garlic);
  font-weight: 700;
  letter-spacing: 0.08em;
  text-decoration: none;
}

.dice-wheel-hero {
  margin-top: 4px;
  flex: 0 0 auto;
}

.dice-wheel-hero h1 {
  margin: 2px 0 0;
  color: var(--coffee);
  font-size: clamp(1.8rem, 3.8vw, 3.2rem);
}

.dice-wheel-hero h1 span {
  display: block;
  margin-top: 3px;
  color: var(--garlic);
  font-family: "Noto Serif SC", serif;
  font-size: 0.96rem;
  letter-spacing: 0.12em;
}

.dice-wheel-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 14px;
  margin-top: 8px;
  min-height: 0;
  flex: 1 1 auto;
}

.dice-card,
.wheel-card {
  position: relative;
  isolation: isolate;
  min-height: 0;
  overflow: hidden;
  border: 1px solid rgba(52, 21, 15, 0.16);
  padding: 12px;
  background: rgba(251, 242, 223, 0.9);
  box-shadow: var(--shadow);
  display: grid;
  gap: 8px;
  align-content: start;
}

.wheel-card {
  grid-template-columns: minmax(200px, 0.9fr) minmax(0, 1.1fr);
  grid-template-rows: auto auto auto auto minmax(0, 1fr);
  align-items: start;
}

.dice-card header,
.wheel-card header {
  position: relative;
  z-index: 2;
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.wheel-card > header {
  grid-column: 1 / -1;
}

.wheel-card > .wheel-stage {
  grid-column: 1;
  grid-row: 2 / span 4;
  align-self: center;
}

.wheel-card > label,
.wheel-card > .wheel-inline,
.wheel-card > .wheel-result,
.wheel-card > .history-list {
  grid-column: 2;
}

.wheel-card > label {
  grid-row: 2;
}

.wheel-card > .wheel-inline {
  grid-row: 3;
}

.wheel-card > .wheel-result {
  grid-row: 4;
}

.wheel-card > .history-list {
  grid-row: 5;
}

h3 {
  margin: 0;
  color: var(--coffee);
}

label {
  position: relative;
  z-index: 2;
  display: grid;
  gap: 6px;
  color: var(--muted);
  font-family: "Noto Serif SC", serif;
}

input,
textarea,
select,
button {
  position: relative;
  z-index: 2;
  border: 1px solid rgba(52, 21, 15, 0.24);
  padding: 9px 10px;
  color: var(--ink);
  background: rgba(255, 248, 234, 0.7);
}

textarea {
  height: clamp(62px, 9vh, 88px);
  min-height: 62px;
  resize: vertical;
}

.primary {
  font-weight: 700;
  color: var(--coffee);
}

.wheel-inline {
  display: grid;
  grid-template-columns: 1fr auto;
  gap: 8px;
  align-items: end;
}

.dice-result,
.wheel-result {
  position: relative;
  z-index: 2;
  border: 1px dashed rgba(52, 21, 15, 0.26);
  padding: 10px;
  background: rgba(255, 248, 234, 0.44);
}

.dice-result p,
.wheel-result p {
  margin: 0 0 8px;
  color: var(--coffee);
  font-weight: 700;
}

.dice-counts {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 7px;
  margin-bottom: 8px;
}

.dice-counts span {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  border: 1px solid rgba(52, 21, 15, 0.13);
  padding: 7px 9px;
  background: rgba(251, 242, 223, 0.72);
}

.dice-counts strong {
  width: 26px;
  height: 26px;
  display: grid;
  place-items: center;
  border-radius: 50%;
  color: var(--cream);
  background: var(--olive);
}

.dice-counts em {
  color: var(--coffee);
  font-style: normal;
  font-weight: 700;
}

.dice-result time,
.wheel-result time {
  color: var(--muted);
  font-size: 0.78rem;
}

.wheel-stage {
  position: relative;
  z-index: 2;
  width: min(100%, clamp(190px, 28vh, 280px));
  aspect-ratio: 1;
  margin: 0 auto;
  display: grid;
  place-items: center;
  transform: translateY(-100px);
  filter: drop-shadow(0 18px 22px rgba(52, 21, 15, 0.2));
}

.wheel-pointer {
  position: absolute;
  z-index: 5;
  top: -5px;
  left: 50%;
  width: 0;
  height: 0;
  border-left: 15px solid transparent;
  border-right: 15px solid transparent;
  border-top: 38px solid var(--coffee);
  transform: translateX(-50%);
  filter: drop-shadow(0 3px 2px rgba(21, 12, 12, 0.24));
}

.roulette-wheel {
  position: relative;
  width: 92%;
  aspect-ratio: 1;
  overflow: hidden;
  border: 8px solid var(--cream);
  border-radius: 50%;
  box-shadow:
    0 0 0 3px var(--gold-foil),
    inset 0 0 0 2px rgba(255, 248, 234, 0.48);
  transition: transform 3.6s cubic-bezier(0.12, 0.62, 0.08, 1);
}

.roulette-wheel::before {
  content: "";
  position: absolute;
  inset: 8px;
  z-index: 1;
  border: 1px solid rgba(251, 242, 223, 0.48);
  border-radius: 50%;
  pointer-events: none;
}

.wheel-label {
  position: absolute;
  z-index: 2;
  width: min(104px, 29%);
  overflow: hidden;
  border: 1px solid rgba(251, 242, 223, 0.18);
  border-radius: 999px;
  padding: 2px 5px;
  color: #fff8ea;
  font-family: "Noto Serif SC", serif;
  font-size: clamp(0.62rem, 1.5vw, 0.82rem);
  font-weight: 800;
  line-height: 1.15;
  text-align: center;
  text-overflow: ellipsis;
  white-space: nowrap;
  background: rgba(21, 12, 12, 0.34);
  text-shadow:
    0 1px 2px rgba(21, 12, 12, 0.92),
    0 0 5px rgba(21, 12, 12, 0.45);
  transform-origin: center;
  pointer-events: none;
}

.wheel-hub {
  position: absolute;
  z-index: 4;
  top: 50%;
  left: 50%;
  width: 24%;
  aspect-ratio: 1;
  display: grid;
  place-items: center;
  border: 4px solid var(--cream);
  padding: 0;
  border-radius: 50%;
  color: var(--champagne);
  font-family: "Noto Serif SC", serif;
  font-size: clamp(0.62rem, 1.5vw, 0.82rem);
  font-weight: 800;
  letter-spacing: 0.08em;
  background: var(--coffee);
  transform: translate(-50%, -50%);
  box-shadow: 0 4px 12px rgba(21, 12, 12, 0.3);
  cursor: pointer;
  transition:
    background 0.2s ease,
    color 0.2s ease;
}

.wheel-hub:hover:not(:disabled) {
  color: var(--coffee);
  background: var(--champagne);
}

.wheel-hub:disabled {
  cursor: wait;
}

.history-list {
  position: relative;
  z-index: 2;
  list-style: none;
  margin: 0;
  padding: 0;
  display: grid;
  gap: 8px;
  overflow: auto;
  scrollbar-color: var(--gold-foil) rgba(52, 21, 15, 0.08);
}

.history-list li {
  border: 1px solid rgba(52, 21, 15, 0.12);
  padding: 8px 9px;
  background: rgba(255, 248, 234, 0.5);
  display: grid;
  gap: 4px;
}

.wheel-card .history-list {
  max-height: 212px;
}

.wheel-card .history-list li {
  min-height: 36px;
  padding: 6px 8px;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
}

.tool-card-decoration {
  position: absolute;
  z-index: 0;
  pointer-events: none;
  user-select: none;
  object-fit: contain;
  filter: saturate(0.86) contrast(1.04);
}

.dice-card-decoration {
  inset: 0;
  width: 100%;
  height: 100%;
  max-height: none;
  object-fit: cover;
  object-position: center 38%;
  opacity: 0.18;
}

.wheel-card-decoration {
  inset: 0;
  width: 100%;
  height: 100%;
  max-height: none;
  object-fit: cover;
  object-position: center;
  transform: translateY(50px);
  opacity: 0.15;
}

.history-list strong {
  color: var(--coffee);
}

.history-list time {
  color: var(--muted);
  font-size: 0.76rem;
}

.empty {
  color: var(--muted);
  text-align: center;
}

@media (max-width: 940px) {
  .dice-wheel-page {
    height: auto;
    min-height: 100dvh;
    overflow: auto;
  }

  .dice-wheel-shell {
    height: auto;
  }

  .dice-wheel-grid {
    grid-template-columns: 1fr;
  }

  .wheel-card {
    grid-template-columns: 1fr;
    grid-template-rows: auto;
  }

  .wheel-card > header,
  .wheel-card > .wheel-stage,
  .wheel-card > label,
  .wheel-card > .wheel-inline,
  .wheel-card > .wheel-result,
  .wheel-card > .history-list {
    grid-column: 1;
    grid-row: auto;
  }

  .wheel-inline {
    grid-template-columns: 1fr;
  }

  .wheel-stage {
    margin-block: 8px 12px;
    transform: none;
  }
}

@media (max-width: 720px) {
  .dice-wheel-shell {
    width: calc(100% - 16px);
    padding:
      max(12px, env(safe-area-inset-top))
      max(12px, env(safe-area-inset-right))
      calc(88px + env(safe-area-inset-bottom))
      max(12px, env(safe-area-inset-left));
  }

  .dice-wheel-header a {
    min-height: 44px;
    display: inline-flex;
    align-items: center;
    padding: 10px 12px;
  }

  input,
  textarea,
  select,
  button {
    min-height: 44px;
    font-size: 16px;
  }

  .wheel-stage {
    width: min(78vw, 280px);
  }

  .wheel-label {
    width: min(84px, 27%);
    font-size: clamp(0.68rem, 2.8vw, 0.78rem);
  }

  .wheel-hub {
    width: max(24%, 48px);
    min-width: 48px;
    min-height: 48px;
  }
}

@media (max-width: 520px) {
  .dice-wheel-shell {
    width: calc(100% - 16px);
    padding:
      max(12px, env(safe-area-inset-top))
      max(12px, env(safe-area-inset-right))
      calc(76px + env(safe-area-inset-bottom))
      max(12px, env(safe-area-inset-left));
  }

  .dice-wheel-header a {
    min-height: 44px;
    display: inline-flex;
    align-items: center;
    padding: 10px 12px;
  }

  .dice-wheel-hero h1 {
    font-size: clamp(1.8rem, 10vw, 2.4rem);
    line-height: 1.08;
  }

  .dice-wheel-hero h1 span {
    font-size: 0.82rem;
    letter-spacing: 0.08em;
  }

  .dice-card,
  .wheel-card {
    padding: 12px 10px;
  }

  .dice-card header,
  .wheel-card header {
    align-items: flex-start;
    flex-wrap: wrap;
    gap: 8px;
  }

  .dice-card h3,
  .wheel-card h3 {
    display: block;
    font-size: 1.15rem;
    line-height: 1.2;
    letter-spacing: 0;
  }

  input,
  textarea,
  select,
  button {
    min-height: 44px;
    padding: 10px 12px;
    font-size: 16px;
  }

  textarea {
    height: auto;
    min-height: 112px;
  }

  .dice-counts {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }

  .wheel-stage {
    width: min(78vw, 240px);
  }

  .wheel-label {
    width: min(72px, 24%);
    padding: 2px 4px;
    font-size: clamp(0.68rem, 3.2vw, 0.74rem);
  }

  .wheel-hub {
    width: max(24%, 44px);
    min-width: 44px;
    min-height: 44px;
    font-size: 0.7rem;
  }

  .wheel-card .history-list {
    max-height: min(160px, 28dvh);
  }

  .wheel-card .history-list li strong {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .wheel-card .history-list time {
    flex-shrink: 0;
    font-size: 0.7rem;
  }

  .tool-card-decoration {
    opacity: 0.08;
  }

  .wheel-card-decoration {
    transform: none;
  }
}

@media (prefers-reduced-motion: reduce) {
  .roulette-wheel {
    transition: none;
  }
}

@media (max-height: 480px) and (orientation: landscape) {
  .dice-wheel-page {
    height: auto;
    min-height: 100dvh;
    overflow: auto;
  }

  .wheel-stage {
    width: min(34vw, 160px);
    margin-block: 4px 8px;
    transform: none;
  }

  .wheel-card .history-list {
    max-height: 120px;
  }
}
</style>

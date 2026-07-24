// V6/E3 (PLAN6 Wave E): Funkelpark „Candy Alley" stall sheet — the §E6 panel
// that sells the three park-exclusive foods (data/foods.js V6_PARK_FOODS,
// park: true). Purchases go through the EXISTING single money path
// economy.buyFood(store, foodId, 1) — catalog price, reason 'shop', inventory
// add — so bought park food lands in the fridge tray and feeds through the
// same care flow as any shop food (no special-casing anywhere downstream).
// The normal shop hides park foods (shopScreen.js park-filter, also E3).
//
// Frozen E1 integration export (see /tmp handoff E3-exports-for-E1.txt):
//   openParkStall(ui, stallId?, deps?) → boolean
// deps { store, audio } are cached from the first wired call (or an explicit
// initParkStall) so the bare contract call openParkStall(ui) works afterward;
// dev builds additionally fall back to the window.__gooby harness handle.
//
// Module level stays DOM-free (node:test import chain rule) — all DOM work
// happens inside mount().

import { t, getLang } from '../data/strings.js';
// V6/E3: strings.js is frozen (§E0.1-8) — E1 commits the v6-park import pair;
// until then keys resolve through the local tx() fallback (G52 precedent).
import { EN as PARK_EN, DE as PARK_DE } from '../data/strings/v6-park.js';
import { PARK_STALLS } from '../park/parkDressing.js';
import { getFood, visibleFoodValues } from '../data/foods.js';
import { buyFood, canAfford } from '../systems/economy.js';
import { count as invCount } from '../systems/inventory.js';
import { icon } from './icons.js';
import { getFoodIcon, foodIconIds } from './foodIcons.js';

/** t() first, then the owned v6-park EN/DE table (shopScreen tx() pattern). */
function tx(key) {
  const v = t(key);
  if (v !== key) return v;
  return (getLang() === 'de' ? PARK_DE : PARK_EN)[key] ?? key;
}

// V6/E3 TEMP until foodIcons.js ships the 3 park glyphs (D3-owned file — see
// /tmp/gooby-v6-handoffs/E3-foodicons-needed.txt): explicit nearby-glyph
// fallbacks so the stall sheet never renders the plate-warning fallback.
// parkFoodIcon degrades to plain getFoodIcon the moment the ids exist, so
// removing this map after integration is optional cleanup, not a blocker.
/** @type {Readonly<Record<string, string>>} */
export const PARK_FOOD_ICON_FALLBACK = Object.freeze({
  cottonCandy: 'lollypop',
  softServe: 'ice-cream',
  waffle: 'pancakes',
});

/**
 * Authored icon for a park food — the real glyph once foodIcons.js has it,
 * else the explicit nearby fallback (never the console-warning plate).
 * @param {string} foodId
 * @param {number} [size] px
 * @returns {string} SVG markup
 */
export function parkFoodIcon(foodId, size = 24) {
  const have = new Set(foodIconIds());
  const id = have.has(foodId) ? foodId : (PARK_FOOD_ICON_FALLBACK[foodId] ?? foodId);
  return getFoodIcon(id, size);
}

// ---------------------------------------------------------------------------
// Panel
// ---------------------------------------------------------------------------

// Owned styles (styles.css belongs to D4 this wave) — injected once.
const PARK_STALL_CSS = `
.panel-parkStall{max-height:78vh;overflow-y:auto;}
.e3-stall-head{display:flex;align-items:center;justify-content:space-between;gap:.5rem;margin-bottom:.25rem;}
.e3-stall-title{margin:0;font-size:1.25rem;}
.e3-stall-hint{font-size:.75rem;opacity:.75;margin-bottom:.625rem;}
.e3-stall-list{display:flex;flex-direction:column;gap:.625rem;}
.e3-stall-card{display:flex;align-items:center;gap:.625rem;padding:.625rem;border-radius:1rem;background:rgba(74,59,54,.06);border:.125rem solid transparent;text-align:left;}
.e3-stall-card.e3-focus{border-color:var(--teal,#59C9B9);}
.e3-stall-awning{flex:none;width:3rem;height:3rem;border-radius:.75rem;display:flex;align-items:center;justify-content:center;background:repeating-linear-gradient(90deg,var(--e3-tint) 0 .5rem,#fff .5rem 1rem);}
.e3-stall-awning svg{filter:drop-shadow(0 1px 0 rgba(255,255,255,.8));}
.e3-stall-info{flex:1;min-width:0;display:flex;flex-direction:column;gap:.125rem;}
.e3-stall-name{font-weight:900;font-size:.875rem;}
.e3-stall-food{display:flex;align-items:center;gap:.375rem;font-size:.8125rem;flex-wrap:wrap;}
.e3-stall-pitch{font-size:.6875rem;opacity:.7;}
.e3-stall-buy{flex:none;display:flex;flex-direction:column;align-items:center;gap:.25rem;}
.e3-stall-count{font-size:.625rem;font-weight:800;opacity:.7;}
`;

let cssInjected = false;
function ensureStyles() {
  if (cssInjected || typeof document === 'undefined') return;
  cssInjected = true;
  if (document.querySelector('style[data-owner="v6e3-parkstall"]')) return;
  const style = document.createElement('style');
  style.dataset.owner = 'v6e3-parkstall';
  style.textContent = PARK_STALL_CSS;
  document.head.appendChild(style);
}

/** @type {{store: object, ui: object, audio: object}|null} */
let cachedDeps = null;
let registeredOn = null; // the ui instance the panel is registered on

/** No-op audio shim (harness fallback has no audio handle). */
const AUDIO_SHIM = { play() {} };

/**
 * Optional explicit boot hook (idempotent): cache deps + register the panel.
 * E1 may call this once from the park scene enter(); afterwards the bare
 * frozen contract call openParkStall(ui) needs no deps anywhere.
 * @param {{store: object, ui: object, audio?: object}} deps
 */
export function initParkStall(deps) {
  if (!deps?.store || !deps?.ui) return;
  cachedDeps = { store: deps.store, ui: deps.ui, audio: deps.audio ?? AUDIO_SHIM };
  registerPanel(deps.ui);
}

/** Register the 'parkStall' §E6 panel once per ui instance. */
function registerPanel(ui) {
  if (registeredOn === ui) return;
  registeredOn = ui;
  ui.registerPanel('parkStall', createParkStallPanel());
}

/**
 * Open the Candy Alley stall sheet (frozen E1 export).
 * @param {object} ui createUi() instance
 * @param {string|null} [stallId] optional PARK_STALLS id to highlight
 *   ('cottonCandy' | 'softServe' | 'waffle'); null lists all three
 * @param {{store: object, audio?: object}|null} [deps] pass { store, audio }
 *   on the first call (cached afterwards); dev builds fall back to the
 *   window.__gooby harness handle
 * @returns {boolean} ui.openPanel result (false when unresolvable/already open)
 */
export function openParkStall(ui, stallId = null, deps = null) {
  if (deps?.store) {
    cachedDeps = { store: deps.store, ui, audio: deps.audio ?? AUDIO_SHIM };
  } else if (!cachedDeps) {
    const harness = typeof window !== 'undefined' ? window.__gooby : null;
    if (harness?.store) cachedDeps = { store: harness.store, ui, audio: AUDIO_SHIM };
  }
  if (!cachedDeps?.store) {
    console.warn('[parkStall] no store available — pass deps {store, audio} on first call');
    return false;
  }
  registerPanel(ui);
  return ui.openPanel('parkStall', { stallId });
}

/** @returns {{mount: Function, unmount: Function}} §E6 panel module */
function createParkStallPanel() {
  /** @type {Array<() => void>} */
  let subs = [];
  /** @type {HTMLElement|null} */
  let panelEl = null;
  /** @type {string|null} */
  let focusStall = null;

  function render() {
    if (!panelEl || !cachedDeps) return;
    const { store, ui, audio } = cachedDeps;
    ensureStyles();
    panelEl.innerHTML = `
      <div class="e3-stall-head">
        <h2 class="e3-stall-title">${tx('park.alley.title')}</h2>
        <span class="shop-coins ac-chip">${icon('coin', 18)}<span class="e3-coins-n">${store.get('coins') ?? 0}</span></span>
      </div>
      <div class="e3-stall-hint">${tx('park.alley.hint')}</div>
      <div class="e3-stall-list"></div>`;
    const list = panelEl.querySelector('.e3-stall-list');
    const inv = store.get('inventory') ?? {};

    for (const stall of PARK_STALLS) {
      const food = getFood(stall.foodId);
      if (!food) continue; // catalog missing — never render a broken card
      const owned = invCount(inv, food.id);
      const chips = visibleFoodValues(food)
        .map(([stat, value]) => `<span class="g79-food-chip">+${value}${icon(stat, 12)}</span>`)
        .join('');
      const card = document.createElement('div');
      card.className = `e3-stall-card${focusStall === stall.id ? ' e3-focus' : ''}`;
      card.dataset.stallId = stall.id;
      card.style.setProperty('--e3-tint', stall.tint);
      card.innerHTML = `
        <span class="e3-stall-awning">${parkFoodIcon(food.id, 30)}</span>
        <span class="e3-stall-info">
          <span class="e3-stall-name">${tx(stall.signKey)}</span>
          <span class="e3-stall-food">
            ${tx(food.nameKey)}
            ${food.junk ? `<span class="g22-junk" aria-hidden="true">${icon('candy', 13)}</span>` : ''}
            <span class="g79-food-values">${chips}</span>
          </span>
          <span class="e3-stall-pitch">${tx(`park.stall.${stall.id}.pitch`)}</span>
        </span>
        <span class="e3-stall-buy">
          <button class="btn btn-teal e3-buy" ${canAfford(store, food.price) ? '' : 'disabled'}>
            ${icon('coin', 13)}${food.price}
          </button>
          ${owned > 0 ? `<span class="e3-stall-count">×${owned}</span>` : ''}
        </span>`;
      card.querySelector('.e3-buy').addEventListener('click', () => {
        audio.play('ui.tap');
        const res = buyFood(store, food.id, 1);
        if (res.ok) {
          audio.play('coin.spend');
          ui.toast('toast.foodBought', { name: tx(food.nameKey), n: 1 });
        } else if (res.reason === 'coins') {
          ui.toast('toast.notEnoughCoins');
        }
        render();
      });
      list.appendChild(card);
    }
  }

  return {
    /** @param {HTMLElement} el @param {{stallId?: string|null}} [params] */
    mount(el, params = {}) {
      panelEl = el;
      focusStall = PARK_STALLS.some((s) => s.id === params.stallId) ? params.stallId : null;
      render();
      const store = cachedDeps?.store;
      if (store?.on) {
        subs = [
          store.on('coinsChanged', (coins) => {
            const n = panelEl?.querySelector('.e3-coins-n');
            if (n) n.textContent = String(coins);
          }),
        ];
      }
      cachedDeps?.audio.play('ui.open');
    },
    unmount() {
      for (const off of subs) off?.();
      subs = [];
      panelEl = null;
      focusStall = null;
    },
  };
}

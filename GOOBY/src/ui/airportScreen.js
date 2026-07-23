// V5/VACATION — the airport panel (ui.openPanel('airport')): destination
// booking cards while Gooby is home, the away countdown / pickup / taxi
// sheet while a vacation is active. Registered from the marked V5/VACATION
// block in ui/hud.js (initShopTrip registration pattern); entry points are
// the cityDestinations picker's airport row (systems/shopTrip.js), the
// travel chooser's airport link and the HUD vacation chip.
//
// V6/B2 (PLAN6 Wave B): the booking board renders the canonical NINE
// destinations. Rows gated by recap progress (data/vacations.js
// unlockRecapLevel vs recap.lastRecapLevel, pure isVacationUnlocked) render
// as MYSTERY cards while locked — lock glyph + '???' + 'Reach level X'
// hint, the V5 mystery-sticker presentation language: no destination name,
// subtitle, icon or accent color is disclosed before unlock, and locked
// cards are non-interactive <div>s (no data-dest, no click path). The
// booking/pickup/taxi flows below are byte-compatible with V5.
//
// Reunion juice: confetti rides gfx/particles.js burstConfettiDom via a
// DYNAMIC import (particles.js statically imports three — keep it out of
// this module's graph), jingle.arrival + the 'vacation.welcomeBack' toast.
//
// Dev harness (§E9 spirit, dev builds only): ?vacation=away|return|overdue
// seeds the matching slice WITHOUT paying (beach destination), and
// ?vacation=open just opens this panel after boot. V6/B2 adds
// ?recaplevel=N — pins recap.lastRecapLevel so the board's lock states can
// be screenshot at any milestone (e.g. ?vacation=open&recaplevel=15).
// Listed in data/harnessParams.js (card 18).

import { t } from '../data/strings.js';
import { icon } from './icons.js';
import { VACATIONS, getVacation, isVacationUnlocked } from '../data/vacations.js';
import {
  VACATION,
  VACATION_PHASE,
  sliceOf,
  bookSlice,
  postcardsDue,
  remainingMs,
  formatCountdown,
} from '../systems/vacation.js';
import { bookVacation, pickupVacation, payTaxiReturn } from '../systems/economy.js';
import { now } from '../core/clock.js';

// V3/G33-style injected CSS (rem units; 1px hairlines exempt). The card rows
// reuse the §C9.2 .dest-option look via their own classes so the styles stay
// self-contained (no dependency on the shopTrip block). V6/B2: the sheet
// caps at the viewport and the card list scrolls (9 rows no longer fit a
// 320×568 screen) — same max-height pattern as .panel-settingsDisplay.
const AIRPORT_CSS = `
.panel-airport{max-height:100%;overflow:hidden;display:flex;flex-direction:column;}
.v5-air{display:flex;flex-direction:column;gap:0.5rem;min-height:0;overflow-y:auto;overscroll-behavior:contain;-webkit-overflow-scrolling:touch;padding:0.125rem;}
.v5-air-title{margin:0;text-align:center;}
.v5-air-sub{margin:0 0 0.25rem;text-align:center;font-size:0.8125rem;color:var(--brown);opacity:.7;font-weight:700;}
.v5-air-card{display:flex;align-items:center;gap:0.625rem;width:100%;min-height:max(44px,3.5rem);border:none;border-radius:var(--radius-row, 1rem);padding:0.5625rem 0.75rem;background:var(--frost);color:var(--brown);font-family:inherit;text-align:left;box-shadow:var(--shadow-soft);cursor:pointer;-webkit-tap-highlight-color:transparent;border-left:0.375rem solid var(--v5-air-accent, var(--teal));flex:none;}
.v5-air-card:active{transform:scale(.98);}
.v5-air-card svg{color:var(--v5-air-accent, var(--teal));flex:none;}
.v5-air-name{display:block;font-weight:800;font-size:0.9375rem;}
.v5-air-flavor{display:block;font-size:0.75rem;opacity:.7;font-weight:700;}
.v5-air-price{margin-left:auto;flex:none;font-size:0.75rem;font-weight:800;opacity:.85;white-space:nowrap;}
.v5-air-locked{cursor:default;--v5-air-accent:var(--ink-faint);background:rgba(255,255,255,.6);}
.v5-air-locked:active{transform:none;}
.v5-air-locked .v5-air-name,.v5-air-locked .v5-air-flavor{opacity:.45;}
.v5-air-locked .v5-air-price{opacity:.55;}
.v5-air-wait{display:flex;flex-direction:column;align-items:center;gap:0.5rem;text-align:center;padding:0.375rem 0;}
.v5-air-wait-big{font-size:2.25rem;line-height:1;}
.v5-air-wait-big svg{color:var(--teal);}
.v5-air-body{margin:0;font-size:0.875rem;font-weight:700;color:var(--brown);}
.v5-air-count{font-variant-numeric:tabular-nums;font-weight:800;}
.v5-air-cards{font-size:0.75rem;font-weight:700;color:var(--brown);opacity:.6;}
`;

/**
 * V6/B2: one booking-board card. Unlocked rows keep the exact V5 markup
 * (data-dest carries the booking id); LOCKED rows are mystery cards — a
 * non-interactive <div> with the lock glyph, '???' and the level hint. No
 * destination-identifying detail (name/sub/icon/accent) leaks before
 * unlock; the only stated fact is the recap level that reveals it.
 * @param {import('../data/vacations.js').VacationDest} d
 * @param {number} lastRecapLevel recap.lastRecapLevel
 * @returns {string} card HTML
 */
function bookingCard(d, lastRecapLevel) {
  if (!isVacationUnlocked(d, lastRecapLevel)) {
    return `
      <div class="v5-air-card v5-air-locked" aria-disabled="true">
        ${icon('lock', 26)}
        <span>
          <span class="v5-air-name">${t('vacation.dest.locked.name')}</span>
          <span class="v5-air-flavor">${t('vacation.dest.locked.sub')}</span>
        </span>
        <span class="v5-air-price">${t('vacation.dest.locked.hint', { level: d.unlockRecapLevel })}</span>
      </div>`;
  }
  return `
    <button class="v5-air-card" data-dest="${d.id}" style="--v5-air-accent:${d.color}">
      ${icon(d.icon, 26)}
      <span>
        <span class="v5-air-name">${t(`vacation.dest.${d.id}.name`)}</span>
        <span class="v5-air-flavor">${t(`vacation.dest.${d.id}.sub`)}</span>
      </span>
      <span class="v5-air-price">${t('vacation.dest.priceDays', { price: d.price, days: d.days })}</span>
    </button>`;
}

/**
 * Register the 'airport' panel + the dev ?vacation= harness. Idempotent.
 * @param {{store: object, ui: object, audio: object}} deps
 */
export function registerAirport({ store, ui, audio }) {
  if (typeof document === 'undefined') return;
  if (!document.querySelector('style[data-owner="v5-airport"]')) {
    const style = document.createElement('style');
    style.dataset.owner = 'v5-airport';
    style.textContent = AIRPORT_CSS;
    document.head.appendChild(style);
  }

  /** @type {Array<() => void>} */
  let subs = [];
  /** @type {HTMLElement|null} */
  let panelEl = null;
  let countTimer = 0;

  /** Reunion tail shared by pickup + taxi: confetti, jingle, toast, close. */
  function celebrate(res) {
    audio.play('jingle.arrival');
    ui.toast('vacation.welcomeBack', { coins: res.souvenir ?? 0 });
    // Confetti over the whole app layer — dynamic import keeps three.js out
    // of this module's static graph (burstConfettiDom is DOM-only at call).
    import('../gfx/particles.js')
      .then((mod) => mod.burstConfettiDom(ui.el ?? document.body, { count: 40 }))
      .catch(() => { /* reduced environments celebrate quietly */ });
    ui.closePanel('airport');
  }

  function render() {
    if (!panelEl) return;
    const state = store.get();
    const v = sliceOf(state);
    const nowMs = now();

    if (v.phase === VACATION_PHASE.NONE) {
      // ---- booking: one card per catalog destination (V6/B2: 9 rows;
      // recap-gated rows render as mystery cards until unlocked) ----------
      const recapLevel = Math.max(0, Math.floor(Number(state?.recap?.lastRecapLevel) || 0));
      panelEl.innerHTML = `
        <div class="v5-air">
          <h2 class="perm-title v5-air-title">${icon('globe', 22)} ${t('vacation.airport.title')}</h2>
          <p class="v5-air-sub">${t('vacation.airport.sub')}</p>
          ${VACATIONS.map((d) => bookingCard(d, recapLevel)).join('')}
          <button class="btn btn-ghost v5-air-later">${t('ui.later')}</button>
        </div>`;
      // Only unlocked cards carry data-dest — mystery cards have no booking
      // path at all (the selector skips them by construction).
      for (const card of panelEl.querySelectorAll('.v5-air-card[data-dest]')) {
        card.addEventListener('click', () => {
          const destId = card.dataset.dest;
          const res = bookVacation(store, destId);
          if (res.ok) {
            audio.play('ui.confirmBig');
            ui.toast('vacation.booked', {
              name: t(`vacation.dest.${destId}.name`),
              days: getVacation(destId)?.days ?? 3,
            });
            ui.closePanel('airport');
          } else if (res.reason === 'coins') {
            audio.play('ui.error');
            ui.toast('vacation.noCoins');
          } else if (res.reason === 'sleeping') {
            ui.toast('toast.sleeping');
          }
        });
      }
      panelEl.querySelector('.v5-air-later')?.addEventListener('click', () => ui.closePanel('airport'));
      return;
    }

    // ---- active vacation: countdown / pickup / taxi -------------------------
    const dest = getVacation(v.destId);
    const remain = formatCountdown(remainingMs(state, nowMs));
    const cards = postcardsDue(v, nowMs);
    const away = v.phase === VACATION_PHASE.AWAY;
    const overdue = v.phase === VACATION_PHASE.OVERDUE;
    panelEl.innerHTML = `
      <div class="v5-air v5-air-wait">
        <h2 class="perm-title v5-air-title">${away
          ? `${icon(dest?.icon ?? 'globe', 22)} ${t(`vacation.dest.${v.destId}.name`)}`
          : t('vacation.pickup.title')}</h2>
        <span class="v5-air-wait-big" aria-hidden="true">${icon(overdue ? 'car' : (away ? (dest?.icon ?? 'globe') : 'globe'), 44)}</span>
        <p class="v5-air-body">${away
          ? t('vacation.pickup.away', { t: `<span class="v5-air-count">${remain}</span>` })
          : overdue
            ? t('vacation.pickup.overdueBody', { fee: VACATION.TAXI_FEE })
            : t('vacation.pickup.body', { t: `<span class="v5-air-count">${remain}</span>` })}</p>
        ${cards > 0 ? `<span class="v5-air-cards">${icon('book', 14)} ${t('vacation.postcard', { text: t(`vacation.postcard.${v.destId}`) })}</span>` : ''}
        <div class="mg-btn-row">
          ${overdue
            ? `<button class="btn btn-teal v5-air-taxi">${t('vacation.pickup.taxiBtn', { fee: VACATION.TAXI_FEE })}</button>`
            : away
              ? ''
              : `<button class="btn btn-teal v5-air-pickup">${t('vacation.pickup.btn')}</button>`}
          <button class="btn btn-ghost v5-air-later">${t('ui.later')}</button>
        </div>
      </div>`;
    panelEl.querySelector('.v5-air-pickup')?.addEventListener('click', () => {
      const res = pickupVacation(store);
      if (res.ok) celebrate(res);
      else render(); // phase slipped (e.g. turned overdue) — re-render
    });
    panelEl.querySelector('.v5-air-taxi')?.addEventListener('click', () => {
      const res = payTaxiReturn(store);
      if (res.ok) {
        audio.play('coin.spend');
        celebrate(res);
      } else render();
    });
    panelEl.querySelector('.v5-air-later')?.addEventListener('click', () => ui.closePanel('airport'));
  }

  ui.registerPanel('airport', {
    /** @param {HTMLElement} el */
    mount(el) {
      panelEl = el;
      render();
      subs.push(store.on('vacationChanged', render));
      // V6/B2: a recap completing while the sheet is open re-evaluates the
      // lock states (rare — recaps only start on quiet home enters — but
      // the subscription keeps the board honest).
      subs.push(store.on('recapChanged', render));
      // 1 s countdown refresh only while a vacation is active (cheap re-render
      // of a small sheet — matches the HUD chip cadence).
      countTimer = setInterval(() => {
        if (sliceOf(store.get()).phase !== VACATION_PHASE.NONE) render();
      }, 1000);
    },
    unmount() {
      for (const off of subs) off?.();
      subs = [];
      clearInterval(countTimer);
      countTimer = 0;
      panelEl = null;
    },
  });

  // ---- dev harness: ?vacation=away|return|overdue|open (§E9 spirit) --------
  const isDev = typeof import.meta !== 'undefined' && import.meta.env?.DEV;
  const query = isDev && typeof location !== 'undefined'
    ? new URLSearchParams(location.search)
    : null;
  const param = query ? query.get('vacation') : null;
  // V6/B2: ?recaplevel=N pins recap.lastRecapLevel (dev only) so the
  // board's mystery-card states are screenshot-able at any milestone —
  // ?level= alone never touches the recap slice (main.js only advances it
  // through real level-ups).
  const recapLevelParam = query ? Number(query.get('recaplevel')) : NaN;
  if (Number.isFinite(recapLevelParam)) {
    store.update((state) => {
      const raw = state.recap != null && typeof state.recap === 'object' && !Array.isArray(state.recap)
        ? state.recap
        : {};
      state.recap = {
        lastRecapLevel: 0, baseline: {}, baselineAt: 0, pendingLevel: 0, history: [],
        ...raw,
      };
      state.recap.lastRecapLevel = Math.max(0, Math.floor(recapLevelParam));
    });
  }
  if (param) {
    const nowMs = now();
    /** @type {object|null} */
    let seed = null;
    if (param === 'away') {
      seed = bookSlice(store.get('vacation'), 'beach', nowMs);
    } else if (param === 'return') {
      const booked = bookSlice(store.get('vacation'), 'beach', nowMs);
      const shift = booked.returnAt - nowMs + 60000; // landed a minute ago
      seed = {
        ...booked,
        phase: VACATION_PHASE.RETURN_READY,
        bookedAt: booked.bookedAt - shift,
        returnAt: booked.returnAt - shift,
        pickupBy: booked.pickupBy - shift,
      };
      seed.postcards = postcardsDue(seed, nowMs);
    } else if (param === 'overdue') {
      const booked = bookSlice(store.get('vacation'), 'beach', nowMs);
      const shift = booked.pickupBy - nowMs + 3600000; // window closed 1 h ago
      seed = {
        ...booked,
        phase: VACATION_PHASE.OVERDUE,
        bookedAt: booked.bookedAt - shift,
        returnAt: booked.returnAt - shift,
        pickupBy: booked.pickupBy - shift,
      };
      seed.postcards = postcardsDue(seed, nowMs);
    }
    if (seed) {
      store.update((state) => { state.vacation = seed; });
      store.emit?.('vacationChanged', { phase: seed.phase, destId: seed.destId });
    }
    // 'away' only seeds (the home scene demos the chip + hidden Gooby);
    // the pickup states and 'open' also open the sheet after the boot fade.
    if (param === 'return' || param === 'overdue' || param === 'open') {
      setTimeout(() => ui.openPanel('airport'), 800);
    }
  }
}

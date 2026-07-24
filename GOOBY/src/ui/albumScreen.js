// Sticker album (PLAN2 §C6, agent V2/G23 + PLAN3 §C5.3, agent V3/G34) — ui
// screen 'album', opened by the HUD profile flow / ?open=album (L1).
//
// 3.0 layout (§B5/§C5.3): a TOP-LEVEL tab strip splits the screen into
//   „Sticker"     the v2 collections album (4 sets, claim rewards) — UNCHANGED
//   „Stickerbuch" the §C5 sticker book (V6/F1: 84 regular): 14 pages (6
//                 slots each, 2×3 grid), horizontal swipe + the V6/F1 titled
//                 page-chip rail (icon + title + n/6 count, ←/→ keyboard
//                 paging — replaces the V3 page dots), themed page titles
//                 from STICKER_PAGES. Locked = mystery „?" placeholder
//                 (V5/STICKERS: the art img is NEVER rendered/fetched while
//                 locked — no padlock and no grey-filter reveal; V6/F1 tints
//                 the box in its page accent + glyph watermark + table
//                 number, all page-generic); unlocked = full AI art with a
//                 300 ms pop-in + confetti on first view. Tap any slot →
//                 detail sheet (art large, title, flavor; locked shows the
//                 mystery box + hint line instead). „NEU" pink dot until
//                 seen (stickers.seen via the engine). Header shows n/84.
// Book styles are component-injected module CSS (G33 owns styles.css this
// wave); new 3.0 rules are rem-based so the §B3 uiScale mechanism scales them.
//
// 4.0 (PLAN4 §C-SYS9.2/§C-SYS5.4, agent V4/G59): a THIRD top-level tab
//   „Fotos"       the IndexedDB photo gallery — 3-col grid of square thumbs
//                 (newest first, lazy objectURLs revoked on unmount), count
//                 header „n/40" (+ replacement footnote at 40/40), full-screen
//                 viewer (photo, date line, Teilen/Sichern via ui/shareImage,
//                 Löschen with confirm sheet, swipe left/right, ✕), empty
//                 state deep-linking to photo mode. Visiting the tab stamps
//                 the §C-SYS9.3 session-seen mark (clears the HUD badge dot).
// PLUS the sticker book's secret 29th slot on page 5 (§C-SYS5.4 render half):
// „?"-heart silhouette, „Geheim", code-word hint; header stays n/28 and gains
// a „+💗" suffix once herzGooby is unlocked.

import { COLLECTION_SETS, getCollectionSet } from '../data/collections.js';
import { countOf, setProgress, isSetComplete } from '../systems/collections.js';
import { getAchievementsEngine } from '../systems/achievementsEngine.js';
// V3/G34: sticker-book catalog + engine (both G34-owned — no lazy import needed)
// V6/F1: + STICKER_PAGES (page rail titles/icons/tints + mystery-box tinting)
import { STICKERS, STICKERS_BY_ID, stickerPages, STICKER_PAGES } from '../data/stickers.js';
import { getStickerBook, stickerCounts } from '../systems/stickerBook.js';
import { burstConfettiDom } from '../gfx/particles.js';
import { t, getLang } from '../data/strings.js';
import { icon } from './icons.js';
import { attachBackdropDismiss } from './backdropDismiss.js'; // V5/FIX-UI: armed click-outside (no click-through)
// V4/G59: gallery store + pure decisions + §E0.1-11 string seam (PLAN4 §C-SYS9)
import * as photoStore from '../core/photoStore.js';
import { GALLERY, sortNewestFirst, markGallerySeen, mirrorSlice, tG } from '../systems/gallery.logic.js';
import { shareImage } from './shareImage.js';
import { now } from '../core/clock.js';

/** Set id → tab icon (icons.js names — reuse per §E0.2). */
const SET_ICONS = { fish: 'fish', veggies: 'carrot', landmarks: 'home', treats: 'hunger' };

// ── V4/G59 (§C-SYS5.4): the secret sticker is a BONUS outside the count ─────
// The book header counts the REGULAR defs only — n/48 since V5 (G53's
// herzGooby catalog append must not shift the target), and the secret slot is
// rendered explicitly on page 5. Until G53's data/stickers.js append lands
// (wave-1b concurrency, §E0.1-11) a placeholder def keeps the render whole —
// the PNG is ART-GATE-1-committed either way.
const REGULAR_STICKERS = STICKERS.filter((s) => s.id !== 'herzGooby');

// ── V6/F1 (PLAN6 Wave F): page-rail + mystery-box presentation lookups ──────
/** sticker id → 1-based table number (the locked-slot „#n" badge — position
 * only, leaks no art/name). */
const STICKER_NO = new Map(REGULAR_STICKERS.map((s, i) => [s.id, i + 1]));
/** sticker id → its STICKER_PAGES meta (positional — pages()[i] ↔ PAGES[i]),
 * for the per-page mystery tint + watermark glyph. */
const PAGE_META = (() => {
  const m = new Map();
  stickerPages().forEach((defs, i) => {
    for (const d of defs) m.set(d.id, STICKER_PAGES[i]);
  });
  return m;
})();
const FALLBACK_PAGE_META = Object.freeze({ icon: 'star', tint: '#E3C6DE' });
/** Page title: themed pages carry a titleKey; legacy pages fall back to the
 * V3 „Seite n" numbering. */
const pageTitle = (i) =>
  (STICKER_PAGES[i]?.titleKey ? t(STICKER_PAGES[i].titleKey) : t('stickerbook.page', { n: i + 1 }));
// ── end V6/F1 lookups ────────────────────────────────────────────────────────
const SECRET_STICKER = () => STICKERS_BY_ID.herzGooby ?? {
  id: 'herzGooby',
  nameKey: 'stickerbook.herzGooby.name',
  flavorKey: 'stickerbook.herzGooby.flavor',
  hintKey: 'stickerbook.secretHint',
  art: 'assets/stickers/herzGooby.png',
};

/** V4/G59: bespoke inline SVGs (icons.js is shared §E0.2 — G23 precedent). */
const G59_ICONS = {
  camera: '<path d="M4 7h3l1.6-2.4A1.5 1.5 0 0 1 9.9 4h4.2a1.5 1.5 0 0 1 1.3.6L17 7h3a1.5 1.5 0 0 1 1.5 1.5V19a1.5 1.5 0 0 1-1.5 1.5H4A1.5 1.5 0 0 1 2.5 19V8.5A1.5 1.5 0 0 1 4 7z"/><circle cx="12" cy="13.5" r="4" fill="#fff" opacity="0.55"/><circle cx="12" cy="13.5" r="2.1"/>',
  share: '<circle cx="6" cy="12" r="2.6"/><circle cx="17.5" cy="5.5" r="2.6"/><circle cx="17.5" cy="18.5" r="2.6"/><path d="M8.3 10.8l6.9-4M8.3 13.2l6.9 4" stroke="currentColor" stroke-width="2" fill="none"/>',
  trash: '<path d="M5 7h14l-1.2 13a2 2 0 0 1-2 1.8H8.2a2 2 0 0 1-2-1.8L5 7z"/><path d="M3.5 7h17M9.5 4.5h5" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" fill="none"/><path d="M10 10.5v6M14 10.5v6" stroke="#fff" stroke-width="1.8" stroke-linecap="round" opacity="0.7"/>',
};
const g59Icon = (name, size = 18) =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">${G59_ICONS[name]}</svg>`;

/** V3/FIX-C: make long DE compounds line-breakable. Chrome's hyphens:auto
 * (a) skips words that already contain a hyphen („Stadt-Sehenswürdigkeiten"
 * stays one unbreakable token) and (b) never hyphenates a word that starts
 * mid-line — so a zero-width space re-tokenizes hard hyphens and soft
 * hyphens (rendered only at an actual break) give ≥10-char words mid-line
 * break points. Display-only (never fed back into state). */
const hy = (s) => String(s)
  .replace(/-/g, '-\u200B')
  .replace(/[A-Za-zÀ-ÿ]{10,}/g, (w) => w.replace(/(.{6})(?=.{3})/g, '$1\u00AD'));

/** Deterministic pastel tint per sticker id (procedural art, §D4). */
function tintOf(setId, entryId) {
  let h = 0;
  const s = `${setId}.${entryId}`;
  for (let i = 0; i < s.length; i += 1) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  return `hsl(${h % 360} 62% 72%)`;
}

/** V6/B3 (PLAN6 Wave B): deterministic polaroid tilt for the Fotos grid —
 * the SAME grid index always leans the SAME way (re-renders must never make
 * the photo wall shiver), neighbours alternate direction so the wall reads
 * hand-pinned rather than wind-blown. Pure (index → degrees, one decimal,
 * |deg| ≤ 2.2) and exported for test/screenThemeDetails.test.js.
 * @param {number} index 0-based grid position
 * @returns {number} rotation in degrees */
export function polaroidJitter(index) {
  const n = Math.abs(Math.floor(Number(index) || 0));
  const h = ((n + 1) * 2654435761) >>> 0; // Knuth multiplicative hash
  const mag = 0.8 + ((h >>> 8) % 141) / 100; // 0.8° … 2.2°
  return Math.round((n % 2 === 0 ? -mag : mag) * 10) / 10;
}

/* V4/G-UI: G23 block swept px→rem (§B3 — was the last FILE_ALLOW holdout in
   px-audit; values ÷16, matching the sibling screens' rem conventions:
   27.5rem rail, 0.625rem gaps, max(44px,2.75rem) tap floors). */
const ALBUM_CSS = `
.screen-album{justify-content:flex-start;overflow-y:auto;-webkit-overflow-scrolling:touch;}
.g23-al-head{width:100%;max-width:27.5rem;display:flex;align-items:center;gap:0.625rem;margin:0.375rem 0 0.375rem;flex:none;}
.g23-al-title{flex:1;min-width:0;margin:0;font-size:clamp(0.9375rem,5.5vw,1.875rem);font-weight:800;color:var(--brown);display:-webkit-box;-webkit-box-orient:vertical;-webkit-line-clamp:2;line-clamp:2;overflow:hidden;overflow-wrap:break-word;hyphens:auto;line-height:1.1;} /* V3/FIX-C: 6vw→5.5vw. V4/FIX-UI: wrap to 2 hyphenated lines instead of „Stickeralb…" at the 320px squeeze */
.g23-al-count{flex:none;background:var(--paper);border-radius:999px;padding:0.5rem 0.75rem;font-size:0.9375rem;font-weight:800;color:var(--teal-dark);box-shadow:0 0 0 1px var(--outline-soft),0 2px 6px rgba(74,59,54,.1);font-variant-numeric:tabular-nums;} /* V4/UI-DEEP: .ac-chip pill language */
/* V3/FIX-C (E9/E13 P1): a single 4-tab row can never hold the DE set names
   („Stadt-Sehenswürdigkeiten") at 320px — the strip wraps into a 2×2 grid and
   labels wrap to 2 hyphenated lines instead of ellipsizing („Stadt-…").
   V4/UI-DEEP: visuals moved to the shared .ac-tabbar/.ac-tab kit (active =
   leaf fill via aria-selected) — only layout stays in these rules. */
.g23-al-tabs{width:100%;max-width:27.5rem;display:flex;flex-wrap:wrap;flex:none;margin-bottom:0.5rem;}
.g23-al-tabs .g23-al-tab.ac-tab-label{flex:1 1 40%;} /* V4/UI-DEEP: outweigh the kit's flex:1 1 0 — keep the V3 2×2 wrap at 320px */
.g23-al-tab{flex:1 1 40%;min-width:0;display:inline-flex;align-items:center;justify-content:center;gap:0.3125rem;border:none;min-height:max(44px,2.75rem);padding:0.5625rem 0.25rem;font-family:inherit;font-size:0.75rem;font-weight:800;cursor:pointer;-webkit-tap-highlight-color:transparent;} /* V2 fix (E16): >=44px hit target */
.g23-al-tab span{min-width:0;display:-webkit-box;-webkit-box-orient:vertical;-webkit-line-clamp:2;line-clamp:2;overflow:hidden;overflow-wrap:break-word;hyphens:auto;text-align:center;line-height:1.15;}
.g23-al-page{width:100%;max-width:27.5rem;background:var(--white);border-radius:var(--card-radius);box-shadow:var(--shadow-soft);padding:0.875rem;flex:none;margin-bottom:1.125rem;}
.g23-al-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(4.75rem,1fr));gap:0.625rem;}
.g23-al-slot{position:relative;display:flex;flex-direction:column;align-items:center;gap:0.25rem;border:none;background:none;padding:0;font-family:inherit;cursor:pointer;-webkit-tap-highlight-color:transparent;}
.g23-al-art{width:3.625rem;height:3.625rem;border-radius:1rem;display:flex;align-items:center;justify-content:center;box-shadow:var(--shadow-soft);}
.g23-al-slot.g23-owned .g23-al-art{color:rgba(42,26,60,.75);}
.g23-al-slot.g23-missing .g23-al-art{background:var(--track-soft)!important;color:rgba(74,59,54,.28);}
.g23-al-name{max-width:5rem;font-size:0.625rem;font-weight:800;color:var(--brown);text-align:center;line-height:1.15;overflow:hidden;text-overflow:ellipsis;}
.g23-al-slot.g23-missing .g23-al-name{opacity:.45;}
.g23-al-n{position:absolute;top:-0.25rem;right:0.125rem;background:var(--pink);color:#fff;border-radius:999px;font-size:0.625rem;font-weight:800;padding:0.125rem 0.375rem;font-variant-numeric:tabular-nums;}
.g23-al-flavor{min-height:1rem;margin-top:0.625rem;font-size:0.75rem;font-weight:700;color:var(--brown);opacity:.72;text-align:center;} /* V4/G-UI: .65→.72 — body-text contrast */
.g23-al-setrow{display:flex;align-items:center;gap:0.625rem;margin-top:0.75rem;}
.g23-al-bar{flex:1;height:0.5625rem;border-radius:999px;background:var(--track-soft);overflow:hidden;}
.g23-al-fill{display:block;height:100%;border-radius:999px;background:var(--teal);transition:width 300ms ease;}
.g23-al-progress{flex:none;font-size:0.75rem;font-weight:800;opacity:.6;font-variant-numeric:tabular-nums;}
.g23-al-claim{flex:none;display:inline-flex;align-items:center;justify-content:center;gap:0.3125rem;border:none;border-radius:999px;min-height:max(44px,2.75rem);min-width:max(44px,2.75rem);padding:0.5rem 0.875rem;font-family:inherit;font-size:0.75rem;font-weight:800;cursor:pointer;background:rgba(74,59,54,.08);color:rgba(74,59,54,.45);-webkit-tap-highlight-color:transparent;} /* V2 fix (E16): >=44px hit target */
.g23-al-claim.g23-ready{background:var(--yellow);color:#fff;box-shadow:var(--shadow-soft);}
.g23-al-claim.g23-claimed-btn{color:var(--teal-dark);}

/* ── V3/G34: top-level album tabs + Stickerbuch (§C5.3 — rem-based) ─────── */
/* V4/UI-DEEP: toptabs ride the shared .ac-tabbar/.ac-tab kit too (active =
   leaf via aria-selected) — layout-only rules remain here. */
.g34-al-toptabs{width:100%;max-width:27.5rem;display:flex;flex:none;margin-bottom:0.5rem;}
/* V3/FIX-C (E8 P2): vw-capped font + inline (non-absolute) count badge — the
   absolutely-positioned badge used to sit ON the tab text at 320px @ 130% DE. */
.g34-al-toptab{flex:1;min-width:0;display:inline-flex;align-items:center;justify-content:center;gap:0.3125rem;border:none;min-height:max(44px,2.75rem);padding:0.5625rem 0.25rem;font-family:inherit;font-size:min(0.8125rem,4vw);font-weight:800;cursor:pointer;-webkit-tap-highlight-color:transparent;position:relative;}
.g34-al-toptab>span:not(.g34-sb-newdot){min-width:0;display:-webkit-box;-webkit-box-orient:vertical;-webkit-line-clamp:2;line-clamp:2;overflow:hidden;overflow-wrap:break-word;hyphens:auto;text-align:center;line-height:1.15;} /* V4/FIX-UI: „Stickerbuch" wraps instead of „Stic…" at 320px @ 130% */
.g34-al-toptab .g34-sb-newdot{position:static;flex:none;}
/* V4/FIX-UI: a single 3-tab row can never hold „Sticker Book" + NEU badge at
   the 320px squeeze — wrap the strip 2+1 (the V3/FIX-C 2×2 set-tab pattern). */
@media (max-width:340px){
  .g34-al-toptabs{flex-wrap:wrap;}
  .g34-al-toptab{flex:1 1 40%;}
}
@media (max-width:400px){
  :root[data-ui-scale="115"] .g34-al-toptabs,
  :root[data-ui-scale="130"] .g34-al-toptabs{flex-wrap:wrap;}
  :root[data-ui-scale="115"] .g34-al-toptab,
  :root[data-ui-scale="130"] .g34-al-toptab{flex:1 1 40%;}
}
.g34-sb-pager{width:100%;max-width:27.5rem;flex:none;display:flex;overflow-x:auto;scroll-snap-type:x mandatory;-webkit-overflow-scrolling:touch;scrollbar-width:none;border-radius:var(--card-radius);}
.g34-sb-pager::-webkit-scrollbar{display:none;}
.g34-sb-page{flex:0 0 100%;min-width:100%;scroll-snap-align:center;scroll-snap-stop:always;background:var(--white);border-radius:var(--card-radius);box-shadow:var(--shadow-soft);padding:0.875rem;box-sizing:border-box;}
.g34-sb-pagetitle{margin:0 0 0.625rem;font-size:0.8125rem;font-weight:800;color:var(--brown);opacity:.55;text-align:center;}
.g34-sb-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:0.625rem;}
.g34-sb-slot{position:relative;display:flex;flex-direction:column;align-items:center;gap:0.25rem;border:none;background:rgba(255,246,236,.75);border-radius:1rem;padding:0.5rem 0.25rem 0.375rem;font-family:inherit;cursor:pointer;-webkit-tap-highlight-color:transparent;min-height:max(44px,2.75rem);}
.g34-sb-art{width:100%;max-width:7rem;aspect-ratio:1;border-radius:0.75rem;object-fit:contain;display:block;}
/* V5/STICKERS: locked = mystery „?" placeholder (secret-slot style for EVERY
   locked slot). The art <img> is never rendered while locked, so no src is
   fetched and no grey-filter reveal is possible (was: grayscale silhouette). */
.g34-sb-mystery{display:flex;align-items:center;justify-content:center;background:var(--track-soft);color:rgba(74,59,54,.38);font-size:2.5rem;font-weight:800;user-select:none;}
.g34-sb-name{max-width:100%;font-size:0.6875rem;font-weight:800;color:var(--brown);text-align:center;line-height:1.15;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
.g34-sb-slot.g34-locked .g34-sb-name{opacity:.4;}
.g34-sb-newdot{background:var(--pink);color:#fff;border-radius:999px;font-size:0.5625rem;font-weight:800;padding:0.125rem 0.375rem;letter-spacing:.04em;}
.g34-sb-slot .g34-sb-newdot{position:absolute;top:0.25rem;right:0.375rem;}
.g34-sb-pop{animation:g34-sb-pop 300ms cubic-bezier(.34,1.56,.64,1);} /* §C5.3 300 ms pop-in */
@keyframes g34-sb-pop{0%{transform:scale(.2);opacity:0;}100%{transform:scale(1);opacity:1;}}
/* ── V6/F1 (PLAN6 Wave F): titled page-chip rail — replaces the V3 page dots
   (14 pages don't fit as dots). Horizontal scroll, snap-free (chips center
   themselves via scrollTo), ≥44px chip height (the V3/FIX-C tap floor). ── */
.f1-sb-rail{width:100%;max-width:27.5rem;flex:none;display:flex;gap:0.375rem;overflow-x:auto;-webkit-overflow-scrolling:touch;scrollbar-width:none;padding:0.125rem 0.125rem 0.375rem;margin:0 0 0.25rem;}
.f1-sb-rail::-webkit-scrollbar{display:none;}
.f1-sb-chip{flex:none;display:inline-flex;align-items:center;gap:0.3125rem;border:none;border-radius:999px;min-height:max(44px,2.75rem);padding:0.375rem 0.6875rem;font-family:inherit;font-size:0.6875rem;font-weight:800;color:var(--brown);background:var(--paper);box-shadow:0 0 0 1px var(--outline-soft);cursor:pointer;-webkit-tap-highlight-color:transparent;white-space:nowrap;transition:background 150ms ease,box-shadow 150ms ease;}
.f1-sb-chip svg{flex:none;opacity:.8;}
.f1-sb-chip-count{font-variant-numeric:tabular-nums;opacity:.55;font-size:0.625rem;}
.f1-sb-chip.f1-active{background:var(--f1-tint);box-shadow:0 0 0 2px rgba(74,59,54,.18),var(--shadow-soft);}
.f1-sb-chip.f1-active svg{opacity:1;}
/* V6/F1: page-tinted mystery tile — the locked-slot „?" box picks up its
   page's pastel accent + a low-opacity page-glyph watermark + the sticker's
   table number. STILL no <img>/art/name anywhere in the locked branch (the
   V5 no-fetch rule — the watermark is a shared ui/icons.js glyph). */
.f1-sb-tile{position:relative;overflow:hidden;background:color-mix(in srgb,var(--f1-tint) 55%,var(--white));display:flex;align-items:center;justify-content:center;}
.f1-sb-tile::after{content:'';position:absolute;inset:0.3125rem;border:2px dashed color-mix(in srgb,var(--f1-tint) 70%,rgba(74,59,54,.35));border-radius:0.5rem;opacity:.6;pointer-events:none;}
.f1-sb-tile .g34-sb-mystery{position:absolute;inset:0;background:none;}
.f1-sb-wm{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;color:rgba(74,59,54,.9);opacity:.13;transform:rotate(-12deg);}
.f1-sb-num{position:absolute;right:0.4375rem;bottom:0.3125rem;font-size:0.5625rem;font-weight:800;color:rgba(74,59,54,.5);font-variant-numeric:tabular-nums;z-index:1;}
/* the locked DETAIL sheet mystery box rides the same page tint */
.f1-sb-tint{background:color-mix(in srgb,var(--f1-tint) 55%,var(--white));}
.g34-sb-sheet{position:fixed;inset:0;z-index:var(--z-float);display:flex;align-items:center;justify-content:center;background:var(--veil);padding:1rem;} /* V4/UI-DEEP: token scrim + z-ladder (was literal plum) */
.g34-sb-card{position:relative;width:100%;max-width:20rem;background:var(--white);border-radius:1.375rem;box-shadow:var(--shadow-pop);padding:1.25rem 1rem 1.125rem;display:flex;flex-direction:column;align-items:center;gap:0.5rem;text-align:center;}
.g34-sb-card-art{width:min(60vw,13rem);aspect-ratio:1;object-fit:contain;}
.g34-sb-card-art.g34-sb-mystery{font-size:4.5rem;border-radius:1rem;} /* V5/STICKERS mystery detail sheet */
.g34-sb-card-title{margin:0;font-size:1.125rem;font-weight:800;color:var(--brown);}
.g34-sb-card-flavor{margin:0;font-size:0.8125rem;font-weight:700;color:var(--brown);opacity:.7;line-height:1.35;}
.g34-sb-card-hintlabel{margin:0.25rem 0 0;font-size:0.625rem;font-weight:800;letter-spacing:.08em;text-transform:uppercase;color:var(--teal-dark);opacity:.8;}
.g34-sb-close{position:absolute;top:0.375rem;right:0.375rem;border:none;background:rgba(74,59,54,.07);border-radius:999px;width:max(44px,2.75rem);height:max(44px,2.75rem);display:inline-flex;align-items:center;justify-content:center;color:var(--brown);cursor:pointer;-webkit-tap-highlight-color:transparent;}
/* ── end V3/G34 ── */

/* ── V4/G59: Fotos tab + viewer + secret slot (§C-SYS9.2/§C-SYS5.4 — rem) ── */
.g59-ph-wrap{width:100%;max-width:27.5rem;display:flex;flex-direction:column;align-items:center;flex:none;margin-bottom:1.125rem;}
.g59-ph-note{width:100%;margin:0 0 0.5rem;font-size:0.6875rem;font-weight:700;color:var(--brown);opacity:.72;text-align:center;} /* V4/G-UI: .55→.72 — instructional body-text contrast */
.g59-ph-grid{width:100%;display:grid;grid-template-columns:repeat(3,1fr);gap:0.375rem;}
.g59-ph-cell{position:relative;border:none;background:rgba(74,59,54,.08);border-radius:var(--radius-row);padding:0;aspect-ratio:1;min-width:0;min-height:max(44px,2.75rem);overflow:hidden;cursor:pointer;-webkit-tap-highlight-color:transparent;}
.g59-ph-img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;display:block;}
.g59-ph-empty{width:100%;background:var(--white);border-radius:var(--card-radius);box-shadow:var(--shadow-soft);padding:1.5rem 1rem;display:flex;flex-direction:column;align-items:center;gap:0.625rem;text-align:center;}
.g59-ph-empty-art{position:relative;width:6.5rem;height:6.5rem;border-radius:50%;background:rgba(244,156,187,.25);display:flex;align-items:center;justify-content:center;color:var(--pink);}
.g59-ph-empty-art .g59-ph-cam{position:absolute;right:0.125rem;bottom:0.25rem;width:2.375rem;height:2.375rem;border-radius:50%;background:var(--white);box-shadow:var(--shadow-soft);display:flex;align-items:center;justify-content:center;color:var(--teal-dark);}
.g59-ph-empty-txt{margin:0;font-size:0.9375rem;font-weight:800;color:var(--brown);}
.g59-ph-cta{display:inline-flex;align-items:center;gap:0.375rem;border:none;border-radius:999px;min-height:max(44px,2.75rem);padding:0.5625rem 1rem;font-family:inherit;font-size:0.8125rem;font-weight:800;background:var(--pink);color:#fff;box-shadow:var(--shadow-soft);cursor:pointer;-webkit-tap-highlight-color:transparent;}
.g59-vw{position:fixed;inset:0;z-index:var(--z-media);background:var(--veil-deep);display:flex;flex-direction:column;} /* V4/UI-DEEP: warm --veil-deep + media z-rung (was literal plum/70) */
.g59-vw-top{flex:none;display:flex;align-items:center;justify-content:space-between;gap:0.5rem;padding:max(0.5rem,var(--safe-top)) max(0.5rem,var(--safe-right)) 0.25rem max(0.5rem,var(--safe-left));}
.g59-vw-date{min-width:0;font-size:0.75rem;font-weight:700;color:#fff;opacity:.75;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-variant-numeric:tabular-nums;}
.g59-vw-close{flex:none;border:none;border-radius:50%;width:max(44px,2.75rem);height:max(44px,2.75rem);background:rgba(255,255,255,.14);color:#fff;display:inline-flex;align-items:center;justify-content:center;cursor:pointer;-webkit-tap-highlight-color:transparent;}
.g59-vw-stage{flex:1;min-height:0;display:flex;align-items:center;justify-content:center;padding:0.25rem 0.5rem;touch-action:pan-y;}
.g59-vw-img{max-width:100%;max-height:100%;object-fit:contain;border-radius:0.75rem;user-select:none;-webkit-user-drag:none;}
.g59-vw-btns{flex:none;display:flex;gap:0.5rem;justify-content:center;padding:0.5rem max(0.5rem,var(--safe-right)) calc(0.625rem + var(--safe-bottom)) max(0.5rem,var(--safe-left));}
.g59-vw-btn{display:inline-flex;align-items:center;justify-content:center;gap:0.375rem;border:none;border-radius:999px;min-height:max(44px,2.75rem);min-width:max(44px,2.75rem);padding:0.5625rem 1rem;font-family:inherit;font-size:min(0.8125rem,3.8vw);font-weight:800;cursor:pointer;box-shadow:var(--shadow-soft);-webkit-tap-highlight-color:transparent;background:var(--teal);color:#fff;}
.g59-vw-btn.g59-danger{background:rgba(255,255,255,.14);color:#FFB3C1;}
.g59-vw-confirm{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;background:rgba(24,14,34,.55);padding:1rem;}
.g59-vw-confirm-card{width:100%;max-width:17.5rem;background:var(--white);border-radius:var(--card-radius);box-shadow:0 12px 40px rgba(42,26,60,.35);padding:1rem;display:flex;flex-direction:column;gap:0.625rem;text-align:center;}
.g59-vw-confirm-card h3{margin:0;font-size:1rem;font-weight:800;color:var(--brown);}
.g59-vw-confirm-row{display:flex;gap:0.5rem;}
.g59-vw-confirm-row .g59-vw-btn{flex:1;}
.g59-vw-confirm-row .g59-cancel{background:rgba(74,59,54,.08);color:var(--brown);box-shadow:none;}
.g59-vw-confirm-row .g59-confirm-del{background:var(--pink);}
.g59-secret .g59-secret-badge{position:absolute;top:0.375rem;left:0.375rem;display:inline-flex;align-items:center;justify-content:center;color:var(--pink);opacity:.9;}
/* V5/STICKERS: the locked secret slot rides the shared .g34-sb-mystery box
   (the old absolutely-positioned .g59-secret-q overlay is gone with the
   grey-filter render). */
/* ── end V4/G59 ── */
`;

/**
 * Create + register the sticker album screen (ui screen 'album').
 * @param {{store: object, ui: object, audio: object}} deps
 */
export function registerAlbumScreen({ store, ui, audio }) {
  if (!document.querySelector('style[data-owner="g23-album"]')) {
    const style = document.createElement('style');
    style.dataset.owner = 'g23-album';
    style.textContent = ALBUM_CSS;
    document.head.appendChild(style);
  }

  /** @type {{off: Function}|null} */
  let live = null;
  let activeSet = COLLECTION_SETS[0]?.id ?? 'fish';
  /** V3/G34: top-level tab ('collections' | 'book') — survives re-renders. */
  let activeTab = 'collections';
  /** V3/G34: current book page (0-based) — survives the 1 Hz re-renders. */
  let bookPage = 0;
  /** Tapped sticker ('<setId>.<entryId>') — survives the store-change
   * re-renders (the time engine ticks 'change' every second). */
  let flavorKey = null;

  function mount(el, params = {}) {
    if (params.set && getCollectionSet(params.set)) activeSet = params.set;
    // V4/G59: third tab id 'photos' (§C-SYS9.2 — deep-linked by profile row)
    if (params.tab === 'book' || params.tab === 'collections' || params.tab === 'photos') activeTab = params.tab;
    flavorKey = null;
    bookPage = 0;

    // V3/G34: per-mount reveal bookkeeping (pop-in once per slot per mount;
    // confetti only on live locked→unlocked transitions while open — §C5.3).
    const poppedIds = new Set();
    let prevUnlocked = null;
    /** @type {HTMLElement|null} open detail sheet (rebuilt on re-render) */
    let sheetEl = null;
    let sheetStickerId = null;
    /** V3/FIX-C (E8 P2): sheet state at open time — re-renders only rebuild
     * the sheet when these change, so the §C5.3 first-view pop-in + confetti
     * survive the markSeen store-write (which used to re-render and replace
     * the card within a frame, killing the animation). */
    let sheetUnlockedAtOpen = null;
    let sheetLangAtOpen = null;

    // ── V4/G59: Fotos-tab state (§C-SYS9.2) ────────────────────────────────
    /** @type {import('../systems/gallery.logic.js').PhotoMeta[]|null} newest-first; null = stale */
    let photosCache = null;
    /** @type {Map<number, string>} photo id → thumb objectURL (revoked on unmount/delete) */
    const thumbUrls = new Map();
    /** async fill guard: stale list() resolutions must not touch the DOM */
    let photosToken = 0;
    /** @type {{el: HTMLElement, id: number, url: string|null}|null} open viewer */
    let viewer = null;

    function revokeThumbUrl(id) {
      const url = thumbUrls.get(id);
      if (url) URL.revokeObjectURL(url);
      thumbUrls.delete(id);
    }

    function revokeAllPhotoUrls() {
      for (const url of thumbUrls.values()) URL.revokeObjectURL(url);
      thumbUrls.clear();
    }
    // ── end V4/G59 state ───────────────────────────────────────────────────

    const head = document.createElement('div');
    head.className = 'g23-al-head';
    const backBtn = document.createElement('button');
    backBtn.className = 'btn btn-ghost btn-round';
    backBtn.setAttribute('aria-label', t('ui.back'));
    backBtn.innerHTML = icon('arrowLeft', 22);
    backBtn.addEventListener('click', () => {
      audio.play('ui.close');
      ui.closeAll();
    });
    const title = document.createElement('h1');
    title.className = 'g23-al-title';
    // V4/FIX-UI: lang attr feeds hyphens:auto so the 2-line title clamp can
    // break „Stickeralbum" (dictionary break: „Sticker-album") instead of
    // ellipsizing at the 320px squeeze. No hy() here — its fixed 6-char soft
    // hyphens would force the uglier „Sticke-ralbum" split on this word.
    title.setAttribute('lang', getLang());
    title.textContent = t('album.title');
    const count = document.createElement('div');
    count.className = 'g23-al-count';
    head.append(backBtn, title, count);
    el.appendChild(head);

    // --- V3/G34: top-level tab strip „Sticker" | „Stickerbuch" (§B5) ---
    const topTabs = document.createElement('div');
    topTabs.className = 'g34-al-toptabs ac-tabbar ac-tabbar-wrap'; // V4/UI-DEEP
    el.appendChild(topTabs);

    const body = document.createElement('div');
    body.style.cssText = 'width:100%;display:flex;flex-direction:column;align-items:center;flex:none;';
    el.appendChild(body);

    function closeSheet() {
      sheetEl?.remove();
      sheetEl = null;
      sheetStickerId = null;
    }

    /** §C5.3 detail sheet: large art + title + flavor (locked: hint). */
    function openSheet(def) {
      closeSheet();
      const c = store.get();
      const unlocked = !!c?.stickers?.unlocked?.[def.id];
      const firstView = unlocked && c?.stickers?.seen?.[def.id] !== true;
      sheetStickerId = def.id;
      sheetUnlockedAtOpen = unlocked; // V3/FIX-C: rebuild guard state
      sheetLangAtOpen = getLang();
      sheetEl = document.createElement('div');
      sheetEl.className = 'g34-sb-sheet';
      const card = document.createElement('div');
      card.className = `g34-sb-card${unlocked ? '' : ' g34-locked'}`;
      // V5/STICKERS: locked sheets render the mystery „?" box — NEVER an
      // <img src> (no art fetch, no grey-filter reveal). V6/F1: the box
      // rides the sticker's PAGE tint (page-generic, leaks nothing).
      card.innerHTML = `
        <button class="g34-sb-close" aria-label="${t('ui.close')}">${icon('close', 18)}</button>
        ${unlocked
          ? `<img class="g34-sb-card-art${firstView ? ' g34-sb-pop' : ''}" src="/${def.art}" alt="" draggable="false"/>`
          : `<span style="--f1-tint:${(PAGE_META.get(def.id) ?? FALLBACK_PAGE_META).tint}" class="g34-sb-card-art f1-sb-tint g34-sb-mystery" aria-hidden="true">?</span>`}
        <h2 class="g34-sb-card-title">${unlocked ? t(def.nameKey) : t('stickerbook.unknown')}</h2>
        ${unlocked
          ? `<p class="g34-sb-card-flavor">${t(def.flavorKey)}</p>`
          : `<p class="g34-sb-card-hintlabel">${t('stickerbook.hintLabel')}</p>
             <p class="g34-sb-card-flavor">${t(def.hintKey)}</p>`}`;
      sheetEl.appendChild(card);
      // V5/FIX-UI: dismiss on completed click, not pointerdown (removing the
      // sheet mid-gesture let the synthetic click fall through to the slot
      // grid underneath) — see src/ui/backdropDismiss.js.
      attachBackdropDismiss(sheetEl, () => {
        audio.play('ui.close');
        closeSheet();
      });
      card.querySelector('.g34-sb-close').addEventListener('click', () => {
        audio.play('ui.close');
        closeSheet();
      });
      el.appendChild(sheetEl);
      if (firstView) {
        // §C5.3: confetti on first view + clear the „NEU" dot (seen).
        burstConfettiDom(card);
        const book = getStickerBook();
        if (book) book.markSeen(def.id);
        else store.update((state) => { state.stickers.seen[def.id] = true; });
      }
    }

    // ══════════════════════════════════════════════════════════ V4/G59 ═══
    // Fotos tab (§C-SYS9.2) + secret-slot sheet (§C-SYS5.4 render half).

    /** §C-SYS5.4: secret-slot detail sheet — „Geheim" + code-word hint while
     * locked; full art/name/flavor once herzGooby is unlocked (first view:
     * pop-in + confetti + markSeen, same contract as the regular sheet). */
    function openSecretSheet() {
      closeSheet();
      const def = SECRET_STICKER();
      const c = store.get();
      const unlocked = !!c?.stickers?.unlocked?.herzGooby;
      const firstView = unlocked && c?.stickers?.seen?.herzGooby !== true;
      sheetStickerId = 'herzGooby';
      sheetUnlockedAtOpen = unlocked;
      sheetLangAtOpen = getLang();
      sheetEl = document.createElement('div');
      sheetEl.className = 'g34-sb-sheet';
      const card = document.createElement('div');
      card.className = `g34-sb-card${unlocked ? '' : ' g34-locked'}`;
      // V5/STICKERS: locked secret sheet = mystery „?" box, no art fetch.
      card.innerHTML = `
        <button class="g34-sb-close" aria-label="${t('ui.close')}">${icon('close', 18)}</button>
        ${unlocked
          ? `<img class="g34-sb-card-art${firstView ? ' g34-sb-pop' : ''}" src="/${def.art}" alt="" draggable="false"/>`
          : '<span class="g34-sb-card-art g34-sb-mystery" aria-hidden="true">?</span>'}
        <h2 class="g34-sb-card-title">${unlocked ? t(def.nameKey) : tG('stickerbook.secret')}</h2>
        ${unlocked
          ? `<p class="g34-sb-card-flavor">${t(def.flavorKey)}</p>`
          : `<p class="g34-sb-card-hintlabel">${t('stickerbook.hintLabel')}</p>
             <p class="g34-sb-card-flavor">${tG('stickerbook.secretHint')}</p>`}`;
      sheetEl.appendChild(card);
      // V5/FIX-UI: armed click-outside (same rationale as the regular sheet).
      attachBackdropDismiss(sheetEl, () => {
        audio.play('ui.close');
        closeSheet();
      });
      card.querySelector('.g34-sb-close').addEventListener('click', () => {
        audio.play('ui.close');
        closeSheet();
      });
      el.appendChild(sheetEl);
      if (firstView) {
        burstConfettiDom(card);
        const book = getStickerBook();
        if (book) book.markSeen('herzGooby');
        else store.update((state) => { state.stickers.seen.herzGooby = true; });
      }
    }

    /** The §C-SYS5.4 secret slot appended to book page 5 (2×3 grid, slot 5). */
    function buildSecretSlot(unlockedMap, seenMap, freshIds, poppedIdsSet) {
      const def = SECRET_STICKER();
      const unlocked = !!unlockedMap.herzGooby;
      const isNew = unlocked && seenMap.herzGooby !== true;
      const pop = unlocked && (freshIds.has('herzGooby') || (isNew && !poppedIdsSet.has('herzGooby')));
      if (pop) poppedIdsSet.add('herzGooby');
      const slot = document.createElement('button');
      slot.className = `g34-sb-slot g59-secret ${unlocked ? 'g34-unlocked' : 'g34-locked'}`;
      // V5/STICKERS: locked = shared mystery „?" box (no <img src>, no fetch).
      slot.innerHTML = `
        ${unlocked
          ? `<img class="g34-sb-art${pop ? ' g34-sb-pop' : ''}" src="/${def.art}" alt="" loading="lazy" draggable="false"/>`
          : '<span class="g34-sb-art g34-sb-mystery" aria-hidden="true">?</span>'}
        <span class="g59-secret-badge">${icon('heart', 14)}</span>
        <span class="g34-sb-name">${unlocked ? t(def.nameKey) : tG('stickerbook.secret')}</span>
        ${isNew ? `<span class="g34-sb-newdot">${t('stickerbook.new')}</span>` : ''}`;
      slot.addEventListener('click', () => {
        audio.play('ui.pick');
        openSecretSheet();
        render();
      });
      return slot;
    }

    function closeViewer() {
      if (!viewer) return;
      if (viewer.url) URL.revokeObjectURL(viewer.url);
      viewer.el.remove();
      viewer = null;
    }

    /** Load one photo into the open viewer (full blob → objectURL + date). */
    function viewerShow(id) {
      if (!viewer) return;
      const meta = (photosCache ?? []).find((m) => m.id === id);
      viewer.id = id;
      const img = viewer.el.querySelector('.g59-vw-img');
      const date = viewer.el.querySelector('.g59-vw-date');
      const when = new Date(meta?.at ?? now());
      date.textContent = when.toLocaleString(getLang() === 'de' ? 'de-DE' : 'en-US', {
        year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
      });
      if (viewer.url) {
        URL.revokeObjectURL(viewer.url); // §C-SYS9.2 objectURL lifecycle
        viewer.url = null;
      }
      img.removeAttribute('src');
      photoStore.get(id).then((blob) => {
        if (!viewer || viewer.id !== id || !blob) return;
        viewer.url = URL.createObjectURL(blob);
        img.src = viewer.url;
      });
    }

    /** Swipe navigation: +1 → older (grid is newest first), −1 → newer. */
    function viewerNav(dir) {
      if (!viewer || !photosCache?.length) return;
      const i = photosCache.findIndex((m) => m.id === viewer.id);
      const next = photosCache[i + dir];
      if (!next) return;
      audio.play('ui.pick');
      viewerShow(next.id);
    }

    /** §C-SYS9.2 confirm sheet „Foto löschen?" inside the viewer. */
    function openDeleteConfirm() {
      if (!viewer || viewer.el.querySelector('.g59-vw-confirm')) return;
      const c = document.createElement('div');
      c.className = 'g59-vw-confirm';
      c.innerHTML = `
        <div class="g59-vw-confirm-card">
          <h3>${tG('gallery.confirmDelete')}</h3>
          <div class="g59-vw-confirm-row">
            <button class="g59-vw-btn g59-cancel">${t('ui.no')}</button>
            <button class="g59-vw-btn g59-confirm-del">${g59Icon('trash', 14)}<span>${tG('gallery.delete')}</span></button>
          </div>
        </div>`;
      // V5/FIX-UI: armed click-outside — a pointerdown-remove here let the
      // synthetic click land on the viewer buttons below the confirm scrim.
      attachBackdropDismiss(c, () => c.remove());
      c.querySelector('.g59-cancel').addEventListener('click', () => {
        audio.play('ui.close');
        c.remove();
      });
      c.querySelector('.g59-confirm-del').addEventListener('click', async () => {
        const id = viewer?.id;
        c.remove();
        if (id == null) return;
        await photoStore.remove(id);
        audio.play('ui.close');
        revokeThumbUrl(id);
        const idx = (photosCache ?? []).findIndex((m) => m.id === id);
        photosCache = (photosCache ?? []).filter((m) => m.id !== id);
        // §B7 mirror: count follows IDB truth synchronously (lastAddedAt kept)
        store.update((state) => {
          const g = state.gallery ?? { count: 0, lastAddedAt: 0, hintShown: false };
          state.gallery = { hintShown: g.hintShown === true, ...mirrorSlice(photosCache.length, g.lastAddedAt) };
        });
        const successor = photosCache[Math.min(Math.max(idx, 0), photosCache.length - 1)];
        if (successor) viewerShow(successor.id);
        else closeViewer();
        render();
      });
      viewer.el.appendChild(c);
    }

    /** Full-screen photo viewer (§C-SYS9.2) — lives on `el` outside `body`,
     * so the 1 Hz store re-renders never wipe it (detail-sheet pattern). */
    function openViewer(id) {
      closeViewer();
      const v = document.createElement('div');
      v.className = 'g59-vw';
      v.innerHTML = `
        <div class="g59-vw-top">
          <span class="g59-vw-date"></span>
          <button class="g59-vw-close" aria-label="${t('ui.close')}">${icon('close', 18)}</button>
        </div>
        <div class="g59-vw-stage"><img class="g59-vw-img" alt="" draggable="false"/></div>
        <div class="g59-vw-btns">
          <button class="g59-vw-btn g59-share">${g59Icon('share', 16)}<span>${tG('gallery.share')}</span></button>
          <button class="g59-vw-btn g59-danger g59-del">${g59Icon('trash', 16)}<span>${tG('gallery.delete')}</span></button>
        </div>`;
      v.querySelector('.g59-vw-close').addEventListener('click', () => {
        audio.play('ui.close');
        closeViewer();
      });
      v.querySelector('.g59-share').addEventListener('click', async () => {
        audio.play('ui.tap');
        if (!viewer) return;
        const blob = await photoStore.get(viewer.id);
        // §C-SYS9.4: native Filesystem→Share, web share → download fallback
        // (desktop fallback toasts „Teilen nicht möglich — Download gestartet")
        if (blob) shareImage(blob, { ui, filename: `gooby-photo-${viewer.id}.png`, toastOnFallback: true });
      });
      v.querySelector('.g59-del').addEventListener('click', () => {
        audio.play('ui.tap');
        openDeleteConfirm();
      });
      const stage = v.querySelector('.g59-vw-stage');
      let downX = null;
      stage.addEventListener('pointerdown', (e) => {
        downX = e.clientX;
      });
      stage.addEventListener('pointerup', (e) => {
        if (downX == null) return;
        const dx = e.clientX - downX;
        downX = null;
        if (dx <= -40) viewerNav(1); // swipe left → older
        else if (dx >= 40) viewerNav(-1); // swipe right → newer
      });
      el.appendChild(v);
      viewer = { el: v, id, url: null };
      viewerShow(id);
    }

    // -------------------------------------------- V4/G59: Fotos tab view
    function renderPhotos() {
      const wrap = document.createElement('div');
      wrap.className = 'g59-ph-wrap';
      body.appendChild(wrap);
      const token = ++photosToken;

      const fill = (metas) => {
        if (token !== photosToken || !wrap.isConnected) return;
        count.textContent = `${metas.length}/${GALLERY.CAP}`; // §C-SYS9.2 „n/40"
        wrap.innerHTML = '';
        if (metas.length === 0) {
          // §C-SYS9.2 empty state: Gooby-with-camera + photo-mode deep link
          const empty = document.createElement('div');
          empty.className = 'g59-ph-empty';
          empty.innerHTML = `
            <span class="g59-ph-empty-art">${icon('rabbit', 56)}<span class="g59-ph-cam">${g59Icon('camera', 20)}</span></span>
            <p class="g59-ph-empty-txt">${tG('gallery.empty')}</p>
            <button class="g59-ph-cta">${g59Icon('camera', 16)}<span>${tG('gallery.emptyCta')}</span></button>`;
          empty.querySelector('.g59-ph-cta').addEventListener('click', () => {
            audio.play('ui.tap');
            ui.closeAll();
            // the HUD camera event (shopTrip pattern) — photoMode consumes it
            window.dispatchEvent(new CustomEvent('gooby:photoMode'));
          });
          wrap.appendChild(empty);
          return;
        }
        if (metas.length >= GALLERY.CAP) {
          const note = document.createElement('p');
          note.className = 'g59-ph-note';
          note.textContent = tG('gallery.footnote'); // §C-SYS9.1 at 40/40
          wrap.appendChild(note);
        }
        const grid = document.createElement('div');
        grid.className = 'g59-ph-grid';
        for (const [idx, m] of metas.entries()) {
          const cell = document.createElement('button');
          // V6/B3: each photo is a polaroid pinned at a deterministic tilt
          cell.className = 'g59-ph-cell b3-polaroid';
          cell.style.setProperty('--b3-tilt', `${polaroidJitter(idx)}deg`);
          cell.dataset.photoId = String(m.id);
          const img = document.createElement('img');
          img.className = 'g59-ph-img';
          img.alt = '';
          img.loading = 'lazy';
          img.draggable = false;
          const cached = thumbUrls.get(m.id);
          if (cached) img.src = cached;
          else {
            // lazy createObjectURL, cached per id, revoked on unmount/delete
            photoStore.getThumb(m.id).then((blob) => {
              if (!blob) return;
              if (!thumbUrls.has(m.id)) thumbUrls.set(m.id, URL.createObjectURL(blob));
              if (img.isConnected) img.src = thumbUrls.get(m.id);
            });
          }
          cell.appendChild(img);
          cell.addEventListener('click', () => {
            audio.play('ui.pick');
            openViewer(m.id);
          });
          grid.appendChild(cell);
        }
        wrap.appendChild(grid);
      };

      if (photosCache) fill(photosCache);
      else {
        photoStore.list().then((metas) => {
          if (token !== photosToken) return;
          photosCache = sortNewestFirst(metas);
          // §B7 mirror healing: IDB is the truth after kills/reloads
          const mirrored = store.get('gallery')?.count ?? 0;
          if (mirrored !== photosCache.length) {
            store.update((state) => {
              const g = state.gallery ?? { count: 0, lastAddedAt: 0, hintShown: false };
              state.gallery = { hintShown: g.hintShown === true, ...mirrorSlice(photosCache.length, g.lastAddedAt) };
            });
          }
          fill(photosCache);
        });
      }
      // §C-SYS9.3-1: visiting the tab stamps session-seen → HUD dot clears
      markGallerySeen(now());
    }
    // ══════════════════════════════════════════════════════ end V4/G59 ═══

    // ------------------------------------------------ v2 collections view
    function renderCollections() {
      const c = store.get('collections') ?? { entries: {}, claimedSets: {} };
      const totalOwned = Object.values(c.entries ?? {})
        .filter((n) => Math.floor(Number(n) || 0) >= 1).length;
      const totalAll = COLLECTION_SETS.reduce((s, set) => s + set.entries.length, 0);
      count.textContent = `${totalOwned}/${totalAll}`;

      const tabs = document.createElement('div');
      tabs.className = 'g23-al-tabs ac-tabbar ac-tabbar-wrap'; // V4/UI-DEEP: shared kit
      body.appendChild(tabs);
      for (const set of COLLECTION_SETS) {
        const tab = document.createElement('button');
        tab.className = `g23-al-tab ac-tab ac-tab-label${set.id === activeSet ? ' g23-active' : ''}`;
        tab.setAttribute('aria-selected', set.id === activeSet ? 'true' : 'false');
        // V3/FIX-C: lang attr drives hyphens:auto for the wrapped DE names
        tab.innerHTML = `${icon(SET_ICONS[set.id] ?? 'star', 14)}<span lang="${getLang()}">${hy(t(set.nameKey))}</span>`;
        tab.addEventListener('click', () => {
          audio.play('ui.tabSwitch'); // V3/FIX-C (E19): tab strips use the tab cue
          activeSet = set.id;
          flavorKey = null;
          render();
        });
        tabs.appendChild(tab);
      }

      const set = getCollectionSet(activeSet);
      const page = document.createElement('div');
      page.className = 'g23-al-page';
      body.appendChild(page);
      const grid = document.createElement('div');
      grid.className = 'g23-al-grid';
      const flavor = document.createElement('div');
      flavor.className = 'g23-al-flavor';
      for (const entry of set.entries) {
        const n = countOf(c, set.id, entry.id);
        const owned = n >= 1;
        const slot = document.createElement('button');
        slot.className = `g23-al-slot ${owned ? 'g23-owned' : 'g23-missing'}`;
        slot.innerHTML = `
          <span class="g23-al-art" style="background:${tintOf(set.id, entry.id)}">${icon(SET_ICONS[set.id] ?? 'star', 30)}</span>
          <span class="g23-al-name">${owned ? t(entry.nameKey) : t('album.unknown')}</span>
          ${n > 1 ? `<span class="g23-al-n">×${n}</span>` : ''}`;
        if (owned) {
          if (flavorKey === entry.flavorKey) flavor.textContent = t(entry.flavorKey);
          slot.addEventListener('click', () => {
            audio.play('ui.pick');
            flavorKey = entry.flavorKey;
            flavor.textContent = t(entry.flavorKey);
          });
        }
        grid.appendChild(slot);
      }
      page.appendChild(grid);
      page.appendChild(flavor);

      const p = setProgress(c, set);
      const claimed = !!c.claimedSets?.[set.id];
      const complete = isSetComplete(c, set.id, set);
      const row = document.createElement('div');
      row.className = 'g23-al-setrow';
      row.innerHTML = `
        <span class="g23-al-bar"><span class="g23-al-fill" style="width:${Math.round((p.have / p.total) * 100)}%"></span></span>
        <span class="g23-al-progress">${t('album.setProgress', { have: p.have, total: p.total })}</span>
        <button class="g23-al-claim ${claimed ? 'g23-claimed-btn' : complete ? 'g23-ready' : ''}"
          ${complete && !claimed ? '' : 'disabled'}>
          ${icon(claimed ? 'check' : 'coin', 13)}${claimed ? t('album.claimed') : t('album.claim')}</button>`;
      const claimBtn = row.querySelector('.g23-al-claim');
      if (complete && !claimed) {
        claimBtn.addEventListener('click', () => {
          const reward = getAchievementsEngine()?.collections?.claimSet?.(set.id);
          if (reward) {
            audio.play('album.claim');
            ui.toast('toast.setClaimed', {
              name: t(set.nameKey),
              coins: reward.coins,
              item: t(`album.reward.${set.id}`),
            });
          }
        });
      }
      page.appendChild(row);
    }

    // ------------------------------------------- V3/G34: Stickerbuch view
    function renderBook() {
      const state = store.get();
      const unlockedMap = state?.stickers?.unlocked ?? {};
      const seenMap = state?.stickers?.seen ?? {};
      // V4/G59 (§C-SYS5.4): the header counts the REGULAR defs only (n/48
      // since V5); the unlocked secret sticker adds a small „+💗" suffix.
      const counts = stickerCounts(state, REGULAR_STICKERS);
      // V4/FIX-EMOJI: the secret-sticker suffix uses the authored heart glyph.
      count.innerHTML = `${counts.unlocked}/${REGULAR_STICKERS.length}${unlockedMap.herzGooby
        ? ` <span style="display:inline-flex;align-items:center;vertical-align:-0.125rem">+${icon('heart', 13)}</span>` : ''}`;

      // Live locked→unlocked transitions while the book is open → confetti.
      const freshIds = new Set();
      if (prevUnlocked) {
        for (const id of Object.keys(unlockedMap)) {
          if (!prevUnlocked.has(id)) freshIds.add(id);
        }
      }
      prevUnlocked = new Set(Object.keys(unlockedMap));

      const pages = stickerPages();

      // V6/F1: the titled page-chip rail sits ABOVE the pager — it replaces
      // the V3 page dots (14 pages don't scan as dots). Populated below,
      // after the pages loop, with live per-page n/6 unlock counts.
      const rail = document.createElement('div');
      rail.className = 'f1-sb-rail';
      body.appendChild(rail);

      const pager = document.createElement('div');
      pager.className = 'g34-sb-pager';
      body.appendChild(pager);
      /** @type {HTMLElement[]} */
      const confettiSlots = [];
      pages.forEach((defs, pageIdx) => {
        const page = document.createElement('div');
        page.className = 'g34-sb-page';
        const pt = document.createElement('h2');
        pt.className = 'g34-sb-pagetitle';
        // V6/F1: themed pages show their title („Reise", „Funkelpark", …);
        // the 8 legacy pages keep the V3 „Seite n" numbering (titleKey null).
        pt.textContent = pageTitle(pageIdx);
        page.appendChild(pt);
        const grid = document.createElement('div');
        grid.className = 'g34-sb-grid';
        // V4/G59 (§C-SYS5.4): the regular pages never include herzGooby
        // (stickerPages filters non-secret defs), but filter defensively.
        for (const def of defs.filter((d) => d.id !== 'herzGooby')) {
          const unlocked = !!unlockedMap[def.id];
          const isNew = unlocked && seenMap[def.id] !== true;
          const pop = unlocked && (freshIds.has(def.id) || (isNew && !poppedIds.has(def.id)));
          if (pop) poppedIds.add(def.id);
          const slot = document.createElement('button');
          slot.className = `g34-sb-slot ${unlocked ? 'g34-unlocked' : 'g34-locked'}`;
          // V5/STICKERS: locked slots render the mystery „?" placeholder —
          // no <img src> means the art is never fetched, so it can't be
          // grey-filter revealed (matches the secret-slot style). V6/F1
          // dresses that box in its PAGE's pastel tint + a low-opacity page
          // glyph watermark + the sticker's table number — page-generic
          // decoration only (shared ui/icons.js glyph, zero art/name leaks).
          const meta = PAGE_META.get(def.id) ?? FALLBACK_PAGE_META;
          slot.innerHTML = `
            ${unlocked
              ? `<img class="g34-sb-art${pop ? ' g34-sb-pop' : ''}" src="/${def.art}" alt="" loading="lazy" draggable="false"/>`
              : `<span class="g34-sb-art f1-sb-tile" style="--f1-tint:${meta.tint}">
                   <span class="f1-sb-wm" aria-hidden="true">${icon(meta.icon, 52)}</span>
                   <span class="g34-sb-mystery" aria-hidden="true">?</span>
                   <span class="f1-sb-num">#${STICKER_NO.get(def.id) ?? '?'}</span>
                 </span>`}
            <span class="g34-sb-name">${unlocked ? t(def.nameKey) : t('stickerbook.unknown')}</span>
            ${isNew ? `<span class="g34-sb-newdot">${t('stickerbook.new')}</span>` : ''}`;
          slot.addEventListener('click', () => {
            audio.play('ui.pick');
            openSheet(def);
            render(); // NEU dot clears once markSeen lands
          });
          if (freshIds.has(def.id)) confettiSlots.push(slot);
          grid.appendChild(slot);
        }
        // V4/G59 (§C-SYS5.4): the LAST page gains the secret „Geheim" slot
        // appended after its regular defs (48 + 1 outside the count).
        if (pageIdx === pages.length - 1) {
          const secret = buildSecretSlot(unlockedMap, seenMap, freshIds, poppedIds);
          if (freshIds.has('herzGooby')) confettiSlots.push(secret);
          grid.appendChild(secret);
        }
        page.appendChild(grid);
        pager.appendChild(page);
      });

      // ── V6/F1: page-chip rail population (icon + title + n/6 count) ─────
      /** Chip-tap smooth scroll in flight (page index) — while set, the
       * scroll listener must NOT downgrade bookPage to intermediate
       * positions, or a mid-flight 1 Hz store re-render pins the book back
       * on the origin page (navigation aborts). Cleared on arrival or on
       * the re-render restore. (The V3 dot-tap guard, unchanged.) */
      let scrollTarget = null;
      /** @type {HTMLElement[]} */
      const chipEls = pages.map((defs, i) => {
        const meta = STICKER_PAGES[i] ?? FALLBACK_PAGE_META;
        const have = defs.reduce((n, d) => n + (unlockedMap[d.id] ? 1 : 0), 0);
        const chip = document.createElement('button');
        chip.className = `f1-sb-chip${i === bookPage ? ' f1-active' : ''}`;
        chip.style.setProperty('--f1-tint', meta.tint);
        chip.setAttribute('aria-label', `${pageTitle(i)} ${have}/${defs.length}`);
        chip.setAttribute('aria-current', i === bookPage ? 'true' : 'false');
        chip.innerHTML = `${icon(meta.icon, 14)}<span class="f1-sb-chip-title">${pageTitle(i)}</span><span class="f1-sb-chip-count">${have}/${defs.length}</span>`;
        chip.addEventListener('click', () => goToPage(i));
        rail.appendChild(chip);
        return chip;
      });

      /** Center the active chip in the rail — re-renders rebuild the rail
       * DOM every second, so its scroll position must be restored
       * deterministically (the pager scrollLeft-restore pattern). */
      function centerChip(behavior) {
        const chip = chipEls[bookPage];
        if (!chip) return;
        rail.scrollTo({
          left: chip.offsetLeft - (rail.clientWidth - chip.offsetWidth) / 2,
          behavior,
        });
      }

      function updateRail() {
        chipEls.forEach((c, i) => {
          c.classList.toggle('f1-active', i === bookPage);
          c.setAttribute('aria-current', i === bookPage ? 'true' : 'false');
        });
        centerChip('smooth');
      }

      function goToPage(i) {
        if (i === bookPage) return;
        audio.play('ui.tap');
        bookPage = i;
        scrollTarget = i;
        pager.scrollTo({ left: i * pager.clientWidth, behavior: 'smooth' });
        updateRail();
      }

      // V6/F1 keyboard support: ←/→ page the book while a chip has focus
      // (chips are buttons, so Tab + Enter/Space already work natively).
      rail.addEventListener('keydown', (e) => {
        if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
        e.preventDefault();
        const next = Math.max(0, Math.min(pages.length - 1, bookPage + (e.key === 'ArrowRight' ? 1 : -1)));
        if (next !== bookPage) {
          goToPage(next);
          chipEls[next]?.focus();
        }
      });

      // Horizontal swipe = native scroll-snap; track the page for the rail
      // and so the 1 Hz store re-renders restore the scroll position.
      pager.addEventListener('scroll', () => {
        const w = pager.clientWidth || 1;
        const p = Math.max(0, Math.min(pages.length - 1, Math.round(pager.scrollLeft / w)));
        if (scrollTarget != null) {
          if (p === scrollTarget) scrollTarget = null; // arrived — resume tracking
          return;
        }
        if (p !== bookPage) {
          bookPage = p;
          updateRail();
        }
      }, { passive: true });
      // Restore the current page instantly (before paint) after a re-render
      // (an instant jump lands exactly on bookPage, so any in-flight chip-tap
      // navigation completes here instead of aborting).
      pager.scrollLeft = bookPage * (pager.clientWidth || 0);
      centerChip('auto');
      requestAnimationFrame(() => {
        pager.scrollLeft = bookPage * (pager.clientWidth || 0);
        centerChip('auto');
      });

      for (const slot of confettiSlots) burstConfettiDom(slot);
    }

    function render() {
      // Top-level tabs (§B5 + V4/G59 §C-SYS9.2: „Sticker | Stickerbuch |
      // Fotos"): re-render keeps the active tab highlighted.
      const state = store.get();
      const counts = stickerCounts(state);
      // V4/G59: pre-G53 the secret sticker is not in the catalog yet — count
      // its NEU state manually so the tab badge is correct either way.
      const herzNew = !!state?.stickers?.unlocked?.herzGooby && state?.stickers?.seen?.herzGooby !== true;
      const unseen = counts.unseen + (herzNew && !STICKERS_BY_ID.herzGooby ? 1 : 0);
      topTabs.innerHTML = '';
      for (const [tabId, labelKey] of [
        ['collections', 'album.tab.collections'],
        ['book', 'album.tab.book'],
        ['photos', 'album.tab.photos'], // V4/G59 (§C-SYS9.2)
      ]) {
        const tab = document.createElement('button');
        tab.className = `g34-al-toptab ac-tab ac-tab-label${activeTab === tabId ? ' g34-active' : ''}`;
        tab.setAttribute('aria-selected', activeTab === tabId ? 'true' : 'false');
        const tabIcon = tabId === 'photos' ? g59Icon('camera', 14) : icon(tabId === 'book' ? 'star' : 'cards', 14);
        // V4/FIX-UI: lang + hy() feed the 2-line label clamp (no more „Stic…")
        tab.innerHTML = `${tabIcon}<span lang="${getLang()}">${hy(tabId === 'photos' ? tG(labelKey) : t(labelKey))}</span>
          ${tabId === 'book' && unseen > 0 ? `<span class="g34-sb-newdot">${unseen}</span>` : ''}`;
        tab.addEventListener('click', () => {
          if (activeTab === tabId) return;
          audio.play('ui.tabSwitch'); // V3/G32 upgrades (sample-backed in wave 1b)
          activeTab = tabId;
          flavorKey = null;
          closeSheet();
          closeViewer(); // V4/G59
          render();
        });
        topTabs.appendChild(tab);
      }

      body.innerHTML = '';
      if (activeTab === 'book') renderBook();
      else if (activeTab === 'photos') renderPhotos(); // V4/G59
      else renderCollections();

      // Keep an open detail sheet alive across re-renders. V3/FIX-C (E8 P2):
      // the sheet DOM lives on `el` (outside `body`), so it survives the wipe
      // above — only REBUILD it when its unlock state or the language changed
      // (a blind rebuild killed the first-view pop-in/confetti within a frame,
      // because openSheet's markSeen store-write re-rendered immediately).
      if (sheetStickerId) {
        const nowUnlocked = !!state?.stickers?.unlocked?.[sheetStickerId];
        if (nowUnlocked !== sheetUnlockedAtOpen || getLang() !== sheetLangAtOpen) {
          if (sheetStickerId === 'herzGooby') {
            openSecretSheet(); // V4/G59: the secret slot owns its sheet
          } else {
            const def = STICKERS.find((s) => s.id === sheetStickerId);
            if (def) openSheet(def);
          }
        }
      }
    }

    render();
    let lang = getLang();
    const off = store.on('change', () => {
      if (getLang() !== lang) lang = getLang();
      render();
    });
    // V4/G59: runtime add/remove signal (photoMode emits on auto-save) —
    // invalidate the cached metas so an open Fotos tab picks new photos up.
    const offGallery = store.on('galleryChanged', () => {
      photosCache = null;
      if (activeTab === 'photos') render();
    });
    live = {
      off,
      closeSheet,
      // V4/G59: §C-SYS9.2 objectURL lifecycle — all URLs die with the screen
      cleanupPhotos() {
        offGallery?.();
        closeViewer();
        photosToken += 1;
        revokeAllPhotoUrls();
      },
    };
  }

  function unmount() {
    live?.closeSheet?.();
    live?.cleanupPhotos?.(); // V4/G59
    live?.off?.();
    live = null;
  }

  ui.registerScreen('album', { mount, unmount });
}

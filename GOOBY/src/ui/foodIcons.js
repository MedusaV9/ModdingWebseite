// V6/D3 (PLAN6 Wave D): authored FOOD / CROP / FURNITURE-CATEGORY icon
// catalogs — the single source of truth that retires the two divergent
// FOOD_EMOJI tables (home/interactions.js + ui/shopScreen.js), gardenPanel's
// CROP_EMOJI and shopScreen's FURN_EMOJI/SLOT_EMOJI.
//
// Style contract: same design language as icons.js (V4/AC-1 — fat, round-join
// 24×24 silhouettes with plumping strokes), but MULTI-COLOR: each glyph is a
// cute minimal 2-tone drawing (soft body fill + one accent tone + a white
// shine) so food/furniture cards read instantly at 30–34 px. icons.js keeps
// its single-color currentColor contract; this module owns the fixed-fill
// item art (the V6 idea-10 ruling).
//
// Consumers size glyphs via the `size` argument (px width/height attributes —
// the gardenPanel V4/FIX-EMOJI precedent). Pure module: no DOM/three imports,
// safe for node:test (test/icons.test.js catalog-sync suite).

// ── shared palette (mirrors the styles.css cozy set) ────────────────────────
const BROWN = '#4A3B36';
const CREAM = '#FFF6EC';
const WOOD = '#C98A4B';
const WOOD_DARK = '#A5713B';
const GREEN = '#58A65C';
const GREEN_DARK = '#4A8F5C';
const GREEN_LIGHT = '#7ECB6F';
const RED = '#E5484D';
const ORANGE = '#F28C28';
const YELLOW = '#F5C518';
const GOLD = '#E8B04B';
const TAN = '#D9A05B';
const PINK = '#F781B0';
const PINK_SOFT = '#F9AFC6';
const PURPLE = '#8E5BA6';
const BLUE = '#9BD7E8';
const BLUE_DEEP = '#6FA8DC';
const GREY = '#8A93A6';
const CHOCO = '#6B4A2F';

/** Plumping stroke attrs (the icons.js trick: same-color round-join stroke). */
const plump = (color, w = 1.6) =>
  `stroke="${color}" stroke-width="${w}" stroke-linejoin="round"`;

// ── FOOD glyphs (24×24 viewBox inner markup) — one per data/foods.js id ─────
/** @type {Record<string, string>} */
const FOOD_PATHS = {
  carrot:
    `<path d="M12 21.6C9 17 7.7 13.4 7.7 10.5c0-2.5 1.9-4.2 4.3-4.2s4.3 1.7 4.3 4.2c0 2.9-1.3 6.5-4.3 11.1z" fill="${ORANGE}" ${plump(ORANGE)}/><path d="M11.1 6.1C9.7 4.2 7.8 3.2 5.6 3.2c.5 2.3 2.3 3.8 4.8 4z" fill="${GREEN}" ${plump(GREEN, 1.2)}/><path d="M12.9 6.1c1.4-1.9 3.3-2.9 5.5-2.9-.5 2.3-2.3 3.8-4.8 4z" fill="${GREEN_DARK}" ${plump(GREEN_DARK, 1.2)}/><path d="M10.3 10.2c-.2 1.5 0 3 .5 4.6" stroke="#fff" stroke-width="1.5" stroke-linecap="round" opacity="0.5" fill="none"/>`,
  apple:
    `<path d="M12 7.2c1-.7 2.1-1.1 3.3-1.1 3 0 5.3 2.4 5.3 5.6 0 4.3-3.2 8-6.2 9.3a6.3 6.3 0 0 1-4.8 0c-3-1.3-6.2-5-6.2-9.3 0-3.2 2.3-5.6 5.3-5.6 1.2 0 2.3.4 3.3 1.1z" fill="${RED}" ${plump(RED)}/><path d="M12 7c0-1.8.7-3.2 2-4.2" stroke="#7A5B40" stroke-width="2" stroke-linecap="round" fill="none"/><path d="M13 4.8c1.7-1.4 3.4-1.6 5-.7-.8 1.8-2.5 2.6-5 2.4z" fill="${GREEN}"/><circle cx="8.8" cy="11.2" r="1.6" fill="#fff" opacity="0.5"/>`,
  banana:
    `<path d="M4 5.6c1 7.3 5.8 11.6 12.7 11.6 1.5 0 3-.2 4.2-.6-1.9 3.2-5.3 5.2-9.3 5.2-5.4 0-9.4-4.4-9.4-10 0-2.4.7-4.5 1.8-6.2z" fill="#F7D154" ${plump('#F7D154')}/><circle cx="3.9" cy="5.4" r="1.5" fill="#8A6B4A"/><circle cx="21" cy="16.8" r="1.3" fill="#8A6B4A"/><path d="M6.2 10.4c1 3 3.2 5 6.4 5.8" stroke="#fff" stroke-width="1.5" stroke-linecap="round" opacity="0.55" fill="none"/>`,
  bread:
    `<path d="M4 10.6c0-3.4 3.6-5.8 8-5.8s8 2.4 8 5.8v6.6a2.4 2.4 0 0 1-2.4 2.4H6.4A2.4 2.4 0 0 1 4 17.2z" fill="${TAN}" ${plump(TAN)}/><path d="M8.2 8.2c.6 1 .7 2.1.3 3.3M12 7.8c.6 1 .7 2.1.3 3.3M15.8 8.2c.6 1 .7 2.1.3 3.3" stroke="${CREAM}" stroke-width="1.7" stroke-linecap="round" opacity="0.85" fill="none"/>`,
  cheese:
    `<path d="M2.8 14.6 19.4 6.2a1.5 1.5 0 0 1 2.2 1.3v10.3a1.6 1.6 0 0 1-1.6 1.6H4.4a1.6 1.6 0 0 1-1.6-1.6z" fill="#F7C948" ${plump('#F7C948')}/><circle cx="10.4" cy="14.4" r="1.7" fill="${CREAM}" opacity="0.9"/><circle cx="16" cy="12" r="1.3" fill="${CREAM}" opacity="0.9"/><circle cx="15.4" cy="16.6" r="1" fill="${CREAM}" opacity="0.9"/>`,
  watermelon:
    `<path d="M2.2 11.2h19.6a1 1 0 0 1 1 1.2A11 11 0 0 1 12 21.4 11 11 0 0 1 1.2 12.4a1 1 0 0 1 1-1.2z" fill="${GREEN_DARK}" ${plump(GREEN_DARK)}/><path d="M4.6 12.6h14.8a7.6 7.6 0 0 1-14.8 0z" fill="#F05D5D"/><path d="M9 14.2c.4.8.4 1.5 0 2.2M12.6 14.6c.4.8.4 1.5 0 2.2" stroke="${BROWN}" stroke-width="1.4" stroke-linecap="round" fill="none"/>`,
  'donut-sprinkles':
    `<circle cx="12" cy="12.4" r="8.8" fill="${GOLD}" ${plump(GOLD)}/><circle cx="12" cy="12.4" r="6.9" fill="${PINK}"/><circle cx="12" cy="12.4" r="2.6" fill="${CREAM}"/><path d="M8.2 9.6l1.2 1M14.8 8.4l-.6 1.4M16.8 12.6l-1.4.4M9 15.4l.8 1.2" stroke="#fff" stroke-width="1.5" stroke-linecap="round" fill="none"/>`,
  cupcake:
    `<path d="M6.6 13h10.8l-1.2 6.4a2.1 2.1 0 0 1-2.1 1.7h-4.2a2.1 2.1 0 0 1-2.1-1.7z" fill="#E8875A" ${plump('#E8875A')}/><path d="M9.4 13.4l.6 7M14.6 13.4l-.6 7" stroke="#fff" stroke-width="1.3" opacity="0.5" fill="none"/><path d="M6.8 13.2c-1.4-.6-2.1-2-1.6-3.4.5-1.2 1.7-1.8 2.9-1.5C8.4 6 9.9 4.7 12 4.7s3.6 1.3 3.9 3.6c1.2-.3 2.4.3 2.9 1.5.5 1.4-.2 2.8-1.6 3.4z" fill="${CREAM}" ${plump(CREAM, 1.2)}/><circle cx="12" cy="4.4" r="1.7" fill="${RED}"/>`,
  salad:
    `<ellipse cx="8.4" cy="9.8" rx="3.6" ry="2.8" fill="${GREEN_LIGHT}"/><ellipse cx="15.6" cy="9.4" rx="3.8" ry="3" fill="${GREEN}"/><circle cx="12" cy="7.4" r="2.7" fill="${GREEN_DARK}"/><circle cx="12.2" cy="10.6" r="1.7" fill="${RED}"/><path d="M3 11.8h18a1 1 0 0 1 1 1.1 9.6 9.6 0 0 1-9.5 8.5h-1A9.6 9.6 0 0 1 2 12.9a1 1 0 0 1 1-1.1z" fill="#E8875A" ${plump('#E8875A')}/><path d="M5.4 14.2h13.2" stroke="#fff" stroke-width="1.5" stroke-linecap="round" opacity="0.45" fill="none"/>`,
  'ice-cream':
    `<path d="M8 12.2h8l-3.2 9a.9.9 0 0 1-1.7 0z" fill="#E0A85C" ${plump('#E0A85C')}/><path d="M9.2 14.6h5.6M10.2 17.4h3.6" stroke="${CREAM}" stroke-width="1.3" stroke-linecap="round" opacity="0.75" fill="none"/><circle cx="12" cy="8.4" r="5.4" fill="${PINK_SOFT}" ${plump(PINK_SOFT)}/><circle cx="10" cy="6.8" r="1.5" fill="#fff" opacity="0.6"/>`,
  sandwich:
    `<path d="M4.4 5.4h15.2a2 2 0 0 1 2 2v2.2H2.4V7.4a2 2 0 0 1 2-2z" fill="${GOLD}" ${plump(GOLD, 1.2)}/><rect x="2.2" y="9.8" width="19.6" height="2.5" rx="1.25" fill="#6BBF59"/><rect x="3" y="12.1" width="18" height="2.2" rx="1.1" fill="${RED}"/><path d="M2.4 14.4h19.2v1.4a2.4 2.4 0 0 1-2.4 2.4H4.8a2.4 2.4 0 0 1-2.4-2.4z" fill="#E0A85C" ${plump('#E0A85C', 1.2)}/>`,
  'hot-dog':
    `<path d="M3.4 9.8C3.9 7.2 7.5 5.4 12 5.4s8.1 1.8 8.6 4.4z" fill="${GOLD}" ${plump(GOLD, 1.2)}/><rect x="1.8" y="9.6" width="20.4" height="4.6" rx="2.3" fill="#D96A4B" ${plump('#D96A4B', 1.2)}/><path d="M4.4 11.9l2.2-1 2.4 1 2.4-1 2.4 1 2.4-1 2.2 1" stroke="${YELLOW}" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" fill="none"/><path d="M3 14.4h18v.6a3.6 3.6 0 0 1-3.6 3.6H6.6A3.6 3.6 0 0 1 3 15z" fill="#E0A85C" ${plump('#E0A85C', 1.2)}/>`,
  pancakes:
    `<ellipse cx="12" cy="16.4" rx="8.8" ry="3.2" fill="#E0A85C" ${plump('#E0A85C', 1.2)}/><ellipse cx="12" cy="13.4" rx="8.1" ry="2.9" fill="${GOLD}" ${plump(GOLD, 1.2)}/><ellipse cx="12" cy="10.6" rx="7.4" ry="2.7" fill="#EFBE62" ${plump('#EFBE62', 1.2)}/><path d="M7.2 10.2c0 1.2.6 2 .6 3.2M16.4 10.4c0 1.2.6 2 .6 3.2" stroke="#B97E3F" stroke-width="1.5" stroke-linecap="round" opacity="0.6" fill="none"/><rect x="10.3" y="7.2" width="3.4" height="2.5" rx="0.7" fill="#F7D154"/>`,
  burger:
    `<path d="M3.4 10.2C3.8 6.6 7.5 4.2 12 4.2s8.2 2.4 8.6 6z" fill="${GOLD}" ${plump(GOLD, 1.2)}/><circle cx="9" cy="7.4" r="0.8" fill="#fff" opacity="0.8"/><circle cx="13" cy="6.4" r="0.8" fill="#fff" opacity="0.8"/><circle cx="15.8" cy="8" r="0.8" fill="#fff" opacity="0.8"/><rect x="2.8" y="10.4" width="18.4" height="2.3" rx="1.15" fill="#6BBF59"/><rect x="3.4" y="12.5" width="17.2" height="2.9" rx="1.45" fill="#8A5A3B"/><path d="M3.4 15.6h17.2v.6a3.4 3.4 0 0 1-3.4 3.4H6.8a3.4 3.4 0 0 1-3.4-3.4z" fill="#E0A85C" ${plump('#E0A85C', 1.2)}/>`,
  pizza:
    `<path d="M12 21.6 3.2 8.2c2.5-2.2 5.5-3.4 8.8-3.4s6.3 1.2 8.8 3.4z" fill="#F7C948" ${plump('#F7C948')}/><path d="M2.8 8.6C5.4 6.2 8.6 4.9 12 4.9s6.6 1.3 9.2 3.7l-1.3 1.9A12.3 12.3 0 0 0 12 7.4c-2.9 0-5.6 1-7.9 3.1z" fill="#E0A85C" ${plump('#E0A85C', 1.2)}/><circle cx="10" cy="11.8" r="1.7" fill="${RED}"/><circle cx="14.2" cy="14.4" r="1.5" fill="${RED}"/><circle cx="11.6" cy="17.2" r="1.2" fill="${RED}"/>`,
  cake:
    `<path d="M4.8 11.6h14.4v7a1.8 1.8 0 0 1-1.8 1.8H6.6a1.8 1.8 0 0 1-1.8-1.8z" fill="${CREAM}" ${plump(CREAM, 1.2)}/><rect x="4.8" y="14.2" width="14.4" height="2.4" fill="${PINK_SOFT}"/><path d="M4.8 11.8c0-3 3.2-5.2 7.2-5.2s7.2 2.2 7.2 5.2v.4c-1.2.8-2.1-.6-3.4 0-1.3.7-2.4 1-3.7.3-1.2-.7-2.4-.9-3.7-.2-1.2.7-2.3-.4-3.6.1z" fill="${PINK}" ${plump(PINK, 1.2)}/><circle cx="12" cy="4.8" r="1.7" fill="${RED}"/>`,
  radish:
    `<path d="M12 9.2c3.8 0 6.7 2.6 6.7 5.7 0 3.4-3.1 5.7-5.7 7a2.2 2.2 0 0 1-2 0c-2.6-1.3-5.7-3.6-5.7-7 0-3.1 2.9-5.7 6.7-5.7z" fill="#E86A9E" ${plump('#E86A9E')}/><path d="M12 9.2c0-3.4-2.4-5.6-5.6-5.8.3 3.3 2.5 5.4 5.6 5.8z" fill="${GREEN}" ${plump(GREEN, 1.2)}/><path d="M12 9.2c0-3.4 2.4-5.6 5.6-5.8-.3 3.3-2.5 5.4-5.6 5.8z" fill="${GREEN_DARK}" ${plump(GREEN_DARK, 1.2)}/><path d="M12 17.2v2.6" stroke="#fff" stroke-width="1.6" stroke-linecap="round" opacity="0.6" fill="none"/>`,
  tomato:
    `<circle cx="12" cy="13.2" r="8.2" fill="${RED}" ${plump(RED)}/><path d="M12 4.2c.5 1.3 1.4 2.2 2.8 2.6-1.1.8-1.8 1.8-2 3h-1.6c-.2-1.2-.9-2.2-2-3 1.4-.4 2.3-1.3 2.8-2.6z" fill="${GREEN_DARK}" ${plump(GREEN_DARK, 1.2)}/><circle cx="8.8" cy="11.4" r="1.6" fill="#fff" opacity="0.5"/>`,
  corn:
    `<path d="M12 3.4c2.9 0 5.1 3.7 5.1 8.5s-2.2 8.5-5.1 8.5-5.1-3.7-5.1-8.5S9.1 3.4 12 3.4z" fill="${YELLOW}" ${plump(YELLOW)}/><path d="M9.4 6.4c1.6-.7 3.6-.7 5.2 0M8.6 9.8c2 -.8 4.8-.8 6.8 0M8.5 13.4c2 .8 5 .8 7 0M9.4 17c1.6.7 3.6.7 5.2 0M12 4v16" stroke="${CREAM}" stroke-width="1.2" stroke-linecap="round" opacity="0.75" fill="none"/><path d="M7.7 9.2c-2.7 1.6-4 4.7-3.5 8.6 3.3-.9 5.1-3.1 5.5-6.4z" fill="${GREEN}" ${plump(GREEN, 1.2)}/><path d="M16.3 9.2c2.7 1.6 4 4.7 3.5 8.6-3.3-.9-5.1-3.1-5.5-6.4z" fill="${GREEN_DARK}" ${plump(GREEN_DARK, 1.2)}/>`,
  eggplant:
    `<path d="M16.4 8.4c2.5 2.3 2.8 6.2.5 9.4-2.4 3.4-6.7 4.4-9.9 2.4-2.5-1.6-3.1-4.7-1.5-6.9 1.4-1.9 3.7-2.4 5.9-2.2 2 .2 3.6-.3 5-2.7z" fill="${PURPLE}" ${plump(PURPLE)}/><path d="M15.2 8.9c-.4-1.7 0-3.2 1.3-4.5.6.5.9 1.1 1.1 1.8.7-.3 1.4-.4 2.2-.3-.2 1.8-1.4 3.1-3.2 3.6z" fill="${GREEN_DARK}" ${plump(GREEN_DARK, 1.2)}/><path d="M8.2 13.6c-1 .8-1.5 1.9-1.4 3.2" stroke="#fff" stroke-width="1.5" stroke-linecap="round" opacity="0.5" fill="none"/>`,
  pumpkin:
    `<ellipse cx="12" cy="14" rx="9" ry="7.2" fill="#E88C2A" ${plump('#E88C2A')}/><path d="M8.4 7.6c-1.7 4.2-1.7 8.6 0 12.8M15.6 7.6c1.7 4.2 1.7 8.6 0 12.8" stroke="${CREAM}" stroke-width="1.4" stroke-linecap="round" opacity="0.55" fill="none"/><path d="M11 6.9c.1-1.7-.3-2.9-1.3-3.9 1.7-.6 3 0 3.6 1.5.3.7.4 1.5.2 2.4z" fill="${GREEN_DARK}" ${plump(GREEN_DARK, 1.2)}/>`,
  strawberry:
    `<path d="M12 21.4c-4.6-1.7-7.8-5-7.8-9.1 0-3.1 2.4-5.3 5.4-5.3h4.8c3 0 5.4 2.2 5.4 5.3 0 4.1-3.2 7.4-7.8 9.1z" fill="${RED}" ${plump(RED)}/><path d="M12 3l2 1.9 2.8-.4-1 2.5-1.9.9h-3.8l-1.9-.9-1-2.5 2.8.4z" fill="${GREEN_DARK}" ${plump(GREEN_DARK, 1.2)}/><circle cx="9.2" cy="12.4" r="0.9" fill="${YELLOW}"/><circle cx="14.8" cy="12.4" r="0.9" fill="${YELLOW}"/><circle cx="12" cy="16" r="0.9" fill="${YELLOW}"/>`,
  grapes:
    `<path d="M12 6.2c0-1.8.7-3.1 2-4" stroke="#7A5B40" stroke-width="2" stroke-linecap="round" fill="none"/><path d="M13 4.6c1.8-1.3 3.5-1.5 5.1-.6-.9 1.8-2.6 2.6-5.1 2.3z" fill="${GREEN}"/><circle cx="8" cy="9.8" r="3" fill="${PURPLE}" ${plump(PURPLE, 1.2)}/><circle cx="16" cy="9.8" r="3" fill="${PURPLE}" ${plump(PURPLE, 1.2)}/><circle cx="12" cy="9.4" r="3" fill="#A06DBB" ${plump('#A06DBB', 1.2)}/><circle cx="9.8" cy="14.4" r="3" fill="#A06DBB" ${plump('#A06DBB', 1.2)}/><circle cx="14.2" cy="14.4" r="3" fill="${PURPLE}" ${plump(PURPLE, 1.2)}/><circle cx="12" cy="18.6" r="3" fill="${PURPLE}" ${plump(PURPLE, 1.2)}/><circle cx="10.9" cy="8.6" r="0.9" fill="#fff" opacity="0.55"/>`,
  croissant:
    `<path d="M12 6.4c1.9 0 3.6.5 4.9 1.4 1.8-.9 3.8-.6 5.1.8-1.4 4-4 6.9-7.4 8.7-1.7.9-3.5.9-5.2 0-3.4-1.8-6-4.7-7.4-8.7 1.3-1.4 3.3-1.7 5.1-.8 1.3-.9 3-1.4 4.9-1.4z" fill="${GOLD}" ${plump(GOLD)}/><path d="M7.4 8.2c-.3 2.6.5 5 2.3 7M16.6 8.2c.3 2.6-.5 5-2.3 7" stroke="#B97E3F" stroke-width="1.5" stroke-linecap="round" opacity="0.7" fill="none"/><path d="M11 9c.2 1.6.6 3 1.4 4.2" stroke="#fff" stroke-width="1.4" stroke-linecap="round" opacity="0.5" fill="none"/>`,
  lollypop:
    `<circle cx="12" cy="9.2" r="6.8" fill="${PINK}" ${plump(PINK)}/><path d="M12 9.2m-3.9 0a3.9 3.9 0 1 1 7.8 0 2.5 2.5 0 1 1-5 0 1.2 1.2 0 1 1 2.4 0" stroke="#fff" stroke-width="1.7" stroke-linecap="round" fill="none" opacity="0.85"/><path d="M12 16.2v5.4" stroke="#C9A87A" stroke-width="2.4" stroke-linecap="round" fill="none"/>`,
  cookie:
    `<circle cx="12" cy="12" r="8.8" fill="${TAN}" ${plump(TAN)}/><circle cx="9" cy="9.4" r="1.4" fill="${CHOCO}"/><circle cx="14.8" cy="8.8" r="1.2" fill="${CHOCO}"/><circle cx="15.6" cy="14.4" r="1.4" fill="${CHOCO}"/><circle cx="9.6" cy="15.2" r="1.2" fill="${CHOCO}"/><circle cx="12.4" cy="12" r="1" fill="${CHOCO}"/><circle cx="7.4" cy="12" r="0.9" fill="#fff" opacity="0.4"/>`,
  chocolate:
    `<rect x="4.4" y="3.6" width="15.2" height="16.8" rx="2.4" fill="${CHOCO}" ${plump(CHOCO)}/><path d="M12 4v16.4M4.6 9.2h14.8M4.6 15h14.8" stroke="#8A6B4A" stroke-width="1.5" opacity="0.9" fill="none"/><rect x="6.2" y="5.4" width="3.4" height="2.2" rx="0.7" fill="#fff" opacity="0.25"/>`,
  'candy-bar':
    `<circle cx="12" cy="12" r="5.4" fill="${PINK}" ${plump(PINK, 1.2)}/><path d="M7.1 10 2.8 7.5v9L7.1 14z" fill="#F45E9C" ${plump('#F45E9C', 1.2)}/><path d="M16.9 10l4.3-2.5v9L16.9 14z" fill="#F45E9C" ${plump('#F45E9C', 1.2)}/><path d="M9.8 9.6l4.6 4.6M13 9.2l1.8 1.8" stroke="#fff" stroke-width="1.5" stroke-linecap="round" opacity="0.7" fill="none"/>`,
  muffin:
    `<path d="M6.8 13.2h10.4l-1.1 6.2a2.1 2.1 0 0 1-2.1 1.7h-4a2.1 2.1 0 0 1-2.1-1.7z" fill="#E0A85C" ${plump('#E0A85C')}/><path d="M9.6 13.6l.5 6.6M14.4 13.6l-.5 6.6" stroke="#fff" stroke-width="1.2" opacity="0.5" fill="none"/><path d="M5.4 11.2c0-3.6 3-6.2 6.6-6.2s6.6 2.6 6.6 6.2c0 1.3-1 2.2-2.3 2.2H7.7c-1.3 0-2.3-.9-2.3-2.2z" fill="${WOOD}" ${plump(WOOD)}/><circle cx="9.4" cy="9.4" r="1" fill="${BLUE_DEEP}"/><circle cx="13.2" cy="8" r="1" fill="${BLUE_DEEP}"/><circle cx="15.2" cy="10.6" r="1" fill="${BLUE_DEEP}"/>`,
  fries:
    `<path d="M7.8 4.2 6.8 12h2.6l.6-7.8a1.1 1.1 0 0 0-2.2 0z" fill="${YELLOW}"/><path d="M10.9 3.6v8.4h2.2V3.6a1.1 1.1 0 0 0-2.2 0z" fill="#F7D154"/><path d="M16.2 4.2l1 7.8h-2.6l-.6-7.8a1.1 1.1 0 0 1 2.2 0z" fill="${YELLOW}"/><path d="M4.8 10.8h14.4a1 1 0 0 1 1 1.1l-1.1 7.5a2.2 2.2 0 0 1-2.2 1.9H8.1a2.2 2.2 0 0 1-2.2-1.9l-1.1-7.5a1 1 0 0 1 1-1.1z" fill="${RED}" ${plump(RED)}/><path d="M8.2 14.6c1.2 1 2.5 1.5 3.8 1.5s2.6-.5 3.8-1.5" stroke="#fff" stroke-width="1.6" stroke-linecap="round" opacity="0.7" fill="none"/>`,
  'corn-dog':
    `<rect x="8.2" y="2.6" width="7.6" height="14.2" rx="3.8" fill="${TAN}" ${plump(TAN)}/><path d="M10.4 5.2c1.5 1.3 2.4 3.1 2 5.3-.4 2 .3 3.6 1.5 4.7" stroke="${YELLOW}" stroke-width="1.8" stroke-linecap="round" fill="none"/><path d="M12 17v4.4" stroke="#B97E3F" stroke-width="2.2" stroke-linecap="round" fill="none"/>`,
  sundae:
    `<circle cx="8.8" cy="8.8" r="3.4" fill="${PINK_SOFT}" ${plump(PINK_SOFT, 1.2)}/><circle cx="15.2" cy="8.8" r="3.4" fill="${CREAM}" ${plump(CREAM, 1.2)}/><circle cx="12" cy="6.4" r="3.4" fill="#F3D9B8" ${plump('#F3D9B8', 1.2)}/><circle cx="12" cy="3.4" r="1.5" fill="${RED}"/><path d="M4.8 11.6h14.4a1 1 0 0 1 1 1.2l-1.5 6.1a2.4 2.4 0 0 1-2.3 1.9H8.6a2.4 2.4 0 0 1-2.3-1.9l-1.5-6.1a1 1 0 0 1 1-1.2z" fill="${BLUE}" ${plump(BLUE)}/><path d="M7.4 14h9.2" stroke="#fff" stroke-width="1.5" stroke-linecap="round" opacity="0.6" fill="none"/>`,
  nutella:
    `<rect x="6" y="2.8" width="12" height="3.4" rx="1.7" fill="${BROWN}"/><rect x="7.2" y="6.2" width="9.6" height="1.6" rx="0.8" fill="${CREAM}"/><path d="M6.5 7.8h11A1.5 1.5 0 0 1 19 9.3V19a2.5 2.5 0 0 1-2.5 2.5h-9A2.5 2.5 0 0 1 5 19V9.3a1.5 1.5 0 0 1 1.5-1.5z" fill="#F3E4CE" ${plump('#F3E4CE', 1.2)}/><path d="M6.5 12.3h11V19a1.5 1.5 0 0 1-1.5 1.5h-8A1.5 1.5 0 0 1 6.5 19z" fill="#5C3A21"/><ellipse cx="12" cy="10.2" rx="3" ry="1.3" fill="#fff" opacity="0.75"/>`,
  cupcakePink:
    `<path d="M6.6 13h10.8l-1.2 6.4a2.1 2.1 0 0 1-2.1 1.7h-4.2a2.1 2.1 0 0 1-2.1-1.7z" fill="#D6669C" ${plump('#D6669C')}/><path d="M9.4 13.4l.6 7M14.6 13.4l-.6 7" stroke="#fff" stroke-width="1.3" opacity="0.5" fill="none"/><path d="M6.8 13.2c-1.4-.6-2.1-2-1.6-3.4.5-1.2 1.7-1.8 2.9-1.5C8.4 6 9.9 4.7 12 4.7s3.6 1.3 3.9 3.6c1.2-.3 2.4.3 2.9 1.5.5 1.4-.2 2.8-1.6 3.4z" fill="${PINK_SOFT}" ${plump(PINK_SOFT, 1.2)}/><circle cx="9.4" cy="9.4" r="0.8" fill="#fff"/><circle cx="12.6" cy="7.8" r="0.8" fill="#fff"/><circle cx="14.8" cy="10.2" r="0.8" fill="#fff"/>`,
  cinnamonRoll:
    `<circle cx="12" cy="12" r="8.8" fill="${TAN}" ${plump(TAN)}/><path d="M12 12.2a1.9 1.9 0 0 1 3.8 0c0 2.2-1.9 3.9-4.1 3.9-3 0-5.5-2.4-5.5-5.4 0-3.7 2.9-6.2 6.3-6.2 4.1 0 7.3 3.1 7.3 7" stroke="#F3E4CE" stroke-width="2.1" stroke-linecap="round" fill="none"/><path d="M7 6.4c1.4 1 3 1.4 4.8 1.2" stroke="#fff" stroke-width="1.4" stroke-linecap="round" opacity="0.6" fill="none"/>`,
  // V6/E3 park foods (Candy Alley stall exclusives — specs from the E3 handoff)
  cottonCandy:
    `<path d="M12 3.2c1.6 0 3 .8 3.8 2 1.9-.5 3.9.4 4.7 2.2.8 1.7.3 3.7-1.1 4.9.4 1.9-.5 3.8-2.3 4.6-1.2.5-2.5.4-3.6-.2-1.1.6-2.4.7-3.6.2-1.8-.8-2.7-2.7-2.3-4.6-1.4-1.2-1.9-3.2-1.1-4.9.8-1.8 2.8-2.7 4.7-2.2.8-1.2 2.2-2 3.8-2z" fill="${PINK_SOFT}" ${plump(PINK_SOFT)}/><circle cx="9" cy="8.2" r="1.5" fill="#fff" opacity="0.6"/><path d="M8.6 12.4c1 .9 2.2 1.3 3.4 1.3s2.4-.4 3.4-1.3" stroke="${PINK}" stroke-width="1.4" stroke-linecap="round" opacity="0.7" fill="none"/><path d="M12 16.6v4.8" stroke="#C9A87A" stroke-width="2.2" stroke-linecap="round" fill="none"/>`,
  softServe:
    `<path d="M8.2 12.6h7.6l-3 8.6a.9.9 0 0 1-1.7 0z" fill="${GOLD}" ${plump(GOLD)}/><path d="M9.3 14.8h5.4M10.2 17.4h3.6" stroke="${CREAM}" stroke-width="1.2" stroke-linecap="round" opacity="0.75" fill="none"/><path d="M9.4 12.2c-1.6 0-2.8-1.2-2.8-2.7 0-1.3.9-2.3 2.1-2.6.2-1.9 1.6-3.3 3.3-3.3 1.3 0 2.4.7 3 1.9 1.5.1 2.7 1.3 2.7 2.8 0 1.3-.8 2.4-2 2.7l-.6 1.2z" fill="${CREAM}" ${plump(CREAM)}/><path d="M12 12.4c-1.9-.4-3-1.5-3.4-3.2M12 12.4c1.9-.4 3-1.5 3.4-3.2" stroke="#EAD9C2" stroke-width="1.3" stroke-linecap="round" fill="none"/><circle cx="9.8" cy="6.8" r="1.2" fill="#fff" opacity="0.7"/>`,
  waffle:
    `<rect x="4" y="5.6" width="16" height="13.6" rx="2.6" fill="${GOLD}" ${plump(GOLD)}/><path d="M9.3 6v13M14.7 6v13M4.4 10.1h15.2M4.4 14.7h15.2" stroke="#B97E3F" stroke-width="1.5" stroke-linecap="round" opacity="0.85" fill="none"/><circle cx="12" cy="12.4" r="2" fill="${RED}"/><path d="M6.4 8.2l1.6-.9" stroke="#fff" stroke-width="1.3" stroke-linecap="round" opacity="0.6" fill="none"/>`,
};

// ── FURNITURE CATEGORY glyphs — one per decor slot id (data/furniture.js) ───
/** @type {Record<string, string>} */
const SLOT_PATHS = {
  sofa: `<path d="M5.2 10.6V9a2.8 2.8 0 0 1 2.8-2.8h8A2.8 2.8 0 0 1 18.8 9v1.6z" fill="#E8875A" ${plump('#E8875A')}/><path d="M4.6 10a2.4 2.4 0 0 1 2.4 2.4v1h10v-1A2.4 2.4 0 0 1 19.4 10 2.4 2.4 0 0 1 21.8 12.4v4a1.8 1.8 0 0 1-1.8 1.8h-.4v1.2a1 1 0 0 1-2 0v-1.2H6.4v1.2a1 1 0 0 1-2 0v-1.2H4a1.8 1.8 0 0 1-1.8-1.8v-4A2.4 2.4 0 0 1 4.6 10z" fill="#E8875A" ${plump('#E8875A')}/><path d="M7 13.6h10" stroke="#fff" stroke-width="1.6" stroke-linecap="round" opacity="0.55" fill="none"/>`,
  tv: `<rect x="3" y="4.8" width="18" height="12" rx="2.2" fill="#5A6272" ${plump('#5A6272')}/><rect x="4.9" y="6.7" width="14.2" height="8.2" rx="1.2" fill="${BLUE}"/><path d="M8.4 19.4h7.2M12 17v2.4" stroke="#5A6272" stroke-width="2.2" stroke-linecap="round" fill="none"/><path d="M6.4 8.2l3-1" stroke="#fff" stroke-width="1.4" stroke-linecap="round" opacity="0.7" fill="none"/>`,
  rug: `<ellipse cx="12" cy="12" rx="9.8" ry="6.8" fill="#F2B8C6" ${plump('#F2B8C6')}/><ellipse cx="12" cy="12" rx="6.6" ry="4.2" fill="none" stroke="#fff" stroke-width="1.7" opacity="0.75"/><circle cx="12" cy="12" r="1.5" fill="#fff" opacity="0.75"/>`,
  plant:
    `<path d="M12 13.6c-.4-3.5-2.7-5.8-6.2-6 .3 3.6 2.7 5.9 6.2 6z" fill="${GREEN}" ${plump(GREEN, 1.2)}/><path d="M12 13.6c.4-3.5 2.7-5.8 6.2-6-.3 3.6-2.7 5.9-6.2 6z" fill="${GREEN_DARK}" ${plump(GREEN_DARK, 1.2)}/><path d="M12 13.8V9.2c0-2 .9-3.6 2.6-4.7" stroke="${GREEN_DARK}" stroke-width="1.8" stroke-linecap="round" fill="none"/><path d="M7.6 14.4h8.8l-1 5a2.2 2.2 0 0 1-2.1 1.8h-2.6a2.2 2.2 0 0 1-2.1-1.8z" fill="#D96A4B" ${plump('#D96A4B')}/>`,
  lamp: `<path d="M8.2 3.6h7.6l2.2 6.6H6z" fill="${YELLOW}" ${plump(YELLOW)}/><path d="M12 10.6v8" stroke="${WOOD_DARK}" stroke-width="2.2" stroke-linecap="round" fill="none"/><path d="M7.6 20.4c1.2-1.2 2.7-1.8 4.4-1.8s3.2.6 4.4 1.8z" fill="${WOOD_DARK}" ${plump(WOOD_DARK, 1.2)}/><circle cx="10" cy="6" r="1.1" fill="#fff" opacity="0.7"/>`,
  bookcase:
    `<rect x="4.4" y="3.4" width="15.2" height="17.2" rx="2" fill="${WOOD}" ${plump(WOOD)}/><path d="M4.6 11.8h14.8" stroke="${CREAM}" stroke-width="1.5" opacity="0.8"/><rect x="6.6" y="6" width="2.6" height="4.6" rx="0.8" fill="${RED}"/><rect x="9.8" y="5.4" width="2.6" height="5.2" rx="0.8" fill="${BLUE_DEEP}"/><rect x="13" y="6.4" width="2.6" height="4.2" rx="0.8" fill="${GREEN}"/><rect x="7.6" y="13.8" width="2.6" height="4.6" rx="0.8" fill="${YELLOW}"/><rect x="11.4" y="14.4" width="2.6" height="4" rx="0.8" fill="${PINK}"/>`,
  wallArt:
    `<rect x="3.8" y="4.4" width="16.4" height="15.2" rx="2" fill="${WOOD}" ${plump(WOOD)}/><rect x="6.2" y="6.8" width="11.6" height="10.4" rx="0.8" fill="#CFE8F5"/><circle cx="15" cy="9.6" r="1.5" fill="${YELLOW}"/><path d="M6.6 15.4l3.4-4 2.6 2.8 2-2.2 3 3.4v1.7H6.6z" fill="${GREEN}"/>`,
  tableSet:
    `<ellipse cx="12" cy="8.6" rx="9.2" ry="3.2" fill="${WOOD}" ${plump(WOOD)}/><path d="M4.6 10.6v6.8M19.4 10.6v6.8M12 11.8v8.4" stroke="${WOOD_DARK}" stroke-width="2.2" stroke-linecap="round" fill="none"/><ellipse cx="12" cy="8" rx="3.8" ry="1.5" fill="${CREAM}"/><ellipse cx="12" cy="8" rx="2" ry="0.8" fill="${BLUE}"/>`,
  fridge:
    `<rect x="5.6" y="2.6" width="12.8" height="18.8" rx="2.6" fill="${BLUE}" ${plump(BLUE)}/><path d="M5.8 9.4h12.4" stroke="#fff" stroke-width="1.6" opacity="0.8"/><path d="M8.2 5.4v2M8.2 12v4.4" stroke="#fff" stroke-width="2" stroke-linecap="round" opacity="0.9" fill="none"/>`,
  appliance:
    `<rect x="4.8" y="3" width="14.4" height="5" rx="1.8" fill="#6E7787" ${plump('#6E7787', 1.2)}/><rect x="4.8" y="16.2" width="14.4" height="4.4" rx="1.8" fill="#6E7787" ${plump('#6E7787', 1.2)}/><path d="M8.6 8.4h6.8v2a3.4 3.4 0 0 1-6.8 0z" fill="${CREAM}" ${plump(CREAM, 1.2)}/><path d="M15.4 9h1.4a1.7 1.7 0 0 1 0 3.4h-1" stroke="${CREAM}" stroke-width="1.6" fill="none"/><path d="M12 13.6v2.4" stroke="#8A93A6" stroke-width="1.8" stroke-linecap="round" fill="none"/><circle cx="16.6" cy="5.5" r="1.1" fill="${RED}"/>`,
  wallShelf:
    `<rect x="3.6" y="6" width="16.8" height="12" rx="2" fill="${WOOD}" ${plump(WOOD)}/><path d="M12 6.2v11.6" stroke="${CREAM}" stroke-width="1.5" opacity="0.8"/><circle cx="9.6" cy="12" r="1" fill="${CREAM}"/><circle cx="14.4" cy="12" r="1" fill="${CREAM}"/>`,
  tub: `<path d="M2.8 10.8h18.4a1 1 0 0 1 1 1.1 7.2 7.2 0 0 1-7.2 6.5H10a7.2 7.2 0 0 1-7.2-6.5 1 1 0 0 1 1-1.1z" fill="#CFE8F5" ${plump('#CFE8F5')}/><path d="M6.6 18.4l-1 2M17.4 18.4l1 2" stroke="#8A93A6" stroke-width="2" stroke-linecap="round" fill="none"/><path d="M5.4 10.6V6.2a2.6 2.6 0 0 1 5.2-.6" stroke="#8A93A6" stroke-width="2" stroke-linecap="round" fill="none"/><circle cx="13.6" cy="7.4" r="1.4" fill="${BLUE}" opacity="0.8"/><circle cx="16.4" cy="5.6" r="1" fill="${BLUE}" opacity="0.6"/>`,
  shelf:
    `<rect x="4.4" y="4.4" width="15.2" height="15.2" rx="2.2" fill="${WOOD}" ${plump(WOOD)}/><path d="M4.6 12h14.8" stroke="${CREAM}" stroke-width="1.5" opacity="0.8"/><path d="M10.6 8.2h2.8M10.6 15.8h2.8" stroke="${CREAM}" stroke-width="2" stroke-linecap="round" fill="none"/>`,
  bed: `<rect x="2.6" y="5.8" width="3.6" height="11.4" rx="1.5" fill="${WOOD}" ${plump(WOOD, 1.2)}/><path d="M6 10.4h13.2a2.6 2.6 0 0 1 2.6 2.6v4.2H6z" fill="${PINK_SOFT}" ${plump(PINK_SOFT, 1.2)}/><path d="M6 17.2h15.8M4.2 17.4v2.2M20.2 17.4v2.2" stroke="${WOOD_DARK}" stroke-width="2" stroke-linecap="round" fill="none"/><rect x="6.8" y="7.6" width="5.4" height="3" rx="1.4" fill="${CREAM}" ${plump(CREAM, 1)}/>`,
  nightstand:
    `<path d="M9.8 4h4.4l1.3 3.8H8.5z" fill="${YELLOW}" ${plump(YELLOW, 1.2)}/><path d="M12 7.8v2" stroke="${WOOD_DARK}" stroke-width="1.8" stroke-linecap="round" fill="none"/><rect x="5.8" y="9.8" width="12.4" height="9.6" rx="1.8" fill="${WOOD}" ${plump(WOOD)}/><path d="M6 14h12" stroke="${CREAM}" stroke-width="1.3" opacity="0.7"/><circle cx="12" cy="12" r="0.9" fill="${CREAM}"/><circle cx="12" cy="16.6" r="0.9" fill="${CREAM}"/>`,
  plushie:
    `<circle cx="6.8" cy="7" r="2.7" fill="${WOOD}" ${plump(WOOD, 1.2)}/><circle cx="17.2" cy="7" r="2.7" fill="${WOOD}" ${plump(WOOD, 1.2)}/><circle cx="6.8" cy="7" r="1.2" fill="${CREAM}"/><circle cx="17.2" cy="7" r="1.2" fill="${CREAM}"/><circle cx="12" cy="13" r="7.4" fill="${WOOD}" ${plump(WOOD)}/><ellipse cx="12" cy="15.4" rx="3.4" ry="2.6" fill="${CREAM}"/><circle cx="9.6" cy="11.4" r="1" fill="${BROWN}"/><circle cx="14.4" cy="11.4" r="1" fill="${BROWN}"/><path d="M12 14.2a1.1 1.1 0 0 1 0 2.2 1.1 1.1 0 0 1 0-2.2z" fill="${BROWN}"/>`,
  ceilingFan:
    `<path d="M12 3v2.4" stroke="${GREY}" stroke-width="2.2" stroke-linecap="round" fill="none"/><path d="M10.2 10.2 3.4 8.6c-1-.3-1.2-1.6-.3-2.1 2.4-1.4 5.2-.9 7.3 1.2z" fill="${WOOD}" ${plump(WOOD, 1.2)}/><path d="M13.8 10.2l6.8-1.6c1-.3 1.2-1.6.3-2.1-2.4-1.4-5.2-.9-7.3 1.2z" fill="${WOOD}" ${plump(WOOD, 1.2)}/><path d="M12 12.2l.4 7c0 1-1.2 1.6-2 .9-2-1.8-2.6-4.6-1.3-7.2z" fill="${WOOD}" ${plump(WOOD, 1.2)}/><circle cx="12" cy="9.4" r="2.6" fill="${GREY}" ${plump(GREY, 1.2)}/><circle cx="12" cy="9.4" r="1" fill="#fff" opacity="0.7"/>`,
  sideboard:
    `<rect x="3.8" y="8.2" width="16.4" height="11.2" rx="2.2" fill="${WOOD}" ${plump(WOOD)}/><path d="M7 8 16 4.2" stroke="#8A6B4A" stroke-width="2" stroke-linecap="round" fill="none"/><circle cx="15.8" cy="13.8" r="3" fill="${CREAM}"/><circle cx="15.8" cy="13.8" r="1.2" fill="${WOOD_DARK}"/><path d="M6.4 11.4h4.4M6.4 14h4.4M6.4 16.6h4.4" stroke="${CREAM}" stroke-width="1.6" stroke-linecap="round" opacity="0.85" fill="none"/>`,
  bar: `<path d="M4.6 4h14.8a1 1 0 0 1 .8 1.7L13.4 12v6h2.8a1.2 1.2 0 0 1 0 2.4H7.8a1.2 1.2 0 0 1 0-2.4h2.8v-6L3.8 5.7A1 1 0 0 1 4.6 4z" fill="${BLUE}" ${plump(BLUE)}/><path d="M6.6 6.4h10.8" stroke="${PINK}" stroke-width="2.2" stroke-linecap="round" fill="none"/><circle cx="15.6" cy="4.6" r="1.6" fill="${RED}"/>`,
  washer:
    `<rect x="4.4" y="3.4" width="15.2" height="17.2" rx="2.4" fill="${BLUE}" ${plump(BLUE)}/><circle cx="12" cy="13.4" r="5" fill="${CREAM}"/><circle cx="12" cy="13.4" r="3.1" fill="${BLUE_DEEP}"/><path d="M9.6 12.4a3.1 3.1 0 0 1 4.4 0" stroke="#fff" stroke-width="1.4" stroke-linecap="round" fill="none" opacity="0.8"/><circle cx="7.4" cy="6" r="0.9" fill="${CREAM}"/><circle cx="10" cy="6" r="0.9" fill="${CREAM}"/>`,
  sideTable:
    `<ellipse cx="12" cy="7.2" rx="7.8" ry="2.8" fill="${WOOD}" ${plump(WOOD)}/><path d="M12 10v8.6" stroke="${WOOD_DARK}" stroke-width="2.4" stroke-linecap="round" fill="none"/><path d="M7.4 20.2c1.3-1.1 2.9-1.6 4.6-1.6s3.3.5 4.6 1.6z" fill="${WOOD_DARK}" ${plump(WOOD_DARK, 1.2)}/>`,
  floorClutter:
    `<rect x="4.6" y="14.6" width="14.8" height="4.6" rx="1.6" fill="${RED}" ${plump(RED, 1.2)}/><rect x="5.8" y="10" width="12.4" height="4.6" rx="1.6" fill="${BLUE_DEEP}" ${plump(BLUE_DEEP, 1.2)}/><rect x="7.2" y="5.4" width="9.6" height="4.6" rx="1.6" fill="${YELLOW}" ${plump(YELLOW, 1.2)}/><path d="M8.8 7.7h6.4M7.4 12.3h9.2M6.2 16.9h11.6" stroke="#fff" stroke-width="1.2" stroke-linecap="round" opacity="0.55" fill="none"/>`,
  gardenBench:
    `<rect x="3.4" y="6.2" width="17.2" height="3" rx="1.5" fill="${WOOD}" ${plump(WOOD, 1.2)}/><rect x="3.4" y="11.6" width="17.2" height="3.2" rx="1.6" fill="${WOOD}" ${plump(WOOD, 1.2)}/><path d="M5.6 9.4v2M18.4 9.4v2M5.6 15v4.4M18.4 15v4.4" stroke="${WOOD_DARK}" stroke-width="2.2" stroke-linecap="round" fill="none"/>`,
  gardenGnome:
    `<path d="M12 2.4c2.9 1.4 4.6 3.9 5 7.4H7c.4-3.5 2.1-6 5-7.4z" fill="${RED}" ${plump(RED)}/><circle cx="12" cy="11.4" r="2.6" fill="#F3C9A5"/><path d="M8.4 13.2c1 3.4 6.2 3.4 7.2 0 .9 2 .9 4-.1 6.1a7.6 7.6 0 0 1-7 0c-1-2.1-1-4.1-.1-6.1z" fill="${CREAM}" ${plump(CREAM, 1.2)}/><circle cx="12" cy="19.2" r="2.4" fill="${BLUE_DEEP}"/>`,
  birdbath:
    `<ellipse cx="12" cy="7" rx="8.2" ry="3" fill="#B9C0CC" ${plump('#B9C0CC', 1.2)}/><ellipse cx="12" cy="6.6" rx="5.6" ry="1.8" fill="${BLUE}"/><path d="M12 10v6" stroke="#8A93A6" stroke-width="2.6" stroke-linecap="round" fill="none"/><path d="M7 20.4c1.4-1.4 3.1-2 5-2s3.6.6 5 2z" fill="#B9C0CC" ${plump('#B9C0CC', 1.2)}/><circle cx="14.6" cy="5.8" r="0.8" fill="#fff" opacity="0.8"/>`,
  flowerBed:
    `<circle cx="6.6" cy="9.6" r="2.8" fill="${PINK}" ${plump(PINK, 1.2)}/><circle cx="6.6" cy="9.6" r="1.1" fill="${YELLOW}"/><circle cx="17.4" cy="9.6" r="2.8" fill="${YELLOW}" ${plump(YELLOW, 1.2)}/><circle cx="17.4" cy="9.6" r="1.1" fill="${ORANGE}"/><circle cx="12" cy="6.8" r="3" fill="#fff" ${plump('#EDE3D5', 1.2)}/><circle cx="12" cy="6.8" r="1.2" fill="${YELLOW}"/><path d="M6.6 12.6v3M12 10v5.6M17.4 12.6v3" stroke="${GREEN_DARK}" stroke-width="1.8" stroke-linecap="round" fill="none"/><path d="M3.4 15.4h17.2a1 1 0 0 1 1 1.2l-.5 2.4a2 2 0 0 1-2 1.6H4.9a2 2 0 0 1-2-1.6l-.5-2.4a1 1 0 0 1 1-1.2z" fill="#8A6B4A" ${plump('#8A6B4A', 1.2)}/>`,
  gardenPath:
    `<ellipse cx="7" cy="6.6" rx="4.4" ry="2.9" fill="#B9C0CC" ${plump('#B9C0CC', 1.2)}/><ellipse cx="15.4" cy="12" rx="4.6" ry="3" fill="#C9CDD4" ${plump('#C9CDD4', 1.2)}/><ellipse cx="8" cy="17.6" rx="4.4" ry="2.9" fill="#B9C0CC" ${plump('#B9C0CC', 1.2)}/><circle cx="6" cy="5.8" r="0.9" fill="#fff" opacity="0.6"/><circle cx="14.4" cy="11.2" r="0.9" fill="#fff" opacity="0.6"/>`,
  gardenTree:
    `<circle cx="8.4" cy="9.4" r="4.6" fill="${GREEN}" ${plump(GREEN, 1.2)}/><circle cx="15.6" cy="9.4" r="4.6" fill="${GREEN_DARK}" ${plump(GREEN_DARK, 1.2)}/><circle cx="12" cy="6" r="4.6" fill="${GREEN_LIGHT}" ${plump(GREEN_LIGHT, 1.2)}/><path d="M12 12.4v8.4M12 15.4l3-2.4" stroke="#8A6B4A" stroke-width="2.4" stroke-linecap="round" fill="none"/>`,
  // reward-only slots (§C6 collection decos — previously the 🪑 fallback)
  candyShelf:
    `<rect x="3.6" y="14.6" width="16.8" height="2.6" rx="1.3" fill="${WOOD}" ${plump(WOOD, 1.2)}/><path d="M6 17.4v3M18 17.4v3" stroke="${WOOD_DARK}" stroke-width="2" stroke-linecap="round" fill="none"/><circle cx="8" cy="10.4" r="3.4" fill="${PINK}" ${plump(PINK, 1.2)}/><path d="M8 10.4m-1.9 0a1.9 1.9 0 1 1 3.8 0" stroke="#fff" stroke-width="1.3" fill="none" opacity="0.8"/><path d="M8 13.8v.8" stroke="#C9A87A" stroke-width="1.6" stroke-linecap="round" fill="none"/><rect x="13.4" y="6.4" width="5.6" height="8.2" rx="1.6" fill="${BLUE}" ${plump(BLUE, 1.2)}/><rect x="14.4" y="4.8" width="3.6" height="2" rx="0.9" fill="${WOOD_DARK}"/>`,
  fishBowl:
    `<path d="M12 3.4a8.6 8.6 0 0 1 8.6 8.6c0 4.8-3.8 8.6-8.6 8.6S3.4 16.8 3.4 12A8.6 8.6 0 0 1 12 3.4z" fill="#CFE8F5" ${plump('#CFE8F5')}/><path d="M4.6 10.4h14.8a7.4 7.4 0 0 1-14.8 0z" fill="${BLUE}" opacity="0.9"/><path d="M9.4 14.2s1.5-2.2 3.7-2.2c1.6 0 2.8 1.1 3.6 2.2-.8 1.1-2 2.2-3.6 2.2-2.2 0-3.7-2.2-3.7-2.2zm-.4-1.6 1.2 1.6-1.2 1.6z" fill="${ORANGE}"/><circle cx="14.7" cy="13.8" r="0.5" fill="#fff"/><circle cx="8.2" cy="7.4" r="1" fill="#fff" opacity="0.7"/>`,
  gardenTrophy:
    `<path d="M6.4 10.2h9.2a1 1 0 0 1 1 1.1l-.8 7a2.2 2.2 0 0 1-2.2 2h-5a2.2 2.2 0 0 1-2.2-2l-.8-7a1 1 0 0 1 1-1.1z" fill="${YELLOW}" ${plump(YELLOW)}/><path d="M15.8 12.2l3.4-2.6a1.3 1.3 0 0 0-1.6-2L14.4 10" stroke="${YELLOW}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" fill="none"/><path d="M6.8 10 4.6 6.8c2-.9 3.8-.5 5.2 1.2" stroke="${YELLOW}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" fill="none"/><path d="M4 5.4c.3 1 .3 2 0 3M2.6 6.4c.2.7.2 1.3 0 2" stroke="${BLUE_DEEP}" stroke-width="1.5" stroke-linecap="round" fill="none"/><path d="M9 13c.4 1.6.4 3.2 0 4.8" stroke="#fff" stroke-width="1.5" stroke-linecap="round" opacity="0.6" fill="none"/>`,
  toyCorner:
    `<rect x="4.2" y="12.6" width="7" height="7" rx="1.4" fill="${RED}" ${plump(RED, 1.2)}/><rect x="7.6" y="5.4" width="7" height="7" rx="1.4" fill="${YELLOW}" ${plump(YELLOW, 1.2)}/><circle cx="16.8" cy="16" r="3.6" fill="${BLUE_DEEP}" ${plump(BLUE_DEEP, 1.2)}/><path d="M13.2 16h7.2" stroke="#fff" stroke-width="1.4" opacity="0.7" fill="none"/><path d="M7.7 16.1h.9M11.1 8.9h.9" stroke="#fff" stroke-width="1.8" stroke-linecap="round" opacity="0.8" fill="none"/>`,
};

// ── PER-ITEM overrides — data/furniture.js entry ids (V6/FIX3 P1-13) ────────
// The four kitchen 'appliance' items shared the one generic category glyph, so
// the furniture tab showed four identical cards. getFurnitureIcon checks this
// map by ENTRY id before falling back to the slot category (same 2-tone +
// plump() language as everything above).
/** @type {Record<string, string>} */
const ITEM_PATHS = {
  toaster:
    `<rect x="7" y="5.2" width="4.2" height="6" rx="1.5" fill="${GOLD}" ${plump(GOLD, 1.2)}/><rect x="12.8" y="5.2" width="4.2" height="6" rx="1.5" fill="#E0A85C" ${plump('#E0A85C', 1.2)}/><path d="M3.6 13.2c0-1.7 1.3-3 3-3h10.8c1.7 0 3 1.3 3 3v4.4a2.6 2.6 0 0 1-2.6 2.6H6.2a2.6 2.6 0 0 1-2.6-2.6z" fill="${BLUE}" ${plump(BLUE)}/><path d="M21.2 12.8v2.6" stroke="${GREY}" stroke-width="2" stroke-linecap="round" fill="none"/><circle cx="8.6" cy="15.6" r="1.2" fill="${CREAM}"/><circle cx="12.2" cy="15.6" r="1.2" fill="${CREAM}"/><path d="M5.8 12.8l2.2-.8" stroke="#fff" stroke-width="1.4" stroke-linecap="round" opacity="0.7" fill="none"/>`,
  kitchenCoffeeMachine:
    `<rect x="5" y="2.8" width="14" height="4.6" rx="1.8" fill="#6E7787" ${plump('#6E7787')}/><rect x="8.2" y="7.4" width="7.6" height="2.4" rx="1" fill="#5A6272" ${plump('#5A6272', 1.2)}/><path d="M12 10v1.8" stroke="${CHOCO}" stroke-width="1.6" stroke-linecap="round" fill="none"/><path d="M9.4 12.2h5.2v2a2.6 2.6 0 0 1-2.6 2.6 2.6 2.6 0 0 1-2.6-2.6z" fill="${CREAM}" ${plump(CREAM, 1.2)}/><path d="M14.8 13h.6a1.4 1.4 0 0 1 0 2.8h-.6" stroke="${CREAM}" stroke-width="1.4" fill="none"/><rect x="4.6" y="18" width="14.8" height="2.6" rx="1.3" fill="#5A6272" ${plump('#5A6272', 1.2)}/><circle cx="16.9" cy="5.1" r="1.1" fill="${RED}"/><path d="M7 4.8l2.4-.6" stroke="#fff" stroke-width="1.4" stroke-linecap="round" opacity="0.7" fill="none"/>`,
  kitchenBlender:
    `<path d="M8 4.6h8l-1 8.9a2.2 2.2 0 0 1-2.2 1.9h-1.6A2.2 2.2 0 0 1 9 13.5z" fill="#CFE8F5" ${plump('#CFE8F5')}/><path d="M8.7 8.6h6.6l-.5 4.6a1.9 1.9 0 0 1-1.9 1.6h-1.8a1.9 1.9 0 0 1-1.9-1.6z" fill="${PINK_SOFT}"/><rect x="7.4" y="2.4" width="9.2" height="2.2" rx="1.1" fill="#6E7787" ${plump('#6E7787', 1.2)}/><rect x="7" y="15.6" width="10" height="5" rx="1.8" fill="#6E7787" ${plump('#6E7787')}/><circle cx="12" cy="18.1" r="1.2" fill="${RED}"/><path d="M9.6 6.8l1.6-.5" stroke="#fff" stroke-width="1.4" stroke-linecap="round" opacity="0.7" fill="none"/>`,
  kitchenMicrowave:
    `<rect x="2.8" y="6" width="18.4" height="12" rx="2.2" fill="#6E7787" ${plump('#6E7787')}/><rect x="5" y="8.2" width="10.2" height="7.6" rx="1.2" fill="#4C5566"/><ellipse cx="10.1" cy="13.6" rx="3" ry="1.2" fill="${CREAM}"/><circle cx="18.3" cy="10" r="1.2" fill="${CREAM}"/><path d="M17.4 12.8h1.8M17.4 14.8h1.8" stroke="${CREAM}" stroke-width="1.5" stroke-linecap="round" fill="none"/><path d="M6.4 18.4v1.2M17.6 18.4v1.2" stroke="${GREY}" stroke-width="2" stroke-linecap="round" fill="none"/><path d="M6.4 9.9l2.2-.8" stroke="#fff" stroke-width="1.4" stroke-linecap="round" opacity="0.7" fill="none"/>`,
};

/** Fallback plate glyph (unknown ids warn — the catalogs must stay complete). */
const PLATE =
  `<circle cx="12" cy="12" r="9.2" fill="#F3E4CE" ${plump('#F3E4CE')}/><circle cx="12" cy="12" r="5.4" fill="#fff" opacity="0.65"/>`;

/**
 * Wrap 24×24 inner markup in an inline-SVG tag.
 * @param {string} inner
 * @param {number} size px
 * @returns {string}
 */
function wrap(inner, size) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 24 24" aria-hidden="true">${inner}</svg>`;
}

/**
 * Authored icon for a data/foods.js catalog id.
 * @param {string} id food id (e.g. 'carrot', 'donut-sprinkles', 'nutella')
 * @param {number} [size] px (default 24)
 * @returns {string} SVG markup (plate fallback + console warning for unknown ids)
 */
export function getFoodIcon(id, size = 24) {
  const inner = FOOD_PATHS[id];
  if (!inner) {
    console.warn(`[foodIcons] unknown food icon: ${id}`);
    return wrap(PLATE, size);
  }
  return wrap(inner, size);
}

/**
 * Authored icon for a garden crop id. Crop ids ARE food ids (CROP_TABLE keys
 * mirror FOOD_TABLE rows), so this delegates to the food catalog — one
 * drawing per ingredient everywhere it appears.
 * @param {string} id crop id ('radish' | 'carrot' | … | 'watermelon')
 * @param {number} [size] px
 * @returns {string}
 */
export function getCropIcon(id, size = 24) {
  return getFoodIcon(id, size);
}

/**
 * Authored CATEGORY icon for a decor slot id (the V6 idea-10 ruling: 78
 * furniture items collapse onto their slot categories; per-item thumbnails
 * are a later, GLB-render-based upgrade).
 * @param {string} slotId decor slot ('sofa' | 'tv' | … | 'toyCorner')
 * @param {number} [size] px
 * @returns {string}
 */
export function getSlotIcon(slotId, size = 24) {
  const inner = SLOT_PATHS[slotId];
  if (!inner) {
    console.warn(`[foodIcons] unknown slot icon: ${slotId}`);
    return wrap(PLATE, size);
  }
  return wrap(inner, size);
}

/**
 * Authored icon for a furniture catalog entry. V6/FIX3 (P1-13): per-item
 * override first (the four kitchen appliances), then the slot category.
 * @param {{id?: string, slot: string}} entry data/furniture.js FurnitureEntry
 * @param {number} [size] px
 * @returns {string}
 */
export function getFurnitureIcon(entry, size = 24) {
  const inner = ITEM_PATHS[entry?.id ?? ''];
  if (inner) return wrap(inner, size);
  return getSlotIcon(entry?.slot ?? '', size);
}

/** @returns {string[]} all food ids with an authored icon (catalog-sync test) */
export function foodIconIds() {
  return Object.keys(FOOD_PATHS);
}

/** @returns {string[]} all slot ids with an authored icon (catalog-sync test) */
export function slotIconIds() {
  return Object.keys(SLOT_PATHS);
}

/** @returns {string[]} furniture ENTRY ids with a per-item override (V6/FIX3) */
export function itemIconIds() {
  return Object.keys(ITEM_PATHS);
}

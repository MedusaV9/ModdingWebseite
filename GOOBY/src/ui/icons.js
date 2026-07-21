// Inline SVG icon set (§D5 — no icon fonts/webfonts, Kenney ui-pack ruled out).
// icon(name, size) returns an SVG string sized for inline use in DOM UI.
// Later agents may add names; keep shapes simple and single-color (currentColor).
//
// V4/AC-1: redrawn for the Animal-Crossing design system — every glyph got
// fatter, rounder 24×24 strokes (round caps/joins, plumper silhouettes) for a
// friendlier look. All icon NAMES and the icon()/iconNames() signatures are
// unchanged (frozen interface for per-screen agents). The plumping trick:
// filled silhouettes carry a currentColor round-join stroke so corners soften
// and the shape gains weight without changing its footprint.

/** @type {Record<string, string>} inner SVG markup per icon (24×24 viewBox). */
const PATHS = {
  // stats
  hunger:
    '<path d="M12 3c-4 0-7 2.6-7 6.2 0 2.4 1.4 4.2 3.4 5.2L8 20a1 1 0 0 0 1 1h6a1 1 0 0 0 1-1l-.4-5.6c2-1 3.4-2.8 3.4-5.2C19 5.6 16 3 12 3z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>',
  energy:
    '<path d="M13 2 4.5 13.5H11L10 22l8.5-11.5H13L13 2z" stroke="currentColor" stroke-width="2.2" stroke-linejoin="round"/>',
  hygiene:
    '<path d="M12 2.6S5.6 9.9 5.6 14.2a6.4 6.4 0 0 0 12.8 0C18.4 9.9 12 2.6 12 2.6z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><circle cx="9.5" cy="14.8" r="1.3" fill="#fff" opacity="0.55"/>',
  fun: '<path d="M12 2.6l2.6 5.8 6.4.6-4.9 4.3 1.5 6.3-5.6-3.3-5.6 3.3 1.5-6.3-4.9-4.3 6.4-.6L12 2.6z" stroke="currentColor" stroke-width="2.4" stroke-linejoin="round"/>',
  // currency / progress
  coin: '<circle cx="12" cy="12" r="9.5"/><circle cx="12" cy="12" r="5.6" fill="none" stroke="#fff" stroke-width="1.8" opacity="0.5"/><circle cx="8.6" cy="8.4" r="1.6" fill="#fff" opacity="0.45"/>',
  star: '<path d="M12 2.6l2.6 5.8 6.4.6-4.9 4.3 1.5 6.3-5.6-3.3-5.6 3.3 1.5-6.3-4.9-4.3 6.4-.6L12 2.6z" stroke="currentColor" stroke-width="2.4" stroke-linejoin="round"/>',
  heart:
    '<path d="M12 20.6c-.4 0-.8-.1-1.1-.4C8.2 18.1 3 13.9 3 9.8 3 6.9 5.2 4.8 7.9 4.8c1.7 0 3.2.8 4.1 2.1.9-1.3 2.4-2.1 4.1-2.1 2.7 0 4.9 2.1 4.9 5 0 4.1-5.2 8.3-7.9 10.4-.3.3-.7.4-1.1.4z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>',
  sparkle:
    '<path d="M12 3.4c.3 0 .6.2.7.5l1.5 4.6 4.6 1.5c.7.2.7 1.2 0 1.4l-4.6 1.5-1.5 4.6c-.2.7-1.2.7-1.4 0l-1.5-4.6-4.6-1.5c-.7-.2-.7-1.2 0-1.4l4.6-1.5 1.5-4.6c.1-.3.4-.5.7-.5z"/><circle cx="19" cy="18.5" r="2.4"/><circle cx="5.4" cy="18.8" r="1.8"/>',
  // controls
  play: '<path d="M8.4 4.9 19 11a1.15 1.15 0 0 1 0 2L8.4 19.1c-.8.4-1.7-.1-1.7-1V5.9c0-.9.9-1.4 1.7-1z" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/>',
  pause:
    '<rect x="4.8" y="4.2" width="5.6" height="15.6" rx="2.8"/><rect x="13.6" y="4.2" width="5.6" height="15.6" rx="2.8"/>',
  close:
    '<path d="M6.2 6.2l11.6 11.6M17.8 6.2 6.2 17.8" stroke="currentColor" stroke-width="3.6" stroke-linecap="round" fill="none"/>',
  check:
    '<path d="M4.4 12.6l4.8 4.8L19.6 6.8" stroke="currentColor" stroke-width="3.6" stroke-linecap="round" stroke-linejoin="round" fill="none"/>',
  replay:
    '<path d="M4.9 6.9A8.6 8.6 0 1 1 3.4 12" stroke="currentColor" stroke-width="3" stroke-linecap="round" fill="none"/><path d="M4.9 2.2v4.7h4.7" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" fill="none"/>',
  arrowLeft:
    '<path d="M14.8 4.6 7.4 12l7.4 7.4" stroke="currentColor" stroke-width="3.6" stroke-linecap="round" stroke-linejoin="round" fill="none"/>',
  arrowRight:
    '<path d="M9.2 4.6 16.6 12l-7.4 7.4" stroke="currentColor" stroke-width="3.6" stroke-linecap="round" stroke-linejoin="round" fill="none"/>',
  lock: '<rect x="4.6" y="10" width="14.8" height="10.4" rx="3.4"/><path d="M8.2 10V7.2a3.8 3.8 0 0 1 7.6 0V10" stroke="currentColor" stroke-width="3" stroke-linecap="round" fill="none"/><circle cx="12" cy="15.2" r="1.7" fill="#fff" opacity="0.55"/>',
  home: '<path d="M3 11.5 12 3l9 8.5v8a1.5 1.5 0 0 1-1.5 1.5H15v-6H9v6H4.5A1.5 1.5 0 0 1 3 19.5v-8z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>',
  gear: '<circle cx="12" cy="12" r="5.4" fill="none" stroke="currentColor" stroke-width="3.2"/><path d="M12 2.6v2.6M12 18.8v2.6M21.4 12h-2.6M5.2 12H2.6M18.6 5.4l-1.8 1.8M7.2 16.8l-1.8 1.8M18.6 18.6l-1.8-1.8M7.2 7.2 5.4 5.4" stroke="currentColor" stroke-width="3" stroke-linecap="round" fill="none"/>',
  bell: '<path d="M12 3a6.2 6.2 0 0 0-6.2 6.2v3.9L4.3 16c-.5.7 0 1.7.9 1.7h13.6c.9 0 1.4-1 .9-1.7l-1.5-2.9V9.2A6.2 6.2 0 0 0 12 3z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><path d="M9.4 20.2a2.8 2.8 0 0 0 5.2 0" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" fill="none"/>',
  cart: '<circle cx="9.4" cy="19.6" r="2.1"/><circle cx="16.8" cy="19.6" r="2.1"/><path d="M3 4.4h2.4l2.4 10.4h9.7l2.5-7.6H7" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" fill="none"/>',
  trophy:
    '<path d="M7 4h10v2h4v2c0 2.5-2 4.5-4.3 4.9A5 5 0 0 1 13 16v2h3v3H8v-3h3v-2a5 5 0 0 1-3.7-3.1C5 12.5 3 10.5 3 8V6h4V4z" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/>',
  shirt:
    '<path d="M8 3 3 6l2 4 2-1v12h10V9l2 1 2-4-5-3a3 3 0 0 1-6 0z" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/>',
  // minigame tile icons (§C6)
  car: '<path d="M4 12l1.6-4.5A2 2 0 0 1 7.5 6h9a2 2 0 0 1 1.9 1.5L20 12v6h-2.5v-1.5h-11V18H4v-6zm3-1h10l-1-3H8l-1 3z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><circle cx="8" cy="14.5" r="1.5" fill="#fff" opacity="0.6"/><circle cx="16" cy="14.5" r="1.5" fill="#fff" opacity="0.6"/>',
  carrot:
    '<path d="M14 3c1.5-1.5 4 0 3.5 2 2-.5 3.5 2 2 3.5L18 10l-4-4 0-3zM17 11 7 21l-4-4L13 7l4 4z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>',
  rabbit:
    '<path d="M9 3c1.5 0 2.5 2 2.5 4.5h1C12.5 5 13.5 3 15 3s2 2.5.8 5c1.5 1 2.7 2.7 2.7 5A6.5 6.5 0 0 1 12 19.5 6.5 6.5 0 0 1 5.5 13c0-2.3 1.2-4 2.7-5C7 5.5 7.5 3 9 3z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>',
  shield:
    '<path d="M12 2.6l7.6 2.9v5.7c0 4.7-3.3 8.8-7.6 10.4-4.3-1.6-7.6-5.7-7.6-10.4V5.5L12 2.6z" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/>',
  cards:
    '<rect x="3" y="5" width="8" height="12" rx="2.5" transform="rotate(-8 7 11)" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><rect x="12" y="6" width="8" height="12" rx="2.5" transform="rotate(8 16 12)" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>',
  run: '<circle cx="15" cy="4.5" r="2.2"/><path d="M9 21l2.5-6L9 12.5l1.5-4L15 9l3 3 3-1-1 3-3.5-.5L14 17l-1.5 4H9z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>',
  ball: '<circle cx="12" cy="12" r="9.5"/><path d="M2.5 12h19M12 2.5a14.6 14.6 0 0 1 0 19M12 2.5a14.6 14.6 0 0 0 0 19" stroke="#fff" stroke-width="2" stroke-linecap="round" fill="none" opacity="0.6"/>',
  stack:
    '<rect x="4.6" y="14.8" width="14.8" height="4.4" rx="2.2"/><rect x="5.8" y="9.8" width="12.4" height="4.4" rx="2.2"/><rect x="7.4" y="4.8" width="9.2" height="4.4" rx="2.2"/>',
  music:
    '<path d="M9 19a3 3 0 1 1-2-2.8V6l12-2.5V16a3 3 0 1 1-2-2.8V7L9 9v10z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>',
  fish: '<path d="M3 12s3.5-5.5 9-5.5c4 0 7 2.8 9 5.5-2 2.7-5 5.5-9 5.5C6.5 17.5 3 12 3 12zm-1-4 3 4-3 4V8z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><circle cx="16" cy="11" r="1.3" fill="#fff"/>',
  bubble:
    '<circle cx="10" cy="10" r="7.2"/><circle cx="18" cy="17.2" r="3.6"/><circle cx="8" cy="8" r="2.1" fill="#fff" opacity="0.5"/>',
  spring:
    '<path d="M5 21h14M6 18h12M7.5 15h9M6.5 12h11M8 9h8" stroke="currentColor" stroke-width="3" stroke-linecap="round" fill="none"/><circle cx="12" cy="4.4" r="2.7"/>',
  // ── V3/G35 (§C6.1): nutella jar — glass jar glyph with a chocolate-brown
  // fill bar + cream lid band (fixed fills; the jar outline stays currentColor)
  nutellaJar:
    '<rect x="6" y="3" width="12" height="3.4" rx="1.7"/><rect x="7.2" y="6.4" width="9.6" height="1.6" rx="0.8" fill="#FFF6EC"/><path d="M6.5 8h11a1.5 1.5 0 0 1 1.5 1.5V19a2.5 2.5 0 0 1-2.5 2.5h-9A2.5 2.5 0 0 1 5 19V9.5A1.5 1.5 0 0 1 6.5 8z"/><path d="M6.5 12.5h11V19a1.5 1.5 0 0 1-1.5 1.5h-8A1.5 1.5 0 0 1 6.5 19v-6.5z" fill="#5C3A21"/>',
  // ── V4/UI-DEEP: new rounded glyphs so shop/vet/garden/codes/whatsNew drop
  // their raw-emoji chrome (same plumping language: round joins, soft fills).
  medicine:
    '<g transform="rotate(-45 12 12)"><rect x="3.6" y="8.4" width="16.8" height="7.2" rx="3.6" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M12 8.4h4.8a3.6 3.6 0 0 1 0 7.2H12v-7.2z" fill="#fff" opacity="0.4"/></g>',
  stethoscope:
    '<path d="M6.2 3.2v4.8a5 5 0 0 0 10 0V3.2" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" fill="none"/><path d="M11.2 12.8v2.6a4.3 4.3 0 0 0 8.6 0v-1.6" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" fill="none"/><circle cx="19.8" cy="11.4" r="2.5"/><circle cx="19.8" cy="11.4" r="0.9" fill="#fff" opacity="0.55"/>',
  clipboard:
    '<rect x="4.6" y="4.4" width="14.8" height="17" rx="2.8" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><rect x="8.4" y="2.4" width="7.2" height="4" rx="1.8"/><path d="M8.2 11.2h7.6M8.2 15.2h5.2" stroke="#fff" stroke-width="1.8" stroke-linecap="round" opacity="0.75"/>',
  sprout:
    '<path d="M12 21.2v-8.4" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" fill="none"/><path d="M12 13C12 8.6 8.8 5.8 4.4 5.8c0 4.4 3.2 7.2 7.6 7.2z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><path d="M12 13c0-4.4 3.2-7.2 7.6-7.2 0 4.4-3.2 7.2-7.6 7.2z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>',
  seeds:
    '<path d="M6 3.4h12a1.6 1.6 0 0 1 1.6 1.6v14a1.6 1.6 0 0 1-1.6 1.6H6A1.6 1.6 0 0 1 4.4 19V5A1.6 1.6 0 0 1 6 3.4z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M4.4 7.6h15.2" stroke="#fff" stroke-width="1.6" opacity="0.6"/><ellipse cx="9.4" cy="12.8" rx="1.6" ry="2.2" fill="#fff" opacity="0.8"/><ellipse cx="14.6" cy="12.8" rx="1.6" ry="2.2" fill="#fff" opacity="0.8"/><ellipse cx="12" cy="17" rx="1.6" ry="2.2" fill="#fff" opacity="0.8"/>',
  key:
    '<circle cx="7" cy="12" r="4.6" stroke="currentColor" stroke-width="2.2" fill="none"/><path d="M11.6 12h9.6M17.2 12v3.4M20.6 12v3.4" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" fill="none"/><circle cx="7" cy="12" r="1.4"/>',
  gift:
    '<rect x="4" y="10.8" width="16" height="9.8" rx="2.2"/><rect x="3" y="6.9" width="18" height="4.6" rx="1.9"/><path d="M12 7v13.6" stroke="#fff" stroke-width="2" opacity="0.7"/><path d="M12 6.4C9.8 6.4 7.6 5.4 7.6 3.9 7.6 2.6 9 2.2 10 2.9c.9.6 1.6 2 2 3.5.4-1.5 1.1-2.9 2-3.5 1-.7 2.4-.3 2.4 1 0 1.5-2.2 2.5-4.4 2.5z" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/>',
  bulb:
    '<path d="M12 2.8a6.6 6.6 0 0 0-3.6 12.1c.7.5 1.1 1.2 1.1 2v.7h5v-.7c0-.8.4-1.5 1.1-2A6.6 6.6 0 0 0 12 2.8z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/><path d="M9.8 20.4h4.4M10.6 22.4h2.8" stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/>',
  bandage:
    '<g transform="rotate(-45 12 12)"><rect x="2.6" y="8.2" width="18.8" height="7.6" rx="3.8" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><rect x="8.9" y="8.2" width="6.2" height="7.6" fill="#fff" opacity="0.45"/><circle cx="12" cy="10.6" r="0.8" fill="#fff"/><circle cx="10.6" cy="12" r="0.8" fill="#fff"/><circle cx="13.4" cy="12" r="0.8" fill="#fff"/><circle cx="12" cy="13.4" r="0.8" fill="#fff"/></g>',
  candy:
    '<circle cx="12" cy="12" r="5.6" stroke="currentColor" stroke-width="1.8"/><path d="M7 10 2.6 7.4v9.2L7 14z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><path d="M17 10l4.4-2.6v9.2L17 14z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><path d="M9.6 9.6l4.8 4.8" stroke="#fff" stroke-width="1.6" stroke-linecap="round" opacity="0.6"/>',
  scooter:
    '<circle cx="5.4" cy="18" r="2.5"/><circle cx="18.6" cy="18" r="2.5"/><path d="M5.4 18h6.8l4-9.6h3" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" fill="none"/><path d="M16.4 4.6h3.4M18.6 18l-1.6-6.4" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" fill="none"/>',
  hat:
    '<path d="M7 4.6h10a1.2 1.2 0 0 1 1.2 1.2V15H5.8V5.8A1.2 1.2 0 0 1 7 4.6z"/><rect x="2.8" y="14.6" width="18.4" height="4.8" rx="2.4"/><rect x="5.8" y="11" width="12.4" height="2.6" fill="#fff" opacity="0.4"/>',
  moon:
    '<path d="M20.4 14.4A8.8 8.8 0 0 1 9.6 3.6a8.8 8.8 0 1 0 10.8 10.8z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><circle cx="17.6" cy="6" r="1.6"/><circle cx="20.8" cy="9.6" r="1"/>',
  book:
    '<path d="M6.8 2.6H18a1.6 1.6 0 0 1 1.6 1.6v15.6a1.6 1.6 0 0 1-1.6 1.6H6.8A2.4 2.4 0 0 1 4.4 19V5a2.4 2.4 0 0 1 2.4-2.4z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M8.2 2.6v18.8" stroke="#fff" stroke-width="1.6" opacity="0.55"/><path d="M11.4 7.4h5" stroke="#fff" stroke-width="1.8" stroke-linecap="round" opacity="0.75"/>',
  radio:
    '<rect x="3" y="7.4" width="18" height="13" rx="2.8" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M7 7 16.6 2.8" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" fill="none"/><circle cx="16.2" cy="13.9" r="3" fill="#fff" opacity="0.75"/><path d="M6.4 11.4h5M6.4 14h5M6.4 16.6h5" stroke="#fff" stroke-width="1.6" stroke-linecap="round" opacity="0.7"/>',
  camera:
    '<path d="M4 7h3l1.6-2.4A1.5 1.5 0 0 1 9.9 4h4.2a1.5 1.5 0 0 1 1.3.6L17 7h3a1.5 1.5 0 0 1 1.5 1.5V19a1.5 1.5 0 0 1-1.5 1.5H4A1.5 1.5 0 0 1 2.5 19V8.5A1.5 1.5 0 0 1 4 7z"/><circle cx="12" cy="13.5" r="4" fill="#fff" opacity="0.55"/><circle cx="12" cy="13.5" r="2.1"/>',
  gamepad:
    '<path d="M7.4 5.6h9.2a5.8 5.8 0 0 1 5.7 7l-.7 3.5a3.4 3.4 0 0 1-5.9 1.6L14 15.9h-4l-1.7 1.8a3.4 3.4 0 0 1-5.9-1.6l-.7-3.5a5.8 5.8 0 0 1 5.7-7z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><path d="M7.6 8.8v4.4M5.4 11h4.4" stroke="#fff" stroke-width="1.8" stroke-linecap="round" opacity="0.8"/><circle cx="15.6" cy="12.4" r="1.1" fill="#fff" opacity="0.8"/><circle cx="18.2" cy="9.8" r="1.1" fill="#fff" opacity="0.8"/>',
  backpack:
    '<path d="M8.6 6a3.4 3.4 0 0 1 6.8 0" stroke="currentColor" stroke-width="2.4" fill="none" stroke-linecap="round"/><path d="M7.4 6.4h9.2A3.4 3.4 0 0 1 20 9.8v8.6a2.6 2.6 0 0 1-2.6 2.6H6.6A2.6 2.6 0 0 1 4 18.4V9.8a3.4 3.4 0 0 1 3.4-3.4z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/><rect x="7.8" y="13.2" width="8.4" height="4.6" rx="1.8" fill="#fff" opacity="0.5"/>',
  bow:
    '<path d="M10.2 12 4 8.4c-.9-.5-2 .1-2 1.2v4.8c0 1.1 1.1 1.7 2 1.2l6.2-3.6z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><path d="M13.8 12 20 8.4c.9-.5 2 .1 2 1.2v4.8c0 1.1-1.1 1.7-2 1.2L13.8 12z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><circle cx="12" cy="12" r="2.5"/>',
  vetRabbit:
    '<path d="M9 3c1.5 0 2.5 2 2.5 4.5h1C12.5 5 13.5 3 15 3s2 2.5.8 5c1.5 1 2.7 2.7 2.7 5A6.5 6.5 0 0 1 12 19.5 6.5 6.5 0 0 1 5.5 13c0-2.3 1.2-4 2.7-5C7 5.5 7.5 3 9 3z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><circle cx="9.6" cy="13" r="2" fill="none" stroke="#fff" stroke-width="1.3"/><circle cx="14.4" cy="13" r="2" fill="none" stroke="#fff" stroke-width="1.3"/><path d="M11.6 13h.8" stroke="#fff" stroke-width="1.3" stroke-linecap="round"/>',
  // ── V4/FIX-EMOJI: final authored-icon sweep — glyphs so careSheet/HUD/
  // radio/shopTrip/credits/garden chrome drops its last raw emoji (same
  // plumping language: fat 24×24 shapes, round joins, white accents).
  shuffle:
    '<path d="M3.4 7.5h3c1.7 0 3.3.9 4.2 2.3l2.8 4.4a5 5 0 0 0 4.2 2.3h1.6" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" fill="none"/><path d="M3.4 16.5h3c1.4 0 2.7-.6 3.6-1.6M13.9 9.1a5 5 0 0 1 3.7-1.6h1.6" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" fill="none"/><path d="M17.1 4.7l3.2 2.8-3.2 2.8M17.1 13.7l3.2 2.8-3.2 2.8" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" fill="none"/>',
  prev: '<rect x="3.8" y="4.6" width="3.2" height="14.8" rx="1.6"/><path d="M20 5.9v12.2c0 1-1.1 1.6-1.9 1L9.4 13a1.2 1.2 0 0 1 0-2l8.7-6.1c.8-.6 1.9 0 1.9 1z" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/>',
  next: '<rect x="17" y="4.6" width="3.2" height="14.8" rx="1.6"/><path d="M4 5.9v12.2c0 1 1.1 1.6 1.9 1l8.7-6.1a1.2 1.2 0 0 0 0-2L5.9 4.9c-.8-.6-1.9 0-1.9 1z" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/>',
  faceHappy:
    '<circle cx="12" cy="12" r="9.4" stroke="currentColor" stroke-width="1.8"/><circle cx="8.5" cy="9.8" r="1.5" fill="#fff"/><circle cx="15.5" cy="9.8" r="1.5" fill="#fff"/><path d="M7.9 14a4.7 4.7 0 0 0 8.2 0" stroke="#fff" stroke-width="2.1" stroke-linecap="round" fill="none"/>',
  faceQueasy:
    '<circle cx="12" cy="12" r="9.4" stroke="currentColor" stroke-width="1.8"/><path d="M6.8 9.2l3.2 1.2M17.2 9.2 14 10.4" stroke="#fff" stroke-width="2" stroke-linecap="round" fill="none"/><path d="M7.5 15.5c.75-1 2.25-1 3 0s2.25 1 3 0 2.25-1 3 0" stroke="#fff" stroke-width="2" stroke-linecap="round" fill="none"/>',
  faceSick:
    '<circle cx="12" cy="12" r="9.4" stroke="currentColor" stroke-width="1.8"/><circle cx="8.5" cy="9.8" r="1.5" fill="#fff"/><circle cx="15.5" cy="9.8" r="1.5" fill="#fff"/><path d="M8.3 16.4a4.7 4.7 0 0 1 7.4-.1" stroke="#fff" stroke-width="2.1" stroke-linecap="round" fill="none"/><path d="M17.2 13.6c1 1.5 1.5 2.5 1.5 3.3a1.7 1.7 0 0 1-3.4 0c0-.8.6-1.8 1.9-3.3z" fill="#fff" opacity="0.85"/>',
  snowflake:
    '<path d="M12 2.8v18.4M4 7.4l16 9.2M20 7.4 4 16.6" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" fill="none"/><circle cx="12" cy="12" r="2.4"/><circle cx="12" cy="12" r="1" fill="#fff" opacity="0.6"/>',
  globe:
    '<circle cx="12" cy="12" r="9.4" stroke="currentColor" stroke-width="1.8"/><path d="M2.9 12h18.2M12 2.9a14.4 14.4 0 0 1 0 18.2M12 2.9a14.4 14.4 0 0 0 0 18.2" stroke="#fff" stroke-width="1.7" stroke-linecap="round" fill="none" opacity="0.7"/><path d="M4.6 7.4a15.8 15.8 0 0 0 14.8 0M4.6 16.6a15.8 15.8 0 0 1 14.8 0" stroke="#fff" stroke-width="1.7" stroke-linecap="round" fill="none" opacity="0.45"/>',
  wrench:
    '<path d="M21.6 6.6a5.4 5.4 0 0 1-7.3 6.5L7.4 20a2.3 2.3 0 0 1-3.3-3.3l6.9-6.9a5.4 5.4 0 0 1 6.5-7.3L14 6l.7 3.3L18 10l3.6-3.4z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>',
  radish:
    '<path d="M12 8.8c3.8 0 6.6 2.5 6.6 5.6 0 3.4-3.1 5.6-5.6 6.9a2.1 2.1 0 0 1-2 0c-2.5-1.3-5.6-3.5-5.6-6.9 0-3.1 2.8-5.6 6.6-5.6z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/><path d="M12 8.8C12 5.4 9.6 3.2 6.4 3c.3 3.3 2.5 5.4 5.6 5.8z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><path d="M12 8.8c0-3.4 2.4-5.6 5.6-5.8-.3 3.3-2.5 5.4-5.6 5.8z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><path d="M12 16.6v2.8" stroke="#fff" stroke-width="1.6" stroke-linecap="round" opacity="0.55"/>',
};

/**
 * Render an icon as an inline SVG string.
 * @param {string} name key in the icon set
 * @param {number} [size] px (default 24)
 * @returns {string} SVG markup ('' for unknown names, with a console warning)
 */
export function icon(name, size = 24) {
  const inner = PATHS[name];
  if (!inner) {
    console.warn(`[icons] unknown icon: ${name}`);
    return '';
  }
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">${inner}</svg>`;
}

/** @returns {string[]} all icon names */
export function iconNames() {
  return Object.keys(PATHS);
}

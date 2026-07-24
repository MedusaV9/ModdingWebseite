// GOOBY 4.0 credits data (PLAN4.md §C-SYS12.4, binding — agent V4/G50).
// Rendered by ui/creditsScreen.js (wave 4, G81) as a static scrollable list;
// test/credits.test.js (G81) cross-checks section 4 rows against the
// committed asset roots so no shipped pack is uncredited and no phantom row
// ships. Pure data: no three.js/DOM imports (§B rule). Names/titles/links are
// LITERALS (not translated); section labels come from strings/v4-credits.js.
//
// Row shape:
//   { text } / { textKey }            plain line (textKey = t()-translated —
//       V6/FIX3 P1-10: body copy was hardcoded German and leaked into EN)
//   { title, by, license, note?|noteKey?, source? }  attribution row —
//       creditsScreen renders „{title}" von {by} — {license}(, {note}) ·
//       Quelle: {source}; noteKey keys translate at render time
//   { link }                          license/homepage URL (renders as TEXT —
//                                     §C-SYS12.4: taps are inert, no browser)
//   `packDir` (section 4 only): the committed root that proves the pack
//       shipped — credits.test.js fails when the dir and the row disagree.

/**
 * @typedef {Object} CreditRow
 * @property {string} [text]    plain LITERAL line (section 5 notice)
 * @property {string} [textKey] plain line, t() key (localized body copy)
 * @property {string} [title]   work title (attribution rows)
 * @property {string} [by]      author/creator as credited by the source
 * @property {string} [license] SPDX-ish label, e.g. 'CC BY 4.0', 'CC0'
 * @property {string} [note]    LITERAL change indication / optional credit
 * @property {string} [noteKey] change indication as t() key (CC BY rows —
 *     both locales must state modification, see strings/v6-fixes.js)
 * @property {string} [source]  source URL (rendered as text)
 * @property {string} [link]    bare URL row
 * @property {string} [packDir] committed dir under public/assets/ (section 4)
 */

/**
 * §C-SYS12.4 sections 1–5, verbatim. Section 2 rows are MANDATORY license
 * obligations (CC BY 4.0): both shipped splat scenes with author, license,
 * change indication („verändert (dezimiert/komprimiert)") and source link —
 * shipping a CC-BY asset without its row is a P1 (§A2). Avoncroft stays
 * staged as reserve; its row ships ONLY if the scene ever ships (§G6.2).
 */
export const CREDITS = Object.freeze({
  /** Section 1 — GOOBY. V6/FIX3 (P1-10): body copy is now t()-keyed EN+DE. */
  gooby: Object.freeze([
    Object.freeze({ textKey: 'credits.gooby.madeBy' }),
    // V4/AC-1: cozy-UI art (assets/acui/ — wordmark, pattern tiles, coin) is
    // project-made generated art, like the sticker art.
    Object.freeze({ textKey: 'credits.gooby.acui' }),
  ]),

  /** Section 2 — 3D-Welten (CC BY 4.0 — attribution REQUIRED, exact rows binding). */
  welten: Object.freeze([
    Object.freeze({
      title: 'S Windmill in Golden Gate Park',
      by: 'azadbal',
      license: 'CC BY 4.0',
      // V6/FIX3 (P1-10): CC BY change indication localizes via noteKey — both
      // locale values state the modification (license obligation intact).
      noteKey: 'credits.note.modified',
      source: 'https://superspl.at/scene/d5f14e49',
    }),
    Object.freeze({
      title: 'Ludlow - Quality Square',
      by: 'ijenko',
      license: 'CC BY 4.0',
      noteKey: 'credits.note.modified', // V6/FIX3 (P1-10)
      source: 'https://superspl.at/scene/ca36efcc',
    }),
    Object.freeze({ link: 'https://creativecommons.org/licenses/by/4.0' }),
  ]),

  /** Section 3 — Musik (CC0, Dank-Erwähnung freiwillig). */
  musik: Object.freeze([
    Object.freeze({ title: 'Playful Piano', by: 'Dylann Taylor', license: 'CC0' }),
    Object.freeze({ title: 'Music Loop Bundle', by: 'Tallbeard Studios/Abstraction', license: 'CC0' }),
    Object.freeze({ title: 'Orchestral & World Music', by: 'Ragnar Random', license: 'CC0' }),
  ]),

  /**
   * Section 4 — Sounds & Grafik (CC0). Rows render only for packs actually
   * committed at ship (`packDir` cross-check). Kenney/KayKit dirs hold many
   * packs each; the itch rows point at their exact committed folder.
   */
  soundsGrafik: Object.freeze([
    Object.freeze({ title: 'Kenney.nl', by: 'Kenney (alle Kenney-Packs)', license: 'CC0', packDir: 'kenney' }),
    Object.freeze({ title: 'KayKit', by: 'Kay Lousberg', license: 'CC0', packDir: 'kaykit' }),
    Object.freeze({ title: 'Tiny Treats — Baked Goods', by: 'Isa Lousberg', license: 'CC0', packDir: 'itch/baked-goods' }),
    Object.freeze({ title: 'Tiny Treats — Bakery Interior', by: 'Isa Lousberg', license: 'CC0', packDir: 'itch/bakery-interior' }),
    Object.freeze({ title: 'Tiny Treats — Pleasant Picnic', by: 'Isa Lousberg', license: 'CC0', packDir: 'itch/pleasant-picnic' }),
    // V5/ASSETS: the four new Tiny Treats packs (kitchen/bath dressing +
    // plant/park stock — all CC0, staged by scripts/stage-assets.mjs).
    Object.freeze({ title: 'Tiny Treats — Charming Kitchen', by: 'Isa Lousberg', license: 'CC0', packDir: 'itch/charming-kitchen' }),
    Object.freeze({ title: 'Tiny Treats — Bubbly Bathroom', by: 'Isa Lousberg', license: 'CC0', packDir: 'itch/bubbly-bathroom' }),
    Object.freeze({ title: 'Tiny Treats — House Plants', by: 'Isa Lousberg', license: 'CC0', packDir: 'itch/house-plants' }),
    Object.freeze({ title: 'Tiny Treats — Pretty Park', by: 'Isa Lousberg', license: 'CC0', packDir: 'itch/pretty-park' }),
    Object.freeze({ title: 'Interface SFX Pack 1', by: 'ObsydianX', license: 'CC0', packDir: 'itch/itch-sfx' }),
    Object.freeze({
      title: "Brackeys' VFX Bundle",
      by: 'Brackeys, Picster, Kenney, Thomas Iché, CodeManu',
      license: 'CC0',
      packDir: 'itch/vfx',
    }),
    Object.freeze({ title: 'Aline Furniture', by: 'Adelina Georgieva', license: 'CC0', packDir: 'itch/aline-furniture' }),
    // §C-SYS12.4 lists Cloudy Skyboxes / Lucid Icons / Particles Pack 2 /
    // Simple Vector UI as CANDIDATES — staged but NOT committed by G50, so
    // no rows ship (credits.test.js would flag them as phantom rows). A
    // later wave that commits one of those packs MUST append its row here.
  ]),

  /** Section 5 — Technik (MIT/BSD notice line). */
  technik: Object.freeze([
    Object.freeze({ text: 'three.js · Vite · Capacitor (MIT/BSD)' }),
    // V4/AC-1: bundled UI face — SIL OFL 1.1 obligation; license text ships at
    // public/assets/fonts/OFL.txt (renders as inert text like every row here).
    // V6/FIX3 (P1-10): the notice sentence localizes; font/foundry/license
    // names stay verbatim inside both locale strings.
    Object.freeze({ textKey: 'credits.technik.font' }),
  ]),
});

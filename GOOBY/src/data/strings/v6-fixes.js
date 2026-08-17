// V6/FIX3: v6-fixes.js — OWNED BY AGENT FIX3 (post-eval fix round).
// New keys for the V6 eval fixes: localized credits body copy (P1-10), the
// album Photos empty-state card (P1-11), the Quick-Delivery unlock hint
// (P1-12), the quest-board pinned-note decoration (P2-5), the Funkelpark
// day-trip loading card (P2-12) and the short album "Book" tab label
// (P2-23). Spread into strings.js after all other v6 modules. Always
// EN + DE. No other agent may edit this module.

/** @type {Record<string, string>} */
export const EN = {
  // ── P1-10: credits body copy (data/credits.js rows render these keys) ────
  'credits.gooby.madeBy': 'A game by PermissionMAXED & the GOOBY agents. Gooby is handmade.',
  'credits.gooby.acui': 'Cozy-UI art (wordmark, patterns, coin): project-made GOOBY art.',
  // CC BY change indication — the EN/DE pair both satisfy the license note
  'credits.note.modified': 'modified (decimated/compressed)',
  'credits.technik.font': 'Font “Baloo 2” by Ek Type (SIL OFL 1.1 — assets/fonts/OFL.txt)',

  // ── P1-11: album Photos tab empty state (codes-panel-style dashed card) ──
  'gallery.emptyTitle': 'No snapshots yet — take photos with the camera button at home!',

  // ── P1-12: Quick-Delivery offer unlock hint (level gate has its own key) ─
  'shop.qd.unlockHint': 'Unlock for {price} coins on your next shop trip!',

  // ── P2-5: quest board pinned-note decoration ─────────────────────────────
  'quests.boardNote': 'New adventures get pinned here!',

  // ── P2-12: Funkelpark day-trip loading card title ────────────────────────
  'mg.title.parkTrip': 'Funkelpark Day Trip',

  // ── P2-23: short album tab label (profile keeps the long album.tab.book) ─
  'album.tab.bookShort': 'Book',
};

/** @type {Record<string, string>} */
export const DE = {
  // ── P1-10: credits body copy ──────────────────────────────────────────────
  'credits.gooby.madeBy': 'Ein Spiel von PermissionMAXED & den GOOBY-Agenten. Gooby ist handgemacht.',
  'credits.gooby.acui': 'Cozy-UI-Grafik (Wortmarke, Muster, Münze): projekt-eigene GOOBY-Kunst.',
  'credits.note.modified': 'verändert (dezimiert/komprimiert)',
  'credits.technik.font': 'Schrift „Baloo 2“ von Ek Type (SIL OFL 1.1 — assets/fonts/OFL.txt)',

  // ── P1-11: Foto-Tab-Leerzustand ───────────────────────────────────────────
  'gallery.emptyTitle': 'Noch keine Schnappschüsse — mach Fotos mit dem Kamera-Knopf zu Hause!',

  // ── P1-12: Schnell-Lieferung-Freischalthinweis ───────────────────────────
  'shop.qd.unlockHint': 'Schalte sie für {price} Münzen bei deiner nächsten Einkaufsfahrt frei!',

  // ── P2-5: Pinnwand-Notizzettel ────────────────────────────────────────────
  'quests.boardNote': 'Neue Abenteuer werden hier angepinnt!',

  // ── P2-12: Funkelpark-Ausflug-Ladekarte ──────────────────────────────────
  'mg.title.parkTrip': 'Funkelpark-Ausflug',

  // ── P2-23: kurzes Album-Tab-Label ────────────────────────────────────────
  'album.tab.bookShort': 'Buch',
};

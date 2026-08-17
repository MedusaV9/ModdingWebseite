// META v1 (GAME-DESIGN §7) — Typen + pure Helfer, beidseitig importierbar.
// Profile ohne Account-Zwang, Shop-Katalog (28 Items + Spenden-Badge),
// die 4 Bestenlisten, der 15er-Stats-Katalog, Spaced-Repetition fürs Training.
// ALLES hier ist pur (kein IO, keine Uhr) — Zeit/Zufall kommen vom Aufrufer.

// ---------- Profile (§7.1) ----------

export interface ProfilAusruestung {
  hut?: string;
  gesicht?: string;
  hand?: string;
  buzzer?: string;
  konfetti?: string;
  titel?: string;
  fell?: string;
  spezies?: string;
  holo?: string;
  /** Podium-Hintergrund-Motiv (CSS-Gradient hinter dem Affen, §7.4-Ausbau). */
  banner?: string;
  /** Namens-Farbe/-Stil (dezente CSS-Klasse am Namen, §7.4-Ausbau). */
  namestil?: string;
  /** Podium-Rahmen um den eigenen Podest-Platz (Kosmetik-Welle 3). */
  podium?: string;
  /** Einlauf-Effekt bei der Kandidaten-Vorstellung im Opening (Welle 3). */
  einlauf?: string;
}

/** Persistiertes Profil (profiles.json) — Identität + AT-Konto + Besitz. */
export interface MetaProfil {
  profileId: string; // stabil (UUID-Kurzform), Name jederzeit änderbar
  name: string;
  avatar: string; // Basis "affe.farbe" (Wire-Format des Join-Flows)
  pinHash: string | null; // optionale 4-stellige PIN als Schloss
  createdAt: number;
  deviceTokens: string[]; // Geräte-Wiedererkennung (localStorage-Token)
  at: { gesamt: number; verfuegbar: number }; // Lifetime-AT (Level-Basis) + Guthaben
  besitz: string[]; // gekaufte Item-Ids
  ausgeruestet: ProfilAusruestung;
  ersteMale: { ultrahard?: boolean; sieg?: boolean; allin?: boolean };
  /** Doppel-Buchungs-Schutz: bereits AT-gebuchte Matches (Ring der letzten 50). */
  gebuchteMatches: string[];
}

/** Profil-Karte (§7.1): Avatar, Titel, Lieblings-/Nemesis-Kategorie, Bestwerte. */
export interface ProfilKarte {
  profileId: string;
  name: string;
  avatar: string;
  titel: string | null;
  level: number;
  at: { gesamt: number; verfuegbar: number };
  lieblingsKategorie: { kategorie: string; quote: number } | null;
  nemesisKategorie: { kategorie: string; quote: number } | null;
  schnellsteAntwortMs: number | null;
  hoechsterMatchGewinn: number;
  laengsteSerie: number;
  matches: number;
  siege: number;
  gesperrt: boolean; // PIN gesetzt?
  /** true = die letzte Match-Buchung steckt noch im Analytics-Ruhefenster
   * (~90 s) — Matches/Siege/Bestwerte hinken dem AT-Konto kurz hinterher. */
  statsAusstehend?: boolean;
}

/**
 * Level = Lifetime-AT-EINNAHMEN (§7.5, Ideen-S-12): KEIN zweites XP-System.
 * Kurve (verbindlich): Level n erreicht ab `1.000 × n × (n+1) / 2` Lifetime-AT —
 * jedes Level kostet 1.000 AT mehr als das vorherige (L1 = 1.000, L2 = 3.000,
 * L5 = 15.000 ≈ 1 Spielwoche, L10 = 55.000, L20 = 210.000 = Saison-Vielspieler,
 * L50 = 1,275 Mio., L100 = 5,05 Mio. — nach oben offen, Level 100+ bleibt ein
 * Lebenswerk). Ausgeben/Spenden senkt NIE das Level (Basis ist at.gesamt,
 * nicht at.verfuegbar).
 */
export function levelFuerAt(atGesamt: number): number {
  let n = 0;
  while ((1000 * (n + 1) * (n + 2)) / 2 <= Math.max(0, atGesamt)) n += 1;
  return n;
}

/** Kumulativ nötige Lifetime-AT für Level n (Umkehrung der Kurve). */
export function atFuerLevel(level: number): number {
  const n = Math.max(0, Math.floor(level));
  return (1000 * n * (n + 1)) / 2;
}

/** Level + Fortschritt zum nächsten Level (Anzeige: „Lv 7 · 62 %"). */
export function levelFortschritt(atGesamt: number): {
  level: number;
  /** AT-Schwelle des aktuellen Levels. */
  aktuellAb: number;
  /** AT-Schwelle des nächsten Levels. */
  naechstesAb: number;
  /** Anteil 0–1 auf dem Weg zum nächsten Level. */
  anteil: number;
} {
  const level = levelFuerAt(atGesamt);
  const aktuellAb = atFuerLevel(level);
  const naechstesAb = atFuerLevel(level + 1);
  const anteil = Math.max(
    0,
    Math.min(1, (Math.max(0, atGesamt) - aktuellAb) / (naechstesAb - aktuellAb)),
  );
  return { level, aktuellAb, naechstesAb, anteil };
}

// ---------- Level-Anzeige im Avatar-Wire-Format (klein neben dem Namen) ----------
// Das Profil-Level reist als Pseudo-Extra "lv<N>" im dritten Avatar-Segment mit
// (z. B. "don-bananas.gelb.hut-zylinder+lv7") — Alt-Clients ignorieren unbekannte
// Extras, der Renderer (meta-avatar.ts) macht daraus das Badge an Podium/Lobby.

export function levelToken(level: number): string | null {
  return level >= 1 ? `lv${Math.floor(level)}` : null;
}

/** Level aus Avatar-Extras lesen — null wenn kein lv-Token dabei ist. */
export function levelAusExtras(extras: string[]): number | null {
  for (const e of extras) {
    const m = /^lv(\d{1,4})$/.exec(e);
    if (m) return Number(m[1]);
  }
  return null;
}

// ---------- Avatar-Extras (Wire-Format-Erweiterung, abwärtskompatibel) ----------
// "affe.farbe" → "affe.farbe.item1+item2" — parseAvatar (Client) liest weiterhin
// nur die ersten beiden Segmente, Alt-Clients/Bots stören sich nicht.

export function avatarBasis(avatar: string): string {
  const [affe, farbe] = String(avatar).split(".");
  return farbe !== undefined ? `${affe}.${farbe}` : String(avatar);
}

export function avatarExtras(avatar: string): string[] {
  const teile = String(avatar).split(".");
  if (teile.length < 3 || teile[2].length === 0) return [];
  return teile[2].split("+").filter((s) => s.length > 0);
}

export function avatarMitExtras(basis: string, items: string[]): string {
  const b = avatarBasis(basis);
  return items.length > 0 ? `${b}.${items.join("+")}` : b;
}

/**
 * Sichtbare + FX-Extras eines Profils (für den Join-Flow): Slots → Item-Ids.
 * Buzzer/Konfetti sind keine Puppen-Overlays, reisen aber MIT, damit der
 * Screen sie im Match abspielen kann (Buzz-Sound, Feier-Konfetti — §7.4).
 */
export function extrasAusAusruestung(a: ProfilAusruestung): string[] {
  const items: string[] = [];
  for (const slot of [
    "hut",
    "gesicht",
    "hand",
    "fell",
    "spezies",
    "holo",
    "buzzer",
    "konfetti",
    "titel",
    "banner",
    "namestil",
    "podium",
    "einlauf",
  ] as const) {
    const id = a[slot];
    if (id) items.push(id);
  }
  return items;
}

// ---------- Shop-Sortiment (§7.4 — die 20 v1-Items + Buzzer-Familie + Spenden-Badge) ----------

export type ItemTyp =
  | "sound"
  | "accessoire"
  | "titel"
  | "sticker"
  | "konfetti"
  | "avatar"
  | "badge"
  | "banner"
  | "namestil"
  | "podium"
  | "einlauf";
export type ItemSlot =
  | "buzzer"
  | "hut"
  | "gesicht"
  | "hand"
  | "titel"
  | "sticker"
  | "konfetti"
  | "fell"
  | "spezies"
  | "holo"
  | "badge"
  | "banner"
  | "namestil"
  | "podium"
  | "einlauf";

export type Seltenheit = "gruen" | "reif" | "gold" | "diamant";

export interface ShopItem {
  id: string;
  name: string;
  emoji: string;
  typ: ItemTyp;
  slot: ItemSlot;
  preis: number; // AT
  beschreibung: string;
  /** Sound-Items: CC0-Datei unter /audio/sfx/ (Kenney-Packs). */
  datei?: string;
  /** Wird am Affen gerendert (SVG-Overlay/Fell-Swap) → wandert in die Avatar-Extras. */
  visuell?: boolean;
  /** Level-Gate (§7.5-Ausbau): kaufbar erst ab diesem Profil-Level. */
  minLevel?: number;
  /** Bananen-Pass-Exklusiv: Saison-Id — NICHT kaufbar, nur über Pass-Stufen. */
  passExklusiv?: string;
  /** Banner-Items: CSS-background des Podium-Hintergrund-Motivs. */
  stil?: string;
  /** Namens-Stil-Items: CSS-Klasse am Namen (dezent!). */
  klasse?: string;
}

/** Seltenheits-Stufe rein aus dem Preis (§7.4): Grün ≤1.000 · Reif ≤4.000 · Gold ≤15.000. */
export function seltenheitFuerPreis(preis: number): Seltenheit {
  if (preis >= 25_000) return "diamant";
  if (preis >= 5_000) return "gold";
  if (preis >= 2_000) return "reif";
  return "gruen";
}

export const SHOP_ITEMS: ShopItem[] = [
  // 1–4: Buzzer-Sounds (aus den CC0-Packs wählbar)
  {
    id: "buzzer-entenquak",
    name: "Buzzer „Entenquak“",
    emoji: "🦆",
    typ: "sound",
    slot: "buzzer",
    preis: 500,
    beschreibung: "Dein Lock-in quakt.",
    datei: "slime_000.ogg",
  },
  {
    id: "buzzer-modem",
    name: "Buzzer „Dial-up-Modem“",
    emoji: "📠",
    typ: "sound",
    slot: "buzzer",
    preis: 750,
    beschreibung: "Brzzzt-krrrsch — Antwort eingewählt.",
    datei: "glitch_002.ogg",
  },
  {
    id: "buzzer-oper",
    name: "Buzzer „Opern-Aaah“",
    emoji: "🎭",
    typ: "sound",
    slot: "buzzer",
    preis: 750,
    beschreibung: "Dramatischer Einsatz, jedes Mal.",
    datei: "jingles_SAX10.ogg",
  },
  {
    id: "buzzer-furz",
    name: "Buzzer „Furz Deluxe“",
    emoji: "💨",
    typ: "sound",
    slot: "buzzer",
    preis: 1000,
    beschreibung: "Der Klassiker. Deluxe-Edition.",
    datei: "lowThreeTone.ogg",
  },
  // Standard-Buzzer-Familie (ART-PLAN §4.3 Lücke 3): 8 echte, klanglich klar
  // unterscheidbare Timbres (CC0, BigSoundBank/Wikimedia — s. CREDITS.md).
  // Jeder Spieler-Slot bekommt automatisch einen ANDEREN davon als Standard
  // (client/shared/fx/sound-map.ts: standardBuzzer) — kaufen heißt: selbst wählen.
  {
    id: "buzzer-hupe",
    name: "Buzzer „Hupe“",
    emoji: "📯",
    typ: "sound",
    slot: "buzzer",
    preis: 250,
    beschreibung: "Tröööt — Vorfahrt für deine Antwort.",
    datei: "buzzer_hupe_cc0_bsb.ogg",
  },
  {
    id: "buzzer-klingel",
    name: "Buzzer „Fahrradklingel“",
    emoji: "🚲",
    typ: "sound",
    slot: "buzzer",
    preis: 250,
    beschreibung: "Ring-ring! Antwort kommt durch.",
    datei: "buzzer_klingel_cc0_bsb.ogg",
  },
  {
    id: "buzzer-quaek-hupe",
    name: "Buzzer „Quietsch-Ente“",
    emoji: "🐥",
    typ: "sound",
    slot: "buzzer",
    preis: 500,
    beschreibung: "Quiek-quiek. Niemand nimmt dich ernst. Perfekt.",
    datei: "buzzer_quaek_cc0_bsb.ogg",
  },
  {
    id: "buzzer-glocke",
    name: "Buzzer „Rezeptions-Glocke“",
    emoji: "🛎️",
    typ: "sound",
    slot: "buzzer",
    preis: 250,
    beschreibung: "Pling! Service, bitte — eine Antwort.",
    datei: "buzzer_glocke_cc0_bsb.ogg",
  },
  {
    id: "buzzer-boing",
    name: "Buzzer „Boing“",
    emoji: "🤸",
    typ: "sound",
    slot: "buzzer",
    preis: 500,
    beschreibung: "Cartoon-Sprungfeder. Deine Antwort federt rein.",
    datei: "buzzer_boing_cc0_bsb.ogg",
  },
  {
    id: "buzzer-pfeife",
    name: "Buzzer „Trillerpfeife“",
    emoji: "⚽",
    typ: "sound",
    slot: "buzzer",
    preis: 250,
    beschreibung: "Schiri-Pfiff — Abpfiff für die Konkurrenz.",
    datei: "buzzer_pfeife_cc0_bsb.ogg",
  },
  {
    id: "buzzer-wecker",
    name: "Buzzer „Wecker“",
    emoji: "⏰",
    typ: "sound",
    slot: "buzzer",
    preis: 500,
    beschreibung: "Mechanisches Rasseln — Schorschs Lieblingsklang.",
    datei: "buzzer_wecker_cc0_bsb.ogg",
  },
  {
    id: "buzzer-airhorn",
    name: "Buzzer „Airhorn“",
    emoji: "📢",
    typ: "sound",
    slot: "buzzer",
    preis: 750,
    beschreibung: "Druckluft-Fanfare. Das ganze Stadion weiß Bescheid.",
    datei: "buzzer_airhorn_cc0_bsb.ogg",
  },
  // 5–10: Accessoires (SVG-Overlays auf die Affen-Puppen)
  {
    id: "hut-zylinder",
    name: "Kopf „Zylinder“",
    emoji: "🎩",
    typ: "accessoire",
    slot: "hut",
    preis: 500,
    beschreibung: "Old Money.",
    visuell: true,
  },
  {
    id: "hut-bananenhelm",
    name: "Kopf „Bananen-Helm“",
    emoji: "🍌",
    typ: "accessoire",
    slot: "hut",
    preis: 1000,
    beschreibung: "Sicherheit geht vor.",
    visuell: true,
  },
  {
    id: "gesicht-monokel",
    name: "Gesicht „Monokel“",
    emoji: "🧐",
    typ: "accessoire",
    slot: "gesicht",
    preis: 500,
    beschreibung: "Für das prüfende Starren.",
    visuell: true,
  },
  {
    id: "gesicht-3dbrille",
    name: "Gesicht „3D-Brille“",
    emoji: "🕶️",
    typ: "accessoire",
    slot: "gesicht",
    preis: 750,
    beschreibung: "Die Show in 3D.",
    visuell: true,
  },
  {
    id: "hand-kaffeetasse",
    name: "Hand „Kaffeetasse“",
    emoji: "☕",
    typ: "accessoire",
    slot: "hand",
    preis: 500,
    beschreibung: "Erst der Kaffee, dann die Antwort.",
    visuell: true,
  },
  {
    id: "hand-minibuzzer",
    name: "Hand „Mini-Buzzer“",
    emoji: "🔴",
    typ: "accessoire",
    slot: "hand",
    preis: 1000,
    beschreibung: "Immer buzzer-bereit.",
    visuell: true,
  },
  // 11–12: Titel (Spaß, kaufbar)
  {
    id: "titel-bananen-baron",
    name: "Titel „Bananen-Baron“",
    emoji: "👑",
    typ: "titel",
    slot: "titel",
    preis: 500,
    beschreibung: "Adel verpflichtet zu nichts.",
  },
  {
    id: "titel-buzzer-berserker",
    name: "Titel „Buzzer-Berserker“",
    emoji: "⚡",
    typ: "titel",
    slot: "titel",
    preis: 1000,
    beschreibung: "Erst drücken, dann denken.",
  },
  // 13: Sticker-Pack
  {
    id: "sticker-boersen-panik",
    name: "Sticker „Börsen-Panik“ (8 Taunts)",
    emoji: "📉",
    typ: "sticker",
    slot: "sticker",
    preis: 1500,
    beschreibung: "8 Taunts für Auflösungs-Fenster.",
  },
  // 14–15: Konfetti-Stile (Money-Regen)
  {
    id: "konfetti-bananen-regen",
    name: "Konfetti „Bananen-Regen“",
    emoji: "🍌",
    typ: "konfetti",
    slot: "konfetti",
    preis: 2000,
    beschreibung: "Es regnet Bananen statt Scheine.",
  },
  {
    id: "konfetti-8bit",
    name: "Konfetti „8-Bit-Scheine“",
    emoji: "👾",
    typ: "konfetti",
    slot: "konfetti",
    preis: 3000,
    beschreibung: "Pixel-Geld wie 1987.",
  },
  // 16–17: Fell-Muster
  {
    id: "fell-leopard",
    name: "Fell „Leopard“",
    emoji: "🐆",
    typ: "avatar",
    slot: "fell",
    preis: 3000,
    beschreibung: "Raubkatzen-Chic.",
    visuell: true,
  },
  {
    id: "fell-neon",
    name: "Fell „Neon“",
    emoji: "🌈",
    typ: "avatar",
    slot: "fell",
    preis: 4000,
    beschreibung: "Leuchtet bis in die letzte Reihe.",
    visuell: true,
    minLevel: 3,
  },
  // 18–19: Spezies
  {
    id: "spezies-orang-utan",
    name: "Spezies „Orang-Utan“",
    emoji: "🦧",
    typ: "avatar",
    slot: "spezies",
    preis: 6000,
    beschreibung: "Rotes Edel-Fell.",
    visuell: true,
    minLevel: 5,
  },
  {
    id: "spezies-pavian",
    name: "Spezies „Pavian“",
    emoji: "🐒",
    typ: "avatar",
    slot: "spezies",
    preis: 6000,
    beschreibung: "Grau, würdevoll, gefährlich.",
    visuell: true,
    minLevel: 5,
  },
  // 20: Legendär
  {
    id: "avatar-hologramm",
    name: "„Hologramm-Affe“ (animiert)",
    emoji: "✨",
    typ: "avatar",
    slot: "holo",
    preis: 25_000,
    beschreibung: "Flimmert wie aus der Zukunft.",
    visuell: true,
    minLevel: 10,
  },
  // Spenden-Badge (AT-Senke, rein kosmetisch — §7.4-Charta: verändert NIE das Spiel)
  {
    id: "badge-spende",
    name: "Spenden-Badge „Bananen-Stiftung“",
    emoji: "💛",
    typ: "badge",
    slot: "badge",
    preis: 1000,
    beschreibung: "1.000 AT an die Bananen-Stiftung. Fürs Herz.",
  },
  // ---------- Kosmetik-Welle 2 (Meta-Agent 2): 10 Titel · 6 Banner ·
  // 4 Namens-Stile · 2 Konfetti — rein kosmetisch, teils level-gated (§7.5).
  // Titel (Spaß, kaufbar — Verdienst-Badges bleiben unkaufbar, S-08)
  {
    id: "titel-bananen-fluesterer",
    name: "Titel „Bananen-Flüsterer“",
    emoji: "🤫",
    typ: "titel",
    slot: "titel",
    preis: 750,
    beschreibung: "Die Bananen erzählen dir alles.",
  },
  {
    id: "titel-ultrahard-ueberlebender",
    name: "Titel „ULTRAHARD-Überlebender“",
    emoji: "💀",
    typ: "titel",
    slot: "titel",
    preis: 2000,
    beschreibung: "Hat die 1.000er-Frage gesehen und lebt noch.",
    minLevel: 4,
  },
  {
    id: "titel-zins-geniesser",
    name: "Titel „Zins-Genießer“",
    emoji: "🛋️",
    typ: "titel",
    slot: "titel",
    preis: 500,
    beschreibung: "Lässt das Geld arbeiten. Selbst? Niemals.",
  },
  {
    id: "titel-frisch-gewaschen",
    name: "Titel „Frisch gewaschen“",
    emoji: "🧼",
    typ: "titel",
    slot: "titel",
    preis: 500,
    beschreibung: "Das Geld, versteht sich.",
  },
  {
    id: "titel-jackpot-magnet",
    name: "Titel „Jackpot-Magnet“",
    emoji: "🍯",
    typ: "titel",
    slot: "titel",
    preis: 1500,
    beschreibung: "Das Glas kommt freiwillig zu dir.",
  },
  {
    id: "titel-schaetz-orakel",
    name: "Titel „Schätz-Orakel“",
    emoji: "🔮",
    typ: "titel",
    slot: "titel",
    preis: 1000,
    beschreibung: "Plusminus 3 % — immer.",
  },
  {
    id: "titel-affenkoenig",
    name: "Titel „Affenkönig“",
    emoji: "🦍",
    typ: "titel",
    slot: "titel",
    preis: 5000,
    beschreibung: "Es gibt nur einen. Meistens.",
    minLevel: 6,
  },
  {
    id: "titel-pleitegeier",
    name: "Titel „Pleitegeier“",
    emoji: "🦅",
    typ: "titel",
    slot: "titel",
    preis: 500,
    beschreibung: "Für Ironiker mit Dispo-Erfahrung.",
  },
  {
    id: "titel-eiskalter-analyst",
    name: "Titel „Eiskalter Analyst“",
    emoji: "🧊",
    typ: "titel",
    slot: "titel",
    preis: 1000,
    beschreibung: "Erst denken, dann drücken. Immer.",
  },
  {
    id: "titel-lianen-legende",
    name: "Titel „Lianen-Legende“",
    emoji: "🌿",
    typ: "titel",
    slot: "titel",
    preis: 2500,
    beschreibung: "Schwingt sich durch jedes Finale.",
  },
  // Banner: Podium-Hintergrund-Motive (CSS-Gradients hinter dem Affen —
  // Anzeige am Podium + in der Lobby, Renderer: client/shared/meta-avatar.ts)
  {
    id: "banner-dschungelnacht",
    name: "Banner „Dschungel-Nacht“",
    emoji: "🌙",
    typ: "banner",
    slot: "banner",
    preis: 2000,
    beschreibung: "Tiefgrünes Blätterdach mit Mondlicht.",
    visuell: true,
    stil: "radial-gradient(circle at 70% 12%, rgba(255,246,227,0.35) 0 8%, transparent 22%), linear-gradient(180deg, #0c2b1d 0%, #14532d 55%, #1f7a45 100%)",
  },
  {
    id: "banner-bananenplantage",
    name: "Banner „Bananen-Tapete“",
    emoji: "🍌",
    typ: "banner",
    slot: "banner",
    preis: 2000,
    beschreibung: "Bananen. Überall Bananen.",
    visuell: true,
    stil: "repeating-linear-gradient(135deg, #f5b301 0 14px, #ffc93c 14px 28px, #f5b301 28px 30px)",
  },
  {
    id: "banner-retro-arcade",
    name: "Banner „Retro-Arcade“",
    emoji: "👾",
    typ: "banner",
    slot: "banner",
    preis: 3000,
    beschreibung: "CRT-Streifen wie 1987.",
    visuell: true,
    stil: "repeating-linear-gradient(0deg, #1f2430 0 6px, #262d3d 6px 12px), linear-gradient(180deg, #2b1b4d 0%, #1f2430 100%)",
  },
  {
    id: "banner-casino-neon",
    name: "Banner „Casino-Neon“",
    emoji: "🎰",
    typ: "banner",
    slot: "banner",
    preis: 4000,
    beschreibung: "Las Vegas fürs Pult.",
    visuell: true,
    stil: "radial-gradient(circle at 20% 20%, rgba(255,62,142,0.5) 0 18%, transparent 40%), radial-gradient(circle at 80% 70%, rgba(41,217,213,0.45) 0 18%, transparent 42%), linear-gradient(160deg, #2a0f3d 0%, #1f2430 100%)",
  },
  {
    id: "banner-goldregen",
    name: "Banner „Goldregen“",
    emoji: "🪙",
    typ: "banner",
    slot: "banner",
    preis: 4000,
    beschreibung: "Es schimmert, wo du stehst.",
    visuell: true,
    minLevel: 6,
    stil: "radial-gradient(circle at 30% 25%, rgba(255,246,227,0.5) 0 6%, transparent 16%), radial-gradient(circle at 65% 55%, rgba(255,246,227,0.4) 0 5%, transparent 14%), linear-gradient(180deg, #8a6100 0%, #f5b301 60%, #ffc93c 100%)",
  },
  {
    id: "banner-weltraum",
    name: "Banner „Weltraum“",
    emoji: "🚀",
    typ: "banner",
    slot: "banner",
    preis: 6000,
    beschreibung: "Anti-Schwerkraft-Scheine nicht inklusive.",
    visuell: true,
    minLevel: 8,
    stil: "radial-gradient(circle at 15% 30%, #fff6e3 0 1.5%, transparent 3%), radial-gradient(circle at 70% 15%, #fff6e3 0 1%, transparent 2.5%), radial-gradient(circle at 45% 70%, #fff6e3 0 1.2%, transparent 2.6%), radial-gradient(circle at 85% 60%, #29d9d5 0 1.5%, transparent 3%), linear-gradient(200deg, #0b1026 0%, #1c2452 100%)",
  },
  // Namens-Farben/-Stile (CSS-Klassen am Namen — dezent, nie Lesbarkeits-Killer)
  {
    id: "namestil-neon-gruen",
    name: "Name „Neon-Grün“",
    emoji: "🟢",
    typ: "namestil",
    slot: "namestil",
    preis: 1500,
    beschreibung: "Dein Name leuchtet dezent nach.",
    visuell: true,
    klasse: "mm-name-neon",
  },
  {
    id: "namestil-eisblau",
    name: "Name „Eisblau“",
    emoji: "🧊",
    typ: "namestil",
    slot: "namestil",
    preis: 1500,
    beschreibung: "Kühl. Klar. Analytisch.",
    visuell: true,
    klasse: "mm-name-eis",
  },
  {
    id: "namestil-gold-glitzer",
    name: "Name „Gold-Glitzer“",
    emoji: "✨",
    typ: "namestil",
    slot: "namestil",
    preis: 3000,
    beschreibung: "Old-Money-Schimmer im Schriftzug.",
    visuell: true,
    minLevel: 7,
    klasse: "mm-name-gold",
  },
  {
    id: "namestil-regenbogen",
    name: "Name „Regenbogen“",
    emoji: "🌈",
    typ: "namestil",
    slot: "namestil",
    preis: 4000,
    beschreibung: "Alle Farben, sanft rotierend.",
    visuell: true,
    minLevel: 9,
    klasse: "mm-name-regenbogen",
  },
  // 2 neue Konfetti-Stile (Money-Regen-Varianten, §7.4/S-07)
  {
    id: "konfetti-goldmuenzen",
    name: "Konfetti „Goldmünzen-Regen“",
    emoji: "🪙",
    typ: "konfetti",
    slot: "konfetti",
    preis: 3000,
    beschreibung: "Kling, kling — Münzen statt Scheine.",
  },
  {
    id: "konfetti-herbstlaub",
    name: "Konfetti „Herbstlaub“",
    emoji: "🍂",
    typ: "konfetti",
    slot: "konfetti",
    preis: 2000,
    beschreibung: "Melancholisch reich. Für die Ironiker.",
  },
  // ---------- Kosmetik-Welle 3 (Cosmetics-Agent): 22 ECHTE Sichtbar-Items ----------
  // 8 Kopf + 4 Gesicht (SVG-Overlays, assets/img/cosmetics/) · 5 Fell-Muster
  // (SVG-Pattern-Fill auf die Fell-Flächen) · 3 Podium-Rahmen · 2 Einlauf-
  // Effekte. 4 davon sind Level-Exklusive (minLevel — die „Pass/Level"-Gates
  // dieser Welle); Renderer: client/shared/meta-avatar.ts.
  {
    id: "hut-blumenkranz",
    name: "Kopf „Blumenkranz“",
    emoji: "🌸",
    typ: "accessoire",
    slot: "hut",
    preis: 1000,
    beschreibung: "Flower-Power fürs Fell.",
    visuell: true,
  },
  {
    id: "hut-pirat",
    name: "Kopf „Piratenhut“",
    emoji: "🏴‍☠️",
    typ: "accessoire",
    slot: "hut",
    preis: 1500,
    beschreibung: "Dreispitz mit Totenkopf — Beute garantiert.",
    visuell: true,
  },
  {
    id: "hut-partyhut",
    name: "Kopf „Party-Hut“",
    emoji: "🥳",
    typ: "accessoire",
    slot: "hut",
    preis: 1500,
    beschreibung: "Mit Konfetti-Spitze. Immer Grund zum Feiern.",
    visuell: true,
  },
  {
    id: "hut-propeller",
    name: "Kopf „Propeller-Kappe“",
    emoji: "🚁",
    typ: "accessoire",
    slot: "hut",
    preis: 2000,
    beschreibung: "Der Propeller dreht wirklich. Abheben nicht garantiert.",
    visuell: true,
  },
  {
    id: "hut-teufelshoerner",
    name: "Kopf „Teufelshörner“",
    emoji: "😈",
    typ: "accessoire",
    slot: "hut",
    preis: 2500,
    beschreibung: "Für den kleinen Klau zwischendurch.",
    visuell: true,
  },
  {
    id: "hut-heiligenschein",
    name: "Kopf „Heiligenschein“",
    emoji: "😇",
    typ: "accessoire",
    slot: "hut",
    preis: 2500,
    beschreibung: "Schwebt. Du hast NIE geklaut.",
    visuell: true,
  },
  {
    id: "hut-ritterhelm",
    name: "Kopf „Ritterhelm“",
    emoji: "⚔️",
    typ: "accessoire",
    slot: "hut",
    preis: 3000,
    beschreibung: "Volle Deckung gegen Buzzer-Attacken.",
    visuell: true,
  },
  {
    id: "hut-krone",
    name: "Kopf „Goldene Krone“",
    emoji: "👑",
    typ: "accessoire",
    slot: "hut",
    preis: 8000,
    beschreibung: "Echtgold-Optik mit Juwelen. Für Affenkönige.",
    visuell: true,
    minLevel: 8,
  },
  {
    id: "gesicht-schnurrbart",
    name: "Gesicht „Schnurrbart“",
    emoji: "🥸",
    typ: "accessoire",
    slot: "gesicht",
    preis: 750,
    beschreibung: "Fein gezwirbelt. Sehr seriös.",
    visuell: true,
  },
  {
    id: "gesicht-augenklappe",
    name: "Gesicht „Augenklappe“",
    emoji: "🦜",
    typ: "accessoire",
    slot: "gesicht",
    preis: 750,
    beschreibung: "Ein Auge reicht für diese Fragen.",
    visuell: true,
  },
  {
    id: "gesicht-sonnenbrille",
    name: "Gesicht „Sonnenbrille“",
    emoji: "🕶️",
    typ: "accessoire",
    slot: "gesicht",
    preis: 2000,
    beschreibung: "Verspiegelt. Niemand sieht dich zweifeln.",
    visuell: true,
  },
  {
    id: "gesicht-kaugummi",
    name: "Gesicht „XXL-Kaugummi“",
    emoji: "🫧",
    typ: "accessoire",
    slot: "gesicht",
    preis: 2500,
    beschreibung: "Rosa Riesen-Blase. Pulsiert. Platzt nie.",
    visuell: true,
  },
  {
    id: "fell-tiger",
    name: "Fell „Tiger-Streifen“",
    emoji: "🐯",
    typ: "avatar",
    slot: "fell",
    preis: 3000,
    beschreibung: "Echtes Streifen-Muster im Fell — Raubtier-Modus.",
    visuell: true,
  },
  {
    id: "fell-dalmatiner",
    name: "Fell „Dalmatiner-Bananen“",
    emoji: "🍌",
    typ: "avatar",
    slot: "fell",
    preis: 3000,
    beschreibung: "Punkte? Nein: Mini-Bananen. Überall.",
    visuell: true,
  },
  {
    id: "fell-camo",
    name: "Fell „Dschungel-Camo“",
    emoji: "🪖",
    typ: "avatar",
    slot: "fell",
    preis: 3500,
    beschreibung: "Tarnflecken — im Dschungel unsichtbar, am Buzzer nicht.",
    visuell: true,
  },
  {
    id: "fell-sterne",
    name: "Fell „Sternenhimmel“",
    emoji: "⭐",
    typ: "avatar",
    slot: "fell",
    preis: 4000,
    beschreibung: "Sterne im Fell. Astrologisch wertvoll.",
    visuell: true,
  },
  {
    id: "fell-goldglitzer",
    name: "Fell „Gold-Glitzer“",
    emoji: "✨",
    typ: "avatar",
    slot: "fell",
    preis: 12_000,
    beschreibung: "Subtiler Gold-Schimmer, funkelt bei jeder Bewegung.",
    visuell: true,
    minLevel: 10,
  },
  {
    id: "podium-girlande",
    name: "Podium „Bananen-Girlande“",
    emoji: "🌿",
    typ: "podium",
    slot: "podium",
    preis: 3000,
    beschreibung: "Dein Podest ist geschmückt wie zum Erntedankfest.",
    visuell: true,
  },
  {
    id: "podium-neon",
    name: "Podium „Neon-Glow“",
    emoji: "💡",
    typ: "podium",
    slot: "podium",
    preis: 4000,
    beschreibung: "Dein Podest pulsiert türkis. Las Vegas nickt.",
    visuell: true,
  },
  {
    id: "podium-goldrahmen",
    name: "Podium „Goldrahmen“",
    emoji: "🖼️",
    typ: "podium",
    slot: "podium",
    preis: 5000,
    beschreibung: "Dein Podest, museumsreif eingerahmt.",
    visuell: true,
    minLevel: 6,
  },
  {
    id: "einlauf-rauchwolke",
    name: "Einlauf „Rauchwolke“",
    emoji: "💨",
    typ: "einlauf",
    slot: "einlauf",
    preis: 4000,
    beschreibung: "Du erscheinst im Opening aus einer Rauchwolke.",
    visuell: true,
  },
  {
    id: "einlauf-blitz",
    name: "Einlauf „Blitz-Einschlag“",
    emoji: "⚡",
    typ: "einlauf",
    slot: "einlauf",
    preis: 6000,
    beschreibung: "Ein Blitz schlägt ein — und da stehst DU.",
    visuell: true,
    minLevel: 7,
  },
];

// ---------- Willkommens-Paket (Null-AT-Einstieg, Meta-Fix W20) ----------
// Das ERSTE Profil pro Gerät bekommt ein einmaliges Starter-Geschenk:
// 300 Start-AT + den Gratis-Titel „Frischer Affe". Server-seitig idempotent
// (profile-store.erstelle prüft, ob der Geräte-Token schon ein Profil hat).
// Der Titel ist NICHT kaufbar (passExklusiv-Gate) — nur verschenkbar.

export const WILLKOMMEN_START_AT = 300;

export const WILLKOMMEN_ITEM: ShopItem = {
  id: "titel-frischer-affe",
  name: "Titel „Frischer Affe“",
  emoji: "🐵",
  typ: "titel",
  slot: "titel",
  preis: 0,
  beschreibung: "Willkommens-Geschenk fürs erste Profil auf einem Gerät.",
  passExklusiv: "willkommen",
};

export const SHOP_ITEM_MAP: ReadonlyMap<string, ShopItem> = new Map(
  [...SHOP_ITEMS, WILLKOMMEN_ITEM].map((i) => [i.id, i]),
);

// ---------- Match-FX aus dem Profil (§7.4 — Shop-Items wirken im Match) ----------

export type KonfettiStil = "klassisch" | "bananen" | "8bit" | "muenzen" | "laub" | "blaetter";

const KONFETTI_STIL_ITEMS: Record<string, KonfettiStil> = {
  "konfetti-bananen-regen": "bananen",
  "konfetti-8bit": "8bit",
  "konfetti-goldmuenzen": "muenzen",
  "konfetti-herbstlaub": "laub",
  // Bananen-Pass Saison 1 „Dschungel-Auftakt" (Stufe 20, shared/quests.ts)
  "konfetti-s1-blaetterwirbel": "blaetter",
};

/** Gekaufter Buzzer-Sound aus den Avatar-Extras (SFX-Id = Item-Id) — null = Standard. */
export function buzzerSoundAus(avatar: string): string | null {
  for (const id of avatarExtras(avatar)) {
    if (SHOP_ITEM_MAP.get(id)?.slot === "buzzer") return id;
  }
  return null;
}

/** Gewählter Konfetti-Stil für die Feier-Momente — "klassisch" ohne gekauftes Item. */
export function konfettiStilAus(avatar: string): KonfettiStil {
  for (const id of avatarExtras(avatar)) {
    const stil = KONFETTI_STIL_ITEMS[id];
    if (stil) return stil;
  }
  return "klassisch";
}

/** Anti-Dark-Pattern (§7.4): Preis zusätzlich in Spielabenden (~3.000 AT/Abend). */
export function preisInAbenden(preis: number): string {
  const abende = preis / 3000;
  if (abende <= 0.5) return "ein paar Runden";
  if (abende <= 1.2) return "≈ 1 Abend";
  return `≈ ${Math.ceil(abende)} Abende`;
}

// ---------- Stats-Katalog (§7.2 — die 15, materialisiert pro Profil) ----------

/** Histogramm-Bucket-Grenzen für Antwortzeiten (Median ohne Rohdaten-Speicher). */
export const ZEIT_BUCKET_MS = 500;
export const ZEIT_BUCKETS = 40; // 0–20 s

export interface ZellStat {
  n: number;
  richtig: number;
}

export interface ProfilStats {
  // 1 Richtig-Quote gesamt
  beantwortet: number;
  richtig: number;
  // 2 Genauigkeits-Matrix Kategorie × Schwierigkeit ("kategorie|schwierigkeit")
  matrix: Record<string, ZellStat>;
  // 3 Median-Antwort-/Buzz-Zeit (Histogramm) + 4 schnellster Buzz
  zeitBuckets: number[];
  schnellsteAntwortMs: number | null;
  // 5 Aggressivitäts-Index (Antworten in den ersten 20 % der Zeit + falsch-schnell)
  schnelleAntworten: number;
  schnelleFalsch: number;
  // 6 Matches / Siege
  matches: number;
  siege: number;
  // 7 Lifetime-AT (Level-Basis — Spiegel des Profil-Kontos)
  atLifetime: number;
  // 8 Höchster Einzel-Match-Endstand
  besterEndstand: number;
  // 9 Längste Richtig-Serie (matchübergreifend)
  laengsteSerie: number;
  aktuelleSerie: number;
  // 10 Längste Sieges-Serie
  laengsteSiegesserie: number;
  aktuelleSiegesserie: number;
  // 11 Joker-Effizienz
  mitJoker: ZellStat;
  ohneJoker: ZellStat;
  // 12 Wett-Bilanz
  wettenGewonnen: number;
  wettenVerloren: number;
  groessterWettgewinn: number;
  // 13 Klau-Bilanz (MM)
  gestohlen: number;
  bestohlen: number;
  // 14 Comeback-Zähler
  comebackSiege: number;
  comebackMatches: number;
}

export function leereProfilStats(): ProfilStats {
  return {
    beantwortet: 0,
    richtig: 0,
    matrix: {},
    zeitBuckets: new Array(ZEIT_BUCKETS).fill(0) as number[],
    schnellsteAntwortMs: null,
    schnelleAntworten: 0,
    schnelleFalsch: 0,
    matches: 0,
    siege: 0,
    atLifetime: 0,
    besterEndstand: 0,
    laengsteSerie: 0,
    aktuelleSerie: 0,
    laengsteSiegesserie: 0,
    aktuelleSiegesserie: 0,
    mitJoker: { n: 0, richtig: 0 },
    ohneJoker: { n: 0, richtig: 0 },
    wettenGewonnen: 0,
    wettenVerloren: 0,
    groessterWettgewinn: 0,
    gestohlen: 0,
    bestohlen: 0,
    comebackSiege: 0,
    comebackMatches: 0,
  };
}

/** Median aus dem Zeit-Histogramm (Bucket-Mitte) — null bei leerer Stichprobe. */
export function medianAusBuckets(buckets: number[], bucketMs = ZEIT_BUCKET_MS): number | null {
  const gesamt = buckets.reduce((a, b) => a + b, 0);
  if (gesamt === 0) return null;
  let rest = Math.ceil(gesamt / 2);
  for (let i = 0; i < buckets.length; i++) {
    rest -= buckets[i];
    if (rest <= 0) return i * bucketMs + bucketMs / 2;
  }
  return (buckets.length - 1) * bucketMs + bucketMs / 2;
}

/** Lieblings-/Nemesis-Kategorie (§7.2/15): höchste/niedrigste Quote ab 20 Antworten. */
export function lieblingsUndNemesis(matrix: Record<string, ZellStat>): {
  lieblings: { kategorie: string; quote: number } | null;
  nemesis: { kategorie: string; quote: number } | null;
} {
  const proKategorie = new Map<string, ZellStat>();
  for (const [key, zelle] of Object.entries(matrix)) {
    const kategorie = key.split("|")[0];
    const summe = proKategorie.get(kategorie) ?? { n: 0, richtig: 0 };
    proKategorie.set(kategorie, { n: summe.n + zelle.n, richtig: summe.richtig + zelle.richtig });
  }
  let lieblings: { kategorie: string; quote: number } | null = null;
  let nemesis: { kategorie: string; quote: number } | null = null;
  for (const [kategorie, z] of proKategorie) {
    if (z.n < 20) continue; // Fairness-Schwelle
    const quote = z.richtig / z.n;
    if (lieblings === null || quote > lieblings.quote) lieblings = { kategorie, quote };
    if (nemesis === null || quote < nemesis.quote) nemesis = { kategorie, quote };
  }
  if (lieblings && nemesis && lieblings.kategorie === nemesis.kategorie) nemesis = null;
  return { lieblings, nemesis };
}

// ---------- Bestenlisten (§7.3 — genau 4, mit Fairness-Schwellen) ----------

export interface BoardEintrag {
  profileId: string;
  name: string;
  avatar: string;
  titel: string | null;
  wert: number; // Sortier-Metrik
  anzeige: string; // formatiert ("12.400 AT", "83 %", "612 ms")
  extra?: string; // z. B. Kategorie beim Kategorie-Meister
}

export interface Boards {
  moneyBoss: BoardEintrag[]; // Lifetime-AT, keine Schwelle
  kategorieMeister: BoardEintrag[]; // beste Quote je Kategorie, ≥ 20 Antworten
  blitzBuzzer: BoardEintrag[]; // MEDIAN-Zeit, ≥ 30 gewertete Antworten
  comebackKoenig: BoardEintrag[]; // Comeback-Win-Rate, ≥ 5 solcher Matches
}

export const BOARD_SCHWELLEN = {
  kategorieMeister: 20,
  blitzBuzzer: 30,
  comebackKoenig: 5,
} as const;

/** Automatische Titel der Board-Spitzen (§7.3) — wandern beim Überholen. */
export const BOARD_TITEL: Record<keyof Boards, string> = {
  moneyBoss: "💰 Money-Boss",
  kategorieMeister: "🎓 Kategorie-Meister",
  blitzBuzzer: "⚡ Blitz-Buzzer",
  comebackKoenig: "👑 Comeback-König",
};

// ---------- Lobby-Rotation (Screen): QR ↔ Bestenlisten, dezent alle 12 s ----------

export const LOBBY_ROTATION_MS = 12_000;

export type LobbySlide = "qr" | keyof Boards;

/** Slides mit Inhalt: erst QR/Join-Info, danach NUR die nicht-leeren Boards. */
export function lobbySlides(boards: Boards | null): LobbySlide[] {
  const slides: LobbySlide[] = ["qr"];
  if (!boards) return slides;
  for (const key of Object.keys(BOARD_TITEL) as (keyof Boards)[]) {
    if (boards[key].length > 0) slides.push(key);
  }
  return slides;
}

/** Aktiver Slide-Index rein aus der Zeit (deterministisch — Uhr injiziert). */
export function lobbySlideIndex(
  nowMs: number,
  slideAnzahl: number,
  intervallMs = LOBBY_ROTATION_MS,
): number {
  if (slideAnzahl <= 1) return 0;
  return Math.floor(Math.max(0, nowMs) / intervallMs) % slideAnzahl;
}

// ---------- Übungsmodus: Spaced-Repetition (leichtgewichtig, §6.2) ----------

export interface UebungsFrageStat {
  richtig: number;
  falsch: number;
  /** Richtige in Folge (Leitner-Box 0–4). */
  serie: number;
  zuletztTs: number | null;
}

/**
 * Auswahl-Gewicht einer Frage im Training: nie gesehen = neugierig (3),
 * oft falsch = deutlich öfter (bis ×4), sicher gekonnt = selten (Box-Abbau).
 * Pure Funktion — die Ziehung selbst macht der Aufrufer mit injiziertem Rng.
 */
export function uebungsGewicht(stat: UebungsFrageStat | undefined): number {
  if (!stat || stat.richtig + stat.falsch === 0) return 3;
  const box = Math.max(0, Math.min(4, stat.serie));
  const boxFaktor = [4, 2, 1, 0.5, 0.25][box];
  const falschAnteil = stat.falsch / (stat.richtig + stat.falsch);
  return (1 + 3 * falschAnteil) * boxFaktor;
}

/** Gewichtete Ziehung (deterministisch mit injiziertem [0,1)-Wert). */
export function gewichteteWahl<T>(kandidaten: { wert: T; gewicht: number }[], u: number): T | null {
  const summe = kandidaten.reduce((a, k) => a + Math.max(0, k.gewicht), 0);
  if (summe <= 0 || kandidaten.length === 0) return null;
  let ziel = Math.max(0, Math.min(0.999999, u)) * summe;
  for (const k of kandidaten) {
    ziel -= Math.max(0, k.gewicht);
    if (ziel < 0) return k.wert;
  }
  return kandidaten[kandidaten.length - 1].wert;
}

// ---------- Fragen-Gesundheit (Analytics §7.6, pro Frage) ----------

export interface FrageStats {
  ausspielungen: number;
  antworten: number;
  richtig: number;
  zeitSummeMs: number;
  zeitN: number;
  tippKaeufe: number;
  flags: { grund: string; ts: number; matchId: string }[];
  /** Ausspiel-Zeitstempel (Ring der letzten 10) — Abnutzungs-Report (3× in 60 Tagen). */
  gespieltTs: number[];
  /** Quote je Spielmodus getrennt (CONTENT-PLAN §3.2). */
  proModus: Record<string, ZellStat>;
}

export function leereFrageStats(): FrageStats {
  return {
    ausspielungen: 0,
    antworten: 0,
    richtig: 0,
    zeitSummeMs: 0,
    zeitN: 0,
    tippKaeufe: 0,
    flags: [],
    gespieltTs: [],
    proModus: {},
  };
}

/** Ratebereinigte Quote (CONTENT-PLAN §3.1): (roh − r) / (1 − r), r = 0,25 bei choice4. */
export function bereinigteQuote(richtig: number, n: number, ratebasis = 0.25): number | null {
  if (n === 0) return null;
  return Math.max(0, (richtig / n - ratebasis) / (1 - ratebasis));
}

/** Ziel-Bänder der ratebereinigten Quote je Stufe (CONTENT-PLAN §3.1). */
export const QUOTE_BAND: Record<string, { min: number; max: number }> = {
  easy: { min: 0.8, max: 0.95 },
  medium: { min: 0.45, max: 0.7 },
  hard: { min: 0.15, max: 0.4 },
  ultrahard: { min: 0, max: 0.1 },
};

const STUFEN_REIHE = ["easy", "medium", "hard", "ultrahard"] as const;

/**
 * Umstufungs-Regel (CONTENT-PLAN §3.2): ab n ≥ 20 — Quote im Band der
 * Nachbar-Stufe ⇒ Vorschlag; 2+ Stufen daneben ⇒ Quarantäne; 0 % bei n ≥ 10 ⇒
 * Sofort-Quarantäne („Frage der Schande").
 */
export function driftUrteil(
  stufe: string,
  richtig: number,
  n: number,
): {
  art: "ok" | "zu-wenig-daten" | "vorschlag" | "quarantaene";
  zielStufe?: string;
  quote: number | null;
} {
  const quote = bereinigteQuote(richtig, n);
  // „Frage der Schande": ROH 0 richtig — die bereinigte Quote klemmt auch
  // Unter-Ratebasis-Werte auf 0 und darf hier nicht fälschlich zünden.
  if (richtig === 0 && n >= 10) return { art: "quarantaene", quote };
  if (n < 20) return { art: "zu-wenig-daten", quote };
  if (quote === null) return { art: "zu-wenig-daten", quote };
  const index = STUFEN_REIHE.indexOf(stufe as (typeof STUFEN_REIHE)[number]);
  if (index < 0) return { art: "ok", quote };
  const band = QUOTE_BAND[stufe];
  if (quote >= band.min && quote <= band.max) return { art: "ok", quote };
  // In welchem Band liegt die gemessene Quote? (bei Überlappungs-Lücken: nächstes Band)
  let gemessen = index;
  for (let i = 0; i < STUFEN_REIHE.length; i++) {
    const b = QUOTE_BAND[STUFEN_REIHE[i]];
    if (quote >= b.min && quote <= b.max) {
      gemessen = i;
      break;
    }
    // Lücken zwischen Bändern: der Stufe mit der näheren Grenze zuschlagen.
    if (i + 1 < STUFEN_REIHE.length) {
      const naechste = QUOTE_BAND[STUFEN_REIHE[i + 1]];
      if (quote < b.min && quote > naechste.max) {
        gemessen = quote - naechste.max < b.min - quote ? i + 1 : i;
        break;
      }
    }
  }
  if (gemessen === index) return { art: "ok", quote };
  if (Math.abs(gemessen - index) >= 2)
    return { art: "quarantaene", zielStufe: STUFEN_REIHE[gemessen], quote };
  return { art: "vorschlag", zielStufe: STUFEN_REIHE[gemessen], quote };
}

// ---------- AI-Spieler-Personas (§8.3-Vorgriff, v1: 5 Personas) ----------

export interface BotPersona {
  id: string;
  name: string;
  avatar: string; // "affe.farbe"
  /** Basis-Trefferwahrscheinlichkeit 0–1. */
  skill: number;
  /** Antwort-Verzögerung (Anteil der verfügbaren Zeit, min–max). */
  tempo: { min: number; max: number };
  /** Kategorie-Stärken/-Schwächen: Oberkategorie-Slug → Skill-Delta. */
  staerken: Record<string, number>;
  /** Wett-Verhalten (Alles oder Banane): Anteil des erlaubten Einsatzes. */
  mut: number;
}

export const BOT_PERSONAS: BotPersona[] = [
  {
    id: "kokos",
    name: "Kokos 🤖",
    avatar: "gitti-giro.gruen",
    skill: 0.85,
    tempo: { min: 0.35, max: 0.7 },
    staerken: { wissen: 0.1, erdkunde: 0.1, popkultur: -0.1 },
    mut: 0.2,
  },
  {
    id: "splitter",
    name: "Splitter 🤖",
    avatar: "kiki-krawall.rot",
    skill: 0.6,
    tempo: { min: 0.1, max: 0.3 },
    staerken: { games: 0.15, sport: 0.1, wissen: -0.1 },
    mut: 0.95,
  },
  {
    id: "banana-joe",
    name: "Banana Joe 🤖",
    avatar: "schnarch-schorsch.gelb",
    skill: 0.55,
    tempo: { min: 0.5, max: 0.9 },
    staerken: { essen: 0.15, tiere: 0.1 },
    mut: 0.05,
  },
  {
    id: "prof-pavian",
    name: "Prof. Pavian 🤖",
    avatar: "baron-von-bananenstein.lila",
    skill: 0.75,
    tempo: { min: 0.4, max: 0.8 },
    staerken: { wissen: 0.2, geschichte: 0.15, popkultur: -0.2, games: -0.15 },
    mut: 0.35,
  },
  {
    id: "chaos-gina",
    name: "Chaos-Gina 🤖",
    avatar: "glitzer-gina.pink",
    skill: 0.35,
    tempo: { min: 0.05, max: 0.25 },
    staerken: { popkultur: 0.2, musik: 0.15 },
    mut: 0.7,
  },
];

/** Effektiver Bot-Skill für eine Kategorie (Ober- oder Unter-Slug). */
export function botSkillFuer(persona: BotPersona, kategorie: string | null): number {
  let delta = 0;
  if (kategorie) {
    for (const [slug, d] of Object.entries(persona.staerken)) {
      if (kategorie === slug || kategorie.startsWith(`${slug}-`) || kategorie.includes(slug)) {
        delta = d;
        break;
      }
    }
  }
  return Math.max(0.05, Math.min(0.98, persona.skill + delta));
}

// BANANEN-PASS + QUESTS (Meta-Agent 2) — pure Logik, beidseitig importierbar.
//
// Saison = Kalendermonat (UTC): saisonIdFuer("2026-08") · 30 Pass-Stufen ·
// PASS-XP aus Matches (beendet = 50, Sieg = +50) und Quests (Daily 80,
// Monats-Quest 400). KEIN Echtgeld — ein einziger Gratis-Track.
//
// XP-Kurve (dokumentiert): Stufe 1–10 kosten je 100 XP, 11–20 je 150,
// 21–30 je 200 ⇒ 4.500 XP für den vollen Pass. Rechnung: ~12 Abende/Monat ×
// 3 Matches (~75 XP im Schnitt) ≈ 2.700 + Dailies (~240/Spieltag) + 3 Monats-
// Quests (1.200) ⇒ der volle Pass ist für regelmäßige Spieler gut erreichbar,
// für Gelegenheits-Spieler ein Streckenziel. Saison-Ende: nicht Erreichtes
// verfällt (Archiv zeigt, was man geholt hat) — die Saison-Items selbst
// bleiben für immer im Besitz.
//
// ALLES hier ist pur (kein IO, keine Uhr) — Zeit kommt IMMER vom Aufrufer.
import { SHOP_ITEM_MAP, type ShopItem } from "./meta";
import { createRng } from "./rng";

// ---------- Saison = Kalendermonat (UTC) ----------

/** Saison 1 „Dschungel-Auftakt" — der erste Pass-Monat des Spiels. */
export const SAISON_ERSTE = "2026-08";

/** Saison-Id ("YYYY-MM", UTC) für einen Zeitpunkt. */
export function saisonIdFuer(nowMs: number): string {
  const d = new Date(nowMs);
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
}

/** Tages-Schlüssel ("YYYY-MM-DD", UTC) — Basis der Daily-Rotation. */
export function tagKeyFuer(nowMs: number): string {
  const d = new Date(nowMs);
  return `${saisonIdFuer(nowMs)}-${String(d.getUTCDate()).padStart(2, "0")}`;
}

/** Laufende Saison-Nummer (1-basiert): Monate seit SAISON_ERSTE + 1. */
export function saisonNummer(saisonId: string): number {
  const [j0, m0] = SAISON_ERSTE.split("-").map(Number);
  const [j, m] = saisonId.split("-").map(Number);
  return Math.max(1, (j - j0) * 12 + (m - m0) + 1);
}

/** Saison-Ende: erste Millisekunde des Folgemonats (UTC) — für Countdown. */
export function saisonEndeMs(saisonId: string): number {
  const [j, m] = saisonId.split("-").map(Number);
  return Date.UTC(m === 12 ? j + 1 : j, m === 12 ? 0 : m, 1);
}

/** 6 rotierende Saison-Themen (Name + Farbwelt für generierte Items). */
const SAISON_THEMEN = [
  {
    name: "Dschungel-Auftakt",
    wort: "Dschungel",
    farbe: "#8fe04b",
    banner1: "linear-gradient(180deg, #14532d 0%, #2e8b57 60%, #8fe04b 100%)",
    banner2:
      "repeating-linear-gradient(115deg, #0c2b1d 0 18px, #14532d 18px 36px), linear-gradient(180deg, transparent, rgba(143,224,75,0.25))",
  },
  {
    name: "Casino-Fieber",
    wort: "Casino",
    farbe: "#ff3e8e",
    banner1:
      "radial-gradient(circle at 25% 30%, rgba(255,62,142,0.55) 0 20%, transparent 45%), linear-gradient(170deg, #2a0f3d, #1f2430)",
    banner2: "repeating-linear-gradient(45deg, #c2183b 0 16px, #1f2430 16px 32px)",
  },
  {
    name: "Weltraum-Expedition",
    wort: "Weltraum",
    farbe: "#29d9d5",
    banner1:
      "radial-gradient(circle at 30% 25%, #fff6e3 0 1.5%, transparent 3%), linear-gradient(200deg, #0b1026, #1c2452)",
    banner2:
      "radial-gradient(circle at 70% 60%, rgba(41,217,213,0.5) 0 15%, transparent 38%), linear-gradient(180deg, #0b1026, #10163a)",
  },
  {
    name: "Piraten-Beute",
    wort: "Piraten",
    farbe: "#f5b301",
    banner1: "linear-gradient(180deg, #0f3a4a 0%, #17607a 60%, #f5b301 130%)",
    banner2: "repeating-linear-gradient(90deg, #6b4226 0 20px, #8a5a3b 20px 40px)",
  },
  {
    name: "Arcade-Angriff",
    wort: "Arcade",
    farbe: "#b26bff",
    banner1:
      "repeating-linear-gradient(0deg, #1f2430 0 8px, #2b1b4d 8px 16px), linear-gradient(180deg, #2b1b4d, #1f2430)",
    banner2:
      "radial-gradient(circle at 50% 40%, rgba(178,107,255,0.5) 0 18%, transparent 42%), #1f2430",
  },
  {
    name: "Eiszeit-Expedition",
    wort: "Eiszeit",
    farbe: "#a8e6ff",
    banner1: "linear-gradient(180deg, #0e2a4a 0%, #2a6f97 60%, #a8e6ff 120%)",
    banner2: "repeating-linear-gradient(135deg, #2a6f97 0 14px, #0e2a4a 14px 28px)",
  },
] as const;

export function saisonName(saisonId: string): string {
  return SAISON_THEMEN[(saisonNummer(saisonId) - 1) % SAISON_THEMEN.length].name;
}

// ---------- Bananen-Pass: Stufen + XP-Kurve ----------

export const PASS_STUFEN = 30;
/** PASS-XP-Quellen (Aufgabe: Match beendet = 50, Sieg = +50 obendrauf). */
export const XP_MATCH = 50;
export const XP_SIEG = 50;
export const XP_DAILY = 80;
export const XP_MONAT = 400;

/** XP-Kosten der Stufe s (1-basiert): 1–10 je 100 · 11–20 je 150 · 21–30 je 200. */
export function xpKostenFuerStufe(stufe: number): number {
  if (stufe <= 10) return 100;
  if (stufe <= 20) return 150;
  return 200;
}

/** Kumulative XP-Schwelle, ab der Stufe s erreicht ist (S10 = 1.000, S30 = 4.500). */
export function xpKumulativFuerStufe(stufe: number): number {
  let summe = 0;
  for (let s = 1; s <= Math.min(PASS_STUFEN, Math.max(0, Math.floor(stufe))); s++) {
    summe += xpKostenFuerStufe(s);
  }
  return summe;
}

/** Erreichte Pass-Stufe (0–30) für einen XP-Stand. */
export function passStufeFuerXp(xp: number): number {
  let stufe = 0;
  while (stufe < PASS_STUFEN && xpKumulativFuerStufe(stufe + 1) <= Math.max(0, xp)) stufe += 1;
  return stufe;
}

// ---------- Saison-Cosmetics (exklusiv, unverkäuflich — Anti-FOMO: bleiben im Besitz) ----------

/**
 * Die 4–6 exklusiven Items einer Saison. Saison 1 „Dschungel-Auftakt" ist
 * konkret ausgestaltet; spätere Saisons generiert das Themen-Rad deterministisch
 * (Titel/Banner/Namens-Farbe — keine generierten Sounds/Konfetti, die Assets
 * bräuchten). Item-Ids tragen die Saison-Nummer („…-s3-…").
 */
export function saisonItems(saisonId: string): ShopItem[] {
  const n = saisonNummer(saisonId);
  const basis = { preis: 0, passExklusiv: saisonId } as const;
  if (n === 1) {
    return [
      {
        id: "titel-s1-dschungel-novize",
        name: "Titel „Dschungel-Novize“ (S1)",
        emoji: "🌱",
        typ: "titel",
        slot: "titel",
        beschreibung: "Bananen-Pass Saison 1, Stufe 5.",
        ...basis,
      },
      {
        id: "namestil-s1-lianengruen",
        name: "Name „Lianen-Grün“ (S1)",
        emoji: "🌿",
        typ: "namestil",
        slot: "namestil",
        beschreibung: "Bananen-Pass Saison 1, Stufe 10.",
        visuell: true,
        stil: "#8fe04b",
        ...basis,
      },
      {
        id: "banner-s1-dschungelmorgen",
        name: "Banner „Dschungel-Morgen“ (S1)",
        emoji: "🌄",
        typ: "banner",
        slot: "banner",
        beschreibung: "Bananen-Pass Saison 1, Stufe 15.",
        visuell: true,
        stil: "radial-gradient(circle at 50% 0%, rgba(255,201,60,0.55) 0 22%, transparent 48%), linear-gradient(180deg, #2e8b57 0%, #14532d 100%)",
        ...basis,
      },
      {
        id: "konfetti-s1-blaetterwirbel",
        name: "Konfetti „Blätter-Wirbel“ (S1)",
        emoji: "🍃",
        typ: "konfetti",
        slot: "konfetti",
        beschreibung: "Bananen-Pass Saison 1, Stufe 20.",
        ...basis,
      },
      {
        id: "banner-s1-lianendickicht",
        name: "Banner „Lianen-Dickicht“ (S1)",
        emoji: "🪢",
        typ: "banner",
        slot: "banner",
        beschreibung: "Bananen-Pass Saison 1, Stufe 25.",
        visuell: true,
        stil: "repeating-linear-gradient(75deg, #0c2b1d 0 12px, #14532d 12px 26px, #1f7a45 26px 30px)",
        ...basis,
      },
      {
        id: "titel-s1-dschungel-legende",
        name: "Titel „Dschungel-Legende“ (S1)",
        emoji: "🏅",
        typ: "titel",
        slot: "titel",
        beschreibung: "Bananen-Pass Saison 1 KOMPLETT — Stufe 30.",
        ...basis,
      },
    ];
  }
  const t = SAISON_THEMEN[(n - 1) % SAISON_THEMEN.length];
  return [
    {
      id: `titel-s${n}-novize`,
      name: `Titel „${t.wort}-Novize“ (S${n})`,
      emoji: "🌱",
      typ: "titel",
      slot: "titel",
      beschreibung: `Bananen-Pass Saison ${n}, Stufe 5.`,
      ...basis,
    },
    {
      id: `namestil-s${n}-farbe`,
      name: `Name „${t.wort}-Farbe“ (S${n})`,
      emoji: "🎨",
      typ: "namestil",
      slot: "namestil",
      beschreibung: `Bananen-Pass Saison ${n}, Stufe 10.`,
      visuell: true,
      stil: t.farbe,
      ...basis,
    },
    {
      id: `banner-s${n}-motiv`,
      name: `Banner „${t.name}“ (S${n})`,
      emoji: "🖼️",
      typ: "banner",
      slot: "banner",
      beschreibung: `Bananen-Pass Saison ${n}, Stufe 15.`,
      visuell: true,
      stil: t.banner1,
      ...basis,
    },
    {
      id: `banner-s${n}-muster`,
      name: `Banner „${t.wort}-Muster“ (S${n})`,
      emoji: "🧩",
      typ: "banner",
      slot: "banner",
      beschreibung: `Bananen-Pass Saison ${n}, Stufe 25.`,
      visuell: true,
      stil: t.banner2,
      ...basis,
    },
    {
      id: `titel-s${n}-legende`,
      name: `Titel „${t.wort}-Legende“ (S${n})`,
      emoji: "🏅",
      typ: "titel",
      slot: "titel",
      beschreibung: `Bananen-Pass Saison ${n} KOMPLETT — Stufe 30.`,
      ...basis,
    },
  ];
}

/** Item-Lookup über Katalog + Saison-Exklusive (Cache pro Saison-Nummer). */
const saisonItemCache = new Map<string, Map<string, ShopItem>>();
export function itemFuer(id: string): ShopItem | undefined {
  const bekannt = SHOP_ITEM_MAP.get(id);
  if (bekannt) return bekannt;
  const m = /-s(\d{1,3})-/.exec(id);
  if (!m) return undefined;
  const n = Number(m[1]);
  const [j0, m0] = SAISON_ERSTE.split("-").map(Number);
  const monat = m0 - 1 + (n - 1);
  const saisonId = saisonIdFuer(Date.UTC(j0 + Math.floor(monat / 12), monat % 12, 1));
  let map = saisonItemCache.get(saisonId);
  if (!map) {
    map = new Map(saisonItems(saisonId).map((i) => [i.id, i]));
    saisonItemCache.set(saisonId, map);
  }
  return map.get(id);
}

// ---------- Pass-Stufen-Belohnungen (Mix aus AT-Boni + Saison-Cosmetics) ----------

export interface PassBelohnung {
  stufe: number;
  art: "at" | "item";
  at?: number;
  itemId?: string;
}

/** AT-Boni der Nicht-Item-Stufen (zählen als EINNAHME ⇒ füttern auch das Level). */
const AT_BONI: Record<number, number> = {
  1: 100,
  2: 100,
  3: 150,
  4: 150,
  6: 150,
  7: 150,
  8: 200,
  9: 200,
  11: 200,
  12: 200,
  13: 250,
  14: 250,
  16: 250,
  17: 250,
  18: 300,
  19: 300,
  21: 300,
  22: 300,
  23: 350,
  24: 350,
  26: 400,
  27: 400,
  28: 450,
  29: 500,
};

/** Item-Stufen: 5 · 10 · 15 · (20 nur S1-Konfetti) · 25 · 30. */
export function passBelohnungen(saisonId: string): PassBelohnung[] {
  const items = saisonItems(saisonId);
  const itemStufen = items.length === 6 ? [5, 10, 15, 20, 25, 30] : [5, 10, 15, 25, 30];
  const belohnungen: PassBelohnung[] = [];
  for (let stufe = 1; stufe <= PASS_STUFEN; stufe++) {
    const idx = itemStufen.indexOf(stufe);
    if (idx >= 0) belohnungen.push({ stufe, art: "item", itemId: items[idx].id });
    else belohnungen.push({ stufe, art: "at", at: AT_BONI[stufe] ?? 300 });
  }
  return belohnungen;
}

// ---------- Match-Fakten (aus dem Event-Log EINES fertigen Matches) ----------

/** Minimales Log-Zeilen-Format (strukturell kompatibel zu analytics/LogZeile). */
export interface QuestLogZeile {
  ts: number;
  type: string;
  actor?: string;
  questionId?: string;
  payload: Record<string, unknown>;
}

export interface QuestFrageInfo {
  kategorie: string;
  oberkategorie?: string;
  schwierigkeit: string;
}

/** Alles, was Quests über EIN Match eines Profils wissen müssen. */
export interface MatchFakten {
  endstand: number;
  sieg: boolean;
  platz: number; // 1-basiert
  beantwortet: number;
  richtig: number;
  besteSerie: number;
  /** Abgaben unter 3 s nach Frage-Start. */
  unter3s: number;
  /** RICHTIGE Antworten unter 5 s. */
  richtigUnter5s: number;
  /** Fragen, bei denen dieses Profil die ERSTE Abgabe hatte. */
  schnellsteAbgaben: number;
  jokerGenutzt: number;
  ultrahardRichtig: number;
  /** RISIKO-Slot: richtige Antworten (gewonnene Wetten). */
  wettenGewonnen: number;
  /** Beim Taschendieb gestohlene MM. */
  gestohlen: number;
  /** Gespielte Minigame-Ids. */
  minigames: string[];
  /** Distinct Ober-Kategorien der beantworteten Fragen. */
  kategorien: string[];
  musikRunde: boolean;
  feedback: boolean;
}

export function leereFakten(): MatchFakten {
  return {
    endstand: 0,
    sieg: false,
    platz: 0,
    beantwortet: 0,
    richtig: 0,
    besteSerie: 0,
    unter3s: 0,
    richtigUnter5s: 0,
    schnellsteAbgaben: 0,
    jokerGenutzt: 0,
    ultrahardRichtig: 0,
    wettenGewonnen: 0,
    gestohlen: 0,
    minigames: [],
    kategorien: [],
    musikRunde: false,
    feedback: false,
  };
}

/**
 * Match-Fakten pro PROFIL aus den Log-Zeilen eines fertigen Matches ableiten —
 * pur, vollständig aus synthetischen Events testbar. Spieler ohne Profil-Bindung
 * (Gäste) tauchen nicht auf (Quests brauchen ein Profil).
 */
export function matchFakten(
  zeilen: QuestLogZeile[],
  frageInfo: (questionId: string) => QuestFrageInfo | null,
): Map<string, MatchFakten> {
  const bindung = new Map<string, string>(); // playerId → profileId
  const fakten = new Map<string, MatchFakten>();
  const serie = new Map<string, number>(); // profileId → aktuelle Richtig-Serie
  const kategorien = new Map<string, Set<string>>();
  const minigames = new Map<string, Set<string>>();
  let slot: string | undefined;
  let minigameId = "?";
  let frageStartTs = 0;
  let ersteAbgabe: string | null = null; // playerId der ersten Abgabe dieser Frage
  const abgabeZeit = new Map<string, number>(); // playerId → ms seit Frage-Start

  const f = (profileId: string): MatchFakten => {
    let vorhanden = fakten.get(profileId);
    if (!vorhanden) {
      vorhanden = leereFakten();
      fakten.set(profileId, vorhanden);
      kategorien.set(profileId, new Set());
      minigames.set(profileId, new Set());
    }
    return vorhanden;
  };
  const profilVon = (playerId: string | undefined): string | undefined =>
    playerId === undefined ? undefined : bindung.get(playerId);

  for (const z of zeilen) {
    switch (z.type) {
      case "profile_bound": {
        if (z.actor && typeof z.payload.profileId === "string") {
          bindung.set(z.actor, z.payload.profileId);
          f(z.payload.profileId);
        }
        break;
      }
      case "runde_gestartet": {
        slot = typeof z.payload.slot === "string" ? z.payload.slot : undefined;
        minigameId = String(z.payload.minigameId ?? "?");
        const kategorie = typeof z.payload.kategorie === "string" ? z.payload.kategorie : "";
        for (const [, profileId] of bindung) {
          minigames.get(profileId)?.add(minigameId);
          if (kategorie.includes("musik")) f(profileId).musikRunde = true;
        }
        break;
      }
      case "question_shown": {
        frageStartTs = z.ts;
        ersteAbgabe = null;
        abgabeZeit.clear();
        break;
      }
      case "answer_submitted": {
        if (!z.actor) break;
        if (ersteAbgabe === null) {
          ersteAbgabe = z.actor;
          const profileId = profilVon(z.actor);
          if (profileId !== undefined) f(profileId).schnellsteAbgaben += 1;
        }
        if (!abgabeZeit.has(z.actor)) {
          abgabeZeit.set(z.actor, Math.max(0, z.ts - frageStartTs));
        }
        break;
      }
      case "joker_used": {
        const profileId = profilVon(z.actor);
        if (profileId !== undefined) f(profileId).jokerGenutzt += 1;
        break;
      }
      case "answer_judged": {
        const profileId = profilVon(z.actor);
        if (profileId === undefined) break;
        const fk = f(profileId);
        const correct = z.payload.correct === true;
        fk.beantwortet += 1;
        const zeit = z.actor !== undefined ? abgabeZeit.get(z.actor) : undefined;
        if (zeit !== undefined && zeit < 3000) fk.unter3s += 1;
        const info = z.questionId ? frageInfo(z.questionId) : null;
        if (info) kategorien.get(profileId)?.add(info.oberkategorie ?? info.kategorie);
        if (info && (info.oberkategorie ?? info.kategorie).includes("musik")) {
          fk.musikRunde = true;
        }
        if (correct) {
          fk.richtig += 1;
          if (zeit !== undefined && zeit < 5000) fk.richtigUnter5s += 1;
          if (info?.schwierigkeit === "ultrahard") fk.ultrahardRichtig += 1;
          if (slot === "risiko") fk.wettenGewonnen += 1;
          const s = (serie.get(profileId) ?? 0) + 1;
          serie.set(profileId, s);
          fk.besteSerie = Math.max(fk.besteSerie, s);
        } else {
          serie.set(profileId, 0);
        }
        break;
      }
      case "money_changed": {
        const profileId = profilVon(z.actor);
        if (profileId === undefined) break;
        const delta = typeof z.payload.delta === "number" ? z.payload.delta : 0;
        if (minigameId === "taschendieb" && delta > 0) f(profileId).gestohlen += delta;
        break;
      }
      case "feedback_given": {
        const profileId = profilVon(z.actor);
        if (profileId !== undefined) f(profileId).feedback = true;
        break;
      }
      case "match_ended": {
        const standings = Array.isArray(z.payload.standings)
          ? (z.payload.standings as { playerId: string; balance: number }[])
          : [];
        for (const [i, s] of standings.entries()) {
          const profileId = bindung.get(s.playerId);
          if (profileId === undefined) continue;
          const fk = f(profileId);
          fk.endstand = s.balance;
          fk.platz = i + 1;
          fk.sieg = i === 0;
        }
        break;
      }
      default:
        break;
    }
  }

  for (const [profileId, fk] of fakten) {
    fk.kategorien = [...(kategorien.get(profileId) ?? [])];
    fk.minigames = [...(minigames.get(profileId) ?? [])];
  }
  return fakten;
}

// ---------- Quest-Definitionen ----------

export interface QuestDef {
  id: string;
  art: "daily" | "monat";
  text: string;
  ziel: number;
  xp: number;
  /** Fortschritts-ZUWACHS aus EINEM fertigen Match. */
  misst(f: MatchFakten): number;
}

const einmal = (wahr: boolean): number => (wahr ? 1 : 0);

/** Daily-Pool (~20): 3 pro Tag rotieren, ALLE aus dem Event-Log prüfbar. */
export const DAILY_QUESTS: QuestDef[] = [
  {
    id: "d-match-500",
    art: "daily",
    text: "Gewinne 500 MM in einem Match",
    ziel: 1,
    xp: XP_DAILY,
    misst: (f) => einmal(f.endstand >= 500),
  },
  {
    id: "d-joker",
    art: "daily",
    text: "Nutze einen Joker",
    ziel: 1,
    xp: XP_DAILY,
    misst: (f) => einmal(f.jokerGenutzt >= 1),
  },
  {
    id: "d-musik",
    art: "daily",
    text: "Spiele 1 Musik-Runde",
    ziel: 1,
    xp: XP_DAILY,
    misst: (f) => einmal(f.musikRunde),
  },
  {
    id: "d-blitz-5",
    art: "daily",
    text: "Antworte 5× in unter 3 s",
    ziel: 5,
    xp: XP_DAILY,
    misst: (f) => f.unter3s,
  },
  {
    id: "d-richtige-10",
    art: "daily",
    text: "Beantworte 10 Fragen richtig",
    ziel: 10,
    xp: XP_DAILY,
    misst: (f) => f.richtig,
  },
  {
    id: "d-sieg",
    art: "daily",
    text: "Gewinne ein Match",
    ziel: 1,
    xp: XP_DAILY,
    misst: (f) => einmal(f.sieg),
  },
  {
    id: "d-matches-2",
    art: "daily",
    text: "Spiele 2 Matches zu Ende",
    ziel: 2,
    xp: XP_DAILY,
    misst: () => 1,
  },
  {
    id: "d-serie-3",
    art: "daily",
    text: "Schaffe 3 Richtige in Folge",
    ziel: 1,
    xp: XP_DAILY,
    misst: (f) => einmal(f.besteSerie >= 3),
  },
  {
    id: "d-podium",
    art: "daily",
    text: "Lande auf dem Podium (Top 3)",
    ziel: 1,
    xp: XP_DAILY,
    misst: (f) => einmal(f.platz >= 1 && f.platz <= 3),
  },
  {
    id: "d-ultrahard",
    art: "daily",
    text: "Beantworte eine ULTRAHARD-Frage richtig",
    ziel: 1,
    xp: XP_DAILY,
    misst: (f) => einmal(f.ultrahardRichtig >= 1),
  },
  {
    id: "d-wette",
    art: "daily",
    text: "Gewinne eine Wette (RISIKO-Runde)",
    ziel: 1,
    xp: XP_DAILY,
    misst: (f) => einmal(f.wettenGewonnen >= 1),
  },
  {
    id: "d-dieb",
    art: "daily",
    text: "Stiehl Geld beim Taschendieb",
    ziel: 1,
    xp: XP_DAILY,
    misst: (f) => einmal(f.gestohlen > 0),
  },
  {
    id: "d-schaetzen",
    art: "daily",
    text: "Spiele eine Schätz-Runde (Bananen-Tresor)",
    ziel: 1,
    xp: XP_DAILY,
    misst: (f) => einmal(f.minigames.includes("bananen-tresor")),
  },
  {
    id: "d-pixel",
    art: "daily",
    text: "Spiele eine Bild-Runde (Pixel-Dschungel)",
    ziel: 1,
    xp: XP_DAILY,
    misst: (f) => einmal(f.minigames.includes("pixel-dschungel")),
  },
  {
    id: "d-fragen-15",
    art: "daily",
    text: "Beantworte 15 Fragen",
    ziel: 15,
    xp: XP_DAILY,
    misst: (f) => f.beantwortet,
  },
  {
    id: "d-endstand-1500",
    art: "daily",
    text: "Erreiche 1.500 MM Endstand",
    ziel: 1,
    xp: XP_DAILY,
    misst: (f) => einmal(f.endstand >= 1500),
  },
  {
    id: "d-schnell-richtig-3",
    art: "daily",
    text: "Antworte 3× richtig in unter 5 s",
    ziel: 3,
    xp: XP_DAILY,
    misst: (f) => f.richtigUnter5s,
  },
  {
    id: "d-erste-abgabe-3",
    art: "daily",
    text: "Gib 3× die schnellste Antwort ab",
    ziel: 3,
    xp: XP_DAILY,
    misst: (f) => f.schnellsteAbgaben,
  },
  {
    id: "d-kategorien-3",
    art: "daily",
    text: "Spiele ein Match mit 3+ Kategorien",
    ziel: 1,
    xp: XP_DAILY,
    misst: (f) => einmal(f.kategorien.length >= 3),
  },
  {
    id: "d-feedback",
    art: "daily",
    text: "Schicke ein Match-Feedback",
    ziel: 1,
    xp: XP_DAILY,
    misst: (f) => einmal(f.feedback),
  },
];

/** Monats-Pool: 3 pro Saison — größere Brocken (je 400 XP). */
export const MONATS_QUESTS: QuestDef[] = [
  {
    id: "m-siege-5",
    art: "monat",
    text: "Gewinne 5 Matches",
    ziel: 5,
    xp: XP_MONAT,
    misst: (f) => einmal(f.sieg),
  },
  {
    id: "m-fragen-100",
    art: "monat",
    text: "Spiele 100 Fragen",
    ziel: 100,
    xp: XP_MONAT,
    misst: (f) => f.beantwortet,
  },
  {
    id: "m-pass-15",
    art: "monat",
    text: "Erreiche Pass-Stufe 15",
    ziel: 15,
    xp: XP_MONAT,
    // Fortschritt = Pass-Stufe — misst der Quest-Store direkt am Pass-Stand.
    misst: () => 0,
  },
  {
    id: "m-richtige-60",
    art: "monat",
    text: "Beantworte 60 Fragen richtig",
    ziel: 60,
    xp: XP_MONAT,
    misst: (f) => f.richtig,
  },
  {
    id: "m-matches-12",
    art: "monat",
    text: "Spiele 12 Matches zu Ende",
    ziel: 12,
    xp: XP_MONAT,
    misst: () => 1,
  },
  {
    id: "m-joker-10",
    art: "monat",
    text: "Nutze 10 Joker",
    ziel: 10,
    xp: XP_MONAT,
    misst: (f) => f.jokerGenutzt,
  },
];

export const QUEST_MAP: ReadonlyMap<string, QuestDef> = new Map(
  [...DAILY_QUESTS, ...MONATS_QUESTS].map((q) => [q.id, q]),
);

/** Mini-Hash (FNV-1a) für deterministische Rotation aus Datums-Schlüsseln. */
function hash(text: string): number {
  let h = 2166136261;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

/** Die 3 Dailies eines Tages: deterministische Ziehung aus dem 20er-Pool. */
export function dailyQuestIdsFuer(tagKey: string): string[] {
  const rng = createRng(hash(`daily:${tagKey}`));
  const pool = DAILY_QUESTS.map((q) => q.id);
  for (let i = pool.length - 1; i > 0; i--) {
    const j = rng.int(i + 1);
    [pool[i], pool[j]] = [pool[j], pool[i]];
  }
  return pool.slice(0, 3);
}

/** Die 3 Monats-Quests einer Saison: m-pass-15 ist IMMER dabei, 2 rotieren. */
export function monatsQuestIdsFuer(saisonId: string): string[] {
  const n = saisonNummer(saisonId);
  if (n === 1) return ["m-siege-5", "m-fragen-100", "m-pass-15"];
  const andere = MONATS_QUESTS.map((q) => q.id).filter((id) => id !== "m-pass-15");
  const rng = createRng(hash(`monat:${saisonId}`));
  for (let i = andere.length - 1; i > 0; i--) {
    const j = rng.int(i + 1);
    [andere[i], andere[j]] = [andere[j], andere[i]];
  }
  return [...andere.slice(0, 2), "m-pass-15"];
}

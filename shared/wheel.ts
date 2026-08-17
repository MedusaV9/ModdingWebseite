// Glücksrad v1 (GAME-DESIGN §5.3): 14 Segmente mit Gewichten (Summe 100 %),
// Fair-Finale-Pool, Pech-Schutz, Pity-Timer, deterministische Ziehung (Seed = Testfall).
import type { Rng } from "./rng";

export type RadSegmentId =
  | "doppelter-zaster"
  | "halbe-miete"
  | "banana-bailout"
  | "dividende"
  | "insider-tipp"
  | "inflation"
  | "affentheater"
  | "boersen-roulette"
  | "umarmungs-bonus"
  | "steuerpruefung"
  | "blackout"
  | "tausch-boerse"
  | "affe-wuerfelt"
  | "kompliment-konto";

export type RadKlasse = "gruen" | "blau" | "gold";

/** Laufzeit-Scope eines Segments: sofort / nächste Frage / Rest der Runde. */
export type RadScope = "sofort" | "naechste-frage" | "runde";

export interface RadSegment {
  id: RadSegmentId;
  name: string;
  klasse: RadKlasse;
  gewicht: number; // Prozent (Summe aller = 100)
  wirkung: string; // EIN Satz für die Erklärkarte
  scope: RadScope;
  /** Segment braucht eine Spieler-Interaktion in der Rad-Phase. */
  interaktion?: { typ: "long-short" | "umarmt" | "kompliment"; dauerMs: number };
  /** Im Fair-Finale-Pool erlaubt (letzte 2 Runden + vor Finale: 1,2,3,5,9,11). */
  fairFinale: boolean;
  /** Nur sinnvoll, wenn die nächste Runde ein MC-Frage-Format ist. */
  brauchtMcFrage?: boolean;
}

export const RAD_SEGMENTE: RadSegment[] = [
  {
    id: "doppelter-zaster",
    name: "Doppelter Zaster",
    klasse: "gruen",
    gewicht: 13,
    scope: "naechste-frage",
    fairFinale: true,
    wirkung: "Nächste Frage: Gewinne ×2, Verluste normal.",
  },
  {
    id: "halbe-miete",
    name: "Halbe Miete",
    klasse: "gruen",
    gewicht: 13,
    scope: "naechste-frage",
    fairFinale: true,
    brauchtMcFrage: true,
    wirkung: "Nächste Frage: Antwortzeit halbiert!",
  },
  {
    id: "banana-bailout",
    name: "Banana Bailout",
    klasse: "gruen",
    gewicht: 13,
    scope: "sofort",
    fairFinale: true,
    wirkung: "Der Letzte bekommt +1 Joker (50:50) + 15 % des Abstands zum Vorletzten.",
  },
  {
    id: "dividende",
    name: "Dividende",
    klasse: "blau",
    gewicht: 7,
    scope: "runde",
    fairFinale: false,
    wirkung: "Rest der Runde: +5 % Zins auf den Kontostand pro richtiger Antwort.",
  },
  {
    id: "insider-tipp",
    name: "Insider-Tipp",
    klasse: "blau",
    gewicht: 7,
    scope: "naechste-frage",
    fairFinale: true,
    brauchtMcFrage: true,
    wirkung: "Jemand hat einen Insider-Tipp … (sieht die nächste Frage 3 s früher)",
  },
  {
    id: "inflation",
    name: "Inflation!",
    klasse: "blau",
    gewicht: 7,
    scope: "runde",
    fairFinale: false,
    wirkung: "Rest der Runde: −3 % Kontostand pro Frage-Ende (mind. 50 MM).",
  },
  {
    id: "affentheater",
    name: "Affentheater",
    klasse: "blau",
    gewicht: 7,
    scope: "naechste-frage",
    fairFinale: false,
    brauchtMcFrage: true,
    wirkung:
      "Nächste Frage: Bildschirm-Reihenfolge ≠ Handy-Reihenfolge — es zählt der TEXT auf deinem Handy!",
  },
  {
    id: "boersen-roulette",
    name: "Börsen-Roulette",
    klasse: "blau",
    gewicht: 7,
    scope: "naechste-frage",
    fairFinale: false,
    brauchtMcFrage: true,
    interaktion: { typ: "long-short", dauerMs: 5000 },
    wirkung:
      "Jeder wählt blind Long/Short: richtig+Long +150 %, richtig+Short +50 %; falsch+Long −100 MM, falsch+Short ±0.",
  },
  {
    id: "umarmungs-bonus",
    name: "Umarmungs-Bonus",
    klasse: "blau",
    gewicht: 7,
    scope: "sofort",
    fairFinale: true,
    interaktion: { typ: "umarmt", dauerMs: 15000 },
    wirkung: "15 s: real umarmen + „Umarmt!“ drücken → je +50 MM.",
  },
  {
    id: "steuerpruefung",
    name: "Steuerprüfung",
    klasse: "blau",
    gewicht: 7,
    scope: "naechste-frage",
    fairFinale: false,
    brauchtMcFrage: true,
    wirkung:
      "Der Führende muss die nächste Frage richtig haben — sonst zahlt er 10 % in den Pott des Fragen-Gewinners.",
  },
  {
    id: "blackout",
    name: "Blackout im Studio",
    klasse: "gold",
    gewicht: 3,
    scope: "naechste-frage",
    fairFinale: true,
    brauchtMcFrage: true,
    wirkung: "Nächste Frage NUR auf den Handys — der Bildschirm zeigt Sendeausfall.",
  },
  {
    id: "tausch-boerse",
    name: "Affen-Tausch-Börse",
    klasse: "gold",
    gewicht: 3,
    scope: "sofort",
    fairFinale: false,
    wirkung: "SOFORT: alle tauschen den Kontostand mit dem Sitznachbarn!",
  },
  {
    id: "affe-wuerfelt",
    name: "Der Affe würfelt",
    klasse: "gold",
    gewicht: 3,
    scope: "naechste-frage",
    fairFinale: false,
    brauchtMcFrage: true,
    wirkung:
      "Ein Bot-Affe rät die nächste Frage mit — wen er schlägt, der zahlt 50 MM Schmach-Gebühr in den Pott.",
  },
  {
    id: "kompliment-konto",
    name: "Kompliment-Konto",
    klasse: "gold",
    gewicht: 3,
    scope: "sofort",
    fairFinale: false,
    interaktion: { typ: "kompliment", dauerMs: 20000 },
    wirkung:
      "Das Rad bestimmt A und B: ernstes Kompliment binnen 20 s (Gruppen-Vote) → beide +50 MM.",
  },
];

export const RAD_SEGMENT_MAP: Record<RadSegmentId, RadSegment> = Object.fromEntries(
  RAD_SEGMENTE.map((s) => [s.id, s]),
) as Record<RadSegmentId, RadSegment>;

/** Rad-Regeln (§5.3). */
export const RAD_RENDER_SLOTS = 10; // pro Dreh werden ~10 Segmente gerendert
export const RAD_PITY_AB_DREHS = 4; // nach 4 Drehs ohne Gold …
export const RAD_PITY_GOLD_BONUS = 0.02; // … +2 % Gold-Chance pro Dreh
export const RAD_DREH_MS = 5000; // Dreh-Animation (Slow-down-Kurve im Client)
export const RAD_DREH_KURZ_MS = 3000; // „Kurze Show"-Setting
export const RAD_ERGEBNIS_MS = 5000; // Erklärkarte des Ergebnisses

export interface RadKontext {
  /** Letzte 2 Runden + vor dem Finale: nur Fair-Finale-Pool. */
  fairFinale: boolean;
  /** Pech-Schutz: dasselbe Segment nie 2× hintereinander. */
  letztesSegment: RadSegmentId | null;
  /** Pity-Timer: Drehs seit dem letzten Gold-Segment. */
  drehsOhneGold: number;
  /** Inflation dreht automatisch neu, wenn jemand unter 200 MM liegt. */
  jemandUnter200: boolean;
  /** Nächste Runde ist ein MC-Frage-Format (Kompatibilitäts-Matrix). */
  naechsteRundeMc: boolean;
  spielerzahl: number;
}

/** Kompatibilitäts-Matrix: welche Segmente dürfen JETZT aufs Rad? */
export function kompatibleSegmente(ctx: RadKontext): RadSegment[] {
  return RAD_SEGMENTE.filter((s) => {
    if (ctx.fairFinale && !s.fairFinale) return false;
    if (s.id === ctx.letztesSegment) return false; // Pech-Schutz
    if (s.brauchtMcFrage && !ctx.naechsteRundeMc) return false;
    if (s.id === "inflation" && ctx.jemandUnter200) return false;
    if (s.id === "tausch-boerse" && ctx.spielerzahl < 2) return false;
    if ((s.id === "umarmungs-bonus" || s.id === "kompliment-konto") && ctx.spielerzahl < 2) {
      return false;
    }
    return true;
  });
}

/** Effektive Gewichte inkl. Pity-Timer (Gold-Bonus wird von grün/blau abgezweigt). */
export function effektiveGewichte(segmente: RadSegment[], ctx: RadKontext): number[] {
  const gewichte = segmente.map((s) => s.gewicht);
  const bonus =
    ctx.drehsOhneGold >= RAD_PITY_AB_DREHS
      ? (ctx.drehsOhneGold - RAD_PITY_AB_DREHS + 1) * RAD_PITY_GOLD_BONUS * 100
      : 0;
  if (bonus <= 0) return gewichte;
  const goldIdx = segmente.map((s, i) => (s.klasse === "gold" ? i : -1)).filter((i) => i >= 0);
  if (goldIdx.length === 0) return gewichte;
  for (const i of goldIdx) gewichte[i] += bonus / goldIdx.length;
  return gewichte;
}

/** Gewichtete Ziehung — deterministisch über injizierten Rng. */
export function zieheSegment(rng: Rng, ctx: RadKontext): RadSegmentId {
  const pool = kompatibleSegmente(ctx);
  if (pool.length === 0) return "doppelter-zaster"; // theoretisch unerreichbar
  const gewichte = effektiveGewichte(pool, ctx);
  const summe = gewichte.reduce((a, b) => a + b, 0);
  let wurf = rng.next() * summe;
  for (let i = 0; i < pool.length; i++) {
    wurf -= gewichte[i];
    if (wurf < 0) return pool[i].id;
  }
  return pool[pool.length - 1].id;
}

/**
 * Anzeige-Ring bauen: bis zu RAD_RENDER_SLOTS Segmente aus dem kompatiblen Pool,
 * Ergebnis garantiert enthalten; Rest gewichtet ohne Zurücklegen gezogen.
 * „gilt hier nicht"-Ergebnisse existieren nicht (§5.3).
 */
export function baueRadAnzeige(
  rng: Rng,
  ctx: RadKontext,
  ergebnis: RadSegmentId,
): { segmente: RadSegmentId[]; ergebnisIndex: number } {
  const pool = kompatibleSegmente(ctx).filter((s) => s.id !== ergebnis);
  const anzeige: RadSegmentId[] = [ergebnis];
  const restSlots = Math.min(RAD_RENDER_SLOTS - 1, pool.length);
  const kandidaten = [...pool];
  for (let n = 0; n < restSlots; n++) {
    const gewichte = kandidaten.map((s) => s.gewicht);
    const summe = gewichte.reduce((a, b) => a + b, 0);
    let wurf = rng.next() * summe;
    let idx = kandidaten.length - 1;
    for (let i = 0; i < kandidaten.length; i++) {
      wurf -= gewichte[i];
      if (wurf < 0) {
        idx = i;
        break;
      }
    }
    anzeige.push(kandidaten[idx].id);
    kandidaten.splice(idx, 1);
  }
  // Ring mischen (Fisher-Yates mit injiziertem Rng) — Ergebnis-Index nachschlagen.
  for (let i = anzeige.length - 1; i > 0; i--) {
    const j = rng.int(i + 1);
    [anzeige[i], anzeige[j]] = [anzeige[j], anzeige[i]];
  }
  return { segmente: anzeige, ergebnisIndex: anzeige.indexOf(ergebnis) };
}

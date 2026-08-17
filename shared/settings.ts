// Match-Settings + Modi-Matrix (GAME-DESIGN §1.3/§6) — die Blaupausen, aus denen
// die Engine den Match-Plan baut. Pure Daten + pure Helfer, beidseitig importierbar.
import type { Schwierigkeit } from "./money";
import type { TeamModusSetting } from "./teams";

export type Modus = "quick" | "klassik" | "marathon";

/** Slot-Dramaturgie (GAME-DESIGN §1.2): jede Runde besetzt einen Slot. */
export type SlotTag = "opener" | "aufbau" | "geld" | "konflikt" | "risiko" | "finale";

export interface MatchSettings {
  modus: Modus;
  /** Finale-Formel-Faktor: 1,0 streng / 1,25 Default / 1,5 Chaos (§3.5). */
  finaleFaktor: 1.0 | 1.25 | 1.5;
  jokerAn: boolean;
  rad: "an" | "aus";
  /** Kategorien-Wahl vor Runden ab R2: Spieler-Voting oder GM-Pick oder aus. */
  kategorienWahl: "voting" | "gm" | "aus";
  /** Auto-GM: Software-Regie (Timer-Heuristik, Auto-Picks) an/aus. */
  autoGm: boolean;
  /** Auto-GM-Tipp: bei zäher Frage (niemand antwortet nach 60 % der Zeit)
   * schickt die Software-Regie automatisch Tipp 1 (nur wenn autoGm an). */
  autoTipp: boolean;
  /** „Kurze Show": Rad-Dreh 6 s statt 12 s, knappere Karten. */
  kurzeShow: boolean;
  /** All-Time-Items (Shop-Kosmetik) im Match zeigen — Auto-AUS bei Gast (§7.4). */
  alltimeItems: boolean;
  /** Tutorial-Videos auf Erklärkarten anbieten (Default AUS — Tempo!). */
  tutorialVideos: boolean;
  /** v2-Formate (§2.12) in den Playlisten spielen (Default AN) — aus ⇒ die
   * als v2 markierten Runden werden beim Plan-Bau übersprungen. */
  v2Formate: boolean;
  /** Team-Modus „Affenbanden" (§1.4, ADDITIV): aus | 2er (Zweierteams,
   * Doppel-Affe bei ungerade) | 2v2v2v2 (4 Lager) | frei (Spieler wählen).
   * Greift erst ab 4 Spielern — darunter startet das Match individuell. */
  teams: TeamModusSetting;
  /** Hintergrund-Musik der Show (Betten-Rotation) an/aus (ADDITIV, Musik-
   * Welle 3). aus ⇒ der Screen spielt KEIN Bett — SFX/Snippets laufen weiter
   * (die MUSIK_STUMME_FORMATE-Logik der Musik-Formate ist davon unabhängig). */
  musik: "an" | "aus";
  /** Show-weite Musik-Lautstärke 0–1 (GM-Regler) — multipliziert sich mit dem
   * lokalen Screen-Regler (ADDITIV, Musik-Welle 3). */
  musikVolume: number;
}

/** Blaupause einer Runde im Match-Plan (vor der Minigame-Auflösung). */
export interface RundenBlaupause {
  slot: SlotTag;
  /** Wunsch-Minigame laut Playlist — Fallback auf verfügbares Frage-Format. */
  minigameId: string;
  fragen: number;
  /** Schwierigkeits-Pool des Slots (§1.2 Schwierigkeits-Progression). */
  schwierigkeiten: Schwierigkeit[];
  /** Kategorien-Wahl-Phase vor dieser Runde ("letzter" = Comeback-Regel §3.4). */
  kategorieWahl: "keine" | "voting" | "letzter";
  /** Garantierter Rad-Dreh NACH dieser Runde (Modi-Matrix §1.3). */
  radDanach: boolean;
  /** v2-Format (§2.12): läuft nur mit Settings-Flag `v2Formate` (Default an). */
  v2?: boolean;
}

export interface ModusBlaupause {
  runden: RundenBlaupause[];
  jackpotFrage: boolean; // 1× vor der RISIKO-Runde (nicht in Quick)
  finaleFragen: number; // Q der Finale-Formel
  ultrahardMax: number; // max. ULTRAHARD-Fragen pro Match
}

const OPENER: Schwierigkeit[] = ["easy", "medium"];
const AUFBAU: Schwierigkeit[] = ["medium", "hard"];
const GELD: Schwierigkeit[] = ["medium"];
const KONFLIKT: Schwierigkeit[] = ["hard"];
const RISIKO: Schwierigkeit[] = ["hard", "ultrahard"];
// Risiko-Leiter (Welle 4): voller Schwierigkeits-Fächer — das Plugin sortiert
// den Vorrat easy → ultrahard, damit die Leiter unten leicht beginnt.
const LEITER: Schwierigkeit[] = ["easy", "medium", "hard", "ultrahard"];

/** Modi-Matrix (GAME-DESIGN §1.3, verbindlich): Playlisten + Q + Rad-Beats. */
export const MODUS_BLAUPAUSEN: Record<Modus, ModusBlaupause> = {
  quick: {
    runden: [
      r("opener", "bananen-basics", 3, OPENER, "keine", false),
      r("aufbau", "kokosnuss-uhr", 3, AUFBAU, "voting", false),
      r("geld", "affenbank", 3, GELD, "voting", true), // 1 Dreh (nach R3)
      r("risiko", "alles-oder-banane", 3, RISIKO, "voting", false),
    ],
    jackpotFrage: false,
    finaleFragen: 3,
    ultrahardMax: 1,
  },
  klassik: {
    runden: [
      r("opener", "bananen-basics", 4, OPENER, "keine", false),
      r("aufbau", "bananen-tresor", 4, AUFBAU, "voting", true), // Dreh nach R2
      r("aufbau", "pixel-dschungel", 4, AUFBAU, "voting", false),
      r("geld", "affenbank", 4, GELD, "voting", true), // Dreh nach R4
      r("konflikt", "stinkbanane", 4, KONFLIKT, "letzter", true), // Dreh nach R5
      r("risiko", "alles-oder-banane", 4, RISIKO, "voting", false),
    ],
    jackpotFrage: true,
    finaleFragen: 5,
    ultrahardMax: 2,
  },
  marathon: {
    runden: [
      r("opener", "bananen-basics", 4, OPENER, "keine", false),
      r("aufbau", "kokosnuss-uhr", 4, AUFBAU, "voting", true), // Dreh nach R2
      r("aufbau", "bananen-tresor", 4, AUFBAU, "voting", false),
      r("aufbau", "affenleiter", 4, AUFBAU, "voting", true), // Dreh nach R4
      r("geld", "affenbank", 4, GELD, "voting", false),
      // v2-Welle (§2.12, Flag v2Formate): Handel + Börse verstärken den
      // GELD-Block, Bluff + Auktion den KONFLIKT-Block vor dem Risiko.
      v2(r("geld", "monkey-market", 4, GELD, "voting", false)),
      r("aufbau", "pixel-dschungel", 4, AUFBAU, "voting", true), // Dreh nach R6
      // Musik-Welle (Agent A): Rückwärts-Banane als AUFBAU-Beat — faires
      // Alle-antworten-Format über Song-Packs (contentKind "songs"; ohne
      // geladene Songs meldet die Registry das Format nicht-verfügbar und
      // plan.aufloesen fällt aufs Frage-Format zurück). Songs statt Fragen ⇒
      // KEINE Kategorien-Wahl.
      v2(r("aufbau", "song-rueckwaerts", 3, AUFBAU, "keine", false)),
      // Musik-Welle (Agent B): Stummfilm-Studio als AUFBAU-Beat — erscheint
      // erst, wenn das Song-Pack ≥ 3 Videos (medien.video3s) hat
      // (meta.minVideoSongs, registry.allePluginsFuer); mit dem 1-Video-
      // Starter-Pack läuft der Slot als Frage-Format (plan.aufloesen).
      v2(r("aufbau", "musikvideo-raten", 3, AUFBAU, "keine", false)),
      v2(r("geld", "bananen-boerse", 4, GELD, "voting", false)),
      // Musik-Welle (Agent B): das Paar-Telegramm ist Koop-Geld (+250 je
      // Partner) — Begriffe kommen aus Song-Pack + eingebautem Pool, darum
      // KEINE Kategorien-Wahl (contentKind "none").
      v2(r("geld", "buchstaben-telegramm", 4, GELD, "keine", false)),
      // Duell-Welle 4: „Wer singt's?" als AUFBAU-Beat der Musik-Strecke —
      // 5 Beats (Fragen zählen nur die Beat-Zahl, Fakten kommen aus dem
      // eingebauten 60+-Pool + Song-Pack ⇒ KEINE Kategorien-Wahl).
      v2(r("aufbau", "wer-singts", 5, AUFBAU, "keine", false)),
      r("konflikt", "stinkbanane", 4, KONFLIKT, "letzter", false),
      r("konflikt", "taschendieb", 4, KONFLIKT, "voting", true), // Dreh nach R8
      // Buzz-Welle 3 (Agent Buzz): die Tortenschlacht ist der Rauswurf-Beat des
      // KONFLIKT-Blocks — 8 Fragen Vorrat (roundBased zieht die ganze Serie;
      // erschöpft ⇒ Punktsieg der Saubersten, s. Plugin-Kopf).
      v2(r("konflikt", "bananen-tortenschlacht", 8, KONFLIKT, "voting", false)),
      v2(r("konflikt", "bananen-bluff", 4, KONFLIKT, "voting", false)),
      // Musik-Welle (Agent A): der Blitz-DJ als KONFLIKT-Beat — Eskalations-
      // Buzzer mit Verfalls-Treppe und Falsch-Buzz-Strafen ins Glas. 3 Songs
      // pro Runde (jeder Song ist ein eigener Buzzer-Showdown).
      v2(r("konflikt", "song-snippet", 3, KONFLIKT, "keine", false)),
      // v2-Welle 2: 1v1-Duell mit Zuschauer-Wetten (7 Fragen = Best-of-5 +
      // 2 Sudden-Death-Reserven, roundBased zieht die ganze Serie).
      v2(r("konflikt", "lianensteg-duell", 7, KONFLIKT, "voting", false)),
      // Buzz-Welle 3 (Agent Buzz): der Boxkampf ist das zweite 1v1 des Blocks —
      // 8 Fragen = BX_RUNDEN (K.O. beendet früher, sonst Punktsieg nach HP).
      v2(r("konflikt", "bananen-boxkampf", 8, KONFLIKT, "voting", false)),
      // Duell-Welle 4: das Konter-Quiz ist das FREUNDLICHE 1v1 des Blocks —
      // 8 kurze leichte/mittlere Fragen (KQ_RUNDEN), richtig zahlt die Bank,
      // falsch schenkt dem Partner die Konter-Gutschrift (nullsummig).
      v2(r("konflikt", "konter-quiz", 8, OPENER, "voting", false)),
      // Klassiker-Welle 4: „Einer gegen alle" — der Führende tritt allein
      // gegen die Mengen-Mehrheit an (6 Fragen; meta.minPlayers 3 wie beim
      // Bananen-Bluff dokumentarisch — mit nur 2 Spielern degradiert das
      // Format sauber zum Duell Solist vs. Ein-Mann-Menge; Slot bewusst
      // NACH den 1v1-Duellen als Zuspitzung des KONFLIKT-Blocks).
      v2(r("konflikt", "einer-gegen-alle", 6, AUFBAU, "voting", false)),
      v2(r("konflikt", "affen-auktion", 4, KONFLIKT, "voting", true)),
      // Klassiker-Welle 4: die Risiko-Leiter eröffnet den RISIKO-Block —
      // 8 Stufen-Fragen, breiter Pool (das Plugin sortiert easy → ultrahard
      // zur Leiter-Progression; ultrahardMax deckelt die Gipfel-Härte).
      v2(r("risiko", "risiko-leiter", 8, LEITER, "voting", false)),
      r("risiko", "alles-oder-banane", 4, RISIKO, "voting", false),
      // v2-Finale-Alternative (§2.12): der Goldene Affe als letzte Runde VOR
      // dem Finale — Slot bewusst KONFLIKT (risiko würde einen 2. Jackpot-Beat
      // einfügen). 4 Fragen = Money-Drop + Buzzer-Best-of-3.
      v2(r("konflikt", "goldener-affe", 4, RISIKO, "keine", false)),
    ],
    jackpotFrage: true,
    finaleFragen: 7,
    ultrahardMax: 2,
  },
};

/** Runde als v2-Format markieren (läuft nur mit Settings-Flag `v2Formate`). */
function v2(runde: RundenBlaupause): RundenBlaupause {
  return { ...runde, v2: true };
}

/** Playlist einer Blaupause unter den Settings: v2-Runden nur mit Flag. */
export function rundenFuerSettings(
  blaupause: ModusBlaupause,
  settings: MatchSettings,
): RundenBlaupause[] {
  // !== false: Settings aus Alt-Saves ohne das Feld spielen v2 (Default AN).
  return blaupause.runden.filter((r) => r.v2 !== true || settings.v2Formate !== false);
}

function r(
  slot: SlotTag,
  minigameId: string,
  fragen: number,
  schwierigkeiten: Schwierigkeit[],
  kategorieWahl: "keine" | "voting" | "letzter",
  radDanach: boolean,
): RundenBlaupause {
  return { slot, minigameId, fragen, schwierigkeiten, kategorieWahl, radDanach };
}

export function defaultSettings(modus: Modus = "klassik"): MatchSettings {
  return {
    modus,
    finaleFaktor: 1.25,
    // Quick Cash: Ein-Tap-Start, Joker AUS (GAME-DESIGN §6.2).
    jokerAn: modus !== "quick",
    rad: "an",
    kategorienWahl: "voting",
    autoGm: true,
    autoTipp: true,
    kurzeShow: modus === "quick",
    alltimeItems: true,
    tutorialVideos: false,
    v2Formate: true,
    teams: "aus",
    musik: "an",
    musikVolume: 1,
  };
}

/** Settings-Patch (GM-Kommando settings.set) — nur bekannte Schlüssel übernehmen. */
export function patchSettings(basis: MatchSettings, patch: Record<string, unknown>): MatchSettings {
  if (patch.modus === "quick" || patch.modus === "klassik" || patch.modus === "marathon") {
    // Modus-Wechsel: Modus-Defaults als neue Basis, explizite Patch-Keys obendrauf.
    return patchOhneModus(defaultSettings(patch.modus), patch);
  }
  return patchOhneModus(basis, patch);
}

function patchOhneModus(basis: MatchSettings, patch: Record<string, unknown>): MatchSettings {
  const neu = { ...basis };
  if (patch.finaleFaktor === 1.0 || patch.finaleFaktor === 1.25 || patch.finaleFaktor === 1.5) {
    neu.finaleFaktor = patch.finaleFaktor;
  }
  if (typeof patch.jokerAn === "boolean") neu.jokerAn = patch.jokerAn;
  if (patch.rad === "an" || patch.rad === "aus") neu.rad = patch.rad;
  if (
    patch.kategorienWahl === "voting" ||
    patch.kategorienWahl === "gm" ||
    patch.kategorienWahl === "aus"
  ) {
    neu.kategorienWahl = patch.kategorienWahl;
  }
  if (typeof patch.autoGm === "boolean") neu.autoGm = patch.autoGm;
  if (typeof patch.autoTipp === "boolean") neu.autoTipp = patch.autoTipp;
  if (typeof patch.kurzeShow === "boolean") neu.kurzeShow = patch.kurzeShow;
  if (typeof patch.alltimeItems === "boolean") neu.alltimeItems = patch.alltimeItems;
  if (typeof patch.tutorialVideos === "boolean") neu.tutorialVideos = patch.tutorialVideos;
  if (typeof patch.v2Formate === "boolean") neu.v2Formate = patch.v2Formate;
  if (
    patch.teams === "aus" ||
    patch.teams === "2er" ||
    patch.teams === "2v2v2v2" ||
    patch.teams === "frei"
  ) {
    neu.teams = patch.teams;
  }
  if (patch.musik === "an" || patch.musik === "aus") neu.musik = patch.musik;
  if (typeof patch.musikVolume === "number" && Number.isFinite(patch.musikVolume)) {
    neu.musikVolume = Math.min(1, Math.max(0, patch.musikVolume));
  }
  return neu;
}

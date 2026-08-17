// „Das 7-Buchstaben-Telegramm" (buchstaben-telegramm, Musik-Welle) — das
// Joko&Klaas-Paar-Spiel: der BESCHREIBER bekommt einen Begriff auf SEIN Handy
// (Song-Titel aus dem Song-Pack ODER berühmter Begriff aus dem eingebauten
// Pool) und darf NUR BUCHSTABEN (A–Z, 0–9) als Hinweis tippen — z. B.
// „NENALUFT" für „99 Luftballons". Der RATENDE sieht die Buchstaben groß +
// 4 Optionen. Beide kriegen Money bei Erfolg (~250 je, Design §3.1-Geist).
//
// BUDGET-TAKTIK (der Kern): pro Hinweis max. 8 Zeichen (Standard-N; der
// Show-Titel „7-Buchstaben-Telegramm" ist die nostalgische Marke), aber das
// MATCH-Budget ist 60 Zeichen ÜBER ALLE RUNDEN — jedes getippte Zeichen ist
// sofort verbraucht (Telegramm-Wörter kosten!), der Rest VERFÄLLT am
// Match-Ende (Anzeige auf Screen + Handy). Wer früh 8 verballert, hat später
// nur noch 4. Budget 0 ⇒ der Partner rät ohne Hinweis.
// KORREKTUR-REGEL (Eval 3, ⌫): VOR dem Senden löscht ⌫ das letzte Zeichen
// vom Streifen und gibt es ins Budget ZURÜCK — Vertipper sind keine
// Telegramm-Wörter. GESENDET (auch Auto-Senden beim Timeout) = endgültig
// verbraucht. Fair, weil nur Zeichen zurückkommen, die in DIESEM Hinweis
// getippt wurden — das Budget kann nie über den Beat-Start-Stand wachsen.
// Paare: bei Teams die Teampartner, sonst zufällige Paare pro Runde
// (ungerade Zahl ⇒ ein Dreier). Beschreiber-Disconnect ⇒ neutraler
// Zufallsbegriff-Skip (NIEMALS Antwort-Buchstaben als Auto-Hinweis leaken!).
import type { Rng } from "../rng";
import type { MvSong } from "./musikvideo-raten.meta";

export const BUCHSTABEN_TELEGRAMM_ID = "buchstaben-telegramm";

export const BUCHSTABEN_TELEGRAMM_META = {
  id: BUCHSTABEN_TELEGRAMM_ID,
  name: "Das 7-Buchstaben-Telegramm",
  minPlayers: 2,
  maxPlayers: 8,
  formats: ["buttons", "text"] as const,
  // Begriffe kommen aus Song-Pack + eingebautem Pool — nicht aus dem Fragen-Pool.
  contentKind: "none" as const,
  // Song-Titel in den Begriffs-Topf: flow.starteFrage hängt den Song-Pool
  // READ-ONLY an (KEIN usedSongIds-Verbrauch — nur Titel-Texte, keine Medien).
  wuenschtSongs: true,
  needsScreen: true,
  // Paar-Koop mit fester Prämie — keine Streak-Kette, keine Speed-Boni.
  streak: false,
  // EIN init() pro Runde: Paar-Bildung + Beat-Rotation brauchen die ganze Runde.
  roundBased: true,
};

/**
 * Spieler-Aktionen:
 * · buchstabe — der Beschreiber tippt EIN Zeichen (nur A–Z/0–9, kostet Budget)
 * · loeschen  — ⌫ VOR dem Senden: letztes Zeichen weg, Budget-Rückgabe (+1)
 * · senden    — der Beschreiber schickt das Telegramm ab (Raten beginnt früher)
 * · answer    — der Ratende wählt eine der 4 Optionen (generischer Draht)
 */
export type BuchstabenTelegrammAction =
  | { type: "buchstabe"; zeichen: string }
  | { type: "loeschen" }
  | { type: "senden" }
  | { type: "answer"; choice: 0 | 1 | 2 | 3 };

// ---------- Budget & Timing (Design-Entscheidungen dieses Formats) ----------

/** Max. Zeichen PRO Hinweis (Standard-N). */
export const BT_HINWEIS_MAX = 8;
/** Zeichen-Budget PRO SPIELER über das GANZE Match (Rest verfällt). */
export const BT_MATCH_BUDGET = 60;
/** Erfolgs-Prämie JE Partner (Beschreiber UND Ratende[r], aus der Bank). */
export const BT_ERFOLG_MM = 250;

export const BT_VORSTELLUNG_MS = 4_000; // Paar-Vorstellung mit Affen
export const BT_TIPPEN_MS = 22_000; // Beschreiber tippt + sendet
export const BT_RATEN_MS = 18_000; // Ratende sehen Buchstaben + 4 Optionen
export const BT_AUFDECKUNG_MS = 6_000; // Show-Moment: Begriff + Money

// ---------- Zeichen-Validierung (nur A–Z, 0–9) ----------

const BT_ZEICHEN_REGEX = /^[A-Z0-9]$/;

/** EIN Eingabe-Zeichen validieren: Großbuchstabe A–Z oder Ziffer — sonst null.
 * Bewusst STRENG (keine Umlaute/Sonderzeichen): das Telegramm-Amt nimmt nur
 * das 36er-Alphabet an, die Handy-Tastatur bietet auch nur das an. */
export function btValidiereZeichen(zeichen: string): string | null {
  const gross = zeichen.toUpperCase();
  return BT_ZEICHEN_REGEX.test(gross) ? gross : null;
}

/** Freitext → Telegramm-Zeichenkette: Umlaute transliterieren (Ä→AE …),
 * alles andere außer A–Z/0–9 fällt weg. Grundlage des Beschreiber-Bots. */
export function btTelegrammZeichen(text: string): string {
  return text
    .toUpperCase()
    .replace(/Ä/g, "AE")
    .replace(/Ö/g, "OE")
    .replace(/Ü/g, "UE")
    .replace(/ß/gi, "SS")
    .replace(/[^A-Z0-9]/g, "");
}

/** Beschreiber-Bot-Hinweis: die ersten maxN sinnvollen Zeichen des Begriffs
 * (ohne Leerzeichen/Sonderzeichen) — deterministisch. */
export function btHinweisAusTitel(titel: string, maxN: number): string {
  return btTelegrammZeichen(titel).slice(0, Math.max(0, maxN));
}

// ---------- Begriffs-Pool (eingebaut, 60+ eindeutige Begriffe) ----------

export type BtBegriffArt = "film" | "sprichwort" | "promi" | "song";

export interface BtBegriff {
  text: string;
  art: BtBegriffArt;
  /** Nur bei art === "song": Zusatz-Info für den Beschreiber. */
  artist?: string;
}

const FILME = [
  "Der König der Löwen",
  "Titanic",
  "Harry Potter",
  "Der Herr der Ringe",
  "Star Wars",
  "Zurück in die Zukunft",
  "Fluch der Karibik",
  "Jurassic Park",
  "Findet Nemo",
  "Die Eiskönigin",
  "King Kong",
  "Der weiße Hai",
  "Rocky",
  "Avatar",
  "Matrix",
  "Ghostbusters",
  "Shrek",
  "Madagascar",
  "Das Dschungelbuch",
  "Kevin allein zu Haus",
  "Forrest Gump",
  "Das Boot",
];

const SPRICHWOERTER = [
  "Morgenstund hat Gold im Mund",
  "Wer rastet, der rostet",
  "Übung macht den Meister",
  "Aller Anfang ist schwer",
  "Der Apfel fällt nicht weit vom Stamm",
  "Lügen haben kurze Beine",
  "Wer zuletzt lacht, lacht am besten",
  "Eile mit Weile",
  "Stille Wasser sind tief",
  "Viele Köche verderben den Brei",
  "Die Katze im Sack kaufen",
  "Tomaten auf den Augen haben",
  "Jemandem einen Bären aufbinden",
  "Das fünfte Rad am Wagen",
  "Alte Liebe rostet nicht",
  "Kleider machen Leute",
  "Wo ein Wille ist, ist auch ein Weg",
  "Hunde, die bellen, beißen nicht",
  "Ausnahmen bestätigen die Regel",
  "Reden ist Silber, Schweigen ist Gold",
  "Ein blindes Huhn findet auch mal ein Korn",
  "Wer anderen eine Grube gräbt, fällt selbst hinein",
];

const PROMIS = [
  "Albert Einstein",
  "Angela Merkel",
  "Ludwig van Beethoven",
  "Wolfgang Amadeus Mozart",
  "Leonardo da Vinci",
  "Napoleon Bonaparte",
  "Kleopatra",
  "Elvis Presley",
  "Marilyn Monroe",
  "Charlie Chaplin",
  "Michael Jackson",
  "Madonna",
  "Boris Becker",
  "Steffi Graf",
  "Franz Beckenbauer",
  "Michael Schumacher",
  "Dirk Nowitzki",
  "Helene Fischer",
  "Otto Waalkes",
  "Thomas Gottschalk",
  "Günther Jauch",
  "Albrecht Dürer",
];

/** Der eingebaute Pool: 66 eindeutige Begriffe (Filme/Sprichwörter/Promis). */
export const BT_BEGRIFFS_POOL: readonly BtBegriff[] = [
  ...FILME.map((text): BtBegriff => ({ text, art: "film" })),
  ...SPRICHWOERTER.map((text): BtBegriff => ({ text, art: "sprichwort" })),
  ...PROMIS.map((text): BtBegriff => ({ text, art: "promi" })),
];

/** Fiktive Song-Köder, falls das Song-Pack < 4 Titel hat (Notbetrieb). */
export const BT_SONG_KOEDER: readonly string[] = [
  "Neonherz",
  "Mitternachtsbanane",
  "Regen über Rio",
  "Dschungeltelefon",
  "Goldstaub-Boulevard",
  "Samtpfoten-Samba",
];

/** Song-Pack-Einträge als Telegramm-Begriffe (Titel raten, Artist als Info). */
export function btBegriffeAusSongs(songs: readonly MvSong[]): BtBegriff[] {
  return songs.map((s) => ({ text: s.titel, art: "song" as const, artist: s.artist }));
}

/** Anzeige-Label der Begriffs-Art (Screen-Banner + Beschreiber-Karte). */
export function btArtLabel(art: BtBegriffArt): string {
  return art === "film"
    ? "Film"
    : art === "sprichwort"
      ? "Sprichwort"
      : art === "promi"
        ? "Promi"
        : "Song-Titel";
}

/**
 * 4 Optionen bauen: der richtige Begriff + 3 Köder DERSELBEN Art (gleiche
 * Kategorie = echtes Raten), deterministisch gemischt; reicht der Pool nicht
 * (z. B. Mini-Song-Pack), füllen artfremde Begriffe bzw. Song-Köder auf.
 */
export function btBaueOptionen(
  kandidaten: readonly BtBegriff[],
  korrekt: BtBegriff,
  rng: Rng,
): { optionen: string[]; answer: number } {
  const andere = (filter: (b: BtBegriff) => boolean): string[] =>
    kandidaten.filter((b) => b.text !== korrekt.text && filter(b)).map((b) => b.text);
  const gleicheArt = andere((b) => b.art === korrekt.art);
  for (let i = gleicheArt.length - 1; i > 0; i--) {
    const j = rng.int(i + 1);
    [gleicheArt[i], gleicheArt[j]] = [gleicheArt[j], gleicheArt[i]];
  }
  const auffueller =
    korrekt.art === "song"
      ? BT_SONG_KOEDER.filter((t) => t !== korrekt.text)
      : andere((b) => b.art !== korrekt.art);
  const koeder = [...new Set([...gleicheArt, ...auffueller])].slice(0, 3);
  const answer = rng.int(4);
  const optionen = [...koeder.slice(0, answer), korrekt.text, ...koeder.slice(answer)];
  return { optionen: optionen.slice(0, 4), answer };
}

// ---------- Paar-Bildung (Teams ODER Zufalls-Paare, ungerade ⇒ Dreier) ----------

export interface BtPaar {
  /** 2 Mitglieder (Standard) oder 3 (Dreier bei ungerader Zahl). */
  mitglieder: string[];
}

/**
 * Paare bilden: MIT Team-Zuordnung (teamVon) werden Teampartner gepaart
 * (Team-Reste landen im Zufalls-Topf), OHNE Teams zufällige Paare
 * (Rng injiziert — deterministisch pro Runde). Ungerade Gesamtzahl ⇒ der
 * letzte Übrige stößt zum letzten Paar (EIN Dreier). Bei nur 2 Spielern
 * gibt es genau 1 Paar; 3 Spieler ⇒ 1 Dreier.
 */
export function btBildePaare(
  spieler: readonly string[],
  teamVon: Record<string, string> | null,
  rng: Rng,
): BtPaar[] {
  const paare: BtPaar[] = [];
  const rest: string[] = [];

  if (teamVon !== null && Object.keys(teamVon).length > 0) {
    const gruppen = new Map<string, string[]>();
    for (const pid of spieler) {
      const team = teamVon[pid];
      if (team === undefined) {
        rest.push(pid);
        continue;
      }
      gruppen.set(team, [...(gruppen.get(team) ?? []), pid]);
    }
    for (const mitglieder of gruppen.values()) {
      for (let i = 0; i + 1 < mitglieder.length; i += 2) {
        paare.push({ mitglieder: [mitglieder[i], mitglieder[i + 1]] });
      }
      if (mitglieder.length % 2 === 1) rest.push(mitglieder[mitglieder.length - 1]);
    }
  } else {
    rest.push(...spieler);
  }

  // Zufalls-Topf deterministisch mischen und zu Paaren falten.
  for (let i = rest.length - 1; i > 0; i--) {
    const j = rng.int(i + 1);
    [rest[i], rest[j]] = [rest[j], rest[i]];
  }
  for (let i = 0; i + 1 < rest.length; i += 2) {
    paare.push({ mitglieder: [rest[i], rest[i + 1]] });
  }
  if (rest.length % 2 === 1) {
    const uebrig = rest[rest.length - 1];
    if (paare.length > 0) {
      // Ungerade ⇒ EIN Dreier (der Übrige stößt zum letzten Paar).
      paare[paare.length - 1] = {
        mitglieder: [...paare[paare.length - 1].mitglieder, uebrig],
      };
    } else {
      paare.push({ mitglieder: [uebrig] }); // 1 Spieler — degeneriert, rät solo
    }
  }
  return paare;
}

/** Beschreiber eines Beats: Paare rotieren pro Beat, innerhalb des Paares
 * wechselt die Rolle bei jedem erneuten Auftritt (Beat k, p Paare:
 * Paar k mod p, Beschreiber-Index ⌊k/p⌋ mod Mitgliederzahl). */
export function btBeschreiberIndex(
  beatIndex: number,
  paarAnzahl: number,
  mitglieder: number,
): number {
  return Math.floor(beatIndex / Math.max(1, paarAnzahl)) % Math.max(1, mitglieder);
}

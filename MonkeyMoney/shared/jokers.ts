// Joker-Katalog v1 (GAME-DESIGN §5.1, genau 7) — gemeinsames Consumable-Datenmodell:
// id, Ladungen pro Spieler, Einsatzfenster, Preisformel, Bildschirm-Inszenierung.
// Preise werden auf 10er gerundet (Prozent-Formeln erzeugen krumme Werte).
import { rundeAuf10 } from "./economy";

export type JokerId =
  | "bananen-split" // J1: 50:50
  | "ueberziehungskredit" // J2: Zeit+
  | "goldene-banane" // J3: Doppel (×2 Gewinn UND Strafe, Frage 1 Stufe höher)
  | "schmiergeld" // J4: Tipp-Kauf (Stufe 1/2)
  | "rueckgaberecht" // J5: Zweitantwort
  | "bananentresor" // J6: Klau-Schutz 1 Runde
  | "portfolio-umschichtung"; // J7: Kategorie-Tausch

/** Einsatzfenster: in welcher Engine-Phase darf der Joker gezündet werden? */
export type JokerFenster = "frage" | "vor-frage" | "zwischen-fragen";

export type JokerPreis =
  | { typ: "gratis" }
  | { typ: "flat"; mm: number }
  | { typ: "prozentFragenwert"; prozent: number }
  | { typ: "prozentKonto"; prozent: number };

export interface JokerDef {
  id: JokerId;
  name: string;
  emoji: string;
  beschreibung: string;
  fenster: JokerFenster;
  /** Info-Joker: max. 1 von (J1 ODER J4) pro Frage (§5.1). */
  infoJoker?: boolean;
  /** Gratis-Ladungen bei Match-Start. */
  gratisLadungen: number;
  /** Max. Nach-KÄUFE pro Spieler/Match (Standard-Modell: 2 gleiche). */
  maxKaeufe: number;
  preis: JokerPreis;
  /** Braucht Plugin-Unterstützung (JokerAktion) — sonst im Format nicht nutzbar. */
  pluginAktion?: "fiftyFifty" | "removeOne" | "secondTry";
  maxProFrage?: number;
}

export const JOKER: Record<JokerId, JokerDef> = {
  "bananen-split": {
    id: "bananen-split",
    name: "Bananen-Split",
    emoji: "🍌",
    beschreibung: "50:50 — die Affenhand reißt 2 falsche Optionen ab.",
    fenster: "frage",
    infoJoker: true,
    gratisLadungen: 1, // 1 Gratis-Ladung zum Start
    maxKaeufe: 2,
    preis: { typ: "prozentFragenwert", prozent: 40 },
    pluginAktion: "fiftyFifty",
    maxProFrage: 1,
  },
  ueberziehungskredit: {
    id: "ueberziehungskredit",
    name: "Überziehungskredit",
    emoji: "⏳",
    beschreibung: "+10 s auf den laufenden Timer (kein Speed-Bonus in den Dispo-Sekunden).",
    fenster: "frage",
    gratisLadungen: 0,
    maxKaeufe: 2,
    preis: { typ: "flat", mm: 150 },
    maxProFrage: 1,
  },
  "goldene-banane": {
    id: "goldene-banane",
    name: "Goldene Banane",
    emoji: "✨",
    beschreibung: "Nächste Frage: Gewinn ×2 UND Strafen ×2 — Gold kostet Mut.",
    fenster: "vor-frage",
    gratisLadungen: 1, // 1× pro Match GRATIS für jeden, keine Nachkäufe
    maxKaeufe: 0,
    preis: { typ: "gratis" },
  },
  schmiergeld: {
    id: "schmiergeld",
    name: "Schmiergeld",
    emoji: "🤫",
    beschreibung:
      "Tipp kaufen: Stufe 1 nimmt eine falsche Option weg, Stufe 2 flüstert den Anfangsbuchstaben.",
    fenster: "frage",
    infoJoker: true,
    gratisLadungen: 0,
    maxKaeufe: 99, // unbegrenzt oft (§5.1) — Kauf zündet sofort
    preis: { typ: "prozentFragenwert", prozent: 25 }, // Stufe 1; Stufe 2 = 35 %
    pluginAktion: "removeOne",
  },
  rueckgaberecht: {
    id: "rueckgaberecht",
    name: "Rückgaberecht",
    emoji: "↩️",
    beschreibung: "Nach falscher Antwort sofort ein 2. Versuch — Gewinn nur 50 %.",
    fenster: "frage",
    gratisLadungen: 0,
    maxKaeufe: 2,
    preis: { typ: "prozentFragenwert", prozent: 50 },
    pluginAktion: "secondTry",
    maxProFrage: 1,
  },
  bananentresor: {
    id: "bananentresor",
    name: "Bananentresor",
    emoji: "🛡️",
    beschreibung: "Klau-Schutz: alle Klau-Effekte prallen 1 Runde lang ab.",
    fenster: "zwischen-fragen",
    gratisLadungen: 0,
    maxKaeufe: 2,
    preis: { typ: "prozentKonto", prozent: 10 },
  },
  "portfolio-umschichtung": {
    id: "portfolio-umschichtung",
    name: "Portfolio-Umschichtung",
    emoji: "🔄",
    beschreibung: "Eigene Kategorie abwerfen — du bekommst eine Ersatzfrage anderer Kategorie.",
    fenster: "vor-frage",
    gratisLadungen: 1, // 1× pro Match gratis
    maxKaeufe: 1, // 2. Ladung 300 MM
    preis: { typ: "flat", mm: 300 },
  },
};

export const ALLE_JOKER_IDS = Object.keys(JOKER) as JokerId[];

export const SCHMIERGELD_STUFE2_PROZENT = 35;

/**
 * Preis einer Joker-Ladung in MM (auf 10er gerundet, min. 0).
 * `rabattFaktor` = Sozialrabatt (economy.sozialrabattFaktor).
 */
export function jokerPreis(
  def: JokerDef,
  fragenwert: number,
  kontostand: number,
  rabattFaktor = 1.0,
  stufe?: number,
): number {
  let basis: number;
  switch (def.preis.typ) {
    case "gratis":
      return 0;
    case "flat":
      basis = def.preis.mm;
      break;
    case "prozentFragenwert": {
      const prozent =
        def.id === "schmiergeld" && stufe === 2 ? SCHMIERGELD_STUFE2_PROZENT : def.preis.prozent;
      basis = (prozent / 100) * fragenwert;
      break;
    }
    case "prozentKonto":
      basis = (def.preis.prozent / 100) * Math.max(0, kontostand);
      break;
  }
  return Math.max(0, rundeAuf10(basis * rabattFaktor));
}

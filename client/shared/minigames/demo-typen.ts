// Erklär-Demo-Choreos (Mario-Party-Prinzip: ZEIGEN statt lesen): reine
// Daten-Typen für die 8-12-s-Demos auf der Erklärkarte. Zwei Beispiel-Affen
// („Mia" und „Bo") spielen die Kern-Mechanik des Formats vor. Die Plugins
// exportieren je ein `demoChoreo` (ADDITIV am Registry-Vertrag) — abgespielt
// wird es von client/screen/erklaer-demo/ (deterministisch, loopt, skippable
// über die unveränderte Engine-Phase).

/** Die zwei Demo-Puppen: a = Mia (links), b = Bo (rechts). */
export type DemoAkteur = "a" | "b";

/** Ort für Geld-Flüge und die Stinkbanane. */
export type DemoOrt = DemoAkteur | "mitte";

/** Körper-Posen (nur transform/opacity — Plan §1.3 Gesetz 6). */
export type DemoPose =
  | "idle"
  | "denk"
  | "tipp"
  | "buzz"
  | "jubel"
  | "frust"
  | "huepf"
  | "duck"
  | "zeig"
  | "wackel"
  | "fall"
  | "schleich";

export type DemoGesicht = "neutral" | "jubel" | "frust" | "denk";

/** Wiederverwendbare Mini-Requisiten im tokens.css-Look. */
export type DemoRequisit =
  | {
      art: "frage";
      /** Verdeckt = nur „???" + Kategorie-Riegel (Auktion/Alles-oder-Banane). */
      verdeckt?: boolean;
      /** Angetippte Option je Akteur (Marker in Spielerfarbe). */
      tippA?: number | null;
      tippB?: number | null;
      /** Aufgelöste richtige Option (grün, falsche Tipps rot). */
      richtig?: number | null;
    }
  | { art: "buzzer"; gedrueckt?: DemoAkteur | null }
  | {
      art: "slider";
      /** Regler-Position 0..1 — Wechsel animiert per CSS-Transition. */
      wert: number;
      markerA?: number | null;
      markerB?: number | null;
      /** Zahlenstrahl-Auflösung: Ziel-Fahne erscheint. */
      ziel?: number | null;
    }
  | {
      art: "tueren";
      /** Chips je Akteur auf den 4 Antwort-Türen. */
      chipsA?: number[];
      chipsB?: number[];
      /** Geöffnete (richtige) Tür. */
      offen?: number | null;
    }
  | {
      art: "kette";
      /** Pott-Kette (z. B. ["50","100","200"]), aktiv = letztes Glied. */
      glieder: string[];
      bankVon?: DemoAkteur | null;
      gerissen?: boolean;
    }
  | { art: "banane"; bei: DemoOrt; hektisch?: boolean; geplatzt?: boolean }
  | {
      art: "pixel";
      /** 0 = grob verpixelt … 1 = scharf. */
      schaerfe: number;
      preis: string;
    }
  | { art: "leiter"; stufen: string[]; perfekt?: boolean }
  | {
      art: "sack";
      betrag: string;
      eingefrorenA?: string | null;
      eingefrorenB?: string | null;
    }
  | {
      art: "lianen";
      /** Kletter-Höhe je Akteur 0..1 (0 = Krokodil-Nähe). */
      hoeheA: number;
      hoeheB: number;
      schnappt?: DemoAkteur | null;
    }
  | { art: "steg" }
  | {
      art: "schild";
      text: string;
      ton?: "gold" | "rot" | "gruen" | "cyan" | "papier";
      /** Position: links (bei Mia), mitte, rechts (bei Bo). */
      bei?: DemoOrt;
    };

/** Voll aufgelöste Szene eines Beats (Defaults füllt die Engine). */
export interface DemoSzene {
  pose: Record<DemoAkteur, DemoPose>;
  gesicht: Record<DemoAkteur, DemoGesicht>;
  blase: { wer: DemoAkteur; text: string } | null;
  requisiten: DemoRequisit[];
  geldflug: { von: DemoOrt; zu: DemoOrt } | null;
  effekt: "konfetti" | "explosion" | null;
}

/**
 * Ein Beat ERSETZT die komplette Szene (kein Merge — deterministisch und
 * explizit): fehlende Felder fallen auf die Grundszene zurück. `sound` spielt
 * NUR im ersten Loop-Durchlauf (Dauerschleife nervt sonst).
 */
export interface DemoBeat extends Partial<DemoSzene> {
  /** Startzeit in ms innerhalb des Loops (aufsteigend, < dauer). */
  at: number;
  sound?: string;
}

/** 3-5 Beats, Loop-Dauer 8 000-12 000 ms (Erklärkarte läuft 12 s). */
export interface DemoChoreo {
  dauer: number;
  beats: DemoBeat[];
}

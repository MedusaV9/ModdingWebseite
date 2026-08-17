// Choreo-Engine der Erklär-Demos: PURE Zeit→Szene-Logik (testbar ohne DOM).
// Ein Loop ist eine Beat-Treppe: Szene(t) = letzter Beat mit at <= t mod dauer,
// fehlende Beat-Felder fallen auf die Grundszene zurück. Sounds feuern nur im
// ERSTEN Loop-Durchlauf (Dauerschleifen-Sound nervt) und pro Beat genau einmal.
import type { DemoBeat, DemoChoreo, DemoSzene } from "../../shared/minigames/demo-typen";

/** Grundszene: beide Affen idle/neutral, Bühne leer. */
export function grundSzene(): DemoSzene {
  return {
    pose: { a: "idle", b: "idle" },
    gesicht: { a: "neutral", b: "neutral" },
    blase: null,
    requisiten: [],
    geldflug: null,
    effekt: null,
  };
}

/** Zeit in den Loop falten (negative Eingaben sicher — Uhr-Sprünge). */
export function loopZeit(dauer: number, tMs: number): number {
  return ((tMs % dauer) + dauer) % dauer;
}

/** Index des aktiven Beats bei t (letzter mit at <= loopZeit; -1 = vor Beat 0). */
export function beatIndexBei(choreo: DemoChoreo, tMs: number): number {
  const t = loopZeit(choreo.dauer, tMs);
  let index = -1;
  for (const [i, beat] of choreo.beats.entries()) {
    if (beat.at <= t) index = i;
    else break;
  }
  return index;
}

/** Beat → voll aufgelöste Szene (Defaults aus der Grundszene). */
export function vollSzene(beat?: Partial<DemoSzene>): DemoSzene {
  const basis = grundSzene();
  if (!beat) return basis;
  return {
    pose: { ...basis.pose, ...beat.pose },
    gesicht: { ...basis.gesicht, ...beat.gesicht },
    blase: beat.blase ?? null,
    requisiten: beat.requisiten ?? [],
    geldflug: beat.geldflug ?? null,
    effekt: beat.effekt ?? null,
  };
}

/** Szene zum Zeitpunkt t — pure Funktion, gleicher t ⇒ gleiche Szene. */
export function szeneBei(choreo: DemoChoreo, tMs: number): DemoSzene {
  const index = beatIndexBei(choreo, tMs);
  return vollSzene(index >= 0 ? choreo.beats[index] : undefined);
}

export interface DemoTakt {
  beatIndex: number;
  szene: DemoSzene;
  /** Beat-Sound — nur im ersten Loop und nur beim Beat-Wechsel gesetzt. */
  sound: string | null;
  /** true beim Betreten eines neuen Beats (DOM nur dann anfassen!). */
  neuerBeat: boolean;
}

export interface DemoSpieler {
  tick(tMs: number): DemoTakt | null;
  stop(): void;
  gestoppt(): boolean;
}

/**
 * Abspiel-Controller: hält Beat-/Loop-Cursor, meldet Beat-Wechsel + Sounds.
 * Nach stop() liefert tick() nur noch null (Skip-Cleanup: der Renderer räumt
 * DOM/rAF ab und darf danach keine Sounds mehr auslösen).
 */
export function createDemoSpieler(choreo: DemoChoreo): DemoSpieler {
  let letzterBeat = -2; // -2 = noch nie getickt (auch Beat -1 gilt als Wechsel)
  let gestoppt = false;

  return {
    tick(tMs: number): DemoTakt | null {
      if (gestoppt) return null;
      const beatIndex = beatIndexBei(choreo, tMs);
      const loopNr = Math.floor(Math.max(0, tMs) / choreo.dauer);
      const neuerBeat = beatIndex !== letzterBeat;
      letzterBeat = beatIndex;
      const beat: DemoBeat | undefined = beatIndex >= 0 ? choreo.beats[beatIndex] : undefined;
      return {
        beatIndex,
        szene: vollSzene(beat),
        sound: neuerBeat && loopNr === 0 ? (beat?.sound ?? null) : null,
        neuerBeat,
      };
    },
    stop() {
      gestoppt = true;
    },
    gestoppt() {
      return gestoppt;
    },
  };
}

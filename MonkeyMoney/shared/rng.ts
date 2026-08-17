// Injizierbarer Zufall — nie Math.random() in Spiellogik (TECH-SPEC Leitprinzip 3).
export interface Rng {
  /** Gleichverteilte Zahl in [0, 1). */
  next(): number;
  /** Ganzzahl in [0, maxExklusiv). */
  int(maxExklusiv: number): number;
}

/** Deterministischer Mulberry32-Generator — Seed = Testfall. */
export function createRng(seed: number): Rng {
  let a = seed >>> 0;
  const next = (): number => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  return {
    next,
    int: (maxExklusiv: number) => Math.floor(next() * maxExklusiv),
  };
}

// ---------- ADDITIV (Meta-Agent): serialisierbarer Rng für Save/Load ----------

/** Rng mit auslesbarem/setzbarem Zustand — Grundlage der rngState-Serialisierung
 * an Phasengrenzen (TECH-SPEC §5.2: Save hält Determinismus über Neustarts). */
export interface StatefulRng extends Rng {
  /** Interner Mulberry32-Zustand (uint32) — wandert 1:1 in die Save-Datei. */
  getState(): number;
  /** Zustand aus einer Save-Datei wiederherstellen. */
  setState(state: number): void;
}

/** Wie createRng, aber mit getState/setState (identische Zahlenfolge bei gleichem Zustand). */
export function createStatefulRng(seed: number): StatefulRng {
  let a = seed >>> 0;
  const next = (): number => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  return {
    next,
    int: (maxExklusiv: number) => Math.floor(next() * maxExklusiv),
    getState: () => a,
    setState: (state: number) => {
      a = state >>> 0;
    },
  };
}

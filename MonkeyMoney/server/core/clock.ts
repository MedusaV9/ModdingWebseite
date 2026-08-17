// Die EINZIGE Stelle, an der die OS-Uhr und echter Zufall angezapft werden —
// überall sonst werden Clock und Rng injiziert (TECH-SPEC Leitprinzip 3).
import { randomInt } from "node:crypto";
import { createStatefulRng, type StatefulRng } from "../../shared/rng";
import type { Clock } from "../../shared/time";

export function createRealClock(): Clock {
  return { now: () => Date.now() };
}

/** Produktions-Rng: deterministischer Generator mit kryptographischem Seed.
 * Stateful (get/setState) — Save/Load friert den Rng-Zustand mit ein. */
export function createSeededRng(seed?: number): StatefulRng {
  return createStatefulRng(seed ?? randomInt(0, 2 ** 31));
}

// Clock-Interface — Zeit wird IMMER injiziert (TECH-SPEC Leitprinzip 3).
// Die einzige echte Implementierung (OS-Uhr) lebt in server/core/clock.ts.
export interface Clock {
  /** Millisekunden seit Epoch (Server-Zeit). */
  now(): number;
}

/** Test-Clock: manuell vorspulbar, deterministisch. */
export function createTestClock(startMs = 0): Clock & { advance(ms: number): void } {
  let t = startMs;
  return {
    now: () => t,
    advance(ms: number) {
      t += ms;
    },
  };
}

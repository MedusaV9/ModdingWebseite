/**
 * Deterministic seeded RNG (SplitMix32 core) so arena runs are reproducible:
 * the same `--seed` produces the same scenario schedule, texts, question ids,
 * device picks and timings (modulo real network/scheduler jitter).
 */

function hashSeed(seed) {
  const str = String(seed);
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i += 1) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

export function makeRng(seed) {
  let state = hashSeed(seed) || 0x9e3779b9;
  function next() {
    state = (state + 0x9e3779b9) >>> 0;
    let z = state;
    z = Math.imul(z ^ (z >>> 16), 0x21f0aaad);
    z = Math.imul(z ^ (z >>> 15), 0x735a2d97);
    z = (z ^ (z >>> 15)) >>> 0;
    return z / 0x100000000;
  }
  return {
    /** Uniform float in [0, 1). */
    next,
    /** Uniform integer in [min, max] (inclusive). */
    int(min, max) {
      return min + Math.floor(next() * (max - min + 1));
    },
    /** Random array element. */
    pick(array) {
      return array[Math.floor(next() * array.length)];
    },
    /** True with probability p. */
    chance(p) {
      return next() < p;
    },
    /** Weighted pick over [{weight, value}] entries. */
    weighted(entries) {
      const total = entries.reduce((sum, e) => sum + e.weight, 0);
      let roll = next() * total;
      for (const entry of entries) {
        roll -= entry.weight;
        if (roll <= 0) return entry.value;
      }
      return entries[entries.length - 1].value;
    },
    /** Derives an independent child RNG (per couple / per scenario). */
    child(label) {
      return makeRng(`${seed}:${label}`);
    },
  };
}

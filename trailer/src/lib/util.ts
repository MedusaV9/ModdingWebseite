/** Deterministic helpers + palette (see docs/plans_v3/trailer/motion_design.md). */

export const SEED = 0xec1195e;

export const mulberry32 = (seed: number) => () => {
  seed |= 0;
  seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};

/** One-shot uniform random in [a,b) from an integer key — stateless per frame. */
export const rnd = (key: number, a = 0, b = 1) => a + mulberry32(SEED + key)() * (b - a);

export const PAL = {
  VOID: '#030204',
  NIGHT: '#0B0614',
  SHADOW_VIOLET: '#1E1433',
  ECLIPSE_VIOLET: '#8B5CF6',
  VIOLET_DEEP: '#5B21B6',
  VIOLET_HOT: '#A78BFA',
  GOLD: '#E8B44A',
  GOLD_HOT: '#FFD98A',
  GOLD_DEEP: '#9A6A1F',
  CORONA_WHITE: '#FFF6E9',
  GLITCH_R: '#FF3355',
  GLITCH_C: '#22F5EE',
  GLOW_1: '#EDE4FF',
  GLOW_2: '#C4B5FD',
} as const;

export const SPRINGS = {
  SLAM: {damping: 12, stiffness: 260, mass: 0.9},
  RISE: {damping: 22, stiffness: 140, mass: 1.0},
  DRIFT: {damping: 40, stiffness: 60, mass: 1.4},
} as const;

/** Exponentially decaying camera shake (deterministic). */
export const shake = (frame: number, start: number, amp: number, tau = 7) => {
  const t = frame - start;
  if (t < 0) return {x: 0, y: 0, rot: 0};
  const d = Math.exp(-t / tau);
  return {
    x: amp * d * Math.sin(t * 1.15),
    y: amp * 0.7 * d * Math.sin(t * 1.36 + 2),
    rot: 0.45 * d * Math.sin(t * 0.9),
  };
};

/** Permanent hand-held idle wobble. */
export const idleWobble = (frame: number) => ({
  x: 5 * Math.sin(frame * 0.042),
  y: 3.4 * Math.sin(frame * 0.031 + 1.7),
});

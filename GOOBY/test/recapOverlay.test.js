// V4/G64 — recap overlay logic + strings tests (PLAN4 §E block G64): the
// node-testable seams of the cinematic player — §C-SYS2.6 track-pick order,
// fire-once cue consumption + skip cut, the per-bar element-clock re-anchor
// (±80 ms §A2 machinery), §B2.2 element volume math, §C-SYS2.7 reward math,
// §C-SYS2.8 history/replay models, the canAutoStart trigger guard, EN/DE
// string parity incl. the VERBATIM §C-SYS2.4 template mirror of
// systems/recap.js STAT_CATALOG, and the shared-file marker pins (§E0.1-10).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join, dirname } from 'node:path';

import {
  OVERLAY, BIOME_BACKDROPS, biomeBackdrop, recapSeed, ownerRecapTrackIds,
  fallbackRecapTrackId, chooseRecapTrack, elementVolume, barIndexAt, barStartT,
  beatIndexAt, advanceClock, createCueScheduler, cutSpans, spanAt, nextSpanAt,
  popDurations, skipAllowed, displayMilestone, rewardCoins, replayRewardFrom,
  historyRows, agoLabel, canAutoStart, createOffsetRecorder,
  endCardHighlights, HIGHLIGHT_ICONS, // POLISH-J
  rotatedFrame, shouldRotate, createRotationGuard, // V6/B1 landscape
} from '../src/ui/recapOverlay.logic.js';
import { RECAP, STAT_CATALOG, beatGrid } from '../src/systems/recap.js';
import { DEFAULT_BIOMES, buildTimeline } from '../src/systems/recapDirector.js';
import { EN, DE } from '../src/data/strings/v4-recap.js';
import { EN as R2_EN, DE as R2_DE } from '../src/data/strings/v4-recap2.js'; // POLISH-J

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const manifest = JSON.parse(readFileSync(join(ROOT, 'src/data/musicManifest.json'), 'utf8'));
const MANIFEST_TRACKS = manifest.tracks;

const DAY = 86_400_000;

/** A committed-shape grid (Bonus Stage Blitz: 94.3 bpm, offset 0.13 s). */
const BLITZ = { bpm: 94.3, offsetSec: 0.13, beatsPerBar: 4 };

/** Timeline over the Blitz grid with a plausible L10 line set. */
function blitzTimeline() {
  return buildTimeline({
    beats: BLITZ,
    durationSec: 83.4,
    lines: [
      { id: 'days', value: 3 }, { id: 'games', value: 12 },
      { id: 'coinsEarned', value: 420 }, { id: 'tickles', value: 27 },
      { id: 'feeds', value: 21 }, { id: 'harvests', value: 9 },
      { id: 'stickers', value: 3 }, { id: 'quests', value: 8 },
      { id: 'washes', value: 6 }, { id: 'sleeps', value: 6 },
      { id: 'trips', value: 3 }, { id: 'distance', value: 380 },
    ],
    level: 10,
    trackId: 'recap-bonus-stage-blitz',
  });
}

// ── strings (§E0.1-8: EN+DE, §C-SYS2.4 verbatim mirror) ──────────────────────

test('v4-recap strings: EN and DE carry the exact same key set', () => {
  assert.deepEqual(Object.keys(EN).sort(), Object.keys(DE).sort());
  assert.ok(Object.keys(EN).length >= 26);
});

test('v4-recap strings: recap.line.* mirror STAT_CATALOG templates VERBATIM', () => {
  for (const row of STAT_CATALOG) {
    assert.equal(EN[`recap.line.${row.id}`], row.en, `EN template for '${row.id}'`);
    assert.equal(DE[`recap.line.${row.id}`], row.de, `DE template for '${row.id}'`);
    if (row.enOne) assert.equal(EN[`recap.line.${row.id}.one`], row.enOne);
    if (row.deOne) assert.equal(DE[`recap.line.${row.id}.one`], row.deOne);
  }
});

test('v4-recap strings: cinematic chrome keys present with {n} slots', () => {
  for (const dict of [EN, DE]) {
    for (const key of ['recap.title', 'recap.skip', 'recap.continue',
      'recap.endcard.rewards', 'recap.endcard.next', 'recap.endcard.all',
      'recap.profile.title', 'recap.profile.row', 'recap.profile.empty',
      'recap.ago.today', 'recap.ago.yesterday', 'recap.ago.days']) {
      assert.equal(typeof dict[key], 'string', key);
    }
    assert.match(dict['recap.title'], /\{n\}/);
    assert.match(dict['recap.endcard.rewards'], /\{n\}/);
    assert.match(dict['recap.profile.row'], /\{level\}.*\{ago\}/);
  }
  assert.equal(DE['recap.skip'], 'Überspringen ›'); // §C-SYS2.2 copy
});

// ── §C-SYS2.6 track pick order ───────────────────────────────────────────────

test('ownerRecapTrackIds: owner Recap tracks only, sorted, never stingers', () => {
  const ids = ownerRecapTrackIds(MANIFEST_TRACKS);
  assert.deepEqual(ids, ['recap-bonus-stage-blitz', 'recap-recap-song-2-moreepic-victory']);
});

test('ownerRecapTrackIds: §C-SYS1.5 disabled tracks drop out via trims', () => {
  const ids = ownerRecapTrackIds(MANIFEST_TRACKS, { 'recap-bonus-stage-blitz': { on: false } });
  assert.deepEqual(ids, ['recap-recap-song-2-moreepic-victory']);
});

test('fallbackRecapTrackId: the committed Recap - Abenteuer builtin', () => {
  assert.equal(fallbackRecapTrackId(MANIFEST_TRACKS), 'recap-abenteuer');
});

test('chooseRecapTrack: seeded pick is deterministic; empty owners → fallback', () => {
  const seed = recapSeed(10, 1_784_000_000_000);
  const a = chooseRecapTrack(MANIFEST_TRACKS, seed);
  const b = chooseRecapTrack(MANIFEST_TRACKS, seed);
  assert.deepEqual(a, b);
  assert.equal(a.fallback, false);
  assert.ok(['recap-bonus-stage-blitz', 'recap-recap-song-2-moreepic-victory'].includes(a.id));
  const off = {
    'recap-bonus-stage-blitz': { on: false },
    'recap-recap-song-2-moreepic-victory': { on: false },
  };
  assert.deepEqual(chooseRecapTrack(MANIFEST_TRACKS, seed, off),
    { id: 'recap-abenteuer', fallback: true });
});

test('recapSeed: deterministic per (level, at) and level-sensitive', () => {
  assert.equal(recapSeed(10, 123456), recapSeed(10, 123456));
  assert.notEqual(recapSeed(10, 123456), recapSeed(15, 123456));
  assert.equal(recapSeed(NaN, -5), recapSeed(0, 0)); // corrupt inputs fold to 0
});

test('chooseRecapTrack: different milestones can reach BOTH owner tracks', () => {
  const picks = new Set();
  for (let lvl = 5; lvl <= 40; lvl += 5) {
    picks.add(chooseRecapTrack(MANIFEST_TRACKS, recapSeed(lvl, 999)).id);
  }
  assert.deepEqual([...picks].sort(),
    ['recap-bonus-stage-blitz', 'recap-recap-song-2-moreepic-victory']);
});

// ── §B2.2 element volume ────────────────────────────────────────────────────

test('elementVolume: replicates MASTER_BASE × master² × music² bus math', () => {
  const v = elementVolume({ gainTrim: 1, trimVol: 100, master: 80, music: 70 });
  assert.ok(Math.abs(v - 0.9 * 0.64 * 0.49) < 1e-9);
});

test('elementVolume: music mute → 0; clamps to the element 0..1 range', () => {
  assert.equal(elementVolume({ musicEnabled: false }), 0);
  assert.equal(elementVolume({ gainTrim: 2, trimVol: 150, master: 100, music: 100 }), 1);
  assert.equal(elementVolume({ trimVol: 0 }), 0);
});

test('elementVolume: manifest gainTrim clamps to the 0.3–2 safety window', () => {
  const base = elementVolume({ gainTrim: 1 });
  assert.ok(Math.abs(elementVolume({ gainTrim: 99 }) - Math.min(1, base * 2)) < 1e-9);
  assert.ok(Math.abs(elementVolume({ gainTrim: 0.01 }) - base * 0.3) < 1e-9);
  assert.ok(Math.abs(elementVolume({ gainTrim: 0 }) - base) < 1e-9); // ≤0 → neutral 1
});

// ── master clock (§C-SYS2.6 re-anchor — the §A2 ±80 ms machinery) ───────────

test('barIndexAt / barStartT / beatIndexAt on the committed Blitz grid', () => {
  const grid = beatGrid(BLITZ, 83.4);
  assert.equal(barIndexAt(grid, 0.13), 0);
  assert.equal(barIndexAt(grid, 0.13 + grid.barSec * 2 + 0.001), 2);
  assert.ok(Math.abs(barStartT(grid, 2) - (0.13 + 2 * grid.barSec)) < 1e-9);
  assert.equal(beatIndexAt(grid, 0.13 + grid.beatSec * 5 + 0.001), 5);
});

test('advanceClock: wall clock advances freely without an element clock', () => {
  const grid = beatGrid(BLITZ, 83.4);
  let c = { t: 0, anchorBar: -1 };
  c = advanceClock(c, { dtSec: 0.016, elT: null, grid });
  assert.ok(Math.abs(c.t - 0.016) < 1e-9);
  assert.equal(c.anchored, false);
});

test('advanceClock: snaps to the element clock on every bar crossing', () => {
  const grid = beatGrid(BLITZ, 83.4);
  const bar1 = barStartT(grid, 1);
  let c = { t: bar1 - 0.01, anchorBar: 0 };
  c = advanceClock(c, { dtSec: 0.02, elT: bar1 + 0.03, grid });
  assert.equal(c.anchored, true); // crossed into bar 1 → re-anchored
  assert.ok(Math.abs(c.t - (bar1 + 0.03)) < 1e-9);
  assert.equal(c.anchorBar, 1);
});

test('advanceClock: small mid-bar drift rides; > MAX_DRIFT_SEC snaps at once', () => {
  const grid = beatGrid(BLITZ, 83.4);
  let c = { t: 1.0, anchorBar: 0 };
  c = advanceClock(c, { dtSec: 0.016, elT: 1.05, grid });
  assert.equal(c.anchored, false); // 34 ms drift, same bar → wall clock rides
  c = advanceClock({ t: 1.0, anchorBar: 0 }, { dtSec: 0.016, elT: 1.5, grid });
  assert.equal(c.anchored, true); // 0.48 s > MAX_DRIFT_SEC 0.25 → hard snap
  assert.equal(c.t, 1.5);
});

// ── cue consumption (fire-once, ordered) ────────────────────────────────────

test('createCueScheduler: fires each cue exactly once, in t order', () => {
  const sched = createCueScheduler([{ t: 2, k: 'b' }, { t: 1, k: 'a' }, { t: 3, k: 'c' }]);
  assert.deepEqual(sched.advance(0.5), []);
  assert.deepEqual(sched.advance(2.1).map((c) => c.k), ['a', 'b']);
  assert.deepEqual(sched.advance(2.1), []); // fire-once
  assert.equal(sched.peek().k, 'c');
  assert.equal(sched.remaining(), 1);
  assert.deepEqual(sched.advance(99).map((c) => c.k), ['c']);
  assert.equal(sched.firedCount(), 3);
});

test('createCueScheduler: skipTo consumes strictly-before cues (skip cut)', () => {
  const sched = createCueScheduler([{ t: 1 }, { t: 5 }, { t: 9 }]);
  sched.advance(1); // intro fired
  const skipped = sched.skipTo(9);
  assert.deepEqual(skipped.map((c) => c.t), [5]);
  assert.deepEqual(sched.advance(9).map((c) => c.t), [9]); // end cue still fires
});

test('createCueScheduler: drops malformed rows, tolerates non-arrays', () => {
  const sched = createCueScheduler([{ t: 'x' }, null, { t: 1 }]);
  assert.equal(sched.remaining(), 1);
  assert.equal(createCueScheduler(undefined).remaining(), 0);
});

test('scheduler + real director timeline: full L10 run fires every cue ≤ ±80 ms', () => {
  const tl = blitzTimeline();
  const sched = createCueScheduler(tl.cues);
  const rec = createOffsetRecorder();
  // Simulated 60 fps rAF loop on the wall clock (no-audio context §C-SYS2.6).
  let clock = { t: 0, anchorBar: -1 };
  const step = 1 / 60;
  for (let t = 0; t <= tl.totalSec + step; t += step) {
    clock = advanceClock(clock, { dtSec: step, elT: null, grid: tl });
    for (const cue of sched.advance(clock.t)) rec.record(cue.kind, cue.bar, cue.t, clock.t);
  }
  assert.equal(sched.remaining(), 0);
  const sum = rec.summary();
  assert.equal(sum.n, tl.cues.length);
  assert.ok(sum.maxAbsMs <= OVERLAY.BEAT_BUDGET_MS,
    `max |offset| ${sum.maxAbsMs} ms must be ≤ ${OVERLAY.BEAT_BUDGET_MS} ms at 60 fps`);
  assert.equal(sum.within, sum.n);
});

// ── vignette spans ──────────────────────────────────────────────────────────

test('cutSpans: 8 contiguous spans in DEFAULT_BIOMES order ending at the end card', () => {
  const tl = blitzTimeline();
  const spans = cutSpans(tl);
  assert.equal(spans.length, RECAP.VIGNETTES);
  assert.deepEqual(spans.map((s) => s.id), DEFAULT_BIOMES.map((b) => b.id));
  for (let i = 1; i < spans.length; i += 1) {
    assert.equal(spans[i].from, spans[i - 1].to, 'spans are contiguous');
  }
  assert.equal(spans[spans.length - 1].to, tl.endCard.t);
});

test('spanAt: live span + dolly progress; null in the intro and end card', () => {
  const tl = blitzTimeline();
  const spans = cutSpans(tl);
  assert.equal(spanAt(spans, 0.5), null); // intro title owns bars 0–1
  const mid = (spans[2].from + spans[2].to) / 2;
  const live = spanAt(spans, mid);
  assert.equal(live.id, 'harbor');
  assert.ok(Math.abs(live.progress - 0.5) < 1e-6);
  assert.equal(spanAt(spans, tl.endCard.t + 0.001), null);
});

test('nextSpanAt: upcoming cut within the pre-roll window only', () => {
  const tl = blitzTimeline();
  const spans = cutSpans(tl);
  const cut0 = spans[0].from;
  assert.equal(nextSpanAt(spans, cut0 - 2.5), null); // too early
  assert.equal(nextSpanAt(spans, cut0 - 0.5).id, 'meadow'); // within 1 s window
  assert.equal(nextSpanAt(spans, spans[1].from - 0.2).id, 'city');
  assert.equal(nextSpanAt(spans, spans[7].from + 0.1), null); // nothing after #8
});

test('biomeBackdrop: committed ART-GATE-2 file per §C-SYS2.3 biome + safe default', () => {
  assert.equal(Object.keys(BIOME_BACKDROPS).length, RECAP.VIGNETTES);
  for (const b of DEFAULT_BIOMES) {
    assert.match(biomeBackdrop(b.id).img, /^recap\/recap_\w+\.png$/);
  }
  assert.equal(biomeBackdrop('nope').img, null);
});

// ── pop windows / skip / milestones / rewards ───────────────────────────────

test('popDurations: §C-SYS2.6 pop + roll-up beats on the grid', () => {
  const grid = beatGrid(BLITZ, 83.4);
  const { popSec, rollSec } = popDurations({ popBeats: 2, rollupBeats: 2 }, grid);
  assert.ok(Math.abs(popSec - 2 * grid.beatSec) < 1e-9);
  assert.ok(Math.abs(rollSec - 2 * grid.beatSec) < 1e-9);
});

test('skipAllowed: taps before t = 10 s do nothing (§C-SYS2.2)', () => {
  assert.equal(skipAllowed(9.99, RECAP.SKIP_AFTER_SEC), false);
  assert.equal(skipAllowed(10, RECAP.SKIP_AFTER_SEC), true);
});

test('displayMilestone: §C-SYS2.1 fold — L4→L11 jump w/ pending 5 plays as 10', () => {
  assert.equal(displayMilestone(5, 11), 10);
  assert.equal(displayMilestone(10, 10), 10);
  assert.equal(displayMilestone(5, 6), 5);
  assert.equal(displayMilestone(999, 99), RECAP.LAST_MILESTONE); // clamps to 40
  assert.equal(displayMilestone(0, 3), RECAP.FIRST_MILESTONE);
});

test('rewardCoins: Σ 25×l for every level gained since the last recap', () => {
  assert.equal(rewardCoins(10, 5), 25 * (6 + 7 + 8 + 9 + 10));
  assert.equal(rewardCoins(5, 0), 25 * (2 + 3 + 4 + 5)); // fromLevel 0 → from L1
  assert.equal(rewardCoins(5, 5), 0);
});

test('replayRewardFrom: prior history row wins, else one milestone step down', () => {
  const history = [
    { level: 5, at: 100 }, { level: 10, at: 200 }, { level: 15, at: 300 },
  ];
  assert.equal(replayRewardFrom(history, history[2]), 10);
  assert.equal(replayRewardFrom(history, history[0]), 0); // 5 − MILESTONE_STEP
  assert.equal(replayRewardFrom([], { level: 20, at: 50 }), 15);
});

// ── profile „Rückblicke" models (§C-SYS2.8) ─────────────────────────────────

test('historyRows: newest-first with original-array replay indices', () => {
  const rows = historyRows([
    { level: 5, at: 100, stats: [{ id: 'days', value: 2 }] },
    { level: 10, at: 200 },
    { level: 0, at: 1 }, // corrupt row dropped
  ]);
  assert.deepEqual(rows.map((r) => [r.level, r.index]), [[10, 1], [5, 0]]);
  assert.deepEqual(rows[1].stats, [{ id: 'days', value: 2 }]);
  assert.deepEqual(historyRows(undefined), []);
});

test('agoLabel: today / yesterday / n days ago buckets', () => {
  const nowMs = 10 * DAY;
  assert.deepEqual(agoLabel(nowMs - 3600_000, nowMs), { key: 'recap.ago.today' });
  assert.deepEqual(agoLabel(nowMs - DAY, nowMs), { key: 'recap.ago.yesterday' });
  assert.deepEqual(agoLabel(nowMs - 3 * DAY, nowMs), { key: 'recap.ago.days', vars: { n: 3 } });
});

// ── POLISH-J: end-card highlights + v4-recap2 strings ───────────────────────

test('v4-recap2 strings: EN/DE parity + a short chip label per catalog id', () => {
  assert.deepEqual(Object.keys(R2_EN).sort(), Object.keys(R2_DE).sort());
  for (const row of STAT_CATALOG) {
    assert.equal(typeof R2_EN[`recap2.stat.${row.id}`], 'string', `EN label '${row.id}'`);
    assert.equal(typeof R2_DE[`recap2.stat.${row.id}`], 'string', `DE label '${row.id}'`);
  }
  assert.match(R2_EN['recap2.endcard.song'], /\{name\}/);
  assert.match(R2_DE['recap2.endcard.song'], /\{name\}/);
  assert.equal(typeof R2_EN['recap2.endcard.highlights'], 'string');
  assert.equal(typeof R2_DE['recap2.endcard.highlights'], 'string');
});

test('HIGHLIGHT_ICONS: an icon for every STAT_CATALOG id', () => {
  for (const row of STAT_CATALOG) {
    assert.ok(HIGHLIGHT_ICONS[row.id], `icon for '${row.id}'`);
  }
});

test('endCardHighlights: top-3 by weight then value; days/zeros excluded', () => {
  const lines = [
    { id: 'days', value: 3 }, { id: 'games', value: 12 },
    { id: 'coinsEarned', value: 420 }, { id: 'tickles', value: 27 },
    { id: 'feeds', value: 0 }, { id: 'washes', value: 6 },
  ];
  const hl = endCardHighlights(lines, 3);
  // games (w10) first; coinsEarned vs tickles are both w9 → value decides
  assert.deepEqual(hl.map((h) => h.id), ['games', 'coinsEarned', 'tickles']);
  assert.equal(hl[0].value, 12);
  assert.ok(hl.every((h) => typeof h.icon === 'string' && h.icon.length > 0));
  assert.deepEqual(endCardHighlights(lines, 3), hl, 'deterministic');
  assert.equal(endCardHighlights(lines, 2).length, 2);
  assert.deepEqual(endCardHighlights([{ id: 'days', value: 9 }]), []);
  assert.deepEqual(endCardHighlights([{ id: 'games', value: 0 }]), []);
  assert.deepEqual(endCardHighlights(undefined), []);
});

test('POLISH-J marker pins: overlay chips/letterbox/biome chip + CSS ship', () => {
  const overlay = readFileSync(join(ROOT, 'src/ui/recapOverlay.js'), 'utf8');
  assert.match(overlay, /endCardHighlights\(s\.lines, 3\)/);
  assert.match(overlay, /showBiomeChip\(cue\.biome\)/);
  assert.match(overlay, /g64-cine/);
  assert.match(overlay, /markRecapHeard/); // POLISH-H completion write intact
  const css = readFileSync(join(ROOT, 'src/ui/styles.css'), 'utf8');
  assert.match(css, /\.g64-biome/);
  assert.match(css, /\.g64-hl-chip/);
  assert.match(css, /\.g64-bar-top/);
  assert.match(css, /\.g64-end-coins/);
});

// ── trigger guard (§C-SYS2.1: never mid-gameplay) ───────────────────────────

test('canAutoStart: only a pending recap on a quiet home scene may start', () => {
  const ok = { pendingLevel: 10, sceneId: 'home', switching: false, activeScreenId: null, playing: false };
  assert.equal(canAutoStart(ok), true);
  assert.equal(canAutoStart({ ...ok, pendingLevel: 0 }), false);
  assert.equal(canAutoStart({ ...ok, sceneId: 'minigame' }), false);
  assert.equal(canAutoStart({ ...ok, switching: true }), false);
  assert.equal(canAutoStart({ ...ok, activeScreenId: 'profile' }), false);
  assert.equal(canAutoStart({ ...ok, playing: true }), false);
});

// ── §A2 offset recorder ─────────────────────────────────────────────────────

test('createOffsetRecorder: rows + summary against the ±80 ms budget', () => {
  const rec = createOffsetRecorder();
  rec.record('text', 3, 10.0, 10.012);
  rec.record('cut', 4, 12.0, 12.1); // 100 ms — outside budget
  const sum = rec.summary();
  assert.equal(sum.n, 2);
  assert.equal(sum.maxAbsMs, 100);
  assert.equal(sum.within, 1);
  assert.equal(sum.budgetMs, OVERLAY.BEAT_BUDGET_MS);
  assert.equal(rec.rows()[0].offsetMs, 12);
});

// ── shared-file marker pins (§E0.1-10 verify protocol) ──────────────────────

test('marker pins: main.js / profileScreen.js / styles.css carry the G64 blocks', () => {
  const main = readFileSync(join(ROOT, 'src/main.js'), 'utf8');
  assert.match(main, /V4\/G64: recap cinematic player/);
  assert.match(main, /end V4\/G64 block/);
  const profile = readFileSync(join(ROOT, 'src/ui/profileScreen.js'), 'utf8');
  assert.match(profile, /data-g64-replay/);
  assert.match(profile, /recap\.profile\.title/);
  const css = readFileSync(join(ROOT, 'src/ui/styles.css'), 'utf8');
  assert.match(css, /V4\/G64 — recap cinematic overlay/);
  assert.match(css, /end V4\/G64/);
  assert.match(css, /\.g64-skip[\s\S]*?font-size: 0\.8125rem/); // §C-SYS2.2 13 px
});

test('OVERLAY constants: §C-SYS2 numbers pinned', () => {
  assert.equal(OVERLAY.WHITE_FADE_MS, 400);
  assert.equal(OVERLAY.EXIT_FADE_MS, 500);
  assert.equal(OVERLAY.SKIP_CUT_MS, 300);
  assert.equal(OVERLAY.SKIP_FADE_IN_MS, 1000);
  assert.equal(OVERLAY.SKIP_OPACITY, 0.4);
  assert.equal(OVERLAY.BEAT_BUDGET_MS, 80);
});

// ── V6/B1 — landscape presentation (PLAN6 Wave B/B1) ────────────────────────

test('V6/B1 rotatedFrame: 390×844 phone → 844×390 layer, insets re-mapped', () => {
  // player turns the phone counter-clockwise (home indicator right): the
  // notch (physical top) becomes the rotated layer's LEFT edge, the home bar
  // its RIGHT, physical right→top, physical left→bottom.
  const f = rotatedFrame({
    width: 390, height: 844,
    insets: { top: 59, right: 0, bottom: 34, left: 0 },
  });
  assert.deepEqual(f, {
    rw: 844, rh: 390,
    rsafe: { left: 59, right: 34, top: 0, bottom: 0 },
  });
  const g = rotatedFrame({
    width: 390, height: 844,
    insets: { top: 1, right: 2, bottom: 3, left: 4 },
  });
  assert.deepEqual(g.rsafe, { left: 1, top: 2, right: 3, bottom: 4 });
});

test('V6/B1 rotatedFrame: integer px only, junk folds to 0', () => {
  const f = rotatedFrame({
    width: 390.6, height: 843.2,
    insets: { top: 58.7, right: -3, bottom: 'x', left: undefined },
  });
  assert.deepEqual(f, {
    rw: 843, rh: 391,
    rsafe: { left: 59, right: 0, top: 0, bottom: 0 },
  });
  assert.deepEqual(rotatedFrame(), { rw: 0, rh: 0, rsafe: { left: 0, right: 0, top: 0, bottom: 0 } });
  assert.deepEqual(rotatedFrame(undefined).rsafe, { left: 0, right: 0, top: 0, bottom: 0 });
});

test('V6/B1 shouldRotate: portrait-only; reduced motion keeps portrait', () => {
  assert.equal(shouldRotate({ reducedMotion: false, width: 390, height: 844 }), true);
  assert.equal(shouldRotate({ reducedMotion: true, width: 390, height: 844 }), false, 'reduced-motion fallback');
  assert.equal(shouldRotate({ reducedMotion: false, width: 1280, height: 800 }), false, 'landscape window never double-rotates');
  assert.equal(shouldRotate({ reducedMotion: false, width: 800, height: 800 }), false, 'square = not portrait');
  assert.equal(shouldRotate({ reducedMotion: false, width: 0, height: 844 }), false, 'zero width');
  assert.equal(shouldRotate(), false);
});

test('V6/B1 createRotationGuard: idempotent apply/restore pairs, balanced()', () => {
  const g = createRotationGuard();
  assert.equal(g.active(), false);
  assert.equal(g.balanced(), true, 'fresh guard is balanced');
  assert.equal(g.restore(), false, 'restore before apply is a no-op');
  assert.equal(g.apply(), true);
  assert.equal(g.apply(), false, 'double apply is a no-op');
  assert.equal(g.active(), true);
  assert.equal(g.balanced(), false, 'active ≠ balanced');
  assert.equal(g.restore(), true);
  assert.equal(g.restore(), false, 'double restore is a no-op (dispose + finish)');
  assert.equal(g.active(), false);
  assert.equal(g.balanced(), true, 'a restore for every apply');
  assert.deepEqual(g.counts(), { applies: 1, restores: 1 });
  // a second cinematic on the same guard keeps the invariant
  g.apply();
  g.restore();
  assert.equal(g.balanced(), true);
  assert.deepEqual(g.counts(), { applies: 2, restores: 2 });
});

test('V6/B1 restore-on-exit pins: every exit path un-rotates (source scan)', () => {
  const overlay = readFileSync(join(ROOT, 'src/ui/recapOverlay.js'), 'utf8');
  // apply happens once, behind the entry white, after scene-mode resolution
  assert.match(overlay, /applyLandscape\(s\);\r?\n {2}try \{/);
  // finish path: restore BEHIND the opaque exit white, before the home switch
  assert.match(
    overlay,
    /await fadeWhite\(s\.dom\.white, 1, OVERLAY\.EXIT_FADE_MS\);[\s\S]{0,400}?restoreLandscape\(s\);/,
    'finishRecap restores behind the exit white'
  );
  // error path: a failed start rethrows AFTER restoring
  assert.match(overlay, /restoreLandscape\(s\);\r?\n {4}throw err;/, 'startCinematic error path restores');
  // scene-dispose path: any switch away from the recap scene restores too
  assert.match(overlay, /if \(sess\) restoreLandscape\(sess\);/, 'recap scene dispose restores');
  // live re-asserts (sceneManager.onResize re-applies portrait sizes) hooked
  // AND unhooked as a pair
  assert.match(overlay, /window\.addEventListener\('resize', reassert\)/);
  assert.match(overlay, /document\.addEventListener\('visibilitychange', reassert\)/);
  assert.match(overlay, /window\.removeEventListener\('resize', reassert\)/);
  assert.match(overlay, /document\.removeEventListener\('visibilitychange', reassert\)/);
  // renderer swap + symmetric restore (JS px — never 100vw/vh)
  assert.match(overlay, /renderer\?\.setSize\?\.\(rw, rh\)/, 'landscape renderer swap');
  assert.match(overlay, /renderer\?\.setSize\?\.\(window\.innerWidth, window\.innerHeight\)/, 'portrait restore');
  // reduced-motion gate + the portrait-only decision ride the session
  assert.match(overlay, /reducedMotion: prefersReducedMotion\(\)/);
  // injected sheet (styles.css untouched this wave): root + canvas both rotate
  assert.match(overlay, /data-owner="v6-b1-recap-landscape"/);
  assert.match(overlay, /\.g64-root\.g64-landscape \{[^}]*transform: rotate\(90deg\) translateY\(-100%\)/);
  assert.match(overlay, /canvas\.g64-landscape-canvas \{[^}]*transform: rotate\(90deg\) translateY\(-100%\)/);
  // rotated safe-area vars flow into the skip/caption/debug chrome
  for (const cls of ['g64-stage', 'g64-pops', 'g64-skip', 'g64-biome', 'g64-debug']) {
    assert.match(overlay, new RegExp(`\\.g64-root\\.g64-landscape \\.${cls}`), `${cls} landscape override`);
  }
  assert.match(overlay, /--rsafe-top/);
});

test('V6/B1 scene-settle pin: a swallowed switchTo never leaves sceneMode over a foreign scene', () => {
  const overlay = readFileSync(join(ROOT, 'src/ui/recapOverlay.js'), 'utf8');
  // switchTo resolves even when SWALLOWED (switch in flight) — the recap must
  // verify it truly landed (framework launch-retry pattern) BEFORE the
  // landscape swap can touch the renderer, else fall back to DOM backdrops.
  assert.match(
    overlay,
    /sceneManager\.currentId\(\) === 'recap' && sceneManager\.isSwitching\?\.\(\) !== true/,
    'settled() checks currentId + isSwitching'
  );
  assert.match(overlay, /OVERLAY\.SCENE_SETTLE_MAX_MS/, 'bounded retry deadline');
  assert.match(overlay, /OVERLAY\.SCENE_SETTLE_POLL_MS/, 'retry poll cadence');
  // the retry lives INSIDE the try — failure routes to the DOM fallback
  assert.match(
    overlay,
    /if \(!settled\(\)\) throw new Error\([\s\S]{0,200}?catch \(err\) \{\r?\n {6}console\.warn\('\[recap\] scene switch failed — DOM fallback:', err\);/,
    'unsettled switch falls back to DOM mode'
  );
  assert.equal(typeof OVERLAY.SCENE_SETTLE_POLL_MS, 'number');
  assert.equal(typeof OVERLAY.SCENE_SETTLE_MAX_MS, 'number');
  assert.ok(OVERLAY.SCENE_SETTLE_MAX_MS > OVERLAY.SCENE_SETTLE_POLL_MS);
});

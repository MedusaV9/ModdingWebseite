// V4/FIX-GA regression suite — pins the fix-agent A defects (2-model eval):
//   1. carrotCatch: the 30 s onboarding tutorial ran the full 60 s while its
//      HUD timer hit 0 at 30 s — timed rounds must end at the durationSec
//      override the framework passes.
//   2. bubblePop: the target banner clipped long (DE) food names in its fixed
//      512×112 canvas and slid under the SCORE/TIME HUD chips — the font now
//      fits-to-width and the pill clears the chip row.
//   3. carrotGuard: the mallet's ground moment sat ~1.2 wu right of the
//      bonked mole — the pivot math must land the head ON the tapped mole.
// Pure modules only (§B rule): the .logic.js siblings carry the frozen
// constants + audit surfaces; game-file wiring is pinned via source scans.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import {
  CATCH,
  applyDifficulty as applyCatchDifficulty,
  isCatchRoundOver,
} from '../src/minigames/games/carrotCatch.logic.js';
import {
  BANNER_FIT,
  fitBannerFontPx,
  bannerCenterY,
} from '../src/minigames/games/bubblePop.logic.js';
import {
  MALLET,
  malletPivotFor,
  malletHeadAt,
} from '../src/minigames/games/carrotGuard.logic.js';

function gameSource(id) {
  return readFileSync(
    fileURLToPath(new URL(`../src/minigames/games/${id}.js`, import.meta.url)),
    'utf8'
  );
}

// ---------------------------------------------------------------------------
// 1 — carrotCatch: timed rounds honor the durationSec override (§C8.1 tutorial)
// ---------------------------------------------------------------------------

test('FIX-GA carrotCatch: a 30 s durationSec override ends the round at 30 s', () => {
  assert.equal(isCatchRoundOver({ elapsed: 29.99, missedCarrots: 0 }, CATCH, 30), false);
  assert.equal(isCatchRoundOver({ elapsed: 30, missedCarrots: 0 }, CATCH, 30), true);
  // arcade rounds without an override still end at the tune's DURATION_SEC
  assert.equal(CATCH.DURATION_SEC, 60);
  assert.equal(isCatchRoundOver({ elapsed: 59.99, missedCarrots: 0 }, CATCH), false);
  assert.equal(isCatchRoundOver({ elapsed: 60, missedCarrots: 0 }, CATCH), true);
});

test('FIX-GA carrotCatch: Endlos still ends on missed carrots, never on the override', () => {
  const endless = applyCatchDifficulty(CATCH, 'endless');
  assert.equal(isCatchRoundOver({ elapsed: 999, missedCarrots: 2 }, endless, 30), false);
  assert.equal(isCatchRoundOver({ elapsed: 1, missedCarrots: 3 }, endless, 30), true);
});

test('FIX-GA carrotCatch: the game loop consults this.durationSec for round end', () => {
  const src = gameSource('carrotCatch');
  assert.match(
    src,
    /isCatchRoundOver\(\s*\{ elapsed, missedCarrots: this\.missedCarrots \},\s*this\.tune,\s*this\.durationSec\s*\)/,
    'carrotCatch.js must pass its per-run duration into isCatchRoundOver'
  );
});

// ---------------------------------------------------------------------------
// 2 — bubblePop: banner fit-to-width + HUD chip clearance
// ---------------------------------------------------------------------------

test('FIX-GA bubblePop: banner font shrinks until long labels fit the pill', () => {
  // synthetic monotone width model: width scales linearly with font px
  const widthFor = (label) => (px) => label.length * px * 0.62;
  assert.equal(
    fitBannerFontPx(widthFor('▲ Pop: Carrot')),
    BANNER_FIT.BASE_FONT_PX,
    'short labels keep the base size'
  );
  const longest = '★ Zerplatze: Streusel-Donut'; // worst live DE label
  const px = fitBannerFontPx(widthFor(longest));
  assert.ok(px < BANNER_FIT.BASE_FONT_PX, 'long labels shrink');
  assert.ok(px >= BANNER_FIT.MIN_FONT_PX, 'never below the readability floor');
  assert.ok(
    widthFor(longest)(px) <= BANNER_FIT.MAX_TEXT_W,
    'the fitted label fits MAX_TEXT_W'
  );
  // pathological measures clamp at the floor instead of looping forever
  assert.equal(fitBannerFontPx(() => 10_000), BANNER_FIT.MIN_FONT_PX);
  // the fit budget leaves the pill's rounded caps inside the 512 canvas
  assert.ok(BANNER_FIT.MAX_TEXT_W <= BANNER_FIT.CANVAS_W - 40);
});

test('FIX-GA bubblePop: banner pill clears the SCORE/TIME HUD chip row', () => {
  const halfH = Math.tan((45 / 2) * Math.PI / 180) * 10; // frustum at the z=0 play plane
  for (const hPx of [568, 667, 800, 926, 1080]) {
    const y = bannerCenterY(halfH, hPx);
    const topGapWu = halfH - (y + BANNER_FIT.SPRITE_HALF_H);
    const topGapPx = (topGapWu / (2 * halfH)) * hPx;
    assert.ok(
      topGapPx >= BANNER_FIT.HUD_CLEAR_PX - 0.5,
      `${hPx}px viewport: banner top edge ${topGapPx}px from top < ${BANNER_FIT.HUD_CLEAR_PX}px chip row`
    );
    assert.ok(y > 0, `${hPx}px viewport: banner stays in the upper half`);
  }
});

test('FIX-GA bubblePop: the game draws the banner through the fit helpers', () => {
  const src = gameSource('bubblePop');
  assert.match(src, /fitBannerFontPx\(/, 'bubblePop.js must fit the label width');
  assert.match(src, /bannerCenterY\(/, 'bubblePop.js must place the pill below the HUD chips');
  assert.ok(!/'900 52px/.test(src), 'the hardcoded 52 px banner font is gone');
});

// ---------------------------------------------------------------------------
// 3 — carrotGuard: mallet impact on-target + impact-synced feedback
// ---------------------------------------------------------------------------

test('FIX-GA carrotGuard: the mallet head lands ON the tapped mole at impact', () => {
  // 3×3 mound grid extremes + center (GRID_SPACING 1.5, z offset −0.3)
  for (const [x, z] of [[-1.5, -1.8], [0, -0.3], [1.5, 1.2]]) {
    const pivot = malletPivotFor(x, z);
    const impact = malletHeadAt(pivot, MALLET.IMPACT_ANGLE);
    assert.ok(Math.abs(impact.x - x) < 1e-9, `head x ${impact.x} lands on mole x ${x}`);
    assert.ok(impact.y > 0.3 && impact.y < 0.7, `head height ${impact.y} bonks the mole body`);
    assert.ok(Math.abs(pivot.z - z - MALLET.PIVOT_DZ) < 1e-9, 'pivot stays on the mole row');
    // the wind-up pose starts up and away so the slam visibly falls onto it
    const raised = malletHeadAt(pivot, MALLET.RAISED_ANGLE);
    assert.ok(raised.y > impact.y + 0.25, 'raised head is clearly above the impact point');
    assert.ok(Math.abs(raised.x - x) > 0.4, 'raised head is off the mole before the slam');
  }
  // the squash/stars/sfx now ride the down-swing completion — keep it a slam
  assert.ok(MALLET.DOWN_SEC <= 0.15, 'down-swing stays fast enough to read as the tap');
});

test('FIX-GA carrotGuard: impact feedback fires from the down-swing completion', () => {
  const src = gameSource('carrotGuard');
  assert.match(src, /swingMallet\(pos, \(\) => \{/, 'bonk feedback is an impact callback');
  assert.match(src, /malletPivotFor\(pos\.x, pos\.z\)/, 'the swing uses the on-target pivot');
  assert.ok(!/mallet\.position\.set\(pos\.x \+ 0\.3/.test(src), 'the old off-target pivot is gone');
});

test('FIX-GA carrotGuard: fence runs span ±3.3 so the ring corners close', () => {
  const src = gameSource('carrotGuard');
  assert.match(src, /const FENCE_SEG = 1\.32;/);
  assert.match(src, /fenceAt\(i \* FENCE_SEG, -3\.3, 0\)/);
  assert.match(src, /fenceAt\(3\.3, i \* FENCE_SEG, Math\.PI \/ 2\)/);
  // 5 segments × 1.32 = 6.6 wu — each run reaches the perpendicular ±3.3 line
  assert.ok(Math.abs(5 * 1.32 - 6.6) < 1e-9);
});

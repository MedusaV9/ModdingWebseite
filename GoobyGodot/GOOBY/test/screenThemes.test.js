// V6/A2 — screen-theme + slow-drift motion contract (PLAN6 Wave A / A2).
// Pure node:test, no DOM/three: derives the registered DOM screen ids by
// parsing the source (registerScreen('<id>' call sites — the same
// source-scanning style test/coreux.test.js and test/onboarding.test.js use)
// and then asserts the V6/A2 THEMES block in src/ui/styles.css upholds the
// binding contract:
//   - exactly ONE theme assignment per registered screen id;
//   - every referenced pattern token resolves to a committed acui tile;
//   - each of the 11 new pattern PNGs is a 512×512 indexed tile ≤48 KiB,
//     aggregate ≤512 KiB, with every palette entry within a 6 % luminance
//     delta of the base color (palette[0]) — PLAN6 hard budget guardrails;
//   - the drift is transform-only (no background-position/filter animation,
//     no calc() length multiplication), 80–120 s linear infinite, drift
//     offsets are explicit ±one-tile lengths, and reduced motion freezes it.

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');

// ---------------------------------------------------------------------------
// Source-derived screen registry
// ---------------------------------------------------------------------------

/** @param {string} dir @returns {string[]} all .js files under dir */
function walkJs(dir) {
  const out = [];
  for (const entry of readdirSync(dir)) {
    const p = join(dir, entry);
    if (statSync(p).isDirectory()) out.push(...walkJs(p));
    else if (entry.endsWith('.js')) out.push(p);
  }
  return out;
}

/** @returns {string[]} sorted registered DOM screen ids (registerScreen('id') */
function registeredScreenIds() {
  const ids = new Set();
  for (const file of walkJs(join(ROOT, 'src'))) {
    const src = readFileSync(file, 'utf8');
    for (const m of src.matchAll(/\bregisterScreen\(\s*'([^']+)'/g)) ids.add(m[1]);
  }
  return [...ids].sort();
}

// ---------------------------------------------------------------------------
// V6/A2 THEMES block extraction + tiny rule scanner
// ---------------------------------------------------------------------------

const css = readFileSync(join(ROOT, 'src/ui/styles.css'), 'utf8');

/** @returns {string} the V6/A2 THEMES block (comments stripped) */
function themesBlock() {
  const start = css.indexOf('V6/A2 THEMES —');
  const end = css.indexOf('end V6/A2 THEMES');
  assert.ok(start >= 0 && end > start, 'V6/A2 THEMES block markers missing in styles.css');
  return css
    .slice(start, end)
    .replace(/\/\*[\s\S]*?\*\//g, ' '); // strip comments (keeps prose out of the regexes)
}

/**
 * Flat `selector { body }` pairs of the block, at-rules skipped.
 * @returns {Array<{selector: string, body: string}>}
 */
function flatRules(block) {
  const rules = [];
  // strip @media / @keyframes wrappers (single nesting level is enough here)
  const flat = block.replace(/@(media|keyframes)[^{]*\{(?:[^{}]*\{[^{}]*\})*[^{}]*\}/g, ' ');
  for (const m of flat.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
    rules.push({ selector: m[1].trim(), body: m[2] });
  }
  return rules;
}

/** True when a rule body DECLARES a --thm-* custom property (var() reads don't count). */
function declaresThm(body) {
  return /(?:^|[;\s])--thm-[a-z-]+\s*:/.test(body);
}

// ---------------------------------------------------------------------------
// PNG chunk parsing (IHDR dimensions + PLTE palette — no inflate needed)
// ---------------------------------------------------------------------------

/**
 * @param {Buffer} buf complete PNG file
 * @returns {{w: number, h: number, colorType: number, palette: Array<[number, number, number]>}}
 */
function pngInfo(buf) {
  assert.equal(buf.readUInt32BE(0), 0x89504e47, 'bad PNG signature');
  let pos = 8;
  const info = { w: 0, h: 0, colorType: -1, palette: [] };
  while (pos + 12 <= buf.length) {
    const len = buf.readUInt32BE(pos);
    const type = buf.toString('ascii', pos + 4, pos + 8);
    if (type === 'IHDR') {
      info.w = buf.readUInt32BE(pos + 8);
      info.h = buf.readUInt32BE(pos + 12);
      info.colorType = buf[pos + 17];
    } else if (type === 'PLTE') {
      for (let i = 0; i < len / 3; i++) {
        info.palette.push([buf[pos + 8 + i * 3], buf[pos + 8 + i * 3 + 1], buf[pos + 8 + i * 3 + 2]]);
      }
    } else if (type === 'IEND') break;
    pos += 12 + len;
  }
  return info;
}

/** Rec. 709 luma (0–255). @param {[number, number, number]} c */
function luma(c) {
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}

/** The 11 committed V6/A2 tiles (PLAN6 A2 owned files). */
const PATTERN_FILES = [
  'pattern_shop.png', 'pattern_wardrobe.png', 'pattern_arcade.png',
  'pattern_quest.png', 'pattern_album.png', 'pattern_passport.png',
  'pattern_clinic.png', 'pattern_radio.png', 'pattern_trophy.png',
  'pattern_credits.png', 'pattern_blueprint.png',
];

// ---------------------------------------------------------------------------
// Registry ↔ theme assignments
// ---------------------------------------------------------------------------

test('V6/A2: every registered screen id has exactly ONE theme assignment', () => {
  const ids = registeredScreenIds();
  assert.ok(ids.length >= 15, `expected ≥15 registered screens, found ${ids.length}`);
  const assignments = flatRules(themesBlock()).filter((r) => declaresThm(r.body));
  for (const id of ids) {
    const hits = assignments.filter((r) =>
      new RegExp(`\\.screen-${id}(?![\\w-])`).test(r.selector));
    assert.equal(hits.length, 1,
      `screen '${id}' must have exactly one theme assignment, found ${hits.length}`);
  }
});

test('V6/A2: every themed screen also carries the drifting pattern layer', () => {
  const block = themesBlock();
  const driftRule = flatRules(block).find((r) =>
    r.selector.includes('::before') && r.body.includes('thm-drift'));
  assert.ok(driftRule, 'drifting ::before rule missing');
  for (const id of registeredScreenIds()) {
    assert.ok(driftRule.selector.includes(`.screen-${id}::before`),
      `screen '${id}' missing from the drift layer selector list`);
  }
  assert.match(driftRule.body, /animation:\s*thm-drift var\(--thm-drift-dur\) linear infinite/,
    'drift layer must run thm-drift via var(--thm-drift-dur) linear infinite');
});

test('V6/A2: every referenced pattern token resolves to a committed acui tile', () => {
  const block = themesBlock();
  const tokens = new Set();
  for (const m of block.matchAll(/--thm-pattern:\s*var\(--pattern-([a-z]+)\)/g)) tokens.add(m[1]);
  assert.ok(tokens.size >= 12, `expected ≥12 distinct pattern tokens, got ${tokens.size}`);
  for (const token of tokens) {
    // --pattern-leaf (the neutral default) is declared in the base :root;
    // the V6/A2 tokens are declared inside the block — accept either.
    const decl = css.match(new RegExp(`--pattern-${token}:\\s*url\\('([^']+)'\\)`));
    assert.ok(decl, `--pattern-${token} has no url() declaration in styles.css`);
    const rel = decl[1].replace(/^\//, '');
    assert.doesNotThrow(() => statSync(join(ROOT, 'public', rel)),
      `pattern file public/${rel} missing`);
  }
});

// ---------------------------------------------------------------------------
// Pattern budget + contrast (PLAN6 hard budget guardrails)
// ---------------------------------------------------------------------------

test('V6/A2: each pattern tile is a 512×512 indexed PNG ≤48 KiB, aggregate ≤512 KiB', () => {
  let total = 0;
  for (const name of PATTERN_FILES) {
    const p = join(ROOT, 'public/assets/acui', name);
    const bytes = statSync(p).size;
    assert.ok(bytes <= 48 * 1024, `${name} is ${bytes} B > 48 KiB`);
    total += bytes;
    const info = pngInfo(readFileSync(p));
    assert.equal(info.w, 512, `${name} width ${info.w} ≠ 512`);
    assert.equal(info.h, 512, `${name} height ${info.h} ≠ 512`);
    assert.equal(info.colorType, 3, `${name} not indexed (color type ${info.colorType})`);
  }
  assert.ok(total <= 512 * 1024, `pattern aggregate ${total} B > 512 KiB`);
});

test('V6/A2: pattern palettes stay within a 6 % luminance delta of the base', () => {
  for (const name of PATTERN_FILES) {
    const { palette } = pngInfo(readFileSync(join(ROOT, 'public/assets/acui', name)));
    assert.ok(palette.length > 0, `${name} has no PLTE palette`);
    const base = luma(palette[0]);
    for (const c of palette) {
      const delta = Math.abs(luma(c) - base);
      assert.ok(delta <= 0.06 * 255,
        `${name}: palette entry rgb(${c}) delta ${delta.toFixed(1)} > 6 % of 255`);
    }
  }
});

// ---------------------------------------------------------------------------
// Motion contract
// ---------------------------------------------------------------------------

test('V6/A2: thm-drift keyframes are transform-only, no calc() multiplication', () => {
  const block = themesBlock();
  const kf = block.match(/@keyframes\s+thm-drift\s*\{([\s\S]*?)\}\s*\}/);
  assert.ok(kf, '@keyframes thm-drift missing from the V6/A2 block');
  const body = kf[1];
  for (const decl of body.matchAll(/([a-z-]+)\s*:/g)) {
    assert.equal(decl[1], 'transform',
      `thm-drift animates '${decl[1]}' — only transform is allowed`);
  }
  assert.ok(!body.includes('calc('), 'thm-drift must not calc()-multiply lengths');
  assert.match(body, /translate3d\(var\(--thm-drift-x\), var\(--thm-drift-y\), 0\)/,
    'thm-drift must translate by the explicit drift variables');
  for (const banned of ['background-position', 'filter', 'opacity', 'background']) {
    assert.ok(!body.includes(banned), `thm-drift must not animate ${banned}`);
  }
});

test('V6/A2: drift durations sit in the 80–120 s window', () => {
  const durs = [...themesBlock().matchAll(/--thm-drift-dur:\s*(\d+(?:\.\d+)?)s/g)]
    .map((m) => Number(m[1]));
  assert.ok(durs.length >= 12, `expected ≥12 --thm-drift-dur declarations, got ${durs.length}`);
  for (const d of durs) {
    assert.ok(d >= 80 && d <= 120, `--thm-drift-dur ${d}s outside 80–120 s`);
  }
});

test('V6/A2: drift offsets are explicit ±one-tile lengths (24rem)', () => {
  const block = themesBlock();
  const offsets = [...block.matchAll(/--thm-drift-[xy]:\s*([^;]+);/g)].map((m) => m[1].trim());
  assert.ok(offsets.length >= 2, 'drift offset declarations missing');
  for (const v of offsets) {
    assert.match(v, /^-?24rem$/, `drift offset '${v}' must be exactly ±24rem (one tile)`);
  }
  for (const m of block.matchAll(/--thm-pattern-size:\s*([^;]+);/g)) {
    assert.equal(m[1].trim(), '24rem', 'pattern size must stay one 24rem tile period');
  }
});

test('V6/A2: no background-position animation anywhere in the block; reduced motion freezes the drift', () => {
  const block = themesBlock();
  assert.ok(!block.includes('background-position'),
    'the V6/A2 block must never touch background-position');
  const media = block.match(/@media\s*\(prefers-reduced-motion:\s*reduce\)\s*\{([\s\S]*?)\}\s*\}/);
  assert.ok(media, 'prefers-reduced-motion freeze missing from the V6/A2 block');
  assert.match(media[1], /\.screen::before\s*\{\s*animation:\s*none/,
    'reduced motion must set animation: none on the pattern layer');
});

// ---------------------------------------------------------------------------
// Kit accent re-pointing (extend, don't rename — leaf fallbacks intact)
// ---------------------------------------------------------------------------

test('V6/A2: kit accent re-pointing keeps the leaf fallback on every frozen selector', () => {
  const block = themesBlock();
  for (const selector of ['.ac-tab.ac-tab-active', ".ac-tab[aria-selected='true']", '.ac-chip.ac-chip-leaf', '.ac-ribbon', '.btn.btn-leaf']) {
    assert.ok(block.includes(selector), `accent re-pointing missing for ${selector}`);
  }
  const repointed = flatRules(block).filter((r) => r.selector.includes('.ac-') || r.selector.includes('.btn.btn-leaf'));
  assert.ok(repointed.length >= 3, 'kit re-pointing rules missing');
  for (const r of repointed) {
    for (const m of r.body.matchAll(/var\(--thm-accent(?:-dark)?\s*(\)?)/g)) {
      assert.equal(m[1], '', `${r.selector}: --thm-accent must carry a leaf fallback`);
    }
    assert.match(r.body, /var\(--thm-accent, var\(--leaf\)\)|var\(--thm-accent-dark, var\(--leaf-dark\)\)/,
      `${r.selector}: kit fill must fall back to the AC-1 leaf`);
  }
});

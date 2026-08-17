// V3/G33 — §B3 px-audit grep-gate. Fails (exit 1) on `px` values in
// font-size/padding/margin/gap/border-radius declarations inside UI CSS:
// `src/ui/styles.css` plus every component-injected CSS string in the
// SCAN_DIRS modules. The rem sweep (§B3: px → rem ÷16) made the DOM UI scale
// with `settings.uiScale`; new px declarations in these properties would
// silently opt out of scaling.
//
// V6/F3 widening: the walk now recurses over src/ui, src/home, src/character,
// src/city and src/minigames (style-injecting modules live outside src/ui —
// the CARE_CSS/CONTROLS_CSS/PANEL_CSS islands were invisible to the V3 gate),
// and the extractor also catches injected stylesheets assigned directly to a
// <style> element (`fooStyle.textContent = `…``, the hud.js pattern) instead
// of only `const *CSS* = `…`` literals. The audit core is exported so
// test/miscQuality.test.js runs it in-process as a regression gate.
//
// Allowed (the §B3 exemption list):
//   - 0px / 1px (hairlines) / 999px (pill radii)
//   - the 44 px real-px tap-target floor inside max(44px, …) (§B3)
//   - env(safe-area-inset-*, 0px) fallbacks (§B9)
//   - CSS comments (historical numbers stay verbatim)
//   - box-shadow/text-shadow/filter/transform values (not in checked props)
//   - @media breakpoints (queries, not declarations)
//   - FILE_ALLOW entries below (justify every addition — §E0.1-5; G47 may
//     extend for §C11.2 border-image slice values)
//
// Usage: npm run px-audit   (add to your pre-commit verification — §E0)

import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');

/** Standalone stylesheets audited verbatim. */
export const CSS_FILES = ['src/ui/styles.css'];

/** Directories whose *.js modules are scanned for injected CSS (V6/F3). */
export const SCAN_DIRS = ['src/ui', 'src/home', 'src/character', 'src/city', 'src/minigames'];

/** Files whose UI CSS is NOT yet swept (owner justification required). */
export const FILE_ALLOW = new Set([
  // (empty — V6/F3 swept the last two islands, city/carController.js'
  // CONTROLS_CSS and character/showcase.js' PANEL_CSS; keep it empty.)
]);

/** Properties gated by §B3 (px here breaks uiScale scaling). */
const PROPS = /(?:^|[;{\s])(font-size|padding(?:-[a-z]+)?|margin(?:-[a-z]+)?|gap|row-gap|column-gap|border-radius|letter-spacing)\s*:\s*([^;}]*)/g;

/** px tokens allowed inside a checked declaration value. */
function pxAllowed(value, px) {
  const n = Number(px);
  if (n === 0 || n === 1 || n === 999) return true;
  // §B3 tap-target floor + §C1.4 safe-area shapes: max(44px, …) / max(Npx, …)
  // keep a real-px floor by design; env(…, 0px) fallbacks ride along.
  if (new RegExp(`(max|env)\\([^)]*${px}px`).test(value)) return true;
  return false;
}

/** Strip CSS comments so historical px numbers in prose don't trip the gate. */
function stripComments(css) {
  return css.replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '));
}

/** @returns {Array<{prop: string, decl: string}>} offending declarations */
export function auditCss(css) {
  const bad = [];
  const clean = stripComments(css);
  for (const m of clean.matchAll(PROPS)) {
    const [, prop, value] = m;
    for (const px of value.matchAll(/(\d*\.?\d+)px/g)) {
      if (!pxAllowed(value, px[1])) {
        bad.push({ prop, decl: `${prop}: ${value.trim()}` });
        break;
      }
    }
  }
  return bad;
}

/**
 * Extract injected-CSS string bodies from a JS module: `const *CSS* = `…``
 * template literals PLUS stylesheet text assigned straight onto a <style>
 * element (`fooStyle.textContent = `…`` / `styleEl.textContent = `…`` —
 * V6/F3; hud.js injects five sheets that way). Variable names are required
 * to contain CSS/style so plain text-label assignments never false-positive.
 * @param {string} js @returns {string[]}
 */
export function extractCssStrings(js) {
  const out = [];
  for (const m of js.matchAll(/const\s+\w*CSS\w*\s*=\s*`([\s\S]*?)`/g)) out.push(m[1]);
  for (const m of js.matchAll(/\w*[Ss]tyle\w*\.textContent\s*=\s*`([\s\S]*?)`/g)) out.push(m[1]);
  return out;
}

/** Recursively list `.js` files under a directory (sorted, repo-relative). */
function walkJs(rel) {
  const out = [];
  for (const entry of fs.readdirSync(path.join(ROOT, rel), { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    const childRel = `${rel}/${entry.name}`;
    if (entry.isDirectory()) out.push(...walkJs(childRel));
    else if (entry.name.endsWith('.js')) out.push(childRel);
  }
  return out;
}

/**
 * Run the full audit (in-process entry point for test/miscQuality.test.js).
 * @returns {Array<{file: string, prop: string, decl: string}>}
 */
export function runAudit() {
  const failures = [];
  const collect = (file, bad) => {
    for (const { prop, decl } of bad) failures.push({ file, prop, decl });
  };
  for (const cssFile of CSS_FILES) {
    collect(cssFile, auditCss(fs.readFileSync(path.join(ROOT, cssFile), 'utf8')));
  }
  for (const dir of SCAN_DIRS) {
    for (const rel of walkJs(dir)) {
      if (FILE_ALLOW.has(rel)) continue;
      const js = fs.readFileSync(path.join(ROOT, rel), 'utf8');
      for (const css of extractCssStrings(js)) collect(rel, auditCss(css));
    }
  }
  return failures;
}

// CLI gate (npm run px-audit) — skipped when imported by the test suite.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const failures = runAudit();
  for (const { file, decl } of failures) console.error(`px-audit: ${file}: ${decl}`);
  if (failures.length > 0) {
    console.error(`px-audit: FAILED — ${failures.length} px declaration(s) in UI CSS (use rem ÷16; see §B3 exemptions in scripts/px-audit.mjs)`);
    process.exit(1);
  }
  console.log('px-audit: OK — UI CSS is rem-clean (§B3)');
}

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = (relative) => fs.readFileSync(path.join(ROOT, relative), 'utf8');

test('quality: pure data and shop-trip modules import headlessly', async () => {
  const strings = await import('../src/data/strings.js');
  const trip = await import('../src/systems/shopTrip.js');
  assert.equal(strings.resolveLang('en'), 'en');
  assert.equal(strings.resolveLang('de'), 'de');
  assert.equal(typeof trip.tripTransition, 'function');
});

test('quality: browser-only shop-trip dependencies stay lazy and injected', () => {
  const trip = source('src/systems/shopTrip.js');
  assert.doesNotMatch(trip, /import\s+[^;]*from\s+['"]\.\.\/ui\//);
  assert.doesNotMatch(trip, /\bwindow\.addEventListener/);
  assert.match(trip, /eventTarget\?\.addEventListener\('gooby:shopTrip'/);

  const strings = source('src/data/strings.js');
  assert.doesNotMatch(strings, /typeof\s+navigator|\bnavigator\.language/);
  assert.match(strings, /globalThis\.navigator\?\.language/);
});

test('quality: Nougatschleuse purchase uses economy.spend', () => {
  const shop = source('src/ui/shopScreen.js');
  assert.match(shop, /spend\(store,\s*NOUGAT\.PRICE,\s*'nougatschleuse'\)/);
  assert.doesNotMatch(shop, /st\.coins\s*-=\s*NOUGAT\.PRICE/);
});

test('quality: Toy Grand Prix and Ghost Hunt forward round counters', () => {
  const racer = source('src/minigames/games/toyRacer.js');
  assert.match(racer, /\.track\?\.\('races',\s*meta\.races\)/);
  assert.match(racer, /\.track\?\.\('wins',\s*meta\.wins\)/);

  const hunt = source('src/minigames/games/ghostHunt.js');
  assert.match(hunt, /\.track\?\.\('ghostsCaught',\s*meta\.ghostsCaught\)/);
});

test('quality: orphan strings and shipped TODO/skip escape hatches are gone', () => {
  for (const file of ['src/data/strings/v3-nutella.js', 'src/data/strings/v3-surf.js']) {
    const text = source(file);
    assert.doesNotMatch(text, /nougat\.shopDesc|mg\.surf\.puddle|mg\.surf\.distance/);
  }
  assert.doesNotMatch(source('src/home/gardenInteractions.js'), /TODO\(G19/);
  assert.doesNotMatch(source('src/ui/sleepFlow.js'), /\[sleepFlow\]\s+TODO/);
  assert.doesNotMatch(source('test/assets.test.js'), /\bt\.skip\(/);
});

test('quality: one V3/G33 marked block and sticker provenance are documented', () => {
  const blocks = source('src/main.js').match(/---- V3\/G33:/g) ?? [];
  assert.equal(blocks.length, 1);

  for (const file of ['README.md', 'AGENTS.md']) {
    const text = source(file);
    assert.match(text, /28 sticker-book images are AI-generated originals/);
    assert.match(text, /CC0-equivalent/);
    assert.match(text, /no third-party IP/);
  }
});

test('quality: required Kenney models are manifest-listed and committed', () => {
  const manifest = source('scripts/kenney-manifest.mjs');
  for (const [pack, name] of [
    ['food-kit', 'chocolate'],
    ['city-kit-roads', 'light-square-double'],
  ]) {
    assert.match(manifest, new RegExp(`slug: '${pack}'[\\s\\S]*?${name}`));
    assert.ok(
      fs.existsSync(path.join(ROOT, 'public', 'assets', 'kenney', pack, `${name}.glb`)),
      `${pack}/${name}.glb is committed`
    );
  }
});

// ---- V6/F3: scale/accessibility hardening gates (PLAN6 Wave F) ------------

test('quality: widened px-audit runs in-process with zero violations', async () => {
  const audit = await import('../scripts/px-audit.mjs');
  // the walk must cover every style-injecting module family (V6/F3 widening)
  assert.deepEqual(audit.SCAN_DIRS, ['src/ui', 'src/home', 'src/character', 'src/city', 'src/minigames']);
  // no temporary allowlist left behind after the two island sweeps
  assert.equal(audit.FILE_ALLOW.size, 0);
  const failures = audit.runAudit();
  assert.deepEqual(
    failures,
    [],
    `px in uiScale-gated props: ${failures.map((f) => `${f.file}: ${f.decl}`).join('; ')}`
  );
  // both injected-CSS grammars extract: const *CSS* literals AND direct
  // <style>.textContent assignments (the hud.js pattern)
  assert.deepEqual(audit.extractCssStrings('const FOO_CSS = `a{gap:2px}`;'), ['a{gap:2px}']);
  assert.deepEqual(audit.extractCssStrings('fooStyle.textContent = `a{gap:2px}`;'), ['a{gap:2px}']);
  // the §B3 exemption grammar survives the rework (44px floors, hairlines)
  assert.equal(audit.auditCss('a{padding:max(44px, 2.75rem);}').length, 0);
  assert.equal(audit.auditCss('a{border-radius:999px;margin:1px;}').length, 0);
  assert.equal(audit.auditCss('a{gap:6px;}').length, 1);
});

test('quality: global focus-visible ring covers the interactive kit, taps stay quiet', () => {
  const css = source('src/ui/styles.css');
  const ring = css.match(/:where\(([^)]*)\):focus-visible\s*\{([^}]*)\}/);
  assert.ok(ring, 'global :focus-visible block exists');
  for (const sel of ['button', 'input', '.ac-tab', '.ac-chip']) {
    assert.ok(ring[1].includes(sel), `:focus-visible ring covers ${sel}`);
  }
  assert.match(ring[2], /outline:\s*0\.1875rem solid var\(--leaf-dark\)/);
  assert.match(ring[2], /outline-offset:\s*0\.125rem/);
  // NO plain :focus fallback may paint an outline (taps must never flash the
  // ring), and nothing may suppress it with outline:none on focus.
  const noComments = css.replace(/\/\*[\s\S]*?\*\//g, ' ');
  for (const rule of noComments.matchAll(/:focus(?!-visible)[^,{]*\{([^}]*)\}/g)) {
    assert.doesNotMatch(rule[1], /outline\s*:/, `plain :focus rule touches outline: ${rule[0]}`);
  }
});

test('quality: panel-up soft-settle bezier is pinned and reduced-motion safe', () => {
  const css = source('src/ui/styles.css');
  // plan-exact settle bezier on the sheet-open animation (PLAN6 F3 restore)
  assert.match(css, /animation:\s*panel-up[^;]*cubic-bezier\(0\.34,\s*1\.56,\s*0\.64,\s*1\)/);
  // the keyframes overshoot past rest (…→ −3px → 0) before settling
  const kf = css.match(/@keyframes panel-up\s*\{([\s\S]*?)\n\}/);
  assert.ok(kf, '@keyframes panel-up exists');
  assert.match(kf[1], /translateY\(-3px\)/);
  // the POLISH-D reduced-motion block still collapses the sheet enter
  assert.match(css, /@media \(prefers-reduced-motion: reduce\) \{\s*\.screen,\s*\.screen\.screen-out,\s*\.panel,/);
});

test('quality: drive HUD and showcase CSS are rem-swept with 44px floors intact', () => {
  const controls = source('src/city/carController.js').match(/const CONTROLS_CSS = `([\s\S]*?)`/)[1];
  // the brake button is a hit target — §B3 real-px 44px floor preserved
  assert.match(controls, /width:max\(44px, 4\.75rem\)/);
  assert.match(controls, /height:max\(44px, 4\.75rem\)/);
  // uiScale-gated declarations are rem now (44px chevron → 2.75rem etc.)
  assert.match(controls, /font-size:2\.75rem/);
  assert.doesNotMatch(controls, /font-size:\s*\d+px/);
  assert.doesNotMatch(controls, /padding:[^;]*\dpx/);

  const panel = source('src/character/showcase.js').match(/const PANEL_CSS = `([\s\S]*?)`/)[1];
  assert.doesNotMatch(panel, /(?:font-size|padding|margin|gap|border-radius):[^;]*\d{2,}px/);
});

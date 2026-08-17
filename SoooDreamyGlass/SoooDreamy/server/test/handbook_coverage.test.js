import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { readdir, readFile } from 'node:fs/promises';

const here = dirname(fileURLToPath(import.meta.url));
const appRoot = resolve(here, '../../ios/SoooDreamy');
const featureRoots = ['Stationen', 'Kino', 'Zeremonien', 'Zustelldienst']
  .map((name) => join(appRoot, name));
const resourceRoot = resolve(here, '../../ios/SoooDreamy/Resources');
const docsRoot = resolve(here, '../../../docs');

const categoryAnchor = Object.freeze({
  Kino: 'setup',
  Zeremonien: 'home',
  Zustelldienst: 'us',
  'Stationen/Postfach': 'home',
  'Stationen/Schreibstube': 'chat',
  'Stationen/Spieltisch': 'play',
  'Stationen/Archiv': 'us',
  'Stationen/Amt': 'settings',
});

async function filesUnder(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(entries.map(async (entry) => {
    const path = join(directory, entry.name);
    return entry.isDirectory() ? filesUnder(path) : [path];
  }));
  return nested.flat();
}

test('every feature view maps to a stable bilingual handbook anchor', async () => {
  const nested = await Promise.all(featureRoots.map((root) => filesUnder(root)));
  const views = nested.flat()
    .filter((path) => path.endsWith('View.swift'))
    .map((path) => relative(appRoot, path).split(sep).join('/'))
    .sort();
  assert.ok(views.length >= 61, `expected the complete feature inventory, found ${views.length}`);

  const mappings = views.map((path) => {
    const segments = path.split('/');
    const category = segments[0] === 'Stationen' ? segments.slice(0, 2).join('/') : segments[0];
    return { path, anchor: categoryAnchor[category] };
  });
  assert.deepEqual(
    mappings.filter(({ anchor }) => !anchor),
    [],
    'a new feature category needs an explicit handbook anchor',
  );

  const [deResource, enResource, deManual, enManual] = await Promise.all([
    readFile(join(resourceRoot, 'Handbook.de.md'), 'utf8'),
    readFile(join(resourceRoot, 'Handbook.en.md'), 'utf8'),
    readFile(join(docsRoot, 'HANDBUCH.de.md'), 'utf8'),
    readFile(join(docsRoot, 'MANUAL.en.md'), 'utf8'),
  ]);
  const anchors = new Set(Object.values(categoryAnchor));
  for (const anchor of anchors) {
    assert.ok(deResource.includes(`<!-- anchor:${anchor} -->`), `DE bundle missing ${anchor}`);
    assert.ok(enResource.includes(`<!-- anchor:${anchor} -->`), `EN bundle missing ${anchor}`);
    assert.ok(deManual.includes(`id="handbook-${anchor}"`), `DE manual missing ${anchor}`);
    assert.ok(enManual.includes(`id="handbook-${anchor}"`), `EN manual missing ${anchor}`);
  }
});

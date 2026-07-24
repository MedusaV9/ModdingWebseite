// AMP-Tauglichkeit: deps NUR express + ws, KEINE nativen Module (kein .node-Binary,
// kein binding.gyp im installierten Baum), keine devDependencies nötig.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

test('package.json: dependencies sind EXAKT express + ws, keine devDeps', () => {
  const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
  assert.deepEqual(Object.keys(pkg.dependencies).sort(), ['express', 'ws']);
  assert.equal(pkg.devDependencies, undefined);
  assert.equal(pkg.scripts.start, 'node server.js');
  assert.equal(pkg.scripts.test, 'node --test');
});

test('node_modules: keine nativen Artefakte (.node, binding.gyp, prebuilds)', () => {
  const nm = path.join(root, 'node_modules');
  assert.ok(fs.existsSync(nm), 'node_modules existiert (npm install gelaufen)');
  const offenders = [];
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        if (entry.name === 'prebuilds') offenders.push(full);
        else walk(full);
      } else if (entry.name.endsWith('.node') || entry.name === 'binding.gyp') {
        offenders.push(full);
      }
    }
  };
  walk(nm);
  assert.deepEqual(offenders, [], 'native Module gefunden — bricht AMP npm install');
});

test('ws: optionale native Beschleuniger (bufferutil/utf-8-validate) sind NICHT installiert', () => {
  assert.equal(fs.existsSync(path.join(root, 'node_modules', 'bufferutil')), false);
  assert.equal(fs.existsSync(path.join(root, 'node_modules', 'utf-8-validate')), false);
});

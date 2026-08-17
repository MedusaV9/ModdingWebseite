#!/usr/bin/env node
// V6/E4: fast headless placement-warning printer for the 5 home rooms — the
// tuning loop the V6 room-audit doc proposes. Wraps src/home/roomAudit.js
// (the same pure math test/roomAudit.test.js locks to ZERO warnings) so a
// placement can be nudged and re-checked in <1 s without booting the game or
// re-running the whole suite. NO three.js/DOM/CDP — plain node + the
// committed fixture.
//
// Usage:
//   node scripts/audit-rooms.mjs                 # audit all 5 rooms
//   node scripts/audit-rooms.mjs garden living   # audit a subset
//   node scripts/audit-rooms.mjs --boxes garden  # also dump the placed AABBs
//                                                # (room-local, post-transform)
//                                                # for measuring placements
//
// Exit code: 0 when every audited room is clean, 1 when any warning printed
// (so the script can gate a local pre-commit loop). Ground truth is
// test/fixtures/asset-bounds.json — REGENERATE it first (scripts/
// gen-asset-bounds.mjs, needs the dev-server + CDP recipe) whenever assets
// or the roomManager transform chain change; this script only replays it.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import process from 'node:process';

import { ROOM as KITCHEN } from '../src/home/rooms/kitchen.js';
import { ROOM as LIVING } from '../src/home/rooms/living.js';
import { ROOM as BATHROOM } from '../src/home/rooms/bathroom.js';
import { ROOM as BEDROOM } from '../src/home/rooms/bedroom.js';
import { ROOM as GARDEN } from '../src/home/rooms/garden.js';
import { auditRoom, computePlacedBoxes } from '../src/home/roomAudit.js';
import { AUDIT_RULES } from '../src/home/roomAudit.rules.js';

const DEFS = [KITCHEN, LIVING, BATHROOM, BEDROOM, GARDEN];

const FIXTURE = JSON.parse(readFileSync(
  fileURLToPath(new URL('../test/fixtures/asset-bounds.json', import.meta.url)), 'utf8'
));

const args = process.argv.slice(2);
const dumpBoxes = args.includes('--boxes');
const wanted = args.filter((a) => a !== '--boxes');
const defs = wanted.length ? DEFS.filter((d) => wanted.includes(d.id)) : DEFS;
if (!defs.length) {
  console.error(`audit-rooms: no room matches [${wanted.join(', ')}] — ids: ${DEFS.map((d) => d.id).join(', ')}`);
  process.exit(2);
}

const fmt = (v) => v.toFixed(3).replace('-0.000', '0.000');
let total = 0;
for (const def of defs) {
  const warnings = auditRoom(def, FIXTURE, AUDIT_RULES);
  total += warnings.length;
  console.log(`\n=== ${def.id} — ${warnings.length ? `${warnings.length} warning(s)` : 'CLEAN'} ===`);
  for (const w of warnings) console.log(`  [${w.type}] ${w.msg}`);

  if (dumpBoxes) {
    const boxes = computePlacedBoxes(def, FIXTURE, {
      extras: AUDIT_RULES.rooms?.[def.id]?.extras,
    });
    for (const b of boxes) {
      console.log(
        `  ${String(b.index).padEnd(20)} ${b.key.padEnd(42)}`
        + ` x ${fmt(b.min[0])}..${fmt(b.max[0])}`
        + `  y ${fmt(b.min[1])}..${fmt(b.max[1])}`
        + `  z ${fmt(b.min[2])}..${fmt(b.max[2])}`
        + `${b.flat ? '  [flat]' : ''}${b.interact ? `  tap:${b.interact}` : ''}`
      );
    }
  }
}
console.log(`\naudit-rooms: ${total === 0 ? 'ALL CLEAN' : `${total} warning(s)`} across ${defs.map((d) => d.id).join(', ')}`);
process.exit(total === 0 ? 0 : 1);

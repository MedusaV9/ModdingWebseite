#!/usr/bin/env node
/**
 * Scannt public/clips/ und schreibt src/lib/clipManifest.ts.
 *
 * Warum generiert statt Laufzeit-Check: im Browser-Bundle laesst sich die
 * Existenz einer Datei nicht synchron pruefen (und ein 404 im Render bricht
 * den Frame ab). Das Manifest entscheidet zur Build-Zeit, ob eine Szene ihr
 * Video oder den V1-Still-Fallback rendert.
 *
 * Aufruf:  npm run clips:manifest      (nach jedem Clip-Drop erneut ausfuehren)
 */
import {readdirSync, writeFileSync, existsSync, mkdirSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const clipsDir = join(root, 'public', 'clips');
const outFile = join(root, 'src', 'lib', 'clipManifest.ts');

if (!existsSync(clipsDir)) mkdirSync(clipsDir, {recursive: true});

const files = readdirSync(clipsDir)
  .filter((f) => f.toLowerCase().endsWith('.mp4'))
  .sort();

const body = `/**
 * AUTO-GENERIERT von tools/gen_clip_manifest.mjs — NICHT von Hand editieren.
 * Liste der tatsaechlich in public/clips/ vorhandenen Videodateien.
 * Fehlt eine Datei hier, faellt die Szene in Clip.tsx auf ihren V1-Still zurueck.
 */

export const AVAILABLE_CLIPS: readonly string[] = [
${files.map((f) => `  'clips/${f}',`).join('\n')}
];

export const hasClip = (src: string): boolean => AVAILABLE_CLIPS.includes(src);
`;

writeFileSync(outFile, body);
console.log(`clipManifest.ts: ${files.length} Clip(s)`);
for (const f of files) console.log(`  - ${f}`);

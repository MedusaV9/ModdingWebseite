#!/usr/bin/env node
/**
 * GOOBY — asset-staging downloader (V5/ASSETS).
 *
 * Rebuilds the LOCAL staging library that fetch-itch.mjs / fetch-kaykit.mjs
 * consume (default /workspace/asset-staging/, gitignored — PLAN3 §D, PLAN4
 * §B3) by downloading the free packs from their public sources:
 *
 *   itch.io  — the csrf `download_url` flow every free pack supports:
 *              GET the game page (cookie + csrf token) → POST
 *              `<page>/download_url` → GET the download page (upload rows)
 *              → POST `<page>/file/<upload_id>` → GET the signed URL
 *              (expires in ~60 s, so the zip is streamed immediately).
 *   GitHub   — KayKit packs are plain public repos under
 *              github.com/KayKit-Game-Assets; the codeload zipball of the
 *              default branch is extracted as `<staging>/kaykit/<repo>/`.
 *
 * Scope: MODEL packs only. The music/sfx/vfx zips and the decimated splat
 * PLYs of the original D1/D2 scout run are NOT re-derivable from public
 * sources (renamed archives, superspl.at exports decimated offline), which
 * is why fetch-itch.mjs grew the `--only models` section filter — committed
 * files remain the evidence for those sections.
 *
 * Every staged itch pack also gets its LICENSE-NOTE.md (fetch-itch copies it
 * into the committed pack folder): for packs already committed the note is
 * reused VERBATIM from public/assets/itch/<slug>/LICENSE-NOTE.md so re-runs
 * stay byte-stable; new packs get a generated note from the table below.
 *
 * Usage:
 *   node scripts/stage-assets.mjs [--staging /workspace/asset-staging]
 *                                 [--all] [--force]
 *   --all    also fetch the 4 KayKit repos whose committed output is already
 *            complete (only needed for a `fetch-kaykit --force` refresh)
 *   --force  re-download staged files even when they already exist
 *
 * Pure Node (global fetch, Node ≥ 20) — unzip(1) for the GitHub zipballs.
 */

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

const argAfter = (flag) => {
  const i = process.argv.indexOf(flag);
  return i !== -1 ? process.argv[i + 1] : null;
};
const STAGING = argAfter('--staging') ?? '/workspace/asset-staging';
const ALL = process.argv.includes('--all');
const FORCE = process.argv.includes('--force');

const UA =
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) ' +
  'Chrome/126.0.0.0 Safari/537.36';

// ── Whitelist tables ─────────────────────────────────────────────────────────

/**
 * itch.io model packs. `dir`/`zip` mirror the staging paths the fetch-itch
 * MODEL_PACKS manifest expects; `slug` is the committed pack dir whose
 * LICENSE-NOTE.md is reused when present; `note` fills the generated note
 * for packs that were never committed before.
 * @type {Array<{dir: string, zip: string, page: string, slug: string,
 *   pick?: RegExp, note: {author: string, credit: string, archive: string}}>}
 */
const ITCH_PACKS = [
  {
    dir: 'tiny-treats-baked-goods',
    zip: 'free.zip',
    page: 'https://tinytreats.itch.io/baked-goods',
    slug: 'baked-goods',
    note: { author: 'Tiny Treats / Isa Lousberg', credit: 'Isa Lousberg, www.isalousberg.com', archive: 'Free 1.0' },
  },
  {
    dir: 'tiny-treats-bakery-interior',
    zip: 'free-v1.1.zip',
    page: 'https://tinytreats.itch.io/bakery-interior',
    slug: 'bakery-interior',
    note: { author: 'Tiny Treats / Isa Lousberg', credit: 'Isa Lousberg, www.isalousberg.com', archive: 'Free v1.1' },
  },
  {
    dir: 'tiny-treats-pleasant-picnic',
    zip: 'free.zip',
    page: 'https://tinytreats.itch.io/pleasant-picnic',
    slug: 'pleasant-picnic',
    note: { author: 'Tiny Treats / Isa Lousberg', credit: 'Isa Lousberg, www.isalousberg.com', archive: 'Free 1.0' },
  },
  {
    dir: 'aline-furniture-asset-pack',
    zip: 'furniture-pack-update-2.0.zip',
    page: 'https://ladoncha.itch.io/furniture-asset-pack',
    slug: 'aline-furniture',
    pick: /furniture_pack_update_2\.0/i,
    note: { author: 'Aline / Adelina Georgieva', credit: "Link to the author's itch.io page or `https://www.dueacaso.it`.", archive: 'furniture_pack_update_2.0.zip' },
  },
  // V5/ASSETS additions (Tiny Treats Charming Kitchen + Bubbly Bathroom
  // + Pretty Park + House Plants — all CC0, same free-upload flow).
  {
    dir: 'tiny-treats-charming-kitchen',
    zip: 'free-v1.1.zip',
    page: 'https://tinytreats.itch.io/charming-kitchen',
    slug: 'charming-kitchen',
    note: { author: 'Tiny Treats / Isa Lousberg', credit: 'Isa Lousberg, www.isalousberg.com', archive: 'Free v1.1' },
  },
  {
    dir: 'tiny-treats-bubbly-bathroom',
    zip: 'free-v1.1.zip',
    page: 'https://tinytreats.itch.io/bubbly-bathroom',
    slug: 'bubbly-bathroom',
    note: { author: 'Tiny Treats / Isa Lousberg', credit: 'Isa Lousberg, www.isalousberg.com', archive: 'Free v1.1' },
  },
  {
    dir: 'tiny-treats-pretty-park',
    zip: 'free.zip',
    page: 'https://tinytreats.itch.io/pretty-park',
    slug: 'pretty-park',
    note: { author: 'Tiny Treats / Isa Lousberg', credit: 'Isa Lousberg, www.isalousberg.com', archive: 'Free 1.0' },
  },
  {
    dir: 'tiny-treats-house-plants',
    zip: 'free.zip',
    page: 'https://tinytreats.itch.io/house-plants',
    slug: 'house-plants',
    note: { author: 'Tiny Treats / Isa Lousberg', credit: 'Isa Lousberg, www.isalousberg.com', archive: 'Free 1.0' },
  },
];

/**
 * KayKit GitHub repos (KayKit-Game-Assets). The staging dir name doubles as
 * the repo name (the kaykit-manifest source paths start with it). Entries
 * with `optional: true` back packs that are ALREADY committed — fetch-kaykit
 * skips complete packs, so they are only downloaded with --all.
 * @type {Array<{repo: string, optional?: boolean}>}
 */
const KAYKIT_REPOS = [
  { repo: 'KayKit-Furniture-Bits-1.0' }, // V5/ASSETS: kaykit-furniture
  { repo: 'KayKit-Character-Pack-Adventures-1.0', optional: true },
  { repo: 'KayKit-Restaurant-Bits-1.0', optional: true },
  { repo: 'KayKit-City-Builder-Bits-1.0', optional: true },
  { repo: 'KayKit-Halloween-Bits-1.0', optional: true },
];

// ── Small cookie-jar fetch (itch needs the page cookies on every POST) ───────

function makeSession() {
  const jar = new Map();
  const cookieHeader = () =>
    [...jar.entries()].map(([k, v]) => `${k}=${v}`).join('; ');
  const absorb = (res) => {
    for (const line of res.headers.getSetCookie?.() ?? []) {
      const [pair] = line.split(';');
      const eq = pair.indexOf('=');
      if (eq > 0) jar.set(pair.slice(0, eq).trim(), pair.slice(eq + 1).trim());
    }
  };
  return async function request(url, opts = {}) {
    const headers = { 'user-agent': UA, ...(opts.headers ?? {}) };
    if (jar.size) headers.cookie = cookieHeader();
    const res = await fetch(url, { ...opts, headers, redirect: 'follow' });
    absorb(res);
    if (!res.ok) {
      throw new Error(`${opts.method ?? 'GET'} ${url} -> HTTP ${res.status}`);
    }
    return res;
  };
}

// ── itch.io download flow ────────────────────────────────────────────────────

/**
 * Download one free itch pack into `<staging>/itchio/<dir>/<zip>`.
 * @param {object} pack ITCH_PACKS entry
 */
async function stageItchPack(pack) {
  const outDir = path.join(STAGING, 'itchio', pack.dir);
  const outZip = path.join(outDir, pack.zip);
  fs.mkdirSync(outDir, { recursive: true });
  writeLicenseNote(pack, outDir);
  if (!FORCE && fs.existsSync(outZip)) {
    console.log(`= ${pack.dir}/${pack.zip}: already staged, skipping`);
    return;
  }

  const request = makeSession();
  const page = await (await request(pack.page)).text();
  const csrf = page.match(/csrf_token"\s+value="([^"]+)"/)?.[1];
  if (!csrf) throw new Error(`${pack.dir}: no csrf_token on ${pack.page}`);
  const form = new URLSearchParams({ csrf_token: csrf });

  // free packs: POST download_url → the keyed download page with upload rows
  const dlPageUrl = (await (await request(`${pack.page}/download_url`, {
    method: 'POST',
    body: form,
  })).json()).url;
  if (!dlPageUrl) throw new Error(`${pack.dir}: download_url returned no url`);
  const dlPage = await (await request(dlPageUrl)).text();

  // pair every upload id with its display name, honor the pick regex
  const uploads = [...dlPage.matchAll(/data-upload_id="(\d+)"/g)].map((m) => {
    const seg = dlPage.slice(m.index, m.index + 1500);
    return { id: m[1], name: seg.match(/class="name"[^>]*title="([^"]*)"/)?.[1]
      ?? seg.match(/<strong title="([^"]*)"/)?.[1] ?? '' };
  });
  if (!uploads.length) throw new Error(`${pack.dir}: no uploads on the download page`);
  const upload = pack.pick
    ? uploads.find((u) => pack.pick.test(u.name))
    : uploads[0];
  if (!upload) {
    throw new Error(`${pack.dir}: no upload matches ${pack.pick} — saw ` +
      uploads.map((u) => `'${u.name}'`).join(', '));
  }

  // signed file URL (expires ~60 s) → stream to the staging zip
  const fileUrl = (await (await request(
    `${pack.page}/file/${upload.id}?source=game_download`,
    { method: 'POST', body: form }
  )).json()).url;
  if (!fileUrl) throw new Error(`${pack.dir}: file/${upload.id} returned no url`);
  const bytes = Buffer.from(await (await request(fileUrl)).arrayBuffer());
  if (bytes.length < 1024 || bytes.toString('ascii', 0, 2) !== 'PK') {
    throw new Error(`${pack.dir}: downloaded file is not a zip (${bytes.length} bytes)`);
  }
  fs.writeFileSync(outZip, bytes);
  console.log(`+ ${pack.dir}/${pack.zip} (${(bytes.length / 1048576).toFixed(2)} MB, ` +
    `upload '${upload.name || upload.id}')`);
}

/** Reuse the committed pack note verbatim, else generate one from the table. */
function writeLicenseNote(pack, outDir) {
  const notePath = path.join(outDir, 'LICENSE-NOTE.md');
  const committed = path.join(ROOT, 'public', 'assets', 'itch', pack.slug, 'LICENSE-NOTE.md');
  const today = new Date().toISOString().slice(0, 10);
  const body = fs.existsSync(committed)
    ? fs.readFileSync(committed)
    : Buffer.from([
      '# License note',
      '',
      `- Source: ${pack.page}`,
      `- Author: ${pack.note.author}`,
      '- License: Creative Commons Zero 1.0 Universal (CC0)',
      '- Commercial use: Yes',
      '- Attribution required: No',
      `- Optional credit supplied by author: \`${pack.note.credit}\``,
      `- Verified: ${today} from the itch.io page and embedded \`License.txt\`.`,
      `- Downloaded: ${pack.note.archive} archive only; the paid Blender source upgrade was not downloaded.`,
      '',
    ].join('\n'));
  if (fs.existsSync(notePath) && fs.readFileSync(notePath).equals(body)) return;
  fs.writeFileSync(notePath, body);
}

// ── KayKit GitHub zipballs ───────────────────────────────────────────────────

async function stageKaykitRepo(entry) {
  const dest = path.join(STAGING, 'kaykit', entry.repo);
  if (!FORCE && fs.existsSync(dest)) {
    console.log(`= kaykit/${entry.repo}: already staged, skipping`);
    return;
  }
  const url = `https://codeload.github.com/KayKit-Game-Assets/${entry.repo}/zip/refs/heads/main`;
  const res = await fetch(url, { headers: { 'user-agent': UA } });
  if (!res.ok) throw new Error(`${entry.repo}: HTTP ${res.status} from codeload`);
  const bytes = Buffer.from(await res.arrayBuffer());
  const tmpZip = path.join(STAGING, 'kaykit', `${entry.repo}.zip.part`);
  fs.mkdirSync(path.dirname(tmpZip), { recursive: true });
  fs.writeFileSync(tmpZip, bytes);
  fs.rmSync(dest, { recursive: true, force: true });
  execFileSync('unzip', ['-q', '-o', tmpZip, '-d', path.join(STAGING, 'kaykit')]);
  fs.rmSync(tmpZip);
  // codeload zipballs extract as <repo>-main/ — rename to the manifest path
  const extracted = path.join(STAGING, 'kaykit', `${entry.repo}-main`);
  if (!fs.existsSync(extracted)) {
    throw new Error(`${entry.repo}: zipball did not extract to ${extracted}`);
  }
  fs.renameSync(extracted, dest);
  console.log(`+ kaykit/${entry.repo} (${(bytes.length / 1048576).toFixed(2)} MB zipball)`);
}

// ── Main ─────────────────────────────────────────────────────────────────────

for (const pack of ITCH_PACKS) {
  await stageItchPack(pack);
}
for (const entry of KAYKIT_REPOS) {
  if (entry.optional && !ALL) {
    console.log(`= kaykit/${entry.repo}: optional (committed pack complete) — use --all`);
    continue;
  }
  await stageKaykitRepo(entry);
}
console.log('\nOK: staging library ready — run fetch-itch.mjs --only models / fetch-kaykit.mjs');

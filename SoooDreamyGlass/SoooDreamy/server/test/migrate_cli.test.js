import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, mkdir, readdir, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { inspectDataDir, needsMigration } from '../src/legacy-migration.js';
import { client, makeApp } from './helpers.js';

const run = promisify(execFile);
const serverRoot = fileURLToPath(new URL('..', import.meta.url));

const MIA_TOKEN = 'tok_mia_legacy_154_0000000000000000';
const BEN_TOKEN = 'tok_ben_legacy_154_0000000000000000';

/** Faithful v1.5.4-era data dir: inline v1 store.json + raw-token sessions. */
async function writeLegacyDataDir() {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'sooodreamy-154-'));
  const store = {
    version: 1,
    couples: {
      c_legacy154: {
        id: 'c_legacy154',
        code: 'LEGACY',
        name: 'Mia & Ben',
        anniversary: '2024-02-14',
        createdAt: '2026-08-01T10:00:00.000Z',
        members: [
          {
            id: 'm_mia', name: 'Mia', avatar: '🦊', color: '#FF5C8A',
            mood: '🥰', moodNote: null, moodUpdatedAt: '2026-08-02T09:00:00.000Z',
            lastSeenAt: '2026-08-02T21:00:00.000Z', joinedAt: '2026-08-01T10:00:00.000Z',
          },
          {
            id: 'm_ben', name: 'Ben', avatar: '🐻', color: '#4A90D9',
            mood: null, moodNote: null, moodUpdatedAt: null,
            lastSeenAt: '2026-08-02T20:00:00.000Z', joinedAt: '2026-08-01T10:05:00.000Z',
          },
        ],
        touches: [{ id: 't_1', type: 'heartbeat', senderId: 'm_mia', createdAt: '2026-08-01T11:00:00.000Z' }],
        messages: [
          { id: 'msg_1', senderId: 'm_mia', type: 'text', text: 'Hallo aus 1.5.4 💜', title: null, createdAt: '2026-08-01T12:00:00.000Z' },
          { id: 'msg_2', senderId: 'm_ben', type: 'letter', text: 'Ein Brief', title: 'Für dich', createdAt: '2026-08-01T13:00:00.000Z' },
        ],
        photos: [],
        events: [{ id: 'e_1', title: 'Jahrestag', date: '2027-02-14', emoji: null, repeatsYearly: true, createdBy: 'm_mia', createdAt: '2026-08-01T14:00:00.000Z' }],
        bucket: [{ id: 'b_1', text: 'Sterne gucken', createdBy: 'm_ben', doneAt: null, createdAt: '2026-08-01T15:00:00.000Z' }],
        strokes: [],
        daily: {
          '2026-08-01': {
            questionId: 3,
            answers: {
              m_mia: { text: 'Pizza!', answeredAt: '2026-08-01T18:00:00.000Z' },
              m_ben: { text: 'Pasta!', answeredAt: '2026-08-01T18:30:00.000Z' },
            },
          },
        },
        games: [
          // Open pre-v4 relay game without a trustworthy server seed → the
          // migration must invalidate it (never silently continue).
          {
            id: 'g_open', type: 'quiz', state: 'active', createdBy: 'm_mia',
            payload: { rounds: 5 }, result: null,
            moves: [{ id: 'mv_1', memberId: 'm_mia', data: { kind: 'answer', index: 0 }, createdAt: '2026-08-01T19:00:00.000Z' }],
            createdAt: '2026-08-01T19:00:00.000Z',
          },
          {
            id: 'g_done', type: 'quiz', state: 'ended', createdBy: 'm_ben',
            payload: { rounds: 3 }, result: { winner: 'm_ben' }, moves: [],
            createdAt: '2026-08-01T20:00:00.000Z',
          },
        ],
        // v1.2.0 wordle day shape (no language buckets) — read path normalizes lazily.
        wordle: { '2026-08-01': { m_mia: { memberId: 'm_mia', lang: 'de', win: true, rows: 3, grid: '🟩🟩🟩🟩🟩' } } },
        moodHistory: {},
        coupons: [],
        songs: [],
        counters: { messages: 2, gamesPlayed: 1, touches: { m_mia: { total: 1, byType: { heartbeat: 1 } } } },
      },
    },
    // Pre-4.0 sessions: RAW tokens as keys, minimal records.
    tokens: {
      [MIA_TOKEN]: { coupleId: 'c_legacy154', memberId: 'm_mia' },
      [BEN_TOKEN]: { coupleId: 'c_legacy154', memberId: 'm_ben' },
    },
  };
  await writeFile(path.join(dataDir, 'store.json'), JSON.stringify(store, null, 2), 'utf8');
  await mkdir(path.join(dataDir, 'media', 'voice'), { recursive: true });
  await writeFile(path.join(dataDir, 'media', 'voice', 'msg_x.m4a'), Buffer.from('legacy-voice'));
  return dataDir;
}

test('inspect + dry-run report a 1.5.4 store without touching anything', async (t) => {
  const dataDir = await writeLegacyDataDir();
  t.after(() => rm(dataDir, { recursive: true, force: true }));

  const inspection = await inspectDataDir(dataDir);
  assert.equal(inspection.state, 'legacy-v1');
  assert.equal(inspection.couples, 1);
  assert.equal(inspection.legacyTokens, 2);
  assert.equal(inspection.staleGames, 1);
  assert.equal(needsMigration(inspection), true);

  const before = await readFile(path.join(dataDir, 'store.json'), 'utf8');
  const dry = await run('node', ['scripts/migrate.js', '--data-dir', dataDir, '--dry-run'], { cwd: serverRoot });
  assert.match(dry.stdout, /DRY RUN/);
  assert.match(dry.stdout, /pre-migration backup/);
  assert.match(dry.stdout, /2 raw bearer token/);
  assert.equal(await readFile(path.join(dataDir, 'store.json'), 'utf8'), before, 'dry run must not write');
  const entries = await readdir(dataDir);
  assert.equal(entries.includes('backups'), false, 'dry run must not create backups');
});

test('npm run migrate lifts a 1.5.4 store to the current layout (with backup) and is idempotent', async (t) => {
  const dataDir = await writeLegacyDataDir();
  t.after(() => rm(dataDir, { recursive: true, force: true }));

  const applied = await run('node', ['scripts/migrate.js', '--data-dir', dataDir], { cwd: serverRoot });
  assert.match(applied.stdout, /done ✓/);
  assert.match(applied.stdout, /backup:\s+\d{8}-\d{6}-[0-9a-f]{12}-pre-migration/);
  assert.match(applied.stdout, /tokens upgraded:\s+2/);

  // Layout: segmented manifest + checksummed segment; tokens are hashed records.
  const manifest = JSON.parse(await readFile(path.join(dataDir, 'store.json'), 'utf8'));
  assert.equal(manifest.format, 'segmented-v1');
  assert.ok(manifest.couples.c_legacy154);
  for (const [key, record] of Object.entries(manifest.tokens)) {
    assert.match(key, /^[0-9a-f]{64}$/, 'no raw bearer keys remain');
    assert.ok(record.sessionId && record.expiresAt, 'full session records');
  }
  const segment = JSON.parse(
    await readFile(path.join(dataDir, 'segments', manifest.couples.c_legacy154), 'utf8'),
  );
  assert.equal(segment.format, 'segment-v2');
  assert.equal(segment.couple.messages.length, 2);

  // The pre-migration backup preserves the EXACT 1.5.4 file.
  const backups = await readdir(path.join(dataDir, 'backups'));
  const preMigration = backups.find((name) => name.endsWith('pre-migration'));
  assert.ok(preMigration);
  const backedUp = JSON.parse(
    await readFile(path.join(dataDir, 'backups', preMigration, 'store.json'), 'utf8'),
  );
  assert.equal(backedUp.version, 1);
  assert.ok(backedUp.tokens[MIA_TOKEN]);

  // Idempotent: a second run finds nothing to do and takes no new backup.
  const again = await run('node', ['scripts/migrate.js', '--data-dir', dataDir], { cwd: serverRoot });
  assert.match(again.stdout, /already up to date/);
  assert.deepEqual(await readdir(path.join(dataDir, 'backups')), backups);
});

test('after migration the server serves 1.5.4 data and the OLD app tokens still sign in', async (t) => {
  const dataDir = await writeLegacyDataDir();
  await run('node', ['scripts/migrate.js', '--data-dir', dataDir], { cwd: serverRoot });

  const { baseUrl } = await makeApp(t, { dataDir });
  t.after(() => rm(dataDir, { recursive: true, force: true }));

  // The raw 1.5.4 bearer hashes onto the migrated digest record.
  const mia = client(baseUrl, MIA_TOKEN);
  const couple = await mia.get('/api/couple');
  assert.equal(couple.status, 200);
  assert.equal(couple.body.couple.name, 'Mia & Ben');
  assert.equal(couple.body.couple.members.length, 2);

  const messages = await mia.get('/api/messages');
  assert.deepEqual(messages.body.messages.map((m) => m.id), ['msg_1', 'msg_2']);

  const daily = await mia.get('/api/daily?limit=10');
  assert.equal(daily.status, 200);

  // Open pre-v4 game was invalidated (not silently continued); ended one kept.
  const games = await mia.get('/api/games?limit=10');
  const gOpen = games.body.games.find((g) => g.id === 'g_open');
  const gDone = games.body.games.find((g) => g.id === 'g_done');
  assert.equal(gOpen.state, 'ended');
  assert.equal(gOpen.result.invalidated, true);
  assert.equal(gDone.result.winner, 'm_ben');

  // v1.2.0 wordle day is normalized on read.
  const wordle = await mia.get('/api/wordle/2026-08-01?lang=de');
  assert.equal(wordle.status, 200);
  assert.equal(wordle.body.mine.win, true);

  // And the new v6.1 features work for migrated members right away.
  const recovery = await mia.post('/api/recovery-key');
  assert.equal(recovery.status, 200);
  assert.equal(recovery.body.rotated, false);
  const rejoin = await client(baseUrl).post('/api/couples/rejoin', {
    json: { code: 'LEGACY', recoveryKey: recovery.body.recoveryKey },
  });
  assert.equal(rejoin.status, 200);
  assert.equal(rejoin.body.memberId, 'm_mia');
});

test('inspect classifies fresh and current dirs correctly', async (t) => {
  const empty = await mkdtemp(path.join(os.tmpdir(), 'sooodreamy-empty-'));
  t.after(() => rm(empty, { recursive: true, force: true }));
  const emptyInspection = await inspectDataDir(empty);
  assert.equal(emptyInspection.state, 'empty');
  assert.equal(needsMigration(emptyInspection), false);

  const currentDir = await mkdtemp(path.join(os.tmpdir(), 'sooodreamy-current-'));
  const app = await makeApp(null, { dataDir: currentDir });
  await client(app.baseUrl).post('/api/couples', { json: { name: 'Solo' } });
  await app.close();
  t.after(() => rm(currentDir, { recursive: true, force: true }));
  const currentInspection = await inspectDataDir(currentDir);
  assert.equal(currentInspection.state, 'current');
  assert.equal(currentInspection.couples, 1);
  assert.equal(currentInspection.legacyTokens, 0);
  assert.equal(needsMigration(currentInspection), false);
});

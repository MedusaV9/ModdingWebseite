import assert from 'node:assert/strict';
import { fork } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

// FullRelease R1-C — the S2 delivery crash window, fault-injected for real:
// a scheduled post's delivery is (1) remove post + mint artifact under its
// STABLE post-derived id, (2) store.markDirty() = synchronous fsynced WAL
// commit, (3) WS fanout + push. These tests SIGKILL a real server process
// exactly before (2) and exactly between (2) and (3) — the two windows the
// server eval proved double-delivered before the fix — and assert the new
// contract: exactly-once for the artifact, at-least-once for the send.

const CHILD = new URL('./post_crash_child.js', import.meta.url);
const MIN = 60_000;

async function startChild(dataDir) {
  const child = fork(CHILD, {
    env: { ...process.env, DATA_DIR: dataDir },
    stdio: ['ignore', 'pipe', 'pipe', 'ipc'],
  });
  let output = '';
  child.stdout.on('data', (chunk) => { output += chunk; });
  child.stderr.on('data', (chunk) => { output += chunk; });
  const ready = await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error(`child start timed out: ${output}`)), 10_000);
    child.once('error', reject);
    child.once('exit', (code, signal) => {
      reject(new Error(`child exited before ready (${code ?? signal}): ${output}`));
    });
    child.on('message', (message) => {
      if (message?.type !== 'ready') return;
      clearTimeout(timeout);
      resolve(message);
    });
  });
  return { child, baseUrl: `http://[::1]:${ready.port}` };
}

/** Runs one sweep in the child; resolves {delivered} or {signal} on crash. */
function sweepInChild(child, { nowMs, crashPoint = null }) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('sweep timed out')), 10_000);
    const onMessage = (message) => {
      if (message?.type !== 'swept') return;
      cleanup();
      resolve({ delivered: message.delivered });
    };
    const onExit = (code, signal) => {
      cleanup();
      resolve({ code, signal });
    };
    const cleanup = () => {
      clearTimeout(timeout);
      child.off('message', onMessage);
      child.off('exit', onExit);
    };
    child.on('message', onMessage);
    child.on('exit', onExit);
    child.send({ type: 'sweep', nowMs, crashPoint });
  });
}

async function killChild(child, signal) {
  if (child.exitCode !== null || child.signalCode !== null) return;
  child.kill(signal);
  await new Promise((resolve) => child.once('exit', resolve));
}

async function request(baseUrl, pathname, { method = 'GET', token, json } = {}) {
  const headers = {};
  if (token) headers.authorization = `Bearer ${token}`;
  let body;
  if (json !== undefined) {
    headers['content-type'] = 'application/json';
    body = JSON.stringify(json);
  }
  const response = await fetch(`${baseUrl}${pathname}`, { method, headers, body });
  return { status: response.status, body: await response.json() };
}

test('SIGKILL exactly between artifact persist and fanout: ONE artifact after restart, no re-delivery', async () => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'sooodreamy-post-crash-'));
  let running;
  try {
    running = await startChild(dataDir);
    const created = await request(running.baseUrl, '/api/couples', {
      method: 'POST',
      json: { name: 'Crash window', deviceId: 'post-crash-device' },
    });
    assert.equal(created.status, 201);
    const token = created.body.token;
    const scheduled = await request(running.baseUrl, '/api/post/schedule', {
      method: 'POST',
      token,
      json: {
        kind: 'note',
        note: 'Genau einmal 💌',
        deliverAt: new Date(Date.now() + 6 * MIN).toISOString(),
      },
    });
    assert.equal(scheduled.status, 201);

    // The transition (remove + mint + WAL commit) completed; the process dies
    // before any fanout/push side effect could run.
    const crash = await sweepInChild(running.child, {
      nowMs: Date.now() + 7 * MIN,
      crashPoint: 'after-persist',
    });
    assert.equal(crash.signal, 'SIGKILL');

    running = await startChild(dataDir);
    const open = await request(running.baseUrl, '/api/post/scheduled', { token });
    assert.deepEqual(open.body.posts, [], 'the delivered post must NOT be open again');
    const journal = await request(running.baseUrl, '/api/post/journal', { token });
    const notes = journal.body.entries.filter((e) => e.kind === 'note');
    assert.equal(notes.length, 1, 'exactly ONE artifact — never a double delivery');
    assert.equal(notes[0].id, `pn_${scheduled.body.post.id}`, 'the artifact carries its stable post-derived id');

    // A later sweep finds nothing left to deliver (no fanout replay either).
    const resweep = await sweepInChild(running.child, { nowMs: Date.now() + 8 * MIN });
    assert.equal(resweep.delivered, 0);
    const after = await request(running.baseUrl, '/api/post/journal', { token });
    assert.equal(after.body.entries.filter((e) => e.kind === 'note').length, 1);
  } finally {
    if (running) await killChild(running.child, 'SIGTERM').catch(() => {});
    await rm(dataDir, { recursive: true, force: true });
  }
});

test('SIGKILL before the persist: the post stays open and the re-sweep delivers exactly once', async () => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'sooodreamy-post-crash-pre-'));
  let running;
  try {
    running = await startChild(dataDir);
    const created = await request(running.baseUrl, '/api/couples', {
      method: 'POST',
      json: { name: 'Crash before persist', deviceId: 'post-crash-pre-device' },
    });
    assert.equal(created.status, 201);
    const token = created.body.token;
    const scheduled = await request(running.baseUrl, '/api/post/schedule', {
      method: 'POST',
      token,
      json: {
        kind: 'note',
        note: 'Kommt später an',
        deliverAt: new Date(Date.now() + 6 * MIN).toISOString(),
      },
    });
    assert.equal(scheduled.status, 201);

    // The in-memory transition ran but was never journaled — a restart must
    // see NEITHER the artifact NOR the removal (all-or-nothing).
    const crash = await sweepInChild(running.child, {
      nowMs: Date.now() + 7 * MIN,
      crashPoint: 'before-persist',
    });
    assert.equal(crash.signal, 'SIGKILL');

    running = await startChild(dataDir);
    const open = await request(running.baseUrl, '/api/post/scheduled', { token });
    assert.equal(open.body.posts.length, 1, 'the undelivered post is still open');
    assert.equal(open.body.posts[0].id, scheduled.body.post.id);
    const before = await request(running.baseUrl, '/api/post/journal', { token });
    assert.equal(before.body.entries.filter((e) => e.kind === 'note').length, 0, 'no half-delivered artifact');

    // At-least-once for the send: the next sweep delivers — exactly once.
    const resweep = await sweepInChild(running.child, { nowMs: Date.now() + 8 * MIN });
    assert.equal(resweep.delivered, 1);
    const journal = await request(running.baseUrl, '/api/post/journal', { token });
    const notes = journal.body.entries.filter((e) => e.kind === 'note');
    assert.equal(notes.length, 1);
    assert.equal(notes[0].note, 'Kommt später an');
    const openAfter = await request(running.baseUrl, '/api/post/scheduled', { token });
    assert.deepEqual(openAfter.body.posts, []);
  } finally {
    if (running) await killChild(running.child, 'SIGTERM').catch(() => {});
    await rm(dataDir, { recursive: true, force: true });
  }
});

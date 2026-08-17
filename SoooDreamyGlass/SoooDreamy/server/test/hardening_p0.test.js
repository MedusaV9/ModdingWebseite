import assert from 'node:assert/strict';
import { fork } from 'node:child_process';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

const CHILD = new URL('./hardening_child.js', import.meta.url);

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

async function startBlockedChild(dataDir) {
  const child = fork(CHILD, {
    env: { ...process.env, DATA_DIR: dataDir },
    stdio: ['ignore', 'pipe', 'pipe', 'ipc'],
  });
  let output = '';
  child.stdout.on('data', (chunk) => { output += chunk; });
  child.stderr.on('data', (chunk) => { output += chunk; });
  const result = await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('blocked child did not exit')), 10_000);
    child.once('error', reject);
    child.once('exit', (code, signal) => {
      clearTimeout(timeout);
      resolve({ code, signal });
    });
    child.on('message', (message) => {
      if (message?.type === 'ready') reject(new Error('second writer unexpectedly started'));
    });
  });
  return { ...result, output };
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

const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

test('120 acknowledged messages survive six immediate SIGKILL/restart cycles', async () => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'sooodreamy-wal-'));
  let running;
  try {
    running = await startChild(dataDir);
    const created = await request(running.baseUrl, '/api/couples', {
      method: 'POST',
      json: {
        name: 'WAL durability',
        deviceId: 'wal-test-device',
        deviceName: 'WAL test device',
      },
    });
    assert.equal(created.status, 201);
    const token = created.body.token;

    let acknowledged = 0;
    for (let cycle = 0; cycle < 6; cycle += 1) {
      const writes = await Promise.all(
        Array.from({ length: 20 }, (_, index) => request(running.baseUrl, '/api/messages', {
          method: 'POST',
          token,
          json: {
            type: 'text',
            text: `acked-before-kill-${cycle}-${index}`,
            clientMessageId: `wal-${cycle}-${index}`,
          },
        })),
      );
      assert.ok(writes.every((entry) => entry.status === 201));
      acknowledged += writes.length;
      await killChild(running.child, 'SIGKILL');
      running = await startChild(dataDir);
      const afterRestart = await request(running.baseUrl, '/api/messages?limit=200', { token });
      assert.equal(afterRestart.status, 200);
      assert.equal(
        afterRestart.body.messages.filter((message) => message.text.startsWith('acked-before-kill-')).length,
        acknowledged,
      );
    }
  } finally {
    if (running) await killChild(running.child, 'SIGTERM').catch(() => {});
    await rm(dataDir, { recursive: true, force: true });
  }
});

test('a second process cannot open the same DATA_DIR and a SIGKILL lock is safely recovered', async () => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'sooodreamy-lock-'));
  let running;
  try {
    running = await startChild(dataDir);
    const created = await request(running.baseUrl, '/api/couples', {
      method: 'POST',
      json: { name: 'Single writer', deviceId: 'lock-owner' },
    });
    assert.equal(created.status, 201);

    const blocked = await startBlockedChild(dataDir);
    assert.equal(blocked.code, 1);
    assert.match(blocked.output, /DATA_DIR is already locked.*PID/u);

    await killChild(running.child, 'SIGKILL');
    running = await startChild(dataDir);
    const recovered = await request(running.baseUrl, '/api/couple', { token: created.body.token });
    assert.equal(recovered.status, 200);
  } finally {
    if (running) await killChild(running.child, 'SIGTERM').catch(() => {});
    await rm(dataDir, { recursive: true, force: true });
  }
});

test('manifest fallback adopts a newer valid segment and WAL generation without deleting either couple', async () => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'sooodreamy-manifest-recovery-'));
  let running;
  try {
    running = await startChild(dataDir);
    const first = await request(running.baseUrl, '/api/couples', {
      method: 'POST',
      json: { name: 'Earlier generation', deviceId: 'earlier' },
    });
    assert.equal(first.status, 201);
    await delay(700);
    const second = await request(running.baseUrl, '/api/couples', {
      method: 'POST',
      json: { name: 'Newer generation', deviceId: 'newer' },
    });
    assert.equal(second.status, 201);
    await delay(700);
    await killChild(running.child, 'SIGTERM');

    const segmentsBefore = (await readdir(path.join(dataDir, 'segments')))
      .filter((name) => name.endsWith('.json')).length;
    await writeFile(path.join(dataDir, 'store.json'), '{"broken":', 'utf8');
    running = await startChild(dataDir);
    assert.equal((await request(running.baseUrl, '/api/couple', { token: first.body.token })).status, 200);
    assert.equal((await request(running.baseUrl, '/api/couple', { token: second.body.token })).status, 200);
    const health = await request(running.baseUrl, '/api/health');
    assert.equal(health.body.storage.couples, 2);
    assert.equal(
      (await readdir(path.join(dataDir, 'segments'))).filter((name) => name.endsWith('.json')).length,
      segmentsBefore,
    );
  } finally {
    if (running) await killChild(running.child, 'SIGTERM').catch(() => {});
    await rm(dataDir, { recursive: true, force: true });
  }
});

test('semantic manifest and segment corruption use recovery/quarantine instead of deleting data', async () => {
  for (const kind of ['manifest', 'segment']) {
    const dataDir = await mkdtemp(path.join(os.tmpdir(), `sooodreamy-semantic-${kind}-`));
    let running;
    try {
      running = await startChild(dataDir);
      const created = await request(running.baseUrl, '/api/couples', {
        method: 'POST',
        json: { name: `Semantic ${kind}`, deviceId: `semantic-${kind}` },
      });
      assert.equal(created.status, 201);
      await delay(700);
      await killChild(running.child, 'SIGTERM');

      const manifestFile = path.join(dataDir, 'store.json');
      if (kind === 'manifest') {
        await writeFile(manifestFile, '{}', 'utf8');
      } else {
        const manifest = JSON.parse(await readFile(manifestFile, 'utf8'));
        await writeFile(
          path.join(dataDir, 'segments', manifest.couples[created.body.coupleId]),
          '{}',
          'utf8',
        );
      }

      running = await startChild(dataDir);
      assert.equal((await request(running.baseUrl, '/api/couple', { token: created.body.token })).status, 200);
      const quarantine = await readdir(path.join(dataDir, 'quarantine'));
      assert.ok(quarantine.some((name) => kind === 'manifest'
        ? name.includes('store.json')
        : name.includes(created.body.coupleId)));
    } finally {
      if (running) await killChild(running.child, 'SIGTERM').catch(() => {});
      await rm(dataDir, { recursive: true, force: true });
    }
  }
});

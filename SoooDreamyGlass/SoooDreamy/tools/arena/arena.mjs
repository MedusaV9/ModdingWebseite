#!/usr/bin/env node
/**
 * SoooDreamy ARENA — reproducible multi-couple live test system.
 *
 *   node arena.mjs run --couples 6 --devices 2 --minutes 3 --seed 42
 *
 * Boots a DEDICATED server (tmux session `arena-server`, port 4399, fresh
 * DATA_DIR) with the Zeitpost test overrides (POST_MIN_LEAD_SECONDS=2,
 * POST_DELIVERY_INTERVAL_SECONDS=1), creates N couples × 2 members ×
 * D devices over the REAL pairing/link APIs, connects every device via WS
 * and drives seeded parallel scenarios — including a hard server crash and
 * restart mid-run. Afterwards a post-run pass checks the full invariant set
 * and writes a JSON report.
 *
 * See README.md for the scenario/invariant catalog.
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { makeRng } from './lib/rng.mjs';
import { sleep } from './lib/util.mjs';
import { World } from './lib/world.mjs';
import { ServerControl } from './lib/server-ctl.mjs';
import { snapshotCouple } from './lib/snapshot.mjs';
import {
  chatScenario, touchEchoScenario, pulseScenario, zeitpostScenario,
  dailyPinRaceScenario, gameScenario, listsCanvasScenario, reconnectScenario,
} from './lib/scenarios.mjs';
import {
  checkFrameOwnership, checkFanout, checkZeitpostDelivery,
  checkJournalOrder, checkGameIntegrity, checkCollections,
  verifyRestartPersistence,
} from './lib/checks.mjs';

function parseArgs(argv) {
  const args = {
    couples: 6, devices: 2, minutes: 3, seed: 42,
    port: 4399, dataDir: '/tmp/arena-data', session: 'arena-server',
    restart: true, label: null, reportDir: '/tmp/arena-reports',
  };
  for (let i = 0; i < argv.length; i += 1) {
    const key = argv[i];
    const next = argv[i + 1];
    switch (key) {
      case '--couples': args.couples = Number(next); i += 1; break;
      case '--devices': args.devices = Number(next); i += 1; break;
      case '--minutes': args.minutes = Number(next); i += 1; break;
      case '--seed': args.seed = next; i += 1; break;
      case '--port': args.port = Number(next); i += 1; break;
      case '--data-dir': args.dataDir = next; i += 1; break;
      case '--session': args.session = next; i += 1; break;
      case '--label': args.label = next; i += 1; break;
      case '--report-dir': args.reportDir = next; i += 1; break;
      case '--no-restart': args.restart = false; break;
      default: break;
    }
  }
  if (!Number.isInteger(args.couples) || args.couples < 1 || args.couples > 24) {
    throw new Error('--couples must be 1…24');
  }
  if (!Number.isInteger(args.devices) || args.devices < 1 || args.devices > 4) {
    throw new Error('--devices must be 1…4 (per member; server cap is 8 sessions)');
  }
  return args;
}

const SCENARIO_WEIGHTS = [
  { weight: 26, value: chatScenario },
  { weight: 16, value: touchEchoScenario },
  { weight: 7, value: pulseScenario },
  { weight: 15, value: zeitpostScenario },
  { weight: 11, value: listsCanvasScenario },
  { weight: 13, value: reconnectScenario },
  { weight: 8, value: gameScenario },
];

async function coupleDriver(world, couple, rng) {
  // One-shot: the daily pin race runs first for every couple.
  world.activeSteps += 1;
  try {
    await dailyPinRaceScenario(world, couple, rng);
  } catch (err) {
    world.violations.add('scenario_error', 'high',
      `dailyPinRace threw on couple ${couple.ci}: ${err.message}`, {});
  } finally {
    world.activeSteps -= 1;
  }
  while (Date.now() < world.deadline) {
    if (world.quiesce) {
      await sleep(100);
      continue;
    }
    const scenario = rng.weighted(SCENARIO_WEIGHTS);
    world.activeSteps += 1;
    try {
      await scenario(world, couple, rng);
    } catch (err) {
      if (!world.expectDisconnects && !world.quiesce) {
        world.violations.add('scenario_error', 'high',
          `${scenario.name} threw on couple ${couple.ci}: ${err.message}`, {});
      }
    } finally {
      world.activeSteps -= 1;
    }
    await sleep(rng.int(120, 600));
  }
}

/**
 * The mid-run crash: quiesce all drivers, schedule Zeitposts that become due
 * WHILE the server is down, snapshot, SIGKILL, restart, reconnect every
 * device, then verify persistence + exactly-once delivery across the outage.
 */
async function crashRestart(world, serverCtl, rng) {
  console.log('— restart: quiescing drivers …');
  world.quiesce = true;
  const quiesceStart = Date.now();
  while (world.activeSteps > 0) {
    if (Date.now() - quiesceStart > 30_000) {
      console.log('— restart: quiesce timeout, proceeding anyway');
      break;
    }
    await sleep(100);
  }

  // One Zeitpost per couple that is due mid-outage (exactly-once across crash).
  for (const couple of world.couples) {
    try {
      await zeitpostScenario(world, couple, rng.child(`restart-${couple.ci}`), { deliverInMs: 3_000 });
    } catch (err) {
      world.violations.add('scenario_error', 'high',
        `restart zeitpost failed on couple ${couple.ci}: ${err.message}`, {});
    }
  }

  console.log('— restart: taking before-snapshots …');
  const before = new Map();
  for (const couple of world.couples) {
    before.set(couple.ci, await snapshotCouple(couple));
  }

  console.log('— restart: SIGKILL server (simulated crash) …');
  world.expectDisconnects = true;
  await serverCtl.crash();
  await sleep(4_000); // outage window — the restart posts become due now
  console.log('— restart: starting server again on the same DATA_DIR …');
  await serverCtl.start();

  console.log('— restart: reconnecting all device sockets …');
  for (const device of world.allDevices()) {
    device.sock.close({ expected: true });
    let connected = false;
    for (let attempt = 0; attempt < 5 && !connected; attempt += 1) {
      try {
        await device.sock.connect();
        await device.sock.waitFor('welcome');
        connected = true;
      } catch {
        await sleep(400);
      }
    }
    if (!connected) {
      world.violations.add('reconnect_failed', 'critical',
        `device ${device.name} could not reconnect after the restart`, {});
    }
  }
  world.expectDisconnects = false;

  await sleep(3_500); // delivery sweep (1 s interval) catches up
  console.log('— restart: taking after-snapshots + verifying persistence …');
  const dueBeforeMs = Date.now() - 2_500;
  for (const couple of world.couples) {
    const after = await snapshotCouple(couple);
    verifyRestartPersistence(world, couple, before.get(couple.ci), after, { dueBeforeMs });
  }
  world.quiesce = false;
  console.log('— restart: done, drivers resume');
}

async function run(args) {
  const label = args.label ?? `arena-${args.couples}x${args.devices}-${args.minutes}m-seed${args.seed}`;
  console.log(`\n═══ ARENA RUN ${label} ═══`);
  console.log(`couples=${args.couples} devices/member=${args.devices} minutes=${args.minutes} seed=${args.seed} restart=${args.restart}`);

  const serverCtl = new ServerControl({
    session: args.session, port: args.port, dataDir: args.dataDir,
  });
  await serverCtl.startFresh();
  console.log(`server: fresh instance in tmux "${args.session}" on ${serverCtl.baseUrl} (DATA_DIR ${args.dataDir})`);

  const rng = makeRng(args.seed);
  const world = new World({ baseUrl: serverCtl.baseUrl, rng });
  world.activeSteps = 0;
  const startedAt = Date.now();
  await world.setup({ couples: args.couples, devicesPerMember: args.devices });

  const runMs = args.minutes * 60_000;
  world.deadline = Date.now() + runMs;

  const drivers = world.couples.map((couple) => coupleDriver(world, couple, rng.child(`couple-${couple.ci}`)));
  const restartTask = args.restart
    ? (async () => {
      await sleep(Math.floor(runMs * 0.55));
      await crashRestart(world, serverCtl, rng);
    })()
    : Promise.resolve();

  await Promise.all([...drivers, restartTask]);
  console.log('— run window over, waiting for outstanding Zeitpost deliveries …');
  const lastDeliverAt = Math.max(0, ...world.scheduledPosts.filter((p) => !p.canceled).map((p) => p.deliverAtMs));
  await sleep(Math.max(0, lastDeliverAt + 4_000 - Date.now()));

  console.log('— post-run invariant pass …');
  checkFrameOwnership(world);
  checkFanout(world);
  await checkZeitpostDelivery(world);
  await checkJournalOrder(world);
  await checkGameIntegrity(world);
  await checkCollections(world);

  world.teardown();

  const report = {
    label,
    config: {
      couples: args.couples, devicesPerMember: args.devices,
      minutes: args.minutes, seed: args.seed, restart: args.restart,
      baseUrl: serverCtl.baseUrl, dataDir: args.dataDir,
    },
    durationMs: Date.now() - startedAt,
    stats: world.stats,
    scheduledPosts: world.scheduledPosts.length,
    violations: world.violations.items,
    violationSummary: world.violations.summary(),
  };
  mkdirSync(args.reportDir, { recursive: true });
  const reportPath = path.join(args.reportDir, `${label}.json`);
  writeFileSync(reportPath, JSON.stringify(report, null, 2));

  console.log(`\n═══ RESULT ${label} ═══`);
  console.log(`requests: ${world.stats.requests}  (status: ${JSON.stringify(world.stats.byStatus)})`);
  console.log(`ws frames: ${world.stats.frames}`);
  console.log(`scenarios: ${JSON.stringify(world.stats.scenarios)}`);
  console.log(`zeitposts tracked: ${world.scheduledPosts.length} (${world.scheduledPosts.filter((p) => p.canceled).length} canceled)`);
  console.log(`VIOLATIONS: ${world.violations.count} ${JSON.stringify(world.violations.summary().byCode)}`);
  console.log(`report: ${reportPath}`);
  return report;
}

const [command, ...rest] = process.argv.slice(2);
if (command !== 'run') {
  console.error('usage: node arena.mjs run [--couples N] [--devices D] [--minutes M] [--seed S] [--no-restart] [--port P] [--data-dir DIR] [--session NAME] [--label L]');
  process.exit(2);
}
const args = parseArgs(rest);
run(args).then((report) => {
  process.exit(report.violationSummary.total === 0 ? 0 : 1);
}).catch((err) => {
  console.error('arena run failed:', err);
  process.exit(3);
});

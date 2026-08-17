#!/usr/bin/env node
// GOOBY latest_native-Bump (W13C/RELEASE; Doc B §5.2, zweite Hälfte).
//
// Setzt in einem BESTEHENDEN Update-Manifest (Release-Asset manifest.json am
// rollenden Tag `updates`, Schema: docs/UPDATES.md §3) das Feld
// `latest_native` auf die frisch released App-Version — der Client zeigt
// älteren Installationen daraufhin „Neue App-Version nötig“
// (scripts/updates/manifest.gd liest das Feld, update_service.gd wertet aus).
//
// BEWUSST kein Neubau des Manifests: tools/packs/build_manifest.mjs braucht
// die gebauten Pack-Artefakte; beim IPA-Release sollen die Pack-Einträge
// aber unangetastet bleiben. Dieses Script patcht NUR latest_native (+
// published_at) und lässt alles andere byte-identisch.
//
// Verwendung (s. auskommentierten Step im release-Job von
// .github/workflows/gooby-godot.yml — aktiv, sobald der `updates`-Release
// existiert):
//   gh release download updates --pattern manifest.json --dir manifest-bump
//   node tools/ci/bump_latest_native.mjs \
//     --manifest manifest-bump/manifest.json --version 5.1.0
//   gh release upload updates manifest-bump/manifest.json --clobber
//
// Fail-closed: ungültiges Semver, kaputtes/unbekanntes Manifest oder ein
// DOWNGRADE (neue Version < vorhandenes latest_native) → Exit 1, Datei
// bleibt unangetastet. Gleiche Version erneut = ok (idempotente Re-Runs).
// --published-at erlaubt deterministische Tests (Zeit injizierbar).
import { readFileSync, writeFileSync } from "node:fs";

function arg(name, fallback = "") {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] !== undefined ? process.argv[i + 1] : fallback;
}

function fail(message) {
  console.error(`FEHLER: ${message}`);
  process.exit(1);
}

const SEMVER = /^\d+\.\d+\.\d+$/;

function semverParts(version) {
  return version.split(".").map((part) => Number.parseInt(part, 10));
}

// -1 / 0 / 1 wie ein Comparator (nur für strikte MAJOR.MINOR.PATCH-Strings).
function semverCompare(a, b) {
  const pa = semverParts(a);
  const pb = semverParts(b);
  for (let i = 0; i < 3; i += 1) {
    if (pa[i] !== pb[i]) return pa[i] < pb[i] ? -1 : 1;
  }
  return 0;
}

const manifestPath = arg("manifest");
const version = arg("version");
const publishedAt = arg("published-at", new Date().toISOString());

if (!manifestPath) fail("--manifest <pfad/zu/manifest.json> fehlt.");
if (!SEMVER.test(version)) {
  fail(`--version '${version}' ist kein striktes Semver (MAJOR.MINOR.PATCH, z. B. 5.1.0).`);
}

let raw;
try {
  raw = readFileSync(manifestPath, "utf8");
} catch (error) {
  fail(`Manifest nicht lesbar: ${manifestPath} (${error.message})`);
}

let manifest;
try {
  manifest = JSON.parse(raw);
} catch (error) {
  fail(`Manifest ist kein gültiges JSON: ${error.message}`);
}

if (typeof manifest !== "object" || manifest === null || Array.isArray(manifest)) {
  fail("Manifest ist kein JSON-Objekt.");
}
if (manifest.schema !== 1) {
  fail(`Unbekanntes Manifest-Schema '${manifest.schema}' — dieses Script kennt nur 1.`);
}

const previous = typeof manifest.latest_native === "string" ? manifest.latest_native : "";
if (SEMVER.test(previous) && semverCompare(version, previous) < 0) {
  fail(
    `Downgrade verweigert: latest_native ist bereits ${previous}, angefragt ${version}. ` +
      "(Alte Apps würden sonst fälschlich 'alles aktuell' sehen.)"
  );
}

manifest.latest_native = version;
manifest.published_at = publishedAt;

// Tab-Einrückung + abschließender Zeilenumbruch — identisch zu
// tools/packs/build_manifest.mjs, damit Diffs der Release-Assets sauber bleiben.
writeFileSync(manifestPath, `${JSON.stringify(manifest, null, "\t")}\n`);
console.log(
  `latest_native: ${previous || "(leer)"} -> ${version} (${manifestPath}, published_at=${publishedAt})`
);

#!/usr/bin/env node
// GOOBY Manifest-Builder (W2b UPDATES; Doc B §1.4/§5.1).
//
// Erzeugt <dir>/manifest.json aus den in <dir> liegenden Pack-Artefakten
// (<id>-v<ver>.pck + config.json). Version/min_native/priority/notes_de kommen
// aus GOOBY-GODOT/content/<id>/pack.json, sha256/size aus der gebauten Datei,
// latest_native aus project.godot (application/config/version).
//
// Aufruf: node tools/packs/build_manifest.mjs --project GOOBY-GODOT \
//           --dir GOOBY-GODOT/build/packs [--base-url URL] [--tag-mode single|per-pack]
// URL-Schema:
//   --base-url leer      -> file://<abs-pfad>          (lokale DEV-Tests)
//   --tag-mode single    -> <base>/updates/<datei>      (rollender Release-Tag)
//   --tag-mode per-pack  -> <base>/<id>-v<ver>/<datei>  (unveraenderliche Tags,
//                           Zielbild Doc B §1.3 — config haengt immer an updates)
import { createHash } from "node:crypto";
import { readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { resolve, join } from "node:path";

function arg(name, fallback = "") {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] !== undefined ? process.argv[i + 1] : fallback;
}

const project = resolve(arg("project", "GOOBY-GODOT"));
const dir = resolve(arg("dir", join(project, "build", "packs")));
const baseUrl = arg("base-url", "").replace(/\/+$/, "");
const tagMode = arg("tag-mode", "single");

function sha256(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

function packMeta(id) {
  const raw = readFileSync(join(project, "content", id, "pack.json"), "utf8");
  return JSON.parse(raw);
}

function urlFor(id, ver, file) {
  if (!baseUrl) return `file://${join(dir, file)}`;
  if (tagMode === "per-pack" && id !== "config") return `${baseUrl}/${id}-v${ver}/${file}`;
  return `${baseUrl}/updates/${file}`;
}

function latestNative() {
  const env = process.env.LATEST_NATIVE;
  if (env) return env;
  const godotProject = readFileSync(join(project, "project.godot"), "utf8");
  const m = godotProject.match(/^config\/version="([^"]+)"/m);
  return m ? m[1] : "5.0.0";
}

const packs = [];
for (const file of readdirSync(dir).sort()) {
  let id = "";
  let ver = "";
  let type = "pck";
  const pckMatch = file.match(/^([a-z0-9_]+)-v(\d+\.\d+\.\d+)\.pck$/);
  if (pckMatch) {
    [, id, ver] = pckMatch;
  } else if (file === "config.json") {
    id = "config";
    type = "json";
  } else {
    continue;
  }
  const meta = packMeta(id);
  if (!ver) ver = meta.version;
  if (ver !== meta.version) {
    console.error(`FEHLER: ${file} (v${ver}) != content/${id}/pack.json (v${meta.version}).`);
    process.exit(1);
  }
  const path = join(dir, file);
  packs.push({
    id,
    version: ver,
    type,
    url: urlFor(id, ver, file),
    sha256: sha256(path),
    size: statSync(path).size,
    min_native: meta.min_native ?? "5.0.0",
    priority: meta.priority ?? 900,
    notes_de: meta.notes_de ?? "",
  });
}

if (packs.length === 0) {
  console.error(`FEHLER: keine Pack-Artefakte in ${dir} gefunden.`);
  process.exit(1);
}
packs.sort((a, b) => a.priority - b.priority);

const manifest = {
  schema: 1,
  latest_native: latestNative(),
  notes_de: process.env.MANIFEST_NOTES_DE ?? "",
  published_at: new Date().toISOString(),
  packs,
};

const outPath = join(dir, "manifest.json");
writeFileSync(outPath, `${JSON.stringify(manifest, null, "\t")}\n`);
console.log(`manifest.json geschrieben: ${outPath} (${packs.length} Packs)`);

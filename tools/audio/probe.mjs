// Hörbarkeits-Beweis (ART-PLAN §4): rendert ALLE Event→Datei-Mappings als
// HTML-Testseite (Event + Play-Button, neue Mappings markiert) und prüft per
// ffprobe, dass jede referenzierte Datei existiert, > 0 s lang und dekodierbar
// ist. Dazu der Lautstärke-Check: ffmpeg-loudnorm misst jede Datei; weicht ein
// NEUER Sound > 6 dB vom Familien-Median ab, schlägt die Probe fehl (Bestand
// wird nur gewarnt — Kenney-Packs bleiben unangetastet).
//
//   node tools/audio/probe.mjs            → Report + tools/audio/probe.html
//   node tools/audio/probe.mjs --schnell  → ohne Loudness-Messung
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HIER = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HIER, "..", "..");
const PUBLIC_AUDIO = join(REPO, "client", "public", "audio");
const SCHNELL = process.argv.includes("--schnell");

// Neue Beschaffungen dieser Runde (assets/audio/extern/**) — für die
// NEU-Markierung auf der Testseite und den harten Loudness-Gate.
const NEUE_DATEIEN = new Set(
  existsSync(join(REPO, "assets", "audio", "extern"))
    ? readdirSync(join(REPO, "assets", "audio", "extern"))
    : [],
);

// ---------- 1) Mapping aus der einen Quelle der Wahrheit (sound-map.ts) ----------
const mapping = JSON.parse(
  execFileSync("npx", ["tsx", join(HIER, "probe-daten.ts")], {
    cwd: REPO,
    encoding: "utf8",
  }),
);

/** Web-Pfad (/audio/…) → Dateisystem-Pfad unter client/public/audio. */
const fsPfad = (webPfad) => join(PUBLIC_AUDIO, webPfad.replace(/^\/audio\//, ""));
const istNeu = (webPfad) => NEUE_DATEIEN.has(webPfad.split("/").at(-1));
const familieVon = (webPfad) => webPfad.split("/")[2]; // sfx | crowd | musik

const alleDateien = new Map(); // webPfad → { familie, events: [] }
for (const [id, def] of Object.entries(mapping.sfx)) {
  for (const d of def.dateien) {
    const e = alleDateien.get(d) ?? { familie: familieVon(d), events: [] };
    e.events.push(id);
    alleDateien.set(d, e);
  }
}
for (const [ebene, d] of Object.entries(mapping.musik)) {
  const e = alleDateien.get(d) ?? { familie: familieVon(d), events: [] };
  e.events.push(`musik:${ebene}`);
  alleDateien.set(d, e);
}

// ---------- 2) ffprobe-Check: existiert, Dauer > 0, dekodierbar ----------
const fehler = [];
const warnungen = [];
const befunde = new Map(); // webPfad → { dauer, lufs }

for (const [webPfad] of alleDateien) {
  const pfad = fsPfad(webPfad);
  if (!existsSync(pfad)) {
    fehler.push(`FEHLT: ${webPfad} (erwartet: ${pfad})`);
    continue;
  }
  let dauer = 0;
  try {
    dauer = Number(
      execFileSync(
        "ffprobe",
        ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", pfad],
        { encoding: "utf8" },
      ).trim(),
    );
  } catch {
    fehler.push(`NICHT DEKODIERBAR: ${webPfad}`);
    continue;
  }
  if (!(dauer > 0)) {
    fehler.push(`DAUER 0: ${webPfad}`);
    continue;
  }
  befunde.set(webPfad, { dauer, lufs: null });
}

// ---------- 3) Loudness-Check (ffmpeg loudnorm, Familien-Median ± 6 dB) ----------
if (!SCHNELL) {
  for (const [webPfad, b] of befunde) {
    // ffmpeg druckt den loudnorm-JSON-Block nach STDERR (Exit-Code 0).
    const lauf = spawnSync(
      "ffmpeg",
      [
        "-hide_banner",
        "-i",
        fsPfad(webPfad),
        "-af",
        "loudnorm=print_format=json",
        "-f",
        "null",
        "-",
      ],
      { encoding: "utf8" },
    );
    const text = String(lauf.stderr ?? "");
    const i = text.lastIndexOf("{");
    if (i >= 0) {
      try {
        b.lufs = Number(JSON.parse(text.slice(i)).input_i);
      } catch {
        warnungen.push(`Loudness nicht messbar: ${webPfad}`);
      }
    } else {
      warnungen.push(`Loudness nicht messbar: ${webPfad}`);
    }
  }
}

const median = (werte) => {
  const s = [...werte].sort((a, b) => a - b);
  return s.length === 0 ? null : s[Math.floor(s.length / 2)];
};

const abweichungen = [];
if (!SCHNELL) {
  const proFamilie = new Map();
  for (const [webPfad, b] of befunde) {
    if (b.lufs === null || !Number.isFinite(b.lufs)) continue;
    const fam = alleDateien.get(webPfad).familie;
    proFamilie.set(fam, [...(proFamilie.get(fam) ?? []), b.lufs]);
  }
  for (const [webPfad, b] of befunde) {
    if (b.lufs === null || !Number.isFinite(b.lufs)) continue;
    const fam = alleDateien.get(webPfad).familie;
    const m = median(proFamilie.get(fam));
    const delta = b.lufs - m;
    if (Math.abs(delta) > 6) {
      const meldung =
        `${webPfad}: ${b.lufs.toFixed(1)} LUFS weicht ${delta.toFixed(1)} dB ` +
        `vom ${fam}-Median (${m.toFixed(1)}) ab`;
      abweichungen.push({ webPfad, meldung, neu: istNeu(webPfad) });
      if (istNeu(webPfad)) fehler.push(`LOUDNESS: ${meldung}`);
      else warnungen.push(`Loudness (Bestand): ${meldung}`);
    }
  }
}

// ---------- 4) HTML-Testseite (Event + Play-Button, NEU markiert) ----------
const zeilen = [];
const eventZeile = (id, def, neu) => {
  const knoepfe = def.dateien
    .map((d, i) => {
      const rel = `../../client/public${d}`;
      const name = d.split("/").at(-1);
      return `<button data-src="${rel}" class="datei">${def.layers ? "≣" : `${i + 1}·`} ${name}</button>`;
    })
    .join(" ");
  const alle = JSON.stringify(def.dateien.map((d) => `../../client/public${d}`));
  return `<tr class="${neu ? "neu" : ""}"><td>${neu ? "🆕 " : ""}<code>${id}</code></td>
    <td><button class="event" data-layers="${def.layers}" data-srcs='${alle}'>▶ Event</button></td>
    <td>${knoepfe}</td><td>${def.gain}</td></tr>`;
};
for (const [id, def] of Object.entries(mapping.sfx)) {
  zeilen.push(eventZeile(id, def, def.dateien.some(istNeu)));
}
for (const [ebene, d] of Object.entries(mapping.musik)) {
  zeilen.push(eventZeile(`musik:${ebene}`, { dateien: [d], gain: 1, layers: false }, istNeu(d)));
}

const html = `<!doctype html>
<html lang="de"><head><meta charset="utf-8"><title>MONKEY MONEY — Sound-Probe</title>
<style>
  body { font: 15px/1.5 system-ui; background: #0E2A1F; color: #FFF6E3; padding: 24px; }
  h1 { color: #FFC93C; } .hinweis { color: #8FE04B; }
  table { border-collapse: collapse; width: 100%; }
  td, th { border-bottom: 1px solid #14532D; padding: 6px 10px; text-align: left; vertical-align: top; }
  tr.neu { background: #14532D; }
  button { background: #F5B301; border: 2px solid #1A1208; border-radius: 8px; padding: 4px 10px;
           font-weight: 700; cursor: pointer; margin: 1px; }
  button.datei { background: #29D9D5; font-weight: 400; }
  code { color: #FFDE6B; }
</style></head><body>
<h1>🐒💰 Sound-Probe — alle Event-Mappings</h1>
<p class="hinweis">Direkt aus <code>client/shared/fx/sound-map.ts</code> generiert
(node tools/audio/probe.mjs). 🆕 = in dieser Runde beschaffte Dateien
(assets/audio/extern). „▶ Event" spielt Layer gleichzeitig bzw. die erste
Round-Robin-Variante; Standard-Buzzer-Slots: ${mapping.standardBuzzer.join(" → ")}.</p>
<table><tr><th>Event</th><th></th><th>Dateien (einzeln anspielen)</th><th>Gain</th></tr>
${zeilen.join("\n")}
</table>
<script>
  document.addEventListener("click", (e) => {
    const b = e.target.closest("button"); if (!b) return;
    if (b.classList.contains("datei")) { new Audio(b.dataset.src).play(); return; }
    const srcs = JSON.parse(b.dataset.srcs);
    if (b.dataset.layers === "true") srcs.forEach((s) => new Audio(s).play());
    else new Audio(srcs[0]).play();
  });
</script></body></html>`;
writeFileSync(join(HIER, "probe.html"), html);

// ---------- 5) Report ----------
console.log(
  `Sound-Probe: ${alleDateien.size} Dateien in ${Object.keys(mapping.sfx).length} SFX-Events`,
);
console.log(
  `+ ${Object.keys(mapping.musik).length} Musik-Ebenen — Testseite: tools/audio/probe.html`,
);
console.log("");
const breite = Math.max(...[...befunde.keys()].map((p) => p.length));
for (const [webPfad, b] of [...befunde].sort()) {
  const lufs =
    b.lufs === null
      ? SCHNELL
        ? "—"
        : "n/a"
      : Number.isFinite(b.lufs)
        ? `${b.lufs.toFixed(1)} LUFS`
        : "(zu kurz für LUFS)";
  console.log(
    `  ${webPfad.padEnd(breite)}  ${b.dauer.toFixed(2).padStart(6)} s  ${lufs}` +
      (istNeu(webPfad) ? "  🆕" : ""),
  );
}
console.log("");
for (const w of warnungen) console.log(`  ⚠ ${w}`);
if (fehler.length > 0) {
  console.error("\nPROBE FEHLGESCHLAGEN:");
  for (const f of fehler) console.error(`  ✗ ${f}`);
  process.exit(1);
}
console.log(`\n✓ Alle ${befunde.size} referenzierten Dateien existieren, Dauer > 0, dekodierbar.`);
if (!SCHNELL) {
  console.log(
    abweichungen.filter((a) => a.neu).length === 0
      ? "✓ Kein NEUER Sound weicht > 6 dB vom Familien-Median ab."
      : "✗ Loudness-Abweichungen bei neuen Sounds (siehe oben).",
  );
}

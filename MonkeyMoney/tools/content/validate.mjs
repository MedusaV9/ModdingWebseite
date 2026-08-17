#!/usr/bin/env node
/* global process, console */
// Content-Validator — hartes Gate aus docs/CONTENT-PLAN.md §2.5 (14 Regeln).
// Nur Node-Builtins. Aufruf:
//   node tools/content/validate.mjs                 # alle Packs unter content/packs/
//   node tools/content/validate.mjs pfad/zu/pack.json [...]
// Exit-Code 1 bei Fehlern (F). Warnungen (W) blockieren nicht.
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const CONTENT_DIR = path.join(REPO, "content");
const PACKS_DIR = path.join(CONTENT_DIR, "packs");

// ---------- Enums (Plan §2.2) ----------
const SCHWIERIGKEITEN = ["leicht", "mittel", "schwer", "ultrahard"];
const REGIONEN = ["de", "global"];
const TYPEN = [
  "choice",
  "wahr_falsch",
  "schaetz",
  "sortier",
  "bild_pixel",
  "audio",
  "emoji",
  "mehrfach",
];
const ALTERSFREIGABEN = ["ab0", "ab12", "ab18"];
const FAKTENCHECK_STATI = ["entwurf", "geprueft", "community"];
const LIZENZ_ALLOWLIST = ["eigen", "CC0", "Public Domain", "CC-BY 3.0", "CC-BY 4.0", "OGA-BY 3.0"];
const ATTRIBUTIONS_LIZENZEN = ["CC-BY 3.0", "CC-BY 4.0", "OGA-BY 3.0"];

// Pflichtfelder aller Typen (Plan §2.2) — typ-spezifische Inhalts-Felder s. TYP_FELDER.
const BASIS_PFLICHT = [
  "id",
  "schema_version",
  "kategorie",
  "unterkategorie",
  "schwierigkeit",
  "region",
  "typ",
  "altersfreigabe",
  "tags",
  "text",
  "tipps",
  "erklaerung",
  "quelle",
  "stand_datum",
  "verfallsdatum",
  "faktencheck_status",
  "erstellt_von",
  "erstellt_am",
];

// Inhalts-Felder je Typ (Plan §2.3): pflicht + optional; alles andere = typfremd (Regel 3).
const ALLE_INHALTS_FELDER = [
  "antworten",
  "korrekt",
  "korrekt_bool",
  "schaetz",
  "elemente",
  "korrekt_reihenfolge",
  "aufloesung_werte",
  "emojis",
  "freitext_akzeptanzen",
  "korrekt_mehrfach",
  "medien",
];
const TYP_FELDER = {
  choice: { pflicht: ["antworten", "korrekt"], optional: ["medien"] },
  wahr_falsch: { pflicht: ["korrekt_bool"], optional: [] },
  schaetz: { pflicht: ["schaetz"], optional: [] },
  sortier: { pflicht: ["elemente", "korrekt_reihenfolge", "aufloesung_werte"], optional: [] },
  bild_pixel: { pflicht: ["antworten", "korrekt", "medien"], optional: [] },
  audio: { pflicht: ["antworten", "korrekt", "medien"], optional: [] },
  emoji: { pflicht: ["emojis", "antworten", "korrekt"], optional: ["freitext_akzeptanzen"] },
  mehrfach: { pflicht: ["antworten", "korrekt_mehrfach"], optional: [] },
};

// Verfalls-Heuristik (Regel 9) + Verbots-Muster (Regel 13).
const VERFALLS_WOERTER = /(aktuell|derzeit|amtierend|neuest|zurzeit|momentan|dieses jahr)/i;
const META_OPTIONEN = /(alle (oben )?genannten|keine der genannten)/i;
const NEGATIONS_WORT = /\b(nicht|kein|keine|keinen|keiner|keinem|keines|nie|niemals|niemand)\b/gi;

// ---------- Helfer ----------
const ARTIKEL = new Set([
  "der",
  "die",
  "das",
  "ein",
  "eine",
  "einen",
  "einem",
  "einer",
  "eines",
  "dem",
  "den",
  "des",
]);

/** Normalisierung für Duplikat-/Tipp-Checks: lowercase, ohne Satzzeichen/Artikel (Regel 6/11). */
function normalisiere(text) {
  return String(text)
    .toLowerCase()
    .replace(/[^a-z0-9äöüßéèáàê\s]/gu, " ")
    .split(/\s+/)
    .filter((w) => w.length > 0 && !ARTIKEL.has(w))
    .join(" ");
}

function zeichenLaenge(s) {
  return [...String(s)].length;
}

const GRAPHEM_SEGMENTER = new Intl.Segmenter("de", { granularity: "grapheme" });

/** Zählt Emojis (Grapheme mit Extended_Pictographic) — Regel 4: 3–7. */
function emojiAnzahl(s) {
  let n = 0;
  for (const seg of GRAPHEM_SEGMENTER.segment(String(s))) {
    if (/\p{Extended_Pictographic}/u.test(seg.segment)) n += 1;
  }
  return n;
}

function trigramme(s) {
  const t = new Set();
  const p = `  ${s} `;
  for (let i = 0; i < p.length - 2; i += 1) t.add(p.slice(i, i + 3));
  return t;
}

/** Dice-Koeffizient über Trigramme — Fuzzy-Duplikat (Regel 11, Warnung ab 0,85). */
function aehnlichkeit(a, b) {
  const ta = trigramme(a);
  const tb = trigramme(b);
  if (ta.size === 0 || tb.size === 0) return 0;
  let gemeinsam = 0;
  for (const g of ta) if (tb.has(g)) gemeinsam += 1;
  return (2 * gemeinsam) / (ta.size + tb.size);
}

function istIsoDatum(s) {
  return typeof s === "string" && /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(s));
}

function sammlePackDateien(wurzel) {
  const dateien = [];
  const stapel = [wurzel];
  while (stapel.length > 0) {
    const dir = stapel.pop();
    if (!existsSync(dir)) continue;
    for (const eintrag of readdirSync(dir)) {
      const voll = path.join(dir, eintrag);
      if (statSync(voll).isDirectory()) stapel.push(voll);
      else if (eintrag.endsWith(".json")) dateien.push(voll);
    }
  }
  return dateien.sort();
}

/** Korrekte Antwort(en) als Strings — für Tipp-Leak- und Duplikat-Paar-Checks. */
function korrekteAntworten(f) {
  if (["choice", "bild_pixel", "audio", "emoji"].includes(f.typ)) {
    if (Array.isArray(f.antworten) && Number.isInteger(f.korrekt))
      return [f.antworten[f.korrekt]].filter(Boolean);
  }
  if (f.typ === "mehrfach" && Array.isArray(f.antworten) && Array.isArray(f.korrekt_mehrfach)) {
    return f.korrekt_mehrfach.map((i) => f.antworten[i]).filter(Boolean);
  }
  if (f.typ === "schaetz" && f.schaetz && typeof f.schaetz.richtwert === "number") {
    return [String(f.schaetz.richtwert)];
  }
  if (f.typ === "wahr_falsch") return []; // Tipps sind ohnehin leer.
  return []; // sortier: keine Einzel-Antwort.
}

// ---------- Validierung ----------
const funde = []; // { schwere: "F"|"W", code, datei, frageId, meldung }
function fehler(code, datei, frageId, meldung) {
  funde.push({ schwere: "F", code, datei, frageId, meldung });
}
function warnung(code, datei, frageId, meldung) {
  funde.push({ schwere: "W", code, datei, frageId, meldung });
}

function ladeTaxonomie() {
  const roh = readFileSync(path.join(CONTENT_DIR, "taxonomie.json"), "utf8");
  const tax = JSON.parse(roh);
  const ober = new Set(tax.oberkategorien.map((o) => o.id));
  const unter = new Map(tax.unterkategorien.map((u) => [u.slug, u]));
  return { ober, unter };
}

function pruefePackMeta(datei, pack, taxonomie) {
  const meta = pack.pack_meta;
  if (!meta || typeof meta !== "object") {
    fehler("F14", datei, "-", "pack_meta fehlt (Pack-Format: { pack_meta, fragen })");
    return;
  }
  for (const feld of [
    "name",
    "oberkategorie",
    "unterkategorie",
    "schema_version",
    "sprache",
    "anzahl",
  ]) {
    if (!(feld in meta)) fehler("F14", datei, "-", `pack_meta.${feld} fehlt`);
  }
  if (meta.schema_version !== 1)
    fehler("F02", datei, "-", `pack_meta.schema_version muss 1 sein (ist: ${meta.schema_version})`);
  if (meta.sprache !== "de")
    fehler("F02", datei, "-", `pack_meta.sprache muss "de" sein (ist: ${meta.sprache})`);
  if (Array.isArray(pack.fragen) && meta.anzahl !== pack.fragen.length) {
    fehler(
      "F14",
      datei,
      "-",
      `pack_meta.anzahl (${meta.anzahl}) != fragen.length (${pack.fragen.length})`,
    );
  }
  if (meta.oberkategorie !== null && !taxonomie.ober.has(meta.oberkategorie)) {
    fehler("F02", datei, "-", `pack_meta.oberkategorie "${meta.oberkategorie}" nicht in Taxonomie`);
  }
  if (meta.unterkategorie !== null) {
    const u = taxonomie.unter.get(meta.unterkategorie);
    if (!u)
      fehler(
        "F02",
        datei,
        "-",
        `pack_meta.unterkategorie "${meta.unterkategorie}" nicht in Taxonomie`,
      );
    else if (u.oberkategorie !== meta.oberkategorie) {
      fehler(
        "F02",
        datei,
        "-",
        `pack_meta: "${meta.unterkategorie}" gehört zu "${u.oberkategorie}", nicht zu "${meta.oberkategorie}"`,
      );
    }
  }
}

// Regel-5-Zusatz (W): Positions-Bias — verrät die POSITION die richtige Antwort?
// Hintergrund: Seed-W1 hatte korrekt=0 bei 123/123 choice-artigen Fragen.
function pruefePositionsBias(datei, pack) {
  const choiceArtig = pack.fragen.filter(
    (f) =>
      ["choice", "bild_pixel", "audio", "emoji"].includes(f.typ) && Number.isInteger(f.korrekt),
  );
  if (choiceArtig.length >= 8) {
    const zaehl = new Map();
    for (const f of choiceArtig) zaehl.set(f.korrekt, (zaehl.get(f.korrekt) ?? 0) + 1);
    const [topIdx, topN] = [...zaehl.entries()].sort((a, b) => b[1] - a[1])[0];
    if (topN > choiceArtig.length / 2) {
      warnung(
        "W05",
        datei,
        "-",
        `Positions-Bias: korrekt=${topIdx} bei ${topN}/${choiceArtig.length} choice-artigen Fragen — Antworten mischen!`,
      );
    }
  }
  for (const f of pack.fragen) {
    if (
      f.typ === "sortier" &&
      Array.isArray(f.korrekt_reihenfolge) &&
      f.korrekt_reihenfolge.join(",") === "0,1,2,3"
    ) {
      warnung(
        "W05",
        datei,
        f.id ?? "-",
        "sortier: Elemente stehen bereits in korrekter Reihenfolge — mischen!",
      );
    }
  }
}

function pruefeFrage(datei, f, taxonomie, packMeta) {
  const id = typeof f.id === "string" ? f.id : "(ohne id)";

  // Regel 3 (Teil 1): Basis-Pflichtfelder.
  for (const feld of BASIS_PFLICHT) {
    if (!(feld in f)) fehler("F03", datei, id, `Pflichtfeld "${feld}" fehlt`);
  }
  if (f.schema_version !== 1)
    fehler("F02", datei, id, `schema_version muss 1 sein (ist: ${f.schema_version})`);

  // Regel 2: Slugs + Enums.
  if (!taxonomie.ober.has(f.kategorie))
    fehler("F02", datei, id, `kategorie "${f.kategorie}" nicht in Taxonomie 1.1`);
  const unterEintrag = taxonomie.unter.get(f.unterkategorie);
  if (!unterEintrag)
    fehler("F02", datei, id, `unterkategorie "${f.unterkategorie}" nicht in Taxonomie 1.2`);
  else if (unterEintrag.oberkategorie !== f.kategorie) {
    fehler(
      "F02",
      datei,
      id,
      `unterkategorie "${f.unterkategorie}" gehört zu "${unterEintrag.oberkategorie}", nicht zu "${f.kategorie}"`,
    );
  }
  if (!SCHWIERIGKEITEN.includes(f.schwierigkeit))
    fehler("F02", datei, id, `schwierigkeit "${f.schwierigkeit}" ∉ ${SCHWIERIGKEITEN.join("|")}`);
  if (!REGIONEN.includes(f.region)) fehler("F02", datei, id, `region "${f.region}" ∉ de|global`);
  if (!TYPEN.includes(f.typ)) {
    fehler("F02", datei, id, `typ "${f.typ}" ∉ ${TYPEN.join("|")}`);
    return; // ohne gültigen Typ sind die Folge-Checks sinnlos
  }
  if (!ALTERSFREIGABEN.includes(f.altersfreigabe))
    fehler("F02", datei, id, `altersfreigabe "${f.altersfreigabe}" ∉ ab0|ab12|ab18`);
  if (!FAKTENCHECK_STATI.includes(f.faktencheck_status))
    fehler(
      "F02",
      datei,
      id,
      `faktencheck_status "${f.faktencheck_status}" ∉ entwurf|geprueft|community`,
    );
  if (f.kategorie === "deutschland_spezial" && f.region !== "de") {
    fehler("F02", datei, id, "deutschland_spezial ist per Definition komplett region=de (Plan §1)");
  }

  // Regel 1: ID-Format + Präfix passt zu kategorie/unterkategorie.
  if (typeof f.id !== "string" || !/^q_[a-z0-9_]+_[0-9]{6}$/.test(f.id)) {
    fehler("F01", datei, id, "id matcht nicht ^q_[a-z0-9_]+_[0-9]{6}$");
  } else if (
    f.kategorie &&
    f.unterkategorie &&
    !f.id.startsWith(`q_${f.kategorie}_${f.unterkategorie}_`)
  ) {
    fehler("F01", datei, id, `id-Präfix passt nicht zu q_${f.kategorie}_${f.unterkategorie}_`);
  }
  if (packMeta && packMeta.unterkategorie !== null && packMeta.unterkategorie !== undefined) {
    if (f.unterkategorie !== packMeta.unterkategorie) {
      fehler(
        "F02",
        datei,
        id,
        `Frage-unterkategorie "${f.unterkategorie}" != Pack-unterkategorie "${packMeta.unterkategorie}"`,
      );
    }
  }

  // Regel 3 (Teil 2): Typ-Pflichtfelder + typfremde Felder.
  const typFelder = TYP_FELDER[f.typ];
  for (const feld of typFelder.pflicht) {
    if (!(feld in f)) fehler("F03", datei, id, `Typ ${f.typ}: Pflichtfeld "${feld}" fehlt`);
  }
  const erlaubt = new Set([...typFelder.pflicht, ...typFelder.optional]);
  for (const feld of ALLE_INHALTS_FELDER) {
    if (feld in f && !erlaubt.has(feld))
      fehler("F03", datei, id, `Typ ${f.typ}: typfremdes Feld "${feld}"`);
  }

  // Regel 4: Längen-Gates.
  if (typeof f.text === "string" && zeichenLaenge(f.text) > 190)
    fehler("F04", datei, id, `text ${zeichenLaenge(f.text)} > 190 Zeichen`);
  const antwortListen = [f.antworten, f.elemente].filter(Array.isArray);
  for (const liste of antwortListen) {
    for (const a of liste) {
      if (zeichenLaenge(a) > 40)
        fehler("F04", datei, id, `Antwort/Element "${a}" ${zeichenLaenge(a)} > 40 Zeichen`);
    }
  }
  if (Array.isArray(f.tipps)) {
    for (const t of f.tipps) {
      if (zeichenLaenge(t) > 90)
        fehler("F04", datei, id, `Tipp "${t.slice(0, 30)}…" ${zeichenLaenge(t)} > 90 Zeichen`);
    }
  }
  if (typeof f.erklaerung === "string" && zeichenLaenge(f.erklaerung) > 220) {
    fehler("F04", datei, id, `erklaerung ${zeichenLaenge(f.erklaerung)} > 220 Zeichen`);
  }
  if (f.typ === "emoji" && typeof f.emojis === "string") {
    const n = emojiAnzahl(f.emojis);
    if (n < 3 || n > 7) fehler("F04", datei, id, `emojis: ${n} Emojis (erlaubt 3–7)`);
  }

  // Regel 5: Antwort-Strukturen je Typ (inkl. Typ-Regeln aus §2.3).
  if (["choice", "bild_pixel", "audio", "emoji"].includes(f.typ)) {
    if (!Array.isArray(f.antworten) || f.antworten.length !== 4) {
      fehler(
        "F05",
        datei,
        id,
        `genau 4 Antworten nötig (ist: ${Array.isArray(f.antworten) ? f.antworten.length : typeof f.antworten})`,
      );
    } else {
      const norm = f.antworten.map(normalisiere);
      if (new Set(norm).size !== 4)
        fehler("F05", datei, id, "Antworten nicht paarweise verschieden");
    }
    if (!Number.isInteger(f.korrekt) || f.korrekt < 0 || f.korrekt > 3)
      fehler("F05", datei, id, `korrekt muss Index 0–3 sein (ist: ${f.korrekt})`);
  }
  if (f.typ === "mehrfach") {
    if (!Array.isArray(f.antworten) || f.antworten.length !== 6)
      fehler("F05", datei, id, "mehrfach: genau 6 Antworten nötig");
    else if (new Set(f.antworten.map(normalisiere)).size !== 6)
      fehler("F05", datei, id, "mehrfach: Antworten nicht paarweise verschieden");
    if (
      !Array.isArray(f.korrekt_mehrfach) ||
      f.korrekt_mehrfach.length !== 2 ||
      new Set(f.korrekt_mehrfach).size !== 2 ||
      f.korrekt_mehrfach.some((i) => !Number.isInteger(i) || i < 0 || i > 5)
    ) {
      fehler(
        "F05",
        datei,
        id,
        "mehrfach: korrekt_mehrfach muss genau 2 verschiedene Indizes 0–5 enthalten",
      );
    }
  }
  if (f.typ === "sortier") {
    if (
      !Array.isArray(f.elemente) ||
      f.elemente.length !== 4 ||
      new Set(f.elemente.map(normalisiere)).size !== 4
    ) {
      fehler("F05", datei, id, "sortier: genau 4 paarweise verschiedene Elemente nötig");
    }
    const r = f.korrekt_reihenfolge;
    if (!Array.isArray(r) || r.length !== 4 || [...new Set(r)].sort().join(",") !== "0,1,2,3") {
      fehler("F05", datei, id, "sortier: korrekt_reihenfolge muss Permutation von 0–3 sein");
    }
    if (!Array.isArray(f.aufloesung_werte) || f.aufloesung_werte.length !== 4) {
      fehler("F05", datei, id, "sortier: aufloesung_werte muss genau 4 Strings enthalten");
    }
  }
  if (f.typ === "schaetz") {
    const s = f.schaetz;
    if (!s || typeof s !== "object") fehler("F05", datei, id, "schaetz-Objekt fehlt");
    else {
      if (typeof s.richtwert !== "number")
        fehler("F05", datei, id, "schaetz.richtwert muss Zahl sein");
      if (typeof s.einheit !== "string" || s.einheit.length === 0)
        fehler("F05", datei, id, "schaetz.einheit fehlt");
      if (
        typeof s.toleranz_prozent !== "number" ||
        s.toleranz_prozent < 1 ||
        s.toleranz_prozent > 50
      ) {
        fehler("F05", datei, id, `schaetz.toleranz_prozent ${s.toleranz_prozent} ∉ 1–50`);
      }
      if (
        s.toleranz_absolut !== undefined &&
        (typeof s.toleranz_absolut !== "number" || s.toleranz_absolut <= 0)
      ) {
        fehler("F05", datei, id, `schaetz.toleranz_absolut ${s.toleranz_absolut} muss > 0 sein`);
      }
      // Jahreszahl-Regel: Kalenderjahre brauchen ein ABSOLUTES Fenster —
      // 1 % von 1969 wären ±20 Jahre (tools/content/fix-jahr-toleranzen.mjs).
      const kalenderjahr =
        s.einheit === "Jahr v. Chr." ||
        (s.einheit === "Jahr" &&
          typeof s.richtwert === "number" &&
          s.richtwert >= 1000 &&
          s.richtwert <= 2100);
      if (kalenderjahr && typeof s.toleranz_absolut !== "number") {
        fehler("F05", datei, id, "Kalenderjahr-Frage ohne schaetz.toleranz_absolut (2–5 Jahre)");
      }
      if (!(
        typeof s.eingabe_min === "number" &&
        typeof s.eingabe_max === "number" &&
        s.eingabe_min < s.richtwert &&
        s.richtwert < s.eingabe_max
      )) {
        fehler(
          "F05",
          datei,
          id,
          `schaetz: eingabe_min < richtwert < eingabe_max verletzt (${s.eingabe_min} / ${s.richtwert} / ${s.eingabe_max})`,
        );
      }
      if (!["linear", "log"].includes(s.skala))
        fehler("F05", datei, id, `schaetz.skala "${s.skala}" ∉ linear|log`);
    }
  }

  // Regel 6: genau 3 Tipps (0 bei wahr_falsch); kein Tipp enthält die Antwort.
  const sollTipps = f.typ === "wahr_falsch" ? 0 : 3;
  if (!Array.isArray(f.tipps) || f.tipps.length !== sollTipps) {
    fehler(
      "F06",
      datei,
      id,
      `genau ${sollTipps} Tipps nötig (ist: ${Array.isArray(f.tipps) ? f.tipps.length : typeof f.tipps})`,
    );
  }
  if (Array.isArray(f.tipps)) {
    for (const antwort of korrekteAntworten(f)) {
      const normAntwort = normalisiere(antwort);
      if (normAntwort.length < 2) continue;
      for (const [i, tipp] of f.tipps.entries()) {
        if (normalisiere(tipp).includes(normAntwort)) {
          fehler("F06", datei, id, `Tipp ${i + 1} enthält die korrekte Antwort ("${antwort}")`);
        }
      }
    }
  }

  // Regel 7: erklaerung nicht leer.
  if (typeof f.erklaerung !== "string" || f.erklaerung.trim().length === 0)
    fehler("F07", datei, id, "erklaerung ist leer");

  // Regel 8: Kuration — stand_datum IMMER (Plan §5.3); Vier-Augen bei geprueft.
  if (!istIsoDatum(f.stand_datum))
    fehler("F08", datei, id, `stand_datum fehlt oder kein ISO-Datum (ist: ${f.stand_datum})`);
  if (typeof f.quelle !== "string" || f.quelle.trim().length === 0)
    fehler("F08", datei, id, "quelle fehlt");
  if (f.faktencheck_status === "geprueft") {
    if (!/^https?:\/\//.test(String(f.quelle)))
      fehler("F08", datei, id, "geprueft: quelle muss URL sein");
    if (typeof f.faktencheck_notiz !== "string" || f.faktencheck_notiz.trim().length === 0)
      fehler("F08", datei, id, "geprueft: faktencheck_notiz fehlt");
    if (typeof f.geprueft_von !== "string" || f.geprueft_von.trim().length === 0)
      fehler("F08", datei, id, "geprueft: geprueft_von fehlt");
    else if (f.geprueft_von === f.erstellt_von)
      fehler("F08", datei, id, "geprueft: geprueft_von == erstellt_von (Vier-Augen verletzt)");
  }
  if (f.verfallsdatum !== null && f.verfallsdatum !== undefined && !istIsoDatum(f.verfallsdatum)) {
    fehler(
      "F08",
      datei,
      id,
      `verfallsdatum muss null oder ISO-Datum sein (ist: ${f.verfallsdatum})`,
    );
  }

  // Regel 9: Verfalls-Heuristik.
  if (
    typeof f.text === "string" &&
    VERFALLS_WOERTER.test(f.text) &&
    !istIsoDatum(f.verfallsdatum)
  ) {
    fehler(
      "F09",
      datei,
      id,
      `text enthält Verfalls-Wort (${f.text.match(VERFALLS_WOERTER)[0]}) → verfallsdatum PFLICHT`,
    );
  }

  // Regel 10: Medien.
  if (f.medien) {
    const m = f.medien;
    if (!LIZENZ_ALLOWLIST.includes(m.lizenz))
      fehler("F10", datei, id, `medien.lizenz "${m.lizenz}" nicht in Allowlist (7.2)`);
    if (ATTRIBUTIONS_LIZENZEN.includes(m.lizenz) && (!m.autor || !m.quelle_url)) {
      fehler("F10", datei, id, `medien: ${m.lizenz} verlangt autor + quelle_url`);
    }
    if (["wikimedia", "cc_pack"].includes(m.quelle_art) && !m.quelle_url)
      fehler("F10", datei, id, `medien: quelle_art ${m.quelle_art} verlangt quelle_url`);
    if (["bild_pixel", "audio"].includes(f.typ)) {
      // Pfad relativ zu content/ ODER zum Repo-Root (z. B. assets/img/generated/…).
      const existiert =
        typeof m.datei === "string" &&
        (existsSync(path.join(CONTENT_DIR, m.datei)) || existsSync(path.join(REPO, m.datei)));
      if (!existiert) {
        fehler(
          "F10",
          datei,
          id,
          `medien.datei existiert nicht: ${m.datei} (content/ oder Repo-Root)`,
        );
      }
    }
    if (f.typ === "bild_pixel" && m.spoiler_sicher !== true)
      fehler("F10", datei, id, "bild_pixel: spoiler_sicher muss true sein");
    if (f.typ === "audio" && typeof m.datei === "string" && !m.datei.endsWith(".ogg"))
      fehler("F10", datei, id, "audio: medien.datei muss .ogg sein");
  }

  // Regel 12 (W): Antwortlängen-Balance.
  if (
    Array.isArray(f.antworten) &&
    f.antworten.length >= 4 &&
    f.antworten.every((a) => typeof a === "string")
  ) {
    const laengen = f.antworten.map(zeichenLaenge);
    const min = Math.min(...laengen);
    const max = Math.max(...laengen);
    if (min > 0 && max > 2 * min) {
      warnung("W12", datei, id, `Antwortlängen unausgewogen: längste ${max} > 2× kürzeste ${min}`);
    }
  }

  // Regel 13 (W): Verbots-Muster.
  if (Array.isArray(f.antworten)) {
    for (const a of f.antworten) {
      if (META_OPTIONEN.test(String(a))) warnung("W13", datei, id, `Meta-Option verboten: "${a}"`);
    }
  }
  if (typeof f.text === "string") {
    const negationen = f.text.match(NEGATIONS_WORT) ?? [];
    if (negationen.length >= 2)
      warnung("W13", datei, id, `mögliche Doppel-Negation im text (${negationen.join(", ")})`);
    const aussageTypen = ["wahr_falsch", "sortier"];
    // „?“ darf vor einem schließenden Anführungszeichen stehen („…‚Wetten, dass..?'“).
    if (!aussageTypen.includes(f.typ) && !/\?["'’‘“”«»‹›)\]]*\s*$/.test(f.text)) {
      warnung("W13", datei, id, "Frage endet nicht mit „?“ (außer Aussage-Typen)");
    }
  }
}

// ---------- Hauptlauf ----------
function main() {
  const args = process.argv.slice(2);
  const dateien = args.length > 0 ? args.map((a) => path.resolve(a)) : sammlePackDateien(PACKS_DIR);
  if (dateien.length === 0) {
    console.error(`Keine Pack-Dateien gefunden unter ${PACKS_DIR}`);
    process.exit(1);
  }

  const taxonomie = ladeTaxonomie();
  const alleFragen = []; // { datei, frage }
  const idNutzung = new Map();

  for (const voll of dateien) {
    const datei = path.relative(REPO, voll);
    let pack;
    try {
      // Regel 14: valides UTF-8-JSON (Format-Idempotenz erzwingt repo-weit Prettier via npm run lint).
      pack = JSON.parse(readFileSync(voll, "utf8"));
    } catch (e) {
      fehler("F14", datei, "-", `kein valides UTF-8-JSON: ${e.message}`);
      continue;
    }
    if (!Array.isArray(pack.fragen)) {
      fehler("F14", datei, "-", "fragen[] fehlt (Pack-Format: { pack_meta, fragen })");
      continue;
    }
    pruefePackMeta(datei, pack, taxonomie);
    pruefePositionsBias(datei, pack);
    for (const f of pack.fragen) {
      pruefeFrage(datei, f, taxonomie, pack.pack_meta);
      alleFragen.push({ datei, frage: f });
      if (typeof f.id === "string") {
        if (!idNutzung.has(f.id)) idNutzung.set(f.id, []);
        idNutzung.get(f.id).push(datei);
      }
    }
  }

  // Regel-5-Zusatz (W, global): identisches korrekt_mehrfach-Set bei allen mehrfach-Fragen.
  const mehrfachFragen = alleFragen.filter(
    ({ frage }) => frage.typ === "mehrfach" && Array.isArray(frage.korrekt_mehrfach),
  );
  if (mehrfachFragen.length >= 3) {
    const sets = new Set(
      mehrfachFragen.map(({ frage }) => [...frage.korrekt_mehrfach].sort().join(",")),
    );
    if (sets.size === 1) {
      warnung(
        "W05",
        "(global)",
        "-",
        `alle ${mehrfachFragen.length} mehrfach-Fragen haben dasselbe korrekt_mehrfach-Set — Antworten mischen!`,
      );
    }
  }

  // Regel 1 (global): eindeutige IDs.
  for (const [id, orte] of idNutzung) {
    if (orte.length > 1) fehler("F01", orte[1], id, `id mehrfach vergeben (${orte.join(" + ")})`);
  }

  // Regel 11: Duplikate (exakt = F, fuzzy/gleiches Paar = W). Beim emoji-Typ
  // gehört die Emoji-Kette zum Vergleichsschlüssel (die Rätsel-Identität liegt
  // in den Emojis, der Rahmentext „Welcher Film ist das?“ wiederholt sich fair).
  const nachNormText = new Map();
  const nachAntwortPaar = new Map();
  for (const { datei, frage } of alleFragen) {
    if (typeof frage.text !== "string" || typeof frage.id !== "string") continue;
    const norm =
      frage.typ === "emoji"
        ? `${normalisiere(frage.text)} ${frage.emojis ?? ""}`
        : normalisiere(frage.text);
    if (nachNormText.has(norm)) {
      const erst = nachNormText.get(norm);
      fehler("F11", datei, frage.id, `exaktes Text-Duplikat von ${erst.id} (${erst.datei})`);
    } else {
      nachNormText.set(norm, { id: frage.id, datei, norm });
    }
    for (const antwort of korrekteAntworten(frage)) {
      const schluessel = `${frage.unterkategorie}::${normalisiere(antwort)}`;
      if (nachAntwortPaar.has(schluessel)) {
        const erst = nachAntwortPaar.get(schluessel);
        warnung(
          "W11",
          datei,
          frage.id,
          `gleiches Paar Antwort+Unterkategorie wie ${erst} („${antwort}“)`,
        );
      } else {
        nachAntwortPaar.set(schluessel, frage.id);
      }
    }
  }
  const normListe = [...nachNormText.values()];
  for (let i = 0; i < normListe.length; i += 1) {
    for (let j = i + 1; j < normListe.length; j += 1) {
      const s = aehnlichkeit(normListe[i].norm, normListe[j].norm);
      if (s >= 0.85) {
        warnung(
          "W11",
          normListe[j].datei,
          normListe[j].id,
          `Fuzzy-Duplikat (${Math.round(s * 100)} %) von ${normListe[i].id}`,
        );
      }
    }
  }

  // ---------- Report ----------
  const fehlerFunde = funde.filter((f) => f.schwere === "F");
  const warnFunde = funde.filter((f) => f.schwere === "W");
  for (const fund of funde) {
    const prefix = fund.schwere === "F" ? "FEHLER" : "WARNUNG";
    console.log(`[${fund.code}] ${prefix} · ${fund.datei} · ${fund.frageId} · ${fund.meldung}`);
  }
  console.log("—".repeat(72));
  console.log(
    `Validator: ${dateien.length} Pack-Datei(en), ${alleFragen.length} Fragen → ` +
      `${fehlerFunde.length} Fehler, ${warnFunde.length} Warnung(en)`,
  );
  if (fehlerFunde.length > 0) {
    console.log("→ Fehler beheben; Codes F01–F14 = Plan §2.5 Regel-Nummern.");
    process.exit(1);
  }
  console.log("→ OK: alle harten Gates (F) bestanden.");
}

main();

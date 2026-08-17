// Requisiten der Erklär-Demos: kleine, wiederverwendbare lit-html-Komponenten
// im tokens.css-Look (Sticker-Prinzip, harte Schatten, Outline-Warm-Schwarz).
// Reine Präsentation: DemoRequisit rein, TemplateResult raus — Zustandswechsel
// zwischen Beats tweent CSS (nur transform/opacity), neue Elemente ploppen ein.
import { html, type TemplateResult } from "lit-html";
import type { DemoAkteur, DemoRequisit } from "../../shared/minigames/demo-typen";

const OPTIONEN = [
  { buchstabe: "A", emoji: "🍌" },
  { buchstabe: "B", emoji: "🥥" },
  { buchstabe: "C", emoji: "🐒" },
  { buchstabe: "D", emoji: "🌴" },
] as const;

/** Marker-Klassen einer Antwort-Option (Tipp-Farben, Auflösung grün/rot). */
function optionKlasse(
  i: number,
  r: { tippA?: number | null; tippB?: number | null; richtig?: number | null },
): string {
  const teile = ["ed-option"];
  if (r.tippA === i) teile.push("tipp-a");
  if (r.tippB === i) teile.push("tipp-b");
  if (r.richtig !== null && r.richtig !== undefined) {
    if (r.richtig === i) teile.push("richtig");
    else if (r.tippA === i || r.tippB === i) teile.push("falsch");
  }
  return teile.join(" ");
}

function frageKarte(r: Extract<DemoRequisit, { art: "frage" }>): TemplateResult {
  if (r.verdeckt) {
    return html`<div class="ed-frage verdeckt">
      <div class="ed-frage-text">🔒 ❓❓❓</div>
      <div class="ed-frage-meta">nur Kategorie + Schwierigkeit bekannt</div>
    </div>`;
  }
  return html`<div class="ed-frage">
    <div class="ed-frage-text">Frage läuft …</div>
    <div class="ed-optionen">
      ${OPTIONEN.map(
        (o, i) => html`<span class=${optionKlasse(i, r)}>${o.buchstabe} ${o.emoji}</span>`,
      )}
    </div>
  </div>`;
}

function buzzer(r: Extract<DemoRequisit, { art: "buzzer" }>): TemplateResult {
  return html`<div class="ed-buzzer ${r.gedrueckt ? `gedrueckt von-${r.gedrueckt}` : ""}">
    <span>BUZZ</span>
  </div>`;
}

function slider(r: Extract<DemoRequisit, { art: "slider" }>): TemplateResult {
  const marke = (wert: number | null | undefined, wer: DemoAkteur): TemplateResult =>
    wert === null || wert === undefined
      ? html``
      : html`<span class="ed-slider-marke von-${wer}" style="--pos:${wert}">▲</span>`;
  return html`<div class="ed-slider">
    <div class="ed-slider-bahn">
      <div class="ed-slider-griff" style="--pos:${r.wert}">🍌</div>
      ${
        r.ziel === null || r.ziel === undefined
          ? ""
          : html`<span class="ed-slider-ziel" style="--pos:${r.ziel}">🚩</span>`
      }
    </div>
    <div class="ed-slider-marken">${marke(r.markerA, "a")} ${marke(r.markerB, "b")}</div>
  </div>`;
}

function tueren(r: Extract<DemoRequisit, { art: "tueren" }>): TemplateResult {
  return html`<div class="ed-tueren">
    ${OPTIONEN.map((o, i) => {
      const a = r.chipsA?.[i] ?? 0;
      const b = r.chipsB?.[i] ?? 0;
      const offen = r.offen === i;
      const daneben = r.offen !== null && r.offen !== undefined && !offen && a + b > 0;
      return html`<div class="ed-tuer ${offen ? "offen" : ""} ${daneben ? "daneben" : ""}">
        <span class="ed-tuer-kopf">${o.buchstabe} ${o.emoji}</span>
        <span class="ed-tuer-chips">
          ${a > 0 ? html`<span class="ed-chip von-a">${a}</span>` : ""}
          ${b > 0 ? html`<span class="ed-chip von-b">${b}</span>` : ""}
        </span>
        ${offen ? html`<span class="ed-tuer-mal">×2</span>` : ""}
      </div>`;
    })}
  </div>`;
}

function kette(r: Extract<DemoRequisit, { art: "kette" }>): TemplateResult {
  return html`<div class="ed-kette ${r.gerissen ? "gerissen" : ""}">
    ${r.glieder.map(
      (g, i) =>
        html`<span class="ed-glied ${i === r.glieder.length - 1 ? "aktiv" : ""}">${g}</span>`,
    )}
    ${
      r.bankVon
        ? html`<span class="ed-bank-knopf von-${r.bankVon}">BANK!</span>`
        : r.gerissen
          ? html`<span class="ed-kette-riss">💥</span>`
          : ""
    }
  </div>`;
}

function banane(r: Extract<DemoRequisit, { art: "banane" }>): TemplateResult {
  if (r.geplatzt) {
    return html`<div class="ed-banane ed-ort-${r.bei} geplatzt">💥🍌💩</div>`;
  }
  return html`<div class="ed-banane ed-ort-${r.bei} ${r.hektisch ? "hektisch" : ""}">🍌</div>`;
}

function pixel(r: Extract<DemoRequisit, { art: "pixel" }>): TemplateResult {
  // Entpixeln über Block-Opacity (nur opacity — kein Filter, kein Layout).
  const bloecke = Array.from({ length: 24 }, (_, i) => i);
  return html`<div class="ed-pixel">
    <div class="ed-pixel-bild" style="--schaerfe:${r.schaerfe}">
      <span class="ed-pixel-motiv">🦜</span>
      <div class="ed-pixel-raster">
        ${bloecke.map(
          (i) =>
            html`<span
              class="ed-pixel-block"
              style="--block-huelle:${((i * 7) % 24) / 24}"
            ></span>`,
        )}
      </div>
    </div>
    <span class="ed-pixel-preis">${r.preis}</span>
  </div>`;
}

function leiter(r: Extract<DemoRequisit, { art: "leiter" }>): TemplateResult {
  return html`<div class="ed-leiter ${r.perfekt ? "perfekt" : ""}">
    ${r.stufen.map((s) => html`<span class="ed-sprosse">${s}</span>`)}
    ${r.perfekt ? html`<span class="ed-leiter-bonus">PERFEKT!</span>` : ""}
  </div>`;
}

function sack(r: Extract<DemoRequisit, { art: "sack" }>): TemplateResult {
  return html`<div class="ed-sack">
    <span class="ed-sack-beutel">💰</span>
    <span class="ed-sack-betrag">${r.betrag}</span>
    ${r.eingefrorenA ? html`<span class="ed-frost von-a">❄ ${r.eingefrorenA}</span>` : ""}
    ${r.eingefrorenB ? html`<span class="ed-frost von-b">❄ ${r.eingefrorenB}</span>` : ""}
  </div>`;
}

function lianen(r: Extract<DemoRequisit, { art: "lianen" }>): TemplateResult {
  const seil = (hoehe: number, wer: DemoAkteur): TemplateResult =>
    html`<div class="ed-liane">
      <span class="ed-kletterer von-${wer}" style="--hoehe:${hoehe}">🐵</span>
    </div>`;
  return html`<div class="ed-lianen">
    ${seil(r.hoeheA, "a")} ${seil(r.hoeheB, "b")}
    <span class="ed-kroko ${r.schnappt ? `schnappt zu-${r.schnappt}` : ""}">🐊</span>
  </div>`;
}

function steg(): TemplateResult {
  return html`<div class="ed-steg">
    <span class="ed-steg-planke"></span>
    <span class="ed-steg-seil"></span>
  </div>`;
}

function schild(r: Extract<DemoRequisit, { art: "schild" }>): TemplateResult {
  return html`<span class="ed-schild ton-${r.ton ?? "papier"} ed-ort-${r.bei ?? "mitte"}">
    ${r.text}
  </span>`;
}

/** Requisit → Template (der Bühnen-Renderer mappt die Szene-Liste). */
export function requisitTpl(r: DemoRequisit): TemplateResult {
  switch (r.art) {
    case "frage":
      return frageKarte(r);
    case "buzzer":
      return buzzer(r);
    case "slider":
      return slider(r);
    case "tueren":
      return tueren(r);
    case "kette":
      return kette(r);
    case "banane":
      return banane(r);
    case "pixel":
      return pixel(r);
    case "leiter":
      return leiter(r);
    case "sack":
      return sack(r);
    case "lianen":
      return lianen(r);
    case "steg":
      return steg();
    case "schild":
      return schild(r);
  }
}

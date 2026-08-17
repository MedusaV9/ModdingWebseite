// Studio-Bausteine des Screens: Podien mit Gelenk-Puppen + wachsenden
// Geldstapeln, LED-Fragen-Wand, Jackpot-Glas, Ticker-Kopfzeile.
// Die Puppen-SVGs füllt main.ts nach jedem render() via fuellePuppen().
import { html, svg, type SVGTemplateResult, type TemplateResult } from "lit-html";
import { kategorieLabel } from "../../shared/kategorien";
import { formatMM } from "../../shared/money";
import type { ScreenView, SpielerPublic } from "../../shared/views";
import { avatarFarbe } from "../shared/fx/avatar";
import type { Gesicht } from "../shared/fx/affe";

const jackpotGlasUrl = new URL("../../assets/img/money/jackpot-glas.svg", import.meta.url).href;

export type GesichtsMap = Record<string, Gesicht>;

/** Podien-Reihe (Zone C): eine Bühne pro Spieler, Reihenfolge = Join-Reihenfolge.
 * Team-Modus: der Aufrufer sortiert nach Teams und liefert teamFarben —
 * die Farbe wird als Pult-Rahmen gerendert (Team-Gruppierung, §1.4). */
export function podiumReihe(
  players: SpielerPublic[],
  opts: {
    gesichter?: GesichtsMap;
    einflug?: boolean;
    siegerId?: string;
    teamFarben?: Record<string, string>;
  } = {},
): TemplateResult {
  return html`<div class="studio-podien">${players.map((p, i) => podium(p, i, opts))}</div>`;
}

function podium(
  p: SpielerPublic,
  index: number,
  opts: {
    gesichter?: GesichtsMap;
    einflug?: boolean;
    siegerId?: string;
    teamFarben?: Record<string, string>;
  },
): TemplateResult {
  const gesicht = opts.gesichter?.[p.id] ?? "neutral";
  const teamFarbe = opts.teamFarben?.[p.id];
  const klassen = [
    "podium",
    p.connected ? "" : "offline",
    p.clown ? "clown" : "",
    opts.einflug ? "einflug" : "",
    opts.siegerId === p.id ? "sieger" : "",
  ].join(" ");
  return html`<div
    class=${klassen}
    data-spieler=${p.id}
    style="--spielerfarbe:${avatarFarbe(p.avatar)};--einflug-index:${index};--kipp:${index % 2 === 0 ? "-1.5deg" : "1.5deg"}"
  >
    <div
      class="podium-puppe mm-affe mm-affe-idle"
      data-avatar=${p.avatar}
      data-gesicht=${gesicht}
      style="--idle-versatz:${(index * 0.55).toFixed(2)}s"
    ></div>
    <div
      class="podium-pult"
      style=${
        teamFarbe !== undefined
          ? `border:3px solid ${teamFarbe};box-shadow:0 0 10px color-mix(in srgb, ${teamFarbe} 60%, transparent)`
          : ""
      }
    >
      ${
        // Geldstapel IM Pult: dockt an dessen Oberkante an (studio.css),
        // egal wie hoch Namensschild/Konto/Badges gerade rendern.
        geldstapel(p.balance)
      }
      <span class="podium-name">${p.name}</span>
      <span class="podium-konto">${formatMM(p.balance)}</span>
      <div class="podium-badges">
        ${p.streak >= 3 ? html`<span title="Streak">🔥${p.streak}</span>` : ""}
        ${p.rueckenwind ? html`<span title="Rückenwind">💨</span>` : ""}
        ${p.schild ? html`<span title="Bananentresor">🛡️</span>` : ""}
        ${p.clown ? html`<span title="Clown">🤡</span>` : ""}
        ${p.connected ? "" : html`<span class="badge-offline">offline</span>`}
      </div>
    </div>
  </div>`;
}

/** Geldstapel am Pult: Scheine wachsen mit dem Kontostand (geldstapel.svg-Fragment). */
function geldstapel(balance: number): TemplateResult {
  const scheine = Math.max(0, Math.min(12, Math.floor(balance / 200)));
  if (scheine === 0) return html``;
  // WICHTIG: svg`` statt html`` — nur so entstehen echte SVG-Elemente
  // (html`` außerhalb eines <svg>-Kontexts erzeugt tote HTMLUnknownElements).
  const lagen: SVGTemplateResult[] = [];
  for (let i = 0; i < scheine; i++) {
    const dx = ((i * 7) % 5) - 2;
    const rot = ((i * 5) % 7) - 3;
    lagen.push(
      svg`<use href="#mm-schein-flach" transform="translate(${dx} ${-9 * i}) rotate(${rot})" />`,
    );
  }
  return html`<svg
    class="podium-geld"
    viewBox="-50 ${-16 - 9 * scheine} 100 ${40 + 9 * scheine}"
    aria-hidden="true"
  >
    <defs>
      <g id="mm-schein-flach">
        <rect
          x="-46"
          y="-13"
          width="92"
          height="26"
          rx="4"
          fill="#85BB65"
          stroke="#1A1208"
          stroke-width="3.5"
        />
        <rect
          x="-38"
          y="-8"
          width="76"
          height="16"
          rx="2"
          fill="none"
          stroke="#FFF6E3"
          stroke-width="2"
        />
        <ellipse cx="0" cy="0" rx="9" ry="6.5" fill="#FFF6E3" stroke="#1A1208" stroke-width="2" />
        <circle cx="0" cy="0" r="3" fill="#6B4226" />
      </g>
    </defs>
    <g transform="translate(0 8)">${lagen}</g>
  </svg>`;
}

/** LED-Fragen-Wand (Zone B) — Rahmen für Frage-Inhalte im tokens.css-Look.
 * spannung=true: Zapp-/Flacker-Zustand des Auflösungs-Spannungs-Fensters. */
export function ledWand(inhalt: TemplateResult, spannung = false): TemplateResult {
  return html`<div class="led-wand ${spannung ? "spannung" : ""}">${inhalt}</div>`;
}

/** Jackpot-Glas (Zone D): schwebt rechts über den Podien, wackelt bei Einzahlung. */
export function jackpotGlas(betrag: number, gefuettert: boolean): TemplateResult {
  if (betrag <= 0) return html``;
  return html`<div class="jackpot-glas ${gefuettert ? "gefuettert" : ""}">
    <img src=${jackpotGlasUrl} alt="Jackpot-Glas" />
    <span class="betrag">${formatMM(betrag)}</span>
  </div>`;
}

/** Ticker-Kopfzeile (Zone A): Fragen-Zähler, Abschnitt, Modifier, Töpfe. */
export function studioKopf(view: ScreenView): TemplateResult {
  const a = view.abschnitt;
  return html`<div class="studio-kopf">
    <span class="zaehler">Frage ${view.frageNr} / ${view.frageTotal}</span>
    ${
      a
        ? a.typ === "runde"
          ? html`<span>Runde ${a.rundeNr}/${a.rundenTotal} · ${a.minigameName}</span>`
          : a.typ === "jackpot"
            ? html`<span class="gold">🍯 JACKPOT-FRAGE</span>`
            : html`<span class="gold"
                >🔥 FINALE ${a.wFinal ? `(${formatMM(a.wFinal)}/Frage)` : ""}</span
              >`
        : ""
    }
    ${view.modifiers.map((m) => html`<span title=${m.scope}>⭐ ${m.name}</span>`)}
    ${view.pott > 0 ? html`<span class="gold">💰 Pott ${formatMM(view.pott)}</span>` : ""}
  </div>`;
}

/** Kategorie-Icon aus assets/img/ui/kategorien/ (IDs = Dateinamen). */
const kategorieIconUrls = new Map<string, string>();
for (const id of [
  "deutschland_spezial",
  "essen_trinken",
  "filme_serien",
  "gaming",
  "geographie",
  "geschichte",
  "internet_memes",
  "kunst_literatur",
  "kurioses_mixed",
  "musik",
  "sport",
  "technik_autos",
  "tiere_natur",
  "wissenschaft",
]) {
  kategorieIconUrls.set(
    id,
    new URL(`../../assets/img/ui/kategorien/${id}.svg`, import.meta.url).href,
  );
}

export function kategorieIcon(kategorie: string): string | null {
  return kategorieIconUrls.get(kategorie) ?? null;
}

/** "essen_trinken" → "Essen & Trinken" — zentraler Taxonomie-Helper (löst
 * auch Unterkategorie-Slugs wie „staedte_wahrzeichen" sauber auf). */
export function kategorieName(kategorie: string): string {
  return kategorieLabel(kategorie);
}

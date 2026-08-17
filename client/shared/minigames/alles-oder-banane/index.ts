// Client-Renderer „Alles oder Banane" (GAME-DESIGN §2.9): Screen = Teaser
// (nur Kategorie + Schwierigkeit) mit verdeckten Geldsäcken, dann Reveal ALLER
// Einsätze mit Trommelwirbel (einzeln aufgedeckt via Stagger), dann MC-4.
// Player = Einsatz-Slider in 50er-Rasterung + „EINLOGGEN", danach 4 Buttons.
import { html, render } from "lit-html";
import { kategorieLabel } from "../../../../shared/kategorien";
import {
  ALLES_ODER_BANANE_ID,
  AOB_EINSATZ_MIN,
  AOB_SCHRITT,
} from "../../../../shared/minigames/alles-oder-banane.meta";
import { formatMM } from "../../../../shared/money";
import { timerBalken } from "../../ui";
import type { FxApi, MinigameClientModule, SendAction } from "../types";
import "./alles-oder-banane.css";

const DEKO = [
  { buchstabe: "A", emoji: "🍌", farbe: "#e6b830" },
  { buchstabe: "B", emoji: "🥥", farbe: "#8a5a3b" },
  { buchstabe: "C", emoji: "🐒", farbe: "#d1495b" },
  { buchstabe: "D", emoji: "🌴", farbe: "#2e8b57" },
] as const;

const SCHWIERIGKEIT_LABEL: Record<string, string> = {
  easy: "LEICHT",
  medium: "MITTEL",
  hard: "SCHWER",
  ultrahard: "ULTRAHARD",
};

interface AobEinsatzView {
  betrag: number;
  gratis: boolean;
}

interface AllesOderBananeView {
  questionId: string;
  phase: "setzen" | "reveal" | "frage";
  kategorie: string;
  schwierigkeit: string;
  endsAt: number;
  timerMs: number;
  eingeloggt: string[];
  einsaetze: Record<string, AobEinsatzView> | null;
  text: string | null;
  options: string[] | null;
  sichtbarAb: number;
  geraeteMischung: boolean;
  answeredCount: number;
  spielerZahl: number;
  finished: boolean;
  yourEinsatz?: AobEinsatzView | null;
  einsatzMax?: number;
  gratisEinsatz?: boolean;
  yourChoice?: number | null;
  gesperrt?: number[];
  zweitversuch?: boolean;
  aufloesung: {
    correctIndex: number;
    erklaerung: string;
    perPlayer: {
      playerId: string;
      choice: number | null;
      correct: boolean;
      delta: number;
      einsatz: number | null;
      gratis: boolean;
    }[];
  } | null;
}

// Slider-Stand pro Frage (Renderer ist zustandslos, der Slider nicht).
let sliderFrage: string | null = null;
let sliderWert = AOB_EINSATZ_MIN;

// Trommelwirbel genau EINMAL pro Reveal (Edge-Detection).
let revealFuer: string | null = null;

function geldsack(fx: FxApi, playerId: string, einsatz: AobEinsatzView | null, index: number) {
  const info = fx.spieler?.(playerId) ?? null;
  return html`<div
    class="aob-sack ${einsatz !== null ? "offen" : "zu"}"
    style="--reveal-index:${index}"
  >
    <span class="aob-sack-emoji">💰</span>
    <span class="aob-sack-name">${info?.name ?? playerId}</span>
    <span class="aob-sack-betrag mm-money-zahl">
      ${einsatz !== null ? formatMM(einsatz.betrag) : "???"}
    </span>
    ${einsatz?.gratis === true ? html`<span class="aob-kredit">🏦 Kredit</span>` : ""}
  </div>`;
}

const modul: MinigameClientModule = {
  id: ALLES_ODER_BANANE_ID,

  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void {
    const v = view as AllesOderBananeView;

    if (v.phase === "reveal" && revealFuer !== v.questionId) {
      revealFuer = v.questionId;
      fx.sound("karten-mischen");
    }

    const teaser = html`<div class="aob-teaser">
      <span class="aob-teaser-label">Gleich:</span>
      <strong>${kategorieLabel(v.kategorie)}</strong>
      <span class="aob-schwierigkeit"
        >${SCHWIERIGKEIT_LABEL[v.schwierigkeit] ?? v.schwierigkeit}</span
      >
    </div>`;

    if (v.aufloesung) {
      render(
        html`<div class="aob-screen">
          <h2 style="text-align:center">🎲 Alles oder Banane — die Abrechnung!</h2>
          <p class="muted" style="text-align:center">${v.aufloesung.erklaerung}</p>
          <div class="aob-bilanz">
            ${[...v.aufloesung.perPlayer]
              .sort((a, b) => b.delta - a.delta)
              .map((r) => {
                const info = fx.spieler?.(r.playerId) ?? null;
                return html`<div class="aob-bilanz-zeile ${r.correct ? "gewonnen" : ""}">
                  <span>${r.correct ? "✅" : r.choice === null ? "😶" : "❌"}</span>
                  <span>${info?.name ?? r.playerId}</span>
                  <span class="muted"
                    >${r.einsatz !== null ? `Einsatz ${formatMM(r.einsatz)}` : "—"}</span
                  >
                  <strong
                    class="mm-money-zahl"
                    style="color:${r.delta >= 0 ? "var(--gold)" : "var(--rot)"}"
                  >
                    ${r.delta > 0 ? "+" : ""}${formatMM(r.delta)}
                  </strong>
                </div>`;
              })}
          </div>
        </div>`,
        host,
      );
      return;
    }

    if (v.phase !== "frage") {
      // SETZEN (Säcke zu) bzw. REVEAL (Säcke gehen gestaffelt auf).
      const offen = v.phase === "reveal" ? v.einsaetze : null;
      const saecke = v.phase === "reveal" ? Object.keys(v.einsaetze ?? {}) : v.eingeloggt;
      render(
        html`<div class="aob-screen">
          <h2 style="text-align:center">
            ${v.phase === "setzen" ? "🤫 Geheim setzen …" : "🥁 Die Einsätze!"}
          </h2>
          ${teaser} ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())}
          <div class="aob-saecke ${v.phase}">
            ${saecke.map((p, i) => geldsack(fx, p, offen?.[p] ?? null, i))}
          </div>
          <p class="muted" style="text-align:center">
            ${
              v.phase === "setzen"
                ? `${v.eingeloggt.length} / ${v.spielerZahl} eingeloggt — richtig = +Einsatz, falsch = weg!`
                : "Jetzt gibt es kein Zurück mehr …"
            }
          </p>
        </div>`,
        host,
      );
      return;
    }

    // FRAGE: MC-4 mit den Einsätzen als kleine Leiste darüber.
    render(
      html`<div class="aob-screen">
        <div class="aob-einsatz-leiste">
          ${Object.entries(v.einsaetze ?? {}).map(
            ([p, e]) =>
              html`<span class="aob-mini-sack">
                ${fx.spieler?.(p)?.name ?? p}: <strong>${formatMM(e.betrag)}</strong>
              </span>`,
          )}
        </div>
        <h2 class="aob-frage">${v.text ?? ""}</h2>
        ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())}
        <div class="aob-optionen">
          ${(v.options ?? []).map(
            (opt, i) =>
              html`<div
                class="aob-option ${v.gesperrt?.includes(i) ? "entfernt" : ""}"
                style="--deko:${DEKO[i].farbe}"
              >
                <span class="aob-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                ${opt}
              </div>`,
          )}
        </div>
        <p class="muted" style="text-align:center">
          ${v.answeredCount} / ${v.spielerZahl} eingerastet …
        </p>
      </div>`,
      host,
    );
  },

  renderPlayer(view: unknown, host: HTMLElement, send: SendAction, fx?: FxApi): void {
    const v = view as AllesOderBananeView;
    if (v.aufloesung) {
      render(html``, host); // Auflösung rendert die Player-App (kennt „you")
      return;
    }

    // ---------- SETZEN: Wett-Slider (50er-Raster) + EINLOGGEN ----------
    if (v.phase === "setzen") {
      const eingeloggt = v.yourEinsatz !== null && v.yourEinsatz !== undefined;
      if (eingeloggt) {
        render(
          html`<div class="aob-player">
            <div class="aob-status">
              💰 Einsatz eingeloggt:
              <strong class="mm-money-zahl">${formatMM(v.yourEinsatz!.betrag)}</strong>
              ${v.yourEinsatz!.gratis ? html`<br /><span class="muted">🏦 Kredit der Affenbank</span>` : ""}
              <br />
              <span class="muted">Warten auf die anderen Affen …</span>
            </div>
          </div>`,
          host,
        );
        return;
      }
      if (v.gratisEinsatz === true) {
        render(
          html`<div class="aob-player">
            <div class="aob-teaser">
              <span class="aob-teaser-label">Gleich:</span>
              <strong>${kategorieLabel(v.kategorie)}</strong>
              <span class="aob-schwierigkeit"
                >${SCHWIERIGKEIT_LABEL[v.schwierigkeit] ?? v.schwierigkeit}</span
              >
            </div>
            <div class="aob-status">
              🏦 Konto fast leer — die Bank stellt dir
              <strong class="mm-money-zahl">${formatMM(AOB_EINSATZ_MIN)}</strong> Gratis-Einsatz!
              <br />
              <span class="muted"
                >Falsch kostet nichts, richtig zahlt +${formatMM(AOB_EINSATZ_MIN)}.</span
              >
            </div>
            <button
              class="aob-einloggen"
              @click=${() => {
                fx?.sound("lockin-thunk");
                void send("einsatz", { betrag: AOB_EINSATZ_MIN });
              }}
            >
              EINLOGGEN
            </button>
          </div>`,
          host,
        );
        return;
      }
      const max = v.einsatzMax ?? 1_000;
      if (sliderFrage !== v.questionId) {
        sliderFrage = v.questionId;
        sliderWert = Math.min(max, AOB_EINSATZ_MIN);
      }
      sliderWert = Math.max(AOB_EINSATZ_MIN, Math.min(max, sliderWert));
      // Slider-Anzeige NUR über lit aktualisieren: direkte textContent-Mutation
      // zerstört den lit-Text-Node ⇒ Crash beim nächsten Snapshot-Rerender.
      const zeichneSetzen = (): void => {
        render(
          html`<div class="aob-player">
            <div class="aob-teaser">
              <span class="aob-teaser-label">Gleich:</span>
              <strong>${kategorieLabel(v.kategorie)}</strong>
              <span class="aob-schwierigkeit"
                >${SCHWIERIGKEIT_LABEL[v.schwierigkeit] ?? v.schwierigkeit}</span
              >
            </div>
            <div class="aob-slider-wert mm-money-zahl">${formatMM(sliderWert)}</div>
            <input
              class="aob-slider"
              type="range"
              min=${AOB_EINSATZ_MIN}
              max=${max}
              step=${AOB_SCHRITT}
              .value=${String(sliderWert)}
              @input=${(e: Event) => {
                sliderWert = Number((e.target as HTMLInputElement).value);
                zeichneSetzen();
              }}
            />
            <p class="muted" style="text-align:center;margin:0">
              ${formatMM(AOB_EINSATZ_MIN)} – ${formatMM(max)} (max. 50 % deines Kontos,
              50er-Schritte)
            </p>
            <button
              class="aob-einloggen"
              @click=${() => {
                fx?.sound("lockin-thunk");
                void send("einsatz", { betrag: sliderWert });
              }}
            >
              EINLOGGEN
            </button>
          </div>`,
          host,
        );
      };
      zeichneSetzen();
      return;
    }

    // ---------- REVEAL: die eigene Wette liegt, Trommelwirbel läuft ----------
    if (v.phase === "reveal") {
      render(
        html`<div class="aob-player">
          <div class="aob-status">
            🥁 Alle Einsätze werden aufgedeckt …
            <br />
            <strong class="mm-money-zahl">
              Dein Einsatz: ${v.yourEinsatz ? formatMM(v.yourEinsatz.betrag) : "—"}
            </strong>
          </div>
        </div>`,
        host,
      );
      return;
    }

    // ---------- FRAGE: 4 XXL-Buttons ----------
    const gewaehlt = v.yourChoice ?? null;
    render(
      html`<div class="aob-player">
        <p class="aob-frage-klein">
          ${v.text ?? ""}
          ${v.yourEinsatz ? html`<br /><span class="muted">Es geht um ${formatMM(v.yourEinsatz.betrag)}!</span>` : ""}
        </p>
        ${v.zweitversuch ? html`<p class="aob-zweitversuch">🔁 Rückgaberecht aktiv — Gewinn 50 %</p>` : ""}
        ${(v.options ?? []).map((opt, i) => {
          const entfernt = v.gesperrt?.includes(i) === true;
          return html`<button
            class="aob-button ${gewaehlt === i ? "gewaehlt" : ""} ${gewaehlt !== null ? "gesperrt" : ""} ${entfernt ? "entfernt" : ""}"
            style="--deko:${DEKO[i].farbe}"
            ?disabled=${gewaehlt !== null || entfernt}
            @click=${() => send("answer", { choice: i })}
          >
            <span class="aob-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
            ${opt}
          </button>`;
        })}
      </div>`,
      host,
    );
  },

  explainCard: {
    text: "Erst wird nur Kategorie + Schwierigkeit verraten — dann setzt jeder GEHEIM auf die eigene Antwort. Richtig = Einsatz verdoppelt, falsch = Einsatz weg!",
    animation: html`<span style="font-size:3rem">💰🤫🥁🎲</span>`,
  },
};

// Erklär-Demo (ADDITIV): erst GEHEIM setzen (nur Kategorie bekannt), dann
// antworten — richtig verdoppelt, falsch verbrennt den Einsatz.
export const demoChoreo: import("../demo-typen").DemoChoreo = {
  dauer: 10800,
  beats: [
    {
      at: 0,
      requisiten: [{ art: "frage", verdeckt: true }],
      pose: { a: "denk", b: "denk" },
      gesicht: { a: "denk", b: "denk" },
    },
    {
      at: 2400,
      requisiten: [
        { art: "frage", verdeckt: true },
        { art: "schild", text: "Einsatz: 200 MM 🤫", ton: "gold", bei: "a" },
        { art: "schild", text: "Einsatz: ALL-IN! 🙈", ton: "gold", bei: "b" },
      ],
      pose: { a: "zeig", b: "buzz" },
      gesicht: { a: "neutral", b: "jubel" },
      sound: "money-klein",
    },
    {
      at: 4800,
      requisiten: [{ art: "frage", tippA: 2, tippB: 0 }],
      pose: { a: "tipp", b: "tipp" },
      blase: { wer: "b", text: "Jetzt erst kommt die Frage!" },
      sound: "lockin-thunk",
    },
    {
      at: 7200,
      requisiten: [
        { art: "frage", tippA: 2, tippB: 0, richtig: 2 },
        { art: "schild", text: "×2 → 400 MM!", ton: "gold", bei: "a" },
        { art: "schild", text: "Einsatz weg!", ton: "rot", bei: "b" },
      ],
      pose: { a: "jubel", b: "frust" },
      gesicht: { a: "jubel", b: "frust" },
      geldflug: { von: "mitte", zu: "a" },
      effekt: "konfetti",
      sound: "richtig",
    },
  ],
};

export default modul;

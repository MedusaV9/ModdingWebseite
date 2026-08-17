// Client-Renderer „Stopp die Kokosnuss-Uhr": Screen = Geldsack mit 50-MM-Ticks +
// Timer-Banane + Eis-Overlays; Player = live schrumpfender Betrag + 4 XXL-Buttons.
// Sound-Mapping (ART-PLAN §4.1): Countdown-Tick pro Sack-Tick (tick_001), Lock-in-
// Thunk beim Einfrieren (impactPlank_medium_000), Zeit-um-Gong (impactBell_heavy_000)
// — wartet auf FxApi.sound() (Engine-Wunsch).
import { html, render } from "lit-html";
import { formatMM } from "../../../../shared/money";
import { sackWertBei } from "../../../../shared/minigames/kokosnuss-uhr.meta";
import { KOKOSNUSS_UHR_ID } from "../../../../shared/minigames/kokosnuss-uhr.meta";
import type { FxApi, MinigameClientModule, SendAction } from "../types";
import { timerBanane } from "./timer-banane";
import "./kokosnuss-uhr.css";

const DEKO = [
  { buchstabe: "A", emoji: "🍌", farbe: "var(--mm-banana, #e6b830)" },
  { buchstabe: "B", emoji: "🥥", farbe: "var(--mm-outline, #8a5a3b)" },
  { buchstabe: "C", emoji: "🐒", farbe: "var(--mm-curtain, #d1495b)" },
  { buchstabe: "D", emoji: "🌴", farbe: "var(--mm-leaf, #2e8b57)" },
] as const;

// Letzter angezeigter Sack-Wert pro Frage (für den Countdown-Tick-Sound).
const letzterSack = new Map<string, number>();

interface KokosnussView {
  questionId: string;
  text: string;
  options: string[];
  startedAt: number;
  endsAt: number;
  timerMs: number;
  sackStart: number;
  sackWert: number;
  tickIntervallMs: number;
  answeredCount: number;
  eingefrorene: { playerId: string; betrag: number }[];
  finished: boolean;
  yourChoice?: number | null;
  yourEingefroren?: number | null;
  aufloesung: {
    correctIndex: number;
    erklaerung: string;
    perPlayer: {
      playerId: string;
      choice: number | null;
      eingefroren: number;
      correct: boolean;
      delta: number;
    }[];
  } | null;
}

/** Live-Sack lokal aus serverNow gerechnet — DIESELBE Tick-Formel wie der Server. */
function liveSack(v: KokosnussView, serverNow: number): number {
  return sackWertBei(v.sackStart, v.tickIntervallMs, serverNow - v.startedAt);
}

function geldsack(betrag: number, sackStart: number): unknown {
  const anteil = sackStart > 0 ? betrag / sackStart : 0;
  return html`<div class="ku-sack mm-sticker" style="--fuellung:${anteil.toFixed(3)}">
    <span class="ku-sack-emoji" style="transform:scale(${(0.6 + 0.4 * anteil).toFixed(3)})"
      >💰</span
    >
    <span class="ku-sack-betrag mm-money-zahl">${formatMM(betrag)}</span>
  </div>`;
}

const modul: MinigameClientModule = {
  id: KOKOSNUSS_UHR_ID,

  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void {
    const v = view as KokosnussView;
    const correct = v.aufloesung?.correctIndex ?? -1;
    const sack = v.finished ? v.sackWert : liveSack(v, fx.serverNow());
    // Countdown-Tick pro Sack-Tick (ART-PLAN §4.1) — deterministisch am Sack-Wert.
    if (!v.finished && letzterSack.get(v.questionId) !== sack) {
      if (letzterSack.has(v.questionId)) fx.sound("tick");
      letzterSack.set(v.questionId, sack);
    }
    render(
      html`<div class="ku-screen">
        ${
          v.aufloesung
            ? html`<p class="muted" style="text-align:center">${v.aufloesung.erklaerung}</p>`
            : html`<div class="ku-kopf">
                ${geldsack(sack, v.sackStart)} ${timerBanane(v.endsAt, v.timerMs, fx.serverNow())}
              </div>`
        }
        <h2 class="ku-frage">${v.text}</h2>
        <div class="ku-optionen">
          ${v.options.map(
            (opt, i) =>
              html`<div
                class="ku-option ${v.aufloesung ? (i === correct ? "richtig" : "falsch") : ""}"
                style="--deko:${DEKO[i].farbe}"
                title=${opt}
              >
                <span class="ku-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                ${opt}
              </div>`,
          )}
        </div>
        ${
          v.aufloesung
            ? html`<div class="ku-eis-reihe">
                ${v.aufloesung.perPlayer.map(
                  (r) =>
                    html`<span class="ku-eis-chip ${r.correct ? "richtig" : ""}">
                      ${r.choice === null ? "💤" : r.correct ? "✅" : "❌"} ❄
                      ${formatMM(r.eingefroren)}
                      ${r.correct ? html`<strong>+${formatMM(r.delta)}</strong>` : ""}
                    </span>`,
                )}
              </div>`
            : html`<div class="ku-eis-reihe">
                ${v.eingefrorene.map(
                  (e) => html`<span class="ku-eis-chip">❄ ${formatMM(e.betrag)}</span>`,
                )}
                <span class="muted">${v.answeredCount} / ? eingefroren …</span>
              </div>`
        }
      </div>`,
      host,
    );
  },

  renderPlayer(view: unknown, host: HTMLElement, send: SendAction, fx?: FxApi): void {
    const v = view as KokosnussView;
    const gewaehlt = v.yourChoice ?? null;
    // Live-Betrag: tickt über das 150-ms-Re-Render der App — jetzt EXAKT auf
    // Server-Takt (Engine-Wunsch b erfüllt: fx.serverNow via time.ping-Offset).
    const sack = v.yourEingefroren ?? liveSack(v, fx?.serverNow() ?? lokalJetzt());
    render(
      html`<div class="ku-player">
        <div class="ku-player-sack ${gewaehlt !== null ? "eingefroren" : ""}">
          ${gewaehlt !== null ? "❄ Eingefroren bei" : "💰 Noch im Sack:"}
          <span class="ku-sack-betrag mm-money-zahl">${formatMM(sack)}</span>
        </div>
        <p class="ku-frage-klein">${v.text}</p>
        ${v.options.map(
          (opt, i) =>
            html`<button
              class="ku-button ${gewaehlt === i ? "gewaehlt" : ""} ${gewaehlt !== null ? "gesperrt" : ""}"
              style="--deko:${DEKO[i].farbe}"
              ?disabled=${gewaehlt !== null}
              @click=${() => send("answer", { choice: i })}
            >
              <span class="ku-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
              ${opt}
            </button>`,
        )}
        ${
          gewaehlt !== null
            ? html`<p class="muted" style="text-align:center">
                Sack eingefroren — richtig = ${formatMM(v.yourEingefroren ?? 0)}, falsch = 0!
              </p>`
            : ""
        }
      </div>`,
      host,
    );
  },

  explainCard: {
    text: "Der Geldsack über der Frage schrumpft alle paar Sekunden um 50 MM! Antworten friert DEINEN Sack ein: richtig = eingefrorener Betrag, falsch = 0.",
    animation: html`<span style="font-size:3rem">💰🥥⏰❄</span>`,
  },
};

// Anzeige-Näherung wie in client/shared/socket.ts: lokale Uhr NUR fürs Sack-Ticken
// zwischen Snapshots — die Wertung macht ausschließlich der Server (atServerTime).
// eslint-disable-next-line no-restricted-properties
const lokalJetzt = (): number => Date.now();

// Erklär-Demo (ADDITIV): der Geldsack schrumpft — Mia friert früh ein und
// kassiert, Bo wartet zu lang und geht leer aus.
export const demoChoreo: import("../demo-typen").DemoChoreo = {
  dauer: 11400,
  beats: [
    {
      at: 0,
      requisiten: [{ art: "sack", betrag: "500 MM" }],
      pose: { a: "denk", b: "denk" },
      gesicht: { a: "denk", b: "denk" },
    },
    {
      at: 2000,
      requisiten: [{ art: "sack", betrag: "450 MM", eingefrorenA: "450 MM" }],
      pose: { a: "tipp", b: "denk" },
      gesicht: { a: "neutral", b: "denk" },
      blase: { wer: "a", text: "Mia friert ein: 450!" },
      sound: "lockin-thunk",
    },
    {
      at: 4300,
      requisiten: [{ art: "sack", betrag: "350 MM", eingefrorenA: "450 MM" }],
      pose: { a: "idle", b: "denk" },
      gesicht: { a: "neutral", b: "denk" },
      blase: { wer: "b", text: "Bo wartet …" },
    },
    {
      at: 6600,
      requisiten: [{ art: "sack", betrag: "250 MM", eingefrorenA: "450 MM" }],
      pose: { a: "idle", b: "tipp" },
      blase: { wer: "b", text: "Bo: erst JETZT!" },
      sound: "lockin-thunk",
    },
    {
      at: 8600,
      requisiten: [
        { art: "sack", betrag: "250 MM", eingefrorenA: "450 MM", eingefrorenB: "0 MM" },
        { art: "schild", text: "+450 MM", ton: "gold", bei: "a" },
        { art: "schild", text: "falsch = 0", ton: "rot", bei: "b" },
      ],
      pose: { a: "jubel", b: "frust" },
      gesicht: { a: "jubel", b: "frust" },
      effekt: "konfetti",
      geldflug: { von: "mitte", zu: "a" },
      sound: "richtig",
    },
  ],
};

export default modul;

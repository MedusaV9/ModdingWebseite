// Client-Renderer „Bananen-Basics" (GAME-DESIGN §2.1): Screen = Frage oben,
// 4 Antwort-Lianen pendeln, pro Abgabe hüpft ein ANONYMER Mini-Affe auf den
// „hat geantwortet"-Ast; Auflösung: falsche Lianen reißen, MM regnet als
// Scheine. Player = 4 Farb-Buttons vertikal XXL (🍌🥥🐒🌴), Antwort-Lock.
// Extras: Insider-Blur (sichtbarAb) + Affentheater (Optionen pro Gerät mischen).
import { html, render } from "lit-html";
import { BANANEN_BASICS_ID, BB_DEKO } from "../../../../shared/minigames/bananen-basics.meta";
import { formatMM } from "../../../../shared/money";
import { timerBalken } from "../../ui";
import type { FxApi, MinigameClientModule, SendAction } from "../types";
import "./bananen-basics.css";

interface BananenBasicsView {
  questionId: string;
  text: string;
  options: string[];
  endsAt: number;
  timerMs: number;
  answeredCount: number;
  spielerZahl: number;
  finished: boolean;
  sichtbarAb: number;
  geraeteMischung: boolean;
  gesperrt?: number[];
  yourChoice?: number | null;
  zweitversuch?: boolean;
  aufloesung: {
    correctIndex: number;
    erklaerung: string;
    perPlayer: { playerId: string; choice: number | null; correct: boolean; delta: number }[];
  } | null;
}

/** Affentheater: kosmetische Geräte-Mischung — es zählt der ORIGINAL-Index.
 * Web-Crypto statt Math.random (Rng-Regel): rein kosmetisch, pro Gerät anders.
 * Wahr/Falsch (2 Optionen) wird NIE gemischt — ✔ oben/✘ unten bleibt fix. */
const geraeteNonce = crypto.getRandomValues(new Uint32Array(1))[0] & 0xffff;
function mischung(questionId: string, aktiv: boolean, anzahl: number): number[] {
  const identitaet = Array.from({ length: anzahl }, (_, i) => i);
  if (!aktiv || anzahl !== 4) return identitaet;
  let h = geraeteNonce;
  for (const c of questionId) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  const reihenfolge = identitaet;
  for (let i = 3; i > 0; i--) {
    h = (h * 1103515245 + 12345) >>> 0;
    const j = h % (i + 1);
    [reihenfolge[i], reihenfolge[j]] = [reihenfolge[j], reihenfolge[i]];
  }
  return reihenfolge;
}

/** Wahr/Falsch-Deko (2 Optionen): ✔ Grün / ✘ Rot statt A–D-Buchstaben. */
const WF_DEKO = [
  { buchstabe: "✔", emoji: "👍", farbe: "#2e8b57" },
  { buchstabe: "✘", emoji: "👎", farbe: "#d1495b" },
] as const;

function dekoFuer(anzahl: number): readonly { buchstabe: string; emoji: string; farbe: string }[] {
  return anzahl === 2 ? WF_DEKO : BB_DEKO;
}

// Scheine-Regen genau EINMAL pro Auflösung (Edge-Detection über die Frage-Id).
let regenFuer: string | null = null;

const modul: MinigameClientModule = {
  id: BANANEN_BASICS_ID,

  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void {
    const v = view as BananenBasicsView;
    const correct = v.aufloesung?.correctIndex ?? -1;
    const verdeckt = !v.aufloesung && fx.serverNow() < v.sichtbarAb;

    if (v.aufloesung && regenFuer !== v.questionId) {
      regenFuer = v.questionId;
      if (v.aufloesung.perPlayer.some((p) => p.delta > 0)) {
        fx.partikel?.("scheine", { anzahl: 24 });
        fx.sound("money-mittel");
      }
    }

    render(
      html`<div class="bb-screen">
        <h2 class="bb-frage ${verdeckt ? "verdeckt" : ""}">
          ${verdeckt ? "🕵️ Der Insider liest schon …" : v.text}
        </h2>
        ${
          v.aufloesung
            ? html`<p class="muted" style="text-align:center">${v.aufloesung.erklaerung}</p>`
            : timerBalken(v.endsAt, v.timerMs, fx.serverNow())
        }
        <div class="bb-lianen ${v.options.length === 2 ? "zweier" : ""}">
          ${v.options.map((opt, i) => {
            const deko = dekoFuer(v.options.length)[i];
            return html`<div
              class="bb-liane ${v.aufloesung ? (i === correct ? "traegt" : "reisst") : "pendelt"} ${
                !v.aufloesung && v.gesperrt?.includes(i) ? "entfernt" : ""
              }"
              style="--deko:${deko.farbe};--pendel-index:${i}"
            >
              <span class="bb-seil"></span>
              <span class="bb-deko">${deko.buchstabe} ${deko.emoji}</span>
              <span class="bb-option-text ${verdeckt ? "verdeckt" : ""}">
                ${verdeckt ? "· · ·" : opt}
              </span>
            </div>`;
          })}
        </div>
        ${
          v.aufloesung
            ? ""
            : html`<div class="bb-ast">
                <span class="bb-ast-label">hat geantwortet:</span>
                ${Array.from(
                  { length: v.answeredCount },
                  (_, i) => html`<span class="bb-mini-affe" style="--hops:${i}">🐵</span>`,
                )}
                <span class="muted">${v.answeredCount} / ${v.spielerZahl}</span>
              </div>`
        }
      </div>`,
      host,
    );
  },

  renderPlayer(view: unknown, host: HTMLElement, send: SendAction, fx?: FxApi): void {
    const v = view as BananenBasicsView;
    if (v.aufloesung) {
      render(html``, host); // Auflösung rendert die Player-App (kennt „you")
      return;
    }
    const gewaehlt = v.yourChoice ?? null;
    const verdeckt = fx !== undefined && fx.serverNow() < v.sichtbarAb;
    const reihenfolge = mischung(v.questionId, v.geraeteMischung, v.options.length);

    render(
      html`<div class="bb-player">
        <p class="bb-frage-klein">${verdeckt ? "🕵️ Gleich siehst du die Frage …" : v.text}</p>
        ${v.zweitversuch ? html`<p class="bb-zweitversuch">🔁 Rückgaberecht aktiv — Gewinn 50 %</p>` : ""}
        ${reihenfolge.map((i) => {
          const deko = dekoFuer(v.options.length)[i];
          const entfernt = v.gesperrt?.includes(i) === true;
          return html`<button
            class="bb-button ${v.options.length === 2 ? "xxl" : ""} ${gewaehlt === i ? "gewaehlt" : ""} ${gewaehlt !== null ? "gesperrt" : ""} ${entfernt ? "entfernt" : ""}"
            style="--deko:${deko.farbe}"
            ?disabled=${gewaehlt !== null || entfernt || verdeckt}
            @click=${() => send("answer", { choice: i })}
          >
            <span class="bb-deko">${deko.buchstabe} ${deko.emoji}</span>
            ${verdeckt ? "· · ·" : v.options[i]}
          </button>`;
        })}
        ${
          gewaehlt !== null
            ? html`<p class="muted" style="text-align:center">Eingerastet — kein Umentscheiden!</p>`
            : ""
        }
      </div>`,
      host,
    );
  },

  explainCard: {
    text: "Lockeres Aufwärmen: alle beantworten dieselbe Frage. Richtig = Grundwert + Speed-Bonus — und die Streak-Kette beginnt!",
    animation: html`<span style="font-size:3rem">🍌🥥🐒🌴</span>`,
  },
};

export default modul;

/** Anzeige-Helfer der Auflösung (Screen-App): +380 MM etc. */
export function bbDeltaText(delta: number): string {
  return delta > 0 ? `+${formatMM(delta)}` : formatMM(0);
}

// Erklär-Demo (ADDITIV): lockeres Aufwärmen — beide richtig, Mia mit
// Speed-Bonus, die Streak-Kette startet.
export const demoChoreo: import("../demo-typen").DemoChoreo = {
  dauer: 9600,
  beats: [
    {
      at: 0,
      requisiten: [{ art: "frage" }],
      pose: { a: "denk", b: "denk" },
      gesicht: { a: "denk", b: "denk" },
    },
    {
      at: 2200,
      requisiten: [{ art: "frage", tippA: 3 }],
      pose: { a: "tipp", b: "denk" },
      gesicht: { a: "neutral", b: "denk" },
      blase: { wer: "a", text: "Mia ist schnell!" },
      sound: "lockin-thunk",
    },
    {
      at: 4200,
      requisiten: [{ art: "frage", tippA: 3, tippB: 3 }],
      pose: { a: "idle", b: "tipp" },
      sound: "lockin-thunk",
    },
    {
      at: 6400,
      requisiten: [
        { art: "frage", tippA: 3, tippB: 3, richtig: 3 },
        { art: "schild", text: "⚡ Speed-Bonus für Mia!", ton: "gold" },
        { art: "schild", text: "🔗 Streak ×2 startet", ton: "cyan" },
      ],
      pose: { a: "jubel", b: "jubel" },
      gesicht: { a: "jubel", b: "jubel" },
      effekt: "konfetti",
      sound: "richtig",
    },
  ],
};

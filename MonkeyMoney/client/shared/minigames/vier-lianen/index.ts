// Client-Renderer „Vier Lianen": Screen = Frage + 4 Antworten + Timer-Balken,
// Player = 4 XXL-Buttons mit Antwort-Lock, Auflösung mit Richtig/Falsch.
// wahr_falsch-Fragen (2 Optionen) laufen als 2 XXL-Buttons mit ✔/✘-Deko.
import { html, render } from "lit-html";
import { ANTWORT_DEKO, VIER_LIANEN_ID } from "../../../../shared/minigames/vier-lianen.meta";
import { formatMM } from "../../../../shared/money";
import { timerBalken } from "../../ui";
import type { FxApi, MinigameClientModule, SendAction } from "../types";
import "./vier-lianen.css";

interface VierLianenScreenView {
  text: string;
  options: string[];
  endsAt: number;
  timerMs: number;
  answeredCount: number;
  finished: boolean;
  yourChoice?: number | null;
  /** Abgerissene Optionen (GM-Tipp-Kanone global bzw. 50:50/Schmiergeld privat). */
  gesperrt?: number[];
  aufloesung: {
    correctIndex: number;
    erklaerung: string;
    perPlayer: { playerId: string; choice: number | null; correct: boolean; delta: number }[];
  } | null;
}

/** Wahr/Falsch-Deko (2 Optionen): ✔ Grün / ✘ Rot statt A–D-Buchstaben. */
const WF_DEKO = [
  { buchstabe: "✔", emoji: "👍", farbe: "#2e8b57" },
  { buchstabe: "✘", emoji: "👎", farbe: "#d1495b" },
] as const;

function dekoFuer(anzahl: number): readonly { buchstabe: string; emoji: string; farbe: string }[] {
  return anzahl === 2 ? WF_DEKO : ANTWORT_DEKO;
}

const modul: MinigameClientModule = {
  id: VIER_LIANEN_ID,

  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void {
    const v = view as VierLianenScreenView;
    const correct = v.aufloesung?.correctIndex ?? -1;
    const deko = dekoFuer(v.options.length);
    render(
      html`<div class="vl-screen">
        <h2 class="vl-frage">${v.text}</h2>
        ${
          v.aufloesung
            ? html`<p class="muted">${v.aufloesung.erklaerung}</p>`
            : timerBalken(v.endsAt, v.timerMs, fx.serverNow())
        }
        <div class="vl-optionen ${v.options.length === 2 ? "zweier" : ""}">
          ${v.options.map(
            (opt, i) =>
              html`<div
                class="vl-option ${v.aufloesung ? (i === correct ? "richtig" : "falsch") : ""} ${
                  !v.aufloesung && v.gesperrt?.includes(i) ? "entfernt" : ""
                }"
                style="--deko:${deko[i].farbe}"
              >
                <span class="vl-deko">${deko[i].buchstabe} ${deko[i].emoji}</span>
                ${opt}
              </div>`,
          )}
        </div>
        ${
          v.aufloesung
            ? ""
            : html`<p class="muted" style="text-align:center">
                ${v.answeredCount} Antwort${v.answeredCount === 1 ? "" : "en"} eingerastet …
              </p>`
        }
      </div>`,
      host,
    );
  },

  renderPlayer(view: unknown, host: HTMLElement, send: SendAction): void {
    const v = view as VierLianenScreenView;
    const gewaehlt = v.yourChoice ?? null;

    if (v.aufloesung) {
      const meins = v.aufloesung.perPlayer.find((p) => p.choice === gewaehlt); // Anzeige unten nutzt eigene Daten
      void meins;
      render(html``, host); // Auflösung rendert die Player-App (kennt „you")
      return;
    }

    const deko = dekoFuer(v.options.length);
    render(
      html`<div class="vl-player">
        <p class="vl-frage-klein">${v.text}</p>
        ${v.options.map((opt, i) => {
          const entfernt = v.gesperrt?.includes(i) === true;
          return html`<button
            class="vl-button ${v.options.length === 2 ? "xxl" : ""} ${gewaehlt === i ? "gewaehlt" : ""} ${gewaehlt !== null ? "gesperrt" : ""} ${entfernt ? "entfernt" : ""}"
            style="--deko:${deko[i].farbe}"
            ?disabled=${gewaehlt !== null || entfernt}
            @click=${() => send("answer", { choice: i })}
          >
            <span class="vl-deko">${deko[i].buchstabe} ${deko[i].emoji}</span>
            ${opt}
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
    text: "Alle beantworten dieselbe Frage gleichzeitig. Schnell + richtig = mehr MONKEY MONEY!",
    animation: html`<span style="font-size:3rem">🍌🥥🐒🌴</span>`,
  },
};

export default modul;

/** Hilfsformat für die Auflösung in den Apps (Screen kennt Namen, Player kennt „you"). */
export function deltaText(delta: number): string {
  return delta > 0 ? `+${formatMM(delta)}` : formatMM(0);
}

// Erklär-Demo (ADDITIV): Mia und Bo tippen dieselbe Frage, B gewinnt.
export const demoChoreo: import("../demo-typen").DemoChoreo = {
  dauer: 9800,
  beats: [
    {
      at: 0,
      requisiten: [{ art: "frage" }],
      pose: { a: "denk", b: "denk" },
      gesicht: { a: "denk", b: "denk" },
    },
    {
      at: 2400,
      requisiten: [{ art: "frage", tippA: 1 }],
      pose: { a: "tipp", b: "denk" },
      gesicht: { a: "neutral", b: "denk" },
      blase: { wer: "a", text: "Mia tippt B!" },
      sound: "lockin-thunk",
    },
    {
      at: 4600,
      requisiten: [{ art: "frage", tippA: 1, tippB: 2 }],
      pose: { a: "idle", b: "tipp" },
      blase: { wer: "b", text: "Bo tippt C!" },
      sound: "lockin-thunk",
    },
    {
      at: 6800,
      requisiten: [
        { art: "frage", tippA: 1, tippB: 2, richtig: 1 },
        { art: "schild", text: "+100 MM", ton: "gold", bei: "a" },
      ],
      pose: { a: "jubel", b: "frust" },
      gesicht: { a: "jubel", b: "frust" },
      geldflug: { von: "mitte", zu: "a" },
      effekt: "konfetti",
      sound: "richtig",
    },
  ],
};

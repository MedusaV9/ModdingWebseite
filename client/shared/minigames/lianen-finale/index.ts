// Client-Renderer „Das große Lianen-Finale" (GAME-DESIGN §2.10): eigenes Set —
// Krokodil-Fluss unten, jeder Affe hängt an SEINER Liane (Länge = live
// normierter Kontostand, Führender 100 %, Minimum 25 %), W_final-Ansage als
// Banner. Auflösung: richtig = Ruck nach oben, falsch = Riss nach unten
// (Übergang auf lianeNachher), das Krokodil schnappt (nur Drama). Player =
// nur 4 Antwort-Buttons + die eigene Restlänge.
import { html, render } from "lit-html";
import { LIANEN_FINALE_ID } from "../../../../shared/minigames/lianen-finale.meta";
import { formatMM } from "../../../../shared/money";
import { timerBalken } from "../../ui";
import type { FxApi, MinigameClientModule, SendAction } from "../types";
import "./lianen-finale.css";

const DEKO = [
  { buchstabe: "A", emoji: "🍌", farbe: "#e6b830" },
  { buchstabe: "B", emoji: "🥥", farbe: "#8a5a3b" },
  { buchstabe: "C", emoji: "🐒", farbe: "#d1495b" },
  { buchstabe: "D", emoji: "🌴", farbe: "#2e8b57" },
] as const;

interface LianeView {
  playerId: string;
  laenge: number;
  kontostand: number;
  verbunden: boolean;
}

interface LianenFinaleView {
  questionId: string;
  text: string;
  options: string[];
  endsAt: number;
  timerMs: number;
  wFinal: number;
  lianen: LianeView[];
  anzeigeMin: number;
  answeredCount: number;
  spielerZahl: number;
  finished: boolean;
  yourChoice?: number | null;
  deineLiane?: number;
  aufloesung: {
    correctIndex: number;
    erklaerung: string;
    perPlayer: {
      playerId: string;
      choice: number | null;
      correct: boolean;
      delta: number;
      lianeNachher: number;
    }[];
  } | null;
}

// Dramatische Auflösung genau EINMAL vertonen (Edge-Detection über die Frage).
let stingerFuer: string | null = null;

/** Eine Liane mit hängendem Affen: --hoehe steuert die Position über dem Fluss. */
function liane(fx: FxApi, l: LianeView, hoehe: number, klasse: string) {
  const info = fx.spieler?.(l.playerId) ?? null;
  return html`<div
    class="lf-liane ${klasse} ${l.verbunden ? "" : "offline"}"
    style="--hoehe:${hoehe}"
  >
    <span class="lf-seil"></span>
    <div class="lf-affe-wrap">
      ${
        info
          ? html`<span class="lf-affe mm-affe" data-avatar=${info.avatar}></span>
              <span class="lf-name">${info.name}</span>`
          : html`<span class="lf-affe-emoji">🐒</span>`
      }
      <span class="lf-stand mm-money-zahl">${formatMM(l.kontostand)}</span>
    </div>
  </div>`;
}

const modul: MinigameClientModule = {
  id: LIANEN_FINALE_ID,

  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void {
    const v = view as LianenFinaleView;

    if (v.aufloesung && stingerFuer !== v.questionId) {
      stingerFuer = v.questionId;
      fx.sound("stinger");
      if (v.aufloesung.perPlayer.some((p) => p.correct)) fx.partikel?.("konfetti", { anzahl: 18 });
    }

    const nachher = new Map(v.aufloesung?.perPlayer.map((p) => [p.playerId, p]) ?? []);
    render(
      html`<div class="lf-screen">
        <div class="lf-banner">
          🏆 FINALE — jede Frage ist heute
          <strong class="mm-money-zahl">${formatMM(v.wFinal)}</strong> wert!
          <span class="muted">(falsch: −${formatMM(v.wFinal / 2)})</span>
        </div>
        <div class="lf-set">
          <div class="lf-lianen">
            ${v.lianen.map((l) => {
              const r = nachher.get(l.playerId);
              const hoehe = r !== undefined ? r.lianeNachher : l.laenge;
              const klasse =
                r === undefined ? "" : r.correct ? "ruck" : r.choice === null ? "" : "riss";
              return liane(fx, l, hoehe, klasse);
            })}
          </div>
          <div class="lf-fluss">
            <span class="lf-welle">〰️〰️〰️〰️〰️</span>
            <span class="lf-krokodil ${v.aufloesung ? "schnappt" : ""}">🐊</span>
          </div>
        </div>
        ${
          v.aufloesung
            ? html`<p class="muted" style="text-align:center">${v.aufloesung.erklaerung}</p>`
            : html`<h2 class="lf-frage">${v.text}</h2>
                ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())}`
        }
        <div class="lf-optionen">
          ${v.options.map(
            (opt, i) =>
              html`<div
                class="lf-option ${
                  v.aufloesung ? (i === v.aufloesung.correctIndex ? "richtig" : "falsch") : ""
                }"
                style="--deko:${DEKO[i].farbe}"
              >
                <span class="lf-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                ${opt}
              </div>`,
          )}
        </div>
        ${
          v.aufloesung
            ? ""
            : html`<p class="muted" style="text-align:center">
                ${v.answeredCount} / ${v.spielerZahl} eingerastet …
              </p>`
        }
      </div>`,
      host,
    );
  },

  renderPlayer(view: unknown, host: HTMLElement, send: SendAction): void {
    const v = view as LianenFinaleView;
    if (v.aufloesung) {
      render(html``, host); // Auflösung rendert die Player-App (kennt „you")
      return;
    }
    const gewaehlt = v.yourChoice ?? null;
    const laenge = v.deineLiane ?? 1;

    render(
      html`<div class="lf-player">
        <div class="lf-restlaenge" title="Deine Lianen-Restlänge">
          <span class="lf-restlaenge-balken" style="--laenge:${laenge.toFixed(3)}"></span>
          <span class="lf-restlaenge-text">
            🌿 ${Math.round(laenge * 100)} % · ±${formatMM(v.wFinal)}
          </span>
        </div>
        <p class="lf-frage-klein">${v.text}</p>
        ${v.options.map(
          (opt, i) =>
            html`<button
              class="lf-button ${gewaehlt === i ? "gewaehlt" : ""} ${gewaehlt !== null ? "gesperrt" : ""}"
              style="--deko:${DEKO[i].farbe}"
              ?disabled=${gewaehlt !== null}
              @click=${() => send("answer", { choice: i })}
            >
              <span class="lf-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
              ${opt}
            </button>`,
        )}
        ${
          gewaehlt !== null
            ? html`<p class="muted" style="text-align:center">Eingerastet — Daumen drücken! 🤞</p>`
            : ""
        }
      </div>`,
      host,
    );
  },

  explainCard: {
    text: "Jeder hängt an seiner Liane über dem Krokodil-Fluss. Richtig = W_final rauf, falsch = die Hälfte runter — niemand scheidet aus, aber das Krokodil schnappt!",
    animation: html`<span style="font-size:3rem">🌿🐒🐊🏆</span>`,
  },
};

// Erklär-Demo (ADDITIV): jede Antwort bewegt die Liane — runter schnappt das
// Krokodil, aber niemand scheidet aus.
export const demoChoreo: import("../demo-typen").DemoChoreo = {
  dauer: 10400,
  beats: [
    {
      at: 0,
      requisiten: [
        { art: "lianen", hoeheA: 0.45, hoeheB: 0.45 },
        { art: "schild", text: "Jede Frage zählt W_final!", ton: "cyan" },
      ],
      pose: { a: "denk", b: "denk" },
      gesicht: { a: "denk", b: "denk" },
    },
    {
      at: 2400,
      requisiten: [{ art: "lianen", hoeheA: 0.75, hoeheB: 0.2 }],
      pose: { a: "jubel", b: "frust" },
      gesicht: { a: "jubel", b: "frust" },
      blase: { wer: "b", text: "Falsch = halbe Höhe runter!" },
      sound: "richtig",
    },
    {
      at: 5000,
      requisiten: [{ art: "lianen", hoeheA: 0.75, hoeheB: 0.2, schnappt: "b" }],
      pose: { a: "idle", b: "duck" },
      gesicht: { a: "neutral", b: "frust" },
      blase: { wer: "b", text: "Das Krokodil schnappt!" },
      sound: "kokosnuss-knack",
    },
    {
      at: 7400,
      requisiten: [{ art: "lianen", hoeheA: 0.9, hoeheB: 0.4 }],
      pose: { a: "jubel", b: "huepf" },
      gesicht: { a: "jubel", b: "neutral" },
      blase: { wer: "a", text: "Niemand fliegt raus — kämpfen!" },
      effekt: "konfetti",
    },
  ],
};

export default modul;

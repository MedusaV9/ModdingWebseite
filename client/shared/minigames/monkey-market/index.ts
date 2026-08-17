// Client-Renderer „Monkey Market" (GAME-DESIGN §2.12/2): Screen = 4 Antwort-
// FALLTÜREN mit dem öffentlichen Chip-Getümmel (Türen-Summen — wer wohin
// legte, bleibt privat), Frage darüber, Timer-Banane. Player = Chip-Vorrat als
// Münz-Reihe + 4 XXL-Tür-Buttons (Tipp = 1 Chip drauf) mit „−"-Rücknahme und
// „REST!"-All-in pro Tür. Auflösung: richtige Tür öffnet sich, Bilanz-Zeilen
// mit Chip-Verteilung + Mut-Bonus-Sticker.
import { html, render } from "lit-html";
import { MM_MARKT_CHIPS, MONKEY_MARKET_ID } from "../../../../shared/minigames/monkey-market.meta";
import { formatMM } from "../../../../shared/money";
import { timerBalken } from "../../ui";
import type { FxApi, MinigameClientModule, SendAction } from "../types";
import "./monkey-market.css";

const DEKO = [
  { buchstabe: "A", emoji: "🍌", farbe: "#e6b830" },
  { buchstabe: "B", emoji: "🥥", farbe: "#8a5a3b" },
  { buchstabe: "C", emoji: "🐒", farbe: "#d1495b" },
  { buchstabe: "D", emoji: "🌴", farbe: "#2e8b57" },
] as const;

interface MonkeyMarketView {
  questionId: string;
  text: string;
  options: string[];
  endsAt: number;
  timerMs: number;
  chipWert: number;
  chipsProSpieler: number;
  tuerSummen: [number, number, number, number];
  fertigCount: number;
  spielerZahl: number;
  finished: boolean;
  yourChips?: [number, number, number, number];
  chipsFrei?: number;
  aufloesung: {
    correctIndex: number;
    erklaerung: string;
    perPlayer: {
      playerId: string;
      choice: null;
      correct: boolean;
      delta: number;
      chips: [number, number, number, number];
      mutBonus: boolean;
    }[];
  } | null;
}

function chipStapel(anzahl: number, klein = false): unknown {
  return html`<span class="mkt-stapel ${klein ? "klein" : ""}">
    ${[...Array(Math.min(anzahl, MM_MARKT_CHIPS))].map(() => html`<i class="mkt-chip"></i>`)}
    ${anzahl > 0 ? html`<b>${anzahl}</b>` : ""}
  </span>`;
}

const modul: MinigameClientModule = {
  id: MONKEY_MARKET_ID,

  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void {
    const v = view as MonkeyMarketView;

    if (v.aufloesung) {
      const a = v.aufloesung;
      render(
        html`<div class="mkt-screen">
          <h2 style="text-align:center">🚪 Die Falltüren öffnen sich!</h2>
          <div class="mkt-tueren">
            ${v.options.map(
              (opt, i) =>
                html`<div
                  class="mkt-tuer ${i === a.correctIndex ? "richtig" : "falsch"}"
                  style="--deko:${DEKO[i].farbe}"
                >
                  <span class="mkt-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                  <span class="mkt-tuer-text">${opt}</span>
                  ${chipStapel(v.tuerSummen[i], true)}
                </div>`,
            )}
          </div>
          <p class="muted" style="text-align:center">${a.erklaerung}</p>
          <div class="mkt-bilanz">
            ${[...a.perPlayer]
              .sort((x, y) => y.delta - x.delta)
              .map((r) => {
                const info = fx.spieler?.(r.playerId) ?? null;
                return html`<div class="mkt-bilanz-zeile ${r.delta > 0 ? "gewonnen" : ""}">
                  <span>${r.mutBonus ? "🦁" : r.correct ? "✅" : "🙈"}</span>
                  <span>${info?.name ?? r.playerId}</span>
                  <span class="muted mkt-mini-chips">
                    ${r.chips.map((c, i) => `${DEKO[i].buchstabe}:${c}`).join(" · ")}
                  </span>
                  ${r.mutBonus ? html`<span class="mkt-mut">MUT +25 %</span>` : ""}
                  <strong
                    class="mm-money-zahl"
                    style="color:${r.delta > 0 ? "var(--gold)" : "var(--muted)"}"
                  >
                    +${formatMM(r.delta)}
                  </strong>
                </div>`;
              })}
          </div>
        </div>`,
        host,
      );
      return;
    }

    render(
      html`<div class="mkt-screen">
        <div class="mkt-kopf">
          <span class="mkt-badge">💱 MONKEY MARKET</span>
          <span class="muted">
            Chip-Wert <strong class="mm-money-zahl">${formatMM(v.chipWert)}</strong> — richtige Tür
            zahlt ×2, alle ${v.chipsProSpieler} auf eine = +25 %!
          </span>
        </div>
        <h2 class="mkt-frage">${v.text}</h2>
        ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())}
        <div class="mkt-tueren">
          ${v.options.map(
            (opt, i) =>
              html`<div class="mkt-tuer" style="--deko:${DEKO[i].farbe}">
                <span class="mkt-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                <span class="mkt-tuer-text">${opt}</span>
                ${chipStapel(v.tuerSummen[i], true)}
              </div>`,
          )}
        </div>
        <p class="muted" style="text-align:center">
          ${v.fertigCount} / ${v.spielerZahl} Affen voll investiert — der Markt schließt, wenn alle
          fertig sind!
        </p>
      </div>`,
      host,
    );
  },

  renderPlayer(view: unknown, host: HTMLElement, send: SendAction, fx?: FxApi): void {
    const v = view as MonkeyMarketView;
    if (v.aufloesung) {
      render(html``, host); // Auflösung rendert die Player-App (kennt „you")
      return;
    }
    const eigene = v.yourChips ?? [0, 0, 0, 0];
    const frei = v.chipsFrei ?? MM_MARKT_CHIPS;

    render(
      html`<div class="mkt-player">
        <p class="mkt-frage-klein">${v.text}</p>
        <div class="mkt-vorrat">
          <span class="muted">Deine Chips (je ${formatMM(v.chipWert)}):</span>
          ${chipStapel(frei)}
        </div>
        ${v.options.map((opt, i) => {
          const drauf = eigene[i];
          return html`<div class="mkt-zeile" style="--deko:${DEKO[i].farbe}">
            <button
              class="mkt-tuer-button"
              ?disabled=${frei <= 0}
              @click=${() => {
                fx?.sound("money-klein");
                void send("chip", { tuer: i });
              }}
            >
              <span class="mkt-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
              <span class="mkt-tuer-text">${opt}</span>
              ${chipStapel(drauf, true)}
            </button>
            <div class="mkt-neben">
              <button
                class="mkt-mini"
                ?disabled=${drauf <= 0}
                @click=${() => void send("zurueck", { tuer: i })}
              >
                −
              </button>
              <button
                class="mkt-mini rest"
                ?disabled=${frei <= 0}
                @click=${() => {
                  fx?.sound("lockin-thunk");
                  void send("answer", { choice: i });
                }}
              >
                REST!
              </button>
            </div>
          </div>`;
        })}
        <p class="muted" style="text-align:center;margin:0">
          Tippen legt 1 Chip — „REST!" schiebt alles auf die Tür. Umschichten erlaubt!
        </p>
      </div>`,
      host,
    );
  },

  explainCard: {
    text: "Die Bank gibt dir 10 Markt-Chips — verteile sie auf die 4 Antwort-Falltüren! Chips auf der richtigen Tür zahlen ×2, der Rest verfällt. Alle 10 auf eine Tür und richtig? MUT-BONUS +25 %!",
    animation: html`<span style="font-size:3rem">💱🪙🚪🐒</span>`,
  },
};

// Erklär-Demo (ADDITIV): 10 Markt-Chips auf die Antwort-Falltüren — Bo geht
// ALL-IN und kassiert den Mut-Bonus.
export const demoChoreo: import("../demo-typen").DemoChoreo = {
  dauer: 10600,
  beats: [
    {
      at: 0,
      requisiten: [
        { art: "schild", text: "🪙 10 Chips von der Bank", ton: "gold" },
        { art: "tueren" },
      ],
      pose: { a: "denk", b: "denk" },
      gesicht: { a: "denk", b: "denk" },
    },
    {
      at: 2400,
      requisiten: [{ art: "tueren", chipsA: [5, 3, 2, 0] }],
      pose: { a: "zeig", b: "denk" },
      gesicht: { a: "neutral", b: "denk" },
      blase: { wer: "a", text: "Mia streut breit …" },
      sound: "money-klein",
    },
    {
      at: 4600,
      requisiten: [{ art: "tueren", chipsA: [5, 3, 2, 0], chipsB: [0, 10, 0, 0] }],
      pose: { a: "idle", b: "zeig" },
      blase: { wer: "b", text: "Bo: ALL-IN auf B!" },
      sound: "money-klein",
    },
    {
      at: 7000,
      requisiten: [
        { art: "tueren", chipsA: [5, 3, 2, 0], chipsB: [0, 10, 0, 0], offen: 1 },
        { art: "schild", text: "MUT-BONUS +25 %!", ton: "gold", bei: "b" },
      ],
      pose: { a: "idle", b: "jubel" },
      gesicht: { a: "neutral", b: "jubel" },
      geldflug: { von: "mitte", zu: "b" },
      effekt: "konfetti",
      sound: "money-gross",
    },
  ],
};

export default modul;

// Client-Renderer „Bananen-Börse" (GAME-DESIGN §2.12/4): Screen = Parkett mit
// KURS-CHART (Canvas: 4 Options-Kurven als Treppen-Linien über die Blöcke),
// Kurs-Tafel (Quote + Halter je Option) und Positions-Ticker. Player = 4
// XXL-KAUFEN-Buttons mit Live-Quote, Positions-Karte mit VERKAUFEN-Button
// (Spread-Warnung) und Mini-Chart. Herdenverhalten drückt den Kurs — live.
import { html, render } from "lit-html";
import {
  BANANEN_BOERSE_ID,
  BOERSE_QUOTE_MIN,
  BOERSE_QUOTE_START,
  boerseGewinn,
  boerseSpreadVerlust,
} from "../../../../shared/minigames/bananen-boerse.meta";
import { formatMM } from "../../../../shared/money";
import { timerBalken } from "../../ui";
import type { FxApi, MinigameClientModule, SendAction } from "../types";
import "./bananen-boerse.css";

const DEKO = [
  { buchstabe: "A", emoji: "🍌", farbe: "#e6b830" },
  { buchstabe: "B", emoji: "🥥", farbe: "#8a5a3b" },
  { buchstabe: "C", emoji: "🐒", farbe: "#d1495b" },
  { buchstabe: "D", emoji: "🌴", farbe: "#2e8b57" },
] as const;

interface BrsPosition {
  option: number;
  quote: number;
  block?: number;
}

interface BananenBoerseView {
  questionId: string;
  text: string;
  options: string[] | null;
  endsAt: number;
  timerMs: number;
  blockMs: number;
  bloeckeTotal: number;
  aktuellerBlock: number;
  einsatz: number;
  kursBloecke: number[][];
  halter: [number, number, number, number];
  positionen: Record<string, BrsPosition>;
  answeredCount: number;
  spielerZahl: number;
  finished: boolean;
  yourPosition?: BrsPosition | null;
  yourVerkaeufe?: number;
  kannVerkaufen?: boolean;
  aufloesung: {
    correctIndex: number;
    erklaerung: string;
    perPlayer: {
      playerId: string;
      choice: number | null;
      correct: boolean;
      delta: number;
      quote: number | null;
      verkaeufe: number;
    }[];
  } | null;
}

/** Treppen-Chart der eingefrorenen Block-Quoten (das Kurs-Futter aus dem View). */
function zeichneChart(canvas: HTMLCanvasElement, v: BananenBoerseView): void {
  const dpr = window.devicePixelRatio || 1;
  const w = canvas.clientWidth || 300;
  const h = canvas.clientHeight || 120;
  canvas.width = Math.round(w * dpr);
  canvas.height = Math.round(h * dpr);
  const g = canvas.getContext("2d");
  if (!g) return;
  g.scale(dpr, dpr);
  g.clearRect(0, 0, w, h);

  const yMax = BOERSE_QUOTE_START + 0.2;
  const yMin = BOERSE_QUOTE_MIN - 0.2;
  const pad = 26;
  const y = (quote: number) => h - 8 - ((quote - yMin) / (yMax - yMin)) * (h - 16);
  const x = (block: number) => pad + (block / Math.max(1, v.bloeckeTotal - 1)) * (w - pad - 8);

  // Gitter + Quote-Beschriftung.
  g.strokeStyle = "rgba(255, 246, 227, 0.15)";
  g.fillStyle = "rgba(255, 246, 227, 0.55)";
  g.font = "10px sans-serif";
  g.lineWidth = 1;
  for (const q of [1.5, 2.0, 2.5, 3.0]) {
    g.beginPath();
    g.moveTo(pad, y(q));
    g.lineTo(w - 8, y(q));
    g.stroke();
    g.fillText(`×${q.toFixed(1)}`, 2, y(q) + 3);
  }

  // 4 Treppen-Linien: Quote bleibt im Block konstant, springt am Block-Rand.
  for (let opt = 0; opt < 4; opt++) {
    g.strokeStyle = DEKO[opt].farbe;
    g.lineWidth = 3;
    g.beginPath();
    for (let b = 0; b < v.kursBloecke.length; b++) {
      const quote = v.kursBloecke[b][opt];
      const xEnde = b + 1 < v.bloeckeTotal ? x(b + 1) : w - 8;
      if (b === 0) g.moveTo(x(0), y(quote));
      else g.lineTo(x(b), y(quote));
      g.lineTo(xEnde, y(quote));
    }
    g.stroke();
    // Punkt am aktuellen Kurs-Ende.
    const letzte = v.kursBloecke.at(-1)?.[opt] ?? BOERSE_QUOTE_START;
    g.fillStyle = DEKO[opt].farbe;
    g.beginPath();
    g.arc(x(v.kursBloecke.length - 1), y(letzte), 4, 0, Math.PI * 2);
    g.fill();
  }
}

function chartNachRender(host: HTMLElement, v: BananenBoerseView): void {
  const canvas = host.querySelector<HTMLCanvasElement>(".brs-chart");
  if (canvas) zeichneChart(canvas, v);
}

const modul: MinigameClientModule = {
  id: BANANEN_BOERSE_ID,

  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void {
    const v = view as BananenBoerseView;

    if (v.aufloesung) {
      const a = v.aufloesung;
      render(
        html`<div class="brs-screen">
          <h2 style="text-align:center">
            🔔 Börsenschluss! Richtig war:
            <span style="color:${DEKO[a.correctIndex].farbe}"
              >${v.options?.[a.correctIndex] ?? "?"}</span
            >
          </h2>
          <canvas class="brs-chart"></canvas>
          <p class="muted" style="text-align:center">${a.erklaerung}</p>
          <div class="brs-bilanz">
            ${[...a.perPlayer]
              .sort((x, y) => y.delta - x.delta)
              .map(
                (r) =>
                  html`<div class="brs-bilanz-zeile ${r.correct ? "gewonnen" : ""}">
                    <span>${r.correct ? "📈" : r.choice === null ? "😶" : "📉"}</span>
                    <span>${fx.spieler?.(r.playerId)?.name ?? r.playerId}</span>
                    <span class="muted">
                      ${r.quote !== null ? `Quote ×${r.quote.toFixed(2)}` : "ohne Position"}
                      ${r.verkaeufe > 0 ? " · verkauft" : ""}
                    </span>
                    <strong
                      class="mm-money-zahl"
                      style="color:${r.delta >= 0 ? "var(--gold)" : "var(--rot)"}"
                    >
                      ${r.delta > 0 ? "+" : ""}${formatMM(r.delta)}
                    </strong>
                  </div>`,
              )}
          </div>
        </div>`,
        host,
      );
      chartNachRender(host, v);
      return;
    }

    const aktuelleQuoten = v.kursBloecke.at(-1) ?? [];
    render(
      html`<div class="brs-screen">
        <div class="brs-kopf">
          <span class="brs-badge">📈 BANANEN-BÖRSE</span>
          <span class="muted">
            Einsatz <strong class="mm-money-zahl">${formatMM(v.einsatz)}</strong> · Block
            ${Math.min(v.aktuellerBlock + 1, v.bloeckeTotal)} / ${v.bloeckeTotal} — Herde drückt den
            Kurs!
          </span>
        </div>
        <h2 class="brs-frage">${v.text}</h2>
        ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())}
        <canvas class="brs-chart"></canvas>
        <div class="brs-tafel">
          ${(v.options ?? []).map(
            (opt, i) =>
              html`<div class="brs-aktie" style="--deko:${DEKO[i].farbe}">
                <span class="brs-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                <span class="brs-aktie-text">${opt}</span>
                <span class="brs-quote"
                  >×${(aktuelleQuoten[i] ?? BOERSE_QUOTE_START).toFixed(2)}</span
                >
                <span class="muted">${v.halter[i]} 🐒</span>
              </div>`,
          )}
        </div>
        <p class="muted" style="text-align:center">
          ${v.answeredCount} / ${v.spielerZahl} investiert —
          ${
            Object.entries(v.positionen)
              .map(([p, pos]) => `${fx.spieler?.(p)?.name ?? p} → ${DEKO[pos.option].buchstabe}`)
              .join(" · ") || "das Parkett wartet …"
          }
        </p>
      </div>`,
      host,
    );
    chartNachRender(host, v);
  },

  renderPlayer(view: unknown, host: HTMLElement, send: SendAction, fx?: FxApi): void {
    const v = view as BananenBoerseView;
    if (v.aufloesung) {
      render(html``, host); // Auflösung rendert die Player-App (kennt „you")
      return;
    }
    const pos = v.yourPosition ?? null;
    const aktuelleQuoten = v.kursBloecke.at(-1) ?? [];

    if (pos) {
      // ---------- HALTEN oder VERKAUFEN ----------
      const gewinnBeiRichtig = boerseGewinn(v.einsatz, pos.quote);
      render(
        html`<div class="brs-player">
          <p class="brs-frage-klein">${v.text}</p>
          <canvas class="brs-chart klein"></canvas>
          <div class="brs-position" style="--deko:${DEKO[pos.option].farbe}">
            <span class="brs-deko">${DEKO[pos.option].buchstabe} ${DEKO[pos.option].emoji}</span>
            <div class="brs-position-text">
              <strong>Deine Position: Quote ×${pos.quote.toFixed(2)}</strong><br />
              <span class="muted">
                richtig = +${formatMM(gewinnBeiRichtig)} · falsch = −${formatMM(v.einsatz)}
              </span>
            </div>
          </div>
          ${
            v.kannVerkaufen === true
              ? html`<button
                  class="brs-verkaufen"
                  @click=${() => {
                    fx?.sound("karte-slide");
                    void send("verkaufen", {});
                  }}
                >
                  🔻 VERKAUFEN (−${formatMM(boerseSpreadVerlust(v.einsatz))} Spread)
                </button>`
              : html`<div class="brs-status muted">
                  Position steht bis Börsenschluss — kein Verkauf mehr möglich.
                </div>`
          }
        </div>`,
        host,
      );
      chartNachRender(host, v);
      return;
    }

    // ---------- KAUFEN: 4 XXL-Buttons mit Live-Quote ----------
    render(
      html`<div class="brs-player">
        <p class="brs-frage-klein">${v.text}</p>
        <canvas class="brs-chart klein"></canvas>
        ${(v.options ?? []).map(
          (opt, i) =>
            html`<button
              class="brs-kaufen"
              style="--deko:${DEKO[i].farbe}"
              @click=${() => {
                fx?.sound("money-klein");
                void send("answer", { choice: i });
              }}
            >
              <span class="brs-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
              <span class="brs-aktie-text">${opt}</span>
              <span class="brs-quote"
                >×${(aktuelleQuoten[i] ?? BOERSE_QUOTE_START).toFixed(2)}</span
              >
            </button>`,
        )}
        <p class="muted" style="text-align:center;margin:0">
          ${
            (v.yourVerkaeufe ?? 0) > 0
              ? `Umschichtung: 1 Neukauf zur aktuellen Quote (Einsatz ${formatMM(v.einsatz)}).`
              : `KAUFEN legt ${formatMM(v.einsatz)} auf eine Option — die Quote friert ein!`
          }
        </p>
      </div>`,
      host,
    );
    chartNachRender(host, v);
  },

  explainCard: {
    text: "Frage + Optionen liegen offen — aber gehandelt wird an der Börse! KAUFEN friert deine Quote ein; je mehr Affen dieselbe Option halten, desto tiefer sinkt der Kurs. Kalte Füße? VERKAUFEN kostet Spread.",
    animation: html`<span style="font-size:3rem">📈🍌💹🐒</span>`,
  },
};

// Erklär-Demo (ADDITIV): Mia kauft früh (Quote friert), Bo folgt der Herde —
// der Kurs sinkt, Mia kassiert mehr.
export const demoChoreo: import("../demo-typen").DemoChoreo = {
  dauer: 11000,
  beats: [
    {
      at: 0,
      requisiten: [{ art: "frage" }, { art: "schild", text: "📈 Kurs B: ×3,0", ton: "cyan" }],
      pose: { a: "denk", b: "denk" },
      gesicht: { a: "denk", b: "denk" },
    },
    {
      at: 2400,
      requisiten: [
        { art: "frage", tippA: 1 },
        { art: "schild", text: "📈 Kurs B: ×3,0", ton: "cyan" },
      ],
      pose: { a: "tipp", b: "denk" },
      gesicht: { a: "neutral", b: "denk" },
      blase: { wer: "a", text: "KAUFEN — Quote friert!" },
      sound: "lockin-thunk",
    },
    {
      at: 5000,
      requisiten: [
        { art: "frage", tippA: 1, tippB: 1 },
        { art: "schild", text: "📉 Herde drückt: Bo nur ×2,0!", ton: "rot" },
        { art: "schild", text: "×3,0 🔒", ton: "gold", bei: "a" },
      ],
      pose: { a: "idle", b: "tipp" },
      blase: { wer: "b", text: "Bo kauft dieselbe …" },
      sound: "lockin-thunk",
    },
    {
      at: 7600,
      requisiten: [
        { art: "frage", tippA: 1, tippB: 1, richtig: 1 },
        { art: "schild", text: "+300 MM", ton: "gold", bei: "a" },
        { art: "schild", text: "+200 MM", ton: "papier", bei: "b" },
      ],
      pose: { a: "jubel", b: "jubel" },
      gesicht: { a: "jubel", b: "neutral" },
      effekt: "konfetti",
      sound: "richtig",
    },
  ],
};

export default modul;

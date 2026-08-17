// Client-Renderer „Der Bananen-Tresor": Player = vertikaler XXL-Slider (70 % Bild-
// höhe, Touch UND Maus) + Zahlenfeld + ±1-Feintuning + EINLOGGEN; Screen = Zahlen-
// strahl-Liane, Auflösung mit einfliegenden Affen-Tipps und goldenem Pfeil.
// Sound-Mapping (ART-PLAN §4.1): Lock-in-Thunk beim Einloggen, Auflösungs-Reveal
// (glitch_002) beim Pfeil, Money-Kling GROSS beim Volltreffer — wartet auf FxApi.
import { html, render } from "lit-html";
import {
  BANANEN_TRESOR_ID,
  anteilZuWert,
  wertZuAnteil,
} from "../../../../shared/minigames/bananen-tresor.meta";
import { formatMM } from "../../../../shared/money";
import type { FxApi, MinigameClientModule, SendAction } from "../types";
import { timerBanane } from "../kokosnuss-uhr/timer-banane";
import "./bananen-tresor.css";

interface TresorView {
  questionId: string;
  text: string;
  einheit: string;
  eingabeMin: number;
  eingabeMax: number;
  skala: "linear" | "log";
  variante: "standard" | "hard";
  endsAt: number;
  timerMs: number;
  answeredCount: number;
  abgegeben: { playerId: string; eingeloggt: boolean }[];
  finished: boolean;
  yourTipp?: { wert: number; eingeloggt: boolean } | null;
  aufloesung: {
    richtwert: number;
    einheit: string;
    erklaerung: string;
    perPlayer: {
      playerId: string;
      tipp: number | null;
      distanz: number | null;
      platz: number | null;
      volltreffer: boolean;
      correct: boolean;
      delta: number;
    }[];
  } | null;
}

/** Lokaler Slider-Zustand pro Frage (überlebt die 150-ms-Re-Renders der App). */
const lokal = new Map<string, { wert: number; bewegt: boolean }>();

function lokalFuer(v: TresorView): { wert: number; bewegt: boolean } {
  let s = lokal.get(v.questionId);
  if (!s) {
    // Startwert = Skalen-Mitte; zählt erst NACH der ersten Bewegung („unbewegt =
    // keine Wertung", §2.3). Server-Stand (Reconnect!) gewinnt immer.
    s = { wert: anteilZuWert(v, 0.5), bewegt: false };
    lokal.set(v.questionId, s);
    if (lokal.size > 8) {
      for (const key of lokal.keys()) {
        if (key !== v.questionId) lokal.delete(key);
      }
    }
  }
  if (v.yourTipp && !s.bewegt) {
    s.wert = v.yourTipp.wert;
    s.bewegt = true;
  }
  return s;
}

function formatWert(wert: number, einheit: string): string {
  return `${wert.toLocaleString("de-DE")} ${einheit}`;
}

const modul: MinigameClientModule = {
  id: BANANEN_TRESOR_ID,

  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void {
    const v = view as TresorView;
    if (v.aufloesung) {
      const a = v.aufloesung;
      const volltreffer = a.perPlayer.some((r) => r.volltreffer);
      render(
        html`<div class="bt-screen">
          <h2 class="bt-frage">${v.text}</h2>
          ${volltreffer ? html`<div class="bt-volltreffer mm-display">🔨 NAGEL AUF DEN KOPF!</div>` : ""}
          <div class="bt-strahl">
            <div class="bt-liane"></div>
            ${a.perPlayer
              .filter((r) => r.tipp !== null)
              .map((r, i) => {
                const anteil = wertZuAnteil(v, r.tipp!);
                return html`<div
                  class="bt-marker ${i % 2 === 0 ? "oben" : "unten"} ${r.volltreffer ? "volltreffer" : ""}"
                  style="left:${(anteil * 100).toFixed(2)}%;animation-delay:${(i * 0.35).toFixed(2)}s"
                >
                  <span class="bt-marker-kopf">🐵</span>
                  <span class="bt-marker-wert">${r.tipp!.toLocaleString("de-DE")}</span>
                  <span class="bt-marker-delta"
                    >${r.delta > 0 ? `+${formatMM(r.delta)}` : "—"}</span
                  >
                </div>`;
              })}
            <div class="bt-pfeil" style="left:${(wertZuAnteil(v, a.richtwert) * 100).toFixed(2)}%">
              <span class="bt-pfeil-symbol">▼</span>
              <span class="bt-pfeil-wert mm-money-zahl">${formatWert(a.richtwert, a.einheit)}</span>
            </div>
          </div>
          <p class="muted" style="text-align:center">${a.erklaerung}</p>
        </div>`,
        host,
      );
      return;
    }

    render(
      html`<div class="bt-screen">
        ${timerBanane(v.endsAt, v.timerMs, fx.serverNow())}
        <h2 class="bt-frage">${v.text}</h2>
        <div class="bt-strahl">
          <div class="bt-liane"></div>
          <span class="bt-skala-label min">${formatWert(v.eingabeMin, v.einheit)}</span>
          <span class="bt-skala-label max">${formatWert(v.eingabeMax, v.einheit)}</span>
        </div>
        <div class="bt-abgegeben">
          ${v.abgegeben.map(
            (a) => html`<span class="bt-tipp-chip">${a.eingeloggt ? "🔒" : "✍️"} 🐵</span>`,
          )}
          <span class="muted">
            ${v.answeredCount} Tipp${v.answeredCount === 1 ? "" : "s"} — Werte bleiben geheim!
          </span>
        </div>
      </div>`,
      host,
    );
  },

  renderPlayer(view: unknown, host: HTMLElement, send: SendAction): void {
    const v = view as TresorView;
    const s = lokalFuer(v);
    const eingeloggt = v.yourTipp?.eingeloggt ?? false;

    const setzeWert = (wert: number): void => {
      s.wert = Math.round(Math.min(v.eingabeMax, Math.max(v.eingabeMin, wert)));
      s.bewegt = true;
      zeichne();
    };
    const sendeTipp = (): void => {
      if (s.bewegt && !eingeloggt) void send("tipp", { wert: s.wert });
    };

    // --- Slider-Drag: Touch (touch-action:none im CSS) UND Maus-Fallback ---
    const wertAusEvent = (track: HTMLElement, clientY: number): number => {
      const rect = track.getBoundingClientRect();
      const anteil = 1 - (clientY - rect.top) / rect.height;
      return anteilZuWert(v, anteil);
    };
    const onTouch = (e: TouchEvent): void => {
      if (eingeloggt) return;
      const track = e.currentTarget as HTMLElement;
      setzeWert(wertAusEvent(track, e.touches[0].clientY));
      if (e.type === "touchend" || e.touches.length === 0) sendeTipp();
    };
    const onTouchEnd = (): void => sendeTipp();
    const onMouseDown = (e: MouseEvent): void => {
      if (eingeloggt) return;
      const track = e.currentTarget as HTMLElement;
      setzeWert(wertAusEvent(track, e.clientY));
      const onMove = (m: MouseEvent): void => setzeWert(wertAusEvent(track, m.clientY));
      const onUp = (): void => {
        document.removeEventListener("mousemove", onMove);
        document.removeEventListener("mouseup", onUp);
        sendeTipp();
      };
      document.addEventListener("mousemove", onMove);
      document.addEventListener("mouseup", onUp);
    };

    function zeichne(): void {
      const anteil = wertZuAnteil(v, s.wert);
      render(
        html`<div class="bt-player">
          <p class="bt-frage-klein">${v.text}</p>
          <div class="bt-wert-anzeige ${eingeloggt ? "eingeloggt" : ""}">
            <input
              class="bt-wert-input mm-money-zahl"
              type="number"
              inputmode="numeric"
              min=${v.eingabeMin}
              max=${v.eingabeMax}
              .value=${String(s.wert)}
              ?disabled=${eingeloggt}
              aria-label="Schätzwert direkt eingeben"
              @change=${(e: Event) => {
                const roh = Number((e.target as HTMLInputElement).value);
                if (Number.isFinite(roh)) {
                  setzeWert(roh);
                  sendeTipp();
                }
              }}
            />
            <span class="bt-einheit">${v.einheit}</span>
          </div>
          <div class="bt-slider-zeile">
            <div
              class="bt-slider ${eingeloggt ? "gesperrt" : ""}"
              role="slider"
              aria-label="Schätz-Slider"
              aria-valuemin=${v.eingabeMin}
              aria-valuemax=${v.eingabeMax}
              aria-valuenow=${s.wert}
              @touchstart=${onTouch}
              @touchmove=${onTouch}
              @touchend=${onTouchEnd}
              @mousedown=${onMouseDown}
            >
              <div class="bt-slider-fuellung" style="height:${(anteil * 100).toFixed(2)}%"></div>
              <div class="bt-slider-griff" style="bottom:${(anteil * 100).toFixed(2)}%">🍌</div>
              <span class="bt-slider-label max">${v.eingabeMax.toLocaleString("de-DE")}</span>
              <span class="bt-slider-label min">${v.eingabeMin.toLocaleString("de-DE")}</span>
            </div>
            <div class="bt-feintuning">
              <button
                class="bt-fein-button"
                ?disabled=${eingeloggt}
                aria-label="Wert plus eins"
                @click=${() => {
                  setzeWert(s.wert + 1);
                  sendeTipp();
                }}
              >
                +1
              </button>
              <button
                class="bt-fein-button"
                ?disabled=${eingeloggt}
                aria-label="Wert minus eins"
                @click=${() => {
                  setzeWert(s.wert - 1);
                  sendeTipp();
                }}
              >
                −1
              </button>
            </div>
          </div>
          ${
            eingeloggt
              ? html`<p class="bt-eingeloggt-banner">
                  🔒 Eingeloggt: ${formatWert(v.yourTipp?.wert ?? s.wert, v.einheit)}
                </p>`
              : html`<button
                  class="bt-einloggen primaer"
                  @click=${() => {
                    s.bewegt = true;
                    void send("einloggen", { wert: s.wert });
                  }}
                >
                  EINLOGGEN 🍌
                </button>`
          }
          ${
            !s.bewegt && !eingeloggt
              ? html`<p class="muted" style="text-align:center">
                  Slider bewegen oder Wert tippen — unbewegt zählt nicht!
                </p>`
              : ""
          }
        </div>`,
        host,
      );
    }
    zeichne();
  },

  explainCard: {
    text: "Schätzfrage! Zieh den Slider auf deinen Tipp — wer am nächsten dran ist, kassiert. Schätzen lohnt IMMER, exakter Volltreffer sprengt den Tresor!",
    animation: html`<span style="font-size:3rem">🍌🔐📏💰</span>`,
  },
};

// Erklär-Demo (ADDITIV): der Slider fährt auf die Tipps, die
// Zahlenstrahl-Auflösung zeigt, wer näher dran ist.
export const demoChoreo: import("../demo-typen").DemoChoreo = {
  dauer: 10600,
  beats: [
    {
      at: 0,
      requisiten: [
        { art: "schild", text: "📏 Schätzfrage!", ton: "cyan" },
        { art: "slider", wert: 0.08 },
      ],
      pose: { a: "denk", b: "denk" },
      gesicht: { a: "denk", b: "denk" },
    },
    {
      at: 2200,
      requisiten: [{ art: "slider", wert: 0.62, markerA: 0.62 }],
      pose: { a: "tipp", b: "denk" },
      gesicht: { a: "neutral", b: "denk" },
      blase: { wer: "a", text: "Mia tippt HIER!" },
      sound: "lockin-thunk",
    },
    {
      at: 4600,
      requisiten: [{ art: "slider", wert: 0.3, markerA: 0.62, markerB: 0.3 }],
      pose: { a: "idle", b: "tipp" },
      blase: { wer: "b", text: "Bo eher hier …" },
      sound: "lockin-thunk",
    },
    {
      at: 7000,
      requisiten: [
        { art: "slider", wert: 0.3, markerA: 0.62, markerB: 0.3, ziel: 0.55 },
        { art: "schild", text: "Mia ist näher dran! 💰", ton: "gold" },
      ],
      pose: { a: "jubel", b: "frust" },
      gesicht: { a: "jubel", b: "frust" },
      geldflug: { von: "mitte", zu: "a" },
      effekt: "konfetti",
      sound: "money-mittel",
    },
  ],
};

export default modul;

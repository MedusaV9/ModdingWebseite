// Client-Renderer „Die Stinkbanane": Screen = Sitzkreis mit wandernder Banane
// (CSS-Transition zwischen Slots), Spannungs-Eskalation über die verstrichene
// Durchgangs-Zeit (der ECHTE Zünd-Zeitpunkt bleibt serverseitig geheim),
// Explosion mit Matsch-Splatter. Player = Halter sieht die Frage (4 XXL),
// alle anderen trommeln ANFEUERN.
// Sound-Mapping (ART-PLAN §4.1): Stinkbananen-Ticken = tick_002 beschleunigend,
// PLATZT = slime_000, Weitergabe-Whoosh = Lücke 2 — wartet auf FxApi.sound().
import { html, render } from "lit-html";
import { formatMM } from "../../../../shared/money";
import {
  SB_EXPLOSION_MM,
  SB_WEITERGABE_MM,
  STINKBANANE_ID,
  type SbHistorieEintrag,
} from "../../../../shared/minigames/stinkbanane.meta";
import type { FxApi, MinigameClientModule, SendAction } from "../types";
import "./stinkbanane.css";

const DEKO = [
  { buchstabe: "A", emoji: "🍌", farbe: "#e6b830" },
  { buchstabe: "B", emoji: "🥥", farbe: "#8a5a3b" },
  { buchstabe: "C", emoji: "🐒", farbe: "#d1495b" },
  { buchstabe: "D", emoji: "🌴", farbe: "#2e8b57" },
] as const;

interface StinkbananeView {
  questionId: string;
  phase: "ticken" | "splatter";
  spieler: string[];
  verbunden: Record<string, boolean>;
  durchgang: number;
  durchgaengeTotal: number;
  holder: string | null;
  durchgangStartetAt: number;
  maxZuendschnurMs: number;
  endsAt: number;
  timerMs: number;
  weitergaben: Record<string, number>;
  matsch: string[];
  trommel: number;
  historie: SbHistorieEintrag[];
  jackpotGlas: number;
  finished: boolean;
  you?: string | null;
  istHalter?: boolean;
  frage?: { text: string; options: string[] } | null;
  /** Welle 1: „Durchatmen"-Cooldown nach falscher Antwort (Server-Deadline). */
  cooldownBisAt?: number | null;
  aufloesung: {
    erklaerung: string;
    perPlayer: {
      playerId: string;
      choice: null;
      correct: boolean;
      delta: number;
      weitergaben: number;
      explodiert: number;
    }[];
  } | null;
}

/** Slot-Position im Sitzkreis (Ellipse), Prozent-Koordinaten fürs CSS. */
function slotPosition(index: number, anzahl: number): { x: number; y: number } {
  const winkel = (index / Math.max(1, anzahl)) * 2 * Math.PI - Math.PI / 2;
  return { x: 50 + 40 * Math.cos(winkel), y: 50 + 36 * Math.sin(winkel) };
}

function historieText(e: SbHistorieEintrag): string {
  switch (e.typ) {
    case "weitergabe":
      return `🍌→ weitergereicht (+${SB_WEITERGABE_MM} MM)`;
    case "falsch":
      return "❌ falsch — festhalten!";
    case "timeout":
      return "⏰ zu langsam — festhalten!";
    case "explosion":
      return `💥 PLATSCH! −${SB_EXPLOSION_MM} MM ins Glas`;
    case "durchgang-start":
      return `🔁 Durchgang ${e.durchgang} läuft`;
  }
}

const modul: MinigameClientModule = {
  id: STINKBANANE_ID,

  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void {
    const v = view as StinkbananeView;

    if (v.aufloesung) {
      render(
        html`<div class="sb-screen">
          <h2 style="text-align:center">🍌💥 Die Stinkbanane ist durch!</h2>
          <p class="muted" style="text-align:center">${v.aufloesung.erklaerung}</p>
          <div class="sb-bilanz">
            ${v.aufloesung.perPlayer.map(
              (r) =>
                html`<div class="sb-bilanz-zeile ${r.explodiert > 0 ? "matsch" : ""}">
                  <span>${r.explodiert > 0 ? "🙊💩" : "🐵"}</span>
                  <span>${r.weitergaben}× weitergereicht</span>
                  <span>${r.explodiert}× geplatzt</span>
                  <strong style="color:${r.delta >= 0 ? "var(--gold)" : "var(--rot)"}">
                    ${r.delta >= 0 ? "+" : ""}${formatMM(r.delta)}
                  </strong>
                </div>`,
            )}
          </div>
          <p style="text-align:center">
            🫙 Jackpot-Glas: <strong style="color:var(--gold)">${formatMM(v.jackpotGlas)}</strong>
          </p>
        </div>`,
        host,
      );
      return;
    }

    // Spannung 0…1 aus der verstrichenen Durchgangs-Zeit — leakt nichts.
    const spannung = Math.min(
      1,
      Math.max(0, (fx.serverNow() - v.durchgangStartetAt) / v.maxZuendschnurMs),
    );
    const tickDauer = (1.1 - 0.85 * spannung).toFixed(2);
    const holderIndex = v.holder === null ? -1 : v.spieler.indexOf(v.holder);
    const bananenPos =
      holderIndex >= 0 ? slotPosition(holderIndex, v.spieler.length) : { x: 50, y: 50 };

    render(
      html`<div class="sb-screen" style="--spannung:${spannung.toFixed(3)}">
        <p class="sb-kopf">
          Durchgang ${v.durchgang} / ${v.durchgaengeTotal} · 🫙 +${formatMM(v.jackpotGlas)} ins Glas
          · 🥁 ${v.trommel}
        </p>
        <div class="sb-kreis ${v.phase === "splatter" ? "splatter" : ""}">
          ${v.spieler.map((p, i) => {
            const pos = slotPosition(i, v.spieler.length);
            const istHalter = p === v.holder;
            // Echte Affen-Köpfe + Namen (FxApi.spieler) — Fallback: Emoji.
            const info = fx.spieler?.(p) ?? null;
            return html`<div
              class="sb-slot ${istHalter ? "haelt" : ""} ${v.verbunden[p] ? "" : "offline"}"
              style="left:${pos.x}%;top:${pos.y}%"
              data-spieler=${p}
            >
              ${
                info
                  ? html`<span class="sb-puppe-wrap">
                      <span class="sb-puppe mm-affe" data-avatar=${info.avatar}></span>
                      ${v.matsch.includes(p) ? html`<span class="sb-matsch-badge">💩</span>` : ""}
                    </span>`
                  : html`<span class="sb-affe">${v.matsch.includes(p) ? "🙊💩" : "🐵"}</span>`
              }
              ${info ? html`<span class="sb-name">${info.name}</span>` : ""}
              <span class="sb-slot-info">
                ${v.weitergaben[p] ? html`+${(v.weitergaben[p] ?? 0) * SB_WEITERGABE_MM}` : ""}
              </span>
            </div>`;
          })}
          ${
            v.phase === "splatter"
              ? html`<div class="sb-explosion">💥🍌💩</div>`
              : html`<div
                  class="sb-banane"
                  style="left:${bananenPos.x}%;top:${bananenPos.y}%;--tick-dauer:${tickDauer}s"
                >
                  🍌
                </div>`
          }
        </div>
        <div class="sb-ticker">
          ${v.historie
            .slice(-3)
            .reverse()
            .map((e) => html`<span class="sb-ticker-eintrag">${historieText(e)}</span>`)}
        </div>
      </div>`,
      host,
    );
  },

  renderPlayer(view: unknown, host: HTMLElement, send: SendAction): void {
    const v = view as StinkbananeView;
    if (v.aufloesung) {
      render(html``, host); // Auflösung rendert die Player-App (kennt „you")
      return;
    }

    if (v.phase === "splatter") {
      const duBistMatsch = v.you !== null && v.you !== undefined && v.matsch.includes(v.you);
      render(
        html`<div class="sb-verdeckt">
          <span style="font-size:5rem">💥🍌</span>
          <h2>${duBistMatsch ? "PLATSCH! Du bist voll Matsch!" : "Die Banane ist geplatzt!"}</h2>
          <p class="muted">
            ${duBistMatsch ? `−${formatMM(SB_EXPLOSION_MM)} ins Jackpot-Glas …` : "Gleich geht's weiter."}
          </p>
        </div>`,
        host,
      );
      return;
    }

    if (v.istHalter && v.cooldownBisAt !== null && v.cooldownBisAt !== undefined) {
      // Cooldown nach falscher Antwort: bewusst ruhiger Beat statt Panik-Spirale.
      render(
        html`<div class="sb-verdeckt">
          <span style="font-size:4rem">😮‍💨🍌</span>
          <h2>Durchatmen …</h2>
          <p class="muted">Falsch war's — gleich kommt die nächste Frage. Die Banane pausiert.</p>
        </div>`,
        host,
      );
      return;
    }

    if (v.istHalter && v.frage) {
      render(
        html`<div class="sb-player">
          <div class="sb-warnung">🍌⚠️ DU hältst die Stinkbanane — richtig = weitergeben!</div>
          <p class="sb-frage-klein">${v.frage.text}</p>
          ${v.frage.options.map(
            (opt, i) =>
              html`<button
                class="sb-button"
                style="--deko:${DEKO[i].farbe}"
                @click=${() => send("answer", { choice: i })}
              >
                <span class="sb-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                ${opt}
              </button>`,
          )}
        </div>`,
        host,
      );
      return;
    }

    render(
      html`<div class="sb-player">
        <div class="sb-status">
          🍌 Die Stinkbanane tickt bei einem anderen Affen …
          <br />
          <span class="muted">Durchgang ${v.durchgang} / ${v.durchgaengeTotal}</span>
        </div>
        <button class="sb-trommel" @click=${() => sendeAnfeuern(send)}>🥁 ANFEUERN!</button>
        <p class="muted" style="text-align:center">
          Trommeln bringt kein Money — aber Stimmung. 🥳
        </p>
      </div>`,
      host,
    );
  },

  explainCard: {
    text: "Nur wer die tickende Stinkbanane hält, sieht die Frage. Richtig = weitergeben (+150 MM). Bei wem sie platzt: 500 MM ins Jackpot-Glas!",
    animation: html`<span style="font-size:3rem">🍌⏱️💥💩</span>`,
  },
};

// Trommel-Taps clientseitig drosseln (500 ms) — der Server zählt nur Kosmetik.
let letzterTrommelschlag = 0;
function sendeAnfeuern(send: SendAction): void {
  const jetzt = performance.now();
  if (jetzt - letzterTrommelschlag < 500) return;
  letzterTrommelschlag = jetzt;
  void send("anfeuern", {});
}

// Erklär-Demo (ADDITIV): die Banane tickt bei Mia, wandert nach richtiger
// Antwort zu Bo — und platzt beim Pech-Affen.
export const demoChoreo: import("../demo-typen").DemoChoreo = {
  dauer: 11600,
  beats: [
    {
      at: 0,
      requisiten: [{ art: "banane", bei: "a" }],
      pose: { a: "denk", b: "idle" },
      gesicht: { a: "denk", b: "neutral" },
      blase: { wer: "a", text: "Nur Mia sieht die Frage!" },
    },
    {
      at: 2400,
      requisiten: [{ art: "banane", bei: "a" }],
      pose: { a: "tipp", b: "idle" },
      blase: { wer: "a", text: "Richtig → weitergeben!" },
      sound: "lockin-thunk",
    },
    {
      at: 4400,
      requisiten: [
        { art: "banane", bei: "b" },
        { art: "schild", text: "+150 MM", ton: "gold", bei: "a" },
      ],
      pose: { a: "jubel", b: "denk" },
      gesicht: { a: "jubel", b: "denk" },
      blase: { wer: "b", text: "Jetzt tickt sie bei Bo!" },
      sound: "money-klein",
    },
    {
      at: 6900,
      requisiten: [{ art: "banane", bei: "b", hektisch: true }],
      pose: { a: "idle", b: "wackel" },
      gesicht: { a: "neutral", b: "frust" },
      blase: { wer: "b", text: "Bo zögert …" },
    },
    {
      at: 8800,
      requisiten: [
        { art: "banane", bei: "b", geplatzt: true },
        { art: "schild", text: "−500 MM ins Glas!", ton: "rot", bei: "b" },
      ],
      pose: { a: "jubel", b: "duck" },
      gesicht: { a: "jubel", b: "frust" },
      geldflug: { von: "b", zu: "mitte" },
      effekt: "explosion",
      sound: "stinkbanane-platzt",
    },
  ],
};

export default modul;

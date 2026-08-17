// Client-Renderer „Stummfilm-Studio": Screen = Kino-Leinwand mit dem STUMM
// geloopten 3-s-Clip (<video muted loop>), Ton-Schnipsel-Loop in der
// Rettungsstufe und intro5s-Ton in der Aufdeckung; Player = 4 XXL-Optionen
// (Titel — Artist), nach der Antwort verdeckt sich das Handy.
import { html, render } from "lit-html";
import { formatMM } from "../../../../shared/money";
import { MUSIKVIDEO_RATEN_ID } from "../../../../shared/minigames/musikvideo-raten.meta";
import { timerBalken } from "../../ui";
import type { FxApi, MinigameClientModule, SendAction } from "../types";
import "./musikvideo-raten.css";

const DEKO = [
  { buchstabe: "A", emoji: "🎬", farbe: "#e6b830" },
  { buchstabe: "B", emoji: "🎥", farbe: "#8a5a3b" },
  { buchstabe: "C", emoji: "🎞️", farbe: "#d1495b" },
  { buchstabe: "D", emoji: "📽️", farbe: "#2e8b57" },
] as const;

interface MvBeatEintrag {
  songId: string;
  titel: string;
  artist: string;
  answer: number;
  wert: number;
  stummRichtig: string[];
  tonRichtig: string[];
  falsch: string[];
}

interface MusikvideoRatenView {
  questionId: string;
  nichtVerfuegbar?: boolean;
  beatNr?: number;
  beatTotal?: number;
  phase?: "stumm" | "ton" | "aufdeckung";
  wert?: number;
  rettungsWert?: number;
  videoUrl?: string;
  tonUrl?: string | null;
  introUrl?: string | null;
  optionen?: string[];
  endsAt?: number;
  timerMs?: number;
  answeredCount?: number;
  spielerZahl?: number;
  eingeloggt?: string[];
  beat?: MvBeatEintrag | null;
  historie?: MvBeatEintrag[];
  deltas?: Record<string, number>;
  finished: boolean;
  yourChoice?: number | null;
  yourPass?: "stumm" | "ton" | null;
  darfNoch?: boolean;
  aufloesung: {
    erklaerung: string;
    perPlayer: { playerId: string; choice: null; correct: boolean; delta: number }[];
  } | null;
}

function name(fx: FxApi | undefined, playerId: string): string {
  return fx?.spieler?.(playerId)?.name ?? playerId;
}

function namen(fx: FxApi | undefined, ids: string[]): string {
  return ids.length > 0 ? ids.map((p) => name(fx, p)).join(", ") : "—";
}

// Aufdeckungs-Sound genau EINMAL pro Beat (Edge-Detection).
let letzterBeatKey = "";
function beatSound(v: MusikvideoRatenView, fx: FxApi): void {
  if (v.phase !== "aufdeckung" || !v.beat) return;
  const key = `${v.beat.songId}:${v.beatNr ?? 0}`;
  if (key === letzterBeatKey) return;
  letzterBeatKey = key;
  const treffer = v.beat.stummRichtig.length + v.beat.tonRichtig.length;
  fx.sound(treffer > 0 ? "money-klein" : "reveal-zap");
}

/** Kino-Leinwand: der Clip läuft IMMER stumm — Ton kommt aus eigenen
 * Audio-Elementen (ms500-Loop in der Rettungsstufe, intro5s zur Aufdeckung). */
function leinwand(v: MusikvideoRatenView) {
  return html`<div class="mvr-leinwand ${v.phase === "stumm" ? "stumm" : ""}">
    <video
      class="mvr-video"
      src=${v.videoUrl ?? ""}
      muted
      autoplay
      loop
      playsinline
      disablepictureinpicture
    ></video>
    ${v.phase === "stumm" ? html`<span class="mvr-stumm-badge">🔇 STUMM</span>` : ""}
    ${
      v.phase === "ton" && v.tonUrl
        ? html`<audio src=${v.tonUrl} autoplay loop></audio>
            <span class="mvr-stumm-badge ton">🔊 TON-SCHNIPSEL</span>`
        : ""
    }
    ${v.phase === "aufdeckung" && v.introUrl ? html`<audio src=${v.introUrl} autoplay></audio>` : ""}
  </div>`;
}

const modul: MinigameClientModule = {
  id: MUSIKVIDEO_RATEN_ID,

  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void {
    const v = view as MusikvideoRatenView;

    if (v.nichtVerfuegbar) {
      render(
        html`<div class="mvr-screen">
          <h2 style="text-align:center">🎬 Stummfilm-Studio</h2>
          <p class="muted" style="text-align:center">${v.aufloesung?.erklaerung ?? ""}</p>
        </div>`,
        host,
      );
      return;
    }
    beatSound(v, fx);

    if (v.aufloesung) {
      render(
        html`<div class="mvr-screen">
          <h2 style="text-align:center">🎬 Stummfilm-Studio — der Abspann!</h2>
          <p class="muted" style="text-align:center">${v.aufloesung.erklaerung}</p>
          <div class="mvr-bilanz">
            ${[...v.aufloesung.perPlayer]
              .sort((a, b) => b.delta - a.delta)
              .map(
                (r) =>
                  html`<div class="mvr-bilanz-zeile ${r.delta > 0 ? "gewonnen" : ""}">
                    <span>${r.delta > 0 ? "🌟" : "🎞️"}</span>
                    <span>${name(fx, r.playerId)}</span>
                    <strong class="mm-money-zahl">+${formatMM(r.delta)}</strong>
                  </div>`,
              )}
          </div>
        </div>`,
        host,
      );
      return;
    }

    const kopf = html`<div class="mvr-kopf">
      <span class="mvr-badge">🎬 STUMMFILM-STUDIO</span>
      <span class="muted"
        >Clip ${v.beatNr} / ${v.beatTotal} —
        ${
          v.phase === "ton"
            ? html`Rettungsstufe:
                <strong class="mm-money-zahl">${formatMM(v.rettungsWert ?? 0)}</strong>`
            : html`stumm erkannt: <strong class="mm-money-zahl">${formatMM(v.wert ?? 0)}</strong>`
        }</span
      >
    </div>`;

    if (v.phase === "aufdeckung" && v.beat) {
      const b = v.beat;
      render(
        html`<div class="mvr-screen">
          ${kopf} ${leinwand(v)}
          <div class="mvr-aufdeckung">
            <span class="mvr-titel">🎵 ${b.titel} — ${b.artist}</span>
            <div class="mvr-stroeme">
              <div class="mvr-strom gut">
                🌟 Stumm erkannt (+${formatMM(b.wert)}): ${namen(fx, b.stummRichtig)}
              </div>
              <div class="mvr-strom halb">
                🔊 Mit Ton gerettet (+${formatMM(Math.round(b.wert / 2))}):
                ${namen(fx, b.tonRichtig)}
              </div>
              ${
                b.falsch.length > 0
                  ? html`<div class="mvr-strom schlecht">🙈 Daneben: ${namen(fx, b.falsch)}</div>`
                  : ""
              }
            </div>
          </div>
          ${timerBalken(v.endsAt ?? 0, v.timerMs ?? 1, fx.serverNow(), true)}
        </div>`,
        host,
      );
      return;
    }

    render(
      html`<div class="mvr-screen">
        ${kopf} ${leinwand(v)} ${timerBalken(v.endsAt ?? 0, v.timerMs ?? 1, fx.serverNow())}
        <div class="mvr-optionen">
          ${(v.optionen ?? []).map(
            (opt, i) =>
              html`<div class="mvr-option" style="--deko:${DEKO[i].farbe}">
                <span class="mvr-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span> ${opt}
              </div>`,
          )}
        </div>
        <p class="muted" style="text-align:center">
          ${
            v.phase === "ton"
              ? html`🔊 RETTUNGSSTUFE — wer noch nicht geraten hat, darf jetzt (halber Wert)!`
              : html`🔇 Der Clip läuft stumm … wer erkennt den Song?`
          }
          ${v.answeredCount} / ${v.spielerZahl} eingeloggt
        </p>
      </div>`,
      host,
    );
  },

  renderPlayer(view: unknown, host: HTMLElement, send: SendAction, fx?: FxApi): void {
    const v = view as MusikvideoRatenView;
    if (v.nichtVerfuegbar || v.aufloesung) {
      render(html``, host); // Auflösung rendert die Player-App (kennt „you")
      return;
    }

    if (v.phase === "aufdeckung") {
      render(
        html`<div class="mvr-player">
          <div class="mvr-status">🎬 Aufdeckung! Schau auf die große Leinwand …</div>
        </div>`,
        host,
      );
      return;
    }

    const gesperrt = v.yourChoice !== null && v.yourChoice !== undefined;
    if (gesperrt) {
      render(
        html`<div class="mvr-player">
          <div class="mvr-status">
            🙈 Eingeloggt
            (${v.yourPass === "stumm" ? "stumm — voller Wert" : "mit Ton — halber Wert"})!<br />
            <span class="muted">Ob's stimmt, verrät erst der Abspann …</span>
          </div>
        </div>`,
        host,
      );
      return;
    }

    render(
      html`<div class="mvr-player">
        <p class="mvr-hinweis">
          ${
            v.phase === "ton"
              ? html`🔊 RETTUNGSSTUFE: jetzt raten bringt noch
                  <strong>${formatMM(v.rettungsWert ?? 0)}</strong>!`
              : html`🔇 Der Clip läuft STUMM auf dem Screen — früh raten bringt
                  <strong>${formatMM(v.wert ?? 0)}</strong>, warten auf den Ton nur die Hälfte!`
          }
        </p>
        ${(v.optionen ?? []).map(
          (opt, i) =>
            html`<button
              class="mvr-option-btn"
              style="--deko:${DEKO[i].farbe}"
              @click=${() => {
                fx?.sound("lockin-thunk");
                void send("answer", { choice: i });
              }}
            >
              <span class="mvr-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
              ${opt}
            </button>`,
        )}
      </div>`,
      host,
    );
  },

  explainCard: {
    text: "Auf dem Screen läuft ein Musikvideo — 3 Sekunden, STUMM! Wer den Song früh erkennt, kassiert den vollen Wert. Wer wartet, bekommt einen Ton-Schnipsel als Rettung — für die halbe Gage. Die Auflösung spielt den Clip MIT Ton.",
    animation: html`<span style="font-size:3rem">🎬🔇🎵💰</span>`,
  },
};

// Erklär-Demo (ADDITIV): stummes Musikvideo — früh erkennen = voller Wert,
// auf den Ton-Schnipsel warten = halbe Gage.
export const demoChoreo: import("../demo-typen").DemoChoreo = {
  dauer: 10800,
  beats: [
    {
      at: 0,
      requisiten: [{ art: "schild", text: "🎬 Musikvideo läuft — 🔇 STUMM!", ton: "cyan" }],
      pose: { a: "denk", b: "denk" },
      gesicht: { a: "denk", b: "denk" },
    },
    {
      at: 2400,
      requisiten: [
        { art: "schild", text: "🎬 🔇 …", ton: "cyan" },
        { art: "frage", tippA: 0 },
        { art: "schild", text: "voller Wert!", ton: "gold", bei: "a" },
      ],
      pose: { a: "buzz", b: "denk" },
      gesicht: { a: "jubel", b: "denk" },
      blase: { wer: "a", text: "Mia erkennt den Song sofort!" },
      sound: "lockin-thunk",
    },
    {
      at: 5000,
      requisiten: [
        { art: "schild", text: "🎵 Ton-Schnipsel als Rettung", ton: "cyan" },
        { art: "frage", tippA: 0, tippB: 0 },
        { art: "schild", text: "halbe Gage", ton: "papier", bei: "b" },
      ],
      pose: { a: "idle", b: "tipp" },
      blase: { wer: "b", text: "Bo brauchte den Ton …" },
      sound: "lockin-thunk",
    },
    {
      at: 7600,
      requisiten: [
        { art: "frage", tippA: 0, tippB: 0, richtig: 0 },
        { art: "schild", text: "+500 MM", ton: "gold", bei: "a" },
        { art: "schild", text: "+250 MM", ton: "papier", bei: "b" },
      ],
      pose: { a: "jubel", b: "jubel" },
      gesicht: { a: "jubel", b: "neutral" },
      blase: { wer: "a", text: "Auflösung MIT Ton! 🎵" },
      effekt: "konfetti",
      sound: "richtig",
    },
  ],
};

export default modul;

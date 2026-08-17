// Client-Renderer „Wer singt's?": Screen = SCHALLPLATTEN-KARTE — die Platte
// senkt sich mit dem Song-Titel + Jahr-Hinweis aufs Deck (auflegen), dreht
// sich beim Raten gemächlich weiter und FLIPPT bei der Auflösung zum
// Interpreten (CSS-3D, .ws-flip). Alle raten gleichzeitig, der Zähler hüpft
// anonym. Player = 4 XXL-Interpret-Buttons im Rate-Fenster, sonst kompakte
// Warte-Zustände. Kein Audio, keine Liedtexte — reines Musik-WISSEN.
import { html, render } from "lit-html";
import {
  WER_SINGTS_ID,
  wsGenreLabel,
  wsJahrHinweis,
  type WsGenre,
} from "../../../../shared/minigames/wer-singts.meta";
import { formatMM } from "../../../../shared/money";
import { timerBalken } from "../../ui";
import type { FxApi, MinigameClientModule, SendAction } from "../types";
import "./wer-singts.css";

const DEKO = [
  { buchstabe: "A", emoji: "🎤", farbe: "#e6b830" },
  { buchstabe: "B", emoji: "🎸", farbe: "#8a5a3b" },
  { buchstabe: "C", emoji: "🎹", farbe: "#d1495b" },
  { buchstabe: "D", emoji: "🥁", farbe: "#2e8b57" },
] as const;

interface WsHistorieEintrag {
  beatNr: number;
  titel: string;
  artist: string;
  jahr: number | null;
  genre: WsGenre;
  ausSongPack: boolean;
  correctIndex: number;
  richtige: string[];
  falsche: string[];
  wert: number;
}

interface WsView {
  questionId: string;
  beatNr: number;
  beatTotal: number;
  phase: "auflegen" | "raten" | "aufdeckung";
  endsAt: number;
  timerMs: number;
  titel: string;
  jahr: number | null;
  genre: WsGenre;
  ausSongPack: boolean;
  schwierigkeit: string;
  wert: number;
  options: string[] | null;
  artist: string | null;
  answeredCount: number;
  spielerZahl: number;
  beat: WsHistorieEintrag | null;
  historie: WsHistorieEintrag[];
  deltas: Record<string, number>;
  finished: boolean;
  yourChoice?: number | null;
  aufloesung: {
    correctIndex: number | null;
    erklaerung: string;
    perPlayer: {
      playerId: string;
      choice: null;
      correct: boolean;
      delta: number;
      treffer: number;
    }[];
  } | null;
}

function info(fx: FxApi | undefined, playerId: string): { name: string; avatar: string } {
  const s = fx?.spieler?.(playerId);
  return { name: s?.name ?? playerId, avatar: s?.avatar ?? "gelb" };
}

/** Die Schallplatten-Karte: Vorderseite Titel + Jahr, Rückseite Interpret.
 * `gedreht` flippt per CSS-3D — die Auflösung „dreht die Platte um". */
function plattenKarte(v: WsView, gedreht: boolean) {
  return html`<div
    class="ws-karte ${v.phase === "auflegen" ? "senkt" : ""} ${gedreht ? "flip" : ""}"
  >
    <div class="ws-karte-innen">
      <div class="ws-seite vorn">
        <div class="ws-platte ${v.phase === "raten" ? "dreht" : ""}">
          <div class="ws-label">
            <span class="ws-genre"
              >${v.ausSongPack ? "🎁 Song-Wunsch" : wsGenreLabel(v.genre)}</span
            >
            <strong class="ws-titel">„${v.titel}"</strong>
            <span class="ws-jahr">📅 ${wsJahrHinweis(v.jahr)}</span>
          </div>
        </div>
        <span class="ws-nadel">🪡</span>
      </div>
      <div class="ws-seite hinten">
        <div class="ws-platte">
          <div class="ws-label aufgedeckt">
            <span class="ws-genre">Das Original:</span>
            <strong class="ws-artist">${v.artist ?? v.beat?.artist ?? "?"}</strong>
            <span class="ws-jahr">„${v.titel}" · ${wsJahrHinweis(v.jahr)}</span>
          </div>
        </div>
      </div>
    </div>
  </div>`;
}

// Plattenspieler-Beats: pro Beat/Phase EIN Sound (Edge-Detection über den Key).
let letzterSoundKey = "";
function beatSound(v: WsView, fx: FxApi): void {
  const key = `${v.phase}:${v.beatNr}`;
  if (key === letzterSoundKey) return;
  letzterSoundKey = key;
  if (v.phase === "auflegen") fx.sound("karte-slide"); // die Platte senkt sich
  if (v.phase === "raten") fx.sound("frage-ein");
  if (v.phase === "aufdeckung") fx.sound("reveal-zap"); // die Platte dreht sich
}

const modul: MinigameClientModule = {
  id: WER_SINGTS_ID,

  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void {
    const v = view as WsView;
    beatSound(v, fx);

    if (v.aufloesung) {
      render(
        html`<div class="ws-screen">
          <div class="ws-kopf"><span class="ws-badge">🎙️ WER SINGT'S?</span></div>
          <h2 class="ws-ueberschrift">Platten-Bilanz</h2>
          <div class="ws-regal">
            ${v.historie.map(
              (h) =>
                html`<div class="ws-regal-karte">
                  <span class="ws-regal-titel">„${h.titel}"</span>
                  <strong>${h.artist}</strong>
                  <span class="muted">${wsJahrHinweis(h.jahr)} · ${h.richtige.length} Treffer</span>
                </div>`,
            )}
          </div>
          <div class="ws-bilanz">
            ${[...v.aufloesung.perPlayer]
              .sort((a, b) => b.delta - a.delta)
              .map(
                (r) =>
                  html`<div class="ws-bilanz-zeile ${r.correct ? "gut" : ""}">
                    <span class="ws-mini mm-affe" data-avatar=${info(fx, r.playerId).avatar}></span>
                    <span>${info(fx, r.playerId).name}</span>
                    <span class="muted">${r.treffer}/${v.beatTotal} Platten erkannt</span>
                    <strong class="mm-money-zahl">+${formatMM(r.delta)}</strong>
                  </div>`,
              )}
          </div>
        </div>`,
        host,
      );
      return;
    }

    const inAufdeckung = v.phase === "aufdeckung";
    render(
      html`<div class="ws-screen">
        <div class="ws-kopf">
          <span class="ws-badge">🎙️ WER SINGT'S? · Platte ${v.beatNr}/${v.beatTotal}</span>
          <span class="muted">
            ${
              inAufdeckung
                ? `${v.beat?.richtige.length ?? 0} von ${v.spielerZahl} wussten es`
                : `Wert ${formatMM(v.wert)} + Speed-Bonus · ${v.answeredCount}/${v.spielerZahl} Tipps`
            }
          </span>
        </div>
        ${v.phase === "raten" ? timerBalken(v.endsAt, v.timerMs, fx.serverNow()) : ""}
        ${plattenKarte(v, inAufdeckung)}
        ${
          v.phase === "auflegen"
            ? html`<p class="ws-hinweis muted">
                🎧 Kein Ton, kein Text — WER hat diesen Welthit gesungen?
              </p>`
            : ""
        }
        ${
          v.options !== null
            ? html`<div class="ws-optionen">
                ${v.options.map(
                  (opt, i) =>
                    html`<div
                      class="ws-option ${inAufdeckung && v.beat?.correctIndex === i ? "richtig" : ""} ${
                        inAufdeckung && v.beat?.correctIndex !== i ? "verblasst" : ""
                      }"
                      style="--deko:${DEKO[i].farbe}"
                    >
                      <span class="ws-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                      ${opt}
                    </div>`,
                )}
              </div>`
            : ""
        }
        ${
          v.historie.length > 0 && !inAufdeckung
            ? html`<div class="ws-ticker muted">
                ${v.historie
                  .slice(-3)
                  .map((h) => `„${h.titel}" → ${h.artist}`)
                  .join(" · ")}
              </div>`
            : ""
        }
      </div>`,
      host,
    );
  },

  renderPlayer(view: unknown, host: HTMLElement, send: SendAction, fx?: FxApi): void {
    const v = view as WsView;
    if (v.aufloesung) {
      render(html``, host); // Auflösung rendert die Player-App (kennt „you")
      return;
    }

    if (v.phase === "auflegen") {
      render(
        html`<div class="ws-player">
          <div class="ws-status">
            💿 Platte ${v.beatNr}/${v.beatTotal} legt auf …<br />
            <strong>„${v.titel}"</strong> (${wsJahrHinweis(v.jahr)})<br />
            <span class="muted">Gleich kommen 4 Interpreten — wer singt's?</span>
          </div>
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "raten") {
      const gewaehlt = v.yourChoice ?? null;
      render(
        html`<div class="ws-player">
          <p class="ws-frage-klein">
            „${v.titel}" (${wsJahrHinweis(v.jahr)}) — wer singt's? ·
            <strong>${formatMM(v.wert)}</strong> + Speed
          </p>
          ${(v.options ?? []).map(
            (opt, i) =>
              html`<button
                class="ws-button ${gewaehlt === i ? "gewaehlt" : ""} ${gewaehlt !== null ? "gesperrt" : ""}"
                style="--deko:${DEKO[i].farbe}"
                ?disabled=${gewaehlt !== null}
                @click=${() => {
                  fx?.sound("lockin-thunk");
                  void send("answer", { choice: i });
                }}
              >
                <span class="ws-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                ${opt}
              </button>`,
          )}
          ${
            gewaehlt !== null
              ? html`<p class="muted" style="text-align:center">
                  Eingerastet — schnell war gut: der Speed-Bonus zählt!
                </p>`
              : ""
          }
        </div>`,
        host,
      );
      return;
    }

    // Aufdeckung: die Platte dreht sich — kompakter Status.
    const b = v.beat;
    render(
      html`<div class="ws-player">
        <div class="ws-status">
          💿 „${v.titel}" ist von<br />
          <strong class="ws-artist-klein">${v.artist ?? b?.artist ?? "?"}</strong><br />
          <span class="muted">
            ${
              b !== null && b.richtige.length > 0
                ? `${b.richtige.length} Treffer · je bis zu ${formatMM(b.wert)} + Speed`
                : "Niemand wusste es — die Platte kichert."
            }
          </span>
        </div>
      </div>`,
      host,
    );
  },

  explainCard: {
    text: "Musik-Wissen ohne Ton: Die Schallplatte zeigt einen WELTHIT-Titel + Jahr — aber WER singt ihn? 4 Interpreten aus derselben Ära stehen zur Wahl, alle raten gleichzeitig. Richtig zahlt den Bekanntheits-Wert plus Speed-Bonus. Bei der Auflösung dreht sich die Platte um!",
    animation: html`<span style="font-size:3rem">💿🎤🐒❓🏦</span>`,
  },
};

// Erklär-Demo (ADDITIV): die Platte senkt sich („Atemlos…“), beide tippen —
// Mia kennt das Original, die Platte flippt zum Interpreten, Bonus für Speed.
export const demoChoreo: import("../demo-typen").DemoChoreo = {
  dauer: 11000,
  beats: [
    {
      at: 0,
      requisiten: [{ art: "schild", text: "💿 Titel + Jahr — WER singt's?", ton: "cyan" }],
      pose: { a: "denk", b: "denk" },
      gesicht: { a: "neutral", b: "neutral" },
      blase: { wer: "a", text: "Kein Ton — nur Wissen!" },
      sound: "karte-slide",
    },
    {
      at: 2400,
      requisiten: [{ art: "frage" }],
      pose: { a: "denk", b: "denk" },
      gesicht: { a: "denk", b: "denk" },
      blase: { wer: "b", text: "4 Interpreten, selbe Ära …" },
      sound: "frage-ein",
    },
    {
      at: 5000,
      requisiten: [{ art: "frage", tippA: 1, tippB: 3 }],
      pose: { a: "tipp", b: "tipp" },
      gesicht: { a: "jubel", b: "denk" },
      blase: { wer: "a", text: "Mia tippt blitzschnell!" },
      sound: "lockin-thunk",
    },
    {
      at: 7200,
      requisiten: [{ art: "frage", tippA: 1, tippB: 3, richtig: 1 }],
      pose: { a: "jubel", b: "frust" },
      gesicht: { a: "jubel", b: "frust" },
      blase: { wer: "b", text: "Die Platte dreht sich um!" },
      sound: "reveal-zap",
    },
    {
      at: 9400,
      requisiten: [{ art: "schild", text: "+150 MM + Speed-Bonus!", ton: "gold", bei: "a" }],
      pose: { a: "jubel", b: "idle" },
      gesicht: { a: "jubel", b: "neutral" },
      geldflug: { von: "mitte", zu: "a" },
      effekt: "konfetti",
      sound: "money-mittel",
    },
  ],
};

export default modul;

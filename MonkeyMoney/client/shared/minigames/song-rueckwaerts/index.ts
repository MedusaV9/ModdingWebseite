// Client-Renderer „Rückwärts-Banane": Screen = Rückwärts-Bühne (die Banane
// dreht rückwärts, das rueckwaerts5s-Audio läuft ÜBER DEN SCREEN nach dem
// Server-Abspielplan via FxApi.sound mit Media-URL); alle raten gleichzeitig
// am Handy (4 XXL-Buttons). Die Auflösung spielt das Intro VORWÄRTS — Aha!
import { html, render } from "lit-html";
import { formatMM, type Schwierigkeit } from "../../../../shared/money";
import {
  RB_CLIP_MS,
  SONG_RUECKWAERTS_ID,
} from "../../../../shared/minigames/song-rueckwaerts.meta";
import { timerBalken } from "../../ui";
import type { FxApi, MinigameClientModule, SendAction } from "../types";
import "./song-rueckwaerts.css";

const DEKO = [
  { buchstabe: "A", emoji: "🍌", farbe: "#e6b830" },
  { buchstabe: "B", emoji: "🥥", farbe: "#8a5a3b" },
  { buchstabe: "C", emoji: "🐒", farbe: "#d1495b" },
  { buchstabe: "D", emoji: "🌴", farbe: "#2e8b57" },
] as const;

interface RbAufloesung {
  correctIndex: number;
  titel: string;
  artist: string;
  jahr: number;
  erklaerung: string;
  perPlayer: { playerId: string; choice: number | null; correct: boolean; delta: number }[];
}

interface SongRueckwaertsView {
  questionId: string;
  schwierigkeit: Schwierigkeit;
  options: string[];
  startedAt: number;
  endsAt: number;
  timerMs: number;
  abspielplan: number[];
  maxAbspielungen: number;
  answeredCount: number;
  eingeloggt: string[];
  finished: boolean;
  yourChoice?: number | null;
  medien?: { rueckwaertsUrl: string; introUrl: string | null };
  aufloesung: RbAufloesung | null;
}

// ---------- Screen-Audio: der SERVER-Abspielplan ist die Wahrheit ----------
// renderScreen läuft alle ~120 ms — jede geplante Abspielung startet genau
// EINMAL (Key questionId:index), Reconnects mitten in alte Slots spielen
// nicht nach (Fenster: nur innerhalb der Clip-Länge nach dem Slot).
const gespielteSlots = new Set<string>();
let letzterSfxKey = "";

function screenAudio(v: SongRueckwaertsView, fx: FxApi): void {
  if (!v.medien) return;
  const now = fx.serverNow();
  if (v.finished) {
    if (v.medien.introUrl !== null && !gespielteSlots.has(`${v.questionId}:intro`)) {
      gespielteSlots.add(`${v.questionId}:intro`);
      fx.sound(v.medien.introUrl);
    }
    if (letzterSfxKey !== `${v.questionId}:fertig`) {
      letzterSfxKey = `${v.questionId}:fertig`;
      fx.sound("reveal-zap");
    }
    return;
  }
  v.abspielplan.forEach((slot, i) => {
    const key = `${v.questionId}:rw:${i}`;
    if (gespielteSlots.has(key)) return;
    if (now < slot || now >= slot + RB_CLIP_MS) return;
    gespielteSlots.add(key);
    fx.sound(v.medien!.rueckwaertsUrl);
  });
  if (gespielteSlots.size > 64) gespielteSlots.clear(); // alte Fragen vergessen
}

/** Läuft der Rückwärts-Clip GERADE? (für die Dreh-Animation) */
function clipLaeuft(v: SongRueckwaertsView, now: number): boolean {
  return !v.finished && v.abspielplan.some((slot) => now >= slot && now < slot + RB_CLIP_MS);
}

const modul: MinigameClientModule = {
  id: SONG_RUECKWAERTS_ID,
  // screenAudio spielt reveal-zap + Vorwärts-Intro SELBST bei finished —
  // die zentrale Regie lässt ihren Dreiklang (Riser→Stille→Fanfare) hier aus.
  eigeneAufloesungsRegie: true,

  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void {
    const v = view as SongRueckwaertsView;
    screenAudio(v, fx);
    const now = fx.serverNow();
    const a = v.aufloesung;
    const laeuft = clipLaeuft(v, now);
    const gespielt = Math.min(v.maxAbspielungen, v.abspielplan.filter((t) => t <= now).length);

    render(
      html`<div class="rb-screen">
        <div class="rb-buehne ${a ? "vorwaerts" : ""}">
          <div class="rb-banane ${laeuft ? "dreht" : ""} ${a ? "party" : ""}">🍌</div>
          <div class="rb-status">
            ${
              a
                ? html`<h2 class="rb-banner vorwaerts">▶️ VORWÄRTS — der Aha-Moment!</h2>
                    <h2 class="rb-titel-reveal">„${a.titel}"</h2>
                    <p class="rb-artist-reveal">${a.artist} · ${a.jahr}</p>`
                : html`<h2 class="rb-banner">⏪ RÜCKWÄRTS-BANANE</h2>
                    <p class="rb-abspielungen">
                      ${Array.from({ length: v.maxAbspielungen }, (_, i) =>
                        i < gespielt ? "🔊" : "🔈",
                      ).join(" ")}
                      · Abspielung ${Math.max(1, gespielt)}/${v.maxAbspielungen}
                    </p>
                    <p class="rb-hinweis muted">
                      Alle raten gleichzeitig — schnell sein bringt Bonus!
                    </p>`
            }
          </div>
        </div>
        ${a ? "" : timerBalken(v.endsAt, v.timerMs, now)}
        <div class="rb-optionen">
          ${v.options.map(
            (opt, i) =>
              html`<div
                class="rb-option ${a ? (i === a.correctIndex ? "richtig" : "falsch") : ""}"
                style="--deko:${DEKO[i].farbe}"
              >
                <span class="rb-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                ${opt}
                ${
                  a && i === a.correctIndex
                    ? html`<span class="rb-treffer">
                        ${a.perPlayer
                          .filter((r) => r.correct)
                          .map(
                            (r) =>
                              html`<b
                                >${fx.spieler?.(r.playerId)?.name ?? "?"} +${formatMM(r.delta)}</b
                              >`,
                          )}
                      </span>`
                    : ""
                }
              </div>`,
          )}
        </div>
        ${
          a
            ? ""
            : html`<div class="rb-eingeloggt">
                ${v.eingeloggt.map(() => html`<span class="rb-ohr">🎧</span>`)}
                <span class="muted">${v.answeredCount} eingeloggt</span>
              </div>`
        }
      </div>`,
      host,
    );
  },

  renderPlayer(view: unknown, host: HTMLElement, send: SendAction, fx?: FxApi): void {
    const v = view as SongRueckwaertsView;
    if (v.aufloesung) {
      render(html``, host); // Auflösung rendert die Player-App (kennt „you")
      return;
    }
    const gewaehlt = v.yourChoice ?? null;

    if (gewaehlt !== null) {
      render(
        html`<div class="rb-verdeckt">
          <span style="font-size:5rem">🎧</span>
          <h2>Eingeloggt!</h2>
          <p class="muted">
            Option ${DEKO[gewaehlt]?.buchstabe ?? "?"} ist drin — gleich läuft's vorwärts.
          </p>
        </div>`,
        host,
      );
      return;
    }

    render(
      html`<div class="rb-player">
        <div class="rb-player-kopf">
          ⏪ Welcher Song läuft rückwärts?
          ${fx ? timerBalken(v.endsAt, v.timerMs, fx.serverNow(), true) : ""}
        </div>
        ${v.options.map(
          (opt, i) =>
            html`<button
              class="rb-button"
              style="--deko:${DEKO[i].farbe}"
              @click=${() => send("answer", { choice: i })}
            >
              <span class="rb-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
              ${opt}
            </button>`,
        )}
      </div>`,
      host,
    );
  },

  explainCard: {
    text: "Ein Song läuft RÜCKWÄRTS — alle raten gleichzeitig aus 4 Optionen! Schnell sein bringt Speed-Bonus. Die Auflösung spielt das Intro vorwärts: der Aha-Moment.",
    animation: html`<span style="font-size:3rem">⏪🍌🎵▶️</span>`,
  },
};

// Erklär-Demo: beide lauschen dem Rückwärts-Brei, Mia tippt schnell (Bonus),
// Bo spät — die Auflösung dreht die Banane vorwärts und beide verstehen's.
export const demoChoreo: import("../demo-typen").DemoChoreo = {
  dauer: 10_000,
  beats: [
    {
      at: 0,
      requisiten: [{ art: "schild", text: "⏪ …gnalk sadnegrI", ton: "cyan", bei: "mitte" }],
      pose: { a: "denk", b: "denk" },
      gesicht: { a: "denk", b: "denk" },
      blase: { wer: "b", text: "Klingt wie Rückwärts-Brei …" },
    },
    {
      at: 2_600,
      requisiten: [
        { art: "frage", tippA: 1, tippB: null },
        { art: "schild", text: "Mia tippt SOFORT", ton: "gruen", bei: "a" },
      ],
      pose: { a: "tipp", b: "denk" },
      gesicht: { a: "jubel", b: "denk" },
      sound: "lockin-thunk",
    },
    {
      at: 4_800,
      requisiten: [{ art: "frage", tippA: 1, tippB: 1 }],
      pose: { a: "idle", b: "tipp" },
      gesicht: { a: "neutral", b: "denk" },
      blase: { wer: "b", text: "Jetzt hab ich's auch!" },
      sound: "lockin-thunk",
    },
    {
      at: 7_000,
      requisiten: [
        { art: "frage", tippA: 1, tippB: 1, richtig: 1 },
        { art: "schild", text: "▶️ VORWÄRTS! +Bonus für Mia", ton: "gold", bei: "mitte" },
      ],
      pose: { a: "jubel", b: "jubel" },
      gesicht: { a: "jubel", b: "jubel" },
      geldflug: { von: "mitte", zu: "a" },
      effekt: "konfetti",
      sound: "richtig",
    },
  ],
};

export default modul;

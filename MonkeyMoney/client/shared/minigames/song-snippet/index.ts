// Client-Renderer „Der Blitz-DJ": Screen = Plattenspieler-Bühne mit Stufen-
// Treppe + „ALLE LAUSCHEN"-Moment (das Snippet läuft ÜBER DEN SCREEN via
// FxApi.sound mit Media-URL — sound.ts spielt beliebige URLs auf dem
// Media-Kanal); Player = Buzzer-XXL, nach dem Buzz-Sieg die 4 Optionen.
import { html, render } from "lit-html";
import { formatMM, type Schwierigkeit } from "../../../../shared/money";
import {
  SONG_SNIPPET_ID,
  SS_SNIPPET_MS,
  ssStufenWert,
} from "../../../../shared/minigames/song-snippet.meta";
import { timerBalken } from "../../ui";
import type { FxApi, MinigameClientModule, SendAction } from "../types";
import "./song-snippet.css";

const DEKO = [
  { buchstabe: "A", emoji: "🍌", farbe: "#e6b830" },
  { buchstabe: "B", emoji: "🥥", farbe: "#8a5a3b" },
  { buchstabe: "C", emoji: "🐒", farbe: "#d1495b" },
  { buchstabe: "D", emoji: "🌴", farbe: "#2e8b57" },
] as const;

interface SsAufloesung {
  correctIndex: number;
  titel: string;
  artist: string;
  jahr: number;
  erklaerung: string;
  gewinnerId: string | null;
  gewinnerStufe: number | null;
  optionen: string[];
  perPlayer: { playerId: string; choice: number | null; correct: boolean; delta: number }[];
}

interface SongSnippetView {
  questionId: string;
  phase: "intro" | "lauschen" | "raten" | "fertig";
  stufe: number;
  stufenTotal: number;
  snippetMs: number;
  schwierigkeit: Schwierigkeit;
  aktuellerWert: number;
  startedAt: number;
  lauschenStartetAt: number;
  endsAt: number;
  timerMs: number;
  raterId: string | null;
  fotofinish: boolean;
  gesperrt: string[];
  /** Buzzes der aktuellen Stufe — BEWUSST nicht answeredCount (das Feld
   * triggert die Auto-GM-+10s-Heuristik, die hier die Eskalation zerstört). */
  buzzCount: number;
  finished: boolean;
  // Screen-Extras:
  optionen?: string[];
  medien?: { snippetUrl: string; introUrl: string | null };
  // Player-Extras:
  duBistRater?: boolean;
  duGesperrt?: boolean;
  deinBuzz?: boolean;
  options?: string[];
  buzzAktiv?: boolean;
  aufloesung: SsAufloesung | null;
}

/** „0,1 s" / „1,0 s" / „5 s (Intro)" — Anzeige-Label einer Snippet-Länge. */
function snippetLabel(ms: number): string {
  return ms >= 5_000 ? "5 s Intro" : `${(ms / 1_000).toLocaleString("de-DE")} s`;
}

// ---------- Screen-Audio: EIN Abspiel-Moment pro Stufe/Auflösung ----------
// renderScreen läuft alle ~120 ms — die Keys stellen sicher, dass jedes
// Snippet (und das Vorwärts-Intro der Auflösung) genau EINMAL startet.
let letzterMediaKey = "";
let letzterSfxKey = "";

function screenAudio(v: SongSnippetView, fx: FxApi): void {
  if (!v.medien) return;
  if (v.finished) {
    if (v.medien.introUrl !== null && letzterMediaKey !== `${v.questionId}:intro`) {
      letzterMediaKey = `${v.questionId}:intro`;
      fx.sound(v.medien.introUrl);
    }
    if (letzterSfxKey !== `${v.questionId}:fertig`) {
      letzterSfxKey = `${v.questionId}:fertig`;
      fx.sound(v.aufloesung?.gewinnerId ? "richtig" : "zeit-um");
    }
    return;
  }
  if (v.phase === "lauschen" && letzterMediaKey !== `${v.questionId}:${v.stufe}`) {
    letzterMediaKey = `${v.questionId}:${v.stufe}`;
    fx.sound(v.medien.snippetUrl);
  }
  if (v.phase === "raten" && letzterSfxKey !== `${v.questionId}:raten:${v.stufe}`) {
    letzterSfxKey = `${v.questionId}:raten:${v.stufe}`;
    fx.sound("buzzer");
  }
}

/** Verfalls-Treppe: aktive Stufe leuchtet, verfallene sind durchgestrichen. */
function treppe(v: SongSnippetView) {
  return html`<div class="ss-treppe">
    ${SS_SNIPPET_MS.map((ms, s) => {
      const status = s < v.stufe || v.finished ? "verfallen" : s === v.stufe ? "aktiv" : "";
      return html`<span class="ss-stufe ${status}">
        <b>${snippetLabel(ms)}</b> ${formatMM(ssStufenWert(v.schwierigkeit, s))}
      </span>`;
    })}
  </div>`;
}

function plattenspieler(v: SongSnippetView) {
  const dreht = v.phase === "lauschen" && !v.finished;
  return html`<div class="ss-plattenspieler ${dreht ? "dreht" : ""}">
    <div class="ss-platte">
      <div class="ss-rille"></div>
      <div class="ss-label">🎵</div>
    </div>
    <div class="ss-tonarm"></div>
  </div>`;
}

function name(fx: FxApi | undefined, playerId: string | null): string {
  if (playerId === null) return "?";
  return fx?.spieler?.(playerId)?.name ?? "Ein Affe";
}

const modul: MinigameClientModule = {
  id: SONG_SNIPPET_ID,
  // screenAudio spielt richtig/zeit-um + Song-Intro SELBST bei finished —
  // die zentrale Regie lässt ihren Dreiklang (Riser→Stille→Fanfare) hier aus.
  eigeneAufloesungsRegie: true,

  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void {
    const v = view as SongSnippetView;
    screenAudio(v, fx);
    const a = v.aufloesung;

    render(
      html`<div class="ss-screen">
        ${treppe(v)}
        <div class="ss-buehne">
          ${plattenspieler(v)}
          <div class="ss-status">
            ${
              a
                ? html`<h2 class="ss-titel-reveal">„${a.titel}"</h2>
                    <p class="ss-artist-reveal">${a.artist} · ${a.jahr}</p>
                    ${
                      a.gewinnerId
                        ? html`<p class="ss-gewinner">
                            🏆 ${name(fx, a.gewinnerId)} holt den Song auf Stufe
                            ${(a.gewinnerStufe ?? 0) + 1}!
                          </p>`
                        : html`<p class="ss-gewinner keiner">Niemand hat den Song erkannt …</p>`
                    }`
                : v.phase === "intro"
                  ? html`<h2 class="ss-lauschen-banner leise">Der Plattenspieler dreht auf …</h2>`
                  : v.phase === "raten"
                    ? html`<h2 class="ss-rater-banner">
                        🎧 ${name(fx, v.raterId)} rät!
                        ${v.fotofinish ? html`<span class="ss-fotofinish">Fotofinish-Los!</span>` : ""}
                      </h2>`
                    : html`<h2 class="ss-lauschen-banner">👂 ALLE LAUSCHEN</h2>
                        <p class="ss-snippet-info">
                          Stufe ${v.stufe + 1}/${v.stufenTotal} · ${snippetLabel(v.snippetMs)} ·
                          <b class="ss-wert">${formatMM(v.aktuellerWert)}</b>
                        </p>`
            }
          </div>
        </div>
        ${a ? "" : timerBalken(v.endsAt, v.timerMs, fx.serverNow())}
        <div class="ss-optionen">
          ${(a?.optionen ?? v.optionen ?? []).map(
            (opt, i) =>
              html`<div
                class="ss-option ${a ? (i === a.correctIndex ? "richtig" : "falsch") : ""}"
                style="--deko:${DEKO[i].farbe}"
                title=${opt}
              >
                <span class="ss-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                ${opt}
                ${
                  a && i === a.correctIndex && a.gewinnerId
                    ? html`<b class="ss-treffer">
                        +${formatMM(a.perPlayer.find((r) => r.correct)?.delta ?? 0)}
                      </b>`
                    : ""
                }
              </div>`,
          )}
        </div>
        ${
          v.gesperrt.length > 0 && !a
            ? html`<p class="ss-sperren">
                🚫 Gesperrt: ${v.gesperrt.map((p) => name(fx, p)).join(", ")}
              </p>`
            : ""
        }
      </div>`,
      host,
    );
  },

  renderPlayer(view: unknown, host: HTMLElement, send: SendAction, fx?: FxApi): void {
    const v = view as SongSnippetView;
    if (v.aufloesung) {
      render(html``, host); // Auflösung rendert die Player-App (kennt „you")
      return;
    }

    if (v.duGesperrt) {
      render(
        html`<div class="ss-verdeckt">
          <span style="font-size:5rem">🚫</span>
          <h2>Gesperrt!</h2>
          <p class="muted">Falscher Tipp — für DIESEN Song bist du raus.</p>
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "raten") {
      if (v.duBistRater && v.options) {
        render(
          html`<div class="ss-player">
            <div class="ss-player-kopf">
              🎤 DU bist dran! <b class="ss-wert">${formatMM(v.aktuellerWert)}</b> wenn's stimmt.
            </div>
            ${v.options.map(
              (opt, i) =>
                html`<button
                  class="ss-antwort-button"
                  style="--deko:${DEKO[i].farbe}"
                  @click=${() => send("answer", { choice: i })}
                >
                  <span class="ss-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                  ${opt}
                </button>`,
            )}
          </div>`,
          host,
        );
      } else {
        render(
          html`<div class="ss-verdeckt">
            <span style="font-size:5rem">🎧</span>
            <h2>${name(fx, v.raterId)} rät …</h2>
            <p class="muted">Falsch geraten? Dann geht die Jagd weiter.</p>
          </div>`,
          host,
        );
      }
      return;
    }

    // Intro + Lauschen: der Buzzer ist der Star (XXL, hochkant mittig).
    const bereit = v.phase === "lauschen" && v.buzzAktiv === true;
    render(
      html`<div class="ss-player buzzerseite">
        <div class="ss-player-kopf">
          Stufe ${v.stufe + 1}/${v.stufenTotal} ·
          <b class="ss-wert">${formatMM(v.aktuellerWert)}</b>
        </div>
        <button
          class="ss-buzzer ${bereit ? "" : "aus"}"
          ?disabled=${!bereit}
          @click=${() => {
            if (!bereit) return;
            void send("buzz", { pressedAtServerEst: fx?.serverNow() ?? 0 });
          }}
        >
          ${v.deinBuzz ? "DRIN!" : "BUZZ!"}
        </button>
        <p class="ss-buzzer-hinweis muted">
          ${
            v.deinBuzz
              ? "Buzz ist drin — Fotofinish läuft …"
              : v.phase === "intro"
                ? "🎧 Ohren auf — gleich läuft das Snippet!"
                : "Erkannt? Buzzern! Aber: falsch = Sperre + Strafe."
          }
        </p>
      </div>`,
      host,
    );
  },

  explainCard: {
    text: "0,1 Sekunden Song — wer buzzert, rät allein aus 4 Optionen! Keiner dran oder falsch? Längeres Snippet, weniger Money. Falsch-Buzz = Sperre + Strafe ins Glas.",
    animation: html`<span style="font-size:3rem">🎧⚡🎵💰</span>`,
  },
};

// Erklär-Demo: Mia buzzert nach 0,1 s und kassiert das Maximum — Bo hört
// beim langen Snippet zu, da ist der Wert schon verfallen.
export const demoChoreo: import("../demo-typen").DemoChoreo = {
  dauer: 10_000,
  beats: [
    {
      at: 0,
      requisiten: [
        { art: "buzzer", gedrueckt: null },
        { art: "schild", text: "0,1 s · 1.000 MM", ton: "gold", bei: "mitte" },
      ],
      pose: { a: "denk", b: "denk" },
      gesicht: { a: "denk", b: "denk" },
      blase: { wer: "a", text: "Das kenn ich!" },
    },
    {
      at: 2_500,
      requisiten: [
        { art: "buzzer", gedrueckt: "a" },
        { art: "schild", text: "Mia rät …", ton: "cyan", bei: "a" },
      ],
      pose: { a: "buzz", b: "denk" },
      gesicht: { a: "jubel", b: "denk" },
      sound: "buzzer",
    },
    {
      at: 5_000,
      requisiten: [{ art: "schild", text: "+1.000 MM", ton: "gold", bei: "a" }],
      pose: { a: "jubel", b: "frust" },
      gesicht: { a: "jubel", b: "frust" },
      blase: { wer: "b", text: "Nach 0,1 Sekunden?!" },
      geldflug: { von: "mitte", zu: "a" },
      effekt: "konfetti",
      sound: "richtig",
    },
    {
      at: 7_600,
      requisiten: [
        { art: "buzzer", gedrueckt: "b" },
        { art: "schild", text: "Falsch! −50 ins Glas", ton: "rot", bei: "b" },
      ],
      pose: { a: "idle", b: "fall" },
      gesicht: { a: "neutral", b: "frust" },
      blase: { wer: "b", text: "Zu voreilig …" },
      geldflug: { von: "b", zu: "mitte" },
      sound: "falsch",
    },
  ],
};

export default modul;

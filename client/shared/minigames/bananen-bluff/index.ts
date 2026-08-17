// Client-Renderer „Bananen-Bluff" (GAME-DESIGN §2.12/3): Screen = Verhör-Bühne
// in 3 Beats — VERKÜNDEN (Spot auf den Verkünder), RATEN (die Ansage XXL +
// Abstimmungs-Zähler), AUFDECKUNG (WAHRHEIT/BLUFF-Stempel + Geld-Ströme).
// Player = Verkünder wählt Wahrheit-oder-Bluff aus den 4 Optionen (Wahrheit
// markiert — nur ER sieht sie), alle anderen: 2 XXL-Urteils-Buttons.
import { html, render } from "lit-html";
import {
  BANANEN_BLUFF_ID,
  BB_RATE_OPTIONEN,
} from "../../../../shared/minigames/bananen-bluff.meta";
import { formatMM } from "../../../../shared/money";
import { timerBalken } from "../../ui";
import type { FxApi, MinigameClientModule, SendAction } from "../types";
import "./bananen-bluff.css";

const DEKO = [
  { buchstabe: "A", emoji: "🍌", farbe: "#e6b830" },
  { buchstabe: "B", emoji: "🥥", farbe: "#8a5a3b" },
  { buchstabe: "C", emoji: "🐒", farbe: "#d1495b" },
  { buchstabe: "D", emoji: "🌴", farbe: "#2e8b57" },
] as const;

interface BbBeat {
  questionId: string;
  verkuender: string;
  option: number;
  wahrheit: boolean;
  auto: boolean;
  reingefallen: string[];
  durchschaut: string[];
  glaeubige: string[];
  praemie: number;
  ehrlichkeitsPraemie: boolean;
}

interface BananenBluffView {
  questionId: string;
  frageNr: number;
  frageTotal: number;
  phase: "verkuenden" | "raten" | "aufdeckung";
  verkuender: string;
  text: string;
  endsAt: number;
  timerMs: number;
  praemie: number;
  ansageText: string | null;
  abgestimmt: number;
  raterZahl: number;
  spielerZahl: number;
  beat: BbBeat | null;
  historie: BbBeat[];
  deltas: Record<string, number>;
  finished: boolean;
  duBistVerkuender?: boolean;
  options?: string[] | null;
  correctIndex?: number | null;
  yourChoice?: number | null;
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

// Aufdeckungs-Stempel genau EINMAL pro Beat vertonen (Edge-Detection).
let letzterBeatKey = "";
function beatSound(v: BananenBluffView, fx: FxApi): void {
  if (v.phase !== "aufdeckung" || v.beat === null) return;
  const key = `${v.beat.questionId}:${v.frageNr}`;
  if (key === letzterBeatKey) return;
  letzterBeatKey = key;
  fx.sound(v.beat.wahrheit ? "applaus-kurz" : "reveal-zap");
}

const modul: MinigameClientModule = {
  id: BANANEN_BLUFF_ID,

  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void {
    const v = view as BananenBluffView;
    beatSound(v, fx);

    if (v.aufloesung) {
      render(
        html`<div class="bbf-screen">
          <h2 style="text-align:center">🕵️ Bananen-Bluff — die Bilanz!</h2>
          <p class="muted" style="text-align:center">${v.aufloesung.erklaerung}</p>
          <div class="bbf-bilanz">
            ${[...v.aufloesung.perPlayer]
              .sort((a, b) => b.delta - a.delta)
              .map(
                (r) =>
                  html`<div class="bbf-bilanz-zeile ${r.delta > 0 ? "gewonnen" : ""}">
                    <span>${r.delta > 0 ? "🕵️" : r.delta < 0 ? "🤡" : "😶"}</span>
                    <span>${name(fx, r.playerId)}</span>
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
      return;
    }

    const kopf = html`<div class="bbf-kopf">
      <span class="bbf-badge">🕵️ BANANEN-BLUFF</span>
      <span class="muted"
        >Frage ${v.frageNr} / ${v.frageTotal} — es geht um
        <strong class="mm-money-zahl">${formatMM(v.praemie)}</strong></span
      >
    </div>`;

    if (v.phase === "verkuenden") {
      render(
        html`<div class="bbf-screen">
          ${kopf}
          <h2 class="bbf-frage">${v.text}</h2>
          ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())}
          <div class="bbf-spot">
            <span class="bbf-spot-emoji">🎙️</span>
            <strong>${name(fx, v.verkuender).toUpperCase()}</strong>
            <span class="muted">überlegt: Wahrheit … oder Bluff?</span>
          </div>
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "raten") {
      render(
        html`<div class="bbf-screen">
          ${kopf}
          <h2 class="bbf-frage">${v.text}</h2>
          ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())}
          <div class="bbf-ansage">
            <span class="muted">${name(fx, v.verkuender)} verkündet:</span>
            <strong class="bbf-ansage-text">„${v.ansageText ?? "…"}"</strong>
            <span class="bbf-urteil-frage">WAHR … oder GELOGEN?</span>
          </div>
          <p class="muted" style="text-align:center">
            ${v.abgestimmt} / ${v.raterZahl} Urteile eingerastet …
          </p>
        </div>`,
        host,
      );
      return;
    }

    // AUFDECKUNG: der Show-Moment.
    const beat = v.beat;
    render(
      html`<div class="bbf-screen">
        ${kopf}
        ${
          beat
            ? html`<div class="bbf-aufdeckung ${beat.wahrheit ? "wahr" : "bluff"}">
                <span class="bbf-stempel">${beat.wahrheit ? "✅ WAHRHEIT" : "🔥 BLUFF!"}</span>
                <p>
                  ${name(fx, beat.verkuender)}
                  ${
                    beat.auto
                      ? "hat verschlafen — die Bank verkündete die Wahrheit."
                      : beat.wahrheit
                        ? "hat die Wahrheit gesagt."
                        : "hat GELOGEN!"
                  }
                  ${
                    beat.ehrlichkeitsPraemie
                      ? html`<span class="bbf-praemie"
                          >Ehrlichkeits-Prämie +${formatMM(beat.praemie)}!</span
                        >`
                      : ""
                  }
                </p>
                <div class="bbf-stroeme">
                  <div class="bbf-strom gut">
                    🕵️ Richtig (+${formatMM(beat.praemie)}):
                    ${namen(fx, beat.wahrheit ? beat.glaeubige : beat.durchschaut)}
                  </div>
                  ${
                    !beat.wahrheit
                      ? html`<div class="bbf-strom schlecht">
                          🤡 Reingefallen (−${formatMM(beat.praemie)} an
                          ${name(fx, beat.verkuender)}): ${namen(fx, beat.reingefallen)}
                        </div>`
                      : ""
                  }
                </div>
              </div>`
            : ""
        }
        ${timerBalken(v.endsAt, v.timerMs, fx.serverNow(), true)}
      </div>`,
      host,
    );
  },

  renderPlayer(view: unknown, host: HTMLElement, send: SendAction, fx?: FxApi): void {
    const v = view as BananenBluffView;
    if (v.aufloesung) {
      render(html``, host); // Auflösung rendert die Player-App (kennt „you")
      return;
    }

    // ---------- VERKÜNDER: Wahrheit oder Bluff wählen ----------
    if (v.duBistVerkuender === true) {
      if (v.phase === "verkuenden" && v.options) {
        render(
          html`<div class="bbf-player">
            <p class="bbf-frage-klein">${v.text}</p>
            <p class="bbf-hinweis">
              🎙️ DU bist der Verkünder! Sag die Wahrheit (Mehrheit glaubt dir =
              +${formatMM(v.praemie)}) — oder bluffe: jeder, der reinfällt, zahlt DIR
              ${formatMM(v.praemie)}!
            </p>
            ${v.options.map(
              (opt, i) =>
                html`<button
                  class="bbf-option ${i === v.correctIndex ? "wahrheit" : ""}"
                  style="--deko:${DEKO[i].farbe}"
                  @click=${() => {
                    fx?.sound("lockin-thunk");
                    void send("answer", { choice: i });
                  }}
                >
                  <span class="bbf-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                  ${opt}
                  ${i === v.correctIndex ? html`<span class="bbf-wahr-tag">✅ WAHRHEIT</span>` : ""}
                </button>`,
            )}
          </div>`,
          host,
        );
        return;
      }
      render(
        html`<div class="bbf-player">
          <div class="bbf-status">
            ${
              v.phase === "raten"
                ? html`🎙️ Deine Ansage steht: <strong>„${v.ansageText ?? "…"}"</strong><br />
                    <span class="muted"
                      >${v.abgestimmt} / ${v.raterZahl} Urteile … schau unschuldig!</span
                    >`
                : html`🎭 Die Aufdeckung läuft — gleich weiß es der ganze Dschungel.`
            }
          </div>
        </div>`,
        host,
      );
      return;
    }

    // ---------- RATER ----------
    if (v.phase === "verkuenden") {
      render(
        html`<div class="bbf-player">
          <p class="bbf-frage-klein">${v.text}</p>
          <div class="bbf-status">
            🎙️ ${name(fx, v.verkuender)} überlegt sich seine Ansage …<br />
            <span class="muted">Gleich urteilst du: WAHR oder GELOGEN?</span>
          </div>
        </div>`,
        host,
      );
      return;
    }
    if (v.phase === "raten") {
      const gewaehlt = v.yourChoice ?? null;
      render(
        html`<div class="bbf-player">
          <p class="bbf-frage-klein">${v.text}</p>
          <div class="bbf-ansage klein">
            <span class="muted">${name(fx, v.verkuender)} verkündet:</span>
            <strong class="bbf-ansage-text">„${v.ansageText ?? "…"}"</strong>
          </div>
          ${BB_RATE_OPTIONEN.map(
            (opt, i) =>
              html`<button
                class="bbf-urteil ${i === 0 ? "wahr" : "bluff"} ${gewaehlt === i ? "gewaehlt" : ""}"
                ?disabled=${gewaehlt !== null}
                @click=${() => {
                  fx?.sound("lockin-thunk");
                  void send("answer", { choice: i });
                }}
              >
                ${i === 0 ? "✅" : "🔥"} ${opt}
              </button>`,
          )}
          <p class="muted" style="text-align:center;margin:0">
            Richtig = +${formatMM(v.praemie)} · auf den Bluff reingefallen = −${formatMM(v.praemie)}
            an den Verkünder!
          </p>
        </div>`,
        host,
      );
      return;
    }
    render(
      html`<div class="bbf-player">
        <div class="bbf-status">🎭 Aufdeckung! Schau auf den großen Bildschirm …</div>
      </div>`,
      host,
    );
  },

  explainCard: {
    text: "Einer wird zum VERKÜNDER: nur er kennt die richtige Antwort — und verkündet Wahrheit oder Bluff! Alle anderen urteilen: WAHR oder GELOGEN? Wer dem Bluff glaubt, zahlt an den Lügner.",
    animation: html`<span style="font-size:3rem">🎙️🤥🕵️💸</span>`,
  },
};

// Erklär-Demo (ADDITIV): Verkünderin Mia blufft — Bo glaubt ihr und zahlt.
export const demoChoreo: import("../demo-typen").DemoChoreo = {
  dauer: 10800,
  beats: [
    {
      at: 0,
      requisiten: [
        { art: "frage", tippA: 2 },
        { art: "schild", text: "🎙 Verkünderin", ton: "cyan", bei: "a" },
      ],
      pose: { a: "zeig", b: "idle" },
      gesicht: { a: "jubel", b: "neutral" },
      blase: { wer: "a", text: "Die Antwort ist … C!" },
    },
    {
      at: 2600,
      requisiten: [
        { art: "frage", tippA: 2 },
        { art: "schild", text: "WAHR ✅ oder GELOGEN ❌?", ton: "papier" },
      ],
      pose: { a: "idle", b: "denk" },
      gesicht: { a: "neutral", b: "denk" },
      blase: { wer: "b", text: "Hmm … sagt sie die Wahrheit?" },
    },
    {
      at: 5200,
      requisiten: [
        { art: "frage", tippA: 2 },
        { art: "schild", text: "Bo: WAHR ✅", ton: "gruen", bei: "b" },
      ],
      pose: { a: "idle", b: "tipp" },
      sound: "lockin-thunk",
    },
    {
      at: 7400,
      requisiten: [
        { art: "frage", tippA: 2, richtig: 0 },
        { art: "schild", text: "zahlt an die Lügnerin", ton: "rot", bei: "b" },
      ],
      pose: { a: "jubel", b: "frust" },
      gesicht: { a: "jubel", b: "frust" },
      blase: { wer: "a", text: "GELOGEN! 🤥" },
      geldflug: { von: "b", zu: "a" },
      sound: "falsch",
    },
  ],
};

export default modul;

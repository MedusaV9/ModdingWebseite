// Client-Renderer „Affen-Auktion" (GAME-DESIGN §2.12/5): Screen = Auktions-
// Podium mit Hammer, Höchstgebot XXL + Höchstbietendem, Bieter-Ticker und
// Teaser (Kategorie + Schwierigkeit — geboten wird BLIND). Danach beantwortet
// NUR der Gewinner die Frage. Player = BIETER-BUTTONS: der große Hammer
// (+25) plus Schnell-Erhöhungen (+100/+250 übers einsatz-Kommando); im
// Frage-Fenster 4 XXL-Antwort-Buttons (exklusiv) bzw. Mitraten-Ansicht.
import { html, render } from "lit-html";
import { kategorieLabel } from "../../../../shared/kategorien";
import { AA_SCHRITT, AFFEN_AUKTION_ID } from "../../../../shared/minigames/affen-auktion.meta";
import { formatMM } from "../../../../shared/money";
import { timerBalken } from "../../ui";
import type { FxApi, MinigameClientModule, SendAction } from "../types";
import "./affen-auktion.css";

const DEKO = [
  { buchstabe: "A", emoji: "🍌", farbe: "#e6b830" },
  { buchstabe: "B", emoji: "🥥", farbe: "#8a5a3b" },
  { buchstabe: "C", emoji: "🐒", farbe: "#d1495b" },
  { buchstabe: "D", emoji: "🌴", farbe: "#2e8b57" },
] as const;

const SCHWIERIGKEIT_LABEL: Record<string, string> = {
  easy: "LEICHT",
  medium: "MITTEL",
  hard: "SCHWER",
  ultrahard: "ULTRAHARD",
};

interface AaGebot {
  playerId: string;
  betrag: number;
  atMs: number;
}

interface AffenAuktionView {
  questionId: string;
  phase: "setzen" | "frage";
  kategorie: string;
  schwierigkeit: string;
  endsAt: number;
  timerMs: number;
  hoechstgebot: number;
  hoechstbietender: string | null;
  gebotHistorie: AaGebot[];
  schritt: number;
  text: string | null;
  answeredCount: number;
  spielerZahl: number;
  finished: boolean;
  options?: string[] | null;
  zuschauerOptionen?: string[] | null;
  einsatzMax?: number;
  yourEinsatz?: { betrag: number } | null;
  duBistGewinner?: boolean;
  yourChoice?: number | null;
  gesperrt?: number[];
  zweitversuch?: boolean;
  aufloesung: {
    correctIndex: number | null;
    erklaerung: string;
    perPlayer: {
      playerId: string;
      choice: number | null;
      correct: boolean;
      delta: number;
      gebot: number | null;
      erstattet: boolean;
    }[];
  } | null;
}

function name(fx: FxApi | undefined, playerId: string | null): string {
  if (playerId === null) return "—";
  return fx?.spieler?.(playerId)?.name ?? playerId;
}

// Jedes NEUE Gebot bekommt seinen Hammer-Tick (Edge-Detection über Historie).
let letztesGebotKey = "";
function gebotSound(v: AffenAuktionView, fx: FxApi): void {
  const letztes = v.gebotHistorie.at(-1);
  if (!letztes) return;
  const key = `${v.questionId}:${letztes.playerId}:${letztes.betrag}`;
  if (key === letztesGebotKey) return;
  letztesGebotKey = key;
  fx.sound("rad-tick");
}

const modul: MinigameClientModule = {
  id: AFFEN_AUKTION_ID,

  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void {
    const v = view as AffenAuktionView;
    gebotSound(v, fx);

    const teaser = html`<div class="auk-teaser">
      <span class="muted">Versteigert wird:</span>
      <strong>${kategorieLabel(v.kategorie)}</strong>
      <span class="auk-schwierigkeit"
        >${SCHWIERIGKEIT_LABEL[v.schwierigkeit] ?? v.schwierigkeit}</span
      >
    </div>`;

    if (v.aufloesung) {
      const a = v.aufloesung;
      render(
        html`<div class="auk-screen">
          <h2 style="text-align:center">🔨 Zuschlag — die Abrechnung!</h2>
          <p class="muted" style="text-align:center">${a.erklaerung}</p>
          <div class="auk-bilanz">
            ${[...a.perPlayer]
              .sort((x, y) => y.delta - x.delta)
              .map(
                (r) =>
                  html`<div class="auk-bilanz-zeile ${r.correct ? "gewonnen" : ""}">
                    <span>${r.gebot !== null ? "🔨" : "👀"}</span>
                    <span>${name(fx, r.playerId)}</span>
                    <span class="muted">
                      ${
                        r.gebot !== null
                          ? r.erstattet
                            ? `Gebot ${formatMM(r.gebot)} erstattet`
                            : `Gebot ${formatMM(r.gebot)} — ${r.correct ? "richtig!" : "daneben"}`
                          : "mitgeboten/zugeschaut"
                      }
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
      return;
    }

    if (v.phase === "setzen") {
      render(
        html`<div class="auk-screen">
          <div class="auk-kopf"><span class="auk-badge">🔨 AFFEN-AUKTION</span></div>
          ${teaser} ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())}
          <div class="auk-podium">
            <span class="auk-hammer">🔨</span>
            <span class="auk-gebot-zahl mm-money-zahl">${formatMM(v.hoechstgebot)}</span>
            <span class="auk-gebot-halter">
              ${
                v.hoechstbietender !== null
                  ? html`führt: <strong>${name(fx, v.hoechstbietender).toUpperCase()}</strong>`
                  : "Wer eröffnet die Auktion?"
              }
            </span>
          </div>
          <div class="auk-ticker">
            ${[...v.gebotHistorie]
              .reverse()
              .map(
                (g, i) =>
                  html`<span class="auk-tick ${i === 0 ? "neu" : ""}">
                    ${name(fx, g.playerId)}: ${formatMM(g.betrag)}
                  </span>`,
              )}
          </div>
          <p class="muted" style="text-align:center">
            Der Gewinner antwortet EXKLUSIV: richtig = Gebot ×2 zurück — falsch = das Gebot geht an
            alle anderen! Gebote in den letzten 5 s verlängern den Hammer.
          </p>
        </div>`,
        host,
      );
      return;
    }

    // FRAGE: nur der Gewinner darf ran.
    render(
      html`<div class="auk-screen">
        <div class="auk-kopf">
          <span class="auk-badge">🔨 ZUSCHLAG</span>
          <span class="muted">
            <strong>${name(fx, v.hoechstbietender)}</strong> antwortet für
            <strong class="mm-money-zahl">${formatMM(v.hoechstgebot)}</strong>
          </span>
        </div>
        <h2 class="auk-frage">${v.text ?? ""}</h2>
        ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())}
        <div class="auk-optionen">
          ${(v.options ?? []).map(
            (opt, i) =>
              html`<div
                class="auk-option ${v.gesperrt?.includes(i) === true ? "entfernt" : ""}"
                style="--deko:${DEKO[i].farbe}"
              >
                <span class="auk-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                ${opt}
              </div>`,
          )}
        </div>
      </div>`,
      host,
    );
  },

  renderPlayer(view: unknown, host: HTMLElement, send: SendAction, fx?: FxApi): void {
    const v = view as AffenAuktionView;
    if (v.aufloesung) {
      render(html``, host); // Auflösung rendert die Player-App (kennt „you")
      return;
    }

    // ---------- AUKTION: die Bieter-Buttons ----------
    if (v.phase === "setzen") {
      const limit = v.einsatzMax ?? 0;
      const fuehrst = v.yourEinsatz !== null && v.yourEinsatz !== undefined;
      const naechstes = v.hoechstgebot + AA_SCHRITT;
      const kannBieten = !fuehrst && naechstes <= limit;
      render(
        html`<div class="auk-player">
          <div class="auk-teaser">
            <span class="muted">Versteigert wird:</span>
            <strong>${kategorieLabel(v.kategorie)}</strong>
            <span class="auk-schwierigkeit"
              >${SCHWIERIGKEIT_LABEL[v.schwierigkeit] ?? v.schwierigkeit}</span
            >
          </div>
          <div class="auk-stand">
            Höchstgebot:
            <strong class="mm-money-zahl">${formatMM(v.hoechstgebot)}</strong>
            <span class="muted">(${name(fx, v.hoechstbietender)})</span>
          </div>
          ${
            fuehrst
              ? html`<div class="auk-status">
                  🔨 DU führst mit
                  <strong class="mm-money-zahl">${formatMM(v.hoechstgebot)}</strong>!<br />
                  <span class="muted"
                    >Richtig = +${formatMM(v.hoechstgebot)} · falsch = das Gebot geht an die anderen
                    …</span
                  >
                </div>`
              : html`<button
                    class="auk-bieten"
                    ?disabled=${!kannBieten}
                    @click=${() => {
                      fx?.sound("lockin-thunk");
                      void send("bieten", {});
                    }}
                  >
                    🔨 BIETEN ${formatMM(naechstes)}
                  </button>
                  <div class="auk-schnell">
                    ${[100, 250].map((plus) => {
                      const ziel = v.hoechstgebot + plus;
                      return html`<button
                        class="auk-schnell-button"
                        ?disabled=${fuehrst || ziel > limit}
                        @click=${() => {
                          fx?.sound("lockin-thunk");
                          void send("einsatz", { betrag: ziel });
                        }}
                      >
                        +${plus}
                      </button>`;
                    })}
                  </div>
                  <p class="muted" style="text-align:center;margin:0">
                    Dein Limit: ${formatMM(limit)}${kannBieten ? "" : " — Limit erreicht!"}
                  </p>`
          }
        </div>`,
        host,
      );
      return;
    }

    // ---------- FRAGE: exklusiv für den Gewinner ----------
    if (v.duBistGewinner === true) {
      const gewaehlt = v.yourChoice ?? null;
      render(
        html`<div class="auk-player">
          <p class="auk-frage-klein">
            ${v.text ?? ""}
            <br /><span class="muted"
              >Dein Gebot: ${formatMM(v.hoechstgebot)} — richtig = ×2 zurück!</span
            >
          </p>
          ${
            v.zweitversuch === true
              ? html`<p class="auk-zweitversuch">🔁 Rückgaberecht aktiv — Gewinn 50 %</p>`
              : ""
          }
          ${(v.options ?? []).map((opt, i) => {
            const entfernt = v.gesperrt?.includes(i) === true;
            return html`<button
              class="auk-button ${gewaehlt === i ? "gewaehlt" : ""} ${
                gewaehlt !== null ? "gesperrt" : ""
              } ${entfernt ? "entfernt" : ""}"
              style="--deko:${DEKO[i].farbe}"
              ?disabled=${gewaehlt !== null || entfernt}
              @click=${() => {
                fx?.sound("lockin-thunk");
                void send("answer", { choice: i });
              }}
            >
              <span class="auk-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
              ${opt}
            </button>`;
          })}
        </div>`,
        host,
      );
      return;
    }
    render(
      html`<div class="auk-player">
        <div class="auk-status">
          🔨 <strong>${name(fx, v.hoechstbietender)}</strong> hat den Zuschlag für
          <strong class="mm-money-zahl">${formatMM(v.hoechstgebot)}</strong>!<br />
          <span class="muted">Antwortet er falsch, bekommst DU einen Anteil …</span>
        </div>
        <p class="auk-frage-klein">${v.text ?? ""}</p>
        <div class="auk-mitraten">
          ${(v.zuschauerOptionen ?? []).map(
            (opt, i) =>
              html`<div class="auk-option klein" style="--deko:${DEKO[i].farbe}">
                <span class="auk-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                ${opt}
              </div>`,
          )}
        </div>
      </div>`,
      host,
    );
  },

  explainCard: {
    text: "Die Frage kommt unter den Hammer — geboten wird BLIND, nur Kategorie + Schwierigkeit sind bekannt! Der Höchstbietende antwortet exklusiv: richtig = Gebot ×2 zurück, falsch = sein Gebot geht an alle anderen.",
    animation: html`<span style="font-size:3rem">🔨💰🐒❓</span>`,
  },
};

// Erklär-Demo (ADDITIV): blind bieten, Zuschlag, exklusiv antworten —
// richtig gibt das Gebot ×2 zurück.
export const demoChoreo: import("../demo-typen").DemoChoreo = {
  dauer: 11400,
  beats: [
    {
      at: 0,
      requisiten: [
        { art: "frage", verdeckt: true },
        { art: "schild", text: "🔨 Wer bietet BLIND?", ton: "gold" },
      ],
      pose: { a: "denk", b: "denk" },
      gesicht: { a: "denk", b: "denk" },
    },
    {
      at: 2400,
      requisiten: [
        { art: "frage", verdeckt: true },
        { art: "schild", text: "Mia: 200 MM", ton: "gold", bei: "a" },
      ],
      pose: { a: "zeig", b: "denk" },
      gesicht: { a: "neutral", b: "denk" },
      sound: "money-klein",
    },
    {
      at: 4400,
      requisiten: [
        { art: "frage", verdeckt: true },
        { art: "schild", text: "Mia: 200 MM", ton: "gold", bei: "a" },
        { art: "schild", text: "Bo: 300 MM!", ton: "gold", bei: "b" },
      ],
      pose: { a: "idle", b: "zeig" },
      blase: { wer: "b", text: "Bo überbietet!" },
      sound: "money-klein",
    },
    {
      at: 6400,
      requisiten: [
        { art: "frage", tippB: 3 },
        { art: "schild", text: "ZUSCHLAG 🔨", ton: "rot", bei: "b" },
      ],
      pose: { a: "denk", b: "tipp" },
      gesicht: { a: "denk", b: "neutral" },
      blase: { wer: "b", text: "Bo antwortet EXKLUSIV" },
      sound: "kokosnuss-knack",
    },
    {
      at: 8600,
      requisiten: [
        { art: "frage", tippB: 3, richtig: 3 },
        { art: "schild", text: "Gebot ×2 zurück!", ton: "gold", bei: "b" },
      ],
      pose: { a: "idle", b: "jubel" },
      gesicht: { a: "neutral", b: "jubel" },
      geldflug: { von: "mitte", zu: "b" },
      effekt: "konfetti",
      sound: "richtig",
    },
  ],
};

export default modul;

// Client-Renderer „Die Affenbank" (GAME-DESIGN §2.8): Screen = Tresor in der
// Mitte füllt sich mit der Kette (50 → … → 1.600), Schnellfeuer-Frage darunter,
// jeder BANK! wird mit Namens-Einblendung genüsslich geoutet („TOM SICHERT
// SICH 400!"). Player = fetter roter BANK!-Button mit Live-Pottstand über den
// 4 Antwort-Buttons. Sounds: gebankt = Chips, verbrannt = Fehlton (Edge-Detect).
import { html, render } from "lit-html";
import { AFFENBANK_ID, type AbHistorieEintrag } from "../../../../shared/minigames/affenbank.meta";
import { formatMM } from "../../../../shared/money";
import { timerBalken } from "../../ui";
import type { FxApi, MinigameClientModule, SendAction } from "../types";
import "./affenbank.css";

const DEKO = [
  { buchstabe: "A", emoji: "🍌", farbe: "#e6b830" },
  { buchstabe: "B", emoji: "🥥", farbe: "#8a5a3b" },
  { buchstabe: "C", emoji: "🐒", farbe: "#d1495b" },
  { buchstabe: "D", emoji: "🌴", farbe: "#2e8b57" },
] as const;

interface AffenbankView {
  questionId: string;
  frageNonce: number;
  phase: "kette" | "pause";
  durchgang: number;
  durchgaengeTotal: number;
  pott: number;
  stufe: number;
  kette: readonly number[];
  ketteEndetAt: number;
  ketteMs: number;
  endsAt: number;
  timerMs: number;
  text: string | null;
  options: string[] | null;
  answeredCount: number;
  spielerZahl: number;
  gebankt: Record<string, number>;
  bankFenster: { betrag: number; drueckerIds: string[] } | null;
  historie: AbHistorieEintrag[];
  finished: boolean;
  you?: string | null;
  yourChoice?: number | null;
  yourGebankt?: number;
  aufloesung: {
    erklaerung: string;
    perPlayer: { playerId: string; choice: null; correct: boolean; delta: number }[];
  } | null;
}

function spielerName(fx: FxApi | undefined, playerId: string | undefined): string {
  if (playerId === undefined) return "?";
  return fx?.spieler?.(playerId)?.name ?? playerId;
}

function historieText(e: AbHistorieEintrag, fx?: FxApi): string {
  switch (e.typ) {
    case "verdoppelt":
      return `📈 Mehrheit richtig — Kette bei ${formatMM(e.betrag)}!`;
    case "verbrannt":
      return "🔥 Falsche Mehrheit — der Pott verbrennt!";
    case "gebankt":
      return `💰 ${spielerName(fx, e.playerId).toUpperCase()} SICHERT SICH ${formatMM(e.betrag)}!`;
    case "durchgang-start":
      return `🔁 Durchgang ${e.durchgang}: die Kette startet leer.`;
  }
}

// Sound-Edges: nur NEUE Historie-Beats vertonen (Renderer wird oft aufgerufen).
let letzterBeat = 0;
function spieleBeatSounds(v: AffenbankView, fx: FxApi): void {
  const beats = v.historie.length > 0 ? v.historie.at(-1) : undefined;
  const key = v.historie.length + v.durchgang * 1000;
  if (key === letzterBeat || beats === undefined) return;
  letzterBeat = key;
  if (beats.typ === "gebankt") fx.sound("money-gross");
  else if (beats.typ === "verbrannt") fx.sound("falsch");
  else if (beats.typ === "verdoppelt") fx.sound("money-klein");
}

/** Tresor + Ketten-Leiter (beide Rollen): welcher Betrag glüht gerade? */
function tresor(v: AffenbankView): unknown {
  return html`<div class="ab-tresor ${v.pott > 0 ? "gefuellt" : ""}">
    <div class="ab-tresor-tuer">🏦</div>
    <div class="ab-pott mm-money-zahl">${formatMM(v.pott)}</div>
    <div class="ab-kette">
      ${v.kette.map(
        (wert, i) =>
          html`<span
            class="ab-stufe ${i < v.stufe ? "erreicht" : ""} ${i === v.stufe - 1 ? "aktiv" : ""}"
          >
            ${wert >= 1000 ? `${wert / 1000}k` : wert}
          </span>`,
      )}
    </div>
  </div>`;
}

const modul: MinigameClientModule = {
  id: AFFENBANK_ID,

  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void {
    const v = view as AffenbankView;
    spieleBeatSounds(v, fx);

    if (v.aufloesung) {
      render(
        html`<div class="ab-screen">
          <h2 style="text-align:center">🏦 Die Affenbank schließt!</h2>
          <p class="muted" style="text-align:center">${v.aufloesung.erklaerung}</p>
          <div class="ab-bilanz">
            ${[...v.aufloesung.perPlayer]
              .sort((a, b) => b.delta - a.delta)
              .map((r) => {
                const info = fx.spieler?.(r.playerId) ?? null;
                return html`<div class="ab-bilanz-zeile ${r.delta > 0 ? "hat-gebankt" : ""}">
                  <span>${r.delta > 0 ? "💰" : "🙈"}</span>
                  <span>${info?.name ?? r.playerId}</span>
                  <strong class="mm-money-zahl"
                    >${r.delta > 0 ? "+" : ""}${formatMM(r.delta)}</strong
                  >
                </div>`;
              })}
          </div>
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "pause") {
      render(
        html`<div class="ab-screen">
          <h2 style="text-align:center">🍹 Tresen-Beat!</h2>
          ${tresor(v)}
          <p class="muted" style="text-align:center">
            Gleich startet Durchgang ${v.durchgang + 1} / ${v.durchgaengeTotal} — Kette wieder leer.
          </p>
          ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())}
        </div>`,
        host,
      );
      return;
    }

    render(
      html`<div class="ab-screen">
        <p class="ab-kopf">
          Durchgang ${v.durchgang} / ${v.durchgaengeTotal} · Kette:
          ${timerRest(v.ketteEndetAt, fx.serverNow())} s
        </p>
        ${tresor(v)}
        ${
          v.bankFenster !== null
            ? html`<div class="ab-outing">
                💰
                ${v.bankFenster.drueckerIds
                  .map((p) => spielerName(fx, p).toUpperCase())
                  .join(" + ")}
                SICHERT SICH ${formatMM(v.bankFenster.betrag)}!
              </div>`
            : ""
        }
        <h2 class="ab-frage">${v.text ?? ""}</h2>
        ${timerBalken(v.endsAt, v.timerMs, fx.serverNow(), true)}
        <div class="ab-optionen">
          ${(v.options ?? []).map(
            (opt, i) =>
              html`<div class="ab-option" style="--deko:${DEKO[i].farbe}">
                <span class="ab-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                ${opt}
              </div>`,
          )}
        </div>
        <div class="ab-ticker">
          ${v.historie
            .slice(-3)
            .reverse()
            .map((e) => html`<span class="ab-ticker-eintrag">${historieText(e, fx)}</span>`)}
        </div>
      </div>`,
      host,
    );
  },

  renderPlayer(view: unknown, host: HTMLElement, send: SendAction, fx?: FxApi): void {
    const v = view as AffenbankView;
    if (v.aufloesung) {
      render(html``, host); // Auflösung rendert die Player-App (kennt „you")
      return;
    }

    if (v.phase === "pause") {
      render(
        html`<div class="ab-player">
          <div class="ab-status">
            🍹 Kurzer Tresen-Beat …
            <br />
            <span class="muted">
              Du hast bisher <strong class="mm-money-zahl">${formatMM(v.yourGebankt ?? 0)}</strong>
              gesichert.
            </span>
          </div>
        </div>`,
        host,
      );
      return;
    }

    const gewaehlt = v.yourChoice ?? null;
    render(
      html`<div class="ab-player">
        <button
          class="ab-bank-button ${v.pott > 0 ? "scharf" : ""}"
          ?disabled=${v.pott <= 0}
          @click=${() => {
            fx?.sound("money-gross");
            void send("bank", {});
          }}
        >
          <span class="ab-bank-label">BANK!</span>
          <span class="ab-bank-pott mm-money-zahl">${formatMM(v.pott)}</span>
        </button>
        <p class="ab-gesichert muted">
          💰 gesichert: ${formatMM(v.yourGebankt ?? 0)} · Frage ${v.answeredCount} /
          ${v.spielerZahl} beantwortet
        </p>
        ${(v.options ?? []).map(
          (opt, i) =>
            html`<button
              class="ab-button ${gewaehlt === i ? "gewaehlt" : ""} ${gewaehlt !== null ? "gesperrt" : ""}"
              style="--deko:${DEKO[i].farbe}"
              ?disabled=${gewaehlt !== null}
              @click=${() => send("answer", { choice: i })}
            >
              <span class="ab-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
              ${opt}
            </button>`,
        )}
      </div>`,
      host,
    );
  },

  explainCard: {
    text: "Schnellfeuer-Fragen im 10-s-Takt: antwortet die MEHRHEIT richtig, wächst der Pott (50 → 1.600). Wer BANK! drückt, sichert sich alles — und die Kette reißt für alle!",
    animation: html`<span style="font-size:3rem">🏦💰🔗💥</span>`,
  },
};

function timerRest(endetAt: number, now: number): number {
  return Math.max(0, Math.round((endetAt - now) / 1000));
}

// Erklär-Demo (ADDITIV): die Pott-Kette wächst mit jeder Mehrheits-Antwort —
// bis Bo BANK! drückt, kassiert und die Kette für alle reißt.
export const demoChoreo: import("../demo-typen").DemoChoreo = {
  dauer: 11400,
  beats: [
    {
      at: 0,
      requisiten: [
        { art: "schild", text: "⏱ Schnellfeuer im 10-s-Takt", ton: "cyan" },
        { art: "kette", glieder: ["50"] },
      ],
      pose: { a: "denk", b: "denk" },
      gesicht: { a: "denk", b: "denk" },
    },
    {
      at: 2200,
      requisiten: [{ art: "kette", glieder: ["50", "100"] }],
      pose: { a: "tipp", b: "tipp" },
      blase: { wer: "a", text: "Mehrheit richtig → Pott wächst!" },
      sound: "richtig",
    },
    {
      at: 4400,
      requisiten: [{ art: "kette", glieder: ["50", "100", "200"] }],
      pose: { a: "tipp", b: "denk" },
      gesicht: { a: "neutral", b: "denk" },
      blase: { wer: "b", text: "Bo schielt auf den Pott …" },
    },
    {
      at: 6600,
      requisiten: [{ art: "kette", glieder: ["50", "100", "200"], bankVon: "b" }],
      pose: { a: "denk", b: "buzz" },
      gesicht: { a: "neutral", b: "jubel" },
      blase: { wer: "b", text: "BANK! Bo kassiert!" },
      geldflug: { von: "mitte", zu: "b" },
      sound: "jackpot-einzahlung",
    },
    {
      at: 8800,
      requisiten: [
        { art: "kette", glieder: ["50", "100", "200"], gerissen: true },
        { art: "schild", text: "+350 MM", ton: "gold", bei: "b" },
      ],
      pose: { a: "frust", b: "jubel" },
      gesicht: { a: "frust", b: "jubel" },
      blase: { wer: "a", text: "Die Kette reißt für ALLE!" },
      sound: "podium-riss",
    },
  ],
};

export default modul;

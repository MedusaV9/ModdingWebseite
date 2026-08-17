// Client-Renderer „Affenleiter": Player = vertikale Karten-Liste (Sprosse 0 unten),
// Touch-Drag UND Maus-Fallback UND Tap-Tap-Tausch (zittrige Finger, §2.4), dann
// EINLOGGEN; Screen = Palmen-Leiter, Auflösung Sprosse für Sprosse von unten.
// Sound-Mapping (ART-PLAN §4.1): Handy-Tap (click_001) je Tausch, Lock-in-Thunk
// beim Einloggen, RICHTIG-Stinger je aufgedeckter Sprosse — wartet auf FxApi.
import { html, render } from "lit-html";
import { AFFENLEITER_ID } from "../../../../shared/minigames/affenleiter.meta";
import { formatMM } from "../../../../shared/money";
import type { FxApi, MinigameClientModule, SendAction } from "../types";
import { timerBanane } from "../kokosnuss-uhr/timer-banane";
import "./affenleiter.css";

interface LeiterView {
  questionId: string;
  text: string;
  elemente: string[];
  endsAt: number;
  timerMs: number;
  answeredCount: number;
  eingeloggte: string[];
  finished: boolean;
  yourStart?: number[];
  yourStand?: number[];
  yourEingeloggt?: boolean;
  aufloesung: {
    korrektReihenfolge: number[];
    aufloesungWerte: string[];
    erklaerung: string;
    perPlayer: {
      playerId: string;
      reihenfolge: number[];
      richtigPositionen: boolean[];
      korrektAnzahl: number;
      perfekt: boolean;
      correct: boolean;
      delta: number;
    }[];
  } | null;
}

/** Lokaler Sortier-Zustand pro Frage (überlebt die 150-ms-Re-Renders der App). */
interface LokalState {
  order: number[];
  gewaehlt: number | null; // Tap-Tap-Tausch: erste gewählte Sprosse
  dragSprosse: number | null;
  dragStartY: number;
  dragBewegt: boolean;
}

const lokal = new Map<string, LokalState>();

function lokalFuer(v: LeiterView): LokalState {
  let s = lokal.get(v.questionId);
  if (!s) {
    s = {
      order: [...(v.yourStand ?? v.yourStart ?? [0, 1, 2, 3])],
      gewaehlt: null,
      dragSprosse: null,
      dragStartY: 0,
      dragBewegt: false,
    };
    lokal.set(v.questionId, s);
    if (lokal.size > 8) {
      for (const key of lokal.keys()) {
        if (key !== v.questionId) lokal.delete(key);
      }
    }
  }
  return s;
}

const modul: MinigameClientModule = {
  id: AFFENLEITER_ID,

  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void {
    const v = view as LeiterView;
    if (v.aufloesung) {
      const a = v.aufloesung;
      const perfekte = a.perPlayer.filter((r) => r.perfekt);
      render(
        html`<div class="al-screen">
          <h2 class="al-frage">${v.text}</h2>
          <div class="al-leiter aufdecken">
            ${a.korrektReihenfolge.map((elementIdx, sprosse) => {
              const richtige = a.perPlayer.filter((r) => r.richtigPositionen[sprosse]).length;
              return html`<div
                class="al-sprosse enthuellt"
                style="order:${-sprosse};animation-delay:${(sprosse * 1.2).toFixed(1)}s"
              >
                <span class="al-sprosse-nr">${sprosse + 1}.</span>
                <span class="al-sprosse-text">${v.elemente[elementIdx]}</span>
                <span class="al-sprosse-wert mm-money-zahl">${a.aufloesungWerte[elementIdx]}</span>
                <span class="al-sprosse-affen" title="${richtige} richtig">
                  ${"🐵".repeat(richtige)}
                </span>
              </div>`;
            })}
          </div>
          ${
            perfekte.length > 0
              ? html`<p class="al-perfekt">
                  🏆 Perfekte Leiter: ${perfekte.map((r) => `+${formatMM(r.delta)}`).join(" · ")}
                </p>`
              : ""
          }
          <p class="muted" style="text-align:center">${a.erklaerung}</p>
        </div>`,
        host,
      );
      return;
    }

    render(
      html`<div class="al-screen">
        ${timerBanane(v.endsAt, v.timerMs, fx.serverNow())}
        <h2 class="al-frage">${v.text}</h2>
        <div class="al-leiter">
          ${[3, 2, 1, 0].map(
            (sprosse) =>
              html`<div class="al-sprosse geheim">
                <span class="al-sprosse-nr">${sprosse + 1}.</span>
                <span class="al-sprosse-text">❓</span>
              </div>`,
          )}
        </div>
        <p class="muted" style="text-align:center">
          🐒 Auf den Handys wird sortiert … ${v.answeredCount} eingeloggt
          ${v.eingeloggte.map(() => "🔒").join(" ")}
        </p>
      </div>`,
      host,
    );
  },

  renderPlayer(view: unknown, host: HTMLElement, send: SendAction): void {
    const v = view as LeiterView;
    const s = lokalFuer(v);
    const eingeloggt = v.yourEingeloggt ?? false;

    const sende = (type: "sortierung" | "einloggen"): void => {
      void send(type, { reihenfolge: [...s.order] });
    };
    const tausche = (a: number, b: number): void => {
      [s.order[a], s.order[b]] = [s.order[b], s.order[a]];
      zeichne();
    };

    // --- Drag (Touch + Maus): Karte über die halbe Kartenhöhe ziehen = Tausch ---
    const dragStart = (sprosse: number, clientY: number): void => {
      if (eingeloggt) return;
      s.dragSprosse = sprosse;
      s.dragStartY = clientY;
      s.dragBewegt = false;
      zeichne();
    };
    const dragMove = (clientY: number, kartenHoehe: number): void => {
      if (s.dragSprosse === null) return;
      const delta = clientY - s.dragStartY;
      const schwelle = Math.max(30, kartenHoehe * 0.6);
      // Liste ist column-reverse: nach OBEN ziehen (delta < 0) = höhere Sprosse.
      if (delta < -schwelle && s.dragSprosse < 3) {
        tausche(s.dragSprosse, s.dragSprosse + 1);
        s.dragSprosse += 1;
        s.dragStartY = clientY;
        s.dragBewegt = true;
      } else if (delta > schwelle && s.dragSprosse > 0) {
        tausche(s.dragSprosse, s.dragSprosse - 1);
        s.dragSprosse -= 1;
        s.dragStartY = clientY;
        s.dragBewegt = true;
      }
    };
    const dragEnd = (): void => {
      if (s.dragSprosse === null) return;
      const bewegt = s.dragBewegt;
      s.dragSprosse = null;
      if (bewegt) sende("sortierung"); // Zwischenstand zählt (letzter Stand, §2.4)
      zeichne();
    };
    const onMouseDown = (sprosse: number) => (e: MouseEvent) => {
      const hoehe = (e.currentTarget as HTMLElement).offsetHeight;
      dragStart(sprosse, e.clientY);
      const onMove = (m: MouseEvent): void => dragMove(m.clientY, hoehe);
      const onUp = (): void => {
        document.removeEventListener("mousemove", onMove);
        document.removeEventListener("mouseup", onUp);
        dragEnd();
      };
      document.addEventListener("mousemove", onMove);
      document.addEventListener("mouseup", onUp);
    };

    // --- Tap-Tap-Tausch (zittrige-Finger-Fallback): 2 Karten antippen ---
    const onTap = (sprosse: number) => (): void => {
      if (eingeloggt || s.dragBewegt) {
        s.dragBewegt = false;
        return;
      }
      if (s.gewaehlt === null) {
        s.gewaehlt = sprosse;
      } else if (s.gewaehlt === sprosse) {
        s.gewaehlt = null;
      } else {
        tausche(s.gewaehlt, sprosse);
        s.gewaehlt = null;
        sende("sortierung");
      }
      zeichne();
    };

    function zeichne(): void {
      render(
        html`<div class="al-player">
          <p class="al-frage-klein">${v.text}</p>
          <div class="al-karten">
            ${s.order.map(
              (elementIdx, sprosse) =>
                html`<button
                  class="al-karte ${s.gewaehlt === sprosse ? "gewaehlt" : ""}
                    ${s.dragSprosse === sprosse ? "dragging" : ""} ${eingeloggt ? "gesperrt" : ""}"
                  style="order:${-sprosse}"
                  ?disabled=${eingeloggt}
                  @touchstart=${(e: TouchEvent) => dragStart(sprosse, e.touches[0].clientY)}
                  @touchmove=${(e: TouchEvent) =>
                    dragMove(e.touches[0].clientY, (e.currentTarget as HTMLElement).offsetHeight)}
                  @touchend=${dragEnd}
                  @mousedown=${onMouseDown(sprosse)}
                  @click=${onTap(sprosse)}
                >
                  <span class="al-griff">⠿</span>
                  <span class="al-karte-text">${v.elemente[elementIdx]}</span>
                  <span class="al-karte-nr">${sprosse + 1}</span>
                </button>`,
            )}
          </div>
          <p class="muted al-hinweis">⬇ Sprosse 1 ist UNTEN — ziehen oder 2× tippen zum Tauschen</p>
          ${
            eingeloggt
              ? html`<p class="al-eingeloggt-banner">🔒 Eingeloggt — Daumen drücken!</p>`
              : html`<button class="al-einloggen primaer" @click=${() => sende("einloggen")}>
                  EINLOGGEN 🍌
                </button>`
          }
        </div>`,
        host,
      );
    }
    zeichne();
  },

  explainCard: {
    text: "Bring die 4 Dinge in die richtige Reihenfolge — ziehen oder antippen zum Tauschen! Jede richtige Sprosse bringt MONKEY MONEY, die perfekte Leiter gibt fetten Bonus.",
    animation: html`<span style="font-size:3rem">🪜🐒🥇🍌</span>`,
  },
};

// Erklär-Demo (ADDITIV): Mia tauscht Sprossen, bis die Leiter perfekt steht.
export const demoChoreo: import("../demo-typen").DemoChoreo = {
  dauer: 10000,
  beats: [
    {
      at: 0,
      requisiten: [{ art: "leiter", stufen: ["Elefant 🐘", "Katze 🐈", "Maus 🐭", "Pferd 🐴"] }],
      pose: { a: "denk", b: "denk" },
      gesicht: { a: "denk", b: "denk" },
    },
    {
      at: 2400,
      requisiten: [{ art: "leiter", stufen: ["Maus 🐭", "Katze 🐈", "Elefant 🐘", "Pferd 🐴"] }],
      pose: { a: "zeig", b: "denk" },
      gesicht: { a: "neutral", b: "denk" },
      blase: { wer: "a", text: "Mia tauscht!" },
      sound: "tap",
    },
    {
      at: 4800,
      requisiten: [{ art: "leiter", stufen: ["Maus 🐭", "Katze 🐈", "Pferd 🐴", "Elefant 🐘"] }],
      pose: { a: "zeig", b: "denk" },
      blase: { wer: "a", text: "… und nochmal!" },
      sound: "tap",
    },
    {
      at: 7000,
      requisiten: [
        {
          art: "leiter",
          stufen: ["Maus 🐭", "Katze 🐈", "Pferd 🐴", "Elefant 🐘"],
          perfekt: true,
        },
        { art: "schild", text: "nur 2 Sprossen", ton: "rot", bei: "b" },
      ],
      pose: { a: "jubel", b: "frust" },
      gesicht: { a: "jubel", b: "frust" },
      effekt: "konfetti",
      sound: "richtig",
    },
  ],
};

export default modul;

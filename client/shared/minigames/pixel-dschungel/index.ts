// Client-Renderer „Pixel-Dschungel": Screen = EIN Bild, clientseitig verpixelt
// (Canvas-Downscale→Upscale, KEIN Server-Preprocessing) + Geld-Uhr mit
// Verfalls-Treppe; Player = 4 XXL-Buttons + „NOCH WARTEN"-Fläche, nach der
// Antwort verdeckt sich das Handy (Design: Avatar hält sich die Augen zu).
import { html, render } from "lit-html";
import { formatMM } from "../../../../shared/money";
import type { Schwierigkeit } from "../../../../shared/money";
import {
  PD_ENTHUELLUNG_MS,
  PD_PIXEL_SPALTEN,
  PD_STUFEN,
  PIXEL_DSCHUNGEL_ID,
  pdJackpotWert,
  pdStufeZuZeit,
  type PdBild,
} from "../../../../shared/minigames/pixel-dschungel.meta";
import { timerBalken } from "../../ui";
import type { FxApi, MinigameClientModule, SendAction } from "../types";
import "./pixel-dschungel.css";

const DEKO = [
  { buchstabe: "A", emoji: "🍌", farbe: "#e6b830" },
  { buchstabe: "B", emoji: "🥥", farbe: "#8a5a3b" },
  { buchstabe: "C", emoji: "🐒", farbe: "#d1495b" },
  { buchstabe: "D", emoji: "🌴", farbe: "#2e8b57" },
] as const;

interface PixelDschungelView {
  questionId: string;
  text: string;
  options: string[];
  bild: PdBild;
  schwierigkeit: Schwierigkeit;
  startedAt: number;
  endsAt: number;
  timerMs: number;
  stufenTotal: number;
  answeredCount: number;
  eingeloggt: string[];
  finished: boolean;
  yourChoice?: number | null;
  yourStufe?: number | null;
  aufloesung: {
    correctIndex: number;
    erklaerung: string;
    perPlayer: {
      playerId: string;
      choice: number | null;
      stufe: number | null;
      correct: boolean;
      delta: number;
    }[];
  } | null;
}

// Platzhalter-Motive werden über Vite als Assets aufgelöst (neue Bilder vom
// Orchestrator kommen als media.bild-URL direkt aus dem Content-Pack).
const PLATZHALTER_URLS: Record<string, string> = {
  banane: new URL("../../../../assets/img/fragen/platzhalter/banane.svg", import.meta.url).href,
  affenkopf: new URL("../../../../assets/img/fragen/platzhalter/affenkopf.svg", import.meta.url)
    .href,
  palme: new URL("../../../../assets/img/fragen/platzhalter/palme.svg", import.meta.url).href,
};

function bildUrl(bild: PdBild): string {
  return bild.typ === "platzhalter" ? (PLATZHALTER_URLS[bild.wert] ?? "") : bild.wert;
}

// ---------- Pixelung: EIN Bild, viele Stufen — alles im Client ----------
const bildCache = new Map<string, HTMLImageElement>();
const kleinCanvas = document.createElement("canvas"); // wiederverwendeter Downscale-Puffer

function ladeBild(url: string): HTMLImageElement {
  let img = bildCache.get(url);
  if (!img) {
    img = new Image();
    img.src = url;
    bildCache.set(url, img);
  }
  return img;
}

/**
 * Downscale→Upscale: Bild erst winzig (spalten×zeilen) zeichnen, dann OHNE
 * Glättung großziehen — die klassische Mosaik-Verpixelung. spalten === null
 * ⇒ scharfes Vollbild.
 */
function zeichneStufe(canvas: HTMLCanvasElement, img: HTMLImageElement, spalten: number | null) {
  if (!img.complete || img.naturalWidth === 0) return;
  const ctx = canvas.getContext("2d");
  if (!ctx) return;
  if (spalten === null) {
    ctx.imageSmoothingEnabled = true;
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
    return;
  }
  const zeilen = Math.max(1, Math.round((spalten * canvas.height) / canvas.width));
  kleinCanvas.width = spalten;
  kleinCanvas.height = zeilen;
  const klein = kleinCanvas.getContext("2d");
  if (!klein) return;
  klein.imageSmoothingEnabled = true;
  klein.clearRect(0, 0, spalten, zeilen);
  klein.drawImage(img, 0, 0, spalten, zeilen);
  ctx.imageSmoothingEnabled = false;
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.drawImage(kleinCanvas, 0, 0, canvas.width, canvas.height);
}

/** Verfalls-Treppe als Geld-Uhr: aktuelle Stufe leuchtet, verfallene sind aus. */
function geldUhr(schwierigkeit: Schwierigkeit, stufe: number, scharf: boolean) {
  const aktueller = pdJackpotWert(schwierigkeit, scharf ? PD_STUFEN - 1 : stufe);
  return html`<div class="pd-gelduhr">
    <span class="pd-jackpot">${formatMM(aktueller)}</span>
    <div class="pd-treppe">
      ${Array.from({ length: PD_STUFEN }, (_, s) => {
        const wert = pdJackpotWert(schwierigkeit, s);
        const status = s < stufe || scharf ? "verfallen" : s === stufe ? "aktiv" : "";
        return html`<span class="pd-stufe ${status}">${wert}</span>`;
      })}
    </div>
  </div>`;
}

const modul: MinigameClientModule = {
  id: PIXEL_DSCHUNGEL_ID,

  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void {
    const v = view as PixelDschungelView;
    const msSeitStart = Math.max(0, fx.serverNow() - v.startedAt);
    const scharf = v.finished || v.aufloesung !== null || msSeitStart >= PD_ENTHUELLUNG_MS;
    const stufe = pdStufeZuZeit(msSeitStart);
    const correct = v.aufloesung?.correctIndex ?? -1;

    render(
      html`<div class="pd-screen">
        ${
          v.aufloesung
            ? html`<p class="muted" style="text-align:center">${v.aufloesung.erklaerung}</p>`
            : geldUhr(v.schwierigkeit, stufe, scharf)
        }
        <div class="pd-buehne">
          <canvas class="pd-canvas" width="800" height="600"></canvas>
          <div class="pd-augen-reihe">
            ${v.eingeloggt.map(() => html`<span class="pd-auge">🙈</span>`)}
          </div>
        </div>
        ${v.aufloesung ? "" : timerBalken(v.endsAt, v.timerMs, fx.serverNow())}
        <div class="pd-optionen">
          ${v.options.map(
            (opt, i) =>
              html`<div
                class="pd-option ${v.aufloesung ? (i === correct ? "richtig" : "falsch") : ""}"
                style="--deko:${DEKO[i].farbe}"
              >
                <span class="pd-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                ${opt}
                ${
                  v.aufloesung && i === correct
                    ? html`<span class="pd-treffer">
                        ${v.aufloesung.perPlayer
                          .filter((r) => r.correct)
                          .map((r) => html`<b>+${formatMM(r.delta)}</b>`)}
                      </span>`
                    : ""
                }
              </div>`,
          )}
        </div>
      </div>`,
      host,
    );

    // Canvas imperativ bespielen — nur neu zeichnen, wenn sich Stufe/Bild ändern.
    const canvas = host.querySelector<HTMLCanvasElement>(".pd-canvas");
    if (!canvas) return;
    const url = bildUrl(v.bild);
    const img = ladeBild(url);
    const signatur = `${url}|${scharf ? "scharf" : stufe}|${img.complete ? 1 : 0}`;
    if (canvas.dataset.signatur !== signatur) {
      canvas.dataset.signatur = signatur;
      const spalten = scharf ? null : PD_PIXEL_SPALTEN[stufe];
      if (img.complete) zeichneStufe(canvas, img, spalten);
      else img.addEventListener("load", () => zeichneStufe(canvas, img, spalten), { once: true });
    }
  },

  renderPlayer(view: unknown, host: HTMLElement, send: SendAction, fx?: FxApi): void {
    const v = view as PixelDschungelView;
    if (v.aufloesung) {
      render(html``, host); // Auflösung rendert die Player-App (kennt „you")
      return;
    }
    const gewaehlt = v.yourChoice ?? null;

    if (gewaehlt !== null) {
      // Handy verdeckt: Wer geantwortet hat, sieht die weiteren Stufen nicht mehr.
      const wert =
        v.yourStufe !== null && v.yourStufe !== undefined
          ? pdJackpotWert(v.schwierigkeit, v.yourStufe)
          : null;
      render(
        html`<div class="pd-verdeckt">
          <span style="font-size:5rem">🙈</span>
          <h2>Eingeloggt!</h2>
          ${
            wert !== null
              ? html`<p>
                  Stufe ${(v.yourStufe ?? 0) + 1} —
                  <strong class="pd-jackpot-klein">${formatMM(wert)}</strong> wenn's stimmt.
                </p>`
              : ""
          }
          <p class="muted">Augen zu — die Auflösung kommt gleich.</p>
        </div>`,
        host,
      );
      return;
    }

    // Stufen-Uhr jetzt auf Server-Takt (Engine-Wunsch b) — Fallback lokale Uhr.
    const stufe = pdStufeZuZeit(Math.max(0, (fx?.serverNow() ?? performanceNow()) - v.startedAt));
    render(
      html`<div class="pd-player">
        <div class="pd-player-uhr">
          💰 Jetzt buzzern =
          <strong class="pd-jackpot-klein">
            ${formatMM(pdJackpotWert(v.schwierigkeit, stufe))}
          </strong>
        </div>
        <p class="pd-frage-klein">${v.text}</p>
        ${v.options.map(
          (opt, i) =>
            html`<button
              class="pd-button"
              style="--deko:${DEKO[i].farbe}"
              @click=${() => send("answer", { choice: i })}
            >
              <span class="pd-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
              ${opt}
            </button>`,
        )}
        <div class="pd-warten">🤚 NOCH WARTEN — das Bild wird klarer, der Jackpot kleiner …</div>
      </div>`,
      host,
    );
  },

  explainCard: {
    text: "Ein Bild wird in 8 Stufen scharf — und der Jackpot schrumpft mit! Früh antworten bringt mehr Money, aber falsch = 0 und gesperrt.",
    animation: html`<span style="font-size:3rem">🟩🟨🖼️💰</span>`,
  },
};

// Fallback ohne FxApi (alte App-Version): lokale Wanduhr als Anzeige-Näherung.
function performanceNow(): number {
  return performance.timeOrigin + performance.now();
}

// Erklär-Demo (ADDITIV): das Bild entpixelt sich, der Jackpot schrumpft —
// Mia buzzert früh und kassiert mehr, Bo ist zu spät.
export const demoChoreo: import("../demo-typen").DemoChoreo = {
  dauer: 10200,
  beats: [
    {
      at: 0,
      requisiten: [{ art: "pixel", schaerfe: 0.05, preis: "1.000 MM" }],
      pose: { a: "denk", b: "denk" },
      gesicht: { a: "denk", b: "denk" },
    },
    {
      at: 2300,
      requisiten: [{ art: "pixel", schaerfe: 0.35, preis: "800 MM" }],
      pose: { a: "denk", b: "denk" },
      gesicht: { a: "denk", b: "denk" },
      blase: { wer: "b", text: "Noch nix zu erkennen …" },
    },
    {
      at: 4400,
      requisiten: [{ art: "pixel", schaerfe: 0.55, preis: "600 MM" }],
      pose: { a: "buzz", b: "denk" },
      gesicht: { a: "jubel", b: "denk" },
      blase: { wer: "a", text: "Mia buzzert!" },
      sound: "buzzer-hupe",
    },
    {
      at: 6600,
      requisiten: [
        { art: "pixel", schaerfe: 1, preis: "600 MM" },
        { art: "schild", text: "+600 MM", ton: "gold", bei: "a" },
      ],
      pose: { a: "jubel", b: "frust" },
      gesicht: { a: "jubel", b: "frust" },
      blase: { wer: "b", text: "Zu spät!" },
      geldflug: { von: "mitte", zu: "a" },
      effekt: "konfetti",
      sound: "richtig",
    },
  ],
};

export default modul;

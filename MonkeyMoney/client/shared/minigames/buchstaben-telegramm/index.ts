// Client-Renderer „Das 7-Buchstaben-Telegramm": Screen = Telegramm-Amt
// (Papierstreifen, Zeichen ticken EINZELN mit Tick-Sound ein, Paar-Vorstellung
// mit Affen); Player = Telegramm-Tastatur am Handy für den Beschreiber
// (NUR Buchstaben/Ziffern, Zähler, ⌫-Korrektur mit Budget-Rückgabe VOR dem
// Senden, Senden) bzw. XXL-Buchstaben + 4 Optionen für den Ratenden.
// Der Begriff erscheint NIE beim Ratenden vor der Aufdeckung.
import { html, render } from "lit-html";
import {
  BUCHSTABEN_TELEGRAMM_ID,
  btArtLabel,
  type BtBegriffArt,
} from "../../../../shared/minigames/buchstaben-telegramm.meta";
import { formatMM } from "../../../../shared/money";
import { timerBalken } from "../../ui";
import type { FxApi, MinigameClientModule, SendAction } from "../types";
import "./buchstaben-telegramm.css";

const TASTATUR_REIHEN = ["QWERTZUIOP", "ASDFGHJKL", "YXCVBNM", "0123456789"] as const;

const DEKO = ["A 📜", "B ✉️", "C 📮", "D 📬"] as const;

interface BtBeatEintrag {
  beatNr: number;
  beschreiber: string;
  ratende: string[];
  begriffText: string;
  art: BtBegriffArt;
  hinweis: string;
  richtige: string[];
  falsche: string[];
  uebersprungen: boolean;
  praemieJe: number;
}

interface BuchstabenTelegrammView {
  questionId: string;
  beatNr: number;
  beatTotal: number;
  phase: "vorstellung" | "tippen" | "raten" | "aufdeckung";
  beschreiber: string;
  ratende: string[];
  art: BtBegriffArt;
  hinweis: string;
  maxZeichen: number;
  hinweisGesendet: boolean;
  budget: Record<string, number>;
  praemie: number;
  endsAt: number;
  timerMs: number;
  abgestimmt: number;
  raterZahl: number;
  optionen: string[] | null;
  beat: BtBeatEintrag | null;
  historie: BtBeatEintrag[];
  deltas: Record<string, number>;
  finished: boolean;
  duBistBeschreiber?: boolean;
  duBistRatender?: boolean;
  begriffText?: string | null;
  begriffArtist?: string | null;
  restBudget?: number;
  yourChoice?: number | null;
  aufloesung: {
    erklaerung: string;
    perPlayer: {
      playerId: string;
      choice: null;
      correct: boolean;
      delta: number;
      restBudget?: number;
    }[];
  } | null;
}

function name(fx: FxApi | undefined, playerId: string): string {
  return fx?.spieler?.(playerId)?.name ?? playerId;
}

/** „Sprichwort" ist Neutrum — die übrigen Arten (Film/Promi/Song-Titel)
 * sind Maskulinum; Artikel/Fragewort müssen mitflektieren. */
function artikel(art: BtBegriffArt, maskulin: string, neutrum: string): string {
  return art === "sprichwort" ? neutrum : maskulin;
}

function namen(fx: FxApi | undefined, ids: string[]): string {
  return ids.length > 0 ? ids.map((p) => name(fx, p)).join(", ") : "—";
}

// Zeichen ticken EINZELN ein: Tick-Sound bei jedem neuen Zeichen (Edge-Detection).
let letzterHinweisKey = "";
let letzteHinweisLaenge = 0;
function hinweisSound(v: BuchstabenTelegrammView, fx: FxApi): void {
  const key = `${v.beatNr}:${v.beatTotal}`;
  if (key !== letzterHinweisKey) {
    letzterHinweisKey = key;
    letzteHinweisLaenge = 0;
  }
  if (v.hinweis.length > letzteHinweisLaenge) fx.sound("tick");
  letzteHinweisLaenge = v.hinweis.length;
}

// Aufdeckungs-Stempel genau EINMAL pro Beat vertonen.
let letzterBeatKey = "";
function beatSound(v: BuchstabenTelegrammView, fx: FxApi): void {
  if (v.phase !== "aufdeckung" || !v.beat) return;
  const key = `${v.beat.beatNr}:${v.beatTotal}`;
  if (key === letzterBeatKey) return;
  letzterBeatKey = key;
  fx.sound(
    v.beat.richtige.length > 0 ? "money-klein" : v.beat.uebersprungen ? "zurueck" : "falsch",
  );
}

/** Papierstreifen: getickte Zeichen + leere Slots bis maxZeichen. */
function papierstreifen(v: BuchstabenTelegrammView, gross = false) {
  const slots: unknown[] = [];
  for (let i = 0; i < Math.max(v.maxZeichen, v.hinweis.length); i++) {
    const zeichen = v.hinweis[i];
    slots.push(html`<span class="btg-slot ${zeichen ? "voll" : ""}">${zeichen ?? "·"}</span>`);
  }
  if (slots.length === 0) slots.push(html`<span class="btg-slot leer">KEIN HINWEIS</span>`);
  return html`<div class="btg-streifen ${gross ? "gross" : ""}">${slots}</div>`;
}

function paarVorstellung(v: BuchstabenTelegrammView, fx: FxApi) {
  return html`<div class="btg-paar">
    <div class="btg-affe">
      <span class="btg-affe-emoji">🐒📝</span>
      <strong>${name(fx, v.beschreiber)}</strong>
      <span class="muted">tippt das Telegramm</span>
    </div>
    <span class="btg-und">✚</span>
    <div class="btg-affe">
      <span class="btg-affe-emoji">${v.ratende.length > 1 ? "🐒🐒🔍" : "🐒🔍"}</span>
      <strong>${namen(fx, v.ratende)}</strong>
      <span class="muted">${v.ratende.length > 1 ? "raten (Dreier!)" : "rät"}</span>
    </div>
  </div>`;
}

const modul: MinigameClientModule = {
  id: BUCHSTABEN_TELEGRAMM_ID,

  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void {
    const v = view as BuchstabenTelegrammView;
    hinweisSound(v, fx);
    beatSound(v, fx);

    if (v.aufloesung) {
      render(
        html`<div class="btg-screen">
          <h2 style="text-align:center">📮 Telegramm-Amt — Endabrechnung!</h2>
          <p class="muted" style="text-align:center">${v.aufloesung.erklaerung}</p>
          <div class="btg-bilanz">
            ${[...v.aufloesung.perPlayer]
              .sort((a, b) => b.delta - a.delta)
              .map(
                (r) =>
                  html`<div class="btg-bilanz-zeile ${r.delta > 0 ? "gewonnen" : ""}">
                    <span>${r.delta > 0 ? "💌" : "📭"}</span>
                    <span>${name(fx, r.playerId)}</span>
                    <span class="muted btg-verfall">${r.restBudget ?? 0} Zeichen verfallen</span>
                    <strong class="mm-money-zahl">+${formatMM(r.delta)}</strong>
                  </div>`,
              )}
          </div>
        </div>`,
        host,
      );
      return;
    }

    const kopf = html`<div class="btg-kopf">
      <span class="btg-badge">📮 7-BUCHSTABEN-TELEGRAMM</span>
      <span class="muted"
        >Telegramm ${v.beatNr} / ${v.beatTotal} — Gesucht: ein
        <strong>${btArtLabel(v.art)}</strong> · Erfolg zahlt BEIDEN je
        <strong class="mm-money-zahl">${formatMM(v.praemie)}</strong></span
      >
    </div>`;

    if (v.phase === "vorstellung") {
      render(
        html`<div class="btg-screen">
          ${kopf} ${paarVorstellung(v, fx)}
          <p class="muted" style="text-align:center">
            Zeichen-Konto von ${name(fx, v.beschreiber)}:
            <strong>${v.budget[v.beschreiber] ?? 0}</strong> übrig — pro Telegramm max.
            ${v.maxZeichen || "0"} Zeichen!
          </p>
          ${timerBalken(v.endsAt, v.timerMs, fx.serverNow(), true)}
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "aufdeckung" && v.beat) {
      const b = v.beat;
      render(
        html`<div class="btg-screen">
          ${kopf}
          <div class="btg-aufdeckung ${b.richtige.length > 0 ? "erfolg" : "fehlschlag"}">
            <span class="btg-stempel">
              ${
                b.uebersprungen
                  ? "📪 ZUGESTELLT AN: NIEMAND (Beschreiber weg — Begriff im Papierkorb)"
                  : b.richtige.length > 0
                    ? "💌 ZUGESTELLT!"
                    : "📭 UNZUSTELLBAR!"
              }
            </span>
            <span class="btg-begriff">„${b.begriffText}"</span>
            ${papierstreifen(v)}
            ${
              !b.uebersprungen
                ? html`<div class="btg-stroeme">
                    ${
                      b.richtige.length > 0
                        ? html`<div class="btg-strom gut">
                            💰 Je +${formatMM(b.praemieJe)}: ${namen(fx, b.richtige)} + Beschreiber
                            ${name(fx, b.beschreiber)}
                          </div>`
                        : ""
                    }
                    ${
                      b.falsche.length > 0
                        ? html`<div class="btg-strom schlecht">
                            🙈 Daneben: ${namen(fx, b.falsche)}
                          </div>`
                        : ""
                    }
                  </div>`
                : ""
            }
          </div>
          ${timerBalken(v.endsAt, v.timerMs, fx.serverNow(), true)}
        </div>`,
        host,
      );
      return;
    }

    // TIPPEN + RATEN: der Papierstreifen ist der Star.
    render(
      html`<div class="btg-screen">
        ${kopf}
        <div class="btg-buehne">
          <span class="muted">
            ${
              v.phase === "tippen"
                ? html`📝 ${name(fx, v.beschreiber)} morst … (Konto: ${v.budget[v.beschreiber] ?? 0}
                  Zeichen übrig)`
                : html`🔍 ${namen(fx, v.ratende)} ${v.ratende.length > 1 ? "rätseln" : "rätselt"}:
                  Was heißt das?`
            }
          </span>
          ${papierstreifen(v, true)}
        </div>
        ${
          v.phase === "raten" && v.optionen
            ? html`<div class="btg-optionen">
                ${v.optionen.map(
                  (opt, i) =>
                    html`<div class="btg-option">
                      <span class="btg-deko">${DEKO[i]}</span> ${opt}
                    </div>`,
                )}
                <p class="muted" style="text-align:center;grid-column:1/-1;margin:0">
                  ${v.abgestimmt} / ${v.raterZahl} Antworten …
                </p>
              </div>`
            : ""
        }
        ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())}
      </div>`,
      host,
    );
  },

  renderPlayer(view: unknown, host: HTMLElement, send: SendAction, fx?: FxApi): void {
    const v = view as BuchstabenTelegrammView;
    if (v.aufloesung) {
      render(html``, host); // Auflösung rendert die Player-App (kennt „you")
      return;
    }

    // ---------- BESCHREIBER: Begriff + Telegramm-Tastatur ----------
    if (v.duBistBeschreiber === true) {
      if (v.phase === "tippen" && !v.hinweisGesendet) {
        const voll = v.hinweis.length >= v.maxZeichen || (v.restBudget ?? 0) <= 0;
        render(
          html`<div class="btg-player">
            <div class="btg-begriff-karte">
              <span class="muted"
                >Bring deinem Partner ${artikel(v.art, "diesen", "dieses")} ${btArtLabel(v.art)}
                bei:</span
              >
              <strong class="btg-begriff">„${v.begriffText ?? ""}"</strong>
              ${v.begriffArtist ? html`<span class="muted">(von ${v.begriffArtist})</span>` : ""}
            </div>
            ${papierstreifen(v)}
            <p class="btg-zaehler">
              ${v.hinweis.length} / ${v.maxZeichen} Zeichen — Match-Konto:
              <strong>${v.restBudget ?? 0}</strong> übrig (verfällt am Ende!)
            </p>
            <div class="btg-tastatur">
              ${TASTATUR_REIHEN.map(
                (reihe) =>
                  html`<div class="btg-reihe">
                    ${[...reihe].map(
                      (z) =>
                        html`<button
                          class="btg-taste"
                          ?disabled=${voll}
                          @click=${() => {
                            fx?.sound("tick");
                            void send("buchstabe", { zeichen: z });
                          }}
                        >
                          ${z}
                        </button>`,
                    )}
                  </div>`,
              )}
              <div class="btg-reihe">
                <button
                  class="btg-taste btg-loeschen"
                  ?disabled=${v.hinweis.length === 0}
                  @click=${() => {
                    fx?.sound("zurueck");
                    void send("loeschen", {});
                  }}
                >
                  ⌫ Korrektur (Zeichen zurück)
                </button>
              </div>
            </div>
            <button
              class="btg-senden"
              @click=${() => {
                fx?.sound("lockin-thunk");
                void send("senden", {});
              }}
            >
              📮 TELEGRAMM SENDEN (${v.hinweis.length} Zeichen)
            </button>
          </div>`,
          host,
        );
        return;
      }
      render(
        html`<div class="btg-player">
          <div class="btg-status">
            ${
              v.phase === "vorstellung"
                ? html`📝 DU bist gleich der Beschreiber! Begriff kommt …`
                : v.phase === "raten"
                  ? html`📮 Telegramm ist raus: <strong>${v.hinweis || "(leer)"}</strong><br />
                      <span class="muted"
                        >${v.abgestimmt} / ${v.raterZahl} Antworten … Daumen drücken!</span
                      >`
                  : html`🎭 Aufdeckung — schau auf den großen Bildschirm!`
            }
          </div>
        </div>`,
        host,
      );
      return;
    }

    // ---------- RATENDE(R): Buchstaben groß + 4 Optionen ----------
    if (v.duBistRatender === true) {
      if (v.phase === "raten" && v.optionen) {
        const gewaehlt = v.yourChoice ?? null;
        render(
          html`<div class="btg-player">
            ${papierstreifen(v, true)}
            <p class="muted" style="text-align:center;margin:0">
              ${artikel(v.art, "Welcher", "Welches")} ${btArtLabel(v.art)} steckt im Telegramm? (je
              Erfolg +${formatMM(v.praemie)} für euch BEIDE)
            </p>
            ${v.optionen.map(
              (opt, i) =>
                html`<button
                  class="btg-option-btn ${gewaehlt === i ? "gewaehlt" : ""}"
                  ?disabled=${gewaehlt !== null}
                  @click=${() => {
                    fx?.sound("lockin-thunk");
                    void send("answer", { choice: i });
                  }}
                >
                  <span class="btg-deko">${DEKO[i]}</span> ${opt}
                </button>`,
            )}
          </div>`,
          host,
        );
        return;
      }
      render(
        html`<div class="btg-player">
          <div class="btg-status">
            ${
              v.phase === "tippen"
                ? html`🔍 Dein Partner tippt …
                    <div style="margin-top:8px">${papierstreifen(v, true)}</div>`
                : v.phase === "vorstellung"
                  ? html`🔍 DU rätst gleich! Augen auf den Streifen …`
                  : html`🎭 Aufdeckung — schau auf den großen Bildschirm!`
            }
          </div>
        </div>`,
        host,
      );
      return;
    }

    // ---------- PUBLIKUM (nicht im aktuellen Paar) ----------
    render(
      html`<div class="btg-player">
        <div class="btg-status">
          📮 Telegramm ${v.beatNr} / ${v.beatTotal} — gerade dran: ein anderes Paar.<br />
          <span class="muted"
            >Dein Zeichen-Konto: <strong>${v.restBudget ?? 0}</strong> übrig.</span
          >
        </div>
      </div>`,
      host,
    );
  },

  explainCard: {
    text: "Paar-Spiel! Der Beschreiber bekommt einen geheimen Begriff und darf NUR Buchstaben tippen — max. 8, und das Match-Konto hat nur 60 Zeichen (Rest verfällt!). Der Partner sieht die Buchstaben groß und rät aus 4 Optionen. Erfolg zahlt BEIDEN je 250 MM.",
    animation: html`<span style="font-size:3rem">📮🔠🐒💰</span>`,
  },
};

export default modul;

// Erklär-Demo (ADDITIV): Mia morst „BANANE" aufs Telegramm, Bo rät richtig —
// Erfolg zahlt BEIDEN (Kern-Mechanik: knappes Zeichen-Konto + Paar-Prämie).
export const demoChoreo: import("../demo-typen").DemoChoreo = {
  dauer: 11000,
  beats: [
    {
      at: 0,
      requisiten: [{ art: "schild", text: "📮 · · · · · · · ·", ton: "papier" }],
      pose: { a: "tipp", b: "idle" },
      gesicht: { a: "denk", b: "neutral" },
      blase: { wer: "a", text: "Mia morst — max. 8 Zeichen!" },
      sound: "tick",
    },
    {
      at: 2600,
      requisiten: [{ art: "schild", text: "📮 B A N A N E", ton: "papier" }],
      pose: { a: "tipp", b: "denk" },
      gesicht: { a: "neutral", b: "denk" },
      blase: { wer: "b", text: "Bo liest den Streifen …" },
      sound: "tick",
    },
    {
      at: 5000,
      requisiten: [
        { art: "schild", text: "📮 B A N A N E", ton: "papier" },
        { art: "frage", tippB: 0 },
      ],
      pose: { a: "idle", b: "zeig" },
      gesicht: { a: "neutral", b: "jubel" },
      blase: { wer: "b", text: "Klar: 🍌 Banane!" },
      sound: "lockin-thunk",
    },
    {
      at: 7400,
      requisiten: [
        { art: "frage", tippB: 0, richtig: 0 },
        { art: "schild", text: "💌 ZUGESTELLT — je +250 MM!", ton: "gold" },
      ],
      pose: { a: "jubel", b: "jubel" },
      gesicht: { a: "jubel", b: "jubel" },
      geldflug: { von: "mitte", zu: "b" },
      effekt: "konfetti",
      sound: "richtig",
    },
    {
      at: 9300,
      requisiten: [{ art: "schild", text: "💌 ZUGESTELLT — je +250 MM!", ton: "gold" }],
      pose: { a: "huepf", b: "jubel" },
      gesicht: { a: "jubel", b: "jubel" },
      geldflug: { von: "mitte", zu: "a" },
      sound: "money-klein",
    },
  ],
};

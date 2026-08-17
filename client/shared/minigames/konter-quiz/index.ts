// Client-Renderer „Konter-Quiz": Screen = Fecht-Planche mit den 2 Duell-Affen
// (FxApi.spieler), LIVE-DUELL-BALKEN (Rundenpunkte als Tauziehen + laufende
// Geld-Bilanz), Konter-Beat mit fliegenden Gutschriften. Phasen: Gegner-Wahl →
// Countdown-Gong → Speed-Frage (die Antwort IST der Buzz) → Konter-Beat
// (Bank-Prämien + Konter-Gutschriften) → Duell-Bilanz.
// Player = Gegner-Wahl-Grid (nur Herausforderer), XXL-Antwort-Buttons
// (Duellanten), Zuschauer-Status mit Mit-Rate-Frage.
import { html, render } from "lit-html";
import { KONTER_QUIZ_ID } from "../../../../shared/minigames/konter-quiz.meta";
import { formatMM } from "../../../../shared/money";
import { timerBalken } from "../../ui";
import type { FxApi, MinigameClientModule, SendAction } from "../types";
import "./konter-quiz.css";

const DEKO = [
  { buchstabe: "A", emoji: "🍌", farbe: "#e6b830" },
  { buchstabe: "B", emoji: "🥥", farbe: "#8a5a3b" },
  { buchstabe: "C", emoji: "🐒", farbe: "#d1495b" },
  { buchstabe: "D", emoji: "🌴", farbe: "#2e8b57" },
] as const;

interface KqKandidat {
  id: string;
  waehlbar: boolean;
  verbunden: boolean;
  kontostand: number | null;
}

interface KqView {
  questionId: string;
  frageNonce: number;
  phase: "herausforderung" | "countdown" | "frage" | "konter" | "ergebnis";
  endsAt: number;
  timerMs: number;
  rundeNr: number;
  runden: number;
  herausforderer: string;
  gegner: string | null;
  spieler: string[];
  punkte: Record<string, number>;
  bilanz: Record<string, number>;
  praemieMM: number;
  konterMM: number;
  text: string | null;
  options: string[] | null;
  answeredCount: number;
  letzteRunde: {
    correctIndex: number;
    antworten: Record<string, { choice: number; nachMs: number }>;
    bank: Record<string, number>;
    transfer: Record<string, number>;
    punktFuer: string | null;
    fotofinish: boolean;
  } | null;
  ergebnis: {
    sieger: string | null;
    geteilt: boolean;
    vorzeitig: boolean;
    ohneTransfer: boolean;
    abgebrochen: boolean;
    punkte: Record<string, number>;
  } | null;
  finished: boolean;
  duBistDuellant?: boolean;
  duBistHerausforderer?: boolean;
  yourChoice?: number | null;
  waehlbareGegner?: KqKandidat[] | null;
  aufloesung: {
    correctIndex: number | null;
    erklaerung: string;
    perPlayer: {
      playerId: string;
      choice: null;
      correct: boolean;
      delta: number;
      bank: number;
      transfer: number;
      punkte: number | null;
    }[];
  } | null;
}

function info(fx: FxApi | undefined, playerId: string | null): { name: string; avatar: string } {
  if (playerId === null) return { name: "—", avatar: "gelb" };
  const s = fx?.spieler?.(playerId);
  return { name: s?.name ?? playerId, avatar: s?.avatar ?? "gelb" };
}

/** Countdown-Ziffer (3-2-1) aus der Server-Zeit — tickt ohne Client-Timer. */
function countdownZiffer(v: KqView, serverNow: number): number {
  return Math.max(1, Math.ceil((v.endsAt - serverNow) / 1_000));
}

/** Der LIVE-DUELL-BALKEN: Rundenpunkte als Tauziehen + laufende Geld-Bilanz. */
function duellBalken(fx: FxApi | undefined, v: KqView) {
  const a = v.herausforderer;
  const b = v.gegner;
  if (b === null) return html``;
  const pa = v.punkte[a] ?? 0;
  const pb = v.punkte[b] ?? 0;
  const gesamt = Math.max(1, pa + pb);
  const anteil = pa === 0 && pb === 0 ? 0.5 : pa / gesamt;
  const ia = info(fx, a);
  const ib = info(fx, b);
  return html`<div class="kq-balken">
    <div class="kq-duellant links">
      <span class="kq-mini mm-affe" data-avatar=${ia.avatar}></span>
      <span class="kq-duell-name">${ia.name}</span>
      <span class="kq-bilanz ${(v.bilanz[a] ?? 0) >= 0 ? "plus" : "minus"}">
        ${(v.bilanz[a] ?? 0) >= 0 ? "+" : ""}${formatMM(v.bilanz[a] ?? 0)}
      </span>
    </div>
    <div class="kq-seil">
      <span class="kq-seil-fuellung" style="width:${(anteil * 100).toFixed(0)}%"></span>
      <span class="kq-punkte">⚔️ ${pa} : ${pb}</span>
    </div>
    <div class="kq-duellant rechts">
      <span class="kq-mini mm-affe" data-avatar=${ib.avatar}></span>
      <span class="kq-duell-name">${ib.name}</span>
      <span class="kq-bilanz ${(v.bilanz[b] ?? 0) >= 0 ? "plus" : "minus"}">
        ${(v.bilanz[b] ?? 0) >= 0 ? "+" : ""}${formatMM(v.bilanz[b] ?? 0)}
      </span>
    </div>
  </div>`;
}

/** Konter-Beat-Karte eines Duellanten: richtig/falsch/stumm + Geld-Flüge. */
function konterKarte(fx: FxApi | undefined, v: KqView, playerId: string) {
  const r = v.letzteRunde;
  if (r === null) return html``;
  const antwort = r.antworten[playerId];
  const bank = r.bank[playerId] ?? 0;
  const transfer = r.transfer[playerId] ?? 0;
  const i = info(fx, playerId);
  const richtig = antwort !== undefined && antwort.choice === r.correctIndex;
  return html`<div class="kq-konter-karte ${richtig ? "richtig" : antwort ? "falsch" : "stumm"}">
    <span
      class="kq-puppe mm-affe"
      data-avatar=${i.avatar}
      data-gesicht=${richtig ? "jubel" : antwort ? "frust" : "neutral"}
    ></span>
    <span class="kq-name">${i.name}</span>
    <span class="kq-urteil">
      ${
        antwort === undefined
          ? "🤐 keine Antwort"
          : richtig
            ? html`✅ ${DEKO[antwort.choice]?.buchstabe ?? antwort.choice}
              richtig${r.punktFuer === playerId ? " · ⚔️ Punkt!" : ""}`
            : html`❌ ${DEKO[antwort.choice]?.buchstabe ?? antwort.choice} daneben`
      }
    </span>
    <span class="kq-geldflug">
      ${bank > 0 ? html`<span class="kq-geld bank">🏦 +${formatMM(bank)}</span>` : ""}
      ${
        transfer > 0
          ? html`<span class="kq-geld gutschrift">🎁 +${formatMM(transfer)} Konter</span>`
          : transfer < 0
            ? html`<span class="kq-geld abgabe">💸 ${formatMM(transfer)} an den Partner</span>`
            : ""
      }
    </span>
  </div>`;
}

// Duell-Beats: pro Phase/Nonce EIN Sound (Edge-Detection über den Key).
let letzterSoundKey = "";
function beatSound(v: KqView, fx: FxApi): void {
  const key = `${v.phase}:${v.frageNonce}:${v.rundeNr}`;
  if (key === letzterSoundKey) return;
  letzterSoundKey = key;
  if (v.phase === "frage") fx.sound("frage-ein");
  if (v.phase === "konter" && v.letzteRunde !== null) {
    const transfers = Object.values(v.letzteRunde.transfer).some((t) => t !== 0);
    fx.sound(transfers ? "money-mittel" : "richtig");
  }
  if (v.phase === "ergebnis" && v.ergebnis?.sieger != null) fx.sound("sieg-fanfare");
}

const modul: MinigameClientModule = {
  id: KONTER_QUIZ_ID,

  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void {
    const v = view as KqView;
    beatSound(v, fx);

    if (v.aufloesung || v.phase === "ergebnis") {
      const e = v.ergebnis;
      const sieger = info(fx, e?.sieger ?? null);
      render(
        html`<div class="kq-screen">
          <div class="kq-kopf"><span class="kq-badge">⚔️ KONTER-QUIZ</span></div>
          ${
            e?.abgebrochen === true
              ? html`<h2 class="kq-titel">Duell abgebrochen — keine Zahlungen.</h2>`
              : e?.vorzeitig === true
                ? html`<h2 class="kq-titel">
                    🔌 Duell vorzeitig beendet — Bank-Prämien bleiben,
                    <strong>alle Konter-Gutschriften storniert</strong>.
                  </h2>`
                : e?.geteilt === true
                  ? html`<h2 class="kq-titel">🤝 UNENTSCHIEDEN nach Punkten!</h2>`
                  : e?.sieger != null
                    ? html`<h2 class="kq-titel">
                        🏆 <strong>${sieger.name.toUpperCase()}</strong> gewinnt das Duell nach
                        Punkten!
                      </h2>`
                    : html`<h2 class="kq-titel">Duell-Bilanz</h2>`
          }
          ${duellBalken(fx, v)}
          ${
            v.aufloesung
              ? html`<div class="kq-bilanz-liste">
                  ${[...v.aufloesung.perPlayer]
                    .filter((r) => r.punkte !== null)
                    .sort((x, y) => y.delta - x.delta)
                    .map(
                      (r) =>
                        html`<div class="kq-bilanz-zeile ${r.delta >= 0 ? "plus" : "minus"}">
                          <span
                            class="kq-mini mm-affe"
                            data-avatar=${info(fx, r.playerId).avatar}
                          ></span>
                          <span>${info(fx, r.playerId).name}</span>
                          <span class="muted">
                            🏦 ${formatMM(r.bank)} · Konter
                            ${r.transfer >= 0 ? "+" : ""}${formatMM(r.transfer)}
                          </span>
                          <strong class="mm-money-zahl">
                            ${r.delta >= 0 ? "+" : ""}${formatMM(r.delta)}
                          </strong>
                        </div>`,
                    )}
                </div>`
              : ""
          }
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "herausforderung") {
      const h = info(fx, v.herausforderer);
      render(
        html`<div class="kq-screen">
          <div class="kq-kopf"><span class="kq-badge">⚔️ KONTER-QUIZ</span></div>
          ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())}
          <div class="kq-wahl">
            <span class="kq-puppe gross mm-affe mm-affe-idle" data-avatar=${h.avatar}></span>
            <h2 class="kq-titel">
              <strong>${h.name.toUpperCase()}</strong> (Letzter im Zwischenstand) sucht sich einen
              Duell-Partner …
            </h2>
            <p class="muted">
              ${v.runden} Blitz-Fragen: Richtig = +${formatMM(v.praemieMM)} aus der Bank. Falsch =
              ${formatMM(v.konterMM)} Konter-Gutschrift an den Partner!
            </p>
          </div>
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "countdown") {
      render(
        html`<div class="kq-screen">
          ${duellBalken(fx, v)}
          <div class="kq-countdown">${countdownZiffer(v, fx.serverNow())}</div>
          <p class="muted" style="text-align:center">
            ⚔️ ${info(fx, v.herausforderer).name} gegen ${info(fx, v.gegner).name} — ${v.runden}
            Fragen, freundliches Feuer: Fehler ZAHLEN dem Partner!
          </p>
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "frage") {
      render(
        html`<div class="kq-screen">
          <div class="kq-kopf">
            <span class="kq-badge">⚔️ FRAGE ${v.rundeNr}/${v.runden}</span>
            <span class="muted">${v.answeredCount}/2 Antworten · Speed zählt für den Punkt</span>
          </div>
          <h2 class="kq-frage">${v.text ?? ""}</h2>
          ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())}
          <div class="kq-optionen">
            ${(v.options ?? []).map(
              (opt, i) =>
                html`<div class="kq-option" style="--deko:${DEKO[i].farbe}">
                  <span class="kq-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                  ${opt}
                </div>`,
            )}
          </div>
          ${duellBalken(fx, v)}
        </div>`,
        host,
      );
      return;
    }

    // KONTER-Beat: Prämien + Gutschriften fliegen sichtbar.
    const r = v.letzteRunde;
    render(
      html`<div class="kq-screen">
        <div class="kq-kopf">
          <span class="kq-badge">💥 KONTER!</span>
          ${r?.fotofinish === true ? html`<span class="muted">📸 Fotofinish-Los!</span>` : ""}
        </div>
        <p class="muted" style="text-align:center">
          Richtig war: <strong>${r !== null ? DEKO[r.correctIndex].buchstabe : "?"}</strong>
        </p>
        <div class="kq-konter-buehne">
          ${konterKarte(fx, v, v.herausforderer)}
          <span class="kq-blitz">⚡</span>
          ${v.gegner !== null ? konterKarte(fx, v, v.gegner) : ""}
        </div>
        ${duellBalken(fx, v)}
      </div>`,
      host,
    );
  },

  renderPlayer(view: unknown, host: HTMLElement, send: SendAction, fx?: FxApi): void {
    const v = view as KqView;
    if (v.aufloesung) {
      render(html``, host); // Auflösung rendert die Player-App (kennt „you")
      return;
    }

    // ---------- Gegner-Wahl (NUR der Herausforderer) ----------
    if (v.phase === "herausforderung") {
      if (v.duBistHerausforderer === true) {
        render(
          html`<div class="kq-player">
            <h3 class="kq-player-titel">⚔️ DU duellierst dich — wähle deinen Partner!</h3>
            <div class="kq-gegner-grid">
              ${(v.waehlbareGegner ?? []).map((k) => {
                const i = info(fx, k.id);
                return html`<button
                  class="kq-gegner ${k.waehlbar ? "" : "geschuetzt"}"
                  ?disabled=${!k.waehlbar}
                  @click=${() => {
                    fx?.sound("lockin-thunk");
                    void send("herausfordern", { targetId: k.id });
                  }}
                >
                  <span class="kq-mini mm-affe" data-avatar=${i.avatar}></span>
                  <span>${i.name}</span>
                  <span class="muted">
                    ${
                      !k.verbunden
                        ? "offline"
                        : !k.waehlbar
                          ? "🛡️ geschützt"
                          : k.kontostand !== null
                            ? formatMM(k.kontostand)
                            : ""
                    }
                  </span>
                </button>`;
              })}
            </div>
          </div>`,
          host,
        );
        return;
      }
      render(
        html`<div class="kq-player">
          <div class="kq-status">
            ⚔️ <strong>${info(fx, v.herausforderer).name}</strong> wählt den Duell-Partner …<br />
            <span class="muted">Trifft es gleich DICH?</span>
          </div>
        </div>`,
        host,
      );
      return;
    }

    const istDuellant = v.duBistDuellant === true;

    if (v.phase === "countdown") {
      render(
        html`<div class="kq-player">
          <div class="kq-countdown klein">${countdownZiffer(v, fx?.serverNow() ?? v.endsAt)}</div>
          ${
            istDuellant
              ? html`<p class="muted" style="text-align:center">
                  Richtig = +${formatMM(v.praemieMM)} Bank. Falsch = ${formatMM(v.konterMM)}
                  Geschenk an den Partner. Schweigen ist gratis!
                </p>`
              : ""
          }
        </div>`,
        host,
      );
      return;
    }

    // ---------- Speed-Frage: XXL-Buttons NUR für Duellanten ----------
    if (v.phase === "frage") {
      if (istDuellant) {
        const gewaehlt = v.yourChoice ?? null;
        render(
          html`<div class="kq-player">
            <p class="kq-frage-klein">${v.text ?? ""}</p>
            ${(v.options ?? []).map(
              (opt, i) =>
                html`<button
                  class="kq-button ${gewaehlt === i ? "gewaehlt" : ""} ${gewaehlt !== null ? "gesperrt" : ""}"
                  style="--deko:${DEKO[i].farbe}"
                  ?disabled=${gewaehlt !== null}
                  @click=${() => {
                    fx?.sound("lockin-thunk");
                    void send("answer", { choice: i });
                  }}
                >
                  <span class="kq-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                  ${opt}
                </button>`,
            )}
            ${
              gewaehlt !== null
                ? html`<p class="muted" style="text-align:center">
                    Eingerastet — jetzt zählt nur noch der Partner …
                  </p>`
                : ""
            }
          </div>`,
          host,
        );
        return;
      }
      render(
        html`<div class="kq-player">
          <div class="kq-status">
            👀 Duell läuft — ${v.answeredCount}/2 Antworten.<br />
            <span class="muted">Rate im Kopf mit — der Duell-Balken wandert live!</span>
          </div>
          <p class="kq-frage-klein muted">${v.text ?? ""}</p>
        </div>`,
        host,
      );
      return;
    }

    // Konter/Ergebnis: kompakter Status.
    const r = v.letzteRunde;
    render(
      html`<div class="kq-player">
        <div class="kq-status">
          ${
            v.phase === "konter"
              ? r !== null && Object.values(r.transfer).some((t) => t !== 0)
                ? html`💸 Konter-Gutschrift fliegt — richtig war
                    <strong>${DEKO[r.correctIndex].buchstabe}</strong>!`
                : html`✅ Richtig war
                    <strong>${r !== null ? DEKO[r.correctIndex].buchstabe : "?"}</strong> — nächste
                    Frage!`
              : v.ergebnis?.geteilt === true
                ? "🤝 Unentschieden nach Punkten!"
                : v.ergebnis?.sieger != null
                  ? html`🏆 <strong>${info(fx, v.ergebnis.sieger).name}</strong> gewinnt das Duell!`
                  : "…"
          }
        </div>
      </div>`,
      host,
    );
  },

  explainCard: {
    text: "Freundliches 1-gegen-1: Der Letzte wählt den Duell-Partner, dann 8 Blitz-Fragen. Richtig = +150 MM aus der Bank. FALSCH = 150 MM Konter-Gutschrift an den Partner! Schweigen kostet nichts — die schnellere richtige Antwort holt den Duell-Punkt.",
    animation: html`<span style="font-size:3rem">⚔️🐒💸🐒🏦</span>`,
  },
};

// Erklär-Demo (ADDITIV): Mia richtig (Bank zahlt), Bo daneben — seine 150 MM
// fliegen als Konter-Gutschrift zu Mia. Freundliches Feuer!
export const demoChoreo: import("../demo-typen").DemoChoreo = {
  dauer: 11000,
  beats: [
    {
      at: 0,
      requisiten: [{ art: "schild", text: "⚔️ Duell: 8 Blitz-Fragen", ton: "cyan" }],
      pose: { a: "buzz", b: "buzz" },
      gesicht: { a: "neutral", b: "neutral" },
      blase: { wer: "a", text: "Schnellrate-Duell!" },
    },
    {
      at: 2200,
      requisiten: [{ art: "frage" }],
      pose: { a: "denk", b: "denk" },
      gesicht: { a: "denk", b: "denk" },
      blase: { wer: "b", text: "Falsch zahlt an den PARTNER!" },
      sound: "frage-ein",
    },
    {
      at: 4600,
      requisiten: [{ art: "frage", tippA: 0, tippB: 2, richtig: 0 }],
      pose: { a: "tipp", b: "tipp" },
      gesicht: { a: "jubel", b: "frust" },
      blase: { wer: "a", text: "Mia richtig — Bo daneben!" },
      sound: "lockin-thunk",
    },
    {
      at: 6800,
      requisiten: [{ art: "schild", text: "🏦 +150 · Konter +150!", ton: "gold", bei: "a" }],
      pose: { a: "jubel", b: "duck" },
      gesicht: { a: "jubel", b: "frust" },
      geldflug: { von: "b", zu: "a" },
      sound: "money-mittel",
    },
    {
      at: 9200,
      requisiten: [{ art: "schild", text: "Schweigen ist gratis!", ton: "papier" }],
      pose: { a: "jubel", b: "idle" },
      gesicht: { a: "jubel", b: "neutral" },
      effekt: "konfetti",
      sound: "runden-sieg",
    },
  ],
};

export default modul;

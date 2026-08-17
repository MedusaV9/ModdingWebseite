// Client-Renderer „Der Goldene Affe" (GAME-DESIGN §2.12, v2-Finale-Alternative):
// der goldene Affentempel öffnet sich in 3 Stufen. Screen: Money-Drop mit 4
// Tempel-Türen (Chips geheim, Falltür-Ergebnis mit ×2-Regen), Schätz-Showdown
// (Richtwert geheim), Wett-Beat der Ausgeschiedenen, Buzzer-Best-of-3 mit
// Punkte-Pips, Krönung mit 20-%-Tribut. Player: Chip-Verteiler (Tap = Chip,
// letzter Stand zählt), Schätz-Slider + Einloggen, Wett-Buttons (Puppen),
// XXL-Speed-Buttons (nur Finalisten), Warte-/Zuschauer-Zustände.
import { html, render } from "lit-html";
import { GA_CHIPS, GOLDENER_AFFE_ID } from "../../../../shared/minigames/goldener-affe.meta";
import { formatMM } from "../../../../shared/money";
import { timerBalken } from "../../ui";
import type { FxApi, MinigameClientModule, SendAction } from "../types";
import "./goldener-affe.css";

const DEKO = [
  { buchstabe: "A", emoji: "🍌", farbe: "#e6b830" },
  { buchstabe: "B", emoji: "🥥", farbe: "#8a5a3b" },
  { buchstabe: "C", emoji: "🐒", farbe: "#d1495b" },
  { buchstabe: "D", emoji: "🌴", farbe: "#2e8b57" },
] as const;

type GaPhase =
  | "drop"
  | "drop-ergebnis"
  | "schaetzen"
  | "schaetz-ergebnis"
  | "wetten"
  | "buzzer"
  | "buzzer-ergebnis"
  | "showdown"
  | "kroenung";

interface GaSchaetzView {
  id: string;
  text: string;
  einheit: string;
  eingabeMin: number;
  eingabeMax: number;
  richtwert: number | null;
  erklaerung: string | null;
  tipps: Record<string, number> | null;
  abgegeben: number;
}

interface GaView {
  questionId: string;
  frageNonce: number;
  phase: GaPhase;
  stufe: 1 | 2 | 3;
  endsAt: number;
  timerMs: number;
  spieler: string[];
  spielerZahl: number;
  finalisten: string[];
  ausgeschieden: string[];
  wildcard: string | null;
  punkte: Record<string, number>;
  buzzerRunde: number;
  buzzerFragen: number;
  punkteZiel: number;
  text: string | null;
  options: string[] | null;
  chipsFertig: string[];
  dropErgebnis: {
    correctIndex: number;
    chips: Record<string, number[]>;
    perPlayer: Record<string, { einsatz: number; gratis: boolean; delta: number }>;
  } | null;
  schaetz: GaSchaetzView | null;
  wettenAnzahl: number;
  wetten: Record<string, string> | null;
  wetteMM: number;
  wetteFaktor: number;
  letzteBuzzerFrage: {
    correctIndex: number;
    gewinner: string | null;
    fotofinish: boolean;
  } | null;
  showdown: Omit<GaSchaetzView, "richtwert" | "erklaerung" | "tipps"> | null;
  answeredCount: number;
  ergebnis: {
    sieger: string | null;
    kampflos: boolean;
    abgebrochen: boolean;
    transferSumme: number;
  } | null;
  finished: boolean;
  duBistFinalist?: boolean;
  duBistAusgeschieden?: boolean;
  deineChips?: number[] | null;
  deinEinsatz?: { betrag: number; gratis: boolean } | null;
  eingabeMin?: number;
  eingabeMax?: number;
  yourTipp?: number | null;
  deineWette?: string | null;
  yourChoice?: number | null;
  zuschauerOptionen?: string[] | null;
  aufloesung: {
    correctIndex: number | null;
    erklaerung: string;
    perPlayer: { playerId: string; choice: number | null; correct: boolean; delta: number }[];
  } | null;
}

function info(fx: FxApi | undefined, playerId: string | null): { name: string; avatar: string } {
  if (playerId === null) return { name: "—", avatar: "gelb" };
  const s = fx?.spieler?.(playerId);
  return { name: s?.name ?? playerId, avatar: s?.avatar ?? "gelb" };
}

function stufenBadge(v: GaView) {
  const label =
    v.stufe === 1
      ? "STUFE 1 · MONEY-DROP"
      : v.stufe === 2
        ? "STUFE 2 · SCHÄTZ-SHOWDOWN"
        : "STUFE 3 · BUZZER-FINALE";
  return html`<div class="ga-kopf">
    <span class="ga-badge">🐵✨ DER GOLDENE AFFE</span>
    <span class="ga-stufe">${label}</span>
  </div>`;
}

function punkteZeile(fx: FxApi | undefined, v: GaView) {
  return html`<div class="ga-punkte">
    ${v.finalisten.map((f) => {
      const i = info(fx, f);
      const p = v.punkte[f] ?? 0;
      return html`<div class="ga-finalist">
        <span class="ga-puppe mm-affe mm-affe-idle" data-avatar=${i.avatar}></span>
        <span class="ga-name">${i.name}${v.wildcard === f ? " 🃏" : ""}</span>
        <span class="ga-pips">
          ${Array.from({ length: v.punkteZiel }, (_, k) => html`<span class="ga-pip ${k < p ? "voll" : ""}"></span>`)}
        </span>
      </div>`;
    })}
  </div>`;
}

// Krönung: einmalige Konfetti-Salve (Edge-Detection über den Sieger).
let letzteKroenung = "";
function kroenungFx(v: GaView, fx: FxApi): void {
  if (v.phase !== "kroenung" || v.ergebnis?.sieger == null) return;
  if (letzteKroenung === v.ergebnis.sieger) return;
  letzteKroenung = v.ergebnis.sieger;
  fx.sound("sieg-fanfare");
  fx.partikel?.("money-regen", { anzahl: 60 });
}

const modul: MinigameClientModule = {
  id: GOLDENER_AFFE_ID,

  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void {
    const v = view as GaView;
    kroenungFx(v, fx);

    // ---------- Krönung / Auflösung ----------
    if (v.phase === "kroenung" || v.aufloesung) {
      const e = v.ergebnis;
      const sieger = info(fx, e?.sieger ?? null);
      render(
        html`<div class="ga-screen">
          ${stufenBadge(v)}
          ${
            e?.abgebrochen === true && e.sieger === null
              ? html`<h2 class="ga-titel">Der Tempel schließt sich — kein Sieger.</h2>`
              : html`<div class="ga-kroenung">
                  <span class="ga-krone">👑</span>
                  <span
                    class="ga-puppe riesig mm-affe mm-affe-idle"
                    data-avatar=${sieger.avatar}
                  ></span>
                  <h2 class="ga-titel">
                    <strong>${sieger.name.toUpperCase()}</strong> ist der GOLDENE AFFE!
                  </h2>
                  ${
                    e !== null && e.transferSumme > 0
                      ? html`<p class="ga-tribut">
                          … und nimmt die Bananen mit:
                          <strong class="mm-money-zahl">+${formatMM(e.transferSumme)}</strong>
                          (20 % der Konten aller anderen)
                        </p>`
                      : e?.kampflos === true
                        ? html`<p class="muted">Kampfloser Titel — kein Tribut, Wetten zurück.</p>`
                        : ""
                  }
                </div>`
          }
          ${
            v.aufloesung
              ? html`<div class="ga-bilanz">
                  ${[...v.aufloesung.perPlayer]
                    .sort((a, b) => b.delta - a.delta)
                    .map(
                      (r) =>
                        html`<div class="ga-bilanz-zeile ${r.correct ? "gewonnen" : ""}">
                          <span
                            class="ga-mini mm-affe"
                            data-avatar=${info(fx, r.playerId).avatar}
                          ></span>
                          <span>${info(fx, r.playerId).name}</span>
                          <strong
                            class="mm-money-zahl"
                            style="color:${r.delta >= 0 ? "var(--gold)" : "var(--rot)"}"
                          >
                            ${r.delta > 0 ? "+" : ""}${formatMM(r.delta)}
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

    // ---------- Stufe 1: Money-Drop ----------
    if (v.phase === "drop" || v.phase === "drop-ergebnis") {
      const d = v.dropErgebnis;
      render(
        html`<div class="ga-screen">
          ${stufenBadge(v)}
          ${v.phase === "drop" ? timerBalken(v.endsAt, v.timerMs, fx.serverNow()) : ""}
          <h2 class="ga-frage">${v.text ?? "Die Falltüren öffnen sich …"}</h2>
          <div class="ga-tueren">
            ${(v.options ?? ["", "", "", ""]).map((opt, i) => {
              const richtig = d !== null && d.correctIndex === i;
              const offen = d !== null && d.correctIndex !== i;
              return html`<div
                class="ga-tuer ${richtig ? "richtig" : ""} ${offen ? "falltuer" : ""}"
                style="--deko:${DEKO[i].farbe}"
              >
                <span class="ga-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                <span class="ga-tuer-text">${opt}</span>
                ${
                  d !== null
                    ? html`<div class="ga-tuer-chips">
                        ${Object.entries(d.chips)
                          .filter(([, c]) => (c[i] ?? 0) > 0)
                          .map(
                            ([p, c]) =>
                              html`<span class="ga-chip-tag">
                                <span
                                  class="ga-mini mm-affe"
                                  data-avatar=${info(fx, p).avatar}
                                ></span>
                                ×${c[i]}
                              </span>`,
                          )}
                      </div>`
                    : ""
                }
              </div>`;
            })}
          </div>
          ${
            v.phase === "drop"
              ? html`<p class="muted" style="text-align:center">
                  Einsatz: 50 % des ECHTEN Kontos! Chips auf der richtigen Tür kommen ×2 zurück —
                  fertig: ${v.chipsFertig.length}/${v.spielerZahl}
                </p>`
              : html`<div class="ga-drop-bilanz">
                  ${Object.entries(d?.perPlayer ?? {}).map(
                    ([p, r]) =>
                      html`<span class="ga-chip-tag ${r.delta >= 0 ? "plus" : "minus"}">
                        ${info(fx, p).name}:
                        ${r.delta > 0 ? "+" : ""}${formatMM(r.delta)}${r.gratis ? " (Gratis-Einsatz)" : ""}
                      </span>`,
                  )}
                </div>`
          }
        </div>`,
        host,
      );
      return;
    }

    // ---------- Stufe 2: Schätzen + Wetten ----------
    if (v.phase === "schaetzen" || v.phase === "schaetz-ergebnis" || v.phase === "wetten") {
      const sch = v.schaetz;
      render(
        html`<div class="ga-screen">
          ${stufenBadge(v)} ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())}
          <h2 class="ga-frage">${sch?.text ?? ""}</h2>
          ${
            v.phase === "schaetzen"
              ? html`<p class="muted" style="text-align:center">
                  ${sch?.abgegeben ?? 0}/${v.spielerZahl} Tipps — die 2 NÄCHSTEN werden Finalisten,
                  der Rest scheidet aus!
                  (${sch?.eingabeMin.toLocaleString("de-DE")}–${sch?.eingabeMax.toLocaleString("de-DE")}
                  ${sch?.einheit})
                </p>`
              : html`<div class="ga-schaetz-ergebnis">
                  <p class="ga-richtwert">
                    Richtwert:
                    <strong class="mm-money-zahl"
                      >${sch?.richtwert?.toLocaleString("de-DE")} ${sch?.einheit}</strong
                    >
                  </p>
                  <div class="ga-tipp-liste">
                    ${Object.entries(sch?.tipps ?? {}).map(
                      ([p, wert]) =>
                        html`<span class="ga-chip-tag ${v.finalisten.includes(p) ? "plus" : ""}">
                          ${info(fx, p).name}: ${wert.toLocaleString("de-DE")}
                          ${v.finalisten.includes(p) ? " ⭐" : ""}
                        </span>`,
                    )}
                  </div>
                  ${punkteZeile(fx, v)}
                  ${
                    v.phase === "wetten"
                      ? html`<p class="muted" style="text-align:center">
                          🚩 Die Ausgeschiedenen wetten ${formatMM(v.wetteMM)} auf den Sieger (zahlt
                          ×${v.wetteFaktor}) — ${v.wettenAnzahl}
                          Wette${v.wettenAnzahl === 1 ? "" : "n"} platziert …
                        </p>`
                      : ""
                  }
                </div>`
          }
        </div>`,
        host,
      );
      return;
    }

    // ---------- Stufe 3: Buzzer + Showdown ----------
    if (v.phase === "showdown") {
      render(
        html`<div class="ga-screen">
          ${stufenBadge(v)} ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())}
          <h2 class="ga-titel">⚖️ GLEICHSTAND — die ultimative Schätzfrage!</h2>
          <h2 class="ga-frage">${v.showdown?.text ?? ""}</h2>
          ${punkteZeile(fx, v)}
          <p class="muted" style="text-align:center">Näher dran gewinnt ALLES.</p>
        </div>`,
        host,
      );
      return;
    }

    const b = v.letzteBuzzerFrage;
    render(
      html`<div class="ga-screen">
        ${stufenBadge(v)}
        <div class="ga-kopf">
          <span class="ga-stufe"
            >Frage ${v.buzzerRunde}/${v.buzzerFragen} · ${v.punkteZiel} Punkte siegen</span
          >
          ${v.phase === "buzzer" ? html`<span class="muted">${v.answeredCount}/2 Antworten</span>` : ""}
        </div>
        ${v.phase === "buzzer" ? timerBalken(v.endsAt, v.timerMs, fx.serverNow()) : ""}
        ${
          v.phase === "buzzer"
            ? html`<h2 class="ga-frage">${v.text ?? ""}</h2>
                <div class="ga-optionen">
                  ${(v.zuschauerOptionen ?? []).map(
                    (opt, i) =>
                      html`<div class="ga-option" style="--deko:${DEKO[i].farbe}">
                        <span class="ga-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                        ${opt}
                      </div>`,
                  )}
                </div>`
            : html`<h2 class="ga-titel">
                ${
                  b?.gewinner != null
                    ? html`⚡ Punkt für
                        <strong>${info(fx, b.gewinner).name.toUpperCase()}</strong>${
                          b.fotofinish ? " (Fotofinish-Los! 📸)" : ""
                        }`
                    : "Niemand richtig — kein Punkt."
                }
                ${b !== null ? html`<span class="muted"> · Richtig: ${DEKO[b.correctIndex].buchstabe}</span>` : ""}
              </h2>`
        }
        ${punkteZeile(fx, v)}
        ${
          v.wetten !== null && Object.keys(v.wetten).length > 0
            ? html`<div class="ga-tipp-liste">
                ${Object.entries(v.wetten).map(
                  ([w, auf]) =>
                    html`<span class="ga-chip-tag"
                      >🚩 ${info(fx, w).name} → ${info(fx, auf).name}</span
                    >`,
                )}
              </div>`
            : ""
        }
      </div>`,
      host,
    );
  },

  renderPlayer(view: unknown, host: HTMLElement, send: SendAction, fx?: FxApi): void {
    const v = view as GaView;
    if (v.aufloesung) {
      render(html``, host); // Auflösung rendert die Player-App (kennt „you")
      return;
    }

    // ---------- Stufe 1: Chips verteilen ----------
    if (v.phase === "drop") {
      const chips = v.deineChips ?? [0, 0, 0, 0];
      const gesetzt = chips.reduce((a, b) => a + b, 0);
      const rest = GA_CHIPS - gesetzt;
      const einsatz = v.deinEinsatz;
      render(
        html`<div class="ga-player">
          <p class="ga-frage-klein">${v.text ?? ""}</p>
          <div class="ga-einsatz">
            Dein Einsatz:
            <strong class="mm-money-zahl">${einsatz ? formatMM(einsatz.betrag) : "—"}</strong>
            ${einsatz?.gratis === true ? html`<span class="muted">(Gratis — die Bank zahlt!)</span>` : ""}
            · Chips übrig: <strong>${rest}</strong>
          </div>
          ${(v.options ?? []).map(
            (opt, i) =>
              html`<button
                class="ga-chip-button"
                style="--deko:${DEKO[i].farbe}"
                ?disabled=${rest <= 0}
                @click=${() => {
                  fx?.sound("money-klein");
                  const neu = [...chips];
                  neu[i] = (neu[i] ?? 0) + 1;
                  void send("chips", { verteilung: neu });
                }}
              >
                <span class="ga-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                <span class="ga-chip-opt">${opt}</span>
                <span class="ga-chip-zahl">${chips[i] > 0 ? `🪙×${chips[i]}` : ""}</span>
              </button>`,
          )}
          <div class="ga-chip-werkzeuge">
            <button
              class="ga-werkzeug"
              ?disabled=${gesetzt === 0}
              @click=${() => void send("chips", { verteilung: [0, 0, 0, 0] })}
            >
              ↺ zurücksetzen
            </button>
            <span class="muted">Tipp: unverteilte Chips wandern reihum auf deine Türen.</span>
          </div>
        </div>`,
        host,
      );
      return;
    }

    // ---------- Stufe 2 + Showdown: Schätz-Slider ----------
    const schaetzAktiv = v.phase === "schaetzen";
    const showdownAktiv = v.phase === "showdown" && v.duBistFinalist === true;
    if (schaetzAktiv || showdownAktiv) {
      const frageText = schaetzAktiv ? (v.schaetz?.text ?? "") : (v.showdown?.text ?? "");
      const einheit = schaetzAktiv ? (v.schaetz?.einheit ?? "") : (v.showdown?.einheit ?? "");
      const min = v.eingabeMin ?? 0;
      const max = v.eingabeMax ?? 100;
      const wert = v.yourTipp ?? Math.round((min + max) / 2);
      render(
        html`<div class="ga-player">
          <p class="ga-frage-klein">${frageText}</p>
          <div class="ga-wert">
            <strong class="mm-money-zahl">${wert.toLocaleString("de-DE")}</strong>
            <span class="muted">${einheit}</span>
          </div>
          <input
            class="ga-slider"
            type="range"
            min=${min}
            max=${max}
            .value=${String(wert)}
            @input=${(e: Event) => {
              const roh = Number((e.target as HTMLInputElement).value);
              if (Number.isFinite(roh)) void send("tipp", { wert: roh });
            }}
          />
          <input
            class="ga-wert-input mm-money-zahl"
            type="number"
            inputmode="numeric"
            min=${min}
            max=${max}
            .value=${String(wert)}
            aria-label="Schätzwert direkt eingeben"
            @change=${(e: Event) => {
              const roh = Number((e.target as HTMLInputElement).value);
              if (Number.isFinite(roh)) void send("tipp", { wert: roh });
            }}
          />
          ${
            schaetzAktiv
              ? html`<button
                  class="ga-einloggen"
                  @click=${() => {
                    fx?.sound("lockin-thunk");
                    void send("einloggen", { wert });
                  }}
                >
                  🔒 EINLOGGEN
                </button>`
              : html`<p class="muted" style="text-align:center;margin:0">
                  Der letzte Stand zählt!
                </p>`
          }
          <p class="muted" style="text-align:center;margin:0">
            ${schaetzAktiv ? "Die 2 Nächsten werden Finalisten!" : "Näher dran gewinnt ALLES."}
          </p>
        </div>`,
        host,
      );
      return;
    }

    // ---------- Wett-Beat der Ausgeschiedenen ----------
    if (v.phase === "wetten") {
      if (v.duBistAusgeschieden === true && (v.deineWette ?? null) === null) {
        render(
          html`<div class="ga-player">
            <h3 class="ga-player-titel">
              🚩 ${formatMM(v.wetteMM)} auf den GOLDENEN AFFEN (zahlt ×${v.wetteFaktor})
            </h3>
            <div class="ga-wett-grid">
              ${v.finalisten.map((f) => {
                const i = info(fx, f);
                return html`<button
                  class="ga-wett-button"
                  @click=${() => {
                    fx?.sound("lockin-thunk");
                    void send("wette", { auf: f });
                  }}
                >
                  <span class="ga-puppe mm-affe mm-affe-idle" data-avatar=${i.avatar}></span>
                  <span>${i.name}</span>
                </button>`;
              })}
            </div>
          </div>`,
          host,
        );
        return;
      }
      render(
        html`<div class="ga-player">
          <div class="ga-status">
            ${
              v.duBistFinalist === true
                ? html`⭐ DU bist im Finale!<br /><span class="muted"
                      >Gleich: Buzzer-Best-of-3 …</span
                    >`
                : (v.deineWette ?? null) !== null
                  ? html`🚩 Wette platziert:
                      <strong>${info(fx, v.deineWette ?? null).name}</strong>`
                  : html`Die Ausgeschiedenen wetten …`
            }
          </div>
        </div>`,
        host,
      );
      return;
    }

    // ---------- Stufe 3: Speed-Buttons (nur Finalisten) ----------
    if (v.phase === "buzzer" && v.duBistFinalist === true) {
      const gewaehlt = v.yourChoice ?? null;
      render(
        html`<div class="ga-player">
          <p class="ga-frage-klein">${v.text ?? ""}</p>
          ${(v.options ?? []).map(
            (opt, i) =>
              html`<button
                class="ga-button ${gewaehlt === i ? "gewaehlt" : ""} ${gewaehlt !== null ? "gesperrt" : ""}"
                style="--deko:${DEKO[i].farbe}"
                ?disabled=${gewaehlt !== null}
                @click=${() => {
                  fx?.sound("lockin-thunk");
                  void send("answer", { choice: i });
                }}
              >
                <span class="ga-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                ${opt}
              </button>`,
          )}
        </div>`,
        host,
      );
      return;
    }

    // ---------- Warte-/Zuschauer-Zustände ----------
    const status =
      v.phase === "drop-ergebnis"
        ? html`💰 Die Falltüren fallen …`
        : v.phase === "schaetz-ergebnis"
          ? html`⚖️ Wer ist am nächsten dran?`
          : v.phase === "buzzer"
            ? html`👀 Finale läuft — ${v.answeredCount}/2
              Antworten.${
                (v.deineWette ?? null) !== null
                  ? html`<br /><span class="muted"
                        >Deine Wette: ${info(fx, v.deineWette ?? null).name} 🚩</span
                      >`
                  : ""
              }`
            : v.phase === "buzzer-ergebnis"
              ? v.letzteBuzzerFrage?.gewinner != null
                ? html`⚡ Punkt für
                    <strong>${info(fx, v.letzteBuzzerFrage.gewinner).name}</strong>!`
                : html`Niemand richtig — nächste Frage!`
              : v.phase === "showdown"
                ? html`⚖️ Die ultimative Schätzfrage entscheidet …`
                : html`👑 Die Krönung …`;
    render(
      html`<div class="ga-player">
        <div class="ga-status">${status}</div>
        ${
          v.phase === "buzzer" && (v.zuschauerOptionen ?? null) !== null
            ? html`<p class="ga-frage-klein muted">${v.text ?? ""}</p>`
            : ""
        }
      </div>`,
      host,
    );
  },

  explainCard: {
    text: "Das 3-Stufen-Finale im goldenen Tempel: 1) Money-Drop — 10 Chips auf 4 Türen, Einsatz = 50 % deines ECHTEN Kontos, richtige Tür ×2! 2) Schätz-Showdown — die 2 Nächsten werden Finalisten, der Rest wettet. 3) Buzzer-Best-of-3 — der Sieger nimmt 20 % der Konten ALLER mit!",
    animation: html`<span style="font-size:3rem">🐵✨💰⚖️⚡👑</span>`,
  },
};

// Erklär-Demo (ADDITIV): das 3-Stufen-Finale im Schnelldurchlauf —
// Money-Drop → Schätz-Showdown → Buzzer-Finale → Krone.
export const demoChoreo: import("../demo-typen").DemoChoreo = {
  dauer: 11800,
  beats: [
    {
      at: 0,
      requisiten: [
        { art: "schild", text: "STUFE 1: Money-Drop", ton: "gold" },
        { art: "tueren", chipsA: [4, 3, 3, 0], chipsB: [0, 0, 10, 0] },
      ],
      pose: { a: "zeig", b: "zeig" },
      gesicht: { a: "denk", b: "denk" },
      blase: { wer: "a", text: "Einsatz: 50 % vom ECHTEN Konto!" },
      sound: "money-klein",
    },
    {
      at: 2800,
      requisiten: [
        { art: "schild", text: "STUFE 1: Money-Drop", ton: "gold" },
        { art: "tueren", chipsA: [4, 3, 3, 0], chipsB: [0, 0, 10, 0], offen: 2 },
      ],
      pose: { a: "idle", b: "jubel" },
      gesicht: { a: "neutral", b: "jubel" },
      blase: { wer: "b", text: "Richtige Tür = ×2!" },
      sound: "money-mittel",
    },
    {
      at: 5000,
      requisiten: [
        { art: "schild", text: "STUFE 2: Schätz-Showdown", ton: "gold" },
        { art: "slider", wert: 0.55, markerA: 0.4, markerB: 0.7 },
      ],
      pose: { a: "denk", b: "denk" },
      gesicht: { a: "denk", b: "denk" },
    },
    {
      at: 7200,
      requisiten: [
        { art: "schild", text: "STUFE 3: Buzzer-Finale", ton: "gold" },
        { art: "buzzer", gedrueckt: "a" },
      ],
      pose: { a: "buzz", b: "denk" },
      gesicht: { a: "jubel", b: "denk" },
      blase: { wer: "a", text: "Mia buzzert!" },
      sound: "buzzer-hupe",
    },
    {
      at: 9400,
      requisiten: [{ art: "schild", text: "👑 20 % von ALLEN Konten!", ton: "gold", bei: "a" }],
      pose: { a: "jubel", b: "frust" },
      gesicht: { a: "jubel", b: "frust" },
      geldflug: { von: "b", zu: "a" },
      effekt: "konfetti",
      sound: "money-gross",
    },
  ],
};

export default modul;

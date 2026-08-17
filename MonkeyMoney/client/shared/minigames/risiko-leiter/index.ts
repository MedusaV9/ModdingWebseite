// Client-Renderer „Risiko-Leiter": Screen = alle Money-Leitern NEBENEINANDER
// mit kletternden Gelenk-Puppen (Kletter-Animation über die Arm-/Bein-Gruppen
// der Inline-SVGs), inszenierte Absicherungs- (💰-Kassen-Chip) und Absturz-
// Momente (Fall auf die Sicherheitsstufe). Phasen: Entscheidung (WEITER oder
// KASSE) → Stufen-Frage → Aufstiegs-Beat → Leiter-Bilanz.
// Player = XXL-Entscheidungs-Buttons (Weiterklettern/Absichern) + XXL-Antwort-
// Buttons für aktive Kletterer; Abgesicherte/Abgestürzte raten charmant als
// Zuschauer mit (Optionen ohne Draht).
import { html, render } from "lit-html";
import { RISIKO_LEITER_ID } from "../../../../shared/minigames/risiko-leiter.meta";
import { formatMM } from "../../../../shared/money";
import { timerBalken } from "../../ui";
import type { FxApi, MinigameClientModule, SendAction } from "../types";
import "./risiko-leiter.css";

const DEKO = [
  { buchstabe: "A", emoji: "🍌", farbe: "#e6b830" },
  { buchstabe: "B", emoji: "🥥", farbe: "#8a5a3b" },
  { buchstabe: "C", emoji: "🐒", farbe: "#d1495b" },
  { buchstabe: "D", emoji: "🌴", farbe: "#2e8b57" },
] as const;

interface RlLeiterEintrag {
  stufe: number;
  status: "klettert" | "abgesichert" | "abgestuerzt" | "gipfel";
  gutschrift: number | null;
  endeAufStufe: number | null;
  verbunden: boolean;
}

interface RlView {
  questionId: string;
  frageNonce: number;
  phase: "entscheidung" | "frage" | "aufstieg" | "ergebnis";
  endsAt: number;
  timerMs: number;
  stufeNr: number;
  stufen: number;
  leiter: number[];
  sicherheitsStufe: number;
  jackpotBonus: number;
  spieler: string[];
  leitern: Record<string, RlLeiterEintrag>;
  text: string | null;
  options: string[] | null;
  schwierigkeit: string | null;
  entschiedenCount: number;
  klettererCount: number;
  answeredCount: number;
  letzterBeat: {
    stufeNr: number;
    optionen: string[];
    correctIndex: number;
    erklaerung: string;
    ereignisse: Record<string, "aufstieg" | "gipfel" | "absturz">;
    antworten: Record<string, { choice: number | null; nachMs: number | null }>;
  } | null;
  ergebnis: { uebersprungen: boolean; gipfelstuermer: string[] } | null;
  finished: boolean;
  duKletterst?: boolean;
  deinStatus?: "klettert" | "abgesichert" | "abgestuerzt" | "gipfel" | null;
  deineStufe?: number | null;
  deinStand?: number | null;
  naechsterWert?: number | null;
  deinSicherheitsWert?: number | null;
  deineGutschrift?: number | null;
  deineWahl?: "weiter" | "absichern" | null;
  yourChoice?: number | null;
  zuschauerOptionen?: string[] | null;
  aufloesung: {
    correctIndex: number | null;
    erklaerung: string;
    perPlayer: {
      playerId: string;
      choice: null;
      correct: boolean;
      delta: number;
      stufe: number;
      status: string;
    }[];
  } | null;
}

function info(fx: FxApi | undefined, playerId: string): { name: string; avatar: string } {
  const s = fx?.spieler?.(playerId);
  return { name: s?.name ?? playerId, avatar: s?.avatar ?? "gelb" };
}

const STATUS_LABEL: Record<RlLeiterEintrag["status"], string> = {
  klettert: "",
  abgesichert: "💰 Kasse",
  abgestuerzt: "🪂 Absturz",
  gipfel: "👑 GIPFEL",
};

/** Eine Spieler-Leiter: 8 Sprossen, Puppe auf der aktuellen Stufe. */
function leiterSpalte(fx: FxApi, v: RlView, playerId: string) {
  const k = v.leitern[playerId];
  const i = info(fx, playerId);
  const beat = v.phase === "aufstieg" ? (v.letzterBeat?.ereignisse[playerId] ?? null) : null;
  // Anzeige-Stufe: beim Absturz sitzt die Puppe schon auf der Sicherheits-
  // stufe — der Fall wird über die CSS-Transition + Wackel-Animation erzählt.
  const zeigStufe =
    k.status === "abgestuerzt" ? ((k.gutschrift ?? 0) > 0 ? v.sicherheitsStufe : 0) : k.stufe;
  const klasse =
    beat === "absturz"
      ? "stuerzt"
      : beat === "gipfel"
        ? "gipfelt"
        : beat === "aufstieg"
          ? "klettert-hoch"
          : k.status === "klettert"
            ? "klettert"
            : k.status;
  return html`<div class="rl-spalte ${klasse}">
    <div class="rl-leiter">
      ${v.leiter.map(
        (_, idx) =>
          html`<span
            class="rl-sprosse ${idx + 1 === v.sicherheitsStufe ? "sicher" : ""} ${
              idx + 1 <= zeigStufe ? "erklommen" : ""
            } ${idx + 1 === v.stufeNr && k.status === "klettert" ? "aktiv" : ""}"
          ></span>`,
      )}
      <div class="rl-puppe-anker" style="--stufe:${zeigStufe};--stufen:${v.stufen}">
        <span
          class="rl-puppe mm-affe"
          data-avatar=${i.avatar}
          data-gesicht=${
            beat === "absturz"
              ? "frust"
              : beat === "gipfel" || k.status === "gipfel" || k.status === "abgesichert"
                ? "jubel"
                : v.phase === "frage" && k.status === "klettert"
                  ? "denk"
                  : "neutral"
          }
        ></span>
      </div>
    </div>
    <div class="rl-schild ${k.status}">
      <span class="rl-name">${i.name}${k.verbunden ? "" : " 🔌"}</span>
      <span class="rl-stand">
        ${
          k.status === "klettert"
            ? formatMM(k.stufe > 0 ? v.leiter[k.stufe - 1] : 0)
            : html`${STATUS_LABEL[k.status]} ${formatMM(k.gutschrift ?? 0)}`
        }
      </span>
    </div>
  </div>`;
}

/** Die Wert-Skala links neben den Leitern (einmal für alle). */
function wertSkala(v: RlView) {
  return html`<div class="rl-skala">
    ${v.leiter.map(
      (wert, idx) =>
        html`<span
          class="rl-skala-wert ${idx + 1 === v.sicherheitsStufe ? "sicher" : ""} ${
            idx + 1 === v.stufeNr ? "aktiv" : ""
          }"
        >
          ${idx + 1 === v.stufen ? html`👑 ${formatMM(wert)}` : formatMM(wert)}
        </span>`,
    )}
  </div>`;
}

function buehne(fx: FxApi, v: RlView) {
  return html`<div class="rl-buehne">
    ${wertSkala(v)} ${v.spieler.map((p) => leiterSpalte(fx, v, p))}
  </div>`;
}

// Phasen-Beats: pro Phase/Nonce EIN Sound (Edge-Detection über den Key).
let letzterSoundKey = "";
function beatSound(v: RlView, fx: FxApi): void {
  const key = `${v.phase}:${v.frageNonce}:${v.stufeNr}`;
  if (key === letzterSoundKey) return;
  letzterSoundKey = key;
  if (v.phase === "entscheidung") fx.sound("karte-slide");
  if (v.phase === "frage") fx.sound("frage-ein");
  if (v.phase === "aufstieg" && v.letzterBeat !== null) {
    const ereignisse = Object.values(v.letzterBeat.ereignisse);
    if (ereignisse.includes("gipfel")) {
      fx.sound("sieg-fanfare");
      fx.partikel?.("money-regen", { anzahl: 40 });
    } else if (ereignisse.includes("absturz")) fx.sound("falsch");
    else if (ereignisse.length > 0) fx.sound("richtig");
  }
  if (v.phase === "ergebnis") fx.sound("runden-sieg");
}

const modul: MinigameClientModule = {
  id: RISIKO_LEITER_ID,

  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void {
    const v = view as RlView;
    beatSound(v, fx);

    if (v.aufloesung || v.phase === "ergebnis") {
      render(
        html`<div class="rl-screen">
          <div class="rl-kopf"><span class="rl-badge">🪜 RISIKO-LEITER</span></div>
          ${
            v.ergebnis?.uebersprungen === true
              ? html`<h2 class="rl-titel">Leiter übersprungen — keine Zahlungen.</h2>`
              : (v.ergebnis?.gipfelstuermer.length ?? 0) > 0
                ? html`<h2 class="rl-titel">
                    👑 GIPFEL!
                    ${v.ergebnis?.gipfelstuermer.map((p) => info(fx, p).name).join(" & ")} holt
                    ${formatMM(v.leiter[v.stufen - 1])} + ${formatMM(v.jackpotBonus)} Bonus!
                  </h2>`
                : html`<h2 class="rl-titel">Leiter-Bilanz</h2>`
          }
          ${buehne(fx, v)}
          ${
            v.aufloesung
              ? html`<div class="rl-bilanz-liste">
                  ${[...v.aufloesung.perPlayer]
                    .sort((x, y) => y.delta - x.delta)
                    .map(
                      (r) =>
                        html`<div class="rl-bilanz-zeile ${r.delta > 0 ? "plus" : ""}">
                          <span class="rl-mini mm-affe" data-avatar=${info(fx, r.playerId).avatar}>
                          </span>
                          <span>${info(fx, r.playerId).name}</span>
                          <span class="muted">
                            ${
                              r.status === "gipfel"
                                ? "👑 Gipfel + Jackpot-Bonus"
                                : r.status === "abgesichert"
                                  ? `💰 Kasse auf Stufe ${r.stufe}`
                                  : r.status === "abgestuerzt"
                                    ? "🪂 Absturz auf die Sicherheitsstufe"
                                    : "—"
                            }
                          </span>
                          <strong class="mm-money-zahl">+${formatMM(r.delta)}</strong>
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

    if (v.phase === "entscheidung") {
      render(
        html`<div class="rl-screen">
          <div class="rl-kopf">
            <span class="rl-badge">🪜 STUFE ${v.stufeNr}/${v.stufen}</span>
            <span class="muted">
              ${v.entschiedenCount}/${v.klettererCount} entschieden · Sicherheitsstufe
              ${v.sicherheitsStufe} = ${formatMM(v.leiter[v.sicherheitsStufe - 1])}
            </span>
          </div>
          <h2 class="rl-titel">
            WEITERKLETTERN zu <strong>${formatMM(v.leiter[v.stufeNr - 1])}</strong> — oder KASSE
            machen?
          </h2>
          ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())} ${buehne(fx, v)}
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "frage") {
      render(
        html`<div class="rl-screen kompakt">
          <div class="rl-kopf">
            <span class="rl-badge"
              >🪜 STUFE ${v.stufeNr}/${v.stufen} · ${formatMM(v.leiter[v.stufeNr - 1])}</span
            >
            <span class="muted">${v.answeredCount}/${v.klettererCount} Antworten</span>
          </div>
          <h2 class="rl-frage">${v.text ?? ""}</h2>
          ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())}
          <div class="rl-optionen">
            ${(v.options ?? []).map(
              (opt, i) =>
                html`<div class="rl-option" style="--deko:${DEKO[i].farbe}">
                  <span class="rl-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                  ${opt}
                </div>`,
            )}
          </div>
          ${buehne(fx, v)}
        </div>`,
        host,
      );
      return;
    }

    // AUFSTIEGS-Beat: Kletterer steigen, Abstürzer fallen — inszeniert.
    const b = v.letzterBeat;
    render(
      html`<div class="rl-screen">
        <div class="rl-kopf">
          <span class="rl-badge">🪜 AUFSTIEG!</span>
          <span class="muted">
            Richtig war:
            <strong>
              ${
                b !== null
                  ? `${DEKO[b.correctIndex]?.buchstabe ?? "?"} — ${b.optionen[b.correctIndex] ?? ""}`
                  : "?"
              }
            </strong>
          </span>
        </div>
        ${
          b !== null && b.erklaerung.length > 0
            ? html`<p class="rl-erklaerung muted">${b.erklaerung}</p>`
            : ""
        }
        ${buehne(fx, v)}
      </div>`,
      host,
    );
  },

  renderPlayer(view: unknown, host: HTMLElement, send: SendAction, fx?: FxApi): void {
    const v = view as RlView;
    if (v.aufloesung) {
      render(html``, host); // Auflösung rendert die Player-App (kennt „you")
      return;
    }

    const klettert = v.duKletterst === true;

    // ---------- Entscheidung: WEITERKLETTERN oder ABSICHERN (XXL) ----------
    if (v.phase === "entscheidung") {
      if (klettert) {
        const wahl = v.deineWahl ?? null;
        render(
          html`<div class="rl-player">
            <p class="rl-player-titel">
              🪜 Stufe ${v.stufeNr}/${v.stufen} — dein Stand:
              <strong>${formatMM(v.deinStand ?? 0)}</strong>
            </p>
            <button
              class="rl-entscheidung weiter ${wahl === "weiter" ? "gewaehlt" : ""}"
              ?disabled=${wahl !== null}
              @click=${() => {
                fx?.sound("lockin-thunk");
                void send("entscheidung", { wahl: "weiter" });
              }}
            >
              <span class="rl-e-titel">🧗 WEITERKLETTERN</span>
              <span class="rl-e-detail">
                Nächste Stufe: <strong>${formatMM(v.naechsterWert ?? 0)}</strong> · Absturz fällt
                auf ${formatMM(v.deinSicherheitsWert ?? 0)}
              </span>
            </button>
            <button
              class="rl-entscheidung kasse ${wahl === "absichern" ? "gewaehlt" : ""}"
              ?disabled=${wahl !== null}
              @click=${() => {
                fx?.sound("money-mittel");
                void send("entscheidung", { wahl: "absichern" });
              }}
            >
              <span class="rl-e-titel">💰 ABSICHERN</span>
              <span class="rl-e-detail">
                Kasse machen: <strong>+${formatMM(v.deinStand ?? 0)}</strong> — sicher, aber Schluss
              </span>
            </button>
            ${
              wahl !== null
                ? html`<p class="muted" style="text-align:center">
                    ${
                      wahl === "weiter"
                        ? "Eingerastet — gleich kommt die Frage!"
                        : "Kasse gemacht — lehn dich zurück!"
                    }
                  </p>`
                : html`<p class="muted" style="text-align:center">
                    Wer zögert, klettert — Schweigen heißt WEITER!
                  </p>`
            }
          </div>`,
          host,
        );
        return;
      }
      render(
        html`<div class="rl-player">
          <div class="rl-status">
            ${
              v.deinStatus === "abgesichert"
                ? html`💰 Kasse gemacht: <strong>+${formatMM(v.deineGutschrift ?? 0)}</strong> sind
                    dir sicher.<br /><span class="muted">Genieß die Show von der Tribüne!</span>`
                : v.deinStatus === "gipfel"
                  ? html`👑 GIPFEL! <strong>+${formatMM(v.deineGutschrift ?? 0)}</strong> inklusive
                      Jackpot-Bonus!`
                  : html`🪂 Abgestürzt — <strong>+${formatMM(v.deineGutschrift ?? 0)}</strong> von
                      der Sicherheitsstufe.<br /><span class="muted"
                        >Drück den anderen die Daumen!</span
                      >`
            }
          </div>
        </div>`,
        host,
      );
      return;
    }

    // ---------- Stufen-Frage: XXL-Antworten NUR für aktive Kletterer ----------
    if (v.phase === "frage") {
      if (klettert && v.options !== null) {
        const gewaehlt = v.yourChoice ?? null;
        render(
          html`<div class="rl-player">
            <p class="rl-frage-klein">${v.text ?? ""}</p>
            ${v.options.map(
              (opt, i) =>
                html`<button
                  class="rl-button ${gewaehlt === i ? "gewaehlt" : ""} ${
                    gewaehlt !== null ? "gesperrt" : ""
                  }"
                  style="--deko:${DEKO[i].farbe}"
                  ?disabled=${gewaehlt !== null}
                  @click=${() => {
                    fx?.sound("lockin-thunk");
                    void send("answer", { choice: i });
                  }}
                >
                  <span class="rl-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                  ${opt}
                </button>`,
            )}
            ${
              gewaehlt !== null
                ? html`<p class="muted" style="text-align:center">
                    Eingerastet — Daumen drücken für den Aufstieg!
                  </p>`
                : html`<p class="muted" style="text-align:center">
                    ⚠️ Falsch = Absturz auf ${formatMM(v.deinSicherheitsWert ?? 0)}!
                  </p>`
            }
          </div>`,
          host,
        );
        return;
      }
      // Zuschauer: charmant mitraten (Optionen ohne Draht).
      render(
        html`<div class="rl-player">
          <div class="rl-status">
            👀 ${v.answeredCount}/${v.klettererCount} Kletterer haben geantwortet.<br />
            <span class="muted">Rate im Kopf mit!</span>
          </div>
          <p class="rl-frage-klein muted">${v.text ?? ""}</p>
          ${(v.zuschauerOptionen ?? []).map(
            (opt, i) =>
              html`<div class="rl-zuschauer-option" style="--deko:${DEKO[i].farbe}">
                <span class="rl-deko">${DEKO[i].buchstabe}</span> ${opt}
              </div>`,
          )}
        </div>`,
        host,
      );
      return;
    }

    // Aufstieg/Ergebnis: kompakter Status (das eigene Ereignis erzählt deinStatus).
    const b = v.letzterBeat;
    render(
      html`<div class="rl-player">
        <div class="rl-status">
          ${
            v.phase === "aufstieg"
              ? html`Richtig war
                  <strong>${b !== null ? DEKO[b.correctIndex]?.buchstabe : "?"}</strong> —
                  ${
                    v.deinStatus === "klettert"
                      ? html`du kletterst auf <strong>${formatMM(v.deinStand ?? 0)}</strong>! 🧗`
                      : v.deinStatus === "gipfel"
                        ? html`👑 GIPFEL! <strong>+${formatMM(v.deineGutschrift ?? 0)}</strong>!`
                        : v.deinStatus === "abgestuerzt"
                          ? html`🪂 Absturz —
                              <strong>+${formatMM(v.deineGutschrift ?? 0)}</strong> bleiben dir.`
                          : html`deine Kasse ist sicher:
                              <strong>+${formatMM(v.deineGutschrift ?? 0)}</strong>.`
                  }`
              : "🪜 Leiter-Bilanz läuft …"
          }
        </div>
      </div>`,
      host,
    );
  },

  explainCard: {
    text: "Jeder klettert SEINE 8-Stufen-Money-Leiter (100 → 3.000 MM). Vor jeder Frage wählst du: WEITERKLETTERN oder ABSICHERN (Kasse machen = Stand gutgeschrieben, Runde vorbei). Falsche Antwort = Absturz auf die Sicherheitsstufe (Stufe 3 = 400 MM). Wer Stufe 8 knackt, holt 3.000 + Jackpot-Bonus!",
    animation: html`<span style="font-size:3rem">🪜🐒💰🧗👑</span>`,
  },
};

// Erklär-Demo (ADDITIV): Mia klettert mutig bis zum Gipfel, Bo macht früh
// Kasse — dann rutscht ein Beispiel-Absturz auf die Sicherheitsstufe durch.
export const demoChoreo: import("../demo-typen").DemoChoreo = {
  dauer: 11500,
  beats: [
    {
      at: 0,
      requisiten: [{ art: "leiter", stufen: ["100", "400", "1.100", "3.000"] }],
      pose: { a: "zeig", b: "denk" },
      gesicht: { a: "neutral", b: "denk" },
      blase: { wer: "a", text: "8 Stufen — wer traut sich hoch?" },
      sound: "karte-slide",
    },
    {
      at: 2400,
      requisiten: [
        { art: "leiter", stufen: ["100", "400", "1.100", "3.000"] },
        { art: "schild", text: "WEITER oder KASSE?", ton: "cyan" },
      ],
      pose: { a: "huepf", b: "tipp" },
      gesicht: { a: "jubel", b: "neutral" },
      blase: { wer: "b", text: "Ich sichere ab — Kasse!" },
      sound: "lockin-thunk",
    },
    {
      at: 4800,
      requisiten: [
        { art: "frage", tippA: 1, richtig: 1 },
        { art: "schild", text: "💰 Bo: +400 sicher", ton: "gold", bei: "b" },
      ],
      pose: { a: "huepf", b: "idle" },
      gesicht: { a: "jubel", b: "jubel" },
      geldflug: { von: "mitte", zu: "b" },
      sound: "money-mittel",
    },
    {
      at: 7200,
      requisiten: [{ art: "schild", text: "Falsch = Sicherheitsstufe 400!", ton: "rot" }],
      pose: { a: "wackel", b: "duck" },
      gesicht: { a: "denk", b: "neutral" },
      blase: { wer: "a", text: "Risiko … ich klettere weiter!" },
      sound: "trommelwirbel-lang",
    },
    {
      at: 9600,
      requisiten: [
        { art: "leiter", stufen: ["100", "400", "1.100", "3.000"], perfekt: true },
        { art: "schild", text: "👑 Gipfel: 3.000 + Bonus!", ton: "gold", bei: "a" },
      ],
      pose: { a: "jubel", b: "jubel" },
      gesicht: { a: "jubel", b: "jubel" },
      geldflug: { von: "mitte", zu: "a" },
      effekt: "konfetti",
      sound: "sieg-fanfare",
    },
  ],
};

export default modul;

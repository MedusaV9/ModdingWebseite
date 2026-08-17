// Client-Renderer „Duell am Lianensteg" (GAME-DESIGN §2.12/6, Design Nr. 15):
// Screen = der Hängesteg über der Schlucht — zwei Affen-Puppen (FxApi.spieler)
// stehen sich gegenüber, der Duell-Stand SCHIEBT die Puppen aufeinander zu,
// die Wett-Fähnchen der Zuschauer hängen an den Seilen. Phasen: Gegner-Wahl →
// Wett-Fenster (geheim, nur Anzahl) → 3-2-1-Countdown → Speed-Frage →
// Schubs-Beat (Teilfragen-Sieger schubst) → Sieger-Cutscene + Wett-Abrechnung.
// Player = Gegner-Wahl-Grid (nur Herausforderer), Wett-Buttons (Zuschauer),
// XXL-Antwort-Buttons (Duellanten — die Antwort IST der Buzz), Warte-Zustände.
import { html, render } from "lit-html";
import {
  LD_WETTE_MM,
  LIANENSTEG_DUELL_ID,
} from "../../../../shared/minigames/lianensteg-duell.meta";
import { formatMM } from "../../../../shared/money";
import { timerBalken } from "../../ui";
import type { FxApi, MinigameClientModule, SendAction } from "../types";
import "./lianensteg-duell.css";

const DEKO = [
  { buchstabe: "A", emoji: "🍌", farbe: "#e6b830" },
  { buchstabe: "B", emoji: "🥥", farbe: "#8a5a3b" },
  { buchstabe: "C", emoji: "🐒", farbe: "#d1495b" },
  { buchstabe: "D", emoji: "🌴", farbe: "#2e8b57" },
] as const;

interface LdKandidat {
  id: string;
  waehlbar: boolean;
  verbunden: boolean;
  kontostand: number | null;
}

interface LdView {
  questionId: string;
  frageNonce: number;
  phase: "herausforderung" | "wetten" | "countdown" | "frage" | "schubs" | "ergebnis";
  endsAt: number;
  timerMs: number;
  teilfrage: number;
  bestOf: number;
  siegeZiel: number;
  suddenDeath: number;
  herausforderer: string;
  gegner: string | null;
  spieler: string[];
  siege: Record<string, number>;
  stand: number;
  wettenAnzahl: number;
  wetten: Record<string, string> | null;
  wetteMM: number;
  text: string | null;
  options: string[] | null;
  answeredCount: number;
  letzteTeilfrage: {
    correctIndex: number;
    gewinner: string | null;
    fotofinish: boolean;
    antworten: Record<string, { choice: number; nachMs: number }>;
  } | null;
  ergebnis: {
    sieger: string | null;
    verlierer: string | null;
    geteilt: boolean;
    kampflos: boolean;
    abgebrochen: boolean;
    praemie: number;
    transfer: number;
    restAnSieger: number;
  } | null;
  finished: boolean;
  duBistDuellant?: boolean;
  duBistHerausforderer?: boolean;
  yourChoice?: number | null;
  deineWette?: string | null;
  waehlbareGegner?: LdKandidat[] | null;
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

/** Countdown-Ziffer (3-2-1) aus der Server-Zeit — tickt ohne Client-Timer. */
function countdownZiffer(v: LdView, serverNow: number): number {
  return Math.max(1, Math.ceil((v.endsAt - serverNow) / 1_000));
}

/** Duell-Puppe mit Namensschild + Siege-Pips. */
function puppe(
  fx: FxApi | undefined,
  playerId: string | null,
  v: LdView,
  seite: "links" | "rechts",
) {
  const i = info(fx, playerId);
  const siege = playerId !== null ? (v.siege[playerId] ?? 0) : 0;
  return html`<div class="ld-duellant ${seite}">
    <span class="ld-puppe mm-affe mm-affe-idle" data-avatar=${i.avatar}></span>
    <span class="ld-name">${i.name}</span>
    <span class="ld-pips">
      ${Array.from({ length: v.siegeZiel }, (_, k) => html`<span class="ld-pip ${k < siege ? "voll" : ""}"></span>`)}
    </span>
  </div>`;
}

/** Der Hängesteg: Puppen laufen mit dem Stand aufeinander zu, Fähnchen = Wetten. */
function steg(fx: FxApi | undefined, v: LdView) {
  // stand > 0: der Herausforderer drängt den Gegner zurück (und umgekehrt).
  const schub = v.stand * 6;
  return html`<div class="ld-steg">
    <div class="ld-seil oben"></div>
    <div class="ld-planken">
      ${Array.from({ length: 9 }, () => html`<span class="ld-planke"></span>`)}
    </div>
    <div class="ld-seil unten"></div>
    <div class="ld-puppen" style="--schub:${schub}%">
      ${puppe(fx, v.herausforderer, v, "links")} ${puppe(fx, v.gegner, v, "rechts")}
    </div>
    ${
      v.wetten !== null && Object.keys(v.wetten).length > 0
        ? html`<div class="ld-faehnchen">
            ${Object.entries(v.wetten).map(([wetter, auf]) => {
              const w = info(fx, wetter);
              const seite = auf === v.herausforderer ? "links" : "rechts";
              return html`<span class="ld-fahne ${seite}" title="${w.name} wettet">
                🚩 ${w.name} → ${info(fx, auf).name}
              </span>`;
            })}
          </div>`
        : v.wettenAnzahl > 0
          ? html`<div class="ld-faehnchen">
              <span class="ld-fahne geheim"
                >🤫 ${v.wettenAnzahl} geheime Wette${v.wettenAnzahl === 1 ? "" : "n"}</span
              >
            </div>`
          : ""
    }
  </div>`;
}

// Schubs-Beat: pro neuer Teilfrage EIN Sound (Edge-Detection über die Nonce).
let letzterSchubsKey = "";
function schubsSound(v: LdView, fx: FxApi): void {
  if (v.phase !== "schubs" || v.letzteTeilfrage === null) return;
  const key = `${v.frageNonce}:${v.letzteTeilfrage.gewinner ?? "-"}`;
  if (key === letzterSchubsKey) return;
  letzterSchubsKey = key;
  fx.sound(v.letzteTeilfrage.gewinner !== null ? "podium-riss" : "reveal-zap");
}

const modul: MinigameClientModule = {
  id: LIANENSTEG_DUELL_ID,

  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void {
    const v = view as LdView;
    schubsSound(v, fx);

    if (v.aufloesung || v.phase === "ergebnis") {
      const e = v.ergebnis;
      const sieger = info(fx, e?.sieger ?? null);
      render(
        html`<div class="ld-screen">
          <div class="ld-kopf"><span class="ld-badge">🌉 DUELL AM LIANENSTEG</span></div>
          ${
            e?.abgebrochen === true
              ? html`<h2 class="ld-titel">Duell abgebrochen — die Schlucht bleibt still.</h2>`
              : e?.geteilt === true
                ? html`<h2 class="ld-titel">
                    🤝 GETEILTER SIEG! Je ${formatMM(e.praemie)} — Wetten zurück.
                  </h2>`
                : html`<h2 class="ld-titel">
                    🏆 <strong>${sieger.name.toUpperCase()}</strong> hält den Steg!
                  </h2>`
          }
          ${steg(fx, v)}
          ${
            e !== null && e.sieger !== null && !e.abgebrochen
              ? html`<p class="ld-abrechnung">
                  ${formatMM(e.praemie)} aus der
                  Bank${
                    e.transfer > 0
                      ? html` + <strong>${formatMM(e.transfer)}</strong> direkt vom Konto von
                          ${info(fx, e.verlierer).name}`
                      : e.kampflos
                        ? " — kampflos (Gegner offline), Wetten zurück"
                        : ""
                  }${e.restAnSieger > 0 ? html` + ${formatMM(e.restAnSieger)} Wett-Topf-Rest` : ""}
                </p>`
              : ""
          }
          ${
            v.aufloesung
              ? html`<div class="ld-bilanz">
                  ${[...v.aufloesung.perPlayer]
                    .sort((a, b) => b.delta - a.delta)
                    .map(
                      (r) =>
                        html`<div class="ld-bilanz-zeile ${r.correct ? "gewonnen" : ""}">
                          <span
                            class="ld-mini mm-affe"
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

    if (v.phase === "herausforderung") {
      const h = info(fx, v.herausforderer);
      render(
        html`<div class="ld-screen">
          <div class="ld-kopf"><span class="ld-badge">🌉 DUELL AM LIANENSTEG</span></div>
          ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())}
          <div class="ld-wahl">
            <span class="ld-puppe gross mm-affe mm-affe-idle" data-avatar=${h.avatar}></span>
            <h2 class="ld-titel">
              <strong>${h.name.toUpperCase()}</strong> (Letzter im Zwischenstand) fordert heraus …
            </h2>
            <p class="muted">
              Wen schickt er auf den Steg? Der Ärmste ist geschützt — der Führende nie!
            </p>
          </div>
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "wetten") {
      render(
        html`<div class="ld-screen">
          <div class="ld-kopf">
            <span class="ld-badge">🌉 WETTEN, BITTE!</span>
            <span class="muted">${formatMM(v.wetteMM)} auf den Sieger — Topf pari-mutuel</span>
          </div>
          ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())} ${steg(fx, v)}
          <p class="muted" style="text-align:center">
            ${info(fx, v.herausforderer).name} ⚔️ ${info(fx, v.gegner).name} — Best-of-${v.bestOf}.
            Die Zuschauer setzen GEHEIM.
          </p>
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "countdown") {
      render(
        html`<div class="ld-screen">
          ${steg(fx, v)}
          <div class="ld-countdown">${countdownZiffer(v, fx.serverNow())}</div>
          ${
            v.suddenDeath > 0
              ? html`<p class="ld-sudden">☠️ SUDDEN DEATH ${v.suddenDeath}</p>`
              : html`<p class="muted" style="text-align:center">
                  Teilfrage ${v.teilfrage}/${v.bestOf}
                </p>`
          }
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "frage") {
      render(
        html`<div class="ld-screen">
          <div class="ld-kopf">
            <span class="ld-badge"
              >⚔️
              ${v.suddenDeath > 0 ? "SUDDEN DEATH" : `TEILFRAGE ${v.teilfrage}/${v.bestOf}`}</span
            >
            <span class="muted">${v.answeredCount}/2 Antworten</span>
          </div>
          <h2 class="ld-frage">${v.text ?? ""}</h2>
          ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())}
          <div class="ld-optionen">
            ${(v.options ?? []).map(
              (opt, i) =>
                html`<div class="ld-option" style="--deko:${DEKO[i].farbe}">
                  <span class="ld-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                  ${opt}
                </div>`,
            )}
          </div>
          ${steg(fx, v)}
        </div>`,
        host,
      );
      return;
    }

    // SCHUBS: Teilfragen-Ergebnis mit Lösung.
    const t = v.letzteTeilfrage;
    render(
      html`<div class="ld-screen">
        <div class="ld-kopf"><span class="ld-badge">💥 SCHUBS!</span></div>
        <h2 class="ld-titel">
          ${
            t?.gewinner != null
              ? html`<strong>${info(fx, t.gewinner).name.toUpperCase()}</strong> holt den
                  Punkt${t.fotofinish ? " (Fotofinish-Los! 📸)" : ""}`
              : "Beide daneben — der Steg wackelt nur."
          }
        </h2>
        ${
          t !== null
            ? html`<p class="muted" style="text-align:center">
                Richtig war: <strong>${DEKO[t.correctIndex].buchstabe}</strong>
              </p>`
            : ""
        }
        ${steg(fx, v)}
      </div>`,
      host,
    );
  },

  renderPlayer(view: unknown, host: HTMLElement, send: SendAction, fx?: FxApi): void {
    const v = view as LdView;
    if (v.aufloesung) {
      render(html``, host); // Auflösung rendert die Player-App (kennt „you")
      return;
    }

    // ---------- Gegner-Wahl (NUR der Herausforderer) ----------
    if (v.phase === "herausforderung") {
      if (v.duBistHerausforderer === true) {
        render(
          html`<div class="ld-player">
            <h3 class="ld-player-titel">⚔️ DU forderst heraus — wähle deinen Gegner!</h3>
            <div class="ld-gegner-grid">
              ${(v.waehlbareGegner ?? []).map((k) => {
                const i = info(fx, k.id);
                return html`<button
                  class="ld-gegner ${k.waehlbar ? "" : "geschuetzt"}"
                  ?disabled=${!k.waehlbar}
                  @click=${() => {
                    fx?.sound("lockin-thunk");
                    void send("herausfordern", { targetId: k.id });
                  }}
                >
                  <span class="ld-mini mm-affe" data-avatar=${i.avatar}></span>
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
        html`<div class="ld-player">
          <div class="ld-status">
            🌉 <strong>${info(fx, v.herausforderer).name}</strong> wählt den Gegner …<br />
            <span class="muted">Wirst DU auf den Steg geschickt?</span>
          </div>
        </div>`,
        host,
      );
      return;
    }

    const istDuellant = v.duBistDuellant === true;

    // ---------- Wett-Fenster (Zuschauer) ----------
    if (v.phase === "wetten") {
      if (istDuellant) {
        render(
          html`<div class="ld-player">
            <div class="ld-status">
              ⚔️ DU stehst auf dem Steg!<br />
              <span class="muted">Die Zuschauer wetten … mach dich bereit.</span>
            </div>
          </div>`,
          host,
        );
        return;
      }
      if (v.deineWette != null) {
        render(
          html`<div class="ld-player">
            <div class="ld-status">
              🚩 Wette platziert: <strong>${info(fx, v.deineWette).name}</strong><br />
              <span class="muted">Richtige Wetten teilen den Topf — 50/50 zahlt ×2!</span>
            </div>
          </div>`,
          host,
        );
        return;
      }
      render(
        html`<div class="ld-player">
          <h3 class="ld-player-titel">🚩 ${formatMM(LD_WETTE_MM)} auf wen?</h3>
          <div class="ld-wett-grid">
            ${[v.herausforderer, v.gegner].map((d) => {
              if (d === null) return "";
              const i = info(fx, d);
              return html`<button
                class="ld-wett-button"
                @click=${() => {
                  fx?.sound("lockin-thunk");
                  void send("wette", { auf: d });
                }}
              >
                <span class="ld-puppe mm-affe mm-affe-idle" data-avatar=${i.avatar}></span>
                <span>${i.name}</span>
              </button>`;
            })}
          </div>
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "countdown") {
      render(
        html`<div class="ld-player">
          <div class="ld-countdown klein">${countdownZiffer(v, fx?.serverNow() ?? v.endsAt)}</div>
          ${istDuellant ? html`<p class="muted" style="text-align:center">Finger auf die Buttons …</p>` : ""}
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
          html`<div class="ld-player">
            <p class="ld-frage-klein">${v.text ?? ""}</p>
            ${(v.options ?? []).map(
              (opt, i) =>
                html`<button
                  class="ld-button ${gewaehlt === i ? "gewaehlt" : ""} ${gewaehlt !== null ? "gesperrt" : ""}"
                  style="--deko:${DEKO[i].farbe}"
                  ?disabled=${gewaehlt !== null}
                  @click=${() => {
                    fx?.sound("lockin-thunk");
                    void send("answer", { choice: i });
                  }}
                >
                  <span class="ld-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                  ${opt}
                </button>`,
            )}
          </div>`,
          host,
        );
        return;
      }
      render(
        html`<div class="ld-player">
          <div class="ld-status">
            👀 Duell läuft — ${v.answeredCount}/2 Antworten.<br />
            ${
              v.deineWette != null
                ? html`<span class="muted">Deine Wette: ${info(fx, v.deineWette).name} 🚩</span>`
                : html`<span class="muted">Schneller UND richtig gewinnt den Punkt!</span>`
            }
          </div>
          <p class="ld-frage-klein muted">${v.text ?? ""}</p>
        </div>`,
        host,
      );
      return;
    }

    // Schubs/Ergebnis: kompakter Status.
    const t = v.letzteTeilfrage;
    render(
      html`<div class="ld-player">
        <div class="ld-status">
          ${
            v.phase === "schubs"
              ? t?.gewinner != null
                ? html`💥 Punkt für <strong>${info(fx, t.gewinner).name}</strong>!`
                : "Beide daneben — nächste Teilfrage!"
              : v.ergebnis?.geteilt === true
                ? "🤝 Geteilter Sieg!"
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
    text: "1-gegen-1 auf dem Hängesteg: Der Letzte fordert heraus, Best-of-5 Speed-Fragen — wer schneller RICHTIG antwortet, schubst! Alle anderen wetten 50 MM auf den Sieger (Topf wird geteilt). Sieger: 300 MM + 100 MM direkt vom Verlierer.",
    animation: html`<span style="font-size:3rem">🌉🐒⚔️🐒🚩</span>`,
  },
};

// Erklär-Demo (ADDITIV): 1-gegen-1 auf dem Hängesteg — wer schneller RICHTIG
// antwortet, schubst den Gegner.
export const demoChoreo: import("../demo-typen").DemoChoreo = {
  dauer: 11600,
  beats: [
    {
      at: 0,
      requisiten: [
        { art: "steg" },
        { art: "schild", text: "⚔️ 1 gegen 1 — Best of 5", ton: "cyan" },
      ],
      pose: { a: "wackel", b: "wackel" },
      gesicht: { a: "neutral", b: "neutral" },
    },
    {
      at: 2600,
      requisiten: [{ art: "steg" }, { art: "frage" }],
      pose: { a: "denk", b: "denk" },
      gesicht: { a: "denk", b: "denk" },
      blase: { wer: "a", text: "Speed-Frage!" },
    },
    {
      at: 4800,
      requisiten: [{ art: "steg" }, { art: "frage", tippA: 0 }],
      pose: { a: "buzz", b: "denk" },
      gesicht: { a: "jubel", b: "denk" },
      blase: { wer: "a", text: "Mia ist schneller!" },
      sound: "buzzer-hupe",
    },
    {
      at: 6800,
      requisiten: [
        { art: "steg" },
        { art: "frage", tippA: 0, richtig: 0 },
        { art: "schild", text: "SCHUBS!", ton: "rot" },
      ],
      pose: { a: "zeig", b: "fall" },
      gesicht: { a: "jubel", b: "frust" },
      sound: "podium-riss",
    },
    {
      at: 9000,
      requisiten: [
        { art: "steg" },
        { art: "schild", text: "+300 MM + Wett-Topf", ton: "gold", bei: "a" },
      ],
      pose: { a: "jubel", b: "fall" },
      gesicht: { a: "jubel", b: "frust" },
      geldflug: { von: "mitte", zu: "a" },
      effekt: "konfetti",
      sound: "money-mittel",
    },
  ],
};

export default modul;

// Client-Renderer „Die große Bananen-Tortenschlacht": Screen = Sitzkreis mit
// Affen-Puppen (FxApi.spieler) — in der Wurf-Phase fliegen die Torten ECHT
// (CSS-Flug von Werfer-Slot zu Ziel-Slot, gestaffelt in Wurf-Reihenfolge,
// Klatsch-Splat + Sound). Getroffene tragen sichtbar Sahne-Schichten 1/2/3
// (CSS-Overlay auf der Puppe), 3 Schichten = RAUS (Puppe grau + Torten-Deckel).
// Player = XXL-Antwort-Buttons (Aktive), geheimes Ziel-Grid (nur Werfer),
// Ehrentribüne für Rausgeflogene.
import { html, render } from "lit-html";
import { formatMM } from "../../../../shared/money";
import {
  TORTENSCHLACHT_ID,
  TS_TORTEN_RAUS,
} from "../../../../shared/minigames/bananen-tortenschlacht.meta";
import { timerBalken } from "../../ui";
import type { FxApi, MinigameClientModule, SendAction } from "../types";
import "./bananen-tortenschlacht.css";

const DEKO = [
  { buchstabe: "A", emoji: "🍌", farbe: "#e6b830" },
  { buchstabe: "B", emoji: "🥥", farbe: "#8a5a3b" },
  { buchstabe: "C", emoji: "🐒", farbe: "#d1495b" },
  { buchstabe: "D", emoji: "🌴", farbe: "#2e8b57" },
] as const;

interface TsWurfView {
  von: string;
  zu: string;
  schicht: number;
  raus: boolean;
}

interface TsView {
  questionId: string;
  frageNonce: number;
  phase: "frage" | "zielwahl" | "wurf" | "niemand" | "ergebnis";
  endsAt: number;
  timerMs: number;
  spieler: string[];
  verbunden: Record<string, boolean>;
  torten: Record<string, number>;
  tortenRaus: number;
  raus: string[];
  text: string | null;
  options: string[] | null;
  answeredCount: number;
  aktiveAnzahl: number;
  werfer: string[];
  wuerfe: TsWurfView[];
  sieger: string[];
  siegerGrund: "letzter-sauberer" | "punktsieg" | "leergefegt" | null;
  topf: number;
  finished: boolean;
  you?: string | null;
  duBistRaus?: boolean;
  deineTorten?: number;
  yourChoice?: number | null;
  istWerfer?: boolean;
  ziele?: { id: string; torten: number; verbunden: boolean }[] | null;
  deinZielGewaehlt?: boolean;
  aufloesung: {
    correctIndex: number;
    erklaerung: string;
    sieger: string[];
    perPlayer: {
      playerId: string;
      choice: null;
      correct: boolean;
      delta: number;
      torten: number;
      rausAls: number | null;
    }[];
  } | null;
}

function info(fx: FxApi | undefined, playerId: string | null): { name: string; avatar: string } {
  if (playerId === null) return { name: "—", avatar: "gelb" };
  const s = fx?.spieler?.(playerId);
  return { name: s?.name ?? playerId, avatar: s?.avatar ?? "gelb" };
}

/** Slot-Position im Sitzkreis (Ellipse), Prozent-Koordinaten fürs CSS. */
function slotPosition(index: number, anzahl: number): { x: number; y: number } {
  const winkel = (index / Math.max(1, anzahl)) * 2 * Math.PI - Math.PI / 2;
  return { x: 50 + 40 * Math.cos(winkel), y: 50 + 36 * Math.sin(winkel) };
}

/** Der Sitzkreis: Puppen mit Sahne-Schichten, Torten-Flüge in der Wurf-Phase.
 * W4-Inszenierung: die Wurf-Salve schüttelt den Kreis (dezenter Screen-Shake
 * pro Einschlag), Sieger jubeln mit Armen hoch (Gelenk-Rotation via jubel). */
function sitzkreis(fx: FxApi, v: TsView) {
  const pos = new Map(v.spieler.map((p, i) => [p, slotPosition(i, v.spieler.length)]));
  const bebt = v.phase === "wurf" && v.wuerfe.length > 0;
  return html`<div class="ts-kreis ${bebt ? "bebt" : ""}" style="--salven:${v.wuerfe.length}">
    ${v.spieler.map((p) => {
      const xy = pos.get(p)!;
      const i = info(fx, p);
      const torten = v.torten[p] ?? 0;
      const raus = v.raus.includes(p);
      const wirft = v.werfer.includes(p) && (v.phase === "zielwahl" || v.phase === "wurf");
      const siegt = v.phase === "ergebnis" && v.sieger.includes(p);
      return html`<div
        class="ts-slot ${raus ? "raus" : ""} ${wirft ? "wirft" : ""} ${siegt ? "sieger-pose" : ""} ${v.verbunden[p] ? "" : "offline"}"
        style="left:${xy.x}%;top:${xy.y}%"
        data-spieler=${p}
      >
        <span class="ts-puppe-wrap">
          <span
            class="ts-puppe mm-affe"
            data-avatar=${i.avatar}
            data-gesicht=${siegt ? "jubel" : raus ? "frust" : wirft ? "jubel" : "neutral"}
          ></span>
          ${siegt ? html`<span class="ts-sieger-krone">👑</span>` : ""}
          ${Array.from(
            { length: Math.min(torten, TS_TORTEN_RAUS) },
            (_, k) => html`<span class="ts-sahne s${k + 1}"></span>`,
          )}
          ${wirft ? html`<span class="ts-torte-in-hand">🥧</span>` : ""}
          ${raus ? html`<span class="ts-raus-deckel">🥧 RAUS</span>` : ""}
        </span>
        <span class="ts-name">${i.name}</span>
        <span class="ts-schichten">
          ${Array.from(
            { length: v.tortenRaus },
            (_, k) => html`<span class="ts-pip ${k < torten ? "voll" : ""}"></span>`,
          )}
        </span>
      </div>`;
    })}
    ${
      v.phase === "wurf"
        ? v.wuerfe.map((w, i) => {
            const von = pos.get(w.von) ?? { x: 50, y: 50 };
            const zu = pos.get(w.zu) ?? { x: 50, y: 50 };
            return html`<span
                class="ts-torte-flug"
                style="--von-x:${von.x}%;--von-y:${von.y}%;--zu-x:${zu.x}%;--zu-y:${zu.y}%;--i:${i}"
                >🥧</span
              >
              <span
                class="ts-splat ${w.raus ? "voll" : ""}"
                style="left:${zu.x}%;top:${zu.y}%;--i:${i}"
                >${w.raus ? "💥" : "🍥"}</span
              >`;
          })
        : ""
    }
  </div>`;
}

// Wurf-/Sieger-Beat: pro Salve/Ergebnis EIN Sound (Edge-Detection über Nonce).
let letzterSoundKey = "";
function beatSound(v: TsView, fx: FxApi): void {
  const key = `${v.phase}:${v.frageNonce}:${v.wuerfe.length}`;
  if (key === letzterSoundKey) return;
  letzterSoundKey = key;
  if (v.phase === "wurf" && v.wuerfe.length > 0) {
    fx.sound(v.wuerfe.some((w) => w.raus) ? "stinkbanane-platzt" : "matsch-treffer");
  }
  if (v.phase === "ergebnis" && v.sieger.length > 0) fx.sound("sieg-fanfare");
}

const modul: MinigameClientModule = {
  id: TORTENSCHLACHT_ID,

  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void {
    const v = view as TsView;
    beatSound(v, fx);

    if (v.aufloesung) {
      render(
        html`<div class="ts-screen">
          <div class="ts-kopf"><span class="ts-badge">🥧 TORTENSCHLACHT VORBEI</span></div>
          <p class="muted" style="text-align:center">${v.aufloesung.erklaerung}</p>
          <div class="ts-bilanz">
            ${[...v.aufloesung.perPlayer]
              .sort((a, b) => b.delta - a.delta)
              .map(
                (r) =>
                  html`<div class="ts-bilanz-zeile ${r.correct ? "sieger" : ""}">
                    <span class="ts-mini mm-affe" data-avatar=${info(fx, r.playerId).avatar}></span>
                    <span>${info(fx, r.playerId).name}</span>
                    <span class="muted">
                      ${
                        r.correct
                          ? "🏆 sauber geblieben"
                          : r.rausAls !== null
                            ? `🥧 raus als ${r.rausAls}.`
                            : `${r.torten}× Sahne überlebt`
                      }
                    </span>
                    <strong class="mm-money-zahl" style="color:var(--gold)">
                      +${formatMM(r.delta)}
                    </strong>
                  </div>`,
              )}
          </div>
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "frage") {
      render(
        html`<div class="ts-screen">
          <div class="ts-kopf">
            <span class="ts-badge">🥧 BANANEN-TORTENSCHLACHT</span>
            <span class="muted">
              ${v.aktiveAnzahl} Affen sauber im Ring · Topf ${formatMM(v.topf)}
            </span>
          </div>
          <h2 class="ts-frage">${v.text ?? ""}</h2>
          ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())}
          <div class="ts-optionen">
            ${(v.options ?? []).map(
              (opt, i) =>
                html`<div class="ts-option" style="--deko:${DEKO[i].farbe}">
                  <span class="ts-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                  ${opt}
                </div>`,
            )}
          </div>
          ${sitzkreis(fx, v)}
          <p class="muted" style="text-align:center">
            ${v.answeredCount} Antwort${v.answeredCount === 1 ? "" : "en"} — wer richtig liegt,
            WIRFT!
          </p>
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "zielwahl") {
      render(
        html`<div class="ts-screen">
          <div class="ts-kopf"><span class="ts-badge">🥧 TORTEN GELADEN!</span></div>
          <h2 class="ts-titel">
            ${v.werfer.length} Werfer wähl${v.werfer.length === 1 ? "t" : "en"} GEHEIM ein Ziel …
          </h2>
          ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())} ${sitzkreis(fx, v)}
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "wurf") {
      render(
        html`<div class="ts-screen">
          <div class="ts-kopf"><span class="ts-badge">💥 SAHNE FREI!</span></div>
          ${sitzkreis(fx, v)}
          <div class="ts-ticker">
            ${v.wuerfe.map(
              (w) =>
                html`<span class="ts-ticker-eintrag ${w.raus ? "raus" : ""}">
                  ${info(fx, w.von).name} 🥧→ ${info(fx, w.zu).name}
                  ${w.raus ? "— 3. TORTE, RAUS!" : `(Schicht ${w.schicht})`}
                </span>`,
            )}
            ${
              v.wuerfe.length === 0
                ? html`<span class="ts-ticker-eintrag">Alle Torten verfallen …</span>`
                : ""
            }
          </div>
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "niemand") {
      render(
        html`<div class="ts-screen">
          <div class="ts-kopf"><span class="ts-badge">🥧 BANANEN-TORTENSCHLACHT</span></div>
          <h2 class="ts-titel">Niemand richtig — die Torten bleiben im Kühlschrank!</h2>
          ${sitzkreis(fx, v)}
        </div>`,
        host,
      );
      return;
    }

    // Phase "ergebnis": Sieger-Beat.
    const siegerNamen = v.sieger.map((s) => info(fx, s).name.toUpperCase()).join(" & ");
    render(
      html`<div class="ts-screen">
        <div class="ts-kopf"><span class="ts-badge">🏆 SIEGER-SAHNE</span></div>
        <h2 class="ts-titel">
          ${
            v.sieger.length > 0
              ? html`<strong>${siegerNamen}</strong> ${
                    v.siegerGrund === "punktsieg"
                      ? html`gewinnt per PUNKTSIEG den Topf (${formatMM(v.topf)})!`
                      : v.siegerGrund === "leergefegt"
                        ? html`fiel als LETZTER — und gewinnt den Topf (${formatMM(v.topf)})!`
                        : html`ist der letzte SAUBERE Affe — Topf: ${formatMM(v.topf)}!`
                  }`
              : "Keine Sieger diese Runde."
          }
        </h2>
        ${sitzkreis(fx, v)}
      </div>`,
      host,
    );
  },

  renderPlayer(view: unknown, host: HTMLElement, send: SendAction, fx?: FxApi): void {
    const v = view as TsView;
    if (v.aufloesung) {
      render(html``, host); // Auflösung rendert die Player-App (kennt „you")
      return;
    }

    // Rausgeflogene: Ehrentribüne (kein Antwort-/Wurf-Zugriff mehr).
    if (v.duBistRaus === true) {
      render(
        html`<div class="ts-verdeckt">
          <span style="font-size:5rem">🥧😵</span>
          <h2>Du bist voll Sahne — RAUS!</h2>
          <p class="muted">
            Ehrentribüne: Trost-Money gibt's am Ende — je länger du standest, desto mehr.
          </p>
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "frage") {
      const gewaehlt = v.yourChoice ?? null;
      render(
        html`<div class="ts-player">
          <p class="ts-warnung">
            🥧 ${"🥧".repeat(Math.max(0, v.deineTorten ?? 0))} Richtig = DU wirfst. Falsch = duck
            dich!
          </p>
          <p class="ts-frage-klein">${v.text ?? ""}</p>
          ${(v.options ?? []).map(
            (opt, i) =>
              html`<button
                class="ts-button ${gewaehlt === i ? "gewaehlt" : ""} ${gewaehlt !== null ? "gesperrt" : ""}"
                style="--deko:${DEKO[i].farbe}"
                ?disabled=${gewaehlt !== null}
                @click=${() => {
                  fx?.sound("lockin-thunk");
                  void send("answer", { choice: i });
                }}
              >
                <span class="ts-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                ${opt}
              </button>`,
          )}
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "zielwahl") {
      if (v.istWerfer === true && v.ziele) {
        if (v.deinZielGewaehlt === true) {
          render(
            html`<div class="ts-verdeckt">
              <span style="font-size:5rem">🥧🤫</span>
              <h2>Ziel eingerastet!</h2>
              <p class="muted">Die Torte fliegt, sobald alle Werfer gewählt haben …</p>
            </div>`,
            host,
          );
          return;
        }
        render(
          html`<div class="ts-player">
            <h2 style="text-align:center">🥧 Wen tortest du?</h2>
            <p class="muted" style="text-align:center">
              Geheime Wahl — 3 Torten und der Affe ist raus! Timeout wirft auf den Saubersten.
            </p>
            ${v.ziele.map((z) => {
              const i = info(fx, z.id);
              return html`<button
                class="ts-ziel"
                @click=${() => {
                  fx?.sound("lockin-thunk");
                  void send("wurf", { targetId: z.id });
                }}
              >
                <span class="ts-ziel-wer">
                  <span class="ts-ziel-puppe mm-affe" data-avatar=${i.avatar}></span>
                  ${i.name} ${z.verbunden ? "" : "📴"}
                </span>
                <span class="ts-ziel-torten"
                  >${"🥧".repeat(z.torten)}${z.torten === 0 ? "sauber" : ""}</span
                >
              </button>`;
            })}
          </div>`,
          host,
        );
        return;
      }
      render(
        html`<div class="ts-verdeckt">
          <span style="font-size:5rem">🙈</span>
          <h2>Die Werfer zielen …</h2>
          <p class="muted">Duck dich — vielleicht bist DU das Ziel!</p>
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "wurf") {
      const du = v.you ?? null;
      const getroffen = du !== null && v.wuerfe.some((w) => w.zu === du);
      const geworfen = du !== null && v.wuerfe.some((w) => w.von === du);
      render(
        html`<div class="ts-verdeckt">
          <span style="font-size:5rem">${getroffen ? "🥧😖" : geworfen ? "🥧😈" : "🍿"}</span>
          <h2>
            ${
              getroffen
                ? "KLATSCH! Du hast Sahne im Gesicht!"
                : geworfen
                  ? "Deine Torte fliegt!"
                  : "Die Torten fliegen …"
            }
          </h2>
          ${
            getroffen
              ? html`<p class="muted">
                  Schicht ${v.torten[du] ?? 0} von ${v.tortenRaus} —
                  ${(v.torten[du] ?? 0) >= v.tortenRaus ? "das war's!" : "noch stehst du!"}
                </p>`
              : ""
          }
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "niemand") {
      render(
        html`<div class="ts-verdeckt">
          <span style="font-size:5rem">🥧❄️</span>
          <h2>Niemand richtig — keine Torte fliegt.</h2>
        </div>`,
        host,
      );
      return;
    }

    // Phase "ergebnis".
    const duSieger = v.you != null && v.sieger.includes(v.you);
    render(
      html`<div class="ts-verdeckt">
        <span style="font-size:5rem">${duSieger ? "🏆🥧" : "👏"}</span>
        <h2>
          ${
            duSieger
              ? `Sauber geblieben — der Topf (${formatMM(v.topf)}) gehört dir!`
              : "Die Schlacht ist geschlagen!"
          }
        </h2>
      </div>`,
      host,
    );
  },

  explainCard: {
    text: "Jede Frage geht an ALLE: Wer richtig liegt, wirft eine Sahnetorte auf einen Wunsch-Gegner (geheime Ziel-Wahl). 3 Torten im Gesicht = raus (Trost-Money nach Überlebensdauer). Der letzte saubere Affe gewinnt den Topf!",
    animation: html`<span style="font-size:3rem">🥧🐒💥🏆</span>`,
  },
};

// Erklär-Demo (ADDITIV): Mia antwortet richtig, tortet Bo — bei der dritten
// Schicht fliegt Bo raus und Mia holt den Topf.
export const demoChoreo: import("../demo-typen").DemoChoreo = {
  dauer: 11800,
  beats: [
    {
      at: 0,
      requisiten: [{ art: "frage" }],
      pose: { a: "denk", b: "denk" },
      gesicht: { a: "denk", b: "denk" },
      blase: { wer: "a", text: "Eine Frage für ALLE!" },
    },
    {
      at: 2400,
      requisiten: [{ art: "frage", tippA: 0, richtig: 0 }],
      pose: { a: "jubel", b: "frust" },
      gesicht: { a: "jubel", b: "frust" },
      blase: { wer: "a", text: "Richtig → Mia darf werfen!" },
      sound: "lockin-thunk",
    },
    {
      at: 4600,
      requisiten: [{ art: "schild", text: "🥧 TORTE auf Bo!", ton: "rot", bei: "b" }],
      pose: { a: "zeig", b: "duck" },
      gesicht: { a: "jubel", b: "frust" },
      effekt: "explosion",
      sound: "matsch-treffer",
    },
    {
      at: 7000,
      requisiten: [{ art: "schild", text: "3 Torten = RAUS!", ton: "rot", bei: "b" }],
      pose: { a: "jubel", b: "fall" },
      gesicht: { a: "jubel", b: "frust" },
      blase: { wer: "b", text: "Voll Sahne …" },
      sound: "stinkbanane-platzt",
    },
    {
      at: 9200,
      requisiten: [{ art: "schild", text: "Letzter sauberer Affe: +TOPF", ton: "gold", bei: "a" }],
      pose: { a: "jubel", b: "fall" },
      gesicht: { a: "jubel", b: "frust" },
      geldflug: { von: "mitte", zu: "a" },
      effekt: "konfetti",
      sound: "money-mittel",
    },
  ],
};

export default modul;

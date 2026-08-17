// Client-Renderer „Bananen-Boxkampf": Screen = Boxring mit den 2 Affen-Puppen
// (FxApi.spieler) — Punch-Animationen laufen über die GELENK-GRUPPEN der
// Inline-SVGs (CSS rotiert #arm-r des Schlagenden, s. README der Puppen),
// HP-Balken über beiden Ecken, K.O.-Moment mit kreisenden Sternen. Phasen:
// Gegner-Wahl → Wett-Fenster (geheim, nur Anzahl) → Ring-Gong-Countdown →
// Speed-Frage → Schlag-Beat (Erstschlag/Konter in Buzzer-Reihenfolge) →
// K.O.-/Punktsieg-Cutscene + Wett-Abrechnung.
// Player = Gegner-Wahl-Grid (nur Herausforderer), Wett-Buttons (Zuschauer),
// XXL-Antwort-Buttons (Boxer — die Antwort IST der Buzz), Warte-Zustände.
import { html, render } from "lit-html";
import { BOXKAMPF_ID, BX_WETTE_MM } from "../../../../shared/minigames/bananen-boxkampf.meta";
import { formatMM } from "../../../../shared/money";
import { timerBalken } from "../../ui";
import type { FxApi, MinigameClientModule, SendAction } from "../types";
import "./bananen-boxkampf.css";

const DEKO = [
  { buchstabe: "A", emoji: "🍌", farbe: "#e6b830" },
  { buchstabe: "B", emoji: "🥥", farbe: "#8a5a3b" },
  { buchstabe: "C", emoji: "🐒", farbe: "#d1495b" },
  { buchstabe: "D", emoji: "🌴", farbe: "#2e8b57" },
] as const;

interface BxKandidat {
  id: string;
  waehlbar: boolean;
  verbunden: boolean;
  kontostand: number | null;
}

interface BxSchlagView {
  von: string;
  schaden: number;
  konter: boolean;
  ko: boolean;
}

interface BxView {
  questionId: string;
  frageNonce: number;
  phase: "herausforderung" | "wetten" | "countdown" | "frage" | "schlag" | "ergebnis";
  endsAt: number;
  timerMs: number;
  rundeNr: number;
  runden: number;
  herausforderer: string;
  gegner: string | null;
  spieler: string[];
  hp: Record<string, number>;
  maxHp: number;
  punch: number;
  wettenAnzahl: number;
  wetten: Record<string, string> | null;
  wetteMM: number;
  text: string | null;
  options: string[] | null;
  answeredCount: number;
  letzterAbtausch: {
    correctIndex: number;
    schlaege: BxSchlagView[];
    fotofinish: boolean;
    antworten: Record<string, { choice: number; nachMs: number }>;
  } | null;
  ergebnis: {
    sieger: string | null;
    verlierer: string | null;
    ko: boolean;
    geteilt: boolean;
    kampflos: boolean;
    abgebrochen: boolean;
    praemie: number;
    restAnSieger: number;
  } | null;
  finished: boolean;
  duBistBoxer?: boolean;
  duBistHerausforderer?: boolean;
  deinHp?: number | null;
  yourChoice?: number | null;
  deineWette?: string | null;
  waehlbareGegner?: BxKandidat[] | null;
  aufloesung: {
    correctIndex: number | null;
    erklaerung: string;
    perPlayer: {
      playerId: string;
      choice: null;
      correct: boolean;
      delta: number;
      hp: number | null;
    }[];
  } | null;
}

function info(fx: FxApi | undefined, playerId: string | null): { name: string; avatar: string } {
  if (playerId === null) return { name: "—", avatar: "gelb" };
  const s = fx?.spieler?.(playerId);
  return { name: s?.name ?? playerId, avatar: s?.avatar ?? "gelb" };
}

/** Countdown-Ziffer (3-2-1) aus der Server-Zeit — tickt ohne Client-Timer. */
function countdownZiffer(v: BxView, serverNow: number): number {
  return Math.max(1, Math.ceil((v.endsAt - serverNow) / 1_000));
}

/** HP-Balken einer Ring-Ecke (grün → orange → rot). */
function hpBalken(v: BxView, playerId: string | null) {
  const hp = playerId !== null ? (v.hp[playerId] ?? v.maxHp) : v.maxHp;
  const anteil = Math.max(0, Math.min(1, hp / v.maxHp));
  const stufe = anteil > 0.5 ? "gruen" : anteil > 0.2 ? "orange" : "rot";
  return html`<span class="bx-hp">
    <span class="bx-hp-fuellung ${stufe}" style="width:${(anteil * 100).toFixed(0)}%"></span>
    <span class="bx-hp-zahl">${hp}</span>
  </span>`;
}

/** Boxer-Puppe mit Namensschild + HP — Punch/Hit/K.O.-Klassen im Schlag-Beat;
 * der Sieger jubelt am Ende mit Armen hoch (Gelenk-Rotation via jubel). */
function boxerPuppe(
  fx: FxApi | undefined,
  v: BxView,
  playerId: string | null,
  seite: "links" | "rechts",
) {
  const i = info(fx, playerId);
  const t = v.phase === "schlag" ? v.letzterAbtausch : null;
  const schlaege = t?.schlaege ?? [];
  const meinSchlag = schlaege.findIndex((s) => s.von === playerId);
  const treffer = schlaege.findIndex((s) => playerId !== null && s.von !== playerId);
  const koGetroffen = schlaege.some((s) => playerId !== null && s.von !== playerId && s.ko);
  const koEnde =
    (v.phase === "ergebnis" || v.finished) &&
    v.ergebnis?.ko === true &&
    playerId !== null &&
    v.ergebnis.verlierer === playerId;
  const siegEnde =
    (v.phase === "ergebnis" || v.finished) &&
    playerId !== null &&
    v.ergebnis?.sieger === playerId &&
    v.ergebnis.abgebrochen !== true;
  return html`<div
    class="bx-ecke ${seite} ${meinSchlag >= 0 ? "punch" : ""} ${treffer >= 0 ? "hit" : ""} ${
      koGetroffen || koEnde ? "ko" : ""
    } ${siegEnde ? "sieger" : ""}"
    style="--schlag-i:${Math.max(meinSchlag, 0)};--treffer-i:${Math.max(treffer, 0)}"
  >
    ${hpBalken(v, playerId)}
    <span class="bx-puppe-wrap">
      <span
        class="bx-puppe mm-affe"
        data-avatar=${i.avatar}
        data-gesicht=${
          siegEnde
            ? "jubel"
            : koGetroffen || koEnde
              ? "frust"
              : meinSchlag >= 0
                ? "jubel"
                : "neutral"
        }
      ></span>
      <span class="bx-handschuh">🥊</span>
      ${koGetroffen || koEnde ? html`<span class="bx-sterne">💫</span>` : ""}
      ${siegEnde ? html`<span class="bx-sieger-guertel">🏆</span>` : ""}
    </span>
    <span class="bx-name">${i.name}</span>
  </div>`;
}

/** Der Boxring: Pfosten, Seile, beide Ecken, Wett-Fähnchen an den Seilen.
 * K.O.-Moment (W4): der ganze Ring zoomt in 0,5-s-Zeitlupe auf den Einschlag. */
function ring(fx: FxApi | undefined, v: BxView) {
  const koIndex =
    v.phase === "schlag" ? (v.letzterAbtausch?.schlaege.findIndex((s) => s.ko) ?? -1) : -1;
  return html`<div
    class="bx-ring ${koIndex >= 0 ? "ko-zeitlupe" : ""}"
    style="--ko-i:${Math.max(koIndex, 0)}"
  >
    <span class="bx-pfosten links"></span>
    <span class="bx-pfosten rechts"></span>
    <div class="bx-seile">
      <span class="bx-seil"></span>
      <span class="bx-seil"></span>
      <span class="bx-seil"></span>
    </div>
    <div class="bx-boden"></div>
    <div class="bx-boxer">
      ${boxerPuppe(fx, v, v.herausforderer, "links")} ${boxerPuppe(fx, v, v.gegner, "rechts")}
    </div>
    ${
      v.wetten !== null && Object.keys(v.wetten).length > 0
        ? html`<div class="bx-faehnchen">
            ${Object.entries(v.wetten).map(([wetter, auf]) => {
              const w = info(fx, wetter);
              const seite = auf === v.herausforderer ? "links" : "rechts";
              return html`<span class="bx-fahne ${seite}" title="${w.name} wettet">
                🚩 ${w.name} → ${info(fx, auf).name}
              </span>`;
            })}
          </div>`
        : v.wettenAnzahl > 0
          ? html`<div class="bx-faehnchen">
              <span class="bx-fahne geheim"
                >🤫 ${v.wettenAnzahl} geheime Wette${v.wettenAnzahl === 1 ? "" : "n"}</span
              >
            </div>`
          : ""
    }
  </div>`;
}

// Ring-Beats: pro Schlagabtausch/Gong EIN Sound (Edge-Detection über Nonce).
let letzterSoundKey = "";
function beatSound(v: BxView, fx: FxApi): void {
  const key = `${v.phase}:${v.frageNonce}`;
  if (key === letzterSoundKey) return;
  letzterSoundKey = key;
  if (v.phase === "frage") fx.sound("zeit-um"); // Ring-Gong: die Frage läuft!
  if (v.phase === "schlag" && v.letzterAbtausch !== null) {
    const s = v.letzterAbtausch.schlaege;
    fx.sound(
      s.some((x) => x.ko) ? "stinkbanane-platzt" : s.length > 0 ? "podium-riss" : "reveal-zap",
    );
  }
  if (v.phase === "ergebnis" && v.ergebnis?.sieger != null) fx.sound("sieg-fanfare");
}

const modul: MinigameClientModule = {
  id: BOXKAMPF_ID,

  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void {
    const v = view as BxView;
    beatSound(v, fx);

    if (v.aufloesung || v.phase === "ergebnis") {
      const e = v.ergebnis;
      const sieger = info(fx, e?.sieger ?? null);
      render(
        html`<div class="bx-screen">
          <div class="bx-kopf"><span class="bx-badge">🥊 BANANEN-BOXKAMPF</span></div>
          ${
            e?.abgebrochen === true
              ? html`<h2 class="bx-titel">Kampf abgebrochen — der Ring bleibt leer.</h2>`
              : e?.geteilt === true
                ? html`<h2 class="bx-titel">
                    🤝 UNENTSCHIEDEN nach Punkten! Je ${formatMM(e.praemie)} — Wetten zurück.
                  </h2>`
                : html`<h2 class="bx-titel">
                    ${e?.ko === true ? "💫 K.O.!" : "🏆"}
                    <strong>${sieger.name.toUpperCase()}</strong>
                    ${e?.ko === true ? "schlägt den Gegner zu Boden!" : "gewinnt nach Punkten!"}
                  </h2>`
          }
          ${ring(fx, v)}
          ${
            e !== null && e.sieger !== null && !e.abgebrochen
              ? html`<p class="bx-abrechnung">
                  ${formatMM(e.praemie)} aus der
                  Bank${
                    e.kampflos
                      ? " — kampflos (Gegner offline), Wetten zurück"
                      : e.restAnSieger > 0
                        ? html` + ${formatMM(e.restAnSieger)} Wett-Topf-Rest`
                        : ""
                  }
                </p>`
              : ""
          }
          ${
            v.aufloesung
              ? html`<div class="bx-bilanz">
                  ${[...v.aufloesung.perPlayer]
                    .sort((a, b) => b.delta - a.delta)
                    .map(
                      (r) =>
                        html`<div class="bx-bilanz-zeile ${r.correct ? "gewonnen" : ""}">
                          <span
                            class="bx-mini mm-affe"
                            data-avatar=${info(fx, r.playerId).avatar}
                          ></span>
                          <span>${info(fx, r.playerId).name}</span>
                          <span class="muted">${r.hp !== null ? `${r.hp} HP` : ""}</span>
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
        html`<div class="bx-screen">
          <div class="bx-kopf"><span class="bx-badge">🥊 BANANEN-BOXKAMPF</span></div>
          ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())}
          <div class="bx-wahl">
            <span class="bx-puppe gross mm-affe mm-affe-idle" data-avatar=${h.avatar}></span>
            <h2 class="bx-titel">
              <strong>${h.name.toUpperCase()}</strong> (Letzter im Zwischenstand) steigt in den Ring
              …
            </h2>
            <p class="muted">
              Wen fordert er zum Faustkampf? Der Ärmste ist geschützt — der Führende nie!
            </p>
          </div>
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "wetten") {
      render(
        html`<div class="bx-screen">
          <div class="bx-kopf">
            <span class="bx-badge">🥊 WETTEN, BITTE!</span>
            <span class="muted">${formatMM(v.wetteMM)} auf den Sieger — Topf pari-mutuel</span>
          </div>
          ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())} ${ring(fx, v)}
          <p class="muted" style="text-align:center">
            ${info(fx, v.herausforderer).name} 🥊 ${info(fx, v.gegner).name} — K.O. oder Punktsieg
            nach ${v.runden} Fragen. Die Zuschauer setzen GEHEIM.
          </p>
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "countdown") {
      render(
        html`<div class="bx-screen">
          ${ring(fx, v)}
          <div class="bx-countdown">${countdownZiffer(v, fx.serverNow())}</div>
          <p class="muted" style="text-align:center">
            🔔 Runde ${v.rundeNr}/${v.runden} — jede richtige Antwort ist ein Schlag (−${v.punch}
            HP), die schnellere schlägt ZUERST!
          </p>
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "frage") {
      render(
        html`<div class="bx-screen">
          <div class="bx-kopf">
            <span class="bx-badge">🥊 RUNDE ${v.rundeNr}/${v.runden}</span>
            <span class="muted">${v.answeredCount}/2 Antworten · Punch −${v.punch} HP</span>
          </div>
          <h2 class="bx-frage">${v.text ?? ""}</h2>
          ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())}
          <div class="bx-optionen">
            ${(v.options ?? []).map(
              (opt, i) =>
                html`<div class="bx-option" style="--deko:${DEKO[i].farbe}">
                  <span class="bx-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                  ${opt}
                </div>`,
            )}
          </div>
          ${ring(fx, v)}
        </div>`,
        host,
      );
      return;
    }

    // SCHLAG: Punch-Cutscene mit Lösung.
    const t = v.letzterAbtausch;
    const erster = t?.schlaege[0] ?? null;
    render(
      html`<div class="bx-screen">
        <div class="bx-kopf"><span class="bx-badge">💥 SCHLAGABTAUSCH!</span></div>
        <h2 class="bx-titel">
          ${
            erster !== null
              ? html`<strong>${info(fx, erster.von).name.toUpperCase()}</strong> schlägt
                  zuerst${t?.fotofinish === true ? " (Fotofinish-Los! 📸)" : ""}${
                    t?.schlaege.some((s) => s.ko) === true
                      ? " — K.O.!"
                      : t !== null && t.schlaege.length > 1
                        ? html` … und <strong>${info(fx, t.schlaege[1].von).name}</strong> kontert!`
                        : "!"
                  }`
              : "Beide daneben — nur der Ring wackelt."
          }
        </h2>
        ${
          t !== null
            ? html`<p class="muted" style="text-align:center">
                Richtig war: <strong>${DEKO[t.correctIndex].buchstabe}</strong>
              </p>`
            : ""
        }
        ${ring(fx, v)}
      </div>`,
      host,
    );
  },

  renderPlayer(view: unknown, host: HTMLElement, send: SendAction, fx?: FxApi): void {
    const v = view as BxView;
    if (v.aufloesung) {
      render(html``, host); // Auflösung rendert die Player-App (kennt „you")
      return;
    }

    // ---------- Gegner-Wahl (NUR der Herausforderer) ----------
    if (v.phase === "herausforderung") {
      if (v.duBistHerausforderer === true) {
        render(
          html`<div class="bx-player">
            <h3 class="bx-player-titel">🥊 DU steigst in den Ring — wähle deinen Gegner!</h3>
            <div class="bx-gegner-grid">
              ${(v.waehlbareGegner ?? []).map((k) => {
                const i = info(fx, k.id);
                return html`<button
                  class="bx-gegner ${k.waehlbar ? "" : "geschuetzt"}"
                  ?disabled=${!k.waehlbar}
                  @click=${() => {
                    fx?.sound("lockin-thunk");
                    void send("herausfordern", { targetId: k.id });
                  }}
                >
                  <span class="bx-mini mm-affe" data-avatar=${i.avatar}></span>
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
        html`<div class="bx-player">
          <div class="bx-status">
            🥊 <strong>${info(fx, v.herausforderer).name}</strong> wählt den Gegner …<br />
            <span class="muted">Steigst DU gleich in den Ring?</span>
          </div>
        </div>`,
        host,
      );
      return;
    }

    const istBoxer = v.duBistBoxer === true;

    // ---------- Wett-Fenster (Zuschauer) ----------
    if (v.phase === "wetten") {
      if (istBoxer) {
        render(
          html`<div class="bx-player">
            <div class="bx-status">
              🥊 DU stehst im Ring!<br />
              <span class="muted">Die Zuschauer wetten … Bandagen festziehen.</span>
            </div>
          </div>`,
          host,
        );
        return;
      }
      if (v.deineWette != null) {
        render(
          html`<div class="bx-player">
            <div class="bx-status">
              🚩 Wette platziert: <strong>${info(fx, v.deineWette).name}</strong><br />
              <span class="muted">Richtige Wetten teilen den Topf — 50/50 zahlt ×2!</span>
            </div>
          </div>`,
          host,
        );
        return;
      }
      render(
        html`<div class="bx-player">
          <h3 class="bx-player-titel">🚩 ${formatMM(BX_WETTE_MM)} auf wen?</h3>
          <div class="bx-wett-grid">
            ${[v.herausforderer, v.gegner].map((d) => {
              if (d === null) return "";
              const i = info(fx, d);
              return html`<button
                class="bx-wett-button"
                @click=${() => {
                  fx?.sound("lockin-thunk");
                  void send("wette", { auf: d });
                }}
              >
                <span class="bx-puppe mm-affe mm-affe-idle" data-avatar=${i.avatar}></span>
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
        html`<div class="bx-player">
          <div class="bx-countdown klein">${countdownZiffer(v, fx?.serverNow() ?? v.endsAt)}</div>
          ${
            istBoxer
              ? html`<p class="muted" style="text-align:center">
                  Fäuste hoch — schneller UND richtig schlägt zuerst!
                </p>`
              : ""
          }
        </div>`,
        host,
      );
      return;
    }

    // ---------- Speed-Frage: XXL-Buttons NUR für Boxer ----------
    if (v.phase === "frage") {
      if (istBoxer) {
        const gewaehlt = v.yourChoice ?? null;
        render(
          html`<div class="bx-player">
            <p class="bx-hp-eigen">
              ${v.deinHp != null ? html`❤️ ${v.deinHp}/${v.maxHp} HP · Punch −${v.punch}` : ""}
            </p>
            <p class="bx-frage-klein">${v.text ?? ""}</p>
            ${(v.options ?? []).map(
              (opt, i) =>
                html`<button
                  class="bx-button ${gewaehlt === i ? "gewaehlt" : ""} ${gewaehlt !== null ? "gesperrt" : ""}"
                  style="--deko:${DEKO[i].farbe}"
                  ?disabled=${gewaehlt !== null}
                  @click=${() => {
                    fx?.sound("lockin-thunk");
                    void send("answer", { choice: i });
                  }}
                >
                  <span class="bx-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                  ${opt}
                </button>`,
            )}
          </div>`,
          host,
        );
        return;
      }
      render(
        html`<div class="bx-player">
          <div class="bx-status">
            👀 Kampf läuft — ${v.answeredCount}/2 Antworten.<br />
            ${
              v.deineWette != null
                ? html`<span class="muted">Deine Wette: ${info(fx, v.deineWette).name} 🚩</span>`
                : html`<span class="muted">Schneller UND richtig schlägt zuerst!</span>`
            }
          </div>
          <p class="bx-frage-klein muted">${v.text ?? ""}</p>
        </div>`,
        host,
      );
      return;
    }

    // Schlag/Ergebnis: kompakter Status.
    const t = v.letzterAbtausch;
    render(
      html`<div class="bx-player">
        <div class="bx-status">
          ${
            v.phase === "schlag"
              ? t !== null && t.schlaege.length > 0
                ? html`💥 <strong>${info(fx, t.schlaege[0].von).name}</strong> trifft
                    (−${t.schlaege[0].schaden} HP)${t.schlaege.some((s) => s.ko) ? " — K.O.!" : ""}`
                : "Beide daneben — nächste Runde!"
              : v.ergebnis?.geteilt === true
                ? "🤝 Unentschieden nach Punkten!"
                : v.ergebnis?.sieger != null
                  ? html`🏆 <strong>${info(fx, v.ergebnis.sieger).name}</strong> gewinnt
                      ${v.ergebnis.ko ? "durch K.O." : "nach Punkten"}!`
                  : "…"
          }
        </div>
      </div>`,
      host,
    );
  },

  explainCard: {
    text: "1-gegen-1 im Boxring: Der Letzte fordert heraus, jede richtige Antwort ist ein SCHLAG (HP runter!) — die schnellere richtige Antwort schlägt ZUERST. K.O. bei 0 HP oder Punktsieg nach 8 Fragen. Zuschauer wetten 50 MM auf den Sieger!",
    animation: html`<span style="font-size:3rem">🥊🐒💫🐒🚩</span>`,
  },
};

// Erklär-Demo (ADDITIV): beide richtig — aber Mia ist schneller, ihr Schlag
// landet zuerst; Bos HP fallen, der K.O.-Moment holt den Sieg.
export const demoChoreo: import("../demo-typen").DemoChoreo = {
  dauer: 11800,
  beats: [
    {
      at: 0,
      requisiten: [{ art: "schild", text: "🥊 1 gegen 1 — 100 HP", ton: "cyan" }],
      pose: { a: "buzz", b: "buzz" },
      gesicht: { a: "neutral", b: "neutral" },
      blase: { wer: "a", text: "Faustkampf im Ring!" },
    },
    {
      at: 2400,
      requisiten: [{ art: "frage" }],
      pose: { a: "denk", b: "denk" },
      gesicht: { a: "denk", b: "denk" },
      blase: { wer: "b", text: "Jede richtige Antwort: ein Schlag!" },
    },
    {
      at: 4800,
      requisiten: [{ art: "frage", tippA: 0, tippB: 0, richtig: 0 }],
      pose: { a: "buzz", b: "tipp" },
      gesicht: { a: "jubel", b: "denk" },
      blase: { wer: "a", text: "Beide richtig — Mia war SCHNELLER!" },
      sound: "buzzer-hupe",
    },
    {
      at: 7000,
      requisiten: [{ art: "schild", text: "ERSTSCHLAG: −30 HP!", ton: "rot", bei: "b" }],
      pose: { a: "zeig", b: "duck" },
      gesicht: { a: "jubel", b: "frust" },
      sound: "podium-riss",
    },
    {
      at: 9200,
      requisiten: [{ art: "schild", text: "K.O.! +400 MM + Wett-Topf", ton: "gold", bei: "a" }],
      pose: { a: "jubel", b: "fall" },
      gesicht: { a: "jubel", b: "frust" },
      geldflug: { von: "mitte", zu: "a" },
      effekt: "konfetti",
      sound: "money-mittel",
    },
  ],
};

export default modul;

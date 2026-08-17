// GM-Cockpit-Templates (W3-Redesign „Zonen statt Button-Wand"):
// 1. REGIE-LEISTE (sticky): die 3 Meistgenutzten GROSS (Weiter/Pause/Zeit)
//    + Status-Chips + Match-Ende — immer erreichbar, nie scrollen.
// 2. KONTEXT-KARTE: was gerade läuft + NUR die dazu passenden Aktionen
//    (Spickzettel bei Fragen, Rad im Zwischenstand, Bots/Settings in der Lobby).
// 3. AKKORDEON-ZONEN (Spieler/Fragen/Show/Log + Regie-Extras): alles Seltene
//    einklappbar — Information-Density runter, kein Funktionsverlust.
// Layout/Optik: client/gm/cockpit.css (Sticker-Look, Status-Farben aus tokens).
import { html, type TemplateResult } from "lit-html";
import { ALLE_JOKER_IDS, JOKER } from "../../shared/jokers";
import { formatMM } from "../../shared/money";
import type { GmLogEntry, TunnelStatusMsg } from "../../shared/protocol";
import type { BettTrack } from "../../shared/songs";
import { RAD_SEGMENTE } from "../../shared/wheel";
import type { GmView } from "../../shared/views";
import { STANDARD_BETTEN } from "../shared/fx/musik-rotation";
import { avatarDot } from "../shared/ui";
import { metaKarte } from "./meta-gm";

export interface GmAppState {
  code: string;
  pin: string;
  verbunden: boolean;
  fehler: string | null;
  view: GmView | null;
  log: GmLogEntry[];
  adjust: { playerId: string; betrag: number; grund: string };
  /** Generische Formularfelder (whisper, vote, rig, zone-…) — überleben Re-Renders. */
  felder: Record<string, string>;
  /** EIN aktives Cockpit: true = ein anderer GM ist aktiv (Beobachter-Modus). */
  beobachter: boolean;
  /** INTERNET-LINK (W4): Tunnel-Status vom Server (S→C tunnel.status). */
  tunnel: TunnelStatusMsg | null;
}

type Sende = (cmd: string, args: Record<string, unknown>) => Promise<boolean>;

/** INTERNET-LINK: Start/Stop-Sender (tunnel.start/stop) — von main.ts injiziert. */
type TunnelCmd = (aktion: "start" | "stop") => void;

/** Doppel-Tap-Wächter: 2 schnelle Klicks auf „Weiter/Skip" überspringen sonst
 *  2 Phasen (z. B. direkt an der Auflösung vorbei). Nur UI-Drossel (monotone
 *  Browser-Uhr, keine Spiellogik), kein Redesign. */
let letzterFlowNext = 0;
function flowNextGedrosselt(sende: Sende): void {
  const jetzt = performance.now();
  if (jetzt - letzterFlowNext < 600) return;
  letzterFlowNext = jetzt;
  void sende("flow.next", {});
}

/** 2-Tap-Bestätigung für destruktive Kommandos (Annullieren, Skip, Match-Ende,
 *  Bestrafung): erster Tap macht den Knopf 3 s lang zu „Wirklich?", erst der
 *  zweite Tap innerhalb des Fensters feuert. Reine UI-Sicherung. */
let bestaetigung: { key: string; timer: ReturnType<typeof setTimeout> } | null = null;

function mitBestaetigung(key: string, zeichne: () => void, aktion: () => void): void {
  if (bestaetigung !== null) {
    clearTimeout(bestaetigung.timer);
    const bestaetigt = bestaetigung.key === key;
    bestaetigung = null;
    if (bestaetigt) {
      aktion();
      zeichne();
      return;
    }
  }
  bestaetigung = {
    key,
    timer: setTimeout(() => {
      bestaetigung = null;
      zeichne();
    }, 3000),
  };
  zeichne();
}

const fragtNach = (key: string): boolean => bestaetigung?.key === key;

/** Mini-Toast AM Auslöser (nicht nur im Log): kurzes Erfolgs-Feedback, das
 *  über dem geklickten Knopf aufpoppt und nach ~1,6 s verschwindet. */
function miniToast(ausloeser: EventTarget | null, text: string): void {
  const knopf = ausloeser instanceof HTMLElement && ausloeser.isConnected ? ausloeser : null;
  const t = document.createElement("div");
  t.textContent = text;
  t.setAttribute("data-testid", "mini-toast");
  t.style.cssText =
    "position:fixed;z-index:99;background:var(--gold);color:#20160a;font-weight:800;" +
    "padding:6px 12px;border-radius:10px;pointer-events:none;white-space:nowrap;" +
    "box-shadow:0 4px 14px rgba(0,0,0,0.45);transition:opacity 0.3s,transform 0.3s";
  document.body.appendChild(t);
  const r = knopf?.getBoundingClientRect() ?? null;
  const b = t.getBoundingClientRect();
  const links =
    r !== null
      ? Math.max(8, Math.min(window.innerWidth - b.width - 8, r.left + r.width / 2 - b.width / 2))
      : window.innerWidth / 2 - b.width / 2;
  const oben = r !== null ? Math.max(8, r.top - b.height - 8) : window.innerHeight - 90;
  t.style.left = `${links}px`;
  t.style.top = `${oben}px`;
  setTimeout(() => {
    t.style.opacity = "0";
    t.style.transform = "translateY(-8px)";
  }, 1300);
  setTimeout(() => t.remove(), 1700);
}

/** Kommando senden + bei Erfolg Mini-Toast am Auslöser (currentTarget) zeigen. */
function sendeMitToast(
  sende: Sende,
  e: Event,
  text: string,
  cmd: string,
  args: Record<string, unknown>,
): void {
  const ausloeser = e.currentTarget;
  void sende(cmd, args).then((ok) => {
    if (ok) miniToast(ausloeser, text);
  });
}

/** Phasen-Etiketten für Status-Chip + Kontext-Karte (Regie-Sprache). */
const PHASEN_LABEL: Record<string, string> = {
  lobby: "🛋 Lobby",
  intro: "🎬 Show-Opening",
  "kategorie-wahl": "📚 Kategorie-Wahl",
  erklaerkarte: "🃏 Erklärkarte",
  frage: "❓ Frage läuft",
  aufloesung: "💡 Auflösung",
  zwischenstand: "💰 Zwischenstand",
  rad: "🎡 Glücksrad",
  tiebreaker: "🥥 Sudden Death",
  highlights: "🎞 Highlights",
  siegerehrung: "🏆 Siegerehrung",
  ende: "🏁 Abspann",
};

const phasenLabel = (phase: string): string => PHASEN_LABEL[phase] ?? phase;

/** Zonen-Navigation (P2 GM-Layout): Anker-Chips springen die Bereiche an UND
 *  klappen deren Akkordeon auf. Ids = gm-zone-<key> (Kompat zu alten Touren). */
const GM_ZONEN = [
  ["regie", "🎬 Regie"],
  ["spieler", "🐒 Spieler"],
  ["fragen", "📦 Fragen"],
  ["show", "🎤 Show"],
  ["log", "📝 Log"],
] as const;

/** Akkordeon-Defaults: Spieler offen, alles Seltene zu (Density runter). */
const ZONE_DEFAULT_OFFEN: Record<string, boolean> = {
  spieler: true,
  fragen: false,
  show: false,
  log: false,
  extras: false,
};

function zoneOffen(state: GmAppState, key: string): boolean {
  const merker = state.felder[`zone-${key}`];
  if (merker === "auf") return true;
  if (merker === "zu") return false;
  return ZONE_DEFAULT_OFFEN[key] ?? false;
}

function ankerChips(state: GmAppState, zeichne: () => void): TemplateResult {
  return html`<nav data-testid="gm-anker" class="anker-chips">
    ${GM_ZONEN.map(
      ([id, label]) =>
        html`<button
          class="anker-chip"
          data-testid="gm-anker-${id}"
          @click=${() => {
            // Zone aufklappen (auch die Extras der Regie-Zone), DANN scrollen.
            state.felder[`zone-${id}`] = "auf";
            if (id === "regie") state.felder["zone-extras"] = "auf";
            zeichne();
            requestAnimationFrame(() =>
              document
                .getElementById(`gm-zone-${id}`)
                ?.scrollIntoView({ behavior: "smooth", block: "start" }),
            );
          }}
        >
          ${label}
        </button>`,
    )}
  </nav>`;
}

/** Einklappbare Zonen-Karte: Titel + Live-Zusammenfassung im Kopf, Nutzer-
 *  Toggles überleben Re-Renders (state.felder statt DOM-Zufall). */
function akkordeon(
  state: GmAppState,
  key: string,
  titel: string,
  info: TemplateResult | string,
  inhalt: TemplateResult,
): TemplateResult {
  return html`<details
    class="karte akkordeon"
    .open=${zoneOffen(state, key)}
    @toggle=${(e: Event) => {
      state.felder[`zone-${key}`] = (e.target as HTMLDetailsElement).open ? "auf" : "zu";
    }}
  >
    <summary>
      <span class="akkordeon-titel">${titel}</span>
      <span class="akkordeon-info">${info}</span>
    </summary>
    <div class="akkordeon-inhalt">${inhalt}</div>
  </details>`;
}

export function renderCockpit(
  state: GmAppState,
  zeichne: () => void,
  verbinde: () => void,
  sende: Sende,
  uebernehme?: (pin: string) => void,
  tunnelCmd?: TunnelCmd,
): TemplateResult {
  if (!state.view) return login(state, zeichne, verbinde);
  const v = state.view;
  const offline = v.players.filter((p) => !p.connected).length;
  return html`<div class="cockpit">
    ${state.beobachter ? beobachterBanner(state, zeichne, uebernehme) : ""}
    ${regieLeiste(state, v, zeichne, sende)}
    <section id="gm-zone-regie" class="cockpit-zone">
      ${kontextKarte(state, v, zeichne, sende)}
      ${akkordeon(
        state,
        "extras",
        "⚙️ Regie-Extras",
        `${v.settings.modus} · Joker ${v.settings.jokerAn ? "AN" : "aus"} · Rad ${v.settings.rad} · Auto-GM ${v.autoGm ? "AN" : "aus"}`,
        regieExtras(state, v, zeichne, sende),
      )}
    </section>
    <section id="gm-zone-spieler" class="cockpit-zone">
      ${akkordeon(
        state,
        "spieler",
        "🐒 Spieler",
        `${v.players.length} im Studio${offline > 0 ? ` · ${offline} offline` : ""}`,
        spielerInhalt(state, v, zeichne, sende),
      )}
    </section>
    <section id="gm-zone-fragen" class="cockpit-zone">
      ${akkordeon(
        state,
        "fragen",
        "📦 Fragen-Regal",
        `${v.regal.length} Kandidaten · geheim`,
        regalInhalt(state, v, sende),
      )}
    </section>
    <section id="gm-zone-show" class="cockpit-zone">
      ${akkordeon(
        state,
        "show",
        "🎤 Show & Publikum",
        v.voting
          ? "🗳 Voting läuft!"
          : `♪ Musik ${v.musikAn ? "an" : "AUS"} · Sounds · Votings · ${v.budgets.blitzStimmungen}× Blitz-Stimmung${state.tunnel?.phase === "laeuft" ? " · 🌐 Internet-Link AN" : ""}`,
        showInhalt(state, v, zeichne, sende, tunnelCmd),
      )}
    </section>
    <section id="gm-zone-log" class="cockpit-zone">
      ${akkordeon(
        state,
        "log",
        "📝 Aktions-Log",
        state.log.length === 0 ? "leer" : `${state.log.length} Einträge`,
        logInhalt(state),
      )}
    </section>
  </div>`;
}

/** Beobachter-Modus: EIN aktives Cockpit — Übernahme nur mit PIN-Bestätigung. */
function beobachterBanner(
  state: GmAppState,
  zeichne: () => void,
  uebernehme?: (pin: string) => void,
): TemplateResult {
  return html`<div class="karte beobachter-banner" data-testid="gm-beobachter">
    <strong>👀 BEOBACHTER-MODUS</strong>
    <span class="muted">
      Ein anderes Cockpit führt gerade Regie — deine Kommandos sind gesperrt. Übernahme nur mit
      PIN-Bestätigung:
    </span>
    <input
      placeholder="GM-PIN"
      inputmode="numeric"
      maxlength="4"
      style="width:9ch"
      .value=${state.felder.takeoverPin ?? ""}
      @input=${(e: Event) => {
        state.felder.takeoverPin = (e.target as HTMLInputElement).value;
        zeichne();
      }}
    />
    <button
      class="primaer"
      ?disabled=${(state.felder.takeoverPin ?? "").length < 4}
      @click=${() => uebernehme?.(state.felder.takeoverPin ?? "")}
    >
      🎙️ Cockpit übernehmen
    </button>
  </div>`;
}

// ---------- 1) REGIE-LEISTE: die 3 Meistgenutzten GROSS, immer sichtbar ----------

function regieLeiste(
  state: GmAppState,
  v: GmView,
  zeichne: () => void,
  sende: Sende,
): TemplateResult {
  // Ungültige Aktionen VORAB sperren statt nachträglich abzulehnen (Engine
  // sagt sonst „nichts-laeuft"/„pausiert" — der Knopf weiß das schon).
  const nichtsLaeuft = v.phase === "lobby" || v.phase === "ende";
  return html`<header class="regie-leiste">
    <div class="regie-zeile">
      <div class="regie-status">
        <span class="status-chip chip-gold">🎩 ${v.roomCode}</span>
        <span class="status-chip chip-cyan">${phasenLabel(v.phase)}</span>
        ${v.paused ? html`<span class="status-chip chip-rot">⏸ PAUSIERT</span>` : ""}
        ${
          state.fehler
            ? html`<span class="status-chip chip-rot" title=${state.fehler}
                >⚠️ ${state.fehler}</span
              >`
            : ""
        }
      </div>
      <button class="primaer regie-gross" @click=${() => flowNextGedrosselt(sende)}>
        ${v.phase === "lobby" ? "▶ Match starten" : "⏭ Weiter / Skip"}
      </button>
      ${
        v.paused
          ? html`<button class="regie-gross" @click=${() => sende("session.resume", {})}>
              ▶ Pause beenden
            </button>`
          : html`<button
              class="regie-gross"
              ?disabled=${nichtsLaeuft}
              title=${nichtsLaeuft ? "Läuft nur im Match — in der Lobby gibt's nichts zu pausieren" : "Pause"}
              @click=${(e: Event) =>
                sendeMitToast(sende, e, "✓ Pausiert", "session.pause", {
                  text: "Der Show-Master telefoniert mit der Bank …",
                })}
            >
              ⏸ Pause
            </button>`
      }
      <button
        class="regie-gross"
        ?disabled=${
          nichtsLaeuft ||
          v.paused !== null ||
          (v.phase === "frage" && v.budgets.verlaengerungenDieseFrage >= 2)
        }
        title=${nichtsLaeuft ? "Läuft nur im Match" : "Timer verlängern"}
        @click=${(e: Event) => sendeMitToast(sende, e, "✓ +15 s", "timer.extend", { ms: 15000 })}
      >
        ⏱ +15 s ${v.phase === "frage" ? `(${v.budgets.verlaengerungenDieseFrage}/2)` : ""}
      </button>
      ${endeKnopf(v, zeichne, sende)}
    </div>
    ${ankerChips(state, zeichne)}
  </header>`;
}

function endeKnopf(v: GmView, zeichne: () => void, sende: Sende): TemplateResult {
  const nichtsLaeuft = v.phase === "lobby" || v.phase === "ende";
  if (v.phase === "ende") {
    return html`<button
      class="regie-ende"
      title="Gibt den Studio-Slot sofort frei (max-rooms)"
      @click=${() => sende("raum.schliessen", {})}
    >
      🚪 Raum schließen
    </button>`;
  }
  return html`<button
    class="regie-ende"
    data-testid="gm-ende"
    ?disabled=${nichtsLaeuft}
    title=${nichtsLaeuft ? "Kein laufendes Match" : "Match beenden"}
    @click=${(e: Event) => {
      // Ab der Siegerehrung ist „Abspann" harmlos — nur das echte
      // Match-Ende braucht die 2-Tap-Bestätigung.
      if (v.phase === "siegerehrung") {
        sendeMitToast(sende, e, "✓ Abspann läuft", "session.ende", {});
        return;
      }
      const ausloeser = e.currentTarget;
      mitBestaetigung("ende", zeichne, () => {
        void sende("session.ende", {}).then((ok) => {
          if (ok) miniToast(ausloeser, "✓ Match beendet");
        });
      });
    }}
  >
    ${
      fragtNach("ende")
        ? "❗ Wirklich beenden?"
        : html`🏁 ${v.phase === "siegerehrung" ? "Abspann" : "Match beenden"}`
    }
  </button>`;
}

// ---------- 2) KONTEXT-KARTE: was läuft + die dazu passenden Aktionen ----------

function kontextKarte(
  state: GmAppState,
  v: GmView,
  zeichne: () => void,
  sende: Sende,
): TemplateResult {
  const a = v.abschnitt;
  return html`<div class="karte kontext-karte" data-testid="gm-kontext">
    <div class="kontext-kopf">
      <strong class="kontext-titel">${phasenLabel(v.phase)}</strong>
      ${
        a
          ? html`<span class="status-chip">
              ${
                a.typ === "runde"
                  ? `Runde ${a.rundeNr}/${a.rundenTotal} · ${a.minigameName}`
                  : a.typ === "jackpot"
                    ? "🍯 Jackpot-Frage"
                    : `🔥 Finale${a.wFinal ? ` (${formatMM(a.wFinal)}/Frage)` : ""}`
              }
            </span>`
          : ""
      }
      <span class="status-chip">Frage ${v.frageNr}/${v.frageTotal}</span>
      <span class="status-chip" title="Drama-Meter (0 = langweilig, 100 = Krimi)">
        🎭 ${v.dramaMeter.score}
      </span>
      ${v.jackpotGlas > 0 ? html`<span class="status-chip chip-gold">🍯 ${formatMM(v.jackpotGlas)}</span>` : ""}
      ${v.pott > 0 ? html`<span class="status-chip chip-gold">💰 Pott ${formatMM(v.pott)}</span>` : ""}
      ${v.modifiers.map((m) => html`<span class="status-chip" title=${m.scope}>⭐ ${m.name}</span>`)}
    </div>
    ${
      v.dramaMeter.empfehlung
        ? html`<p class="kontext-tipp">🎭 <strong>${v.dramaMeter.empfehlung}</strong></p>`
        : ""
    }
    ${kontextInhalt(state, v, zeichne, sende)}
  </div>`;
}

function kontextInhalt(
  state: GmAppState,
  v: GmView,
  zeichne: () => void,
  sende: Sende,
): TemplateResult {
  switch (v.phase) {
    case "lobby":
      return html`<p class="kontext-hinweis">
          ${
            v.players.length < 2
              ? `${v.players.length} Affen im Studio — ab 2 geht's los (▶ Match starten oben).`
              : `${v.players.length} Affen bereit — ▶ Match starten, wenn alle da sind.`
          }
        </p>
        ${metaKarte(v, zeichne, sende)} ${settingsZeile(v, sende)}`;
    case "frage":
    case "aufloesung":
      return spickzettelInhalt(v, zeichne, sende);
    case "kategorie-wahl":
      return kategorieInhalt(v, sende);
    case "zwischenstand":
      return radRegie(state, v, sende);
    case "rad":
      return html`<p class="kontext-hinweis">
        ${
          v.rad?.ergebnis
            ? html`Ergebnis: <strong>${v.rad.ergebnis.name}</strong> — ⏭ Weiter schließt die
                Rad-Phase ab.`
            : "Das Rad dreht — das Ergebnis kommt von selbst, ⏭ Weiter überspringt."
        }
      </p>`;
    case "erklaerkarte": {
      const ek = v.erklaerkarte;
      const verbunden = v.players.filter((p) => p.connected).length;
      return html`<p class="kontext-hinweis">
        🃏 <strong>${ek?.minigameName ?? "Regeln"}</strong> wird erklärt —
        ${ek ? `${ek.bereit.length}/${verbunden} bereit` : "Handys drücken BEREIT"}, ⏭ Weiter
        startet sofort.
      </p>`;
    }
    case "intro":
      return html`<p class="kontext-hinweis">
        Opening läuft (Logo → Kandidaten-Vorstellung) — ⏭ Weiter startet Runde 1.
      </p>`;
    case "tiebreaker":
      return html`<p class="kontext-hinweis">
        🥥 Sudden Death: Kokosnuss-Shake entscheidet den Gleichstand — einfach zusehen.
      </p>`;
    case "highlights":
      return html`<p class="kontext-hinweis">
        🎞 Die Highlights des Abends laufen — danach kommt die Siegerehrung.
      </p>`;
    case "siegerehrung":
      return html`<p class="kontext-hinweis">
        🏆 Podest + Awards laufen — 🏁 Abspann (oben rechts) beendet den Abend.
      </p>`;
    default:
      return html`<p class="kontext-hinweis">
        🏁 Abspann — 🚪 Raum schließen (oben rechts) gibt den Studio-Slot frei.
      </p>`;
  }
}

/** Rad-Regie im Zwischenstand: Spin + heimliches Rig — die EINE passende Aktion. */
function radRegie(state: GmAppState, v: GmView, sende: Sende): TemplateResult {
  const radAus = v.settings.rad !== "an";
  return html`<div class="werkzeug-zeile">
    <button
      class="primaer"
      ?disabled=${radAus}
      title=${radAus ? "Rad ist in den Settings deaktiviert" : "Glücksrad drehen"}
      @click=${() => {
        const rig = state.felder.rig ?? "";
        void sende("wheel.spin", rig ? { rigTarget: rig } : {});
      }}
    >
      🎡 Rad drehen
    </button>
    <select
      title="Heimliches Wunsch-Segment (Rig)"
      @change=${(e: Event) => {
        state.felder.rig = (e.target as HTMLSelectElement).value;
      }}
    >
      <option value="">ehrlich</option>
      ${RAD_SEGMENTE.map(
        (s) =>
          html`<option value=${s.id} ?selected=${state.felder.rig === s.id}>${s.name}</option>`,
      )}
    </select>
    <span class="muted">⏭ Weiter geht ohne Rad zur nächsten Runde.</span>
  </div>`;
}

/** Geheim-Ansicht: aktuelle Frage + Antwort + Frage-Werkzeuge (nur frage/aufloesung). */
function spickzettelInhalt(v: GmView, zeichne: () => void, sende: Sende): TemplateResult {
  const mg = v.minigame?.view as
    | { text?: string; options?: string[]; correctIndex?: number; answeredCount?: number }
    | undefined;
  // Destruktive Frage-Werkzeuge: 2-Tap-Bestätigung + Erfolgs-Toast am Knopf.
  const destruktiv = (
    key: string,
    label: string,
    toast: string,
    cmd: string,
    args: Record<string, unknown>,
  ): TemplateResult =>
    html`<button
      data-testid="gm-${key}"
      class=${fragtNach(key) ? "warnt" : ""}
      @click=${(e: Event) => {
        const ausloeser = e.currentTarget;
        mitBestaetigung(key, zeichne, () => {
          void sende(cmd, args).then((ok) => {
            if (ok) miniToast(ausloeser, toast);
          });
        });
      }}
    >
      ${fragtNach(key) ? "❗ Wirklich?" : label}
    </button>`;
  return html`<div class="spickzettel">
    <h3>🗒 Spickzettel <span class="geheim-tag">GEHEIM</span></h3>
    ${v.frageKategorie ? html`<p class="muted" style="margin:0 0 4px">📚 ${v.frageKategorie}</p>` : ""}
    ${mg?.text ? html`<p class="spick-frage">${mg.text}</p>` : html`<p class="muted">Kein Quiz-Format — siehe Bühne.</p>`}
    ${
      mg?.options && mg.correctIndex !== undefined
        ? html`<p class="spick-antwort">
            ✅ <strong>${mg.options[mg.correctIndex]}</strong>
            <span class="muted"> · ${mg.answeredCount ?? 0} Antworten</span>
          </p>`
        : ""
    }
    ${
      v.spickzettelTipps.length > 0
        ? html`<div style="margin:0 0 8px">
            ${v.spickzettelTipps.map((tipp, i) => {
              const gesendet = i < v.budgets.hintStufe;
              const naechster = i === v.budgets.hintStufe;
              return html`<p style="margin:2px 0;display:flex;gap:8px;align-items:center">
                <span class=${gesendet ? "" : "muted"} style="flex:1">
                  ${gesendet ? "✅" : "💡"} Tipp ${i + 1}: ${tipp}
                </span>
                <button
                  data-testid="gm-tipp-${i + 1}"
                  ?disabled=${!naechster || v.phase !== "frage"}
                  title="Enthüllt den Tipp auf Bühne + Handys (−25 % Gewinn pro Stufe)"
                  @click=${(e: Event) =>
                    sendeMitToast(sende, e, `✓ Tipp ${i + 1} raus`, "hint.global", {})}
                >
                  ${gesendet ? "gesendet" : `Tipp ${i + 1} senden`}
                </button>
              </p>`;
            })}
          </div>`
        : ""
    }
    <div class="werkzeug-zeile">
      <button
        ?disabled=${v.phase !== "frage" || v.budgets.hintStufe >= 3}
        @click=${(e: Event) => sendeMitToast(sende, e, "✓ Tipp raus", "hint.global", {})}
      >
        📣 Tipp-Kanone (Stufe ${v.budgets.hintStufe}/3, −25 %)
      </button>
      ${destruktiv("annul", "🚫 Fehlerhaft → annullieren", "✓ Annulliert", "question.markBroken", {
        grund: "GM-Flag",
        refund: "annul",
      })}
      ${destruktiv(
        "grantall",
        "🎁 Fehlerhaft → alle kriegen Punkte",
        "✓ Punkte für alle",
        "question.markBroken",
        { grund: "GM-Flag", refund: "grantAll" },
      )}
      ${destruktiv("skip-mit", "⏭ Skip (Punkte behalten)", "✓ Übersprungen", "game.skip", {
        keepPoints: true,
      })}
      ${destruktiv("skip-ohne", "⏭ Skip (ohne Punkte)", "✓ Übersprungen", "game.skip", {
        keepPoints: false,
      })}
      <button
        @click=${(e: Event) =>
          sendeMitToast(sende, e, "✓ Geflaggt", "game.flagBuggy", { grund: "GM-Flag" })}
      >
        🐛 Buggy-Flag
      </button>
    </div>
  </div>`;
}

/** Kategorie-Pick während der Kategorien-Wahl-Phase (GM-Pick oder Override). */
function kategorieInhalt(v: GmView, sende: Sende): TemplateResult {
  if (!v.kategorieWahl) return html``;
  return html`<div class="werkzeug-zeile">
    ${v.kategorieWahl.optionen.map(
      (o, i) =>
        html`<button @click=${() => sende("kategorie.pick", { kategorie: o })}>
          ${o} (${v.kategorieWahl!.stimmen[i]})
        </button>`,
    )}
  </div>`;
}

// ---------- 3) REGIE-EXTRAS: Settings + Bots/Saves + seltene Regie-Schalter ----------

function settingsZeile(v: GmView, sende: Sende): TemplateResult {
  const s = v.settings;
  return html`<div class="werkzeug-zeile">
    <strong>⚙️</strong>
    <select
      ?disabled=${v.phase !== "lobby"}
      title="Modus (nur in der Lobby wechselbar)"
      @change=${(e: Event) => sende("settings.set", { modus: (e.target as HTMLSelectElement).value })}
    >
      ${(["quick", "klassik", "marathon"] as const).map(
        (m) => html`<option value=${m} ?selected=${s.modus === m}>${m}</option>`,
      )}
    </select>
    <button @click=${() => sende("settings.set", { jokerAn: !s.jokerAn })}>
      🃏 Joker: ${s.jokerAn ? "AN" : "aus"}
    </button>
    <button @click=${() => sende("settings.set", { rad: s.rad === "an" ? "aus" : "an" })}>
      🎡 Rad: ${s.rad === "an" ? "AN" : "aus"}
    </button>
    <select
      title="Kategorien-Wahl"
      @change=${(e: Event) =>
        sende("settings.set", { kategorienWahl: (e.target as HTMLSelectElement).value })}
    >
      ${(["voting", "gm", "aus"] as const).map(
        (k) =>
          html`<option value=${k} ?selected=${s.kategorienWahl === k}>Kategorien: ${k}</option>`,
      )}
    </select>
    <select
      ?disabled=${v.phase !== "lobby"}
      title="Team-Modus „Affenbanden" (nur in der Lobby wechselbar; greift ab 4 Spielern)"
      @change=${(e: Event) => sende("settings.set", { teams: (e.target as HTMLSelectElement).value })}
    >
      ${(["aus", "2er", "2v2v2v2", "frei"] as const).map(
        (t) => html`<option value=${t} ?selected=${s.teams === t}>🐒 Teams: ${t}</option>`,
      )}
    </select>
    <button @click=${() => sende("settings.set", { kurzeShow: !s.kurzeShow })}>
      ⚡ Kurze Show: ${s.kurzeShow ? "AN" : "aus"}
    </button>
    <button
      title="Erklärkarten bieten Tutorial-Videos an (kostet Tempo)"
      @click=${() => sende("settings.set", { tutorialVideos: !s.tutorialVideos })}
    >
      🎬 Tutorial-Videos: ${s.tutorialVideos ? "AN" : "aus"}
    </button>
    <select
      title="Finale-Faktor"
      @change=${(e: Event) =>
        sende("settings.set", { finaleFaktor: Number((e.target as HTMLSelectElement).value) })}
    >
      ${[1.0, 1.25, 1.5].map(
        (f) => html`<option value=${f} ?selected=${s.finaleFaktor === f}>Finale ×${f}</option>`,
      )}
    </select>
  </div>`;
}

function regieExtras(
  state: GmAppState,
  v: GmView,
  zeichne: () => void,
  sende: Sende,
): TemplateResult {
  const nichtsLaeuft = v.phase === "lobby" || v.phase === "ende";
  return html`<div class="werkzeug-zeile">
      <button @click=${() => sende("autogm.set", { enabled: !v.autoGm })}>
        🤖 Auto-GM: ${v.autoGm ? "AN" : "aus"}
      </button>
      <button
        title="Auto-GM schickt Tipp 1, wenn nach 60 % der Zeit niemand geantwortet hat"
        ?disabled=${!v.autoGm}
        @click=${() => sende("settings.set", { autoTipp: !v.settings.autoTipp })}
      >
        💡 Auto-Tipp: ${v.settings.autoTipp ? "AN" : "aus"}
      </button>
      <button
        ?disabled=${nichtsLaeuft || v.paused !== null}
        title=${nichtsLaeuft ? "Läuft nur im Match" : "Bananen-Pause (10 min Countdown)"}
        @click=${(e: Event) =>
          sendeMitToast(sende, e, "✓ Bananen-Pause", "session.pause", {
            text: "🍌 BANANEN-PAUSE! Streckt euch, holt Wasser.",
            dauerMs: 600000,
          })}
      >
        🍌 Bananen-Pause (10 min)
      </button>
    </div>
    ${v.phase === "lobby" ? "" : html`${settingsZeile(v, sende)} ${metaKarte(v, zeichne, sende)}`}`;
}

// ---------- Zone: Spieler-Werkzeuge (Matrix + Punkte/Strafen/Boosts/Flüstern) ----------

function spielerInhalt(
  state: GmAppState,
  v: GmView,
  zeichne: () => void,
  sende: Sende,
): TemplateResult {
  const ziel = state.adjust.playerId;
  const zielName = v.players.find((p) => p.id === ziel)?.name ?? "—";
  return html`${v.players.length === 0 ? html`<p class="muted">Noch niemand da.</p>` : ""}
    <div class="spieler-matrix">
      ${v.players.map(
        (p) => html`
          <div
            class="spieler-zeile ${p.id === ziel ? "gewaehlt" : ""}"
            @click=${() => {
              state.adjust.playerId = p.id;
              zeichne();
            }}
          >
            ${avatarDot(p.avatar)} <strong>${p.name}</strong>
            ${p.connected ? "" : html`<span class="badge-offline">offline</span>`}
            ${p.rueckenwind ? html`<span title="Rückenwind">💨×${p.rueckenwind}</span>` : ""}
            ${p.schild ? "🛡" : ""} ${p.clown ? "🤡" : ""}
            <span class="spieler-konto">${formatMM(p.balance)}</span>
            <span class="muted">Streak ${p.streak}</span>
          </div>
        `,
      )}
    </div>

    <p class="muted" style="margin:8px 0 4px">
      Ziel: <strong>${zielName}</strong> (Zeile antippen zum Wechseln)
    </p>
    <div class="werkzeug-zeile">
      <input
        type="number"
        step="50"
        style="width:110px"
        .value=${String(state.adjust.betrag)}
        @input=${(e: Event) => {
          state.adjust.betrag = Number((e.target as HTMLInputElement).value);
        }}
      />
      <input
        placeholder="Grund (Pflicht!)"
        style="flex:1;min-width:150px"
        .value=${state.adjust.grund}
        @input=${(e: Event) => {
          state.adjust.grund = (e.target as HTMLInputElement).value;
        }}
      />
      <button
        ?disabled=${ziel === ""}
        @click=${(e: Event) =>
          sendeMitToast(sende, e, `✓ +${Math.abs(state.adjust.betrag)} MM`, "score.adjust", {
            playerId: ziel,
            delta: Math.abs(state.adjust.betrag),
            grund: state.adjust.grund,
          })}
      >
        + geben
      </button>
      <button
        ?disabled=${ziel === ""}
        @click=${(e: Event) =>
          sendeMitToast(sende, e, `✓ −${Math.abs(state.adjust.betrag)} MM`, "score.adjust", {
            playerId: ziel,
            delta: -Math.abs(state.adjust.betrag),
            grund: state.adjust.grund,
          })}
      >
        − abziehen
      </button>
    </div>

    <div class="werkzeug-zeile">
      <button
        ?disabled=${ziel === ""}
        data-testid="gm-strafe-steuer"
        class=${fragtNach("straf-steuer") ? "warnt" : ""}
        @click=${(e: Event) => {
          const ausloeser = e.currentTarget;
          mitBestaetigung("straf-steuer", zeichne, () => {
            void sende("player.punish", { playerId: ziel, strafe: "bananensteuer" }).then((ok) => {
              if (ok) miniToast(ausloeser, `✓ ${zielName} bestraft`);
            });
          });
        }}
      >
        ${fragtNach("straf-steuer") ? "❗ Wirklich?" : "⚖️ Bananensteuer (−100 ins Glas)"}
      </button>
      <button
        ?disabled=${ziel === ""}
        data-testid="gm-strafe-clown"
        class=${fragtNach("straf-clown") ? "warnt" : ""}
        @click=${(e: Event) => {
          const ausloeser = e.currentTarget;
          mitBestaetigung("straf-clown", zeichne, () => {
            void sende("player.punish", { playerId: ziel, strafe: "clown" }).then((ok) => {
              if (ok) miniToast(ausloeser, `✓ ${zielName} ist jetzt 🤡`);
            });
          });
        }}
      >
        ${fragtNach("straf-clown") ? "❗ Wirklich?" : "🤡 Clowns-Avatar"}
      </button>
      ${(["x2", "plus300", "joker"] as const).map(
        (art) =>
          html`<button
            ?disabled=${ziel === ""}
            @click=${(e: Event) =>
              sendeMitToast(sende, e, "✓ Boost raus", "player.boost", {
                playerId: ziel,
                art,
                grund: state.adjust.grund || "Underdog-Boost",
              })}
          >
            🚀 Boost ${art === "x2" ? "×2" : art === "plus300" ? "+300" : "Joker"}
          </button>`,
      )}
    </div>

    <div class="werkzeug-zeile">
      <input
        placeholder="Flüster-Tipp (nur Ziel-Handy!)"
        style="flex:1;min-width:180px"
        data-testid="gm-whisper-input"
        .value=${state.felder.whisper ?? ""}
        @input=${(e: Event) => {
          state.felder.whisper = (e.target as HTMLInputElement).value;
          // P1-Fix: Re-Render, sonst bleibt der Flüster-Knopf disabled, bis
          // irgendein ANDERES Event zeichnet (z. B. Spielerzeile antippen).
          zeichne();
        }}
      />
      <button
        data-testid="gm-whisper-senden"
        ?disabled=${ziel === "" || !(state.felder.whisper ?? "").trim()}
        @click=${(e: Event) => {
          const ausloeser = e.currentTarget;
          void sende("hint.whisper", { playerId: ziel, text: state.felder.whisper.trim() }).then(
            (ok) => {
              if (ok) miniToast(ausloeser, `✓ An ${zielName} geflüstert`);
            },
          );
          state.felder.whisper = "";
          zeichne();
        }}
      >
        🤫 Flüstern
      </button>
      <select
        @change=${(e: Event) => {
          state.felder.grantJoker = (e.target as HTMLSelectElement).value;
        }}
      >
        ${ALLE_JOKER_IDS.map(
          (id) =>
            html`<option
              value=${id}
              ?selected=${(state.felder.grantJoker ?? ALLE_JOKER_IDS[0]) === id}
            >
              ${JOKER[id].emoji} ${JOKER[id].name}
            </option>`,
        )}
      </select>
      <button
        ?disabled=${ziel === "" || v.budgets.jokerChips <= 0}
        @click=${(e: Event) =>
          sendeMitToast(sende, e, "✓ Joker raus", "joker.grant", {
            ziel,
            jokerId: state.felder.grantJoker ?? ALLE_JOKER_IDS[0],
          })}
      >
        🃏 Joker geben (${v.budgets.jokerChips} Chips)
      </button>
      <button
        ?disabled=${v.budgets.jokerChips < v.players.length}
        @click=${(e: Event) =>
          sendeMitToast(sende, e, "✓ Joker an alle", "joker.grant", {
            ziel: "alle",
            jokerId: state.felder.grantJoker ?? ALLE_JOKER_IDS[0],
          })}
      >
        🃏 an ALLE
      </button>
    </div>`;
}

// ---------- Zone: Fragen-Regal (GEHEIM: mit Antwort!) + Maßanzug ----------

function regalInhalt(state: GmAppState, v: GmView, sende: Sende): TemplateResult {
  if (v.regal.length === 0) {
    return html`<p class="muted">Noch keine Kandidaten — das Regal füllt sich im Match.</p>`;
  }
  const kategorien = [...new Set(v.regal.map((r) => r.kategorie))];
  // Maßanzug-Ehrlichkeit: unterstützt das Ziel-Format per-Spieler-Fragen?
  const ziel = v.zuweisungsZiel;
  const massanzugOk = ziel === null || ziel.verfuegbar;
  return html`${
      !massanzugOk && ziel !== null
        ? html`<p
            class="muted"
            data-testid="massanzug-hinweis"
            style="margin:0 0 8px;color:var(--gold)"
          >
            🧵 Maßanzug bei „${ziel.minigameName}" nicht verfügbar — Zuweisungen bleiben liegen und
            greifen beim nächsten Fragen-Format.
          </p>`
        : ""
    }
    <div class="werkzeug-zeile" style="margin-bottom:8px">
      <select
        @change=${(e: Event) => {
          const wert = (e.target as HTMLSelectElement).value;
          void sende("regal.filter", { kategorie: wert === "" ? null : wert });
        }}
      >
        <option value="">Kategorie: alle</option>
        ${kategorien.map((k) => html`<option value=${k}>${k}</option>`)}
      </select>
      <select
        @change=${(e: Event) => {
          const wert = (e.target as HTMLSelectElement).value;
          void sende("regal.filter", { schwierigkeit: wert === "" ? null : wert });
        }}
      >
        <option value="">Schwierigkeit: alle</option>
        ${["easy", "medium", "hard", "ultrahard"].map((s) => html`<option value=${s}>${s}</option>`)}
      </select>
    </div>
    ${v.regal.map(
      (r) =>
        html`<div class="regal-zeile">
          <span class="muted" style="min-width:9ch">${r.kategorie} · ${r.schwierigkeit}</span>
          <span style="flex:1"
            >${r.text} <strong class="regal-antwort">→ ${r.antwort}</strong></span
          >
          <button @click=${() => sende("question.pick", { questionId: r.id })}>Als nächste</button>
          <button
            ?disabled=${state.adjust.playerId === "" || !massanzugOk}
            title=${
              massanzugOk
                ? "Maßanzug: diese Frage NUR für den ausgewählten Spieler"
                : `Bei diesem Format (${ziel?.minigameName ?? "?"}) nicht verfügbar`
            }
            @click=${() =>
              sende("question.assign", { playerId: state.adjust.playerId, questionId: r.id })}
          >
            → Maßanzug
          </button>
        </div>`,
    )}
    ${
      Object.keys(v.zuweisungen).length > 0
        ? html`<p class="muted" style="margin:6px 0 0">
            Maßanzüge:
            ${Object.entries(v.zuweisungen).map(
              ([pid, qid]) =>
                html`<span style="margin-right:8px">
                  ${v.players.find((p) => p.id === pid)?.name ?? pid} ← ${qid}
                  <button
                    style="min-height:44px;min-width:44px;padding:0 10px"
                    title="Maßanzug entfernen"
                    @click=${() => sende("question.assign", { playerId: pid, questionId: null })}
                  >
                    ✕
                  </button>
                </span>`,
            )}
          </p>`
        : ""
    }`;
}

// ---------- Zone: Show & Publikum (Sounds, Zugabe, Voting, Stimmung, Feedback) ----------

// ---------- Zone: Show & Publikum — Musik-Karte (Musik-Welle 3) ----------
// Der GM steuert das Show-Bett als MATCH-Setting (musik/musikVolume) plus den
// „Nächster Track"-Skip (gm.musikSkip-Zähler) — abgespielt wird auf dem
// SCREEN (Rotation in musik-rotation.ts). Die Playlist-Ansicht lädt den
// Bett-Katalog (import.mjs --bett) einmal lazy über GET /api/musik/betten.
let bettKatalog: BettTrack[] | null = null;
let bettKatalogAngefragt = false;

function ladeBettKatalog(zeichne: () => void): void {
  if (bettKatalogAngefragt) return;
  bettKatalogAngefragt = true;
  void fetch("/api/musik/betten")
    .then((r) => (r.ok ? (r.json() as Promise<{ betten: BettTrack[] }>) : null))
    .then((d) => {
      bettKatalog = d?.betten ?? [];
      zeichne();
    })
    .catch(() => {
      bettKatalog = [];
      zeichne();
    });
}

function playlistZeile(ueberschrift: string, standard: string, loops: BettTrack[]): TemplateResult {
  return html`<p style="margin:2px 0">
    <strong>${ueberschrift}:</strong> ${standard}
    ${loops.map((b) => html`<span> · ${b.titel} — ${b.artist}</span>`)}
  </p>`;
}

function musikKarte(
  state: GmAppState,
  v: GmView,
  zeichne: () => void,
  sende: Sende,
): TemplateResult {
  const an = v.musikAn;
  const playlistOffen = state.felder.musikPlaylist === "auf";
  if (playlistOffen) ladeBettKatalog(zeichne);
  const chillig = (bettKatalog ?? []).filter((b) => b.stimmung === "chillig");
  const upbeat = (bettKatalog ?? []).filter((b) => b.stimmung === "upbeat");
  return html`<div class="werkzeug-zeile" data-testid="gm-musik-karte">
      <strong>♪ Musik</strong>
      <button
        data-testid="gm-musik-toggle"
        title="Match-Setting musik: an/aus — stoppt das Bett auf dem Screen"
        @click=${() => sende("settings.set", { musik: an ? "aus" : "an" })}
      >
        ${an ? "🎵 Musik: AN" : "🔇 Musik: aus"}
      </button>
      <input
        type="range"
        min="0"
        max="100"
        style="width:110px"
        title="Show-Musik-Lautstärke (multipliziert den Screen-Regler)"
        data-testid="gm-musik-vol"
        .value=${String(Math.round(v.musikVolume * 100))}
        ?disabled=${!an}
        @change=${(e: Event) =>
          sende("settings.set", {
            musikVolume: Number((e.target as HTMLInputElement).value) / 100,
          })}
      />
      <button
        data-testid="gm-musik-skip"
        ?disabled=${!an}
        title="Rotation der laufenden Phase weiterschalten (Screen skippt)"
        @click=${(e: Event) => sendeMitToast(sende, e, "⏭ Nächster Track", "musik.skip", {})}
      >
        ⏭ Nächster Track
      </button>
      <button
        data-testid="gm-musik-playlist-btn"
        @click=${() => {
          state.felder.musikPlaylist = playlistOffen ? "zu" : "auf";
          zeichne();
        }}
      >
        📻 Playlist ${playlistOffen ? "▴" : "▾"}
      </button>
    </div>
    ${
      playlistOffen
        ? html`<div class="muted" data-testid="gm-musik-playlist" style="margin:4px 0 8px">
            ${
              bettKatalog === null
                ? html`<p style="margin:2px 0">Lade Bett-Katalog …</p>`
                : html`${playlistZeile(
                      "Lobby (chillig)",
                      `${STANDARD_BETTEN.lobby.titel} — ${STANDARD_BETTEN.lobby.artist}`,
                      chillig,
                    )}
                    ${playlistZeile(
                      "Runde (upbeat)",
                      `${STANDARD_BETTEN.runde.titel} — ${STANDARD_BETTEN.runde.artist}`,
                      upbeat,
                    )}
                    <p style="margin:2px 0">
                      <strong>Feste Signale:</strong> ${STANDARD_BETTEN.schleich.titel} (Schleichen)
                      · ${STANDARD_BETTEN.rad.titel} (Rad) · ${STANDARD_BETTEN.news.titel} (News) ·
                      ${STANDARD_BETTEN.erklaer.titel} (Erklärkarte)
                    </p>
                    <p style="margin:2px 0">
                      Eigene Loops:
                      <code>node tools/musik/import.mjs --bett --quelle "&lt;URL&gt;" …</code>
                      (docs/MUSIK-PACKS.md)
                    </p>`
            }
          </div>`
        : ""
    }`;
}

// ---------- Zone: Show & Publikum — Internet-Link-Karte (W4) ----------
// Der Tunnel ist SERVER-global: Status kommt per tunnel.status-Broadcast,
// Start/Stop feuern tunnel.start/stop (nur Screen/aktives Cockpit — der
// Server prüft, Beobachter bekommen „keine-berechtigung").
const TUNNEL_LABEL: Record<string, string> = {
  aus: "aus",
  startet: "startet …",
  laeuft: "LÄUFT",
  fehler: "Fehler",
  "nicht-installiert": "nicht installiert",
};

function tunnelKarte(state: GmAppState, tunnelCmd?: TunnelCmd): TemplateResult {
  const s = state.tunnel;
  // Alter Server/Standalone-Relay: kein tunnel.status ⇒ Karte bleibt weg.
  if (s === null || tunnelCmd === undefined) return html``;
  return html`<div class="werkzeug-zeile" data-testid="gm-tunnel-karte">
      <strong>🌐 Internet-Link</strong>
      <span
        class="status-chip ${s.phase === "laeuft" ? "chip-gold" : ""}"
        data-testid="gm-tunnel-status"
      >
        ${TUNNEL_LABEL[s.phase] ?? s.phase}
      </span>
      ${
        s.phase === "laeuft" && s.url !== null
          ? html`<span
              class="mono"
              data-testid="gm-tunnel-url"
              style="font-size:0.85rem;word-break:break-all"
              >${s.url}</span
            >`
          : ""
      }
      <button
        data-testid="gm-tunnel-start"
        ?disabled=${s.phase === "startet" || s.phase === "laeuft"}
        title="Cloudflare-Quick-Tunnel starten — öffentliche URL für Freunde außerhalb des WLANs"
        @click=${() => tunnelCmd("start")}
      >
        🌐 Link erstellen
      </button>
      <button
        data-testid="gm-tunnel-stop"
        ?disabled=${s.phase !== "laeuft" && s.phase !== "startet"}
        title="Tunnel beenden — die öffentliche URL verfällt sofort"
        @click=${() => tunnelCmd("stop")}
      >
        ■ Link beenden
      </button>
    </div>
    ${
      s.fehler !== null
        ? html`<p class="muted" data-testid="gm-tunnel-fehler" style="margin:2px 0 6px">
            ${s.phase === "nicht-installiert" ? "🔌" : "⚠️"} ${s.fehler}
            ${s.installHinweise.map(
              (hinweis) =>
                html`<br /><code style="font-size:0.75rem;word-break:break-all">${hinweis}</code>`,
            )}
          </p>`
        : ""
    }
    ${
      s.phase === "laeuft"
        ? html`<p class="muted" style="margin:2px 0 6px">
            ⚠️ Jeder mit dem Link kann beitreten — der Raum-Code bleibt zusätzlich nötig. Der Link
            endet mit dem Server-Stopp (Quick-URLs sind flüchtig).
          </p>`
        : ""
    }`;
}

function showInhalt(
  state: GmAppState,
  v: GmView,
  zeichne: () => void,
  sende: Sende,
  tunnelCmd?: TunnelCmd,
): TemplateResult {
  return html`${tunnelKarte(state, tunnelCmd)} ${musikKarte(state, v, zeichne, sende)}
    <div class="werkzeug-zeile">
      ${["tusch", "trommelwirbel", "fail", "kaching"].map(
        (sfx) =>
          html`<button @click=${() => sende("sound.play", { sfxId: sfx })}>🔊 ${sfx}</button>`,
      )}
      <button
        ?disabled=${v.budgets.encoresDieseRunde >= 2}
        title="Wiederholt den letzten Jubel-Moment auf der Bühne"
        @click=${() => sende("flow.encore", {})}
      >
        🎉 ZUGABE! (${v.budgets.encoresDieseRunde}/2)
      </button>
    </div>
    <div class="werkzeug-zeile">
      <input
        placeholder="Voting-Frage"
        style="flex:1;min-width:160px"
        .value=${state.felder.voteFrage ?? ""}
        @input=${(e: Event) => {
          state.felder.voteFrage = (e.target as HTMLInputElement).value;
          // Gleicher P1-Input-Bug wie beim Flüstern: ohne Re-Render bleibt
          // „Voting starten" disabled, bis ein anderes Event zeichnet.
          zeichne();
        }}
      />
      <input
        placeholder="Optionen (Komma-getrennt)"
        style="flex:1;min-width:160px"
        .value=${state.felder.voteOptionen ?? ""}
        @input=${(e: Event) => {
          state.felder.voteOptionen = (e.target as HTMLInputElement).value;
          zeichne();
        }}
      />
      <button
        ?disabled=${
          !(state.felder.voteFrage ?? "").trim() ||
          (state.felder.voteOptionen ?? "").split(",").filter((o) => o.trim()).length < 2
        }
        @click=${(e: Event) => {
          const ausloeser = e.currentTarget;
          void sende("vote.start", {
            frage: state.felder.voteFrage.trim(),
            optionen: state.felder.voteOptionen
              .split(",")
              .map((o) => o.trim())
              .filter(Boolean),
          }).then((ok) => {
            if (ok) miniToast(ausloeser, "✓ Voting läuft");
          });
          state.felder.voteFrage = "";
          state.felder.voteOptionen = "";
          zeichne();
        }}
      >
        🗳 Voting starten
      </button>
      <button ?disabled=${v.budgets.blitzStimmungen <= 0} @click=${() => sende("mood.poll", {})}>
        ⚡ Blitz-Stimmung (${v.budgets.blitzStimmungen} übrig)
      </button>
      <button ?disabled=${v.feedbackAngefragt} @click=${() => sende("feedback.collect", {})}>
        💬 Feedback einsammeln
      </button>
    </div>
    ${
      v.voting
        ? html`<p style="margin:8px 0 0">
            🗳 <strong>${v.voting.frage}</strong> —
            ${v.voting.optionen.map((o, i) => html`<span style="margin-right:10px">${o}: ${v.voting!.stimmen[i]}</span>`)}
          </p>`
        : ""
    }
    ${
      v.stimmung.length > 0
        ? html`<p class="muted" style="margin:8px 0 0">
            Stimmungen:
            ${v.stimmung.map(
              (s) => html`<span style="margin-right:10px">[${s.werte.join(" / ")}]</span>`,
            )}
            <span>(😴 … 🤩)</span>
          </p>`
        : ""
    }
    ${
      v.feedback.length > 0
        ? html`<div style="margin-top:8px">
            ${v.feedback.map(
              (f) => html`<p style="margin:2px 0">💌 <strong>${f.name}</strong>: ${f.text}</p>`,
            )}
          </div>`
        : ""
    }`;
}

function logInhalt(state: GmAppState): TemplateResult {
  return html`${state.log.length === 0 ? html`<p class="muted">Noch keine Kommandos.</p>` : ""}
  ${[...state.log].reverse().map(
    (e) =>
      html`<div class="log-zeile">
        <span class="muted mono log-zeit">${new Date(e.ts).toLocaleTimeString("de-DE")}</span>
        ${e.text}
      </div>`,
  )}`;
}

function login(state: GmAppState, zeichne: () => void, verbinde: () => void): TemplateResult {
  return html`<div class="zentriert">
    <div class="karte login-karte">
      <h1>🎩 Show-Master</h1>
      <p class="muted" style="margin:0">Code + PIN stehen auf dem Bildschirm.</p>
      ${state.fehler ? html`<p class="login-fehler">${state.fehler}</p>` : ""}
      <label for="gm-code">Raum-Code:</label>
      <input
        id="gm-code"
        class="mono"
        style="text-transform:uppercase;font-size:1.4rem;width:9ch;text-align:center"
        maxlength="4"
        autocapitalize="characters"
        .value=${state.code}
        @input=${(e: Event) => {
          state.code = (e.target as HTMLInputElement).value.toUpperCase();
          zeichne();
        }}
      />
      <label for="gm-pin">PIN (steht auf dem Bildschirm):</label>
      <input
        id="gm-pin"
        class="mono"
        inputmode="numeric"
        style="font-size:1.4rem;width:9ch;text-align:center"
        maxlength="4"
        .value=${state.pin}
        @input=${(e: Event) => {
          state.pin = (e.target as HTMLInputElement).value;
          zeichne();
        }}
      />
      <button
        class="primaer"
        style="width:min(320px,70vw)"
        ?disabled=${state.code.length !== 4 || state.pin.length !== 4}
        @click=${verbinde}
      >
        Raum übernehmen
      </button>
    </div>
  </div>`;
}

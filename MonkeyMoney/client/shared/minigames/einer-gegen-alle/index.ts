// Client-Renderer „Einer gegen alle": Screen = Solisten-PODEST (links, die
// Puppe des Führenden im Goldlicht) gegen die Mengen-TRIBÜNE (rechts, alle
// anderen Puppen in Reihen). Im Frage-Fenster reist NUR die Beteiligung
// (anonymer Stimmen-Balken) — die Verteilungs-Balken fallen erst im
// Enthüllungs-Beat (der Solist sieht die Mengen-Antwort NIE vorher).
// Player = XXL-Antwort-Buttons für beide Seiten; die Menge sieht die
// Stimm-Beteiligung, der Solist bleibt bewusst im Dunkeln (Spannung!).
import { html, render } from "lit-html";
import { EINER_GEGEN_ALLE_ID } from "../../../../shared/minigames/einer-gegen-alle.meta";
import { formatMM } from "../../../../shared/money";
import { timerBalken } from "../../ui";
import type { FxApi, MinigameClientModule, SendAction } from "../types";
import "./einer-gegen-alle.css";

const DEKO = [
  { buchstabe: "A", emoji: "🍌", farbe: "#e6b830" },
  { buchstabe: "B", emoji: "🥥", farbe: "#8a5a3b" },
  { buchstabe: "C", emoji: "🐒", farbe: "#d1495b" },
  { buchstabe: "D", emoji: "🌴", farbe: "#2e8b57" },
] as const;

interface EgaView {
  questionId: string;
  frageNonce: number;
  phase: "vorstellung" | "frage" | "enthuellung" | "ergebnis";
  endsAt: number;
  timerMs: number;
  frageNr: number;
  fragen: number;
  solist: string;
  menge: string[];
  spieler: string[];
  soloPunkte: number;
  teamPunkte: number;
  soloMM: number;
  beideMM: number;
  teamMM: number;
  bilanz: Record<string, number>;
  text: string | null;
  options: string[] | null;
  stimmenAbgegeben: number;
  mengeGroesse: number;
  solistHatGeantwortet: boolean;
  answeredCount: number;
  letzteFrage: {
    optionen: string[];
    correctIndex: number;
    erklaerung: string;
    solistChoice: number | null;
    solistRichtig: boolean;
    mengeChoice: number | null;
    mengeRichtig: boolean;
    gleichstand: boolean;
    verteilung: number[];
    deltas: Record<string, number>;
  } | null;
  ergebnis: {
    neutral: boolean;
    abgebrochen: boolean;
    soloPunkte: number;
    teamPunkte: number;
    sieger: "solist" | "menge" | null;
  } | null;
  finished: boolean;
  duBistSolist?: boolean;
  yourChoice?: number | null;
  aufloesung: {
    correctIndex: number | null;
    erklaerung: string;
    perPlayer: { playerId: string; choice: null; correct: boolean; delta: number }[];
  } | null;
}

function info(fx: FxApi | undefined, playerId: string): { name: string; avatar: string } {
  const s = fx?.spieler?.(playerId);
  return { name: s?.name ?? playerId, avatar: s?.avatar ?? "gelb" };
}

/** Podest (Solist) vs. Tribüne (Menge) — die Bühne des Formats. */
function buehne(fx: FxApi, v: EgaView, opts: { kompakt?: boolean } = {}) {
  const s = info(fx, v.solist);
  return html`<div class="ega-buehne ${opts.kompakt === true ? "kompakt" : ""}">
    <div class="ega-podest">
      <span class="ega-krone">👑</span>
      <span
        class="ega-puppe mm-affe ${v.phase === "vorstellung" ? "mm-affe-idle" : ""}"
        data-avatar=${s.avatar}
        data-gesicht=${
          v.phase === "enthuellung"
            ? v.letzteFrage?.solistRichtig === true
              ? "jubel"
              : "frust"
            : v.phase === "frage"
              ? "denk"
              : "neutral"
        }
      ></span>
      <span class="ega-podest-name">${s.name}</span>
      <span class="ega-punkte solo">⭐ ${v.soloPunkte}</span>
    </div>
    <div class="ega-blitz">⚡ GEGEN ⚡</div>
    <div class="ega-tribuene">
      <div class="ega-tribuene-reihen">
        ${v.menge.map((p, idx) => {
          const i = info(fx, p);
          return html`<span
            class="ega-tribuene-affe mm-affe"
            style="--idle-versatz:${(idx * 0.4).toFixed(1)}s"
            data-avatar=${i.avatar}
            data-gesicht=${
              v.phase === "enthuellung"
                ? v.letzteFrage?.mengeRichtig === true
                  ? "jubel"
                  : "frust"
                : v.phase === "frage"
                  ? "denk"
                  : "neutral"
            }
            title=${i.name}
          ></span>`;
        })}
      </div>
      <span class="ega-tribuene-label">DIE MENGE (${v.mengeGroesse})</span>
      <span class="ega-punkte team">⭐ ${v.teamPunkte}</span>
    </div>
  </div>`;
}

/** Anonymer Beteiligungs-Balken im Frage-Fenster (KEINE Verteilung!). */
function beteiligung(v: EgaView) {
  const anteil = v.mengeGroesse > 0 ? v.stimmenAbgegeben / v.mengeGroesse : 0;
  return html`<div class="ega-beteiligung">
    <span class="ega-beteiligung-label">
      🗳️ ${v.stimmenAbgegeben}/${v.mengeGroesse} Stimmen ·
      ${v.solistHatGeantwortet ? "👑 Solist hat geantwortet" : "👑 Solist überlegt …"}
    </span>
    <div class="ega-beteiligung-balken">
      <span class="ega-beteiligung-fuellung" style="width:${(anteil * 100).toFixed(0)}%"></span>
    </div>
    <span class="ega-anonym muted">Verteilung bleibt geheim bis zur Enthüllung!</span>
  </div>`;
}

/** Enthüllungs-Balken: die Mengen-Verteilung fällt, Marker für beide Seiten. */
function enthuellungsBalken(v: EgaView, optionen: string[]) {
  const f = v.letzteFrage;
  if (f === null) return html``;
  const gesamt = Math.max(
    1,
    f.verteilung.reduce((a, b) => a + b, 0),
  );
  return html`<div class="ega-verteilung">
    ${optionen.map((opt, i) => {
      const stimmen = f.verteilung[i] ?? 0;
      return html`<div
        class="ega-v-zeile ${i === f.correctIndex ? "richtig" : ""} ${
          i === f.mengeChoice ? "menge-wahl" : ""
        }"
      >
        <span class="ega-v-deko" style="--deko:${DEKO[i].farbe}">${DEKO[i].buchstabe}</span>
        <span class="ega-v-text">${opt}</span>
        <span class="ega-v-balken">
          <span class="ega-v-fuellung" style="width:${((stimmen / gesamt) * 100).toFixed(0)}%">
          </span>
        </span>
        <span class="ega-v-stimmen">${stimmen}</span>
        <span class="ega-v-marker">
          ${i === f.solistChoice ? html`<span class="ega-marker solist">👑</span>` : ""}
          ${i === f.mengeChoice ? html`<span class="ega-marker menge">🗳️</span>` : ""}
          ${i === f.correctIndex ? "✅" : ""}
        </span>
      </div>`;
    })}
    ${
      f.gleichstand
        ? html`<p class="ega-gleichstand">
            🎲 Gleichstand in der Menge — das Los hat entschieden!
          </p>`
        : ""
    }
  </div>`;
}

// Phasen-Beats: pro Phase/Nonce EIN Sound (Edge-Detection über den Key).
let letzterSoundKey = "";
function beatSound(v: EgaView, fx: FxApi): void {
  const key = `${v.phase}:${v.frageNonce}`;
  if (key === letzterSoundKey) return;
  letzterSoundKey = key;
  if (v.phase === "vorstellung") fx.sound("applaus-mittel");
  if (v.phase === "frage") fx.sound("frage-ein");
  if (v.phase === "enthuellung" && v.letzteFrage !== null) {
    const deltas = Object.values(v.letzteFrage.deltas).some((d) => d > 0);
    fx.sound(deltas ? "money-mittel" : "falsch");
  }
  if (v.phase === "ergebnis") fx.sound("sieg-fanfare");
}

const modul: MinigameClientModule = {
  id: EINER_GEGEN_ALLE_ID,

  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void {
    const v = view as EgaView;
    beatSound(v, fx);

    if (v.aufloesung || v.phase === "ergebnis") {
      const e = v.ergebnis;
      const s = info(fx, v.solist);
      render(
        html`<div class="ega-screen">
          <div class="ega-kopf"><span class="ega-badge">👑 EINER GEGEN ALLE</span></div>
          ${
            e?.abgebrochen === true
              ? html`<h2 class="ega-titel">Runde abgebrochen — keine Zahlungen.</h2>`
              : e?.neutral === true
                ? html`<h2 class="ega-titel">
                    🔌 Der Solist ist weg — das Format endet neutral, keine Zahlungen.
                  </h2>`
                : e?.sieger === "solist"
                  ? html`<h2 class="ega-titel">
                      👑 <strong>${s.name.toUpperCase()}</strong> schlägt die Menge —
                      ${e.soloPunkte}:${e.teamPunkte} Solo-Coups!
                    </h2>`
                  : e?.sieger === "menge"
                    ? html`<h2 class="ega-titel">
                        🗳️ DIE MENGE triumphiert — ${e.teamPunkte}:${e.soloPunkte} gegen ${s.name}!
                      </h2>`
                    : html`<h2 class="ega-titel">
                        🤝 Unentschieden — ${e?.soloPunkte ?? 0}:${e?.teamPunkte ?? 0}.
                      </h2>`
          }
          ${buehne(fx, v)}
          ${
            v.aufloesung && e?.neutral !== true && e?.abgebrochen !== true
              ? html`<div class="ega-bilanz-liste">
                  ${[...v.aufloesung.perPlayer]
                    .sort((x, y) => y.delta - x.delta)
                    .map(
                      (r) =>
                        html`<div class="ega-bilanz-zeile ${r.delta > 0 ? "plus" : ""}">
                          <span class="ega-mini mm-affe" data-avatar=${info(fx, r.playerId).avatar}>
                          </span>
                          <span>
                            ${info(fx, r.playerId).name}${r.playerId === v.solist ? " 👑" : ""}
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

    if (v.phase === "vorstellung") {
      const s = info(fx, v.solist);
      render(
        html`<div class="ega-screen">
          <div class="ega-kopf"><span class="ega-badge">👑 EINER GEGEN ALLE</span></div>
          <h2 class="ega-titel">
            <strong>${s.name.toUpperCase()}</strong> führt den Zwischenstand an — und tritt jetzt
            ALLEIN gegen alle an!
          </h2>
          ${buehne(fx, v)}
          <p class="ega-regeln muted">
            ${v.fragen} Fragen · Solist richtig + Menge falsch =
            <strong>+${formatMM(v.soloMM)}</strong>
            · beide richtig = je +${formatMM(v.beideMM)} · Menge richtig + Solist falsch = je
            +${formatMM(v.teamMM)} fürs Team. Die Mehrheit entscheidet — anonym bis zur Enthüllung!
          </p>
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "frage") {
      render(
        html`<div class="ega-screen">
          <div class="ega-kopf">
            <span class="ega-badge">👑 FRAGE ${v.frageNr}/${v.fragen}</span>
            <span class="muted">⭐ Solist ${v.soloPunkte} : ${v.teamPunkte} Menge</span>
          </div>
          <h2 class="ega-frage">${v.text ?? ""}</h2>
          ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())}
          <div class="ega-optionen">
            ${(v.options ?? []).map(
              (opt, i) =>
                html`<div class="ega-option" style="--deko:${DEKO[i].farbe}">
                  <span class="ega-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                  ${opt}
                </div>`,
            )}
          </div>
          ${beteiligung(v)} ${buehne(fx, v, { kompakt: true })}
        </div>`,
        host,
      );
      return;
    }

    // ENTHÜLLUNG: die Balken fallen, Marker + Deltas fliegen.
    const f = v.letzteFrage;
    const beat =
      f === null
        ? ""
        : f.solistRichtig && !f.mengeRichtig
          ? html`👑 SOLO-COUP! +${formatMM(v.soloMM)} für den Solisten!`
          : f.solistRichtig && f.mengeRichtig
            ? html`🤝 BEIDE richtig — je +${formatMM(v.beideMM)}!`
            : !f.solistRichtig && f.mengeRichtig
              ? html`🗳️ TEAM-TRIUMPH! Je +${formatMM(v.teamMM)} für die Menge!`
              : html`💨 Beide daneben — nichts fliegt.`;
    render(
      html`<div class="ega-screen">
        <div class="ega-kopf">
          <span class="ega-badge">🔦 ENTHÜLLUNG</span>
          <span class="muted">⭐ Solist ${v.soloPunkte} : ${v.teamPunkte} Menge</span>
        </div>
        <h2 class="ega-titel">${beat}</h2>
        ${enthuellungsBalken(v, f?.optionen ?? [])}
        ${
          f !== null && f.erklaerung.length > 0
            ? html`<p class="ega-erklaerung muted">${f.erklaerung}</p>`
            : ""
        }
        ${buehne(fx, v, { kompakt: true })}
      </div>`,
      host,
    );
  },

  renderPlayer(view: unknown, host: HTMLElement, send: SendAction, fx?: FxApi): void {
    const v = view as EgaView;
    if (v.aufloesung) {
      render(html``, host); // Auflösung rendert die Player-App (kennt „you")
      return;
    }

    const istSolist = v.duBistSolist === true;

    if (v.phase === "vorstellung") {
      render(
        html`<div class="ega-player">
          <div class="ega-status ${istSolist ? "solist" : ""}">
            ${
              istSolist
                ? html`👑 <strong>DU bist der Solist!</strong><br />
                    <span class="muted">
                      Allein gegen ${v.mengeGroesse} — richtig, wenn die Menge patzt:
                      +${formatMM(v.soloMM)}!
                    </span>`
                : html`🗳️ Du gehörst zur <strong>MENGE</strong> — ${info(fx, v.solist).name} tritt
                    allein gegen euch an!<br />
                    <span class="muted">
                      Eure Mehrheits-Antwort zählt. Team-Triumph = je +${formatMM(v.teamMM)}!
                    </span>`
            }
          </div>
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "frage") {
      const gewaehlt = v.yourChoice ?? null;
      render(
        html`<div class="ega-player">
          <p class="ega-rolle ${istSolist ? "solist" : ""}">
            ${istSolist ? "👑 DEINE Solo-Antwort" : "🗳️ Deine Stimme für die Menge"}
          </p>
          <p class="ega-frage-klein">${v.text ?? ""}</p>
          ${(v.options ?? []).map(
            (opt, i) =>
              html`<button
                class="ega-button ${gewaehlt === i ? "gewaehlt" : ""} ${
                  gewaehlt !== null ? "gesperrt" : ""
                }"
                style="--deko:${DEKO[i].farbe}"
                ?disabled=${gewaehlt !== null}
                @click=${() => {
                  fx?.sound("lockin-thunk");
                  void send("answer", { choice: i });
                }}
              >
                <span class="ega-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                ${opt}
              </button>`,
          )}
          ${
            gewaehlt !== null
              ? istSolist
                ? html`<p class="muted" style="text-align:center">
                    Eingerastet — was die Menge wählt, erfährst du ERST bei der Enthüllung …
                  </p>`
                : html`<p class="muted" style="text-align:center">
                    Stimme drin — ${v.stimmenAbgegeben}/${v.mengeGroesse} aus der Menge haben
                    gewählt. Die Mehrheit zählt!
                  </p>`
              : ""
          }
        </div>`,
        host,
      );
      return;
    }

    // Enthüllung/Ergebnis: kompakter Status.
    const f = v.letzteFrage;
    render(
      html`<div class="ega-player">
        <div class="ega-status">
          ${
            v.phase === "enthuellung" && f !== null
              ? html`Richtig war <strong>${DEKO[f.correctIndex]?.buchstabe ?? "?"}</strong> —
                  ${
                    f.solistRichtig && !f.mengeRichtig
                      ? "👑 Solo-Coup!"
                      : f.solistRichtig && f.mengeRichtig
                        ? "🤝 beide richtig!"
                        : !f.solistRichtig && f.mengeRichtig
                          ? "🗳️ Team-Triumph!"
                          : "💨 beide daneben."
                  }
                  ${f.gleichstand ? html`<br /><span class="muted">🎲 Los-Entscheid!</span>` : ""}`
              : v.ergebnis?.sieger === "solist"
                ? html`👑 Der Solist schlägt die Menge!`
                : v.ergebnis?.sieger === "menge"
                  ? html`🗳️ Die Menge triumphiert!`
                  : "🤝 Bilanz läuft …"
          }
        </div>
      </div>`,
      host,
    );
  },

  explainCard: {
    text: "Der FÜHRENDE tritt allein gegen alle an: 6 Fragen. Die Menge stimmt ab — die MEHRHEIT zählt fürs Team. Solist richtig + Menge falsch = +400 für den Solisten. Beide richtig = je +150. Menge richtig + Solist falsch = je +200 fürs Team. Der Solist sieht eure Antwort NICHT vor der Enthüllung!",
    animation: html`<span style="font-size:3rem">👑⚡🐒🐒🐒</span>`,
  },
};

// Erklär-Demo (ADDITIV): Mia (Führende) auf dem Podest gegen Bo + die Menge —
// erst beide richtig (je +150), dann patzt die Menge: Solo-Coup +400!
export const demoChoreo: import("../demo-typen").DemoChoreo = {
  dauer: 11000,
  beats: [
    {
      at: 0,
      requisiten: [{ art: "schild", text: "👑 EINER gegen ALLE", ton: "gold" }],
      pose: { a: "zeig", b: "wackel" },
      gesicht: { a: "jubel", b: "neutral" },
      blase: { wer: "a", text: "Ich führe — ich trete solo an!" },
      sound: "applaus-mittel",
    },
    {
      at: 2400,
      requisiten: [{ art: "frage" }],
      pose: { a: "denk", b: "denk" },
      gesicht: { a: "denk", b: "denk" },
      blase: { wer: "b", text: "Die MEHRHEIT zählt für uns!" },
      sound: "frage-ein",
    },
    {
      at: 4800,
      requisiten: [{ art: "frage", tippA: 0, tippB: 0, richtig: 0 }],
      pose: { a: "jubel", b: "jubel" },
      gesicht: { a: "jubel", b: "jubel" },
      blase: { wer: "a", text: "Beide richtig — je +150!" },
      geldflug: { von: "mitte", zu: "b" },
      sound: "money-klein",
    },
    {
      at: 7200,
      requisiten: [{ art: "frage", tippA: 2, tippB: 1, richtig: 2 }],
      pose: { a: "jubel", b: "frust" },
      gesicht: { a: "jubel", b: "frust" },
      blase: { wer: "a", text: "Menge daneben: SOLO-COUP +400!" },
      geldflug: { von: "mitte", zu: "a" },
      sound: "money-mittel",
    },
    {
      at: 9400,
      requisiten: [{ art: "schild", text: "Anonym bis zur Enthüllung!", ton: "cyan" }],
      pose: { a: "jubel", b: "tipp" },
      gesicht: { a: "jubel", b: "denk" },
      effekt: "konfetti",
      sound: "runden-sieg",
    },
  ],
};

export default modul;

// Client-Renderer „Der Taschendieb-Affe": Screen = Frage-Rennen → Klau-Recht-
// Ansage → KLAU-CUTSCENE (Dieb-Affe mit Maske flitzt zum Opfer, die haarige
// Affenhand trägt den Geldsack rüber — von→zu aus dem Server-View). Der
// Dieb-Affe ist Kiki Krawall (assets/img/monkeys, INLINE eingebettet laut
// README — Gesichts-/Gelenk-Steuerung braucht Inline-SVG).
// Sound-Mapping (ART-PLAN §4.1): Klau „Affenhand" = phaserUp3 + card-shove-2,
// Fehlbuzz/Sperre = error_007 — wartet auf FxApi.sound().
import { html, render } from "lit-html";
import { formatMM, type Schwierigkeit } from "../../../../shared/money";
import { TASCHENDIEB_ID, TD_KLAU_MM } from "../../../../shared/minigames/taschendieb.meta";
import { timerBalken } from "../../ui";
import type { FxApi, MinigameClientModule, SendAction } from "../types";
import "./taschendieb.css";

const DEKO = [
  { buchstabe: "A", emoji: "🍌", farbe: "#e6b830" },
  { buchstabe: "B", emoji: "🥥", farbe: "#8a5a3b" },
  { buchstabe: "C", emoji: "🐒", farbe: "#d1495b" },
  { buchstabe: "D", emoji: "🌴", farbe: "#2e8b57" },
] as const;

interface TdZiel {
  id: string;
  kontostand: number | null;
  verbunden: boolean;
  waehlbar: boolean;
  geschuetzt: boolean;
}

interface TaschendiebView {
  questionId: string;
  text: string;
  options: string[];
  schwierigkeit: Schwierigkeit;
  spieler: string[];
  phase: "frage" | "opferwahl" | "cutscene" | "niemand";
  endsAt: number;
  timerMs: number;
  answeredCount: number;
  dieb: string | null;
  fotofinish: string[];
  klau: { von: string | null; zu: string | null; betrag: number; abgeprallt: boolean } | null;
  finished: boolean;
  yourChoice?: number | null;
  istDieb?: boolean;
  duBistOpfer?: boolean;
  ziele?: TdZiel[] | null;
  aufloesung: {
    correctIndex: number;
    erklaerung: string;
    klau: { von: string | null; zu: string | null; betrag: number; abgeprallt: boolean } | null;
    perPlayer: { playerId: string; choice: number | null; correct: boolean; delta: number }[];
  } | null;
}

// ---------- Dieb-Affe: Kiki Krawall INLINE (Palette-Swap + Gesichter, s. README) ----------
const DIEB_SVG_URL = new URL("../../../../assets/img/monkeys/kiki-krawall.svg", import.meta.url)
  .href;
const SACK_URL = new URL("../../../../assets/img/money/sack.svg", import.meta.url).href;

let diebSvgText: string | null = null;
let diebSvgLaedt = false;

function ladeDiebSvg(): void {
  if (diebSvgText !== null || diebSvgLaedt) return;
  diebSvgLaedt = true;
  void fetch(DIEB_SVG_URL)
    .then((r) => r.text())
    .then((text) => {
      diebSvgText = text;
    })
    .catch(() => {
      diebSvgLaedt = false; // nächster Render probiert es erneut
    });
}

/** Inline-SVG in den Slot setzen (einmalig) + Gesicht/Arm für den Klau posen. */
function befuelleDiebSlot(host: HTMLElement, abgeprallt: boolean): void {
  const slot = host.querySelector<HTMLElement>(".td-dieb-svg");
  if (!slot) return;
  if (diebSvgText === null) {
    ladeDiebSvg();
    return;
  }
  if (slot.dataset.befuellt !== "1") {
    slot.innerHTML = diebSvgText;
    slot.dataset.befuellt = "1";
  }
  const svg = slot.querySelector("svg");
  if (!svg) return;
  svg.dataset.gesicht = abgeprallt ? "frust" : "jubel";
  // Gelenk-Steuerung relativ zum SVG (README): Klau-Arm ausstrecken.
  const arm = svg.querySelector<SVGGElement>("#arm-r");
  if (arm) arm.style.transform = abgeprallt ? "rotate(30deg)" : "rotate(-70deg)";
}

/** Klau-Cutscene: Maske drauf, Hand rüber, Sack wandert von → zu. */
function cutscene(v: TaschendiebView, fx?: FxApi) {
  const klau = v.klau ?? v.aufloesung?.klau ?? null;
  if (!klau) return html``;
  if (klau.von === null) {
    return html`<div class="td-cutscene">
      <p class="td-ansage">🐒 … aber es gibt niemanden zu beklauen!</p>
    </div>`;
  }
  // Echte Namen unter Dieb/Opfer (FxApi.spieler) — Fallback: generische Labels.
  const dieb = klau.zu !== null ? (fx?.spieler?.(klau.zu) ?? null) : null;
  const opfer = klau.von !== null ? (fx?.spieler?.(klau.von) ?? null) : null;
  return html`<div class="td-cutscene ${klau.abgeprallt ? "abgeprallt" : ""}">
    <div class="td-podest td-podest-dieb">
      <span class="td-maske">🦹</span>
      <div class="td-dieb-svg"></div>
      <span class="td-label">
        ${dieb ? dieb.name : "DER TASCHENDIEB"} ${klau.abgeprallt ? "⭐" : ""}
      </span>
    </div>
    <div class="td-flugbahn">
      ${
        klau.abgeprallt
          ? html`<span class="td-schild">🛡️ ABGEPRALLT!</span>`
          : html`<span class="td-hand">
              🤚<img class="td-sack" src=${SACK_URL} alt="Beutesack" />
            </span>`
      }
      <span class="td-betrag ${klau.abgeprallt ? "" : "klaut"}">
        ${klau.abgeprallt ? "0 MM — Bananentresor!" : `−${formatMM(klau.betrag)}`}
      </span>
    </div>
    <div class="td-podest td-podest-opfer">
      ${
        opfer
          ? html`<span
              class="td-opfer-puppe mm-affe"
              data-avatar=${opfer.avatar}
              data-gesicht=${klau.abgeprallt ? "jubel" : "frust"}
            ></span>`
          : html`<span class="td-opfer-affe">${klau.abgeprallt ? "🐵🛡️" : "🙀"}</span>`
      }
      <span class="td-label"
        >${opfer ? opfer.name : "DAS OPFER"}${klau.abgeprallt ? " 🛡️" : ""}</span
      >
    </div>
  </div>`;
}

const modul: MinigameClientModule = {
  id: TASCHENDIEB_ID,

  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void {
    const v = view as TaschendiebView;
    const correct = v.aufloesung?.correctIndex ?? -1;

    if (v.aufloesung) {
      const klau = v.aufloesung.klau;
      render(
        html`<div class="td-screen">
          <p class="muted" style="text-align:center">${v.aufloesung.erklaerung}</p>
          ${
            klau && klau.von !== null
              ? html`<p class="td-ansage">
                  ${
                    klau.abgeprallt
                      ? "🛡️ Der Bananentresor hat den Klau ABPRALLEN lassen!"
                      : html`🐒✋ Beute:
                          <strong style="color:var(--gold)">${formatMM(klau.betrag)}</strong>
                          geklaut!`
                  }
                </p>`
              : html`<p class="td-ansage muted">Kein Klau diese Runde.</p>`
          }
          <div class="td-optionen">
            ${v.options.map(
              (opt, i) =>
                html`<div
                  class="td-option ${i === correct ? "richtig" : "falsch"}"
                  style="--deko:${DEKO[i].farbe}"
                >
                  <span class="td-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                  ${opt}
                </div>`,
            )}
          </div>
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "cutscene") {
      render(html`<div class="td-screen">${cutscene(v, fx)}</div>`, host);
      befuelleDiebSlot(host, v.klau?.abgeprallt ?? false);
      return;
    }

    if (v.phase === "opferwahl") {
      render(
        html`<div class="td-screen">
          <div class="td-suspense">
            <span class="td-maske-gross">🦹🐒</span>
            <h2>Klau-Recht vergeben!</h2>
            <p class="muted">
              Der schnellste richtige Affe wählt GEHEIM sein Opfer …
              ${v.fotofinish.length > 0 ? html`<br />📸 FOTOFINISH — der Zweite kriegt den vollen Grundwert!` : ""}
            </p>
            ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())}
          </div>
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "niemand") {
      render(
        html`<div class="td-screen">
          <div class="td-suspense">
            <span class="td-maske-gross">🐒💨</span>
            <h2>Niemand richtig — der Taschendieb geht leer aus!</h2>
          </div>
        </div>`,
        host,
      );
      return;
    }

    // Phase "frage": das Rennen läuft.
    render(
      html`<div class="td-screen">
        <p class="td-beute-teaser">
          🦹 Schnellste richtige Antwort klaut
          <strong style="color:var(--gold)">${formatMM(TD_KLAU_MM[v.schwierigkeit])}</strong>
          (max. 25 % vom Opfer-Konto)!
        </p>
        <h2 class="td-frage">${v.text}</h2>
        ${timerBalken(v.endsAt, v.timerMs, fx.serverNow())}
        <div class="td-optionen">
          ${v.options.map(
            (opt, i) =>
              html`<div class="td-option" style="--deko:${DEKO[i].farbe}">
                <span class="td-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                ${opt}
              </div>`,
          )}
        </div>
        <p class="muted" style="text-align:center">
          ${v.answeredCount} Antwort${v.answeredCount === 1 ? "" : "en"} eingerastet …
        </p>
      </div>`,
      host,
    );
  },

  renderPlayer(view: unknown, host: HTMLElement, send: SendAction, fx?: FxApi): void {
    const v = view as TaschendiebView;
    if (v.aufloesung) {
      render(html``, host); // Auflösung rendert die Player-App (kennt „you")
      return;
    }

    if (v.phase === "frage") {
      const gewaehlt = v.yourChoice ?? null;
      render(
        html`<div class="td-player">
          <p class="td-frage-klein">${v.text}</p>
          ${v.options.map(
            (opt, i) =>
              html`<button
                class="td-button ${gewaehlt === i ? "gewaehlt" : ""} ${gewaehlt !== null ? "gesperrt" : ""}"
                style="--deko:${DEKO[i].farbe}"
                ?disabled=${gewaehlt !== null}
                @click=${() => send("answer", { choice: i })}
              >
                <span class="td-deko">${DEKO[i].buchstabe} ${DEKO[i].emoji}</span>
                ${opt}
              </button>`,
          )}
          ${
            gewaehlt !== null
              ? html`<p class="muted" style="text-align:center">
                  Eingerastet — schnellste richtige Antwort klaut!
                </p>`
              : ""
          }
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "opferwahl") {
      if (v.istDieb && v.ziele) {
        render(
          html`<div class="td-player">
            <h2 style="text-align:center">🦹 Bei wem klaust du?</h2>
            <p class="muted" style="text-align:center">
              Geheime Wahl — Timeout nimmt den Reichsten!
            </p>
            ${v.ziele.map((z, i) => {
              // Echte Namen + Affen-Köpfe im Ziel-Grid (FxApi.spieler).
              const info = fx?.spieler?.(z.id) ?? null;
              return html`<button
                class="td-ziel ${z.waehlbar ? "" : "gesperrt"}"
                ?disabled=${!z.waehlbar}
                @click=${() => send("steal", { targetId: z.id })}
              >
                <span class="td-ziel-wer">
                  ${
                    info
                      ? html`<span class="td-ziel-puppe mm-affe" data-avatar=${info.avatar}></span>
                          ${info.name}`
                      : html`🐵 Affe ${i + 1}`
                  }
                  ${z.geschuetzt ? "🛡️" : ""} ${z.verbunden ? "" : "📴"}
                </span>
                <span class="td-ziel-konto">
                  ${z.kontostand === null ? "?" : formatMM(z.kontostand)}
                </span>
                ${z.waehlbar ? "" : html`<span class="td-antimobbing">Anti-Mobbing-Schutz</span>`}
              </button>`;
            })}
          </div>`,
          host,
        );
        return;
      }
      render(
        html`<div class="td-verdeckt">
          <span style="font-size:5rem">🦹</span>
          <h2>Der Taschendieb sucht sein Opfer …</h2>
          <p class="muted">Halt deine Taschen fest!</p>
        </div>`,
        host,
      );
      return;
    }

    if (v.phase === "cutscene") {
      const klau = v.klau;
      render(
        html`<div class="td-verdeckt">
          ${
            v.duBistOpfer
              ? html`<span style="font-size:5rem">${klau?.abgeprallt ? "🛡️" : "🙀✋"}</span>
                  <h2>${klau?.abgeprallt ? "Dein Bananentresor hält!" : "DU wirst beklaut!"}</h2>
                  <p style="color:var(--rot);font-size:1.5rem">
                    ${klau?.abgeprallt ? "0 MM weg." : `−${formatMM(klau?.betrag ?? 0)}`}
                  </p>`
              : v.istDieb
                ? html`<span style="font-size:5rem">🦹💰</span>
                    <h2>${klau?.abgeprallt ? "Abgeprallt!" : "Deine Beute!"}</h2>
                    <p style="color:var(--gold);font-size:1.5rem">
                      +${formatMM(klau?.betrag ?? 0)}
                    </p>`
                : html`<span style="font-size:5rem">🍿</span>
                    <h2>Der Taschendieb schlägt zu …</h2>`
          }
        </div>`,
        host,
      );
      return;
    }

    render(
      html`<div class="td-verdeckt">
        <span style="font-size:5rem">🐒💨</span>
        <h2>Niemand richtig — kein Klau.</h2>
      </div>`,
      host,
    );
  },

  explainCard: {
    text: "Alle kriegen dieselbe Frage — die SCHNELLSTE richtige Antwort darf beim Wunsch-Opfer klauen (300/500 MM, max. 25 % vom Konto). Mitmachen lohnt: alle anderen Richtigen kriegen den halben Grundwert.",
    animation: html`<span style="font-size:3rem">🦹🤚💰🙀</span>`,
  },
};

// Erklär-Demo (ADDITIV): die schnellste richtige Antwort darf klauen —
// Mias Hand schnappt sich Bos Scheine.
export const demoChoreo: import("../demo-typen").DemoChoreo = {
  dauer: 11200,
  beats: [
    {
      at: 0,
      requisiten: [{ art: "frage" }],
      pose: { a: "denk", b: "denk" },
      gesicht: { a: "denk", b: "denk" },
    },
    {
      at: 2200,
      requisiten: [{ art: "frage", tippA: 0 }],
      pose: { a: "tipp", b: "denk" },
      gesicht: { a: "neutral", b: "denk" },
      blase: { wer: "a", text: "Mia ist die Schnellste!" },
      sound: "lockin-thunk",
    },
    {
      at: 4400,
      requisiten: [{ art: "frage", tippA: 0, tippB: 0, richtig: 0 }],
      pose: { a: "jubel", b: "jubel" },
      gesicht: { a: "jubel", b: "jubel" },
      sound: "richtig",
    },
    {
      at: 6200,
      requisiten: [
        { art: "frage", tippA: 0, tippB: 0, richtig: 0 },
        { art: "schild", text: "−300 MM", ton: "rot", bei: "b" },
      ],
      pose: { a: "schleich", b: "frust" },
      gesicht: { a: "jubel", b: "frust" },
      blase: { wer: "a", text: "Mia klaut bei Bo! 🤚" },
      geldflug: { von: "b", zu: "a" },
      sound: "klau",
    },
    {
      at: 8900,
      requisiten: [{ art: "schild", text: "+300 MM geklaut", ton: "gold", bei: "a" }],
      pose: { a: "jubel", b: "frust" },
      gesicht: { a: "jubel", b: "frust" },
      blase: { wer: "b", text: "Miese Masche!" },
      effekt: "konfetti",
    },
  ],
};

export default modul;

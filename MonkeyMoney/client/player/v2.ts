// v2-Features (Handy): Replay-Highlights („DU warst das!"), Sudden-Death-
// Kokosnuss-Shake (Tap-Frenzy mit ~250-ms-Batches) und Foto-Finish
// („Bild speichern" als data-URL — HTTP-tauglich, kein Server-Roundtrip).
import { html, type TemplateResult } from "lit-html";
import { detectCaps } from "../../shared/caps";
import { formatMM } from "../../shared/money";
import type { PlayerView } from "../../shared/views";
import { avatarFarbe } from "../shared/fx/avatar";
import {
  fotoDateiname,
  fotoDatum,
  ladeFotoHerunter,
  zeichneFotoFinish,
} from "../shared/foto-finish";
import type { SendeAktion } from "./views";

const caps = detectCaps();

/** Icon je Highlight-Art (identisch zum Screen — bewusst dupliziert statt Import-Zyklus). */
const HIGHLIGHT_ICON: Record<string, string> = {
  "groesster-klau": "🕵️",
  "knappster-buzzer": "⚡",
  "teuerste-falschantwort": "💸",
  "bank-verrat": "🏦",
  comeback: "📈",
  jackpot: "🏺",
};

// ---------- Replay-Highlights: eigene Beteiligung hervorheben ----------

export function highlightsHandy(view: PlayerView, serverNow: number): TemplateResult {
  const hl = view.highlights;
  if (!hl) return html`<div class="zentriert"><h2>🎬 Die Highlights des Abends …</h2></div>`;
  const karte = hl.karten[hl.index];
  const meins = karte.playerId === view.you.id;
  const beteiligt = karte.gegnerId === view.you.id;
  const rest = Math.max(0, hl.endetAt - serverNow);
  const fortschritt = 1 - Math.min(1, rest / Math.max(1, hl.karteMs));
  return html`<div class="zentriert" style="gap:10px" data-testid="highlight-karte">
    <p class="muted" style="margin:0">🎬 Highlight ${hl.index + 1} / ${hl.karten.length}</p>
    <div
      style="display:flex;flex-direction:column;align-items:center;gap:8px;padding:18px 20px;
             border-radius:16px;background:var(--bg2);max-width:min(360px,90vw);text-align:center;
             ${meins ? "outline:4px solid var(--gold);box-shadow:0 0 26px rgb(255 201 60 / 45%)" : ""}"
    >
      ${
        meins
          ? html`<span
              data-testid="du-warst-das"
              style="font-size:1.3rem;font-weight:900;color:var(--gold)"
              >⭐ DU warst das! ⭐</span
            >`
          : beteiligt
            ? html`<span style="font-weight:800;color:var(--rot)">😬 DU warst beteiligt …</span>`
            : ""
      }
      <span style="font-size:3rem;line-height:1">${HIGHLIGHT_ICON[karte.art] ?? "🎬"}</span>
      <h2 style="margin:0;color:var(--gold)">${karte.titel}</h2>
      <p style="margin:0">${karte.text}</p>
      ${
        karte.betrag !== undefined
          ? html`<strong class="mm-money-zahl" style="font-size:1.4rem;color:var(--gold)">
              ${formatMM(karte.betrag)}
            </strong>`
          : ""
      }
    </div>
    <div
      style="width:min(300px,80vw);height:8px;border-radius:4px;background:var(--bg2);overflow:hidden"
    >
      <div
        style="height:100%;width:${(fortschritt * 100).toFixed(1)}%;background:var(--gold);transition:width 0.15s linear"
      ></div>
    </div>
  </div>`;
}

// ---------- Sudden-Death: Kokosnuss-Shake (Tap-Frenzy) ----------

// Tap-Batching: Taps lokal zählen und alle ~250 ms als EIN shake.tap senden —
// jeder Einzel-Tap als Socket-Nachricht würde Funk + Server fluten.
const BATCH_MS = 250;
let tapsLokal = 0; // Gesamt (sofortiges UI-Feedback)
let tapsUngesendet = 0;
let batchTimer: number | null = null;
let shakeKey = ""; // Runde gewechselt ⇒ lokale Zähler zurücksetzen

function tap(sende: SendeAktion, zeichne: () => void): void {
  tapsLokal += 1;
  tapsUngesendet += 1;
  if (caps.vibrate) navigator.vibrate(12);
  batchTimer ??= window.setTimeout(() => {
    batchTimer = null;
    const n = Math.min(40, tapsUngesendet);
    tapsUngesendet = 0;
    if (n > 0) sende("shake.tap", { taps: n });
  }, BATCH_MS);
  zeichne();
}

export function tiebreakerHandy(
  view: PlayerView,
  serverNow: number,
  sende: SendeAktion,
  zeichne: () => void,
): TemplateResult {
  const tb = view.tiebreaker;
  if (!tb) return html`<div class="zentriert"><h2>💥 SUDDEN DEATH!</h2></div>`;
  const key = `${tb.runde}:${tb.subphase}`;
  if (shakeKey !== key) {
    shakeKey = key;
    tapsLokal = 0;
    tapsUngesendet = 0;
  }
  const dabei = tb.teilnehmer.some((t) => t.playerId === view.you.id);
  const rest = Math.max(0, tb.endetAt - serverNow);
  const kopf = html`<h2 style="margin:0;color:var(--rot)">💥 SUDDEN DEATH</h2>
    <p class="muted" style="margin:0">
      Gleichstand bei ${formatMM(tb.betrag)}${tb.runde > 1 ? ` — Runde ${tb.runde}` : ""}
    </p>`;

  if (tb.subphase === "ergebnis") {
    const sieger = tb.teilnehmer.find((t) => t.playerId === tb.siegerId);
    const ich = tb.siegerId === view.you.id;
    return html`<div class="zentriert" style="gap:10px">
      ${kopf}
      <h1 style="margin:0">
        ${ich ? "🥇 DU knackst die Kokosnuss!" : `🥥 ${sieger?.name ?? "?"} gewinnt!`}
      </h1>
      ${tb.teilnehmer.map(
        (t) =>
          html`<p
            style="margin:0;${t.playerId === tb.siegerId ? "color:var(--gold);font-weight:800" : ""}"
          >
            ${t.name}: ${t.taps} Taps
          </p>`,
      )}
    </div>`;
  }

  if (!dabei) {
    // Zuschauer: Live-Duell mitverfolgen.
    return html`<div class="zentriert" style="gap:10px">
      ${kopf}
      <p style="margin:0">🥥 ${tb.teilnehmer.map((t) => t.name).join(" vs. ")}</p>
      ${
        tb.subphase === "shake"
          ? tb.teilnehmer.map(
              (t) =>
                html`<p style="margin:0;font-size:1.2rem">
                  <strong>${t.name}</strong>: ${t.taps} Taps
                </p>`,
            )
          : html`<p class="muted">
              Gleich geht's los — Countdown ${Math.max(1, Math.ceil(rest / 1000))} …
            </p>`
      }
    </div>`;
  }

  if (tb.subphase === "countdown") {
    return html`<div class="zentriert" style="gap:12px">
      ${kopf}
      <h1 style="font-size:4rem;margin:0;color:var(--gold)">
        ${Math.max(1, Math.ceil(rest / 1000))}
      </h1>
      <p style="margin:0;font-size:1.15rem">🥥 Gleich: TIPP SO SCHNELL DU KANNST!</p>
    </div>`;
  }

  // subphase "shake": das eigene Tap-Inferno.
  const serverTaps = tb.teilnehmer.find((t) => t.playerId === view.you.id)?.taps ?? 0;
  const anzeige = Math.max(serverTaps, tapsLokal);
  return html`<div class="zentriert" style="gap:12px">
    ${kopf}
    <p style="margin:0;font-size:1.15rem">
      Noch <strong style="color:var(--gold)">${Math.ceil(rest / 1000)} s</strong>!
    </p>
    <button
      class="buzzer-xxl"
      data-testid="shake-knopf"
      style="--spielerfarbe:${avatarFarbe(view.you.avatar)};font-size:2rem"
      @click=${() => tap(sende, zeichne)}
    >
      🥥 SHAKE!
    </button>
    <h1 class="mm-money-zahl" style="margin:0;color:var(--gold)">${anzeige} Taps</h1>
  </div>`;
}

// ---------- Foto-Finish: „Bild speichern" auf dem Handy ----------

let fotoUrl: string | null = null;
let fotoKey = "";

export function fotoFinishHandy(
  view: PlayerView,
  serverNow: number,
  zeichne: () => void,
): TemplateResult {
  const key = view.standings.map((s) => `${s.id}${s.balance}`).join(",");
  if (fotoKey !== key) {
    fotoKey = key;
    fotoUrl = null;
  }
  const erzeuge = (): void => {
    fotoUrl ??= zeichneFotoFinish({ standings: view.standings, datum: fotoDatum(serverNow) });
    if (fotoUrl !== null) ladeFotoHerunter(fotoUrl, fotoDateiname(serverNow));
    zeichne();
  };
  return html`<div
    style="display:flex;flex-direction:column;align-items:center;gap:8px"
    data-testid="foto-finish"
  >
    ${
      fotoUrl !== null
        ? html`<img
            src=${fotoUrl}
            alt="Foto-Finish Ergebnis-Bild"
            style="width:min(200px,60vw);border-radius:10px;border:2px solid var(--gold)"
          />`
        : ""
    }
    <button class="primaer" style="width:min(340px,86vw)" @click=${erzeuge}>
      📸 Bild speichern
    </button>
    ${fotoUrl !== null ? html`<p class="muted" style="margin:0;font-size:0.85rem">Lange aufs Bild tippen zum Teilen!</p>` : ""}
  </div>`;
}

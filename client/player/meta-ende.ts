// Match-Ende-Meta am Handy (§7.5, Meta-Agent 2): Sobald die Siegerehrung
// läuft, pollt das Gerät /api/meta/profile/:id/match-meta (der Server braucht
// 1-2 s, bis Event-Log + Quest-/Pass-Buchung durch sind) und zeigt dann ein
// Bottom-Sheet: „+80 XP · Daily 2/3 ✓ · LEVEL UP!" — mit Handy-Konfetti im
// eigenen Konfetti-Stil. Alles lebt in einem EIGENEN Overlay außerhalb des
// lit-Render-Baums (main.ts hängt nur den metaEndeBeobachte-Hook ein).
import { html, render, type TemplateResult } from "lit-html";
import { konfettiStilAus } from "../../shared/meta";
import type { PlayerView } from "../../shared/views";
import { createPartikel, type PartikelApi } from "../shared/fx/partikel";
import { metaFetch } from "../shared/meta-fetch";
import { aktivesProfilId } from "./meta-join";

/** Wire-Format von GET /api/meta/profile/:id/match-meta (server/meta/index.ts). */
interface MatchMetaWire {
  matchId: string;
  ts: number;
  profileId: string;
  at: number;
  atGesamt: number;
  level: number;
  levelUp: { von: number; zu: number } | null;
  xp: number;
  stufeVorher: number;
  stufeNeu: number;
  saisonId: string;
  belohnungen: {
    stufe: number;
    art: "at" | "item";
    at?: number;
    itemId?: string;
  }[];
  quests: {
    questId: string;
    art: "daily" | "monat";
    text: string;
    ziel: number;
    vorher: number;
    nachher: number;
    fertigJetzt: boolean;
    xp: number;
  }[];
}

const MAX_VERSUCHE = 20;
const POLL_MS = 1200;
/** Ergebnisse älter als 5 min sind vom LETZTEN Abend — nie anzeigen. */
const MAX_ALTER_MS = 5 * 60_000;

const zustand = {
  sichtbar: false,
  ergebnis: null as MatchMetaWire | null,
  gezeigtFuer: null as string | null, // matchId der letzten Anzeige
  pollLaeuft: false,
  avatar: "",
};

const STYLE = `
  .mm-ende-overlay { position: fixed; inset: 0; z-index: 60; display: flex;
    align-items: flex-end; justify-content: center; pointer-events: none; }
  .mm-ende-overlay canvas { position: absolute; inset: 0; width: 100%; height: 100%; }
  .mm-ende-panel { pointer-events: auto; width: min(440px, 100%);
    max-height: 72vh; overflow-y: auto; background: var(--panel, #1f2430);
    border-radius: 18px 18px 0 0; padding: 14px 16px 18px;
    box-shadow: 0 -8px 30px rgba(0,0,0,0.45); border: 2px solid var(--gold, #f5b301);
    border-bottom: none; animation: mm-ende-rein 0.45s cubic-bezier(0.2, 0.9, 0.3, 1.1); }
  @keyframes mm-ende-rein { from { transform: translateY(105%); } to { transform: translateY(0); } }
  .mm-ende-panel h3 { margin: 0 0 8px; }
  .mm-ende-levelup { margin: 8px 0; padding: 8px 12px; border-radius: 12px;
    background: linear-gradient(120deg, rgba(245,179,1,0.25), rgba(255,201,60,0.12));
    border: 2px solid var(--gold, #f5b301); font-weight: 800; text-align: center;
    font-size: 1.05rem; animation: mm-ende-puls 1.2s ease-in-out infinite; }
  @keyframes mm-ende-puls { 0%,100% { transform: scale(1); } 50% { transform: scale(1.03); } }
  .mm-ende-zeile { display: flex; gap: 8px; align-items: baseline;
    padding: 4px 0; border-bottom: 1px solid rgba(255,246,227,0.08); font-size: 0.92rem; }
  .mm-ende-zeile .wert { margin-left: auto; font-weight: 800; color: var(--gold, #f5b301);
    white-space: nowrap; }
  .mm-ende-zeile .fertig { color: var(--gruen, #8fe04b); }
  .mm-ende-quest-balken { height: 7px; border-radius: 4px; flex: 0 0 52px;
    background: rgba(255,246,227,0.12); overflow: hidden; align-self: center; }
  .mm-ende-quest-balken > div { height: 100%; background: var(--gold, #f5b301); }
  .mm-ende-panel button { width: 100%; margin-top: 12px; min-height: 46px; }
`;

let wurzel: HTMLElement | null = null;
let panel: HTMLElement | null = null;
let canvas: HTMLCanvasElement | null = null;
let partikel: PartikelApi | null = null;

function stelleDomSicher(): void {
  if (wurzel !== null) return;
  const style = document.createElement("style");
  style.textContent = STYLE;
  document.head.appendChild(style);
  wurzel = document.createElement("div");
  wurzel.className = "mm-ende-overlay";
  wurzel.style.display = "none";
  canvas = document.createElement("canvas");
  wurzel.appendChild(canvas);
  panel = document.createElement("div");
  panel.className = "mm-ende-panel";
  wurzel.appendChild(panel);
  document.body.appendChild(wurzel);
}

function questZeile(q: MatchMetaWire["quests"][number]): TemplateResult {
  const anteil = Math.min(100, Math.round((q.nachher / q.ziel) * 100));
  return html`<div class="mm-ende-zeile">
    <span>${q.art === "daily" ? "📅" : "🗓️"} ${q.text}</span>
    <span class="mm-ende-quest-balken"><div style="width:${anteil}%"></div></span>
    <span class="wert ${q.fertigJetzt ? "fertig" : ""}">
      ${q.nachher}/${q.ziel}${q.fertigJetzt ? ` ✓ +${q.xp} XP` : ""}
    </span>
  </div>`;
}

function panelInhalt(e: MatchMetaWire): TemplateResult {
  const stufenSprung = e.stufeNeu > e.stufeVorher;
  return html`
    <h3>🍌 Deine Match-Ausbeute</h3>
    ${
      e.levelUp !== null
        ? html`<div class="mm-ende-levelup">
            ⬆️ LEVEL UP! Lv ${e.levelUp.von} → Lv ${e.levelUp.zu}
          </div>`
        : ""
    }
    <div class="mm-ende-zeile" title="AT = All-Time-Bananen: dein Dauer-Konto">
      <span>💰 AT (All-Time-Bananen)</span>
      <span class="wert">+${e.at.toLocaleString("de-DE")} AT</span>
    </div>
    <div class="mm-ende-zeile">
      <span>✨ Bananen-Pass</span>
      <span class="wert">
        +${e.xp} XP ${stufenSprung ? `→ Stufe ${e.stufeNeu}/30 🎉` : `(Stufe ${e.stufeNeu}/30)`}
      </span>
    </div>
    ${e.belohnungen.map(
      (b) =>
        html`<div class="mm-ende-zeile">
          <span>🎁 Pass-Stufe ${b.stufe}</span>
          <span class="wert fertig">
            ${b.art === "at" ? `+${b.at} Bonus-AT` : "Saison-Item freigeschaltet!"}
          </span>
        </div>`,
    )}
    ${e.quests.map((q) => questZeile(q))}
    <button
      @click=${() => {
        verstecke();
      }}
    >
      Weiter
    </button>
  `;
}

function zeige(e: MatchMetaWire): void {
  stelleDomSicher();
  if (!wurzel || !panel) return;
  zustand.sichtbar = true;
  wurzel.style.display = "flex";
  // Partikel ERST jetzt anlegen: createPartikel liest die Canvas-Maße einmalig —
  // solange das Overlay display:none ist, wären sie 0×0 (unsichtbares Konfetti).
  if (partikel === null && canvas !== null) partikel = createPartikel(canvas);
  render(panelInhalt(e), panel);
  // Handy-Konfetti im EIGENEN Stil (§7.4) — beim Level-Up eine Extra-Salve.
  const stil = konfettiStilAus(zustand.avatar);
  partikel?.konfetti({ stil, anzahl: 44 });
  window.setTimeout(() => partikel?.konfetti({ stil, anzahl: 32 }), 500);
  if (e.levelUp !== null) {
    if (navigator.vibrate) navigator.vibrate([60, 60, 60, 60, 160]);
    window.setTimeout(() => partikel?.moneyRegen({ stil, anzahl: 24 }), 900);
  }
}

function verstecke(): void {
  zustand.sichtbar = false;
  if (wurzel) wurzel.style.display = "none";
  partikel?.leeren();
}

async function polle(profileId: string, versuch: number): Promise<void> {
  if (versuch >= MAX_VERSUCHE) {
    zustand.pollLaeuft = false;
    return;
  }
  try {
    const r = await metaFetch(`/api/meta/profile/${profileId}/match-meta`);
    if (r.ok) {
      const d = r.json as { ergebnis: MatchMetaWire | null };
      const e = d.ergebnis;
      // Epoch-Zeit OHNE Date.now (Lint-Konvention): timeOrigin + monotone Uhr.
      const jetzt = performance.timeOrigin + performance.now();
      if (e !== null && e.matchId !== zustand.gezeigtFuer && jetzt - e.ts < MAX_ALTER_MS) {
        zustand.ergebnis = e;
        zustand.gezeigtFuer = e.matchId;
        zustand.pollLaeuft = false;
        zeige(e);
        return;
      }
    }
  } catch {
    // Netz-Hänger: einfach weiter pollen.
  }
  window.setTimeout(() => void polle(profileId, versuch + 1), POLL_MS);
}

let letztePhase = "";

/**
 * Von main.ts bei jedem Snapshot gerufen: startet das Ergebnis-Polling GENAU
 * beim Übergang in die Siegerehrung (einmal pro Match-Ende) und räumt das
 * Overlay auf, sobald es zurück in die Lobby/nächste Runde geht. Ohne aktives
 * Profil passiert nichts — Gäste haben keine Quests (§7.1).
 */
export function metaEndeBeobachte(view: PlayerView): void {
  const istEnde = view.phase === "siegerehrung" || view.phase === "ende";
  const warEnde = letztePhase === "siegerehrung" || letztePhase === "ende";
  letztePhase = view.phase;
  const profileId = aktivesProfilId();
  if (profileId === null) return;
  zustand.avatar = String(view.you.avatar);
  if (istEnde && !warEnde && !zustand.pollLaeuft) {
    zustand.pollLaeuft = true;
    void polle(profileId, 0);
  } else if (!istEnde && zustand.sichtbar) {
    verstecke();
  }
}

// Kleine gemeinsame lit-html-Bausteine aller drei Clients.
import { html, type TemplateResult } from "lit-html";
import { formatMM } from "../../shared/money";
import type { PauseInfo, SpielerPublic } from "../../shared/views";
import { avatarFarbe } from "./fx/avatar";

/** Farb-Punkt — versteht Alt-Format ("gelb") UND Neu-Format ("affe.farbe"). */
export function avatarDot(avatar: string): TemplateResult {
  return html`<span class="avatar-dot" style="--dot:${avatarFarbe(avatar)}"></span>`;
}

/** Spieler-Chip mit „offline"-Badge während der Grace-Period. */
export function spielerChip(p: SpielerPublic): TemplateResult {
  return html`<span class="spieler-chip ${p.connected ? "" : "offline"}">
    ${avatarDot(p.avatar)} ${p.name}
    ${p.connected ? "" : html`<span class="badge-offline">offline</span>`}
  </span>`;
}

/** Zwischenstand mit Einflug-Choreo (Zeilen fliegen gestaffelt ein). */
export function zwischenstand(
  standings: { id: string; name: string; avatar: string; balance: number }[],
  meineId?: string,
): TemplateResult {
  return html`<div
    class="zwischenstand-choreo"
    style="display:flex;flex-direction:column;gap:8px;align-items:center"
  >
    ${standings.map(
      (s, i) =>
        html`<div
          class="zwischenstand-zeile"
          style="--einflug-index:${i};${s.id === meineId ? "outline:3px solid var(--gold)" : ""}"
        >
          <strong>${i + 1}.</strong> ${avatarDot(s.avatar)} ${s.name}
          <span class="betrag">${formatMM(s.balance)}</span>
        </div>`,
    )}
  </div>`;
}

/** Pause = Timeout-Screen auf Screen UND Playern (GM-Kommando session.pause).
 * Mit `bis` (Bananen-Pause) läuft ein Countdown auf allen Geräten. */
export function pauseOverlay(paused: PauseInfo | null, serverNow?: number): TemplateResult {
  if (!paused) return html``;
  const rest =
    paused.bis !== undefined && serverNow !== undefined
      ? Math.max(0, paused.bis - serverNow)
      : null;
  const countdown =
    rest !== null
      ? `${Math.floor(rest / 60_000)}:${String(Math.floor((rest % 60_000) / 1000)).padStart(2, "0")}`
      : null;
  return html`<div class="pause-overlay">
    <h1>⏸ PAUSE</h1>
    <p style="font-size:1.2rem">${paused.text}</p>
    ${
      countdown !== null
        ? html`<p class="mono" style="font-size:2.6rem;color:var(--gold)">${countdown}</p>`
        : ""
    }
    <p class="muted">Der Show-Master macht gleich weiter …</p>
  </div>`;
}

/**
 * Timer-Banane (assets/img/ui/timer-banane.svg, inline für die CSS-Variable):
 * wird von rechts „aufgegessen" — ersetzt überall den nackten Balken.
 * Rendert lokal aus {endsAt}+Offset — kein Server-Tick-Spam.
 */
export function timerBalken(
  endsAt: number,
  timerMs: number,
  serverNow: number,
  schmal = false,
): TemplateResult {
  const rest = Math.max(0, endsAt - serverNow);
  const fortschritt = Math.min(1, rest / Math.max(1, timerMs));
  const kritisch = rest > 0 && rest <= 5_000; // letzte 5 s: Pulsieren (Design §2.0)
  return html`<div
    class="mm-timer-banane ${kritisch ? "kritisch" : ""} ${schmal ? "schmal" : ""}"
    style="--fortschritt:${fortschritt.toFixed(3)}"
  >
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 480 120"
      role="img"
      aria-label="Timer-Banane"
    >
      <g class="banane-geist" opacity="0.3">
        <path
          d="M 40 44 C 90 86 200 106 300 100 C 380 95 432 72 448 46"
          fill="none"
          stroke="#FFF6E3"
          stroke-width="40"
          stroke-linecap="round"
          stroke-dasharray="2 16"
        />
      </g>
      <g class="banane-voll">
        <path
          d="M 40 44 C 90 86 200 106 300 100 C 380 95 432 72 448 46"
          fill="none"
          stroke="#1A1208"
          stroke-width="52"
          stroke-linecap="round"
        />
        <path
          d="M 40 44 C 90 86 200 106 300 100 C 380 95 432 72 448 46"
          fill="none"
          stroke="#FFC93C"
          stroke-width="40"
          stroke-linecap="round"
        />
        <path
          d="M 60 62 C 110 94 210 108 300 102"
          fill="none"
          stroke="#FFDE6B"
          stroke-width="10"
          stroke-linecap="round"
        />
        <path d="M 34 38 L 22 26" stroke="#1A1208" stroke-width="16" stroke-linecap="round" />
        <path d="M 452 40 L 462 28" stroke="#1A1208" stroke-width="14" stroke-linecap="round" />
      </g>
    </svg>
  </div>`;
}

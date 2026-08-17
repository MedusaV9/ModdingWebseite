// Team-Modus „Affenbanden" (GAME-DESIGN §1.4): gemeinsame lit-html-Bausteine
// für Screen + Player — Lobby-Wahl (Buttons/Spalten), Team-Zwischenstand mit
// Individual-Aufschlüsselung und das Team-Podest der Siegerehrung.
// Bewusst NUR Inline-Styles: kein CSS-File-Anfassen (parallele Agents).
import { html, type TemplateResult } from "lit-html";
import { formatMM } from "../../shared/money";
import type { SiegerehrungView, TeamEintragView, TeamsView } from "../../shared/views";
import { avatarDot } from "./ui";

/** Team des Spielers (deinTeam) — null wenn (noch) keins. */
function eigenesTeam(teams: TeamsView | null): TeamEintragView | null {
  if (!teams || teams.deinTeam === undefined || teams.deinTeam === null) return null;
  return teams.teams.find((t) => t.id === teams.deinTeam) ?? null;
}

/** Kleines Team-Abzeichen für den Handy-Kopf (nur im laufenden Team-Match). */
export function teamBadge(teams: TeamsView | null): TemplateResult {
  const team = eigenesTeam(teams);
  if (!team || teams?.wahlOffen) return html``;
  return html`<span
    data-testid="team-badge"
    style="display:inline-flex;align-items:center;gap:4px;padding:2px 10px;border-radius:999px;border:2px solid ${team.farbe};background:color-mix(in srgb, ${team.farbe} 18%, transparent);font-size:0.85rem;font-weight:700;white-space:nowrap"
  >
    ${team.emoji} ${team.name}
  </span>`;
}

/** Doppel-Affe-Tag (zählt im Team-Topf ×2 — ungerade Zahl, 2er-Modus). */
function doppelAffeTag(m: TeamEintragView["mitglieder"][number]): TemplateResult {
  return m.doppelAffe
    ? html`<span title="Doppel-Affe: zählt im Team-Topf doppelt" style="font-weight:800"
        >🐵🐵×2</span
      >`
    : html``;
}

/**
 * Lobby-Wahl-Spalten (Screen): eine Spalte pro Team mit den Wunsch-Affen.
 * Unter minSpieler Spielern weist eine Zeile darauf hin, dass das Match
 * (noch) individuell startet.
 */
export function teamSpalten(teams: TeamsView, spielerzahl: number): TemplateResult {
  return html`<div
    data-testid="team-spalten"
    style="display:flex;flex-direction:column;gap:8px;align-items:center"
  >
    <p class="muted" style="margin:0">
      🐒 AFFENBANDEN (${teams.modus}) — wählt euer Team auf den Handys!
    </p>
    <div style="display:flex;gap:14px;justify-content:center;flex-wrap:wrap">
      ${teams.teams.map(
        (t) =>
          html`<div
            style="min-width:150px;padding:10px 14px;border-radius:14px;border:3px solid ${t.farbe};background:color-mix(in srgb, ${t.farbe} 12%, transparent);display:flex;flex-direction:column;gap:6px;align-items:center"
          >
            <strong style="font-size:1.1rem">${t.emoji} ${t.name}</strong>
            ${
              t.mitglieder.length === 0
                ? html`<span class="muted" style="font-size:0.85rem">– frei –</span>`
                : t.mitglieder.map(
                    (m) =>
                      html`<span style="display:flex;align-items:center;gap:6px">
                        ${avatarDot(m.avatar)} ${m.name}
                      </span>`,
                  )
            }
          </div>`,
      )}
    </div>
    ${
      spielerzahl < teams.minSpieler
        ? html`<p class="muted" style="margin:0;font-size:0.9rem">
            Teams greifen ab ${teams.minSpieler} Spielern — darunter läuft's individuell.
          </p>`
        : ""
    }
  </div>`;
}

/** Team-Wahl-Buttons (Player-Lobby): Team-Farbe + Mitglieder-Zahl, Um-Wahl ok. */
export function teamWahlBlock(
  teams: TeamsView,
  sende: (event: string, payload?: Record<string, unknown>) => void,
): TemplateResult {
  return html`<div style="display:flex;flex-direction:column;gap:8px;align-items:center;width:100%">
    <p class="muted" style="margin:0">🐒 Wähle deine Affenbande:</p>
    ${teams.teams.map((t) => {
      const gewaehlt = teams.deinTeam === t.id;
      return html`<button
        data-testid="team-wahl-${t.id}"
        style="width:min(340px,86vw);border:3px solid ${t.farbe};${
          gewaehlt
            ? `background:color-mix(in srgb, ${t.farbe} 30%, transparent);font-weight:800;`
            : ""
        }"
        @click=${() => sende("team.wahl", { team: t.id })}
      >
        ${gewaehlt ? "✅ " : ""}${t.emoji} ${t.name}
        <span class="muted">(${t.mitglieder.length})</span>
      </button>`;
    })}
  </div>`;
}

/**
 * Team-Zwischenstand: Ranking nach TOPF (Doppel-Affe ×2) mit Individual-
 * Aufschlüsselung — Screen UND Handy (meineId hebt den eigenen Affen hervor).
 */
export function teamZwischenstand(teams: TeamsView, meineId?: string): TemplateResult {
  return html`<div
    data-testid="team-zwischenstand"
    style="display:flex;flex-direction:column;gap:10px;align-items:center;width:100%"
  >
    ${teams.teams.map(
      (t, i) =>
        html`<div
          class="zwischenstand-zeile"
          style="--einflug-index:${i};flex-direction:column;align-items:stretch;gap:6px;border:3px solid ${t.farbe};background:color-mix(in srgb, ${t.farbe} 10%, transparent)"
        >
          <div style="display:flex;align-items:center;gap:10px">
            <strong>${t.platz}.</strong>
            <span style="font-weight:800">${t.emoji} ${t.name}</span>
            <span class="betrag" style="margin-left:auto;color:${t.farbe}">
              💰 ${formatMM(t.topf)}
            </span>
          </div>
          <div style="display:flex;gap:12px;flex-wrap:wrap;font-size:0.9rem;opacity:0.9">
            ${t.mitglieder.map(
              (m) =>
                html`<span
                  style="display:inline-flex;align-items:center;gap:5px;${
                    m.playerId === meineId
                      ? "outline:2px solid var(--gold);border-radius:8px;padding:1px 6px"
                      : ""
                  }"
                >
                  ${avatarDot(m.avatar)} ${m.name} ${formatMM(m.balance)} ${doppelAffeTag(m)}
                </span>`,
            )}
          </div>
        </div>`,
    )}
  </div>`;
}

/**
 * Team-Podest der Siegerehrung (Screen): Team-Karten in End-Reihenfolge —
 * Team-Farbe als Rahmen/Banner, TOPF groß, Mitglieder mit Einzel-Konten.
 * Die Mitglieder-Aufschlüsselung kommt aus dem TeamsView (gleiches Match).
 */
export function teamPodest(
  sgTeams: NonNullable<SiegerehrungView["teams"]>,
  teams: TeamsView | null,
): TemplateResult {
  const mitgliederVon = (teamId: string): TeamEintragView["mitglieder"] =>
    teams?.teams.find((t) => t.id === teamId)?.mitglieder ?? [];
  const medaille = (platz: number): string =>
    platz === 1 ? "🥇" : platz === 2 ? "🥈" : platz === 3 ? "🥉" : `${platz}.`;
  return html`<div
    data-testid="team-podest"
    style="display:flex;gap:16px;justify-content:center;align-items:flex-end;flex-wrap:wrap"
  >
    ${sgTeams.map((t, i) => {
      const sieger = t.platz === 1;
      return html`<div
        data-testid="team-podest-${t.platz}"
        style="display:flex;flex-direction:column;gap:6px;align-items:center;padding:${
          sieger ? "18px 26px" : "12px 18px"
        };border-radius:16px;border:4px solid ${t.farbe};background:color-mix(in srgb, ${t.farbe} ${
          sieger ? "26" : "12"
        }%, transparent);animation:kandidat-rein 0.5s ${0.3 + i * 0.45}s var(--mm-kurve-bounce) both"
      >
        <span style="font-size:${sieger ? "2rem" : "1.4rem"}">${medaille(t.platz)}</span>
        <strong style="font-size:${sieger ? "1.5rem" : "1.1rem"}">${t.emoji} ${t.name}</strong>
        <span
          class="mm-money-zahl"
          style="color:var(--gold);font-size:${sieger ? "1.6rem" : "1.15rem"}"
        >
          ${formatMM(t.topf)}
        </span>
        <div style="display:flex;gap:10px;flex-wrap:wrap;justify-content:center;font-size:0.9rem">
          ${mitgliederVon(t.teamId).map(
            (m) =>
              html`<span style="display:inline-flex;align-items:center;gap:5px">
                ${avatarDot(m.avatar)} ${m.name}
                <span class="muted">${formatMM(m.balance)}</span> ${doppelAffeTag(m)}
              </span>`,
          )}
        </div>
      </div>`;
    })}
  </div>`;
}

/** Team-Ergebnis fürs Handy: eigene Team-Platzierung + Topf (Siegerehrung). */
export function teamErgebnisHandy(teams: TeamsView | null): TemplateResult {
  const team = eigenesTeam(teams);
  if (!team || teams?.wahlOffen) return html``;
  return html`<div
    style="display:flex;flex-direction:column;gap:2px;align-items:center;padding:8px 18px;border-radius:14px;border:3px solid ${team.farbe};background:color-mix(in srgb, ${team.farbe} 15%, transparent)"
  >
    <strong>${team.platz === 1 ? "🏆" : `${team.platz}.`} ${team.emoji} ${team.name}</strong>
    <span class="muted" style="font-size:0.9rem">Team-Topf: ${formatMM(team.topf)}</span>
  </div>`;
}

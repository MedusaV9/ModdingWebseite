// Join-Flow (Eval-6-Härtung: CODE ZUERST): der Raum-Code wird sofort beim
// Eintippen geprüft („Raum gefunden ✓"), erst DANACH erscheinen Name +
// AFFE+FARBE-Wahl; „Code ändern" führt jederzeit zurück. Doppelte Namen lehnt
// der Server ab (name-vergeben) — dann gibt's den Session-Restore-Hinweis
// „bist du das?" mit Wiederverbinden-Knopf. Wire-Format bleibt hello.avatar
// als String "affe.farbe" — Alt-Clients/Bots mit reiner Farbe laufen weiter.
import { html, type TemplateResult } from "lit-html";
import { AVATAR_FARBEN, type AvatarFarbe } from "../../shared/ids";
import { AFFEN, FARBWERTE, formatAvatar, parseAvatar } from "../shared/fx/avatar";
import { ladeToken } from "../shared/session";
import { istStandalone } from "../shared/standalone-transport";
import { renderProfilWahl, verbindeViaMeta } from "./meta-join";
import "./meta-join.css";
import type { PlayerAppState } from "./main";

/** Sofort-Check des Raum-Codes (VOR Name/Avatar — Eval 6). */
interface RaumCheck {
  code: string;
  status: "prueft" | "ok" | "fehlt" | "unbekannt";
  spieler: number;
  phase: string;
}

let raumCheck: RaumCheck | null = null;

function pruefeRaum(code: string, zeichne: () => void): void {
  if (raumCheck?.code === code) return;
  raumCheck = { code, status: "prueft", spieler: 0, phase: "" };
  // Standalone (iPad = Server): kein HTTP-API hinterm Relay — Check entfällt,
  // der Join selbst validiert den Code (raum-nicht-gefunden kommt vom hello).
  if (istStandalone()) {
    raumCheck.status = "unbekannt";
    return;
  }
  void fetch(`/api/raum/${encodeURIComponent(code)}`)
    .then(async (r) => {
      const d = (await r.json().catch(() => ({}))) as {
        ok?: boolean;
        error?: string;
        status?: string;
        spieler?: number;
      };
      if (raumCheck?.code !== code) return; // Code wurde inzwischen geändert
      raumCheck.status =
        d.ok === true ? "ok" : d.error === "raum-nicht-gefunden" ? "fehlt" : "unbekannt";
      raumCheck.spieler = d.spieler ?? 0;
      raumCheck.phase = d.status ?? "";
      zeichne();
    })
    .catch(() => {
      // Server nicht erreichbar (z. B. exotisches Setup): Join NICHT blocken.
      if (raumCheck?.code !== code) return;
      raumCheck.status = "unbekannt";
      zeichne();
    });
}

/** Schritt 1: Code-Feld + Live-Status („Raum gefunden ✓" / „nicht gefunden"). */
function codeSchritt(state: PlayerAppState, zeichne: () => void): TemplateResult {
  const check = state.roomCode !== null && raumCheck?.code === state.roomCode ? raumCheck : null;
  return html`
    <label for="join-code">Raum-Code:</label>
    <input
      id="join-code"
      class="mono"
      style="text-transform:uppercase;font-size:1.5rem;width:9ch;text-align:center"
      maxlength="4"
      autocapitalize="characters"
      autocomplete="off"
      .value=${state.roomCode ?? ""}
      @input=${(e: Event) => {
        const wert = (e.target as HTMLInputElement).value.toUpperCase();
        state.roomCode = wert.length === 4 ? wert : null;
        if (state.roomCode === null) raumCheck = null;
        zeichne();
      }}
    />
    ${check?.status === "prueft" ? html`<p class="muted" style="margin:0">Prüfe Raum …</p>` : ""}
    ${
      check?.status === "fehlt"
        ? html`<p style="margin:0;color:var(--rot)" data-testid="raum-fehlt">
            Raum ${check.code} nicht gefunden — Tippfehler? Codes haben 4 Buchstaben.
          </p>`
        : ""
    }
  `;
}

/** Kopfzeile nach erfolgreichem Check: Code + ✓ + „Code ändern". */
function raumKopf(state: PlayerAppState, zeichne: () => void, check: RaumCheck): TemplateResult {
  return html`<div
    style="display:flex;gap:10px;align-items:center;flex-wrap:wrap;justify-content:center"
  >
    <span class="muted"
      >Raum <span class="mono" style="font-size:1.4rem">${state.roomCode}</span></span
    >
    ${
      check.status === "ok"
        ? html`<span style="color:var(--gruen);font-weight:700" data-testid="raum-gefunden">
            ✓ Raum
            gefunden${check.spieler > 0 ? ` · ${check.spieler} 🐒` : ""}${
              check.phase === "laeuft" ? " · Match läuft" : ""
            }
          </span>`
        : ""
    }
    <button
      data-testid="code-aendern"
      style="min-height:44px;padding:6px 14px;font-size:0.9rem"
      @click=${() => {
        state.roomCode = null;
        raumCheck = null;
        state.fehler = null;
        state.fehlerCode = null;
        zeichne();
      }}
    >
      ✏️ Code ändern
    </button>
  </div>`;
}

/** Join-Steps-Progress: Code → Affe & Name → Los! (Eval W3: der Flow fühlt
 * sich wie geführte Schritte an statt wie ein einziges langes Formular). */
function joinSchritte(aktiv: 1 | 2 | 3): TemplateResult {
  const labels = ["Code", "Affe & Name", "Los!"];
  return html`<div class="join-schritte" data-testid="join-schritte">
    ${labels.map((label, i) => {
      const nr = i + 1;
      const zustand = nr < aktiv ? "fertig" : nr === aktiv ? "aktiv" : "offen";
      return html`<span class="join-schritt ${zustand}">
        <span class="join-punkt">${nr < aktiv ? "✓" : nr}</span>
        <span class="join-label">${label}</span>
      </span>`;
    })}
  </div>`;
}

/** name-vergeben: „bist du das?" — Session-Restore-Hinweis + Wiederverbinden. */
function nameVergebenHinweis(
  state: PlayerAppState,
  zeichne: () => void,
  verbinde: () => void,
): TemplateResult {
  if (state.fehlerCode !== "name-vergeben") return html``;
  const token = state.roomCode ? ladeToken(state.roomCode) : null;
  return html`<div
    class="karte"
    data-testid="name-vergeben"
    style="max-width:min(420px,90vw);padding:10px 14px;display:flex;flex-direction:column;gap:8px"
  >
    ${
      token
        ? html`<span style="font-size:0.9rem">
              Du warst hier schon drin — dein Platz (samt Punkten) ist reserviert.
            </span>
            <button
              class="primaer"
              data-testid="wiederverbinden"
              @click=${() => {
                state.fehler = null;
                state.fehlerCode = null;
                zeichne();
                verbinde();
              }}
            >
              🔄 Wiederverbinden (alter Platz)
            </button>`
        : html`<span style="font-size:0.9rem">
            Falls du das bist: öffne die Seite wieder im URSPRÜNGLICHEN Browser/Gerät — dein Platz
            samt Punkten ist reserviert. Sonst: nimm einen anderen Namen.
          </span>`
    }
  </div>`;
}

export function renderJoinForm(
  state: PlayerAppState,
  zeichne: () => void,
  verbinde: () => void,
): TemplateResult {
  // Code aus URL (/j/CODE) oder Eingabe: sofort prüfen (fire-and-forget).
  if (state.roomCode !== null) pruefeRaum(state.roomCode, zeichne);
  const check = state.roomCode !== null && raumCheck?.code === state.roomCode ? raumCheck : null;
  // „unbekannt" (Standalone/kein API) blockt nie — der Join validiert selbst.
  const raumOk = check !== null && (check.status === "ok" || check.status === "unbekannt");

  const wahl = parseAvatar(state.avatar);
  const affeIndex = Math.max(
    0,
    AFFEN.findIndex((a) => a.id === wahl.affe),
  );
  const affe = AFFEN[affeIndex];
  const setzeAffe = (index: number): void => {
    const neu = AFFEN[(index + AFFEN.length) % AFFEN.length];
    state.avatar = formatAvatar({ affe: neu.id, farbe: wahl.farbe });
    zeichne();
  };
  const setzeFarbe = (farbe: AvatarFarbe): void => {
    state.avatar = formatAvatar({ affe: wahl.affe, farbe });
    zeichne();
  };

  return html`<div class="zentriert" style="gap:12px">
    <h1>🐒 Mitspielen</h1>
    ${joinSchritte(!raumOk ? 1 : state.name.length === 0 ? 2 : 3)}
    ${state.fehler ? html`<p style="color:var(--rot)">${state.fehler}</p>` : ""}
    ${nameVergebenHinweis(state, zeichne, verbinde)}
    ${raumOk && check !== null ? raumKopf(state, zeichne, check) : codeSchritt(state, zeichne)}
    ${
      raumOk
        ? html`<div class="join-einflug">
            <input
              placeholder="Dein Name"
              maxlength="24"
              style="width:min(320px,80vw);text-align:center;font-size:1.2rem"
              .value=${state.name}
              @input=${(e: Event) => {
                state.name = (e.target as HTMLInputElement).value.trim();
                zeichne();
              }}
            />

            <div class="affen-wahl">
              <button
                class="pfeil"
                aria-label="Voriger Affe"
                @click=${() => setzeAffe(affeIndex - 1)}
              >
                ◀
              </button>
              <div class="affen-buehne">
                <div
                  class="grosse-puppe mm-affe mm-affe-idle"
                  data-puppe=${affe.id}
                  data-farbe=${wahl.farbe}
                ></div>
                <span class="affen-name">${affe.name}</span>
                <span class="affen-rolle">${affe.rolle}</span>
              </div>
              <button
                class="pfeil"
                aria-label="Nächster Affe"
                @click=${() => setzeAffe(affeIndex + 1)}
              >
                ▶
              </button>
            </div>

            <div class="farb-reihe">
              ${AVATAR_FARBEN.map(
                (farbe) =>
                  html`<button
                    class="farb-knopf ${wahl.farbe === farbe ? "gewaehlt" : ""}"
                    style="--farbe:${FARBWERTE[farbe].farbe}"
                    aria-label="Farbe ${farbe}"
                    @click=${() => setzeFarbe(farbe)}
                  ></button>`,
              )}
            </div>

            ${renderProfilWahl(state, zeichne)}

            <button
              class="primaer"
              style="width:min(320px,80vw)"
              ?disabled=${!state.roomCode || state.name.length === 0}
              @click=${() => verbindeViaMeta(state, verbinde)}
            >
              Rein da! 🍌
            </button>
          </div>`
        : ""
    }
  </div>`;
}

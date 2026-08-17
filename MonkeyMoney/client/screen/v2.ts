// v2-Features (Screen): Replay-Highlights-Sequenz, Sudden-Death-Kokosnuss-Shake,
// Jubiläums-Karte im Opening und der Foto-Finish-Share-Block. Neue Datei statt
// Chirurgie in views.ts/cutscenes.ts — dort kommen nur die Aufrufe dazu.
import { html, type TemplateResult } from "lit-html";
import { keyed } from "lit-html/directives/keyed.js";
import { formatMM } from "../../shared/money";
import type { HighlightsView, JubilaeumsView, ScreenView } from "../../shared/views";
import { avatarFarbe } from "../shared/fx/avatar";
import {
  fotoDateiname,
  fotoDatum,
  ladeFotoHerunter,
  zeichneFotoFinish,
} from "../shared/foto-finish";
import "./v2.css";

/** Icon je Highlight-Art (Farbe/Icon wählt der Client — shared bleibt schlank). */
const HIGHLIGHT_ICON: Record<string, string> = {
  "groesster-klau": "🕵️",
  "knappster-buzzer": "⚡",
  "teuerste-falschantwort": "💸",
  "bank-verrat": "🏦",
  comeback: "📈",
  jackpot: "🏺",
};

export function highlightIcon(art: string): string {
  return HIGHLIGHT_ICON[art] ?? "🎬";
}

// ---------- Replay-Highlights: „Die Highlights des Abends" ----------

/** Replay-Mini-Animation je Highlight-Art (W4: „Replay-Gefühl statt
 * Ergebnisfolie") — Klau-Hand wandert, Blitz-Duell, Absturz-Pfeil usw.
 * Reines CSS (transform/opacity), keyed über die Karten-Id ⇒ startet pro
 * Karte frisch. */
function highlightAnimation(art: string): TemplateResult {
  switch (art) {
    case "groesster-klau":
      return html`<div class="hl-anim klau" aria-hidden="true">
        <span class="hl-klau-beute">💰</span><span class="hl-klau-hand">🤏</span>
      </div>`;
    case "knappster-buzzer":
      return html`<div class="hl-anim buzzer" aria-hidden="true">
        <span class="hl-blitz links">⚡</span><span class="hl-blitz-funke">💥</span
        ><span class="hl-blitz rechts">⚡</span>
      </div>`;
    case "teuerste-falschantwort":
      return html`<div class="hl-anim patzer" aria-hidden="true">
        <span class="hl-patzer-pfeil">📉</span><span class="hl-patzer-krach">💸</span>
      </div>`;
    case "comeback":
      return html`<div class="hl-anim comeback" aria-hidden="true">
        <span class="hl-comeback-pfeil">📈</span><span class="hl-comeback-stern">🌟</span>
      </div>`;
    case "bank-verrat":
      return html`<div class="hl-anim bank" aria-hidden="true">
        <span class="hl-bank">🏦</span><span class="hl-bank-beute">💰</span>
      </div>`;
    case "jackpot":
      return html`<div class="hl-anim jackpot" aria-hidden="true">
        <span class="hl-jackpot-glas">🏺</span><span class="hl-jackpot-muenze m1">🪙</span
        ><span class="hl-jackpot-muenze m2">🪙</span>
      </div>`;
    default:
      return html`<span class="hl-icon">${highlightIcon(art)}</span>`;
  }
}

export function highlightsSequenz(view: ScreenView, serverNow: number): TemplateResult {
  const hl = view.highlights;
  if (!hl) return html`<div class="zentriert"><h1>🎬 Die Highlights des Abends …</h1></div>`;
  const karte = hl.karten[hl.index];
  const rest = Math.max(0, hl.endetAt - serverNow);
  const fortschritt = 1 - Math.min(1, rest / Math.max(1, hl.karteMs));
  // Count-up-Betrag (W4): zählt in den ersten ~1,3 s der Karte hoch — rein aus
  // der Server-Zeit abgeleitet (der 120-ms-Live-Tick treibt die Renders).
  const seitStart = Math.max(0, hl.karteMs - rest);
  const zaehlAnteil = Math.min(1, seitStart / 1300);
  const eased = 1 - Math.pow(1 - zaehlAnteil, 3);
  const betragAnzeige = karte.betrag !== undefined ? Math.round(karte.betrag * eased) : null;
  return html`<div class="highlight-buehne">
    <h1 style="margin:0;color:var(--gold)">🎬 Die Highlights des Abends</h1>
    ${keyed(
      karte.id,
      html`<div class="highlight-karte" data-testid="highlight-karte" data-art=${karte.art}>
        ${highlightAnimation(karte.art)}
        <h1>${karte.titel}</h1>
        ${highlightPuppen(karte, view)}
        <p class="hl-text">${karte.text}</p>
        ${
          betragAnzeige !== null
            ? html`<span class="hl-betrag mm-money-zahl ${zaehlAnteil < 1 ? "zaehlt" : "fertig"}"
                >${formatMM(betragAnzeige)}</span
              >`
            : ""
        }
        <p class="muted" style="margin:0;font-size:0.9rem">Frage ${karte.frageNr}</p>
      </div>`,
    )}
    <div class="highlight-balken"><div style="width:${(fortschritt * 100).toFixed(1)}%"></div></div>
    <div class="highlight-punkte">
      ${hl.karten.map((_, i) => html`<span class=${i === hl.index ? "aktiv" : ""}></span>`)}
    </div>
  </div>`;
}

/** Haupt-Akteur (+ Gegner) als Puppen auf der Karte — der Betroffene bekommt
 * seinen echten Puppen-Kopf (Avatar aus view.players) + „GETROFFEN!"-Chip. */
function highlightPuppen(
  karte: HighlightsView["karten"][number],
  view: ScreenView,
): TemplateResult {
  const gegnerAvatar =
    karte.gegnerId !== undefined
      ? (view.players.find((p) => p.id === karte.gegnerId)?.avatar ?? null)
      : null;
  return html`<div class="highlight-puppen">
    <div style="display:flex;flex-direction:column;align-items:center;gap:4px">
      <div
        class="kandidaten-puppe mm-affe mm-affe-idle"
        data-avatar=${karte.avatar}
        data-gesicht="jubel"
      ></div>
      <span
        class="podium-name"
        style="--spielerfarbe:${avatarFarbe(karte.avatar)};font-size:0.95rem;padding:2px 10px"
      >
        ${karte.playerName}
      </span>
    </div>
    ${
      karte.gegnerName !== undefined
        ? html`<span style="font-size:2rem;align-self:center">⚔️</span>
            <div class="hl-gegner">
              ${
                gegnerAvatar !== null
                  ? html`<div
                      class="kandidaten-puppe mm-affe hl-gegner-puppe"
                      data-avatar=${gegnerAvatar}
                      data-gesicht="frust"
                    ></div>`
                  : html`<span style="font-size:3.4rem">😵</span>`
              }
              <span
                class="podium-name"
                style="--spielerfarbe:${gegnerAvatar !== null ? avatarFarbe(gegnerAvatar) : "var(--gold)"};font-size:0.95rem;padding:2px 10px"
                >${karte.gegnerName}</span
              >
              <span class="hl-getroffen-chip">💥 GETROFFEN!</span>
            </div>`
        : ""
    }
  </div>`;
}

// ---------- Sudden-Death: Kokosnuss-Shake (rotes Studiolicht via v2.css) ----------

export function tiebreakerBuehne(view: ScreenView, serverNow: number): TemplateResult {
  const tb = view.tiebreaker;
  if (!tb) return html`<div class="zentriert"><h1>💥 SUDDEN DEATH!</h1></div>`;
  const maxTaps = Math.max(1, ...tb.teilnehmer.map((t) => t.taps));
  const rest = Math.max(0, tb.endetAt - serverNow);
  return html`<div class="sudden-death-buehne" data-testid="sudden-death">
    <h1 class="sudden-death-titel">💥 SUDDEN DEATH 💥</h1>
    <p style="font-size:1.3rem;margin:0">
      Gleichstand bei <strong style="color:var(--gold)">${formatMM(tb.betrag)}</strong> — der
      <strong>🥥 Kokosnuss-Shake</strong> entscheidet!
      ${tb.runde > 1 ? html`<strong style="color:var(--rot)"> Runde ${tb.runde}!</strong>` : ""}
    </p>
    ${
      tb.subphase === "countdown"
        ? html`<div class="sudden-death-countdown">${Math.max(1, Math.ceil(rest / 1000))}</div>
            <p class="muted" style="font-size:1.2rem">Handys bereit — gleich wird gehämmert!</p>`
        : ""
    }
    <div class="shake-duell">
      ${tb.teilnehmer.map((t) => {
        const sieger = tb.siegerId === t.playerId;
        const hoehe = Math.round((t.taps / maxTaps) * 100);
        return html`<div class="shake-spalte ${sieger ? "sieger" : ""}">
          ${tb.subphase !== "countdown" ? html`<span class="shake-taps">${t.taps}</span>` : ""}
          ${
            tb.subphase === "shake"
              ? html`<div class="shake-balken"><div style="height:${hoehe}%"></div></div>`
              : ""
          }
          <div
            class="kandidaten-puppe mm-affe mm-affe-idle"
            data-avatar=${t.avatar}
            data-gesicht=${sieger ? "jubel" : tb.subphase === "ergebnis" ? "frust" : "denk"}
          ></div>
          <span class="podium-name" style="--spielerfarbe:${avatarFarbe(t.avatar)};font-size:1rem">
            ${sieger ? "👑 " : ""}${t.name}
          </span>
        </div>`;
      })}
    </div>
    ${
      tb.subphase === "shake"
        ? html`<p style="font-size:1.35rem;margin:0">
            🥥 HÄMMERT AUF DIE KOKOSNUSS! Noch
            <strong style="color:var(--gold)">${Math.ceil(rest / 1000)} s</strong>!
          </p>`
        : ""
    }
    ${
      tb.subphase === "ergebnis" && tb.siegerId !== null
        ? html`<h2 style="margin:0;color:var(--gold)">
            🥥 KNACK! ${tb.teilnehmer.find((t) => t.playerId === tb.siegerId)?.name ?? "?"} holt
            Platz 1!
          </h2>`
        : ""
    }
  </div>`;
}

// ---------- Jubiläums-Karte im Opening ----------

export function jubilaeumsKarte(j: JubilaeumsView): TemplateResult {
  return html`<div class="jubilaeums-karte" data-testid="jubilaeums-karte">
    <h2>${j.titel}</h2>
    <p style="margin:0;max-width:32em">${j.text}</p>
    <div class="jubilaeums-stats">
      <div class="stat">
        <strong class="mm-money-zahl">${formatMM(j.gesamtMoney)}</strong>
        <span class="muted">Gesamt-Money der Gruppe</span>
      </div>
      ${
        j.rekord !== null
          ? html`<div class="stat">
              <strong class="mm-money-zahl">${formatMM(j.rekord.endstand)}</strong>
              <span class="muted">Ewiger Rekord: ${j.rekord.name}</span>
            </div>`
          : ""
      }
      <div class="stat">
        <strong>${j.matchNr}.</strong>
        <span class="muted">gemeinsamer Abend</span>
      </div>
    </div>
  </div>`;
}

// ---------- Foto-Finish-Share (Abspann) ----------

let fotoUrl: string | null = null;
let fotoKey = "";

/** Download-Button + Vorschau des generierten Ergebnis-Bilds (Screen). */
export function fotoFinishBlock(
  view: ScreenView,
  serverNow: number,
  zeichne: () => void,
): TemplateResult {
  const key = `${view.roomCode}:${view.standings.map((s) => `${s.id}${s.balance}`).join(",")}`;
  if (fotoKey !== key) {
    fotoKey = key;
    fotoUrl = null;
  }
  const erzeuge = (): void => {
    fotoUrl ??= zeichneFotoFinish({
      standings: view.standings,
      datum: fotoDatum(serverNow),
      roomCode: view.roomCode,
    });
    if (fotoUrl !== null) ladeFotoHerunter(fotoUrl, fotoDateiname(serverNow));
    zeichne();
  };
  return html`<div class="foto-finish-block" data-testid="foto-finish">
    ${fotoUrl !== null ? html`<img src=${fotoUrl} alt="Foto-Finish Ergebnis-Bild" />` : ""}
    <button class="primaer" style="font-size:1.15rem" @click=${erzeuge}>
      📸 Foto-Finish herunterladen
    </button>
  </div>`;
}

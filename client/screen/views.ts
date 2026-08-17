// Screen-Phasen: das Studio (Kopf-Ticker + LED-Wand + Podien + Jackpot-Glas)
// plus Cutscenes (Opening, Runden-Karte, Siegerehrung) und das Glücksrad.
// iPad-Landscape/Beamer ist das Zielformat.
import { html, type TemplateResult } from "lit-html";
import { keyed } from "lit-html/directives/keyed.js";
import { detectCaps } from "../../shared/caps";
import { BOARD_TITEL, lobbySlideIndex, lobbySlides, type Boards } from "../../shared/meta";
import { formatMM } from "../../shared/money";
import type { TunnelStatusMsg } from "../../shared/protocol";
import type { ScreenView } from "../../shared/views";
import type { FxApi } from "../shared/minigames/types";
import { istStandalone } from "../shared/standalone-transport";
import { teamSpalten, teamZwischenstand } from "../shared/teams-ui";
import { zwischenstand } from "../shared/ui";
import { endeScreen, introCutscene, rundenKarte, siegerehrungCutscene } from "./cutscenes";
import { radPhase } from "./rad";
import { highlightsSequenz, tiebreakerBuehne } from "./v2";
import {
  jackpotGlas,
  kategorieIcon,
  kategorieName,
  ledWand,
  podiumReihe,
  studioKopf,
  type GesichtsMap,
} from "./studio";
import "./studio.css";

interface AufloesungView {
  aufloesung: { perPlayer: { playerId: string; correct: boolean; delta: number }[] } | null;
  blackout?: boolean;
}

/** LOBBY: room.config-Sender (Sichtbarkeit/Name) — von main.ts injiziert. */
export type RaumConfigSender = (patch: { name?: string; oeffentlich?: boolean }) => void;

/** INTERNET-LINK (W4): Tunnel-Status + Start/Stop-Sender — von main.ts injiziert. */
export interface TunnelUi {
  status: TunnelStatusMsg | null;
  cmd: (aktion: "start" | "stop") => void;
}

export function renderPhase(
  view: ScreenView,
  mgHost: TemplateResult,
  serverNow: number,
  fx: FxApi,
  lobbyBoards: Boards | null = null,
  raumConfig: RaumConfigSender | null = null,
  // 2-Stufen-Auflösung (P1): false = Spannungs-Fenster (Wand zappt neutral,
  // keine Chips/Gesichter) — der Flip kommt exakt mit der Fanfare (main.ts).
  aufgedeckt = true,
  tunnel: TunnelUi | null = null,
): TemplateResult {
  const inhalt = phaseInhalt(
    view,
    mgHost,
    serverNow,
    fx,
    lobbyBoards,
    raumConfig,
    aufgedeckt,
    tunnel,
  );
  // Cutscenes (Opening/Sudden-Death/Highlights/Siegerehrung/Abspann) laufen
  // OHNE Ticker + Banner — „Frage 0/15" wäre dort nur Störfeuer.
  const cutscene = ["intro", "tiebreaker", "highlights", "siegerehrung", "ende"].includes(
    view.phase,
  );
  const mitPodien = !cutscene;
  // Team-Modus: Podien nach Teams gruppiert (Team-Farbe als Pult-Rahmen).
  const teams = view.teams !== null && !view.teams.wahlOffen ? view.teams : null;
  let podiumSpieler = view.players;
  let teamFarben: Record<string, string> | undefined;
  if (teams !== null) {
    teamFarben = {};
    const reihenfolge: string[] = [];
    for (const t of teams.teams) {
      for (const m of t.mitglieder) {
        teamFarben[m.playerId] = t.farbe;
        reihenfolge.push(m.playerId);
      }
    }
    podiumSpieler = [...view.players].sort(
      (a, b) => reihenfolge.indexOf(a.id) - reihenfolge.indexOf(b.id),
    );
  }
  return html`<div class="studio" data-phase=${view.phase}>
    ${cutscene ? "" : momentBanner(view, serverNow)}
    ${view.phase === "lobby" || cutscene ? "" : studioKopf(view)}
    <div class="studio-mitte">
      ${
        // Sanfter Phasen-Übergang (W3): keyed erzeugt den Container pro Phase
        // NEU — die phase-rein-Animation läuft bei jedem Wechsel frisch an.
        keyed(view.phase, html`<div class="phasen-container">${inhalt}</div>`)
      }
    </div>
    ${mitPodien ? podiumReihe(podiumSpieler, { gesichter: gesichter(view), einflug: view.phase === "lobby", teamFarben }) : ""}
    ${jackpotGlas(view.jackpotGlas, false)} ${votingBanner(view)}
  </div>`;
}

function phaseInhalt(
  view: ScreenView,
  mgHost: TemplateResult,
  serverNow: number,
  fx: FxApi,
  lobbyBoards: Boards | null,
  raumConfig: RaumConfigSender | null,
  aufgedeckt = true,
  tunnel: TunnelUi | null = null,
): TemplateResult {
  switch (view.phase) {
    case "lobby":
      return lobby(view, lobbyBoards, serverNow, raumConfig, tunnel);
    case "intro":
      return introCutscene(view);
    case "kategorie-wahl":
      return kategorieWahl(view);
    case "erklaerkarte":
      return rundenKarte(view, fx);
    case "frage": {
      const mg = view.minigame?.view as AufloesungView | undefined;
      if (mg?.blackout) {
        return html`<div class="zentriert">
          <h1 style="font-size:3rem">📺 SENDEAUSFALL!</h1>
          <p class="muted" style="font-size:1.3rem">Diese Frage läuft NUR auf den Handys …</p>
        </div>`;
      }
      return html`${kategorieChip(view)} ${ledWand(mgHost)} ${tippKanoneBanner(view)}`;
    }
    case "aufloesung":
      // Spannungs-Fenster: Wand zappt neutral (Antworten sichtbar, KEINE
      // Korrekt-Markierung/Chips/Deltas) — Flip exakt bei der Fanfare.
      if (!aufgedeckt) return html`${kategorieChip(view)} ${ledWand(mgHost, true)}`;
      return html`${kategorieChip(view)} ${ledWand(mgHost)}
        <div class="spieler-liste" style="margin-top:10px">${ergebnisChips(view)}</div>`;
    case "zwischenstand":
      // Team-Modus: Team-Ranking (Topf) MIT Individual-Aufschlüsselung (§1.4).
      return html`<div class="zentriert" style="gap:12px">
        <h1>💰 Zwischenstand</h1>
        ${zwischenstandStory(view)} ${abschnittZeile(view)} ${toepfe(view)}
        ${
          view.teams !== null && !view.teams.wahlOffen
            ? teamZwischenstand(view.teams)
            : zwischenstand(view.standings)
        }
      </div>`;
    case "rad":
      return radPhase(view, serverNow, fx);
    // v2 Sudden-Death: rotes Studiolicht + Kokosnuss-Shake-Duell.
    case "tiebreaker":
      return tiebreakerBuehne(view, serverNow);
    // v2 Replay-Highlights: „Die Highlights des Abends" vor der Siegerehrung.
    case "highlights":
      return highlightsSequenz(view, serverNow);
    case "siegerehrung":
      return siegerehrungCutscene(view);
    case "ende":
      return endeScreen(view, serverNow);
  }
}

/** Gesichts-Reaktionen der Podium-Puppen je Phase (dataset.gesicht). */
function gesichter(view: ScreenView): GesichtsMap {
  const map: GesichtsMap = {};
  if (view.phase === "frage") {
    for (const p of view.players) map[p.id] = "denk";
    return map;
  }
  if (view.phase === "aufloesung") {
    const mg = view.minigame?.view as AufloesungView | undefined;
    for (const r of mg?.aufloesung?.perPlayer ?? []) {
      map[r.playerId] = r.correct ? "jubel" : "frust";
    }
  }
  return map;
}

function abschnittZeile(view: ScreenView): TemplateResult {
  const a = view.abschnitt;
  if (!a || a.typ !== "runde") return html``;
  return html`<p class="muted">Runde ${a.rundeNr} / ${a.rundenTotal} gespielt</p>`;
}

/** Kategorie-Badge (Kontext-Anker, Eval 5): dezenter Chip „Gaming · Minecraft"
 * über der Frage — zentral in ALLEN Frage-Formaten (Daten aus dem View). */
function kategorieChip(view: ScreenView): TemplateResult {
  if (!view.frageKategorie) return html``;
  return html`<p data-testid="frage-kategorie" style="text-align:center;margin:0 0 4px">
    <span class="phasen-chip">📚 ${view.frageKategorie}</span>
  </p>`;
}

/** Tipp-Kanone: enthüllte Autoren-Tipps unter der LED-Wand (Stufe 1→3). */
function tippKanoneBanner(view: ScreenView): TemplateResult {
  if (view.tipps.length === 0) return html``;
  return html`<div data-testid="tipp-kanone" style="text-align:center;margin-top:8px">
    ${view.tipps.map(
      (t, i) =>
        html`<p style="margin:2px 0;color:var(--gold);font-size:1.05rem">
          💡 Tipp ${i + 1}: ${t}
        </p>`,
    )}
  </div>`;
}

// ---------- Zwischenstand-Story: EINE animierte News pro Beat ----------
// Der Screen merkt sich den Stand des LETZTEN Zwischenstands und erzählt genau
// eine Geschichte: Führungswechsel (Krone) oder größter Geld-Sprung (hüpft
// ein) — statt 5 s stiller Tabelle (Playtest 3: „Wartezimmer statt News-Beat").
let standMemo: { fuehrerId: string | null; staende: Record<string, number> } | null = null;
let storyKey = "";
let story: { icon: string; text: string } | null = null;

function baueStandStory(view: ScreenView): { icon: string; text: string } | null {
  const s = view.standings;
  if (s.length < 2) return null;
  if (standMemo !== null && standMemo.fuehrerId !== null && standMemo.fuehrerId !== s[0].id) {
    return { icon: "👑📈", text: `${s[0].name} reißt die Führung an sich!` };
  }
  // Größter Geld-Sprung seit dem letzten Zwischenstand (Runde 1: seit Start).
  let bester: { name: string; delta: number } | null = null;
  for (const sp of s) {
    const delta = sp.balance - (standMemo?.staende[sp.id] ?? 0);
    if (delta > 0 && (bester === null || delta > bester.delta)) {
      bester = { name: sp.name, delta };
    }
  }
  if (bester !== null) {
    return {
      icon: "💰",
      text: `${bester.name} kassiert +${formatMM(bester.delta)} — größter Sprung!`,
    };
  }
  const abstand = s[0].balance - s[1].balance;
  return abstand <= 100
    ? { icon: "🔥", text: `Nur ${formatMM(abstand)} zwischen Platz 1 und 2!` }
    : { icon: "👑", text: `${s[0].name} führt mit ${formatMM(abstand)} Vorsprung.` };
}

function zwischenstandStory(view: ScreenView): TemplateResult {
  const a = view.abschnitt;
  const key = `${a?.typ ?? "?"}-${a !== null && a.typ === "runde" ? a.rundeNr : view.frageNr}`;
  if (key !== storyKey) {
    storyKey = key;
    story = baueStandStory(view);
    standMemo = {
      fuehrerId: view.standings[0]?.id ?? null,
      staende: Object.fromEntries(view.standings.map((sp) => [sp.id, sp.balance])),
    };
  }
  if (story === null) return html``;
  return html`<div class="stand-story" data-testid="stand-story">
    <span class="stand-story-icon">${story.icon}</span>
    <span>${story.text}</span>
  </div>`;
}

function toepfe(view: ScreenView): TemplateResult {
  if (view.jackpotGlas === 0 && view.pott === 0) return html``;
  return html`<p style="font-size:1.2rem">
    ${view.jackpotGlas > 0 ? html`🍯 Jackpot-Glas: <strong style="color:var(--gold)">${formatMM(view.jackpotGlas)}</strong> ` : ""}
    ${view.pott > 0 ? html`💰 Pott: <strong style="color:var(--gold)">${formatMM(view.pott)}</strong>` : ""}
  </p>`;
}

/** Kategorien-Wahl: Icon-Karten + Live-Stimmen-Balken. */
function kategorieWahl(view: ScreenView): TemplateResult {
  const kw = view.kategorieWahl;
  if (!kw) return html`<div class="zentriert"><h1>📚 Kategorie-Wahl …</h1></div>`;
  const max = Math.max(1, ...kw.stimmen);
  return html`<div class="zentriert" style="gap:14px">
    <h1>📚 Welche Kategorie?</h1>
    ${
      kw.nurLetzterWaehlt
        ? html`<p style="font-size:1.3rem">
            Comeback-Regel: <strong style="color:var(--gold)">${kw.waehlerName}</strong> wählt
            allein!
          </p>`
        : html`<p class="muted">Stimmt auf euren Handys ab!</p>`
    }
    <div class="kategorie-karten">
      ${kw.optionen.map((o, i) => {
        const icon = kategorieIcon(o);
        return html`<div class="kategorie-karte" style="--einflug-index:${i}">
          ${icon ? html`<img src=${icon} alt="" />` : html`<span style="font-size:2rem">📚</span>`}
          <span class="name">${kategorieName(o)}</span>
          <div class="balken">
            <div style="width:${(kw.stimmen[i] / max) * 100}%"></div>
          </div>
          <strong style="width:2ch;font-size:1.3rem">${kw.stimmen[i]}</strong>
        </div>`;
      })}
    </div>
  </div>`;
}

/** Letzter Bildschirm-Moment als Banner (Joker/Boost/Strafe/Rad — max. ~6 s). */
function momentBanner(view: ScreenView, serverNow: number): TemplateResult {
  const m = view.momente[view.momente.length - 1];
  if (!m || serverNow - m.ts > 6000) return html``;
  return html`<div class="moment-banner">${m.text}</div>`;
}

/** GM-Voting: Frage + Live-Stimmen unten einblenden (jede Phase). */
function votingBanner(view: ScreenView): TemplateResult {
  const v = view.voting;
  if (!v) return votingErgebnisBanner(view);
  return html`<div style="text-align:center;padding:12px;background:var(--bg2)">
    <strong style="font-size:1.3rem">🗳 ${v.frage}</strong>
    <span style="margin-left:12px">
      ${v.optionen.map((o, i) => html`<span style="margin:0 8px">${o}: <strong>${v.stimmen[i]}</strong></span>`)}
    </span>
  </div>`;
}

/** Voting-Ergebnis (~7 s nach Schluss): Balken + Sieger-Option (Befund-Fix). */
function votingErgebnisBanner(view: ScreenView): TemplateResult {
  const e = view.votingErgebnis;
  if (!e) return html``;
  const max = Math.max(1, ...e.stimmen);
  return html`<div
    data-testid="voting-ergebnis"
    style="text-align:center;padding:12px;background:var(--bg2)"
  >
    <strong style="font-size:1.3rem">🗳 ${e.frage} — Ergebnis</strong>
    <div style="display:flex;gap:20px;justify-content:center;align-items:flex-end;margin-top:8px">
      ${e.optionen.map((o, i) => {
        const gewinner = i === e.gewinnerIndex;
        const hoehe = 8 + Math.round(((e.stimmen[i] ?? 0) / max) * 56);
        return html`<div style="display:flex;flex-direction:column;align-items:center;gap:4px">
          <strong>${e.stimmen[i] ?? 0}</strong>
          <div
            style="width:46px;height:${hoehe}px;border-radius:6px 6px 0 0;background:${
              gewinner ? "var(--gold)" : "var(--gruen)"
            };opacity:${gewinner ? 1 : 0.55}"
          ></div>
          <span style=${gewinner ? "color:var(--gold);font-weight:700" : ""}>
            ${gewinner ? "🏆 " : ""}${o}
          </span>
        </div>`;
      })}
    </div>
  </div>`;
}

/**
 * Lobby-Rotation (Befund-Fix): alle 12 s wechselt der Screen dezent zwischen
 * QR/Join-Info und den 4 Bestenlisten — leere Boards rotieren NICHT mit.
 */
// ---------- LOBBY-UX: Link teilen + Sichtbarkeit + Raum-Name (room.config) ----------
let linkKopiert = false;
let zeigeLinkFeld = false; // HTTP-Fallback: Text-Feld mit Auswahl (Caps-Schicht!)
let nameEntwurf: string | null = null; // null = nicht im Editier-Modus

function neuZeichnen(): void {
  window.dispatchEvent(new Event("mm:zeichne"));
}

function teileLink(joinUrl: string): void {
  if (detectCaps().clipboard) {
    void navigator.clipboard
      .writeText(joinUrl)
      .then(() => {
        linkKopiert = true;
        neuZeichnen();
        window.setTimeout(() => {
          linkKopiert = false;
          neuZeichnen();
        }, 2500);
      })
      .catch(() => {
        zeigeLinkFeld = true;
        neuZeichnen();
      });
  } else {
    // LAN-Modus (HTTP): kein Clipboard-API — Feld zeigen, Text vorausgewählt.
    zeigeLinkFeld = !zeigeLinkFeld;
    neuZeichnen();
  }
}

/** Teilen/Sichtbarkeit/Name-Zeile der Lobby (nur mit room.config-Sender). */
function lobbyConfigZeile(view: ScreenView, raumConfig: RaumConfigSender): TemplateResult {
  return html`<div class="zentriert" style="gap:8px">
    <div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap;justify-content:center">
      ${
        nameEntwurf === null
          ? html`<span data-testid="lobby-name" style="font-size:1.1rem">🏷️ ${view.lobbyName}</span>
              <button
                style="min-height:40px;padding:4px 12px;font-size:0.85rem"
                aria-label="Raum-Namen ändern"
                @click=${() => {
                  nameEntwurf = view.lobbyName;
                  neuZeichnen();
                }}
              >
                ✏️
              </button>`
          : html`<input
                style="font-size:1rem;width:min(280px,60vw)"
                maxlength="32"
                .value=${nameEntwurf}
                @input=${(e: Event) => {
                  nameEntwurf = (e.target as HTMLInputElement).value;
                }}
                @keydown=${(e: KeyboardEvent) => {
                  if (e.key === "Enter") {
                    raumConfig({ name: nameEntwurf ?? "" });
                    nameEntwurf = null;
                    neuZeichnen();
                  }
                }}
              />
              <button
                class="primaer"
                style="min-height:40px;padding:4px 12px;font-size:0.85rem"
                @click=${() => {
                  raumConfig({ name: nameEntwurf ?? "" });
                  nameEntwurf = null;
                  neuZeichnen();
                }}
              >
                OK
              </button>`
      }
      <button
        data-testid="sichtbarkeit-toggle"
        style="min-height:40px;padding:4px 12px;font-size:0.85rem"
        @click=${() => raumConfig({ oeffentlich: !view.oeffentlich })}
      >
        ${view.oeffentlich ? "🌍 Öffentlich sichtbar" : "🔒 Privat (nur Code)"}
      </button>
      <button
        data-testid="link-teilen"
        style="min-height:40px;padding:4px 12px;font-size:0.85rem"
        @click=${() => teileLink(view.joinUrl)}
      >
        ${linkKopiert ? "✅ Link kopiert!" : "🔗 Link teilen"}
      </button>
    </div>
    ${
      zeigeLinkFeld
        ? html`<input
            data-testid="link-feld"
            class="mono"
            readonly
            style="width:min(420px,80vw);font-size:0.95rem;text-align:center"
            .value=${view.joinUrl}
            @focus=${(e: Event) => (e.target as HTMLInputElement).select()}
            @click=${(e: Event) => (e.target as HTMLInputElement).select()}
          />`
        : ""
    }
  </div>`;
}

// ---------- INTERNET-LINK (W4): 🌐-Bereich neben dem LAN-QR ----------
// Screen-lokaler UI-Zustand (Kopier-Feedback + HTTP-Fallback-Feld) — gleiche
// Muster wie teileLink oben; der Tunnel-Status selbst kommt vom Server.
let tunnelLinkKopiert = false;
let zeigeTunnelLinkFeld = false;

function kopiereTunnelLink(joinUrl: string): void {
  if (detectCaps().clipboard) {
    void navigator.clipboard
      .writeText(joinUrl)
      .then(() => {
        tunnelLinkKopiert = true;
        neuZeichnen();
        window.setTimeout(() => {
          tunnelLinkKopiert = false;
          neuZeichnen();
        }, 2500);
      })
      .catch(() => {
        zeigeTunnelLinkFeld = true;
        neuZeichnen();
      });
  } else {
    // LAN-Modus (HTTP): kein Clipboard-API — Feld zeigen, Text vorausgewählt.
    zeigeTunnelLinkFeld = !zeigeTunnelLinkFeld;
    neuZeichnen();
  }
}

/** 🌐 Internet-Link neben dem LAN-QR: Knopf → Spinner → öffentliche URL GROSS
 * + eigener QR (/api/qr?via=tunnel) + Kopieren-Fallback. iPad-Standalone
 * bekommt den ehrlichen Hinweis — cloudflared läuft NICHT auf iOS. */
function internetLinkBereich(view: ScreenView, tunnel: TunnelUi | null): TemplateResult {
  if (istStandalone()) {
    return html`<div class="internet-link" data-testid="internet-link">
      <p class="internet-link-titel">🌐 Internet-Link</p>
      <p class="muted" style="margin:4px 0;max-width:30ch">
        Internet-Links gehen nur am PC/AMP-Server — auf dem iPad läuft kein cloudflared. Für Freunde
        außerhalb deines WLANs: MONKEY MONEY auf einem PC starten (docs/DEPLOY-PC.md).
      </p>
    </div>`;
  }
  if (tunnel === null) return html``;
  const s = tunnel.status;
  const phase = s?.phase ?? "aus";
  return html`<div class="internet-link" data-testid="internet-link">
    <p class="internet-link-titel">🌐 Internet-Link</p>
    ${
      phase === "aus"
        ? html`<button
              class="primaer"
              data-testid="tunnel-erstellen"
              style="min-height:52px;font-size:1.05rem"
              @click=${() => tunnel.cmd("start")}
            >
              🌐 Link erstellen
            </button>
            <p class="muted" style="margin:6px 0 0">Für Freunde außerhalb deines WLANs</p>`
        : ""
    }
    ${
      phase === "startet"
        ? html`<p data-testid="tunnel-spinner" style="margin:6px 0;font-size:1.05rem">
            <span class="lade-kringel"></span> Internet-Link wird erstellt …
          </p>`
        : ""
    }
    ${phase === "laeuft" && s?.url ? internetLinkAktiv(view, tunnel, s.url) : ""}
    ${
      phase === "fehler"
        ? html`<p style="margin:6px 0;color:var(--rot);max-width:34ch">⚠️ ${s?.fehler}</p>
            <button data-testid="tunnel-erstellen" @click=${() => tunnel.cmd("start")}>
              🔁 Nochmal versuchen
            </button>`
        : ""
    }
    ${
      phase === "nicht-installiert"
        ? html`<p style="margin:6px 0;max-width:38ch">🔌 ${s?.fehler}</p>
            <div style="text-align:left;max-width:min(560px,72vw)">
              ${(s?.installHinweise ?? []).map(
                (hinweis) =>
                  html`<p class="mono" style="font-size:0.75rem;margin:2px 0;word-break:break-all">
                    ${hinweis}
                  </p>`,
              )}
            </div>
            <button data-testid="tunnel-erstellen" @click=${() => tunnel.cmd("start")}>
              🔁 Nochmal prüfen
            </button>`
        : ""
    }
  </div>`;
}

/** Aktiver Tunnel: öffentliche Join-URL GROSS + eigener QR + Kopieren + Stopp. */
function internetLinkAktiv(view: ScreenView, tunnel: TunnelUi, url: string): TemplateResult {
  const joinUrl = `${url}/j/${view.roomCode}`;
  return html`<div style="display:flex;gap:14px;align-items:center;justify-content:center">
      <img
        data-testid="tunnel-qr"
        src="/api/qr?code=${view.roomCode}&via=tunnel"
        alt="QR-Code für den Internet-Link"
        class="mm-sticker"
        style="width:min(170px,20vw);background:#fff;padding:6px;rotate:1.5deg"
      />
      <div style="text-align:left;max-width:min(460px,44vw)">
        <p data-testid="tunnel-url" style="font-size:1.25rem;margin:0;word-break:break-all">
          ${joinUrl}
        </p>
        <div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:8px">
          <button
            data-testid="tunnel-link-kopieren"
            style="min-height:40px;padding:4px 12px;font-size:0.85rem"
            @click=${() => kopiereTunnelLink(joinUrl)}
          >
            ${tunnelLinkKopiert ? "✅ Link kopiert!" : "📋 Link kopieren"}
          </button>
          <button
            data-testid="tunnel-beenden"
            style="min-height:40px;padding:4px 12px;font-size:0.85rem"
            @click=${() => tunnel.cmd("stop")}
          >
            ✕ Link beenden
          </button>
        </div>
      </div>
    </div>
    ${
      zeigeTunnelLinkFeld
        ? html`<input
            data-testid="tunnel-link-feld"
            class="mono"
            readonly
            style="width:min(420px,70vw);font-size:0.9rem;text-align:center;margin-top:6px"
            .value=${joinUrl}
            @focus=${(e: Event) => (e.target as HTMLInputElement).select()}
            @click=${(e: Event) => (e.target as HTMLInputElement).select()}
          />`
        : ""
    }
    <p class="muted" style="font-size:0.85rem;margin:8px 0 0;max-width:44ch">
      ⚠️ Jeder mit dem Link kann beitreten — der Raum-Code bleibt zusätzlich nötig. Der Link endet
      mit dem Server-Stopp.
    </p>`;
}

function lobby(
  view: ScreenView,
  boards: Boards | null,
  nowMs: number,
  raumConfig: RaumConfigSender | null,
  tunnel: TunnelUi | null = null,
): TemplateResult {
  const slides = lobbySlides(boards);
  const slide = slides[lobbySlideIndex(nowMs, slides.length)];
  if (slide !== "qr" && boards) return lobbyBoardSlide(view, boards, slide);
  return html`<div class="zentriert" style="gap:16px">
    <h1 style="font-size:var(--mm-display-m);color:var(--gold)">🐒 MONKEY MONEY</h1>
    <div style="display:flex;gap:32px;align-items:center;flex-wrap:wrap;justify-content:center">
      <img
        src=${view.qrPath}
        alt="QR-Code zum Mitspielen"
        class="mm-sticker"
        style="width:min(250px,32vw);background:#fff;padding:8px;rotate:-1.5deg"
      />
      <div style="text-align:left">
        <p class="muted" style="margin:0">Handy-Kamera drauf oder tippen:</p>
        <p style="font-size:1.3rem;margin:4px 0">${view.joinUrl}</p>
        <p class="mono" style="font-size:3.2rem;margin:8px 0;color:var(--gold)">${view.roomCode}</p>
        <p class="muted" style="font-size:0.9rem">
          🎩 Show-Master-PIN: <strong>${view.gmPin}</strong>
        </p>
      </div>
      ${internetLinkBereich(view, tunnel)}
    </div>
    ${raumConfig !== null ? lobbyConfigZeile(view, raumConfig) : ""}
    <p class="muted">
      ${
        view.players.length === 0
          ? "Noch keine Affen im Studio …"
          : `${view.players.length} / 8 Spieler — der Show-Master startet das Match (mind. 2).`
      }
    </p>
    ${
      view.teams !== null && view.teams.wahlOffen
        ? teamSpalten(view.teams, view.players.length)
        : ""
    }
  </div>`;
}

/** Ein Bestenlisten-Slide (dezent): Top 5 + kleine Join-Zeile unten. */
function lobbyBoardSlide(view: ScreenView, boards: Boards, key: keyof Boards): TemplateResult {
  const eintraege = boards[key].slice(0, 5);
  return html`<div class="zentriert" data-testid="lobby-board" style="gap:12px">
    <h1 style="color:var(--gold)">${BOARD_TITEL[key]}</h1>
    <div style="display:flex;flex-direction:column;gap:6px;min-width:min(560px,80vw)">
      ${eintraege.map(
        (e, i) =>
          html`<div
            style="display:flex;align-items:center;gap:14px;padding:8px 16px;background:var(--bg2);border-radius:10px;font-size:1.25rem"
          >
            <span style="width:2ch;color:var(--gold);font-weight:700">${i + 1}.</span>
            <span style="flex:1;text-align:left"
              >${e.name}${e.extra ? html` <span class="muted" style="font-size:0.85rem">(${e.extra})</span>` : ""}</span
            >
            <strong style="color:var(--gold)">${e.anzeige}</strong>
          </div>`,
      )}
    </div>
    <p class="muted" style="font-size:0.95rem">
      📱 Mitspielen: ${view.joinUrl} · Code
      <strong class="mono" style="color:var(--gold)">${view.roomCode}</strong>
    </p>
  </div>`;
}

/** Richtig/Falsch-Chips unter der Auflösung (Namen kennt nur die App, nicht das Plugin).
 * W4-Polish: Puppen-Kopf-Mini statt nackter Namen (Kopf-Ausschnitt-Muster der
 * Meta-Seiten), Richtige zuerst, Deltas konsistent grün (+) / rot (−). */
function ergebnisChips(view: ScreenView): TemplateResult[] {
  const mg = view.minigame?.view as AufloesungView | undefined;
  if (!mg?.aufloesung) return [];
  const sortiert = [...mg.aufloesung.perPlayer].sort(
    (a, b) => Number(b.correct) - Number(a.correct) || b.delta - a.delta,
  );
  return sortiert.map((r, i) => {
    const p = view.players.find((x) => x.id === r.playerId);
    return html`<span
      class="ergebnis-chip ${r.correct ? "richtig" : "falsch"}"
      style="--chip-i:${i}"
    >
      <span
        class="ergebnis-kopf mm-affe"
        data-avatar=${p?.avatar ?? "gelb"}
        data-gesicht=${r.correct ? "jubel" : "frust"}
      ></span>
      <span class="ergebnis-name">${r.correct ? "✅" : "❌"} ${p?.name ?? "?"}</span>
      <strong
        class="ergebnis-delta mm-money-zahl ${r.delta < 0 ? "minus" : r.delta > 0 ? "plus" : "null"}"
      >
        ${r.delta > 0 ? `+${formatMM(r.delta)}` : r.delta < 0 ? `−${formatMM(-r.delta)}` : "±0"}
      </strong>
    </span>`;
  });
}

// Cutscenes (skippable, Echtzeit): Show-Opening mit Logo-Stinger + Kandidaten-
// Vorstellung (intro-Phase), aufgewertete Runden-Ankündigungs-Karten und die
// Siegerehrung mit Podest-Einlauf 3-2-1 + Awards. Beats laufen über CSS-Delays
// (nur transform/opacity) — Skip regelt die Engine (alle-bereit/GM-next).
import { html, type TemplateResult } from "lit-html";
import { detectCaps } from "../../shared/caps";
import { schwierigkeitLabel } from "../../shared/kategorien";
import { formatMM } from "../../shared/money";
import type { ScreenView } from "../../shared/views";
import { affeInfo, avatarFarbe, parseAvatar } from "../shared/fx/avatar";
import { SIEG_FANFARE_MS } from "../shared/fx/sound-map";
import type { FxApi } from "../shared/minigames/types";
import { getMinigameModule } from "../shared/minigames/registry";
import { teamPodest } from "../shared/teams-ui";
import { demoBuehne, demoChoreoFuer } from "./erklaer-demo";
import { kategorieIcon, kategorieName } from "./studio";
import { fotoFinishBlock, jubilaeumsKarte } from "./v2";

const logoUrl = new URL("../../assets/img/logo/monkey-money-logo.svg", import.meta.url).href;

// ---------- Logo-Stinger (gerendertes 3D-Video, VOR der Kandidaten-Vorstellung) ----------
// Caps-Schicht: ohne <video>-Support (oder wenn Autoplay/Laden scheitert) fällt
// das Opening sofort auf das bisherige Logo-Bild zurück — kein schwarzes Loch.
const STINGER_WEBM = "/media/video/logo_stinger.webm"; // VP9 MIT Alpha
const STINGER_MP4 = "/media/video/logo_stinger.mp4";
const STINGER_TIMEOUT_MS = 2_500; // Autoplay-Policy/Laden zickt ⇒ Fallback

const caps = detectCaps();
let stingerFertig = !caps.video; // pro Screen-Load einmal (1 Match pro Load)
let stingerLief = false;
let stingerTimer: number | null = null;

/** Cutscene-State geändert (Video zu Ende/Fehler) ⇒ App soll neu zeichnen. */
function neuZeichnen(): void {
  window.dispatchEvent(new Event("mm:zeichne"));
}

function stingerVorbei(): void {
  if (stingerFertig) return;
  stingerFertig = true;
  if (stingerTimer !== null) window.clearTimeout(stingerTimer);
  neuZeichnen();
}

/** Overlay mit dem Stinger-Video — Ende/Fehler/Timeout blenden zur Vorstellung über. */
function stingerOverlay(): TemplateResult {
  if (stingerTimer === null) {
    stingerTimer = window.setTimeout(() => {
      if (!stingerLief) stingerVorbei(); // Autoplay wurde geblockt / lädt nicht
    }, STINGER_TIMEOUT_MS);
  }
  return html`<div class="stinger-overlay">
    <video
      class="stinger-video"
      autoplay
      muted
      playsinline
      @playing=${() => {
        stingerLief = true;
      }}
      @ended=${stingerVorbei}
      @error=${stingerVorbei}
    >
      <source src=${STINGER_WEBM} type="video/webm" />
      <source src=${STINGER_MP4} type="video/mp4" />
    </video>
  </div>`;
}

/** Beat-2-Startzeit: erst wenn der LETZTE Kandidat gelandet ist (Einflug
 * startet bei 1,1 s + i×0,45 s, Hop ~0,5 s) plus eine kurze Atempause. */
function beat2Start(kandidaten: number): string {
  return `${(1.1 + Math.max(0, kandidaten - 1) * 0.45 + 1.2).toFixed(2)}s`;
}

/** Show-Opening: Stinger-Video → Logo → Kandidaten hüpfen nacheinander rein.
 * Spotlight-Sweep (CSS-Gradient, günstig) bespielt die dunkle Bühne; die
 * Rollen-Labels sind auf Sofadistanz lesbar (Playtest 3).
 * Beat 2 (W3): danach schwenkt ein Spot im Loop von Affe zu Affe + Name-
 * Callout — reine CSS-Animation (kandidaten-reihe in studio.css). */
export function introCutscene(view: ScreenView): TemplateResult {
  return html`<div class="cutscene intro-cutscene ${stingerFertig ? "" : "stinger-aktiv"}">
    <div class="spotlight-sweep" aria-hidden="true"></div>
    ${stingerFertig ? "" : stingerOverlay()}
    <img class="cutscene-logo" src=${logoUrl} alt="MONKEY MONEY" />
    ${view.jubilaeum ? jubilaeumsKarte(view.jubilaeum) : ""}
    <p
      class="muted"
      style="font-size:1.25rem;animation:kandidat-rein 0.5s 0.8s var(--mm-kurve-bounce) both"
    >
      ${view.frageTotal} Fragen — wer sammelt das meiste MONKEY MONEY?
    </p>
    <div
      class="kandidaten-reihe"
      style="--kandidaten:${view.players.length};--beat-start:${beat2Start(view.players.length)}"
    >
      ${view.players.map((p, i) => {
        const wahl = parseAvatar(p.avatar);
        return html`<div
          class="kandidaten-karte"
          style="animation-delay:${1.1 + i * 0.45}s;--beat-index:${i}"
        >
          <div
            class="kandidaten-puppe mm-affe mm-affe-idle"
            data-avatar=${p.avatar}
            data-gesicht="jubel"
            style="--idle-versatz:${(i * 0.4).toFixed(2)}s"
          ></div>
          <span
            class="podium-name"
            style="--spielerfarbe:${avatarFarbe(p.avatar)};font-size:1.05rem;padding:3px 12px"
            >${p.name}</span
          >
          <span class="kandidaten-rolle">${affeInfo(wahl.affe).rolle}</span>
        </div>`;
      })}
    </div>
  </div>`;
}

// ---------- Tutorial-Video auf der Erklärkarte (Match-Setting tutorialVideos) ----------
// Ein Klick klappt das Video auf (Klick = Nutzer-Geste ⇒ Autoplay mit Ton ok);
// GM-Weiter/alle-bereit-Skip bleiben unberührt — die Phase läuft normal weiter.
let tutorialOffenFuer: string | null = null;

function tutorialVideoBlock(videoUrl: string, karteKey: string): TemplateResult {
  if (tutorialOffenFuer !== karteKey) {
    return html`<button
      class="tutorial-knopf"
      @click=${() => {
        tutorialOffenFuer = karteKey;
        neuZeichnen();
      }}
    >
      🎬 Video ansehen
    </button>`;
  }
  return html`<video class="tutorial-video" controls autoplay playsinline src=${videoUrl}></video>`;
}

/** Runden-Ankündigungs-Karte: Slot-Tag + Format-Titel + Regel-Beats + Bereit-Punkte.
 * Mit Demo-Choreo (Mario-Party-Prinzip): 2 Beispiel-Affen SPIELEN die Mechanik
 * vor (Bühne groß, Regel-Kurztext max. 2 Zeilen) — Formate ohne Choreo behalten
 * die Emoji-Animation + Volltext; Skip (GM/alle-bereit) bleibt unverändert. */
export function rundenKarte(view: ScreenView, fx?: FxApi): TemplateResult {
  const ek = view.erklaerkarte;
  if (!ek) return html`<div class="zentriert"><h1>🃏 …</h1></div>`;
  const modul = getMinigameModule(ek.minigameId);
  const verbunden = view.players.filter((p) => p.connected);
  const slotNamen: Record<string, string> = {
    opener: "🎬 Opener",
    aufbau: "🧱 Aufbau",
    geld: "💰 Geld-Runde",
    konflikt: "⚔️ Konflikt",
    risiko: "🎲 Risiko",
  };
  // Offenes Tutorial-Video braucht Platz auf der Karte ⇒ Emoji-Anim/Demo weicht.
  const tutorialOffen =
    ek.videoUrl !== undefined &&
    caps.video &&
    tutorialOffenFuer === `${ek.minigameId}:${ek.endetAt}`;
  const choreo = fx ? demoChoreoFuer(ek.minigameId) : null;
  const demoAn = choreo !== null && !tutorialOffen;
  return html`<div class="cutscene">
    <div class="runden-karte ${demoAn ? "mit-demo" : ""}">
      <span class="slot-tag">${slotNamen[ek.slot ?? ""] ?? ek.slot ?? "Neue Runde"}</span>
      <h1>${ek.minigameName}</h1>
      ${
        tutorialOffen
          ? ""
          : demoAn
            ? demoBuehne(`${ek.minigameId}:${ek.endetAt}`, choreo, fx!)
            : html`<div class="anim">${modul?.explainCard.animation ?? html`🐒`}</div>`
      }
      ${
        ek.wFinal
          ? html`<p class="regel" style="color:var(--mm-curtain);font-weight:800">
              Jede Frage ist heute ${formatMM(ek.wFinal)} wert!
            </p>`
          : ""
      }
      ${tutorialOffen ? "" : html`<p class="regel">${ek.text}</p>`}
      ${ek.videoUrl && caps.video ? tutorialVideoBlock(ek.videoUrl, `${ek.minigameId}:${ek.endetAt}`) : ""}
      <p style="margin:4px 0;display:flex;align-items:center;justify-content:center;gap:8px">
        ${kategorieBadge(ek.kategorie)}
        <span style="opacity:0.7">${ek.schwierigkeiten.map(schwierigkeitLabel).join(" / ")}</span>
      </p>
      <div class="bereit-punkte">
        ${verbunden.map(
          (p) =>
            html`<span
              class="bereit-punkt ${ek.bereit.includes(p.id) ? "ja" : ""}"
              title=${p.name}
            ></span>`,
        )}
      </div>
      ${
        ek.streik.length > 0
          ? html`<p style="color:var(--mm-curtain);font-weight:800;margin:6px 0 0">
              ✊ ${ek.streik.length} Streik-Stimme(n) gegen dieses Spiel!
            </p>`
          : ""
      }
    </div>
    <p class="muted">Bereit-Knopf auf den Handys drücken — dann geht's sofort los!</p>
  </div>`;
}

function kategorieBadge(kategorie: string | null): TemplateResult {
  if (!kategorie) return html``;
  const icon = kategorieIcon(kategorie);
  return html`<span style="display:inline-flex;align-items:center;gap:6px;font-weight:700">
    ${icon ? html`<img src=${icon} alt="" style="width:32px;height:32px" />` : ""}
    ${kategorieName(kategorie)}
  </span>`;
}

/** Siegerehrung: Podest-Einlauf 3-2-1, dann Awards (Money-Regen macht main.ts). */
export function siegerehrungCutscene(view: ScreenView): TemplateResult {
  const sg = view.siegerehrung;
  if (!sg) return html`<div class="zentriert"><h1>🏆 Siegerehrung!</h1></div>`;
  // Team-Modus (§1.4): Team-Podest (Farbe als Rahmen/Banner, Topf groß,
  // Mitglieder mit Einzel-Konten) statt Einzel-Podest — Awards bleiben
  // (inkl. „Bester Einzel-Affe" aus der Engine).
  if (sg.teams !== undefined) {
    return html`<div class="cutscene" style="gap:12px">
      <h1 style="font-size:var(--mm-display-l);color:var(--gold)">🏆 Siegerehrung</h1>
      ${teamPodest(sg.teams, view.teams)}
      <p class="sieger-restzeile">
        ${sg.platzierungen
          .map((p) => `${p.platz}. ${p.name} (${formatMM(p.balance)} · +${p.at} AT)`)
          .join(" · ")}
      </p>
      ${awardBand(sg.awards)}
    </div>`;
  }
  const podest = sg.platzierungen.filter((p) => p.platz <= 3);
  // Einlauf-Reihenfolge 3 → 2 → 1; Anordnung auf der Bühne: 2 | 1 | 3.
  const reihenfolge = [2, 1, 3]
    .map((platz) => podest.find((p) => p.platz === platz))
    .filter((p) => p !== undefined);
  // Podest-Landung an die FANFARE gekoppelt (P2-Audio-Sync): Platz 1 landet
  // (Hop-Dauer 0,7 s) exakt bei SIEG_FANFARE_MS — 3 und 2 je 0,9 s davor.
  const delay = (platz: number): string =>
    `${(SIEG_FANFARE_MS / 1000 - 0.7 - (platz - 1) * 0.9).toFixed(2)}s`;
  const rest = sg.platzierungen.filter((p) => p.platz > 3);
  return html`<div class="cutscene" style="gap:10px">
    <h1 style="font-size:var(--mm-display-l);color:var(--gold)">🏆 Siegerehrung</h1>
    <div class="podest-reihe">
      ${reihenfolge.map(
        (p) =>
          html`<div class="podest platz-${p.platz}" style="--einlauf-delay:${delay(p.platz)}">
            <div
              class="kandidaten-puppe mm-affe mm-affe-idle"
              data-avatar=${p.avatar}
              data-gesicht=${p.platz === 1 ? "jubel" : p.platz === 3 ? "frust" : "neutral"}
            ></div>
            <span
              class="podium-name"
              style="--spielerfarbe:${avatarFarbe(p.avatar)};font-size:1rem"
            >
              ${p.name}
            </span>
            <span class="podium-konto" style="font-size:1.15rem">
              ${formatMM(p.balance)} <span class="podium-at">+${p.at} AT</span>
            </span>
            <div class="podest-block">${p.platz}</div>
          </div>`,
      )}
    </div>
    ${
      rest.length > 0
        ? html`<p class="sieger-restzeile">
            ${rest.map((p) => `${p.platz}. ${p.name} (${formatMM(p.balance)})`).join(" · ")}
          </p>`
        : ""
    }
    ${awardBand(sg.awards)}
  </div>`;
}

/** Award-Zone (Einzel- UND Team-Siegerehrung): Awards laufen als Beats
 * NACHEINANDER groß in einer reservierten Zone (Playtest 3: gleichzeitige
 * kleine Karten verloren gegen das Konfetti); der letzte bleibt stehen. */
function awardBand(awards: { titel: string; name: string; wert: string }[]): TemplateResult {
  if (awards.length === 0) return html``;
  // 12-s-Phase: Awards starten NACH der Fanfare (P2-Audio-Sync: Landung +
  // Konfetti gehören der Fanfare allein) und teilen sich den Rest der Phase.
  const startS = SIEG_FANFARE_MS / 1000 + 0.1;
  const beatS = Math.min(2.4, Math.max(1.6, (12 - startS - 0.1) / awards.length));
  return html`<div class="award-zone">
    ${awards.map(
      (a, i) =>
        html`<div
          class="award-karte ${i === awards.length - 1 ? "bleibt" : ""}"
          style="--einlauf-delay:${(startS + i * beatS).toFixed(2)}s;--beat-dauer:${beatS.toFixed(2)}s;--kipp:${i % 2 === 0 ? "-1.5deg" : "2deg"}"
        >
          🏅 <strong>${a.titel}</strong>: ${a.name} <span class="award-wert">(${a.wert})</span>
        </div>`,
    )}
  </div>`;
}

/** Abspann (ende) — W4-Hierarchie: 1) Sieger-Schlagzeile, 2) prominenter
 * Rematch-CTA (lädt den Screen für eine neue Runde neu), 3) Foto-Finish +
 * Feedback als sekundäre Zone, 4) Credits als dezenter Aufklapp-Link.
 * Team-Modus: das SIEGER-TEAM (höchster Topf) steht in der Schlagzeile. */
export function endeScreen(view: ScreenView, serverNow: number): TemplateResult {
  const sieger = view.standings[0];
  const teamSieger = view.siegerehrung?.teams?.[0];
  return html`<div class="cutscene ende-cutscene">
    <h1 style="font-size:var(--mm-display-xl);color:var(--gold)">
      🏆 ${teamSieger ? `${teamSieger.emoji} ${teamSieger.name}` : (sieger?.name ?? "?")} gewinnt!
    </h1>
    <p style="font-size:1.5rem;color:var(--gold);margin:0" class="mm-money-zahl">
      ${teamSieger ? formatMM(teamSieger.topf) : sieger ? formatMM(sieger.balance) : ""} 🎉🍌🎉
    </p>
    <button
      class="ende-rematch"
      data-testid="ende-rematch"
      @click=${() => window.location.reload()}
    >
      🔁 REVANCHE — neues Match!
    </button>
    <div class="ende-sekundaer">
      ${fotoFinishBlock(view, serverNow, neuZeichnen)}
      ${
        view.feedbackAngefragt
          ? html`<p class="muted" style="margin:0">
              💬 Feedback auf euren Handys — tippt drauf los!
            </p>`
          : ""
      }
    </div>
    <details class="ende-credits">
      <summary>Credits</summary>
      <p>
        Musik: Kevin MacLeod (incompetech.com), CC BY 4.0 · Sounds: Kenney.nl (CC0) · Applaus:
        freesound.org (CC0/CC BY) — Details im Landing-Footer unter „Credits".
      </p>
    </details>
  </div>`;
}

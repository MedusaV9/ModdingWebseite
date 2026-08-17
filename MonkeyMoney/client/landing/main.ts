// Landing (/) — Geräte-Erkennung + Rollen-Wahl (TECH-SPEC §7.1) + Credits.
// Heuristik wählt VOR, aber IMMER mit einem Tap bestätigen lassen.
// LOBBY: öffentlicher Lobby-Browser (Opt-in!) + „⚡ Schnell beitreten" +
// „Zuletzt gespielt"-Banner (Session-Token-Restore existiert bereits).
import { html, render, type TemplateResult } from "lit-html";
import { io, type Socket } from "socket.io-client";
import { detectCaps, detectGeraet, type Geraet } from "../../shared/caps";
import type { LobbyInfo } from "../../shared/protocol";
import { ladeToken } from "../shared/session";
import { metaAktiv, oeffneMeta, zeichneMeta } from "./meta-landing";
import "../shared/base.css";
import "./landing.css";

// Das echte Show-Logo (Wortmarke mit Münzen-Os) — Vite bündelt es, damit es
// auch im Standalone-/AMP-Betrieb ohne /media-Route da ist (Muster: cutscenes.ts).
const logoUrl = new URL("../../assets/img/logo/monkey-money-logo.svg", import.meta.url).href;

const app = document.getElementById("app")!;
const geraet: Geraet = detectGeraet();
const caps = detectCaps();

let zeigeCodeEingabe = false;
let zeigeCredits = false;
let zeigeBildschirmWahl = false;
let zeigeSchnellDialog = false;
let code = "";
let codeHinweis: string | null = null;

// ---------- LOBBY: Browser-Liste + Live-Socket + „Zuletzt gespielt" ----------
let lobbys: LobbyInfo[] = [];
let lobbySocket: Socket | null = null;
let zuletzt: { code: string; spieler: number } | null = null;

const MODUS_LABEL: Record<string, string> = {
  quick: "⚡ Quick",
  klassik: "🎪 Klassik",
  marathon: "🏃 Marathon",
};

const MODUS_ICON: Record<string, string> = {
  quick: "⚡",
  klassik: "🎪",
  marathon: "🏃",
};

function verbindeLobbyBrowser(): void {
  if (lobbySocket) return;
  lobbySocket = io(); // relative URL — HTTP-LAN und HTTPS-Tunnel mit EINEM Build
  lobbySocket.on("connect", () => lobbySocket?.emit("lobby.subscribe", {}));
  lobbySocket.on("lobby.update", (msg: { lobbys: LobbyInfo[] }) => {
    lobbys = msg.lobbys;
    zeichne();
  });
}

/** „Zuletzt gespielt mit Raum XY — wieder beitreten?" (localStorage + Token). */
function pruefeZuletzt(): void {
  let gemerkt: string | null = null;
  try {
    gemerkt = localStorage.getItem("mm:zuletzt");
  } catch {
    return;
  }
  if (!gemerkt || ladeToken(gemerkt) === null) return;
  const raumCode = gemerkt;
  void fetch(`/api/raum/${raumCode}`)
    .then((r) => (r.ok ? (r.json() as Promise<{ ok: boolean; spieler: number }>) : null))
    .then((d) => {
      if (d?.ok) {
        zuletzt = { code: raumCode, spieler: d.spieler };
        zeichne();
      }
    })
    .catch(() => {
      /* Server nicht erreichbar ⇒ kein Banner */
    });
}

/** Schnell-Beitritt: vollste offene öffentliche Lobby — sonst Dialog. */
function schnellBeitreten(): void {
  void fetch("/api/schnell-beitritt")
    .then((r) => (r.ok ? (r.json() as Promise<{ ok: boolean; code: string }>) : null))
    .then((d) => {
      if (d?.ok) {
        window.location.href = `/j/${d.code}`;
      } else {
        zeigeSchnellDialog = true;
        zeichne();
      }
    })
    .catch(() => {
      zeigeSchnellDialog = true;
      zeichne();
    });
}

function empfehlung(rolle: "screen" | "player" | "gm"): string {
  if (geraet === "phone" && rolle === "player") return "empfohlen für dein iPhone";
  if (geraet === "ipad" && rolle === "screen") return "empfohlen für dein iPad";
  return "";
}

function mitspielen(): void {
  zeigeCodeEingabe = true;
  zeichne();
  // Autofokus: das Feld existiert erst nach dem Render-Durchlauf.
  window.setTimeout(() => document.getElementById("code-eingabe")?.focus(), 0);
}

function joinMitCode(): void {
  if (code.length === 4) {
    window.location.href = `/join/${code.toUpperCase()}`;
    return;
  }
  codeHinweis = "Fast! Codes haben genau 4 Buchstaben.";
  zeichne();
}

function merkeRolle(rolle: string): void {
  try {
    localStorage.setItem("mm:rolle", rolle);
  } catch {
    /* egal */
  }
}

/** iOS-Safari außerhalb des Homescreen-Modus? → dezenter Hinweis. */
function zeigeIosHinweis(): boolean {
  const nav = navigator as Navigator & { standalone?: boolean };
  const ios = /iPhone|iPad|iPod/i.test(navigator.userAgent) || geraet === "ipad";
  return ios && nav.standalone !== true;
}

/** Credits-Screen (Pflicht: MacLeod-Attributions-Formel, aus CREDITS.md). */
function creditsScreen(): TemplateResult {
  return html`<div class="zentriert" style="gap:10px;overflow-y:auto">
    <h1>💛 Credits</h1>
    <div class="karte" style="max-width:min(560px,92vw);text-align:left;font-size:0.95rem">
      <p style="margin:4px 0">
        <strong>Musik:</strong> "Music: Kevin MacLeod (incompetech.com), Licensed under Creative
        Commons: By Attribution 4.0" —
        <a href="https://creativecommons.org/licenses/by/4.0/" style="color:var(--gold)"
          >CC BY 4.0</a
        ><br />
        <span class="muted"
          >Tracks: Monkeys Spinning Monkeys · Quirky Dog · Sneaky Snitch · Merry Go · Fluffing a
          Duck · Local Forecast (Elevator)</span
        >
      </p>
      <p style="margin:10px 0 4px">
        <strong>Sound-Effekte:</strong>
        <a href="https://kenney.nl" style="color:var(--gold)">Kenney.nl</a> (Interface, UI, Music
        Jingles, Digital, Impact, Casino, Sci-Fi) — CC0 1.0 ·
        <a href="https://bigsoundbank.com" style="color:var(--gold)">BigSoundBank.com</a> / Joseph
        SARDIN (Buzzer-Familie) — CC0
      </p>
      <p style="margin:10px 0 4px">
        <strong>Trommelwirbel &amp; Riser:</strong> Kevin MacLeod (CC BY 3.0), Iwan Sounds and DIY
        (CC0), „Riser 42" von Tri-Tachyon /
        <a href="https://opengameart.org" style="color:var(--gold)">OpenGameArt</a> (CC BY 4.0)
      </p>
      <p style="margin:10px 0 4px">
        <strong>Applaus &amp; Kasse:</strong> Wikimedia Commons — RHumphries (CC BY 3.0), thore,
        stephan, starlite, Kassen-Kaching (Public Domain)
      </p>
      <p style="margin:10px 0 4px">
        <strong>Fonts:</strong> Bungee / Bungee Shade (David Jonathan Ross), Rubik (Hubert & Fischer
        u. a.) — SIL OFL 1.1
      </p>
      <p class="muted" style="margin:10px 0 0;font-size:0.85rem">
        Alle Dritt-Assets frei lizenziert — Details in CREDITS.md im Repo.
      </p>
    </div>
    <button
      @click=${() => {
        zeigeCredits = false;
        zeichne();
      }}
    >
      ← Zurück
    </button>
  </div>`;
}

/** Bildschirm eröffnen: Privat (nur Code, Default) oder öffentlich sichtbar. */
function bildschirmWahl(): TemplateResult {
  return html`<div class="zentriert" style="gap:12px">
    <h1>📺 Bildschirm eröffnen</h1>
    <p class="muted" style="max-width:min(420px,86vw);margin:0">
      Soll deine Lobby im öffentlichen Lobby-Browser auftauchen — oder bleibt ihr unter euch?
    </p>
    <button
      class="primaer"
      style="width:min(360px,86vw)"
      @click=${() => {
        merkeRolle("screen");
        window.location.href = "/screen";
      }}
    >
      🔒 Privat (nur Code)
      <small style="display:block;font-weight:400">Nur wer den Code hat, kommt rein</small>
    </button>
    <button
      style="width:min(360px,86vw)"
      @click=${() => {
        merkeRolle("screen");
        window.location.href = "/screen?public=1";
      }}
    >
      🌍 Öffentlich sichtbar
      <small style="display:block;font-weight:400"
        >Erscheint im Lobby-Browser — jeder kann joinen</small
      >
    </button>
    <button
      @click=${() => {
        zeigeBildschirmWahl = false;
        zeichne();
      }}
    >
      ← Zurück
    </button>
  </div>`;
}

/** Schnell-Beitritt ohne Treffer: eigene Lobby braucht einen Bildschirm. */
function schnellDialog(): TemplateResult {
  return html`<div class="zentriert" style="gap:12px">
    <h1>🙈 Keine offene Lobby</h1>
    <p class="muted" style="max-width:min(420px,86vw);margin:0">
      Gerade wartet niemand öffentlich. Eröffne selbst eine — du brauchst dafür einen großen
      Bildschirm (iPad, TV oder Beamer), auf dem die Show läuft.
    </p>
    <button
      class="primaer"
      style="width:min(360px,86vw)"
      @click=${() => {
        merkeRolle("screen");
        window.location.href = "/screen?public=1";
      }}
    >
      📺 Öffentliche Lobby eröffnen
      <small style="display:block;font-weight:400">Dieses Gerät wird der große Bildschirm</small>
    </button>
    <button
      style="width:min(360px,86vw)"
      @click=${() => {
        zeigeSchnellDialog = false;
        mitspielen();
      }}
    >
      🔑 Ich habe einen Raum-Code
    </button>
    <button
      @click=${() => {
        zeigeSchnellDialog = false;
        zeichne();
      }}
    >
      ← Zurück
    </button>
  </div>`;
}

/** Sitz-Reihe (Welle 4): belegte Plätze als Mini-Affen, freie als leere Sitze —
 * der Wire liefert (bewusst) keine Avatare, nur spieler/max. */
function lobbySitzreihe(l: LobbyInfo): TemplateResult {
  const plaetze = Math.min(l.max, 8);
  const belegt = Math.min(l.spieler, plaetze);
  return html`<span class="lobby-sitzreihe" title="${l.spieler}/${l.max} Plätze belegt">
    ${Array.from(
      { length: plaetze },
      (_, i) =>
        html`<span class="sitz ${i < belegt ? "belegt" : ""}">${i < belegt ? "🐵" : ""}</span>`,
    )}
    <span class="sitz-zahl">${l.spieler}/${l.max}</span>
  </span>`;
}

/** Öffentlicher Lobby-Browser: nur Opt-in-Lobbys, joinbar nur im Lobby-Status. */
function lobbyBrowser(): TemplateResult {
  if (lobbys.length === 0) return html``;
  return html`<div class="karte lobby-browser" data-testid="lobby-browser">
    <p class="muted" style="margin:2px 0 8px;font-size:0.9rem">🌍 Offene Lobbys</p>
    ${lobbys.map(
      (l) => html`
        <div class="lobby-karte" data-testid="lobby-zeile">
          <span class="lobby-modus" title=${MODUS_LABEL[l.modus] ?? l.modus}>
            ${MODUS_ICON[l.modus] ?? "🎲"}
          </span>
          <div class="lobby-info">
            <div class="lobby-name">${l.name}</div>
            <div class="lobby-meta">
              ${lobbySitzreihe(l)}
              <span class="lobby-status ${l.status === "lobby" ? "wartet" : "laeuft"}">
                ${l.status === "lobby" ? "🟢 wartet" : "🔴 läuft"}
              </span>
              <span class="muted">${MODUS_LABEL[l.modus] ?? l.modus}</span>
            </div>
          </div>
          ${
            l.status === "lobby"
              ? html`<button
                  class="primaer"
                  style="min-height:44px;padding:4px 14px;font-size:0.9rem"
                  @click=${() => (window.location.href = `/j/${l.code}`)}
                >
                  Beitreten
                </button>`
              : html`<span class="muted" style="font-size:0.82rem">läuft …</span>`
          }
        </div>
      `,
    )}
  </div>`;
}

/** Studio-Deko: Blätter-/Geldschein-Silhouetten (flache Token-Füllungen,
 * Farben via CSS currentColor — keine Hexwerte, keine Verläufe). */
function landingDeko(): TemplateResult {
  const blatt =
    "M12 95 C8 55 28 18 90 6 C86 40 66 82 18 94 C46 70 64 48 76 28 C56 42 38 62 22 88 Z";
  const schein =
    "M4 8 L116 8 L116 56 L4 56 Z M60 18 A14 14 0 1 0 60 46 A14 14 0 1 0 60 18 " +
    "M14 16 L22 16 L22 24 L14 24 Z M98 40 L106 40 L106 48 L98 48 Z";
  return html`<div class="landing-deko" aria-hidden="true">
    <svg class="deko-blatt" style="left:-36px;top:4%;width:200px" viewBox="0 0 100 100">
      <path d=${blatt} fill="currentColor" />
    </svg>
    <svg
      class="deko-blatt"
      style="right:-44px;top:12%;width:230px;transform:scaleX(-1) rotate(14deg)"
      viewBox="0 0 100 100"
    >
      <path d=${blatt} fill="currentColor" />
    </svg>
    <svg
      class="deko-blatt"
      style="left:-30px;bottom:-4%;width:190px;transform:rotate(88deg)"
      viewBox="0 0 100 100"
    >
      <path d=${blatt} fill="currentColor" />
    </svg>
    <svg
      class="deko-schein"
      style="right:6%;bottom:16%;width:110px;transform:rotate(-14deg)"
      viewBox="0 0 120 64"
    >
      <path d=${schein} fill="currentColor" fill-rule="evenodd" />
    </svg>
    <svg
      class="deko-schein"
      style="left:5%;top:38%;width:90px;transform:rotate(9deg)"
      viewBox="0 0 120 64"
    >
      <path d=${schein} fill="currentColor" fill-rule="evenodd" />
    </svg>
    <svg
      class="deko-schein"
      style="right:12%;top:6%;width:74px;transform:rotate(22deg)"
      viewBox="0 0 120 64"
    >
      <path d=${schein} fill="currentColor" fill-rule="evenodd" />
    </svg>
  </div>`;
}

/** „Zuletzt gespielt"-Banner: Token existiert ⇒ 1-Tap-Rejoin. */
function zuletztBanner(): TemplateResult {
  if (!zuletzt) return html``;
  return html`<button
    data-testid="zuletzt-banner"
    style="width:min(360px,86vw);border-color:var(--gold)"
    @click=${() => (window.location.href = `/j/${zuletzt!.code}`)}
  >
    🔁 Zuletzt gespielt: Raum <span class="mono">${zuletzt.code}</span>
    <small style="display:block;font-weight:400">Wieder beitreten?</small>
  </button>`;
}

function zeichne(): void {
  // META: Bestenlisten/Shop/Profil/Training als eigener Screen (§7).
  if (metaAktiv()) {
    zeichneMeta(app, zeichne);
    return;
  }
  if (zeigeCredits) {
    render(creditsScreen(), app);
    return;
  }
  if (zeigeBildschirmWahl) {
    render(bildschirmWahl(), app);
    return;
  }
  if (zeigeSchnellDialog) {
    render(schnellDialog(), app);
    return;
  }
  render(
    html`<div class="zentriert landing-buehne">
      ${landingDeko()}
      <div class="landing-logo-buehne">
        <img class="landing-logo" src=${logoUrl} alt="MONKEY MONEY" />
      </div>
      <p class="landing-tagline">Die Quiz-Show für deinen Affenstall</p>
      ${caps.secureContext ? "" : html`<p class="landing-lan-badge">🔌 LAN-Modus (HTTP)</p>`}
      ${
        zeigeCodeEingabe
          ? html`
              <label for="code-eingabe">Raum-Code (4 Buchstaben):</label>
              <input
                id="code-eingabe"
                class="mono"
                style="text-transform:uppercase;font-size:1.6rem;width:9ch;text-align:center"
                maxlength="4"
                autocomplete="off"
                autocapitalize="characters"
                .value=${code}
                @input=${(e: Event) => {
                  // Großbuchstaben-Auto: intern IMMER uppercase führen.
                  code = (e.target as HTMLInputElement).value.toUpperCase();
                  codeHinweis = null;
                  zeichne();
                }}
                @keydown=${(e: KeyboardEvent) => e.key === "Enter" && joinMitCode()}
              />
              ${
                codeHinweis
                  ? html`<p style="color:var(--gold);font-size:0.9rem;margin:0">${codeHinweis}</p>`
                  : ""
              }
              <button
                class="primaer"
                style="width:min(320px,80vw)"
                ?disabled=${code.length !== 4}
                @click=${joinMitCode}
              >
                Rein da!
              </button>
              <button
                @click=${() => {
                  zeigeCodeEingabe = false;
                  zeichne();
                }}
              >
                Zurück
              </button>
            `
          : html`
              ${zuletztBanner()}
              <button
                class="primaer landing-hero"
                @click=${() => {
                  zeigeBildschirmWahl = true;
                  zeichne();
                }}
              >
                📺 Bildschirm eröffnen
                <small>${empfehlung("screen") || "iPad/TV wird die Bühne — Show ab!"}</small>
              </button>
              <div class="landing-sekundaer">
                <button
                  data-testid="schnell-beitreten"
                  @click=${() => {
                    merkeRolle("player");
                    schnellBeitreten();
                  }}
                >
                  ⚡ Schnell beitreten
                  <small>vollste offene Lobby</small>
                </button>
                <button
                  @click=${() => {
                    merkeRolle("player");
                    mitspielen();
                  }}
                >
                  🎮 Mitspielen
                  <small>${empfehlung("player") || "mit Raum-Code"}</small>
                </button>
              </div>
              ${lobbyBrowser()}
              <div class="landing-leise">
                <button
                  @click=${() => {
                    merkeRolle("gm");
                    window.location.href = "/gm";
                  }}
                >
                  🎩 Show-Master
                </button>
                <button @click=${() => oeffneMeta(zeichne)}>
                  🏆 Profile · Shop · Pass
                  <small>Bestenlisten · Training</small>
                </button>
                <button
                  @click=${() => {
                    zeigeCredits = true;
                    zeichne();
                  }}
                >
                  💛 Credits
                </button>
              </div>
            `
      }
      ${
        zeigeIosHinweis()
          ? html`<p class="muted" style="font-size:0.78rem;opacity:0.7;max-width:min(360px,86vw)">
              💡 Tipp: In Safari „Teilen → Zum Home-Bildschirm" — dann startet MONKEY MONEY wie eine
              App.
            </p>`
          : ""
      }
    </div>`,
    app,
  );
}

zeichne();
// LOBBY: Live-Liste abonnieren + „Zuletzt gespielt" prüfen (nach dem 1. Paint).
verbindeLobbyBrowser();
pruefeZuletzt();

// Profil-Wahl im Join-Flow (GAME-DESIGN §7.1 — OHNE Account-Zwang):
// „Willkommen zurück"-Kacheln zeigen NUR Profile DIESES Geräts (der Server
// filtert strikt nach Geräte-Token — fremde Profile sind auf geteilten
// Servern unsichtbar, P1-Fix). Auf vertrautem Gerät loggt ein Tipp DIREKT ein
// (kein Schein-PIN-Dialog); fremde Profile holt man bewusst über „Anderes
// Profil laden" mit Name + PIN — die PIN prüft der Server WIRKLICH.
// join.ts hängt NUR die zwei Hooks ein (renderProfilWahl + verbindeViaMeta).
import { html, type TemplateResult } from "lit-html";
import { metaFetch } from "../shared/meta-fetch";
import type { PlayerAppState } from "./main";

interface ProfilSummary {
  profileId: string;
  name: string;
  avatar: string;
  titel: string | null;
  level: number;
  atVerfuegbar: number;
  gesperrt: boolean;
  diesesGeraet: boolean;
}

interface MetaJoinState {
  geladen: boolean;
  profile: ProfilSummary[];
  aktiv: { profileId: string; pin?: string } | null;
  aktivName: string | null;
  hinweis: string | null; // z. B. „vertrauenswürdiges Gerät"
  fehler: string | null;
  speichern: boolean; // „Als Profil auf diesem Gerät speichern"
  neuPin: string;
  // „Anderes Profil laden" (Name + PIN, server-seitig geprüft)
  fremdOffen: boolean;
  fremdName: string;
  fremdPin: string;
}

const meta: MetaJoinState = {
  geladen: false,
  profile: [],
  aktiv: null,
  aktivName: null,
  hinweis: null,
  fehler: null,
  speichern: false,
  neuPin: "",
  fremdOffen: false,
  fremdName: "",
  fremdPin: "",
};

/** Aktives Profil im localStorage: überlebt Reload/Reconnect — sonst wüsste
 * meta-ende.ts nach einem Reload zur Siegerehrung nicht mehr, WER die
 * Match-Ausbeute (XP/Quests/Level) abholen darf (Eval-4-Befund). Die PIN
 * wird bewusst NIE persistiert — nur Id/Name/Avatar. */
const AKTIV_KEY = "mm:aktivProfil";

function persistiereAktiv(avatar?: string): void {
  try {
    if (meta.aktiv === null) {
      localStorage.removeItem(AKTIV_KEY);
      return;
    }
    localStorage.setItem(
      AKTIV_KEY,
      JSON.stringify({
        profileId: meta.aktiv.profileId,
        name: meta.aktivName,
        ...(avatar !== undefined ? { avatar } : {}),
      }),
    );
  } catch {
    /* egal */
  }
}

function restauriereAktiv(): { avatar?: string } {
  try {
    const roh = localStorage.getItem(AKTIV_KEY);
    if (roh === null) return {};
    const d = JSON.parse(roh) as { profileId?: string; name?: string; avatar?: string };
    if (typeof d.profileId !== "string") return {};
    meta.aktiv = { profileId: d.profileId };
    meta.aktivName = typeof d.name === "string" ? d.name : null;
    return typeof d.avatar === "string" ? { avatar: d.avatar } : {};
  } catch {
    return {};
  }
}

const restauriertesAvatar = restauriereAktiv();

/** Geräte-Token (localStorage): Wiedererkennung ohne Account (§7.1). */
export function deviceToken(): string {
  try {
    let token = localStorage.getItem("mm:device");
    if (!token) {
      token = `d_${crypto.randomUUID()}`;
      localStorage.setItem("mm:device", token);
    }
    return token;
  } catch {
    return "d_ohne-storage";
  }
}

/** Aktives Profil dieses Geräts — Basis fürs Match-Ende-Meta (meta-ende.ts). */
export function aktivesProfilId(): string | null {
  return meta.aktiv?.profileId ?? null;
}

/** Hello-Zusatzfelder fürs Profil-Join (main.ts spreizt das ins hello). */
export function aktivesProfilHello(): Record<string, string> {
  if (!meta.aktiv) return {};
  return {
    profileId: meta.aktiv.profileId,
    ...(meta.aktiv.pin ? { profilPin: meta.aktiv.pin } : {}),
    deviceToken: deviceToken(),
  };
}

function ladeProfile(zeichne: () => void): void {
  if (meta.geladen) return;
  meta.geladen = true;
  void metaFetch(`/api/meta/profile?device=${encodeURIComponent(deviceToken())}`)
    .then((r) => {
      const d = r.json as { profile?: ProfilSummary[] };
      meta.profile = d.profile ?? [];
      zeichne();
    })
    .catch(() => {});
}

function login(state: PlayerAppState, profil: ProfilSummary, zeichne: () => void): void {
  // Geräte-Profil: KEIN PIN-Dialog — der Geräte-Token ist der echte Zugriffs-
  // Beweis (der Server prüft ihn). Ein PIN-Dialog wäre hier Scheinprüfung.
  void metaFetch(`/api/meta/profile/${profil.profileId}/login`, {
    body: { deviceToken: deviceToken() },
  })
    .then((r) => {
      if (!r.ok) {
        meta.fehler = r.status === 403 ? "Zugriff verweigert." : "Profil-Fehler.";
        zeichne();
        return;
      }
      const d = r.json as { profil: { name: string; avatar: string; gesperrt: boolean } };
      meta.aktiv = { profileId: profil.profileId };
      meta.aktivName = d.profil.name;
      meta.hinweis = d.profil.gesperrt
        ? "🔐 Ohne PIN angemeldet — dieses Gerät ist für dein Profil als vertrauenswürdig gespeichert."
        : null;
      meta.fehler = null;
      state.name = d.profil.name;
      state.avatar = d.profil.avatar;
      persistiereAktiv(d.profil.avatar);
      zeichne();
    })
    .catch(() => {
      meta.fehler = "Keine Verbindung.";
      zeichne();
    });
}

/** „Anderes Profil laden": Name + PIN — der Server prüft die PIN wirklich. */
function ladeFremdesProfil(state: PlayerAppState, zeichne: () => void): void {
  const name = meta.fremdName.trim();
  if (name.length === 0) {
    meta.fehler = "Profil-Name fehlt.";
    zeichne();
    return;
  }
  void metaFetch("/api/meta/profile/laden", {
    body: {
      name,
      pin: meta.fremdPin.length > 0 ? meta.fremdPin : undefined,
      deviceToken: deviceToken(),
    },
  })
    .then((r) => {
      if (!r.ok) {
        const d = r.json as { error?: string };
        meta.fehler =
          d.error === "pin-falsch"
            ? "PIN falsch."
            : d.error === "name-mehrdeutig"
              ? "Mehrere Profile mit diesem Namen — bitte am Ursprungs-Gerät anmelden."
              : "Kein Profil mit diesem Namen gefunden.";
        zeichne();
        return;
      }
      const d = r.json as {
        profil: { profileId: string; name: string; avatar: string };
      };
      meta.aktiv = {
        profileId: d.profil.profileId,
        ...(meta.fremdPin.length > 0 ? { pin: meta.fremdPin } : {}),
      };
      meta.aktivName = d.profil.name;
      meta.hinweis = "✅ Profil geladen — dieses Gerät ist jetzt damit verknüpft.";
      meta.fehler = null;
      meta.fremdOffen = false;
      meta.fremdName = "";
      meta.fremdPin = "";
      state.name = d.profil.name;
      state.avatar = d.profil.avatar;
      persistiereAktiv(d.profil.avatar);
      zeichne();
    })
    .catch(() => {
      meta.fehler = "Keine Verbindung.";
      zeichne();
    });
}

/** Verbinden-Hook: legt vorher optional das Profil an („speichern"-Toggle). */
export function verbindeViaMeta(state: PlayerAppState, verbinde: () => void): void {
  if (meta.aktiv !== null || !meta.speichern) {
    verbinde();
    return;
  }
  void metaFetch("/api/meta/profile", {
    body: {
      name: state.name,
      avatar: state.avatar,
      pin: meta.neuPin.length >= 4 ? meta.neuPin : undefined,
      deviceToken: deviceToken(),
    },
  })
    .then((r) => {
      if (r.ok) {
        const d = r.json as { profil: { profileId: string } };
        meta.aktiv = {
          profileId: d.profil.profileId,
          pin: meta.neuPin.length >= 4 ? meta.neuPin : undefined,
        };
        meta.aktivName = state.name;
        persistiereAktiv(state.avatar);
      }
      verbinde(); // auch bei Profil-Fehler: als Gast rein (nie den Join blocken)
    })
    .catch(() => verbinde());
}

function kachel(state: PlayerAppState, p: ProfilSummary, zeichne: () => void): TemplateResult {
  const gewaehlt = meta.aktiv?.profileId === p.profileId;
  return html`<button
    class="profil-kachel ${gewaehlt ? "gewaehlt" : ""}"
    @click=${() => {
      if (gewaehlt) {
        meta.aktiv = null;
        meta.aktivName = null;
        meta.hinweis = null;
        persistiereAktiv();
        zeichne();
        return;
      }
      login(state, p, zeichne);
    }}
  >
    <span class="profil-name">${p.gesperrt ? "🔒 " : ""}${p.name}</span>
    <span class="profil-sub">Lv ${p.level} · ${p.atVerfuegbar.toLocaleString("de-DE")} AT</span>
    ${p.titel ? html`<span class="profil-sub">${p.titel}</span>` : ""}
  </button>`;
}

/** „Anderes Profil laden": bewusst geöffneter Flow — Name + PIN nötig. */
function anderesProfil(state: PlayerAppState, zeichne: () => void): TemplateResult {
  if (!meta.fremdOffen) {
    return html`<button
      data-testid="anderes-profil"
      style="min-height:44px;padding:6px 14px;font-size:0.85rem;opacity:0.85"
      @click=${() => {
        meta.fremdOffen = true;
        meta.fehler = null;
        zeichne();
      }}
    >
      👤 Anderes Profil laden (Name + PIN)
    </button>`;
  }
  return html`<div
    style="display:flex;gap:6px;align-items:center;flex-wrap:wrap"
    data-testid="anderes-profil-formular"
  >
    <input
      type="text"
      placeholder="Profil-Name"
      maxlength="24"
      style="width:14ch"
      .value=${meta.fremdName}
      @input=${(e: Event) => {
        meta.fremdName = (e.target as HTMLInputElement).value;
      }}
    />
    <input
      type="password"
      inputmode="numeric"
      maxlength="4"
      placeholder="PIN"
      style="width:7ch;text-align:center"
      .value=${meta.fremdPin}
      @input=${(e: Event) => {
        meta.fremdPin = (e.target as HTMLInputElement).value;
      }}
      @keydown=${(e: KeyboardEvent) => e.key === "Enter" && ladeFremdesProfil(state, zeichne)}
    />
    <button data-testid="anderes-profil-laden" @click=${() => ladeFremdesProfil(state, zeichne)}>
      Laden
    </button>
    <button
      style="min-height:44px;min-width:44px;padding:6px 12px;font-size:0.85rem"
      @click=${() => {
        meta.fremdOffen = false;
        meta.fehler = null;
        zeichne();
      }}
    >
      ✕
    </button>
  </div>`;
}

/** Join-Formular-Sektion: Profil wählen ODER Gast (Default) — §7.1.
 * „Willkommen zurück" zeigt NUR Geräte-Profile (Server filtert, P1-Fix). */
export function renderProfilWahl(state: PlayerAppState, zeichne: () => void): TemplateResult {
  ladeProfile(zeichne);
  // Restauriertes Profil (Reload): Name/Avatar ins Formular übernehmen, sonst
  // stünde „Profil gewählt" über einem leeren (= gesperrten) Namensfeld.
  if (meta.aktiv !== null && meta.aktivName !== null && state.name.length === 0) {
    state.name = meta.aktivName;
    if (restauriertesAvatar.avatar !== undefined) state.avatar = restauriertesAvatar.avatar;
  }
  const eigene = meta.profile;
  return html`
    ${
      eigene.length > 0 && meta.aktiv === null
        ? html`<div class="profil-reihe">
            <span class="muted" style="font-size:0.85rem">Willkommen zurück (dieses Gerät):</span>
            ${eigene.slice(0, 6).map((p) => kachel(state, p, zeichne))}
          </div>`
        : ""
    }
    ${
      meta.aktiv !== null
        ? html`<p style="margin:0;color:var(--gold)">
              👤 Profil <strong>${meta.aktivName}</strong> gewählt
              <button
                style="min-height:44px;padding:6px 12px;font-size:0.85rem;margin-left:8px"
                @click=${() => {
                  meta.aktiv = null;
                  meta.aktivName = null;
                  meta.hinweis = null;
                  persistiereAktiv();
                  zeichne();
                }}
              >
                ✕ doch als Gast
              </button>
            </p>
            ${
              meta.hinweis
                ? html`<p class="muted" style="margin:0;font-size:0.8rem" data-testid="pin-hinweis">
                    ${meta.hinweis}
                  </p>`
                : ""
            }`
        : html`<label style="display:flex;gap:8px;align-items:center;font-size:0.9rem">
              <input
                type="checkbox"
                .checked=${meta.speichern}
                @change=${(e: Event) => {
                  meta.speichern = (e.target as HTMLInputElement).checked;
                  zeichne();
                }}
              />
              ✨ Als Profil speichern (AT-Konto + Shop)
            </label>
            ${
              meta.speichern
                ? html`<input
                    type="password"
                    inputmode="numeric"
                    maxlength="4"
                    placeholder="PIN (optional, 4 Ziffern)"
                    style="width:24ch;text-align:center;font-size:0.95rem"
                    .value=${meta.neuPin}
                    @input=${(e: Event) => {
                      meta.neuPin = (e.target as HTMLInputElement).value;
                    }}
                  />`
                : ""
            }
            ${anderesProfil(state, zeichne)}`
    }
    ${meta.fehler ? html`<p style="color:var(--rot);margin:0">${meta.fehler}</p>` : ""}
  `;
}

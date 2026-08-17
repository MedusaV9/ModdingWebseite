// Meta-Screens auf der Landing (eigene Board-Seite §7.3, Shop §7.4,
// Profil-Karte §7.1, Trainingslager §6.2). Die Landing hängt NUR den
// Einstiegs-Knopf + die Delegation ein (metaAktiv/zeichneMeta) — der ganze
// Zustand lebt hier. Alles läuft über die Meta-HTTP-API, kein Socket nötig.
import { html, render, type TemplateResult } from "lit-html";
import {
  BOARD_TITEL,
  WILLKOMMEN_ITEM,
  WILLKOMMEN_START_AT,
  konfettiStilAus,
  levelFortschritt,
  levelFuerAt,
  type Boards,
  type ProfilKarte,
} from "../../shared/meta";
import { BB_DEKO } from "../../shared/minigames/bananen-basics.meta";
import { fuellePuppen, ladeAllePuppen, onPuppenGeladen } from "../shared/fx/affe";
import { createPartikel } from "../shared/fx/partikel";
import { schmueckePuppen, vorschauAvatar } from "../shared/meta-avatar";
import { metaFetch } from "../shared/meta-fetch";
import "./meta-landing.css";

type Tab = "boards" | "shop" | "pass" | "karte" | "training";

const SCHWIERIGKEIT_LABEL: Record<string, string> = {
  easy: "leicht",
  medium: "mittel",
  hard: "schwer",
  ultrahard: "ULTRAHARD",
};

function lesbaresKategorieLabel(slug: string): string {
  return slug
    .replaceAll("_", " ")
    .replaceAll("-", " ")
    .replace(/\b\w/g, (zeichen) => zeichen.toUpperCase());
}

interface ProfilSummary {
  profileId: string;
  name: string;
  avatar: string;
  level: number;
  atVerfuegbar: number;
  gesperrt: boolean;
  diesesGeraet: boolean;
}

interface ProfilVoll {
  profileId: string;
  name: string;
  avatarBasis: string;
  avatar: string;
  at: { gesamt: number; verfuegbar: number };
  besitz: string[];
  ausgeruestet: Record<string, string>;
  gesperrt: boolean;
}

interface ShopItemWire {
  id: string;
  name: string;
  emoji: string;
  typ: string;
  slot: string;
  preis: number;
  beschreibung: string;
  seltenheit: string;
  inAbenden: string;
  /** Level-Gate (§7.5): kaufbar erst ab diesem Profil-Level. */
  minLevel?: number;
  /** Gesetzt = NICHT kaufbar (Pass-Saison bzw. Willkommens-Geschenk). */
  passExklusiv?: string;
  /** Wird am Affen/Podium gerendert ⇒ Live-Vorschau im Shop (Welle 3). */
  visuell?: boolean;
}

/** Wire von GET /api/meta/profile/:id/board-fortschritt (server/meta/boards.ts). */
type BoardFortschrittWire = Record<keyof Boards, { ist: number; schwelle: number }>;

/** Wire-Format von GET /api/meta/profile/:id/pass (server/meta/index.ts). */
interface PassWire {
  saison: { id: string; name: string; endetTs: number; stufen: number };
  xp: number;
  stufe: number;
  atBonus: number;
  stufeAbXp: number;
  naechsteAbXp: number | null;
  belohnungen: {
    stufe: number;
    art: "at" | "item";
    at?: number;
    item?: {
      id: string;
      name: string;
      emoji: string;
      typ: string;
      slot: string;
      beschreibung: string;
    };
    erreicht: boolean;
  }[];
  tagKey: string;
  quests: {
    questId: string;
    art: "daily" | "monat";
    text: string;
    ziel: number;
    fortschritt: number;
    fertig: boolean;
    xp: number;
  }[];
  archiv: { saisonId: string; name: string; stufe: number; xp: number; verdient: string[] }[];
}

interface TrainingsFrage {
  questionId: string;
  text: string;
  options: string[];
  tippsGesamt?: number;
  kategorie: string;
  schwierigkeit: string;
  bisherFalsch: number;
}

interface TrainingsStats {
  beantwortet: number;
  richtig: number;
  quote: number | null;
  serie: number;
  besteSerie: number;
  schwaechen: { kategorie: string; quote: number; n: number }[];
}

interface MetaState {
  aktiv: boolean;
  tab: Tab;
  boards: Boards | null;
  fortschritt: BoardFortschrittWire | null;
  fortschrittFuer: string | null; // profileId, für den s.fortschritt geladen wurde
  shop: ShopItemWire[];
  // Shop-Navigation (UX-Fix: 51er-Wand → Chips/Filter/Sortierung)
  shopTyp: string; // "" = alle Typen
  shopBesitz: "" | "kaufbar" | "besitz";
  shopSort: "" | "auf" | "ab";
  /** Kauf-Moment (Eval 4): itemId des letzten Kaufs — Konfetti + Anlegen-CTA. */
  kaufMoment: string | null;
  /** Live-Vorschau (Welle 3): Item probeweise am eigenen Affen zeigen. */
  vorschauItem: string | null;
  profile: ProfilSummary[];
  gewaehlt: ProfilVoll | null;
  hinweis: string | null; // z. B. „vertrauenswürdiges Gerät"
  // „Anderes Profil laden" (Name + PIN, server-seitig geprüft)
  fremdOffen: boolean;
  fremdName: string;
  fremdPin: string;
  karte: ProfilKarte | null;
  pass: PassWire | null;
  passFuer: string | null; // profileId, für den s.pass geladen wurde
  fehler: string | null;
  // Training
  kategorien: { slug: string; oberkategorie: string; fragen: number }[];
  tKategorie: string;
  tSchwierigkeit: string;
  tFrage: TrainingsFrage | null;
  tWeg: number[]; // per Tipp ausgeblendete Optionen
  tTipps: string[]; // stufenweise enthüllte Autoren-Tipps (1→2→3)
  tAufloesung: { korrekt: boolean; antwort: number; erklaerung: string } | null;
  tGewaehlt: number | null;
  tStart: number;
  tStats: TrainingsStats | null;
  /** Trainings-SESSION (Welle 4): lokale Zählung nur für die Fazit-Karte —
   * die Server-Stats (tStats) laufen profilweit weiter. */
  tSession: { beantwortet: number; richtig: number; kategorien: Record<string, ZellZaehler> };
  /** Session-Fazit-Karte sichtbar („12 geübt · 75 % · stärkste Kategorie X"). */
  tFazit: boolean;
}

interface ZellZaehler {
  n: number;
  richtig: number;
}

const s: MetaState = {
  aktiv: false,
  tab: "boards",
  boards: null,
  fortschritt: null,
  fortschrittFuer: null,
  shop: [],
  shopTyp: "",
  shopBesitz: "",
  shopSort: "",
  kaufMoment: null,
  vorschauItem: null,
  profile: [],
  gewaehlt: null,
  hinweis: null,
  fremdOffen: false,
  fremdName: "",
  fremdPin: "",
  karte: null,
  pass: null,
  passFuer: null,
  fehler: null,
  kategorien: [],
  tKategorie: "",
  tSchwierigkeit: "",
  tFrage: null,
  tWeg: [],
  tTipps: [],
  tAufloesung: null,
  tGewaehlt: null,
  tStart: 0,
  tStats: null,
  tSession: { beantwortet: 0, richtig: 0, kategorien: {} },
  tFazit: false,
};

let neuZeichnen: () => void = () => {};

function deviceToken(): string {
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

function trainingsKey(): string {
  return s.gewaehlt?.profileId ?? deviceToken();
}

async function api<T>(pfad: string, body?: unknown): Promise<T | null> {
  try {
    // metaFetch: HTTP am AMP-/PC-Server, Wire-Event im iPad-Standalone (W4).
    const r = await metaFetch(pfad, { body });
    if (!r.ok) {
      const fehler = r.json as { error?: string };
      s.fehler = fehlerText(fehler.error ?? `Fehler ${r.status}`);
      neuZeichnen();
      return null;
    }
    s.fehler = null;
    return r.json as T;
  } catch {
    s.fehler = "Keine Verbindung zum Server.";
    neuZeichnen();
    return null;
  }
}

function fehlerText(code: string): string {
  const texte: Record<string, string> = {
    "zu-wenig-at": "Zu wenig AT — erst ein paar Matches gewinnen!",
    "schon-gekauft": "Hast du schon!",
    "pin-falsch": "PIN falsch.",
    "keine-fragen": "Keine Fragen für diese Auswahl.",
    "level-zu-niedrig": "Noch gesperrt — dafür brauchst du ein höheres Level!",
    "nur-im-pass": "Nicht kaufbar — gibt's nur geschenkt (Pass bzw. Willkommens-Paket).",
    "profil-unbekannt": "Kein Profil mit diesem Namen gefunden.",
    "name-mehrdeutig": "Mehrere Profile mit diesem Namen — bitte am Ursprungs-Gerät anmelden.",
  };
  return texte[code] ?? code;
}

// ---------- Count-up-Ticker (Welle 4): Handy-Feedback-Muster wiederverwendet ----------
// client/player/handy-fx.ts ist Player-only (Import-Grenze TECH-SPEC §2), darum
// hier dieselbe Mechanik lokal: lit bindet NUR Attribute ([data-tick-ziel]),
// der Textinhalt gehört dieser Funktion — kein lit-Text-Node wird zerstört.

const TICK_DAUER_MS = 600;

/** Zwischenwert eines Count-ups bei Fortschritt 0..1 (cubic ease-out). */
function tickWert(fortschritt: number, von: number, ziel: number): number {
  const t = Math.min(1, Math.max(0, fortschritt));
  const eased = 1 - (1 - t) ** 3;
  return Math.round(von + (ziel - von) * eased);
}

/** Alle [data-tick-ziel]-Elemente zum Ziel hochticken (+ kurzer Gold-Flash):
 * frisch gerenderte Elemente zählen von 0, bekannte vom zuletzt gezeigten
 * Wert. data-tick-suffix hängt z. B. " %" an. */
function fuelleTicker(root: ParentNode): void {
  for (const el of root.querySelectorAll<HTMLElement>("[data-tick-ziel]")) {
    const ziel = Number(el.dataset.tickZiel ?? "0");
    const suffix = el.dataset.tickSuffix ?? "";
    const gezeigt = el.dataset.tickStand;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      el.dataset.tickStand = String(ziel);
      el.textContent = `${ziel}${suffix}`;
      continue;
    }
    const von = gezeigt === undefined ? 0 : Number(gezeigt);
    if (gezeigt !== undefined && von === ziel) {
      if (el.textContent === "") el.textContent = `${ziel}${suffix}`;
      continue;
    }
    el.dataset.tickStand = String(ziel);
    el.classList.remove("tickt");
    void el.offsetWidth; // Flash-Animation neu starten
    el.classList.add("tickt");
    const start = performance.now();
    const tick = (jetzt: number): void => {
      if (el.dataset.tickStand !== String(ziel) || !el.isConnected) return;
      const t = (jetzt - start) / TICK_DAUER_MS;
      el.textContent = `${tickWert(t, von, ziel)}${suffix}`;
      if (t < 1) requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  }
}

/** Preis-Stufen-Rahmen der Shop-Vitrine (Welle 4): <1k Bronze · <4k Silber ·
 * <8k Gold · drüber Legendär-Glow; Geschenke (Pass/Willkommen) eigener Look. */
function preisRahmen(item: ShopItemWire): string {
  if (item.passExklusiv !== undefined) return "geschenk";
  if (item.preis < 1_000) return "bronze";
  if (item.preis < 4_000) return "silber";
  if (item.preis < 8_000) return "gold";
  return "legendaer";
}

// ---------- Daten-Lader ----------

function ladeBoards(): void {
  void api<{ boards: Boards }>("/api/meta/boards").then((d) => {
    if (d) {
      s.boards = d.boards;
      neuZeichnen();
    }
  });
}

function ladeShopUndProfile(): void {
  if (s.shop.length === 0) {
    void api<{ items: ShopItemWire[] }>("/api/meta/shop").then((d) => {
      if (d) {
        s.shop = d.items;
        neuZeichnen();
      }
    });
  }
  void api<{ profile: ProfilSummary[] }>(
    `/api/meta/profile?device=${encodeURIComponent(deviceToken())}`,
  ).then((d) => {
    if (d) {
      s.profile = d.profile;
      neuZeichnen();
    }
  });
}

let karteTimer: number | null = null;

function ladeKarte(): void {
  if (!s.gewaehlt) return;
  const fuer = s.gewaehlt.profileId;
  void api<{ karte: ProfilKarte }>(`/api/meta/profile/${fuer}/karte`).then((d) => {
    if (d) {
      s.karte = d.karte;
      // Analytics-Ruhefenster (~90 s): solange die letzte Match-Buchung noch
      // nicht eingerechnet ist, alle 15 s nachladen — Karte heilt sich selbst.
      if (karteTimer !== null) window.clearTimeout(karteTimer);
      if (d.karte.statsAusstehend && s.aktiv && s.tab === "karte") {
        karteTimer = window.setTimeout(() => {
          karteTimer = null;
          if (s.aktiv && s.tab === "karte" && s.gewaehlt?.profileId === fuer) ladeKarte();
        }, 15_000);
      }
      neuZeichnen();
    }
  });
}

function ladeFortschritt(): void {
  if (!s.gewaehlt) return;
  const fuer = s.gewaehlt.profileId;
  void api<{ fortschritt: BoardFortschrittWire }>(
    `/api/meta/profile/${fuer}/board-fortschritt`,
  ).then((d) => {
    if (d) {
      s.fortschritt = d.fortschritt;
      s.fortschrittFuer = fuer;
      neuZeichnen();
    }
  });
}

function ladePass(): void {
  if (!s.gewaehlt) return;
  const fuer = s.gewaehlt.profileId;
  void api<{ pass: PassWire }>(`/api/meta/profile/${fuer}/pass`).then((d) => {
    if (d) {
      s.pass = d.pass;
      s.passFuer = fuer;
      neuZeichnen();
    }
  });
}

function ladeKategorien(): void {
  if (s.kategorien.length > 0) return;
  void api<{ kategorien: MetaState["kategorien"] }>("/api/meta/uebung/kategorien").then((d) => {
    if (d) {
      s.kategorien = d.kategorien;
      neuZeichnen();
    }
  });
}

function ladeTrainingsStats(): void {
  void api<{ stats: TrainingsStats }>(
    `/api/meta/uebung/stats?key=${encodeURIComponent(trainingsKey())}`,
  ).then((d) => {
    if (d) {
      s.tStats = d.stats;
      neuZeichnen();
    }
  });
}

function nachLogin(profil: ProfilVoll, hinweis: string | null): void {
  s.gewaehlt = profil;
  s.hinweis = hinweis;
  s.fremdOffen = false;
  s.fremdName = "";
  s.fremdPin = "";
  if (s.tab === "karte") ladeKarte();
  if (s.tab === "pass") ladePass();
  if (s.tab === "boards") ladeFortschritt();
  neuZeichnen();
}

function profilLogin(profileId: string): void {
  // Geräte-Profil ⇒ Direkt-Login OHNE PIN-Dialog: der Geräte-Token ist der
  // echte Zugriffs-Beweis (Server-seitig geprüft) — kein Schein-Schloss.
  void api<{ profil: ProfilVoll }>(`/api/meta/profile/${profileId}/login`, {
    deviceToken: deviceToken(),
  }).then((d) => {
    if (d) {
      nachLogin(
        d.profil,
        d.profil.gesperrt
          ? "🔐 Ohne PIN angemeldet — dieses Gerät ist als vertrauenswürdig gespeichert."
          : null,
      );
    }
  });
}

/** „Anderes Profil laden": Name + PIN — der Server prüft die PIN wirklich. */
function ladeFremdesProfil(): void {
  const name = s.fremdName.trim();
  if (name.length === 0) {
    s.fehler = "Profil-Name fehlt.";
    neuZeichnen();
    return;
  }
  void api<{ profil: ProfilVoll }>("/api/meta/profile/laden", {
    name,
    pin: s.fremdPin.length > 0 ? s.fremdPin : undefined,
    deviceToken: deviceToken(),
  }).then((d) => {
    if (d) {
      nachLogin(d.profil, "✅ Profil geladen — dieses Gerät ist jetzt damit verknüpft.");
      ladeShopUndProfile();
    }
  });
}

// ---------- Öffentliche Hooks (landing/main.ts) ----------

export function metaAktiv(): boolean {
  return s.aktiv;
}

export function oeffneMeta(zeichneLanding: () => void): void {
  s.aktiv = true;
  neuZeichnen = zeichneLanding;
  ladeAllePuppen();
  onPuppenGeladen(() => neuZeichnen());
  ladeBoards();
  ladeShopUndProfile();
  zeichneLanding();
}

/** Landing delegiert hierher, solange metaAktiv() — rendert in den App-Root. */
export function zeichneMeta(app: HTMLElement, zeichneLanding: () => void): void {
  neuZeichnen = () => zeichneMeta(app, zeichneLanding);
  render(metaScreen(zeichneLanding), app);
  fuellePuppen(app);
  schmueckePuppen(app, true);
  fuelleTicker(app);
}

// ---------- Screens ----------

/** Titel-Hierarchie (Welle 4): EIN H2-Kopf pro Tab, Karten bleiben bei H3. */
const TAB_KOEPFE: Record<Tab, { titel: string; unter: string }> = {
  boards: { titel: "🏆 Bestenlisten", unter: "Vier Boards — wer regiert den Affenstall?" },
  shop: { titel: "🛍 Shop-Vitrine", unter: "AT gibt's nur fürs Spielen — kein Echtgeld" },
  pass: { titel: "🍌 Bananen-Pass", unter: "Deine Saison-Reise: Stufen, Geschenke, Aufgaben" },
  karte: { titel: "👤 Affen-Ausweis", unter: "Dein Profil als Sticker-Ausweis" },
  training: { titel: "🏋️ Trainingslager", unter: "Endlos üben — mit Tipps, ohne AT-Wertung" },
};

function metaScreen(zeichneLanding: () => void): TemplateResult {
  const tabs: [Tab, string][] = [
    ["boards", "🏆 Bestenlisten"],
    ["shop", "🛍 Shop"],
    ["pass", "🍌 Pass & Aufgaben"],
    ["karte", "👤 Profil-Karte"],
    ["training", "🏋️ Training"],
  ];
  const kopf = TAB_KOEPFE[s.tab];
  return html`<div class="meta-wrap">
    <div class="meta-tabs">
      <button
        class="zurueck"
        title="Zurück zur Startseite"
        @click=${() => {
          s.aktiv = false;
          zeichneLanding();
        }}
      >
        ← Zurück
      </button>
      ${tabs.map(
        ([tab, label]) =>
          html`<button
            class=${s.tab === tab ? "aktiv" : ""}
            aria-pressed=${s.tab === tab ? "true" : "false"}
            @click=${() => {
              s.tab = tab;
              if (tab === "boards") {
                ladeBoards();
                ladeShopUndProfile();
                if (s.gewaehlt) ladeFortschritt();
              }
              if (tab === "shop") ladeShopUndProfile();
              if (tab === "pass") {
                ladeShopUndProfile();
                ladePass();
              }
              if (tab === "karte") ladeKarte();
              if (tab === "training") {
                ladeKategorien();
                ladeTrainingsStats();
              }
              neuZeichnen();
            }}
          >
            ${label}
          </button>`,
      )}
    </div>
    <div class="meta-kopf">
      <h2>${kopf.titel}</h2>
      <p class="muted">${kopf.unter}</p>
    </div>
    ${
      s.fehler
        ? html`<div class="meta-fehler" role="alert">
            <span class="fehler-emoji">🙈</span>
            <span>${s.fehler}</span>
          </div>`
        : ""
    }
    <div class="meta-inhalt">
      ${s.tab === "boards" ? boardsScreen() : ""} ${s.tab === "shop" ? shopScreen() : ""}
      ${s.tab === "pass" ? passScreen() : ""} ${s.tab === "karte" ? karteScreen() : ""}
      ${s.tab === "training" ? trainingScreen() : ""}
    </div>
  </div>`;
}

/** Persönlicher Fortschritt zur Board-Schwelle („Noch 2 bis zur Wertung"). */
function boardFortschrittZeile(key: keyof Boards): TemplateResult {
  const p = s.gewaehlt;
  if (!p || !s.fortschritt || s.fortschrittFuer !== p.profileId) return html``;
  const f = s.fortschritt[key];
  const einheit: Record<keyof Boards, string> = {
    moneyBoss: "AT aus Matches",
    kategorieMeister: "Antworten in deiner fleißigsten Kategorie",
    blitzBuzzer: "gewertete Antworten",
    comebackKoenig: "Aufhol-Matches (vorm Finale hinten gelegen)",
  };
  if (f.ist >= f.schwelle) {
    return html`<p class="board-fortschritt geschafft" data-testid="board-fortschritt">
      ✅ ${p.name}: Schwelle erreicht — du wirst gewertet.
    </p>`;
  }
  const fehlt = f.schwelle - f.ist;
  return html`<p class="board-fortschritt" data-testid="board-fortschritt">
    🐾 ${p.name}: ${f.ist}/${f.schwelle} ${einheit[key]} — noch ${fehlt.toLocaleString("de-DE")} bis
    zur Wertung.
  </p>`;
}

/** Podest-Optik (Welle 4): Top 3 als Treppchen (2-1-3), Medaillen + Sockel. */
function boardPodest(eintraege: Boards[keyof Boards]): TemplateResult {
  const medaillen = ["🥇", "🥈", "🥉"];
  const reihenfolge = [1, 0, 2].filter((i) => i < eintraege.length);
  return html`<div class="board-podest" data-testid="board-podest">
    ${reihenfolge.map((i) => {
      const e = eintraege[i];
      return html`<div class="podest-platz platz-${i + 1}">
        <span class="podest-medaille">${medaillen[i]}</span>
        <span class="podest-name">${e.name}</span>
        ${e.extra ? html`<span class="podest-extra">${e.extra}</span>` : ""}
        <span class="podest-wert">${e.anzeige}</span>
        <div class="podest-sockel">${i + 1}</div>
      </div>`;
    })}
  </div>`;
}

function boardsScreen(): TemplateResult {
  if (!s.boards) return html`<p class="muted">Lade Bestenlisten …</p>`;
  const schwellen: Record<keyof Boards, string> = {
    moneyBoss: "AT gesamt (alle Zeit)",
    kategorieMeister: "beste Quote je Kategorie (ab 20 Antworten)",
    blitzBuzzer: "MEDIAN-Antwortzeit (ab 30 Antworten)",
    comebackKoenig: "Win-Rate ohne Führung vorm Finale (ab 5 Matches)",
  };
  return html`${profilWahlKarte("Dein Fortschritt zur Wertung — Profil wählen")}
    <div class="board-grid">
      ${(Object.keys(BOARD_TITEL) as (keyof Boards)[]).map((key) => {
        const eintraege = s.boards![key];
        return html`<div class="karte board-karte">
          <h3>${BOARD_TITEL[key]}</h3>
          <p class="muted" style="margin:0 0 6px;font-size:0.78rem">${schwellen[key]}</p>
          ${
            eintraege.length === 0
              ? html`<div class="leer-zustand">
                  <span class="leer-emoji">🐒💤</span>
                  <p>Noch gähnend leer — spielt Matches mit Profil, dann klettert ihr hier hoch!</p>
                </div>`
              : html`${boardPodest(eintraege)}
                ${eintraege.slice(3).map(
                  (e, i) =>
                    html`<div class="board-zeile">
                      <span class="platz">${i + 4}</span>
                      <span>${e.name}</span>
                      ${e.extra ? html`<span class="muted">(${e.extra})</span>` : ""}
                      <span class="wert">${e.anzeige}</span>
                    </div>`,
                )}`
          }
          ${boardFortschrittZeile(key)}
        </div>`;
      })}
    </div>`;
}

// ---------- Shop ----------

function profilWahlKarte(titel = "Profil wählen"): TemplateResult {
  return html`<div class="karte">
    <h3 style="margin:0 0 6px">${titel}</h3>
    ${
      s.profile.length === 0
        ? html`<p class="muted">
            Noch kein Profil auf diesem Gerät — beim Mitspielen „✨ Als Profil speichern“ antippen.
          </p>`
        : ""
    }
    <div style="display:flex;gap:8px;flex-wrap:wrap;align-items:center">
      ${s.profile.map(
        (p) => html`
          <button
            class=${s.gewaehlt?.profileId === p.profileId ? "primaer" : ""}
            @click=${() => profilLogin(p.profileId)}
          >
            ${p.gesperrt ? "🔒 " : ""}${p.name}
            <small style="display:block;font-weight:400">
              Lv ${p.level} · ${p.atVerfuegbar.toLocaleString("de-DE")} AT
            </small>
          </button>
        `,
      )}
      ${
        s.fremdOffen
          ? html`<span
              style="display:flex;gap:6px;align-items:center;flex-wrap:wrap"
              data-testid="anderes-profil-formular"
            >
              <input
                type="text"
                placeholder="Profil-Name"
                maxlength="24"
                style="width:14ch"
                .value=${s.fremdName}
                @input=${(e: Event) => {
                  s.fremdName = (e.target as HTMLInputElement).value;
                }}
              />
              <input
                type="password"
                inputmode="numeric"
                maxlength="4"
                placeholder="PIN"
                style="width:7ch;text-align:center"
                .value=${s.fremdPin}
                @input=${(e: Event) => {
                  s.fremdPin = (e.target as HTMLInputElement).value;
                }}
                @keydown=${(e: KeyboardEvent) => e.key === "Enter" && ladeFremdesProfil()}
              />
              <button data-testid="anderes-profil-laden" @click=${() => ladeFremdesProfil()}>
                Laden
              </button>
              <button
                style="min-height:44px;min-width:44px;padding:6px 12px;font-size:0.85rem"
                @click=${() => {
                  s.fremdOffen = false;
                  s.fehler = null;
                  neuZeichnen();
                }}
              >
                ✕
              </button>
            </span>`
          : html`<button
              data-testid="anderes-profil"
              style="min-height:44px;padding:6px 14px;font-size:0.85rem;opacity:0.85"
              @click=${() => {
                s.fremdOffen = true;
                s.fehler = null;
                neuZeichnen();
              }}
            >
              👤 Anderes Profil laden (Name + PIN)
            </button>`
      }
    </div>
    ${
      s.hinweis
        ? html`<p class="muted" style="margin:6px 0 0;font-size:0.8rem" data-testid="pin-hinweis">
            ${s.hinweis}
          </p>`
        : ""
    }
  </div>`;
}

// Typ-Chips (UX-Fix: 51er-Wand gliedern) — Reihenfolge = Anzeige-Reihenfolge.
const SHOP_TYP_CHIPS: [string, string][] = [
  ["sound", "🔊 Sounds"],
  ["accessoire", "🎩 Accessoires"],
  ["titel", "📛 Titel"],
  ["banner", "🖼 Banner"],
  ["namestil", "✍️ Namensstile"],
  ["konfetti", "🎊 Konfetti"],
  ["avatar", "🐒 Avatare"],
  ["podium", "🏛 Podium"],
  ["einlauf", "💥 Einlauf"],
  ["sonstiges", "🎲 Sonstiges"],
];

function shopChipTyp(item: ShopItemWire): string {
  return SHOP_TYP_CHIPS.some(([typ]) => typ === item.typ) ? item.typ : "sonstiges";
}

/** Sichtbare Shop-Basis: Geschenk-Items (unkaufbar) nur zeigen, wenn besessen. */
function sichtbarerShop(): ShopItemWire[] {
  return s.shop.filter(
    (i) => i.passExklusiv === undefined || (s.gewaehlt?.besitz.includes(i.id) ?? false),
  );
}

// ---------- Belohnungs-Momente (Eval 4) ----------

/** Mini-Konfetti beim Kauf: eigener Wegwerf-Canvas über der Seite, damit der
 * lit-Baum unberührt bleibt (Muster: meta-ende.ts am Handy). */
function kaufKonfetti(): void {
  const canvas = document.createElement("canvas");
  canvas.width = window.innerWidth;
  canvas.height = window.innerHeight;
  canvas.style.cssText = "position:fixed;inset:0;z-index:80;pointer-events:none";
  document.body.appendChild(canvas);
  const partikel = createPartikel(canvas);
  const stil = konfettiStilAus(s.gewaehlt?.avatar ?? "");
  partikel.konfetti({ stil, anzahl: 36 });
  window.setTimeout(() => partikel.konfetti({ stil, anzahl: 24 }), 350);
  window.setTimeout(() => {
    partikel.leeren();
    canvas.remove();
  }, 2600);
}

/** Einmalige Willkommens-Paket-Karte: der Server verschenkt 300 AT + Titel
 * still beim ersten Profil — OHNE Moment merkt das niemand (Eval 4). Einmal
 * pro Profil, „Danke"-Tap merkt sich das Gerät im localStorage. */
const WILLKOMMEN_GEZEIGT_KEY = "mm:willkommenGezeigt";

function willkommenSchonGezeigt(profileId: string): boolean {
  try {
    return localStorage.getItem(`${WILLKOMMEN_GEZEIGT_KEY}:${profileId}`) !== null;
  } catch {
    return true;
  }
}

function willkommensKarte(p: ProfilVoll): TemplateResult {
  if (!p.besitz.includes(WILLKOMMEN_ITEM.id) || willkommenSchonGezeigt(p.profileId)) return html``;
  return html`<div
    class="karte"
    data-testid="willkommens-karte"
    style="border:2px solid var(--gold);display:flex;gap:10px;align-items:center;flex-wrap:wrap"
  >
    <span style="font-size:1.8rem">🎁</span>
    <div style="flex:1;min-width:200px">
      <strong>Willkommens-Paket!</strong>
      <p class="muted" style="margin:2px 0 0;font-size:0.85rem">
        ${WILLKOMMEN_START_AT} AT + Titel „Frischer Affe" geschenkt — fürs erste Profil auf diesem
        Gerät. Viel Spaß im Shop!
      </p>
    </div>
    <button
      @click=${() => {
        try {
          localStorage.setItem(`${WILLKOMMEN_GEZEIGT_KEY}:${p.profileId}`, "1");
        } catch {
          /* egal */
        }
        neuZeichnen();
      }}
    >
      Danke! 🐵
    </button>
  </div>`;
}

/** „Weg zum nächsten Level" (Eval 4): Fortschritts-Balken für Karte + Shop. */
function levelBalken(atGesamt: number): TemplateResult {
  const f = levelFortschritt(atGesamt);
  const fehlt = f.naechstesAb - Math.max(0, atGesamt);
  return html`<div data-testid="level-fortschritt" style="margin-top:6px;min-width:200px">
    <div class="muted" style="display:flex;justify-content:space-between;font-size:0.75rem">
      <span>Lv ${f.level}</span>
      <span>noch ${fehlt.toLocaleString("de-DE")} AT bis Lv ${f.level + 1}</span>
    </div>
    <div style="height:8px;border-radius:4px;background:rgb(255 246 227 / 14%);overflow:hidden">
      <div style="height:100%;width:${Math.round(f.anteil * 100)}%;background:var(--gold)"></div>
    </div>
  </div>`;
}

function istKaufbar(item: ShopItemWire, p: ProfilVoll): boolean {
  if (item.passExklusiv !== undefined) return false;
  if (p.besitz.includes(item.id) && item.typ !== "badge") return false;
  if (item.minLevel !== undefined && levelFuerAt(p.at.gesamt) < item.minLevel) return false;
  return p.at.verfuegbar >= item.preis;
}

function gefilterterShop(): ShopItemWire[] {
  const p = s.gewaehlt;
  let liste = sichtbarerShop();
  if (s.shopTyp !== "") liste = liste.filter((i) => shopChipTyp(i) === s.shopTyp);
  if (p && s.shopBesitz === "kaufbar") liste = liste.filter((i) => istKaufbar(i, p));
  if (p && s.shopBesitz === "besitz") liste = liste.filter((i) => p.besitz.includes(i.id));
  if (s.shopSort !== "") {
    liste = [...liste].sort((a, b) =>
      s.shopSort === "auf" ? a.preis - b.preis : b.preis - a.preis,
    );
  }
  return liste;
}

function shopChipLeiste(): TemplateResult {
  const basis = sichtbarerShop();
  const p = s.gewaehlt;
  const zaehler = new Map<string, number>();
  for (const i of basis) zaehler.set(shopChipTyp(i), (zaehler.get(shopChipTyp(i)) ?? 0) + 1);
  return html`<div class="shop-chips" data-testid="shop-chips">
    <div class="chip-zeile">
      <button
        class="chip ${s.shopTyp === "" ? "aktiv" : ""}"
        @click=${() => {
          s.shopTyp = "";
          neuZeichnen();
        }}
      >
        Alle (${basis.length})
      </button>
      ${SHOP_TYP_CHIPS.filter(([typ]) => (zaehler.get(typ) ?? 0) > 0).map(
        ([typ, label]) =>
          html`<button
            class="chip ${s.shopTyp === typ ? "aktiv" : ""}"
            @click=${() => {
              s.shopTyp = s.shopTyp === typ ? "" : typ;
              neuZeichnen();
            }}
          >
            ${label} (${zaehler.get(typ)})
          </button>`,
      )}
    </div>
    <div class="chip-zeile">
      <button
        class="chip ${s.shopBesitz === "kaufbar" ? "aktiv" : ""}"
        ?disabled=${!p}
        title=${p ? "Nur Items, die du dir JETZT leisten kannst" : "Erst Profil wählen"}
        @click=${() => {
          s.shopBesitz = s.shopBesitz === "kaufbar" ? "" : "kaufbar";
          neuZeichnen();
        }}
      >
        💰 Kaufbar
      </button>
      <button
        class="chip ${s.shopBesitz === "besitz" ? "aktiv" : ""}"
        ?disabled=${!p}
        title=${p ? "Nur Items in deinem Besitz" : "Erst Profil wählen"}
        @click=${() => {
          s.shopBesitz = s.shopBesitz === "besitz" ? "" : "besitz";
          neuZeichnen();
        }}
      >
        🎒 Besitz
      </button>
      <button
        class="chip ${s.shopSort !== "" ? "aktiv" : ""}"
        @click=${() => {
          s.shopSort = s.shopSort === "" ? "auf" : s.shopSort === "auf" ? "ab" : "";
          neuZeichnen();
        }}
      >
        ${s.shopSort === "auf" ? "Preis ↑" : s.shopSort === "ab" ? "Preis ↓" : "Preis sortieren"}
      </button>
    </div>
  </div>`;
}

/** Null-AT-Einstieg (UX-Fix): Verdien-Hinweis + Fortschritt zum billigsten Item. */
function verdienHinweis(p: ProfilVoll): TemplateResult {
  const kaufbarePreise = s.shop
    .filter((i) => i.passExklusiv === undefined && !p.besitz.includes(i.id))
    .map((i) => i.preis);
  const billigst = kaufbarePreise.length > 0 ? Math.min(...kaufbarePreise) : 0;
  if (billigst === 0 || p.at.verfuegbar >= billigst) return html``;
  return html`<p
    class="muted"
    style="margin:4px 0 0;font-size:0.82rem;color:var(--gold);opacity:1"
    data-testid="verdien-hinweis"
  >
    💡 Verdiene AT durch Matches: Endstand ÷ 10 (Sieger ×1,5) + Pass-Boni. Bis zum günstigsten Item
    (${billigst.toLocaleString("de-DE")} AT) fehlen dir noch
    ${(billigst - p.at.verfuegbar).toLocaleString("de-DE")} AT.
  </p>`;
}

function shopScreen(): TemplateResult {
  const p = s.gewaehlt;
  const liste = gefilterterShop();
  // Live-Vorschau (Welle 3): gewähltes Item probeweise am eigenen Affen —
  // gleicher Renderer wie am Podium (schmueckePuppen), Slot-exklusiv ersetzt.
  const vorschauWahl = s.vorschauItem !== null ? s.shop.find((i) => i.id === s.vorschauItem) : null;
  const puppeAvatar = p ? vorschauAvatar(p.avatar, vorschauWahl?.id ?? null) : "";
  return html`
    ${profilWahlKarte("Wer shoppt?")} ${p ? willkommensKarte(p) : ""}
    ${
      p
        ? html`<div class="karte shop-vorschau">
            <div
              class="puppe ${vorschauWahl?.typ === "einlauf" ? "mm-einlauf-demo" : ""}"
              data-testid="shop-puppe"
              data-avatar=${puppeAvatar}
            ></div>
            <div>
              <h3 style="margin:0">${p.name}</h3>
              <p style="margin:4px 0;color:var(--gold);font-weight:700">
                <span title="AT = All-Time-Bananen: dein Dauer-Konto">
                  ${p.at.verfuegbar.toLocaleString("de-DE")} AT verfügbar
                </span>
              </p>
              <p class="muted" style="margin:0;font-size:0.8rem">
                AT = All-Time-Bananen: dein Dauer-Konto (gesamt
                ${p.at.gesamt.toLocaleString("de-DE")}) · Vorschau zeigt deine angelegten Items
              </p>
              ${
                vorschauWahl
                  ? html`<p
                      data-testid="vorschau-hinweis"
                      style="margin:4px 0 0;font-size:0.82rem;color:var(--gold)"
                    >
                      👁 Vorschau: ${vorschauWahl.emoji} ${vorschauWahl.name}
                      <button
                        style="min-height:32px;padding:2px 10px;margin-left:6px;font-size:0.8rem"
                        @click=${() => {
                          s.vorschauItem = null;
                          neuZeichnen();
                        }}
                      >
                        ✕ aus
                      </button>
                    </p>`
                  : ""
              }
              ${verdienHinweis(p)} ${levelBalken(p.at.gesamt)}
            </div>
          </div>`
        : ""
    }
    ${shopChipLeiste()}
    ${
      liste.length === 0
        ? html`<div class="leer-zustand">
            <span class="leer-emoji">🙈</span>
            <p>Nichts gefunden — Filter etwas lockern, dann füllt sich die Vitrine wieder.</p>
          </div>`
        : shopVitrine(liste)
    }
    <p class="muted" style="font-size:0.78rem">
      Kein Echtgeld, keine Lootboxen — AT gibt's nur fürs Spielen (§7.4-Charta).
    </p>
  `;
}

/** Live-Thumbnails am Affen: nur die ersten 12 sichtbaren Karten (Performanz —
 * jede Puppe ist ein Inline-SVG-Klon; fuellePuppen lädt lazy aus dem Cache). */
const MAX_THUMBS = 12;

/** Shop-Vitrine (Welle 4): bei „Alle" nach Typ-Abschnitten mit Headern + Icons
 * gruppiert; mit aktivem Chip/Preis-Sortierung bleibt es EIN flaches Grid. */
function shopVitrine(liste: ShopItemWire[]): TemplateResult {
  let thumbs = 0;
  const karte = (item: ShopItemWire): TemplateResult => {
    const mitThumb = item.visuell === true && thumbs < MAX_THUMBS;
    if (mitThumb) thumbs++;
    return shopItemKarte(item, mitThumb);
  };
  if (s.shopTyp !== "" || s.shopSort !== "") {
    return html`<div class="shop-grid">${liste.map(karte)}</div>`;
  }
  const gruppen = SHOP_TYP_CHIPS.map(([typ, label]) => ({
    typ,
    label,
    items: liste.filter((i) => shopChipTyp(i) === typ),
  })).filter((g) => g.items.length > 0);
  return html`${gruppen.map(
    (g) => html`
      <h3 class="shop-abschnitt" data-testid="shop-abschnitt-${g.typ}">
        <span>${g.label}</span>
        <small>${g.items.length} Item${g.items.length === 1 ? "" : "s"}</small>
      </h3>
      <div class="shop-grid">${g.items.map(karte)}</div>
    `,
  )}`;
}

function shopItemKarte(item: ShopItemWire, mitThumb = false): TemplateResult {
  const p = s.gewaehlt;
  const besessen = p?.besitz.includes(item.id) ?? false;
  const angelegt = p?.ausgeruestet[item.slot] === item.id;
  const geschenk = item.passExklusiv !== undefined; // unkaufbar (Pass/Willkommen)
  const kaufbar = p !== null && !geschenk && (!besessen || item.typ === "badge");
  // Level-Gate (§7.5): Basis ist das LIFETIME-Level — Ausgeben sperrt nie.
  const levelZuNiedrig =
    item.minLevel !== undefined && p !== null && levelFuerAt(p.at.gesamt) < item.minLevel;
  // Thumbnail = eigener Affe MIT dem Item (Vorschau-Pfad Welle 3); Kopf-Items
  // (Hut/Gesicht) zeigen den Kopf-Ausschnitt statt der ganzen Puppe.
  const basisAvatar = p?.avatar ?? "don-bananas.gelb";
  const kopfItem = item.slot === "hut" || item.slot === "gesicht";
  return html`<div class="shop-item rahmen-${preisRahmen(item)} ${besessen ? "besessen" : ""}">
    ${besessen ? html`<span class="besitz-badge">✓ Deins</span>` : ""}
    <div class="shop-item-kopf">
      ${
        mitThumb
          ? html`<div
              class="shop-thumb ${kopfItem ? "kopf" : ""}"
              data-testid="shop-thumb"
              data-avatar=${vorschauAvatar(basisAvatar, item.id)}
            ></div>`
          : html`<span class="shop-item-emoji">${item.emoji}</span>`
      }
      <strong>${mitThumb ? html`${item.emoji} ` : ""}${item.name}</strong>
      ${item.minLevel !== undefined ? html`<span class="level-gate">ab Lv ${item.minLevel}</span>` : ""}
    </div>
    <small>${item.beschreibung}</small>
    ${
      geschenk
        ? html`<span class="preis seltenheit-gruen">🎁 Geschenk — unverkäuflich</span>`
        : html`<span class="preis seltenheit-${item.seltenheit}">
            ${item.preis.toLocaleString("de-DE")} AT <small>(${item.inAbenden})</small>
          </span>`
    }
    ${
      s.kaufMoment === item.id
        ? html`<span
            data-testid="kauf-moment"
            style="color:var(--gold);font-weight:800;animation:mm-kauf-puls 0.9s ease-in-out 2"
          >
            🎉 Gekauft!${angelegt ? " Angelegt! ✓" : ""}
          </span>`
        : ""
    }
    <div style="display:flex;gap:6px;flex-wrap:wrap">
      ${
        kaufbar
          ? html`<button
              ?disabled=${(p !== null && p.at.verfuegbar < item.preis) || levelZuNiedrig}
              @click=${() => kaufe(item)}
            >
              ${levelZuNiedrig ? "🔒 Level zu niedrig" : besessen ? "Nochmal spenden 💛" : "Kaufen"}
            </button>`
          : ""
      }
      ${
        item.visuell === true && p !== null
          ? html`<button
              class=${s.vorschauItem === item.id ? "primaer" : ""}
              data-testid="vorschau-${item.id}"
              title="Live-Vorschau am eigenen Affen (oben)"
              @click=${() => {
                s.vorschauItem = s.vorschauItem === item.id ? null : item.id;
                neuZeichnen();
              }}
            >
              ${s.vorschauItem === item.id ? "👁 Vorschau an" : "👁 Vorschau"}
            </button>`
          : ""
      }
      ${
        besessen && item.typ !== "badge" && item.typ !== "sticker"
          ? html`<button
              class=${angelegt || s.kaufMoment === item.id ? "primaer" : ""}
              data-testid=${s.kaufMoment === item.id && !angelegt ? "anlegen-cta" : "anlegen"}
              @click=${() => ruesteAus(item, angelegt)}
            >
              ${angelegt ? "✓ Angelegt" : s.kaufMoment === item.id ? "✨ Gleich anlegen!" : "Anlegen"}
            </button>`
          : ""
      }
      ${!p ? html`<small class="muted">Profil wählen zum Kaufen</small>` : ""}
    </div>
  </div>`;
}

function kaufe(item: ShopItemWire): void {
  if (!s.gewaehlt) return;
  void api<{ profil: ProfilVoll }>(`/api/meta/profile/${s.gewaehlt.profileId}/kaufe`, {
    itemId: item.id,
    deviceToken: deviceToken(),
  }).then((d) => {
    if (d) {
      s.gewaehlt = d.profil;
      // Kauf-Moment (Eval 4): Mini-Konfetti + „Gleich anlegen!"-CTA am Item.
      s.kaufMoment = item.id;
      kaufKonfetti();
      neuZeichnen();
    }
  });
}

function ruesteAus(item: ShopItemWire, ablegen: boolean): void {
  if (!s.gewaehlt) return;
  void api<{ profil: ProfilVoll }>(`/api/meta/profile/${s.gewaehlt.profileId}/ruestung`, {
    slot: item.slot,
    itemId: ablegen ? null : item.id,
    deviceToken: deviceToken(),
  }).then((d) => {
    if (d) {
      s.gewaehlt = d.profil;
      neuZeichnen();
    }
  });
}

// ---------- Bananen-Pass & Quests (§7.5, Meta-Agent 2) ----------

function ruesteAusDirekt(slot: string, itemId: string | null): void {
  if (!s.gewaehlt) return;
  void api<{ profil: ProfilVoll }>(`/api/meta/profile/${s.gewaehlt.profileId}/ruestung`, {
    slot,
    itemId,
    deviceToken: deviceToken(),
  }).then((d) => {
    if (d) {
      s.gewaehlt = d.profil;
      neuZeichnen();
    }
  });
}

/** Bananen-Pfad (Welle 4): die 30 Stufen als gewundene Reise — Serpentinen-
 * Reihen à 5, jede zweite läuft rückwärts, Kurven-Verbinder an den Enden. */
const PASS_REIHE = 5;

function passStufe(
  b: PassWire["belohnungen"][number],
  d: PassWire,
  markerStufe: number,
): TemplateResult {
  const naechste = b.stufe === d.stufe + 1;
  const marker = b.stufe === markerStufe;
  return html`<div
    class="pass-stufe ${b.erreicht ? "erreicht" : ""} ${naechste ? "naechste" : ""} ${b.art === "item" ? "item-stufe" : ""}"
    title=${b.art === "at" ? `Stufe ${b.stufe}: +${b.at} AT` : `Stufe ${b.stufe}: ${b.item?.name ?? "?"}`}
  >
    ${
      marker
        ? html`<div
            class="pass-marker ${d.stufe === 0 ? "wartet" : ""}"
            data-testid="pass-marker"
            title=${d.stufe === 0 ? "Hier startet deine Reise" : "Du bist hier"}
            data-avatar=${s.gewaehlt?.avatar ?? "don-bananas.gelb"}
          ></div>`
        : ""
    }
    <span class="stufe-nr">${b.stufe}</span>
    <span class="stufe-icon">${b.art === "at" ? "💰" : "🎁"}</span>
    <small>${b.art === "at" ? `+${b.at}` : html`${b.item?.emoji ?? ""} EXKLUSIV`}</small>
  </div>`;
}

function passPfad(d: PassWire): TemplateResult {
  const reihen: PassWire["belohnungen"][] = [];
  for (let i = 0; i < d.belohnungen.length; i += PASS_REIHE) {
    reihen.push(d.belohnungen.slice(i, i + PASS_REIHE));
  }
  // Marker sitzt auf der aktuellen Stufe; vor Stufe 1 wartet er am Start.
  const markerStufe = Math.max(1, Math.min(d.stufe, d.saison.stufen));
  return html`<div class="pass-pfad" data-testid="pass-pfad">
    ${reihen.map((reihe, r) => {
      const kurve = r < reihen.length - 1 ? (r % 2 === 0 ? "kurve-rechts" : "kurve-links") : "";
      return html`<div class="pass-reihe ${r % 2 === 1 ? "rueckweg" : ""} ${kurve}">
        ${reihe.map((b) => passStufe(b, d, markerStufe))}
      </div>`;
    })}
  </div>`;
}

function passItemBelohnungen(d: PassWire): TemplateResult {
  const items = d.belohnungen.filter((b) => b.art === "item" && b.item !== undefined);
  return html`<div class="karte">
    <h3 style="margin:0 0 6px">Saison-exklusive Belohnungen</h3>
    <p class="muted" style="margin:0 0 8px;font-size:0.8rem">
      Neue Stufen sind nur bis zum Saisonende freischaltbar. Schon verdiente Items bleiben dauerhaft
      in deinem Besitz — dein Stand wandert am Monatswechsel ins Saison-Archiv.
    </p>
    <div class="pass-items">
      ${items.map((b) => {
        const item = b.item!;
        const angelegt = s.gewaehlt?.ausgeruestet[item.slot] === item.id;
        return html`<div class="shop-item rahmen-geschenk ${b.erreicht ? "besessen" : ""}">
          ${b.erreicht ? html`<span class="besitz-badge">✓ Deins</span>` : ""}
          <div class="shop-item-kopf">
            <span class="shop-item-emoji">${item.emoji}</span>
            <strong>${item.name}</strong>
          </div>
          <small>${item.beschreibung}</small>
          <span class="preis seltenheit-diamant">Stufe ${b.stufe}</span>
          ${
            b.erreicht
              ? html`<button
                  class=${angelegt ? "primaer" : ""}
                  @click=${() => ruesteAusDirekt(item.slot, angelegt ? null : item.id)}
                >
                  ${angelegt ? "✓ Angelegt" : "Anlegen"}
                </button>`
              : html`<small class="muted">🔒 noch ${b.stufe - d.stufe} Stufen</small>`
          }
        </div>`;
      })}
    </div>
  </div>`;
}

/** Fortschritts-RING statt Balken (Welle 4): SVG-Kreis, startet oben (−90°). */
const RING_UMFANG = 2 * Math.PI * 20;

function questRing(q: PassWire["quests"][number]): TemplateResult {
  const anteil = Math.min(1, q.ziel > 0 ? q.fortschritt / q.ziel : 0);
  return html`<svg class="quest-ring" viewBox="0 0 48 48" aria-hidden="true">
    <circle class="ring-spur" cx="24" cy="24" r="20"></circle>
    <circle
      class="ring-wert"
      cx="24"
      cy="24"
      r="20"
      stroke-dasharray="${(anteil * RING_UMFANG).toFixed(1)} ${RING_UMFANG.toFixed(1)}"
    ></circle>
    <text x="24" y="25">${q.fertig ? "✓" : `${q.fortschritt}/${q.ziel}`}</text>
  </svg>`;
}

function questKarte(q: PassWire["quests"][number]): TemplateResult {
  return html`<div class="quest-karte ${q.fertig ? "fertig" : ""}">
    ${questRing(q)}
    <div class="quest-text">
      <strong>${q.text}</strong>
      <span class="quest-xp">${q.fertig ? "✓ geschafft!" : `+${q.xp} XP`}</span>
    </div>
  </div>`;
}

function passScreen(): TemplateResult {
  const p = s.gewaehlt;
  if (!p) {
    return html`${profilWahlKarte("Wessen Pass & Aufgaben?")}
      <p class="muted">Profil wählen — Pass & Aufgaben laufen pro Profil.</p>`;
  }
  const d = s.pass;
  if (!d || s.passFuer !== p.profileId) {
    if (s.passFuer !== p.profileId) ladePass();
    return html`${profilWahlKarte("Wessen Pass & Aufgaben?")}
      <p class="muted">Lade Bananen-Pass …</p>`;
  }
  // Epoch-Zeit OHNE Date.now (Lint-Konvention): timeOrigin + monotone Uhr.
  const jetzt = performance.timeOrigin + performance.now();
  const tageRest = Math.max(0, Math.ceil((d.saison.endetTs - jetzt) / 86_400_000));
  const spanne = d.naechsteAbXp !== null ? d.naechsteAbXp - d.stufeAbXp : 1;
  const anteil = d.naechsteAbXp === null ? 100 : Math.round(((d.xp - d.stufeAbXp) / spanne) * 100);
  const dailies = d.quests.filter((q) => q.art === "daily");
  const monate = d.quests.filter((q) => q.art === "monat");
  return html`${profilWahlKarte("Wessen Pass & Aufgaben?")}
    <div class="karte">
      <div style="display:flex;gap:10px;align-items:baseline;flex-wrap:wrap">
        <h3 style="margin:0">🍌 Bananen-Pass — ${d.saison.name}</h3>
        <span class="muted" style="font-size:0.8rem">
          Saison ${d.saison.id} · endet in ${tageRest} Tag${tageRest === 1 ? "" : "en"}
        </span>
      </div>
      <p style="margin:6px 0 4px">
        <strong style="color:var(--gold)">Stufe ${d.stufe}/${d.saison.stufen}</strong>
        · ${d.xp.toLocaleString("de-DE")} XP
        ${
          d.naechsteAbXp !== null
            ? html`<span class="muted" style="font-size:0.85rem">
                — noch ${(d.naechsteAbXp - d.xp).toLocaleString("de-DE")} XP bis Stufe
                ${d.stufe + 1}</span
              >`
            : html`<span style="color:var(--gruen)"> — PASS KOMPLETT! 🎉</span>`
        }
      </p>
      <div class="quest-balken pass-balken"><div style="width:${anteil}%"></div></div>
      <p class="muted" style="margin:6px 0 0;font-size:0.78rem">
        XP gibt's fürs Spielen (Match +50, Sieg +50) und für Aufgaben — gratis für alle, kein
        Echtgeld. Diese Saison schon ${d.atBonus.toLocaleString("de-DE")} Bonus-AT eingesammelt.
      </p>
    </div>
    <div class="karte">
      <h3 style="margin:0 0 2px">Deine Bananen-Reise</h3>
      <p class="muted" style="margin:0 0 6px;font-size:0.78rem">
        ${d.saison.stufen} Stufen bis zum Saison-Gipfel — 🎁 = saison-exklusives Item.
      </p>
      ${passPfad(d)}
    </div>
    ${passItemBelohnungen(d)}
    <div class="karte">
      <h3 style="margin:0 0 6px">Tages-Aufgaben <span class="muted">(${d.tagKey})</span></h3>
      <div class="quest-karten">${dailies.map((q) => questKarte(q))}</div>
    </div>
    <div class="karte">
      <h3 style="margin:0 0 6px">Saison-Aufgaben <span class="muted">(${d.saison.id})</span></h3>
      <div class="quest-karten">${monate.map((q) => questKarte(q))}</div>
    </div>
    ${
      d.archiv.length > 0
        ? html`<div class="karte">
            <h3 style="margin:0 0 6px">Saison-Archiv</h3>
            ${[...d.archiv].reverse().map(
              (a) =>
                html`<div class="board-zeile">
                  <span>${a.name}</span>
                  <span class="muted">(${a.saisonId})</span>
                  <span class="wert">
                    Stufe ${a.stufe} · ${a.verdient.length}
                    Item${a.verdient.length === 1 ? "" : "s"}
                  </span>
                </div>`,
            )}
          </div>`
        : ""
    }`;
}

// ---------- Profil-Karte ----------

function karteScreen(): TemplateResult {
  if (!s.gewaehlt)
    return html`${profilWahlKarte("Wessen Profil-Karte?")}
      <p class="muted">Profil wählen …</p>`;
  const k = s.karte;
  if (!k || k.profileId !== s.gewaehlt.profileId) {
    ladeKarte();
    return html`${profilWahlKarte("Wessen Profil-Karte?")}
      <p class="muted">Lade Karte …</p>`;
  }
  const quote = (q: { kategorie: string; quote: number } | null): string =>
    q ? `${q.kategorie} (${Math.round(q.quote * 100)} %)` : "— (ab 20 Antworten)";
  return html`${profilWahlKarte("Wessen Profil-Karte?")}
    ${s.gewaehlt ? willkommensKarte(s.gewaehlt) : ""}
    <div class="karte ausweis" data-testid="ausweis">
      <div class="ausweis-kopf">
        <span>🐒 Affen-Ausweis</span>
        <span class="ausweis-serie">MONKEY MONEY · Lv ${k.level}</span>
      </div>
      <div class="ausweis-mitte">
        <div class="ausweis-foto">
          <div class="puppe" data-avatar=${k.avatar}></div>
        </div>
        <div class="ausweis-daten">
          <h3 class="ausweis-name">${k.name} ${k.gesperrt ? "🔒" : ""}</h3>
          ${k.titel ? html`<p class="ausweis-titel">${k.titel}</p>` : ""}
          <dl class="ausweis-stats">
            <div>
              <dt>Matches</dt>
              <dd>${k.matches}</dd>
            </div>
            <div>
              <dt>Siege</dt>
              <dd>${k.siege}</dd>
            </div>
            <div>
              <dt>AT gesamt</dt>
              <dd title="AT = All-Time-Bananen: dein Dauer-Konto">
                ${k.at.gesamt.toLocaleString("de-DE")}
              </dd>
            </div>
            <div>
              <dt>AT verfügbar</dt>
              <dd>${k.at.verfuegbar.toLocaleString("de-DE")}</dd>
            </div>
          </dl>
        </div>
      </div>
      <div class="ausweis-fuss">${levelBalken(k.at.gesamt)}</div>
    </div>
    ${
      k.statsAusstehend
        ? html`<p
            style="margin:0;color:var(--gold);font-size:0.85rem"
            data-testid="stats-ausstehend"
          >
            ⏳ Statistik aktualisiert sich — die letzte Match-Wertung braucht bis zu 90 Sekunden.
            Diese Karte lädt automatisch nach.
          </p>`
        : ""
    }
    <div class="karte medaillen-karte">
      <h3 style="margin:0 0 8px">🏅 Bestleistungen</h3>
      <div class="medaillen" data-testid="medaillen">
        <div class="medaille gold">
          <span class="medaille-icon">🏆</span>
          <b>${k.hoechsterMatchGewinn.toLocaleString("de-DE")}</b>
          <small>bester Endstand (MM)</small>
        </div>
        <div class="medaille silber">
          <span class="medaille-icon">🔥</span>
          <b>${k.laengsteSerie}</b>
          <small>längste Antwort-Serie</small>
        </div>
        <div class="medaille bronze">
          <span class="medaille-icon">⚡</span>
          <b
            >${k.schnellsteAntwortMs !== null ? `${(k.schnellsteAntwortMs / 1000).toFixed(1)} s` : "—"}</b
          >
          <small>schnellste richtige Antwort</small>
        </div>
      </div>
    </div>
    <div class="karte">
      <p style="margin:2px 0">
        💚 Lieblings-Kategorie: <strong>${quote(k.lieblingsKategorie)}</strong>
      </p>
      <p style="margin:2px 0">
        💀 Nemesis-Kategorie: <strong>${quote(k.nemesisKategorie)}</strong>
      </p>
    </div>`;
}

// ---------- Trainingslager (§6.2) ----------

function naechsteTrainingsFrage(): void {
  s.tAufloesung = null;
  s.tGewaehlt = null;
  s.tWeg = [];
  s.tTipps = [];
  void api<TrainingsFrage>("/api/meta/uebung/frage", {
    key: trainingsKey(),
    kategorie: s.tKategorie || undefined,
    schwierigkeit: s.tSchwierigkeit || undefined,
  }).then((d) => {
    if (d) {
      s.tFrage = d;
      // Lokale Dauer-Messung (nur Lern-Statistik) — performance statt OS-Uhr.
      s.tStart = performance.now();
      neuZeichnen();
    }
  });
}

function beantworte(choice: number): void {
  if (!s.tFrage || s.tAufloesung) return;
  s.tGewaehlt = choice;
  void api<{ korrekt: boolean; antwort: number; erklaerung: string; stats: TrainingsStats }>(
    "/api/meta/uebung/antwort",
    {
      key: trainingsKey(),
      questionId: s.tFrage.questionId,
      choice,
      dauerMs: Math.round(performance.now() - s.tStart),
    },
  ).then((d) => {
    if (d) {
      s.tAufloesung = { korrekt: d.korrekt, antwort: d.antwort, erklaerung: d.erklaerung };
      s.tStats = d.stats;
      // Session-Zählung (Welle 4) — nur für die Fazit-Karte, Server zählt selbst.
      const frage = s.tFrage;
      s.tSession.beantwortet++;
      if (d.korrekt) s.tSession.richtig++;
      if (frage) {
        const zelle = (s.tSession.kategorien[frage.kategorie] ??= { n: 0, richtig: 0 });
        zelle.n++;
        if (d.korrekt) zelle.richtig++;
      }
      neuZeichnen();
    }
  });
}

/** Session beenden → Fazit-Karte („12 geübt · 75 % · stärkste Kategorie: X"). */
function beendeSession(): void {
  s.tFazit = true;
  s.tFrage = null;
  s.tAufloesung = null;
  s.tGewaehlt = null;
  s.tWeg = [];
  s.tTipps = [];
  neuZeichnen();
}

function staerksteSessionKategorie(): { name: string; quote: number } | null {
  let beste: { name: string; quote: number; n: number } | null = null;
  for (const [slug, z] of Object.entries(s.tSession.kategorien)) {
    const quote = z.richtig / Math.max(1, z.n);
    if (!beste || quote > beste.quote || (quote === beste.quote && z.n > beste.n)) {
      beste = { name: lesbaresKategorieLabel(slug), quote, n: z.n };
    }
  }
  return beste ? { name: beste.name, quote: beste.quote } : null;
}

function holeTipp(): void {
  if (!s.tFrage || s.tAufloesung) return;
  // Stufenweise Enthüllung: echte Autoren-Tipps (1→2→3); Fragen ohne
  // Tipps antworten mit dem alten 50:50 ({ entfernt }).
  void api<{ tipp?: string; stufe?: number; entfernt?: number[] }>("/api/meta/uebung/tipp", {
    key: trainingsKey(),
    questionId: s.tFrage.questionId,
  }).then((d) => {
    if (d) {
      if (typeof d.tipp === "string") s.tTipps = [...s.tTipps, d.tipp];
      if (Array.isArray(d.entfernt)) s.tWeg = d.entfernt;
      neuZeichnen();
    }
  });
}

function trainingScreen(): TemplateResult {
  const oberkategorien = [...new Set(s.kategorien.map((k) => k.oberkategorie))].sort();
  return html`<div class="karte">
      <div class="training-optionen">
        <strong>🏋️ Trainingslager</strong>
        <select
          @change=${(e: Event) => {
            s.tKategorie = (e.target as HTMLSelectElement).value;
          }}
        >
          <option value="">Alle Kategorien</option>
          ${oberkategorien.map(
            (o) => html`<option value=${o} ?selected=${s.tKategorie === o}>${o}</option>`,
          )}
        </select>
        <select
          @change=${(e: Event) => {
            s.tSchwierigkeit = (e.target as HTMLSelectElement).value;
          }}
        >
          <option value="">Jede Schwierigkeit</option>
          ${["easy", "medium", "hard", "ultrahard"].map(
            (st) =>
              html`<option value=${st} ?selected=${s.tSchwierigkeit === st}>
                ${SCHWIERIGKEIT_LABEL[st]}
              </option>`,
          )}
        </select>
        <button
          class="primaer"
          @click=${() => {
            if (s.tFazit) {
              s.tFazit = false;
              s.tSession = { beantwortet: 0, richtig: 0, kategorien: {} };
            }
            naechsteTrainingsFrage();
          }}
        >
          ${s.tFrage ? "Nächste Frage →" : "Los geht's!"}
        </button>
        ${
          s.tFrage !== null && s.tSession.beantwortet > 0
            ? html`<button data-testid="session-ende" @click=${beendeSession}>
                🏁 Session beenden
              </button>`
            : ""
        }
      </div>
      <p class="muted" style="font-size:0.78rem;margin:6px 0 0">
        Endlos üben, sofortige Auflösung, kostenlose Tipps — was du oft falsch hast, kommt öfter.
        KEINE AT-Wertung.
      </p>
    </div>
    ${s.tFazit ? trainingsFazitKarte() : ""} ${s.tFrage ? trainingsFrageKarte() : ""}
    ${s.tStats ? trainingsStatsKarte() : ""}`;
}

/** Session-Fazit (Welle 4): „12 geübt · 75 % · stärkste Kategorie: X". */
function trainingsFazitKarte(): TemplateResult {
  const se = s.tSession;
  const quote = se.beantwortet > 0 ? Math.round((se.richtig / se.beantwortet) * 100) : 0;
  // „Stärkste Kategorie" nur, wenn es überhaupt Richtige gab (sonst hohl).
  const beste = se.richtig > 0 ? staerksteSessionKategorie() : null;
  return html`<div class="karte training-fazit" data-testid="training-fazit">
    <h3 style="margin:0">${quote >= 60 ? "🏁 Starke Session!" : "🏁 Session-Fazit"}</h3>
    <div class="fazit-zahlen">
      <span class="kpi">
        <b data-tick-ziel=${se.beantwortet}></b>
        geübt
      </span>
      <span class="kpi">
        <b data-tick-ziel=${quote} data-tick-suffix=" %"></b>
        richtig
      </span>
      ${
        beste
          ? html`<span class="kpi">
              <b>${beste.name}</b>
              stärkste Kategorie (${Math.round(beste.quote * 100)} %)
            </span>`
          : ""
      }
    </div>
    <p class="muted" style="margin:4px 0 0;font-size:0.82rem">
      ${
        quote >= 75
          ? "Bananenstark — das Match kann kommen! 🍌"
          : "Dranbleiben — was du oft falsch hast, kommt im Training öfter dran."
      }
    </p>
  </div>`;
}

function trainingsFrageKarte(): TemplateResult {
  const f = s.tFrage!;
  const a = s.tAufloesung;
  const serie = s.tStats?.serie ?? 0;
  return html`<div
    class="karte training-karte ${a ? (a.korrekt ? "moment-richtig" : "moment-falsch") : ""}"
  >
    <div class="training-kopfzeile">
      <p class="muted" style="margin:0;font-size:0.8rem">
        ${lesbaresKategorieLabel(f.kategorie)} ·
        ${SCHWIERIGKEIT_LABEL[f.schwierigkeit] ?? f.schwierigkeit}
        ${f.bisherFalsch > 0 ? html`· <span style="color:var(--gold)">🔁 Wiederholer</span>` : ""}
      </p>
      ${
        serie >= 2
          ? html`<span class="training-streak ${serie >= 5 ? "heiss" : ""}" data-testid="streak">
              🔥 ${serie}er-Serie
            </span>`
          : ""
      }
    </div>
    <p class="training-frage">${f.text}</p>
    <div class="training-antworten">
      ${f.options.map((opt, i) => {
        const deko = BB_DEKO[i % BB_DEKO.length];
        const klasse = a
          ? i === a.antwort
            ? "richtig"
            : i === s.tGewaehlt
              ? "falsch"
              : ""
          : s.tWeg.includes(i)
            ? "weg"
            : "";
        return html`<button
          class="training-antwort ${klasse}"
          style="--deko:${deko.farbe}"
          ?disabled=${a !== null}
          @click=${() => beantworte(i)}
        >
          <span class="training-deko">${deko.emoji} ${deko.buchstabe}</span>
          <span>${opt}</span>
        </button>`;
      })}
    </div>
    ${
      s.tTipps.length > 0
        ? html`<div style="margin-top:8px">
            ${s.tTipps.map(
              (t, i) => html`<p class="muted" style="margin:2px 0">💡 Tipp ${i + 1}: ${t}</p>`,
            )}
          </div>`
        : ""
    }
    <div style="display:flex;gap:8px;margin-top:8px;align-items:center;flex-wrap:wrap">
      ${
        a === null
          ? (f.tippsGesamt ?? 0) > 0
            ? html`<button ?disabled=${s.tTipps.length >= (f.tippsGesamt ?? 0)} @click=${holeTipp}>
                💡 Tipp ansehen (${s.tTipps.length}/${f.tippsGesamt}, kostenlos)
              </button>`
            : html`<button ?disabled=${s.tWeg.length > 0} @click=${holeTipp}>
                💡 Tipp (2 weg, kostenlos)
              </button>`
          : html`<strong class="training-moment ${a.korrekt ? "richtig" : "falsch"}">
                ${a.korrekt ? "✔ RICHTIG!" : "✘ Daneben."}
              </strong>
              ${a.erklaerung ? html`<span class="muted">${a.erklaerung}</span>` : ""}
              <button class="primaer" @click=${naechsteTrainingsFrage}>Nächste →</button>`
      }
    </div>
  </div>`;
}

function trainingsStatsKarte(): TemplateResult {
  const st = s.tStats!;
  return html`<div class="karte karten-stat">
    <span class="kpi"><b data-tick-ziel=${st.beantwortet}></b> geübt</span>
    <span class="kpi">
      ${
        st.quote !== null
          ? html`<b data-tick-ziel=${Math.round(st.quote * 100)} data-tick-suffix=" %"></b>`
          : html`<b>—</b>`
      }
      Quote
    </span>
    <span class="kpi"><b data-tick-ziel=${st.serie}></b> Serie</span>
    <span class="kpi"><b data-tick-ziel=${st.besteSerie}></b> Rekord-Serie</span>
    ${
      st.schwaechen.length > 0
        ? html`<span class="kpi">
            <b>${st.schwaechen[0].kategorie}</b> übungsbedürftig
            (${Math.round(st.schwaechen[0].quote * 100)} %)
          </span>`
        : ""
    }
  </div>`;
}

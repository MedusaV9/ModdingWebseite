// Raum = Engine-Instanz + Sessions + Sync (Snapshot/Event/seq) + Event-Log.
// Jede Zustandsänderung läuft durch die Engine und erhöht seq; Clients bekommen
// rollen-gefilterte Views. seq-Lücke beim Client ⇒ sync.request ⇒ Voll-Snapshot.
// NEU (Engine-Ausbau): Plugin-Registry statt Einzel-Plugin, Median-RTT-Messung
// pro Spieler (Buzzer-Fairness) und Buzz-Clamping VOR dem Engine-Reducer.
import { randomUUID } from "node:crypto";
import type { Socket } from "socket.io";
import { clampBuzz, medianRtt } from "../../shared/buzzer";
import type { Question } from "../../shared/content";
import { zaehleVideoSongs } from "../../shared/songs";
import type { Role } from "../../shared/ids";
import type { BuzzMsg, GmLogEntry, ViewEvent } from "../../shared/protocol";
import type { JubilaeumsView } from "../../shared/views";
import type { Rng } from "../../shared/rng";
import type { Clock } from "../../shared/time";
import { createMatchEventLog, type MatchEventLog } from "../analytics/event-log";
import type { ContentLoader, PlanFrageTyp } from "../content-loader/index";
import * as engine from "../engine/engine";
import type { EngineDeps } from "../engine/engine";
import type { EngineAction, EngineEvent, EngineState } from "../engine/types";
import { viewFor, type RoomInfo } from "../engine/views";
import type { MinigamePlugin } from "../minigames/_api/plugin";
import type { Storage } from "../persistence/storage";
import { autoRaumName } from "./lobby";
import { createSessionStore, type SessionStore } from "./sessions";

/** Kappe des Abend-Gedächtnisses (Welle 1): so viele zuletzt gespielte
 * Fragen-IDs bleiben über Matches hinweg gesperrt (LRU). */
const ABEND_GEDAECHTNIS_MAX = 500;

/** META-Hooks (ADDITIV, Meta-Agent): AT-Buchung, In-Prozess-Bots, Save/Load.
 * Interface lebt HIER (Room kennt nur den Vertrag — keine Import-Zyklen). */
export interface RoomMetaHooks {
  /** Join MIT Profil (§7.1): PIN/Gerät prüfen + Anzeige-Name/-Avatar liefern.
   * staerke = Lifetime-AT (Team-Auto-Balance, GAME-DESIGN §1.4 — ADDITIV). */
  profilJoin(
    profileId: string,
    zugriff: { pin?: string; deviceToken?: string },
  ): Promise<{ ok: boolean; error?: string; name?: string; avatar?: string; staerke?: number }>;
  /** Match gestartet ⇒ Gruppen-Jubiläum erkennen (v2, synchron aus dem Cache). */
  matchGestartet(room: Room): JubilaeumsView | null;
  /** match_ended committed ⇒ AT-Buchung pro gebundenem Profil (idempotent). */
  matchBeendet(room: Room): void;
  /** Pro Manager-Tick: In-Prozess-Bots dieses Raums handeln lassen. */
  botTick(room: Room): void;
  /** Pro Manager-Tick (optional): periodischer Crash-Schutz-Autosave —
   * der Meta-Service drosselt intern auf ~30 s und nur laufende Matches. */
  autosaveTick?(room: Room): void;
  /** GM-Meta-Kommandos (save.*, bot.*) — null = kein Meta-Kommando. */
  gmMetaCmd(
    room: Room,
    cmd: string,
    args: Record<string, unknown>,
  ): Promise<{ ok: boolean; error?: string; logText?: string }> | null;
  /** Raum wird abgebaut (TTL): Autosave laufender Matches. */
  raumSchliesst(room: Room, reason: "ttl" | "gm-ende"): void;
}

export interface RoomDeps {
  clock: Clock;
  rng: Rng;
  storage: Storage;
  contentLoader: ContentLoader;
  plugins: {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    get(id: string): MinigamePlugin<any, any>;
    alle(): string[];
    /** ADDITIV (Musik): verfügbare Plugins nach Song-Pack-Zustand filtern
     * (registry.allePluginsFuer) — optional, damit Test-Fakes gültig bleiben.
     * videoSongs = Songs MIT video3s (Stummfilm-Studio-Gate, minVideoSongs). */
    alleFuer?(opts: { songsVerfuegbar: boolean; videoSongs?: number }): string[];
  };
  /** Ziel-Größe des Fragen-Pools pro Match (Loader liefert, was da ist). */
  fragenProMatch: number;
  /** META (optional): Profile/AT/Bots/Saves — Räume laufen auch ohne. */
  meta?: RoomMetaHooks;
}

/** Ein verbundener Client (Socket + Rolle + optional Spieler-Slot). */
export interface RoomClient {
  socket: Socket;
  role: Role;
  playerId: string | null;
}

export class Room {
  // code/gmPin/matchId sind intern mutierbar: Save-Load übernimmt die Werte
  // aus der Save-Datei (Raum läuft unter altem Code/PIN/Event-Log weiter).
  code: string;
  gmPin: string;
  matchId: string;
  readonly createdAt: number;
  origin: string; // Screen-Origin für Join-URL/QR (Tunnel vs. LAN automatisch richtig)
  // ---------- LOBBY (ADDITIV): öffentlicher Lobby-Browser (Opt-in) ----------
  /** Anzeige-Name im Lobby-Browser (Auto: „Bananen-Bande #CODE", editierbar). */
  lobbyName: string;
  /** true = im öffentlichen Lobby-Browser sichtbar — Default PRIVAT (nur Code). */
  oeffentlich = false;

  state: EngineState;
  seq = 0;
  emptySince: number | null;

  readonly sessions: SessionStore;
  /** META: playerId → profileId (Join mit Profil) — Basis der AT-Buchung. */
  readonly profilBindungen = new Map<string, string>();
  /** Team-Modus: playerId → Lifetime-AT (Stärke) — Basis der Auto-Balance.
   * Nur bei Profil-Joins gefüllt; Gäste zählen als Stärke 0 (fair genug). */
  readonly profilStaerken = new Map<string, number>();
  /** v2 Jubiläums-Erkennung: Gruppen-Meilenstein DIESES Matches (Opening-Feier). */
  jubilaeum: JubilaeumsView | null = null;
  /** EIN aktives GM-Cockpit (GAME-DESIGN §4-Geist: „der eine Mensch mit Cockpit").
   * Weitere GM-Verbindungen sind Beobachter; Übernahme nur via PIN (gm.takeover). */
  private aktiverGmSocketId: string | null = null;
  private readonly clients = new Map<string, RoomClient>(); // key = socket.id
  private readonly gmLog: GmLogEntry[] = [];
  private log: MatchEventLog;
  readonly deps: RoomDeps;
  /** RTT-Proben pro Spieler (letzte 5) — Grundlage der Buzzer-Kompensation. */
  private readonly rtts = new Map<string, number[]>();
  /** Abend-Gedächtnis (Welle 1, Eval „Dauerwiederholungen"): über MATCHES
   * hinweg gespielte Fragen-IDs — Match 2 des Abends zieht frische Fragen.
   * LRU-gedeckelt; reicht der Rest-Vorrat nicht, füllt startMatch per Top-Up
   * kontrolliert mit Wiederholungen auf (kleine Packs verhungern nicht). */
  private readonly abendFragenIds: string[] = [];

  constructor(code: string, origin: string, deps: RoomDeps) {
    this.code = code;
    this.origin = origin;
    this.deps = deps;
    this.lobbyName = autoRaumName(code);
    this.gmPin = String(1000 + deps.rng.int(9000)); // 4-stellige GM-PIN (Screen zeigt sie an)
    this.matchId = `m_${randomUUID().slice(0, 8)}`;
    this.createdAt = deps.clock.now();
    this.emptySince = deps.clock.now();
    this.sessions = createSessionStore();
    this.state = engine.createInitialState();
    this.log = createMatchEventLog(deps.storage, this.matchId, deps.clock);
  }

  // ---------- META: Profil-Bindung (Join mit Profil, §7.1) ----------

  /** Spieler-Slot an ein Profil binden + ins Event-Log (Stats-Zuordnung).
   * staerke (Lifetime-AT) füttert die Team-Auto-Balance beim Match-Start. */
  bindeProfil(playerId: string, profileId: string, staerke?: number): void {
    this.profilBindungen.set(playerId, profileId);
    if (staerke !== undefined) this.profilStaerken.set(playerId, staerke);
    this.log.append(this.seq, {
      type: "profile_bound",
      actor: playerId,
      payload: { profileId },
    });
  }

  // ---------- META: Save/Load ----------

  /** Zustand aus einer Save-Datei übernehmen (Code-Re-Key macht der Manager). */
  uebernimmSave(save: {
    gmPin: string;
    matchId: string;
    seq: number;
    engineState: EngineState;
    sessions: { token: string; role: Role; playerId: string | null }[];
    profilBindungen: Record<string, string>;
  }): void {
    this.gmPin = save.gmPin;
    this.matchId = save.matchId;
    this.seq = save.seq;
    this.state = save.engineState;
    this.sessions.importiere(save.sessions);
    this.profilBindungen.clear();
    for (const [pid, prof] of Object.entries(save.profilBindungen)) {
      this.profilBindungen.set(pid, prof);
    }
    // Event-Log unter der ALTEN matchId weiterführen (ein Match = eine Datei).
    this.log = createMatchEventLog(this.deps.storage, this.matchId, this.deps.clock);
    this.log.append(this.seq, { type: "match_loaded", payload: { code: this.code } });
  }

  /** NUR für Meta-Verwaltung (Bot-Entfernen in der Lobby): State roh ersetzen. */
  ersetzeStateRoh(neuerState: EngineState): void {
    this.commit(neuerState, []);
    this.broadcastSnapshots();
  }

  // ---------- Client-Verwaltung ----------

  attachClient(client: RoomClient): void {
    this.clients.set(client.socket.id, client);
    this.emptySince = null;
  }

  detachClient(socketId: string): RoomClient | undefined {
    const client = this.clients.get(socketId);
    this.clients.delete(socketId);
    if (this.clients.size === 0) this.emptySince = this.deps.clock.now();
    // Aktiver GM weg ⇒ erster verbliebener GM-Beobachter rückt automatisch nach.
    if (socketId === this.aktiverGmSocketId) {
      this.aktiverGmSocketId = null;
      for (const [id, c] of this.clients) {
        if (c.role === "gm") {
          this.aktiverGmSocketId = id;
          break;
        }
      }
      if (this.aktiverGmSocketId !== null) {
        this.gmLogEintrag(
          "gm.wechsel",
          { grund: "nachrueckt" },
          "🎙️ GM-Wechsel: Beobachter rückt nach",
        );
        this.applyAction({ type: "gm.wechsel", grund: "nachrueckt" });
        this.sendeGmStatus();
      }
    }
    return client;
  }

  get clientCount(): number {
    return this.clients.size;
  }

  /** Ist NOCH ein Socket mit diesem Spieler-Slot verbunden? (Doppelgerät:
   * Tab 2 zu ≠ Spieler offline — Eval-7-Befund „Falsch-Offline".) */
  hatVerbundenenSpieler(playerId: string): boolean {
    for (const client of this.clients.values()) {
      if (client.role === "player" && client.playerId === playerId) return true;
    }
    return false;
  }

  /** Namens-Check (Eval 6): ist der Name in DIESEM Raum schon vergeben?
   * Case-insensitiv + getrimmt — zwei „Anna"s auf Screen/GM wären nicht
   * unterscheidbar. Wer wirklich dieselbe Person ist, kommt per Session-Token
   * (Reconnect) zurück in den ALTEN Slot, nie über einen zweiten Join. */
  nameVergeben(name: string): boolean {
    const norm = name.trim().toLowerCase();
    if (norm.length === 0) return false;
    return Object.values(this.state.players).some((p) => p.name.trim().toLowerCase() === norm);
  }

  // ---------- GM-Verbindungs-Verwaltung (EIN aktives Cockpit) ----------

  /** GM-Anmeldung: erster GM wird aktiv, weitere sind Beobachter (return true). */
  gmAngemeldet(socketId: string): boolean {
    if (this.aktiverGmSocketId === null || !this.clients.has(this.aktiverGmSocketId)) {
      this.aktiverGmSocketId = socketId;
      return false;
    }
    return this.aktiverGmSocketId !== socketId;
  }

  istAktiverGm(socketId: string): boolean {
    return this.aktiverGmSocketId === socketId;
  }

  /** Takeover NUR mit PIN-Bestätigung: Beobachter übernimmt das aktive Cockpit. */
  gmTakeover(socketId: string, pin: string): { ok: boolean; error?: string } {
    const client = this.clients.get(socketId);
    if (!client || client.role !== "gm") return { ok: false, error: "kein-gm" };
    if (pin !== this.gmPin) return { ok: false, error: "gm-pin-falsch" };
    if (this.aktiverGmSocketId === socketId) return { ok: true };
    this.aktiverGmSocketId = socketId;
    this.gmLogEintrag(
      "gm.wechsel",
      { grund: "takeover" },
      "🎙️ GM-Wechsel: Cockpit per PIN übernommen",
    );
    this.applyAction({ type: "gm.wechsel", grund: "takeover" });
    this.sendeGmStatus();
    return { ok: true };
  }

  /** Beobachter-Flag an ALLE GM-Sockets pushen (nach jedem Wechsel). */
  private sendeGmStatus(): void {
    for (const [id, client] of this.clients) {
      if (client.role === "gm") {
        client.socket.emit("gm.status", { beobachter: id !== this.aktiverGmSocketId });
      }
    }
  }

  // ---------- RTT-Messung (time.probe-Echos) ----------

  recordRtt(playerId: string, rttMs: number): void {
    const liste = this.rtts.get(playerId) ?? [];
    liste.push(Math.max(0, rttMs));
    if (liste.length > 5) liste.shift();
    this.rtts.set(playerId, liste);
  }

  medianRttVon(playerId: string): number {
    return medianRtt(this.rtts.get(playerId) ?? []);
  }

  // ---------- Engine-Zugriff ----------

  private engineDeps(): EngineDeps {
    return {
      getPlugin: (id) => this.deps.plugins.get(id),
      rttVon: (playerId) => this.medianRttVon(playerId),
    };
  }

  private roomInfo(): RoomInfo {
    return {
      roomCode: this.code,
      joinUrl: `${this.origin}/j/${this.code}`,
      qrPath: `/api/qr?code=${this.code}`,
      gmPin: this.gmPin,
      gmLog: this.gmLog.map(({ id, ts, cmd, text }) => ({ id, ts, cmd, text })),
      jubilaeum: this.jubilaeum,
      // LOBBY (ADDITIV): Sichtbarkeit + Name für die Screen-Lobby-Anzeige.
      lobbyName: this.lobbyName,
      oeffentlich: this.oeffentlich,
    };
  }

  viewFuer(role: Role, playerId?: string): unknown {
    const ctx = { clock: this.deps.clock, rng: this.deps.rng };
    return viewFor(this.state, role, this.engineDeps(), this.roomInfo(), ctx, playerId);
  }

  /** Aktion durch die Engine schicken; bei Erfolg committen + broadcasten. */
  applyAction(action: EngineAction): { ok: boolean; error?: string } {
    const ctx = { clock: this.deps.clock, rng: this.deps.rng };
    const result = engine.reduce(this.state, action, this.engineDeps(), ctx);
    if (result.error) return { ok: false, error: result.error };
    this.commit(result.state, result.events);
    return { ok: true };
  }

  /** Buzz (TECH-SPEC §3.3): Median-RTT-Clamp HIER, dann als Plugin-Action weiter. */
  applyBuzz(playerId: string, msg: BuzzMsg): { ok: boolean; error?: string } {
    const now = this.deps.clock.now();
    const finalAt = clampBuzz({
      pressedAtServerEst: msg.pressedAtServerEst,
      receiveTime: now,
      medianRtt: this.medianRttVon(playerId),
    });
    return this.applyAction({
      type: "playerAction",
      playerId,
      minigameId: msg.minigameId,
      action: { type: "buzz", finalAt },
      atServerTime: now,
    });
  }

  /** Gespielte Fragen ins Abend-Gedächtnis übernehmen (Recycle-Klone `id~n`
   * zählen für ihre Basis-Frage); älteste Einträge fallen LRU-artig raus. */
  private merkeAbendFragen(ids: readonly string[]): void {
    const bekannt = new Set(this.abendFragenIds);
    for (const id of ids) {
      const basis = id.split("~")[0];
      if (!bekannt.has(basis)) {
        bekannt.add(basis);
        this.abendFragenIds.push(basis);
      }
    }
    const zuViel = this.abendFragenIds.length - ABEND_GEDAECHTNIS_MAX;
    if (zuViel > 0) this.abendFragenIds.splice(0, zuViel);
  }

  /** Frische Fragen ziehen (Abend-Gedächtnis respektiert), bei Mangel per
   * Top-Up mit Wiederholungen auffüllen — Match-intern bleibt alles eindeutig. */
  private ziehefragen(anzahl: number, imMatch: string[], typen?: PlanFrageTyp[]): Question[] {
    const frisch = this.deps.contentLoader.pickQuestions({
      anzahl,
      typen,
      usedQuestionIds: [...this.abendFragenIds, ...imMatch],
      rng: this.deps.rng,
    });
    imMatch.push(...frisch.map((q) => q.id));
    if (frisch.length >= anzahl) return frisch;
    // Kleines Pack / langer Abend: Rest MIT Abend-Wiederholungen auffüllen
    // (Id-Filter schützt gegen Loader, die usedQuestionIds ignorieren).
    const imMatchSet = new Set(imMatch);
    const topUp = this.deps.contentLoader
      .pickQuestions({
        anzahl: anzahl - frisch.length,
        typen,
        usedQuestionIds: imMatch,
        rng: this.deps.rng,
      })
      .filter((q) => !imMatchSet.has(q.id));
    imMatch.push(...topUp.map((q) => q.id));
    return [...frisch, ...topUp];
  }

  /** Match starten: Fragen-Pool über den Content-Loader ziehen (gekapselt!). */
  startMatch(): { ok: boolean; error?: string } {
    // Abend-Gedächtnis (Welle 1): die Fragen des VORIGEN Matches jetzt einsammeln.
    this.merkeAbendFragen(this.state.usedQuestionIds);
    const imMatch: string[] = [];
    // Großzügiger Pool: die Engine wählt daraus nach Plan (Rest bleibt ungenutzt).
    const fragenPool = this.ziehefragen(Math.max(this.deps.fragenProMatch, 120), imMatch);
    // Format-gebundene Typen GARANTIERT beimischen: der Zufalls-Pool enthält
    // sonst oft zu wenige — Pixel-Dschungel soll echte Bilder zeigen, der
    // Bananen-Tresor echte schaetz- und die Affenleiter echte sortier-Fragen
    // (statt der eingebauten Fallback-Pools; engine/plan.ts passtFrageZuFormat).
    const extraFragen: Question[] = [];
    for (const [typ, anzahl] of [
      ["bild_pixel", 12],
      ["schaetz", 10],
      ["sortier", 10],
    ] as const) {
      extraFragen.push(...this.ziehefragen(anzahl, imMatch, [typ]));
    }
    // ADDITIV (Musik): Song-Pool ziehen (ohne Region-Filter — wie der
    // Fragen-Pool; Regler kommt ggf. später über die Settings). Ohne Songs
    // filtert alleFuer die contentKind-"songs"-Formate aus der Playlist
    // (registry.allePluginsFuer, Fallback: plan.aufloesen).
    const songsPool = this.deps.contentLoader.pickSongs?.({ anzahl: 24, rng: this.deps.rng }) ?? [];
    const verfuegbar =
      this.deps.plugins.alleFuer?.({
        songsVerfuegbar: songsPool.length > 0,
        // Stummfilm-Studio-Gate: erst ab meta.minVideoSongs (3) Video-Songs
        // erscheint das Format in der Playlist (sonst plan.aufloesen-Fallback).
        videoSongs: zaehleVideoSongs(songsPool),
      }) ?? this.deps.plugins.alle();
    const result = this.applyAction({
      type: "start",
      matchId: this.matchId,
      fragenPool: [...fragenPool, ...extraFragen],
      verfuegbareMinigames: verfuegbar,
      songsPool,
      // Team-Auto-Balance (§1.4): Lifetime-AT der Profil-Spieler als Stärke.
      staerke: Object.fromEntries(this.profilStaerken),
    });
    // v2 Jubiläums-Erkennung: NACH erfolgreichem Start (kein Meilenstein wird
    // durch einen fehlgeschlagenen Start „verbrannt") — dann frisch broadcasten.
    if (result.ok && this.deps.meta) {
      this.jubilaeum = this.deps.meta.matchGestartet(this);
      if (this.jubilaeum !== null) this.broadcastSnapshots();
    }
    return result;
  }

  /** Tick-System: von der globalen Schleife alle ~250 ms aufgerufen. */
  tick(): void {
    const ctx = { clock: this.deps.clock, rng: this.deps.rng };
    const vorher = this.state;
    const result = engine.tick(this.state, this.engineDeps(), ctx);
    if (result.state === vorher && result.events.length === 0) return;
    // View-dirty-Check (Wunsch der Minispiel-Agents): tick-getriebene
    // minigameState-Änderungen (Stinkbananen-Weitergabe, Pixel-Stufen, Sack-Ticks)
    // committen OHNE Events — ohne Broadcast kämen sie nie live bei den Clients an.
    const tickSichtbar =
      result.events.length === 0 && this.minigameViewGeaendert(vorher, result.state);
    this.commit(result.state, result.events);
    if (tickSichtbar) this.broadcastSnapshots();
  }

  /** Hat sich der SICHTBARE Minigame-View (Screen oder irgendein Spieler) geändert? */
  private minigameViewGeaendert(vorher: EngineState, nachher: EngineState): boolean {
    if (vorher.minigameState === nachher.minigameState) return false;
    if (!nachher.minigameId || vorher.minigameId !== nachher.minigameId) return true;
    const plugin = this.deps.plugins.get(nachher.minigameId);
    const gleich = (role: Role, playerId?: string): boolean =>
      JSON.stringify(plugin.viewFor(vorher.minigameState, role, playerId as never)) ===
      JSON.stringify(plugin.viewFor(nachher.minigameState, role, playerId as never));
    if (!gleich("screen")) return true;
    return nachher.order.some((id) => !gleich("player", id));
  }

  gmLogEintrag(cmd: string, args: Record<string, unknown>, text: string): GmLogEntry {
    const entry: GmLogEntry = {
      id: `log_${randomUUID().slice(0, 8)}`,
      ts: this.deps.clock.now(),
      cmd,
      args,
      text,
    };
    this.gmLog.push(entry);
    if (this.gmLog.length > 100) this.gmLog.shift();
    this.log.append(this.seq, { type: "gm_command", payload: { cmd, args, text } });
    for (const client of this.clients.values()) {
      if (client.role === "gm") client.socket.emit("gm.log", { entry });
    }
    return entry;
  }

  // ---------- Sync: Snapshot + Events mit Sequenznummern ----------

  private commit(neuerState: EngineState, events: EngineEvent[]): void {
    this.state = neuerState;
    this.seq += 1;
    for (const event of events) this.log.append(this.seq, toLogEvent(event));
    // META-Hook: Match vorbei ⇒ AT-Buchung pro gebundenem Profil (idempotent).
    if (events.some((e) => e.type === "match_ended")) this.deps.meta?.matchBeendet(this);

    const deltas = alsDeltas(events, this.state, this.deps);
    if (deltas !== null && deltas.length > 0) {
      // Kleines Delta im Normalbetrieb (view.event) — Client mit Lücke fordert Snapshot.
      for (const client of this.clients.values()) {
        for (const delta of deltas)
          client.socket.emit("view.event", { seq: this.seq, event: delta });
      }
    } else if (deltas === null) {
      this.broadcastSnapshots();
    }
    // deltas === [] ⇒ reiner State-Fortschritt ohne sichtbare Änderung: nichts senden.
  }

  broadcastSnapshots(): void {
    for (const client of this.clients.values()) this.sendSnapshot(client);
  }

  sendSnapshot(client: RoomClient): void {
    client.socket.emit("view.snapshot", {
      seq: this.seq,
      view: this.viewFuer(client.role, client.playerId ?? undefined),
    });
  }

  broadcastRoomClosed(reason: "ttl" | "gm-ende"): void {
    for (const client of this.clients.values()) {
      client.socket.emit("room.closed", { reason });
    }
  }
}

/** Engine-Event → JSONL-Zeile (Schema TECH-SPEC §5.3). */
function toLogEvent(event: EngineEvent): {
  type: string;
  actor?: string;
  questionId?: string;
  payload?: Record<string, unknown>;
} {
  const { type, ...rest } = event as { type: string } & Record<string, unknown>;
  const actor = typeof rest.playerId === "string" ? rest.playerId : undefined;
  const questionId = typeof rest.questionId === "string" ? rest.questionId : undefined;
  delete rest.playerId;
  delete rest.questionId;
  return { type, actor, questionId, payload: rest };
}

/**
 * Prüft, ob ALLE Events eines Commits als kleine Wire-Deltas gesendet werden
 * können. Sonst null ⇒ Voll-Snapshots (Phasenwechsel/neue Engine-Zustände).
 */
function alsDeltas(events: EngineEvent[], state: EngineState, deps: RoomDeps): ViewEvent[] | null {
  if (events.length === 0) return [];
  const deltas: ViewEvent[] = [];
  for (const event of events) {
    if (event.type === "presence") {
      deltas.push({
        type: "presence",
        playerId: event.playerId,
        connected: event.connected,
        graceUntil: event.graceUntil,
      });
    } else if (event.type === "answer_submitted" && state.minigameId) {
      const view = deps.plugins.get(state.minigameId).viewFor(state.minigameState, "screen") as {
        answeredCount?: number;
      };
      if (typeof view?.answeredCount !== "number") return null;
      deltas.push({ type: "answered", count: view.answeredCount, playerId: event.playerId });
    } else if (event.type === "timer_extended" && state.phase === "frage" && state.minigameId) {
      const view = deps.plugins.get(state.minigameId).viewFor(state.minigameState, "screen") as {
        endsAt?: number;
      };
      if (typeof view?.endsAt !== "number") return null;
      deltas.push({ type: "timer", endsAt: view.endsAt });
    } else if (event.type === "shake_tap") {
      // v2 Sudden-Death: Tap-Stände als leichte Deltas (bis zu 8×4 Batches/s —
      // Voll-Snapshots an alle wären hier reine Verschwendung).
      deltas.push({ type: "shake", playerId: event.playerId, taps: event.taps });
    } else {
      return null; // großer Wechsel ⇒ Snapshot an alle
    }
  }
  return deltas;
}

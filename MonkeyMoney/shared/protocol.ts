// Nachrichten-Katalog (TECH-SPEC §3.1) — implementierter Kern des Walking Skeletons.
// Grundmodell: Snapshot + Events mit Sequenznummern; Filterung IMMER serverseitig.
import { z } from "zod";

// ---------- Grenzen & Konstanten ----------
export const MIN_SPIELER = 2;
export const MAX_SPIELER = 8;
export const GRACE_MS = 180_000; // Disconnect ≠ Rauswurf (TECH-SPEC §3.2)
export const RAUM_TTL_MS = 30 * 60_000; // leerer Raum → Timeout-Abbau
/** Phase „ende" + niemand mehr verbunden ⇒ Slot nach 2 min freigeben
 * (Eval-7 P2: Ende-Räume belegten max-rooms-Slots volle 30 min). */
export const ENDE_RAUM_TTL_MS = 2 * 60_000;
export const PING_INTERVALL_MS = 5_000; // time.ping ~alle 5 s
export const SPAETANTWORT_GNADE_MS = 400; // Gnadenfenster nach Timer-Ende

// ---------- C→S ----------
export const RoomCreateSchema = z.object({
  role: z.enum(["screen", "gm"]),
  origin: z.string(), // QR-URL basiert auf der Screen-Origin (Tunnel vs. LAN)
  // ---------- LOBBY (ADDITIV): öffentlicher Lobby-Browser (Opt-in!) ----------
  /** true = im öffentlichen Lobby-Browser sichtbar — Default PRIVAT (nur Code). */
  oeffentlich: z.boolean().optional(),
  /** Anzeige-Name der Lobby (Auto: „Bananen-Bande #CODE", editierbar). */
  name: z.string().max(64).optional(),
});

/** LOBBY (ADDITIV) — room.config: Screen des Raums oder aktiver GM ändern
 * Sichtbarkeit/Name nachträglich (Namens-Moderation macht der Server). */
export const RoomConfigSchema = z.object({
  oeffentlich: z.boolean().optional(),
  name: z.string().max(64).optional(),
});

export const HelloSchema = z.object({
  roomCode: z.string().length(4),
  role: z.enum(["screen", "player", "gm"]),
  sessionToken: z.string().optional(), // Rejoin: Slot-Restore
  name: z.string().min(1).max(24).optional(),
  avatar: z.string().optional(),
  gmPin: z.string().optional(), // GM verlangt PIN (auf dem Screen angezeigt)
  origin: z.string().optional(),
  // ---------- META (ADDITIV, §7.1): Join MIT Profil statt als Gast ----------
  profileId: z.string().optional(),
  profilPin: z.string().max(8).optional(), // 4-stellige Profil-PIN (falls gesetzt)
  deviceToken: z.string().max(64).optional(), // Geräte-Wiedererkennung
});

export const TimePingSchema = z.object({ t0: z.number() });

export const PlayerActionSchema = z.object({
  minigameId: z.string(),
  actionId: z.string(),
  payload: z.unknown(),
  idemKey: z.string(), // macht Netz-Retries idempotent (Doppel-Tap-Schutz)
});

export const GmCmdSchema = z.object({
  cmd: z.string(),
  args: z.record(z.unknown()).default({}),
  cmdId: z.string(),
});

/** GM-Takeover: Beobachter übernimmt das aktive Cockpit — NUR mit PIN-Bestätigung. */
export const GmTakeoverSchema = z.object({ pin: z.string() });

// ---------- C→S: Engine-Phasen-Nachrichten (ADDITIV, Engine-Ausbau) ----------

/** #9 buzz — Sonderfall von player.action mit Latenz-Kompensation (TECH-SPEC §3.3).
 * Der Server clampt pressedAtServerEst (Median-RTT-Floor) und reicht das Ergebnis
 * als PlayerAction `{type:"buzz", finalAt}` ans Minigame-Plugin weiter. */
export const BuzzSchema = z.object({
  minigameId: z.string(),
  pressedAtServerEst: z.number(),
  idemKey: z.string(),
});

/** Joker zünden (Einsatzfenster prüft der Server). stufe: nur Schmiergeld (1|2). */
export const JokerUseSchema = z.object({
  jokerId: z.string(),
  stufe: z.number().int().min(1).max(2).optional(),
  idemKey: z.string(),
});

/** Joker-Ladung nachkaufen (Preisformel + Sozialrabatt serverseitig). */
export const JokerBuySchema = z.object({
  jokerId: z.string(),
  idemKey: z.string(),
});

/** Kategorien-Wahl-Phase: Stimme für eine der angebotenen Kategorien. */
export const KategorieVoteSchema = z.object({ kategorie: z.string() });

/** GM-Voting (Publikums-Entscheid): Stimme für Option n. */
export const VoteCastSchema = z.object({ option: z.number().int().min(0) });

/** Erklärkarten-Phase: „Bereit"-Meldung oder Streik-Stimme (Minispiel-Skip §5.2). */
export const PhaseReadySchema = z.object({
  was: z.enum(["bereit", "streik"]).default("bereit"),
});

/** Rad-Interaktionen: long/short (Börsen-Roulette), umarmt, ja/nein (Kompliment). */
export const RadAktionSchema = z.object({
  wahl: z.enum(["long", "short", "umarmt", "ja", "nein"]),
});

/** Feedback-Freitext (GM-Werkzeug 14 / Abspann). */
export const FeedbackTextSchema = z.object({ text: z.string().min(1).max(280) });

/** Team-Modus (ADDITIV, GAME-DESIGN §1.4): Team-Wunsch in der Lobby-Phase.
 * Die Engine erfüllt Wünsche beim Match-Start, solange Kapazität da ist —
 * der Rest wird ausbalanciert verteilt (shared/teams.ts). */
export const TeamWahlSchema = z.object({ team: z.string().min(1).max(16) });

/** v2 Sudden-Death: Tap-Batch des Kokosnuss-Shakes (Client sammelt ~250 ms,
 * Server kappt pro Batch — mehr als 40 Taps/Batch sind physisch unplausibel). */
export const ShakeTapSchema = z.object({
  taps: z.number().int().min(1).max(40),
  idemKey: z.string(),
});

export type RoomCreate = z.infer<typeof RoomCreateSchema>;
export type Hello = z.infer<typeof HelloSchema>;
export type PlayerActionMsg = z.infer<typeof PlayerActionSchema>;
export type GmCmd = z.infer<typeof GmCmdSchema>;
export type BuzzMsg = z.infer<typeof BuzzSchema>;
export type JokerUseMsg = z.infer<typeof JokerUseSchema>;
export type JokerBuyMsg = z.infer<typeof JokerBuySchema>;

// ---------- S→C ----------
export interface Welcome {
  playerId: string | null; // null für Screen (tokenlos)
  sessionToken: string | null;
  roomCode: string;
  gmPin?: string; // nur an Screen (Anzeige) und GM
  seq: number;
  view: unknown; // Voll-Snapshot der Rolle
  serverTime: number;
  /** GM: true = ein anderes Cockpit ist bereits aktiv → Beobachter-Modus
   * (Kommandos gesperrt; Übernahme nur via gm.takeover mit PIN). */
  gmBeobachter?: boolean;
}

/** S→C gm.status: aktiver GM gewechselt (Beobachter-Flag DIESES Sockets). */
export interface GmStatusMsg {
  beobachter: boolean;
}

export interface ViewSnapshot {
  seq: number;
  view: unknown;
}

/** Kleine Deltas im Normalbetrieb; unbekannter Typ oder seq-Lücke ⇒ sync.request. */
export type ViewEvent =
  | { type: "presence"; playerId: string; connected: boolean; graceUntil?: number }
  | { type: "answered"; count: number; playerId: string }
  | { type: "timer"; endsAt: number }
  // v2 Sudden-Death: Live-Tap-Stand EINES Shakers (taps = neue Gesamtsumme).
  | { type: "shake"; playerId: string; taps: number };

export interface ViewEventMsg {
  seq: number;
  event: ViewEvent;
}

export interface TimePong {
  t0: number;
  serverTime: number;
}

export interface GmAck {
  cmdId: string;
  ok: boolean;
  error?: string;
}

export interface GmLogEntry {
  id: string;
  ts: number;
  cmd: string;
  args: Record<string, unknown>;
  text: string; // menschenlesbare Zeile fürs Aktions-Log
}

export interface RoomClosed {
  reason: "ttl" | "gm-ende";
}

// ---------- LOBBY (ADDITIV): öffentlicher Lobby-Browser + Schnell-Beitritt ----------

/** Eine öffentliche Lobby im Browser auf der Landing (GET /api/lobbys +
 * S→C lobby.update). Nur status "lobby" ist joinbar — Zuschauer-Beitritt zu
 * laufenden Matches kennt das Protokoll (Rollen screen/player/gm) nicht. */
export interface LobbyInfo {
  code: string;
  name: string;
  spieler: number;
  max: number;
  modus: string;
  status: "lobby" | "laeuft";
}

/** S→C lobby.update — Live-Liste für abonnierte Landing-Clients. */
export interface LobbyUpdateMsg {
  lobbys: LobbyInfo[];
}

// ---------- INTERNET-LINK (ADDITIV): Cloudflare-Quick-Tunnel aus der App-UI ----------

/** Zustands-Maschine des Server-Tunnels (server/core/tunnel.ts):
 * aus → startet → laeuft(url) → aus | fehler; "nicht-installiert" = cloudflared
 * fehlt auf dem Server-PC (klare Meldung + Install-Einzeiler statt Fehler). */
export type TunnelPhase = "aus" | "startet" | "laeuft" | "fehler" | "nicht-installiert";

/** S→C tunnel.status — an Screen + GM (Broadcast bei jedem Übergang + beim hello). */
export interface TunnelStatusMsg {
  phase: TunnelPhase;
  /** Öffentliche https://….trycloudflare.com-URL — nur in phase "laeuft". */
  url: string | null;
  /** Menschenlesbare Meldung (phase "fehler"/"nicht-installiert"). */
  fehler: string | null;
  /** Install-Einzeiler je OS (nur "nicht-installiert", Server-OS zuerst). */
  installHinweise: string[];
}

// ---------- Fehler-Codes für hello/room.create-ACKs ----------
export type JoinFehler =
  | "raum-nicht-gefunden"
  | "raum-voll"
  | "match-laeuft"
  | "gm-pin-falsch"
  | "name-fehlt"
  | "max-rooms";

// ---------- Wire-Namen der neuen C→S-Nachrichten (Engine-Ausbau, ADDITIV) ----------
// "buzz"          → BuzzSchema           (ACK {ok, error?})
// "joker.use"     → JokerUseSchema       (ACK {ok, error?})
// "joker.buy"     → JokerBuySchema       (ACK {ok, error?})
// "kategorie.vote"→ KategorieVoteSchema  (ACK {ok, error?})
// "vote.cast"     → VoteCastSchema       (ACK {ok, error?})
// "phase.ready"   → PhaseReadySchema     (ACK {ok, error?})
// "rad.aktion"    → RadAktionSchema      (ACK {ok, error?})
// "feedback.text" → FeedbackTextSchema   (ACK {ok, error?})
// "shake.tap"     → ShakeTapSchema       (ACK {ok, error?}) — v2 Sudden-Death
// "team.wahl"     → TeamWahlSchema       (ACK {ok, error?}) — Team-Wunsch (Lobby)
// S→C "time.probe" {t} — Client echot SOFORT dasselbe Payload zurück (Server
// misst daraus den Median-RTT pro Spieler für die Buzzer-Kompensation).
// ---------- LOBBY (ADDITIV) ----------
// "room.config"      → RoomConfigSchema  (ACK {ok, error?}) — Screen/aktiver GM
// "lobby.subscribe"  → {}                (S→C lobby.update sofort + bei Änderung)
// "lobby.unsubscribe"→ {}
// S→C "lobby.update" → LobbyUpdateMsg {lobbys} — nur an Abonnenten (Landing)
// ---------- INTERNET-LINK (ADDITIV) ----------
// "tunnel.start"     → {} (ACK {ok, status?, error?}) — nur Screen/aktiver GM
// "tunnel.stop"      → {} (ACK {ok, status?, error?}) — nur Screen/aktiver GM
// S→C "tunnel.status"→ TunnelStatusMsg — an Screen+GM (Broadcast + beim hello)

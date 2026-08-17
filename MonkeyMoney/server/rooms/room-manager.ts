// Raum-Lebenszyklus: Erzeugen (kollisionsfreier Code), Nachschlagen, TTL-Abbau
// (leer → Timeout), Persistenz der Raum-Metadaten (meta/rooms.json, atomar).
import { ENDE_RAUM_TTL_MS, RAUM_TTL_MS, type LobbyInfo } from "../../shared/protocol";
import type { Rng } from "../../shared/rng";
import type { Clock } from "../../shared/time";
import type { Storage } from "../persistence/storage";
import { generiereRaumCode, istGueltigerCode } from "./codes";
import { autoRaumName, normalisiereRaumName, oeffentlicheLobbys } from "./lobby";
import { Room, type RoomDeps } from "./room";

export interface RoomManagerOptions {
  maxRooms: number;
  ttlMs?: number;
}

export class RoomManager {
  private readonly rooms = new Map<string, Room>();
  private readonly deps: RoomDeps;
  private readonly maxRooms: number;
  private readonly ttlMs: number;

  constructor(deps: RoomDeps, options: RoomManagerOptions) {
    this.deps = deps;
    this.maxRooms = options.maxRooms;
    this.ttlMs = options.ttlMs ?? RAUM_TTL_MS;
  }

  get clock(): Clock {
    return this.deps.clock;
  }

  get rng(): Rng {
    return this.deps.rng;
  }

  get storage(): Storage {
    return this.deps.storage;
  }

  get anzahl(): number {
    return this.rooms.size;
  }

  erzeugeRaum(origin: string, lobby?: { oeffentlich?: boolean; name?: string }): Room | null {
    if (this.rooms.size >= this.maxRooms) return null;
    const code = generiereRaumCode(this.deps.rng, new Set(this.rooms.keys()));
    const room = new Room(code, origin, this.deps);
    // LOBBY (ADDITIV): Sichtbarkeit ist Opt-in — Default bleibt PRIVAT (nur Code).
    if (lobby?.oeffentlich === true) room.oeffentlich = true;
    if (lobby?.name !== undefined) room.lobbyName = normalisiereRaumName(lobby.name, code);
    this.rooms.set(code, room);
    void this.persistiereMeta();
    return room;
  }

  // ---------- LOBBY (ADDITIV): öffentlicher Lobby-Browser + Schnell-Beitritt ----------

  /** Öffentliche Lobby-Liste (Sichtbarkeits-Filter + tote Lobbys raus). */
  lobbyListe(): LobbyInfo[] {
    return oeffentlicheLobbys(
      [...this.rooms.values()].map((r) => ({
        code: r.code,
        name: r.lobbyName,
        oeffentlich: r.oeffentlich,
        phase: r.state.phase,
        spieler: r.state.order.length,
        clientCount: r.clientCount,
        modus: r.state.settings.modus,
      })),
    );
  }

  /** Sichtbarkeit/Name ändern (room.config vom Screen oder aktiven GM). */
  setzeLobbyEinstellungen(room: Room, patch: { oeffentlich?: boolean; name?: string }): void {
    if (patch.oeffentlich !== undefined) room.oeffentlich = patch.oeffentlich;
    if (patch.name !== undefined) room.lobbyName = normalisiereRaumName(patch.name, room.code);
    void this.persistiereMeta();
    // Screen-Lobby zeigt Name/Sichtbarkeit an ⇒ frische Snapshots an den Raum.
    room.broadcastSnapshots();
  }

  finde(code: string): Room | null {
    const normalisiert = code.toUpperCase();
    if (!istGueltigerCode(normalisiert)) return null;
    return this.rooms.get(normalisiert) ?? null;
  }

  /** Tick-Schleife: Engine-Ticks + Bot-Ticks + TTL-Abbau leerer Räume.
   * Räume in Phase „ende" ohne Clients fliegen schon nach 2 min (Eval-7 P2:
   * Ende-Räume belegten max-rooms-Slots sonst die vollen 30 min). */
  tickAlle(): void {
    const now = this.deps.clock.now();
    for (const room of this.rooms.values()) {
      room.tick();
      this.deps.meta?.botTick(room);
      this.deps.meta?.autosaveTick?.(room);
      if (room.clientCount === 0 && room.emptySince !== null) {
        const ttl =
          room.state.phase === "ende" ? Math.min(ENDE_RAUM_TTL_MS, this.ttlMs) : this.ttlMs;
        if (now - room.emptySince > ttl) this.schliesseRaum(room, "ttl");
      }
    }
  }

  /** Boot-Wiederbelebung: frisch erzeugten Raum STILL entfernen (kein
   * Close-Hook/Broadcast) — z. B. wenn die Umschlüsselung kollidiert. */
  verwerfeRaum(room: Room): void {
    this.rooms.delete(room.code);
    void this.persistiereMeta();
  }

  schliesseRaum(room: Room, reason: "ttl" | "gm-ende"): void {
    // Autosave vor dem Abbau (Meta-Hook): laufende Matches überleben den TTL.
    this.deps.meta?.raumSchliesst(room, reason);
    this.rooms.delete(room.code);
    void this.persistiereMeta();
    // Broadcast an eventuell noch hängende Sockets (bei TTL normalerweise leer).
    room.broadcastRoomClosed(reason);
  }

  /**
   * META (Save/Load): Raum auf den Code aus der Save-Datei umschlüsseln —
   * Spieler behalten ihre Join-URL (/j/CODE) UND ihre localStorage-Token
   * (Schlüssel mm:CODE). Kollision mit fremdem Raum ⇒ Fehler.
   */
  schluessleUm(room: Room, neuerCode: string): { ok: boolean; error?: string } {
    const code = neuerCode.toUpperCase();
    if (code === room.code) return { ok: true };
    const belegt = this.rooms.get(code);
    if (belegt !== undefined && belegt !== room) return { ok: false, error: "code-belegt" };
    this.rooms.delete(room.code);
    // Unangetasteter Auto-Name wandert mit auf den neuen Code (Save-Load-Re-Key).
    if (room.lobbyName === autoRaumName(room.code)) room.lobbyName = autoRaumName(code);
    room.code = code;
    this.rooms.set(code, room);
    void this.persistiereMeta();
    return { ok: true };
  }

  /** meta/rooms.json — Grundlage für TTL-Wiederbelebung nach Server-Neustart (TODO). */
  private async persistiereMeta(): Promise<void> {
    const daten = {
      schemaVersion: 1,
      rooms: [...this.rooms.values()].map((r) => ({
        code: r.code,
        matchId: r.matchId,
        createdAt: r.createdAt,
        // LOBBY (ADDITIV): Sichtbarkeit + Name überleben in meta/rooms.json.
        lobbyName: r.lobbyName,
        oeffentlich: r.oeffentlich,
      })),
    };
    try {
      await this.deps.storage.writeJsonAtomic("meta/rooms.json", daten);
    } catch (err) {
      console.error("meta/rooms.json konnte nicht geschrieben werden:", err);
    }
  }
}

// Öffentlicher Lobby-Browser + Schnell-Beitritt („Matchmaking light") — PURE
// Logik ohne Raum-Interna: Sichtbarkeits-Filter, Status-Mapping, Namens-
// Moderation und die Auswahl-Regel „vollste offene Lobby zuerst". Der
// RoomManager füttert LobbyRaumBlick-Zeilen, HTTP/Socket liefern nur aus.
import { MAX_SPIELER, type LobbyInfo } from "../../shared/protocol";
import type { Clock } from "../../shared/time";

/** Namens-Moderation (minimal): Längen-Limit + kein Leerstring. */
export const RAUM_NAME_MAX = 32;

/** Auto-Name eines frischen Raums — editierbar (room.config). */
export function autoRaumName(code: string): string {
  return `Bananen-Bande #${code}`;
}

/**
 * Raum-Namen normalisieren: trimmen, Mehrfach-Leerzeichen zusammenziehen,
 * auf RAUM_NAME_MAX kappen. Leer/nur-Whitespace ⇒ zurück zum Auto-Namen.
 */
export function normalisiereRaumName(roh: string, code: string): string {
  const sauber = roh.replace(/\s+/g, " ").trim().slice(0, RAUM_NAME_MAX).trim();
  return sauber.length === 0 ? autoRaumName(code) : sauber;
}

/** Der schmale Blick auf einen Raum, den die Lobby-Logik braucht. */
export interface LobbyRaumBlick {
  code: string;
  name: string;
  oeffentlich: boolean;
  /** Engine-Phase ("lobby" = joinbar, alles andere = läuft). */
  phase: string;
  /** Spieler-Slots (state.order) — NICHT Sockets. */
  spieler: number;
  /** Verbundene Sockets (Screen + Spieler + GM): 0 ⇒ tote Lobby. */
  clientCount: number;
  modus: string;
}

/**
 * Öffentliche Lobby-Liste: nur Opt-in-Räume, tote (0 verbundene Clients)
 * fliegen sofort raus — der TTL-Abbau räumt sie später endgültig weg.
 * Sortierung: joinbare zuerst, darin die vollsten oben (Schnell-Beitritt-Logik
 * und Anzeige teilen sich EINE Reihenfolge).
 */
export function oeffentlicheLobbys(raeume: LobbyRaumBlick[]): LobbyInfo[] {
  return raeume
    .filter((r) => r.oeffentlich && r.clientCount > 0)
    .map((r): LobbyInfo => ({
      code: r.code,
      name: r.name,
      spieler: r.spieler,
      max: MAX_SPIELER,
      modus: r.modus,
      status: r.phase === "lobby" ? "lobby" : "laeuft",
    }))
    .sort((a, b) => {
      if (a.status !== b.status) return a.status === "lobby" ? -1 : 1;
      if (a.spieler !== b.spieler) return b.spieler - a.spieler;
      return a.code.localeCompare(b.code);
    });
}

/**
 * Schnell-Beitritt: die VOLLSTE offene öffentliche Lobby mit freiem Platz
 * (< MAX_SPIELER). Läuft-Status und volle Räume sind tabu; nichts frei ⇒ null.
 */
export function waehleSchnellBeitritt(lobbys: LobbyInfo[]): LobbyInfo | null {
  let beste: LobbyInfo | null = null;
  for (const lobby of lobbys) {
    if (lobby.status !== "lobby" || lobby.spieler >= lobby.max) continue;
    if (beste === null || lobby.spieler > beste.spieler) beste = lobby;
  }
  return beste;
}

/** GET /api/lobbys wird 2 s gecacht — Landing-Polls kosten den Server nichts. */
export const LOBBY_CACHE_MS = 2_000;

/**
 * Kleiner TTL-Cache um eine Lobby-Listen-Quelle (injizierte Clock — testbar).
 */
export function erzeugeLobbyCache(
  hole: () => LobbyInfo[],
  clock: Clock,
  ttlMs: number = LOBBY_CACHE_MS,
): () => LobbyInfo[] {
  let stand: LobbyInfo[] | null = null;
  let geholtAt = 0;
  return () => {
    const now = clock.now();
    if (stand === null || now - geholtAt >= ttlMs) {
      stand = hole();
      geholtAt = now;
    }
    return stand;
  };
}

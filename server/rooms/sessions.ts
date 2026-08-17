// Sessions: Token ↔ Slot. Der Token (UUID) geht im welcome an den Client
// (localStorage) und stellt beim Rejoin Rolle + Spieler-Slot wieder her.
import { randomUUID } from "node:crypto";
import type { Role } from "../../shared/ids";

export interface Session {
  token: string;
  role: Role;
  playerId: string | null; // null für GM (kein Spieler-Slot)
}

export interface SessionStore {
  erstelle(role: Role, playerId: string | null): Session;
  /** Slot-Restore beim Rejoin; null bei unbekanntem Token. */
  restore(token: string): Session | null;
  /** ADDITIV (Save/Load): alle Sessions exportieren (wandern in die Save-Datei). */
  alle(): Session[];
  /** ADDITIV (Save/Load): Sessions aus einer Save-Datei übernehmen. */
  importiere(sessions: Session[]): void;
}

export function createSessionStore(tokenFactory: () => string = randomUUID): SessionStore {
  const sessions = new Map<string, Session>();
  return {
    erstelle(role: Role, playerId: string | null): Session {
      const session: Session = { token: tokenFactory(), role, playerId };
      sessions.set(session.token, session);
      return session;
    },
    restore(token: string): Session | null {
      return sessions.get(token) ?? null;
    },
    alle(): Session[] {
      return [...sessions.values()].map((s) => ({ ...s }));
    },
    importiere(neue: Session[]): void {
      for (const s of neue) sessions.set(s.token, { ...s });
    },
  };
}

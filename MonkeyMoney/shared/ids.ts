// Branded Types für IDs — verhindert, dass ein RoomCode als PlayerId durchrutscht.
export type PlayerId = string & { readonly __brand: "PlayerId" };
export type RoomCode = string & { readonly __brand: "RoomCode" };
export type MatchId = string & { readonly __brand: "MatchId" };
export type SessionToken = string & { readonly __brand: "SessionToken" };

export const asPlayerId = (s: string): PlayerId => s as PlayerId;
export const asRoomCode = (s: string): RoomCode => s.toUpperCase() as RoomCode;
export const asMatchId = (s: string): MatchId => s as MatchId;
export const asSessionToken = (s: string): SessionToken => s as SessionToken;

/** Rollen pro Verbindung — Rollenwechsel = neuer hello (TECH-SPEC §3.1). */
export type Role = "screen" | "player" | "gm";

/** Die 8 Avatar-Farben (1-Tap-Auswahl beim Join). */
export const AVATAR_FARBEN = [
  "gelb",
  "rot",
  "gruen",
  "blau",
  "lila",
  "orange",
  "tuerkis",
  "pink",
] as const;
export type AvatarFarbe = (typeof AVATAR_FARBEN)[number];

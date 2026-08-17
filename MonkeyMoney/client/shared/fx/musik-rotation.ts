// Musik-Rotation (Musik-Welle 3): die Show spielt pro Phase nicht mehr EINEN
// fixen MacLeod-Track, sondern rotiert durch eine PLAYLIST — Standard-Betten
// plus alle Bett-Loops des Users (import.mjs --bett, GET /api/musik/betten).
// Phasen-Zuordnung: Lobby-Ebene = chillige Loops, Runden-Ebene = upbeat;
// der MacLeod-Kern bleibt IMMER der Default (erster Track jeder Ebene).
// Determinismus: die Reihenfolge wird pro Match aus dem Raum-Code geseedet
// (Mulberry32, Rng-Disziplin — kein Math.random), die Rotation läuft dann
// sequenziell durch — dadurch ist „kein Track 2× hintereinander" garantiert,
// sobald eine Ebene mehr als einen Track hat.
// WICHTIG: die MUSIK_STUMME_FORMATE-Logik (Blitz-DJ & Co. = Bett stumm) lebt
// ÜBER der Rotation — die Regie liefert dann Ebene null, und null spielt
// nichts, egal was in der Playlist steht (regie.musikEbene bleibt der Boss).
import type { BettTrack } from "../../../shared/songs";
import { createRng } from "../../../shared/rng";
import { MUSIK } from "./sound-map";

/** Ein Track der Rotation (Standard-Bett oder User-Bett-Loop). */
export interface RotationsTrack {
  id: string;
  titel: string;
  artist: string;
  url: string;
}

/** Was das Sound-System pro Ebene wissen muss: Track + darf er loopen?
 * (loop nur bei 1-Track-Playlists — sonst schaltet das Ende weiter). */
export interface BettQuelle {
  trackFuer(ebene: string): (RotationsTrack & { loop: boolean }) | null;
  weiter(ebene: string): void;
}

/** Die 6 festen MacLeod-Betten (CC BY 4.0) mit Credits-Metadaten — Titel und
 * Artist speisen den Track-Ticker (Credits-Pflicht, charmant gelöst). */
export const STANDARD_BETTEN: Record<string, RotationsTrack> = {
  lobby: {
    id: "std_lobby",
    titel: "Monkeys Spinning Monkeys",
    artist: "Kevin MacLeod",
    url: MUSIK.lobby,
  },
  runde: { id: "std_runde", titel: "Quirky Dog", artist: "Kevin MacLeod", url: MUSIK.runde },
  schleich: {
    id: "std_schleich",
    titel: "Sneaky Snitch",
    artist: "Kevin MacLeod",
    url: MUSIK.schleich,
  },
  rad: { id: "std_rad", titel: "Merry Go", artist: "Kevin MacLeod", url: MUSIK.rad },
  news: {
    id: "std_news",
    titel: "Local Forecast — Elevator",
    artist: "Kevin MacLeod",
    url: MUSIK.news,
  },
  erklaer: {
    id: "std_erklaer",
    titel: "Fluffing a Duck",
    artist: "Kevin MacLeod",
    url: MUSIK.erklaer,
  },
};

/** Raum-Code → Rotations-Seed (djb2 wie shared/songs.ts#songFrageId — pro
 * Match/Raum deterministisch, über Reconnects hinweg stabil). */
export function seedAusRaumCode(roomCode: string): number {
  let h = 5381;
  for (let i = 0; i < roomCode.length; i++) {
    h = (Math.imul(h, 33) ^ roomCode.charCodeAt(i)) >>> 0;
  }
  return h;
}

/** Playlisten je Ebene bauen: MacLeod-Kern zuerst (Default!), dahinter die
 * User-Bett-Loops in geseedeter Reihenfolge (chillig → Lobby, upbeat → Runde). */
export function bauePlaylists(
  seed: number,
  betten: readonly BettTrack[],
): Record<string, RotationsTrack[]> {
  const rng = createRng(seed);
  const mische = (liste: BettTrack[]): BettTrack[] => {
    const kopie = [...liste];
    for (let i = kopie.length - 1; i > 0; i--) {
      const j = rng.int(i + 1);
      [kopie[i], kopie[j]] = [kopie[j], kopie[i]];
    }
    return kopie;
  };
  const chillig = mische(betten.filter((b) => b.stimmung === "chillig"));
  const upbeat = mische(betten.filter((b) => b.stimmung === "upbeat"));
  return {
    lobby: [STANDARD_BETTEN.lobby, ...chillig],
    runde: [STANDARD_BETTEN.runde, ...upbeat],
    // Charakter-Ebenen bleiben 1-Track-Loops: Schleich-Klassiker, Rad-Orgel,
    // Börsen-News, Erklär-Gedudel sind BEWUSST wiedererkennbare Signale.
    schleich: [STANDARD_BETTEN.schleich],
    rad: [STANDARD_BETTEN.rad],
    news: [STANDARD_BETTEN.news],
    erklaer: [STANDARD_BETTEN.erklaer],
  };
}

export interface MusikRotation extends BettQuelle {
  /** Playlist einer Ebene (fürs GM-Cockpit/Debug — Kopie, nie mutieren). */
  playlist(ebene: string): RotationsTrack[];
}

/**
 * Rotation über die geseedeten Playlisten: jede Ebene merkt sich ihre
 * Position; `weiter` (Track-Ende oder Skip) schaltet sequenziell — bei > 1
 * Track kommt daher NIE derselbe Track zweimal hintereinander.
 */
export function createMusikRotation(seed: number, betten: readonly BettTrack[]): MusikRotation {
  const playlists = bauePlaylists(seed, betten);
  const position: Record<string, number> = {};
  return {
    trackFuer(ebene) {
      const liste = playlists[ebene];
      if (liste === undefined || liste.length === 0) return null;
      const track = liste[(position[ebene] ?? 0) % liste.length];
      return { ...track, loop: liste.length === 1 };
    },
    weiter(ebene) {
      const liste = playlists[ebene];
      if (liste === undefined || liste.length <= 1) return;
      position[ebene] = ((position[ebene] ?? 0) + 1) % liste.length;
    },
    playlist(ebene) {
      return [...(playlists[ebene] ?? [])];
    },
  };
}

// Save/Load-Slots (TECH-SPEC §5 / ARCHITEKTUR „NOCH offen": Save-Serialisierung).
// Der komplette EngineState ist JSON-serialisierbar; dazu kommen rngState
// (StatefulRng), Sessions (Token ⇒ Spieler finden ihren Slot wieder), Raum-Code
// + GM-PIN (Raum läuft unter demselben Code weiter) und die Profil-Bindungen.
// Pausen-Trick: Der Save friert das Match als `paused{seit: savedAt}` ein —
// beim Laden verschiebt gm.resume ALLE Deadlines (inkl. Plugin-Timer via
// timer.shift) um exakt die verstrichene Zeit. 3 manuelle Slots + 1 Autosave.
import type { Clock } from "../../shared/time";
import type { EngineState } from "../engine/types";
import type { Session } from "../rooms/sessions";
import type { Storage } from "../persistence/storage";

export const SAVE_SLOTS = [1, 2, 3] as const;
export const AUTOSAVE_SLOT = 0;

export interface SaveDatei {
  schemaVersion: 1;
  slot: number; // 1–3 manuell, 0 = Autosave (TTL-Abbau)
  auto: boolean;
  savedAt: number;
  roomCode: string;
  gmPin: string;
  matchId: string;
  seq: number;
  engineState: EngineState;
  /** Mulberry32-Zustand des Server-Rng (null, wenn der Rng nicht stateful ist). */
  rngState: number | null;
  sessions: Session[];
  /** playerId → profileId (AT-Buchung läuft nach dem Laden korrekt weiter). */
  profilBindungen: Record<string, string>;
  /** In-Prozess-Bots (Persona-Ids) — werden nach dem Laden neu angebunden. */
  bots: { playerId: string; personaId: string }[];
}

export interface SaveSlotInfo {
  slot: number;
  auto: boolean;
  savedAt: number;
  roomCode: string;
  matchId: string;
  phase: string;
  frageNr: number;
  spieler: { name: string; avatar: string }[];
}

export interface SaveStore {
  schreibe(save: Omit<SaveDatei, "schemaVersion" | "savedAt" | "auto">): Promise<void>;
  lade(slot: number): Promise<SaveDatei | null>;
  liste(): Promise<SaveSlotInfo[]>;
  /** Crash-Schutz (Eval-7 P1): periodischer Autosave PRO Match
   * (saves/auto/<matchId>.json) — Grundlage der Boot-Wiederbelebung. */
  schreibeAutosave(save: Omit<SaveDatei, "schemaVersion" | "savedAt" | "auto">): Promise<void>;
  /** Alle Match-Autosaves (für die Boot-Wiederbelebung nach einem Crash). */
  listeAutosaves(): Promise<SaveDatei[]>;
  /** Match vorbei/Raum zu ⇒ sein Crash-Schutz-Autosave ist Geschichte. */
  loescheAutosave(matchId: string): Promise<void>;
}

const PAUSE_TEXT = "💾 Spielstand gespeichert — gleich geht's weiter!";

/** EngineState fürs Speichern einfrieren: pausiert AB savedAt (Resume-Trick). */
export function friereEin(state: EngineState, savedAt: number): EngineState {
  if (state.phase === "lobby" || state.phase === "ende") return state;
  if (state.paused !== null) return state; // GM-Pause bleibt — seit zählt weiter
  return { ...state, paused: { text: PAUSE_TEXT, seit: savedAt, bis: null } };
}

function slotPfad(slot: number): string {
  return slot === AUTOSAVE_SLOT ? "saves/autosave.json" : `saves/slot-${slot}.json`;
}

function autosavePfad(matchId: string): string {
  return `saves/auto/${matchId}.json`;
}

export function createSaveStore(storage: Storage, clock: Clock): SaveStore {
  function baueDatei(save: Omit<SaveDatei, "schemaVersion" | "savedAt" | "auto">): SaveDatei {
    const savedAt = clock.now();
    return {
      schemaVersion: 1,
      auto: save.slot === AUTOSAVE_SLOT,
      savedAt,
      ...save,
      engineState: friereEin(save.engineState, savedAt),
    };
  }

  return {
    async schreibe(save) {
      await storage.writeJsonAtomic(slotPfad(save.slot), baueDatei(save));
    },

    async schreibeAutosave(save) {
      await storage.writeJsonAtomic(autosavePfad(save.matchId), baueDatei(save));
    },

    async listeAutosaves() {
      const dateien = await storage.listeDateien("saves/auto");
      const saves: SaveDatei[] = [];
      for (const name of dateien) {
        if (!name.endsWith(".json")) continue;
        const datei = await storage.readJson<SaveDatei>(`saves/auto/${name}`);
        if (datei !== null && datei.schemaVersion === 1) saves.push(datei);
      }
      return saves;
    },

    async loescheAutosave(matchId) {
      await storage.loesche(autosavePfad(matchId));
    },

    async lade(slot) {
      const datei = await storage.readJson<SaveDatei>(slotPfad(slot));
      if (!datei || datei.schemaVersion !== 1) return null;
      return datei;
    },

    async liste() {
      const infos: SaveSlotInfo[] = [];
      for (const slot of [AUTOSAVE_SLOT, ...SAVE_SLOTS]) {
        const datei = await storage.readJson<SaveDatei>(slotPfad(slot));
        if (!datei) continue;
        infos.push({
          slot: datei.slot,
          auto: datei.auto,
          savedAt: datei.savedAt,
          roomCode: datei.roomCode,
          matchId: datei.matchId,
          phase: datei.engineState.phase,
          frageNr: datei.engineState.fragenZaehler,
          spieler: datei.engineState.order.map((id) => ({
            name: datei.engineState.players[id]?.name ?? id,
            avatar: String(datei.engineState.players[id]?.avatar ?? "gelb"),
          })),
        });
      }
      return infos;
    },
  };
}

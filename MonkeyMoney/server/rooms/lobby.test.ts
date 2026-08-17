// Lobby-Browser + Schnell-Beitritt: Sichtbarkeits-Flag (Opt-in!), Auswahl-Regel
// „vollste offene Lobby zuerst", TTL-/Tote-Lobby-Filter, Namens-Moderation und
// der 2-s-Cache von GET /api/lobbys — plus RoomManager-Integration (echte Räume).
import { beforeEach, describe, expect, it } from "vitest";
import type { Question } from "../../shared/content";
import type { LobbyInfo } from "../../shared/protocol";
import { createRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { ContentLoader, KatalogFrage } from "../content-loader/index";
import { allePlugins, getPlugin } from "../minigames/registry";
import type { Storage } from "../persistence/storage";
import {
  autoRaumName,
  erzeugeLobbyCache,
  normalisiereRaumName,
  oeffentlicheLobbys,
  waehleSchnellBeitritt,
  RAUM_NAME_MAX,
  type LobbyRaumBlick,
} from "./lobby";
import type { Room, RoomClient } from "./room";
import { RoomManager } from "./room-manager";

// ---------- Helfer: LobbyRaumBlick-Zeilen kompakt bauen ----------

function raum(teil: Partial<LobbyRaumBlick>): LobbyRaumBlick {
  return {
    code: "AAAA",
    name: "Bananen-Bande #AAAA",
    oeffentlich: true,
    phase: "lobby",
    spieler: 0,
    clientCount: 1,
    modus: "klassik",
    ...teil,
  };
}

function lobby(teil: Partial<LobbyInfo>): LobbyInfo {
  return {
    code: "AAAA",
    name: "Bananen-Bande #AAAA",
    spieler: 0,
    max: 8,
    modus: "klassik",
    status: "lobby",
    ...teil,
  };
}

describe("lobby: Namens-Moderation (minimal)", () => {
  it("Auto-Name folgt dem Muster Bananen-Bande #CODE", () => {
    expect(autoRaumName("AFFE")).toBe("Bananen-Bande #AFFE");
  });

  it("trimmt und zieht Mehrfach-Leerzeichen zusammen", () => {
    expect(normalisiereRaumName("  Die   wilden\t Affen  ", "AFFE")).toBe("Die wilden Affen");
  });

  it("Leerstring/nur Whitespace fällt auf den Auto-Namen zurück", () => {
    expect(normalisiereRaumName("", "AFFE")).toBe("Bananen-Bande #AFFE");
    expect(normalisiereRaumName("   \t  ", "AFFE")).toBe("Bananen-Bande #AFFE");
  });

  it("kappt auf das Längen-Limit (ohne hängendes Leerzeichen)", () => {
    const lang = "A".repeat(31) + " Banane";
    const ergebnis = normalisiereRaumName(lang, "AFFE");
    expect(ergebnis.length).toBeLessThanOrEqual(RAUM_NAME_MAX);
    expect(ergebnis).toBe("A".repeat(31));
  });
});

describe("lobby: Sichtbarkeits-Flag + Status (oeffentlicheLobbys)", () => {
  it("private Räume erscheinen NIE in der Liste (Opt-in!)", () => {
    const liste = oeffentlicheLobbys([
      raum({ code: "PRIV", oeffentlich: false, spieler: 4 }),
      raum({ code: "PUBL", oeffentlich: true, spieler: 2 }),
    ]);
    expect(liste.map((l) => l.code)).toEqual(["PUBL"]);
  });

  it("Lobby-Phase ⇒ status lobby, alles andere ⇒ laeuft", () => {
    const liste = oeffentlicheLobbys([
      raum({ code: "WART", phase: "lobby" }),
      raum({ code: "SPIE", phase: "frage", spieler: 3 }),
      raum({ code: "ENDE", phase: "ende", spieler: 3 }),
    ]);
    expect(liste.find((l) => l.code === "WART")?.status).toBe("lobby");
    expect(liste.find((l) => l.code === "SPIE")?.status).toBe("laeuft");
    expect(liste.find((l) => l.code === "ENDE")?.status).toBe("laeuft");
  });

  it("tote Lobbys (0 verbundene Clients) werden gefiltert", () => {
    const liste = oeffentlicheLobbys([
      raum({ code: "TOTE", clientCount: 0, spieler: 2 }),
      raum({ code: "LEBT", clientCount: 1 }),
    ]);
    expect(liste.map((l) => l.code)).toEqual(["LEBT"]);
  });

  it("sortiert joinbare zuerst, darin die vollsten oben", () => {
    const liste = oeffentlicheLobbys([
      raum({ code: "LAUF", phase: "frage", spieler: 6 }),
      raum({ code: "EINS", spieler: 1 }),
      raum({ code: "FUEN", spieler: 5 }),
      raum({ code: "DREI", spieler: 3 }),
    ]);
    expect(liste.map((l) => l.code)).toEqual(["FUEN", "DREI", "EINS", "LAUF"]);
  });
});

describe("lobby: Schnell-Beitritt (Matchmaking light)", () => {
  it("wählt die VOLLSTE offene Lobby", () => {
    const wahl = waehleSchnellBeitritt([
      lobby({ code: "EINS", spieler: 1 }),
      lobby({ code: "FUEN", spieler: 5 }),
      lobby({ code: "DREI", spieler: 3 }),
    ]);
    expect(wahl?.code).toBe("FUEN");
  });

  it("überspringt volle (8/8) und laufende Lobbys", () => {
    const wahl = waehleSchnellBeitritt([
      lobby({ code: "VOLL", spieler: 8 }),
      lobby({ code: "LAUF", spieler: 4, status: "laeuft" }),
      lobby({ code: "FREI", spieler: 2 }),
    ]);
    expect(wahl?.code).toBe("FREI");
  });

  it("keine offene Lobby ⇒ null (Landing zeigt den Eröffnen-Dialog)", () => {
    expect(waehleSchnellBeitritt([])).toBeNull();
    expect(waehleSchnellBeitritt([lobby({ spieler: 8 })])).toBeNull();
    expect(waehleSchnellBeitritt([lobby({ status: "laeuft" })])).toBeNull();
  });
});

describe("lobby: 2-s-Cache von GET /api/lobbys", () => {
  it("innerhalb der TTL wird NICHT neu berechnet, danach schon", () => {
    const clock = createTestClock(1_000);
    let berechnungen = 0;
    const cache = erzeugeLobbyCache(
      () => {
        berechnungen += 1;
        return [lobby({ code: "AAAA" })];
      },
      clock,
      2_000,
    );
    cache();
    clock.advance(1_999);
    cache();
    expect(berechnungen).toBe(1);
    clock.advance(1);
    cache();
    expect(berechnungen).toBe(2);
  });
});

// ---------- RoomManager-Integration: echte Räume, Test-Clock, TTL ----------

function frage(id: string): Question {
  return {
    id,
    kind: "choice4",
    category: "affen",
    difficulty: "easy",
    text: `Frage ${id}?`,
    options: ["A", "B", "C", "D"],
    answer: 1,
    erklaerung: "Weil B.",
  };
}

function fakeLoader(): ContentLoader {
  const pool = Array.from({ length: 40 }, (_, i) => frage(`q${i + 1}`));
  const katalog: KatalogFrage[] = pool.map((f) => ({
    frage: f,
    oberkategorie: "wissen",
    planTyp: "mc4",
    region: "global",
  }));
  return {
    async loadPacks() {},
    pickQuestions: ({ anzahl }) => pool.slice(0, anzahl).map((f) => ({ ...f })),
    alleFragen: () => katalog,
  };
}

/** Fake-Client (Screen-Socket): clientCount > 0 ⇒ Lobby gilt als lebendig. */
function fakeClient(id: string): RoomClient {
  return {
    socket: { id, emit: () => {} } as unknown as RoomClient["socket"],
    role: "screen",
    playerId: null,
  };
}

/** In-Memory-Storage: kein Datei-Aufräum-Wettlauf mit dem async Event-Log. */
function memoryStorage(): Storage {
  const dateien = new Map<string, string>();
  return {
    resolve: (p) => p,
    async readJson<T>(p: string): Promise<T | null> {
      const text = dateien.get(p);
      return text === undefined ? null : (JSON.parse(text) as T);
    },
    async writeJsonAtomic(p, data) {
      dateien.set(p, JSON.stringify(data));
    },
    async appendLine(p, line) {
      dateien.set(p, (dateien.get(p) ?? "") + line + "\n");
    },
    async readText(p) {
      return dateien.get(p) ?? null;
    },
    async listeDateien() {
      return [];
    },
    async loesche(p) {
      dateien.delete(p);
    },
  };
}

let clock: ReturnType<typeof createTestClock>;
let manager: RoomManager;

beforeEach(() => {
  clock = createTestClock(1_000_000);
  manager = new RoomManager(
    {
      clock,
      rng: createRng(7),
      storage: memoryStorage(),
      contentLoader: fakeLoader(),
      plugins: { get: getPlugin, alle: allePlugins },
      fragenProMatch: 3,
    },
    { maxRooms: 8, ttlMs: 60_000 },
  );
});

function erzeugeLebendig(lobbyOpts?: { oeffentlich?: boolean; name?: string }): Room {
  const room = manager.erzeugeRaum("http://test", lobbyOpts)!;
  room.attachClient(fakeClient(`sock-${room.code}`));
  return room;
}

describe("lobby: RoomManager-Integration", () => {
  it("Default ist PRIVAT — nur Opt-in-Räume landen in lobbyListe()", () => {
    erzeugeLebendig(); // Default: privat
    const publik = erzeugeLebendig({ oeffentlich: true });
    const liste = manager.lobbyListe();
    expect(liste).toHaveLength(1);
    expect(liste[0]).toMatchObject({
      code: publik.code,
      name: `Bananen-Bande #${publik.code}`,
      spieler: 0,
      max: 8,
      modus: "klassik",
      status: "lobby",
    });
  });

  it("Spieler-Joins erhöhen den Zähler; Match-Start ⇒ status laeuft", () => {
    const room = erzeugeLebendig({ oeffentlich: true });
    room.applyAction({ type: "join", playerId: "p1", name: "Zoe", avatar: "gelb" });
    room.applyAction({ type: "join", playerId: "p2", name: "Ben", avatar: "rot" });
    expect(manager.lobbyListe()[0]).toMatchObject({ spieler: 2, status: "lobby" });
    expect(room.startMatch().ok).toBe(true);
    expect(manager.lobbyListe()[0]?.status).toBe("laeuft");
  });

  it("setzeLobbyEinstellungen moderiert den Namen und schaltet die Sichtbarkeit", () => {
    const room = erzeugeLebendig();
    manager.setzeLobbyEinstellungen(room, { oeffentlich: true, name: "  Affen  WG  " });
    expect(manager.lobbyListe()[0]?.name).toBe("Affen WG");
    // Leerstring ⇒ zurück zum Auto-Namen (kein anonymer Leer-Eintrag).
    manager.setzeLobbyEinstellungen(room, { name: "" });
    expect(manager.lobbyListe()[0]?.name).toBe(`Bananen-Bande #${room.code}`);
    manager.setzeLobbyEinstellungen(room, { oeffentlich: false });
    expect(manager.lobbyListe()).toHaveLength(0);
  });

  it("TTL räumt verlassene öffentliche Lobbys ab — Liste UND Manager", () => {
    const room = erzeugeLebendig({ oeffentlich: true });
    expect(manager.lobbyListe()).toHaveLength(1);
    // Screen trennt ⇒ sofort aus der Liste (tote Lobby), Raum existiert noch.
    room.detachClient(`sock-${room.code}`);
    expect(manager.lobbyListe()).toHaveLength(0);
    expect(manager.anzahl).toBe(1);
    // Nach Ablauf der TTL baut die Tick-Schleife den Raum endgültig ab.
    clock.advance(60_001);
    manager.tickAlle();
    expect(manager.anzahl).toBe(0);
    expect(manager.lobbyListe()).toHaveLength(0);
  });
});

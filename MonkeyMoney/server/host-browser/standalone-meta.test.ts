// Storage-Adapter-Beweis der W4-Standalone-Lücke: Meta-Stores (save-store,
// profile-store) laufen UNVERÄNDERT gegen den IndexedDB-Adapter — der
// „App-Neustart" ist hier eine FRISCHE createBrowserStorage-Instanz auf
// derselben DB (fake-indexeddb hält die Daten prozessweit, genau wie das
// echte IndexedDB des WKWebView über App-Starts hinweg).
import "fake-indexeddb/auto";
import { describe, expect, it } from "vitest";
import { createTestClock } from "../../shared/time";
import { defaultSettings } from "../../shared/settings";
import { createInitialState } from "../engine/engine";
import type { EngineState } from "../engine/types";
import type { Storage } from "../persistence/storage";
import { createProfileStore } from "../meta/profile-store";
import { createSaveStore, friereEin, type SaveDatei } from "../meta/save-store";
import { createBrowserStorage } from "./browser-storage";

let dbNr = 0;
const neueDb = (): string => `meta-db-${++dbNr}`;
const oeffne = (dbName: string): Promise<Storage> => createBrowserStorage({ dbName });

/** Minimaler Match-Zustand für Save-Dateien (2 Spieler, Frage 3 läuft). */
function matchState(): EngineState {
  const s = createInitialState(defaultSettings("quick"));
  s.phase = "frage";
  s.matchId = "m_test1";
  s.fragenZaehler = 3;
  s.order = ["p1", "p2"];
  s.players = {
    p1: { id: "p1", name: "Zoe", avatar: "pink" } as EngineState["players"][string],
    p2: { id: "p2", name: "Ben", avatar: "blau" } as EngineState["players"][string],
  };
  return s;
}

function saveRumpf(): Omit<SaveDatei, "schemaVersion" | "savedAt" | "auto"> {
  return {
    slot: 1,
    roomCode: "AFFE",
    gmPin: "1234",
    matchId: "m_test1",
    seq: 42,
    engineState: matchState(),
    rngState: 777,
    sessions: [],
    profilBindungen: { p1: "pr_abc12345" },
    bots: [],
  };
}

describe("save-store auf IndexedDB (GM-Save/Load im Browser-Host)", () => {
  it("schreibe → lade Roundtrip: kompletter Spielstand inkl. rngState/Bindungen", async () => {
    const saves = createSaveStore(await oeffne(neueDb()), createTestClock(5_000));
    await saves.schreibe(saveRumpf());
    const geladen = await saves.lade(1);
    expect(geladen?.roomCode).toBe("AFFE");
    expect(geladen?.rngState).toBe(777);
    expect(geladen?.profilBindungen).toEqual({ p1: "pr_abc12345" });
    expect(geladen?.savedAt).toBe(5_000);
  });

  it("friereEin pausiert das laufende Match im Save (Resume-Trick)", async () => {
    const saves = createSaveStore(await oeffne(neueDb()), createTestClock(9_000));
    await saves.schreibe(saveRumpf());
    const geladen = await saves.lade(1);
    expect(geladen?.engineState.paused?.seit).toBe(9_000);
    // friereEin lässt Lobby/Ende unangetastet (nichts zu pausieren).
    expect(friereEin(createInitialState(defaultSettings("quick")), 1).paused).toBeNull();
  });

  it("liste zeigt Slot-Infos (Phase, Frage-Nr, Spieler) für die GM-Karte", async () => {
    const saves = createSaveStore(await oeffne(neueDb()), createTestClock(0));
    await saves.schreibe(saveRumpf());
    const slots = await saves.liste();
    expect(slots).toHaveLength(1);
    expect(slots[0]).toMatchObject({ slot: 1, auto: false, phase: "frage", frageNr: 3 });
    expect(slots[0].spieler.map((s) => s.name)).toEqual(["Zoe", "Ben"]);
  });

  it("APP-NEUSTART: frische Storage-Instanz auf derselben DB liest den Save", async () => {
    const dbName = neueDb();
    const vorher = createSaveStore(await oeffne(dbName), createTestClock(0));
    await vorher.schreibe(saveRumpf());
    // „Neustart": neue Adapter-Instanz, gleiche IndexedDB — wie App-Kill + Start.
    const nachher = createSaveStore(await oeffne(dbName), createTestClock(60_000));
    const geladen = await nachher.lade(1);
    expect(geladen?.matchId).toBe("m_test1");
    expect(geladen?.engineState.fragenZaehler).toBe(3);
  });

  it("Autosave-Zyklus: schreibeAutosave → listeAutosaves → loescheAutosave", async () => {
    const saves = createSaveStore(await oeffne(neueDb()), createTestClock(30_000));
    await saves.schreibeAutosave({ ...saveRumpf(), slot: 0 });
    const autos = await saves.listeAutosaves();
    expect(autos).toHaveLength(1);
    expect(autos[0]).toMatchObject({ auto: true, matchId: "m_test1", savedAt: 30_000 });
    await saves.loescheAutosave("m_test1");
    expect(await saves.listeAutosaves()).toEqual([]);
  });

  it("Autosave überlebt den Neustart (Grundlage der Boot-Wiederbelebung)", async () => {
    const dbName = neueDb();
    const vorher = createSaveStore(await oeffne(dbName), createTestClock(0));
    await vorher.schreibeAutosave({ ...saveRumpf(), slot: 0 });
    const nachher = createSaveStore(await oeffne(dbName), createTestClock(1));
    expect((await nachher.listeAutosaves())[0]?.roomCode).toBe("AFFE");
  });
});

describe("profile-store auf IndexedDB (Profile/AT im Browser-Host)", () => {
  it("erstelle → hole: Profil landet in IndexedDB", async () => {
    const profile = createProfileStore(await oeffne(neueDb()), createTestClock(0));
    const p = await profile.erstelle({ name: "Coco", avatar: "gelb", deviceToken: "d_1" });
    expect(p.profileId).toMatch(/^pr_/);
    expect((await profile.hole(p.profileId))?.name).toBe("Coco");
  });

  it("APP-NEUSTART: Profil + gebuchte AT überleben die neue Storage-Instanz", async () => {
    const dbName = neueDb();
    const vorher = createProfileStore(await oeffne(dbName), createTestClock(0));
    const p = await vorher.erstelle({ name: "Coco", avatar: "gelb" });
    const buchung = await vorher.bucheMatch("m_1", [
      { profileId: p.profileId, endstand: 12_000, at: 1_200, sieg: true },
    ]);
    expect(buchung[0]?.atGesamt).toBe(1_200);
    // „Neustart": neue Adapter-Instanz auf derselben DB.
    const nachher = createProfileStore(await oeffne(dbName), createTestClock(99_000));
    const geladen = await nachher.hole(p.profileId);
    expect(geladen?.at.gesamt).toBe(1_200);
    expect(geladen?.at.verfuegbar).toBe(1_200);
  });

  it("AT-Buchung bleibt idempotent über den Neustart (gebuchteMatches-Ring)", async () => {
    const dbName = neueDb();
    const vorher = createProfileStore(await oeffne(dbName), createTestClock(0));
    const p = await vorher.erstelle({ name: "Coco", avatar: "gelb" });
    await vorher.bucheMatch("m_1", [{ profileId: p.profileId, endstand: 1, at: 500, sieg: false }]);
    const nachher = createProfileStore(await oeffne(dbName), createTestClock(1));
    // Dasselbe Match nochmal buchen (z. B. nach save.load) ⇒ KEINE Doppel-AT.
    const nochmal = await nachher.bucheMatch("m_1", [
      { profileId: p.profileId, endstand: 1, at: 500, sieg: false },
    ]);
    expect(nochmal).toEqual([]);
    expect((await nachher.hole(p.profileId))?.at.gesamt).toBe(500);
  });

  it("PIN-Login funktioniert nach dem Neustart (Hash liegt in IndexedDB)", async () => {
    const dbName = neueDb();
    const vorher = createProfileStore(await oeffne(dbName), createTestClock(0));
    const p = await vorher.erstelle({ name: "Zoe", avatar: "pink", pin: "4711" });
    const nachher = createProfileStore(await oeffne(dbName), createTestClock(1));
    expect(await nachher.login(p.profileId, { pin: "0000" })).toEqual({ fehler: "pin-falsch" });
    const okLogin = await nachher.login(p.profileId, { pin: "4711" });
    expect("fehler" in okLogin).toBe(false);
  });

  it("liste(deviceToken) zeigt nur Profile DIESES Geräts — auch nach Neustart", async () => {
    const dbName = neueDb();
    const vorher = createProfileStore(await oeffne(dbName), createTestClock(0));
    await vorher.erstelle({ name: "Coco", avatar: "gelb", deviceToken: "d_ipad" });
    await vorher.erstelle({ name: "Fremd", avatar: "blau", deviceToken: "d_anders" });
    const nachher = createProfileStore(await oeffne(dbName), createTestClock(1));
    const eigene = await nachher.liste("d_ipad");
    expect(eigene.map((p) => p.name)).toEqual(["Coco"]);
  });
});

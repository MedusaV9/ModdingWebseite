// Save/Load-Roundtrip (TECH-SPEC §5 / ARCHITEKTUR-Punkt „Save-Serialisierung"):
// Match mit In-Prozess-Bots bis in die Frage-Phase spielen → Slot speichern →
// „Server-Neustart" (frische Manager/Stores/Rng auf demselben DATA_DIR) →
// laden → Raum läuft unter altem Code/PIN/matchId weiter → gm.resume verschiebt
// die Deadlines → die Bots spielen das Match ZU ENDE → AT-Buchung ans Profil.
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { Question } from "../../shared/content";
import { createStatefulRng } from "../../shared/rng";
import { createTestClock } from "../../shared/time";
import type { ContentLoader, KatalogFrage } from "../content-loader/index";
import { allePlugins, getPlugin } from "../minigames/registry";
import { createFileStorage } from "../persistence/storage";
import { RoomManager } from "../rooms/room-manager";
import { createMetaService, type MetaService } from "./index";
import { friereEin } from "./save-store";

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

interface Welt {
  clock: ReturnType<typeof createTestClock>;
  rng: ReturnType<typeof createStatefulRng>;
  meta: MetaService;
  manager: RoomManager;
}

function baueWelt(dir: string, startMs: number, seed: number): Welt {
  const clock = createTestClock(startMs);
  const rng = createStatefulRng(seed);
  const storage = createFileStorage(dir);
  const contentLoader = fakeLoader();
  const meta = createMetaService({ storage, clock, rng, contentLoader });
  const manager = new RoomManager(
    {
      clock,
      rng,
      storage,
      contentLoader,
      plugins: { get: getPlugin, alle: allePlugins },
      fragenProMatch: 3,
      meta,
    },
    { maxRooms: 4, ttlMs: 86_400_000 },
  );
  meta.verbindeManager((room, code) => manager.schluessleUm(room, code));
  return { clock, rng, meta, manager };
}

/** Tick-Schleife mit Test-Clock, bis `fertig` (Sicherheits-Deckel inklusive). */
function laufeBis(welt: Welt, fertig: () => boolean, maxTicks = 20_000): void {
  for (let i = 0; i < maxTicks && !fertig(); i++) {
    welt.clock.advance(250);
    welt.manager.tickAlle();
  }
  expect(fertig()).toBe(true);
}

let dir: string;

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "mm-save-"));
});

afterEach(async () => {
  // Fire-and-forget-Writes (Autosave/rooms.json) können beim Teardown noch in
  // der Luft hängen. rmSync-eigene Retries decken ENOTEMPTY nicht ab (eine
  // Datei landet ZWISCHEN zwei Lösch-Pässen) — deshalb eigener Retry-Loop mit
  // Drain-Pausen; wenn es nach 10 Anläufen immer noch schreibt, ist ein
  // verwaistes tmp-Verzeichnis das kleinere Übel als ein CI-Flake.
  for (let i = 0; i < 10; i++) {
    try {
      rmSync(dir, { recursive: true, force: true, maxRetries: 5, retryDelay: 50 });
      return;
    } catch {
      await new Promise((r) => setTimeout(r, 150));
    }
  }
});

describe("meta: friereEin (Pausen-Trick)", () => {
  it("pausiert laufende Matches AB savedAt; Lobby/Ende bleiben unberührt", () => {
    const laufend = { phase: "frage", paused: null } as never;
    const eingefroren = friereEin(laufend, 12_345);
    expect((eingefroren as { paused: { seit: number } }).paused.seit).toBe(12_345);
    const lobby = { phase: "lobby", paused: null } as never;
    expect(friereEin(lobby, 1)).toBe(lobby);
    // Bestehende GM-Pause bleibt (seit zählt ab der echten Pause weiter).
    const pausiert = { phase: "frage", paused: { text: "x", seit: 99, bis: null } } as never;
    expect(friereEin(pausiert, 12_345)).toBe(pausiert);
  });
});

describe("meta: Save/Load-Roundtrip mit Engine-Resume (§5)", () => {
  it("Match speichern → Neustart → laden → Bots spielen zu Ende → AT gebucht", async () => {
    // ---------- Phase 1: Match anspielen + speichern ----------
    const welt1 = baueWelt(dir, 1_000_000, 42);
    const room1 = welt1.manager.erzeugeRaum("http://test")!;
    const alterCode = room1.code;
    const altePin = room1.gmPin;
    const alteMatchId = room1.matchId;

    // 3 Bot-Personas in die Lobby (GM-Kommando über den Meta-Hook).
    for (let i = 0; i < 3; i++) {
      const r = await welt1.meta.gmMetaCmd(room1, "bot.add", {})!;
      expect(r.ok).toBe(true);
    }
    expect(room1.state.order).toHaveLength(3);

    // Profil an Bot 1 binden (AT-Buchung am Ende) + eine GM-Session anlegen.
    const profil = await welt1.meta.profile.erstelle({ name: "Anna", avatar: "gelb" });
    room1.bindeProfil(room1.state.order[0], profil.profileId);
    const gmToken = room1.sessions.erstelle("gm", null).token;

    // Quick-Match starten und bis in die erste Frage-Phase spielen.
    expect(room1.applyAction({ type: "gm.settings", patch: { modus: "quick" } }).ok).toBe(true);
    expect(room1.startMatch().ok).toBe(true);
    laufeBis(welt1, () => room1.state.phase === "frage");
    const frageNrBeimSave = room1.state.fragenZaehler;

    const gespeichert = await welt1.meta.gmMetaCmd(room1, "save.write", { slot: 1 })!;
    expect(gespeichert.ok).toBe(true);
    const savedAt = welt1.clock.now();
    const rngStateBeimSave = welt1.rng.getState();

    const slots = await welt1.meta.saves.liste();
    expect(slots).toHaveLength(1);
    expect(slots[0]).toMatchObject({ slot: 1, auto: false, roomCode: alterCode, phase: "frage" });
    expect(slots[0].spieler).toHaveLength(3);

    // Ungültige Slots + Save ohne laufendes Match blocken sauber.
    expect((await welt1.meta.gmMetaCmd(room1, "save.write", { slot: 9 })!).error).toBe(
      "ungueltiger-slot",
    );

    // ---------- Phase 2: „Server-Neustart" — alles frisch, gleiche Daten ----------
    const welt2 = baueWelt(dir, savedAt + 90_000, 777); // andere Uhr, anderer Seed
    const room2 = welt2.manager.erzeugeRaum("http://test")!;
    expect((await welt2.meta.gmMetaCmd(room2, "save.load", { slot: 3 })!).error).toBe("slot-leer");

    const geladen = await welt2.meta.gmMetaCmd(room2, "save.load", { slot: 1 })!;
    expect(geladen.ok).toBe(true);

    // Identität wiederhergestellt: Code, GM-PIN, matchId, Fragen-Stand, Bindung.
    expect(room2.code).toBe(alterCode);
    expect(room2.gmPin).toBe(altePin);
    expect(room2.matchId).toBe(alteMatchId);
    expect(room2.state.fragenZaehler).toBe(frageNrBeimSave);
    expect(room2.profilBindungen.get(room2.state.order[0])).toBe(profil.profileId);
    // Session-Token aus dem Save funktioniert weiter (Spieler-Rejoin).
    expect(room2.sessions.restore(gmToken)?.role).toBe("gm");
    // Rng-Zustand exakt wie beim Speichern (Determinismus über den Neustart).
    expect(welt2.rng.getState()).toBe(rngStateBeimSave);
    // Save friert als Pause ein — Deadlines ruhen bis zum Resume.
    expect(room2.state.paused).not.toBeNull();
    expect(room2.state.paused?.seit).toBe(savedAt);

    // Laden ist NUR in der Lobby erlaubt (laufende Räume nie überbügeln).
    expect((await welt2.meta.gmMetaCmd(room2, "save.load", { slot: 1 })!).error).toBe(
      "nur-in-lobby",
    );

    // ---------- Phase 3: Resume — die Bots spielen das Match ZU ENDE ----------
    expect(room2.applyAction({ type: "gm.resume" }).ok).toBe(true);
    laufeBis(welt2, () => ["siegerehrung", "ende"].includes(room2.state.phase), 40_000);

    // Sieger ermittelt + AT-Buchung ans gebundene Profil (Formel §3.6, min. 50).
    let atGesamt = 0;
    for (let i = 0; i < 100 && atGesamt === 0; i++) {
      await new Promise((r) => setTimeout(r, 10));
      atGesamt = (await welt2.meta.profile.hole(profil.profileId))?.at.gesamt ?? 0;
    }
    expect(atGesamt).toBeGreaterThanOrEqual(50);
    expect((await welt2.meta.profile.hole(profil.profileId))?.gebuchteMatches).toContain(
      alteMatchId,
    );

    // Event-Log: EIN Match = EINE Datei — Lade-Marker + Match-Ende drin.
    // Appends laufen fire-and-forget (Ketten-Promise) ⇒ auf den Flush pollen.
    let log = "";
    for (let i = 0; i < 200 && !log.includes('"match_ended"'); i++) {
      log = (await welt2.manager.storage.readText(`events/${alteMatchId}.jsonl`)) ?? "";
      if (!log.includes('"match_ended"')) await new Promise((r) => setTimeout(r, 10));
    }
    expect(log).toContain('"match_loaded"');
    expect(log).toContain('"match_ended"');
  }, 30_000);

  it("Autosave beim Raum-TTL-Abbau: laufendes Match landet in Slot 0", async () => {
    const welt = baueWelt(dir, 1_000_000, 42);
    const room = welt.manager.erzeugeRaum("http://test")!;
    for (let i = 0; i < 2; i++) await welt.meta.gmMetaCmd(room, "bot.add", {})!;
    room.applyAction({ type: "gm.settings", patch: { modus: "quick" } });
    expect(room.startMatch().ok).toBe(true);
    laufeBis(welt, () => room.state.phase === "frage");

    welt.manager.schliesseRaum(room, "ttl");
    let slots = await welt.meta.saves.liste();
    for (let i = 0; i < 100 && slots.length === 0; i++) {
      await new Promise((r) => setTimeout(r, 10));
      slots = await welt.meta.saves.liste();
    }
    expect(slots[0]).toMatchObject({ slot: 0, auto: true, roomCode: room.code });

    // Aus dem Autosave kommt das Match zurück (Laden aus der Lobby).
    const neu = welt.manager.erzeugeRaum("http://test")!;
    const geladen = await welt.meta.gmMetaCmd(neu, "save.load", { slot: 0 })!;
    expect(geladen.ok).toBe(true);
    expect(neu.code).toBe(room.code);
    expect(neu.state.phase).toBe("frage");
  }, 30_000);

  it("Crash-Schutz: periodischer Autosave (~30 s) sichert laufende Matches nach saves/auto/", async () => {
    const welt = baueWelt(dir, 1_000_000, 42);
    const room = welt.manager.erzeugeRaum("http://test")!;
    for (let i = 0; i < 2; i++) await welt.meta.gmMetaCmd(room, "bot.add", {})!;
    room.applyAction({ type: "gm.settings", patch: { modus: "quick" } });

    // In der Lobby passiert NICHTS (kein laufendes Match, kein Write-Spam).
    for (let i = 0; i < 10; i++) {
      welt.clock.advance(30_000);
      welt.manager.tickAlle();
    }
    await new Promise((r) => setTimeout(r, 50));
    expect(await welt.manager.storage.listeDateien("saves/auto")).toEqual([]);

    expect(room.startMatch().ok).toBe(true);
    laufeBis(welt, () => room.state.phase === "frage");
    // Autosave läuft fire-and-forget ⇒ auf die Datei pollen.
    let auto: { matchId: string; auto: boolean } | null = null;
    for (let i = 0; i < 100 && auto === null; i++) {
      await new Promise((r) => setTimeout(r, 10));
      auto = await welt.manager.storage.readJson(`saves/auto/${room.matchId}.json`);
    }
    expect(auto).not.toBeNull();
    expect(auto!.matchId).toBe(room.matchId);
    expect(auto!.auto).toBe(true);
  }, 30_000);

  it("Boot-Wiederbelebung: SIGKILL-Szenario — frischer Autosave stellt den Raum her, Tokens resumen, Match spielbar zu Ende", async () => {
    // ---------- Phase 1: Match läuft, Autosave entsteht, dann „Crash" ----------
    const welt1 = baueWelt(dir, 1_000_000, 42);
    const room1 = welt1.manager.erzeugeRaum("http://test")!;
    for (let i = 0; i < 3; i++) await welt1.meta.gmMetaCmd(room1, "bot.add", {})!;
    const spielerToken = room1.sessions.erstelle("player", room1.state.order[0]).token;
    room1.applyAction({ type: "gm.settings", patch: { modus: "quick" } });
    expect(room1.startMatch().ok).toBe(true);
    laufeBis(welt1, () => room1.state.phase === "frage");
    const alterCode = room1.code;
    const alteMatchId = room1.matchId;
    // Autosave-Intervall (30 s) sicher überschreiten ⇒ DIESER Tick sichert
    // den aktuellen Stand (seq-genau) — dann „crasht" der Server.
    welt1.clock.advance(31_000);
    welt1.manager.tickAlle();
    const crashSeq = room1.seq;
    const frageNrBeimCrash = room1.state.fragenZaehler;
    let auto: { seq: number } | null = null;
    for (let i = 0; i < 200 && auto?.seq !== crashSeq; i++) {
      await new Promise((r) => setTimeout(r, 10));
      auto = await welt1.manager.storage.readJson(`saves/auto/${alteMatchId}.json`);
    }
    expect(auto?.seq).toBe(crashSeq);
    // 💥 SIGKILL: welt1 wird einfach fallen gelassen — kein Close-Hook läuft.

    // ---------- Phase 2: Boot < 10 min später ⇒ automatische Wiederbelebung ----------
    const welt2 = baueWelt(dir, welt1.clock.now() + 60_000, 777);
    const wiederbelebt = await welt2.meta.bootWiederbelebung({
      erzeuge: () => welt2.manager.erzeugeRaum("http://test"),
      verwerfe: (r) => welt2.manager.verwerfeRaum(r),
    });
    expect(wiederbelebt).toHaveLength(1);
    expect(wiederbelebt[0].code).toBe(alterCode);
    const room2 = welt2.manager.finde(alterCode)!;
    expect(room2).not.toBeNull();
    expect(room2.matchId).toBe(alteMatchId);
    expect(room2.state.fragenZaehler).toBe(frageNrBeimCrash);
    // Save friert als Pause ein — der GM drückt nur noch „Pause beenden".
    expect(room2.state.paused).not.toBeNull();
    // Spieler-Token aus der Vor-Crash-Welt findet seinen Slot wieder (resume).
    expect(room2.sessions.restore(spielerToken)?.playerId).toBe(room1.state.order[0]);

    // ---------- Phase 3: Resume ⇒ Bots (restauriert!) spielen ZU ENDE ----------
    expect(room2.applyAction({ type: "gm.resume" }).ok).toBe(true);
    laufeBis(welt2, () => ["siegerehrung", "ende"].includes(room2.state.phase), 40_000);
    // Match sauber vorbei ⇒ der Crash-Schutz-Autosave ist aufgeräumt.
    let dateien = await welt2.manager.storage.listeDateien("saves/auto");
    for (let i = 0; i < 100 && dateien.length > 0; i++) {
      await new Promise((r) => setTimeout(r, 10));
      dateien = await welt2.manager.storage.listeDateien("saves/auto");
    }
    expect(dateien).toEqual([]);
  }, 30_000);

  it("Boot-Wiederbelebung: stale Autosaves (>10 min) werden NICHT wiederbelebt, nur aufgeräumt", async () => {
    const welt1 = baueWelt(dir, 1_000_000, 42);
    const room1 = welt1.manager.erzeugeRaum("http://test")!;
    for (let i = 0; i < 2; i++) await welt1.meta.gmMetaCmd(room1, "bot.add", {})!;
    room1.applyAction({ type: "gm.settings", patch: { modus: "quick" } });
    expect(room1.startMatch().ok).toBe(true);
    laufeBis(welt1, () => room1.state.phase === "frage");
    let auto: unknown = null;
    for (let i = 0; i < 100 && auto === null; i++) {
      await new Promise((r) => setTimeout(r, 10));
      auto = await welt1.manager.storage.readJson(`saves/auto/${room1.matchId}.json`);
    }
    expect(auto).not.toBeNull();

    // Boot erst NACH dem 10-min-Fenster: der Abend ist vorbei.
    const welt2 = baueWelt(dir, welt1.clock.now() + 11 * 60_000, 777);
    const wiederbelebt = await welt2.meta.bootWiederbelebung({
      erzeuge: () => welt2.manager.erzeugeRaum("http://test"),
      verwerfe: (r) => welt2.manager.verwerfeRaum(r),
    });
    expect(wiederbelebt).toEqual([]);
    expect(welt2.manager.anzahl).toBe(0);
    let dateien = await welt2.manager.storage.listeDateien("saves/auto");
    for (let i = 0; i < 100 && dateien.length > 0; i++) {
      await new Promise((r) => setTimeout(r, 10));
      dateien = await welt2.manager.storage.listeDateien("saves/auto");
    }
    expect(dateien).toEqual([]);
  }, 30_000);

  it("Bots: Lobby-Verwaltung (add/remove nur in der Lobby, Personas einmalig)", async () => {
    const welt = baueWelt(dir, 1_000_000, 42);
    const room = welt.manager.erzeugeRaum("http://test")!;
    for (let i = 0; i < 5; i++) {
      expect((await welt.meta.gmMetaCmd(room, "bot.add", {})!).ok).toBe(true);
    }
    // Alle 5 Personas vergeben ⇒ Nr. 6 blockt.
    expect((await welt.meta.gmMetaCmd(room, "bot.add", {})!).error).toBe("alle-personas-vergeben");
    expect((await welt.meta.gmMetaCmd(room, "bot.remove", {})!).ok).toBe(true);
    expect(room.state.order).toHaveLength(4);
    room.applyAction({ type: "gm.settings", patch: { modus: "quick" } });
    expect(room.startMatch().ok).toBe(true);
    expect((await welt.meta.gmMetaCmd(room, "bot.add", {})!).error).toBe("nur-in-lobby");
  });
});

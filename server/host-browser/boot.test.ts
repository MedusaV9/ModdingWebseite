// Integrations-Test der Kompositions-Wurzel: der komplette Browser-Server
// (Relay-Shim → wireSockets → RoomManager → Engine) OHNE Browser — die
// Test-Brücke spielt Swift/relay-sim, Memory-Storage spielt IndexedDB.
// Beweist: room.create, Screen-hello (Origin-Rewrite in der Join-URL),
// Spieler-Join mit Welcome+Snapshot, Match-Start per GM über die Relay-Frames.
// Seit W4 zusätzlich: Meta über das Wire ("meta.http"-Event), GM-Save/Load
// über einen simulierten App-Neustart (gleiche Storage, frischer Server),
// Autosave-Tick und Boot-Wiederbelebung — die Standalone-Speicher-Lücke.
import { afterEach, describe, expect, it } from "vitest";
import { createTestClock } from "../../shared/time";
import type { KatalogFrage } from "../content-loader/index";
import { startStandaloneServer, type StandaloneServer } from "./boot";
import { createMemoryStorage } from "./browser-storage";
import type { HostZumRelay, RelayBridge, RelayZumHost } from "./relay";

function katalog(n: number): KatalogFrage[] {
  return Array.from({ length: n }, (_, i) => ({
    frage: {
      id: `q${i}`,
      kind: "choice4" as const,
      category: "tiere",
      difficulty: "easy" as const,
      text: `Frage ${i}?`,
      options: ["A", "B", "C", "D"],
      answer: 0,
      erklaerung: "Weil.",
    },
    oberkategorie: "wissen",
    planTyp: "choice",
    region: "global",
  }));
}

/** Brücke + Mini-Client: sendet Wire-Frames wie ein Telefon, sammelt Antworten. */
function createLoopback() {
  let zumHost: ((msg: RelayZumHost) => void) | null = null;
  const anClients = new Map<string, { t: string; ev?: string; ack?: number; p?: unknown }[]>();
  const bridge: RelayBridge = {
    send(msg: HostZumRelay) {
      if (msg.kind !== "frame") return;
      const liste = anClients.get(msg.clientId) ?? [];
      liste.push(JSON.parse(msg.data));
      anClients.set(msg.clientId, liste);
    },
    onMessage: (cb) => {
      zumHost = cb;
    },
  };
  let ackNr = 0;
  return {
    bridge,
    verbinde(clientId: string) {
      anClients.set(clientId, []);
      zumHost?.({ kind: "open", clientId });
    },
    sende(clientId: string, ev: string, p?: unknown): number {
      const ack = ++ackNr;
      zumHost?.({ kind: "frame", clientId, data: JSON.stringify({ t: "e", ev, p, ack }) });
      return ack;
    },
    antwort(clientId: string, ack: number): unknown {
      return anClients.get(clientId)?.find((m) => m.t === "a" && m.ack === ack)?.p;
    },
    events(clientId: string, ev: string): unknown[] {
      return (anClients.get(clientId) ?? [])
        .filter((m) => m.t === "e" && m.ev === ev)
        .map((m) => m.p);
    },
  };
}

describe("startStandaloneServer (Browser-Server end-zu-end, ohne Browser)", () => {
  let server: StandaloneServer | null = null;
  afterEach(() => server?.stop());

  it("Raum eröffnen → 2 Spieler joinen → GM startet das Match — alles über Relay-Frames", async () => {
    const loop = createLoopback();
    server = startStandaloneServer({
      bridge: loop.bridge,
      origin: "http://192.168.1.20:8080",
      katalog: katalog(150),
      storage: createMemoryStorage(),
      seed: 42,
      clock: createTestClock(1_000_000),
    });

    // Screen: room.create + hello (Client meldet localhost — LAN-Origin gewinnt).
    loop.verbinde("screen");
    const a1 = loop.sende("screen", "room.create", {
      role: "screen",
      origin: "http://localhost:8080",
    });
    const raum = loop.antwort("screen", a1) as { ok: boolean; code: string; gmPin: string };
    expect(raum.ok).toBe(true);
    expect(raum.code).toHaveLength(4);

    const a2 = loop.sende("screen", "hello", {
      roomCode: raum.code,
      role: "screen",
      origin: "http://localhost:8080",
    });
    const screenWelcome = loop.antwort("screen", a2) as {
      ok: boolean;
      view: { joinUrl: string };
    };
    expect(screenWelcome.ok).toBe(true);
    expect(screenWelcome.view.joinUrl).toBe(`http://192.168.1.20:8080/j/${raum.code}`);

    // Zwei Spieler joinen als Gäste.
    for (const [clientId, name] of [
      ["zoe", "Zoe"],
      ["ben", "Ben"],
    ] as const) {
      loop.verbinde(clientId);
      const ack = loop.sende(clientId, "hello", { roomCode: raum.code, role: "player", name });
      const welcome = loop.antwort(clientId, ack) as { ok: boolean; playerId: string | null };
      expect(welcome.ok).toBe(true);
      expect(welcome.playerId).toBeTruthy();
    }

    // Joins lösen Snapshots an den Screen aus (Broadcast über die Brücke).
    expect(loop.events("screen", "view.snapshot").length).toBeGreaterThan(0);

    // GM: hello mit PIN, dann flow.next (Lobby → Intro) — Engine läuft im Browser-Server.
    loop.verbinde("gm");
    const a3 = loop.sende("gm", "hello", { roomCode: raum.code, role: "gm", gmPin: raum.gmPin });
    expect((loop.antwort("gm", a3) as { ok: boolean }).ok).toBe(true);
    const a4 = loop.sende("gm", "gm.cmd", { cmd: "flow.next", args: {}, cmdId: "t1" });
    // gm.cmd ackt asynchron (Meta-Kommandos sind Promises) — Microtasks abwarten.
    await new Promise((r) => setTimeout(r, 0));
    expect((loop.antwort("gm", a4) as { ok: boolean; error?: string }).ok).toBe(true);

    const snapshotNachStart = loop.events("screen", "view.snapshot").at(-1) as {
      view: { phase: string };
    };
    expect(snapshotNachStart.view.phase).not.toBe("lobby");
    expect(server.relay.anzahlClients()).toBe(4);
  });

  it("falsche GM-PIN wird über den Relay-Pfad sauber abgelehnt", () => {
    const loop = createLoopback();
    server = startStandaloneServer({
      bridge: loop.bridge,
      origin: "http://ipad:8080",
      katalog: katalog(150),
      storage: createMemoryStorage(),
      seed: 7,
      clock: createTestClock(0),
    });
    loop.verbinde("screen");
    const a1 = loop.sende("screen", "room.create", { role: "screen", origin: "http://x" });
    const raum = loop.antwort("screen", a1) as { code: string };
    loop.verbinde("gm");
    const a2 = loop.sende("gm", "hello", { roomCode: raum.code, role: "gm", gmPin: "0000" });
    expect(loop.antwort("gm", a2)).toEqual({ ok: false, error: "gm-pin-falsch" });
  });
});

// ---------------------------------------------------------------------------
// W4: Meta im Standalone — Profile/Saves über das Wire, Neustart-Überleben.
// ---------------------------------------------------------------------------

/** Screen eröffnet Raum, 2 Spieler joinen, GM startet das Match (bis Intro). */
function starteMatch(loop: ReturnType<typeof createLoopback>): { code: string; gmPin: string } {
  loop.verbinde("screen");
  const a1 = loop.sende("screen", "room.create", { role: "screen", origin: "http://x" });
  const raum = loop.antwort("screen", a1) as { code: string; gmPin: string };
  loop.sende("screen", "hello", { roomCode: raum.code, role: "screen", origin: "http://x" });
  for (const [clientId, name] of [
    ["zoe", "Zoe"],
    ["ben", "Ben"],
  ] as const) {
    loop.verbinde(clientId);
    loop.sende(clientId, "hello", { roomCode: raum.code, role: "player", name });
  }
  loop.verbinde("gm");
  loop.sende("gm", "hello", { roomCode: raum.code, role: "gm", gmPin: raum.gmPin });
  loop.sende("gm", "gm.cmd", { cmd: "flow.next", args: {}, cmdId: "start" });
  return raum;
}

const mikrotasks = (): Promise<void> => new Promise((r) => setTimeout(r, 0));

describe("Standalone-Meta (W4): Wire-API, Save/Load-Neustart, Autosave, Wiederbelebung", () => {
  let server: StandaloneServer | null = null;
  afterEach(() => server?.stop());

  it("meta.http über das Relay: Profil anlegen + Geräte-Liste per Query-String", async () => {
    const loop = createLoopback();
    server = startStandaloneServer({
      bridge: loop.bridge,
      origin: "http://ipad:8080",
      katalog: katalog(150),
      storage: createMemoryStorage(),
      seed: 7,
      clock: createTestClock(0),
    });
    loop.verbinde("tel1");
    const a1 = loop.sende("tel1", "meta.http", {
      method: "POST",
      pfad: "/api/meta/profile",
      body: { name: "Coco", avatar: "gelb", deviceToken: "d_tel1" },
    });
    await mikrotasks();
    const anlage = loop.antwort("tel1", a1) as {
      status: number;
      body: { profil: { profileId: string; name: string } };
    };
    expect(anlage.status).toBe(200);
    expect(anlage.body.profil.name).toBe("Coco");

    const a2 = loop.sende("tel1", "meta.http", {
      method: "GET",
      pfad: "/api/meta/profile?device=d_tel1",
    });
    await mikrotasks();
    const liste = loop.antwort("tel1", a2) as {
      status: number;
      body: { profile: { name: string }[] };
    };
    expect(liste.body.profile.map((p) => p.name)).toEqual(["Coco"]);
  });

  it("APP-NEUSTART: save.write → frischer Server auf derselben Storage → save.load", async () => {
    const storage = createMemoryStorage();
    const clock = createTestClock(1_000_000);

    // Abend 1: Match läuft, GM sichert nach Slot 1, dann „stirbt die App".
    const loop1 = createLoopback();
    server = startStandaloneServer({
      bridge: loop1.bridge,
      origin: "http://ipad:8080",
      katalog: katalog(150),
      storage,
      seed: 42,
      clock,
    });
    const raum1 = starteMatch(loop1);
    await mikrotasks();
    const aSave = loop1.sende("gm", "gm.cmd", { cmd: "save.write", args: { slot: 1 }, cmdId: "s" });
    await mikrotasks();
    expect((loop1.antwort("gm", aSave) as { ok: boolean }).ok).toBe(true);
    server.stop();

    // Abend 2 („App neu gestartet"): NEUER Server, GLEICHE Storage (=IndexedDB).
    const loop2 = createLoopback();
    server = startStandaloneServer({
      bridge: loop2.bridge,
      origin: "http://ipad:8080",
      katalog: katalog(150),
      storage,
      seed: 43,
      clock,
    });
    // Der manuelle Slot wird NICHT automatisch wiederbelebt (nur Autosaves) —
    // der GM lädt ihn bewusst aus der frischen Lobby.
    loop2.verbinde("screen");
    const a1 = loop2.sende("screen", "room.create", { role: "screen", origin: "http://x" });
    const raum2 = loop2.antwort("screen", a1) as { code: string; gmPin: string };
    loop2.verbinde("gm");
    loop2.sende("gm", "hello", { roomCode: raum2.code, role: "gm", gmPin: raum2.gmPin });
    const aLoad = loop2.sende("gm", "gm.cmd", { cmd: "save.load", args: { slot: 1 }, cmdId: "l" });
    await mikrotasks();
    expect((loop2.antwort("gm", aLoad) as { ok: boolean }).ok).toBe(true);

    // Der Raum läuft wieder unter dem ALTEN Code (Join-URLs/Token der Telefone
    // bleiben gültig) und steht mitten im Match statt in der Lobby.
    const raum = server.manager.finde(raum1.code);
    expect(raum).not.toBeNull();
    expect(raum?.state.phase).not.toBe("lobby");
  });

  it("Autosave-Tick schreibt saves/auto/<matchId>.json (30-s-Crash-Schutz)", async () => {
    const storage = createMemoryStorage();
    const clock = createTestClock(0);
    const loop = createLoopback();
    server = startStandaloneServer({
      bridge: loop.bridge,
      origin: "http://ipad:8080",
      katalog: katalog(150),
      storage,
      seed: 5,
      clock,
    });
    const raum = starteMatch(loop);
    await mikrotasks();
    const matchId = server.manager.finde(raum.code)?.matchId ?? "";
    expect(matchId).not.toBe("");
    server.manager.tickAlle(); // erster Tick eines laufenden Matches ⇒ Autosave
    await mikrotasks();
    const autosave = await storage.readJson<{ matchId: string; auto: boolean }>(
      `saves/auto/${matchId}.json`,
    );
    expect(autosave?.auto).toBe(true);
    expect(autosave?.matchId).toBe(matchId);
  });

  it("Boot-Wiederbelebung: frischer Autosave belebt das Match beim Neustart", async () => {
    const storage = createMemoryStorage();
    const clock = createTestClock(0);

    const loop1 = createLoopback();
    server = startStandaloneServer({
      bridge: loop1.bridge,
      origin: "http://ipad:8080",
      katalog: katalog(150),
      storage,
      seed: 5,
      clock,
    });
    const raum1 = starteMatch(loop1);
    await mikrotasks();
    server.manager.tickAlle(); // Autosave entsteht
    await mikrotasks();
    server.stop();

    clock.advance(2 * 60_000); // 2 min später — Autosave ist noch „frisch" (<10 min)
    const loop2 = createLoopback();
    server = startStandaloneServer({
      bridge: loop2.bridge,
      origin: "http://ipad:8080",
      katalog: katalog(150),
      storage,
      seed: 6,
      clock,
    });
    const belebt = await server.wiederbelebt;
    expect(belebt).toHaveLength(1);
    expect(belebt[0].code).toBe(raum1.code);
    expect(belebt[0].phase).not.toBe("lobby");
    expect(server.manager.finde(raum1.code)).not.toBeNull();
  });
});

// Tunnel-Manager-Tests: URL-Parsing aus ECHTEM cloudflared-stderr (Mitschnitt
// eines realen Quick-Tunnel-Laufs), Status-Maschine (aus→startet→laeuft→aus/
// fehler), Nicht-installiert-Pfad mit Install-Einzeilern und Neustart-
// Sicherheit — alles mit injiziertem Fake-Spawn (kein cloudflared nötig).
import { describe, expect, it } from "vitest";
import {
  createTunnelManager,
  installHinweise,
  parseTunnelUrl,
  type TunnelKind,
  type TunnelManager,
} from "./tunnel";

// ---------- Fake-Kind-Prozess (strukturell kompatibel zu ChildProcess) ----------

interface FakeKind extends TunnelKind {
  kills: string[];
  stderrData(text: string): void;
  stdoutData(text: string): void;
  exitMit(code: number | null): void;
  fehlerMit(err: Error): void;
}

function fakeKind(): FakeKind {
  const handler = new Map<string, ((...args: unknown[]) => void)[]>();
  const merke =
    (quelle: string) =>
    (event: string, cb: (...args: unknown[]) => void): void => {
      const key = `${quelle}:${event}`;
      handler.set(key, [...(handler.get(key) ?? []), cb]);
    };
  const feuere = (key: string, ...args: unknown[]): void => {
    for (const cb of handler.get(key) ?? []) cb(...args);
  };
  const kind: FakeKind = {
    stdout: { on: merke("stdout") as never },
    stderr: { on: merke("stderr") as never },
    on: merke("kind") as never,
    kills: [],
    kill(signal?: NodeJS.Signals) {
      kind.kills.push(signal ?? "SIGTERM");
    },
    stderrData: (text) => feuere("stderr:data", Buffer.from(text)),
    stdoutData: (text) => feuere("stdout:data", Buffer.from(text)),
    exitMit: (code) => feuere("kind:exit", code, null),
    fehlerMit: (err) => feuere("kind:error", err),
  };
  return kind;
}

interface Welt {
  manager: TunnelManager;
  kinder: FakeKind[];
  spawns: { cmd: string; args: string[] }[];
}

function welt(opts: { port?: number; plattform?: NodeJS.Platform } = {}): Welt {
  const kinder: FakeKind[] = [];
  const spawns: { cmd: string; args: string[] }[] = [];
  const manager = createTunnelManager({
    port: opts.port ?? 8080,
    plattform: opts.plattform ?? "linux",
    spawnFn: (cmd, args) => {
      spawns.push({ cmd, args });
      const kind = fakeKind();
      kinder.push(kind);
      return kind;
    },
  });
  return { manager, kinder, spawns };
}

// Echtes cloudflared-2026.8.2-stderr (Mitschnitt, VM-Lauf) — Banner-Links und
// URL-Kasten exakt wie im Original; die zugewiesene URL steht im |…|-Kasten.
const ECHTES_LOG =
  [
    "2026-08-16T14:50:02Z INF Thank you for trying Cloudflare Tunnel. Doing so, without a Cloudflare account, is a quick way to experiment and try it out. However, be aware that these account-less Tunnels have no uptime guarantee, are subject to the Cloudflare Online Services Terms of Use (https://www.cloudflare.com/website-terms/), and Cloudflare reserves the right to investigate your use of Tunnels for violations of such terms. If you intend to use Tunnels in production you should use a pre-created named tunnel by following: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps",
    "2026-08-16T14:50:02Z INF Requesting new quick Tunnel on trycloudflare.com...",
    "2026-08-16T14:50:13Z INF +--------------------------------------------------------------------------------------------+",
    "2026-08-16T14:50:13Z INF |  Your quick Tunnel has been created! Visit it at (it may take some time to be reachable):  |",
    "2026-08-16T14:50:13Z INF |  https://triple-added-served-pens.trycloudflare.com                                        |",
    "2026-08-16T14:50:13Z INF +--------------------------------------------------------------------------------------------+",
  ].join("\n") + "\n";

describe("tunnel: URL-Parsing aus Beispiel-stderr", () => {
  it("findet die zugewiesene URL im echten cloudflared-Log-Kasten", () => {
    const urls = ECHTES_LOG.split("\n")
      .map(parseTunnelUrl)
      .filter((u) => u !== null);
    expect(urls).toEqual(["https://triple-added-served-pens.trycloudflare.com"]);
  });

  it("ignoriert Banner-Links (developers.cloudflare.com, website-terms)", () => {
    expect(
      parseTunnelUrl(
        "INF … following: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps",
      ),
    ).toBeNull();
    expect(parseTunnelUrl("… (https://www.cloudflare.com/website-terms/) …")).toBeNull();
  });

  it("ignoriert api.trycloudflare.com (API-Endpunkt in FEHLER-Zeilen)", () => {
    expect(
      parseTunnelUrl(
        'ERR failed to request quick Tunnel: Post "https://api.trycloudflare.com/tunnel": dial tcp: lookup api.trycloudflare.com: no such host',
      ),
    ).toBeNull();
  });
});

describe("tunnel: Status-Maschine", () => {
  it("aus → startet → laeuft(url) mit dem echten Log als stderr", () => {
    const w = welt({ port: 8093 });
    expect(w.manager.status().phase).toBe("aus");
    const nachStart = w.manager.start();
    expect(nachStart.phase).toBe("startet");
    expect(w.spawns).toEqual([
      { cmd: "cloudflared", args: ["tunnel", "--url", "http://localhost:8093"] },
    ]);
    w.kinder[0].stderrData(ECHTES_LOG);
    expect(w.manager.status()).toMatchObject({
      phase: "laeuft",
      url: "https://triple-added-served-pens.trycloudflare.com",
      fehler: null,
    });
  });

  it("parst die URL auch, wenn sie über zwei stderr-Chunks zerteilt ankommt", () => {
    const w = welt();
    w.manager.start();
    w.kinder[0].stderrData("INF |  https://halbe-banane-");
    expect(w.manager.status().phase).toBe("startet");
    w.kinder[0].stderrData("split.trycloudflare.com  |\n");
    expect(w.manager.status().url).toBe("https://halbe-banane-split.trycloudflare.com");
  });

  it("liest zur Sicherheit auch stdout (falls cloudflared dorthin loggt)", () => {
    const w = welt();
    w.manager.start();
    w.kinder[0].stdoutData("|  https://stdout-affe.trycloudflare.com  |\n");
    expect(w.manager.status()).toMatchObject({
      phase: "laeuft",
      url: "https://stdout-affe.trycloudflare.com",
    });
  });

  it("stop(): läuft → aus, Kind bekommt SIGTERM, spätes exit bleibt folgenlos", () => {
    const w = welt();
    w.manager.start();
    w.kinder[0].stderrData(ECHTES_LOG);
    const nachStop = w.manager.stop();
    expect(nachStop).toMatchObject({ phase: "aus", url: null, fehler: null });
    expect(w.kinder[0].kills).toEqual(["SIGTERM"]);
    // Das gekillte Kind meldet seinen exit später — KEIN Umkippen auf "fehler".
    w.kinder[0].exitMit(0);
    expect(w.manager.status().phase).toBe("aus");
  });

  it("Kind stirbt VOR der URL (z. B. ohne Internet) ⇒ fehler mit klarer Meldung", () => {
    const w = welt();
    w.manager.start();
    w.kinder[0].exitMit(1);
    const s = w.manager.status();
    expect(s.phase).toBe("fehler");
    expect(s.fehler).toContain("Code 1");
    expect(s.url).toBeNull();
  });

  it("laufender Tunnel-Prozess stirbt ⇒ fehler (Neustart über den Knopf)", () => {
    const w = welt();
    w.manager.start();
    w.kinder[0].stderrData(ECHTES_LOG);
    w.kinder[0].exitMit(137);
    expect(w.manager.status().phase).toBe("fehler");
    expect(w.manager.status().fehler).toContain("unerwartet beendet");
  });
});

describe("tunnel: nicht installiert (ENOENT statt Crash)", () => {
  it("spawn-ENOENT ⇒ phase nicht-installiert mit Install-Einzeilern je OS", () => {
    const w = welt({ plattform: "linux" });
    w.manager.start();
    const err = new Error("spawn cloudflared ENOENT") as NodeJS.ErrnoException;
    err.code = "ENOENT";
    w.kinder[0].fehlerMit(err);
    const s = w.manager.status();
    expect(s.phase).toBe("nicht-installiert");
    expect(s.fehler).toContain("nicht installiert");
    expect(s.installHinweise).toHaveLength(3);
    // Server-OS (linux) steht zuerst, macOS/Windows bleiben als Referenz.
    expect(s.installHinweise[0]).toContain("cloudflared-linux-amd64.deb");
    expect(s.installHinweise.join(" ")).toContain("brew install cloudflared");
    expect(s.installHinweise.join(" ")).toContain("winget install Cloudflare.cloudflared");
  });

  it("installHinweise: das eigene OS steht zuerst (macOS-Server ⇒ brew zuerst)", () => {
    expect(installHinweise("darwin")[0]).toContain("brew");
    expect(installHinweise("win32")[0]).toContain("winget");
    expect(installHinweise("linux")[0]).toContain("dpkg");
  });

  it("anderer spawn-Fehler (kein ENOENT) ⇒ phase fehler ohne Install-Hinweise", () => {
    const w = welt();
    w.manager.start();
    w.kinder[0].fehlerMit(new Error("EACCES: permission denied"));
    const s = w.manager.status();
    expect(s.phase).toBe("fehler");
    expect(s.installHinweise).toEqual([]);
  });
});

describe("tunnel: Neustart-Sicherheit", () => {
  it("start() während startet/laeuft startet KEIN zweites Kind", () => {
    const w = welt();
    w.manager.start();
    expect(w.manager.start().phase).toBe("startet"); // idempotent, kein Spawn
    w.kinder[0].stderrData(ECHTES_LOG);
    const nochmal = w.manager.start();
    expect(nochmal.phase).toBe("laeuft"); // liefert den AKTUELLEN Status
    expect(w.spawns).toHaveLength(1);
  });

  it("nach fehler/stop spawnt der nächste start() frisch und erreicht laeuft", () => {
    const w = welt();
    w.manager.start();
    w.kinder[0].exitMit(1); // ⇒ fehler
    expect(w.manager.status().phase).toBe("fehler");
    w.manager.start();
    expect(w.spawns).toHaveLength(2);
    w.kinder[1].stderrData(ECHTES_LOG);
    expect(w.manager.status().phase).toBe("laeuft");
    // … und einmal komplett stop → start → laeuft (Neustart-Roundtrip).
    w.manager.stop();
    w.manager.start();
    w.kinder[2].stderrData(ECHTES_LOG);
    expect(w.manager.status().phase).toBe("laeuft");
    // Daten des ALTEN (gestoppten) Kinds können den frischen Lauf nie stören.
    w.kinder[1].stderrData("|  https://alte-leiche.trycloudflare.com  |\n");
    expect(w.manager.status().url).toBe("https://triple-added-served-pens.trycloudflare.com");
  });

  it("onStatus-Listener sieht die Übergänge in Reihenfolge (startet→laeuft→aus)", () => {
    const w = welt();
    const phasen: string[] = [];
    w.manager.onStatus((s) => phasen.push(s.phase));
    w.manager.start();
    w.kinder[0].stderrData(ECHTES_LOG);
    w.manager.stop();
    expect(phasen).toEqual(["startet", "laeuft", "aus"]);
  });
});

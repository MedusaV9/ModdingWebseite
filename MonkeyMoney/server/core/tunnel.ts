// INTERNET-LINK (W4): Cloudflare-Quick-Tunnel als Kind-Prozess — direkt aus
// der App-UI startbar (Screen-Lobby „Link erstellen", GM-Show-Zone Start/Stop).
// Der Manager kapselt EINE Zustands-Maschine (aus → startet → laeuft(url) →
// aus | fehler) um `cloudflared tunnel --url http://localhost:<port>` und
// parst die zugewiesene trycloudflare.com-URL aus dem stderr-Log (dasselbe
// Muster wie tools/tunnel/start.sh). Fehlendes cloudflared ist KEIN Crash,
// sondern die ehrliche Phase "nicht-installiert" mit Install-Einzeilern je OS.
// Neustart-sicher: start() während startet/laeuft startet KEIN zweites Kind;
// nach stop()/fehler spawnt der nächste start() frisch. Der Tunnel endet mit
// dem Server (stop()-Hook in core/index.ts) — Quick-URLs sind ohnehin flüchtig.
import { spawn } from "node:child_process";
import type { TunnelStatusMsg } from "../../shared/protocol";

/** Minimal-Strom (stdout/stderr) — injizierbar für Tests (vitest = Node pur). */
export interface KindStrom {
  on(event: "data", cb: (chunk: Buffer | string) => void): unknown;
}

/** Minimal-Oberfläche des cloudflared-Kind-Prozesses (ChildProcess erfüllt sie). */
export interface TunnelKind {
  stdout: KindStrom | null;
  stderr: KindStrom | null;
  on(event: "error", cb: (err: Error) => void): unknown;
  on(event: "exit", cb: (code: number | null, signal: string | null) => void): unknown;
  kill(signal?: NodeJS.Signals): unknown;
}

export interface TunnelManagerOpts {
  /** Lokaler Server-Port, den der Tunnel öffentlich macht. */
  port: number;
  /** Spawn-Fabrik — injizierbar für Tests (Default: echtes child_process.spawn). */
  spawnFn?: (cmd: string, args: string[]) => TunnelKind;
  /** Server-OS für die Install-Einzeiler-Reihenfolge (Default: process.platform). */
  plattform?: NodeJS.Platform;
}

export interface TunnelManager {
  status(): TunnelStatusMsg;
  /** Tunnel anfordern — idempotent: läuft/startet schon ⇒ aktueller Status. */
  start(): TunnelStatusMsg;
  /** Tunnel beenden (Kind-Prozess killen) — idempotent, Status sofort "aus". */
  stop(): TunnelStatusMsg;
  /** Status-Übergänge abonnieren (Socket-Schicht broadcastet an Screen+GM). */
  onStatus(cb: (status: TunnelStatusMsg) => void): void;
}

/** Die zugewiesene Quick-Tunnel-URL aus einer cloudflared-Log-Zeile ziehen.
 * NUR *.trycloudflare.com zählt — api.trycloudflare.com ist der API-Endpunkt
 * (taucht in FEHLER-Zeilen auf) und die Banner-Links (developers.cloudflare.com
 * etc.) matchen das Muster gar nicht erst. */
export function parseTunnelUrl(zeile: string): string | null {
  const treffer = /https:\/\/[a-z0-9][a-z0-9-]*\.trycloudflare\.com/.exec(zeile);
  if (treffer === null) return null;
  if (treffer[0] === "https://api.trycloudflare.com") return null;
  return treffer[0];
}

/** Install-Einzeiler je OS — das Server-OS steht zuerst (die Meldung im UI
 * zeigt dem Host direkt SEINEN Befehl, die anderen bleiben als Referenz). */
export function installHinweise(plattform: NodeJS.Platform): string[] {
  const alle: [NodeJS.Platform, string][] = [
    ["darwin", "macOS: brew install cloudflared"],
    ["win32", "Windows: winget install Cloudflare.cloudflared"],
    [
      "linux",
      "Debian/Ubuntu: curl -fL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o /tmp/cloudflared.deb && sudo dpkg -i /tmp/cloudflared.deb",
    ],
  ];
  return [...alle]
    .sort((a, b) => Number(b[0] === plattform) - Number(a[0] === plattform))
    .map(([, text]) => text);
}

/** Zeilen-Puffer: Chunks können mitten in der Zeile enden (URL über 2 Chunks). */
function zeilenParser(onZeile: (zeile: string) => void): (chunk: Buffer | string) => void {
  let rest = "";
  return (chunk) => {
    rest += String(chunk);
    const zeilen = rest.split("\n");
    rest = zeilen.pop() ?? "";
    for (const zeile of zeilen) onZeile(zeile);
    // Die URL-Zeile kann als letzter Chunk OHNE \n enden — Rest mitprüfen,
    // parseTunnelUrl ist auf Teilzeilen sicher (matcht nur komplette URLs).
    if (parseTunnelUrl(rest) !== null) {
      onZeile(rest);
      rest = "";
    }
  };
}

export function createTunnelManager(opts: TunnelManagerOpts): TunnelManager {
  const spawnFn =
    opts.spawnFn ??
    ((cmd: string, args: string[]): TunnelKind =>
      spawn(cmd, args, { stdio: ["ignore", "pipe", "pipe"] }));
  const plattform = opts.plattform ?? process.platform;

  let status: TunnelStatusMsg = { phase: "aus", url: null, fehler: null, installHinweise: [] };
  let kind: TunnelKind | null = null;
  // Generation-Zähler: stop()/error erhöhen ihn — Events des ALTEN Kinds
  // (später eintrudelnde exit/data) können den frischen Zustand nie umwerfen.
  let generation = 0;
  const listeners: ((status: TunnelStatusMsg) => void)[] = [];

  function setStatus(neu: TunnelStatusMsg): void {
    status = neu;
    for (const cb of listeners) cb(status);
  }

  function start(): TunnelStatusMsg {
    // Neustart-sicher: läuft/startet schon ⇒ KEIN zweites Kind.
    if (status.phase === "startet" || status.phase === "laeuft") return status;
    generation += 1;
    const gen = generation;
    setStatus({ phase: "startet", url: null, fehler: null, installHinweise: [] });

    let neuesKind: TunnelKind;
    try {
      neuesKind = spawnFn("cloudflared", ["tunnel", "--url", `http://localhost:${opts.port}`]);
    } catch (err) {
      setStatus({
        phase: "fehler",
        url: null,
        fehler: `cloudflared-Start fehlgeschlagen: ${String(err)}`,
        installHinweise: [],
      });
      return status;
    }
    kind = neuesKind;

    const aufZeile = (zeile: string): void => {
      if (gen !== generation) return;
      const url = parseTunnelUrl(zeile);
      if (url !== null && status.phase === "startet") {
        setStatus({ phase: "laeuft", url, fehler: null, installHinweise: [] });
      }
    };
    // cloudflared loggt auf stderr — stdout sicherheitshalber mitlesen.
    neuesKind.stderr?.on("data", zeilenParser(aufZeile));
    neuesKind.stdout?.on("data", zeilenParser(aufZeile));

    neuesKind.on("error", (err) => {
      if (gen !== generation) return;
      generation += 1; // exit/close des kaputten Kinds ignorieren
      kind = null;
      if ((err as NodeJS.ErrnoException).code === "ENOENT") {
        setStatus({
          phase: "nicht-installiert",
          url: null,
          fehler:
            "cloudflared ist auf dem Server-PC nicht installiert — einmal installieren, dann klappt der Internet-Link:",
          installHinweise: installHinweise(plattform),
        });
      } else {
        setStatus({
          phase: "fehler",
          url: null,
          fehler: `cloudflared-Fehler: ${err.message}`,
          installHinweise: [],
        });
      }
    });

    neuesKind.on("exit", (code) => {
      if (gen !== generation) return;
      generation += 1;
      kind = null;
      setStatus({
        phase: "fehler",
        url: null,
        fehler:
          status.phase === "startet"
            ? `cloudflared beendete sich (Code ${code ?? "?"}), bevor eine URL zugewiesen wurde — nochmal versuchen (Internet nötig).`
            : `Tunnel-Prozess unerwartet beendet (Code ${code ?? "?"}) — „Link erstellen“ startet ihn neu.`,
        installHinweise: [],
      });
    });

    return status;
  }

  function stop(): TunnelStatusMsg {
    generation += 1; // exit-Event des gekillten Kinds zählt nicht als Fehler
    if (kind !== null) {
      try {
        kind.kill("SIGTERM");
      } catch {
        /* Kind ist schon weg — Ziel erreicht */
      }
      kind = null;
    }
    if (status.phase !== "aus") {
      setStatus({ phase: "aus", url: null, fehler: null, installHinweise: [] });
    }
    return status;
  }

  return {
    status: () => status,
    start,
    stop,
    onStatus: (cb) => {
      listeners.push(cb);
    },
  };
}

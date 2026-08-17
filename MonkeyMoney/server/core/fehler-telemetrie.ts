// Client-Fehler-Telemetrie (Gegenstück zu client/shared/fehler-telemetrie.ts):
// POST /api/fehler nimmt {msg, stack, phase, minigameId, url, ts} an, drosselt
// auf 10 Meldungen/min/IP und hängt JSONL-Zeilen an <dataDir>/fehler.log.
// GET /api/admin/fehler (PIN wie /api/admin/reports) liefert die letzten 20 —
// die Admin-Seite (server/meta/admin-ui.ts) zeigt sie als 6. Karte.
import express, { type Express } from "express";
import { appendFile, readFile } from "node:fs/promises";
import { join } from "node:path";
import { z } from "zod";

/** Wire-Schema — Längen HART gekappt (Client kappt schon, Server traut nicht). */
const FehlerMeldungSchema = z.object({
  msg: z.string().min(1).max(400),
  stack: z.string().max(1_500).nullish(),
  phase: z.string().max(40).nullish(),
  minigameId: z.string().max(60).nullish(),
  url: z.string().max(300).nullish(),
  ts: z.number().int().nullish(),
});

export interface FehlerEintrag {
  msg: string;
  stack: string | null;
  phase: string | null;
  minigameId: string | null;
  url: string | null;
  ts: number;
}

/** Meldung validieren + normalisieren; null bei Müll (Netz = Systemgrenze). */
export function parseFehlerMeldung(body: unknown, serverNow: number): FehlerEintrag | null {
  const parsed = FehlerMeldungSchema.safeParse(body);
  if (!parsed.success) return null;
  const m = parsed.data;
  return {
    msg: m.msg,
    stack: m.stack ?? null,
    phase: m.phase ?? null,
    minigameId: m.minigameId ?? null,
    url: m.url ?? null,
    // Client-ts nur übernehmen, wenn plausibel (±24 h) — sonst Server-Zeit.
    ts: m.ts != null && Math.abs(m.ts - serverNow) < 86_400_000 ? m.ts : serverNow,
  };
}

/** Sliding-Window-Drossel: true = darf, false = gedrosselt. Pro Schlüssel
 * (IP) bleiben nur die Zeitstempel des aktuellen Fensters im Speicher. */
export function createRateLimiter(
  limit: number,
  fensterMs: number,
  now: () => number,
): (key: string) => boolean {
  const proKey = new Map<string, number[]>();
  return (key: string): boolean => {
    const t = now();
    const frisch = (proKey.get(key) ?? []).filter((alt) => t - alt < fensterMs);
    if (frisch.length >= limit) {
      proKey.set(key, frisch);
      return false;
    }
    frisch.push(t);
    proKey.set(key, frisch);
    // Speicher-Hygiene: tote Keys nicht ewig sammeln (Map wächst sonst pro IP).
    if (proKey.size > 10_000) proKey.clear();
    return true;
  };
}

/** Letzte `anzahl` JSONL-Zeilen aus fehler.log lesen (fehlende Datei = leer). */
export async function letzteFehler(dataDir: string, anzahl = 20): Promise<FehlerEintrag[]> {
  let roh: string;
  try {
    roh = await readFile(join(dataDir, "fehler.log"), "utf8");
  } catch {
    return [];
  }
  const eintraege: FehlerEintrag[] = [];
  for (const zeile of roh
    .split("\n")
    .filter((z) => z.trim().length > 0)
    .slice(-anzahl)) {
    try {
      eintraege.push(JSON.parse(zeile) as FehlerEintrag);
    } catch {
      /* halbe Zeile (Crash beim Schreiben) — überspringen */
    }
  }
  return eintraege.reverse(); // neueste zuerst (Admin-Anzeige)
}

export interface FehlerApiOptions {
  dataDir: string;
  /** Admin-PIN (wie /api/admin/reports) — null ⇒ GET /api/admin/fehler ist 503. */
  adminPin: string | null;
  /** Injizierbare Uhr (Tests) — Default: OS-Uhr (core darf, TECH-SPEC §2). */
  now?: () => number;
  /** Drossel-Parameter (Tests) — Default 10 Meldungen / 60 s / IP. */
  limit?: number;
  fensterMs?: number;
}

export function registriereFehlerApi(app: Express, opts: FehlerApiOptions): void {
  const now = opts.now ?? ((): number => Date.now());
  const darf = createRateLimiter(opts.limit ?? 10, opts.fensterMs ?? 60_000, now);
  app.use("/api/fehler", express.json({ limit: "8kb" }));

  app.post("/api/fehler", (req, res) => {
    if (!darf(req.ip ?? "unbekannt")) {
      return void res.status(429).json({ ok: false, error: "zu-viele-meldungen" });
    }
    const eintrag = parseFehlerMeldung(req.body, now());
    if (eintrag === null) return void res.status(400).json({ ok: false, error: "ungueltig" });
    // Fire-and-forget: der Client wartet nicht auf die Platte (keepalive-POST).
    void appendFile(join(opts.dataDir, "fehler.log"), JSON.stringify(eintrag) + "\n").catch((err) =>
      console.error("fehler.log-Schreibfehler:", err),
    );
    res.json({ ok: true });
  });

  app.get("/api/admin/fehler", (req, res) => {
    if (opts.adminPin === null) return void res.status(503).json({ error: "admin-deaktiviert" });
    const pin = req.header("x-admin-pin") ?? String(req.query.pin ?? "");
    if (pin !== opts.adminPin) return void res.status(403).json({ error: "pin-falsch" });
    void letzteFehler(opts.dataDir, 20)
      .then((fehler) => res.json({ fehler }))
      .catch(() => res.status(500).json({ error: "lese-fehler" }));
  });
}

// Wächter: POST /api/fehler (JSONL + 10/min/IP-Drossel) und die Admin-Sicht
// GET /api/admin/fehler (letzte 20, PIN-Gate) — echter Express-Roundtrip über
// einen Ephemeral-Port (Node-fetch), Platte = frisches Temp-Verzeichnis.
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { AddressInfo } from "node:net";
import express from "express";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import {
  createRateLimiter,
  letzteFehler,
  parseFehlerMeldung,
  registriereFehlerApi,
} from "./fehler-telemetrie";

describe("Rate-Limiter (Sliding Window)", () => {
  it("erlaubt 10 pro Fenster, drosselt die 11., gibt nach Fenster-Ablauf frei", () => {
    let t = 0;
    const darf = createRateLimiter(10, 60_000, () => t);
    for (let i = 0; i < 10; i++) expect(darf("ip1")).toBe(true);
    expect(darf("ip1")).toBe(false);
    expect(darf("ip2")).toBe(true); // andere IP hat ihr eigenes Fenster
    t = 59_999;
    expect(darf("ip1")).toBe(false);
    t = 60_001; // die ersten Meldungen fallen aus dem Fenster
    expect(darf("ip1")).toBe(true);
  });
});

describe("parseFehlerMeldung (Wire-Validierung)", () => {
  it("normalisiert Optionales und ersetzt unplausible Client-Zeit", () => {
    const jetzt = 1_000_000_000;
    const ok = parseFehlerMeldung({ msg: "boom", ts: jetzt - 5_000 }, jetzt);
    expect(ok).toMatchObject({ msg: "boom", stack: null, phase: null, ts: jetzt - 5_000 });
    // Uralt-/Zukunfts-ts (> ±24 h) ⇒ Server-Zeit.
    expect(parseFehlerMeldung({ msg: "boom", ts: 1 }, jetzt)!.ts).toBe(jetzt);
    expect(parseFehlerMeldung({ msg: "" }, jetzt)).toBeNull();
    expect(parseFehlerMeldung("quatsch", jetzt)).toBeNull();
    expect(parseFehlerMeldung({ msg: "x".repeat(500) }, jetzt)).toBeNull(); // Server traut nicht
  });
});

describe("POST /api/fehler + GET /api/admin/fehler (Express-Roundtrip)", () => {
  let dataDir: string;
  let basis: string;
  let server: ReturnType<express.Express["listen"]>;
  // Injizierte Uhr: Tests spulen das Drossel-Fenster gezielt vor.
  let fakeNow = 1_000_000_000;

  beforeAll(async () => {
    dataDir = await mkdtemp(join(tmpdir(), "mm-fehler-"));
    const app = express();
    registriereFehlerApi(app, { dataDir, adminPin: "1234", now: () => fakeNow });
    server = app.listen(0);
    await new Promise((resolve) => server.once("listening", resolve));
    basis = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  });

  afterAll(async () => {
    server.close();
    await rm(dataDir, { recursive: true, force: true });
  });

  const post = (body: unknown): Promise<Response> =>
    fetch(`${basis}/api/fehler`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });

  it("nimmt 10 Meldungen an, drosselt die 11. (429), schreibt JSONL", async () => {
    for (let i = 0; i < 10; i++) {
      const res = await post({
        msg: `TypeError ${i}`,
        stack: "at kaputt()",
        phase: "frage",
        minigameId: "vier-lianen",
        url: "/j/AFFE",
      });
      expect(res.status).toBe(200);
    }
    const gedrosselt = await post({ msg: "einer zu viel" });
    expect(gedrosselt.status).toBe(429);
    expect((await gedrosselt.json()).error).toBe("zu-viele-meldungen");

    const zeilen = (await readFile(join(dataDir, "fehler.log"), "utf8"))
      .split("\n")
      .filter((z) => z.length > 0);
    expect(zeilen).toHaveLength(10); // die gedrosselte Meldung landet NICHT auf Platte
    expect(JSON.parse(zeilen[0])).toMatchObject({
      msg: "TypeError 0",
      phase: "frage",
      minigameId: "vier-lianen",
    });
  });

  it("weist Müll mit 400 ab (kein JSONL-Gift)", async () => {
    fakeNow += 61_000; // frisches Drossel-Fenster (die 10 oben sind abgelaufen)
    const res = await post({ keineMsg: true });
    expect(res.status).toBe(400);
  });

  it("Admin-Sicht: PIN-Gate + letzte Einträge neueste-zuerst", async () => {
    const falsch = await fetch(`${basis}/api/admin/fehler`, {
      headers: { "x-admin-pin": "0000" },
    });
    expect(falsch.status).toBe(403);
    const res = await fetch(`${basis}/api/admin/fehler`, { headers: { "x-admin-pin": "1234" } });
    expect(res.status).toBe(200);
    const { fehler } = (await res.json()) as { fehler: { msg: string }[] };
    expect(fehler.length).toBeGreaterThanOrEqual(10);
    expect(fehler.length).toBeLessThanOrEqual(20);
    expect(fehler[0].msg).toBe("TypeError 9"); // neueste zuerst
  });

  it("letzteFehler: fehlende Datei ⇒ leere Liste (frischer Server)", async () => {
    expect(await letzteFehler(join(dataDir, "gibt-es-nicht"))).toEqual([]);
  });
});

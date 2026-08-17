// Bananen-Pass-Store: XP-Gutschrift mit Stufen-Grenzen, Belohnungs-Ausschüttung
// (nur NEU erreichte Stufen), 30er-Deckel und der Kalendermonat-Rollover mit
// Archiv (nicht Erreichtes verfällt — Zeit via Test-Clock injiziert).
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { PASS_STUFEN } from "../../shared/quests";
import { createTestClock } from "../../shared/time";
import { createFileStorage } from "../persistence/storage";
import { createSeasonStore, type SeasonStore } from "./season";

const AUG = Date.UTC(2026, 7, 15); // Saison "2026-08" (S1 „Dschungel-Auftakt")
const SEP = Date.UTC(2026, 8, 2); // Saison "2026-09"

let dir: string;
let clock: ReturnType<typeof createTestClock>;
let store: SeasonStore;

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "mm-pass-"));
  clock = createTestClock(AUG);
  store = createSeasonStore(createFileStorage(dir), clock);
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

describe("season: XP-Vergabe + Stufen", () => {
  it("XP akkumuliert; Stufen folgen der Kurve; Belohnungen nur fürs NEU Erreichte", async () => {
    const e1 = await store.gibXp("pr_a", 250); // → Stufe 2 (100er-Schritte)
    expect(e1).toMatchObject({ xpVorher: 0, xpNeu: 250, stufeVorher: 0, stufeNeu: 2 });
    expect(e1.belohnungen.map((b) => b.stufe)).toEqual([1, 2]);
    expect(e1.belohnungen.every((b) => b.art === "at")).toBe(true);

    const e2 = await store.gibXp("pr_a", 250); // 500 XP → Stufe 5 (S1-Item!)
    expect(e2.stufeNeu).toBe(5);
    expect(e2.belohnungen.map((b) => b.stufe)).toEqual([3, 4, 5]);
    expect(e2.belohnungen.at(-1)).toMatchObject({
      art: "item",
      itemId: "titel-s1-dschungel-novize",
    });
    const stand = await store.stand("pr_a");
    expect(stand.verdient).toEqual(["titel-s1-dschungel-novize"]);
    expect(stand.atBonus).toBe(100 + 100 + 150 + 150); // Stufen 1-4
  });

  it("Stufe 30 ist der Deckel: Über-XP hebt weder Stufe noch schüttet doppelt aus", async () => {
    const e = await store.gibXp("pr_b", 999_999);
    expect(e.stufeNeu).toBe(PASS_STUFEN);
    expect(e.belohnungen).toHaveLength(PASS_STUFEN);
    const nochmal = await store.gibXp("pr_b", 500);
    expect(nochmal.stufeNeu).toBe(PASS_STUFEN);
    expect(nochmal.belohnungen).toEqual([]); // alles schon ausgeschüttet
    const stand = await store.stand("pr_b");
    expect(stand.verdient).toHaveLength(6); // die 6 S1-Exklusiven
  });

  it("negative/krumme XP-Werte können den Stand nie senken", async () => {
    await store.gibXp("pr_c", 300);
    const e = await store.gibXp("pr_c", -500);
    expect(e.xpNeu).toBe(300);
    expect(e.stufeNeu).toBe(e.stufeVorher);
  });
});

describe("season: Kalendermonat-Rollover + Archiv", () => {
  it("neue Saison: Fortschritt auf 0, alter Stand wandert ins Archiv", async () => {
    await store.gibXp("pr_a", 1100); // S1: Stufe 10 (S11 bräuchte 1.150 XP)
    clock.advance(SEP - AUG);
    const e = await store.gibXp("pr_a", 100); // erster Kontakt in S2
    expect(e).toMatchObject({ xpVorher: 0, xpNeu: 100, stufeVorher: 0, stufeNeu: 1 });
    const stand = await store.stand("pr_a");
    expect(stand.saisonId).toBe("2026-09");
    expect(stand.archiv).toHaveLength(1);
    expect(stand.archiv[0]).toMatchObject({
      saisonId: "2026-08",
      name: "Dschungel-Auftakt",
      stufe: 10,
      xp: 1100,
    });
    expect(stand.archiv[0].verdient).toEqual([
      "titel-s1-dschungel-novize",
      "namestil-s1-lianengruen",
    ]);
  });

  it("stand() rollt nur die LESE-Sicht — ohne Schreib-Zwang, ohne Datenverlust", async () => {
    await store.gibXp("pr_a", 500);
    clock.advance(SEP - AUG);
    const sicht = await store.stand("pr_a"); // virtueller Rollover
    expect(sicht.xp).toBe(0);
    expect(sicht.archiv).toHaveLength(1);
    // Die Datei ist noch unangefasst — der ECHTE Rollover kommt mit gibXp.
    clock.advance(-(SEP - AUG));
    const zurueck = await store.stand("pr_a");
    expect(zurueck.saisonId).toBe("2026-08");
    expect(zurueck.xp).toBe(500);
  });

  it("leere Saisons (0 XP) erzeugen KEINEN Archiv-Eintrag", async () => {
    await store.gibXp("pr_neu", 0);
    clock.advance(SEP - AUG);
    const stand = await store.stand("pr_neu");
    expect(stand.archiv).toEqual([]);
  });
});

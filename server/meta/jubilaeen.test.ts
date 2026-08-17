// JUBILÄUMS-ERKENNUNG (v2): Gruppen-Meilensteine aus Match-Historie-Fixtures —
// pure Erkennung (Schwellen, nie doppelt feiern), Karten-Bau und der Store
// (In-Memory-Cache + sequenzielle Persistenz über das Storage-Interface).
import { describe, expect, it } from "vitest";
import type { Storage } from "../persistence/storage";
import {
  baueJubilaeumsView,
  createJubilaeenStore,
  erkenneMeilensteine,
  gruppenKey,
  leereGruppe,
  MONEY_MEILENSTEIN,
  type JubilaeumsGruppe,
} from "./jubilaeen";

/** In-Memory-Storage (nur JSON-Teil — Jubiläen brauchen nicht mehr). */
function memStorage(): Storage & { dateien: Map<string, unknown> } {
  const dateien = new Map<string, unknown>();
  return {
    dateien,
    readJson: <T>(p: string) => Promise.resolve((dateien.get(p) as T | undefined) ?? null),
    writeJsonAtomic: (p, data) => {
      dateien.set(p, JSON.parse(JSON.stringify(data)));
      return Promise.resolve();
    },
    appendLine: () => Promise.resolve(),
    readText: () => Promise.resolve(null),
    listeDateien: () => Promise.resolve([]),
    loesche: (p) => {
      dateien.delete(p);
      return Promise.resolve();
    },
    resolve: (p) => p,
  };
}

const gruppe = (patch: Partial<JubilaeumsGruppe>): JubilaeumsGruppe => ({
  ...leereGruppe(),
  ...patch,
});

describe("jubilaeen: Gruppen-Schlüssel", () => {
  it("sortiert + dedupliziert Profil-Ids (Reihenfolge egal)", () => {
    expect(gruppenKey(["b", "a", "c"])).toBe("a+b+c");
    expect(gruppenKey(["a", "b"])).toBe(gruppenKey(["b", "a", "a"]));
  });

  it("unter 2 Profilen gibt es keine Gruppe", () => {
    expect(gruppenKey(["solo"])).toBeNull();
    expect(gruppenKey([])).toBeNull();
  });
});

describe("jubilaeen: Meilenstein-Erkennung (pure, Fixtures)", () => {
  it("feiert den 10. Abend beim START des 10. Matches (9 abgeschlossene)", () => {
    expect(erkenneMeilensteine(gruppe({ matches: 9 }))).toEqual(["match-10"]);
    expect(erkenneMeilensteine(gruppe({ matches: 8 }))).toEqual([]);
    expect(erkenneMeilensteine(gruppe({ matches: 10 }))).toEqual([]);
  });

  it("kennt 25/50/100 — und feiert nie doppelt", () => {
    expect(erkenneMeilensteine(gruppe({ matches: 24 }))).toEqual(["match-25"]);
    expect(erkenneMeilensteine(gruppe({ matches: 49 }))).toEqual(["match-50"]);
    expect(erkenneMeilensteine(gruppe({ matches: 99 }))).toEqual(["match-100"]);
    expect(erkenneMeilensteine(gruppe({ matches: 24, gefeiert: ["match-25"] }))).toEqual([]);
  });

  it("erste 100k Gesamt-Money feuern beim ersten Start NACH dem Überschreiten", () => {
    expect(erkenneMeilensteine(gruppe({ matches: 3, gesamtMoney: 99_999 }))).toEqual([]);
    expect(erkenneMeilensteine(gruppe({ matches: 3, gesamtMoney: MONEY_MEILENSTEIN }))).toEqual([
      "money-100k",
    ]);
    expect(
      erkenneMeilensteine(gruppe({ matches: 3, gesamtMoney: 150_000, gefeiert: ["money-100k"] })),
    ).toEqual([]);
  });

  it("Doppel-Jubiläum: 10. Abend UND 100k gleichzeitig", () => {
    const m = erkenneMeilensteine(gruppe({ matches: 9, gesamtMoney: 120_000 }));
    expect(m).toEqual(["match-10", "money-100k"]);
  });

  it("neue Gruppe (undefined) hat keine Meilensteine", () => {
    expect(erkenneMeilensteine(undefined)).toEqual([]);
  });
});

describe("jubilaeen: Karten-Bau (Opening-View)", () => {
  it("baut Titel, Text und Mini-Rückblick-Stats", () => {
    const g = gruppe({
      matches: 9,
      gesamtMoney: 42_000,
      rekordEndstand: 3_200,
      rekordName: "Anna",
    });
    const view = baueJubilaeumsView(g, ["match-10"]);
    expect(view?.titel).toBe("🎉 Euer 10. Abend!");
    expect(view?.matchNr).toBe(10);
    expect(view?.gesamtMoney).toBe(42_000);
    expect(view?.rekord).toEqual({ name: "Anna", endstand: 3_200 });
  });

  it("ohne Meilensteine gibt es keine Karte", () => {
    expect(baueJubilaeumsView(gruppe({ matches: 9 }), [])).toBeNull();
  });
});

describe("jubilaeen: Store (Cache + Persistenz + nie doppelt feiern)", () => {
  const PROFILE = ["prof-a", "prof-b", "prof-c"];

  it("verbucht 9 Abende, feiert den 10. — und danach NIE wieder", async () => {
    const storage = memStorage();
    const store = createJubilaeenStore(storage);
    await store.ladeInitial();
    for (let i = 0; i < 9; i++) {
      store.verbucheMatch(PROFILE, [
        { name: "Anna", balance: 900 },
        { name: "Ben", balance: 400 },
        { name: "Cleo", balance: 250 },
      ]);
    }
    expect(store.gruppe(PROFILE)?.matches).toBe(9);
    const view = store.fuerMatchStart(PROFILE);
    expect(view?.titel).toBe("🎉 Euer 10. Abend!");
    expect(view?.gesamtMoney).toBe(9 * 1550);
    expect(view?.rekord).toEqual({ name: "Anna", endstand: 900 });
    // Zweiter Start (z. B. Abbruch + Neustart): NICHT nochmal feiern.
    expect(store.fuerMatchStart(PROFILE)).toBeNull();
    // Reihenfolge der Profil-Ids ist egal (gleiche Gruppe).
    expect(store.fuerMatchStart([...PROFILE].reverse())).toBeNull();
  });

  it("100k-Meilenstein: Lifetime-Summe der Endstände triggert die Feier", async () => {
    const store = createJubilaeenStore(memStorage());
    await store.ladeInitial();
    for (let i = 0; i < 4; i++) {
      store.verbucheMatch(PROFILE, [
        { name: "Anna", balance: 20_000 },
        { name: "Ben", balance: 10_000 },
      ]);
    }
    // 4 × 30k = 120k ≥ 100k ⇒ Feier beim nächsten Start (Match Nr. 5).
    const view = store.fuerMatchStart(PROFILE);
    expect(view?.meilensteine).toEqual(["money-100k"]);
    expect(view?.titel).toBe("💰 100.000 MM geknackt!");
  });

  it("persistiert über Store-Neustarts (Datei bleibt die Wahrheit)", async () => {
    const storage = memStorage();
    const alt = createJubilaeenStore(storage);
    await alt.ladeInitial();
    for (let i = 0; i < 9; i++) alt.verbucheMatch(PROFILE, [{ name: "Anna", balance: 500 }]);
    // Writes sind fire-and-forget-sequenziell — kurz ausrollen lassen.
    await new Promise((r) => setTimeout(r, 0));
    const neu = createJubilaeenStore(storage);
    await neu.ladeInitial();
    expect(neu.gruppe(PROFILE)?.matches).toBe(9);
    expect(neu.fuerMatchStart(PROFILE)?.titel).toBe("🎉 Euer 10. Abend!");
  });

  it("Solo/Gast-Runden (unter 2 gebundene Profile) zählen nicht", async () => {
    const store = createJubilaeenStore(memStorage());
    await store.ladeInitial();
    store.verbucheMatch(["solo"], [{ name: "Anna", balance: 500 }]);
    expect(store.gruppe(["solo"])).toBeNull();
    expect(store.fuerMatchStart(["solo"])).toBeNull();
  });

  it("Negativ-Endstände (Dispo) drücken die Lifetime-Summe nicht", async () => {
    const store = createJubilaeenStore(memStorage());
    await store.ladeInitial();
    store.verbucheMatch(PROFILE, [
      { name: "Anna", balance: 800 },
      { name: "Ben", balance: -300 },
    ]);
    expect(store.gruppe(PROFILE)?.gesamtMoney).toBe(800);
  });
});

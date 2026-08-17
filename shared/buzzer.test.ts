// Buzzer-Fairness-Goldens (TECH-SPEC §3.3): Median-RTT, harter Clamp,
// +150-ms-Asymmetrie-Fall, Sammel-Fenster, Fotofinish-Los (deterministisch per Seed).
import { describe, expect, it } from "vitest";
import {
  BUZZER_FOTOFINISH_MS,
  BUZZER_SAMMELFENSTER_MS,
  clampBuzz,
  finaleBuzzZeit,
  medianRtt,
  ordneBuzzes,
  sammelfensterEnde,
} from "./buzzer";
import { createRng } from "./rng";

describe("buzzer: Median-RTT (WLAN-Ausreißer-Schutz)", () => {
  it("nimmt den Median statt des Mittelwerts", () => {
    expect(medianRtt([20, 22, 24, 26, 900])).toBe(24); // 900er-Spike egal
    expect(medianRtt([50])).toBe(50);
    expect(medianRtt([])).toBe(0);
  });
});

describe("buzzer: Clamp (Manipulations-Schutz)", () => {
  const receiveTime = 10_000;

  it("Behauptung innerhalb [receive − RTT, receive] bleibt unangetastet", () => {
    expect(clampBuzz({ pressedAtServerEst: 9_950, receiveTime, medianRtt: 80 })).toBe(9_950);
  });

  it("zu frühe Behauptung wird auf receive − medianRTT geklemmt (floor)", () => {
    // Cheater behauptet, VOR 1 Sekunde gedrückt zu haben — kriegt max. die RTT gut.
    expect(clampBuzz({ pressedAtServerEst: 9_000, receiveTime, medianRtt: 80 })).toBe(9_920);
  });

  it("Zukunfts-Behauptung wird auf receiveTime gedeckelt", () => {
    expect(clampBuzz({ pressedAtServerEst: 11_000, receiveTime, medianRtt: 80 })).toBe(10_000);
  });

  it("negative RTT-Messwerte werden ignoriert (floor nie über receiveTime)", () => {
    expect(clampBuzz({ pressedAtServerEst: 9_000, receiveTime, medianRtt: -50 })).toBe(10_000);
  });

  it("finaleBuzzZeit respektiert die Armierung (nie vor armedAt)", () => {
    expect(finaleBuzzZeit(9_980, { pressedAtServerEst: 9_950, receiveTime, medianRtt: 80 })).toBe(
      9_980,
    );
    expect(finaleBuzzZeit(9_900, { pressedAtServerEst: 9_950, receiveTime, medianRtt: 80 })).toBe(
      9_950,
    );
  });
});

describe("buzzer: +150-ms-Asymmetrie (der TECH-SPEC-Fall)", () => {
  it("beide drücken real gleichzeitig — der 150-ms-langsamere verliert NICHT", () => {
    // Spieler A: RTT 20 ms, Spieler B: RTT 170 ms (+150 ms Asymmetrie).
    // Beide drücken real bei t = 5_000 (Server-Zeit); Pakete kommen nach RTT/2 an.
    const echteDrueckzeit = 5_000;
    const a = clampBuzz({
      pressedAtServerEst: echteDrueckzeit,
      receiveTime: echteDrueckzeit + 10, // 20/2
      medianRtt: 20,
    });
    const b = clampBuzz({
      pressedAtServerEst: echteDrueckzeit,
      receiveTime: echteDrueckzeit + 85, // 170/2
      medianRtt: 170,
    });
    // Kompensation: beide landen auf der ECHTEN Drückzeit — Differenz 0 ms.
    expect(a).toBe(echteDrueckzeit);
    expect(b).toBe(echteDrueckzeit);
    // Und weil |a − b| < 40 ms: sichtbares Fotofinish-Los statt WLAN-Vorteil.
    const erg = ordneBuzzes(
      [
        { playerId: "a", finalAt: a },
        { playerId: "b", finalAt: b },
      ],
      createRng(1),
    );
    expect(erg[0].fotofinish).toBe(true);
    expect(erg[1].fotofinish).toBe(true);
  });

  it("ohne Kompensation hätte der langsamere verloren (Kontroll-Rechnung)", () => {
    // Nur zur Doku: Empfangszeiten lägen 75 ms auseinander — > Fotofinish-Fenster.
    expect(5_085 - 5_010).toBeGreaterThan(BUZZER_FOTOFINISH_MS);
  });
});

describe("buzzer: Sammel-Fenster (280 ms)", () => {
  it("endet exakt 280 ms nach dem ersten Buzz-Empfang", () => {
    expect(sammelfensterEnde(7_000)).toBe(7_000 + BUZZER_SAMMELFENSTER_MS);
    expect(BUZZER_SAMMELFENSTER_MS).toBe(280);
  });
});

describe("buzzer: Sortierung + Fotofinish-Los", () => {
  it("sortiert aufsteigend nach finalAt; klare Abstände ⇒ kein Fotofinish", () => {
    const erg = ordneBuzzes(
      [
        { playerId: "c", finalAt: 5_200 },
        { playerId: "a", finalAt: 5_000 },
        { playerId: "b", finalAt: 5_100 },
      ],
      createRng(42),
    );
    expect(erg.map((e) => e.playerId)).toEqual(["a", "b", "c"]);
    expect(erg.every((e) => !e.fotofinish)).toBe(true);
    expect(erg.map((e) => e.rank)).toEqual([1, 2, 3]);
  });

  it("<40 ms Differenz ⇒ beide als Fotofinish markiert, Los per Seed reproduzierbar", () => {
    const kandidaten = [
      { playerId: "a", finalAt: 5_000 },
      { playerId: "b", finalAt: 5_030 }, // 30 ms — Fotofinish!
    ];
    const erg1 = ordneBuzzes(kandidaten, createRng(7));
    const erg2 = ordneBuzzes(kandidaten, createRng(7));
    expect(erg1).toEqual(erg2); // Determinismus: gleicher Seed ⇒ gleiches Los
    expect(erg1[0].fotofinish).toBe(true);
    expect(erg1[1].fotofinish).toBe(true);
    // Über viele Seeds gewinnt mal a, mal b (echter Münzwurf).
    const gewinner = new Set<string>();
    for (let seed = 0; seed < 20; seed++) {
      gewinner.add(ordneBuzzes(kandidaten, createRng(seed))[0].playerId);
    }
    expect(gewinner).toEqual(new Set(["a", "b"]));
  });

  it("exakt 40 ms ist KEIN Fotofinish (hartes Fenster)", () => {
    const erg = ordneBuzzes(
      [
        { playerId: "a", finalAt: 5_000 },
        { playerId: "b", finalAt: 5_040 },
      ],
      createRng(3),
    );
    expect(erg[0].playerId).toBe("a");
    expect(erg.every((e) => !e.fotofinish)).toBe(true);
  });
});

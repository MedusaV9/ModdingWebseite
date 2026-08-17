// Choreo-Engine der Erklär-Demos: Timeline-Determinismus, Beat-Ersetzungs-
// Semantik, Sound-Disziplin (nur Loop 0), Skip-Cleanup (stop) und die
// Invarianten ALLER registrierten Format-Choreos (3-5 Beats, 8-12 s, Sounds
// existieren in der SFX-Map, alle Kern-Formate abgedeckt).
import { describe, expect, it } from "vitest";
import type { DemoChoreo } from "../../shared/minigames/demo-typen";
import { SFX } from "../../shared/fx/sound-map";
import {
  beatIndexBei,
  createDemoSpieler,
  grundSzene,
  loopZeit,
  szeneBei,
  vollSzene,
} from "./choreo";

// Node-Env-Kniff für die Choreo-Sammlung (importiert ALLE Minigame-Renderer):
// 1) lit-html ZUERST laden — ohne globales document greift sein Node-Shim.
// 2) Danach ein Mini-document stubben — pixel-dschungel legt auf Modul-Ebene
//    ein Canvas an (gerendert wird in diesen Tests nichts).
await import("lit-html");
(globalThis as { document?: unknown }).document ??= {
  createElement: () => ({ getContext: () => null }),
};
const { alleDemoChoreos } = await import("./choreos");
const { ladeAlleMinigameModule } = await import("../../shared/minigames/registry");
const { alleKernregelIds, kernregelFuer } = await import("./kernregeln");
// Lazy-Registry (Eval-7 Bundle-Split): ALLE Chunks einmal laden, dann sync prüfen.
const formatChoreos = await alleDemoChoreos();
const alleModule = await ladeAlleMinigameModule();

const mini: DemoChoreo = {
  dauer: 10000,
  beats: [
    { at: 0, pose: { a: "denk", b: "denk" }, sound: "lockin-thunk" },
    { at: 3000, blase: { wer: "a", text: "Mia buzzert!" }, sound: "buzzer-hupe" },
    { at: 6000, pose: { a: "jubel", b: "frust" }, effekt: "konfetti", sound: "richtig" },
  ],
};

describe("Choreo-Engine: Timeline pur & deterministisch", () => {
  it("loopZeit faltet in den Loop (inkl. Wrap und negativer Zeit)", () => {
    expect(loopZeit(100, 0)).toBe(0);
    expect(loopZeit(100, 99)).toBe(99);
    expect(loopZeit(100, 100)).toBe(0);
    expect(loopZeit(100, 250)).toBe(50);
    expect(loopZeit(100, -30)).toBe(70);
  });

  it("beatIndexBei wählt den letzten Beat mit at <= t", () => {
    expect(beatIndexBei(mini, 0)).toBe(0);
    expect(beatIndexBei(mini, 2999)).toBe(0);
    expect(beatIndexBei(mini, 3000)).toBe(1);
    expect(beatIndexBei(mini, 5999)).toBe(1);
    expect(beatIndexBei(mini, 9999)).toBe(2);
    // Wrap: t = dauer + x landet wieder am Anfang.
    expect(beatIndexBei(mini, 10000)).toBe(0);
    expect(beatIndexBei(mini, 13500)).toBe(1);
  });

  it("szeneBei ist pur: gleicher Zeitpunkt ⇒ identische Szene", () => {
    const a = szeneBei(mini, 6400);
    const b = szeneBei(mini, 6400);
    expect(a).toEqual(b);
    expect(a.pose).toEqual({ a: "jubel", b: "frust" });
    expect(a.effekt).toBe("konfetti");
  });

  it("vollSzene füllt fehlende Beat-Felder mit der Grundszene", () => {
    expect(vollSzene(undefined)).toEqual(grundSzene());
    const teil = vollSzene({ blase: { wer: "a", text: "Hi" } });
    expect(teil.blase).toEqual({ wer: "a", text: "Hi" });
    expect(teil.pose).toEqual({ a: "idle", b: "idle" });
    expect(teil.requisiten).toEqual([]);
    expect(teil.geldflug).toBeNull();
  });

  it("Beats ERSETZEN die Szene (kein Merge): Blase aus Beat 1 ist in Beat 2 weg", () => {
    expect(szeneBei(mini, 4000).blase).toEqual({ wer: "a", text: "Mia buzzert!" });
    expect(szeneBei(mini, 6500).blase).toBeNull();
    expect(szeneBei(mini, 6500).pose.a).toBe("jubel");
  });
});

describe("Choreo-Engine: Abspiel-Controller (Sounds + Skip-Cleanup)", () => {
  it("Sound feuert beim Beat-Wechsel genau einmal (nicht pro Frame)", () => {
    const s = createDemoSpieler(mini);
    expect(s.tick(0)?.sound).toBe("lockin-thunk");
    expect(s.tick(16)?.sound).toBeNull();
    expect(s.tick(1000)?.sound).toBeNull();
    expect(s.tick(3050)?.sound).toBe("buzzer-hupe");
    expect(s.tick(3070)?.sound).toBeNull();
    expect(s.tick(6001)?.sound).toBe("richtig");
  });

  it("ab Loop 2 bleiben die Beats, aber die Sounds schweigen", () => {
    const s = createDemoSpieler(mini);
    s.tick(0);
    s.tick(6500);
    // Loop-Wrap: wieder Beat 0/1/2, aber loopNr >= 1 ⇒ kein Sound mehr.
    const wrap = s.tick(10001);
    expect(wrap?.beatIndex).toBe(0);
    expect(wrap?.neuerBeat).toBe(true);
    expect(wrap?.sound).toBeNull();
    expect(s.tick(13200)?.sound).toBeNull();
    expect(s.tick(16400)?.sound).toBeNull();
  });

  it("stop() = Skip-Cleanup: tick liefert null, nichts feuert mehr", () => {
    const s = createDemoSpieler(mini);
    expect(s.tick(0)).not.toBeNull();
    s.stop();
    expect(s.gestoppt()).toBe(true);
    expect(s.tick(3200)).toBeNull();
    expect(s.tick(6200)).toBeNull();
  });

  it("neuerBeat ist nur beim Betreten true — DOM wird nur dann angefasst", () => {
    const s = createDemoSpieler(mini);
    expect(s.tick(0)?.neuerBeat).toBe(true);
    expect(s.tick(500)?.neuerBeat).toBe(false);
    expect(s.tick(2999)?.neuerBeat).toBe(false);
    expect(s.tick(3000)?.neuerBeat).toBe(true);
    expect(s.tick(3016)?.neuerBeat).toBe(false);
  });
});

describe("Format-Choreos: Invarianten über ALLE registrierten Demos", () => {
  const KERN_FORMATE = [
    "vier-lianen",
    "bananen-basics",
    "kokosnuss-uhr",
    "bananen-tresor",
    "affenleiter",
    "pixel-dschungel",
    "stinkbanane",
    "taschendieb",
    "affenbank",
    "alles-oder-banane",
    "lianen-finale",
    "monkey-market",
    "bananen-bluff",
    "bananen-boerse",
    "affen-auktion",
    "lianensteg-duell",
    "goldener-affe",
  ];

  it("alle 17 Kern-Formate haben eine Demo-Choreo", () => {
    const choreos = formatChoreos;
    for (const id of KERN_FORMATE) {
      expect(choreos.has(id), `Choreo fehlt: ${id}`).toBe(true);
    }
  });

  it("jede Choreo: 3-5 Beats, 8-12 s Loop, Beats aufsteigend & im Loop", () => {
    for (const [id, choreo] of formatChoreos) {
      expect(choreo.beats.length, `${id}: Beat-Zahl`).toBeGreaterThanOrEqual(3);
      expect(choreo.beats.length, `${id}: Beat-Zahl`).toBeLessThanOrEqual(5);
      expect(choreo.dauer, `${id}: dauer`).toBeGreaterThanOrEqual(8000);
      expect(choreo.dauer, `${id}: dauer`).toBeLessThanOrEqual(12000);
      expect(choreo.beats[0].at, `${id}: Beat 0 startet bei 0`).toBe(0);
      for (let i = 1; i < choreo.beats.length; i++) {
        expect(choreo.beats[i].at, `${id}: Beat ${i} nach Beat ${i - 1}`).toBeGreaterThan(
          choreo.beats[i - 1].at,
        );
      }
      const letzter = choreo.beats[choreo.beats.length - 1];
      expect(letzter.at, `${id}: letzter Beat im Loop`).toBeLessThan(choreo.dauer);
      // Der letzte Beat braucht Zeit zum Wirken (mind. 1 s bis zum Wrap).
      expect(choreo.dauer - letzter.at, `${id}: letzter Beat zu knapp`).toBeGreaterThanOrEqual(
        1000,
      );
    }
  });

  it("alle Beat-Sounds existieren in der SFX-Map", () => {
    for (const [id, choreo] of formatChoreos) {
      for (const beat of choreo.beats) {
        if (beat.sound !== undefined) {
          expect(SFX[beat.sound], `${id}: unbekannter Sound "${beat.sound}"`).toBeDefined();
        }
      }
    }
  });

  it("jede Choreo ist deterministisch abspielbar (Szene an jeder Beat-Grenze)", () => {
    for (const [, choreo] of formatChoreos) {
      for (const beat of choreo.beats) {
        const szene = szeneBei(choreo, beat.at);
        expect(szene.pose.a).toBeDefined();
        expect(szene.pose.b).toBeDefined();
        expect(Array.isArray(szene.requisiten)).toBe(true);
      }
    }
  });

  it("Sprech-Blasen bleiben Screen-tauglich kurz (max. 34 Zeichen)", () => {
    for (const [id, choreo] of formatChoreos) {
      for (const beat of choreo.beats) {
        if (beat.blase) {
          expect(beat.blase.text.length, `${id}: Blase zu lang`).toBeLessThanOrEqual(34);
        }
      }
    }
  });
});

describe("Kernregel-Banner (W4, Eval-6): 1-Satz-Merksatz über der Demo-Bühne", () => {
  it("jedes Format mit Demo-Choreo hat eine Kernregel (kein Banner-Loch)", () => {
    for (const id of formatChoreos.keys()) {
      expect(kernregelFuer(id), `Kernregel fehlt: ${id}`).not.toBeNull();
    }
  });

  it("jede Kernregel gehört zu einem registrierten Format (keine Karteileichen)", () => {
    for (const id of alleKernregelIds()) {
      expect(alleModule.has(id), `Kernregel ohne Client-Renderer: ${id}`).toBe(true);
    }
  });

  it("Kernregeln bleiben Banner-tauglich kurz (max. 72 Zeichen)", () => {
    for (const id of alleKernregelIds()) {
      expect(kernregelFuer(id)!.length, `${id}: Kernregel zu lang`).toBeLessThanOrEqual(72);
    }
  });

  it("unbekannte Formate liefern null (Fallback: Karte ohne Banner)", () => {
    expect(kernregelFuer("gibt-es-nicht")).toBeNull();
  });
});

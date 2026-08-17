// Sound-System-Wächter (Eval 3): Volumen-Timeline des Musik-Betts über eine
// Musik-Runde (musik(null) ⇒ Bett pausiert = 0, Snippet läuft allein), der
// Duck-Mechanismus (faktor 0 senkt wirklich Richtung Stille und erholt sich)
// und die Anti-Stapel-Regel (gleiche Sound-Id stoppt ihren Vorgänger — vorher
// stapelten sich 17-s-Applaus-Dateien bis zum 8-Stimmen-Deckel).
// Musik-Welle 3: dazu die Rotation-Verdrahtung (BettQuelle, Track-Ende,
// Skip, Ticker), der Musik-Toggle (getrennt vom SFX-Stumm) und der Vorrang
// der MUSIK_STUMME_FORMATE (Ebene null schlägt ALLES — auch Skips).
// DOM-Stubs statt Browser: HTMLAudioElement/Window/localStorage sind hier
// Fakes, die Zeit läuft über vi.useFakeTimers (inkl. performance.now).
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { BettTrack } from "../../../shared/songs";
import { createMusikRotation } from "./musik-rotation";
import { createSoundSystem, type SoundSystem } from "./sound";

class FakeAudio {
  static alle: FakeAudio[] = [];
  src = "";
  volume = 1;
  loop = false;
  paused = true;
  currentTime = 0;
  private handler = new Map<string, (() => void)[]>();
  constructor(src?: string) {
    if (src !== undefined) this.src = src;
    FakeAudio.alle.push(this);
  }
  play(): Promise<void> {
    this.paused = false;
    return Promise.resolve();
  }
  pause(): void {
    this.paused = true;
  }
  addEventListener(ev: string, fn: () => void): void {
    this.handler.set(ev, [...(this.handler.get(ev) ?? []), fn]);
  }
  removeEventListener(): void {}
  /** Natürliches Abspiel-Ende simulieren (feuert die ended-Listener). */
  endeSimulieren(): void {
    this.paused = true;
    for (const fn of this.handler.get("ended") ?? []) fn();
  }
}

let gesten: (() => void)[] = [];

function neuesSystem(): SoundSystem {
  const sys = createSoundSystem("screen");
  sys.unlockBeiGeste();
  gesten.forEach((fn) => fn()); // erste Nutzer-Geste ⇒ Unlock
  return sys;
}

/** Das Bett-Element: EINZIGES mit loop=true (Fix-Track) bzw. — bei laufender
 * Rotation (loop=false, Playlist > 1) — das mit einer Musik-Quelle als src. */
function bett(): FakeAudio {
  const el = FakeAudio.alle.find(
    (a) => a.loop || a.src.includes("/audio/musik/") || a.src.includes("/media-musik-bett/"),
  );
  if (!el) throw new Error("kein Musik-Element erzeugt");
  return el;
}

/** Timeline: alle 100 ms { ms, volumen } sammeln (pausiert zählt als 0). */
function timeline(dauerMs: number): { ms: number; volumen: number }[] {
  const punkte: { ms: number; volumen: number }[] = [];
  for (let t = 0; t < dauerMs; t += 100) {
    vi.advanceTimersByTime(100);
    const el = bett();
    punkte.push({ ms: t + 100, volumen: el.paused ? 0 : el.volume });
  }
  return punkte;
}

beforeEach(() => {
  vi.useFakeTimers({
    toFake: ["setTimeout", "clearTimeout", "setInterval", "clearInterval", "performance"],
  });
  FakeAudio.alle = [];
  gesten = [];
  vi.stubGlobal("Audio", FakeAudio);
  vi.stubGlobal("window", {
    location: { origin: "http://mm.test" },
    addEventListener: (ev: string, fn: () => void) => {
      if (ev === "pointerdown") gesten.push(fn);
    },
    removeEventListener: () => {},
  });
  vi.stubGlobal("localStorage", { getItem: () => null, setItem: () => {} });
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

describe("Volumen-Timeline: Musik-Runde = Bett KOMPLETT stumm", () => {
  it("Bett fährt hoch, musik(null) schaltet HART auf 0 — für die ganze Runde", () => {
    const sys = neuesSystem();
    sys.musik("runde");
    const anfahrt = timeline(2000);
    expect(anfahrt.at(-1)?.volumen).toBeCloseTo(0.4, 5); // screen-Profil: 0,4

    // Musik-Format beginnt (Regie liefert null): SOFORT 0 — kein Fade-Rest.
    sys.musik(null);
    expect(bett().paused).toBe(true);

    // Snippet läuft über den Media-Kanal — das Bett bleibt die GANZE Runde 0.
    sys.sound("/media-musik/s_test/buzz_ms1000.ogg");
    const runde = timeline(8000);
    expect(runde.every((p) => p.volumen === 0)).toBe(true);
    const media = FakeAudio.alle.find((a) => a.src.includes("/media-musik/"));
    expect(media?.paused).toBe(false);
    expect(media?.volume ?? 0).toBeGreaterThan(0.8); // Snippet in voller Lautstärke

    // Nach der Runde (Zwischenstand): das Bett kommt zurück.
    sys.musik("news");
    expect(bett().paused).toBe(false);
  });

  it("duck(…, 0): Timeline fällt Richtung Stille und erholt sich danach", () => {
    const sys = neuesSystem();
    sys.musik("runde");
    timeline(2000); // eingeschwungen auf 0,4
    sys.duck(1500, 0);
    const geduckt = timeline(1500);
    expect(geduckt.at(-1)?.volumen ?? 1).toBeLessThan(0.05);
    const erholt = timeline(3000);
    expect(erholt.at(-1)?.volumen).toBeCloseTo(0.4, 5);
  });
});

describe("Anti-Stapel-Regel: gleiche Sound-Id stoppt den Vorgänger", () => {
  it("zweiter Applaus stoppt den ersten — nie 2 gleiche Sounds parallel", () => {
    const sys = neuesSystem();
    sys.sound("applaus-kurz");
    sys.sound("applaus-kurz");
    const crowd = FakeAudio.alle.filter((a) => a.src.includes("/audio/crowd/"));
    expect(crowd).toHaveLength(2);
    expect(crowd[0].paused).toBe(true); // Vorgänger gestoppt
    expect(crowd[1].paused).toBe(false);
  });

  it("gestoppte Vorgänger blockieren den 8-Stimmen-Deckel nicht", () => {
    const sys = neuesSystem();
    // 10× dieselbe Id: ohne Anti-Stapel wäre der Deckel längst erschöpft.
    for (let i = 0; i < 10; i++) sys.sound("applaus-kurz");
    expect(FakeAudio.alle.filter((a) => !a.paused)).toHaveLength(1);
    // 7 weitere VERSCHIEDENE Ids passen noch unter den Deckel (1+7 = 8).
    const weitere = ["tap", "bestaetigen", "zurueck", "fehler", "ticker", "toggle", "tick"];
    for (const id of weitere) sys.sound(id);
    expect(FakeAudio.alle.filter((a) => !a.paused)).toHaveLength(8);
  });

  it("natürlich beendete Sounds räumen den Deckel ebenfalls frei", () => {
    const sys = neuesSystem();
    sys.sound("applaus-kurz");
    const erster = FakeAudio.alle.at(-1);
    erster?.endeSimulieren();
    for (const id of ["tap", "bestaetigen", "zurueck", "fehler", "ticker", "toggle", "tick"]) {
      sys.sound(id);
    }
    sys.sound("zeit-um"); // Platz 8 ist wieder frei — spielt
    expect(FakeAudio.alle.filter((a) => !a.paused)).toHaveLength(8);
  });
});

// ---------- Musik-Welle 3: Rotation, Toggle, Skip, Ticker ----------

const bettTrack = (id: string, stimmung: "chillig" | "upbeat"): BettTrack => ({
  id,
  titel: `Titel ${id}`,
  artist: `Artist ${id}`,
  stimmung,
  url: `/media-musik-bett/${id}.ogg`,
});

/** System mit Rotation: Lobby = MacLeod + 2 chillige User-Loops (3 Tracks). */
function systemMitRotation(): SoundSystem {
  const sys = neuesSystem();
  sys.setBettQuelle(
    createMusikRotation(42, [bettTrack("s_bett_x", "chillig"), bettTrack("s_bett_y", "chillig")]),
  );
  return sys;
}

describe("Rotation: Playlist statt Fix-Track, Track-Ende schaltet weiter", () => {
  it("Lobby spielt den MacLeod-Kern zuerst, ohne Loop (Playlist > 1)", () => {
    const sys = systemMitRotation();
    sys.musik("lobby");
    const el = bett();
    expect(el.src).toContain("MonkeysSpinningMonkeys");
    expect(el.loop).toBe(false);
    expect(sys.aktuellerTrack()).toEqual({
      titel: "Monkeys Spinning Monkeys",
      artist: "Kevin MacLeod",
    });
  });

  it("Track-Ende (ended) schaltet zum nächsten Track — kein Doppel", () => {
    const sys = systemMitRotation();
    sys.musik("lobby");
    const el = bett();
    const gesehen = [el.src];
    for (let i = 0; i < 6; i++) {
      el.endeSimulieren();
      gesehen.push(el.src);
    }
    for (let i = 1; i < gesehen.length; i++) {
      expect(gesehen[i]).not.toBe(gesehen[i - 1]);
    }
    expect(el.paused).toBe(false); // Rotation läuft nahtlos weiter
  });

  it("musikSkip() wechselt den Track und meldet den Ticker-Hörer", () => {
    const sys = systemMitRotation();
    let ticks = 0;
    sys.onTrackWechsel(() => ticks++);
    sys.musik("lobby");
    const vorher = bett().src;
    const ticksVorher = ticks;
    sys.musikSkip();
    expect(bett().src).not.toBe(vorher);
    expect(ticks).toBeGreaterThan(ticksVorher);
    expect(sys.aktuellerTrack()?.titel).toContain("Titel s_bett_");
  });

  it("ohne Rotation bleibt alles beim Alten: MUSIK-Map, loop=true", () => {
    const sys = neuesSystem();
    sys.musik("runde");
    const el = bett();
    expect(el.src).toContain("QuirkyDog");
    expect(el.loop).toBe(true);
    expect(sys.aktuellerTrack()).toEqual({ titel: "Quirky Dog", artist: "Kevin MacLeod" });
  });
});

describe("MUSIK_STUMME_FORMATE gewinnen IMMER gegen die Rotation", () => {
  it("Ebene null: Bett pausiert, Skip ist ein No-op, Ticker leer", () => {
    const sys = systemMitRotation();
    sys.musik("lobby");
    const el = bett();
    sys.musik(null); // Regie: Blitz-DJ & Co. — Bett bewusst stumm
    expect(el.paused).toBe(true);
    expect(sys.aktuellerTrack()).toBeNull();
    const srcVorher = el.src;
    sys.musikSkip(); // GM-Skip während einer Musik-Runde: darf NICHTS tun
    expect(el.paused).toBe(true);
    expect(el.src).toBe(srcVorher);
    // Auch der lokale Toggle weckt das Bett nicht — null bleibt null.
    sys.setMusikAn(false);
    sys.setMusikAn(true);
    expect(el.paused).toBe(true);
  });
});

describe("Musik-Toggle + Match-Setting (getrennt vom SFX-Stumm)", () => {
  it("setMusikAn(false) pausiert NUR das Bett — SFX spielen weiter", () => {
    const sys = systemMitRotation();
    sys.musik("lobby");
    sys.setMusikAn(false);
    expect(bett().paused).toBe(true);
    expect(sys.istMusikAn()).toBe(false);
    sys.sound("tap"); // SFX unabhängig vom Musik-Toggle
    expect(FakeAudio.alle.filter((a) => !a.paused && !a.loop).length).toBeGreaterThan(0);
    sys.setMusikAn(true);
    expect(bett().paused).toBe(false);
  });

  it("Match-Setting musik:aus (GM) stoppt das Bett trotz lokalem AN", () => {
    const sys = systemMitRotation();
    sys.musik("lobby");
    sys.setMatchMusik(false, 1);
    expect(bett().paused).toBe(true);
    expect(sys.istMatchMusikAn()).toBe(false);
    sys.setMatchMusik(true, 1);
    expect(bett().paused).toBe(false);
  });

  it("Musik-Volume (lokal × Match) skaliert das Bett, nicht die SFX", () => {
    const sys = systemMitRotation();
    sys.musik("lobby");
    timeline(2000);
    expect(bett().volume).toBeCloseTo(0.4, 5); // screen-Profil 0,4
    sys.setMusikLautstaerke(0.5);
    sys.setMatchMusik(true, 0.5);
    timeline(2000);
    expect(bett().volume).toBeCloseTo(0.4 * 0.5 * 0.5, 5);
    sys.sound("tap");
    const sfx = FakeAudio.alle.at(-1);
    expect(sfx?.volume ?? 0).toBeGreaterThan(0.4); // SFX unberührt (0,9-Profil)
  });
});

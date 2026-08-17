// Regie-Wächter (Eval 3, P1): In Musik-Formaten (Blitz-DJ, Rückwärts-Banane,
// Stummfilm-Studio) ist das Musik-Bett für die GANZE Runde stumm — die Regie
// schaltet auf Ebene null statt nur zu ducken. Vorher lief das Bett auf
// Snippet-Lautstärke weiter (SNR≈0 dB), der Duck griff ~1 s zu spät und
// endete mitten im 5-s-Clip: „ALLE LAUSCHEN" heißt Stille.
import { describe, expect, it, vi } from "vitest";
import type { ViewBase } from "../../../shared/views";
import { createRegie, musikEbene } from "./regie";
import { MUSIK_STUMME_FORMATE } from "./sound-map";
import type { SoundSystem } from "./sound";

// Die Renderer-Registry zieht per Glob ALLE Minigame-Renderer (DOM-Zugriffe
// beim Modul-Laden) — für die reine Regie-Logik hier gemockt (Node-Env).
vi.mock("../minigames/registry", () => ({ getMinigameModule: () => null }));

function view(phase: string, minigameId?: string): ViewBase {
  return {
    phase,
    momente: [],
    abschnitt: minigameId !== undefined ? { minigameId } : null,
    minigame: minigameId !== undefined ? { id: minigameId, view: {} } : null,
    frageNr: 1,
  } as unknown as ViewBase;
}

describe("musikEbene: Musik-Formate = Bett KOMPLETT stumm (ganze Runde)", () => {
  it("song-snippet/song-rueckwaerts/musikvideo-raten → null in frage UND aufloesung", () => {
    for (const mg of MUSIK_STUMME_FORMATE) {
      expect(musikEbene(view("frage", mg)), `${mg} frage`).toBeNull();
      expect(musikEbene(view("aufloesung", mg)), `${mg} aufloesung`).toBeNull();
    }
  });

  it("die drei Musik-Formate sind registriert (Set-Wächter)", () => {
    expect([...MUSIK_STUMME_FORMATE].sort()).toEqual([
      "musikvideo-raten",
      "song-rueckwaerts",
      "song-snippet",
    ]);
  });

  it("Nicht-Musik-Formate behalten ihr Bett (runde/schleich)", () => {
    expect(musikEbene(view("frage", "vier-lianen"))).toBe("runde");
    expect(musikEbene(view("frage", "taschendieb"))).toBe("schleich");
    expect(musikEbene(view("aufloesung", "affenbank"))).toBe("runde");
    // Telegramm spielt KEIN Song-Material — das Bett bleibt an.
    expect(musikEbene(view("frage", "buchstaben-telegramm"))).toBe("runde");
  });

  it("Rest der Show unverändert: Lobby-Loop, News, Rad", () => {
    expect(musikEbene(view("lobby"))).toBe("lobby");
    expect(musikEbene(view("zwischenstand"))).toBe("news");
    expect(musikEbene(view("rad"))).toBe("rad");
  });
});

describe("createRegie: Bett-Timeline über eine komplette Blitz-DJ-Runde", () => {
  it("Regie fordert für JEDEN Snapshot der Musik-Runde Ebene null an", () => {
    const ebenen: (string | null)[] = [];
    const stub: SoundSystem = {
      sound: () => {},
      stopMedia: () => {},
      musik: (e) => ebenen.push(e),
      duck: () => {},
      unlockBeiGeste: () => {},
      istEntsperrt: () => true,
      istStumm: () => false,
      setStumm: () => {},
      setLautstaerke: () => {},
      getLautstaerke: () => 1,
      setBettQuelle: () => {},
      musikSkip: () => {},
      aktuellerTrack: () => null,
      istMusikAn: () => true,
      setMusikAn: () => {},
      setMusikLautstaerke: () => {},
      getMusikLautstaerke: () => 1,
      setMatchMusik: () => {},
      istMatchMusikAn: () => true,
      onTrackWechsel: () => {},
    };
    const regie = createRegie(stub, "screen");
    regie.update(view("erklaerkarte", "song-snippet"));
    const vorher = ebenen.at(-1);
    // Die ganze Runde: mehrere frage-Snapshots (Stufen-Eskalation) + Auflösung.
    for (let i = 0; i < 5; i++) regie.update(view("frage", "song-snippet"));
    regie.update(view("aufloesung", "song-snippet"));
    const rundenEbenen = ebenen.slice(1);
    expect(vorher).toBe("erklaer");
    expect(rundenEbenen).toHaveLength(6);
    expect(rundenEbenen.every((e) => e === null)).toBe(true);
    // Nach der Runde kommt das Bett zurück (Zwischenstand-News).
    regie.update(view("zwischenstand"));
    expect(ebenen.at(-1)).toBe("news");
  });
});

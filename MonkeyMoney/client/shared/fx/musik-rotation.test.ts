// Rotation-Wächter (Musik-Welle 3): die Playlist-Rotation ist pro Match
// DETERMINISTISCH geseedet (Raum-Code → djb2 → Mulberry32), der MacLeod-Kern
// bleibt IMMER der Default (erster Track jeder Ebene), Stimmungen landen in
// der richtigen Phase (chillig=Lobby, upbeat=Runde) und kein Track läuft
// zweimal hintereinander, sobald eine Ebene mehr als einen Track hat.
import { describe, expect, it } from "vitest";
import type { BettTrack } from "../../../shared/songs";
import {
  STANDARD_BETTEN,
  bauePlaylists,
  createMusikRotation,
  seedAusRaumCode,
} from "./musik-rotation";

const bett = (id: string, stimmung: "chillig" | "upbeat"): BettTrack => ({
  id,
  titel: `Titel ${id}`,
  artist: `Artist ${id}`,
  stimmung,
  url: `/media-musik-bett/${id}.ogg`,
});

const DEMO: BettTrack[] = [
  bett("s_bett_a", "chillig"),
  bett("s_bett_b", "chillig"),
  bett("s_bett_c", "chillig"),
  bett("s_bett_d", "upbeat"),
  bett("s_bett_e", "upbeat"),
];

describe("seedAusRaumCode: Raum-Code → deterministischer Seed", () => {
  it("gleicher Code = gleicher Seed, anderer Code = anderer Seed", () => {
    expect(seedAusRaumCode("BANANE")).toBe(seedAusRaumCode("BANANE"));
    expect(seedAusRaumCode("BANANE")).not.toBe(seedAusRaumCode("KOKOSNUSS"));
  });
});

describe("bauePlaylists: MacLeod-Kern zuerst, Stimmung → Phase", () => {
  it("Lobby/Runde beginnen IMMER mit dem MacLeod-Standard-Bett", () => {
    const p = bauePlaylists(seedAusRaumCode("BANANE"), DEMO);
    expect(p.lobby[0]).toEqual(STANDARD_BETTEN.lobby);
    expect(p.runde[0]).toEqual(STANDARD_BETTEN.runde);
  });

  it("chillig rotiert in der Lobby, upbeat in der Runde — nie umgekehrt", () => {
    const p = bauePlaylists(7, DEMO);
    expect(p.lobby.slice(1).map((t) => t.id)).toEqual(
      expect.arrayContaining(["s_bett_a", "s_bett_b", "s_bett_c"]),
    );
    expect(p.lobby).toHaveLength(4);
    expect(p.runde.slice(1).map((t) => t.id)).toEqual(
      expect.arrayContaining(["s_bett_d", "s_bett_e"]),
    );
    expect(p.runde).toHaveLength(3);
  });

  it("Charakter-Ebenen (schleich/rad/news/erklaer) bleiben 1-Track-Signale", () => {
    const p = bauePlaylists(7, DEMO);
    for (const ebene of ["schleich", "rad", "news", "erklaer"]) {
      expect(p[ebene]).toHaveLength(1);
    }
  });

  it("gleicher Seed = gleiche Reihenfolge, anderer Seed = andere Mischung", () => {
    const a1 = bauePlaylists(seedAusRaumCode("BANANE"), DEMO).lobby.map((t) => t.id);
    const a2 = bauePlaylists(seedAusRaumCode("BANANE"), DEMO).lobby.map((t) => t.id);
    expect(a1).toEqual(a2);
    // Über mehrere Seeds MUSS mindestens eine andere Reihenfolge auftauchen
    // (fixe Prüfung dank deterministischem Mulberry32 — kein Flake möglich).
    const varianten = new Set(
      ["A1", "B2", "C3", "D4", "E5"].map((code) =>
        bauePlaylists(seedAusRaumCode(code), DEMO)
          .lobby.map((t) => t.id)
          .join(","),
      ),
    );
    expect(varianten.size).toBeGreaterThan(1);
  });
});

describe("createMusikRotation: sequenziell, kein Track 2× hintereinander", () => {
  it("weiter() schaltet durch die ganze Playlist und wrapt dann", () => {
    const rot = createMusikRotation(seedAusRaumCode("BANANE"), DEMO);
    const gesehen: string[] = [];
    for (let i = 0; i < 12; i++) {
      const t = rot.trackFuer("lobby");
      expect(t).not.toBeNull();
      gesehen.push(t!.id);
      rot.weiter("lobby");
    }
    // Kein Doppel: benachbarte Einträge unterscheiden sich IMMER.
    for (let i = 1; i < gesehen.length; i++) {
      expect(gesehen[i]).not.toBe(gesehen[i - 1]);
    }
    // Alle 4 Lobby-Tracks (MacLeod + 3 chillige) kommen in 12 Schritten 3× vor.
    expect(new Set(gesehen).size).toBe(4);
  });

  it("Playlist der Länge 1 loopt (loop=true), > 1 schaltet weiter (loop=false)", () => {
    const rot = createMusikRotation(1, DEMO);
    expect(rot.trackFuer("schleich")?.loop).toBe(true);
    expect(rot.trackFuer("lobby")?.loop).toBe(false);
    // weiter() auf 1-Track-Ebenen ist ein No-op — das Signal bleibt stabil.
    const vorher = rot.trackFuer("rad")?.id;
    rot.weiter("rad");
    expect(rot.trackFuer("rad")?.id).toBe(vorher);
  });

  it("unbekannte Ebene (z. B. null-Bett der Musik-Formate) liefert null", () => {
    const rot = createMusikRotation(1, DEMO);
    expect(rot.trackFuer("gibt-es-nicht")).toBeNull();
  });

  it("jede Ebene merkt sich ihre Position unabhängig", () => {
    const rot = createMusikRotation(2, DEMO);
    const lobbyStart = rot.trackFuer("lobby")?.id;
    rot.weiter("runde");
    expect(rot.trackFuer("lobby")?.id).toBe(lobbyStart);
  });

  it("playlist() liefert eine Kopie fürs GM-Cockpit (Mutation wirkungslos)", () => {
    const rot = createMusikRotation(3, DEMO);
    const kopie = rot.playlist("lobby");
    kopie.pop();
    expect(rot.playlist("lobby")).toHaveLength(4);
  });
});

describe("ohne Bett-Katalog: Standard-Betten als 1-Track-Loops", () => {
  it("leerer Katalog ⇒ Lobby/Runde loopen den MacLeod-Kern", () => {
    const rot = createMusikRotation(seedAusRaumCode("X"), []);
    expect(rot.trackFuer("lobby")).toEqual({ ...STANDARD_BETTEN.lobby, loop: true });
    expect(rot.trackFuer("runde")).toEqual({ ...STANDARD_BETTEN.runde, loop: true });
  });
});

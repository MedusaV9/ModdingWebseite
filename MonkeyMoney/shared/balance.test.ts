// Invarianten-Wächter der Economy-Tabelle (MASTERPLAN Welle 1).
// Kunden-Befund „Rewards inkonsistent": diese Tests machen die Kurve
// verbindlich — wer eine Konstante verschiebt, muss die Invarianten halten.
import { describe, expect, it } from "vitest";
import { alleBetraege, BALANCE } from "./balance";
import { speedBonus } from "./money";

const SCHWIERIGKEITEN = ["easy", "medium", "hard", "ultrahard"] as const;

describe("balance: Raster & Progression", () => {
  it("alle MM-Beträge liegen auf dem 5er-Raster (Scheine, keine Cents)", () => {
    for (const betrag of alleBetraege()) {
      expect(betrag % 5, `Betrag ${betrag} bricht das 5er-Raster`).toBe(0);
    }
  });

  it("Frage-Grundwerte steigen streng mit der Schwierigkeit", () => {
    const w = BALANCE.fragen.werte;
    expect(w.easy).toBeLessThan(w.medium);
    expect(w.medium).toBeLessThan(w.hard);
    expect(w.hard).toBeLessThan(w.ultrahard);
  });

  it("Frage-Timer wachsen mit der Schwierigkeit (Pacing-Kurve)", () => {
    const t = BALANCE.fragen.timerMs;
    expect(t.easy).toBeLessThanOrEqual(t.medium);
    expect(t.medium).toBeLessThanOrEqual(t.hard);
    expect(t.hard).toBeLessThanOrEqual(t.ultrahard);
  });

  it("W/2 und W/10 sind für JEDE Stufe ganzzahlig (Bluff, Börse, Market)", () => {
    for (const s of SCHWIERIGKEITEN) {
      const w = BALANCE.fragen.werte[s];
      expect(w % 2, `W/2 von ${s}`).toBe(0);
      expect(w % 10, `W/10 von ${s}`).toBe(0);
    }
  });
});

describe("balance: Format-Kurven", () => {
  it("Affenbank-Kette verdoppelt sauber bis zur Kappe", () => {
    const kette = BALANCE.formate.affenbankKette;
    for (let i = 1; i < kette.length; i++) {
      expect(kette[i]).toBe(kette[i - 1] * 2);
    }
  });

  it("Risiko-Leiter steigt streng monoton", () => {
    const leiter = BALANCE.formate.risikoLeiter;
    for (let i = 1; i < leiter.length; i++) {
      expect(leiter[i]).toBeGreaterThan(leiter[i - 1]);
    }
  });

  it("Pixel-Dschungel-Treppe: verdoppelt je Stufe, Schritt = Start/8 (§2.5)", () => {
    // Eigene Verdopplungs-Kurve (200→400→800→1.600), NICHT stur 2×W —
    // medium ist bewusst milder (400 statt 500), dokumentiert in der Meta.
    expect(BALANCE.formate.pixelDschungelTreppe.easy.start).toBe(BALANCE.fragen.werte.easy * 2);
    for (let i = 1; i < SCHWIERIGKEITEN.length; i++) {
      const [a, b] = [SCHWIERIGKEITEN[i - 1], SCHWIERIGKEITEN[i]];
      expect(BALANCE.formate.pixelDschungelTreppe[b].start).toBe(
        BALANCE.formate.pixelDschungelTreppe[a].start * 2,
      );
    }
    for (const s of SCHWIERIGKEITEN) {
      const t = BALANCE.formate.pixelDschungelTreppe[s];
      expect(t.schritt).toBe(t.start / 8);
    }
  });

  it("Taschendieb-Klau und Wer-singt's steigen mit der Schwierigkeit", () => {
    for (let i = 1; i < SCHWIERIGKEITEN.length; i++) {
      const [a, b] = [SCHWIERIGKEITEN[i - 1], SCHWIERIGKEITEN[i]];
      expect(BALANCE.formate.taschendiebKlau[b]).toBeGreaterThan(
        BALANCE.formate.taschendiebKlau[a],
      );
      expect(BALANCE.formate.werSingts[b]).toBeGreaterThan(BALANCE.formate.werSingts[a]);
    }
  });

  it("Wer-singt's zahlt milder als der Standard-Grundwert (Wissens-Bonus-Runde)", () => {
    for (const s of SCHWIERIGKEITEN) {
      expect(BALANCE.formate.werSingts[s]).toBeLessThanOrEqual(BALANCE.fragen.werte[s]);
    }
  });
});

describe("balance: Konsistenz-Regeln (Eval „Rewards inkonsistent“)", () => {
  it("Zuschauer-Wetten kosten ÜBERALL gleich viel", () => {
    const { lianensteg, boxkampf, goldenerAffe } = BALANCE.wetten;
    expect(boxkampf).toBe(lianensteg);
    expect(goldenerAffe).toBe(lianensteg);
  });

  it("Einer-gegen-alle: Solo-Coup > Team-Sieg > Unentschieden", () => {
    const e = BALANCE.formate.einerGegenAlle;
    expect(e.solo).toBeGreaterThan(e.team);
    expect(e.team).toBeGreaterThan(e.beide);
  });

  it("Konter-Quiz bleibt symmetrisch (richtig = Konter — freundliches Duell)", () => {
    expect(BALANCE.formate.konterQuiz.richtig).toBe(BALANCE.formate.konterQuiz.konter);
  });

  it("Speed-Bonus ist auf +50 % von W gedeckelt (plus 10er-Rundung)", () => {
    for (const s of SCHWIERIGKEITEN) {
      const w = BALANCE.fragen.werte[s];
      const timer = BALANCE.fragen.timerMs[s];
      const kappe = Math.round(w / 2 / 10) * 10; // 50 % aufs 10er-Raster gerundet
      expect(speedBonus(w, 0, timer)).toBeLessThanOrEqual(kappe);
    }
  });

  it("Dispo-Limit fängt jede Einzel-Strafe ab (niemand fällt durchs Netz)", () => {
    // Größte reguläre Einzel-Strafe: Stinkbananen-Explosion.
    expect(Math.abs(BALANCE.sicherungen.dispoLimit)).toBeGreaterThanOrEqual(
      BALANCE.formate.stinkbanane.explosion,
    );
  });
});

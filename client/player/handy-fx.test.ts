// Reine Rechenhelfer der Handy-FX-Schicht: Count-up-Interpolation + Wett-
// Slider-Snap (DOM-frei, laufen im Node-Env).
import { describe, expect, it } from "vitest";
import { snapWert, zaehlerWert } from "./handy-fx";

describe("zaehlerWert (Count-up 0..1)", () => {
  it("startet beim Startwert und endet exakt am Ziel", () => {
    expect(zaehlerWert(0, 0, 380)).toBe(0);
    expect(zaehlerWert(1, 0, 380)).toBe(380);
    expect(zaehlerWert(1.4, 0, 380)).toBe(380); // Überlauf geklemmt
    expect(zaehlerWert(-0.2, 100, 380)).toBe(100);
  });

  it("ease-out: in der ersten Hälfte ist mehr als die Hälfte geschafft", () => {
    const halb = zaehlerWert(0.5, 0, 1000);
    expect(halb).toBeGreaterThan(500);
    expect(halb).toBeLessThan(1000);
  });

  it("zählt monoton und ganzzahlig hoch", () => {
    let vorher = -1;
    for (let t = 0; t <= 1.001; t += 0.05) {
      const w = zaehlerWert(t, 0, 777);
      expect(Number.isInteger(w)).toBe(true);
      expect(w).toBeGreaterThanOrEqual(vorher);
      vorher = w;
    }
  });

  it("kann auch runterzählen (Konto-Tick nach Verlust)", () => {
    expect(zaehlerWert(1, 500, 200)).toBe(200);
    expect(zaehlerWert(0.5, 500, 200)).toBeLessThan(500);
  });
});

describe("snapWert (Wett-Slider-Snap-Punkte)", () => {
  // Typischer Wett-Slider: 50–1000 MM in 50er-Schritten.
  const snap = (wert: number): number => snapWert(wert, 50, 1000, 50);

  it("rastet nahe der Viertel-Punkte ein", () => {
    expect(snap(300)).toBe(300); // 25 %-Punkt (287,5 → auf Step 300)
    expect(snap(550)).toBe(550); // Mitte (525 → 550)
    expect(snap(1000)).toBe(1000); // Max
    expect(snap(50)).toBe(50); // Min
  });

  it("lässt Werte weit weg von Snap-Punkten unverändert", () => {
    expect(snap(150)).toBe(150);
    expect(snap(450)).toBe(450);
    expect(snap(900)).toBe(900);
  });

  it("zieht auch NACHBAR-Schritte magnetisch an (Toleranz > step)", () => {
    // Toleranz = max(50·1,2; 950·0,02) = 60 ⇒ ±1 Step um den Punkt rastet ein.
    expect(snap(500)).toBe(550); // Nachbar der Mitte (525 → Step 550)
    expect(snap(600)).toBe(550);
    expect(snap(250)).toBe(300); // Nachbar des 25 %-Punkts
    expect(snap(980)).toBe(1000); // nahe Max
  });

  it("nimmt bei überlappenden Toleranzen den NÄCHSTEN Punkt (Mini-Range)", () => {
    // Wenig Konto ⇒ Range 100–250 (3 Steps): jeder Step ist ein Viertel-Punkt,
    // die Toleranz (60) überlappt — 150 darf NICHT zum Min (100) gerissen werden.
    expect(snapWert(150, 100, 250, 50)).toBe(150);
    expect(snapWert(200, 100, 250, 50)).toBe(200);
  });

  it("ist robust gegen degenerierte Ranges", () => {
    expect(snapWert(5, 10, 10, 1)).toBe(5); // spanne 0
    expect(snapWert(5, 0, 10, 0)).toBe(5); // step 0
  });
});

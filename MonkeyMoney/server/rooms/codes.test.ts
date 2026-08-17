// Raum-Codes: Format, Verwechsler-freies Alphabet, Kollisionsfreiheit.
import { describe, expect, it } from "vitest";
import { createRng } from "../../shared/rng";
import { CODE_ALPHABET, generiereRaumCode, istGueltigerCode } from "./codes";

describe("rooms: Raum-Codes", () => {
  it("erzeugt 4 Buchstaben aus dem Verwechsler-freien Alphabet (kein I/O)", () => {
    const rng = createRng(1);
    for (let i = 0; i < 50; i++) {
      const code = generiereRaumCode(rng, new Set());
      expect(code).toHaveLength(4);
      expect(istGueltigerCode(code)).toBe(true);
      expect(code).not.toMatch(/[IO01]/);
    }
    expect(CODE_ALPHABET).not.toContain("I");
    expect(CODE_ALPHABET).not.toContain("O");
  });

  it("weicht vergebenen Codes aus (kollisionsfrei)", () => {
    const rng1 = createRng(7);
    const erster = generiereRaumCode(rng1, new Set());
    // Gleicher Seed ⇒ gleicher erster Vorschlag — mit belegtem Code MUSS ein anderer kommen.
    const rng2 = createRng(7);
    const zweiter = generiereRaumCode(rng2, new Set([erster]));
    expect(zweiter).not.toBe(erster);
  });

  it("wirft, wenn kein Code mehr frei ist", () => {
    const rng = createRng(3);
    const alleBelegt = {
      has: () => true,
      size: Number.MAX_SAFE_INTEGER,
    } as unknown as ReadonlySet<string>;
    expect(() => generiereRaumCode(rng, alleBelegt)).toThrow();
  });

  it("validiert Codes strikt (Länge + Alphabet)", () => {
    expect(istGueltigerCode("AFFE")).toBe(true);
    expect(istGueltigerCode("AFF")).toBe(false);
    expect(istGueltigerCode("AIOE")).toBe(false); // I/O nicht im Alphabet
  });
});

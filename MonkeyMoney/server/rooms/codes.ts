// Raum-Codes: 4 Buchstaben, Alphabet ohne Verwechsler (kein I/O — Ziffern gibt es
// nicht, also auch kein 0/1-Problem), server-generiert, kollisionsfrei.
import type { Rng } from "../../shared/rng";

export const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ"; // 24 Buchstaben
export const CODE_LAENGE = 4;

export function istGueltigerCode(code: string): boolean {
  return code.length === CODE_LAENGE && [...code].every((c) => CODE_ALPHABET.includes(c));
}

/**
 * Erzeugt einen freien Raum-Code. Wirft, wenn nach vielen Versuchen nichts
 * frei ist (praktisch nur bei MAX_ROOMS-Fehlkonfiguration erreichbar).
 */
export function generiereRaumCode(rng: Rng, vergeben: ReadonlySet<string>): string {
  for (let versuch = 0; versuch < 1000; versuch++) {
    let code = "";
    for (let i = 0; i < CODE_LAENGE; i++) {
      code += CODE_ALPHABET[rng.int(CODE_ALPHABET.length)];
    }
    if (!vergeben.has(code)) return code;
  }
  throw new Error("Kein freier Raum-Code gefunden (Raum-Limit prüfen)");
}

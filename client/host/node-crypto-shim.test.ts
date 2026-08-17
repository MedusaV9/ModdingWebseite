// Shim-Verifikation gegen die REFERENZ: vitest läuft in Node, also vergleichen
// wir die Pure-TS-SHA-256 (Browser-Pfad des profile-store-PIN-Hashes) Bit für
// Bit mit node:crypto — inklusive Multi-Block (>64 Byte) und UTF-8-Umlauten.
import { createHash as nodeCreateHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import { createHash, randomUUID } from "./node-crypto-shim";

const referenz = (text: string): string => nodeCreateHash("sha256").update(text).digest("hex");

describe("node-crypto-shim: createHash('sha256') — identisch zu node:crypto", () => {
  it.each([
    ["leer", ""],
    ["kurz", "pr_abc123:1234"],
    ["ein Block exakt (64 Byte Grenze)", "a".repeat(64)],
    ["Padding-Kante (55/56/57 Byte)", "b".repeat(55)],
    ["Padding-Kante 56", "b".repeat(56)],
    ["Multi-Block lang", "MONKEY MONEY 🐒 Bananen-Tresor!".repeat(40)],
    ["UTF-8 Umlaute/Emoji", "Zoë:Prüfung-🍌-ßÄÖÜ:0815"],
  ])("Hash stimmt: %s", (_name, text) => {
    expect(createHash("sha256").update(text).digest("hex")).toBe(referenz(text));
  });

  it("PIN-Hash-Muster des profile-store (profileId:pin) stimmt überein", () => {
    const text = "pr_1a2b3c4d:4711";
    expect(createHash("sha256").update(text).digest("hex")).toBe(referenz(text));
  });

  it("lehnt fremde Algorithmen/Formate laut ab (kein stiller Falsch-Hash)", () => {
    expect(() => createHash("md5")).toThrow(/nur sha256/);
    expect(() => createHash("sha256").update("x").digest("base64")).toThrow(/nur hex/);
  });

  it("randomUUID liefert RFC-4122-v4-Format", () => {
    const uuid = randomUUID();
    expect(uuid).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  });
});

// Browser-Shim für node:crypto (vite.config-Alias, NUR im Client-Build aktiv):
// Der Browser-Server bündelt rooms/room.ts, rooms/sessions.ts, core/sockets.ts
// und (seit dem Meta-Wiring, W4) meta/profile-store.ts, die randomUUID bzw.
// createHash aus node:crypto ziehen. randomUUID kommt aus WebCrypto;
// createHash("sha256") ist eine SYNCHRONE Pure-TS-Implementierung, weil
// WebCryptos subtle.digest async ist und die PIN-Hash-Signatur des
// profile-store synchron bleibt (API-konservativ — der Node-Pfad ist die
// Referenz, der Shim-Test vergleicht beide Bit für Bit).
export function randomUUID(): string {
  const webCrypto = globalThis.crypto;
  if (typeof webCrypto.randomUUID === "function") return webCrypto.randomUUID();
  // Fallback für nicht-sichere Kontexte (z. B. http://<lan-ip> im Test-Browser):
  // RFC-4122-v4 von Hand aus getRandomValues.
  const bytes = webCrypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = [...bytes].map((b) => b.toString(16).padStart(2, "0"));
  return [
    hex.slice(0, 4).join(""),
    hex.slice(4, 6).join(""),
    hex.slice(6, 8).join(""),
    hex.slice(8, 10).join(""),
    hex.slice(10).join(""),
  ].join("-");
}

// ---------- createHash("sha256") — synchron, FIPS-180-4 ----------

const K = new Uint32Array([
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]);

const rotr = (x: number, n: number): number => (x >>> n) | (x << (32 - n));

function sha256Hex(text: string): string {
  const daten = new TextEncoder().encode(text);
  // Padding: 0x80, Nullen, dann 64-Bit-Bitlänge big-endian (Blöcke à 64 Byte).
  const gesamt = (((daten.length + 8) >> 6) + 1) << 6;
  const puffer = new Uint8Array(gesamt);
  puffer.set(daten);
  puffer[daten.length] = 0x80;
  const dv = new DataView(puffer.buffer);
  const bitLen = daten.length * 8;
  dv.setUint32(gesamt - 8, Math.floor(bitLen / 4294967296));
  dv.setUint32(gesamt - 4, bitLen >>> 0);

  const h = new Uint32Array([
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ]);
  const w = new Uint32Array(64);
  for (let block = 0; block < gesamt; block += 64) {
    for (let i = 0; i < 16; i++) w[i] = dv.getUint32(block + i * 4);
    for (let i = 16; i < 64; i++) {
      const s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
      const s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
    }
    let [a, b, c, d, e, f, g, hh] = h;
    for (let i = 0; i < 64; i++) {
      const s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      const ch = (e & f) ^ (~e & g);
      const t1 = (hh + s1 + ch + K[i] + w[i]) >>> 0;
      const s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      const maj = (a & b) ^ (a & c) ^ (b & c);
      const t2 = (s0 + maj) >>> 0;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) >>> 0;
    }
    h[0] = (h[0] + a) >>> 0;
    h[1] = (h[1] + b) >>> 0;
    h[2] = (h[2] + c) >>> 0;
    h[3] = (h[3] + d) >>> 0;
    h[4] = (h[4] + e) >>> 0;
    h[5] = (h[5] + f) >>> 0;
    h[6] = (h[6] + g) >>> 0;
    h[7] = (h[7] + hh) >>> 0;
  }
  return [...h].map((x) => x.toString(16).padStart(8, "0")).join("");
}

/** Genau die Teilmenge, die meta/profile-store.ts nutzt:
 * createHash("sha256").update(text).digest("hex"). */
export function createHash(algorithmus: string): {
  update(text: string): { digest(format: string): string };
} {
  if (algorithmus !== "sha256") {
    throw new Error(`node-crypto-shim: nur sha256, nicht "${algorithmus}"`);
  }
  return {
    update(text: string) {
      return {
        digest(format: string): string {
          if (format !== "hex") throw new Error(`node-crypto-shim: nur hex, nicht "${format}"`);
          return sha256Hex(text);
        },
      };
    },
  };
}

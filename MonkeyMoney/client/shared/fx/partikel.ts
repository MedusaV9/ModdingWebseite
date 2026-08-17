// Partikel-Overlay (Plan §3-Rendering-Grundsatz): EIN transparentes Vollbild-
// Canvas für Konfetti-Kanone, Money-Regen und fliegende Scheine (Klau).
// Deckel 120 Sprites, prefers-reduced-motion = aus, rAF läuft nur bei Bedarf.
// Zufall: eigener Mini-LCG (deterministisch, keine OS-Rng in Spiellogik).
// Stil-Parameter (§7.4 — Shop-Items wirken im Match): "bananen" regnet Bananen,
// "8bit" zeichnet Pixel-Geld — der Stil kommt aus dem Profil des Gefeierten.
import type { KonfettiStil } from "../../../shared/meta";

type PartikelStil = "bananen" | "8bit" | "muenzen" | "laub" | "blaetter";

interface Partikel {
  art: "konfetti" | "schein";
  x: number;
  y: number;
  vx: number;
  vy: number;
  rot: number;
  vrot: number;
  farbe: string;
  leben: number; // Restlebenszeit in ms
  gesamt: number;
  /** Gekaufter Konfetti-Stil — undefined = klassisch. */
  stil?: PartikelStil;
  /** Zielflug (Klau): von Start zu Ziel statt Physik. */
  ziel?: { x0: number; y0: number; x1: number; y1: number };
}

export interface PartikelApi {
  konfetti(opts?: { x?: number; y?: number; anzahl?: number; stil?: KonfettiStil }): void;
  moneyRegen(opts?: { anzahl?: number; farbe?: string; stil?: KonfettiStil }): void;
  scheine(opts: {
    vonX: number;
    vonY: number;
    zuX: number;
    zuY: number;
    anzahl?: number;
    farbe?: string;
  }): void;
  leeren(): void;
}

/** Opts-Stil → Partikel-Stil (klassisch bleibt undefined = Standard-Zeichnung). */
function stilVon(stil: KonfettiStil | undefined): PartikelStil | undefined {
  return stil === undefined || stil === "klassisch" ? undefined : stil;
}

const KONFETTI_FARBEN = ["#f5b301", "#ffc93c", "#ff3e8e", "#29d9d5", "#8fe04b", "#fff6e3"];
// Stil-Paletten: Herbstlaub in Rost-/Goldtönen, Blätterwirbel (Pass S1) in Dschungel-Grün.
const LAUB_FARBEN = ["#c1440e", "#d99a3d", "#8a5a3b", "#f5b301", "#a33b20", "#e07b39"];
const BLAETTER_FARBEN = ["#8fe04b", "#4c9a2a", "#2e7d32", "#a2d95e", "#6ab04c", "#38761d"];

function farbeFuer(stil: PartikelStil | undefined, i: number): string {
  if (stil === "laub") return LAUB_FARBEN[i % LAUB_FARBEN.length];
  if (stil === "blaetter") return BLAETTER_FARBEN[i % BLAETTER_FARBEN.length];
  if (stil === "muenzen") return "#f5b301";
  return KONFETTI_FARBEN[i % KONFETTI_FARBEN.length];
}
const MAX_SPRITES = 120;

let seed = 7;
const rnd = (): number => (seed = (seed * 48271) % 2147483647) / 2147483647;
const zw = (a: number, b: number): number => a + rnd() * (b - a);

export function createPartikel(canvas: HTMLCanvasElement): PartikelApi {
  const ctx = canvas.getContext("2d");
  const reduziert = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const teilchen: Partikel[] = [];
  let laeuft = false;
  let zuletzt = 0;

  function resize(): void {
    canvas.width = canvas.clientWidth;
    canvas.height = canvas.clientHeight;
  }
  window.addEventListener("resize", resize);
  resize();

  /** Banane als Sichel (Doppel-Strich: Outline + Fruchtfleisch) + Stiel-Punkt. */
  function zeichneBanane(c: CanvasRenderingContext2D, r: number): void {
    c.lineCap = "round";
    c.strokeStyle = "#1a1208";
    c.lineWidth = r * 0.62 + 3;
    c.beginPath();
    c.arc(0, -r * 0.35, r, Math.PI * 0.12, Math.PI * 0.88);
    c.stroke();
    c.strokeStyle = "#ffc93c";
    c.lineWidth = r * 0.62;
    c.stroke();
    c.fillStyle = "#8a5a3b";
    c.beginPath();
    c.arc(r * 0.93, -r * 0.35 + r * 0.37, r * 0.22, 0, Math.PI * 2);
    c.fill();
  }

  /** Goldmünze: Scheibe + Prägering + Glanzpunkt (dreht via rot-Skalierung). */
  function zeichneMuenze(c: CanvasRenderingContext2D, r: number, rot: number): void {
    // „3D"-Dreh-Effekt: horizontale Stauchung über den Rotationswinkel.
    const quetsch = Math.max(0.25, Math.abs(Math.cos(rot)));
    c.scale(quetsch, 1);
    c.fillStyle = "#f5b301";
    c.strokeStyle = "#1a1208";
    c.lineWidth = 2.5;
    c.beginPath();
    c.arc(0, 0, r, 0, Math.PI * 2);
    c.fill();
    c.stroke();
    c.strokeStyle = "#ffc93c";
    c.lineWidth = 2;
    c.beginPath();
    c.arc(0, 0, r * 0.62, 0, Math.PI * 2);
    c.stroke();
    c.fillStyle = "#fff6e3";
    c.beginPath();
    c.arc(-r * 0.3, -r * 0.35, r * 0.18, 0, Math.PI * 2);
    c.fill();
  }

  /** Blatt (Laub/Dschungel): spitze Ellipse aus zwei Bögen + Mittelrippe. */
  function zeichneBlatt(c: CanvasRenderingContext2D, farbe: string, r: number): void {
    c.fillStyle = farbe;
    c.strokeStyle = "#1a1208";
    c.lineWidth = 1.5;
    c.beginPath();
    c.moveTo(0, -r);
    c.quadraticCurveTo(r * 0.85, 0, 0, r);
    c.quadraticCurveTo(-r * 0.85, 0, 0, -r);
    c.closePath();
    c.fill();
    c.stroke();
    c.beginPath();
    c.moveTo(0, -r * 0.8);
    c.lineTo(0, r * 0.8);
    c.stroke();
  }

  /** Pixel-Schein (8-Bit): harte Kanten, Block-Rahmen, Pixel-„Auge". */
  function zeichnePixelSchein(c: CanvasRenderingContext2D, farbe: string): void {
    c.fillStyle = "#85bb65";
    c.fillRect(-16, -9, 32, 18);
    c.fillStyle = "#1a1208";
    c.fillRect(-16, -9, 32, 3);
    c.fillRect(-16, 6, 32, 3);
    c.fillRect(-16, -9, 3, 18);
    c.fillRect(13, -9, 3, 18);
    c.fillStyle = farbe;
    c.fillRect(-11, -5, 4, 10);
    c.fillStyle = "#fff6e3";
    c.fillRect(1, -4, 8, 8);
  }

  function zeichne(p: Partikel): void {
    if (!ctx) return;
    ctx.save();
    ctx.translate(p.x, p.y);
    // 8-Bit-Stil: Rotation auf 90°-Raster einrasten (Retro-Look ohne Schräglage).
    // Münzen drehen um die VERTIKALE Achse (Stauchung in zeichneMuenze) statt zu kippen.
    const halbPi = Math.PI / 2;
    ctx.rotate(
      p.stil === "8bit" ? Math.round(p.rot / halbPi) * halbPi : p.stil === "muenzen" ? 0 : p.rot,
    );
    ctx.globalAlpha = Math.min(1, p.leben / 500);
    if (p.art === "konfetti") {
      if (p.stil === "bananen") zeichneBanane(ctx, 8);
      else if (p.stil === "muenzen") zeichneMuenze(ctx, 7, p.rot * 3);
      else if (p.stil === "laub" || p.stil === "blaetter") zeichneBlatt(ctx, p.farbe, 9);
      else if (p.stil === "8bit") {
        ctx.fillStyle = p.farbe;
        ctx.fillRect(-4, -4, 9, 9);
      } else {
        ctx.fillStyle = p.farbe;
        ctx.fillRect(-5, -3, 10, 6);
      }
    } else if (p.stil === "bananen") {
      zeichneBanane(ctx, 13);
    } else if (p.stil === "muenzen") {
      zeichneMuenze(ctx, 12, p.rot * 3);
    } else if (p.stil === "laub" || p.stil === "blaetter") {
      zeichneBlatt(ctx, p.farbe, 14);
    } else if (p.stil === "8bit") {
      zeichnePixelSchein(ctx, p.farbe);
    } else {
      // Banana Buck: Bill-Green-Fläche + Outline + Farbbalken des Besitzers
      ctx.fillStyle = "#85bb65";
      ctx.strokeStyle = "#1a1208";
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.roundRect(-16, -9, 32, 18, 3);
      ctx.fill();
      ctx.stroke();
      ctx.fillStyle = p.farbe;
      ctx.fillRect(-13, -6, 4, 12);
      ctx.fillStyle = "#fff6e3";
      ctx.beginPath();
      ctx.ellipse(2, 0, 5, 4, 0, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  }

  function schritt(ts: number): void {
    if (!ctx) return;
    const dt = Math.min(48, zuletzt === 0 ? 16 : ts - zuletzt);
    zuletzt = ts;
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    for (let i = teilchen.length - 1; i >= 0; i--) {
      const p = teilchen[i];
      p.leben -= dt;
      if (p.leben <= 0 || p.y > canvas.height + 40) {
        teilchen.splice(i, 1);
        continue;
      }
      if (p.ziel) {
        // Klau-Flug: quadratische Kurve mit Überschwung nach oben
        const t = 1 - p.leben / p.gesamt;
        const mx = (p.ziel.x0 + p.ziel.x1) / 2;
        const my = Math.min(p.ziel.y0, p.ziel.y1) - 120;
        const u = 1 - t;
        p.x = u * u * p.ziel.x0 + 2 * u * t * mx + t * t * p.ziel.x1;
        p.y = u * u * p.ziel.y0 + 2 * u * t * my + t * t * p.ziel.y1;
      } else {
        // Schwerkraft MIT Endgeschwindigkeit (Luftwiderstand): Scheine segeln
        // gemächlich (~2,5 s pro Bildschirmhöhe), Konfetti fliegt im Bogen.
        const vMax = p.art === "schein" ? 0.32 : 0.55;
        const g = p.art === "schein" ? 0.0005 : 0.0012;
        p.vy = Math.min(vMax, p.vy + g * dt);
        p.x += p.vx * dt;
        p.y += p.vy * dt;
      }
      p.rot += p.vrot * dt;
      zeichne(p);
    }
    if (teilchen.length > 0) requestAnimationFrame(schritt);
    else {
      laeuft = false;
      zuletzt = 0;
      ctx.clearRect(0, 0, canvas.width, canvas.height);
    }
  }

  function start(): void {
    if (laeuft || teilchen.length === 0) return;
    laeuft = true;
    zuletzt = 0;
    requestAnimationFrame(schritt);
  }

  function platz(anzahl: number): number {
    return Math.max(0, Math.min(anzahl, MAX_SPRITES - teilchen.length));
  }

  return {
    konfetti(opts = {}) {
      if (reduziert) return;
      const x = opts.x ?? canvas.width / 2;
      const y = opts.y ?? canvas.height * 0.65;
      const n = platz(opts.anzahl ?? 44);
      const stil = stilVon(opts.stil);
      for (let i = 0; i < n; i++) {
        const winkel = zw(-Math.PI * 0.85, -Math.PI * 0.15);
        const tempo = zw(0.25, 0.62);
        teilchen.push({
          art: "konfetti",
          x: x + zw(-24, 24),
          y,
          vx: Math.cos(winkel) * tempo,
          vy: Math.sin(winkel) * tempo,
          rot: zw(0, Math.PI),
          vrot: zw(-0.012, 0.012),
          farbe: farbeFuer(stil, i),
          leben: zw(1400, 2400),
          gesamt: 2400,
          stil,
        });
      }
      start();
    },
    moneyRegen(opts = {}) {
      if (reduziert) return;
      const n = platz(opts.anzahl ?? 30);
      const stil = stilVon(opts.stil);
      for (let i = 0; i < n; i++) {
        teilchen.push({
          art: "schein",
          x: zw(0, canvas.width),
          y: zw(-canvas.height * 0.6, -20),
          vx: zw(-0.05, 0.05),
          vy: zw(0.1, 0.22),
          rot: zw(-0.6, 0.6),
          vrot: zw(-0.004, 0.004),
          farbe:
            stil === "muenzen" || stil === "laub" || stil === "blaetter"
              ? farbeFuer(stil, i)
              : (opts.farbe ?? "#f5b301"),
          leben: 6000,
          gesamt: 6000,
          stil,
        });
      }
      start();
    },
    scheine(opts) {
      if (reduziert) return;
      const n = platz(opts.anzahl ?? 7);
      for (let i = 0; i < n; i++) {
        const dauer = zw(700, 1150);
        teilchen.push({
          art: "schein",
          x: opts.vonX,
          y: opts.vonY,
          vx: 0,
          vy: 0,
          rot: zw(-0.5, 0.5),
          vrot: zw(-0.008, 0.008),
          farbe: opts.farbe ?? "#f5b301",
          leben: dauer + i * 90,
          gesamt: dauer + i * 90,
          ziel: {
            x0: opts.vonX + zw(-16, 16),
            y0: opts.vonY + zw(-10, 10),
            x1: opts.zuX + zw(-16, 16),
            y1: opts.zuY + zw(-10, 10),
          },
        });
      }
      start();
    },
    leeren() {
      teilchen.length = 0;
    },
  };
}

// FOTO-FINISH-Share (v2, E-02): teilbares Ergebnis-Bild KOMPLETT Client-seitig
// als eigene Canvas-Komposition (Logo-Schriftzug + Podium + Namen + Money +
// Datum). Bewusst OHNE externe Bild-Ladungen: nur Text/Formen/Emoji ⇒ synchron,
// nie „tainted", funktioniert über HTTP (LAN) und als data-URL speicherbar.
import { formatMM } from "../../shared/money";
import { avatarFarbe, parseAvatar } from "./fx/avatar";

export interface FotoFinishDaten {
  standings: { name: string; avatar: string; balance: number }[];
  /** Anzeigedatum (z. B. „15.08.2026") — der Aufrufer formatiert. */
  datum: string;
  roomCode?: string;
}

const BREITE = 1080;
const HOEHE = 1350; // 4:5 — Insta/WhatsApp-freundlich
const AFFEN_EMOJI: Record<string, string> = {
  "don-bananas": "🦍",
  "gitti-giro": "🐵",
  "kiki-krawall": "🐒",
  "baron-von-bananenstein": "🎩",
  "oma-zinseszins": "👵",
  "pumper-paule": "💪",
  "schnarch-schorsch": "😴",
  "glitzer-gina": "✨",
  "dj-trommelfell": "🎧",
  "astro-astrid": "🚀",
  "kommissar-kokosnuss": "🔍",
  "iro-ines": "🤘",
  "abraka-dieter": "🧙",
  "kahuna-kalle": "🏄",
};

function affenEmoji(avatar: string): string {
  return AFFEN_EMOJI[parseAvatar(avatar).affe] ?? "🐒";
}

/** Podium-Reihenfolge auf der Bühne: 2 | 1 | 3 (wie die Siegerehrung). */
function podestReihenfolge<T>(podest: T[]): { eintrag: T; platz: number }[] {
  const mitPlatz = podest.map((eintrag, i) => ({ eintrag, platz: i + 1 }));
  return [2, 1, 3]
    .map((platz) => mitPlatz.find((p) => p.platz === platz))
    .filter((p): p is { eintrag: T; platz: number } => p !== undefined);
}

/**
 * DIE Komposition: zeichnet das Ergebnis-Bild und liefert die PNG-data-URL.
 * Pure bzgl. der Eingaben — gleiche Daten ⇒ gleiches Bild (bis auf Font-Raster).
 */
export function zeichneFotoFinish(daten: FotoFinishDaten): string | null {
  const canvas = document.createElement("canvas");
  canvas.width = BREITE;
  canvas.height = HOEHE;
  const ctx = canvas.getContext("2d");
  if (!ctx) return null;

  // ---------- Hintergrund: Dschungel-Nacht mit Vignette + Konfetti-Sprenkeln ----------
  const verlauf = ctx.createLinearGradient(0, 0, 0, HOEHE);
  verlauf.addColorStop(0, "#0d2b1d");
  verlauf.addColorStop(1, "#071a11");
  ctx.fillStyle = verlauf;
  ctx.fillRect(0, 0, BREITE, HOEHE);
  const sprenkel = ["#ffc93c", "#ff3e8e", "#29d9d5", "#8fe04b"];
  for (let i = 0; i < 90; i++) {
    // deterministisch „gestreut" (kein Rng nötig): goldener-Schnitt-Hüpfer
    const x = ((i * 611) % BREITE) + 20;
    const y = ((i * 947) % (HOEHE - 80)) + 40;
    ctx.fillStyle = sprenkel[i % sprenkel.length];
    ctx.globalAlpha = 0.18;
    ctx.beginPath();
    ctx.arc(x, y, 5 + (i % 4), 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.globalAlpha = 1;

  // ---------- Kopf: Logo-Schriftzug + Datum ----------
  ctx.textAlign = "center";
  ctx.fillStyle = "#ffc93c";
  ctx.font = "900 92px system-ui, sans-serif";
  ctx.fillText("🐒 MONKEY MONEY", BREITE / 2, 140);
  ctx.fillStyle = "#fff6e3";
  ctx.font = "700 44px system-ui, sans-serif";
  ctx.fillText("FOTO-FINISH", BREITE / 2, 210);
  ctx.fillStyle = "#9dbfa9";
  ctx.font = "500 34px system-ui, sans-serif";
  ctx.fillText(
    daten.roomCode ? `${daten.datum} · Raum ${daten.roomCode}` : daten.datum,
    BREITE / 2,
    262,
  );

  // ---------- Podium (Plätze 1–3) ----------
  const podest = daten.standings.slice(0, 3);
  const sockelHoehen: Record<number, number> = { 1: 240, 2: 170, 3: 120 };
  const spaltenBreite = 300;
  const podiumMitte = BREITE / 2;
  const bodenY = 880;
  const spalten = podestReihenfolge(podest);
  spalten.forEach(({ eintrag, platz }, spalte) => {
    const x = podiumMitte + (spalte - 1) * spaltenBreite;
    const sockel = sockelHoehen[platz] ?? 100;
    const farbe = avatarFarbe(eintrag.avatar);
    // Sockel
    ctx.fillStyle = "#123a28";
    ctx.strokeStyle = farbe;
    ctx.lineWidth = 6;
    ctx.beginPath();
    ctx.roundRect(x - 120, bodenY - sockel, 240, sockel, 18);
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = "#ffc93c";
    ctx.font = "900 84px system-ui, sans-serif";
    ctx.fillText(String(platz), x, bodenY - sockel / 2 + 30);
    // Affe + Krone für Platz 1
    ctx.font = "120px system-ui, sans-serif";
    ctx.fillText(affenEmoji(eintrag.avatar), x, bodenY - sockel - 46);
    if (platz === 1) {
      ctx.font = "64px system-ui, sans-serif";
      ctx.fillText("👑", x, bodenY - sockel - 168);
    }
    // Namensschild + Money
    ctx.fillStyle = farbe;
    ctx.font = "800 40px system-ui, sans-serif";
    ctx.fillText(eintrag.name.slice(0, 12), x, bodenY + 52);
    ctx.fillStyle = "#fff6e3";
    ctx.font = "700 36px system-ui, sans-serif";
    ctx.fillText(formatMM(eintrag.balance), x, bodenY + 102);
  });

  // ---------- Restliche Plätze als Zeilen ----------
  const rest = daten.standings.slice(3);
  ctx.font = "600 34px system-ui, sans-serif";
  rest.forEach((s, i) => {
    const y = 1030 + i * 52;
    ctx.fillStyle = "#9dbfa9";
    ctx.textAlign = "right";
    ctx.fillText(`${i + 4}.`, BREITE / 2 - 220, y);
    ctx.fillStyle = "#fff6e3";
    ctx.textAlign = "left";
    ctx.fillText(`${affenEmoji(s.avatar)} ${s.name.slice(0, 16)}`, BREITE / 2 - 190, y);
    ctx.textAlign = "right";
    ctx.fillStyle = "#ffc93c";
    ctx.fillText(formatMM(s.balance), BREITE / 2 + 320, y);
  });
  ctx.textAlign = "center";

  // ---------- Fuß ----------
  ctx.fillStyle = "#9dbfa9";
  ctx.font = "500 30px system-ui, sans-serif";
  ctx.fillText("🍌 Wer sammelt das meiste MONKEY MONEY? 🍌", BREITE / 2, HOEHE - 60);

  return canvas.toDataURL("image/png");
}

/** Download anstoßen (Screen-Button UND Handy — data-URL ist HTTP-tauglich). */
export function ladeFotoHerunter(dataUrl: string, dateiname: string): void {
  const a = document.createElement("a");
  a.href = dataUrl;
  a.download = dateiname;
  document.body.appendChild(a);
  a.click();
  a.remove();
}

/** Dateiname mit Datum, z. B. monkey-money-2026-08-15.png. */
export function fotoDateiname(jetztMs: number): string {
  const d = new Date(jetztMs);
  const iso = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  return `monkey-money-${iso}.png`;
}

/** Anzeige-Datum (de), z. B. „15.08.2026". */
export function fotoDatum(jetztMs: number): string {
  const d = new Date(jetztMs);
  return `${String(d.getDate()).padStart(2, "0")}.${String(d.getMonth() + 1).padStart(2, "0")}.${d.getFullYear()}`;
}

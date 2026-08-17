// Avatar = Affe + Farbe (Join-Flow-Erweiterung). Wire-Format bleibt der
// hello.avatar-String: "affe.farbe" (z. B. "don-bananas.gelb"); Alt-Clients
// und Bots senden weiterhin nur die Farbe ("gelb") — dann wählt eine
// deterministische Zuordnung den Affen. Der Server reicht den String durch.
import { AVATAR_FARBEN, type AvatarFarbe } from "../../../shared/ids";

export interface AffeInfo {
  id: string;
  name: string;
  rolle: string; // Kurz-Charakterisierung für die Auswahl + Namensschilder
}

/**
 * Die 14 Affen (8 aus ART-PLAN §2.1 + 6 Erweiterungs-Welle) — Reihenfolge =
 * Auswahl-Reihenfolge. WICHTIG: Die ersten 8 NICHT umsortieren, ihre Indizes
 * bestimmen den Legacy-Farbe→Affe-Fallback (affeFuerFarbe).
 */
export const AFFEN: AffeInfo[] = [
  { id: "don-bananas", name: "Don Bananas", rolle: "der Pate" },
  { id: "gitti-giro", name: "Gitti Giro", rolle: "die Buchhalterin" },
  { id: "kiki-krawall", name: "Kiki Krawall", rolle: "das Chaos-Äffchen" },
  { id: "baron-von-bananenstein", name: "Baron Bodo", rolle: "der Adelige" },
  { id: "oma-zinseszins", name: "Oma Zinseszins", rolle: "die Unterschätzte" },
  { id: "pumper-paule", name: "Pumper-Paule", rolle: "der Gym-Gorilla" },
  { id: "schnarch-schorsch", name: "Schnarch-Schorsch", rolle: "der Entspannte" },
  { id: "glitzer-gina", name: "Glitzer-Gina", rolle: "die Diva" },
  { id: "dj-trommelfell", name: "DJ Trommelfell", rolle: "der Beat-Affe" },
  { id: "astro-astrid", name: "Astro-Astrid", rolle: "die Raumfahrerin" },
  { id: "kommissar-kokosnuss", name: "Kommissar Kokosnuss", rolle: "der Detektiv" },
  { id: "iro-ines", name: "Iro-Ines", rolle: "die Punkerin" },
  { id: "abraka-dieter", name: "Abraka-Dieter", rolle: "der Zauberer" },
  { id: "kahuna-kalle", name: "Kahuna-Kalle", rolle: "der Surfer" },
];

/** Spielerfarben nach Plan §1.1 (volle 8er-Reihe) + hellere Fell-Variante. */
export const FARBWERTE: Record<AvatarFarbe, { farbe: string; hell: string }> = {
  gelb: { farbe: "#ffc93c", hell: "#ffe9ad" },
  rot: { farbe: "#ff3e8e", hell: "#ffc2dc" },
  tuerkis: { farbe: "#29d9d5", hell: "#b8f2f0" },
  gruen: { farbe: "#8fe04b", hell: "#d8f5ba" },
  orange: { farbe: "#f97316", hell: "#fdc79e" },
  lila: { farbe: "#8b5cf6", hell: "#d5c5fc" },
  blau: { farbe: "#3b82f6", hell: "#bcd6fc" },
  pink: { farbe: "#f472b6", hell: "#fcd0e7" },
};

export interface AvatarWahl {
  affe: string;
  farbe: AvatarFarbe;
}

const AFFEN_IDS = new Set(AFFEN.map((a) => a.id));

function istFarbe(s: string): s is AvatarFarbe {
  return (AVATAR_FARBEN as readonly string[]).includes(s);
}

/** Legacy-Farbe → deterministischer Default-Affe (Bots, Alt-Sessions). */
export function affeFuerFarbe(farbe: AvatarFarbe): string {
  const i = (AVATAR_FARBEN as readonly string[]).indexOf(farbe);
  return AFFEN[(i >= 0 ? i : 0) % AFFEN.length].id;
}

/** "affe.farbe" | "farbe" | Unbekanntes → immer eine gültige Wahl. */
export function parseAvatar(avatar: string): AvatarWahl {
  const [a, b] = String(avatar).split(".");
  if (b !== undefined && AFFEN_IDS.has(a) && istFarbe(b)) return { affe: a, farbe: b };
  if (istFarbe(a)) return { affe: affeFuerFarbe(a), farbe: a };
  if (AFFEN_IDS.has(a)) return { affe: a, farbe: "gelb" };
  return { affe: AFFEN[0].id, farbe: "gelb" };
}

export function formatAvatar(wahl: AvatarWahl): string {
  return `${wahl.affe}.${wahl.farbe}`;
}

export function affeInfo(affeId: string): AffeInfo {
  return AFFEN.find((a) => a.id === affeId) ?? AFFEN[0];
}

/** Hex-Farbe eines Avatars (Namensschilder, Rahmen, Schein-Farbbalken). */
export function avatarFarbe(avatar: string): string {
  return FARBWERTE[parseAvatar(avatar).farbe].farbe;
}

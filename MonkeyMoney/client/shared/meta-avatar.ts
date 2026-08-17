// Shop-Kosmetik am Affen (GAME-DESIGN §7.4): Avatar-Extras aus dem Wire-Format
// "affe.farbe.item1+item2" als SVG-Overlays/Fell-Swaps auf die Gelenk-Puppen.
// Aufruf NACH fuellePuppen(root): schmueckePuppen(root, anAus) — idempotent.
// Alle Overlays hängen im #kopf (folgen Kopf-Animationen) bzw. am SVG-Root;
// alltimeItems=aus (Match-Setting) entfernt die Extras wieder (Gast-Fairness).
// NEU (§7.5, Meta-Agent 2): Banner (Hintergrund hinter der Puppe — Podium +
// Lobby), Namens-Stile (dezente CSS-Klassen/Farben) und das Level-Badge
// (Pseudo-Extra "lv<N>" im Avatar-String) — alles aus DEMSELBEN Wire-Format.
// NEU (Kosmetik-Welle 3, Cosmetics-Agent): 8 Kopf- + 4 Gesichts-Overlays aus
// assets/img/cosmetics/ (?raw, EINE Quelle für Client + Probe-Tools), 5 echte
// Fell-MUSTER als SVG-Pattern-Fill auf die .fell/.fell-s-Flächen, 3 Podium-
// Rahmen um den eigenen Podest-Platz und 2 Einlauf-Effekte fürs Opening.
import { avatarBasis, avatarExtras, avatarMitExtras, levelAusExtras } from "../../shared/meta";
import { itemFuer } from "../../shared/quests";
import hutPiratRoh from "../../assets/img/cosmetics/hut-pirat.svg?raw";
import hutKroneRoh from "../../assets/img/cosmetics/hut-krone.svg?raw";
import hutPropellerRoh from "../../assets/img/cosmetics/hut-propeller.svg?raw";
import hutHeiligenscheinRoh from "../../assets/img/cosmetics/hut-heiligenschein.svg?raw";
import hutTeufelshoernerRoh from "../../assets/img/cosmetics/hut-teufelshoerner.svg?raw";
import hutBlumenkranzRoh from "../../assets/img/cosmetics/hut-blumenkranz.svg?raw";
import hutRitterhelmRoh from "../../assets/img/cosmetics/hut-ritterhelm.svg?raw";
import hutPartyhutRoh from "../../assets/img/cosmetics/hut-partyhut.svg?raw";
import gesichtSchnurrbartRoh from "../../assets/img/cosmetics/gesicht-schnurrbart.svg?raw";
import gesichtSonnenbrilleRoh from "../../assets/img/cosmetics/gesicht-sonnenbrille.svg?raw";
import gesichtAugenklappeRoh from "../../assets/img/cosmetics/gesicht-augenklappe.svg?raw";
import gesichtKaugummiRoh from "../../assets/img/cosmetics/gesicht-kaugummi.svg?raw";
import fellTigerRoh from "../../assets/img/cosmetics/fell-tiger.svg?raw";
import fellDalmatinerRoh from "../../assets/img/cosmetics/fell-dalmatiner.svg?raw";
import fellSterneRoh from "../../assets/img/cosmetics/fell-sterne.svg?raw";
import fellCamoRoh from "../../assets/img/cosmetics/fell-camo.svg?raw";
import fellGoldglitzerRoh from "../../assets/img/cosmetics/fell-goldglitzer.svg?raw";
import podiumGirlandeRoh from "../../assets/img/cosmetics/podium-girlande.svg?raw";

/** Fell-/Spezies-Swaps: Item-Id → Custom-Property-Werte (Palette-Swap-Slot). */
const FELL_SWAPS: Record<string, { fell: string; hell: string }> = {
  "fell-leopard": { fell: "#d99a3d", hell: "#f2d09b" },
  "fell-neon": { fell: "#39ff14", hell: "#baffb0" },
  "spezies-orang-utan": { fell: "#c1440e", hell: "#f0a06a" },
  "spezies-pavian": { fell: "#8a8f98", hell: "#d8dbe0" },
};

/** Inhalt (und viewBox-Maße) aus einer Cosmetics-SVG-Datei ziehen (?raw). */
function svgKern(roh: string): { inhalt: string; breite: number; hoehe: number } {
  const vb = /viewBox="0 0 ([\d.]+) ([\d.]+)"/.exec(roh);
  const m = /<svg[^>]*>([\s\S]*)<\/svg>/.exec(roh);
  return {
    inhalt: m?.[1] ?? "",
    breite: Number(vb?.[1] ?? 0),
    hoehe: Number(vb?.[2] ?? 0),
  };
}

// SVG-Overlays im STANDARD-Kopfraum (Don Bananas: Kopf-Mitte 120/94, r 44,
// Augen ≈ 104/136 auf y 82). Die 14 Puppen teilen zwar das Skelett, aber NICHT
// die Kopf-Position/-Größe (Kiki tief, Oma vorgebeugt, Paule winzig …) — der
// Kopf-Anker unten mappt jedes Overlay affin auf die jeweilige Puppe.
// Kopf-Slot-Items docken im #accessoire an (der Standard-Hut der Puppe wird
// dabei per CSS ausgeblendet — Klasse mm-hut-an), Gesichts-Items im #kopf.
const HUT_OVERLAYS: Record<string, string> = {
  "hut-zylinder": `
    <rect x="94" y="46" width="52" height="10" rx="4" fill="#1f2430" stroke="#1A1208" stroke-width="3"/>
    <rect x="102" y="6" width="36" height="44" rx="4" fill="#1f2430" stroke="#1A1208" stroke-width="3"/>
    <rect x="102" y="38" width="36" height="8" fill="#f5b301"/>`,
  "hut-bananenhelm": `
    <path d="M 86 52 A 34 30 0 0 1 154 52 L 150 60 L 90 60 Z" fill="#ffc93c" stroke="#1A1208" stroke-width="3"/>
    <path d="M 96 30 Q 120 14 144 30" fill="none" stroke="#8fe04b" stroke-width="5" stroke-linecap="round"/>`,
  "hut-pirat": svgKern(hutPiratRoh).inhalt,
  "hut-krone": svgKern(hutKroneRoh).inhalt,
  "hut-propeller": svgKern(hutPropellerRoh).inhalt,
  "hut-heiligenschein": svgKern(hutHeiligenscheinRoh).inhalt,
  "hut-teufelshoerner": svgKern(hutTeufelshoernerRoh).inhalt,
  "hut-blumenkranz": svgKern(hutBlumenkranzRoh).inhalt,
  "hut-ritterhelm": svgKern(hutRitterhelmRoh).inhalt,
  "hut-partyhut": svgKern(hutPartyhutRoh).inhalt,
};

const GESICHT_OVERLAYS: Record<string, string> = {
  "gesicht-monokel": `
    <circle cx="135" cy="86" r="13" fill="none" stroke="#f5b301" stroke-width="3.5"/>
    <path d="M 146 94 Q 152 112 148 126" fill="none" stroke="#f5b301" stroke-width="2.5"/>`,
  "gesicht-3dbrille": `
    <rect x="92" y="78" width="26" height="16" rx="3" fill="#c2183b" opacity="0.85" stroke="#fff6e3" stroke-width="2.5"/>
    <rect x="122" y="78" width="26" height="16" rx="3" fill="#29d9d5" opacity="0.85" stroke="#fff6e3" stroke-width="2.5"/>
    <line x1="118" y1="86" x2="122" y2="86" stroke="#fff6e3" stroke-width="3"/>`,
  "gesicht-schnurrbart": svgKern(gesichtSchnurrbartRoh).inhalt,
  "gesicht-sonnenbrille": svgKern(gesichtSonnenbrilleRoh).inhalt,
  "gesicht-augenklappe": svgKern(gesichtAugenklappeRoh).inhalt,
  "gesicht-kaugummi": svgKern(gesichtKaugummiRoh).inhalt,
};

// Kopf-Anker pro Puppe (Kopf-Kreis aus assets/img/monkeys/<id>.svg): Overlays
// sind für den Standard-Kopf gezeichnet und werden mit translate+scale auf
// diese Anker gelegt — Hüte sitzen so auch auf Kiki (tief) und Paule (winzig).
const KOPF_STANDARD = { x: 120, y: 94, r: 44 };
const KOPF_ANKER: Record<string, { x: number; y: number; r: number }> = {
  "don-bananas": { x: 120, y: 94, r: 44 },
  "gitti-giro": { x: 120, y: 102, r: 42 },
  "kiki-krawall": { x: 120, y: 166, r: 36 },
  "baron-von-bananenstein": { x: 120, y: 98, r: 42 },
  "oma-zinseszins": { x: 112, y: 140, r: 38 },
  "pumper-paule": { x: 120, y: 74, r: 30 },
  "schnarch-schorsch": { x: 120, y: 106, r: 42 },
  "glitzer-gina": { x: 120, y: 112, r: 40 },
  "dj-trommelfell": { x: 120, y: 94, r: 42 },
  "astro-astrid": { x: 120, y: 96, r: 34 },
  "kommissar-kokosnuss": { x: 120, y: 96, r: 40 },
  "iro-ines": { x: 120, y: 98, r: 38 },
  "abraka-dieter": { x: 120, y: 92, r: 40 },
  "kahuna-kalle": { x: 120, y: 96, r: 41 },
};

/** transform-Attribut, das den Standard-Kopfraum auf die Puppe mappt — null = passt schon. */
function kopfTransform(affeId: string | undefined): string | null {
  const anker = affeId !== undefined ? KOPF_ANKER[affeId] : undefined;
  if (anker === undefined) return null;
  const s = anker.r / KOPF_STANDARD.r;
  const tx = anker.x - s * KOPF_STANDARD.x;
  const ty = anker.y - s * KOPF_STANDARD.y;
  if (Math.abs(s - 1) < 0.01 && Math.abs(tx) < 0.5 && Math.abs(ty) < 0.5) return null;
  return `translate(${tx.toFixed(2)} ${ty.toFixed(2)}) scale(${s.toFixed(3)})`;
}

const ROOT_OVERLAYS: Record<string, string> = {
  "hand-kaffeetasse": `
    <g transform="translate(182 196)">
      <rect x="-10" y="-10" width="22" height="18" rx="3" fill="#fff6e3" stroke="#1A1208" stroke-width="3"/>
      <path d="M 12 -6 Q 22 -2 12 4" fill="none" stroke="#1A1208" stroke-width="3"/>
      <path d="M -4 -14 q 2 -5 0 -8 M 4 -14 q 2 -5 0 -8" fill="none" stroke="#9dbfa9" stroke-width="2.5" stroke-linecap="round"/>
    </g>`,
  "hand-minibuzzer": `
    <g transform="translate(56 198)">
      <rect x="-12" y="0" width="24" height="8" rx="3" fill="#1f2430" stroke="#1A1208" stroke-width="3"/>
      <ellipse cx="0" cy="-2" rx="9" ry="6" fill="#ff3e8e" stroke="#1A1208" stroke-width="3"/>
    </g>`,
};

// Fell-MUSTER (Welle 3): nahtlose Kacheln aus assets/img/cosmetics/, injiziert
// als <pattern> mit Instanz-eindeutiger Id + <style>, der .fell (fill) und
// .fell-s (stroke — Arme/Beine/Schwanz sind dicke Striche!) auf das Pattern
// umbiegt. Die Kachel-Basis nutzt var(--fell) ⇒ Palette-Swaps scheinen durch.
function kachelAus(roh: string): { kachel: string; breite: number; hoehe: number } {
  const kern = svgKern(roh);
  return { kachel: kern.inhalt, breite: kern.breite, hoehe: kern.hoehe };
}

const FELL_MUSTER: Record<string, { kachel: string; breite: number; hoehe: number }> = {
  "fell-tiger": kachelAus(fellTigerRoh),
  "fell-dalmatiner": kachelAus(fellDalmatinerRoh),
  "fell-sterne": kachelAus(fellSterneRoh),
  "fell-camo": kachelAus(fellCamoRoh),
  "fell-goldglitzer": kachelAus(fellGoldglitzerRoh),
};

// Podium-Rahmen (Welle 3): CSS-Klassen am Puppen-Slot (Podium/Lobby/Vorschau);
// die Girlande bekommt zusätzlich eine SVG-Deko-Leiste über dem Slot.
const PODIUM_RAHMEN: Record<string, string> = {
  "podium-goldrahmen": "mm-podium-goldrahmen",
  "podium-neon": "mm-podium-neon",
  "podium-girlande": "mm-podium-girlande",
};

const GIRLANDE = svgKern(podiumGirlandeRoh);
const GIRLANDE_HTML = `<svg viewBox="0 0 ${GIRLANDE.breite} ${GIRLANDE.hoehe}" preserveAspectRatio="none" aria-hidden="true">${GIRLANDE.inhalt}</svg>`;

// Einlauf-Effekte (Welle 3): spielen bei der Kandidaten-Vorstellung im Opening
// (.kandidaten-karte) — bzw. in der Shop-Vorschau via Klasse mm-einlauf-demo.
const EINLAUF_EFFEKTE: Record<string, string> = {
  "einlauf-rauchwolke": `
    <span class="wolke" style="left:6%;width:40%;aspect-ratio:1;--puff-delay:0s"></span>
    <span class="wolke" style="left:32%;width:48%;aspect-ratio:1;--puff-delay:0.08s"></span>
    <span class="wolke" style="left:58%;width:36%;aspect-ratio:1;--puff-delay:0.16s"></span>
    <span class="wolke" style="left:22%;width:30%;aspect-ratio:1;--puff-delay:0.26s"></span>
    <span class="wolke" style="left:46%;width:26%;aspect-ratio:1;--puff-delay:0.34s"></span>`,
  "einlauf-blitz": `
    <svg class="blitz-svg" viewBox="0 0 100 130" preserveAspectRatio="none" aria-hidden="true">
      <path class="blitz-strahl" d="M 56 0 L 38 52 L 52 52 L 34 104 L 66 44 L 51 44 L 68 0 Z"
        fill="#ffe9ad" stroke="#f5b301" stroke-width="3" stroke-linejoin="round"/>
    </svg>
    <span class="blitz-flash"></span>
    <span class="funke" style="left:30%;bottom:18%;--fx:-26px;--fy:-34px"></span>
    <span class="funke" style="left:56%;bottom:16%;--fx:18px;--fy:-40px;background:#29d9d5"></span>
    <span class="funke" style="left:44%;bottom:24%;--fx:-6px;--fy:-48px;background:#fff6e3"></span>`,
};

const HOLO_STYLE = `
  .mm-holo-an { animation: mm-holo-flimmern 1.6s ease-in-out infinite; filter: drop-shadow(0 0 7px #29d9d5) saturate(0.7) hue-rotate(160deg); }
  @keyframes mm-holo-flimmern { 0%,100% { opacity: 0.85; } 45% { opacity: 0.68; } 50% { opacity: 0.92; } 55% { opacity: 0.72; } }
  .mm-neon-an { animation: mm-neon-puls 3s linear infinite; }
  @keyframes mm-neon-puls { 0%,100% { filter: drop-shadow(0 0 4px #39ff14); } 50% { filter: drop-shadow(0 0 10px #39ff14) hue-rotate(25deg); } }
  .mm-banner-an { border-radius: 14px; box-shadow: inset 0 0 0 2px rgba(26,18,8,0.35); }
  .mm-lv-abzeichen { display:inline-block; margin-left:6px; padding:0 6px; border-radius:9px;
    background:#f5b301; color:#1a1208; font-size:0.68em; font-weight:800;
    border:2px solid #1a1208; vertical-align:middle; line-height:1.5; }
  .mm-name-neon { color:#8fe04b; text-shadow:0 0 6px rgba(143,224,75,0.8); }
  .mm-name-eis { color:#9bd7ff; text-shadow:0 0 5px rgba(155,215,255,0.7); }
  .mm-name-gold { background:linear-gradient(90deg,#f5b301,#fff3b0,#f5b301); background-size:200% 100%;
    -webkit-background-clip:text; background-clip:text; color:transparent;
    animation:mm-name-gold-schimmer 4s linear infinite; }
  @keyframes mm-name-gold-schimmer { to { background-position:200% 0; } }
  .mm-name-regenbogen { background:linear-gradient(90deg,#ff5f6d,#f5b301,#8fe04b,#29d9d5,#a06bff,#ff5f6d);
    background-size:300% 100%; -webkit-background-clip:text; background-clip:text; color:transparent;
    animation:mm-name-rgb 6s linear infinite; }
  @keyframes mm-name-rgb { to { background-position:300% 0; } }

  /* ---------- Kosmetik-Welle 3 (Cosmetics-Agent) ---------- */
  /* Gekaufter Kopf-Schmuck ersetzt den Standard-Hut im #accessoire-Slot. */
  svg.mm-hut-an #accessoire > :not(.mm-meta-extra) { display: none; }
  .mm-propeller { transform-box: fill-box; transform-origin: center; animation: mm-propeller-dreh 0.9s linear infinite; }
  @keyframes mm-propeller-dreh { 0% { transform: scaleX(1); } 25% { transform: scaleX(0.12); }
    50% { transform: scaleX(-1); } 75% { transform: scaleX(-0.12); } 100% { transform: scaleX(1); } }
  .mm-heiligenschein { animation: mm-halo-schweben 2.6s ease-in-out infinite; }
  @keyframes mm-halo-schweben { 0%,100% { transform: translateY(0); } 50% { transform: translateY(-4px); } }
  .mm-partyhut-konfetti { transform-box: fill-box; transform-origin: center; animation: mm-konfetti-flattern 1.8s ease-in-out infinite; }
  @keyframes mm-konfetti-flattern { 0%,100% { transform: translateY(0) rotate(0deg); } 50% { transform: translateY(-2.5px) rotate(4deg); } }
  .mm-kaugummi { transform-box: fill-box; transform-origin: 50% 6%; animation: mm-kaugummi-puls 2.4s ease-in-out infinite; }
  @keyframes mm-kaugummi-puls { 0%,100% { transform: scale(1); } 50% { transform: scale(1.09); } }
  .mm-gold-schimmer { animation: mm-gold-schimmer-puls 3.2s ease-in-out infinite; }
  @keyframes mm-gold-schimmer-puls { 0%,100% { filter: saturate(1); } 50% { filter: saturate(1.3) drop-shadow(0 0 6px rgba(245,179,1,0.55)); } }
  .mm-deko-traeger { position: relative; }
  .mm-podium-goldrahmen { outline: 4px solid #f5b301; outline-offset: -1px; border-radius: 14px;
    box-shadow: 0 0 14px rgba(245,179,1,0.55), inset 0 0 0 3px rgba(26,18,8,0.4); }
  .mm-podium-neon { outline: 3px solid #29d9d5; outline-offset: -1px; border-radius: 14px;
    animation: mm-podium-neon-puls 2.2s ease-in-out infinite; }
  @keyframes mm-podium-neon-puls {
    0%,100% { box-shadow: 0 0 8px rgba(41,217,213,0.5), inset 0 0 6px rgba(41,217,213,0.25); }
    50% { box-shadow: 0 0 18px rgba(41,217,213,0.9), inset 0 0 12px rgba(41,217,213,0.4); } }
  .mm-podium-deko { position: absolute; left: -4%; right: -4%; top: -6px; pointer-events: none; z-index: 2; }
  .mm-podium-deko svg { display: block; width: 100%; height: auto; }
  .mm-einlauf-fx { position: absolute; inset: 0; overflow: visible; pointer-events: none; z-index: 3; }
  .mm-einlauf-fx .wolke { position: absolute; bottom: 4%; border-radius: 50%; opacity: 0;
    background: radial-gradient(circle at 35% 35%, #fff6e3 0 30%, #cfc9c2 68%, rgba(207,201,194,0) 72%);
    animation: mm-rauch-puff 1.5s ease-out calc(var(--mm-einlauf-delay, 0s) + var(--puff-delay, 0s)) forwards; }
  @keyframes mm-rauch-puff { 0% { opacity: 0; transform: translateY(10%) scale(0.4); }
    18% { opacity: 0.95; } 100% { opacity: 0; transform: translateY(-46%) scale(1.5); } }
  .mm-einlauf-fx .blitz-svg { position: absolute; inset: 0; width: 100%; height: 100%; }
  .mm-einlauf-fx .blitz-strahl { opacity: 0; transform-box: fill-box; transform-origin: top center;
    animation: mm-blitz-schlag 0.9s cubic-bezier(0.2, 0.9, 0.3, 1) var(--mm-einlauf-delay, 0s) forwards; }
  @keyframes mm-blitz-schlag { 0% { opacity: 0; transform: scaleY(0); } 8% { opacity: 1; transform: scaleY(1); }
    30% { opacity: 1; } 45% { opacity: 0.2; } 55% { opacity: 0.9; } 100% { opacity: 0; } }
  .mm-einlauf-fx .blitz-flash { position: absolute; inset: -6%; border-radius: 16px; opacity: 0;
    background: radial-gradient(circle at 50% 30%, rgba(255,246,227,0.95), rgba(255,246,227,0) 70%);
    animation: mm-blitz-flash 0.7s ease-out calc(var(--mm-einlauf-delay, 0s) + 0.08s) forwards; }
  @keyframes mm-blitz-flash { 0% { opacity: 0; } 15% { opacity: 1; } 100% { opacity: 0; } }
  .mm-einlauf-fx .funke { position: absolute; width: 7px; height: 7px; border-radius: 2px;
    background: #f5b301; opacity: 0;
    animation: mm-funke 0.8s ease-out calc(var(--mm-einlauf-delay, 0s) + 0.15s) forwards; }
  @keyframes mm-funke { 0% { opacity: 0; transform: translate(0, 0) rotate(0); } 20% { opacity: 1; }
    100% { opacity: 0; transform: translate(var(--fx, 0px), var(--fy, -30px)) rotate(160deg); } }
  /* Solange der Show-Stinger läuft, pausiert das Opening ALLE Kandidaten-
     Animationen (studio.css) — die Einlauf-Partikel müssen mitwarten, sonst
     verpufft der Effekt unsichtbar UNTER dem Stinger-Overlay. */
  .stinger-aktiv .mm-einlauf-fx * { animation-play-state: paused !important; }
  @media (prefers-reduced-motion: reduce) {
    .mm-propeller, .mm-heiligenschein, .mm-partyhut-konfetti, .mm-kaugummi,
    .mm-gold-schimmer, .mm-podium-neon { animation: none; }
    .mm-einlauf-fx { display: none; }
  }
`;

/** Alle bekannten Namens-Stil-Klassen (fürs saubere Zurücksetzen). */
const NAMESTIL_KLASSEN = ["mm-name-neon", "mm-name-eis", "mm-name-gold", "mm-name-regenbogen"];

let styleEingebaut = false;
function stelleStyleSicher(): void {
  if (styleEingebaut) return;
  const style = document.createElement("style");
  style.textContent = HOLO_STYLE;
  document.head.appendChild(style);
  styleEingebaut = true;
}

function bannerVon(extras: string[]): string | null {
  for (const id of extras) {
    const item = itemFuer(id);
    if (item?.typ === "banner" && item.stil !== undefined) return item.stil;
  }
  return null;
}

function namensStilVon(extras: string[]): { klasse: string | null; farbe: string | null } {
  for (const id of extras) {
    const item = itemFuer(id);
    if (item?.typ !== "namestil") continue;
    return {
      klasse: item.klasse ?? null,
      farbe: item.klasse === undefined ? (item.stil ?? null) : null,
    };
  }
  return { klasse: null, farbe: null };
}

/** CSS-Hintergrund des ausgerüsteten Banners — null ohne Banner. */
export function bannerStilAus(avatar: string): string | null {
  return bannerVon(avatarExtras(avatar));
}

/** Namens-Stil: CSS-Klasse (Katalog-Items) ODER schlichte Farbe (Saison-Items). */
export function namensStilAus(avatar: string): { klasse: string | null; farbe: string | null } {
  return namensStilVon(avatarExtras(avatar));
}

/** Profil-Level aus dem Avatar-String (Pseudo-Extra "lv<N>") — null ohne. */
export function levelAusAvatar(avatar: string): number | null {
  return levelAusExtras(avatarExtras(avatar));
}

/**
 * Hat ein visuelles Katalog-Item hier einen Renderer? (Katalog-Integritäts-
 * Test: kein Item darf „visuell“ versprechen, ohne dass etwas zu sehen ist.)
 */
export function hatVisuellenRenderer(itemId: string): boolean {
  return (
    itemId in HUT_OVERLAYS ||
    itemId in GESICHT_OVERLAYS ||
    itemId in ROOT_OVERLAYS ||
    itemId in FELL_SWAPS ||
    itemId in FELL_MUSTER ||
    itemId in PODIUM_RAHMEN ||
    itemId in EINLAUF_EFFEKTE ||
    itemId === "avatar-hologramm"
  );
}

/**
 * Hat die Puppe einen Kopf-Anker fürs Overlay-Mapping? (Puppen-Regression:
 * neue Affen brauchen einen KOPF_ANKER-Eintrag, sonst sitzen Hüte daneben.)
 */
export function hatKopfAnker(affeId: string): boolean {
  return affeId in KOPF_ANKER;
}

/** Kachel-Rohdaten eines Fell-Musters (für Probe-Tools/Tests) — null ohne. */
export function fellMusterFuer(
  itemId: string,
): { kachel: string; breite: number; hoehe: number } | null {
  return FELL_MUSTER[itemId] ?? null;
}

/**
 * Shop-Vorschau (Welle 3): Item probeweise anlegen — ersetzt dabei das
 * angelegte Item DESSELBEN Slots (Slot-Exklusivität wie beim echten Anlegen).
 */
export function vorschauAvatar(avatar: string, itemId: string | null): string {
  if (itemId === null) return avatar;
  const item = itemFuer(itemId);
  if (!item) return avatar;
  const extras = avatarExtras(avatar).filter((id) => itemFuer(id)?.slot !== item.slot);
  extras.push(itemId);
  return avatarMitExtras(avatarBasis(avatar), extras);
}

/**
 * EIN Namens-Element schmücken: Namens-Stil (Klasse/Farbe) + kleines
 * Level-Badge („Lv 7" neben dem Namen — Profil-Karte/Lobby/Podium, §7.5).
 * Idempotent; anAus=false räumt alles wieder ab (Gast-Fairness im Match).
 */
export function schmueckeName(el: HTMLElement, avatar: string, anAus = true): void {
  stelleStyleSicher();
  const stil = anAus ? namensStilAus(avatar) : { klasse: null, farbe: null };
  for (const k of NAMESTIL_KLASSEN) el.classList.toggle(k, k === stil.klasse);
  el.style.color = stil.farbe ?? "";
  const level = anAus ? levelAusAvatar(avatar) : null;
  let badge = el.querySelector<HTMLElement>(":scope > .mm-lv-abzeichen");
  if (level === null) {
    badge?.remove();
    return;
  }
  if (!badge) {
    badge = document.createElement("span");
    badge.className = "mm-lv-abzeichen";
    el.appendChild(badge);
  }
  const text = `Lv ${level}`;
  if (badge.textContent !== text) badge.textContent = text;
}

const SVG_NS = "http://www.w3.org/2000/svg";

/** Laufende Nummer für Instanz-eindeutige Pattern-Ids (mehrere Affen pro Seite). */
let musterZaehler = 0;

/** Slot-Deko (Girlande/Einlauf) an-/abbauen — überlebt fuellePuppen-Refills. */
function stelleSlotDeko(
  slot: HTMLElement,
  klasse: string,
  an: boolean,
  html: string,
): Element | null {
  let el = slot.querySelector(`:scope > .${klasse}`);
  if (!an) {
    el?.remove();
    return null;
  }
  if (!el) {
    el = document.createElement("div");
    el.className = klasse;
    el.innerHTML = html;
    slot.appendChild(el);
  }
  return el;
}

/**
 * Alle bereits BEFÜLLTEN Puppen-Slots unter root mit den Avatar-Extras
 * schmücken (bzw. bei anAus=false wieder blank ziehen). Der Avatar-String
 * kommt aus data-avatar; ohne drittes Segment passiert nichts.
 */
export function schmueckePuppen(root: ParentNode, anAus = true): void {
  for (const slot of root.querySelectorAll<HTMLElement>("[data-avatar]")) {
    const svg = slot.querySelector("svg");
    if (!svg) continue;
    const extras = anAus ? avatarExtras(slot.dataset.avatar ?? "") : [];

    // Fell-/Spezies-Swaps + Effekt-Klassen bei JEDEM Aufruf anwenden —
    // fuellePuppen setzt --fell pro Render neu (würde den Swap zurückdrehen).
    let holo = false;
    let neon = false;
    for (const item of extras) {
      const swap = FELL_SWAPS[item];
      if (swap) {
        svg.style.setProperty("--fell", swap.fell);
        svg.style.setProperty("--fell-hell", swap.hell);
        if (item === "fell-neon") neon = true;
      }
      if (item === "avatar-hologramm") holo = true;
    }
    svg.classList.toggle("mm-holo-an", holo);
    svg.classList.toggle("mm-neon-an", neon);
    svg.classList.toggle("mm-gold-schimmer", extras.includes("fell-goldglitzer"));
    if (holo || neon) stelleStyleSicher();

    // Banner HINTER der Puppe (Podium/Lobby, §7.5) — dataset merkt sich den
    // gesetzten Wert, damit fremde Inline-Backgrounds nie überschrieben werden.
    const banner = bannerVon(extras);
    if (banner !== null) {
      stelleStyleSicher();
      if (slot.dataset.mmBanner !== banner) {
        slot.style.background = banner;
        slot.dataset.mmBanner = banner;
      }
      slot.classList.add("mm-banner-an");
    } else if (slot.dataset.mmBanner !== undefined) {
      slot.style.background = "";
      delete slot.dataset.mmBanner;
      slot.classList.remove("mm-banner-an");
    }

    // Podium-Rahmen (Welle 3): CSS-Klassen am Slot — Girlande zusätzlich als
    // Deko-Leiste ÜBER dem Slot (fuellePuppen-Refresh-fest: Existenz-Check).
    const rahmenId = extras.find((id) => PODIUM_RAHMEN[id] !== undefined) ?? null;
    for (const [id, klasse] of Object.entries(PODIUM_RAHMEN)) {
      slot.classList.toggle(klasse, id === rahmenId);
    }
    stelleSlotDeko(slot, "mm-podium-deko", rahmenId === "podium-girlande", GIRLANDE_HTML);

    // Einlauf-Effekt (Welle 3): NUR bei der Kandidaten-Vorstellung im Opening
    // (bzw. in der Shop-Vorschau via mm-einlauf-demo) — spielt einmal (forwards).
    const einlaufId = extras.find((id) => EINLAUF_EFFEKTE[id] !== undefined) ?? null;
    const einlaufAktiv =
      einlaufId !== null &&
      (slot.closest(".kandidaten-karte") !== null || slot.classList.contains("mm-einlauf-demo"));
    const fx = stelleSlotDeko(
      slot,
      "mm-einlauf-fx",
      einlaufAktiv,
      einlaufId !== null ? EINLAUF_EFFEKTE[einlaufId] : "",
    );
    if (fx instanceof HTMLElement && fx.dataset.mmItem !== einlaufId && einlaufId !== null) {
      fx.dataset.mmItem = einlaufId;
      fx.innerHTML = EINLAUF_EFFEKTE[einlaufId];
      // Beat-Sync: der Effekt zündet, wenn die eigene Kandidaten-Karte
      // einfliegt (deren animation-delay), plus kurzer Lande-Versatz.
      const karte = slot.closest<HTMLElement>(".kandidaten-karte");
      if (karte) {
        const delay = getComputedStyle(karte).animationDelay.split(",")[0]?.trim() || "0s";
        fx.style.setProperty("--mm-einlauf-delay", `calc(${delay} + 0.2s)`);
      }
    }
    if (rahmenId !== null || einlaufAktiv) {
      stelleStyleSicher();
      slot.classList.add("mm-deko-traeger");
    } else {
      slot.classList.remove("mm-deko-traeger");
    }

    // Namens-Stil + Level-Badge am zugehörigen Namens-Element (Podium-Karten
    // rendern ".podium-name" als Geschwister — Screen-Markup bleibt unberührt).
    const nameEl = slot.parentElement?.querySelector<HTMLElement>(".podium-name");
    if (nameEl) schmueckeName(nameEl, slot.dataset.avatar ?? "", anAus);

    // SVG-Overlays nur bei Signatur-Wechsel neu bauen (idempotent).
    const signatur = extras.join("+");
    if (svg.dataset.mmExtras === signatur) continue;
    svg.dataset.mmExtras = signatur;
    for (const alt of svg.querySelectorAll(".mm-meta-extra")) alt.remove();
    svg.classList.remove("mm-hut-an");
    delete svg.dataset.mmMuster;
    if (extras.length === 0) continue;

    stelleStyleSicher();
    const kopf = svg.querySelector("#kopf");
    const accessoire = svg.querySelector("#accessoire");
    const anker = kopfTransform(svg.dataset.affe);
    for (const item of extras) {
      const hutSvg = HUT_OVERLAYS[item];
      const gesichtSvg = GESICHT_OVERLAYS[item];
      const rootSvg = ROOT_OVERLAYS[item];
      if (hutSvg === undefined && gesichtSvg === undefined && rootSvg === undefined) continue;
      const g = document.createElementNS(SVG_NS, "g");
      g.setAttribute("class", "mm-meta-extra");
      g.innerHTML = hutSvg ?? gesichtSvg ?? rootSvg ?? "";
      // Kopf-Items in den Puppen-Kopfraum mappen (Kiki/Oma/Paule-Anker).
      if (rootSvg === undefined && anker !== null) g.setAttribute("transform", anker);
      if (hutSvg !== undefined && (accessoire || kopf)) {
        // Kopf-Slot: im #accessoire andocken — Standard-Hut wird ausgeblendet.
        (accessoire ?? kopf)!.appendChild(g);
        svg.classList.add("mm-hut-an");
      } else if (gesichtSvg !== undefined && kopf) {
        kopf.appendChild(g);
      } else {
        svg.appendChild(g);
      }
    }

    // Fell-MUSTER: <pattern> mit Instanz-eindeutiger Id + Stil-Override für
    // .fell/.fell-s — beides als .mm-meta-extra (Sweep räumt automatisch auf).
    const musterId = extras.find((id) => FELL_MUSTER[id] !== undefined);
    if (musterId !== undefined) {
      const muster = FELL_MUSTER[musterId];
      musterZaehler += 1;
      const uid = `mm-muster-${musterZaehler}`;
      svg.dataset.mmMuster = uid;
      const defs = document.createElementNS(SVG_NS, "defs");
      defs.setAttribute("class", "mm-meta-extra");
      defs.innerHTML = `<pattern id="${uid}" patternUnits="userSpaceOnUse" width="${muster.breite}" height="${muster.hoehe}">${muster.kachel}</pattern>`;
      svg.appendChild(defs);
      const stil = document.createElementNS(SVG_NS, "style");
      stil.setAttribute("class", "mm-meta-extra");
      // [data-affe] hebt die Spezifität ÜBER die Fell-Regeln der Puppen-Datei
      // (svg[data-affe="…"] .fell) — Chrome löst den Dokument-Reihenfolge-
      // Tiebreak bei dynamisch eingefügten SVG-Styles nicht verlässlich auf.
      stil.textContent =
        `svg[data-affe][data-mm-muster="${uid}"] .fell{fill:url(#${uid})}` +
        `svg[data-affe][data-mm-muster="${uid}"] .fell-s{stroke:url(#${uid})}`;
      svg.appendChild(stil);
    }
  }
}

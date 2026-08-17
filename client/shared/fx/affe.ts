// Affen-Puppen-Lader: die Gelenk-Puppen aus assets/img/monkeys/ INLINE einbetten
// (README: fetch → innerHTML, nie <img> — sonst kein Palette-Swap/Gesichts-Attribut).
// Nutzung: Template rendert einen Slot <div data-puppe="kiki-krawall" …>, nach
// jedem render() einmal fuellePuppen(root) aufrufen — idempotent + Cache-schnell.
import { FARBWERTE, parseAvatar } from "./avatar";

const urls = new Map<string, string>();
for (const id of [
  "don-bananas",
  "gitti-giro",
  "kiki-krawall",
  "baron-von-bananenstein",
  "oma-zinseszins",
  "pumper-paule",
  "schnarch-schorsch",
  "glitzer-gina",
  "dj-trommelfell",
  "astro-astrid",
  "kommissar-kokosnuss",
  "iro-ines",
  "abraka-dieter",
  "kahuna-kalle",
]) {
  urls.set(id, new URL(`../../../assets/img/monkeys/${id}.svg`, import.meta.url).href);
}

const cache = new Map<string, string>();
const laufend = new Set<string>();
let geladenCb: (() => void) | null = null;

/** Wird aufgerufen, sobald weitere Puppen aus dem Netz eingetroffen sind (→ neu füllen). */
export function onPuppenGeladen(cb: () => void): void {
  geladenCb = cb;
}

function lade(affeId: string): void {
  if (cache.has(affeId) || laufend.has(affeId) || !urls.has(affeId)) return;
  laufend.add(affeId);
  void fetch(urls.get(affeId)!)
    .then((r) => r.text())
    .then((text) => {
      cache.set(affeId, text);
      laufend.delete(affeId);
      geladenCb?.();
    })
    .catch(() => laufend.delete(affeId));
}

/** Alle 14 Puppen vorladen (Screen macht das beim Start — Lobby braucht alle). */
export function ladeAllePuppen(): void {
  for (const id of urls.keys()) lade(id);
}

export type Gesicht = "neutral" | "jubel" | "frust" | "denk";

/**
 * Alle [data-puppe]-Slots unterhalb von root befüllen/aktualisieren.
 * dataset: puppe = Affen-Id · farbe = AvatarFarbe (optional: Fell-Swap) ·
 * gesicht = neutral|jubel|frust|denk. Avatar-Komplett-Strings ("affe.farbe")
 * werden über data-avatar unterstützt.
 */
export function fuellePuppen(root: ParentNode): void {
  for (const slot of root.querySelectorAll<HTMLElement>("[data-puppe],[data-avatar]")) {
    let affeId = slot.dataset.puppe ?? "";
    let farbe = slot.dataset.farbe ?? "";
    if (slot.dataset.avatar) {
      const wahl = parseAvatar(slot.dataset.avatar);
      affeId = wahl.affe;
      farbe = farbe || wahl.farbe;
    }
    if (!urls.has(affeId)) continue;
    const svgText = cache.get(affeId);
    if (svgText === undefined) {
      lade(affeId);
      continue;
    }
    if (slot.dataset.befuellt !== affeId) {
      slot.innerHTML = svgText;
      slot.dataset.befuellt = affeId;
    }
    const svg = slot.querySelector("svg");
    if (!svg) continue;
    const gesicht = slot.dataset.gesicht ?? "";
    if (gesicht && gesicht !== "neutral") svg.dataset.gesicht = gesicht;
    else delete svg.dataset.gesicht;
    if (farbe && farbe in FARBWERTE) {
      const f = FARBWERTE[farbe as keyof typeof FARBWERTE];
      svg.style.setProperty("--fell", f.farbe);
      svg.style.setProperty("--fell-hell", f.hell);
    } else {
      svg.style.removeProperty("--fell");
      svg.style.removeProperty("--fell-hell");
    }
  }
}

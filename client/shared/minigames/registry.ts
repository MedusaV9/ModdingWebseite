// Minigame-Renderer-Registry: LAZY Vite-Glob-Import über alle Minigame-Ordner
// (Eval-7 P2 „Erstladung 1,4 MB": jedes Format ist ein eigener Chunk und lädt
// erst, wenn der Server es wirklich ansagt — die Player-Erstlast schrumpft um
// alle 21 Renderer). Neue Client-Renderer docken an, indem sie ./<id>/index.ts
// anlegen — Konvention: Ordnername = Minigame-Id (Wächter-Test prüft das).
import type { DemoChoreo } from "./demo-typen";
import type { MinigameClientModule } from "./types";

const importer = import.meta.glob<{ default: MinigameClientModule; demoChoreo?: DemoChoreo }>(
  "./*/index.ts",
);

const geladen = new Map<string, MinigameClientModule>();
const choreos = new Map<string, DemoChoreo>();
const angefordert = new Set<string>();
const nachladeCbs = new Set<() => void>();

function uebernimm(mod: { default: MinigameClientModule; demoChoreo?: DemoChoreo }): void {
  geladen.set(mod.default.id, mod.default);
  if (mod.demoChoreo) choreos.set(mod.default.id, mod.demoChoreo);
}

/** Nachlade-Hook: App re-rendert, sobald ein angefordertes Modul da ist. */
export function onMinigameNachgeladen(cb: () => void): void {
  nachladeCbs.add(cb);
}

/** Modul anfordern (idempotent) — Chunk lädt im Hintergrund, dann Callback. */
export function ladeMinigameModul(id: string): void {
  if (geladen.has(id) || angefordert.has(id)) return;
  const lade = importer[`./${id}/index.ts`];
  if (lade === undefined) return; // unbekannte Id (z. B. Server-only-Format)
  angefordert.add(id);
  void lade()
    .then((mod) => {
      uebernimm(mod);
      for (const cb of nachladeCbs) cb();
    })
    .catch((err) => {
      // Netz-Schluckauf: nächster getMinigameModule-Aufruf probiert es erneut.
      angefordert.delete(id);
      console.error(`Minigame-Modul ${id} lädt nicht:`, err);
    });
}

/** Renderer holen; null = (noch) nicht geladen — der Aufruf stößt das
 * Nachladen an, onMinigameNachgeladen re-rendert dann automatisch. */
export function getMinigameModule(id: string): MinigameClientModule | null {
  const mod = geladen.get(id);
  if (mod !== undefined) return mod;
  ladeMinigameModul(id);
  return null;
}

/** Erklär-Demo-Choreo eines Formats — lädt mit dem Modul-Chunk mit. */
export function getDemoChoreo(id: string): DemoChoreo | null {
  if (!geladen.has(id)) ladeMinigameModul(id);
  return choreos.get(id) ?? null;
}

/** ALLE Module laden (Tests/Abdeckungs-Wächter — nie im App-Hot-Path). */
export async function ladeAlleMinigameModule(): Promise<Map<string, MinigameClientModule>> {
  for (const [pfad, lade] of Object.entries(importer)) {
    const mod = await lade();
    uebernimm(mod);
    // Wächter der Lazy-Konvention: Ordnername MUSS der Minigame-Id entsprechen,
    // sonst findet ladeMinigameModul(id) den Chunk nicht.
    const ordner = pfad.split("/")[1];
    if (ordner !== mod.default.id) {
      throw new Error(`Minigame-Ordner „${ordner}" ≠ Modul-Id „${mod.default.id}"`);
    }
  }
  return geladen;
}

/** Alle Choreos (Tests) — vorher ladeAlleMinigameModule() aufrufen. */
export function alleGeladenenChoreos(): Map<string, DemoChoreo> {
  return choreos;
}

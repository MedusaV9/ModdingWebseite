// Choreo-Zugriff: Die `demoChoreo`-Exporte reisen seit dem Lazy-Split im
// jeweiligen Minigame-Chunk mit (Registry lädt Modul + Choreo zusammen).
// Formate ohne Choreo fallen auf der Erklärkarte automatisch auf die
// bisherige Emoji-Animation + Volltext zurück.
import type { DemoChoreo } from "../../shared/minigames/demo-typen";
import {
  alleGeladenenChoreos,
  getDemoChoreo,
  ladeAlleMinigameModule,
} from "../../shared/minigames/registry";

/** Choreo eines Formats — null = (noch) kein Demo (Fallback: Text + Emoji);
 * stößt das Nachladen an, onMinigameNachgeladen re-rendert dann. */
export function demoChoreoFuer(minigameId: string): DemoChoreo | null {
  return getDemoChoreo(minigameId);
}

/** Alle Choreos laden (Tests: Format-Abdeckung + Invarianten). */
export async function alleDemoChoreos(): Promise<Map<string, DemoChoreo>> {
  await ladeAlleMinigameModule();
  return alleGeladenenChoreos();
}

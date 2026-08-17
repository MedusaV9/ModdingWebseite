// Bananen-Pass-Store (Meta-Agent 2): PASS-XP + Stufen pro Profil, persistiert
// als EINE atomare Datei (meta/pass.json). Saison = Kalendermonat (UTC,
// shared/quests.ts) — beim ersten Schreib-/Lese-Kontakt einer NEUEN Saison
// wird der alte Stand archiviert (Anzeige „Saison-Archiv") und der Fortschritt
// beginnt bei 0: nicht erreichte Stufen verfallen, verdiente Items bleiben
// natürlich im Profil-Besitz. Mutationen strikt sequenziell (Promise-Kette).
import {
  PASS_STUFEN,
  passBelohnungen,
  passStufeFuerXp,
  saisonIdFuer,
  saisonName,
  type PassBelohnung,
} from "../../shared/quests";
import type { Clock } from "../../shared/time";
import type { Storage } from "../persistence/storage";

const DATEI = "meta/pass.json";
const MAX_ARCHIV = 24; // 2 Jahre Saison-Historie reichen fürs Archiv

export interface PassArchivEintrag {
  saisonId: string;
  name: string;
  stufe: number;
  xp: number;
  verdient: string[]; // Item-Ids, die in dieser Saison geholt wurden
}

export interface PassProfil {
  saisonId: string;
  xp: number;
  stufe: number;
  verdient: string[];
  atBonus: number; // Summe der AT-Boni dieser Saison (Anzeige)
  archiv: PassArchivEintrag[];
}

interface PassDatei {
  schemaVersion: 1;
  profile: Record<string, PassProfil>;
}

/** Ergebnis einer XP-Gutschrift: was wurde JETZT neu erreicht? */
export interface XpErgebnis {
  xpVorher: number;
  xpNeu: number;
  stufeVorher: number;
  stufeNeu: number;
  /** Neu erreichte Stufen-Belohnungen (Reihenfolge = Stufe aufsteigend). */
  belohnungen: PassBelohnung[];
}

export interface SeasonStore {
  /** PASS-XP gutschreiben — rollt die Saison, rechnet Stufen, liefert Neues. */
  gibXp(profileId: string, xp: number): Promise<XpErgebnis>;
  /** Aktueller Stand (rollover-bereinigte Sicht, ohne Schreib-Zwang). */
  stand(profileId: string): Promise<PassProfil>;
}

function leeresProfil(saisonId: string): PassProfil {
  return { saisonId, xp: 0, stufe: 0, verdient: [], atBonus: 0, archiv: [] };
}

/** Saison-Rollover: alten Stand ins Archiv, Fortschritt auf 0 (mutiert p). */
function rolleSaison(p: PassProfil, saisonId: string): void {
  if (p.saisonId === saisonId) return;
  if (p.xp > 0 || p.verdient.length > 0) {
    p.archiv = [
      ...p.archiv,
      {
        saisonId: p.saisonId,
        name: saisonName(p.saisonId),
        stufe: p.stufe,
        xp: p.xp,
        verdient: p.verdient,
      },
    ].slice(-MAX_ARCHIV);
  }
  p.saisonId = saisonId;
  p.xp = 0;
  p.stufe = 0;
  p.verdient = [];
  p.atBonus = 0;
}

export function createSeasonStore(storage: Storage, clock: Clock): SeasonStore {
  let kette: Promise<unknown> = Promise.resolve();
  function seriell<T>(op: () => Promise<T>): Promise<T> {
    const ergebnis = kette.then(op, op);
    kette = ergebnis.catch(() => undefined);
    return ergebnis;
  }

  async function lade(): Promise<PassDatei> {
    const daten = await storage.readJson<PassDatei>(DATEI);
    return daten ?? { schemaVersion: 1, profile: {} };
  }

  return {
    gibXp(profileId, xp) {
      return seriell(async () => {
        const daten = await lade();
        const saisonId = saisonIdFuer(clock.now());
        const p = (daten.profile[profileId] ??= leeresProfil(saisonId));
        rolleSaison(p, saisonId);
        const xpVorher = p.xp;
        const stufeVorher = p.stufe;
        p.xp += Math.max(0, Math.round(xp));
        p.stufe = Math.min(PASS_STUFEN, passStufeFuerXp(p.xp));
        const belohnungen = passBelohnungen(saisonId).filter(
          (b) => b.stufe > stufeVorher && b.stufe <= p.stufe,
        );
        for (const b of belohnungen) {
          if (b.art === "item" && b.itemId !== undefined) {
            if (!p.verdient.includes(b.itemId)) p.verdient = [...p.verdient, b.itemId];
          }
          if (b.art === "at") p.atBonus += b.at ?? 0;
        }
        await storage.writeJsonAtomic(DATEI, daten);
        return { xpVorher, xpNeu: p.xp, stufeVorher, stufeNeu: p.stufe, belohnungen };
      });
    },

    async stand(profileId) {
      const daten = await lade();
      const saisonId = saisonIdFuer(clock.now());
      const p = daten.profile[profileId] ?? leeresProfil(saisonId);
      const kopie: PassProfil = { ...p, verdient: [...p.verdient], archiv: [...p.archiv] };
      rolleSaison(kopie, saisonId); // Lese-Sicht rollt virtuell (Schreiben macht gibXp)
      return kopie;
    },
  };
}

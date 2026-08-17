// JUBILÄUMS-ERKENNUNG (v2, C-05): Gruppen-Meilensteine aus der Match-Historie.
// Eine „Gruppe" = dieselbe Menge gebundener Profile (≥ 2) — der Schlüssel ist
// die sortierte Profil-Id-Liste. Persistiert als meta/jubilaeen.json; der
// Lookup beim Match-START läuft SYNCHRON aus dem In-Memory-Cache (Räume dürfen
// nie auf Disk warten), Writes laufen strikt sequenziell (Ketten-Promise).
import type { JubilaeumsView } from "../../shared/views";
import type { Storage } from "../persistence/storage";

const DATEI = "meta/jubilaeen.json";

/** Gefeiert wird beim START des n-ten Abends derselben Gruppe. */
export const MATCH_MEILENSTEINE = [10, 25, 50, 100] as const;
/** „Erste 100k Gesamt-Money" — Lifetime-Summe aller Endstände der Gruppe. */
export const MONEY_MEILENSTEIN = 100_000;

export interface JubilaeumsGruppe {
  matches: number; // abgeschlossene Matches der Gruppe
  gesamtMoney: number; // Summe aller End-Kontostände (nur gebundene Profile)
  rekordEndstand: number; // ewiger Einzel-Match-Rekord …
  rekordName: string; // … und wer ihn hält
  gefeiert: string[]; // bereits gefeierte Meilenstein-Ids (nie doppelt feiern)
}

interface JubilaeenDatei {
  schemaVersion: 1;
  gruppen: Record<string, JubilaeumsGruppe>;
}

export function leereGruppe(): JubilaeumsGruppe {
  return { matches: 0, gesamtMoney: 0, rekordEndstand: 0, rekordName: "", gefeiert: [] };
}

/** Gruppen-Schlüssel: sortierte Profil-Ids (≥ 2 Profile, sonst keine Gruppe). */
export function gruppenKey(profileIds: string[]): string | null {
  const eindeutig = [...new Set(profileIds)].sort();
  return eindeutig.length >= 2 ? eindeutig.join("+") : null;
}

/**
 * PURE Erkennung: welche Meilensteine feiert das JETZT startende Match?
 * matches zählt ABGESCHLOSSENE Abende ⇒ das laufende Match ist Nr. matches+1.
 * Der 100k-Meilenstein feuert beim ersten Start NACH dem Überschreiten.
 */
export function erkenneMeilensteine(gruppe: JubilaeumsGruppe | undefined): string[] {
  const g = gruppe ?? leereGruppe();
  const matchNr = g.matches + 1;
  const meilensteine: string[] = [];
  if (
    (MATCH_MEILENSTEINE as readonly number[]).includes(matchNr) &&
    !g.gefeiert.includes(`match-${matchNr}`)
  ) {
    meilensteine.push(`match-${matchNr}`);
  }
  if (g.gesamtMoney >= MONEY_MEILENSTEIN && !g.gefeiert.includes("money-100k")) {
    meilensteine.push("money-100k");
  }
  return meilensteine;
}

/** PURE Karten-Bau: Titel + Text + Mini-Rückblick-Stats fürs Opening. */
export function baueJubilaeumsView(
  gruppe: JubilaeumsGruppe | undefined,
  meilensteine: string[],
): JubilaeumsView | null {
  if (meilensteine.length === 0) return null;
  const g = gruppe ?? leereGruppe();
  const matchNr = g.matches + 1;
  const matchM = meilensteine.find((m) => m.startsWith("match-"));
  const geld = meilensteine.includes("money-100k");
  const titel = matchM !== undefined ? `🎉 Euer ${matchNr}. Abend!` : "💰 100.000 MM geknackt!";
  const teile: string[] = [];
  if (matchM !== undefined) {
    teile.push(`Ihr spielt heute zum ${matchNr}. Mal zusammen — was für eine Truppe!`);
  }
  if (geld) {
    teile.push("Eure Gruppe hat zusammen die 100.000-MONKEY-MONEY-Marke durchbrochen!");
  }
  return {
    titel,
    text: teile.join(" "),
    matchNr,
    gesamtMoney: g.gesamtMoney,
    rekord: g.rekordEndstand > 0 ? { name: g.rekordName, endstand: g.rekordEndstand } : null,
    meilensteine,
  };
}

export interface JubilaeenStore {
  /** Cache von Disk füllen (einmalig beim Service-Start). */
  ladeInitial(): Promise<void>;
  /** SYNCHRON (Match-Start): Meilensteine erkennen + sofort als gefeiert
   * markieren (nie doppelt feiern) — null wenn keine Gruppe/kein Jubiläum. */
  fuerMatchStart(profileIds: string[]): JubilaeumsView | null;
  /** Match-Ende: Zähler/Gesamt-Money/Rekord der Gruppe fortschreiben. */
  verbucheMatch(profileIds: string[], endstaende: { name: string; balance: number }[]): void;
  /** Lese-Snapshot einer Gruppe (Tests/Diagnose). */
  gruppe(profileIds: string[]): JubilaeumsGruppe | null;
}

export function createJubilaeenStore(storage: Storage): JubilaeenStore {
  let cache: JubilaeenDatei = { schemaVersion: 1, gruppen: {} };
  // Writes strikt sequenziell + fire-and-forget: Meta darf NIE ein Match reißen.
  let kette: Promise<void> = Promise.resolve();
  const speichere = (): void => {
    const snapshot: JubilaeenDatei = {
      schemaVersion: 1,
      gruppen: Object.fromEntries(
        Object.entries(cache.gruppen).map(([k, g]) => [k, { ...g, gefeiert: [...g.gefeiert] }]),
      ),
    };
    kette = kette
      .then(() => storage.writeJsonAtomic(DATEI, snapshot))
      .catch((err) => console.error(`Jubiläen-Speicherfehler (${DATEI}):`, err));
  };

  return {
    async ladeInitial() {
      const daten = await storage.readJson<JubilaeenDatei>(DATEI);
      if (daten !== null && daten.schemaVersion === 1) cache = daten;
    },

    fuerMatchStart(profileIds) {
      const key = gruppenKey(profileIds);
      if (key === null) return null;
      const gruppe = cache.gruppen[key];
      const meilensteine = erkenneMeilensteine(gruppe);
      if (meilensteine.length === 0) return null;
      const view = baueJubilaeumsView(gruppe, meilensteine);
      // Sofort als gefeiert markieren — auch bei Abbruch nie doppelt feiern.
      const g = gruppe ?? leereGruppe();
      cache.gruppen[key] = { ...g, gefeiert: [...g.gefeiert, ...meilensteine] };
      speichere();
      return view;
    },

    verbucheMatch(profileIds, endstaende) {
      const key = gruppenKey(profileIds);
      if (key === null) return;
      const g = cache.gruppen[key] ?? leereGruppe();
      let rekordEndstand = g.rekordEndstand;
      let rekordName = g.rekordName;
      let summe = 0;
      for (const e of endstaende) {
        summe += Math.max(0, e.balance);
        if (e.balance > rekordEndstand) {
          rekordEndstand = e.balance;
          rekordName = e.name;
        }
      }
      cache.gruppen[key] = {
        ...g,
        matches: g.matches + 1,
        gesamtMoney: g.gesamtMoney + summe,
        rekordEndstand,
        rekordName,
      };
      speichere();
    },

    gruppe(profileIds) {
      const key = gruppenKey(profileIds);
      if (key === null) return null;
      const g = cache.gruppen[key];
      return g ? { ...g, gefeiert: [...g.gefeiert] } : null;
    },
  };
}

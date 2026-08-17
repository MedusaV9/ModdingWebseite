// Fragen-Moderation (Admin-Fix W20): macht die Fehlerhaft-Queue BEDIENBAR.
// Drei Aktionen pro Frage — „Quarantäne" (raus aus der Match-Rotation),
// „Entkräften" (bisherige Flags ausblenden), „Geprüft markieren" (Sichtvermerk).
// Persistiert als EINE atomare Datei (meta/moderation.json) mit In-Memory-
// Cache, damit die Rotation-Sperre SYNCHRON in pickQuestions wirken kann.
import type { Clock } from "../../shared/time";
import type { ContentLoader, PickOptions } from "../content-loader/index";
import type { Storage } from "../persistence/storage";

const DATEI = "meta/moderation.json";

export interface ModerationEintrag {
  /** true = Frage ist aus der Match-Rotation genommen (pickQuestions-Sperre). */
  quarantaene: boolean;
  /** Zeitstempel der letzten „geprüft"-Markierung — null = ungeprüft. */
  geprueftTs: number | null;
  /** Flags mit ts ≤ diesem Zeitstempel gelten als entkräftet (ausgeblendet). */
  entkraeftetBis: number | null;
}

interface ModerationDatei {
  schemaVersion: 1;
  fragen: Record<string, ModerationEintrag>;
}

function leererEintrag(): ModerationEintrag {
  return { quarantaene: false, geprueftTs: null, entkraeftetBis: null };
}

function istLeer(e: ModerationEintrag): boolean {
  return !e.quarantaene && e.geprueftTs === null && e.entkraeftetBis === null;
}

export interface ModerationStore {
  /** Cache aus der Datei füllen (einmal beim Service-Bau). */
  ladeInitial(): Promise<void>;
  /** Lese-Snapshot aller Einträge (Cache-Sicht, synchron). */
  alle(): Record<string, ModerationEintrag>;
  istGesperrt(questionId: string): boolean;
  gesperrteIds(): string[];
  setzeQuarantaene(questionId: string, an: boolean): Promise<ModerationEintrag>;
  /** Alle BISHERIGEN Flags entkräften (ts ≤ jetzt) — künftige zählen wieder. */
  entkraefte(questionId: string): Promise<ModerationEintrag>;
  setzeGeprueft(questionId: string, an: boolean): Promise<ModerationEintrag>;
}

export function createModerationStore(storage: Storage, clock: Clock): ModerationStore {
  let cache: Record<string, ModerationEintrag> = {};
  // Mutationen strikt sequenziell (gleiche Op-Ketten-Disziplin wie profile-store).
  let kette: Promise<unknown> = Promise.resolve();
  function seriell<T>(op: () => Promise<T>): Promise<T> {
    const ergebnis = kette.then(op, op);
    kette = ergebnis.catch(() => undefined);
    return ergebnis;
  }

  function aendere(
    questionId: string,
    patch: (e: ModerationEintrag) => ModerationEintrag,
  ): Promise<ModerationEintrag> {
    return seriell(async () => {
      const daten = (await storage.readJson<ModerationDatei>(DATEI)) ?? {
        schemaVersion: 1 as const,
        fragen: {},
      };
      const neu = patch(daten.fragen[questionId] ?? leererEintrag());
      if (istLeer(neu)) delete daten.fragen[questionId];
      else daten.fragen[questionId] = neu;
      await storage.writeJsonAtomic(DATEI, daten);
      cache = daten.fragen;
      return { ...neu };
    });
  }

  return {
    async ladeInitial() {
      const daten = await storage.readJson<ModerationDatei>(DATEI);
      if (daten) cache = daten.fragen;
    },
    alle() {
      return { ...cache };
    },
    istGesperrt(questionId) {
      return cache[questionId]?.quarantaene === true;
    },
    gesperrteIds() {
      return Object.entries(cache)
        .filter(([, e]) => e.quarantaene)
        .map(([qid]) => qid);
    },
    setzeQuarantaene(questionId, an) {
      return aendere(questionId, (e) => ({ ...e, quarantaene: an }));
    },
    entkraefte(questionId) {
      return aendere(questionId, (e) => ({ ...e, entkraeftetBis: clock.now() }));
    },
    setzeGeprueft(questionId, an) {
      return aendere(questionId, (e) => ({ ...e, geprueftTs: an ? clock.now() : null }));
    },
  };
}

/**
 * Quarantäne-Wirkung auf die Match-Rotation: pickQuestions des (geteilten)
 * Loaders wird IN-PLACE dekoriert — quarantänisierte Fragen wirken wie schon
 * gespielt (usedQuestionIds) und werden nie mehr gezogen. Bewusst am selben
 * Loader-Objekt, damit Räume/Engine OHNE Wiring-Änderung profitieren.
 */
export function moderierePickQuestions(loader: ContentLoader, store: ModerationStore): void {
  const original = loader.pickQuestions.bind(loader);
  loader.pickQuestions = (opts: PickOptions) => {
    const gesperrt = store.gesperrteIds();
    if (gesperrt.length === 0) return original(opts);
    return original({
      ...opts,
      usedQuestionIds: [...(opts.usedQuestionIds ?? []), ...gesperrt],
    });
  };
}

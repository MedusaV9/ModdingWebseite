// Content-Loader für den Standalone-Modus: statt content/packs/**/*.json von
// Disk (node:fs) kommt der komplette choice4-fähige Katalog als STATISCHES
// JSON-Bundle (client/dist/host-content.json, erzeugt zur Build-Zeit vom
// Vite-Plugin mmHostContentBundle in vite.config.ts — Quelle ist derselbe
// createContentLoader().alleFragen()-Pfad wie im Node-Server, also identische
// Validierung + identisches Engine-Mapping inkl. /media-URLs).
//
// Das Interface ist ContentLoader (server/content-loader/index.ts) — Räume und
// Engine merken keinen Unterschied. pickQuestions spiegelt die Filter-Semantik
// des Datei-Loaders 1:1 (No-Repeat, kategorien ober/unter, schwierigkeiten,
// region global+de, typen, deterministischer Fallback-Rng).
import type { Question } from "../../shared/content";
import { createRng, type Rng } from "../../shared/rng";
import type {
  ContentLoader,
  KatalogFrage,
  PickOptions,
  PlanFrageTyp,
} from "../content-loader/index";

/** Format von client/dist/host-content.json (Vite-Plugin schreibt es). */
export interface HostContentBundle {
  schemaVersion: number;
  /** Anzahl + Quelle nur für Diagnose/Anzeige auf der Host-Seite. */
  quelle: string;
  fragen: KatalogFrage[];
}

/** Bundle-Rohdaten prüfen (Netz/Datei ist Systemgrenze) — wirft bei Müll. */
export function parseHostContentBundle(roh: unknown): HostContentBundle {
  const bundle = roh as HostContentBundle;
  if (typeof bundle !== "object" || bundle === null || !Array.isArray(bundle.fragen)) {
    throw new Error("host-content.json: kein gültiges Bundle (fragen[] fehlt)");
  }
  if (bundle.fragen.length === 0) throw new Error("host-content.json: 0 Fragen im Bundle");
  const erste = bundle.fragen[0];
  if (typeof erste?.frage?.id !== "string" || !Array.isArray(erste?.frage?.options)) {
    throw new Error("host-content.json: Fragen-Format unbekannt (frage.id/options fehlen)");
  }
  return bundle;
}

/** Ziehung ohne Zurücklegen (partielles Fisher-Yates — wie content-loader). */
function ziehe<T>(pool: readonly T[], anzahl: number, rng: Rng): T[] {
  const arr = [...pool];
  const n = Math.min(anzahl, arr.length);
  for (let i = 0; i < n; i++) {
    const j = i + rng.int(arr.length - i);
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr.slice(0, n);
}

export function createBundleContentLoader(katalog: KatalogFrage[]): ContentLoader {
  // Deterministischer Fallback wie im Datei-Loader (OS-Zufall ist in
  // Spiellogik tabu) — echte Varianz kommt über opts.rng vom Boot-Rng.
  const fallbackRng = createRng(0xaffe);
  // Tiefe Kopie inkl. der ADDITIVEN Frage-Daten (tips/schaetz/sortier) —
  // Aufrufer mutieren nie den Katalog (Semantik wie server/content-loader).
  const kopie = (frage: Question): Question => ({
    ...frage,
    options: [...frage.options],
    ...(frage.tips ? { tips: [...frage.tips] } : {}),
    ...(frage.schaetz ? { schaetz: { ...frage.schaetz } } : {}),
    ...(frage.sortier
      ? {
          sortier: {
            korrektReihenfolge: [...frage.sortier.korrektReihenfolge],
            aufloesungWerte: [...frage.sortier.aufloesungWerte],
          },
        }
      : {}),
  });

  return {
    async loadPacks(): Promise<void> {
      // Bundle ist bereits geladen (Konstruktor-Argument) — nichts zu tun.
    },

    pickQuestions(opts: PickOptions): Question[] {
      const benutzt = new Set(opts.usedQuestionIds ?? []);
      const pool = katalog.filter((f) => {
        if (benutzt.has(f.frage.id)) return false;
        if (
          opts.kategorien &&
          !opts.kategorien.includes(f.oberkategorie) &&
          !opts.kategorien.includes(f.frage.category)
        )
          return false;
        if (opts.schwierigkeiten && !opts.schwierigkeiten.includes(f.frage.difficulty))
          return false;
        if (opts.region && f.region !== "global" && f.region !== opts.region) return false;
        if (opts.typen && !opts.typen.includes(f.planTyp as PlanFrageTyp)) return false;
        return true;
      });
      return ziehe(pool, opts.anzahl, opts.rng ?? fallbackRng).map((f) => kopie(f.frage));
    },

    alleFragen(): KatalogFrage[] {
      return katalog.map((f) => ({ ...f, frage: kopie(f.frage) }));
    },
  };
}

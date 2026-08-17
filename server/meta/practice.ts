// Übungsmodus „Trainingslager" (GAME-DESIGN §6.2): endloses Solo-Üben mit
// Sofort-Auflösung, kostenlosen Tipps und leichtem Spaced-Repetition —
// oft-falsche Fragen kommen öfter (uebungsGewicht), KEINE AT-Wertung.
// Lern-Statistik pro Übungs-Schlüssel (Profil-Id ODER Geräte-Token) als
// atomare JSON-Datei unter meta/uebung/<key>.json.
import { gewichteteWahl, uebungsGewicht, type UebungsFrageStat } from "../../shared/meta";
import type { Rng } from "../../shared/rng";
import type { Clock } from "../../shared/time";
import type { ContentLoader, KatalogFrage } from "../content-loader/index";
import type { Storage } from "../persistence/storage";

interface UebungsDatei {
  schemaVersion: 1;
  stats: Record<string, UebungsFrageStat>;
  gesamt: { richtig: number; falsch: number };
  serie: number;
  besteSerie: number;
  kategorien: Record<string, { richtig: number; falsch: number }>;
}

export interface UebungsFrageAusgabe {
  questionId: string;
  text: string;
  options: string[];
  kategorie: string;
  oberkategorie: string;
  schwierigkeit: string;
  /** Wie oft diese Frage schon falsch beantwortet wurde (Anzeige „Wiederholer"). */
  bisherFalsch: number;
  /** Wie viele echte Autoren-Tipps diese Frage hat (Knopf „Tipp ansehen 1→3"). */
  tippsGesamt: number;
}

export interface UebungsAntwortAusgabe {
  korrekt: boolean;
  antwort: number;
  erklaerung: string;
  stats: UebungsStatsAusgabe;
}

export interface UebungsStatsAusgabe {
  beantwortet: number;
  richtig: number;
  quote: number | null;
  serie: number;
  besteSerie: number;
  schwaechen: { kategorie: string; quote: number; n: number }[];
}

/** Tipp-Antwort des Trainings: echte Autoren-Tipps stufenweise (1→2→3) —
 * Fragen OHNE Tipps fallen aufs alte 50:50 zurück (entfernt = 2 falsche). */
export type UebungsTippAusgabe =
  { tipp: string; stufe: number; gesamt: number } | { entfernt: number[] } | { fehler: string };

export interface PracticeService {
  kategorien(): { slug: string; oberkategorie: string; fragen: number }[];
  naechsteFrage(
    key: string,
    filter: { kategorie?: string; schwierigkeit?: string },
  ): Promise<UebungsFrageAusgabe | { fehler: string }>;
  antwort(
    key: string,
    questionId: string,
    choice: number,
    dauerMs: number,
  ): Promise<UebungsAntwortAusgabe | { fehler: string }>;
  /** Kostenloser Tipp: echte Autoren-Tipps stufenweise; ohne Tipps 50:50. */
  tipp(key: string, questionId: string): UebungsTippAusgabe;
  stats(key: string): Promise<UebungsStatsAusgabe>;
}

function leereDatei(): UebungsDatei {
  return {
    schemaVersion: 1,
    stats: {},
    gesamt: { richtig: 0, falsch: 0 },
    serie: 0,
    besteSerie: 0,
    kategorien: {},
  };
}

function sanitizeKey(key: string): string {
  return key.replace(/[^a-zA-Z0-9_-]/g, "").slice(0, 40) || "anonym";
}

function statsAusgabe(datei: UebungsDatei): UebungsStatsAusgabe {
  const beantwortet = datei.gesamt.richtig + datei.gesamt.falsch;
  const schwaechen = Object.entries(datei.kategorien)
    .map(([kategorie, z]) => ({
      kategorie,
      quote: z.richtig / Math.max(1, z.richtig + z.falsch),
      n: z.richtig + z.falsch,
    }))
    .filter((s) => s.n >= 5)
    .sort((a, b) => a.quote - b.quote)
    .slice(0, 3);
  return {
    beantwortet,
    richtig: datei.gesamt.richtig,
    quote: beantwortet > 0 ? datei.gesamt.richtig / beantwortet : null,
    serie: datei.serie,
    besteSerie: datei.besteSerie,
    schwaechen,
  };
}

export function createPracticeService(
  storage: Storage,
  contentLoader: ContentLoader,
  rng: Rng,
  clock: Clock,
  /** Moderation-Gate (Admin-Quarantäne): gesperrte Fragen nie ausspielen. */
  istGesperrt: (questionId: string) => boolean = () => false,
): PracticeService {
  // Ausgegebene Fragen (Anti-Cheat: Lösung erst NACH der Antwort herausgeben).
  // tippStufe = wie viele echte Tipps zu DIESER Frage schon angesehen wurden.
  const offen = new Map<string, { questionId: string; ausgegebenTs: number; tippStufe: number }>();
  let katalogCache: KatalogFrage[] | null = null;
  const katalog = (): KatalogFrage[] => {
    katalogCache ??= contentLoader.alleFragen();
    return katalogCache;
  };

  const pfad = (key: string): string => `meta/uebung/${sanitizeKey(key)}.json`;

  async function lade(key: string): Promise<UebungsDatei> {
    return (await storage.readJson<UebungsDatei>(pfad(key))) ?? leereDatei();
  }

  return {
    kategorien() {
      const zaehler = new Map<string, { oberkategorie: string; fragen: number }>();
      for (const k of katalog()) {
        const z = zaehler.get(k.frage.category) ?? { oberkategorie: k.oberkategorie, fragen: 0 };
        z.fragen += 1;
        zaehler.set(k.frage.category, z);
      }
      return [...zaehler.entries()]
        .map(([slug, z]) => ({ slug, ...z }))
        .sort((a, b) => b.fragen - a.fragen);
    },

    async naechsteFrage(key, filter) {
      const datei = await lade(key);
      const letzteId = offen.get(sanitizeKey(key))?.questionId;
      const kandidaten = katalog().filter((k) => {
        if (k.frage.id === letzteId) return false; // nie dieselbe direkt nochmal
        if (istGesperrt(k.frage.id)) return false; // Admin-Quarantäne
        if (k.frage.media !== undefined) return false; // Bild-Fragen brauchen die Pixel-Bühne
        // Slider-/Sortier-Fragen brauchen ihre Bühnen (Tresor/Leiter) — das
        // Training ist eine reine Options-Klick-UI (choice4 + wahr_falsch).
        if (k.frage.kind === "schaetz" || k.frage.kind === "sortier") return false;
        if (
          filter.kategorie &&
          k.frage.category !== filter.kategorie &&
          k.oberkategorie !== filter.kategorie
        ) {
          return false;
        }
        if (filter.schwierigkeit && k.frage.difficulty !== filter.schwierigkeit) return false;
        return true;
      });
      if (kandidaten.length === 0) return { fehler: "keine-fragen" };
      // Spaced-Repetition: Gewicht aus der Lern-Statistik (falsch ⇒ öfter).
      const wahl = gewichteteWahl(
        kandidaten.map((k) => ({ wert: k, gewicht: uebungsGewicht(datei.stats[k.frage.id]) })),
        rng.next(),
      );
      if (wahl === null) return { fehler: "keine-fragen" };
      offen.set(sanitizeKey(key), {
        questionId: wahl.frage.id,
        ausgegebenTs: clock.now(),
        tippStufe: 0,
      });
      return {
        questionId: wahl.frage.id,
        text: wahl.frage.text,
        options: [...wahl.frage.options],
        kategorie: wahl.frage.category,
        oberkategorie: wahl.oberkategorie,
        schwierigkeit: wahl.frage.difficulty,
        bisherFalsch: datei.stats[wahl.frage.id]?.falsch ?? 0,
        tippsGesamt: wahl.frage.tips?.length ?? 0,
      };
    },

    async antwort(key, questionId, choice, dauerMs) {
      const eintrag = offen.get(sanitizeKey(key));
      if (!eintrag || eintrag.questionId !== questionId) return { fehler: "frage-nicht-offen" };
      const k = katalog().find((x) => x.frage.id === questionId);
      if (!k) return { fehler: "frage-unbekannt" };
      offen.delete(sanitizeKey(key));

      const korrekt = choice === k.frage.answer;
      const datei = await lade(key);
      const stat = datei.stats[questionId] ?? { richtig: 0, falsch: 0, serie: 0, zuletztTs: null };
      datei.stats[questionId] = {
        richtig: stat.richtig + (korrekt ? 1 : 0),
        falsch: stat.falsch + (korrekt ? 0 : 1),
        serie: korrekt ? stat.serie + 1 : 0,
        zuletztTs: clock.now(),
      };
      datei.gesamt = {
        richtig: datei.gesamt.richtig + (korrekt ? 1 : 0),
        falsch: datei.gesamt.falsch + (korrekt ? 0 : 1),
      };
      datei.serie = korrekt ? datei.serie + 1 : 0;
      datei.besteSerie = Math.max(datei.besteSerie, datei.serie);
      const kat = datei.kategorien[k.frage.category] ?? { richtig: 0, falsch: 0 };
      datei.kategorien[k.frage.category] = {
        richtig: kat.richtig + (korrekt ? 1 : 0),
        falsch: kat.falsch + (korrekt ? 0 : 1),
      };
      await storage.writeJsonAtomic(pfad(key), datei);
      void dauerMs; // v1: Zeit fließt (noch) nicht in die Übungs-Statistik ein
      return {
        korrekt,
        antwort: k.frage.answer,
        erklaerung: k.frage.erklaerung ?? "",
        stats: statsAusgabe(datei),
      };
    },

    tipp(key, questionId) {
      const eintrag = offen.get(sanitizeKey(key));
      if (!eintrag || eintrag.questionId !== questionId) return { fehler: "frage-nicht-offen" };
      const k = katalog().find((x) => x.frage.id === questionId);
      if (!k) return { fehler: "frage-unbekannt" };
      // Echte Autoren-Tipps stufenweise (Eval 5 „Training zeigt nur 50:50"):
      // jeder Aufruf enthüllt den NÄCHSTEN Tipp (1→2→3, kostenlos).
      const tips = k.frage.tips ?? [];
      if (eintrag.tippStufe < tips.length) {
        eintrag.tippStufe += 1;
        return { tipp: tips[eintrag.tippStufe - 1], stufe: eintrag.tippStufe, gesamt: tips.length };
      }
      if (tips.length > 0) return { fehler: "alle-tipps-gesehen" };
      const falsche = k.frage.options.map((_, i) => i).filter((i) => i !== k.frage.answer);
      if (falsche.length < 2) return { fehler: "keine-tipps" };
      // Fallback ohne Autoren-Tipps: zwei falsche Optionen ausblenden (50:50).
      const erste = falsche.splice(rng.int(falsche.length), 1)[0];
      const zweite = falsche.splice(rng.int(falsche.length), 1)[0];
      return { entfernt: [erste, zweite].sort((a, b) => a - b) };
    },

    async stats(key) {
      return statsAusgabe(await lade(key));
    },
  };
}

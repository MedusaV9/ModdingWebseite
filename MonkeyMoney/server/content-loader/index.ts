// Content-Loader — KAPSELUNG des Fragen-Zugriffs. Das Interface bleibt stabil
// (Engine/Rooms kennen nur dieses); alle Erweiterungen sind ADDITIV.
//
// v1 (Content-Agent):
//   - loadPacks(): liest ALLE Packs unter content/packs/**/*.json und prüft
//     leichtgewichtig (Pflichtfelder, Enums, choice4-Konsistenz). Die harte
//     inhaltliche Prüfung (14 Regeln aus docs/CONTENT-PLAN.md §2.5) läuft in
//     `node tools/content/validate.mjs` — CI/Autoren-Gate, nicht Boot-Gate.
//   - pickQuestions(): No-Repeat via usedQuestionIds, injizierbarer Rng,
//     additive Filter (kategorien/schwierigkeiten/region/typen — alle optional,
//     die Engine ruft heute pickQuestions({ anzahl })).
//
// pickQuestions liefert heute die Plan-Typen:
//   choice/emoji/bild_pixel → kind "choice4" (Emojis wandern in den Fragetext,
//     Medien-Datei wird zur /media-URL — nur Pixel-Dschungel zieht Bild-Fragen)
//   wahr_falsch → kind "wahr_falsch" (options ["Wahr","Falsch"], 2 XXL-Buttons)
//   schaetz → kind "schaetz" (Slider-Daten in question.schaetz — Bananen-Tresor)
//   sortier → kind "sortier" (Elemente in options, Lösung in question.sortier —
//     Affenleiter; aufloesungWerte werden auf ELEMENT-Indizes normalisiert)
// Format-Zuordnung: server/engine/plan.ts passtFrageZuFormat.
// Noch nicht ausspielbar (v-next, bewusst engine=null): `audio` (0 Fragen im
// Bestand, braucht Audio-Bühne) und `mehrfach` (71 Fragen, 6 Optionen/„wähle
// 2" — braucht eine eigene Mehrfach-Auswahl-UI + Scoring in vier-lianen).
// Doku: docs/ARCHITEKTUR.md §„Andocken 2" + docs/CONTENT-PLAN.md.
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { Question } from "../../shared/content";
import type { Schwierigkeit } from "../../shared/money";
import { createRng, type Rng } from "../../shared/rng";
import { SongSchema, istBettEintrag, type Song } from "../../shared/songs";

/** Plan-Schwierigkeiten (CONTENT-PLAN §2.3) → Engine-Schwierigkeiten (shared/money). */
const SCHWIERIGKEIT_NACH_ENGINE: Record<string, Schwierigkeit> = {
  leicht: "easy",
  mittel: "medium",
  schwer: "hard",
  ultrahard: "ultrahard",
};

/** Die 8 Plan-Fragetypen (CONTENT-PLAN §2.2). */
const PLAN_TYPEN = [
  "choice",
  "wahr_falsch",
  "schaetz",
  "sortier",
  "bild_pixel",
  "audio",
  "emoji",
  "mehrfach",
] as const;
export type PlanFrageTyp = (typeof PLAN_TYPEN)[number];

export interface PickOptions {
  anzahl: number;
  /** Bereits gespielte Fragen (No-Repeat). */
  usedQuestionIds?: string[];
  rng?: Rng;
  /** ADDITIV: Ober- ODER Unter-Kategorie-Slugs (taxonomie.json); leer = alle. */
  kategorien?: string[];
  /** ADDITIV: Engine-Schwierigkeiten (easy|medium|hard|ultrahard); leer = alle. */
  schwierigkeiten?: Schwierigkeit[];
  /** ADDITIV: Region-Regler — `"de"` liefert global+de, `"global"` nur global. */
  region?: string;
  /** ADDITIV: Plan-Typen (ausspielbar: choice, emoji, bild_pixel, wahr_falsch,
   * schaetz, sortier); leer = alle ausspielbaren. */
  typen?: PlanFrageTyp[];
}

/** ADDITIV (Meta-Agent): Katalog-Zeile für Analytics/Übungsmodus. */
export interface KatalogFrage {
  frage: Question;
  oberkategorie: string;
  planTyp: string;
  region: string;
}

/** ADDITIV (Musik-Agent): Filter für die Song-Auswahl (docs/MUSIK-PACKS.md). */
export interface PickSongsOptions {
  anzahl: number;
  /** Bereits gespielte Songs (No-Repeat). */
  usedSongIds?: string[];
  rng?: Rng;
  /** Engine-Schwierigkeiten (Song-Pack „leicht…" ⇒ easy… wie beim Fragen-Loader). */
  schwierigkeiten?: Schwierigkeit[];
  /** Region-Regler wie bei Fragen — `"de"` liefert global+de, `"global"` nur global. */
  region?: string;
  /** true ⇒ nur Songs MIT stummem 3-s-Videoclip (medien.video3s). */
  mitVideo?: boolean;
}

export interface ContentLoader {
  /** Packs von Disk laden + leichtgewichtig validieren (wirft bei kaputten Packs). */
  loadPacks(): Promise<void>;
  /** Fragen für ein Match auswählen (Filter s. PickOptions; Rng-Ziehung ohne Zurücklegen). */
  pickQuestions(opts: PickOptions): Question[];
  /** ADDITIV: kompletter ausspielbarer Katalog (Analytics-Metadaten + Übungsmodus). */
  alleFragen(): KatalogFrage[];
  // ---------- ADDITIV (Musik-Agent) — optional, damit Test-Fakes gültig bleiben ----------
  /** Song-Pack laden (content/musik/songs.json) — FEHLENDE Datei ist ok (0 Songs,
   * die Song-Formate melden sich dann nicht-verfügbar); kaputte Einträge werfen. */
  loadSongs?(): Promise<void>;
  /** Songs für ein Match ziehen (Rng ohne Zurücklegen; Filter s. PickSongsOptions).
   * medien-Referenzen bleiben Pipeline-Pfade („media/<id>/…") — die Plugins
   * normalisieren beim init() über shared/songs.ts#songMediaUrl. */
  pickSongs?(opts: PickSongsOptions): Song[];
}

/** Roh-Frage im Pack-Format (Ausschnitt; volle Struktur: content/schema/frage.schema.json). */
interface PackFrage {
  id: string;
  kategorie: string;
  unterkategorie: string;
  schwierigkeit: string;
  typ: string;
  region: string;
  text: string;
  antworten?: string[];
  korrekt?: number;
  emojis?: string;
  erklaerung: string;
  medien?: { datei?: string };
  tipps?: string[];
  // wahr_falsch
  korrekt_bool?: boolean;
  // schaetz
  schaetz?: {
    richtwert?: number;
    einheit?: string;
    toleranz_prozent?: number;
    toleranz_absolut?: number;
    eingabe_min?: number;
    eingabe_max?: number;
    skala?: string;
  };
  // sortier
  elemente?: string[];
  korrekt_reihenfolge?: number[];
  aufloesung_werte?: string[];
}

interface GeladeneFrage {
  roh: PackFrage;
  /** Abbildung auf das Engine-Format — null = Typ (noch) nicht choice4-fähig. */
  engine: Question | null;
}

/** content/packs relativ zu cwd ODER zum Modul finden (dev, vitest, esbuild-Bundle). */
function findePacksVerzeichnis(): string {
  const kandidaten = [
    resolve(process.cwd(), "content/packs"),
    resolve(fileURLToPath(new URL(".", import.meta.url)), "../../content/packs"),
  ];
  for (const pfad of kandidaten) {
    if (existsSync(pfad)) return pfad;
  }
  throw new Error(`content/packs nicht gefunden (gesucht: ${kandidaten.join(", ")})`);
}

function istStringArray(wert: unknown): wert is string[] {
  return Array.isArray(wert) && wert.every((e) => typeof e === "string" && e.length > 0);
}

/** Eine Frage leichtgewichtig prüfen; Fehlertexte in `fehler` sammeln. */
function pruefeFrage(frage: PackFrage, datei: string, fehler: string[]): boolean {
  const wo = `${datei} → ${frage.id ?? "<ohne id>"}`;
  let ok = true;
  const meckere = (was: string): void => {
    fehler.push(`${wo}: ${was}`);
    ok = false;
  };
  if (typeof frage.id !== "string" || frage.id.length === 0) meckere("id fehlt");
  if (!(PLAN_TYPEN as readonly string[]).includes(frage.typ))
    meckere(`unbekannter typ ${frage.typ}`);
  if (!(frage.schwierigkeit in SCHWIERIGKEIT_NACH_ENGINE))
    meckere(`unbekannte schwierigkeit ${frage.schwierigkeit}`);
  if (typeof frage.text !== "string" || frage.text.length === 0) meckere("text fehlt");
  if (typeof frage.erklaerung !== "string" || frage.erklaerung.length === 0)
    meckere("erklaerung fehlt (Pflichtfeld — Warum-Karte)");
  if (typeof frage.region !== "string" || frage.region.length === 0) meckere("region fehlt");
  if (typeof frage.kategorie !== "string" || typeof frage.unterkategorie !== "string")
    meckere("kategorie/unterkategorie fehlt");
  if (frage.typ === "choice" || frage.typ === "emoji" || frage.typ === "bild_pixel") {
    if (!istStringArray(frage.antworten) || frage.antworten.length !== 4)
      meckere("choice/emoji/bild_pixel braucht genau 4 nicht-leere antworten");
    if (
      !Number.isInteger(frage.korrekt) ||
      (frage.korrekt as number) < 0 ||
      (frage.korrekt as number) > 3
    )
      meckere("korrekt muss Integer 0–3 sein");
  }
  if (frage.typ === "emoji" && (typeof frage.emojis !== "string" || frage.emojis.length === 0))
    meckere("emoji-Frage braucht emojis");
  if (
    frage.typ === "bild_pixel" &&
    (typeof frage.medien?.datei !== "string" || frage.medien.datei.length === 0)
  )
    meckere("bild_pixel braucht medien.datei (Pflicht laut Schema)");
  if (frage.typ === "wahr_falsch" && typeof frage.korrekt_bool !== "boolean")
    meckere("wahr_falsch braucht korrekt_bool");
  if (frage.typ === "schaetz") {
    const s = frage.schaetz;
    if (
      !s ||
      typeof s.richtwert !== "number" ||
      typeof s.einheit !== "string" ||
      s.einheit.length === 0 ||
      typeof s.toleranz_prozent !== "number" ||
      typeof s.eingabe_min !== "number" ||
      typeof s.eingabe_max !== "number" ||
      !(s.eingabe_min < s.richtwert && s.richtwert < s.eingabe_max) ||
      (s.skala !== "linear" && s.skala !== "log") ||
      (s.toleranz_absolut !== undefined &&
        (typeof s.toleranz_absolut !== "number" || s.toleranz_absolut <= 0))
    ) {
      meckere("schaetz braucht richtwert/einheit/toleranz/eingabe_min<richtwert<eingabe_max/skala");
    }
  }
  if (frage.typ === "sortier") {
    const r = frage.korrekt_reihenfolge;
    const gueltigePermutation =
      Array.isArray(r) && r.length === 4 && [0, 1, 2, 3].every((i) => r.includes(i));
    if (
      !istStringArray(frage.elemente) ||
      frage.elemente.length !== 4 ||
      !gueltigePermutation ||
      !istStringArray(frage.aufloesung_werte) ||
      frage.aufloesung_werte.length !== 4
    ) {
      meckere(
        "sortier braucht 4 elemente + korrekt_reihenfolge (Permutation) + 4 aufloesung_werte",
      );
    }
  }
  return ok;
}

/**
 * Medien-Pfad aus dem Pack (repo-relativ, z. B. assets/img/generated/pixel/x.png)
 * → Auslieferungs-URL des Servers (Express-Static /media → repo-assets/).
 */
export function medienUrl(datei: string): string {
  return `/media/${datei.replace(/^assets\//, "")}`;
}

/** Plan-Frage → Engine-Question. null = Typ (noch) nicht ausspielbar
 * (audio: keine Audio-Bühne; mehrfach: „wähle 2" ist v-next, s. Kopf-Doku). */
function nachEngine(frage: PackFrage): Question | null {
  const basisFelder = {
    id: frage.id,
    category: frage.unterkategorie,
    difficulty: SCHWIERIGKEIT_NACH_ENGINE[frage.schwierigkeit],
    erklaerung: frage.erklaerung,
    ...(istStringArray(frage.tipps) && frage.tipps.length > 0 ? { tips: [...frage.tipps] } : {}),
  };
  if (frage.typ === "choice" || frage.typ === "emoji" || frage.typ === "bild_pixel") {
    const text = frage.typ === "emoji" ? `${frage.text}\n\n${frage.emojis}` : frage.text;
    const basis: Question = {
      ...basisFelder,
      kind: "choice4",
      text,
      options: frage.antworten as string[],
      answer: frage.korrekt as number,
    };
    if (frage.typ === "bild_pixel" && frage.medien?.datei) {
      return { ...basis, media: { bild: medienUrl(frage.medien.datei) } };
    }
    return basis;
  }
  if (frage.typ === "wahr_falsch") {
    return {
      ...basisFelder,
      kind: "wahr_falsch",
      text: frage.text,
      options: ["Wahr", "Falsch"],
      answer: frage.korrekt_bool === true ? 0 : 1,
    };
  }
  if (frage.typ === "schaetz") {
    const s = frage.schaetz as NonNullable<PackFrage["schaetz"]>; // pruefeFrage garantiert Felder
    return {
      ...basisFelder,
      kind: "schaetz",
      text: frage.text,
      options: [],
      answer: 0,
      schaetz: {
        richtwert: s.richtwert as number,
        einheit: s.einheit as string,
        toleranzProzent: s.toleranz_prozent as number,
        ...(typeof s.toleranz_absolut === "number" ? { toleranzAbsolut: s.toleranz_absolut } : {}),
        eingabeMin: s.eingabe_min as number,
        eingabeMax: s.eingabe_max as number,
        skala: s.skala as "linear" | "log",
      },
    };
  }
  if (frage.typ === "sortier") {
    const reihenfolge = frage.korrekt_reihenfolge as number[];
    // Pack-Konvention: aufloesung_werte[i] = Wert des Elements auf POSITION i.
    // Engine-Konvention (affenleiter.meta): aufloesungWerte[e] = Wert von ELEMENT e.
    const werteProElement = ["", "", "", ""];
    reihenfolge.forEach((elementIdx, position) => {
      werteProElement[elementIdx] = (frage.aufloesung_werte as string[])[position];
    });
    return {
      ...basisFelder,
      kind: "sortier",
      text: frage.text,
      options: [...(frage.elemente as string[])],
      answer: 0,
      sortier: { korrektReihenfolge: [...reihenfolge], aufloesungWerte: werteProElement },
    };
  }
  return null; // audio + mehrfach: v-next (s. Kopf-Doku)
}

/** Alle Packs synchron laden (Boot/Lazy) — wirft mit Datei+Frage-Id bei Defekten. */
function ladeAllePacks(): GeladeneFrage[] {
  const verzeichnis = findePacksVerzeichnis();
  const dateien = readdirSync(verzeichnis, { recursive: true })
    .map(String)
    .filter((pfad) => pfad.endsWith(".json"))
    .sort();
  const fehler: string[] = [];
  const geladen: GeladeneFrage[] = [];
  const gesehen = new Set<string>();
  for (const relativ of dateien) {
    const voll = join(verzeichnis, relativ);
    let inhalt: unknown;
    try {
      inhalt = JSON.parse(readFileSync(voll, "utf8"));
    } catch (e) {
      fehler.push(`${relativ}: kein gültiges JSON (${(e as Error).message})`);
      continue;
    }
    const fragen = (inhalt as { fragen?: unknown }).fragen;
    if (!Array.isArray(fragen)) {
      fehler.push(`${relativ}: Pack ohne fragen[]`);
      continue;
    }
    for (const roh of fragen as PackFrage[]) {
      if (!pruefeFrage(roh, relativ, fehler)) continue;
      if (gesehen.has(roh.id)) {
        fehler.push(`${relativ} → ${roh.id}: doppelte Frage-Id über alle Packs`);
        continue;
      }
      gesehen.add(roh.id);
      geladen.push({ roh, engine: nachEngine(roh) });
    }
  }
  if (fehler.length > 0)
    throw new Error(`Content-Packs ungültig (${fehler.length} Fehler):\n${fehler.join("\n")}`);
  if (geladen.length === 0) throw new Error("Keine Fragen in content/packs gefunden");
  return geladen;
}

/** Tiefe Fragen-Kopie: Aufrufer (Engine, Übungsmodus) mutieren nie den Katalog. */
function frageKopie(frage: Question): Question {
  return {
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
  };
}

/** Ziehung ohne Zurücklegen (partielles Fisher-Yates). */
function ziehe<T>(pool: readonly T[], anzahl: number, rng: Rng): T[] {
  const arr = [...pool];
  const n = Math.min(anzahl, arr.length);
  for (let i = 0; i < n; i++) {
    const j = i + rng.int(arr.length - i);
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr.slice(0, n);
}

/** content/musik/songs.json finden — fehlende Datei ist OK (Songs sind optionaler
 * Content: ohne sie filtert die Registry die Song-Formate aus der Playlist). */
function findeSongsJson(): string | null {
  const kandidaten = [
    resolve(process.cwd(), "content/musik/songs.json"),
    resolve(fileURLToPath(new URL(".", import.meta.url)), "../../content/musik/songs.json"),
  ];
  for (const pfad of kandidaten) {
    if (existsSync(pfad)) return pfad;
  }
  return null;
}

/** Song-Pack laden + hart validieren (Zod aus shared/songs.ts — DIE eine Quelle
 * des Wire-Formats). Wirft mit Song-Id bei Defekten: lieber beim Boot scheitern
 * als kaputte Medien-Pfade in ein laufendes Match geben. Volle inhaltliche
 * Prüfung (Datei-Existenz, ffprobe-Dauern): node tools/musik/validate-songs.mjs. */
function ladeSongPack(): Song[] {
  const pfad = findeSongsJson();
  if (pfad === null) return [];
  let inhalt: unknown;
  try {
    inhalt = JSON.parse(readFileSync(pfad, "utf8"));
  } catch (e) {
    throw new Error(`${pfad}: kein gültiges JSON (${(e as Error).message})`);
  }
  const roh = (inhalt as { songs?: unknown }).songs;
  if (!Array.isArray(roh)) throw new Error(`${pfad}: Song-Pack ohne songs[]`);
  const fehler: string[] = [];
  const songs: Song[] = [];
  const gesehen = new Set<string>();
  roh.forEach((eintrag, i) => {
    // Bett-Loops (import.mjs --bett): NUR Show-Bett, nie Rate-Song — sie
    // haben keine Snippets und gehören nicht in den Song-Pool (die Rotation
    // holt sie über /api/musik/betten, shared/songs.ts#parseBettTracks).
    if (istBettEintrag(eintrag)) return;
    const parsed = SongSchema.safeParse(eintrag);
    const wo = (eintrag as { id?: string }).id ?? `#${i}`;
    if (!parsed.success) {
      fehler.push(
        `${wo}: ${parsed.error.issues.map((f) => `${f.path.join(".")} ${f.message}`).join("; ")}`,
      );
      return;
    }
    if (gesehen.has(parsed.data.id)) {
      fehler.push(`${wo}: doppelte Song-Id`);
      return;
    }
    gesehen.add(parsed.data.id);
    songs.push(parsed.data);
  });
  if (fehler.length > 0)
    throw new Error(`Song-Pack ungültig (${fehler.length} Fehler):\n${fehler.join("\n")}`);
  return songs;
}

/** Factory: lädt Packs beim ersten Zugriff (loadPacks ODER pickQuestions) genau einmal. */
export function createContentLoader(): ContentLoader {
  let fragen: GeladeneFrage[] | null = null;
  let songs: Song[] | null = null;
  // Deterministischer Fallback (OS-Zufall ist in Spiellogik tabu, TECH-SPEC LP3);
  // der Zustand wandert über Aufrufe weiter. Echte Varianz: opts.rng injizieren.
  const fallbackRng = createRng(0xaffe);
  const sichergestellt = (): GeladeneFrage[] => {
    fragen ??= ladeAllePacks();
    return fragen;
  };
  const songsSichergestellt = (): Song[] => {
    songs ??= ladeSongPack();
    return songs;
  };
  return {
    async loadPacks(): Promise<void> {
      sichergestellt();
    },
    pickQuestions(opts: PickOptions): Question[] {
      const benutzt = new Set(opts.usedQuestionIds ?? []);
      const pool = sichergestellt().filter((f) => {
        if (f.engine === null) return false; // audio/mehrfach: v-next (s. Kopf-Doku)
        if (benutzt.has(f.roh.id)) return false;
        if (
          opts.kategorien &&
          !opts.kategorien.includes(f.roh.kategorie) &&
          !opts.kategorien.includes(f.roh.unterkategorie)
        )
          return false;
        if (opts.schwierigkeiten && !opts.schwierigkeiten.includes(f.engine.difficulty))
          return false;
        if (opts.region && f.roh.region !== "global" && f.roh.region !== opts.region) return false;
        if (opts.typen && !opts.typen.includes(f.roh.typ as PlanFrageTyp)) return false;
        return true;
      });
      const auswahl = ziehe(pool, opts.anzahl, opts.rng ?? fallbackRng);
      // Kopien: Aufrufer dürfen options mischen, ohne den Katalog zu mutieren.
      return auswahl.map((f) => frageKopie(f.engine as Question));
    },

    alleFragen(): KatalogFrage[] {
      return sichergestellt()
        .filter((f) => f.engine !== null)
        .map((f) => ({
          frage: frageKopie(f.engine as Question),
          oberkategorie: f.roh.kategorie,
          planTyp: f.roh.typ,
          region: f.roh.region,
        }));
    },

    async loadSongs(): Promise<void> {
      songsSichergestellt();
    },

    pickSongs(opts: PickSongsOptions): Song[] {
      const benutzt = new Set(opts.usedSongIds ?? []);
      const pool = songsSichergestellt().filter((s) => {
        // nurBett-Tracks (die 6 MacLeod-Show-Betten) sind NIE Rate-Songs —
        // sie fehlen damit auch im Telegramm-Begriffs-Topf und in jedem
        // anderen songsPool-Abnehmer (docs/MUSIK-PACKS.md „Bett vs. Rate-Pool").
        if (s.nurBett === true) return false;
        if (benutzt.has(s.id)) return false;
        if (opts.schwierigkeiten && !opts.schwierigkeiten.includes(s.schwierigkeit)) return false;
        if (opts.region && s.region !== "global" && s.region !== opts.region) return false;
        if (opts.mitVideo && s.medien.video3s === undefined) return false;
        return true;
      });
      const auswahl = ziehe(pool, opts.anzahl, opts.rng ?? fallbackRng);
      // Tiefe Medien-Kopie: Plugins normalisieren URLs, ohne den Katalog zu mutieren.
      return auswahl.map((s) => ({
        ...s,
        medien: { ...s.medien, buzz: { ...s.medien.buzz } },
      }));
    },
  };
}

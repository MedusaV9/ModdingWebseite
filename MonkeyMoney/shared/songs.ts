// Song-Pack-Typen für die Musik-Minispiele (Blitz-DJ, Rückwärts-Banane) —
// VERBINDLICHES Wire-Format des Song-Pack-Systems (Pipeline-Agent):
// content/musik/songs.json trägt Einträge { id, titel, artist, jahr, region,
// schwierigkeit, medien: { intro5s, buzz: {ms100…ms1000}, mitte10s,
// rueckwaerts5s, video3s? } }, die Dateien liegen unter
// content/musik/media/<id>/. SCHNITTSTELLEN-ANNAHMEN an den Loader:
//   1. medien.*-Werte dürfen Pipeline-Referenzen („media/<id>/…", relativ zu
//      content/musik/) ODER fertige URLs sein — songMediaUrl normalisiert
//      beim init(); content/musik/media/* muss dafür als /media-musik/*
//      ausgeliefert werden (analog assets/* ⇒ /media/*, server/core/http.ts).
//   2. Der Loader liefert einen songs-Slice „analog Fragen": songs[0] ist der
//      Song DIESER Frage (No-Repeat verwaltet der Loader), der Rest ist der
//      Distraktoren-Pool desselben Packs.
//   3. Slice-Transport: ContentSlice.songs ODER Ctx.songs (beides ADDITIV,
//      beides optional) — die Plugins prüfen erst den Slice, dann ctx, dann
//      fällt der Fixture-Katalog ein (Match darf NIE crashen).
// Ohne geladene songs.json melden sich die Song-Formate als NICHT verfügbar
// (server/minigames/registry.ts#allePluginsFuer) — die Playlist fällt dann
// über plan.aufloesen() aufs Frage-Format zurück (Mechanismus existiert).
import { z } from "zod";
import type { Rng } from "./rng";
import type { Schwierigkeit } from "./money";

/** Pack-Schwierigkeiten: die Pipeline schreibt PLAN-Stufen (leicht/mittel/
 * schwer/ultrahard, tools/musik/import.mjs) — hier normalisiert auf die
 * Engine-Stufen (wie Plan ⇒ easy/medium/hard/ultrahard beim Fragen-Loader). */
const SchwierigkeitSchema = z
  .enum(["easy", "medium", "hard", "ultrahard", "leicht", "mittel", "schwer"])
  .transform((s): Schwierigkeit => {
    if (s === "leicht") return "easy";
    if (s === "mittel") return "medium";
    if (s === "schwer") return "hard";
    return s;
  });

export const SongSchema = z.object({
  id: z.string().min(1),
  titel: z.string().min(1),
  artist: z.string().min(1),
  jahr: z.number().int(),
  /** Region-Regler wie bei Fragen: "de" | "global" | … */
  region: z.string().min(1),
  schwierigkeit: SchwierigkeitSchema,
  /** true = der Track läuft NUR als Show-Bett (client MUSIK-Ebenen) und wird
   * NIE zum Rate-Song (pickSongs filtert ihn aus dem kompletten Match-Pool).
   * Eval 3: QuirkyDog lief als Bett, WÄHREND QuirkyDog rückwärts zu raten
   * war. Das Import-Tool setzt das Flag nie — User-Songs sind nie Betten. */
  nurBett: z.boolean().optional(),
  medien: z.object({
    intro5s: z.string().min(1),
    buzz: z.object({
      ms100: z.string().min(1),
      ms200: z.string().min(1),
      ms300: z.string().min(1),
      ms500: z.string().min(1),
      ms1000: z.string().min(1),
    }),
    mitte10s: z.string().min(1),
    rueckwaerts5s: z.string().min(1),
    video3s: z.string().min(1).optional(),
  }),
});

export type Song = z.output<typeof SongSchema>;

/** Minimal-Basis eines Song-Pack-Eintrags — ContentSlice.songs ist bewusst
 * WEIT typisiert, damit alle Musik-Formate ihre eigene Sicht über dasselbe
 * Feld transportieren können (z. B. MvSong des Stummfilm-Studios braucht nur
 * video3s). Strikte Formate validieren an der Grenze mit parseSongs. */
export interface SongBasis {
  id: string;
  titel: string;
  artist: string;
}

/** Slice-Einträge strikt validieren (Zod) — Ungültiges wird verworfen statt
 * zu crashen; leeres Ergebnis ⇒ die Plugins fallen auf FIXTURE_SONGS zurück. */
export function parseSongs(eintraege: readonly unknown[] | undefined): Song[] {
  if (eintraege === undefined) return [];
  const songs: Song[] = [];
  for (const e of eintraege) {
    const parsed = SongSchema.safeParse(e);
    if (parsed.success) songs.push(parsed.data);
  }
  return songs;
}

/**
 * Medien-Referenz ⇒ Client-abspielbare URL. Die Pipeline schreibt
 * songs.json-Pfade RELATIV zu content/musik/ („media/<id>/intro5s.ogg") —
 * SCHNITTSTELLEN-ANNAHME an den Loader/HTTP: content/musik/media/* wird als
 * /media-musik/* ausgeliefert (analog assets/* ⇒ /media/*). Bett-Loops
 * („bett/<id>.ogg", import.mjs --bett) kommen als /media-musik-bett/*.
 * Repo-Pfade auf assets/… laufen über den bestehenden /media-Mount; fertige
 * URLs (führender Slash oder http…) passieren unverändert.
 */
export function songMediaUrl(referenz: string): string {
  if (referenz.startsWith("media/")) return `/media-musik/${referenz.slice("media/".length)}`;
  if (referenz.startsWith("bett/")) return `/media-musik-bett/${referenz.slice("bett/".length)}`;
  if (referenz.startsWith("assets/")) return `/media/${referenz.slice("assets/".length)}`;
  return referenz;
}

// ---------- Bett-Loops (ADDITIV, Musik-Welle 3): Party-Hintergrund-Betten ----------
// import.mjs --bett schreibt Katalog-Einträge OHNE Rate-Snippets: nurBett:true
// + medien.bett („bett/<id>.ogg") + stimmung. Diese Einträge sind KEINE Songs
// im Sinne des Rate-Pools (SongSchema) — der Content-Loader überspringt sie
// (istBettEintrag), die Show-Regie zieht sie über GET /api/musik/betten in
// die Musik-Rotation (chillig=Lobby-Bett, upbeat=Runden-Bett).

export const BettEintragSchema = z.object({
  id: z.string().min(1),
  titel: z.string().min(1),
  artist: z.string().min(1),
  nurBett: z.literal(true),
  stimmung: z.enum(["chillig", "upbeat"]).default("chillig"),
  medien: z.object({ bett: z.string().min(1) }),
});

/** Ein Bett-Loop, wie ihn die Client-Rotation braucht (url = abspielbar). */
export interface BettTrack {
  id: string;
  titel: string;
  artist: string;
  stimmung: "chillig" | "upbeat";
  url: string;
}

/** Bett-only-Eintrag erkennen (medien.bett OHNE Snippets) — der Loader
 * überspringt solche Einträge VOR der strengen SongSchema-Validierung. */
export function istBettEintrag(eintrag: unknown): boolean {
  const e = eintrag as { nurBett?: unknown; medien?: { bett?: unknown; intro5s?: unknown } };
  return (
    e?.nurBett === true && typeof e?.medien?.bett === "string" && e?.medien?.intro5s === undefined
  );
}

/** songs.json-Einträge ⇒ Bett-Tracks der Rotation (Ungültiges wird verworfen —
 * ein kaputter Bett-Eintrag darf die Show-Musik nie crashen). */
export function parseBettTracks(eintraege: readonly unknown[] | undefined): BettTrack[] {
  if (eintraege === undefined) return [];
  const tracks: BettTrack[] = [];
  for (const e of eintraege) {
    if (!istBettEintrag(e)) continue;
    const parsed = BettEintragSchema.safeParse(e);
    if (!parsed.success) continue;
    const b = parsed.data;
    tracks.push({
      id: b.id,
      titel: b.titel,
      artist: b.artist,
      stimmung: b.stimmung,
      url: songMediaUrl(b.medien.bett),
    });
  }
  return tracks;
}

/** Alle medien-Referenzen eines Songs auf Client-URLs normalisieren. */
export function normalisiereMedien(song: Song): Song {
  const m = song.medien;
  return {
    ...song,
    medien: {
      intro5s: songMediaUrl(m.intro5s),
      buzz: {
        ms100: songMediaUrl(m.buzz.ms100),
        ms200: songMediaUrl(m.buzz.ms200),
        ms300: songMediaUrl(m.buzz.ms300),
        ms500: songMediaUrl(m.buzz.ms500),
        ms1000: songMediaUrl(m.buzz.ms1000),
      },
      mitte10s: songMediaUrl(m.mitte10s),
      rueckwaerts5s: songMediaUrl(m.rueckwaerts5s),
      ...(m.video3s !== undefined ? { video3s: songMediaUrl(m.video3s) } : {}),
    },
  };
}

/** Der Song-Ausschnitt, den ein Musik-Minigame beim init() bekommt (analog
 * ContentSlice): songs[0] = Ziel-Song, Rest = Distraktoren-Pool. Bewusst
 * SongBasis-weit (siehe oben) — strikte Formate validieren mit parseSongs. */
export interface SongsSlice {
  songs: SongBasis[];
}

// ---------- Fixture-Katalog (Fallback + Tests + Bot-Beweise) ----------
// 5 FIKTIVE Songs — Audio aus Kenney-Music-Jingles (CC0 1.0) geschnitten via
// tools/audio/mach-musik-fixtures.mjs nach assets/audio/fixtures/musik/<id>/;
// /media/* liefert repo-assets/ aus, die URLs funktionieren also SOFORT.
function fixture(
  id: string,
  titel: string,
  artist: string,
  jahr: number,
  region: string,
  schwierigkeit: Schwierigkeit,
): Song {
  const basis = `/media/audio/fixtures/musik/${id}`;
  return {
    id,
    titel,
    artist,
    jahr,
    region,
    schwierigkeit,
    medien: {
      intro5s: `${basis}/intro5s.ogg`,
      buzz: {
        ms100: `${basis}/buzz_ms100.ogg`,
        ms200: `${basis}/buzz_ms200.ogg`,
        ms300: `${basis}/buzz_ms300.ogg`,
        ms500: `${basis}/buzz_ms500.ogg`,
        ms1000: `${basis}/buzz_ms1000.ogg`,
      },
      mitte10s: `${basis}/mitte10s.ogg`,
      rueckwaerts5s: `${basis}/rueckwaerts5s.ogg`,
    },
  };
}

/** Eingebaute Test-Songs — Reihenfolge ist Teil des Determinismus-Vertrags. */
export const FIXTURE_SONGS: readonly Song[] = [
  fixture("fx-sax-banane", "Banane in Samt", "Saxo Simia", 1988, "global", "medium"),
  fixture("fx-pizzi-kokos", "Kokosnuss-Polka", "Die Pizzikaten", 1975, "de", "hard"),
  fixture("fx-steel-liane", "Liane im Wind", "Steel-Dschungel-Band", 2003, "global", "easy"),
  fixture("fx-nes-affe", "Pixel-Affe", "8-Bit-Bande", 1990, "global", "hard"),
  fixture("fx-hit-dschungel", "Dschungel-Beben", "MC Gorilla", 2015, "de", "ultrahard"),
];

/** Anzeige-String einer MC-Option: „Titel — Artist" (Task-Vorgabe Titel+Artist). */
export function songOption(song: Pick<Song, "titel" | "artist">): string {
  return `${song.titel} — ${song.artist}`;
}

/** Songs MIT 3-s-Videoclip zählen — Playlist-Gate des Stummfilm-Studios
 * (registry.allePluginsFuer: meta.minVideoSongs, room.startMatch liefert). */
export function zaehleVideoSongs(songs: readonly Song[]): number {
  return songs.filter((s) => (s.medien.video3s ?? "").length > 0).length;
}

/** NICHT-SPRECHENDE Frage-Id eines Songs (djb2-Hex): Song-Ids der Pipeline
 * dürfen sprechend sein („nena-99-luftballons") und wären in questionId ein
 * Leak in Player-Views — die Views tragen deshalb nur diesen Hash. */
export function songFrageId(songId: string): string {
  let h = 5381;
  for (let i = 0; i < songId.length; i++) h = (Math.imul(h, 33) ^ songId.charCodeAt(i)) >>> 0;
  return `song~${h.toString(16)}`;
}

export interface SongAuswahl {
  ziel: Song;
  /** 4 Anzeige-Strings (Ziel + 3 artgleiche Distraktoren), rng-gemischt. */
  optionen: string[];
  correctIndex: number;
}

/**
 * Ziel-Song + 4 MC-Optionen bestimmen (deterministisch über den injizierten
 * Rng). Slice-Vertrag: songs[0] = Ziel, Rest = Distraktoren-Pool. Fallback
 * ohne Slice: Fixture-Katalog, Ziel per Rng (No-Repeat übernimmt dann
 * niemand — der Katalog ist nur das Sicherheitsnetz). „Artgleich": gleiche
 * schwierigkeit bevorzugt, dann Rest des Packs, dann Fixtures auffüllen.
 */
export function waehleSongUndOptionen(songs: Song[] | undefined, rng: Rng): SongAuswahl {
  const pack = songs !== undefined && songs.length > 0 ? songs : undefined;
  const roh = pack ? pack[0] : FIXTURE_SONGS[rng.int(FIXTURE_SONGS.length)];
  // Medien-Referenzen (Pipeline: relativ zu content/musik/) ⇒ Client-URLs.
  const ziel = normalisiereMedien(roh);
  const rest = (pack ? pack.slice(1) : [...FIXTURE_SONGS]).filter(
    (s) => s.id !== ziel.id && s.titel !== ziel.titel,
  );

  // Distraktoren: artgleich (gleiche Schwierigkeit) zuerst, dann der Rest,
  // dann Fixture-Auffüllung — Dubletten über den Anzeige-Text ausgeschlossen.
  const artgleich = rest.filter((s) => s.schwierigkeit === ziel.schwierigkeit);
  const andere = rest.filter((s) => s.schwierigkeit !== ziel.schwierigkeit);
  const auffuellung = FIXTURE_SONGS.filter((s) => s.id !== ziel.id && s.titel !== ziel.titel);
  const gesehen = new Set([songOption(ziel)]);
  const distraktoren: string[] = [];
  for (const kandidat of [...mische(artgleich, rng), ...mische(andere, rng), ...auffuellung]) {
    if (distraktoren.length >= 3) break;
    const text = songOption(kandidat);
    if (gesehen.has(text)) continue;
    gesehen.add(text);
    distraktoren.push(text);
  }
  // Not-Ausstieg (Pack + Fixtures decken < 4 ab — praktisch unmöglich):
  // generische Füller, damit IMMER 4 Optionen stehen (Match darf nie crashen).
  let fueller = 1;
  while (distraktoren.length < 3) distraktoren.push(`Unbekannter Track ${fueller++} — ???`);

  const optionen = mische([songOption(ziel), ...distraktoren], rng);
  return { ziel, optionen, correctIndex: optionen.indexOf(songOption(ziel)) };
}

/** Fisher-Yates über den injizierten Rng (Kopie — nie in-place am Input). */
function mische<T>(liste: readonly T[], rng: Rng): T[] {
  const kopie = [...liste];
  for (let i = kopie.length - 1; i > 0; i--) {
    const j = rng.int(i + 1);
    [kopie[i], kopie[j]] = [kopie[j], kopie[i]];
  }
  return kopie;
}

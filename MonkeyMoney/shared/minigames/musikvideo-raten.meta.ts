// „Stummfilm-Studio" (musikvideo-raten, Musik-Welle): 3 s STUMMER
// Musikvideo-Clip läuft auf dem Screen — alle raten gleichzeitig aus 4
// Optionen (Titel + Artist). Wer im Stumm-Durchlauf nicht antwortet, bekommt
// einen 2. Durchlauf MIT Ton-Schnipsel (ms500) als RETTUNGSSTUFE für den
// HALBEN Wert. Die Auflösung zeigt den Clip MIT intro5s-Ton.
//
// SONG-PACK-FORMAT: das KANONISCHE Wire-Format aus shared/songs.ts
// (content/musik/songs.json, Pipeline-Agent) — dieses Format liest davon nur
// seine WEITE Sicht (MvSong): id/titel/artist + medien.video3s (Kern-Medium),
// medien.buzz.ms500 (Rettungsstufe; toleriert auch flaches medien.ms500
// älterer Pack-Entwürfe) und medien.intro5s (Auflösungs-Ton).
// · Pfade: Pipeline-Referenzen („media/<id>/…"), repo-relativ („assets/…")
//   oder fertige URLs — mvMediaUrl delegiert an songMediaUrl (shared/songs.ts).
// · medien.video3s ist OPTIONAL — Songs ohne video3s kann dieses Format
//   nicht inszenieren (sie taugen aber als Options-Köder).
// · Datei-Namen bitte mit NICHT-sprechenden Song-Ids (kein Titel-Slug in der
//   URL — sonst verrät der Netzwerk-Tab die Antwort).
// VERFÜGBARKEIT: contentKind "songs" ⇒ ohne geladene songs.json filtert die
// Registry das Format weg (allePluginsFuer); sind Songs da, aber KEINER mit
// video3s, greift mvVerfuegbar(songs) bzw. die init()-Wache im Plugin
// (sofort beendete 0-Punkte-Runde statt Crash).
import type { Rng } from "../rng";
import { songMediaUrl } from "../songs";

export const MUSIKVIDEO_RATEN_ID = "musikvideo-raten";

export const MUSIKVIDEO_RATEN_META = {
  id: MUSIKVIDEO_RATEN_ID,
  name: "Stummfilm-Studio",
  minPlayers: 2,
  maxPlayers: 8,
  formats: ["buttons"] as const,
  // Song-Pack-Format: ohne geladene songs.json nicht verfügbar (Registry).
  contentKind: "songs" as const,
  // Playlist-Gate (registry.allePluginsFuer): erst ab 3 Songs MIT video3s
  // meldet sich das Format verfügbar — mit dem 1-Video-Starter-Pack bleibt
  // es draußen (plan.aufloesen fällt aufs Frage-Format zurück). 3 statt 4:
  // die Options-Köder füllt MV_FALLBACK_OPTIONEN notfalls auf.
  minVideoSongs: 3,
  needsScreen: true,
  // Zwei-Stufen-Wertung (voll/halb) ist eigene Mathe — keine Streak-Kette.
  streak: false,
  // EIN init() pro Runde: die Song-Auswahl braucht alle Beats auf einmal
  // (kein Song doppelt, Köder-Optionen aus dem ganzen Pack).
  roundBased: true,
};

/** Spieler-Aktion: MC-4 über den generischen answer/choice-Draht — in BEIDEN
 * Durchläufen (stumm = voller Wert, ton = halber Wert). Erste Antwort zählt. */
export type MusikvideoRatenAction = { type: "answer"; choice: 0 | 1 | 2 | 3 };

// ---------- Song-Pack-Typen (strukturgleich zu songs.json) ----------

export interface MvSongMedien {
  /** 5-s-Intro MIT Ton — läuft in der Auflösung unter dem Clip. */
  intro5s?: string;
  /** KANONISCH (shared/songs.ts): buzz.ms500 = 500-ms-Schnipsel. */
  buzz?: { ms500?: string };
  /** Flaches ms500 älterer Pack-Entwürfe — toleriert (mvTonReferenz). */
  ms500?: string;
  /** 3-s-Videoclip (stumm abgespielt) — OPTIONAL, unser Kern-Medium. */
  video3s?: string;
}

export interface MvSong {
  id: string;
  titel: string;
  artist: string;
  medien?: MvSongMedien;
}

/** Rettungsstufen-Ton: kanonisch buzz.ms500, toleriert flaches ms500. */
export function mvTonReferenz(song: MvSong): string | null {
  return song.medien?.buzz?.ms500 ?? song.medien?.ms500 ?? null;
}

// ---------- Timing (Beat = stumm → ton? → aufdeckung) ----------

export const MV_STUMM_MS = 12_000; // 3-s-Clip läuft 4× im Loop
export const MV_TON_MS = 8_000; // Rettungsstufe mit dem 500-ms-Schnipsel
export const MV_AUFDECKUNG_MS = 7_000; // 5 s intro5s-Ton + 2 s Feiern

/** Rettungsstufen-Wert: W/2 — bei 100/250/500/1000 → 50/125/250/500. */
export function mvRettungsWert(frageWert: number): number {
  return Math.round(frageWert / 2);
}

// ---------- Media-URL + Verfügbarkeit (pure Helfer) ----------

/** Medien-Referenz → Client-URL — delegiert an die KANONISCHE Übersetzung
 * (shared/songs.ts): „media/…" ⇒ /media-musik/…, „assets/…" ⇒ /media/…,
 * fertige URLs passieren unverändert. */
export function mvMediaUrl(pfad: string): string {
  return songMediaUrl(pfad);
}

/** Kann dieses Format den Song inszenieren? (Kern-Medium video3s vorhanden.) */
export function mvSpielbar(song: MvSong): boolean {
  return typeof song.medien?.video3s === "string" && song.medien.video3s.length > 0;
}

/** Format-Verfügbarkeit: ohne einen einzigen video3s-Song nicht spielbar. */
export function mvVerfuegbar(songs: readonly MvSong[] | undefined): boolean {
  return (songs ?? []).some(mvSpielbar);
}

// ---------- Fixture-Katalog (Tests + Bot-Beweise — NICHT der Live-Fallback:
// ohne echte video3s-Songs meldet sich das Format nicht-verfügbar) ----------
// 3 FIKTIVE Video-Songs; die 3-s-Platzhalter-Clips (testsrc/Farbflächen) und
// die ms500/intro5s-Audios liegen unter assets/{video,audio}/fixtures/musik/
// (ffmpeg-generiert — echte Clips kommen vom Pipeline-Agent).
function mvFixture(id: string, titel: string, artist: string): MvSong {
  return {
    id,
    titel,
    artist,
    medien: {
      video3s: `assets/video/fixtures/musik/${id}/video3s.mp4`,
      buzz: { ms500: `assets/audio/fixtures/musik/${id}/buzz_ms500.mp3` },
      intro5s: `assets/audio/fixtures/musik/${id}/intro5s.mp3`,
    },
  };
}

/** Eingebaute Test-Video-Songs — Reihenfolge ist Teil des Determinismus. */
export const MV_FIXTURE_SONGS: readonly MvSong[] = [
  mvFixture("fx-video-neon", "Neon-Nächte", "Synthesia"),
  mvFixture("fx-video-gitter", "Gitternetz-Groove", "Vector Vera"),
  mvFixture("fx-video-welle", "Wellenreiter-Walzer", "Amplitude Andi"),
];

// ---------- Options-Bau (Titel + Artist, Köder aus dem Pack) ----------

/** Anzeige-Text einer Option: „Titel — Artist". */
export function mvOptionText(song: Pick<MvSong, "titel" | "artist">): string {
  return `${song.titel} — ${song.artist}`;
}

/** Fiktive Köder-Songs, falls das Pack < 4 Songs hat (Fixture-/Notbetrieb).
 * Bewusst erfunden — sie kollidieren nie mit echten Pack-Titeln. */
export const MV_FALLBACK_OPTIONEN: readonly string[] = [
  "Neonherz — Die Palmen-Piloten",
  "Mitternachtsbanane — Kluntje & die Kokosbande",
  "Regen über Rio — Marla Monsun",
  "Dschungeltelefon — DJ Liane",
  "Goldstaub-Boulevard — Die Kapuziner",
  "Samtpfoten-Samba — Orchidee Deluxe",
];

/**
 * 4 Optionen für einen Beat bauen: der richtige Song + 3 Köder aus den
 * ÜBRIGEN Pack-Songs (deterministisch gemischt, Rng injiziert); reicht das
 * Pack nicht, füllen die Fallback-Köder auf. Rückgabe: Options-Texte +
 * Index der richtigen Antwort.
 */
export function mvBaueOptionen(
  songs: readonly MvSong[],
  korrekt: MvSong,
  rng: Rng,
): { optionen: string[]; answer: number } {
  const koeder = songs
    .filter((s) => s.id !== korrekt.id && mvOptionText(s) !== mvOptionText(korrekt))
    .map(mvOptionText);
  // Deterministisch mischen (Fisher-Yates mit injiziertem Rng).
  for (let i = koeder.length - 1; i > 0; i--) {
    const j = rng.int(i + 1);
    [koeder[i], koeder[j]] = [koeder[j], koeder[i]];
  }
  const fallback = MV_FALLBACK_OPTIONEN.filter((t) => t !== mvOptionText(korrekt));
  // Dubletten über den Anzeige-Text ausschließen (Pack-Titel könnten mit
  // Fallback-Ködern oder untereinander kollidieren) — dann erst kappen.
  const gewaehlt = [...new Set([...koeder, ...fallback])].slice(0, 3);
  const answer = rng.int(4);
  const optionen = [...gewaehlt.slice(0, answer), mvOptionText(korrekt), ...gewaehlt.slice(answer)];
  return { optionen: optionen.slice(0, 4), answer };
}

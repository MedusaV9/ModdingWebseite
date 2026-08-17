// „Wer singt's?" (wer-singts, Musik-Welle): Musik-WISSENS-Quiz ohne Audio und
// ohne Liedtexte — der Screen zeigt einen weltbekannten Song-TITEL auf einer
// Schallplatten-Karte plus Jahr-Hinweis, gefragt ist der INTERPRET aus 4
// Optionen. ALLE antworten gleichzeitig (generischer answer/choice-Draht),
// richtig zahlt WS_WERT[schwierigkeit] + Speed-Bonus (shared/money.ts).
// DISTRAKTOREN sind artgleich: bevorzugt Interpreten aus DERSELBEN Ära
// (±WS_AERA_JAHRE) und DEMSELBEN Genre — echtes Raten statt Ausschlussprinzip.
// POOL: eingebauter Fakten-Pool mit 60+ Einträgen (deutsche + internationale
// Klassiker quer durch die Jahrzehnte; NUR eindeutige, faktensichere
// Titel-Interpret-Paare — berühmte Cover-Fälle wie „Hallelujah" sind bewusst
// draußen; Schwierigkeit über Bekanntheit gestaffelt). Der
// POOL-INTEGRITÄTS-WÄCHTER (wsPoolFehler) prüft Eindeutigkeit, Jahr-Plausi
// und Options-Baubarkeit — Wächter-Test in server/minigames/wer-singts.test.ts.
// BONUS: Song-Pack-Einträge (meta.wuenschtSongs, Muster Telegramm) fließen als
// Zusatz-Fragen ein — bis zur Hälfte der Beats, valide + gegen den Pool
// dedupliziert (wsFaktenAusSongs).
import type { Rng } from "../rng";
import type { Schwierigkeit } from "../money";

export const WER_SINGTS_ID = "wer-singts";

export const WER_SINGTS_META = {
  id: WER_SINGTS_ID,
  name: "Wer singt's?",
  minPlayers: 2,
  maxPlayers: 8,
  formats: ["buttons"] as const,
  // Fakten kommen aus dem eingebauten Pool + Song-Pack — nicht aus dem
  // Fragen-Pool (die Engine-Fragen zählen nur die Beats, Muster Telegramm).
  contentKind: "none" as const,
  // Song-Titel als Zusatz-Fragen: flow.starteFrage hängt den Song-Pool
  // READ-ONLY an (KEIN usedSongIds-Verbrauch — nur Titel/Artist/Jahr).
  wuenschtSongs: true,
  needsScreen: true,
  // Eigene Wert-Tabelle + Speed-Bonus, aber kein ±W-Standard — keine Streak.
  streak: false,
  // EIN init() pro Runde: die Beat-Auswahl braucht alle Fragen auf einmal
  // (kein Titel doppelt, Schwierigkeits-Staffelung über die Runde).
  roundBased: true,
};

/** Spieler-Aktion: MC-4 über den generischen answer/choice-Draht. */
export type WerSingtsAction = { type: "answer"; choice: 0 | 1 | 2 | 3 };

// ---------- Timing (Beat = auflegen → raten → aufdeckung) ----------

export const WS_AUFLEGEN_MS = 2_500; // die Platte senkt sich: Titel + Jahr
export const WS_RATEN_MS = 12_000; // alle raten gleichzeitig (timerFaktor wirkt)
export const WS_AUFDECKUNG_MS = 6_000; // die Platte dreht sich zum Interpreten

// ---------- Wertung (Bekanntheits-Staffel + Speed-Bonus) ----------

/** Grundwert je Bekanntheits-Stufe (Speed-Bonus obendrauf: shared/money.ts,
 * max. +50 % bei Antwort in den ersten 20 % der Zeit). */
export const WS_WERT: Record<Schwierigkeit, number> = {
  easy: 100,
  medium: 150,
  hard: 250,
  ultrahard: 400,
};

/** Ära-Fenster der Distraktoren-Wahl: gleiche Ära = ±10 Jahre. */
export const WS_AERA_JAHRE = 10;

// ---------- Fakten-Pool (eingebaut, 60+ eindeutige Titel-Interpret-Paare) ----------

export type WsGenre =
  | "pop"
  | "rock"
  | "oldie"
  | "disco"
  | "hiphop"
  | "country"
  | "reggae"
  | "schlager"
  | "ndw"
  | "deutschrock"
  | "deutschpop"
  | "song-pack";

export interface WsFakt {
  titel: string;
  artist: string;
  /** Erscheinungsjahr (Jahr-Hinweis auf der Platte) — null nur bei
   * Song-Pack-Einträgen ohne Jahresangabe. */
  jahr: number | null;
  genre: WsGenre;
  /** Schwierigkeit = Bekanntheit (easy = jeder kennt's … ultrahard = Kenner). */
  schwierigkeit: Schwierigkeit;
  region: "de" | "global";
}

function w(
  titel: string,
  artist: string,
  jahr: number,
  genre: WsGenre,
  schwierigkeit: Schwierigkeit,
  region: "de" | "global",
): WsFakt {
  return { titel, artist, jahr, genre, schwierigkeit, region };
}

/**
 * Der eingebaute Pool: 84 faktensichere Klassiker (Stand der Kuratierung —
 * der Wächter-Test hält die 60+-Untergrenze und die Eindeutigkeit).
 * Kurations-Regeln: nur DIE berühmte Original-Zuordnung (keine Cover-Fallen),
 * Jahr = Erstveröffentlichung des Hits, Schwierigkeit nach Bekanntheit beim
 * Partyvolk — nicht nach musikalischem Anspruch.
 */
export const WS_FAKTEN_POOL: readonly WsFakt[] = [
  // ---- International: Oldies & Rock'n'Roll (50er/60er) ----
  w("Jailhouse Rock", "Elvis Presley", 1957, "oldie", "medium", "global"),
  w("Great Balls of Fire", "Jerry Lee Lewis", 1957, "oldie", "hard", "global"),
  w("Johnny B. Goode", "Chuck Berry", 1958, "oldie", "hard", "global"),
  w("What a Wonderful World", "Louis Armstrong", 1967, "oldie", "medium", "global"),
  w("Ring of Fire", "Johnny Cash", 1963, "country", "hard", "global"),
  w("Hey Jude", "The Beatles", 1968, "rock", "easy", "global"),
  w("Let It Be", "The Beatles", 1970, "rock", "easy", "global"),
  w("(I Can't Get No) Satisfaction", "The Rolling Stones", 1965, "rock", "medium", "global"),
  // ---- International: 70er ----
  w("Imagine", "John Lennon", 1971, "pop", "medium", "global"),
  w("Jolene", "Dolly Parton", 1973, "country", "hard", "global"),
  w("No Woman, No Cry", "Bob Marley", 1974, "reggae", "medium", "global"),
  w("Bohemian Rhapsody", "Queen", 1975, "rock", "easy", "global"),
  w("Dancing Queen", "ABBA", 1976, "disco", "easy", "global"),
  w("Waterloo", "ABBA", 1974, "disco", "medium", "global"),
  w("Daddy Cool", "Boney M.", 1976, "disco", "medium", "global"),
  w("Hotel California", "Eagles", 1977, "rock", "medium", "global"),
  w("Stayin' Alive", "Bee Gees", 1977, "disco", "medium", "global"),
  w("Y.M.C.A.", "Village People", 1978, "disco", "easy", "global"),
  w("Sultans of Swing", "Dire Straits", 1978, "rock", "hard", "global"),
  w("Hot Stuff", "Donna Summer", 1979, "disco", "medium", "global"),
  w("Highway to Hell", "AC/DC", 1979, "rock", "medium", "global"),
  // ---- International: 80er ----
  w("In the Air Tonight", "Phil Collins", 1981, "pop", "medium", "global"),
  w("Thriller", "Michael Jackson", 1982, "pop", "easy", "global"),
  w("Billie Jean", "Michael Jackson", 1983, "pop", "easy", "global"),
  w("Africa", "Toto", 1982, "rock", "medium", "global"),
  w("Eye of the Tiger", "Survivor", 1982, "rock", "medium", "global"),
  w("Every Breath You Take", "The Police", 1983, "rock", "medium", "global"),
  w("Karma Chameleon", "Culture Club", 1983, "pop", "hard", "global"),
  w("Girls Just Want to Have Fun", "Cyndi Lauper", 1983, "pop", "hard", "global"),
  w("Purple Rain", "Prince", 1984, "pop", "medium", "global"),
  w("Take On Me", "a-ha", 1985, "pop", "medium", "global"),
  w("The Final Countdown", "Europe", 1986, "rock", "medium", "global"),
  w("Livin' on a Prayer", "Bon Jovi", 1986, "rock", "medium", "global"),
  w("Sweet Child O' Mine", "Guns N' Roses", 1987, "rock", "medium", "global"),
  w("Like a Prayer", "Madonna", 1989, "pop", "medium", "global"),
  // ---- International: 90er ----
  w("Wind of Change", "Scorpions", 1991, "rock", "easy", "de"),
  w("Smells Like Teen Spirit", "Nirvana", 1991, "rock", "easy", "global"),
  w("Nothing Else Matters", "Metallica", 1991, "rock", "medium", "global"),
  w("Losing My Religion", "R.E.M.", 1991, "rock", "hard", "global"),
  w("Zombie", "The Cranberries", 1994, "rock", "hard", "global"),
  w("Wonderwall", "Oasis", 1995, "rock", "medium", "global"),
  w("My Heart Will Go On", "Céline Dion", 1997, "pop", "easy", "global"),
  w("Baby One More Time", "Britney Spears", 1998, "pop", "easy", "global"),
  w("Believe", "Cher", 1998, "pop", "medium", "global"),
  // ---- International: 2000er ----
  w("Lose Yourself", "Eminem", 2002, "hiphop", "medium", "global"),
  w("In da Club", "50 Cent", 2003, "hiphop", "medium", "global"),
  w("Seven Nation Army", "The White Stripes", 2003, "rock", "medium", "global"),
  w("Hips Don't Lie", "Shakira", 2006, "pop", "medium", "global"),
  w("Umbrella", "Rihanna", 2007, "pop", "medium", "global"),
  w("Viva la Vida", "Coldplay", 2008, "rock", "medium", "global"),
  w("Poker Face", "Lady Gaga", 2008, "pop", "easy", "global"),
  w("Halo", "Beyoncé", 2008, "pop", "medium", "global"),
  w("I Gotta Feeling", "The Black Eyed Peas", 2009, "pop", "medium", "global"),
  // ---- International: 2010er ----
  w("Rolling in the Deep", "Adele", 2010, "pop", "easy", "global"),
  w("Firework", "Katy Perry", 2010, "pop", "medium", "global"),
  w("Gangnam Style", "Psy", 2012, "pop", "easy", "global"),
  w("Royals", "Lorde", 2013, "pop", "hard", "global"),
  w("Wrecking Ball", "Miley Cyrus", 2013, "pop", "medium", "global"),
  w("Happy", "Pharrell Williams", 2013, "pop", "easy", "global"),
  w("Chandelier", "Sia", 2014, "pop", "hard", "global"),
  w("Shape of You", "Ed Sheeran", 2017, "pop", "easy", "global"),
  w("Despacito", "Luis Fonsi", 2017, "pop", "medium", "global"),
  w("Blinding Lights", "The Weeknd", 2019, "pop", "medium", "global"),
  w("Bad Guy", "Billie Eilish", 2019, "pop", "medium", "global"),
  // ---- Deutsch: Schlager & Oldies ----
  w("Marmor, Stein und Eisen bricht", "Drafi Deutscher", 1965, "schlager", "medium", "de"),
  w("Schöne Maid", "Tony Marshall", 1971, "schlager", "ultrahard", "de"),
  w("Griechischer Wein", "Udo Jürgens", 1974, "schlager", "medium", "de"),
  w("Er gehört zu mir", "Marianne Rosenberg", 1975, "schlager", "hard", "de"),
  w("Ein Bett im Kornfeld", "Jürgen Drews", 1976, "schlager", "medium", "de"),
  w("Moskau", "Dschinghis Khan", 1979, "schlager", "medium", "de"),
  w("Ein bisschen Frieden", "Nicole", 1982, "schlager", "medium", "de"),
  w("Wahnsinn", "Wolfgang Petry", 1983, "schlager", "medium", "de"),
  w("Verdammt, ich lieb' dich", "Matthias Reim", 1990, "schlager", "medium", "de"),
  w("Anton aus Tirol", "DJ Ötzi", 1999, "schlager", "medium", "de"),
  w("Atemlos durch die Nacht", "Helene Fischer", 2013, "schlager", "easy", "de"),
  // ---- Deutsch: NDW ----
  w("Skandal im Sperrbezirk", "Spider Murphy Gang", 1981, "ndw", "medium", "de"),
  w("Da Da Da", "Trio", 1982, "ndw", "medium", "de"),
  w("Ich will Spaß", "Markus", 1982, "ndw", "hard", "de"),
  w("Major Tom (völlig losgelöst)", "Peter Schilling", 1982, "ndw", "medium", "de"),
  w("Sternenhimmel", "Hubert Kah", 1982, "ndw", "hard", "de"),
  w("99 Luftballons", "Nena", 1983, "ndw", "easy", "de"),
  w("Rock Me Amadeus", "Falco", 1985, "ndw", "easy", "de"),
  // ---- Deutsch: Rock & Liedermacher ----
  w("Über den Wolken", "Reinhard Mey", 1974, "deutschpop", "medium", "de"),
  w("Du hast den Farbfilm vergessen", "Nina Hagen", 1974, "deutschrock", "hard", "de"),
  w("Am Fenster", "City", 1977, "deutschrock", "ultrahard", "de"),
  w("Sonderzug nach Pankow", "Udo Lindenberg", 1983, "deutschrock", "medium", "de"),
  w("Männer", "Herbert Grönemeyer", 1984, "deutschrock", "easy", "de"),
  w("1000 und 1 Nacht", "Klaus Lage", 1984, "deutschrock", "hard", "de"),
  w(
    "Ohne dich (schlaf ich heut Nacht nicht ein)",
    "Münchener Freiheit",
    1985,
    "deutschpop",
    "hard",
    "de",
  ),
  w("König von Deutschland", "Rio Reiser", 1986, "deutschrock", "medium", "de"),
  w("Freiheit", "Marius Müller-Westernhagen", 1987, "deutschrock", "medium", "de"),
  w("Schrei nach Liebe", "Die Ärzte", 1993, "deutschrock", "medium", "de"),
  w("Du hast", "Rammstein", 1997, "deutschrock", "easy", "de"),
  w("Supergirl", "Reamonn", 2000, "deutschrock", "hard", "de"),
  w("Symphonie", "Silbermond", 2004, "deutschrock", "medium", "de"),
  w("Durch den Monsun", "Tokio Hotel", 2005, "deutschrock", "easy", "de"),
  w("Nur ein Wort", "Wir sind Helden", 2005, "deutschrock", "medium", "de"),
  w("Tage wie diese", "Die Toten Hosen", 2012, "deutschrock", "easy", "de"),
  w("Applaus, Applaus", "Sportfreunde Stiller", 2013, "deutschrock", "medium", "de"),
  // ---- Deutsch: Pop & Hip-Hop ----
  w("MfG", "Die Fantastischen Vier", 1999, "hiphop", "medium", "de"),
  w("Emanuela", "Fettes Brot", 2005, "hiphop", "medium", "de"),
  w("Haus am See", "Peter Fox", 2008, "deutschpop", "medium", "de"),
  w("Lieder", "Adel Tawil", 2013, "deutschpop", "hard", "de"),
  w("Auf uns", "Andreas Bourani", 2014, "deutschpop", "easy", "de"),
  w("80 Millionen", "Max Giesinger", 2016, "deutschpop", "hard", "de"),
  w("Chöre", "Mark Forster", 2017, "deutschpop", "medium", "de"),
  w("Cordula Grün", "Josh.", 2018, "deutschpop", "hard", "de"),
];

/** Anzeige-Label der Genre-Chips (Platten-Karte + Auflösung). */
export function wsGenreLabel(genre: WsGenre): string {
  switch (genre) {
    case "pop":
      return "Pop";
    case "rock":
      return "Rock";
    case "oldie":
      return "Oldie";
    case "disco":
      return "Disco";
    case "hiphop":
      return "Hip-Hop";
    case "country":
      return "Country";
    case "reggae":
      return "Reggae";
    case "schlager":
      return "Schlager";
    case "ndw":
      return "Neue Deutsche Welle";
    case "deutschrock":
      return "Deutschrock";
    case "deutschpop":
      return "Deutschpop";
    default:
      return "Song-Wunsch";
  }
}

/** Jahr-Hinweis der Platte: „1983" — null (Song-Pack ohne Jahr) ⇒ „Jahr ?". */
export function wsJahrHinweis(jahr: number | null): string {
  return jahr === null ? "Jahr ?" : String(jahr);
}

// ---------- Pool-Integritäts-Wächter ----------

const WS_POOL_MINIMUM = 60;
const WS_JAHR_MIN = 1950;
const WS_JAHR_MAX = 2030;

/**
 * Integritäts-Prüfung eines Fakten-Pools — leere Liste = alles sauber.
 * Regeln: 60+-Untergrenze, Titel eindeutig (ein Titel darf im Pool nie auf
 * zwei Interpreten zeigen), Titel/Artist nicht leer, Jahr plausibel, und
 * GLOBAL genug verschiedene Interpreten für 3 Distraktoren.
 */
export function wsPoolFehler(fakten: readonly WsFakt[]): string[] {
  const fehler: string[] = [];
  if (fakten.length < WS_POOL_MINIMUM) {
    fehler.push(`Pool zu klein: ${fakten.length} < ${WS_POOL_MINIMUM}`);
  }
  const titelGesehen = new Set<string>();
  const artists = new Set<string>();
  for (const f of fakten) {
    const titelKey = f.titel.trim().toLowerCase();
    if (titelKey.length === 0) fehler.push("Leerer Titel im Pool");
    if (f.artist.trim().length === 0) fehler.push(`Leerer Artist: „${f.titel}"`);
    if (titelGesehen.has(titelKey)) fehler.push(`Titel doppelt (mehrdeutig!): „${f.titel}"`);
    titelGesehen.add(titelKey);
    artists.add(f.artist.trim());
    if (
      f.jahr !== null &&
      (!Number.isInteger(f.jahr) || f.jahr < WS_JAHR_MIN || f.jahr > WS_JAHR_MAX)
    ) {
      fehler.push(`Jahr unplausibel: „${f.titel}" (${String(f.jahr)})`);
    }
  }
  if (artists.size < 4) fehler.push(`Zu wenige Interpreten für 4 Optionen: ${artists.size}`);
  return fehler;
}

/** EIN Song-Pack-Eintrag als Zusatz-Fakt — null, wenn er den Wächter reißt
 * (leerer Titel/Artist) oder sein Titel schon vergeben ist (Mehrdeutigkeit!). */
export function wsFaktAusSong(
  eintrag: { titel?: unknown; artist?: unknown; jahr?: unknown },
  vergebeneTitel: ReadonlySet<string>,
): WsFakt | null {
  const titel = typeof eintrag.titel === "string" ? eintrag.titel.trim() : "";
  const artist = typeof eintrag.artist === "string" ? eintrag.artist.trim() : "";
  if (titel.length === 0 || artist.length === 0) return null;
  if (vergebeneTitel.has(titel.toLowerCase())) return null;
  const jahr =
    typeof eintrag.jahr === "number" &&
    Number.isInteger(eintrag.jahr) &&
    eintrag.jahr >= WS_JAHR_MIN &&
    eintrag.jahr <= WS_JAHR_MAX
      ? eintrag.jahr
      : null;
  return { titel, artist, jahr, genre: "song-pack", schwierigkeit: "medium", region: "de" };
}

/** Song-Pack ⇒ valide Zusatz-Fakten (dedupliziert gegen Pool UND Pack). */
export function wsFaktenAusSongs(
  songs: readonly { titel?: unknown; artist?: unknown; jahr?: unknown }[] | undefined,
): WsFakt[] {
  if (songs === undefined) return [];
  const vergeben = new Set(WS_FAKTEN_POOL.map((f) => f.titel.trim().toLowerCase()));
  const fakten: WsFakt[] = [];
  for (const s of songs) {
    const fakt = wsFaktAusSong(s, vergeben);
    if (fakt === null) continue;
    vergeben.add(fakt.titel.toLowerCase());
    fakten.push(fakt);
  }
  return fakten;
}

// ---------- Beat-Wahl + Options-Bau (deterministisch, Rng injiziert) ----------

const SCHWIERIGKEIT_RANG: Record<Schwierigkeit, number> = {
  easy: 0,
  medium: 1,
  hard: 2,
  ultrahard: 3,
};

/** Fisher-Yates über den injizierten Rng (Kopie — nie in-place am Input). */
function mische<T>(liste: readonly T[], rng: Rng): T[] {
  const kopie = [...liste];
  for (let i = kopie.length - 1; i > 0; i--) {
    const j = rng.int(i + 1);
    [kopie[i], kopie[j]] = [kopie[j], kopie[i]];
  }
  return kopie;
}

/**
 * Beats einer Runde wählen: bis zur HÄLFTE (aufgerundet) Song-Pack-Wünsche
 * (frisches Party-Futter zuerst), Rest aus dem eingebauten Pool — beides
 * Rng-gemischt, kein Titel doppelt. Die gewählten Beats laufen nach
 * BEKANNTHEIT gestaffelt auf (easy → ultrahard): die Runde wird schwerer.
 */
export function wsWaehleBeats(anzahl: number, packFakten: readonly WsFakt[], rng: Rng): WsFakt[] {
  const n = Math.max(1, anzahl);
  const ausPack = mische(packFakten, rng).slice(0, Math.min(Math.ceil(n / 2), packFakten.length));
  const rest = mische(WS_FAKTEN_POOL, rng).slice(0, Math.max(0, n - ausPack.length));
  const beats = mische([...ausPack, ...rest], rng).slice(0, n);
  return beats.sort(
    (a, b) => SCHWIERIGKEIT_RANG[a.schwierigkeit] - SCHWIERIGKEIT_RANG[b.schwierigkeit],
  );
}

/**
 * 4 Interpret-Optionen bauen: Distraktoren-Staffel (artgleich!) —
 *   1. gleiches Genre UND gleiche Ära (±WS_AERA_JAHRE)
 *   2. gleiches Genre
 *   3. gleiche Ära (±7 Jahre, genrefremd)
 *   4. Rest des Pools
 * — dedupliziert über den Interpret-Namen (nie der richtige, nie doppelt),
 * deterministisch gemischt; die richtige Option landet auf rng.int(4).
 */
export function wsBaueOptionen(
  fakt: WsFakt,
  alleFakten: readonly WsFakt[],
  rng: Rng,
): { optionen: string[]; answer: number } {
  const andere = alleFakten.filter((f) => f.artist !== fakt.artist);
  const gleicheAera = (f: WsFakt, fenster: number): boolean =>
    fakt.jahr !== null && f.jahr !== null && Math.abs(f.jahr - fakt.jahr) <= fenster;
  const stufen: WsFakt[][] = [
    andere.filter((f) => f.genre === fakt.genre && gleicheAera(f, WS_AERA_JAHRE)),
    andere.filter((f) => f.genre === fakt.genre),
    andere.filter((f) => gleicheAera(f, 7)),
    [...andere],
  ];
  const gesehen = new Set([fakt.artist]);
  const distraktoren: string[] = [];
  for (const stufe of stufen) {
    for (const kandidat of mische(stufe, rng)) {
      if (distraktoren.length >= 3) break;
      if (gesehen.has(kandidat.artist)) continue;
      gesehen.add(kandidat.artist);
      distraktoren.push(kandidat.artist);
    }
    if (distraktoren.length >= 3) break;
  }
  // Not-Ausstieg (Pool-Wächter macht das praktisch unmöglich): generische
  // Füller, damit IMMER 4 Optionen stehen — ein Match darf nie crashen.
  let fueller = 1;
  while (distraktoren.length < 3) distraktoren.push(`Unbekannte Band ${fueller++}`);
  const answer = rng.int(4);
  const optionen = [...distraktoren.slice(0, answer), fakt.artist, ...distraktoren.slice(answer)];
  return { optionen: optionen.slice(0, 4), answer };
}

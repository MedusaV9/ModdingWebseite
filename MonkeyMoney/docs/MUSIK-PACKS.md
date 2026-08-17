# MUSIK-PACKS — Songs importieren & pflegen

Das Song-Pack-System versorgt die Musik-Minigames (Blitz-DJ, Rückwärts-Banane,
Stummfilm-Studio) mit kurzen Rate-Snippets echter Songs. EIN Befehl auf deinem
PC macht aus einem Song alle Schnipsel + Katalog-Eintrag + Credits-Zeile.
Mit `--bett` macht derselbe Befehl aus DEINEM Lieblings-Song stattdessen einen
Party-Hintergrund-Loop für die Show (Abschnitt „Bett-Loops").

## Voraussetzungen (einmalig installieren)

Der Import braucht zwei freie Werkzeuge: **yt-dlp** (Downloader) und
**ffmpeg** (Schnitt + Loudness; bringt `ffprobe` mit). Node ≥ 20 hast du
fürs Projekt sowieso. Ein Einzeiler je System:

| System                | yt-dlp                                                 | ffmpeg                       |
| --------------------- | ------------------------------------------------------ | ---------------------------- |
| macOS (Homebrew)      | `brew install yt-dlp`                                  | `brew install ffmpeg`        |
| Windows (winget)      | `winget install yt-dlp.yt-dlp`                         | `winget install Gyan.FFmpeg` |
| Linux (Debian/Ubuntu) | `pipx install yt-dlp` (vorher `sudo apt install pipx`) | `sudo apt install ffmpeg`    |

Danach ein NEUES Terminal öffnen (PATH!). Fehlt ein Werkzeug, sagt dir
`import.mjs` genau das mit denselben Einzeilern — kein kryptischer
`spawnSync ENOENT` mehr. Prüfen: `yt-dlp --version` und `ffmpeg -version`.

## Song adden in 1 Zeile (zuhause)

```bash
node tools/musik/import.mjs --suche "Nena - 99 Luftballons" \
  --titel "99 Luftballons" --artist "Nena" --jahr 1983 \
  --schwierigkeit leicht --region de
```

Das war's. Der Befehl:

1. lädt den Song per yt-dlp (`--suche` = YouTube-Topsuche `ytsearch1:`;
   alternativ `--url <YouTube/archive.org/Dailymotion/direkte-Datei-URL>` oder
   `--datei <lokale-Datei>`),
2. normalisiert auf −16 LUFS (loudnorm) und schneidet ALLE Snippets:
   `intro5s` (Sekunde 0–5), Buzz-Serie `100/200/300/500/1000 ms` ab dem Hook,
   `mitte10s` (ab 40 % der Laufzeit), `rueckwaerts5s` (5 s ab Hook, rückwärts),
3. LÖSCHT den Volldownload (nur die Snippets bleiben — bewusst schlank,
   ~0,3 MB pro Song),
4. schreibt den Eintrag in `content/musik/songs.json` und die Credits-Zeile
   in `content/musik/CREDITS-SONGS.md` (automatisch, keine Ausrede).

Danach prüfen und einchecken:

```bash
node tools/musik/validate-songs.mjs   # Schema + Dateien + ffprobe-Dauern
git add content/musik && git commit -m "Song: 99 Luftballons"
```

## Hook-Sekunde wählen

Die Buzz-Serie und `rueckwaerts5s` starten am „Hook" — der wiedererkennbarsten
Stelle. Standard: Sekunde 30. Liegt der ikonische Moment woanders
(Refrain-Einsatz, berühmte Zeile), mit `--hook <sekunden>` setzen:

```bash
node tools/musik/import.mjs --suche "Queen - Bohemian Rhapsody" \
  --titel "Bohemian Rhapsody" --artist "Queen" --jahr 1975 \
  --schwierigkeit mittel --region global --hook 355   # "Galileo!"-Teil
```

Ist der Song kürzer als Hook+5 s, clampt das Tool automatisch (mit Hinweis).

## Video-Modus (Stummfilm-Studio)

`--video` lädt zusätzlich das Video und schneidet einen STUMMEN
3-Sekunden-Clip (480p mp4) ab dem Hook — das Format „Stummfilm-Studio"
(musikvideo-raten) spielt nur Songs MIT `video3s`:

```bash
node tools/musik/import.mjs --url "https://www.youtube.com/watch?v=…" \
  --titel "…" --artist "…" --jahr 1984 --schwierigkeit mittel --region de --video
```

## Bett-Loops: DEINE Songs als Party-Hintergrund (`--bett`)

Die Show spielt zwischen den Fragen Musik-BETTEN (Lobby, Runden-Bett, News …).
Mit `--bett` baust du dir deine eigene Party-Playlist: der Import behält statt
Rate-Snippets EINEN 60–90-s-Loop-Schnitt —

```bash
node tools/musik/import.mjs --bett --suche "Yello - Oh Yeah" \
  --titel "Oh Yeah" --artist "Yello" --jahr 1985 --stimmung upbeat --hook 12
```

1. Loop ab `--hook` (Default-Länge 75 s, einstellbar mit `--laenge 60–90`),
2. loudnorm auf **−18 LUFS** — bewusst LEISER als die SFX (−16): Hintergrund,
   die Show spricht über dem Bett,
3. Fade-in/-out für nahtloses Loopen (kein Klick an der Kante),
4. Ablage unter `content/musik/bett/<id>.ogg` + Eintrag in `songs.json` mit
   `nurBett: true`, `stimmung` und `medien.bett` — KEINE Snippets, der Song
   ist NIE Rate-Material. `--schwierigkeit`/`--region` sind im Bett-Modus
   optional (Defaults `mittel`/`global`).

**Rotation:** Die Show spielt pro Phase nicht mehr EINEN fixen Track, sondern
rotiert durch eine Playlist (`client/shared/fx/musik-rotation.ts`): der
MacLeod-Kern bleibt IMMER der Default (erster Track), dahinter laufen deine
Bett-Loops — `--stimmung chillig` in der **Lobby**, `--stimmung upbeat` im
**Runden-Bett**. Die Reihenfolge wird pro Match aus dem Raum-Code geseedet
(deterministisch, kein Track 2× hintereinander); Schleich-/Rad-/News-/
Erklär-Signale bleiben bewusst wiedererkennbare 1-Track-Loops. Die Rotation
zieht die Loops über `GET /api/musik/betten` (Dateien: `/media-musik-bett/`).

**Bedienung:** Screen unten rechts (Musik-Control: An/Aus, Lautstärke,
„Nächster Track", Track-Ticker „♪ Titel — Artist"; persistiert im
localStorage), GM-Cockpit → Show & Publikum → ♪ Musik (Match-Setting
`musik: an/aus`, Show-Volume, Skip, Playlist-Ansicht). Musik-Formate mit
stummem Bett (Blitz-DJ & Co., `MUSIK_STUMME_FORMATE`) gewinnen IMMER gegen
die Rotation — da spielt und skippt nichts.

## Alle Optionen

| Option                     | Bedeutung                                                         |
| -------------------------- | ----------------------------------------------------------------- |
| `--suche "Artist - Titel"` | YouTube-Topsuche (ytsearch1:)                                     |
| `--url <URL>`              | direkte Quelle (YouTube, archive.org, Dailymotion, Datei-URL)     |
| `--datei <pfad>`           | lokale Datei (dann `--quelle-url` für die Credits setzen!)        |
| `--titel/--artist/--jahr`  | Pflicht-Metadaten (das Quiz fragt danach!)                        |
| `--schwierigkeit`          | `leicht`&#124;`mittel`&#124;`schwer`&#124;`ultrahard`             |
| `--region`                 | `de` (nur bei DE-Region im Pool) oder `global`                    |
| `--hook <s>`               | Start der Buzz-Serie + rueckwaerts5s (Default 30)                 |
| `--video`                  | stummen 3-s-Clip zusätzlich schneiden                             |
| `--cover`                  | Aufnahme ist ein Cover — wird in Tags + Credits MARKIERT          |
| `--tags "a,b"`             | freie Tags                                                        |
| `--id s_mein_slug`         | eigene Id (Default: aus dem Titel)                                |
| `--force`                  | vorhandenen Eintrag gleicher Id überschreiben                     |
| `--bett`                   | Bett-Loop statt Rate-Snippets (60–90 s, −18 LUFS, Fades)          |
| `--stimmung`               | `chillig` (Lobby-Rotation) &#124; `upbeat` (Runde) — nur `--bett` |
| `--laenge <s>`             | Loop-Länge 60–90 (Default 75) — nur `--bett`                      |

## Wenn YouTube blockt („Sign in to confirm …")

YouTube blockt Server-/Cloud-IPs. Der Import erkennt das und sagt es klar:
**auf deinem PC zuhause läuft derselbe Befehl normal durch.** Falls YouTube
auch dort zickt: Browser-Cookies mitgeben —

```bash
YTDLP_EXTRA="--cookies-from-browser chrome" node tools/musik/import.mjs …
```

archive.org- und direkte Dailymotion-URLs funktionieren auch von Servern.
Für archive.org am besten den DIREKTEN Datei-Link nehmen (auf der Item-Seite
rechts unter „Download Options" → MP3/FLAC verlinken).

## Das Song-Pack-Format (verbindlich)

`content/musik/songs.json` — die Minigames bauen gegen dieses Format
(kanonische Typen: `shared/songs.ts`):

```jsonc
{
  "songs": [
    {
      "id": "s_hound_dog",
      "titel": "Hound Dog",
      "artist": "Elvis Presley",
      "jahr": 1956,
      "region": "global", // "de" | "global"
      "schwierigkeit": "leicht", // leicht|mittel|schwer|ultrahard
      "nurBett": false, // optional: true = NUR Show-Bett, nie Rate-Song (s. unten)
      "tags": ["50s", "rocknroll"],
      "medien": {
        "intro5s": "media/s_hound_dog/intro5s.ogg",
        "buzz": { "ms100": "…", "ms200": "…", "ms300": "…", "ms500": "…", "ms1000": "…" },
        "mitte10s": "media/s_hound_dog/mitte10s.ogg",
        "rueckwaerts5s": "media/s_hound_dog/rueckwaerts5s.ogg",
        "video3s": "media/s_hound_dog/video3s.mp4", // optional (--video)
      },
      "quelle": { "plattform": "archive.org", "url": "…", "abgerufen": "2026-08-15" },
    },
  ],
}
```

Dateien liegen unter `content/musik/media/<id>/`; der Server liefert sie als
`/media-musik/<id>/…` aus (`server/core/http.ts`). Loader-Zugriff für Engine
und Formate: `pickSongs()` im Content-Loader (docs/ARCHITEKTUR.md §Andocken 2).

## Bett vs. Rate-Pool (`nurBett`)

Die Show spielt zwischen den Fragen Musik-BETTEN (Lobby-Loop, Runden-Bett,
News …, `client/shared/fx/sound-map.ts` → `MUSIK`) — das sind die 6
Kevin-MacLeod-Tracks des Projekts. Dieselben Tracks standen anfangs auch als
Rate-Songs im Katalog, mit absurdem Ergebnis (Eval 3): **QuirkyDog lief als
Bett, WÄHREND QuirkyDog rückwärts zu raten war.**

Deshalb tragen die 6 MacLeod-Einträge in `songs.json` das Flag
`"nurBett": true`: `pickSongs()` filtert sie aus JEDEM Match-Pool (Blitz-DJ,
Rückwärts-Banane, Stummfilm-Studio, Telegramm-Begriffs-Topf) — sie bleiben
aber im Katalog dokumentiert (Credits, Validierung) und laufen weiter als
Betten. Dieselbe Trennung gilt für deine `--bett`-Loops: sie sind IMMER
`nurBett: true` und haben gar keine Snippets — ein Konflikt wie oben kann
also nicht entstehen. Willst du denselben Song als Bett UND als Rate-Song,
importierst du ihn einfach zweimal (einmal mit, einmal ohne `--bett` — die
Ids kollidieren nicht: `s_bett_<slug>` vs. `s_<slug>`); in Musik-Runden ist
das Bett ohnehin stumm (`MUSIK_STUMME_FORMATE`), gespoilert wird nichts.

Bett-Einträge in `songs.json` sehen so aus (kanonisch: `shared/songs.ts`
→ `BettEintragSchema`; Validierung inkl. 60–90-s-Fenster + Waisen-Check:
`node tools/musik/validate-songs.mjs`):

```jsonc
{
  "id": "s_bett_in_the_mood",
  "titel": "In the Mood",
  "artist": "Glenn Miller & His Orchestra",
  "jahr": 1939,
  "nurBett": true,
  "stimmung": "upbeat", // "chillig" = Lobby-Rotation, "upbeat" = Runde
  "medien": { "bett": "bett/s_bett_in_the_mood.ogg" }, // KEINE Snippets
  "quelle": { "plattform": "archive.org", "url": "…", "abgerufen": "2026-08-16" },
}
```

## Hook-Loudness pflegen

Der Import normalisiert den GANZEN Song auf −16 LUFS. Ist die Hook-Stelle
selbst leise (La Vie en rose: −25 LUFS am 1-s-Buzz), bleiben die
Buzz-Schnipsel im Match zu leise. Kuratier-Werkzeug:

```bash
node tools/musik/normalisiere-hooks.mjs --check   # nur messen (Exit 1 bei > ±3 dB)
node tools/musik/normalisiere-hooks.mjs           # Ausreißer nachziehen
```

Es misst `buzz_ms1000` (Proxy der ganzen Buzz-Serie) + `rueckwaerts5s` per
loudnorm und zieht Ausreißer mit konstantem Gain (True-Peak-Deckel −1,5 dBTP,
bei Crest-Fällen mit Limiter) auf −16 LUFS. Alternativ: Import mit besserem
`--hook <s>` wiederholen (`--force`).

## Demo-Pack „starter"

Mitgeliefert: ~19 Songs — echte Originale der 78er-/Klassiker-Ära von
archive.org (Elvis, Bill Haley, Glenn Miller, Piaf, Judy Garland, Little
Richard, Fats Domino, Lale Andersen, Hans Albers, Comedian Harmonists …)
plus die 6 Kevin-MacLeod-Tracks des Projekts (CC BY 4.0) — Letztere mit
`"nurBett": true`, d. h. sie sind Show-Betten und tauchen NIE als Rate-Song
auf (Abschnitt „Bett vs. Rate-Pool"). Rate-Pool damit: 13 Songs.
Dazu 4 Demo-**Bett-Loops** (`--bett`-Pipeline, 78rpm-Klassiker als
Lobby-Vibe): La Vie en rose (Piaf), What a Wonderful World (Armstrong),
Over the Rainbow (Garland) — chillig/Lobby — und In the Mood (Glenn Miller)
— upbeat/Runde. Vollständige Liste + Quellen: `content/musik/CREDITS-SONGS.md`.

Hinweis zur Quellen-Lage: Das Great-78-Project auf archive.org wurde nach der
Label-Klage ausgedünnt — die großen Major-Hits (z. B. Sinatra „My Way",
Armstrong-Originale nach 1960) sind dort teils nicht mehr als Original zu
bekommen. Was das Demo-Pack enthält, IST das jeweils echte Original (bzw. ist
in den Credits ehrlich markiert, z. B. „TV-Fassung").

## Rechtlicher Rahmen (bitte lesen)

- **Privates Freundes-Projekt**: keine Veröffentlichung, kein Vertrieb, keine
  öffentliche Aufführung. Die Snippets (0,1–10 s) dienen dem privaten
  Quiz-Abend im Wohnzimmer.
- **Volldownloads werden gelöscht** — im Repo liegen nur die kurzen Snippets.
- **Credits sind PFLICHT und automatisch**: das Import-Tool führt
  `content/musik/CREDITS-SONGS.md` (Titel/Artist/Quelle-URL/Datum) bei jedem
  Import mit. Cover IMMER mit `--cover` kennzeichnen.
- Für alles, was über den privaten Rahmen hinausgeht (Streams, Videos,
  öffentliche Events), braucht ihr lizenzierte Musik — die MacLeod-Tracks
  (CC BY 4.0) sind dafür die sichere Wahl.

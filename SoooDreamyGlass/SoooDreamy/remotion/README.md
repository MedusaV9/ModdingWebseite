# SoooDreamy Kino-Prolog — Remotion-Pipeline (FullRelease N1-C)

Dieses npm-Projekt rendert die drei **Video-Szenen** der Kino-Dramaturgie
(`docs/styles/STYLE_DECISION.md` §3.9) im Papier&Licht-Stil — **in CI, nie
committet**. Es verlängert die App-Philosophie „kein Binary im Repo"
(Icons: `GenerateIcon.swift`, Sounds: `prepare_sounds.sh`) um Videos.
Bauplan und Belege: `docs/styles/RECON_REMOTION_PIPELINE.md`.

| Komposition | Datei | Dauer | Szene (Decision §3.9) |
|---|---|---|---|
| `Scene2Envelope` | `scene2_envelope.mp4` | 8 s | #2 „Der Umschlag": schiebt sich in den Kegel, Poststempel prägt sich auf |
| `Scene3SealBreak` | `scene3_seal.mp4` | 10 s | #3 „Der Siegelbruch": Wachs bricht, der Brief entfaltet sich (blank) |
| `Scene6Polaroid` | `scene6_polaroid.mp4` | 8 s | #6 „Das leere Polaroid": entwickelt sich von Weiß zu `Papier.polaroid`, bleibt leer |

Format: **1170×2532 @ 30 fps**, HEVC (`--codec=h265 --crf=23`), **`--color-space=bt709`**
(Pflicht — der 4.0-Default ist BT.601, Recon §6.2), **`--muted`** (Ton kommt aus der
SoundEngine der App, gesteuert vom Manifest).

**Pflicht-Remux `hvc1`** (Geräte-Bug 15.0.0): Remotion/ffmpeg schreibt das
HEVC-Sample-Entry `hev1`; echte iPhones (Hardware-Decoder) verlangen `hvc1`
und lassen `hev1`-Items **still** sterben — leerer Kino-Raum auf dem Gerät,
während der Simulator (Software-Decode) fröhlich abspielt. Nach jedem Render:
`npm run remux:hvc1` (verlustfrei, `-c copy -tag:v hvc1`). CI erzwingt das
Tag mit einem fail-closed ffprobe-Gate.

## Warum textfrei?

Es wird **kein einziges Wort** gerendert — Anschrift, Stempel und Briefkopf sind
abstrakte Geometrie. Konsequenzen (Recon §6.1, Option A):

- **Kein Font-Problem auf Linux** (SF Pro existiert dort nicht und Apples
  Font-Lizenz bindet es an Apple-Plattformen — gar nicht erst versuchen).
- **Eine Sprachfassung** statt DE+EN: halbes Budget, halbe Renderzeit.
- Sprache lebt in **nativen SwiftUI-Overlays** der App (Timecodes/`captions`
  wären App-seitig zu pflegen; VoiceOver + Dynamic Type gratis).
- Die Papier-**Mitte** der Szenen bleibt bewusst ruhig — dort liegt der
  Overlay-Text der App (Safe-Area: äußere ~6 % meiden, Recon §6.5).

Die Tintenfarben sind `inputProps` mit Defaults (`inkA` #FF5C8A, `inkB`
#60A5FA) — Laufzeit-Paarfarben bleiben per Design der prozeduralen Hälfte
(beim First Launch existiert noch kein Paar, Recon §6.5).

## Lokal arbeiten

```bash
cd SoooDreamy/remotion
npm ci                       # Node 22; package-lock.json ist gepinnt (4.0.512)
npx remotion browser ensure  # Chrome Headless Shell (einmalig, ~90 MB)
npm run studio               # interaktive Preview
npm run render:all           # alle drei Szenen nach out/ (HEVC, bt709, muted)
npm run manifests            # Haptik-Manifeste aus src/timeline.mjs erzeugen
npm run manifests:check      # Drift-Gate (CI): committete JSONs == Timeline
npm run typecheck
```

Schneller Smoke-Render (halbe Auflösung, 3 s):

```bash
npx remotion render src/index.ts Scene2Envelope /tmp/s2.mp4 \
  --frames=0-89 --scale=0.5 --codec=h264 --muted --color-space=bt709
```

Achtung: `--scale` muss ganzzahlige Pixelmaße ergeben (0.5 ✓, ⅓ ✗).
Kein `--gl`-Flag setzen: DOM/CSS-Kompositionen brauchen keins, und
`--gl=angle` schlägt auf GPU-losen GitHub-Runnern fehl (Recon §1.3).

**Determinismus-Regeln** (das CI-Gate erzwingt sie): kein `Math.random()`,
kein `Date.now()` — nur die seeded `random()`-API von Remotion; keine
Netz-Assets; SVG-Turbulenz nur mit festem `seed`.

## Eine Quelle für Bild UND Haptik: `src/timeline.mjs`

Alle Szenen-Zeitmarken, Beats und Sound-Cues leben in `src/timeline.mjs`
(bewusst plain-ESM: die Kompositionen importieren sie via TypeScript,
`src/export-manifests.mjs` als dependency-freies Node-Skript). Die
Kompositionen choreografieren auf dieselben Marken, auf denen die Beats
liegen — Bild und Haptik können nicht driften.

### Manifest-Format (`manifests/<scene>.haptics.json`, committet)

```json
{
  "video": "scene2_envelope.mp4",
  "composition": "Scene2Envelope",
  "fps": 30,
  "durationSec": 8,
  "posterTime": 6.8,
  "beats": [{ "t": 5.2, "type": "tap", "i": 0.9, "s": 0.62, "d": 0 }],
  "cues": [{ "t": 5.2, "id": "sealed" }]
}
```

- `beats`: `t/i/s/d` sind 1:1 das App-`HapticEventSpec`
  (`Core/HapticPatternKit.swift`) — t = Sekunden ab Videostart, i = Intensität,
  s = Schärfe, d = Dauer (0 = Transient). `type` (`tap`/`success`/`soft`) ist
  die menschenlesbare Beat-Klasse für Review/Mapping.
- `cues`: AppCue-IDs **mit committetem Sample** (`cue_<id>.caf`,
  `Core/AppCueCatalog.swift`); der Export validiert gegen diese Positivliste.
- `posterTime`: Frame-Zeit für das Reduce-Motion-Standbild
  (`AVAssetImageGenerator`, Recon §3.4).
- Trigger-Empfehlung: `AVPlayer.addBoundaryTimeObserver(forTimes:)` auf der
  Player-Clock — feuert korrekt nach Pause/Seek/Skip (Recon §3.6).

Manifeste werden generiert (`npm run manifests`) und committet; das CI-Gate
`manifests:check` bricht, wenn JSON und Timeline auseinanderlaufen.

## CI-Fluss (`.github/workflows/sooodreamy.yml`)

1. **`render-videos`** (ubuntu-latest, 1×-Minuten): `actions/cache` auf
   `out/` mit Key = Hash über `src/**`, `manifests/**`, `remotion.config.ts`,
   `package-lock.json`. **Nur bei Cache-Miss** wird installiert und gerendert:
   - Manifest-Drift-Gate (`manifests:check`),
   - **Determinismus-Gate**: 2-s-Probe (`--frames=0-59`) zweimal rendern,
     SHA-256 muss identisch sein (fängt eingeschlepptes `Math.random()`,
     bevor es den Cache vergiftet — Recon §5.2, [Gemessen] stabil),
   - Render aller drei Szenen (HEVC/bt709/muted),
   - **Filmstreifen**: alle 2 s ein Full-Res-Still → Artefakt
     `SoooDreamy-video-filmstrips` (Optik-Review durch Agents/Menschen).
   - **Größen-Gate (fail-closed, läuft auch bei Cache-Hit): Σ MP4 ≤ 15 MB.**
   - Artefakt `SoooDreamy-cinematic-videos` = `out/` (MP4s + Manifeste).
2. **`build-ipa`** hat `needs: render-videos` und lädt das Artefakt nach
   `ios/SoooDreamy/Resources/Videos/` **vor** `xcodegen generate`
   (XcodeGen scannt das Dateisystem beim Generate — exakt das Icon-Muster).
   Der Package-Step verifiziert fail-closed, dass alle drei MP4s + Manifeste
   im App-Bundle liegen.
3. **`build-ipa-lite`** bleibt ohne `needs`/Download: Die Dateien existieren
   beim Generate nicht und können nicht ins Bundle geraten. Der Lite-Package-
   Step verifiziert spiegelbildlich, dass KEIN Szenen-Video eingebettet ist.
   **Fehlende Videos sind ein legaler Zustand** — die Abspielseite muss auf
   den prozeduralen Intro-Pfad zurückfallen (Lite = prozedural-only).

## Was die App-Welle wissen muss

- **Bundle-Dateinamen** (flache Kopie wie `Sounds/*.caf`): `scene2_envelope.mp4`,
  `scene3_seal.mp4`, `scene6_polaroid.mp4`, `scene2.haptics.json`,
  `scene3.haptics.json`, `scene6.haptics.json`. Der CI-Check akzeptiert auch
  eine `Videos/`-Unterordner-Kopie und loggt den tatsächlichen Ort — beim
  ersten echten Lauf prüfen und den Loader entsprechend festnageln
  (`Bundle.main.url(forResource:withExtension:)`, ggf. `subdirectory:`).
- **`project.yml`-Anforderungen (bewusst NICHT hier umgesetzt — App-Welle):**
  1. `SoooDreamyLite`-Target: `sources: - path: SoooDreamy` um
     `excludes: ["Resources/Videos/**"]` ergänzen (Recon §2.6) — schützt
     gegen lokal herumliegende Renders; in CI ist Lite schon heute sicher,
     weil der Ordner dort schlicht nicht existiert.
  2. `SoooDreamy/.gitignore`: `ios/SoooDreamy/Resources/Videos/` aufnehmen
     (lokal gerenderte Videos dürfen nie committet werden).
  Ein fehlender `Resources/Videos/`-Ordner bricht **keinen** Build:
  `project.yml` hat keinen expliziten `resources:`-Block, XcodeGen ordnet
  nur tatsächlich vorhandene Dateien den Build-Phasen zu.
- Szene 3 beginnt auf dem End-Frame von Szene 2 (gestempelter Umschlag) —
  die beiden gehören im `AVQueuePlayer` direkt hintereinander; zwischen
  Szene 3 und 6 liegen die prozeduralen Szenen 4/5.
- Alle Szenen starten und enden auf ruhigen Hold-Frames im Zimmer-Dunkel —
  Übergänge zu prozeduralen Szenen auf derselben Raumfarbe (#201613-Familie)
  wirken als eine Einstellung.

## Budget

Gate: **Σ ≤ 15 MB** für alle drei MP4s (ohne Sprachdopplung; real liegen die
drei HEVC-Renders bei ~2–4 MB gesamt — weiches Gradient-Material komprimiert
exzellent, Recon §4.1). Das Gate ist Code, nicht Absicht — gleicher Geist wie
das 120-KB-Gate in `prepare_sounds.sh`. Design-Regel dahinter: kein animiertes
Filmkorn, keine Full-Frame-Partikelstürme (Faktor 3–5 Bitrate).

## Lizenz

Remotion ist source-available mit zweistufiger Lizenz; dieses Projekt (privates
Zwei-Personen-Hobby, nicht gewinnorientiert) fällt unter die **Free License**
(Schwelle „Company License" beginnt bei ≥ 4 Personen; Recon §1.2 mit
Lizenz-Quellen). Version ist via `package-lock.json` auf 4.0.512 gepinnt;
bei jedem Major-Upgrade (5.0: Telemetrie-Pflicht nur für den bezahlten
Automators-Tarif) den Lizenztext neu lesen.

# RECON: Remotion-Video-Pipeline für SooDreamy

**Stand: 2026-08-15. Bau-Dossier, keine Implementierung.** Ziel: echte Videos/Animationen
(First-Launch-Cutscenes in Kapiteln, DE + EN, auch im Demo-Modus; ggf. Feature-Vignetten)
mit [Remotion](https://www.remotion.dev) programmatisch bauen — **in CI gerendert, ins
App-Bundle injiziert, nur Remotion-Quellcode im Repo**. Das verlängert die bestehende
Philosophie (App-Icons rendert `ios/scripts/GenerateIcon.swift` in CI, Sounds baut
`ios/scripts/prepare_sounds.sh`) statt sie zu brechen: kein Video-Binary wird je committet.

**Beleg-Disziplin dieses Dossiers:** Jede Behauptung trägt eine Quelle (Remotion-Doku-URL,
Apple-Doku) oder ist explizit als **[Gemessen]** (eigener Benchmark, Methodik in §1.5) bzw.
**[Annahme]** markiert. Der Benchmark lief am 2026-08-15 auf einer 4-vCPU-Linux-VM mit
Remotion 4.0.512 — einem `ubuntu-latest`-Runner vergleichbar.

**Spannungsfeld, ehrlich benannt:** `ios/SoooDreamy/Content/CinematicScript.swift` beantwortet
im Header „die Remotion-Frage" bewusst mit *prozedural statt MP4* (Localization, Couple-Tint,
Reduce-Motion, VoiceOver, Haptik-Synchronität). Diese Argumente verschwinden nicht — das
Dossier löst sie einzeln auf (§3) und empfiehlt eine **Hybrid-Dramaturgie**: Video für das
Filmische, prozedural für alles Interaktive/Haptische. Wo ein Argument nicht sauber lösbar
ist (z. B. Couple-Tint im vorgerenderten Video), steht das hier ausdrücklich.

---

## 1. Remotion-Grundlagen 2026

### 1.1 Version

- Aktuelle Release-Linie: **Remotion 4.0.4xx** — `npm i remotion @remotion/cli` installierte
  am 2026-08-15 **4.0.512** [Gemessen].
- **Remotion 5.0 ist angekündigt, aber nicht released** („Remotion 5.0 is not yet released",
  <https://www.remotion.dev/docs/5-0-migration>). Relevante 5.0-Änderungen zum Vormerken:
  `bt709` wird Default-Farbraum, `angle` wird Default-GL-Renderer (mit Swangle-Fallback),
  Telemetrie wird für den **bezahlten** Automators-Tarif Pflicht (Free-Tier unberührt).
- Empfehlung: **exakte 4.0.x-Version pinnen** (`package-lock.json` committen), Upgrade auf
  5.0 erst nach eigener Evaluierung. Grund: Cache-Determinismus (§1.5) und der
  Chrome-Headless-Shell-Versionskoppel (Remotion-Version ↔ Chrome-Version, Tabelle in
  <https://www.remotion.dev/docs/miscellaneous/chrome-headless-shell>).

### 1.2 Lizenz — gilt die Company-Klausel für uns?

**Nein. Ein privates Zwei-Personen-Hobby-Projekt fällt unter die Free License.**

- Remotion ist source-available (nicht OSI-open-source) mit zweistufiger Lizenz. Die
  **Free License** gilt laut Lizenztext für: „an individual", „a for-profit organization
  with up to 3 employees", „a non-profit or not-for-profit organization" sowie Evaluierung.
  Quellen: <https://www.remotion.dev/docs/license/terms> und
  <https://github.com/remotion-dev/remotion/blob/main/LICENSE.md>.
- Die Company-License-Schwelle: „A license is mandatory when the total number of personnel
  across all involved parties that operate the Remotion Software reaches the threshold of
  **four or more**" (<https://www.remotion.dev/docs/license/terms>). Zwei Personen, nicht
  gewinnorientiert, keine Auftraggeber — wir liegen unter jeder Schwelle, sogar doppelt
  (Personenzahl **und** Non-Profit-Charakter).
- Kommerzieller Output ist unter der Free License ausdrücklich erlaubt („to use the software
  non-commercially or commercially for the purpose of creating videos and images",
  LICENSE.md) — für uns irrelevant, aber es gäbe auch da keinen Konflikt.
- **Restrisiko, ehrlich:** Die Lizenz kann sich ändern (für 5.0 ist eine Änderung
  angekündigt — Telemetrie-Pflicht, aber nur für den bezahlten Automators-Tarif,
  <https://www.remotion.dev/docs/5-0-migration>). Beim Versions-Pin bleibt die beim
  Installieren geltende Lizenz maßgeblich; bei jedem Major-Upgrade Lizenztext neu lesen.

### 1.3 Renderer: `ubuntu-latest` vs. `macos-26`

**Empfehlung: eigener `render-videos`-Job auf `ubuntu-latest`.** Begründung:

- Remotion rendert headless über eine mitinstallierte **Chrome Headless Shell**
  (landet in `node_modules/.remotion/`, `npx remotion browser ensure` lädt sie explizit;
  <https://www.remotion.dev/docs/miscellaneous/chrome-headless-shell>).
- Linux braucht Shared Libraries (Ubuntu 24.04: `libnss3 libdbus-1-3 libatk1.0-0
  libasound2t64 libxrandr2 libxkbcommon-dev libxfixes3 libxcomposite1 libxdamage1
  libgbm-dev libcups2 libcairo2 libpango-1.0-0 libatk-bridge2.0-0`;
  <https://www.remotion.dev/docs/miscellaneous/linux-dependencies>). Auf der Test-VM war
  ohne zusätzliche Installation alles lauffähig [Gemessen] — der GitHub-Runner bringt die
  Chrome-Abhängigkeiten typischerweise mit; der `apt install`-Schritt gehört trotzdem als
  Absicherung in den Job (idempotent, ~10 s).
- **`--gl`-Flags:** In 4.0 ist der Default `null` (Chrome entscheidet). GitHub-Actions-Runner
  haben **keine GPU**, `--gl=angle` schlägt dort fehl („In Remotion 4.0, GitHub Actions will
  fail when using angle, since Actions runners don't have a GPU"). Für DOM/CSS-Kompositionen
  (unser Fall): **kein Flag setzen**. Nur falls WebGL/Three.js dazukommt: `--gl=swangle`
  (Software-Rendering, langsamer). Quelle: <https://www.remotion.dev/docs/gl-options>.
- `macos-26` wäre technisch möglich, bringt für DOM-Kompositionen aber nichts — und kostet
  bei privaten Repos den **10×-Minuten-Multiplikator** (Linux 1×, macOS 10×;
  <https://docs.github.com/en/billing/managing-billing-for-github-actions/about-billing-for-github-actions>).
  Die macos-26-Runner bleiben dem reserviert, was nur dort geht (xcodebuild).
- Offizielles GitHub-Actions-Rezept (checkout → setup-node → `npm i` →
  `npx remotion render` → upload-artifact): <https://www.remotion.dev/docs/ssr>
  („Render using GitHub Actions").

### 1.4 Renderzeiten (1080×2340-Klasse, iPhone-Portrait)

**[Gemessen]** auf 4 vCPU (Methodik §1.5): eine 10-s-Komposition, **1170×2532 @ 30 fps**
(300 Frames), Aurora-Gradienten + 140 Sterne + Orbs + Text (bewusst nah am
SooDreamy-Cinematic-Look), H.264 CRF 23:

| Schritt | Dauer |
|---|---|
| `npm i` (245 Pakete) | ~9 s |
| Chrome Headless Shell Download (`browser ensure`) | ~15 s (einmalig, cachebar) |
| Render 10 s / 300 Frames | **~19 s** (≈ 16 Frames/s, ≈ 1,9× Echtzeit) |
| `remotion still` (1 Frame inkl. Start) | ~1,9 s |

Hochrechnung **[Annahme: lineare Skalierung]**: ein 60-s-Kapitel ≈ 2 min; sechs Kapitel
à 45–60 s in DE + EN (≈ 9–12 min Gesamtmaterial) ≈ **18–25 min Renderzeit** auf 4 vCPU.
Achtung: `ubuntu-latest` hat für **öffentliche** Repos 4 vCPU, für **private** Repos 2 vCPU
(<https://docs.github.com/en/actions/using-github-hosted-runners/about-github-hosted-runners>)
— im privaten Repo also grob **Faktor 2** einplanen; beim ersten echten CI-Lauf nachmessen.
Deshalb ist der Render-Cache (§2.4) nicht Kür, sondern Pflicht: gerendert wird nur, wenn
sich Remotion-Quellen ändern.

Concurrency-Default ist die halbe Kernzahl; `--concurrency` ist tunebar
(<https://www.remotion.dev/docs/cli/render>). Erst messen, dann drehen.

### 1.5 Deterministische Renders (Cache-Grundlage)

- Regel Nr. 1: **kein `Math.random()`, kein `Date.now()`** in Kompositionen — Remotion
  rendert parallel in mehreren Browser-Instanzen; nichtdeterministische Werte divergieren
  zwischen Frames. Stattdessen die seeded `random()`-API
  (<https://www.remotion.dev/docs/using-randomness>). Das ESLint-Plugin
  (`@remotion/eslint-plugin`) warnt automatisch.
- **[Gemessen]**: Zwei aufeinanderfolgende Renders derselben Komposition (gleiche Maschine,
  Remotion 4.0.512, H.264 CRF 23) waren **byte-identisch** (SHA-256
  `de8aecd9…a26f7b` beide Male). Byte-Determinismus auf derselben Umgebung ist also real.
- **Ehrliche Einschränkung:** Byte-Stabilität **über Versionsgrenzen hinweg** ist nicht
  garantiert — ein Remotion-Upgrade wechselt die gebündelte Chrome-Version
  (<https://www.remotion.dev/docs/miscellaneous/chrome-headless-shell>), und
  Font-Rasterung/Antialiasing können sich ändern **[Annahme]**. Konsequenz für den Cache:
  `package-lock.json` gehört mit in den Cache-Key (§2.4), damit ein Dependency-Bump den
  Cache korrekt invalidiert.

Benchmark-Methodik: Scratch-Projekt (drei Dateien: `index.ts` mit `registerRoot`,
`Root.tsx` mit einer `<Composition>` 1170×2532/30fps/300 Frames und `language`-Prop,
`Bench.tsx` mit Gradienten/Sternen/Orbs/Titel), gerendert via
`npx remotion render src/index.ts Bench out.mp4 --codec=h264 --crf=<N>`, Größen via `du -b`,
Farbmetadaten via `ffprobe`, Determinismus via `sha256sum` zweier Läufe.

---

## 2. Pipeline-Design für dieses Repo

### 2.1 Verzeichnis `SoooDreamy/remotion/`

Eigenes npm-Projekt, strikt getrennt vom Server (`SoooDreamy/server/` bleibt unberührt,
eigene `package.json`/`package-lock.json`):

```
SoooDreamy/remotion/
├── package.json            # remotion, @remotion/cli, react, react-dom — Version gepinnt
├── package-lock.json       # committen (Cache-Key + Reproduzierbarkeit)
├── remotion.config.ts      # Codec/CRF/ColorSpace-Defaults zentral
├── fonts/                  # NUR falls Text ins Video gebacken wird (§6.1) — OFL-Font + credits
├── src/
│   ├── index.ts            # registerRoot
│   ├── Root.tsx            # alle <Composition>-Registrierungen
│   ├── chapters/
│   │   ├── IntroChapter1.tsx … IntroChapterN.tsx
│   │   └── timeline.ts     # EINZIGE Quelle für Timings/Beats (speist Video UND Manifest)
│   └── export-manifests.mjs # Node-Skript: timeline.ts → beats-JSON je Kapitel (§3.6)
└── out/                    # Render-Output — gitignored, nur CI-Artefakt
```

### 2.2 Kompositionen: Sprache als Prop, nicht als Kompositions-Kopie

Eine Komposition pro Kapitel (`IntroChapter1`…`N`); DE/EN via `inputProps`
(`--props='{"language":"de"}'` bzw. Props-JSON-Datei;
<https://www.remotion.dev/docs/passing-props>). **[Gemessen]**: `remotion still … --props`
mit `{"language":"en"}` rendert korrekt den EN-Text — der Mechanismus trägt.
Kein Kompositions-Doppel, keine Drift zwischen den Sprachen.

Wichtiger Gegenvorschlag zur Diskussion (Details §6.1): Texte **gar nicht** ins Video
backen, sondern als SwiftUI-Overlay über dem Video rendern (Timecodes aus dem Manifest).
Dann kollabiert die Sprachmatrix — **ein** Render pro Kapitel statt zwei, echte Dynamic-Type-
und VoiceOver-Unterstützung, kein Font-Problem auf Linux. Sprache-per-Prop bleibt der
Fallback für Kapitel, in denen Typografie Teil des Bildes sein muss.

### 2.3 Render-Matrix

| Dimension | Empfehlung | Begründung |
|---|---|---|
| Auflösung | **eine**: 1170×2532 @ 30 fps | Basisgröße der iPhone-Portrait-Klasse; die App ist auf iPhone portrait-only (`project.yml`). `AVPlayerLayer`/`videoGravity: .resizeAspectFill` skaliert auf 2340er/2556er/2622er-Panels ohne sichtbaren Verlust bei weichem Gradient-Content **[Annahme, per Sichtprüfung auf Gerät verifizieren]**. |
| iPad | **kein eigener Render** | iPad zeigt dasselbe Video aspect-fit mit Ambient-Hintergrund (App-eigene `DreamyBackground`). Eine iPad-Matrix (Landscape + Portrait) würde Renderzeit und Budget verdoppeln für einen Zweitgeräte-Fall. |
| Codec | **HEVC (`--codec=h265`)** | Halbiert die Größe gegenüber H.264 [Gemessen, §4]; alle iOS-26-Geräte dekodieren HEVC in Hardware (HEVC-Decode seit A9/iOS 11 — **[Annahme]**, deckt jede iOS-26-fähige Hardware ab). H.264-Fallback unnötig. |
| Alpha | **nein** für Fullscreen-Cutscenes | Remotion exportiert Alpha nur als ProRes 4444 oder VP8/VP9-WebM (<https://www.remotion.dev/docs/transparent-videos>) — iOS spielt transparentes WebM nicht. Falls später Overlay-Vignetten mit Alpha gewünscht: ProRes-4444-Zwischenformat auf ubuntu rendern, auf dem macos-26-Runner nach **HEVC-with-Alpha** transkodieren (`ffmpeg -c:v hevc_videotoolbox -alpha_quality 0.75 -vtag hvc1`, nur VideoToolbox/macOS kann das; iOS ≥ 13 spielt es ab — <https://developer.apple.com/videos/play/wwdc2019/506/>). Für v1 bewusst weggelassen. |
| Farbraum | **`--color-space=bt709`** explizit | §6.2 — der 4.0-Default ist BT.601-Familie [Gemessen]. |
| Audio | **`--muted`, Videos sind stumm** | Ton kommt live aus der App-eigenen SoundEngine, gesteuert vom selben Timecode-Manifest wie die Haptik (§3.5). Löst Silent-Switch-Politik, Quiet-Hours (existiert in der App), Audio-Lizenzfragen und spart Bytes. Ohne `--muted` legt Remotion eine AAC-Spur an [Gemessen]. |

### 2.4 CI-Job-Skizze: `render-videos` auf `ubuntu-latest`

Kernidee: `actions/cache` auf einen Key aus dem Hash der Remotion-Quellen — **nur bei
Änderung wird gerendert**, sonst kommt `out/` aus dem Cache. Explizite Positivliste im
`hashFiles()` (kein Negations-Gefummel, `out/`/`node_modules/` bleiben automatisch draußen):

```yaml
render-videos:
  name: Render intro videos (Remotion)
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: actions/cache@v4
      id: video-cache
      with:
        path: SoooDreamy/remotion/out
        key: remotion-videos-v1-${{ hashFiles(
          'SoooDreamy/remotion/src/**',
          'SoooDreamy/remotion/fonts/**',
          'SoooDreamy/remotion/remotion.config.ts',
          'SoooDreamy/remotion/package-lock.json') }}
    - uses: actions/setup-node@v4
      if: steps.video-cache.outputs.cache-hit != 'true'
      with:
        node-version: 22
        cache: npm
        cache-dependency-path: SoooDreamy/remotion/package-lock.json
    - name: Install Linux deps for Chrome Headless Shell
      if: steps.video-cache.outputs.cache-hit != 'true'
      # https://www.remotion.dev/docs/miscellaneous/linux-dependencies (Ubuntu 24.04)
      run: sudo apt-get update -qq && sudo apt-get install -y --no-install-recommends
        libnss3 libdbus-1-3 libatk1.0-0 libasound2t64 libxrandr2 libxkbcommon-dev
        libxfixes3 libxcomposite1 libxdamage1 libgbm-dev libcups2 libcairo2
        libpango-1.0-0 libatk-bridge2.0-0
    - name: Render chapters (DE + EN) + manifests + filmstrips
      if: steps.video-cache.outputs.cache-hit != 'true'
      working-directory: SoooDreamy/remotion
      run: |
        npm ci
        npx remotion browser ensure
        node src/export-manifests.mjs out/
        for lang in de en; do
          for ch in 1 2 3 4 5; do
            npx remotion render src/index.ts "IntroChapter$ch" \
              "out/intro_ch${ch}_${lang}.mp4" \
              --codec=h265 --color-space=bt709 --muted \
              --props="{\"language\":\"$lang\"}"
          done
        done
        # Filmstreifen + Determinismus-Probe: siehe §5
    - name: Video budget gate (≤ 40 MB)   # §4.3 — läuft auch bei Cache-Hit
      run: |
        total=$(du -cb SoooDreamy/remotion/out/*.mp4 | tail -1 | cut -f1)
        echo "Videos gesamt: $total Bytes ($((total / 1048576)) MB)"
        test "$total" -le $((40 * 1048576))
    - uses: actions/upload-artifact@v4
      with:
        name: intro-videos
        path: SoooDreamy/remotion/out
        if-no-files-found: error
```

Muster-Quelle für den Grundaufbau: <https://www.remotion.dev/docs/ssr> („Render using
GitHub Actions"). Cache-Limits: 10 GB pro Repo — bei ≤ 40 MB Videos irrelevant
(<https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/caching-dependencies-to-speed-up-workflows>).

### 2.5 Artefakt-Übergabe an den `macos-26`-IPA-Job

**Befund `project.yml`:** Es gibt **keinen expliziten `resources:`-Block**. Beide App-Targets
(`SoooDreamy` und `SoooDreamyLite`) listen `sources: [SoooDreamy, Shared]`; XcodeGen ordnet
Dateien unter diesen Pfaden anhand der Endung der passenden Build-Phase zu — `.mp4`/`.json`
landen in *Copy Bundle Resources* (TargetSource-Verhalten,
<https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md#target-source>).
Genau so kommen heute schon `Resources/Sounds/*.caf` und die CI-gerenderten Icon-PNGs ins
Bundle.

**Kritischer Reihenfolge-Punkt:** XcodeGen scannt das Dateisystem **beim `xcodegen
generate`**. Die Videos müssen also **vor** dem Generate-Schritt liegen — nicht bloß vor
`xcodebuild`. (Der Workflow macht es bei den Icons bereits exakt so: erst
`GenerateIcon.swift`, dann `xcodegen generate`.) Einbau in `build-ipa`:

```yaml
build-ipa:
  needs: [render-videos]
  steps:
    - uses: actions/checkout@v4
    # … Xcode version, XcodeGen install, Icons rendern (unverändert) …
    - name: Inject intro videos (rendered in CI, never committed)
      uses: actions/download-artifact@v4
      with:
        name: intro-videos
        path: SoooDreamy/ios/SoooDreamy/Resources/Videos
    - name: Generate Xcode project        # unverändert — jetzt sieht xcodegen die Videos
      working-directory: SoooDreamy/ios
      run: xcodegen generate
    # … Build, Package (unverändert) …
```

Zusätzlich im *Package IPA*-Schritt (Symmetrie zur bestehenden Lite-PlugIns-Prüfung) fail-closed
verifizieren, dass die Videos wirklich im Bundle sind:
`test -f "$APP_DIR/intro_ch1_de.mp4"` (bzw. der Unterordner, je nachdem ob XcodeGen den
`Videos/`-Ordner als Group oder Folder-Reference kopiert — beim ersten Lauf prüfen und den
Pfad festnageln **[Annahme: flache Kopie, wie bei `Sounds/`]**).

Und: `SoooDreamy/ios/SoooDreamy/Resources/Videos/` in `.gitignore` aufnehmen — lokal
gerenderte Videos dürfen nie versehentlich committet werden (Philosophie-Invariante).

### 2.6 Lite-IPA: Videos weglassen

Zwei Schichten, beide umsetzen:

1. **`build-ipa-lite` lädt das Artefakt einfach nicht herunter** (kein
   `download-artifact`-Schritt, kein `needs: render-videos`) — dann existieren die Dateien
   beim `xcodegen generate` nicht und können nicht ins Bundle geraten. Der Lite-Job bleibt
   dadurch auch unabhängig vom Render-Job (Parallelität, keine neue Kritikpfad-Abhängigkeit).
2. **Explizites `excludes` im Lite-Target** (macht die Absicht im Projekt-Spec sichtbar und
   schützt gegen lokal herumliegende Dateien):

   ```yaml
   SoooDreamyLite:
     sources:
       - path: SoooDreamy
         excludes:
           - "Resources/Videos/**"
       - path: Shared
   ```

   `excludes` mit Glob-Patterns ist XcodeGen-Standard
   (<https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md#target-source>).
   Die Alternative — Build-Setting `EXCLUDED_SOURCE_FILE_NAMES` — funktioniert ebenfalls,
   ist aber unsichtbarer; ein separater „nur-Voll-Target-Resources-Ordner" wäre ein dritter
   Weg, bricht aber die heutige Ein-Pfad-Struktur. Empfehlung: `excludes`.

Der Lite-Verifikations-Schritt prüft spiegelbildlich `! -e "$APP_DIR/intro_ch1_de.mp4"`.
Konsequenz fürs App-Design: **fehlende Videos sind ein legaler Zustand** (Lite, und auch der
`simulator-screenshots`-Job rendert ohne) — die Abspielseite muss bei fehlendem Bundle-File
lautlos auf den prozeduralen Intro-Pfad zurückfallen (§3.7). Das ist kein Workaround,
sondern das Feature: Lite = prozedural-only.

---

## 3. App-Abspielseite

### 3.1 Player-Wahl

`AVPlayer` + `AVPlayerLayer` (in einem `UIViewRepresentable`) statt SwiftUI-`VideoPlayer`:
die Cutscene braucht eigenes Chrome (Skip-Button pro Kapitel, Sprach-Overlays, kein
System-Transport-UI). Bundle-MP4s per `Bundle.main.url(forResource:withExtension:)` — rein
lokal, kein Netz, kein Stalling. `AVAudioSession` bleibt unangetastet, solange Videos stumm
sind (§2.3) — der Ton kommt aus der bestehenden SoundEngine (§3.5).

### 3.2 Nahtlose Kapitel-Übergänge

Zwei Optionen, ehrlich abgewogen:

- **Pro Kapitel eine Datei + `AVQueuePlayer`** (Empfehlung): alle `AVPlayerItem`s beim Start
  in die Queue, lokale Dateien dekodieren ohne Pufferpause; `AVQueuePlayer` ist Apples
  API für sequentielles Abspielen (<https://developer.apple.com/documentation/avfoundation/avqueueplayer>).
  **[Annahme]**: an Item-Grenzen ist ein Übergang von ~1 Frame nicht hart ausschließbar.
  Gegenmittel dramaturgisch statt technisch: jedes Kapitel endet und beginnt auf demselben
  „Hold-Frame" (ruhiger Gradient) — eine etwaige Naht ist dann unsichtbar. Vorteil:
  Cache-Granularität (nur geänderte Kapitel re-rendern), Skip = `advanceToNextItem()`.
- **Eine Datei pro Sprache** (alle Kapitel konkateniert), Kapitelwechsel = Seek auf
  Manifest-Timecodes: garantiert nahtlos (eine Decoder-Session), aber jedes Detail-Tuning
  re-rendert den ganzen Film und der Render-Cache wird grobkörnig.

Preloading: erstes Item mit `player.currentItem?.preferredForwardBufferDuration` ist bei
Bundle-Dateien unnötig; wichtig ist nur, den `AVQueuePlayer` **vor** dem Sprachwahl-Gate zu
instanziieren, damit Kapitel 1 beim Fade-in bereits `readyToPlay` ist **[Annahme: bei
lokalen Dateien < 100 ms, auf Gerät messen]**.

### 3.3 Sprachwahl-Gate VOR dem ersten Video

User-Anforderung: Sprache wird zuerst gefragt — auch im Demo-Modus. Einbau:

- Neuer, bewusst minimaler `LanguageGateView` (zwei große Glas-Buttons „Deutsch/English",
  vorausgewählt nach `Locale.preferredLanguages`), montiert **vor** `CinematicIntroView`
  in `OnboardingFlowView.showsCinematic` (dort sitzt heute schon der Intro-Einstieg).
- Persistenz über die existierende Infrastruktur: `L10n.language = .de/.en`
  (`Core/L10n.swift` schreibt `sooodreamy.appLanguage` + `SharedStore.resolvedLanguage`).
  Ein eigener Gate-Flag-Key analog `CinematicIntroGate.seenKey` verhindert Wiederholung.
- Danach wählt der Player `intro_chN_\(L10n.lang).mp4`. Demo-Modus („Erst mal ansehen")
  liegt hinter dem Onboarding-Einstieg und erbt die Wahl automatisch — kein Sonderpfad.
- Das Gate selbst ist prozedural (SwiftUI), nicht Video — es muss vor dem ersten Video
  stehen und in beiden Sprachen gleichzeitig lesbar sein.

### 3.4 Skip, Reduce Motion, VoiceOver

- **Skip pro Kapitel:** dezenter Button (wie der heutige Intro-Skip), Aktion =
  `advanceToNextItem()`; letztes Kapitel → `onFinished`. Der Haptik-/Sound-Score stoppt
  beim Skip sofort mit (`CinematicHapticScore.stop()` existiert genau dafür).
- **Reduce Motion:** kein Video abspielen. Stattdessen pro Kapitel ein Standbild + Text —
  das Standbild zur Laufzeit via `AVAssetImageGenerator` aus dem gebündelten MP4 ziehen
  (Frame vom Manifest-`posterTime`), Null zusätzliche Assets. Das entspricht dem bereits
  gebauten Muster (CinematicIntroView wird unter Reduce Motion zu Crossfade-Stills).
  Eine „bewegungsreduzierte Video-Variante" würde die Render-Matrix verdoppeln — bewusst
  verworfen.
- **VoiceOver:** Kapiteltexte liegen als Strings im Manifest/L10n, nicht nur als Pixel —
  damit bleibt der Intro-Inhalt vorlesbar (heutiger prozeduraler Vorteil bleibt erhalten).

### 3.5 Ton-Politik beim First Launch

Empfehlung: **Ton an, aber unter `AVAudioSession.Category.ambient`** — dann respektiert der
Intro-Sound den Ring/Silent-Schalter und mischt sich unter fremde Wiedergabe, statt z. B.
laufende Musik zu stoppen. Genau das verlangt die HIG: im Silent-Modus sollen nur explizit
angeforderte Medien spielen; nicht-essentielle Sounds (Effekte, Soundtracks) verstummen
(<https://developer.apple.com/design/human-interface-guidelines/playing-audio>;
`ambient`-Kategorie: <https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/ambient>).
Zusätzlich: wenn `AVAudioSession.sharedInstance().isOtherAudioPlaying`, Score stumm starten
und nur ein Mute/Unmute-Toggle anbieten. Da die Videos selbst stumm sind (§2.3) und der Ton
aus der SoundEngine kommt, gelten Quiet-Hours und die bestehende Sound-Politik der App
automatisch weiter — die Cutscene bekommt keine eigene Audio-Sonderwelt.

### 3.6 Haptik: Timecode-Manifest neben dem MP4

Haptik kann nicht aus dem Video kommen — sie kommt aus einem **JSON-Manifest**, das beim
Render aus derselben TypeScript-Timeline (`src/chapters/timeline.ts`) exportiert wird wie
das Bild. Eine Quelle, zwei Ausgaben: Frames und Beats driften nie auseinander. Format,
bewusst deckungsgleich mit dem existierenden `HapticEventSpec` (t/i/s/d) der App:

```json
{
  "video": "intro_ch1_de.mp4",
  "fps": 30,
  "durationSec": 46.0,
  "posterTime": 12.5,
  "beats": [
    { "t": 8.00, "i": 1.00, "s": 0.30, "d": 0.60 },
    { "t": 8.45, "i": 0.60, "s": 0.10, "d": 0.00 }
  ],
  "cues": [
    { "t": 8.00, "id": "pairing" }
  ],
  "captions": [
    { "t": 4.0, "end": 7.5, "de": "Zwei Welten.", "en": "Two worlds." }
  ]
}
```

- `beats` spielt `CinematicHapticScore` ab; `cues` sind AppCue-IDs für die SoundEngine;
  `captions` speist SwiftUI-Text-Overlays (und VoiceOver).
- Trigger über **`AVPlayer.addBoundaryTimeObserver(forTimes:)`** auf der Player-Clock —
  Beats feuern damit korrekt auch nach Pause/Seek/Skip
  (<https://developer.apple.com/documentation/avfoundation/avplayer/addboundarytimeobserver(fortimes:queue:using:)>).
  Alternativ hätte Apple mit AHAP (`CHHapticPattern(contentsOf:)`) ein eigenes Datei-Format —
  verworfen, weil die App mit `HapticEventSpec` + `CinematicHapticScore` bereits eine
  Linux-testbare Beat-Pipeline hat und das Manifest zusätzlich Sound + Captions trägt.
- Die Manifeste sind Text → sie dürfen sogar committet werden; konsequenter ist aber, sie
  im selben CI-Schritt zu generieren wie die Videos (eine Quelle, ein Artefakt).

### 3.7 Hybrid-Dramaturgie: Was bleibt prozedural?

| Bleibt prozedural-interaktiv | Wird Video |
|---|---|
| Sprachwahl-Gate (§3.3) | Prolog-Kapitel: filmische Welten, die SwiftUI nicht im Frame-Budget schafft (Volumetrik, komplexe Blur-Stacks, viele Partikel) |
| **Der Merge-Moment** („two become one") — der haptische Höhepunkt bleibt im bestehenden `CinematicIntroView`-Renderer, weil dort Haptik, Synth-Sound und Bild aus **einer** Clock kommen und der Couple-Tint live einfärbt | Erzählende Zwischenkapitel ohne Interaktion |
| Reduce-Motion-Pfad (Stills + Text) | Feature-Vignetten (optional, später) |
| Alles nach dem Intro (Onboarding, Demo) | — |

Dramaturgie-Regel: **Video = Kino (zuschauen), prozedural = Bühne (fühlen).** Die Videos
laufen als Prolog-Kapitel; der Übergang ins bestehende `CinematicIntroView` passiert auf
einem Hold-Frame in App-Hintergrundfarbe (`#060618`-Familie), sodass Video-Ende und
prozeduraler Beginn optisch eine Einstellung sind. Der Couple-Tint — im vorgerenderten
Video prinzipiell unlösbar, da beim First Launch ohnehin noch kein Paar existiert — gehört
ausschließlich der prozeduralen Hälfte.

---

## 4. Größen-/Qualitäts-Budget

### 4.1 Messwerte

**[Gemessen]** 10-s-Komposition 1170×2532 @ 30 fps, Gradient/Sterne/Orbs-Content
(SooDreamy-typisch, dunkel, weich — kompressionsfreundlich):

| Encoding | Größe / 10 s | ≈ Bitrate |
|---|---|---|
| H.264 CRF 18 | 2,45 MB | 2,0 Mbit/s |
| H.264 CRF 23 | 1,96 MB | 1,6 Mbit/s |
| H.264 CRF 28 | 1,38 MB | 1,1 Mbit/s |
| **HEVC CRF 28** | **0,74 MB** | **0,6 Mbit/s** |

**Ehrliche Warnung:** Diese Zahlen gelten für weichen Gradient-Content. Rausch-/Grain-,
Konfetti- oder Schnellschnitt-Material kostet **Faktor 3–5** mehr **[Annahme]** —
Design-Regel für die Kompositionen: kein Filmkorn, keine Full-Frame-Partikelstürme.

### 4.2 Hochrechnung & Budget

IPA-Wachstum ≈ 1:1 zu den Video-Bytes (MP4/HEVC ist bereits komprimiert; das IPA-Zip
verkleinert nichts mehr). Szenario 5 Kapitel à 50 s, DE + EN = 500 s Material:

| Encoding | 500 s gesamt | Bewertung |
|---|---|---|
| H.264 CRF 18 | ~123 MB | inakzeptabel |
| H.264 CRF 23 | ~98 MB | inakzeptabel |
| HEVC CRF 28 | **~37 MB** | passt ins Budget |
| HEVC CRF 28, textfreie Videos (nur 1 Sprachfassung nötig, §6.1) | **~19 MB** | komfortabel |

**Empfehlung: Gesamtbudget ≤ 40 MB Videos** (Sideload-freundlich; die App ist heute
asset-arm und soll es fühlbar bleiben). HEVC ist damit gesetzt; die textfreie
Video-Strategie halbiert zusätzlich.

### 4.3 CI-Gate

Fail-closed-Step im `render-videos`-Job (läuft auch bei Cache-Hit, siehe Skizze §2.4):

```bash
total=$(du -cb SoooDreamy/remotion/out/*.mp4 | tail -1 | cut -f1)
test "$total" -le $((40 * 1048576))   # sonst exit 1 → Job rot
```

Gleichen Geist wie das 120-KB-Gate in `prepare_sounds.sh`: Budget ist Code, nicht Absicht.

---

## 5. Review-Prozess für Video-Qualität in CI

Kein Linux-Test „sieht" ein Video — deshalb produziert der Render-Job **prüfbare Neben-Artefakte**:

1. **Filmstreifen-PNGs**: pro Kapitel alle 2 s ein Still über `npx remotion still … --frame=N`
   (<https://www.remotion.dev/docs/cli/still>). **[Gemessen]**: ~1,9 s pro Still inkl.
   CLI-Start → ein 50-s-Kapitel = 25 Stills ≈ 50 s. Für die Gesamtmatrix vertretbar; wem das
   zu langsam wird, der rendert stattdessen einmal mit `--sequence` (Bildsequenz statt Video,
   Flag-Name in 4.0.512 im CLI-Quellcode verifiziert; <https://www.remotion.dev/docs/config#setimagesequence>)
   in ein Temp-Verzeichnis und behält jeden 60. Frame. Die Stills gehen als
   `intro-filmstrips`-Artefakt hoch — Agents
   und Menschen reviewen die Optik Frame für Frame, exakt wie heute die Simulator-Screenshots
   (gleiche Review-Kultur, gleicher Artefakt-Weg).

   ```bash
   for f in $(seq 0 60 1499); do   # 50 s * 30 fps, alle 2 s
     npx remotion still src/index.ts "IntroChapter$ch" \
       "strips/ch${ch}_${lang}_f$(printf %04d $f).png" \
       --frame=$f --props="{\"language\":\"$lang\"}"
   done
   ```

2. **Determinismus-Hash-Test**: ein kurzes Probe-Kapitel wird zweimal gerendert und die
   SHA-256-Hashes verglichen; Abweichung → Job rot. Fängt eingeschleppte `Math.random()`/
   `Date`-Abhängigkeiten, bevor sie den Render-Cache vergiften (Anti-Pattern-Begründung:
   <https://www.remotion.dev/docs/using-randomness>). **[Gemessen]**: auf identischer
   Umgebung sind die Hashes tatsächlich stabil — der Test ist also scharf, nicht flaky.
3. **Manifest-Kreuz-Check**: ein Node-Step validiert, dass jedes `beats.t`/`captions.t` <
   `durationSec` liegt und jede `cues.id` im AppCue-Katalog existiert (Katalog-Namen als
   Liste exportieren) — die Swift-Seite hat mit `LogicTests` bereits das Muster, Timings
   Linux-seitig zu pinnen.

---

## 6. Risiken

### 6.1 Fonts: SF Pro gibt es auf ubuntu nicht

- Chromium auf Linux rasterisiert mit dem, was da ist (DejaVu & Co.) — gebackener Text sähe
  nie aus wie die App. **SF Pro nach Linux kopieren ist keine Option**: Apples Font-Lizenz
  bindet die Nutzung an Apple-Plattformen/-Software **[Annahme zur Lizenzauslegung — vor
  jedem Abweichen den Lizenztext von developer.apple.com/fonts prüfen; Empfehlung: gar nicht
  erst versuchen]**.
- **Option A (empfohlen): typo-arme Videos.** Kein Text im Video; alle Wörter als
  SwiftUI-Overlay (`captions` im Manifest, §3.6) in der System-Schrift der App. Gewinnt
  vierfach: kein Font auf Linux nötig, **eine** Sprachfassung pro Kapitel statt zwei
  (halbes Budget, halbe Renderzeit), Dynamic Type + VoiceOver gratis, und die
  No-Binary-Philosophie bleibt unangetastet.
- **Option B (Fallback für Typo-als-Bild-Momente):** eine lizenzfreie Variable-Font (z. B.
  Inter, SIL OFL) als `woff2` in `remotion/fonts/` committen und via `@remotion/fonts`
  `loadFont()` laden (<https://www.remotion.dev/docs/fonts>, lokale Fonts seit v4.0.164).
  Ehrliche Abwägung gegen die No-Binary-Philosophie: das **ist** ein committetes Binary
  (~100–300 KB). Präzedenzfall existiert aber schon — `Resources/Sounds/*.caf` liegen im
  Repo, mit Provenienz-Ledger `sound_credits.json`. Dieselbe Disziplin anwenden:
  `font_credits.json` mit Quelle, Lizenz, SHA-256. Ein Font ist zudem Quellmaterial
  (Input des Builds), kein Build-Produkt — der Geist der Regel („keine generierten/
  undurchschaubaren Blobs") bleibt gewahrt. Trotzdem: A vor B.

### 6.2 Farbmanagement (sRGB vs. P3)

- **[Gemessen]**: Remotion 4.0 taggt Output per Default als `yuvj420p` / `bt470bg`
  (= BT.601-Familie) — auf einem iPhone-Display führt das zu sichtbar verschobenen Farben
  gegenüber den sRGB-Werten der Komposition **[Annahme zur Sichtbarkeit, auf Gerät prüfen]**.
  Der 5.0-Migrationsguide bestätigt: bisheriger Default „equivalent to bt601", künftig
  `bt709` (<https://www.remotion.dev/docs/5-0-migration>).
- Konsequenz: **immer `--color-space=bt709`** setzen. **[Gemessen]**: Flag erzeugt korrekt
  `yuv420p` + `color_space=bt709`.
- Display-P3-Export bietet Remotion nicht an (kein dokumentierter P3-Farbraum-Wert) —
  die Videos sind sRGB/Rec.709. Für dunkle Aurora-Paletten reicht das; die satten
  P3-Momente gehören ohnehin der prozeduralen Hälfte (SwiftUI rendert wide-gamut nativ).
  Farb-Abnahme läuft über die Filmstreifen (§5) plus einmalige Gerät-Sichtprüfung.

### 6.3 CI-Minuten

- Rendern auf `ubuntu-latest` = 1×-Multiplikator; `macos-26` = 10×
  (<https://docs.github.com/en/billing/managing-billing-for-github-actions/about-billing-for-github-actions>).
  Der Render-Job kostet dank Cache nur bei Remotion-Änderungen (~20–50 min Linux-Minuten je
  nach vCPU-Zahl, §1.4); der macos-Job wächst nur um Sekunden (Artefakt-Download + Kopie).
- Wichtig: `build-ipa` bekommt mit `needs: render-videos` eine neue serielle Abhängigkeit.
  Bei Cache-Hit ist der Render-Job in < 1 min durch; bei Cache-Miss verlängert sich die
  IPA-Pipeline um die Renderzeit. Wer das nicht will, splittet später auf einen separaten
  Workflow mit committetem Cache-Warmup — für v1 unnötige Komplexität.

### 6.4 Flakiness

| Risiko | Gegenmaßnahme |
|---|---|
| Chrome-Headless-Shell-Download schlägt fehl | dedizierter `npx remotion browser ensure`-Step (<https://www.remotion.dev/docs/cli/browser/ensure>) — Fehler fällt früh und eindeutig, nicht mitten im Render; optional `node_modules/.remotion` mit in einen Cache legen |
| Fehlende Linux-Libs nach Runner-Image-Update | expliziter `apt install`-Step (§2.4) statt Vertrauen aufs Image |
| `delayRender()`-Timeouts (Fonts/Assets) | keine Netz-Assets in Kompositionen (alles lokal im remotion/-Projekt); Timeout-Fehler sind dann deterministisch statt sporadisch |
| OOM bei Parallel-Rendering | Default-Concurrency (halbe Kernzahl) belassen; 2-vCPU-Runner rendert seriell — langsam, aber stabil |
| Cache-Poisoning durch nichtdeterministische Comps | Determinismus-Hash-Test (§5) bricht den Build, bevor ein kaputter Render im Cache landet |
| Artefakt-Größenlimits | irrelevant bei ≤ 40 MB + Filmstrips; Artefakte leben nur innerhalb des Workflow-Laufs |
| Remotion-Upgrade ändert Pixel-Output | Version gepinnt; `package-lock.json` im Cache-Key → Upgrade = bewusster Re-Render + Filmstrip-Review |

### 6.5 Rest-Risiken ohne technische Lösung (benannt, akzeptiert)

- **Couple-Tint im Video**: unlösbar vorgerendert — per Design der prozeduralen Hälfte
  zugewiesen (§3.7). Beim First Launch existiert noch kein Paar; der Konflikt ist theoretisch.
- **`aspectFill`-Beschnitt** auf abweichenden Panel-Seitenverhältnissen (19.5:9 vs. neuere
  Panels): Kompositionen brauchen eine Safe-Area-Disziplin (nichts Wichtiges in die äußeren
  ~6 % **[Annahme, auf Geräten verifizieren]**).
- **Lite/Fallback-Pfad muss gepflegt bleiben**: Da fehlende Videos legal sind (§2.6), gibt es
  dauerhaft zwei Intro-Erlebnisse (Video-Prolog vs. rein prozedural). Das ist gewollt, kostet
  aber Test-Matrix: beide Pfade gehören in die Screenshot-/Review-Routine.

---

## Anhang: Erst-Implementierungs-Reihenfolge (kompakt)

1. `SoooDreamy/remotion/` mit einem einzigen Probe-Kapitel + Manifest-Export anlegen;
   `.gitignore`-Einträge (`remotion/out/`, `ios/SoooDreamy/Resources/Videos/`).
2. `render-videos`-Job (§2.4) inkl. Budget-Gate, Filmstrips, Determinismus-Test.
3. `project.yml`: `excludes` im Lite-Target (§2.6); `build-ipa`: `needs` + Download vor
   `xcodegen generate` (§2.5); Bundle-Verifikation in beiden Package-Steps.
4. App-Seite: `LanguageGateView` → `IntroMovieView` (AVQueuePlayer + Manifest-Observer +
   Skip + Reduce-Motion-Stills + Fallback auf `CinematicIntroView` bei fehlenden Dateien).
5. Erst dann: echte Kapitel-Dramaturgie in Remotion bauen, Filmstrip-Reviews als Taktgeber.

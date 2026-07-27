# ECLIPSE Trailer — Remotion Tech-Bauplan (4K60, headless, ohne GPU)

**Ziel:** 30-Sekunden-Trailer, 3840×2160 @ 60 fps = **1800 Frames**, gerendert headless auf der Linux-VM (kein GPU, Chrome unter `/usr/local/bin/google-chrome`, Node v22.14, ffmpeg 6.1). Finale Datei: `ECLIPSE-Trailer-4K.mp4` im Repo-Root (`/home/ubuntu/project-eclipse/`), **< 95 MB** (GitHub-Limit 100 MB), H.264 High Profile, ~18–22 Mbps, `yuv420p`, `+faststart`.

**Verifizierter Stand (Juli 2026):** Remotion **4.0.497** (Release 23.07.2026). Alle `remotion`/`@remotion/*`-Pakete müssen **exakt dieselbe Version** haben (kein `^`). React 19 wird ab Remotion 4.0.236 voll unterstützt.

---

## 1. Projekt-Struktur + Dependencies

Eigenständiges npm-Paket unter `/home/ubuntu/project-eclipse/trailer/` — komplett unabhängig vom Gradle-Build und vom Vite-Frontend im Repo-Root (eigene `package.json`, eigenes `node_modules`, eigene `tsconfig.json`).

```
/home/ubuntu/project-eclipse/trailer/
├── package.json
├── tsconfig.json
├── remotion.config.ts            # Render-Defaults (gl, browser, jpeg, concurrency …)
├── .gitignore                    # node_modules/, out/, .remotion/
├── public/                       # → staticFile()-Root
│   ├── audio/
│   │   ├── music.wav             # aus OGG konvertiert, 48 kHz stereo PCM (siehe §3)
│   │   └── doom_kick.wav         # SFX-Einzeltreffer
│   ├── fonts/
│   │   └── Orbitron-Bold.woff2   # (Beispiel) lokale Fonts, KEIN Netz-Fetch
│   └── stills/
│       ├── scene01_statue.png    # 1920×1080-Stills (werden 2× skaliert, §6)
│       ├── scene02_armor.png
│       └── …
├── src/
│   ├── index.ts                  # registerRoot(RemotionRoot)
│   ├── Root.tsx                  # <Composition id="EclipseTrailer" …/>
│   ├── Trailer.tsx               # Szenen-Orchestrierung (TransitionSeries)
│   ├── scenes/
│   │   ├── S01_ColdOpen.tsx
│   │   ├── S02_Oxidation.tsx
│   │   ├── S03_Statue.tsx
│   │   ├── S04_DrPepper.tsx
│   │   ├── S05_DoomKick.tsx
│   │   └── S06_TitleCard.tsx
│   ├── components/
│   │   ├── KenBurnsStill.tsx     # <Img> + interpolierte transform
│   │   ├── GlowOverlay.tsx       # radial-gradient statt CSS-blur (§6)
│   │   └── TitleText.tsx
│   ├── audio/
│   │   └── TrailerAudio.tsx      # Musik + SFX, volume-Envelopes
│   └── lib/
│       ├── fonts.ts              # loadFont()-Aufrufe (Modul-Ebene!)
│       ├── timings.ts            # SCENE_DURATIONS, Frame-Konstanten
│       └── ease.ts               # gemeinsame Easing-/Spring-Configs
└── out/                          # Test-Renders & Stills (gitignored)
```

### package.json

```json
{
  "name": "eclipse-trailer",
  "private": true,
  "scripts": {
    "studio": "remotion studio",
    "still": "remotion still src/index.ts EclipseTrailer",
    "render:test": "remotion render src/index.ts EclipseTrailer out/test_0-120.mp4 --frames=0-120",
    "render:final": "remotion render src/index.ts EclipseTrailer ../ECLIPSE-Trailer-4K.mp4"
  },
  "dependencies": {
    "@remotion/cli": "4.0.497",
    "@remotion/fonts": "4.0.497",
    "@remotion/media": "4.0.497",
    "@remotion/transitions": "4.0.497",
    "react": "19.2.0",
    "react-dom": "19.2.0",
    "remotion": "4.0.497"
  },
  "devDependencies": {
    "@types/react": "19.2.0",
    "@types/react-dom": "19.2.0",
    "typescript": "^5.9.2"
  }
}
```

Hinweise:

- **Exakte, identische Versionen** für alle Remotion-Pakete (offizielle Empfehlung; `npx remotion versions` prüft das). 4.0.497 ist die letzte 4.x-Version per 23.07.2026; falls beim Setup neuer: `npm view remotion version` und alle vier Pakete gemeinsam anheben.
- `@remotion/media` liefert die aktuellen `<Audio>`/`<Video>`-Tags (Mediabunny/WebCodecs-basiert) — 2026 die offizielle Empfehlung für neuen Code. Wir brauchen daraus nur `<Audio>`. `<OffthreadVideo>` wird **nicht** benötigt (keine Videoquellen, nur Stills + Audio).
- `@remotion/transitions` für Szenen-Blenden (§2), `@remotion/fonts` für headless-sicheres Font-Loading (§6).
- Node v22.14 ist voll kompatibel. ffmpeg muss **nicht** installiert werden — Remotion bringt sein eigenes ffmpeg mit; das System-ffmpeg 6.1 nutzen wir nur für Audio-Konvertierung und Nachbearbeitung.

### remotion.config.ts (Render-Defaults, damit CLI-Zeilen kurz bleiben)

```ts
import {Config} from '@remotion/cli/config';

Config.setChromiumOpenGlRenderer('swangle');                  // Software-GL, §4
Config.setBrowserExecutable('/usr/local/bin/google-chrome');  // System-Chrome statt Download
Config.setVideoImageFormat('jpeg');                           // §4
Config.setJpegQuality(95);
Config.setConcurrency(3);                                     // §4 — an RAM anpassen!
Config.setTimeoutInMilliseconds(180000);
Config.setCodec('h264');
Config.setPixelFormat('yuv420p');
```

Remotion lädt standardmäßig eine eigene „Chrome Headless Shell" nach `~/.remotion` herunter. Auf einer VM mit eingeschränktem Egress schlägt das fehl → `setBrowserExecutable` (bzw. `--browser-executable`) auf das vorhandene System-Chrome zeigen lassen. Alternativ einmalig `npx remotion browser ensure` versuchen.

---

## 2. Root / Composition-Setup

```tsx
// src/index.ts
import {registerRoot} from 'remotion';
import {RemotionRoot} from './Root';
registerRoot(RemotionRoot);
```

```tsx
// src/Root.tsx
import {Composition} from 'remotion';
import {Trailer} from './Trailer';

export const RemotionRoot: React.FC = () => (
  <Composition
    id="EclipseTrailer"
    component={Trailer}
    durationInFrames={1800}   // 30 s × 60 fps
    fps={60}
    width={3840}
    height={2160}
  />
);
```

### Szenen-Orchestrierung: TransitionSeries — **ja**

Für einen Trailer mit 5–6 Szenen und Überblendungen ist `<TransitionSeries>` aus `@remotion/transitions` die richtige Wahl (statt manuell überlappender `<Sequence>`-Offsets):

```tsx
// src/Trailer.tsx
import {AbsoluteFill} from 'remotion';
import {TransitionSeries, linearTiming} from '@remotion/transitions';
import {fade} from '@remotion/transitions/fade';
import {TrailerAudio} from './audio/TrailerAudio';

const X = 20; // Blenden-Dauer in Frames (~0,33 s)

export const Trailer: React.FC = () => (
  <AbsoluteFill style={{backgroundColor: '#000'}}>
    <TransitionSeries>
      <TransitionSeries.Sequence durationInFrames={300}>
        <S01_ColdOpen />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={fade()}
        timing={linearTiming({durationInFrames: X})}
      />
      <TransitionSeries.Sequence durationInFrames={320}>
        <S02_Oxidation />
      </TransitionSeries.Sequence>
      {/* … weitere Szenen … */}
    </TransitionSeries>
    <TrailerAudio />
  </AbsoluteFill>
);
```

**Wichtigste Rechenregel:** Transitions **überlappen** die angrenzenden Sequenzen. Gesamtdauer = Σ(Sequenz-Dauern) − Σ(Transition-Dauern). Bei 6 Szenen mit 5 Blenden à 20 Frames müssen die Sequenzen zusammen 1800 + 100 = **1900** Frames ergeben. Diese Invariante als Konstante in `lib/timings.ts` halten und mit einer Assertion prüfen:

```ts
// lib/timings.ts
export const FPS = 60;
export const TOTAL = 1800;
export const T = 20; // transition frames
export const SCENES = [300, 320, 320, 320, 320, 320]; // Σ = 1900
console.assert(SCENES.reduce((a, b) => a + b, 0) - (SCENES.length - 1) * T === TOTAL);
```

- Harte Schnitte (kein Overlap): einfach zwei `TransitionSeries.Sequence` **ohne** `Transition` dazwischen — oder klassische `<Sequence from={...} durationInFrames={...}>`.
- Innerhalb einer Szene liefert `useCurrentFrame()` den **szenenlokalen** Frame (beginnt bei 0) — alle Animationen szenenintern rechnen, nie gegen den globalen Frame.
- `useVideoConfig()` für `fps`/`width`/`height` statt hartkodierter Zahlen in Komponenten.

---

## 3. Asset-Pipeline

### Stills (PNG 1920×1080)

- Alle Bilder nach `public/stills/`, Referenz **ausschließlich** über `staticFile('stills/scene01_statue.png')`.
- **Immer `<Img>` aus `remotion`**, nie natives `<img>` — `<Img>` blockiert den Frame via internem `delayRender()`, bis das Bild geladen **und dekodiert** ist → frame-perfekt, keine leeren/halb geladenen Frames im Export.

```tsx
import {Img, staticFile, useCurrentFrame, interpolate} from 'remotion';

export const KenBurnsStill: React.FC<{src: string; zoomFrom: number; zoomTo: number; frames: number}> =
  ({src, zoomFrom, zoomTo, frames}) => {
    const f = useCurrentFrame();
    const scale = interpolate(f, [0, frames], [zoomFrom, zoomTo], {
      extrapolateLeft: 'clamp',
      extrapolateRight: 'clamp',
    });
    return (
      <Img
        src={staticFile(src)}
        style={{width: '100%', height: '100%', objectFit: 'cover', transform: `scale(${scale})`}}
      />
    );
  };
```

- 1080p-Stills auf der 4K-Leinwand werden 2× hochskaliert (Chrome skaliert bilinear — für Screenshots/Renders okay, aber weich). Wer knackige Kanten will: Assets vorab auf 3840×2160 hochrechnen (`ffmpeg -i in.png -vf "scale=3840:2160:flags=lanczos" out.png`) oder von vornherein 4K-Screenshots ziehen. Für Ken-Burns-Zooms > 1.0 ohnehin größere Quellbilder verwenden, sonst wird sichtbar interpoliert.

### Audio: OGG → **WAV** (Empfehlung)

Die Quell-OGGs (Vorbis) vor dem Einbinden konvertieren. Rangfolge der Zielformate:

1. **WAV (PCM 48 kHz, 16 bit, stereo) — empfohlen.** Wird von allen drei relevanten Decodern garantiert verstanden (Chrome/HTMLAudio im Studio, WebCodecs/Mediabunny beim `@remotion/media`-Render-Pfad, ffmpeg beim finalen Mux). Lossless → keine doppelte verlustbehaftete Kette (Vorbis→AAC wäre 2× lossy, Vorbis→PCM→AAC nur 1×). Größe egal: liegt nur in `public/`, landet nicht im MP4-Repo-Artefakt (dort wird ohnehin neu AAC-enkodiert). 30 s ≈ 5,8 MB.
2. **M4A/AAC (256 kbps)** — ebenfalls sicher, falls WAV-Dateigröße im Repo stört.
3. OGG direkt: funktioniert in Chrome/Mediabunny meist, ist aber der am wenigsten garantierte Pfad — nicht riskieren.

```bash
ffmpeg -i music.ogg      -ar 48000 -ac 2 -c:a pcm_s16le trailer/public/audio/music.wav
ffmpeg -i doom_kick.ogg  -ar 48000 -ac 2 -c:a pcm_s16le trailer/public/audio/doom_kick.wav
```

### Einbindung, Volume-Envelopes, Trim

`<Audio>` aus `@remotion/media` (aktuelle Empfehlung; fällt bei Decode-Problemen automatisch auf den klassischen `remotion`-Pfad zurück):

```tsx
// src/audio/TrailerAudio.tsx
import {Sequence, staticFile, interpolate} from 'remotion';
import {Audio} from '@remotion/media';
import {TOTAL} from '../lib/timings';

export const TrailerAudio: React.FC = () => (
  <>
    <Audio
      src={staticFile('audio/music.wav')}
      trimBefore={0}          // Trim in FRAMES der Composition-fps (60): 120 = 2 s
      trimAfter={TOTAL}
      volume={(f) =>
        interpolate(f, [0, 60, TOTAL - 120, TOTAL], [0, 1, 1, 0], {
          extrapolateLeft: 'clamp',
          extrapolateRight: 'clamp',
        })
      }
    />
    {/* DOOM-Kick punktgenau bei Frame 1140 */}
    <Sequence from={1140}>
      <Audio src={staticFile('audio/doom_kick.wav')} volume={0.9} />
    </Sequence>
  </>
);
```

- **`volume`-Callback:** `(frame) => number` — `frame` ist relativ zum Audio-Start (Frame 0 = erster hörbarer Frame, Trim schon abgezogen). Werte 0–1; >1 wird verstärkt. Immer mit `clamp` interpolieren.
- **Trim:** `trimBefore` / `trimAfter` in **Frames** (bei fps=60: 1 s = 60). Die alten Namen `startFrom`/`endAt` sind seit **4.0.319 deprecated** (funktionieren noch, aber nicht mit den neuen mischen) — nur noch `trimBefore`/`trimAfter` verwenden.
- Audio-Endcodierung ins MP4 steuert der Render: `--audio-codec=aac --audio-bitrate=320k` (§7).

---

## 4. Performance ohne GPU

### `--gl=swangle`

Für Maschinen **ohne GPU** ist 2026 in Remotion 4.x **`swangle`** der richtige Wert (= ANGLE mit SwiftShader-Backend; expandiert zu `--use-gl=angle --use-angle=swiftshader`). Es ist der Default auf AWS Lambda und die offizielle Empfehlung für GPU-lose Maschinen. `angle`/`angle-egl` sind für Maschinen **mit** GPU; nacktes `swiftshader` ist der Legacy-Weg. (Remotion 5.0 wird auf `angle` + automatischem SwiftShader-Fallback umstellen — für 4.x explizit `swangle` setzen.)

### Concurrency = RAM-Frage

Jeder Concurrency-Slot ist ein eigener Chrome-Tab, der eine volle 3840×2160-Seite rastert. Realistischer Bedarf pro Tab bei diesem Inhalt (Stills + Text + Gradients): **1–2 GB RSS**. Faustregel:

```
concurrency = min( CPU-Kerne / 2 , floor(freies RAM in GB / 2) )
```

- 8 GB VM → `--concurrency=2`
- 16 GB VM → `--concurrency=3` bis `4`
- Default von Remotion ist die Hälfte der Kerne — bei 4K **nicht** blind übernehmen, sonst OOM-Kill mitten im Render. Vor dem Finalrender `free -h` prüfen und beim 120-Frame-Test `htop` mitlaufen lassen.

### `--timeout`

Default 30 000 ms für `delayRender()`-Handles. Software-Rasterung bei 4K kann einzelne Frames (Font-Load, großes PNG-Decode beim Szenenwechsel) über die Grenze schieben → **`--timeout=180000`** setzen. Kostet nichts, verhindert Flakes.

### Frame-Format: JPEG statt PNG

- `--image-format=jpeg` (Default für Video-Renders) mit **`--jpeg-quality=95`**. PNG-Encoding eines 4K-Frames ist CPU-seitig ein Vielfaches teurer und bringt vor der H.264-Quantisierung praktisch nichts. JPEG q95 ist visuell transparent gegenüber dem, was x264 bei 20 Mbps ohnehin wegwirft.
- PNG nur für `remotion still`-Prüfbilder (dort will man Pixel-Wahrheit).

### x264-Settings

- `--codec=h264` (Default-MP4-Pfad, Remotion muxt mit eingebautem ffmpeg).
- **Bitrate statt CRF für den Finalrender:** `--video-bitrate=20M` gibt eine planbare Dateigröße: (20 + 0,32) Mbps × 30 s / 8 ≈ **76 MB** — sicher unter 95 MB. CRF (`--crf=17`) liefert konstante Qualität, aber unvorhersehbare Größe (bei kontrastreichen 4K60-Motion-Graphics kann CRF 17 > 25 Mbps ausschlagen). `--crf` und `--video-bitrate` schließen sich gegenseitig aus.
- `--x264-preset=slow` für den Finalrender (bessere Kompression pro Bit; Encode ist bei diesem Workload nicht der Flaschenhals — das Rastern ist es). Für Testrenders `medium` lassen.
- `--pixel-format=yuv420p` (Default, trotzdem explizit setzen — Kompatibilitätsanker).
- H.264-Level: 4K60 erfordert **Level 5.2** — x264 wählt das automatisch korrekt; bei der ffmpeg-Nachbearbeitung (§7) explizit `-level:v 5.2 -profile:v high` setzen.

### Renderzeit: Schätzung + Messung

Erwartung für DOM/CSS-Inhalte (Stills, Text, Gradients, **kein** Blur) mit swangle @ 4K, JPEG-Capture, `--concurrency=3` auf einer 8-Kern-VM:

- ~0,4–1,2 s/Frame effektiv → **1800 Frames ≈ 15–45 min**, realistischer Mittelwert **~25–35 min**.
- Mit CSS-`filter: blur()` in Szenen kann das auf 2–4 s/Frame explodieren (→ §6 vermeiden) = 1–2 h.

**Messen statt raten** — 121-Frame-Testrender stoppen und hochrechnen:

```bash
time npx remotion render src/index.ts EclipseTrailer out/test_0-120.mp4 --frames=0-120
# Hochrechnung: T_final ≈ (gemessene Sekunden / 121) × 1800  (+ ~1 min Encode/Mux-Overhead)
```

Alternativ misst `npx remotion benchmark src/index.ts EclipseTrailer` mehrere Concurrency-Werte automatisch — nützlich, um das Optimum für die konkrete VM zu finden.

---

## 5. Determinismus (reproduzierbare Frames)

Jeder Frame wird isoliert und potenziell parallel/wiederholt gerendert. Alles, was zwischen zwei Evaluationen desselben Frames unterschiedliche Werte liefert, erzeugt Flicker oder nicht-reproduzierbare Renders.

- **`random(seed)` aus `remotion`** statt `Math.random()`. Deterministische PRNG-Funktion: gleicher Seed → gleiche Zahl, auf jedem Worker, in jedem Prozess. Pro Verwendungszweck eigene Seeds (`random('spark-' + i)`). Für animiertes Rauschen: Seed vom Frame ableiten (`random('flicker-' + frame)`).
- **Kein `Date.now()`, `new Date()`, `performance.now()`** — Zeit existiert nur als `useCurrentFrame()`. Auch keine frame-übergreifenden Mutationen in `useRef`/Modul-State als Animationsquelle.
- **`interpolate()` immer clampen**, sonst laufen Werte vor/nach dem Keyframe-Fenster linear weiter (Opacity > 1, Positionen im Off):

```ts
interpolate(frame, [0, 30], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})
```

- **`spring()` korrekt füttern:** `spring({frame, fps, config: {damping: 200}})` — `fps` **aus `useVideoConfig()`**, nie hartkodiert; sonst ändert sich das Timing, falls die Composition-fps je angepasst wird. Springs sind deterministisch (reine Funktion von frame/fps/config) — unbedenklich.
- Keine Netz-Fetches zur Renderzeit (Fonts, Bilder, Daten) — alles über `public/` + `staticFile()` bündeln. Netz = nichtdeterministisch + potenziell vom VM-Egress blockiert.

---

## 6. Anti-Fallstricke

### Font-Loading: `@remotion/fonts` + `staticFile()` — der zuverlässige Weg headless

- **Empfohlen:** Font-Dateien (woff2) in `public/fonts/`, laden via `loadFont()` aus `@remotion/fonts` — **auf Modul-Ebene, nie im Component-Body**. `loadFont()` blockiert den Render intern via `delayRender()`, bis der Font wirklich registriert ist → garantiert kein Frame mit Fallback-Font, kein Netzzugriff:

```ts
// src/lib/fonts.ts  (aus Root.tsx importieren)
import {loadFont} from '@remotion/fonts';
import {staticFile} from 'remotion';

loadFont({family: 'Orbitron', url: staticFile('fonts/Orbitron-Bold.woff2'), weight: '700'});
```

- `@fontsource`-Imports (CSS `@font-face`, von Webpack gebündelt) funktionieren auch offline, aber die Font-Bereitschaft ist **nicht** an `delayRender()` gekoppelt — theoretisches Risiko, dass allererste Frames mit Fallback-Font rastern. Bei einem Trailer, wo Frame 0 sichtbar ist: `loadFont()` nehmen.
- `@remotion/google-fonts` lädt zur Renderzeit vom Google-CDN — auf einer Egress-beschränkten VM tabu.

### `<Img>` statt `<img>`

Immer `<Img>` aus `remotion` (siehe §3) — wartet auf Laden **und** Decode pro Frame. Natives `<img>` kann im Headless-Render leere erste Frames produzieren. Gleiches Prinzip: kein CSS `background-image` für inhaltstragende Bilder (kein Load-Blocking) — nur für dekorative Gradients okay.

### `<OffthreadVideo>` / `<Video>`: nicht nötig

Der Trailer besteht aus Stills + Audio. Keine Video-Tags importieren — das vermeidet den kompletten Video-Extraktions-Pfad und dessen Speicher-/Zeitkosten.

### CSS-`filter` bei 4K: Blur ist Gift

Ohne GPU rastert SwiftShader/Skia jeden `filter: blur()` als Full-Res-Gauß auf der CPU — bei 3840×2160 pro Frame teils Sekunden. Ebenso teuer: `backdrop-filter` (komplett verbieten), große `box-shadow`-Radien, `drop-shadow()`.

Alternativen, praktisch gratis:

1. **Vorgerenderte Glow-PNGs**: Glow/Bloom einmal in einem Bildeditor oder via ffmpeg/ImageMagick baken, als transparentes PNG mit `<Img>` + `opacity`/`transform` animieren.
2. **`radial-gradient`** für weiche Lichtscheine/Vignetten: `background: radial-gradient(circle at 50% 40%, rgba(255,120,0,.55), transparent 60%)` — rastert billig.
3. **Blur-Downscale-Trick**, falls echter Blur unvermeidbar: kleines Element (z. B. 480×270) blurren und per `transform: scale(8)` hochziehen — Blur-Kosten sinken quadratisch mit der Fläche.

### `will-change`: weglassen

Bringt in Remotion nichts — es gibt keine Compositor-Animation zwischen Frames; jeder Frame wird komplett neu gerastert und geschreenshottet. `will-change` erzeugt nur zusätzliche Layer und RAM-Druck pro Tab. Dasselbe gilt für `translateZ(0)`-Hacks.

### `contain`: kann, muss nicht

`contain: layout paint` auf Szenen-Wrappern schadet nicht und kann Skias Invalidierung minimal entlasten, aber da ohnehin pro Frame der volle Viewport geschossen wird, ist der Effekt vernachlässigbar. Keine Zeit hineinstecken; Performance-Hebel sind Blur-Vermeidung und Concurrency/RAM.

### Sonstiges

- Immer `<AbsoluteFill>` mit explizitem `backgroundColor` als Wurzel — sonst transparente Pixel, die im JPEG-Capture-Pfad schwarz werden können, im `still`-PNG aber transparent sind (verwirrende Diffs).
- Sub-Pixel-Text-Animationen (`translateY` mit Bruchpixeln) bei 4K okay, aber `letter-spacing`-Animationen vermeiden (Layout-Thrash pro Frame).

---

## 7. Render-Kommandos

Alle Kommandos aus `/home/ubuntu/project-eclipse/trailer/`. Da `remotion.config.ts` (§1) `gl`, Browser, JPEG, Concurrency und Timeout schon setzt, sind die Flags hier zur Dokumentation trotzdem voll ausgeschrieben — CLI-Flags überstimmen die Config.

### (a) Einzel-Frame-Prüfbilder als PNG (`remotion still`)

```bash
npx remotion still src/index.ts EclipseTrailer out/still_0000.png --frame=0    --image-format=png --gl=swangle --browser-executable=/usr/local/bin/google-chrome --timeout=180000
npx remotion still src/index.ts EclipseTrailer out/still_0900.png --frame=900  --image-format=png --gl=swangle --browser-executable=/usr/local/bin/google-chrome --timeout=180000
npx remotion still src/index.ts EclipseTrailer out/still_1799.png --frame=1799 --image-format=png --gl=swangle --browser-executable=/usr/local/bin/google-chrome --timeout=180000
```

Ideal für Typo-/Layout-Checks pro Szene, bevor ein einziger Video-Frame gerendert wird. Erster Frame (0), Szenen-Mitten und letzter Frame (1799) prüfen.

### (b) 120-Frame-Testrender (2 s, mit Zeitmessung)

```bash
time npx remotion render src/index.ts EclipseTrailer out/test_0-120.mp4 \
  --frames=0-120 \
  --gl=swangle --browser-executable=/usr/local/bin/google-chrome \
  --concurrency=3 --timeout=180000 \
  --image-format=jpeg --jpeg-quality=95 \
  --codec=h264 --crf=17 --pixel-format=yuv420p
```

Danach: Sichtprüfung + Hochrechnung `T_final ≈ (t/121) × 1800`. Bei RAM-Druck (htop) `--concurrency=2`.

### (c) Finaler 1800-Frame-Render mit Audio → Repo-Root

```bash
npx remotion render src/index.ts EclipseTrailer /home/ubuntu/project-eclipse/ECLIPSE-Trailer-4K.mp4 \
  --gl=swangle --browser-executable=/usr/local/bin/google-chrome \
  --concurrency=3 --timeout=180000 \
  --image-format=jpeg --jpeg-quality=95 \
  --codec=h264 --video-bitrate=20M --x264-preset=slow --pixel-format=yuv420p \
  --audio-codec=aac --audio-bitrate=320k
```

Erwartete Größe: (20 + 0,32) Mbps × 30 s / 8 ≈ **76 MB**. Obergrenze für < 95 MB wäre ~24,5 Mbps Gesamtbitrate — 20M lässt bewussten Puffer.

### (d) ffprobe-Verifikation

```bash
ffprobe -v error \
  -select_streams v:0 -show_entries stream=codec_name,profile,level,width,height,r_frame_rate,pix_fmt \
  -show_entries format=duration,size,bit_rate \
  -of default=noprint_wrappers=1 \
  /home/ubuntu/project-eclipse/ECLIPSE-Trailer-4K.mp4
```

Soll-Werte: `codec_name=h264`, `profile=High`, `level=52`, `width=3840`, `height=2160`, `r_frame_rate=60/1`, `pix_fmt=yuv420p`, `duration=30.0…`, `size<99614720` (95 MiB), `bit_rate≈20–22M`. Größen-Gate als Shell-Check:

```bash
[ "$(stat -c%s /home/ubuntu/project-eclipse/ECLIPSE-Trailer-4K.mp4)" -lt 99614720 ] && echo "OK <95MiB" || echo "ZU GROSS"
```

**`+faststart` sicherstellen** (moov-Atom vor mdat; verlustfreier Remux, dauert Sekunden):

```bash
ffmpeg -v error -i ECLIPSE-Trailer-4K.mp4 -c copy -movflags +faststart ECLIPSE-Trailer-4K.faststart.mp4 \
  && mv ECLIPSE-Trailer-4K.faststart.mp4 ECLIPSE-Trailer-4K.mp4
```

### Nachbearbeitung, falls Datei > 95 MB: 2-Pass-Re-Encode

Ziel ~85 MB gesamt → Videobudget ≈ (85 MiB × 8 / 30 s) − 0,32 Mbps ≈ **22 Mbps**; hier konservativ 20M:

```bash
cd /home/ubuntu/project-eclipse
ffmpeg -y -i ECLIPSE-Trailer-4K.mp4 \
  -c:v libx264 -profile:v high -level:v 5.2 -preset slow \
  -b:v 20M -maxrate 24M -bufsize 40M -pix_fmt yuv420p \
  -pass 1 -an -f null /dev/null
ffmpeg -y -i ECLIPSE-Trailer-4K.mp4 \
  -c:v libx264 -profile:v high -level:v 5.2 -preset slow \
  -b:v 20M -maxrate 24M -bufsize 40M -pix_fmt yuv420p \
  -pass 2 -c:a copy -movflags +faststart ECLIPSE-Trailer-4K.2pass.mp4
mv ECLIPSE-Trailer-4K.2pass.mp4 ECLIPSE-Trailer-4K.mp4
rm -f ffmpeg2pass-0.log ffmpeg2pass-0.log.mbtree
```

(Doppel-Encode kostet minimal Qualität — der bessere Weg ist, gleich mit `--video-bitrate=20M` zu rendern, dann entfällt dieser Schritt fast immer.)

---

## 8. Fallback-Plan: 4K60 zu langsam/instabil → kleiner rendern + hochskalieren

Composition bleibt 3840×2160; Remotion rendert mit **`--scale`** verkleinert (Chrome-Tab wird kleiner → weniger RAM, ~4× weniger Rasterarbeit bei 0.5):

```bash
# Variante A: 1920×1080 @ 60 (Faktor 0.5 → sauber ganzzahlig, ~4× schneller)
npx remotion render src/index.ts EclipseTrailer out/ECLIPSE-Trailer-2K.mp4 \
  --scale=0.5 \
  --gl=swangle --browser-executable=/usr/local/bin/google-chrome \
  --concurrency=4 --timeout=180000 \
  --image-format=jpeg --jpeg-quality=95 \
  --codec=h264 --crf=14 --x264-preset=slow --pixel-format=yuv420p \
  --audio-codec=aac --audio-bitrate=320k
```

CRF 14 statt Bitrate: das Zwischenergebnis soll möglichst verlustarm sein (Größe egal, wird eh re-enkodiert).

**Hochskalieren** — bevorzugt `zscale` (libzimg, präziseres Resampling & Dithering; in Ubuntus ffmpeg 6.1 einkompiliert), sonst klassisches `scale` mit Lanczos:

```bash
# bevorzugt: zscale (Spline36 ≈ Lanczos-Qualität, weniger Ringing) + Dithering
ffmpeg -y -i out/ECLIPSE-Trailer-2K.mp4 \
  -vf "zscale=w=3840:h=2160:filter=spline36:dither=error_diffusion" \
  -c:v libx264 -profile:v high -level:v 5.2 -preset slow \
  -b:v 20M -maxrate 24M -bufsize 40M -pix_fmt yuv420p \
  -c:a copy -movflags +faststart \
  /home/ubuntu/project-eclipse/ECLIPSE-Trailer-4K.mp4

# Fallback ohne libzimg:
ffmpeg -y -i out/ECLIPSE-Trailer-2K.mp4 \
  -vf "scale=3840:2160:flags=lanczos+accurate_rnd+full_chroma_int" \
  -c:v libx264 -profile:v high -level:v 5.2 -preset slow \
  -b:v 20M -maxrate 24M -bufsize 40M -pix_fmt yuv420p \
  -c:a copy -movflags +faststart \
  /home/ubuntu/project-eclipse/ECLIPSE-Trailer-4K.mp4
```

Danach dieselbe ffprobe-Verifikation wie in §7(d).

**Qualitätsbewertung des Upscales:**

- **Flat-Design-Inhalte (Stills, große Typo, Gradients) skalieren von 1080p→4K erstaunlich gut** — Lanczos/Spline36 hält Kanten sauber; auf normalem Betrachtungsabstand kaum vom nativen 4K-Render unterscheidbar. Der Trailer-Look (Copper-Texturen aus Screenshots, große Titel) ist dafür gutmütig.
- Sichtbare Verluste: sehr feine Texte (< ~28 px im 1080p-Master), 1-px-Linien, feiner Grain/Noise — die werden weicher. Gegenmittel: Mindest-Schriftgrößen einhalten oder **Zwischenweg 2560×1440** (`--scale=0.6667`, ganzzahlig 2560×1440) rendern — nur ~2,25× Rasterkosten-Ersparnis statt 4×, aber Upscale-Faktor 1,5 ist quasi unsichtbar.
- Reihenfolge im Ernstfall: erst `--concurrency` senken (Stabilität), dann Blur/Schatten eliminieren (Speed), erst dann Auflösung opfern. Der Upscale-Encode selbst läuft auf der VM mit ~2–6 fps → zusätzliche ~5–15 min.

---

## Anhang: Checkliste vor dem Finalrender

1. `npx remotion versions` — alle Pakete identisch auf 4.0.497.
2. Stills §7(a) für Frame 0 / Szenenmitten / 1799 abgenommen.
3. 120-Frame-Test §7(b): Sichtprüfung (Fonts! Bilder! Blenden!) + Zeit hochgerechnet + RAM in htop beobachtet.
4. Audio-Check am Testrender: Fade-in hörbar, Kick sitzt auf dem Frame.
5. Finalrender §7(c) → ffprobe §7(d) → Größen-Gate → `+faststart`-Remux.
6. Datei liegt als `/home/ubuntu/project-eclipse/ECLIPSE-Trailer-4K.mp4` im Repo-Root, < 95 MB.

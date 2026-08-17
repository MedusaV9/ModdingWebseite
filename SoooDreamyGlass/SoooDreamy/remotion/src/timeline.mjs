// FullRelease N1-C — EINZIGE Quelle für Szenen-Timings, Haptik-Beats und
// Sound-Cues. Die Kompositionen (src/scenes/*.tsx) lesen dieselben Zeiten wie
// der Manifest-Export (src/export-manifests.mjs): Frames und Beats können
// nie auseinanderdriften (RECON_REMOTION_PIPELINE.md §3.6).
//
// Beat-Format spiegelt das App-seitige `HapticEventSpec` (Core/HapticPatternKit.swift):
//   t = Start in Sekunden ab Videostart, i = Intensität 0…1, s = Schärfe 0…1,
//   d = Dauer in Sekunden (0 = transienter Tap).
// `type` ist die menschenlesbare Beat-Klasse (tap/success/soft) für Review
// und für die App-Welle (Mapping auf Haptics.tap()/success()/soft-Rumble).
//
// Cue-IDs sind AppCue-Rohwerte MIT committetem Sample (`cue_<id>.caf`,
// plannedMode sample/hybrid in Core/AppCueCatalog.swift) — die App spielt sie
// über die bestehende SoundEngine, getriggert via addBoundaryTimeObserver.

export const FPS = 30;
export const WIDTH = 1170;
export const HEIGHT = 2532;

// ── Szene 2 · „Der Umschlag" (Decision 3.9 #2, 8–16 s der Dramaturgie) ──────
// Ein Umschlag schiebt sich in den Lichtkegel, der Poststempel prägt sich auf.
// Textfrei: Anschrift = abstrakte Tintenstriche, Stempel = Ring + Kerbe.
const s2 = {
  holdIn: 0.5, // ruhiger Zimmer-Hold-Frame (Naht zur prozeduralen Szene 1)
  envelopeIn: 0.8, // Umschlag beginnt zu gleiten
  envelopeLand: 3.0, // Umschlag setzt im Kegel auf
  addressStart: 3.6, // Tintenstriche ziehen sich
  stamp: 5.2, // Poststempel schlägt auf (rigid)
  stampEcho: 5.34, // Nachfedern des Papiers
  holdFrom: 6.4, // End-Hold-Frame
};

// ── Szene 3 · „Der Siegelbruch" (Decision 3.9 #3, 16–26 s) ──────────────────
// Das neutrale Wachssiegel bricht, der Brief entfaltet sich — blank, der
// Satz „Ein Ort für zwei…" kommt als natives SwiftUI-Overlay.
const s3 = {
  holdIn: 0.6,
  sealTension: 1.2, // Druck baut sich auf, Risslinie wandert
  sealCrack: 2.4, // SNAP — Siegel bricht in zwei Hälften
  crackEcho: 2.56,
  letterOut: 2.9, // Brief hebt sich aus dem Umschlag
  unfoldTop: 3.6, // obere Falz öffnet
  unfoldBottom: 4.5, // untere Falz öffnet
  unfoldDone: 5.4, // Papier liegt plan
  inkLines: 6.0, // zwei Tinten-Schwünge im Briefkopf
  holdFrom: 7.4,
};

// ── Szene 6 · „Das leere Polaroid" (Decision 3.9 #6, 46–54 s) ───────────────
// Ein leeres Polaroid entwickelt sich von Weiß zu Papier.polaroid und bleibt
// leer („Eure erste Erinnerung fehlt noch" — Overlay der App).
const s6 = {
  holdIn: 0.4,
  dropIn: 0.6, // Polaroid segelt in den Kegel
  land: 1.4, // Aufsetzen
  developStart: 1.8, // Entwicklung beginnt (Weiß → Papierton)
  rockA: 2.2, // sanftes Nachwippen wie frisch geschüttelt
  rockB: 2.9,
  glint: 4.6, // Lampen-Glanz streicht über die Fläche
  developDone: 5.8, // Entwicklung fertig, Siegel-Sticker setzt sich
  holdFrom: 6.6,
};

export const SCENES = {
  scene2: {
    composition: 'Scene2Envelope',
    video: 'scene2_envelope.mp4',
    durationSec: 8,
    posterTime: 6.8, // Reduce-Motion-Standbild: gestempelter Umschlag im Kegel
    t: s2,
    beats: [
      // Umschlag setzt auf: weiches Papier-Aufsetzen.
      {t: s2.envelopeLand, type: 'soft', i: 0.45, s: 0.3, d: 0.22},
      // Poststempel: rigider Schlag (Decision: „rigid-Haptik aus dem Manifest").
      {t: s2.stamp, type: 'tap', i: 0.9, s: 0.62, d: 0},
      {t: s2.stampEcho, type: 'soft', i: 0.32, s: 0.2, d: 0.16},
    ],
    cues: [
      {t: s2.envelopeLand, id: 'drop'},
      {t: s2.stamp, id: 'sealed'},
    ],
  },
  scene3: {
    composition: 'Scene3SealBreak',
    video: 'scene3_seal.mp4',
    durationSec: 10,
    posterTime: 8.6, // entfalteter, blanker Brief im Lampenlicht
    t: s3,
    beats: [
      // Druck schwillt ins Wachs (Spiegel des sealed-Twins, invertiert).
      {t: s3.sealTension, type: 'soft', i: 0.35, s: 0.2, d: 0.9},
      // Der Bruch: der eine laute Moment der Szene (Do #8).
      {t: s3.sealCrack, type: 'tap', i: 0.85, s: 0.72, d: 0},
      {t: s3.crackEcho, type: 'tap', i: 0.4, s: 0.5, d: 0},
      // Brief entfaltet sich: getragenes Öffnen.
      {t: s3.unfoldTop, type: 'soft', i: 0.3, s: 0.15, d: 0.5},
      {t: s3.unfoldBottom, type: 'soft', i: 0.26, s: 0.15, d: 0.4},
      // Papier liegt plan: doppelter Erfolgs-Tick (Muster: AppCue.success-Twin).
      {t: s3.unfoldDone, type: 'success', i: 0.5, s: 0.5, d: 0},
      {t: s3.unfoldDone + 0.11, type: 'success', i: 0.65, s: 0.55, d: 0},
    ],
    cues: [
      {t: s3.sealCrack, id: 'unseal'},
      {t: s3.unfoldTop, id: 'reveal'},
    ],
  },
  scene6: {
    composition: 'Scene6Polaroid',
    video: 'scene6_polaroid.mp4',
    durationSec: 8,
    posterTime: 7.2, // fertig entwickeltes, leeres Polaroid
    t: s6,
    beats: [
      // Polaroid landet: weicher Papier-Tap.
      {t: s6.land, type: 'soft', i: 0.5, s: 0.35, d: 0},
      // Nachwippen: zwei leise Ticks.
      {t: s6.rockA, type: 'tap', i: 0.22, s: 0.4, d: 0},
      {t: s6.rockB, type: 'tap', i: 0.16, s: 0.4, d: 0},
      // Entwicklung fertig + Siegel-Sticker: Erfolgs-Doppel.
      {t: s6.developDone, type: 'success', i: 0.5, s: 0.5, d: 0},
      {t: s6.developDone + 0.11, type: 'success', i: 0.65, s: 0.55, d: 0},
    ],
    cues: [
      {t: s6.land, id: 'drop'},
      {t: s6.developDone, id: 'chime'},
    ],
  },
};

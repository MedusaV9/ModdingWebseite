# B7 — Cutscene-Beats (FX-Wave-13, Zensus §5)

Team B7: sechs neue Cutscene-Beats, je einer pro Sequenz-Klasse, alle Assets aus EINEM
neuen Generator `tools/photon/wave13_cutscene_fx.py`, alle Rows in EINEM neuen Registrar
`veilfx/CutsceneBeatFxRows.java`. `FxCues.java` bleibt unangetastet: die Cue-IDs werden
nach dem CreditsSequence/CreditsFinale3FxRows-Präzedenzfall auf BEIDEN Seiten über
`FxCues.cue("beat_…")` abgeleitet (Server-Sequenz hält eine private Konstante, der
Client-Registrar leitet DIESELBE ID ab — Namensvertrag, siehe §4).

Alle sechs Beats sind Photon-only-Garnish (`Mode.LAYER`, Quasar-Leg `null` — legal für
NEUE Cues, deren Vor-Row-Baseline "nichts" war; die bestehenden Server-Partikel- und
Sound-Baselines jeder Sequenz laufen unverändert darunter weiter). Kanal: `SEQUENCE`.

> **Tester-Hinweis:** Photon cached .fx statisch — nach jedem Asset-Rebuild im laufenden
> Client `/photon_client clear_client_fx_cache` (+ `F3+T` bei Resource-Pack-Drop-in).

## §1 Beat-Timings (Tick-genau)

| # | Sequenz (Klasse) | Phase + Tick | Cue (`eclipse:fx/cue/…`) | Photon-Asset | Kernidee |
|---|---|---|---|---|---|
| 1 | Intro (`sequence.IntroSequence`) | FLIGHT abs. t=340 (40t nach `VORTEX_SPAWN_TICK` 300, Wand steht opak); Re-fire alle 220t in FLIGHT **und** APPROACH (220 teilt die 660t-Laufzeit → nahtloser Sustain, Dedup schluckt Mid-Run-Sends) | `beat_intro_windshear` | `eclipse:beat_intro_windshear` (660t) | Wind-Shear-Streamer auf einem 30–58-Block-Ring um die Vortex-Säule, die nach innen kondensieren (radial −6→−15) und orbital mitdrehen (0.10–0.22 rad/s = 4–10 b/s tangential auf dem Band); Eskalationskurve über emissionRate 0.3→1.4 (world-anchored ⇒ Rate-Kurve statt distanceRate) füllt den langen Gleitteil |
| 2 | Expansion (`sequence.ExpansionSequence`) | FLYOVER (Shot = 220t): Monolith-Pulse bei Shot-t 40/90/140/190; Boden-Schatten-Lauf bei Shot-t 80 (= `0.5·220−30`, Kamera-Skim) + Re-fire t 150 **22 Blöcke weiter außen** (Front ist weitergezogen; frischer Anker umgeht zugleich Photon-Same-Anchor-Dedup) | `beat_monolith_pulse`, `beat_flyover_shadow` (a = Yaw nach außen) | `eclipse:beat_monolith_pulse` (70t), `eclipse:beat_flyover_shadow` (110t) | Fern-Monolith-Silhouetten am Karten-Rand (`StageRadii.radius(fromStage)`, Flanken-Winkel +0.10/−0.18/+0.24/−0.30 rad um `frontAngle` — dort clustert `ExpansionBorderFx.armFrontier` die echten Monolithe) pulsen violett auf; ein dunkles Schattenband rennt mit 10 b/s ~44 Blöcke radial nach außen unter der Skim-Kamera durch (ferry_wave_crest-Bauart: Burst auf Launch-Tick + World-Space-Marsch) |
| 3 | Nether (`sequence.NetherOpeningSequence`) | AFTERMATH-Eintritt t=880 (Cue), Nachbeben-Puls t=910 (`RUMBLE`-Broadcast 0.45 + Anchor-Deplete, deckungsgleich mit dem im Asset gebackenen t=30-Aftershock; liegt zwischen den 20t-Rasterpulsen 900/920) | `beat_nether_ember_tear` (a = Kriech-Yaw) | `eclipse:beat_nether_ember_tear` (140t) | "Erste Glut-Träne": EIN Lava-Riss kriecht sichtbar vom Kraterrand weg — Partikel werden ~85t lang am Ursprung geboren und kriechen mit 1.6–3.2 b/s (speed_modifier klingt auf 0.12 ab) auf lokal −Z hinaus, die langsamen bleiben nah, die schnellen erreichen ~12 Blöcke → die Linie WÄCHST; glühender Riss-Kopf + dünne Fumarolen (Rate rampt ein, wo der Riss schon war) + Aftershock-Ring bei Asset-t 30 |
| 4 | End-Ankunft (`sequence.endarrival.EndArrivalSequence`) | CHARGE-Countdown-Leiter t = 260 / 300 / 334 / 362 / 384 / 396 (Intervalle 40→34→28→22→12, beschleunigend; MAW_AT=240 liegt davor, CHARGE_END=400 danach); pro Sprosse `EVENT_END_SHATTER_CRACK`-Sting mit Pitch 0.6→1.1 | `beat_endarrival_crack` | **Re-Cue** von `eclipse:end_crack_bleed` (kein neues Asset — geprüft: 3 HDR-Bleed-Shafts ≈ 36–40t, positions-anchored; Custom-Leg = Default-Spawn mit `allowMulti=true`, OHNE die RiftFx-Suppression-Nebenwirkung der `CUE_END_CRACK`-Row) | Himmel-Riss-Vorzeichen: Instanzen zünden im Raster um den Rift-Punkt (Goldener-Winkel-Spirale mit Zufallsphase, Radius 46→16 kondensierend, Höhe rift−8±6) mit ansteigender Frequenz + steigendem Crack-Sound-Pitch — Countdown aufs SPILL |
| 5 | Ferryman-Finale (`ferryman.finale.FinaleSequence`) | UNLOCK t=0 (`insertKey`, Cue mit a=gateYaw, Anker keyhole−1.5); Server-Klick-Stings (`LODESTONE_COMPASS_LOCK`, Pitch 0.6/0.75/0.9) bei UNLOCK t=8/22/36 (deckungsgleich mit den 3 im Asset gebackenen Ring-Snaps; BREACH_AT_TICK=50 bleibt frei) | `beat_finale_keyglyphs` (a = Gate-Yaw) | `eclipse:beat_finale_keyglyphs` (60t) | Key-Photon: 3 Klick-Beats rasten je 18 Bart-Glyphen mit Ring-Snap auf den vertikalen Tor-Ring (radial −40, arretiert nach ~3t = der Snap; jeder Klick verdichtet den Schloss-Ring), dritter Snap flasht den Ring, dann saugt der Portal-Veil ein (Indraw-Motes t=36–58, Einatmen fertig zum t=50-Breach) |
| 6 | Credits (`ritual.CreditsSequence`) | BEACH-Eintritt `T_BEACH` = abs. t=900 (die Whiteout-Release endet exakt hier) | `beat_credits_afterglow` | `eclipse:beat_credits_afterglow` (200t = 10 s) | Nachglühen-Brücke: weiße Asche-Motes rieseln 10 s in die Beach-Stille (Anchor Surf-Linie `SURF_X+0.5 / BEACH_Y+9 / z=0`, 30×24-Block-Feld, Sinken 2.2–3.2 b/s), Crossfade im Asset gebacken (40t ein, ab Asset-t 140 aus), bewusst OHNE HDR (LINT-HDR-DUST: Asche bloomt nicht). Gewollter Rest-Overlap: `T_LIGHTNING`=abs. 1020 trifft die letzten 80t der Ausblende — Low-Alpha-Asche in den ersten Blitzen liest gut und kämpft mit nichts |

## §2 Replay-Parität

- Intro: `replay("FLIGHT")` schedult den Windshear-Cue bei +240 (= abs. 340) an die Watcher.
- Expansion: `replay("FLYOVER")` feuert dieselben Monolith-/Schatten-Beats um den
  `resolveGrowthFront`-Anker.
- Nether/EndArrival: die Replays (`/dev nether replay_fx`, `/dev event start endarrival
  fxonly`) laufen durch dieselben Live-Hooks — keine Extra-Verdrahtung.
- Finale: `/dev start_ferryman` läuft durch `insertKey` — keine Extra-Verdrahtung.
- Credits: `replay("BEACH")` feuert den Afterglow pro Watcher (Anker 8 über dem Spieler).

## §3 Budgets / Leitplanken-Nachweis

- Photon-speed = b/s beachtet (Schatten-Lauf 10 b/s = 0.5 b/t; Riss-Kriechen 1.6–3.2 b/s);
  radial ×0.01/t (Windshear −6→−15 ⇒ 0.06→0.15 b/t Kondensation; Glyph-Snap −40 ⇒ 0.4 b/t);
  orbital ist **rad/s** (jar-verifiziert, AngularVelocity ×0.05 rad/t — STORM_MASS-Befund):
  Windshear-Streamer 0.10–0.22 rad/s ⇒ 4–10 b/s tangential auf dem 30–58er-Band.
- Kein distanceRate (alle Anker world-anchored) → Eskalation über emissionRate-Kurven.
- Alpha-Blend-Pässe (soft_particle/Asche/Schatten) sorten DISTANCE; HDR ≤ 1.45 via
  lokalem `hdr()`-Clamp (ferryman2-Muster); keine section-Tubes; keine neuen Payloads —
  alles über den bestehenden `FxPayloads.sendFxEvent` → `PhotonFxRegistry.dispatch`-Tail
  (a/b threading für die Yaw-Legs, `FerrymanFinaleFxRows.yawAlignedLeg`-Konvention 180°−a).
- Render-Mode-Gesetz beachtet: der Keyglyph-Ring-Flash ist bewusst Billboard (Render-Modi
  ignorieren die Executor-Rotation — ein Horizontal-Quad läge flach am Boden statt im Tor).
- max_particles: windshear 96+40, shadow 40+30+16, monolith 10+8, ember_tear 64+6+20+26,
  keyglyphs 54+40+2, afterglow 90+12 — alle weit unter der CPU-Warnschwelle.

## §5 Verifikation + Dateien (Stand nach Umsetzung)

- `python3 tools/photon/wave13_cutscene_fx.py` → 6/6 WROTE + round-trip-valid + `.fxproj`.
- `python3 tools/photon/fxlib.py validate --lint` → **0 NEW error/warn** (50 grandfathered,
  Baseline unverändert); nur 3 neue LINT-PALETTE-*Advisories* (Lava-Heißweiß/Gold-Mids —
  dieselbe Klasse wie die bestehenden wandfx2-Glut-Assets, legitime Off-Token-Mids).
- `./gradlew compileJava` → BUILD SUCCESSFUL.
- NEU: `tools/photon/wave13_cutscene_fx.py`,
  `src/main/java/dev/projecteclipse/eclipse/veilfx/CutsceneBeatFxRows.java`,
  `assets/eclipse/fx/beat_{intro_windshear,monolith_pulse,flyover_shadow,nether_ember_tear,finale_keyglyphs,credits_afterglow}.fx(+.fxproj)`, dieser Report.
- GEÄNDERT (nur B7-Hooks): `IntroSequence`, `ExpansionSequence`, `NetherOpeningSequence`,
  `endarrival/EndArrivalSequence`, `ferryman/finale/FinaleSequence`, `ritual/CreditsSequence`.
- `FxCues.java` unangetastet (Namensvertrag §4 greift — kein Patch-Snippet nötig).

## §4 Cue-Namensvertrag (FxCues.java unangetastet)

Beide Seiten leiten mit `FxCues.cue(<name>)` ab; die Strings sind der Vertrag:
`beat_intro_windshear`, `beat_flyover_shadow`, `beat_monolith_pulse`,
`beat_nether_ember_tear`, `beat_endarrival_crack`, `beat_finale_keyglyphs`,
`beat_credits_afterglow`. Server-Konstanten privat in der jeweiligen Sequenz-Klasse
(CreditsSequence-Präzedenzfall `CUE_CREDITS3_*`), Client-Rows in
`veilfx/CutsceneBeatFxRows` (selbstregistrierend über `FMLClientSetupEvent`).

# PLAN5-GAMES-IDEEN — Mehr Minispiele & Content-Tiefe (V5/G06)

> IDEA/PLAN-Agent 06 · Thema: **mehr Minigames + einzigartige Inhalte** (comfy cute,
> Polish & Juice). Bestand: 28 Spiele → mit dieser Welle **30**. Alle Konzepte
> nutzen ausschließlich vorhandene Engine-Muster (§E8-Plugin, `ctx`-Framework,
> Partikel, Gooby-Rig, Float-Texte, Schwierigkeits-Familie §G5, Modifier §C-SYS4).

## Status dieser Runde

| # | Spiel | Id | Status |
|---|-------|----|--------|
| 1 | **Teestube** | `teaParty` | ✅ **MVP implementiert** (Logic + View + Bot + Cover + Tests) |
| 2 | **Guck-guck-Garten** | `hideSeek` | ✅ **MVP implementiert** (Logic + View + Bot + Cover + Tests) |
| 3 | Sternenlaterne | `lanternFloat` | 💡 Konzept (Stubs unten) |
| 4 | Plüsch-Wäscherei | `plushWash` | 💡 Konzept |
| 5 | Marmeladen-Karussell | `jamCarousel` | 💡 Konzept |
| 6 | Schneckenpost | `snailMail` | 💡 Konzept |

---

## 1. Teestube (`teaParty`) — ✅ implementiert

**Fantasie:** Gooby betreibt ein winziges Teestübchen. Tassen gleiten herein,
jede trägt ein türkises Zielband mit goldenem Perfekt-Ring — **halten** kippt
die rosa Kanne und gießt, **loslassen** serviert.

- **Kern-Loop:** Band treffen = +3 („Gut"), Perfekt-Ring = +6; jede 3. perfekte
  Tasse in Folge +2 Streak-Bonus. Überlaufen/daneben = Patzer (Gooby wird
  schwindelig). 60 s, Kadenz zieht an.
- **Steuerung:** Ein-Finger-Halten irgendwo (`pointerdown`/`up` am Renderer) —
  `controls.invertible: false` (§G2.1 Regel 4, Timing-Input).
- **Ökonomie (§V5.1):** Coin-Row `4/4/26`, Gate **L3**, Energie 8. CapScore 104,
  Schwer-Ziel 85, typisch roh ≈ 70 → **~17 c**.
- **Schwierigkeit (§G5.3-Familie):** Leicht = breiteres Band ×1,25, Füllrate
  ×0,8, +20 % Zeit · Schwer = Band ×0,8, Füllrate ×1,2, Kadenz ×0,85 ·
  Endlos = Schwer-Tuning, Ende beim 3. Patzer.
- **Engine-Reuse:** `tween` (Tassen-Slide mit `easeOutBack`), `createParticles`
  (sparkles/confetti/bubbles/dizzyStars), `createGooby` + Emotionen, Float-Texte,
  `clampFloatTextToView`, HUD-Banner, Kamera-Micro-Shake (reduced-motion-gated).
- **Dateien:** `src/minigames/games/teaParty.logic.js` (pure) + `teaParty.js`
  (View), Strings in `src/data/strings/v5-games.js`, Cover
  `public/assets/covers/teaParty.png`.

## 2. Guck-guck-Garten (`hideSeek`) — ✅ implementiert

**Fantasie:** Pastell-Häschen verstecken sich hinter Büschen, Kisten und
Blumentöpfen im Morgengarten und **lugen** alle paar Sekunden hervor — merken,
tippen, finden!

- **Kern-Loop:** 3×4-Raster, pro Welle verstecken sich 3→5 Freunde; Fund = +2,
  ganze Welle vor Ablauf des Timers = +3 Bonus. Abgelaufene Welle = neu
  versteckt (Endlos: 3 abgelaufene Wellen beenden den Lauf). Gefundene Häschen
  bleiben jubelnd auf ihrem Versteck sitzen — der Garten füllt sich.
- **Steuerung:** Tap auf Versteck (Raycast auf unsichtbare Hit-Sphären) —
  `controls.invertible: false` (positionaler Input).
- **Ökonomie (§V5.2):** Coin-Row `5/4/20`, Gate **L2**, Energie 8. CapScore 100,
  Schwer-Ziel 80, typisch roh ≈ 70 → **~14 c**.
- **Schwierigkeit:** Leicht = Wellen-Timer ×1,25, Guck-Dauer ×1,3, +20 % Zeit ·
  Schwer = Timer ×0,8, Guck-Dauer ×0,8, Gucken seltener ×1,25 · Endlos wie
  Schwer mit 3-Strikes.
- **Engine-Reuse:** Raycaster-Tap-Muster (wie `memoryMatch`), Partikel
  (hearts/sparkles/confetti), Wellen-Timerbar (Farbwechsel teal→koralle),
  Gooby-Cameo unten rechts, `says.pad1` als Guck-Cue.
- **Dateien:** `hideSeek.logic.js` + `hideSeek.js`, Strings/Cover analog.

---

## 3. Sternenlaterne (`lanternFloat`) — 💡 Konzept

**Fantasie:** Nachthimmel über dem Garten. Gooby lässt eine Papierlaterne
steigen und **lenkt sie per Drag** sanft durch Sternringe, vorbei an
Windböen und neugierigen Glühwürmchen.

- **Kern-Loop:** Vertikal auto-steigend; Ringe durchfliegen +2, goldene Ringe
  +5, Glühwürmchen einsammeln +1; Böen (telegraphiert durch Blätter) schieben
  die Laterne — 3 Wolken-Rempler beenden (Endlos) bzw. kosten Punkte (60 s).
- **Steuerung:** Horizontaler Drag = screen-true Lenken → **`invertible: true`**
  (wie `goobyWelt`-Zeile) — der globale Invert-Schalter greift.
- **Ökonomie-Vorschlag:** Row `4/4/24`, Gate L7, CapScore 96, Ziel 75.
- **Engine-Reuse:** Drag-Muster von `harborHopper` (ein `dragX`-Mirror an der
  Input-Grenze!), Sternenhimmel-Backdrop von `starHopper`, `ambience`-Glow,
  Partikel `sparkles`; Musik-Kontext optional (Fallback-Medley reicht).
- **Juice-Momente:** Laterne pulsiert warm beim Ring-Treffer; Glühwürmchen
  folgen kurz als Schweif; Sternschnuppe alle ~20 s (nur Deko).
- **Datei-Stubs:**
  - `src/minigames/games/lanternFloat.logic.js` — `LANTERN`, `applyDifficulty`,
    `ringAt`, `gustAt`, `applyScore`, `endlessShouldEnd`, `simulateLanternAutoplay(mode, seed)`
  - `src/minigames/games/lanternFloat.js` — View (+ `controls = { invertible: true }`)
  - Zeilen in: `constants.js` (V5-Block), `minigames.js` (L7-Position + Icon
    `star`), `difficultyTargets.js`, `modifierEngine.js` (ALL + ggf. `muenzregen`),
    `strings/v5-games.js`, `test/…` (Pins 30→31), Cover-PNG.

## 4. Plüsch-Wäscherei (`plushWash`) — 💡 Konzept

**Fantasie:** Schaumige Wanne, verschmutzte Plüschtiere. **Kreisendes Rubbeln**
über Schmutzflecken schrubbt sie weg; danach ausspülen (kurzer Swipe nach
oben) und aufhängen — das nächste Plüschtier plumpst herein.

- **Kern-Loop:** Flecken haben Füllstände; vollständig geschrubbt +2 pro Fleck,
  Plüschtier komplett = +4 + Herzchen-Regen. Zu langes Rubbeln auf sauberer
  Stelle schäumt über (kleiner Zeitverlust, kein Minus — comfy!). 60 s.
- **Steuerung:** Kreis-Geste (Pointer-Move-Distanz zählt) — `invertible: false`.
- **Ökonomie-Vorschlag:** Row `3/4/25`, Gate L4, CapScore 75, Ziel 60.
- **Engine-Reuse:** Rubbel-Distanz-Muster von `gardenRush` (Gieß-/Putzgesten),
  `wash.splash`/`bubble.pop`-Cues, Partikel `bubbles` + `hearts`, Gooby schaut
  über den Wannenrand.
- **Juice-Momente:** Schaumkronen wachsen mit Rubbel-Tempo; Plüschtier blinzelt
  glücklich, wenn sauber; Wäscheleine mit baumelnden Freunden als Fortschritt.
- **Datei-Stubs:** analog #3 (`plushWash.logic.js` + `plushWash.js`, Icon
  `hygiene`, Sim `simulateWashAutoplay`).

## 5. Marmeladen-Karussell (`jamCarousel`) — 💡 Konzept

**Fantasie:** Ein Holzkarussell dreht Marmeladengläser an Gooby vorbei. Oben
zeigt ein Rezept-Banner die gesuchte Sorte („Erdbeere!") — **im richtigen
Moment tippen**, wenn das passende Glas unter dem Zeiger steht.

- **Kern-Loop:** Treffer +3 (Perfekt-Fenster ±40 ms: +5), falsches Glas −1,
  Rezept rotiert alle 10 s, Karussell beschleunigt. Jede 4. richtige Sorte in
  Folge: Brot-Bonus (+3, Gooby beißt genüsslich ab).
- **Steuerung:** Ein-Tap (Timing) — `invertible: false`.
- **Ökonomie-Vorschlag:** Row `4/4/26`, Gate L8, CapScore 104, Ziel 85.
- **Engine-Reuse:** Timing-Fenster-Logik von `danceParty`/`goobySays`,
  Food-Kit-Assets (`food-kit/*` wie `bubblePop`), `combo.up`/`hop.bell`,
  Rezept-Banner = HUD-Banner.
- **Juice-Momente:** Glas ploppt beim Treffer auf und der Deckel wirbelt;
  Perfekt = Zeitlupen-Beat (60 ms) + Konfetti; Karussell-Pferdchen nicken im Takt.
- **Datei-Stubs:** analog (`jamCarousel.logic.js` + `.js`, Icon `hunger`,
  Sim `simulateJamAutoplay`).

## 6. Schneckenpost (`snailMail`) — 💡 Konzept

**Fantasie:** Eine gemütliche Schnecke trägt Briefchen durch den Gemüsegarten.
**Pfad vorzeichnen** (Finger zieht eine Glitzerspur), die Schnecke folgt —
Briefkästen einsammeln, Pfützen umkurven.

- **Kern-Loop:** Zugestellter Brief +3, alle 3 Briefe einer Runde = +4 Bonus,
  Pfütze = Schnecke zieht sich 2 s ins Haus zurück (Endlos: 3× = Ende).
  Runden werden größer/verwinkelter.
- **Steuerung:** Pfad-Draw (Pointer-Trace, wie `miniGolf`-Zielen) —
  `invertible: false` (semantischer Input).
- **Ökonomie-Vorschlag:** Row `4/4/24`, Gate L6, CapScore 96, Ziel 75.
- **Engine-Reuse:** Spline-Follow von `goobyWelt.logic` (Scripted-Follower),
  Garten-Setdressing von `gardenRush`, `jingle.short` bei Zustellung.
- **Juice-Momente:** Glitzerspur verblasst hinter der Schnecke; Briefkasten-
  Fähnchen springt hoch; Schneckenhaus schimmert nach jeder Zustellung minimal
  bunter (Runden-Fortschritt sichtbar am Charakter!).
- **Datei-Stubs:** analog (`snailMail.logic.js` + `.js`, Icon `cart`,
  Sim `simulateSnailAutoplay`).

---

## Juice-Checkliste (für jedes neue Spiel — aus Teestube/Guck-guck destilliert)

1. **Eintritt:** Objekt-Slide-in mit `easeOutBack` (nie hart spawnen).
2. **Treffer-Dreiklang:** Partikel + passender SFX (`hop.bell`/`bubble.pop`) +
   Float-Text mit Punkten — alle drei am selben Weltpunkt.
3. **Gooby reagiert:** `setEmotion` + Clip (`happyBounce`/`wave`/`dizzy`) für
   ~1,1 s, danach zurück zu `happy` — Gooby ist Publikum, nie Statist.
4. **Streak/Combo hörbar machen:** `combo.up` + HUD-Banner, nicht nur Zahlen.
5. **Fehler comfy bestrafen:** kurzer Micro-Shake (≤0,25 s, hinter
   `prefersReducedMotion()`), `dizzyStars` — kein hartes Rot, kein Buzzer.
6. **Idle-Leben:** alles atmet (Sinus-Bob, Sway ±0,015 rad) — nichts steht still.
7. **Timer sichtbar & farbig:** Balken teal → koralle unter 30 %.
8. **Rundenende feiern:** `ui.win` + Konfetti auf Gooby + 1,3 s Ausklang vor
   `ctx.onEnd` (nie abrupt zum Result-Screen schneiden).
9. **Audio nur aus `sfxMap.js`** (Coverage-Test!), `sfx: […]`-Warmup-Liste am Plugin.
10. **Disposal-Hygiene:** eigene Geos/Mats in `ownedGeos`/`ownedMats` sammeln,
    Listener im `dispose()` abhängen (Framework-Contract-Tests prüfen Leaks).

## Verdrahtungs-Spickzettel (Datei-Stubs pro neuem Spiel)

| Datei | Was rein muss |
|-------|---------------|
| `src/minigames/games/<id>.logic.js` | frozen Tune, `applyDifficulty` (§G5.3-Familie, Guardrail 0,55–2,05), pure Regeln, `simulate…Autoplay(mode, seed)` |
| `src/minigames/games/<id>.js` | §E8-Plugin `{id, assetKeys, init, update, dispose}` + `sfx`-Warmup + `export const controls = Object.freeze({ invertible: … });` |
| `src/data/constants.js` | Coin-Row + `UNLOCKS.MINIGAMES`-Gate im V5-Block (Datei gilt danach wieder als eingefroren) |
| `src/data/minigames.js` | Id an Unlock-Position + Icon-Zeile |
| `src/data/difficultyTargets.js` | `capScore = divisor × max`, Ziel ≈ 80 %, Endlos-Notiz |
| `src/systems/modifierEngine.js` | Id in `ALL_ARCADE_GAMES` (+ ggf. Spezial-Rows) |
| `src/data/strings/v5-games.js` | Titel + Banner-Keys, immer EN **und** DE |
| `public/assets/covers/<id>.png` | 512×384, indexed (colorType 3), ≤85 KiB |
| `test/…` | Zähler-Pins hochziehen (Meta/Data/Economy/Leveling/Covers/Controls/Modifier/Oracle) + Adapter-Zeile in `difficultyCertification.test.js` + eigene Mechanik-Tests |

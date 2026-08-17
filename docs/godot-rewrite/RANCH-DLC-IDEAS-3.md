# RANCH-DLC-IDEAS-3 — Die Pferde: Individuen, Progression, Reitgefühl, Zucht, Wettbewerbe

> Ideen-Agent 3 · Schwerpunkt: **die Pferde selbst**. Kein Spielcode — ein Bauplan mit Zahlen.
>
> **Bestand, auf dem alles aufsetzt (ausbauen, nicht neu erfinden):**
>
> | Datei | Was schon da ist |
> |---|---|
> | `GOOBY-GODOT/scripts/ranch/gameplay/horse_care.gd` | Pflegewerte hunger/durst/sauberkeit (0–100), abgeleitete Laune, Bindung 0–100 mit Tagesdeckel 12, Bindungsstufen fremd→seelenpferd, `reit_perks()` (+6 % Galopp, +25 % Ausdauer-Regen) |
> | `GOOBY-GODOT/scripts/ranch/gameplay/ride_feel.gd` | Gangarten stand/schritt/trab/galopp (0 / 1,7 / 4,2 / 8,5 m/s), Lenk-Tiefpass τ=140 ms, Sprungphysik (vy 4,8, g −11,5), Ausdauer 100 (−7/s Galopp, +9/s Regen), Kopfnicken, Kamera-FOV 58–66° |
> | `GOOBY-GODOT/scripts/ranch/gameplay/ride_controller.gd` | Node-Verdrahtung: `steer_input()/gait_up()/gait_down()/jump()` — Touch-HUD dockt hier an |
> | `GOOBY-GODOT/scripts/ranch/data/ranch_play_slices.gd` | Pferde-Dict (`neues_pferd()`), 6 Fellfarben, Gear-Slots sattel/decke/halfter; `normalize` erhält fremde Schlüssel VERBATIM → **alle neuen Felder sind additiv möglich** |
> | `GOOBY-GODOT/scripts/ranch/data/ranch_wirtschaft.gd` + `wirtschaft.json` | Preis-Handschrift: Heu 8, Sattel 120, Boxen2 400, Boxen3 900, Reitplatz 300, Weidezaun 250; Balance ist Content-Pack-updatebar |
> | `GOOBY-GODOT/scripts/ranch/data/spiele_progress.gd` | Sterne/Best/Cleared je Level — Muster für Wettbewerbs-Fortschritt |
> | `GOOBY-GODOT/scripts/logic/stats.gd` | Die Handschrift: pure static-Funktionen, Konstanten oben, Bänder von oben geprüft, Raten pro realer Minute, Tagesdeckel |
> | `GOOBY-SERVER/server.js` | Node.js-Instanz für Mehrspieler (Geisterläufe hochladen, Live-Rennen-Räume) |
>
> **Design-Leitplanken:** Kein Pferd stirbt, kein Pferd verkümmert unumkehrbar. Alles verzeiht. Zahlen
> bleiben in der `stats.gd`-Handschrift (pro-Minute-Raten, Tagesdeckel, Bänder). Jede neue Mechanik
> muss auf dem Touchscreen mit einem Daumen bedienbar sein.

---

## 1. Pferde-Individuen — was macht MEIN Pferd besonders?

Jedes Pferd ist ein Unikat aus **Rasse + Fellgenetik + Abzeichen + Charakter + Statur + Name +
Geschichte** (Schleifenwand, Stammbaum). Ziel: Zwei Spieler mit "braunem Puschelhufer" sollen auf
einen Blick zwei verschiedene Pferde sehen.

### 1.1 Rassen (12, Gooby-Stil)

Basiswerte auf der Skala 1–20 (Kap. 2). Größe = Skalierungsfaktor auf `RanchPferd` (Bestand = 1,00).
Preise in der Handschrift von `wirtschaft.json` (Boxen3 = 900 als Anker für "teuer").

| # | Rasse | Tempo | Ausdauer | Sprung | Wendigkeit | Gelassenheit | Größe | Rarität | Preis (G) | Eigenheit |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | **Puschelhufer** | 10 | 10 | 10 | 10 | 10 | 1,00 | Start | (Startpferd) | Allrounder; flauschige Fesseln wippen im Trab |
| 2 | **Knuffpony** | 9 | 9 | 8 | 14 | 9 | 0,85 | häufig | 650 | Slalom-Ass; passt durch enge Tore, die Große verweigern |
| 3 | **Zottelgnuff** | 8 | 11 | 7 | 9 | 13 | 0,95 | häufig | 700 | Bindung wächst ×1,25 (Tagesdeckel 15 statt 12) |
| 4 | **Wolkentraber** | 10 | 11 | 9 | 12 | 14 | 1,05 | ungewöhnlich | 1 200 | Dressur-Neigung; Übergänge geben +20 % Takt-Bonusfenster |
| 5 | **Flitzewind** | 15 | 9 | 9 | 10 | 7 | 1,02 | ungewöhnlich | 1 400 | Renn-Neigung; Antritts-Kick 1,2 s statt 0,8 s |
| 6 | **Moosmähne** | 9 | 15 | 10 | 9 | 12 | 0,98 | ungewöhnlich | 1 300 | Gelände: Matsch/Geröll-Tempomalus halbiert |
| 7 | **Donnerbommel** | 7 | 13 | 8 | 6 | 16 | 1,15 | ungewöhnlich | 1 250 | Kaltblut mit Bommel-Schweif; scheut nie, +1 Satteltaschen-Slot |
| 8 | **Federsprung** | 10 | 10 | 15 | 11 | 8 | 1,04 | selten | 2 200 | Spring-Neigung; Perfekt-Absprungfenster +50 ms |
| 9 | **Westernwuschel** | 11 | 11 | 8 | 14 | 11 | 0,97 | selten | 2 100 | Trail: Rückwärtsrichten rastet zentimetergenau ein |
| 10 | **Tölterle** | 11 | 13 | 7 | 10 | 12 | 0,92 | selten | 2 400 | **Exklusive 5. Gangart Tölt** (5,8 m/s, kaum Kopfnicken, −3/s Ausdauer) |
| 11 | **Miniknopf** | 7 | 8 | 7 | 12 | 12 | 0,78 | selten | 1 800 | Schau-Liebling: +10 % Stilpunkte; kleinste Rasse |
| 12 | **Sternschnuppler** | 12 | 12 | 12 | 12 | 12 | 1,00 | legendär | 4 800 *oder* erzüchtbar (✨-Gen, Kap. 4) | Glitzerfell, Mähne leuchtet nachts sanft |

Basiswert-Summen liegen bei 46–56 (legendär 60): Rassen sind **Profile, keine Machtstufen** —
ein maximal trainiertes Knuffpony schlägt einen untrainierten Sternschnuppler.

### 1.2 Fellfarben & Vererbungslogik (Kurzfassung; Würfe in Kap. 4)

Drei Gen-Orte + ein Glitzer-Gen, je zwei Allele (eins von jedem Elternteil, Mendel pur):

| Gen-Ort | Allele (Dominanz von links) | Wirkung |
|---|---|---|
| **G** Grundfarbe | `B` (braun) > `F` (fuchs) > `Z` (schwarz) | dominantestes Allel bestimmt die Grundfarbe |
| **H** Aufhellung | `h0` (keine) / `h+` (hell), unvollständig dominant | 1× `h+`: braun→**palomino**, fuchs→**apricot** (neu), schwarz→**rauchgrau** (neu); 2× `h+`: **weiss** |
| **S** Schecke | `Sch` (dominant) / `s0` | ≥1 `Sch` → Schecken-Overlay; Muster aus Pferde-Seed → jede Schecke einzigartig |
| **✨** Glitzer | `g0` / `g✨` (rezessiv) | nur `g✨/g✨` glitzert (Sternschnuppler sind immer `g✨/g✨`) |

Das erweitert `RanchPlaySlices.FELLFARBEN` additiv um `apricot`, `rauchgrau` und das
Glitzer-Overlay; Pastell-Vorschläge im Stil der `RanchPferd.FELL`-Tabelle:
`apricot` = `#E8B48A`/`#B57A4E`, `rauchgrau` = `#A9A4B8`/`#6E6880`.

**Abzeichen** (kein Gen, sondern Eltern-Chance): Blesse, Stern, Schnippe, je Bein eine Socke.
`P(Merkmal) = 0,05 + 0,35 · (Anzahl Eltern mit Merkmal)` → 5 % / 40 % / 75 %.
**Mähnenform**: glatt / wellig / puschel — 40 % Mutter, 40 % Vater, 20 % Überraschung.

### 1.3 Charakterzüge — spürbar, nicht nur Text

Jedes Pferd hat **2 Züge**: einer steht am Verkaufsschild, der zweite zeigt sich erst ab
Bindung ≥ 45 ("freund", Bestand `BINDUNG_STUFEN`) — Kennenlernen wird belohnt. Effekte docken an
bestehende Konstanten an:

| Zug | Spürbarer Effekt |
|---|---|
| **mutig** | scheut nie an Spuk-Punkten; Perfekt-Sprungfenster +30 ms |
| **scheu** | 15 % Scheu-Chance an Spuk-Punkten (Flatterband, Traktor…): 0,5 s Seitwärtshopser, Tempo −30 % für 2 s. Dafür Striegel-Bindung ×1,5 |
| **verfressen** | Futterwirkung auf hunger +30 %, aber hunger-Verfall −0,30/min statt −0,25 |
| **verspielt** | Minispiel-Sterne geben +15 % Pferde-XP; will 1×/Tag den Spielball (Laune +5) |
| **gelassen** | Ausdauer-Regen +10 %; Nick-Amplitude ×0,8 (ruhigeres Sitzgefühl) |
| **fleißig** | Trainingsfrische-Verbrauch 30 statt 35 pro Einheit (Kap. 2.3) |
| **eitel** | +10 % Stilpunkte in der Schau; sauberkeit-Verfall ×1,2 |
| **anhänglich** | Bindungs-Tagesdeckel 14 statt 12; wiehert, wenn Gooby die Ranch betritt |
| **stur** | erster Gangartwechsel je Ritt verzögert 0,4 s; Gelassenheits-Trainings-XP +20 % |
| **neugierig** | auf Ausritten alle 10 min 35 % Chance auf ein Extra-Sammelitem |

### 1.4 "Das ist MEINS" auf einen Blick

- **Statur-Varianz**: ±8 % Größe innerhalb der Rasse (Seed), plus Bauch-/Halsproportion ±5 %.
- **Wieher-Stimme**: Pitch 0,85–1,15 aus dem Seed — das eigene Pferd *klingt* wiedererkennbar.
- **Lauf-Mikrovarianz**: Phasen-Offset der Beinanimation aus dem Seed (kein Klon-Gleichschritt).
- **Namensschild** an der Box + Turnier­schleifen-Wand daneben (echte Erfolge sichtbar).
- **Bindungsaura**: ab "vertraut" dreht das Pferd den Kopf zu Gooby; "seelenpferd" begrüßt mit
  Herzchen-Partikeln und kommt auf der Weide angetrabt (Pathfinding zum Spieler).
- **Stammbaum-Popup** am Pferd: Porträts der Eltern/Großeltern (Kap. 4.5).

---

## 2. Statsystem & Leveln

### 2.1 Die Werte

Zwei getrennte Schichten — **Pflege** (Bestand, verfällt) und **Training** (neu, persistent):

| Schicht | Werte | Verhalten |
|---|---|---|
| Pflege (Bestand) | hunger, durst, sauberkeit → Laune | verfallen pro Minute, `horse_care.gd` unverändert |
| Bindung (Bestand) | 0–100, Tagesdeckel 12 | bleibt das soziale Fundament; speist `reit_perks()` |
| **Training (neu)** | **Tempo, Ausdauer, Sprungkraft, Wendigkeit, Gelassenheit** je 1–20 | `Wert = Rassenbasis + trainierte Punkte (0–10)`, Deckel 20 |
| **Pferde-Level (neu)** | 1–30 | wächst aus allem; schaltet trainierbare Punkte + Wettbewerbsklassen frei |

### 2.2 XP-Kurven

**Pferde-Level:** `XP(L→L+1) = 30·L + L²`

| Übergang | 1→2 | 5→6 | 10→11 | 20→21 | 29→30 | Σ 1→30 |
|---|---|---|---|---|---|---|
| XP | 31 | 175 | 400 | 1 000 | 1 711 | ≈ 21 600 |

XP-Quellen (pro Tag realistisch 300–600 XP bei 15–20 min Spielzeit → Level 30 nach ~6–8 Wochen
Alltagsspiel, schneller mit Wettbewerben):

| Quelle | XP |
|---|---|
| Ausritt (pro Minute im Sattel) | 4, Tagesdeckel 60 |
| Minispiel-Stern (`spiele_progress`-Muster) | 20 je Stern |
| Wettbewerb beendet | 60–240 je Klasse (Kap. 5.1) |
| Erste Pflegeaktion des Tages je Pferd | 5 |
| Fohlen-Aufzuchtaufgabe | 25 |

**Trainierte Punkte:** Aktivitäten zahlen Stat-XP in den *passenden* Wert (Training durch Tun,
kein Menü-Grind):

| Aktivität | Stat-XP |
|---|---|
| 50 m Galopp | 1 → Tempo |
| 1 min unterwegs (egal welche Gangart) | 2 → Ausdauer |
| Sprung gut / perfekt | 4 / 8 → Sprungkraft |
| Slalom-Tor sauber durchritten | 2 → Wendigkeit |
| 1 min Schritt bei Laune ≥ 60 | 3 → Gelassenheit |

Kosten pro Punkt (p = bereits trainierte Punkte, 0–9): `StatXP(p→p+1) = 100 · 1,4^p`
→ 100, 140, 196, 274, 384, 538, 753, 1 054, 1 476, 2 066 (Σ ≈ 6 980 je Wert).
**Level-Gate statt Hard-Grind:** `max. trainierte Punkte je Wert = ⌈Level / 3⌉` — Level 30 = +10.

### 2.3 Trainingsfrische (Anti-Grind-Sättigung, Muster `BOND_TAGES_DECKEL`)

Jeder der 5 Werte hat pro Tag eine **Frische 100**. Eine Trainingseinheit (~3 min fokussierte
Aktivität) verbraucht **35** (fleißig: 30). Stat-XP-Multiplikator = `max(0,15; frische/100)`:

| Einheit | 1. | 2. | 3. | 4.+ |
|---|---|---|---|---|
| Frische vorher | 100 | 65 | 30 | ≤0 |
| XP-Faktor | 1,00 | 0,65 | 0,30 | 0,15 |

Reset am Tageswechsel (gleiches `bondTag`-String-Muster wie die Bindung). **Hafermash** (25 G,
1×/Tag/Wert) füllt +25 Frische — kleine Gold-Senke, kein Pay-to-Win. Futter-Buffs on top:
Karotte +10 % Tempo-Stat-XP für 10 min, Apfel +10 % Sprungkraft-Stat-XP für 10 min.

### 2.4 Wirkung der Werte im Sattel (konkret, an `ride_feel.gd`-Konstanten)

| Wert | Formel (Basis = Bestand) | Spanne 1 → 20 |
|---|---|---|
| Tempo | Galopp-Ziel = `8,5 · (1 + 0,015·(Tempo−10))` · Bindungs-Perk | 7,4 → 9,8 m/s (+ bis 6 % Bindung) |
| Ausdauer | `AUSDAUER_MAX = 100 + 5·(Ausdauer−10)`; Galoppverbrauch `7 · (1 − 0,01·(Ausdauer−10))` | Tank 55→150; Verbrauch 7,63→6,3/s |
| Sprungkraft | `SPRUNG_VY = 4,8 + 0,06·(Sprungkraft−10)` | Sprunghöhe 0,74 → 1,31 m |
| Wendigkeit | `STEER_RATE = 1,7 · (1 + 0,02·(Wendigkeit−10))`; `STEER_SPEED_DAMP = 0,3 − 0,006·(Wendigkeit−10)` | Yaw 1,39→2,04 rad/s (Deckel 100°/s bleibt) |
| Gelassenheit | Scheu-Chance `15 % · (1 − 0,05·(Gelassenheit−10))`; Pflegeverfall im Ritt ×`(1 − 0,01·(Gelassenheit−10))` | Scheuen 21,75 % → 7,5 % |

### 2.5 Wie sich ein Level-Up anfühlt

1. **Moment**: 0,6 s Freeze-Frame, Konfetti in Fellfarbe, Fanfare, das Pferd macht den
   Galopp-Freudensprung aus dem Bestand-Rig; großes pastelliges "Level 7!".
2. **Sofort spürbar**: alle 3 Level +1 trainierbarer Punkt (der Balken "bereit zum Training!"
   pulsiert) — der nächste Ritt IST messbar besser, weil aufgestaute Stat-XP sich sofort in den
   freien Punkt entladen (Überlauf wird gebankt, Deckel 1 Punkt Vorrat).
3. **Meilensteine**: L5 Schleife "Jungstar", L10 exklusive Mähnenfrisur, L15 Sattel-Farbe gold
   gratis, L20 Fanpost-NPC besucht die Ranch, L25 goldenes Namensschild, L30 Statue-Deko +
   Titel "Legende von Goobyhausen".

---

## 3. Reitgefühl — das Wichtigste

Grundsatz: Der Bestand (`ride_feel.gd`) fühlt sich bereits nach "sanftem Fahrzeug" an. Das DLC
macht daraus **ein Tier**: Antritts-Kick, Untergrund, Erschöpfungs-Drama, Sprung-Timing, Tölt.

### 3.1 Gangarten & Beschleunigung

| Gangart | Ziel (m/s) | Antritt | Gefühl |
|---|---|---|---|
| Schritt | 1,7 (Bestand) | 2,0 m/s² | gemächliches Schaukeln, Kamera ruhig |
| Trab | 4,2 (Bestand) | 2,8 m/s² | deutliches 2,4-Hz-Nicken (Bestand), leichtes vertikales Hüpfen |
| Galopp | 8,5·Stat·Bindung | **Antritts-Kick**: 0,8 s lang 4,5 m/s² (=`ACCEL_AUF`·1,5), danach 3,0 | Schub ins Kreuz, FOV zieht 58→66° auf (Bestand), Staub 100 % |
| Tölt (nur Tölterle) | 5,8 | 3,0 m/s² | Nick-Amplitude 0,012 (fast glatt) bei 2,8 Hz — "schwebt" |
| Bremsen | — | 5,5 m/s² (Bestand `ACCEL_AB`) | willig; Vollstopp aus Galopp ≈ 1,5 s mit Rutsch-Staub |

### 3.2 Kamera & Körpergefühl

- Follow-Faktor `k = 4,5`, Abstand 5,4 m, Höhe 2,7 m, FOV 58–66° (alles Bestand — beibehalten).
- **Neu**: Galopp-Shake 0,03 m Amplitude bei 7 Hz (abschaltbar!), Landungs-Kick 0,06 m nach
  unten mit 0,15 s Ausklang, bei Erschöpfung sackt die Kamera 0,1 m tiefer.
- Kopfnicken je Gangart aus Bestand (`NICK_HZ`/`NICK_AMP`) bleibt die Basis der Immersion.

### 3.3 Hufgeräusche & Untergrund

Hufschlag-Momente liefert `RanchRideFeel.hufschlaege()` (Bestand) — je Untergrund Sample + Effekt:

| Untergrund | Sound | Lautstärke | Pitch | Physik-Effekt |
|---|---|---|---|---|
| Wiese | dumpfes *Tuck* | −6 dB | 0,9 | — |
| Sandplatz | weiches *Puff* | −4 dB | 1,0 | — |
| Holzbrücke | *Klock-klock* | +3 dB | 1,05 | — |
| Stein/Straße | helles *Klack* | 0 dB | 1,1 | — |
| Wasser (flach) | *Platsch* + Gischtpartikel | 0 dB | 1,0 | Tempo ×0,85 |
| Matsch | *Schmatz* | −2 dB | 0,8 | Tempo ×0,9 (Moosmähne ×0,95) |
| Schnee (Event) | gedämpftes *Fump* | −9 dB | 0,85 | Staub → Schneepuder |

### 3.4 Ausdauer & Erschöpfung

- Tank 100 (+5 je Ausdauerpunkt über 10), Galopp −7/s, Tölt −3/s, Regen +9/s unterhalb Trab,
  wieder angaloppieren erst ab 20 (alles Bestand/Kap. 2.4).
- **Erschöpfungsmoment** (Tank = 0): Zwangs-Trab (Bestand), dazu 2 s Schnauben mit
  Puste-Wölkchen, Ohren hängen, Kamera sackt ab, HUD-Balken blinkt sanft (kein Alarm-Rot —
  Gooby-Welt). Bei Laune < 40 zusätzlich −1 Bindung je Erschöpfung (max −3/Tag): Überreiten
  ist erlaubt, aber das Pferd "merkt" es.
- **Zweiter Wind**: 1×/Ritt bei Tank < 10 kurz anhalten + streicheln (Tipp aufs Pferd) → +25
  Ausdauer sofort, kleines Herzchen. Lehrt Pausen statt Dauergalopp.

### 3.5 Springen — Timing-Fenster mit Automatik-Netz

- Physik Bestand: vy 4,8 (+Stat), g −11,5 → Flugzeit 0,83 s, Höhe ~1,0 m, Weite = Tempo·0,83.
- Vor jedem Parcours-Hindernis liegt eine **Absprungzone** (Bodenmarkierung, ausblendbar):
  - **Perfekt**: Absprung 0,9–1,3 m vor dem Hindernis (bei 4,2 m/s ≈ 95-ms-Fenster; Federsprung
    +50 ms, mutig +30 ms) → +15 Punkte, Glitzerspur, kein Tempoverlust.
  - **Gut**: 0,5–1,9 m → sauberer Sprung.
  - **Zu früh/zu spät**: Stangenkontakt-Chance 60 %, Abwurf-Animation (Stange kullert, Pferd
    schüttelt Mähne — nie stürzt jemand).
  - **Verweigerung** nur unter `SPRUNG_MIN_TEMPO` 3,0 m/s (Bestand): Pferd stoppt weich davor.
- **Auto-Sprung-Assist** (Barrierearmut, Standard AN bei "Entspannt"): springt automatisch am
  Zonenanfang; Perfekt-Bonus bleibt manuellen Absprüngen vorbehalten (max 3 Sterne trotzdem
  erreichbar, nur die Bestenliste ist assistfrei markiert).

### 3.6 Touchscreen-Steuerung (Handyspiel!)

**Layout Standard ("Zwei Daumen"):**

| Zone | Element | Maße/Verhalten |
|---|---|---|
| links unten | virtueller Stick, **nur X-Achse lenkt** | Radius 64 dp, Deadzone 12 %, Auslenkung → `steer_input(−1..1)`; Stick erscheint dort, wo der Daumen aufsetzt ("floating") |
| rechts unten | Gangart-Wische | Wisch ↑ = `gait_up()`, Wisch ↓ = `gait_down()`; Mindestweg 24 dp innerhalb 250 ms |
| rechts unten | Sprung-Button | 72 dp, Tipp = `jump()`; pulsiert, wenn eine Absprungzone naht |
| rechts oben | Ausdauerbalken | Füllstand + Hufeisen-Symbol + Textur-Schraffur (nicht nur Farbe → farbfehlsicht-tauglich) |

**Alternative "Zügel-Modus" (eine Hand):** Auto-Vorwärts im Schritt; Tippen-und-Halten oben =
schneller (Halten 0–0,4 s: Trab, > 0,4 s: Galopp), Loslassen = eine Gangart runter; Lenken durch
Neigen (Gyro, ±15° = Vollausschlag, Deadzone 3°) ODER Wischen links/rechts.

**Barrierearmut (Einstellungen, alle einzeln schaltbar):**
- Auto-Sprung (3.5), **Lenkassistent** 0–30 % (Magnet zur Ideallinie in Wettbewerben),
  Auto-Trab (nie schneller als Trab), Kamera-Shake aus, Haptik an/aus,
  Buttons skalierbar 64–96 dp, Linkshänder-Spiegelung, hoher Kontrast fürs HUD.
- Kein Wettbewerb verlangt Multi-Touch; alles geht sequenziell mit einem Finger.

---

## 4. Zucht & Fohlen

### 4.1 Anbahnung

- Voraussetzung: **Zuchtstall** gebaut (Kap. 6), Stute + Hengst je **Level ≥ 8**, Bindung ≥ 45
  ("freund"), Laune ≥ 60, Stute nicht in Ruhezeit.
- Partner: eigenes Pferd, **Deckhengst eines Freundes** (Freund bekommt 10 % der Deckgebühr als
  Geschenk-Gold) oder NPC-Deckhengste (rotierende Liste, Gebühr 300–1 500 G nach Rarität).
- Das Paar verbringt einen "Kennenlern-Tag" auf der Fohlenweide (Herzchen-Vignette) — kein
  explizites Gameplay, reine Feier.

### 4.2 Vererbungsmodell (konkret)

**Farben:** je Gen-Ort erhält das Fohlen 1 zufälliges Allel pro Elternteil (Kap. 1.2).
Beispiel-Punnett — Mutter Palomino (`B/Z`, `h+/h0`), Vater Fuchs (`F/Z`, `h0/h0`):

| Ergebnis | Rechnung | Chance |
|---|---|---|
| braun | (B/F oder B/Z) · h0/h0 | 25,0 % |
| **palomino** | (B/F oder B/Z) · h+/h0 | 25,0 % |
| fuchs | Z/F · h0/h0 | 12,5 % |
| apricot | Z/F · h+/h0 | 12,5 % |
| schwarz | Z/Z · h0/h0 | 12,5 % |
| rauchgrau | Z/Z · h+/h0 | 12,5 % |

Glitzer: `g✨/g0 × g✨/g0` → 25 % Sternschnuppler-Look — **der** Community-Traum, erzüchtbar ohne
Kauf. Träger sieht man nicht an Buchstaben, sondern an einem NPC-Hinweis ("Ihre Mähne
schimmert… da steckt was drin!").

**Werte:** je Stat `Fohlen-Basis = round((Mutter-Basis + Vater-Basis) / 2) + Würfel`,
Würfel = **−1: 15 % · 0: 55 % · +1: 20 % · +2: 8 % · +3: 2 %**, geklemmt auf [1, 20].
Erwartungswert +0,27 je Generation: Zucht verbessert spürbar, explodiert aber nie.

**Rasse:** gleiche Rasse → reinrassig. Gemischt → **"Puschelmix"** mit gemitteltem Profil und
*beiden* Rassen-Eigenheiten in halber Stärke; 10 % Chance auf "Rassensprung" (Fohlen schlägt
ganz nach einem Elternteil, inkl. voller Eigenheit).

**Charakter:** Zug 1 und Zug 2 unabhängig: 45 % Mutter, 45 % Vater, 10 % zufällig neu;
Duplikat wird neu gewürfelt. Größe: Mittel der Eltern ±5 % Seed.

### 4.3 Trächtigkeit als Wartequest (48 h real)

- Grunddauer **48 h**; 5 **Fürsorge-Checkpoints** (alle ~9,6 h: Mash füttern + Bauch striegeln,
  je 30 s) verkürzen je −2 h → minimal **38 h**. Verpasste Checkpoints schaden NIE — sie
  verkürzen nur nicht.
- Sichtbar: Stute bekommt runden Bauch (Rumpf-Skalierung +12 %), NPC-Tierärztin Frau Dr. Huf
  schaut vorbei (Dialog-Flavor), Kalender-Icon am HUD zählt runter.
- Geburt = kleines Event: Stallszene, Fohlen steht wackelig auf (IK-Zittern), **Namenswahl**,
  Stammbaum-Eintrag, Foto-Moment für die Pinnwand.

### 4.4 Fohlen aufziehen (wächst sichtbar)

| Phase | Dauer (real) | Größe | Aufgaben (je 25 Pferde-XP) | Freischaltung |
|---|---|---|---|---|
| Fohlen | 3 Tage | 0,55 | 3× täglich streicheln, Milch geben, ab Tag 2 Halfter-Gewöhnung | — (nicht reitbar) |
| Jährling | 4 Tage | 0,75 | Führtraining-Minigame (1–3 Sterne → je 100 Stat-XP frei verteilbar), Hufe heben | Fohlenweide-Spiele |
| Jungpferd | 3 Tage | 0,90 | Longieren (Kreis-Timing), erste Ritte Schritt/Trab | reitbar, Werte-Deckel 15, Stat-XP ×1,2 ("lernt schnell") |
| ausgewachsen | dauerhaft | 1,00 | — | alles; **kein Altern darüber hinaus, kein Tod** |

Beine sind in den ersten Phasen überproportional lang (+15 % Relativlänge) — der klassische
niedliche Fohlen-Look mit dem Bestand-Rig (Skalierung je Körperteil, kein neues Modell nötig).

### 4.5 Stammbaum-Ansicht & Anti-Excel

- Baum über 3 Generationen: **Porträts, Fellfarben, Schleifen** — bewusst KEINE Zahlen im Baum.
  Statt Statspalten gibt es "Erbe"-Badges ("Omas Sprungtalent", "Papas Glitzer-Geheimnis").
- Anti-Excel-Regeln: max **2 Trächtigkeiten gleichzeitig** pro Ranch, Stuten-Ruhezeit **5 Tage**,
  Fohlenverkauf nur an den NPC-Ponyhof zum Festpreis **150 G** (Zucht ist Liebe, kein Markt),
  Gene erscheinen nirgends als Buchstaben-Tabelle, Würfelanteil (Kap. 4.2) macht "perfekte
  Planung" unmöglich — Überraschung bleibt der Kern.

---

## 5. Wettbewerbe & Training

### 5.1 Klassen, Belohnungen, Fortschritt

Fortschritt speichert im `spiele_progress.gd`-Muster (stars/best/cleared je Disziplin×Klasse).

| Klasse | ab Pferde-Level | Gold-Faktor | XP je Teilnahme |
|---|---|---|---|
| Holz | 1 | ×1,0 | 60 |
| Bronze | 5 | ×1,5 | 90 |
| Silber | 10 | ×2,0 | 130 |
| Gold | 18 | ×3,0 | 180 |
| Sternenklasse | 25 | ×4,0 | 240 |

Basis-Gold je Disziplin 40 G; Platzierung 1./2./3. = 100 / 60 / 35 % davon × Klassenfaktor;
Turnierschleife (Cosmetic, Kap. 7) ab Platz 3, je Disziplin×Klasse einmalig.
Reitplatz-Ausbau multipliziert Trainings-Coins ×1,1 (Bestand `reitplatz_parcours_coin_mult`).

### 5.2 Die 7 Disziplinen

**1) Springparcours** — 8–14 Hindernisse, Richtzeit je Kurs.
`Score = 1000 − 40·Abwürfe − 20·Verweigerungen − 5·max(0; Zeit−Richtzeit in s) + 15·Perfekt-Absprünge`.
Sterne: ≥ 900 / ≥ 750 / ≥ 550. Steuerung: Lenken + Gangart + Sprung-Timing (3.5).
Schwierigkeit: Hindernishöhe 0,6→1,1 m, engere Wendungen, Distanz-Kombinationen.
**Duell:** asynchroner **Geisterlauf** (5.3).

**2) Dressur** — Figurenfolge (Zirkel, Acht, Schlangenlinie, Halten, Rückwärtsrichten) auf
leuchtender Ideallinie. Je Figur: `Punkte = max(0; 100 − 50·(d̄/0,75) − 25·Gangartfehler)`
(d̄ = mittlere Abweichung von der Linie in m; Lenkassistent erlaubt, senkt Bestenlisten-Flag).
`Gesamt = Ø Figurpunkte + 10 Taktbonus`, wenn alle Gangartwechsel im Metronom-Fenster ±250 ms
liegen. Drei NPC-Gooby-Richter heben Zahlentafeln (Feier-Moment). Stat-Fokus: Gelassenheit +
Wendigkeit. **Duell:** Geisterlauf zeigt die Linie des Gegners als Farbspur.

**3) Geländeritt** — 1,2–2,5 km offene Strecke, 8–15 Flaggentore, Untergrundwechsel (3.3),
Wassergraben, feste Hindernisse. `Wertung = Zeit + 8 s je ausgelassenem Tor`; Erschöpfung ist
die eigentliche Gegnerin (Tank-Management, Zweiter Wind!). Sterne: ≤ Richtzeit / ≤ 110 % /
≤ 125 %. Stat-Fokus: Ausdauer. **Duell:** Geisterlauf.

**4) Grasbahn-Rennen** — 3 Runden Oval, 4–8 Teilnehmer.
Wertung = Zielreihenfolge; **Windschatten**: < 2 m hinter einem Pferd für 1 s → +3 % Tempo für
3 s (Überhol-Drama statt Gummiband). Stat-Fokus: Tempo + Antritts-Timing.
**Duell: LIVE** über die Node.js-Instanz (5.3); ohne Verbindung: 5 Geister + 2 NPCs.

**5) Westerntrail** — 6 Präzisionsaufgaben: Tor öffnen/schließen, Rückwärts durchs L, Stangen-
Slalom, Brücke, Planen-Feld, 360°-Kreisel. Je Aufgabe 0–10 P (Berührung −2, Auslassen 0);
`Zeitbonus = max(0; 20 − ⌈max(0; Zeit−90 s)⌉)` → Maximum 80. Steuerung: alles im Schritt/Trab,
Feingefühl statt Speed — der "ruhige" Wettbewerb. Stat-Fokus: Wendigkeit + Gelassenheit.
**Duell:** Geisterlauf (Geist wird bei Aufgaben transparent geparkt).

**6) Schau (Schönheitswettbewerb)** — DER Cosmetics-Showcase.
`Wertung = 0,4·Pflege + 0,3·Stil + 0,3·Kür` (je 0–100):
- **Pflege** = `(sauberkeit + Laune) / 2` — direkter Payoff des Bestand-Pflegesystems.
- **Stil** = `min(100; Σ Raritätspunkte + Setbonus + Themenbonus)`; Raritätspunkte pro
  angelegtem Teil: gewöhnlich 4 / selten 7 / episch 11 / legendär 16; komplettes Set +10;
  Wochen-Motto getroffen (z. B. "Blumenzauber") +15.
- **Kür** = Freiheitsdressur-Simon-Says: 5 Kommandos (Verbeugen, Drehen, Steigen, Kompliment,
  Kuss), je Timing-Treffer ±300 ms = 20 P.
**Duell: LIVE-Voting**: bis 8 Spieler stellen nacheinander vor, jeder vergibt 1 Herz
(nicht an sich selbst); Herzen = je +2 Zusatzpunkte (max +10). Stat-unabhängig → auch
Level-1-Pferde können gewinnen. Miniknopf/eitel glänzen hier.

**7) Tonnenrennen (Barrel Race)** — Kleeblatt um 3 Tonnen, fliegender Start.
`Wertung = Zeit + 5 s je umgeworfener Tonne`; Idealzeit ~24 s (Holz) bis ~17 s (Sternenklasse).
Der "noch ein Versuch!"-Kick: Läufe dauern < 30 s. Stat-Fokus: Wendigkeit + Antritt.
**Duell:** Geisterlauf, dazu Wochen-Blitzliga (beste Zeit der Woche je Klasse).

### 5.3 Mehrspieler-Technik (an `GOOBY-SERVER` andocken)

- **Geisterlauf (asynchron, Standard):** Aufzeichnung mit 10 Hz — Position (x, z als 2×
  float16), Heading (int8), Gangart (2 Bit), Sprungflag → ~130 B/s, ein 3-min-Lauf ≈ 24 KB.
  Upload an die Node.js-Instanz, Abruf: Bestenlisten-Geist + 3 Freunde-Geister, halbtransparent
  gerendert, keine Kollision. Funktioniert offline gegen lokal gespeicherte eigene Geister.
- **Live (Rennen, Schau-Voting):** Raum auf dem Node-Server (4–8 Spieler), Positionssync 10 Hz
  mit Client-Interpolation, keine Kollision (nur Windschatten-Abfrage serverseitig), Countdown-
  Start vom Server. Kein Voice/Chat — Emote-Rad mit 8 Gooby-Emotes (COPPA-freundlich).
- **Wochenliga:** je Disziplin×Klasse eine Bestenliste (Server), Reset montags; Top 10 % →
  Schleife "Ligastern", alle Teilnehmer → 50 G Trostgold.

### 5.4 Training (ohne Wettbewerbsdruck)

- **Freies Training** auf dem eigenen Hindernisparcours/Reithalle (Kap. 6): volle Stat-XP,
  keine Wertung, Richtzeit-Anzeige optional.
- **Longieren-Minigame** (Kreis-Timing, 60 s): +30 Stat-XP wahlweise, kostet 20 Frische.
- **Führanlage** (Kap. 6): passives Training für Pferde, die gerade nicht geritten werden.

---

## 6. Ranch-Ausbau auf dem Grid (expliziter Userwunsch)

Raster **16×16 Zellen** (1 Zelle = 3×3 m); Start: 10×10 frei, Erweiterung Nord 800 G, Ost
1 600 G. Objekte drehbar in 90°-Schritten, Wege/Deko frei platzierbar. Bestehende Käufe
(`wirtschaft.json`: boxen2/boxen3/reitplatz/weidezaun) werden 1:1 auf die neuen Stufen gemappt —
kein Fortschrittsverlust.

| Objekt (Fläche) | Stufe → Kosten (G) | Spürbarer Nutzen (Mechanik **und** Optik/Leben) |
|---|---|---|
| **Stallboxen** (2×3) | 1 inkl. · 2 → 400 · 3 → 900 · 4 → 1 800 | Kapazität 2/4/6/8 Pferde (Bestand `boxen_kapazitaet` + neue St. 4 mit Fohlenbox); ab St. 3 Laternen + Katze auf dem Heuboden, ab St. 4 schauen Pferde über die Boxentüren |
| **Weide/Paddock** (4×4) | 1 inkl. · 2 → 350 · 3 → 800 | St. 2 sattes Gras: hunger-Verfall ×0,85; St. 3 Kräuterweide: +1 Laune/h bis 70; sichtbar: Blumen, Pferde grasen/wälzen sich |
| **Weidezaun** | 1 → 250 (Bestand) · 2 → 600 · 3 → 1 200 | sauberkeit-Verfall ×0,8/×0,7/×0,6 (`weide_sauberkeit_mult`-Erweiterung); Optik Holz → weißer Lattenzaun → Blumenranken mit Schmetterlingen |
| **Wasserstelle** (1×1) | 1 → 150 · 2 → 400 · 3 → 900 | durst-Verfall ×0,7; St. 2 Brunnen: Weidepferde tränken sich selbst ab durst < 40; St. 3 Teich: Enten ziehen ein, Pferde planschen (+3 Laune, Gischt-Partikel) |
| **Heulager** (2×2) | 1 → 200 · 2 → 500 · 3 → 1 000 | Kapazität 12/24/48 Ballen; St. 2 Lagerkatze (Deko-NPC); St. 3 Heurutsche: Füttern vom Lager mit 1 Tipp für alle Boxen |
| **Waschplatz** (2×2) | 1 → 300 · 2 → 700 · 3 → 1 400 | Striegeln gibt +50 statt +35 (Schaumparty-Animation!); St. 2 Warmwasser: +2 Bonus-Bindung 1×/Tag/Pferd; St. 3 Föhn + Glitzerspray: +5 Schau-Pflegewert |
| **Führanlage** (3×3) | 1 → 600 · 2 → 1 300 · 3 → 2 600 | 1/2/3 Pferde laufen passiv: +40/+60/+80 Stat-XP pro Tag in den schwächsten Wert; sichtbar drehende Anlage, Pferde traben darin |
| **Reithalle** (5×4) | 1 → 1 500 · 2 → 3 000 · 3 → 5 000 | Training bei jedem Wetter; Dressur-Stat-XP +20 %; St. 2 Spiegelwand (Figurpunkte-Live-Vorschau) + Reitlehrerin Frau Wieherlich (Tages-Tipp-NPC); St. 3 Heim-Dressurturniere |
| **Hindernisparcours** (5×5) | 1 → 300 (Bestand Reitplatz) · 2 → 900 · 3 → 2 000 | St. 1 Trainings-Coins ×1,1 (Bestand); St. 2 verstellbare Hindernisse 0,6–1,1 m + Spring-Stat-XP +20 %; St. 3 Wassergraben + Zeitmessanlage → Heim-Geisterläufe |
| **Sattelkammer** (2×2) | 1 → 250 · 2 → 650 · 3 → 1 300 | St. 1 Outfit-Sets speichern (1-Tipp-Wechsel); St. 2 schaltet Slots **bandagen** + **kopfschmuck** frei; St. 3 Mannequin-Pferd mit Schau-Vorschauwertung |
| **Zuchtstall** (3×3) | 1 → 2 000 · 2 → 3 500 | schaltet Zucht frei (1 Trächtigkeit); St. 2: 2 Trächtigkeiten + Stammbaum-Wand (begehbare Ahnengalerie) |
| **Fohlenweide** (3×3) | 1 → 800 | Fohlen-Aufgaben vor Ort, Aufzucht-XP +15 %; Fohlen toben sichtbar miteinander (bis zu 3) |
| **Zuschauertribüne** (4×2) | 1 → 1 200 · 2 → 2 400 | Heim-Schau möglich, 6/12 NPC-Zuschauer klatschen + machen Fotos; St. 2 Heimturnier-Gold +15 %, Freunde-Geister sitzen als Zuschauer |
| **Deko: Beete/Wege/Bänke** (1×1) | 40–120 je Stück | je 5 Deko-Objekte +1 Stilpunkt bei Heim-Schauen (max +10); Bienen und Schmetterlinge folgen den Beeten |

**Leben statt Zahlen:** Jede Stufe verändert hörbar/sichtbar etwas (neue Ambient-Sounds,
NPC-Kommentare der Postbotin: "Ein Teich! Darf ich die Enten füttern?"). Pferde *benutzen*
die Objekte sichtbar (Selbsttränken, Wälzen, Führanlage) — die Ranch wirkt bewohnt, nicht
wie ein Menü.

---

## 7. Cosmetics (44 Vorschläge)

Slots: `sattel`, `decke`, `halfter` (Bestand) + neu `bandagen`, `kopfschmuck`, `maehne`
(Frisur), `schweif`, `hufglanz` sowie **Gooby-Reitkleidung** (helm/jacke/stiefel) und
**Turnierschleifen** (Boxenwand, nicht kaufbar). Preisbänder: gewöhnlich 60–150 G, selten
200–450 G, episch 500–1 200 G, legendär 2 000–4 000 G oder nur erspielbar.

| # | Item | Slot | Rarität | Quelle | Stil-Notiz |
|---|---|---|---|---|---|
| 1 | Klassiker-Sattel (5 Farben, Bestand) | sattel | gewöhnlich | Shop 120 (gold ×2) | Bestand behalten |
| 2 | Wanderreitsattel mit Satteltaschen | sattel | gewöhnlich | Shop 150 | Taschen wackeln im Trab |
| 3 | Westernsattel „Kaktusblüte" | sattel | selten | Shop 320 | Fransen + Kaktus-Prägung |
| 4 | Turniersattel „Silberdistel" | sattel | selten | Springen Bronze, Platz 1 | silberne Nähte |
| 5 | Ponyhof-Sattel mit Herzsteppung | sattel | selten | Shop 260 | rosa Pastell |
| 6 | Wolkensattel | sattel | episch | Shop 900 | sitzt auf einer Mini-Wolke, wippt |
| 7 | Sternenstaub-Sattel | sattel | legendär | Sternenklasse Springen | Glitzerpartikel-Spur |
| 8 | Karodecke rot-weiß | decke | gewöhnlich | Shop 80 (Bestand-Preis) | Picknick-Look |
| 9 | Erdbeer-Decke | decke | gewöhnlich | Shop 110 | Erdbeermuster + grüner Rand |
| 10 | Regenbogen-Fransendecke | decke | selten | Shop 300 | Fransen flattern im Galopp |
| 11 | Bienen-Decke | decke | selten | Event „Blumenzauber" | 2 Deko-Bienen folgen |
| 12 | Sternennacht-Decke | decke | episch | Shop 750 | leuchtet nachts schwach |
| 13 | Drachendecke | decke | episch | Geländeritt Gold, Platz 1 | Schuppenmuster, Rauch-Wölkchen |
| 14 | Blümchenhalfter | halfter | gewöhnlich | Shop 60 (Bestand-Preis) | Gänseblümchen am Backenstück |
| 15 | Seil-Halfter Western | halfter | gewöhnlich | Shop 90 | geflochten |
| 16 | Glöckchen-Trense | halfter | selten | Shop 240 | klingelt leise im Trab |
| 17 | Lack-Trense schwarz-glanz | halfter | selten | Dressur Bronze, Platz 1 | Turnier-Chic |
| 18 | Gold-Trense | halfter | episch | Shop 520 (gold ×2-Muster) | Bestand-Goldlogik |
| 19 | Pastell-Bandagen (4er-Set) | bandagen | gewöhnlich | Shop 70 | rosa/mint/flieder/gelb |
| 20 | Ringel-Bandagen | bandagen | gewöhnlich | Shop 90 | Zuckerstangen-Look |
| 21 | Glitzer-Bandagen | bandagen | selten | Schau Bronze, Platz 1 | Funkel-Shader |
| 22 | Reflektor-Bandagen | bandagen | selten | Shop 280 | leuchten bei Nachtritten |
| 23 | Turnierzöpfchen | maehne | gewöhnlich | Shop 100 | 8 Mini-Zöpfe mit Gummis |
| 24 | Wellenmähne | maehne | gewöhnlich | Shop 120 | frisch gebrusht |
| 25 | Doppelzopf mit Schleifen | maehne | selten | Shop 260 | 2 Schleifen in Wunschfarbe |
| 26 | Punk-Bürste | maehne | selten | Tonnenrennen Silber, Platz 1 | aufgestellte Mähne |
| 27 | Blumen-Flechtmähne | maehne | episch | Schau Silber, Platz 1 | eingeflochtene Blüten regnen Blätter |
| 28 | Regenbogen-Strähnen | maehne | episch | Shop 800 | Farbverlauf, im Wind sichtbar |
| 29 | Blumenkranz Gänseblümchen | kopfschmuck | gewöhnlich | Shop 80 | DER Sommer-Look |
| 30 | Blumenkranz Rosen | kopfschmuck | selten | Shop 320 | tiefrot, Blütenblätter rieseln |
| 31 | Sonnenhut mit Ohrlöchern | kopfschmuck | selten | Shop 350 | Strohhut, wippt |
| 32 | Pompon-Ohrenschützer | kopfschmuck | gewöhnlich | Winter-Event | gestrickt |
| 33 | Rentier-Geweih | kopfschmuck | selten | Winter-Event | mit Glöckchen |
| 34 | Einhorn-Glitzerhorn | kopfschmuck | episch | Schau Gold, Platz 1 | Regenbogen-Schimmer |
| 35 | Schweifschleife Satin | schweif | gewöhnlich | Shop 60 | Turnier-Klassiker |
| 36 | Glitzerspray Schweif | schweif | selten | Shop 300 | Funkeln bei jedem Wedeln |
| 37 | Leucht-Sternchen | schweif | episch | Wochenliga Top 10 % | kleine Sterne schweben hinterher |
| 38 | Huf-Klarlack | hufglanz | gewöhnlich | Shop 60 | dezenter Glanz |
| 39 | Gold-Hufe | hufglanz | episch | Rennen Gold, Platz 1 | goldene Hufschlag-Fünkchen |
| 40 | Regenbogen-Hufe | hufglanz | legendär | Sternenklasse-Liga Saisonsieg | bunte Hufabdrücke bleiben 3 s |
| 41 | Reithelm klassisch (5 Farben) | Gooby: helm | gewöhnlich | Shop 100 | Pflicht-Look, süß |
| 42 | Melone mit Blume | Gooby: helm | selten | Dressur Silber, Platz 1 | Chaplin-Chic |
| 43 | Cowboyhut | Gooby: helm | selten | Westerntrail Bronze, Platz 1 | mit Kordel |
| 44 | Turnierjackett blau | Gooby: jacke | selten | Shop 400 | Goldknöpfe |
| 45 | Gelbes Regencape | Gooby: jacke | gewöhnlich | Shop 130 | flattert im Galopp |
| 46 | Glitzer-Umhang | Gooby: jacke | legendär | Schau Sternenklasse, Platz 1 | Sternschnuppen-Schleppe |
| 47 | Gummistiefel rot | Gooby: stiefel | gewöhnlich | Shop 90 | Matsch-Partikel beim Laufen |
| 48 | Turnierstiefel schwarz | Gooby: stiefel | selten | Shop 350 | blitzblank poliert |
| 49–58 | Turnierschleifen Holz→Stern je Disziplin | Boxenwand | — | nur erspielbar | Trophäen-Cosmetic, nicht handelbar |

**Set-Boni (nur Schau-Stilpunkte, nie Stats):** z. B. „Blumenzauber" (29+27+11) +10 Stil,
„Western" (3+15+43) +10, „Sternennacht" (7+12+37+46) +10. Cosmetics geben NIEMALS
Leistungsvorteile — Fairness-Grundsatz des Projekts.

---

## 8. Datenskizze (additiv am Bestand, kein Schema-Bruch)

`RanchPlaySlices._normalize_pferd()` erhält fremde Schlüssel verbatim — die DLC-Felder können
darum additiv ins Pferde-Dict (Migration = Defaults für Bestandspferde):

```text
pferd += {
  "rasse": "puschelhufer",
  "gene": {"g": ["B","Z"], "h": ["h0","h+"], "s": ["s0","s0"], "glitzer": ["g0","g✨"]},
  "abzeichen": {"blesse": true, "socken": [1,0,0,1], "maehnenform": "puschel"},
  "charakter": ["verspielt", "verfressen"],   # [offen, versteckt]
  "groesse": 1.03,                             # Seed-Varianz
  "stats": {"tempo": 10, "ausdauer": 10, "sprungkraft": 10, "wendigkeit": 10, "gelassenheit": 10},
  "trainiert": {"tempo": 0, ...},              # gekaufte Punkte 0–10
  "statXp": {"tempo": 0.0, ...},
  "frische": {"tempo": 100.0, ...}, "frischeTag": "",   # bondTag-Muster
  "level": 1, "xp": 0.0,
  "alter": "ausgewachsen",                     # fohlen|jaehrling|jungpferd|ausgewachsen
  "eltern": ["pferdId|npcId", "..."], "geborenAm": 0,
}
```

Neue Balance-Blöcke wandern nach `wirtschaft.json`-Muster in eigene JSONs
(`zucht.json`, `wettbewerbe.json`, `ausbau_grid.json`) unter dem `ranchplay`-Balance-Namespace —
Content-Pack-updatebar wie der Bestand.

---

## 9. Offene Fragen an die anderen Agenten / den User

1. Sollen NPC-Deckhengste rotieren (Wochenrhythmus) oder saisonal (Event-exklusive Gene)?
2. Live-Rennen: 8 Spieler ok für die Node-Instanz, oder konservativ mit 4 starten?
3. Wochen-Motto der Schau global (Server) oder lokal würfelbar (offline-freundlich)?
4. Tölt als Tölterle-Exklusiv belassen oder per teurem Trainings-Item erlernbar machen (2 500 G)?

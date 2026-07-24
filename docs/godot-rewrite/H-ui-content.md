# H — UI & Content (Godot 4.4) — konkretes Design

Ideen-Improver H. Bereich: USER-WISHES §H komplett + Sticker/Cosmetics/Save-Migration.
Referenz verifiziert in `/workspace/GOOBY`: Design-System `src/ui/styles.css` (`.ac-*`-Kit,
`--thm-*`-Screen-Themes, Token-Block Zeile 15–147), 85 Sticker-PNGs in
`public/assets/stickers/` (84 regulär + 1 geheim, IDs aus `src/data/stickers.js`),
44 Achievements (`src/data/achievements.js`), 42 Outfits (`src/data/outfits.js`),
7 Fellfarben (`SKIN_TABLE` in `src/data/constants.js`), Save-Schema **v4** komplett aus
`src/core/save.js` analysiert (plus additive Slices `vacation`/`themePark` aus
`src/systems/vacation.js`/`themePark.js`), Capacitor-AppId `com.permissionmaxed.gooby`
(`capacitor.config.json`), G13-Preferences-Mirror (save.js Z. 126–165), Dev-Panel-Save-Export
(devPanel.js Z. 1136, Freischaltung: 5× Tap auf Sprachsegment „Auto“, settingsScreen.js Z. 690).

---

## 1) Godot-UI-Kit „AC 2.0“

### 1.1 Theme-Ressource (`res://theme/ac_theme.tres` + `theme_builder.gd`)

Ein Theme wird **im Code gebaut** (`theme_builder.gd`, `@tool`-Skript erzeugt die .tres),
damit alle Tokens EINE Quelle haben (`res://theme/tokens.gd`, const-Dictionary). Tokens
1:1 aus styles.css übernommen:

| Token | Wert (aus styles.css) | Godot-Verwendung |
|---|---|---|
| `BG_CREAM` | `#FFF6EC` | ClearColor / Screen-Wash |
| `PAPER` / `PAPER_SHADE` | `#FFFAF2` / `#F6EAD8` | Panel-Faces / Inset-Wells |
| `PINK` / `PINK_DARK` | `#FF7BA9` / `#E05F8D` | Primär-Button |
| `TEAL` / `TEAL_DARK` | `#59C9B9` / `#3FA89A` | Sekundär-Button |
| `YELLOW` / `YELLOW_DARK` | `#FFD166` / `#E0B04A` | Akzent / Coins |
| `LEAF` / `LEAF_DARK` | `#8FD06C` / `#6DB54E` | CTA / aktiver Tab |
| `BROWN` (Ink) | `#4A3B36` | Text; `INK_SOFT` = 72 % Alpha, `INK_FAINT` = 55 % |
| `GOLD` / `DANGER` | `#FFD34D` / `#E0655F` | Belohnung / destruktiv |
| `STAT_*` | hunger `#FF9F5A`, energy `#FFD166`, hygiene `#6EC6FF`, fun `#FF7BA9` | ProgressBar-Fills |
| Radien | Karte 28 px, Karte-groß 36 px (≙ 1.75rem), Row 14 px, Button = Pill | StyleBoxFlat `corner_radius` |
| Schatten | `shadow_color rgba(74,59,54,.18)`, `shadow_size 10` | StyleBoxFlat-Shadow |
| Motion | Pop 0.18 s, Sheet 0.24 s, Spring `Tween.TRANS_BACK/EASE_OUT` | Tweens |

**Font:** Baloo 2 Variable (bereits im Repo als woff2, SIL OFL — für Godot die TTF von
Google Fonts bundlen, `res://theme/fonts/Baloo2-VariableFont_wght.ttf`; Fallback
`NotoSans` für fehlende Glyphen). Gewichte: 800 Headlines, 700 Buttons, 600 Body.

**Komponenten (Theme-Types + StyleBoxFlat-Spezifikation):**

- `Button` (Pill): Fill Identitätsfarbe, `corner_radius 999`, **Boden-Lippe** =
  `border_width_bottom 4`, `border_color` = Fill × 0.82 (ersetzt den CSS-Inset-Shadow).
  `pressed`: Lippe 2 px, Content-Offset +2 px, Scale-Tween 0.96 (Skript `SquishButton.gd`
  extends Button — EIN Skript, überall wiederverwendet). Varianten als Theme-Variations:
  `BtnPink`, `BtnTeal`, `BtnYellow` (Ink-Text), `BtnGhost` (Paper + Outline 8 % Ink).
- `PanelContainer` „AcCard“: Paper, Radius 28, Shadow-Pop; Variation „AcWell“:
  Paper-Shade, Radius 14, kein Schatten (Inset-Flächen).
- `AcChip` (Variation von Button): Höhe 40 px, Radius 999, Paper + Outline; `ChipLeaf`
  (Leaf-Fill, weißer Text), `ChipSky` (`#CFE9F5`).
- `TabBar` „AcTabs“: Träger = Paper-Pill; aktiver Tab = Leaf-Pill mit weißem Text
  (wie `.ac-tab-active`); Icons 20 px aus dem Icon-Set.
- `ProgressBar` „StatBar“: Track `rgba(74,59,54,.10)`, Fill = Statfarbe, Radius 999.
- `AcStamp` (Passstempel), `AcRibbon` (Ecken-Band „NEU!“), `AcEmptyState`
  (zentriertes Icon 48 px + INK_FAINT-Text) — 1:1 die `.ac-*`-Klassen als Szenen.
- Touch-Floor: **überall `custom_minimum_size ≥ 48×48 px`** (Web-Regel übernommen).

### 1.2 Animierte Wallpaper (der „schräge Slow-Scroll“)

EIN CanvasItem-Shader ersetzt das komplette `--thm-drift`-CSS (styles.css Z. 5603 ff.):

```glsl
shader_type canvas_item;
uniform sampler2D tile : repeat_enable, filter_linear_mipmap;
uniform vec2  drift      = vec2(-0.010, 0.007); // Tiles/Sekunde, schräg (~100 s/Tile)
uniform float tile_count = 3.0;                  // Kacheln über die kürzere Achse
uniform float opacity    = 0.06;                 // Web-Guardrail: ≤ 6 %
uniform vec4  wash : source_color = vec4(1.0);   // Screen-Grundfarbe darunter
void fragment() {
    vec2 uv = UV * tile_count * vec2(1.0, SCREEN_PIXEL_SIZE.x / SCREEN_PIXEL_SIZE.y);
    vec4 c = texture(tile, uv + TIME * drift);
    COLOR = mix(wash, vec4(c.rgb, 1.0), c.a * opacity);
}
```

Szene `AcBackdrop.tscn` = `ColorRect` (Wash) + `TextureRect` (Shader-Material); jede
Screen-Szene instanziert sie und setzt nur `tile` + `wash` + Akzent. Die 12 vorhandenen
Patterns (`public/assets/acui/pattern_*.png`, 512×512 seamless) werden 1:1 übernommen;
**neue Patterns nötig** (→ §8): travel/flughafen, stadt, teich, freunde, post, baumarkt,
markt, news, gvz, gobnom, goobyman. Guardrails aus dem Web übernehmen: 80–120 s pro
Kachelperiode, linear, Reduced-Motion-Setting stoppt `drift`.

### 1.3 Haupt-Layout NEU (Entscheidung + 2 Varianten je Orientierung)

Analyse alt (hud.js): Stats als Pill-Zeile OBEN quer, 6+ quadratische Buttons UNTEN
mittig — Probleme: Buttons außerhalb der Daumenzone (Mitte unten ist am weitesten vom
Daumen), Stats fraßen die Raum-Sicht oben an, Wrap-Chaos bei uiScale 130.

**Prinzip:** Stats sind *Glance-Info* (klein, Ecke reicht — Details per Tap), Aktionen
gehören in die *Daumenzone* (Bogen um die untere Ecke / Bildschirmkanten im Querformat).

**Hochkant — Variante P1 „Daumen-Bogen“ (GEWÄHLT):**

```
┌──────────────────────────────┐
│ (Lv◔12)▪▪▪▪  ᴳ427🥕    ⚙    │ ← Status-Kapsel: Ring+4 Mini-Bars+Coins (Tap=Sheet)
│                              │
│                              │
│          3D-RAUM             │
│        (volle Höhe!)         │
│                              │
│ [Wo ist Gooby?]           👁 │ ← kontextuelle Chips links · Interaktions-Auge rechts
│                              │
│                    ╭────╮    │
│              ╭────╮│🎮  │    │
│        ╭────╮│✈  │╰────╯    │ ← Bogen um die rechte untere Ecke,
│  ╭────╮│🌱  │╰────╯╭────╮   │   Radius ≈ 9 rem = Daumenradius
│  │📱  │╰────╯╭────╮│👤  │   │
│  ╰────╯      │🏠  │╰────╯   │
│              ╰────╯          │
└──────────────────────────────┘
 📱 IGohbie · 🏠 Haus/Bauen · 🌱 Garten · ✈ Reise · 🎮 Arcade · 👤 Profil
```

**Hochkant — Variante P2 „Split-Dock“ (verworfen):** Stats oben links, Dock als 2×3-Grid
unten mittig. Verworfen: Grid-Mitte = tote Daumenzone, exakt der alte Fehler.

**Querformat — Variante L1 „Cockpit“ (GEWÄHLT, Querformat ist bevorzugt):**

```
┌────────────────────────────────────────────────────┐
│ (Lv◔12)                                       ⚙   │
│ ▮hunger                                      ╭──╮  │
│ ▮energy          3D-RAUM                     │🏠│  │
│ ▮hygiene       (Breite komplett              ╰──╯  │
│ ▮fun            für den Raum)                ╭──╮  │
│ ᴳ427🥕                                       │🌱│  │
│                                              ╰──╯  │
│                                              ╭──╮  │
│ [Wo ist Gooby?]                              │✈ │  │
│                                              ╰──╯  │
│ ╭──╮                                         ╭──╮  │
│ │📱│                                    👁   │🎮│  │
│ ╰──╯                                         ╰──╯  │
└────────────────────────────────────────────────────┘
  links: Stat-Spalte kompakt vertikal (Glance) · rechts: Button-Spalte am rechten Daumen
  👤 Profil liegt als 5. Button unter 🎮 (Spalte scrollt nie — max 5 + Auge)
```

**Querformat — Variante L2 „Radial“ (verworfen als Primär):** Halb-Radialmenü um eine
Pfoten-Taste unten rechts. Verworfen: schlechtere Entdeckbarkeit (Zielgruppe!), 2 Taps
für alles, Labels schwer unterzubringen. **Aber:** Long-Press auf die 🏠-Taste öffnet
optional ein Quick-Wheel (Füttern/Waschen/Schlafen) als P2-Bonus — Geste, kein Ersatz.

Begründung der Wahl: beide gewählten Varianten legen die 5 Hauptbuttons an die
natürliche Ruheposition des rechten Daumens (Bogen bzw. Kante), lassen den Raum maximal
frei (User-Wunsch §A „Raum nutzt den Platz“), und die Status-Kapsel/Spalte ist auf
einen Blick lesbar, expandiert aber erst auf Tap (Bottom-Sheet mit großen Bars + Pflege-
Buttons). Ein `HudLayout.gd` besitzt BEIDE Layouts als Container-Presets und schaltet
bei `size_changed`/Rotation um (gleiche Buttons-Nodes, nur Reparenting).

**Buttons-Bereinigung (final):**

| Alt | Neu |
|---|---|
| Ton-Knopf | **weg** — nur noch Settings (⚙ oben rechts) |
| Garderobe-Knopf | **weg** — Anpassen über Spiegel im Haus (§F) + Shop |
| „Laden“ | **„Reise“** (✈) — öffnet Stadt/Orte-Auswahl + Flughafen |
| Erfolge-Knopf | **weg** — Erfolge wohnen im Profil (§2) |
| — | **NEU: Interaktions-Auge 👁** — Toggle, hebt alles Interagierbare im Raum hervor (Outline-Shader-Puls + kleine Icon-Bubbles); schaltet sich nach 8 s selbst aus |
| — | **NEU: 📱 IGohbie** (unten links, §E-Team liefert Inhalt) |

---

## 2) Profil-Tab NEU, Reisepass 2.0, 5.0-News, Flughafen-UI

### 2.1 Profil-Tab (Sektionen, eine scrollende AcCard-Spalte)

1. **Reisepass-Karte** (Header, §2.2) — Tap flippt sie groß.
2. **Werdegang**: Level-Ring groß, XP-Bar, „Bürger von Goobyhausen seit …“.
3. **Statistiken**: Spielzeit, Münzen verdient/ausgegeben, Distanz, Fotos, Reisen
   (aus `profile.*` + Counters; Migration behält alle Zähler, §5).
4. **Erfolge** (NEU hier): 44 Erfolge als Grid von AcStamps, Filter-Chips
   „Alle/Offen/Geschafft“; Fortschritts-Pill „31/44“.
5. **Stickerbuch-Schnellzugriff**: Karte „n/126 Sticker“ + letzte 3 neue → öffnet Album.
6. **Web-Rekorde (Legacy)**: importierte Minigame-Bestwerte als nostalgische Karte
   „Aus der alten Welt 🕰“ (nur sichtbar nach Migration).
7. **Freunde** (Hook für §C-Team): Platzhalter-Karte.

### 2.2 Reisepass 2.0 (witziger + niedlicher + FOTO)

Aufbau wie ein echter Kinderpass, als flippbare Karte (3D-Flip-Tween):

- **Cover** (zu): Prägeoptik „GOOBYHAUSEN · REISEPASS“, Wappen = Gooby-Kopf mit Karotte
  (generiertes Asset), Pastell-Bordeaux `#C98BA8`.
- **Innen links:** **Passfoto-Rahmen** — der Spieler wählt ein Foto aus dem Fotomodus
  (Galerie-Picker, quadratischer Crop, Serrated-Stamp-Rahmen + „bürokratisch schief“
  aufgeklebter Look, −2° Rotation). Ohne Foto: gestempelte Silhouette + Hinweis
  „Foto beim POW!-Fotomodus knipsen!“. Felder: Name (Spieler), Spitzname (Gooby),
  Fellfarbe („Besondere Merkmale: extrem flauschig“ — Gag-Zeile rotiert aus 10 Texten),
  Level, Beitrittsdatum.
- **Innen rechts:** Stempelseite — datengetriebene AcStamps (Urlaube je Ziel, Funkelpark,
  Erfolge-Meilensteine, „5.0 UMZUG“-Sonderstempel nach Save-Import!), MRZ-Gag-Zeile unten
  (`GOOBY<<FLAUSCH<PDF417<NOM<NOM<…` — Konzept aus Web-B3 übernehmen).

### 2.3 5.0-Neuigkeiten-Panel

Wie die whatsNew-Panels der Web-App (`onboarding.whatsNew4Seen`-Muster): Save v5 hat
`onboarding.whats_new_5_seen`; **frisch = true, importiert/migriert = false** → Panel
zeigt sich genau einmal. 4–5 Seiten (PageIndicator-Dots, Swipe): „Alles neu gebaut!“,
„Bau dein Haus!“, „Reise & Stadt“, „Freunde“, „Dein alter Spielstand ist umgezogen 📦“
(nur nach Import). Header-Illustration generiert (§8).

### 2.4 Flughafen-UI im Design-System

Alte Web-Airport-UI passte nicht (User) → Neu als **Abflugtafel**: AcCard mit
Flip-Board-Zeilen (Godot: Label-Roll-Tween pro Zeichen, dezent), je Reiseziel eine
Zeile „GOOBY AIR · STRAND · 3 TAGE · ᴳ180“; Tap → Ziel-Karte (Pattern-Hintergrund
travel, Illustration, Nutzen-Box „Was bringt mir Urlaub?“ — §E-Team definiert den
Nutzen, UI reserviert die Box), Bestätigen-Dialog mit Warnung (User-Wunsch §E).
Boarding-Pass-Optik für die Buchungsbestätigung (Barcode-Gag, abreißbarer Abschnitt).

---

## 3) STICKER-OFFENSIVE

### 3.1 Entscheidung: Text NIE ins generierte Bild

**ENTSCHIEDEN: Beschriftung als Godot-Label ÜBER dem Bild, niemals im Bild.**
Begründung: (a) generierter Text ist fehleranfällig (kaputte Glyphen ruinieren einen
ganzen Batch), (b) deutsche Umlaute/ß besonders riskant, (c) Namen bleiben per
Content-Pack/Lokalisierung änderbar ohne Asset-Neubau, (d) einheitliche Baloo-2-Typo.
Die Sticker-Szene (`StickerCard.tscn`) rendert: Art-PNG + gewölbtes Namens-Band unten
(Label auf `Path2D`-Bogen oder simpel: Pill-Label, −3° Rotation, weißer Rand).
**Einzige Ausnahme:** Onomatopoesie/Logos als Bildbestandteil (z. B. „POW!“, „NOM!“),
weil das Art ist und einzeln reviewt wird — nie Fließtext, nie Namen.

### 3.2 Germanisierung — Migrationsliste ALLE 85 (ID bleibt, Name wird deutsch)

IDs bleiben stabil (Save-Kompatibilität!), nur Anzeigenamen ändern sich. ✎ = neuer Name,
✓ = vorhandener DE-Name übernommen (aus `strings/v3/v5/v6-stickers.js` verifiziert):

| # | ID | Deutscher Name (final) | |
|---|---|---|---|
| 1 | firstNom | Erster Happs | ✓ |
| 2 | squeakyClean | Blitzeblank | ✓ |
| 3 | ballBuddy | Ballfreund | ✓ |
| 4 | sleepyhead | Schlafmütze | ✓ |
| 5 | tenNights | Zehn gute Nächte | ✓ |
| 6 | grumpMorning | Morgenmuffel | ✓ |
| 7 | feverFace | Fieberbäckchen | ✓ |
| 8 | drGooby | Beim Tierarzt | ✓ |
| 9 | firstSprout | Erster Spross | ✓ |
| 10 | rainyDay | Regentag | ✓ |
| 11 | starGazer | Sternengucker | ✓ |
| 12 | sayCheese | Bitte lächeln! | ✓ |
| 13 | bigTen | Level 10! | ✓ |
| 14 | quarterClub | Level 25! | ✓ |
| 15 | maxLevel | Level 40! | ✓ |
| 16 | roadTripper | Spritztour | ✓ |
| 17 | towTrouble | Abschlepp-Ärger | ✓ |
| 18 | goldenCatch | Goldener Fang | ✓ |
| 19 | discoGooby | Disco-Gooby | ✓ |
| 20 | holeInOneHero | **Loch in eins!** | ✎ (war „Hole-in-one“) |
| 21 | parcelPro | Paket-Profi | ✓ |
| 22 | freshDrip | Frisches Fell | ✓ |
| 23 | fullFit | Komplett-Look | ✓ |
| 24 | maxFloof | **Maximal flauschig** | ✎ (war „Maximaler Floof“) |
| 25 | nutellaGlob | Nutella-Zeit | ✓ |
| 26 | cakeBoss | Tortenboss | ✓ |
| 27 | surfStar | **Einkaufswagen-Surfer** | ✎ |
| 28 | albumMaster | **Album-Meister** | ✎ |
| 29 | snackStack | **Snackturm** | ✎ (war „Snack-Stapel“) |
| 30 | cleanMachine | Putzmaschine | ✓ |
| 31 | bellyLaugh | Bauchkitzler | ✓ |
| 32 | dreamTeam | Traumteam | ✓ |
| 33 | gardenBasket | Erntekorb | ✓ |
| 34 | greenThumb | Grüner Daumen | ✓ |
| 35 | seedStarter | **Saathelfer** | ✎ |
| 36 | photoWall | Fotowand | ✓ |
| 37 | roadRegular | Stammfahrer | ✓ |
| 38 | ballStorm | Bälleregen | ✓ |
| 39 | safeDriver | Sicherer Fahrer | ✓ |
| 40 | deliveryAce | Paket-Ass | ✓ |
| 41 | modifierMischief | **Bonus-Schabernack** | ✎ |
| 42 | carrotChampion | Karotten-Champion | ✓ |
| 43 | memoryMaster | Memory-Meister | ✓ (Memory = dt. Spielname) |
| 44 | saysSuperstar | **„Gooby sagt“-Superstar** | ✎ |
| 45 | questScout | **Aufgaben-Pfadfinder** | ✎ |
| 46 | getWellSoon | Gute Besserung | ✓ |
| 47 | radioBunny | Radiohase | ✓ |
| 48 | codeWhisperer | Code-Flüsterer | ✓ |
| 49 | beachPostcard | Strandpostkarte | ✓ |
| 50 | harborPostcard | Hafenpostkarte | ✓ |
| 51 | bakeryPostcard | Bäckereipostkarte | ✓ |
| 52 | nightSkyPostcard | Sternenhimmel-Postkarte | ✓ |
| 53 | frequentFlyer | Vielflieger | ✓ |
| 54 | penPal | Brieffreund | ✓ |
| 55 | parkFirstVisit | Funkelpark-Debüt | ✓ |
| 56 | loopStar | Looping-Star | ✓ |
| 57 | handsUp | Hände hoch! | ✓ |
| 58 | candyDay | Naschtag | ✓ |
| 59 | nightLights | Nachtlichter | ✓ |
| 60 | parkExplorer | Park-Entdecker | ✓ |
| 61 | lanternKeeper | Laternenwächter | ✓ |
| 62 | snailCourier | Schneckenkurier | ✓ |
| 63 | ghostWhisperer | Geisterflüsterer | ✓ |
| 64 | harborMaster | Hafenmeister | ✓ |
| 65 | rocketHero | Raketenheld | ✓ |
| 66 | pipeDreamer | Rohrträumer | ✓ |
| 67 | weekStreak | Volle Woche | ✓ |
| 68 | medsMaster | Medizin-Meister | ✓ |
| 69 | marketDay | Markttag | ✓ |
| 70 | memoryKeeper | Erinnerungshüter | ✓ |
| 71 | interiorDesigner | Einrichtungsprofi | ✓ |
| 72 | storyTeller | Geschichtenerzähler | ✓ |
| 73 | teaTime | Teestunde | ✓ |
| 74 | pancakeMountain | Pfannkuchenberg | ✓ |
| 75 | burgerBoss | Burger-Boss | ✓ |
| 76 | veggieChef | Gemüsekoch | ✓ |
| 77 | cakeParade | Tortenparade | ✓ |
| 78 | nougatFlood | Nougatflut | ✓ |
| 79 | bestBuddies | **Beste Freunde** | ✎ (war „Beste Kumpel“) |
| 80 | inseparable | Unzertrennlich | ✓ |
| 81 | tickleTornado | Kitzeltornado | ✓ |
| 82 | monthStreak | Treues Herz | ✓ |
| 83 | hatParade | Hutparade | ✓ |
| 84 | bigSpender | Großeinkäufer | ✓ |
| 85 | herzGooby (geheim) | **Herz-Gooby** | ✎ |

Flavor-/Hint-Texte: alle 85 DE-Texte aus den strings-Modulen übernehmen, die ~9 mit
Anglizismen im Rewrite-Datenfile glätten (Arbeitspaket „sticker_texts_de.json“).

### 3.3 NEUE Sticker-Sets (7 Sets × 6 = 42 neue, Buch: 126 + 1 geheim)

Alle Bild-Specs teilen den **Serien-Stil** (an die 85 Bestands-PNGs angelehnt):
„512×512 PNG, transparenter Hintergrund, Sticker-Look mit dickem weißem Rand und
Pastell-Innenoutline, niedlicher flauschiger cremefarbener Hase GOOBY (runde Ohren,
rosa Wangen) als Hauptmotiv, flache Farben + weiche Schattierung, KEIN TEXT im Bild“.
Unlock-Bedingungen nutzen NUR das deklarative Vokabular (counter/special/event, §3.5).

**Set „Garten“** (Seite garten, Tint `#CDE6BE`, Icon sprout):

| ID | Name | Rarität | Unlock | Bild-Spec (Zusatz zum Serien-Stil) |
|---|---|---|---|---|
| gartenGiesser | Gießmeister | häufig | waterings ≥ 100 | Gooby gießt mit riesiger Gießkanne, Regenbogen im Wasserstrahl |
| gartenErdbeere | Erdbeerglück | häufig | Ernte Erdbeere ≥ 10 | Gooby umarmt eine übergroße Erdbeere |
| gartenKuerbis | Kürbiskönig | selten | Riesenkürbis geerntet (event) | Gooby sitzt mit Blätterkrone auf einem Riesenkürbis |
| gartenScheuche | Vogelscheuchen-Freund | häufig | Vogelscheuche platziert | Gooby-förmige Vogelscheuche, echter Gooby imitiert die Pose |
| gartenGewaechs | Gewächshaus-Gärtner | selten | Gewächshaus gebaut | Gooby winkt durch beschlagene Gewächshausscheibe |
| gartenWurm | Regenwurm-Rettung | episch | event wurmFreund | Gooby hält winzigen lächelnden Regenwurm auf der Pfote, Herzchen |

**Set „Fische & Teich“** (Seite teich, Tint `#AFD8E8`, Icon fish):

| ID | Name | Rarität | Unlock | Bild-Spec |
|---|---|---|---|---|
| teichErsterFang | Erster Fang | häufig | Fisch gefangen ≥ 1 | Gooby staunt über kleinen Fisch an der Angel |
| teichSammler | Teichmeister | selten | 10 Fischarten | Gooby vor Aquarium voller bunter Fantasiefische |
| teichGold | Goldschuppe | episch | goldener Fisch | Goldener glitzernder Fisch springt über Goobys Kopf, Funkeln |
| teichSeerose | Seerosen-Nickerchen | häufig | am Teich einschlafen (event) | Gooby schläft zusammengerollt auf riesigem Seerosenblatt |
| teichAngelAss | Angel-Ass | selten | 50 Fische | Gooby mit Anglerhut und stolz geschwellter Brust, Angel geschultert |
| teichFrosch | Quakfreund | häufig | event froschBegegnung | Kleiner Frosch sitzt auf Goobys Kopf, beide gucken sich an |

**Set „Stadt“** (Seite stadt, Tint `#C2D6EE`, Icon skyline):

| ID | Name | Rarität | Unlock | Bild-Spec |
|---|---|---|---|---|
| stadtBummel | Stadtbummel | häufig | 5 Orte besucht | Gooby mit Einkaufstüten vor Pastell-Skyline |
| stadtTaxi | Taxi-Stammgast | häufig | 10 Taxifahrten | Gooby winkt aus gelbem Taxi-Fenster |
| stadtNacht | Nachtschwärmer | selten | nachts in der Stadt | Gooby unter Straßenlaterne, Sternenhimmel, Glühwürmchen |
| stadtAmpel | Ampel-Tänzer | häufig | event ampelTanz | Gooby tanzt an grüner Fußgängerampel, Ampelmännchen ist auch ein Gooby |
| stadtBrunnen | Springbrunnen-Sprung | selten | event brunnenPlatscher | Gooby hüpft mit Gummistiefeln in Springbrunnen, Wasserfontäne |
| stadtKenner | Stadtplan-Profi | episch | ALLE Orte besucht | Gooby mit Lupe über riesigem Stadtplan, Fähnchen-Pins |

**Set „Orte“** (Seite orte, Tint `#F2CDB4`, Icon shop):

| ID | Name | Rarität | Unlock | Bild-Spec |
|---|---|---|---|---|
| orteRehwei | REHWEI-Stammkunde | häufig | 10× REHWEI | Gooby schiebt vollen Einkaufswagen, Karotten obenauf (Logo separat als UI-Asset) |
| orteBaumarkt | Baumarkt-Bauheld | häufig | 1. Baumarkt-Einkauf | Gooby mit Bauhelm balanciert Holzbretter |
| orteApotheke | GOOBYTHEKE-Kunde | häufig | Medizin gekauft | Gooby mit Wärmflasche + Medizinfläschchen, Pflaster auf der Backe |
| orteDoktor | Mutiger Patient | selten | Arztbesuch überstanden | Gooby mit Lolli und stolzem „tapfer gewesen“-Blick, Stethoskop |
| ortePow | POW!-Schnäppchenjäger | selten | 10 POW!-Tagesangebote | Gooby taucht kopfüber in Wühlkiste, Beine ragen raus |
| ortePost | Postbote Gooby | episch | 25 Sendungen | Gooby mit Posttasche und Brief im Mund, stolze Pose |

**Set „Multiplayer & Freunde“** (Seite freunde, Tint `#F4BFCD`, Icon heart):

| ID | Name | Rarität | Unlock | Bild-Spec |
|---|---|---|---|---|
| freundeBesuch | Erster Besuch | häufig | Freund besucht | Zwei Goobys (creme + karamell) winken sich an einer Haustür zu |
| freundeGast | Gastgeber-Gooby | häufig | Besuch empfangen | Gooby serviert Gast-Gooby Tee auf Tablett |
| freundeTomate | Tomaten-Treffer | selten | Tomaten-Emote getroffen | Gooby mit Tomate im Gesicht, zweiter Gooby kichert im Hintergrund |
| freundeBrett | Brettspiel-Champion | selten | 5 Brettspiel-Siege | Zwei Goobys am Spieltisch, einer jubelt, Figuren fliegen |
| freundeCouch | Couch-Schläfer | häufig | Besucher übernachtet | Gast-Gooby schläft eingerollt auf Couch, Sabberfleck, Zzz-Partikel |
| freundePost | Briefeschreiber | episch | 10 Briefe verschickt | Gooby steckt Umschlag mit Herzsiegel in Briefkasten |

**Set „GvZ“ (Goobys vs Zombies)** (Seite gvz, Tint `#D9CFF0`, Icon shield):

| ID | Name | Rarität | Unlock | Bild-Spec |
|---|---|---|---|---|
| gvzNutella | Nutella-Sammler | häufig | 100 Nutella gesammelt | Gooby stapelt Nutella-Gläser als Turm |
| gvzErsteWelle | Erste Verteidigung | häufig | Level 1 geschafft | Gooby in Mini-Festung aus Kissen, entschlossener Blick |
| gvzStopper | Zombie-Stopper | selten | 50 Zombies gestoppt | Comic-Zombie-Gooby (grünlich, niedlich!) prallt an Zaun ab |
| gvzWelle15 | Welle 15! | episch | Kampagne durch | Gooby mit Siegerpose auf Gartenzaun, Konfetti, Sonnenuntergang |
| gvzCoop | Doppel-Kommando | selten | Coop-Level geschafft | Zwei Goobys Rücken an Rücken mit Spielzeug-Blastern |
| gvzGeneral | Garten-General | episch | alle Gooby-Typen freigespielt | Gooby mit Papierhut-„Helm“ vor aufgereihten Mini-Goobys |

**Set „GOB NOM“** (Seite gobnom, Tint `#F0E3B8`, Icon candy):

| ID | Name | Rarität | Unlock | Bild-Spec |
|---|---|---|---|---|
| nomErster | Erster Nom | häufig | Level 1 geschafft | Gooby mit aufgerissenem Mund vor fliegendem Bonbon |
| nomGlas | Glas voll! | häufig | 1. Nutella-Glas gefüllt | Randvolles Nutella-Glas mit Herzchen-Deckel, Gooby leckt sich die Lippen |
| nomKette | Ketten-Nom | selten | 10er-Combo | Gooby wirbelt, Süßigkeiten-Spirale um ihn herum |
| nomFünfzehn | Naschprofi | episch | Kampagne (15) durch | Gooby mit Schärpe und Pokal aus Bonbons |
| nomTeam | Team-Nom | selten | Coop-Level geschafft | Zwei Goobys ziehen an einer Riesen-Lakritzschnecke |
| nomRekord | Naschkatzen-Rekord | episch | Endlos-Highscore-Ziel | Gooby mit rundem Bauch, seliges Grinsen, Krümel überall |

### 3.4 Rarity-/Mystery-Regeln (übernommen + erweitert)

Übernommen aus dem Web: verdeckte Slots zeigen **„?“ + Seiten-Tint** (nie das Motiv),
Hints sind spoilerfrei, Geheim-Sticker liegen **außerhalb** des n/126-Zählers (Suffix
„+💗“-Prinzip), Seiten = 2×3-Grid. Neu formalisiert: `rarity` ∈ häufig (weißer Rand) /
selten (silberner Rand + dezente Funkel-Partikel beim Unlock) / episch (Goldrand +
Glitzer-Shader, Unlock-Jingle länger) / geheim (Mystery-Slot „Geheim“, zählt nicht).
Pro Set genau 3–4 häufig, 1–2 selten, 1–2 episch. Der Web-Visual-Bug (Sticker blinken
beim Seitenwechsel weg) entfällt in Godot: Texturen sind preloaded, Seiten sind
`TabContainer`-Kinder statt DOM-Rebuild.

### 3.5 Sticker-Content-Pack-Format (updatebar ohne .ipa, Anschluss an §B)

```json
{
  "packId": "stickers-garten", "type": "stickers", "version": "1.0.0",
  "minAppVersion": "5.0.0",
  "pages": [{ "id": "garten", "title": "Garten", "icon": "sprout", "tint": "#CDE6BE" }],
  "stickers": [{
    "id": "gartenGiesser", "page": "garten", "name": "Gießmeister",
    "flavor": "Kein Beet bleibt trocken.", "hint": "Gieße fleißig deine Pflanzen.",
    "rarity": "haeufig", "art": "art/gartenGiesser.png",
    "cond": { "counter": "waterings", "target": 100 }
  }]
}
```

Regeln: Packs sind **additiv-only** (IDs nie entfernen/umdeuten — Save referenziert sie),
IDs pack-präfixfrei aber kollisionget­estet beim Laden, `cond` ist ein **deklaratives
Whitelist-Vokabular** (`counter`/`special`/`event` — exakt die 3 Web-Shapes, KEIN Code im
Pack!), Art liegt als PNG im Pack-Zip, geladen nach `user://packs/<packId>/`,
`StickerRegistry`-Autoload mergt Basis-Katalog (res://) + Packs (user://) beim Boot.
Texte deutsch im Pack (optional `name_en` etc.).

---

## 4) Cosmetics 2.0

### 4.1 Katalog-Datenformat (Pack-updatebar, gleiche Mechanik wie §3.5)

```json
{
  "packId": "cosmetics-winter", "type": "cosmetics", "version": "1.0.0",
  "items": [{
    "id": "zipfelmuetze", "slot": "hat", "name": "Zipfelmütze",
    "price": 220, "minLevel": 5,
    "attach": { "bone": "head", "offset": [0, 0.11, 0], "scale": 1.0 },
    "mesh": "meshes/zipfelmuetze.glb",
    "iconMode": "auto"
  }]
}
```

Slots bleiben `hat/glasses/neck/back` (+ `fur` für Fellfarben, nur Preis+Farben, kein
Mesh). Meshes als .glb im Pack — Godot 4 kann sie zur Laufzeit via `GLTFDocument.
append_from_file()` importieren (kein .ipa nötig!). **Icons werden NICHT generiert**,
sondern per SubViewport vom echten Mesh gerendert (`iconMode:"auto"`) — immer konsistent.
Fellfarben **nur im Shop** (User-Wunsch §F bestätigt Bestands-Regel).

### 4.2 Bestandsübernahme

Alle **42 Outfit-IDs** aus `outfits.js` bleiben 1:1 (partyHat … surfBoard), Preise +
minLevel verbatim; alle **7 Fellfarben** (cream/snow/caramel/ash/rose/midnight/golden,
golden behält Metalness-Look als Godot-Material). `outfits.owned`/`skins.owned`
migrieren ohne Mapping-Tabelle (IDs identisch).

### 4.3 Neue Cosmetics (36 Ideen, deutsche Namen)

**Hüte (12):** Zipfelmütze (220) · Fischerhut (240) · Bauhelm (260, Baumarkt!) ·
Melone (280) · Blätterhut (200) · Erdbeermütze (320) · Ritterhelm (400) ·
Kapitänsmütze (350) · Bommel-Schlafmütze (180) · Gießkannen-Hut (300, Gag: tröpfelt) ·
Wintermütze mit Ohrenklappen (260) · Partyhut „5.0“ (0 — Geschenk des 5.0-News-Panels).

**Brillen (7):** Taucherbrille (240) · Retro-Pilotenbrille (280) · Nerd-Brille mit
Tape (200) · Skibrille (260) · Cyber-Brille (450, leuchtet nachts) · Opernglas (380,
hält er mit unsichtbarer Pfote — Gag) · Gurkenscheiben-Wellness (150, Gag).

**Hals (8):** Punkte-Fliege (160) · Rettungsring (300) · Goldkette „GOOBY“ (800) ·
Kariertes Halstuch (180) · Karotten-Lätzchen (140) · REHWEI-Fanschal (220) ·
Medaille „Bester Gooby“ (500) · Glöckchen-Schleife (240, klingelt beim Hüpfen).

**Rücken (9):** Schulranzen (320) · Gitarre (450) · Drachenflügel (550) ·
Picknickkorb (280) · Angelrute (300) · Regenschirm geschultert (260, spannt bei
Regen auf!) · Nutella-Glas-Rucksack (420) · Goobyman-Umhang (500, Goobyman-Laden!) ·
Girlanden-Schleppe (350, Party-Deko-Crossover).

**Fellfarben (7, nur Shop):** Minze (500) · Lavendel (500) · Himmelblau (600) ·
Schoko (400) · Erdbeermilch (600) · Karotte (700) · **Galaxie** (2000, dunkelblau mit
Sternchen-Shimmer-Shader — neues Endgame-Flex über golden).

---

## 5) SAVE-MIGRATION Web-v4 → Godot-v5

### 5.1 Web-Schema v4 (Zusammenfassung der save.js-Analyse)

localStorage-Key `gooby.save` (+ `gooby.save.gen` Zähler, `gooby.save.corrupt` Backup).
JSON, `v:4`. Top-Level: `createdAt, lastTickAt, stats{hunger,energy,hygiene,fun 0–100},
sleep{sleeping,startedAt,wakeAt}, grumpyUntil, coins, xp, level(≤40), inventory{foodId→n},
furniture{owned[], placed{'raumId:slotId'→itemId FLACH}}, decor{wallpaper{},floor{}},
outfits{owned[],equipped{hat,glasses,neck,back}}, minigames{best,plays,lastPlayDay,
difficulty,beaten,bestByDiff,endlessBest}, achievements{unlocked{},counters{~40 Keys}},
daily{lastClaimDay,streak}, quickDelivery, settings{lang,sfx,music,haptics,notifications,
uiScale,volumes{5},devUnlocked,gyro,controls{invertX,invertY},goobyWeltQuality},
onboarding{done,step,whatsNew2/3/4Seen}, garden{plotsOwned,plots[6]{crop,plantedAt,
progressMin,wateredUntil,waterings,fertilized},lastTickAt}, health{state,junkScore,…},
weight{value}, quests{day,active[],rerolledDay,completedTotal}, collections{entries,
claimedSets}, skins{owned,equipped}, items{medicine,fertilizer}, profile{playtimeMin,
coinsEarned,coinsSpent,distanceM,photos}, stickers{unlocked{id→ms},seen{}},
nougat{lastGlobAt,installed}, radio{station,playing,shuffle,replaceContext,lastTrack,
trims,recapHeard}, codes{redeemed{id→ms},lockUntil,buffs{doubleCoinsUntil}},
modifiers{nextAt,seed,current,lastGameId,dayCoins,dayCoinsDay}, recap{lastRecapLevel,
baseline,baselineAt,pendingLevel,history[≤8]}, gallery{count,lastAddedAt,hintShown}` —
**plus additive Slices ohne Versions-Bump**: `vacation{phase,destId,…,postcards,trips,
archive[],visited{}}` und `themePark{visits,rides,…}`. Fotos selbst liegen in
**IndexedDB** (photoStore), NICHT im Save!

### 5.2 Feld-Mapping-Tabelle v4 → v5 (`user://save.json`, `"v":5`)

Konverter `migration/web_import.gd`: nimmt einen v0–v4-JSON (Migrationskette v0→v4 wird
in GDScript nachgebaut — ~80 LOC, Regeln stehen oben in save.js) und mappt dann:

| Web v4 | Godot v5 | Regel |
|---|---|---|
| `v:4` | `meta.imported_from = "web-v4"`, `v:5` | + Import-Zeitstempel |
| `createdAt` | `meta.created_at` | verbatim (ms) |
| `stats/sleep/grumpyUntil` | `gooby.stats/sleep/grumpy_until` | verbatim, Clamps wie validate() |
| `coins` | `economy.coins` | verbatim + „Umzugsbonus“ +250 ᴳ (Willkommensgeste) |
| `xp`,`level` | `progression.level` | **Level 1:1, XP→0** (neues Multiplayer-Level-System §C hat neue Kurve; niemand verliert ein Level, XP-Rest wird verschenkt) |
| `inventory`,`items` | `inventory.food`, `inventory.items` | verbatim |
| `furniture.owned` | `furniture.owned` | ID-Map-Tabelle alt→neu (Datei `legacy_furniture_map.json`); Unbekanntes → Coins-Erstattung |
| `furniture.placed` (Slot-System!) | **NICHT mappbar** aufs freie Grid (§D) | → alles ins **Lager** + „Umzugstag!“-Flow: Umzugskartons im neuen Haus, Spieler platziert neu (narrativ perfekt); Pflichtmöbel (Bett/Couch) vorplatziert |
| `decor.wallpaper/floor` | `decor` | ID gleich → übernehmen, sonst owned-only |
| `outfits.owned/equipped` | `cosmetics.owned/equipped` | IDs 1:1 (42) |
| `skins` | `cosmetics.fur{owned,equipped}` | IDs 1:1 (7) |
| `minigames.*` | `minigames.legacy{}` + `plays` | Bestwerte als „Web-Rekorde“ (Profil §2.1-6); neue Rekorde starten frisch (Spiele sind neu gebaut) |
| `achievements.unlocked/counters` | verbatim | 44 IDs bleiben; Counters sind Superset-kompatibel |
| `daily`,`collections`,`quests.completedTotal` | verbatim / `quests.completed_total` | `quests.active` verworfen (neues System) |
| `garden.plots[6]` | `garden.grid` | Plots 1–6 → erste 6 Grid-Felder (row-major) mit crop/progress/wateredUntil; `plotsOwned` → Grid-Startgröße |
| `health/weight/nougat` | `gooby.health/weight`, `easter_eggs.nougat` | verbatim |
| `profile` | `profile` | verbatim + NEU `player_name`,`gooby_nickname` (Onboarding fragt nach, auch nach Import!) |
| `stickers.unlocked/seen` | `stickers` | IDs 1:1 (85); neue Sets starten zu |
| `radio.*` | `radio` | verbatim; **Radio-Besitz-Grandfathering**: `furniture.owned` enthielt `radio` → `radio.owned=true` (v5-Neusaves: false, → §6.1) |
| `codes.redeemed/lockUntil/buffs` | `codes` | verbatim (Single-Use bleibt eingelöst!) |
| `modifiers` | — | verworfen (System wird neu ausgerollt); `seed` neu |
| `recap.history` | `recap.history` | behalten (Rückblick 2.0 zeigt Historie); baseline neu snapshotten |
| `gallery.count` | `gallery.legacy_count` | Zähler bleibt (Erfolge!), **Fotos sind NICHT migrierbar** (IndexedDB-Blobs, §5.3) — Galerie startet leer |
| `gallery`/`profile.photos>0` | `camera.owned=true` | **POW!-Kamera-Grandfathering**: wer je fotografiert hat, bekommt die Kamera geschenkt (§6.5) |
| `vacation.trips/visited/archive/postcards` | `vacation` | verbatim (laufender Urlaub: `phase→none`, Kosten erstatten) |
| `themePark` | `theme_park` | verbatim |
| `settings` | `settings` | lang/haptics/notifications/volumes/gyro/controls verbatim; `sfx:false`/`music:false` → Bus-Mute; `uiScale` → Godot-`content_scale_factor`-Stufe; `goobyWeltQuality` verworfen (Welt entfernt, §A); `devUnlocked` verbatim |
| `onboarding.done` | `onboarding.done` | verbatim; `whats_new_5_seen=false` → 5.0-Panel; Passstempel „5.0 UMZUG“ |

Import-Bericht als UI: „📦 Umzug abgeschlossen! Level 23 · 4 210 ᴳ · 61 Sticker ·
38 Outfits · 12 Möbel im Umzugskarton“ + Hinweis-Zeile zu Fotos (ehrlich!).

### 5.3 iOS-Import-Realität (ehrlich recherchiert/argumentiert)

**Frage: gleiche Bundle-Id ersetzt die App — bleibt der WebView-localStorage?**

- iOS-Update-Semantik: Installation einer .ipa mit **derselben Bundle-Id**
  (`com.permissionmaxed.gooby`) ersetzt NUR das App-Bundle; der **App-Container
  (Documents/, Library/) bleibt erhalten**. Das gilt für App Store, TestFlight UND
  Sideloading (AltStore/Sideloadly), auch bei anderem Signatur-Zertifikat. **Löschen +
  Neuinstallation wipet dagegen alles** → große Warnung im Onboarding: „Alte App NICHT
  löschen, einfach drüber installieren!“
- WKWebView-localStorage liegt als SQLite unter `Library/WebKit/WebsiteData/…/
  LocalStorage/` im Container — er **bleibt** beim Update liegen, ABER: Godot müsste
  dafür SQLite parsen (keine eingebaute Lib) und der Pfad/Hash ist WebKit-intern →
  **fragil, nicht der Weg**.
- **Der Goldweg ist der G13-Preferences-Mirror** (save.js Z. 126–165, verifiziert):
  JEDES persist() spiegelt den kompletten Save nach `@capacitor/preferences` =
  **NSUserDefaults**, physisch `Library/Preferences/com.permissionmaxed.gooby.plist`.
  Capacitor prefixt Keys mit der Default-Gruppe → erwarteter Key
  `CapacitorStorage.gooby.save` (beim Bau verifizieren!). NSUserDefaults überlebt
  Updates garantiert. Godot liest das über ein **~40-Zeilen-ObjC-iOS-Plugin**
  (`legacy_save_reader`: `stringForKey:`); Fallback ohne Plugin: bplist-Parser in
  GDScript (~200 LOC, Format dokumentiert) auf dem Plist-Pfad (`NSHomeDirectory()/
  Library/Preferences/…`, im eigenen Sandbox lesbar).
- Rest-Risiken ehrlich benannt: (a) Mirror könnte in exotischen Fällen stale sein
  (Plugin-Load-Fehler auf alten Geräten) → Import zeigt Vorschau (Level/Coins/Datum)
  + Bestätigung; (b) Prefix-Annahme `CapacitorStorage.` muss auf einem echten Gerät
  verifiziert werden — Plan B: Plugin dumpt alle UserDefaults-Keys und sucht
  `*gooby.save`; (c) Fotos (IndexedDB) sind realistisch verloren — kommunizieren,
  nicht verschweigen.

**Fallback: manueller Transfer-Code (funktioniert HEUTE ohne Update der Alt-App):**

Die Alt-App hat bereits einen Export: Einstellungen → 5× auf das Sprachsegment „Auto“
tippen (Dev-Freischaltung, settingsScreen.js Z. 690) → Entwickler-Panel → „Save
exportieren“ → kompletter JSON in die Zwischenablage (devPanel.js Z. 1136). Die
Godot-App bekommt dazu den **„Umzugskoffer“-Screen**: Textfeld „Code einfügen“,
akzeptiert (1) den rohen JSON aus der Zwischenablage (v0–v4, volle Migrationskette +
validate-Klamps laufen drüber) und (2) das neue kompakte Format
`GOOBY5.<base64url(gzip(json))>.<crc32>` für zukünftige Godot↔Godot-Transfers
(gleicher Screen exportiert v5-Saves in diesem Format — Gerätewechsel-Feature gratis).
Anleitung mit Screenshots im Panel („So holst du deinen Spielstand aus der alten App“).

**Import-Reihenfolge beim ersten Start:** 1. `user://save.json` da? → normal laden.
2. iOS-Plugin findet Legacy-Save? → Vorschau + „Übernehmen“. 3. Nichts? → Onboarding
mit dezenter „Ich habe einen alten Spielstand“-Option (öffnet Umzugskoffer).

---

## 6) Radio 2.0, GOB.TY, Girlanden, Goobyman, POW!-Gate

### 6.1 Radio 2.0

- v5-Neusaves besitzen **kein Radio** mehr (Web-v4 verschenkte es). Vorher läuft überall
  die **„Bordmusik“ im Loop: nur Pause, KEIN Skip, keine Sender** — Mini-Player-Chip
  zeigt gedimmten Skip-Button mit Tooltip „Kauf dir ein Radio bei IKEA!“ (Verkaufs-Gag).
- IKEA verkauft „Radio“ (450 ᴳ, Möbel + Feature-Unlock in einem). Migrierte Spieler:
  Grandfathering (§5.2). Danach: Sender-Picker als AcCard-Liste (Pattern radio),
  `trims`/Lieblingssender aus dem Web-Save wirken sofort.
- Verbesserungen: Sender-Cover-Art (generiert, §8), „Was läuft?“-Ticker im Chip,
  Multiplayer-Sync-Hook (§C-Team: Beifahrer steuert Radio).

### 6.2 GOB.TY — 5 Video-Gag-Clips (als Godot-Animationen, kein Video-Encoding)

Umsetzung: 2D-Puppet-Szenen (Sticker-Stil-Sprites + AnimationPlayer, 8–15 s), gerendert
in ein SubViewport → Textur auf dem TV-Mesh. Pro Clip 1 Szene, zufällige Rotation:

1. **„Gooby-Nachrichten“**: Sprecher-Gooby mit Papierstapel, niest, Blätter wirbeln —
   Bauchbinde: „Und nun das Wetter: flauschig bis wolkig.“
2. **„Kochen mit Gooby“**: Koch-Gooby klatscht Nutella auf Toast, Toast klebt an der
   Decke, Gooby schaut in die Kamera. Schnitt.
3. **„GvZ — der Werbespot“**: Zombie-Gooby stolpert in Zeitlupe über Gartenzwerg,
   dramatische Musik, „JETZT im Arcade-Automaten!“
4. **„Goobyman-Teleshopping“**: Verkäufer-Gooby preist „Zahnbürste 3000“ an, sie
   zerbricht live, Preisschild rotiert trotzdem auf „–50 %!“.
5. **„Sendeschluss“**: Testbild mit schlafendem Gooby, die Frequenzbalken sind sein
   Schnarchen (Audio-reaktiv — Godot AudioSpectrumAnalyzer, billig & witzig).

### 6.3 Girlanden-Deko

Deko-Kategorie „Girlanden“ (IKEA + POW!): Wimpelkette, Lichterkette (echte
Godot-OmniLights, gedimmt nachts!), Papierlaternen, Geburtstags-Girlande. Technisch:
`Path3D`-Spline zwischen zwei Wand-Ankern, durchhängend (Catenary-Approximation),
Segmente als MultiMesh — Grid-Objekt-Typ „Spann-Deko“ (2 Anker statt 1 Zelle, §D-Anschluss).

### 6.4 Goobyman-Laden

Kleiner Laden (Stadt): verkauft Zahnbürste (geht kaputt — Haltbarkeit, Bruch-Chance
**remote-config via §B-Updater**), Ersatzbürsten-3er-Pack, Seife, Badeente, den
Goobyman-Umhang (§4.3). Laden-Theke im AC-2.0-Look, Goobyman-Maskottchen-Logo
(generiert, §8). Kaputte Zahnbürste triggert Zähneputz-Blocker + Quest „Neue Bürste!“.

### 6.5 POW!-Kamera-Gate

Fotomodus (und damit Passfoto §2.2) erfordert die **Kamera aus dem POW!** (150 ᴳ).
Gate-UI: Kamera-Button zeigt Schloss + „Gibt's im POW!“-Bubble. Grandfathering §5.2.
Nach Kauf: kurze „Erste Kamera!“-Konfetti-Szene, Foto-Tutorial (3 Schritte).

---

## 7) Bild-Generierungs-Spec-Liste (für den Orchestrator)

Alle mit Stil-Anker: „GOOBY-Spiel-Stil: cremefarbener flauschiger Hase, Pastellfarben
(#FFF6EC/#FF7BA9/#59C9B9/#FFD166), runde Formen, dicke Outlines, kein Text im Bild“
(Ausnahmen markiert). Seamless-Patterns: „nahtlos kachelbar 512×512, monochrome
Linien-Icons auf Transparenz, Motive ~96 px, versetzt gestreut, volle Deckkraft
(Opacity macht der Shader)“.

| # | Asset | Format | Spec-Kern |
|---|---|---|---|
| 1–11 | `pattern_travel/city/pond/friends/post/baumarkt/market/news/gvz/gobnom/goobyman.png` | 512² seamless | Themen-Icons: Koffer+Flugzeug / Häuser+Ampel / Fische+Seerosen / Herzen+Briefe / Pakete / Hammer+Säge / Marktstand+Gemüse / Konfetti+„5“-Ballon / Schild+Zombie-Ohren / Bonbons / Zahnbürste+Cape |
| 12–53 | 42 Sticker-PNGs (§3.3-Tabellen) | 512², transparent | je Zeile „Bild-Spec“; Sticker-Rand weiß 12 px |
| 54 | Reisepass-Cover-Wappen | 1024² | Gooby-Kopf-Wappen mit Karotten, Prägelinien-Look, bordeaux/gold |
| 55 | 5.0-News-Header | 1024×512 | Gooby springt aus Umzugskarton, Konfetti, „5“-Luftballon (Ziffer ok, ist Form nicht Text) |
| 56–60 | 5 Radio-Sender-Cover | 512² | je Genre-Motiv mit Gooby (Bordmusik: Gooby am Steuer; etc.) |
| 61 | Goobyman-Logo | 512², transparent | Gooby mit Cape + Zahnbürste als Schwert, Comic-Emblem, Schriftzug „GOOBYMAN“ als Logo-Lettering ERLAUBT (Einzelreview) |
| 62 | POW!-Kamera-Icon | 512² | Retro-Sofortbildkamera in Pastell, „POW!“-Sternchen-Emblem (Logo-Ausnahme) |
| 63 | GOB.TY-Senderlogo | 512² | TV-Testbild-Ästhetik, Gooby-Ohren auf dem Bildschirm, „GOB.TY“ Logo-Lettering (Ausnahme) |
| 64–68 | GOB.TY-Clip-Sprites (5 Sets) | Spritesheets | je Clip: 1 Kulisse + 2–4 Puppet-Teile (Sprecherpult, Küche, Garten, Studio, Testbild) |
| 69 | Umzugskoffer-Illustration | 768² | offener Koffer voller Sticker/Möbel-Miniaturen, Gooby sitzt obendrauf |
| 70+ | REHWEI/GOOBYTHEKE/Baumarkt-Logos | 512² | Laden-Logos (Lettering-Ausnahmen, je einzeln reviewen) |

Cosmetics-Icons werden **nicht** generiert (SubViewport-Render, §4.1).

---

## 8) Prioritäten, Risiken, Scope

### Prioritäten

- **P0 (blockiert andere Teams):** Theme-Ressource + Tokens + AcBackdrop-Shader;
  Haupt-Layout P1/L1; Save-Konverter + iOS-Plugin + Umzugskoffer (Migration ist
  Vertrauenssache — zuerst bauen, mit echten Alt-Saves testen!).
- **P1:** Profil + Reisepass 2.0 + 5.0-Panel; Sticker-Germanisierung (85) +
  StickerRegistry mit Pack-Support; Radio-Gate; POW!-Kamera-Gate; Flughafen-UI.
- **P2:** 42 neue Sticker (Set-weise shipbar als Packs!); Cosmetics-Packs + 36 neue
  Items; GOB.TY-Clips; Girlanden; Goobyman-Laden.

### Risiken

1. **Bundle-Id-/Container-Annahme**: Muss früh auf echtem Gerät verifiziert werden
   (Alt-App drauf → Godot-Build drüber → Plist lesen). Mitigation: Fallback-Pfad
   (Umzugskoffer) funktioniert IMMER; Onboarding warnt vor App-Löschen.
2. **`CapacitorStorage.`-Prefix**: Annahme, per Key-Dump-Plugin absichern.
3. **Fotos nicht migrierbar** (IndexedDB): ehrlich kommunizieren; Kamera-Grandfathering
   + „Web-Rekorde“-Karte mildern den Verlustschmerz.
4. **Furniture-Slot→Grid**: kein 1:1-Mapping möglich — „Umzugstag“-Flow macht aus der
   Schwäche ein Feature; braucht aber §D-Grid früh.
5. **Text in generierten Bildern**: per Entscheidung §3.1 eliminiert; Logo-Ausnahmen
   einzeln reviewen (Umlaut-Check!).
6. **Pack-System-Sicherheit**: `cond`-Whitelist strikt halten, niemals Code in Packs.

### Scope (Dateien/LOC, GDScript + Daten)

| Modul | Dateien | ~LOC |
|---|---|---|
| `theme/` (tokens, builder, SquishButton, AcCard/Chip/Tabs/Stamp/Ribbon-Szenen) | 12 | 700 |
| `shaders/` (pattern_drift, glitzer_rarity, galaxie_fell) | 3 | 60 |
| `ui/hud/` (HudLayout P1+L1, Status-Kapsel, Interaktions-Auge) | 6 | 900 |
| `ui/profile/` (+Passport, +News-Panel, +Erfolge-Grid) | 8 | 1 100 |
| `ui/airport/` | 3 | 350 |
| `stickers/` (Registry, Album, StickerCard, Packs) + `sticker_texts_de.json` (127) | 6+2 | 800 + Daten |
| `cosmetics/` (Registry, Packs, Icon-Renderer) + Katalog-JSON (78 Items) | 5+2 | 600 + Daten |
| `migration/` (web_import, bplist-Fallback, Umzugskoffer-UI, ObjC-Plugin) | 5 | 900 (+60 ObjC) |
| Radio-Gate / POW!-Gate / Goobyman / Girlanden / GOB.TY (5 Clip-Szenen) | 12 | 1 100 |
| **Summe** | **~64** | **~6 500 + Daten/Assets** |

---

## Abschluss (Zusammenfassung)

Bereich H liefert vier Bausteine. **Erstens** das UI-Kit „AC 2.0“: eine Godot-Theme-
Ressource, die die verifizierten Web-Tokens (Cream/Pastell, Pill-Buttons mit
Boden-Lippe, 28-px-Karten, Baloo 2) 1:1 überträgt, plus ein einziger 15-Zeilen-Shader
für die schräg driftenden Wallpaper aller Screens. Das Haupt-Layout wird neu gedacht:
Hochkant „Daumen-Bogen“ (Status-Kapsel oben, Aktions-Bogen um die rechte untere Ecke),
Querformat „Cockpit“ (Stat-Spalte links, Button-Spalte rechts) — beide begründet über
Daumenzonen; Ton/Garderobe fliegen raus, „Laden“ wird „Reise“, Erfolge ziehen ins neue
Profil mit Reisepass 2.0 samt einsetzbarem Gooby-Foto. **Zweitens** die Sticker-
Offensive: komplette Germanisierungs-Tabelle aller 85 Bestands-Sticker (IDs stabil),
42 neue Sticker in 7 Sets mit Bild-Specs, Rarity-/Mystery-Regeln und ein additives
Content-Pack-Format; Beschriftung kommt als Godot-Label über das Bild, nie hinein.
**Drittens** Cosmetics 2.0: Pack-Katalogformat mit Laufzeit-glb-Import, Übernahme aller
42 Outfits und 7 Fellfarben, 36 neue Items. **Viertens** die Save-Migration mit
vollständiger Feld-Mapping-Tabelle v4→v5: Goldweg ist der verifizierte
Capacitor-Preferences-Mirror (NSUserDefaults überlebt das Bundle-Id-Update; kleines
iOS-Plugin liest ihn), Fallback der schon heute existierende Dev-Panel-JSON-Export
plus „Umzugskoffer“-Import; Möbel ziehen narrativ per „Umzugstag“ um, Fotoverlust wird
ehrlich kommuniziert und mit Kamera-Grandfathering abgefedert.

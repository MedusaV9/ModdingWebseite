# DLC-MCGOOBY — W14/IDEEN: „McGooby" — Goobys eigener Fast-Food-Laden

Auftrag (User, wörtlich): Zweites „Riesen DLC" — „das man auch einen ‚McGooby' haben kann …
einen eigenen Fast Food Laden der wie McDonald's und Burger King ist". Dieses Dokument
bündelt die Ideen von **20 Perspektiven** (Rolle IDEEN-MCGOOBY) und verdichtet sie zu einem
bauplan-reifen DLC-Design: (§1) Vision & Ton, (§2) Kern-Loop, (§3) Rezepte/Menü, (§4) Rush-Hours
& Kunden, (§5) Mitarbeiter & Stationen, (§6) Progression, (§7) Events & Gags, (§8) Multiplayer,
(§9) Synergien, (§10) Technik-Blaupause, (§11) Teaser für den DLC-Hub. Aufwand nur als
**S/M/L** (Umfang/Risiko/betroffene Systeme), niemals Kalenderzeit. Vorbild in Struktur und
Anspruch: `RANCH-DLC-IDEAS-1.md` (das erste Riesen-DLC).

---

## 0) Die 20 Perspektiven — wer hat was gefordert, und wo ist es gelandet?

| # | Perspektive | Kernforderung (verdichtet) | Gelandet in |
|---|---|---|---|
| 1 | Diner-Dash-Veteran | Kundenstrom mit Prioritäten-Jonglage, „eine Aktion mehr, als du Hände hast" | §2.2, §4 |
| 2 | Cooking-Mama-Fan | Zubereitung als TAKTILES Geschick (wischen, tippen, kreisen), „Perfekt!"-Callouts | §2.2 |
| 3 | Overcooked-Koop-Fan | Stationen-Arbeitsteilung mit Freund, Chaos zum Lachen statt zum Streiten | §8.1 |
| 4 | Casual-Spieler | Kurze Schichten (5–8 min), jederzeit pausierbar, nie Bestrafung | §2.4, §4.2 |
| 5 | Kind (8 Jahre) | Alles anfassbar, Kunden knuffig, Kinder-Menü mit Überraschung | §3.1 (#15), §4.3 |
| 6 | Completionist | Rezepte-Sammlung, geheime Rezepte, Sticker, Erfolge, 5-Sterne-Endziel | §3.2, §6 |
| 7 | Deko-Fan | Laden SELBST einrichten (Grid-Baumodus!), Themen-Sets, Neonschild | §2.3.3, §6.1 |
| 8 | Multiplayer-Fan | Freund isst bei mir, Koop-Schicht, Wochen-Wettbewerb unter Freunden | §8 |
| 9 | Speedrunner | Combo-Ketten, Schicht-Bestwerte, „perfekte Schicht" als Skill-Ziel | §2.2.5, §6.3 |
| 10 | Mobile-UX-Designer | Hochkant, Daumen-Zonen, eine Geste pro Station, keine Menü-Tiefe im Rush | §2.2, §10.5 |
| 11 | Story-Fan | Warum eröffnet Gooby einen Laden? Kapitel-Bogen mit Eröffnungs-Feier | §1.3, §6.2 |
| 12 | Humor-Autor | Parodie-Namen, Kunden-Sprüche, Bürgermeister will 7 Gurken | §1.2, §4.3, §7 |
| 13 | Sound-Designer | Brutzel-ASMR, Bestellglocke, Shake-Blubbern, Laden-Radio | §2.2.6 |
| 14 | Accessibility-Advocat | Einfacher Modus ohne Timer, Form+Farbe-Zutaten-Icons, Einhand-Layout | §2.2.7 |
| 15 | Performance-Ingenieur | Kunden-Deckel, Partikel-Pooling, Draw-Call-Budget wie Ranch | §10.6 |
| 16 | Live-Ops-Planer | Tages-Specials + Saison-Menüs als Content-Packs nachliefern | §3.3, §10.2 |
| 17 | QA-Tester | Jede Station bot-zertifizierbar (`simulate_autoplay`), deterministisch | §10.4 |
| 18 | Food-Fotograf | Eigene Fotos werden die Bilder auf MEINER Speisekarte | §2.3.5 |
| 19 | Franchise-Parodie-Liebhaber | Goldene Löffel-Bögen, „GoobyMac", Drive-In, Maskottchen | §1.2, §2.3.4 |
| 20 | Ranch/Garten-Synergie-Denker | Zutaten aus dem eigenen Garten + Ranch-Milch, GOOBERANDO liefert aus | §9 |

---

## 1) Vision & Ton

### 1.1 Elevator-Pitch

**McGooby ist die Fast-Food-Parodie mit Herz:** Gooby eröffnet in der Stadt seinen eigenen
Burger-Laden unter zwei goldenen Bögen — die bei genauem Hinsehen **Löffel mit Ohren**
sind (Logo-Artwork existiert bereits beim Orchestrator). Das DLC verzahnt zwei Spielgefühle,
die GOOBY beide schon kann, aber noch nie kombiniert hat: **echtes Geschicklichkeits-Gameplay**
(der Bestell-Rush als Minispiel-Kette im bestehenden Framework) und **gemütliches Management**
(Menü, Preise, Einkauf, Ausbau — Zahlen ohne Zeitdruck). Wie bei der Ranch gilt: kuschelig,
deutsch, offline-first, eine Währung, kein FOMO — nur dass hier statt Hufschlag eben
Pommes-Duft in der Luft liegt.

### 1.2 Der Ton: Parodie mit Herz (nie zynisch, nie „Junk")

- **Logo-Gag:** Die goldenen Bögen sind zwei **Löffel mit Löffel-Ohren** — von weitem
  „M", von nahem ein Gooby-Insider. Nachts leuchten sie warm-gelb (Stadtnacht-Look).
- **Menü-Namen sind liebevolle Parodien**, nie 1:1-Kopien: der **GoobyMac** (Doppeldecker
  mit „Geheim-Gold-Soße"), **Möhren-Pommes** (natürlich sind es Möhren — es ist Gooby!),
  der Milchshake **„Der rosa Flausch"** (so fluffig, dass er Ohren hat), **Nugget-Wölkchen**,
  **Gurken-Deluxe**, die Apfeltasche **„Heißes Herzchen"** (Vorsicht, heiß! — steht 4× drauf).
- **Kein Fett-Shaming, kein Junk-Food-Zeigefinger:** Essen ist bei GOOBY immer Freude
  (das Gewichts-System des Hauptspiels bleibt unangetastet — McGooby-Essen zählt wie
  normales Essen, `scripts/logic/weight.gd` braucht KEINE Sonderregel). Die Parodie zielt
  auf die FORMEN des Fast-Food (Bögen, Drive-In, Menü-Tafeln, Maskottchen), nie auf Esser.
- **Knuffig statt hektisch:** Der Rush darf kribbeln, aber niemals bestrafen. Verpatzte
  Burger sehen LUSTIG aus (schiefer Turm, Gurke auf dem Kopf) und werden vom
  Personal aufgegessen — nichts wird weggeworfen, niemand ist sauer.
- **Marken-Sicherheit (Designregel):** Eigene Wortschöpfungen, eigene Formen (Löffel
  statt Arches, Ohren statt Krone), keine echten Logos/Slogans/Schriftzüge. Parodie ja,
  Verwechselbarkeit nein.

### 1.3 Rahmen-Geschichte (kurz, optional erzählt über das Dialog-System)

Die Stadt hat REHWEI, Wochenmarkt, GOOBYTHEKE — aber keinen Ort, an dem man um 18 Uhr
mit den Pfoten isst. Ein leerstehendes Eckgrundstück, ein Bauschild, ein Traum: Kapitel-Bogen
**„Die große Eröffnung"** in 4 Schritten (Grundstück kaufen → Probeschicht mit 3 Kunden →
Menü festlegen → Eröffnungsfeier mit halber Stadt vor der Tür). Erzählt über den bestehenden
`dialog_runner.gd` — die Ranch hat mit `ranch_kauf.gd` das Kauf-Flow-Muster schon etabliert.

### 1.4 Fünf bewusste Nicht-Ziele

1. **Kein Echtzeit-Zwang im Management:** Preise/Einkauf/Ausbau haben NIE einen Timer.
2. **Kein Personal-Feuern, kein Burnout-Sim:** Mitarbeiter machen höchstens „Pausentag".
3. **Keine Fließband-Idle-Mechanik:** McGooby ist kein Cookie-Clicker — Einnahmen entstehen
   durch GESPIELTE Schichten (plus kleine gedeckelte Tageskasse, §2.3.6), nicht durch Warten.
4. **Kein globales Leaderboard, kein PvP:** Wettbewerb nur unter Freunden (Ranch-Regel F5).
5. **Kein verderbendes Essen, keine Lager-Strafe:** Zutaten verfallen nicht, Läden brennen
   nicht ab. Der Frittenfett-Alarm (§7) ist ein GAG-Event, kein Fail-State.

---

## 2) Kern-Loop: Rush spielen, Laden denken

### 2.1 Der Doppel-Loop

```
   MANAGEMENT (ruhig, jederzeit)             RUSH (Geschick, 5–8 min „Schicht")
   Menü zusammenstellen, Preise setzen  ───▶  Kunden bestellen dein Menü
   Zutaten einkaufen (Garten/REHWEI)    ───▶  Stationen-Kette: wenden→belegen→
   Laden ausbauen & dekorieren               frittieren→mixen
   Mitarbeiter einteilen                ◀───  Münzen + Trinkgeld + Laden-XP
                                              zurück in Ausbau & Einkauf
```

Beide Hälften funktionieren einzeln (Management ohne Rush = Deko/Zahlen-Spielplatz;
Rush ohne Management = Arcade-Spiel), aber die Verzahnung erzeugt den Sog: **Was ich
anbaue, kaufe und auf die Karte setze, bestellen die Kunden wirklich.**

### 2.2 Der Bestell-Rush — echtes Geschicklichkeits-Gameplay im Minigame-Framework

Der Rush ist EIN Minispiel (`mcgoobyRush`) im bestehenden Framework
(`scripts/minigames/minigame_base.gd` + `framework_logic.gd` + `juice_kit.gd`), aber mit
**4 Stationen**, zwischen denen der Spieler per Tap wechselt (Tab-Leiste unten, Daumen-Zone).
Jede Station ist eine EIGENE pure Logik-Datei (bot-zertifizierbar, §10.4) mit einer eigenen
Geste — das Cooking-Mama-Prinzip „eine Station = eine Hand-Bewegung":

1. **Grill — Patty wenden (Timing-Tap):** Pattys brutzeln sichtbar durch 3 Zustände
   (roh → goldbraun → „uups, Kohle-Style"). Tap im goldenen Fenster = „Perfekt!"-Callout
   + Funken (JuiceKit). Zu spät ist NICHT verloren: der Kohle-Patty wird zum
   „Röstaroma-Spezial" mit halben Punkten und einem Gag-Spruch. Vorbild: das
   Absprung-Timing der Ranch (`ride_feel`-„Perfekt!"-Regel A3).
2. **Belegstation — Burger stapeln (Wisch-Reihenfolge):** Das Bestell-Ticket zeigt den
   Zutaten-Turm; Zutaten werden in Ticket-Reihenfolge aus einer Leiste aufs Brötchen
   gewischt. **Direkter Erbe von `burger_build`** (`scripts/minigames/games/burger_build/`,
   4–7-Lagen-Tickets, +5 richtige Lage / −2 falsche / +15 fertig) — nur ohne Zutaten-Regen:
   Hier WÄHLT der Spieler, das Tempo kommt von der Kundenschlange, nicht von der Physik.
3. **Fritteuse — Pommes-Timing (Halten & Loslassen):** Korb per Halte-Geste absenken,
   Blubber-Intensität + Farbton zeigen den Gargrad, im goldenen Fenster loslassen.
   Doppel-Korb ab Ausbaustufe 2 = zwei Timer jonglieren (Diner-Dash-Priorität).
   Möhren-Pommes haben ein KÜRZERES Fenster (knackig!) — Rezept-Gefühl durch Timing.
4. **Shake-Bar — mixen (Kreis-Geste):** Zutaten antippen, dann im Takt kreisen
   (Rhythmus-Feedback wie beim geplanten Wildpferd-Beruhigen der Ranch, A5); gleichmäßige
   Kreise füllen die Flausch-Krone. Überdrehen lässt den Shake comic-haft überschäumen —
   Lacher, halbe Punkte, Wischtuch-Mini-Geste als Wiedergutmachung.

Dazu kommen: **2.2.5 Combo-Kette** (jede fehlerfreie Bestellung erhöht den Trinkgeld-Multiplikator
×1,1 … ×2,0 — Speedrunner-Futter, aber Verlust der Kette kostet nie Basis-Punkte) ·
**2.2.6 Sound-Konzept** (Brutzel-ASMR pro Patty-Zustand, Bestellglocken-„Pling" als
Beat-Anker, Shake-Blubbern in Tonhöhe des Füllstands, Lo-Fi-Laden-Radio über den bestehenden
`MusicDirector` — Audio trägt 50 % des Diner-Gefühls) · **2.2.7 Zugänglichkeit**
(„Gemütlich"-Schalter: Kunden-Geduld eingefroren, Timing-Fenster ×1,6, identische Belohnung
minus Combo — Muster „Einfach reiten" I4; Zutaten-Icons unterscheiden sich IMMER in Form UND
Farbe; alle Gesten auch als Tap-Alternative).

**Framework-Zahlen (Vorschlag, `game.json`-Format wie `burger_build`):** Hochkant,
`coin_table {divisor: 4, min: 6, max: 30}`, Ziel 85, `energy_cost 8`, `supports_endless: true`
(Endlos = „Feierabend erst, wenn DU willst"). 10 Level + Sterne über das
`ranch_level_select.gd`-Muster: Level = Schicht-Szenarien (L1 „3 Stammkunden", L5 „erste
Rush-Hour", L10 „Bürgermeister-Bankett").

### 2.3 Die Management-Ebene — ruhig, tief, jederzeit

- **2.3.1 Menü-Tafel:** Aus freigeschalteten Rezepten (§3) bis zu 8 aktive Menü-Slots
  bestücken; **Preis-Schieberegler pro Gericht** (± 40 % um den Richtwert). Teuer = mehr
  Münzen pro Verkauf, aber Kunden bestellen seltener und die Geduld-Herzen starten niedriger;
  günstig = Schlange wird länger (mehr Rush-Action). Eine EINFACHE, fühlbare Kurve — kein
  BWL-Excel. Pure Logik `menu_logic.gd`, Zahlen im Balance-Pack.
- **2.3.2 Zutaten-Einkauf mit Herkunft:** Jede Zutat hat Bezugsquellen mit Preisstaffel:
  **eigener Garten** (am billigsten, §9.2), **Wochenmarkt/REHWEI** (Normalpreis, nutzt die
  bestehenden Sortiment-JSONs), **„Notlieferung"** (sofort, +50 % — der Anti-Frust-Knopf,
  damit nie eine Schicht an fehlendem Salat scheitert). Lager ohne Verfall (§1.4).
- **2.3.3 Laden-Ausbau im Grid-Baumodus:** Der Gastraum ist ein Grid-Raum im
  Haus-Baumodus-Muster (`scripts/home/build_mode/` + `grid_data.gd`, exakt wie der
  Ranch-Plan D1): Tische, Stühle, Bodenfliesen, Wand-Deko, Pflanzen, Kassen-Theke frei
  platzieren. Deko-Kataloge als Möbel-Pack-Einträge (`content/mcgooby/`), Themen-Sets
  (Retro-Diner chrom-rosa, Wald-Picknick, Weltraum-Imbiss als Raumstations-Gruß).
  Ausbau-STUFEN (Küche 2. Fritteuse, 2. Kasse, Drive-In-Spur, Terrasse) sind sichtbare
  Weltänderungen mit der Gooby-hämmert-Qualm-Animation (Ranch-D2-Muster).
- **2.3.4 Drive-In-Schalter mit Auto-Anbindung:** Ausbaustufe 3 baut die Drive-In-Spur ans
  Eck-Grundstück — echte Autos aus dem Stadtverkehr (`city_verkehr.gd`-Kulisse) biegen ein,
  und der Spieler kann mit dem EIGENEN Auto (Autohaus!) selbst vorfahren und per
  Sprechanlagen-Sheet bestellen (Radio-Moderator-Stimme von Danny, §5). Im Rush ist der
  Drive-In eine 5. Bestell-Quelle mit eigenem Fenster-Übergabe-Moment.
- **2.3.5 Speisekarten-Fotos (Food-Fotograf-Perspektive, der stille Star):** Der bestehende
  Fotomodus (POW!-Kamera) bekommt einen „Menü-Foto"-Rahmen über der Theke: **das eigene
  Foto wird das Bild auf der Speisekarte** — Kunden halten beim Bestellen die Karte hoch,
  und da prangt MEIN schiefer GoobyMac. Freunde sehen die Fotos beim Besuch (§8.3).
- **2.3.6 Tageskasse (sanfte Offline-Komponente):** Ist mindestens 1 Mitarbeiter eingeteilt,
  verkauft der Laden „nebenbei" — gedeckelt wie `ranch_offline.gd` (max. 8 h Simulation,
  gedrosselte Rate), rein Timestamp-basiert über die Zeit-Injektion. Kein Idle-Exploit,
  nur ein „Willkommen zurück, die Kasse klimpert"-Lächeln.

### 2.4 Eine Schicht in 6 Minuten (Soll-Erlebnis)

Laden betreten → Schürze umbinden (1 Tap) → 3 ruhige Aufwärm-Kunden → Rush-Hour-Jingle,
Schlange wächst auf 5, Drive-In-Hupe → Stationen-Jonglage mit 2 „Perfekt!"-Ketten →
Bürgermeister-Gooby erscheint (VIP-Fanfare, §4.3) → Schichtende-Glocke → Kassensturz-Screen
(Münzen hüpfen, Trinkgeld-Combo, Laden-XP-Balken, 1 neues Rezept-Puzzleteil) →
Feierabend-Vignette: Gooby dreht das Schild auf „GESCHLOSSEN", Lichter der Löffel-Bögen an.

---

## 3) Rezept- & Menü-System

### 3.1 Die 15 Start-Rezepte (mit Zutaten-Bäumen)

Zutaten-Notation: `→` = Stapel-/Arbeitsreihenfolge, `(G)` = Grill, `(F)` = Fritteuse,
`(S)` = Shake-Bar, `(B)` = Belegstation. Bezugsquelle **Garten** meint §9.2-Crops,
**Ranch** die Milch der Ranch-Kuh (§9.3), Rest über REHWEI/Wochenmarkt.

| # | Rezept | Zutaten-Baum | Stationen | Quelle-Highlights |
|---|---|---|---|---|
| 1 | **GoobyMac** | Brötchen → Patty (G) → Geheim-Gold-Soße → Salat → Patty (G) → Käse → Brötchen | G+B | Salat: Garten |
| 2 | **Möhren-Pommes** | Möhren → schnippeln → frittieren (F, kurzes Fenster) → Glitzersalz | F | Möhre: Garten |
| 3 | **„Der rosa Flausch"** (Shake) | Milch → Erdbeeren → mixen (S) → Flausch-Krone | S | Milch: Ranch |
| 4 | Käse-Knusperle | Brötchen → Patty (G) → Käse ×2 → Brötchen | G+B | — |
| 5 | Garten-Gooby (Veggie) | Brötchen → Kürbis-Patty (G) → Tomate → Salat → Brötchen | G+B | Kürbis/Tomate/Salat: Garten |
| 6 | Nugget-Wölkchen (6er) | Teig → formen → frittieren (F) → Wolken-Dip | F | — |
| 7 | **Gurken-Deluxe** | Brötchen → Patty (G) → Gurke ×7 → Brötchen | G+B | Bürgermeister-Kanon (§4.3) |
| 8 | Pommes Klassik | Kartoffeln → schnippeln → frittieren (F) → Salz | F | — |
| 9 | Shake „Grüner Galopp" | Milch → Apfel → Minze → mixen (S) | S | Milch: Ranch |
| 10 | Frühstücks-Höppel | Brötchen → Rührei (G) → Käse → Brötchen — **nur vormittags bestellbar** | G+B | Zeit-Injektion als Menü-Gag |
| 11 | Zwiebel-Ringlein | Zwiebel → Ringe → Teig → frittieren (F) | F | — |
| 12 | Knusper-Maiskolben | Maiskolben → grillen (G) → Butterpinsel | G | Mais: Garten (NEUER Crop, §9.2) |
| 13 | Schoko-Flausch | Milch → Schoko → mixen (S) → Raspel-Regen | S | Milch: Ranch |
| 14 | Apfeltasche „Heißes Herzchen" | Apfel → würfeln → Teigtasche → frittieren (F) | F | Apfel: Ranch-Apfelbaum |
| 15 | **Kleines Hoppel-Menü** | Mini-GoobyMac + Mini-Pommes + Saft + **Überraschungs-Sticker** | G+B+F | Kinder-Perspektive #5 |

Balancing-Prinzip: Jede Station trägt 3–5 Rezepte; Mehr-Stationen-Rezepte (GoobyMac,
Hoppel-Menü) geben überproportional Punkte, weil sie Jonglage verlangen. Alle Zahlen
(Preise, Punktwerte, Timing-Fenster) leben in der `balance`-Domain des Packs — updatebar
ohne App-Release.

### 3.2 Geheime Rezepte (freispielbar, nie kaufbar)

Fünf Rezepte mit Entdeck-Moment (Rezeptkarte flattert als Konfetti-Umschlag ins Menü);
Hinweise laufen als vage Kunden-Sprüche über das Dialog-System — markerloses Suchen im
Geiste der Ranch-B5-Regel:

1. **Der Goldene GoobyMac** — Food-Kritiker (§7.3) dreimal restlos begeistern. Vergoldetes
   Brötchen, doppelte Punkte, Kunden applaudieren beim Servieren.
2. **Mitternachts-Burger** — eine Endlos-Schicht spielen, die (Gerätezeit) nach 22 Uhr endet.
   Dunkles Brötchen, Glühwürmchen-Sesam; nur nachts auf der Karte.
3. **Ranch-Burger** — Ranch-DLC-Besitz + 20× Ranch-Milch verarbeitet. Heu-Deko-Spieß,
   Frau Wieher wird Stammkundin (Cross-DLC-Gruß).
4. **Möwen-Snack** — den Möwen-Überfall (§7.2) einmal ohne verlorene Pommes überstehen.
   Fisch-förmiges Gebäck; Möwen sitzen danach FRIEDLICH auf dem Schild (Welt-Detail!).
5. **Regenbogen-Shake** — alle 3 Start-Shakes je 10× perfekt gemixt. Schichtet sich live
   im Becher — der Foto-Modus-Magnet (§2.3.5).

### 3.3 Tages-Specials (deterministisch, Live-Ops-tauglich)

Jeden Tag kürt der Laden 1 Gericht zum **Tages-Special** (−20 % Preis, +50 % Bestell-Häufigkeit
im Rush): Auswahl = pure Funktion aus Datums-Seed + aktiver Menükarte (`GoobyRng`-Muster,
zeitinjiziert, testbar). Saison-Specials (Kürbis-Oktober, Zimt-Flausch im Winter) kommen als
kleine Content-Packs nach — dieselbe „Ranch-Post"-Idee (Ranch I1), hier als **„Neu auf der Karte!"**-Aushang.

---

## 4) Rush-Hours & Kunden

### 4.1 Deterministische Stoßzeiten

Kundenstrom = pure Funktion aus (Tages-Seed, Uhrzeit via Zeit-Injektion `scripts/logic/clock.gd`,
Laden-Sterne, Menükarte). **Stoßzeiten 12–13 Uhr und 18–19 Uhr** (reale Gerätezeit) bringen
dichtere Spawns und den Rush-Hour-Jingle; dazwischen ist der Laden gemütlich (Casual-Fenster).
Wichtig: Schichten sind IMMER spielbar — Stoßzeit ist Bonus-Dichte, nie Voraussetzung. Wer nur
um 22 Uhr spielt, bekommt die „Nachtschwärmer"-Kundschaft (und den Mitternachts-Burger-Pfad, §3.2).
Gleiche Zeit + gleicher Seed = gleicher Kundenstrom → Koop-Sync (§8.1) und Bot-Tests (§10.4) gratis.

### 4.2 Geduld-Mechanik: knuffig statt stressig

Kunden haben **3 Herzchen-Geduld**, aber die Eskalation ist Komik, kein Countdown-Terror:

- ❤❤❤ **fröhlich** — summt mit dem Laden-Radio, schaut sich Deko an (Deko-Fan-Belohnung:
  schöner Laden = +1 Start-Geduld!).
- ❤❤ **hungrig** — Bauch knurrt COMIC-LAUT (Sound-Gag), Blick wird treuherzig-groß.
- ❤ **dramatisch** — fällt theatralisch über die Theke („Ich VERGEHE!"), Ohren hängen.
- 0 ❤ — der Kunde geht NICHT wütend: er bestellt seufzend das Tages-Special zum halben
  Preis („na gut, dann eben DAS") — weniger Trinkgeld, nie eine Strafe, oft ein Lacher.

Geduld friert ein, solange man aktiv an SEINER Bestellung arbeitet (Anti-Frust-Kern) und
komplett im „Gemütlich"-Modus (§2.2.7).

### 4.3 Kunden-Typen (Casting mit Gag-Vertrag — jede Figur braucht einen)

| Kunde | Verhalten | Gag |
|---|---|---|
| Stammkunde Herr Höppel | täglich, bestellt IMMER dasselbe | Merkt man sich sein Menü (1-Tap-Bestätigung), gibt es Doppel-Trinkgeld + Nicken |
| Oma Hoppel | langsam, unendliche Geduld | zahlt in einzelnen Münzchen, erzählt dabei vom „Krieg der Möhren" |
| Teenager-Schwarm (3er) | bestellen NACHEINANDER dasselbe | wer das erkennt, macht 3× dasselbe in Serie — Combo-Geschenk |
| Eiliger Pendler-Gooby | Nur-Drive-In, Geduld startet bei ❤❤ | trommelt aufs Lenkrad im Takt des Laden-Radios |
| **VIP: Bürgermeister-Gooby** | Fanfare, rote Ampel-Eskorte, will den Gurken-Deluxe **mit exakt 7 Gurken** | zählt beim Servieren LAUT mit; bei 7: Foto fürs Rathaus (+Sticker-Fortschritt §6.4); bei 6 oder 8: „Hmpf. Demokratie ist Kompromiss." — isst ihn trotzdem |
| VIP: Food-Kritiker von Monokel | kündigt sich einen Tag vorher an (§7.3) | Monokel beschlägt bei perfektem Essen — DAS Erfolgssignal |
| Nachtschwärmer | nur nach 21 Uhr | bestellt flüsternd, Trinkgeld in Sternschnuppen-Konfetti |

Alle Kunden sind prozedurale Goobys im `ranch_tiere.gd`-/`city_fussgaenger.gd`-Kostüm-Stil —
keine neuen Rigs, nur Requisiten (Hut, Monokel, Aktentasche).

---

## 5) Mitarbeiter & Stationen

### 5.1 Das Team (einstellbar über Aushang am Schwarzen Brett)

| Mitarbeiter | Station | Stats (je 1–5) | Gag-Vertrag |
|---|---|---|---|
| **Grill-Gooby „Gino"** | Grill | Tempo 4 · Sorgfalt 2 · Frohsinn 5 | trägt Sonnenbrille „wegen der Glut", wendet Pattys hinter dem Rücken (bei Sorgfalt-Ausbau: sogar fangen) |
| **Fritten-Gooby „Frida"** | Fritteuse | Tempo 2 · Sorgfalt 5 · Frohsinn 3 | zählt Pommes EINZELN in die Tüte („…41, 42. Perfekt.") — Kunden mit Zahlen-Faible lieben sie |
| **Shake-Gooby „Salvatore"** | Shake-Bar | Tempo 3 · Sorgfalt 3 · Frohsinn 4 | mixt mit Hüftschwung im Takt des Radios; bei Frohsinn 5 tanzt die ganze Schlange mit |
| **Drive-In-Gooby „Danny"** | Sprechanlage | Tempo 5 · Sorgfalt 1 · Frohsinn 5 | spricht JEDE Durchsage in samtiger Radio-Moderator-Stimme („Und hiiiier … Ihre Pommes.") |
| **Kassen-Gooby „Kassandra"** | Kasse | Tempo 3 · Sorgfalt 4 · Frohsinn 2 | prophezeit Kunden ihre Bestellung, BEVOR sie bestellen — liegt fast immer richtig (liest heimlich die Stammkunden-Liste) |

### 5.2 Mechanik: Stationen abgeben statt Personal verwalten

Ein eingeteilter Mitarbeiter **automatisiert seine Station im Rush** (mit Stat-abhängiger
Qualität: Ginos Tempo-4 wendet schnell, aber Sorgfalt-2 heißt gelegentlich „Röstaroma") —
der Spieler konzentriert sich auf die übrigen Stationen. Das ist die Solo-Antwort auf
Overcooked: **Arbeitsteilung mit KI-Kollegen**, und im Koop (§8.1) ersetzt der Freund einfach
einen davon. Stats wachsen langsam durch gemeinsame Schichten (Bindungs-Gedanke der Ranch A1 —
Beziehung statt Excel), Obergrenze 5, kein Grind-Loch.

### 5.3 Schichtplan light

Zwei Slots (Vormittag/Abend) × 5 Mitarbeiter, simple Zuordnung per Drag — wer NICHT
eingeteilt ist, sitzt als Gast im Laden und isst (Welt-Detail!). Es gibt keinen Lohn-Druck:
Mitarbeiter kosten einen fixen kleinen Tagesbetrag NUR an Tagen mit gespielter Schicht oder
aktiver Tageskasse. Ein „Pausentag"-Knopf pro Figur (Urlaubs-Gag: Gino schickt eine
Postkarte vom Ranch-See) — niemand wird je gefeuert (§1.4).

---

## 6) Progression

### 6.1 Laden-Sterne 1–5 (das sichtbare Endziel)

Sterne hängen über der Tür und sind **Zustands-Prüfung, kein Grind-Zähler** — jede Stufe
verlangt etwas QUALITATIVES:

| Stern | Anforderung (alle erfüllen) | Schaltet frei |
|---|---|---|
| ★ | Eröffnungs-Kapitel abgeschlossen | Grundmenü (8 Slots), Fritteuse |
| ★★ | 5 Rezepte gemeistert (je 3× perfekt) + 10 Deko-Objekte platziert | Shake-Bar, Mitarbeiter-Slot 1 |
| ★★★ | Rush-Level 5 mit 2 Sternen + 1 VIP glücklich gemacht | Drive-In-Ausbau, Slot 2, Terrasse |
| ★★★★ | Alle 15 Start-Rezepte auf der Karte gehabt + Kritiker-Besuch bestanden | 2. Fritteuse/Kasse, Koop-Rush-Aushang |
| ★★★★★ | 3 geheime Rezepte + „Perfekte Schicht" (fehlerfrei, ≥ 12 Kunden) | **Funkelpark-Filiale (§9.5)** + goldene Löffel-Bögen-Politur (Nacht-Glanz-Look) |

### 6.2 Freischalt-Gate (Vorschlag): **Level 14 + 3000 Münzen**

Begründung: Die Ranch liegt bei Level 15 + 2500 (nach W13-Senkung). McGooby EINEN Level
früher (14) macht es zum „ersten Riesen-DLC-Moment" für Neuspieler und entzerrt die beiden
Kauf-Momente; dafür 3000 Münzen, weil der Laden — anders als die Ranch — sofort eine
EINKOMMENS-Maschine ist (Schichten + Tageskasse) und der Preis das vorwegnimmt. Beides
liegt als Balance-Daten im Pack (`content/mcgooby/data/balance.json`, deep-merge wie
`content/ranch/`) — per Auto-Update nachjustierbar, exakt das Ranch-Muster (`ranch_offer.gd`
/ `ranch_kauf.gd` als Code-Vorlage für `mcgooby_offer.gd`).

### 6.3 Erfolge (Achievements-Pack, `achievements.counters`-Mechanik)

`flipMeister` (50 perfekte Patty-Flips) · `siebenGurken` (Bürgermeister exakt bedient) ·
`schichtHeld` (erste fehlerfreie Schicht) · `driveInDurst` (25 Drive-In-Bestellungen) ·
`flauschFabrik` (100 Shakes) · `gartenKoch` (30 Gerichte NUR aus Eigenanbau-Zutaten) ·
`nachtEule` (Mitternachts-Schicht) · `sterneKoch` (5 Laden-Sterne) · `vollesHaus`
(12 Kunden in einer Schicht) · `kritikerLiebling` (Monokel 3× beschlagen).

### 6.4 Sticker-Set „mcgooby" (6 Motive, `content/stickers/`-Format wie Set `kueche`/`ranch`)

1. **„Erster Arbeitstag"** — Gooby mit viel zu großer Papier-Servicemütze, die über ein
   Ohr gerutscht ist; Schürze noch mit Preisschild. (Eröffnungs-Kapitel)
2. **„Flip!"** — Patty in Zeitlupe über dem Grill, Gino und Gooby schauen beide ehrfürchtig
   nach oben. (Counter `flipMeister`-Fortschritt 50)
3. **„Der rosa Flausch"** — der Shake höchstpersönlich: rosa Sahne-Wolke mit zwei kleinen
   Löffel-Ohren, Kirsche als Stupsnase. (10 Flausch-Shakes gemixt)
4. **„Sieben. Exakt sieben."** — Bürgermeister-Gooby mit Amtskette, selig über einem
   aufgeklappten Gurken-Deluxe, hält sieben Finger hoch (naja, Pfoten). (Counter `siebenGurken`)
5. **„Monokel ab!"** — der Food-Kritiker, Monokel komplett beschlagen, eine einzelne
   Träne der Rührung. **Rarität: geheim.** (Counter `kritikerLiebling`)
6. **„Fünf Sterne über der Stadt"** — der Laden bei Nacht, goldene Löffel-Bögen leuchten,
   fünf Sterne funkeln darüber wie Sternbilder. (5 Laden-Sterne)

---

## 7) Events & Gags (Random-Event-Engine, Kontext `mcgooby`)

Die Event-Engine hat seit W13 ein Kontext-Tor (`scripts/events/random_events.gd`,
`context`-Feld — die Ranch nutzt es schon). McGooby-Events docken identisch an; alle sind
Zeitfenster-Gags mit witzigem Fail-Text, NIE Strafen (Ranch-H3-Regel):

1. **Frittenfett-Alarm 🍟** — die Fritteuse blubbert ÜBERDRAMATISCH (reine Inszenierung,
   nichts brennt): 10-Sekunden-Deckel-drauf-Minimoment. Geschafft: „Krise gemeistert"-Buff
   (+Trinkgeld 1 Schicht). Verpasst: Die Sprinkler-Anlage macht … Seifenblasen. Kunden applaudieren.
2. **Möwen-Überfall aufs Drive-In 🐦** — 3 Möwen im Anflug auf ein wartendes Pommes-Tablett;
   Tap-Abwehr im Wackelkurs. Verpasst: Die Möwen posieren frech mit je einer Pommes fürs
   Foto (POW!-Kamera-Aufforderung). Fehlerfrei überstanden → Pfad zum „Möwen-Snack" (§3.2).
3. **Food-Kritiker-Besuch mit Monokel 🧐** — kündigt sich per Brief einen Tag vorher an
   (NotifyScheduler, sanft & opt-in): „Man speist. Man urteilt." Bestellt 3 Gänge quer durch
   die Karte; Bewertung = ehrliche Funktion der Rush-Leistung, verpackt in herrlich
   gestelzte Kritiker-Prosa über das Dialog-System. Bei Perfektion beschlägt das Monokel (§6.4).
4. **Der Praktikant** — ein winziger Azubi-Gooby „hilft" eine Schicht lang: sortiert die
   Gurken nach GRÖSSE, stapelt Becher zu Türmen. Rein kosmetisches Chaos + 1 Bonus-Sticker-Chance.
5. **Doppelter Regenbogen überm Laden** — Foto-Aufforderung; Shake-Verkäufe funkeln 1 Tag.
   (Direkter Verwandter des Ranch-Regenbogen-Events — Wiedererkennungs-Humor.)

---

## 8) Multiplayer (offline-first, GOOBY-SERVER-Bestand)

### 8.1 Koop-Rush: „Übernimm die Fritteuse!" (Overcooked-light)

Ein Freund tritt der Schicht bei und **übernimmt 1–2 Stationen komplett** — der Host sieht
die Station als „von Mira besetzt" (Namensschild + Remote-Gooby hinter der Theke).
Technik-Pfad ist VORGEZEICHNET: die generischen **`mg:`-Räume** des Servers
(`GOOBY-SERVER/src/rooms.js`; `ranchmp.js` zeigt das komplette Muster inkl. Invite/Rejoin
über `mg:`-Room-Codes). Weil der Kundenstrom deterministisch aus dem Seed kommt (§4.1),
reicht ein schlankes Input-Relay: beide Clients simulieren dieselbe Schicht, übertragen
werden nur Stations-Aktionen + Ergebnis-Bestätigungen des Hosts (Autorität). Drift-Fallback:
Host-Snapshot alle 5 s (POS-Relay-Frequenz des Besuchssystems). Punkte werden GETEILT
gefeiert — es gibt EINE Schicht-Wertung, keine Solo-Konkurrenz im Koop (Overcooked-Lehre:
zusammen lachen, nicht gegeneinander rechnen).

### 8.2 Beste-Woche-Leaderboard (nur Freunde)

Pro Woche (deterministischer Wochen-Seed) zählt die beste Schicht-Wertung; das Board zeigt
NUR Freunde + die eigene Bestleistung (Ranch-F5-Regel: kein globales Board, kein Abstieg).
Async & offline-first: Scores syncen, wann immer online — offline zeigt der Aushang die
lokale Bestmarke mit freundlichem Chip (Muster C §6).

### 8.3 Besuch: „Ich ess bei dir!"

Das Besuchssystem (visits/rooms) erweitert um den Laden: der Freund sitzt als Gast im
Gastraum, sieht Deko, Speisekarten-Fotos (§2.3.5) und Sterne — und kann EIN Gericht
„bestellen", das der Host live zubereitet (Mini-Rush mit einem einzigen, sehr geduldigen
Kunden). Der stärkste Zeig-Moment des DLC — Gästebuch-Stempel inklusive (Ranch-F3-Muster).

---

## 9) Synergien — McGooby macht bestehende Systeme wertvoller

1. **GOOBERANDO liefert DEINE Burger aus! 🛵** Der Laden wird Eintrag in
   `scripts/city/delivery/restaurants.gd` — Gooby kann bei sich selbst bestellen (Gag-Dialog:
   „Der Koch sieht Ihnen ähnlich."), und die bestehende **Fahrer-Sim** (`fahrer_sim.gd`,
   deterministische A*-Fahrt) fährt sichtbar VOM eigenen Laden los. Ausbaustufe: eingehende
   GOOBERANDO-Bestellungen erscheinen als 6. Bestell-Quelle im Rush („Online-Bestellung!
   3 GoobyMac außer Haus") und der Fahrer holt sie am Tresen ab — zwei W13-Systeme, ein Loop.
2. **Garten-Gemüse als Zutaten 🥕** Eigenanbau = billigste Bezugsquelle (§2.3.2): Möhre,
   Tomate, Salat existieren als Crops; **Mais, Kürbis, Zwiebel** kommen als neue
   `garden_crops`-Einträge — und schließen dabei GLEICH die offene veggies-Sticker-Lücke aus
   dem W13-SAMMLUNG-Request (radish/corn/eggplant/pumpkin fehlen dort noch — corn + pumpkin
   liefert McGooby, die Restlücke wird im selben Zug billig). Garten-Fans bekommen erstmals
   einen ÖKONOMISCHEN Grund für Großanbau.
3. **Ranch-Milch für Shakes 🐄** Ranch-Besitzer verarbeiten Kuhmilch (Sammel-Einkommen D4)
   zu Shakes mit „Frisch von der Ranch"-Bonus-Trinkgeld; der Ranch-Burger (§3.2) ist der
   Cross-DLC-Handschlag. Kein Zwang: Milch gibt es auch bei REHWEI.
4. **Auto & Stadt 🚗** Drive-In nutzt das eigene Autohaus-Auto samt `car_stats_logic`
   (schnelleres Vorfahren ist reiner Show-Gag, keine Pay-to-Win-Mechanik); der Laden liegt
   als neuer Ort in `city_map.json` mit Straßen-Anbindung (Muster `goobyman`-Eintrag W13C —
   Achtung: Zentrums-Tiles sind knapp, Kulisse-Tests mitziehen).
5. **Funkelpark-Filiale als Endgame-Gag 🎡** Bei 5 Sternen eröffnet ein WINZIGER
   McGooby-Kiosk im Funkelpark (`scripts/park/funkelpark.gd`): ein Fenster, ein Mitarbeiter
   nach Wahl, verkauft GENAU ein rotierendes Gericht an Parkbesucher. Kein zweiter
   Management-Sim — ein Denkmal, das man besuchen kann („Vom Eckgrundstück zum Imperium").
6. **Level/Wirtschaft/Sticker** XP über den Minigame-Standard (`leveling.gd`), Münz-Senken
   (Ausbau, Deko, Einkauf) und -Quellen (Schichten, Tageskasse) halten die eine Währung im
   Kreislauf; Sticker-Set + Erfolge füttern die bestehende Sammel-Meta.

---

## 10) Technik-Blaupause

### 10.1 Save-Slice `mcgooby` (additiv, `ranch_play_slices.gd`-Muster)

```
mcgooby: {
  besitz: { gekauft, kaufAt },                    // Gate-Kauf, atomar wie ranch_kauf
  laden: { sterne, ausbau: {kueche, driveIn, terrasse, kasse2}, dekoGrid },
  menu:  { slots: [rezeptId…], preise: {id: faktor}, fotos: {id: fotoRef} },
  rezepte: { freigeschaltet: [id…], geheimFortschritt: {…}, gemeistert: {id: n} },
  lager: { zutatId: menge },                      // ohne Verfall
  team:  { mitarbeiterId: {stats, schicht, pausentag} },
  schichten: { bestwert, wochenBest: {seed, score}, perfekte: n },
  kasse: { offlineStandAt }                       // Tageskasse-Timestamp (Zeit-Injektion)
}
```

Additive Unterschlüssel mit normalize-Self-Heal, NIE Version-Bump (Ranch-I6-Regel).
Alle Zeitlogik (Tageskasse, Specials, Stoßzeiten, Kritiker-Ankündigung) läuft über die
injizierte Uhr — golden-value-testbar wie `fahrer_sim.gd`.

### 10.2 Pack-Struktur `content/mcgooby/` (Schema 1, Vorbild `content/ranch/pack.json`)

```
content/mcgooby/
  pack.json          // { id: "mcgooby", domains: ["mcgooby", "balance"], min_native, priority }
  data/
    rezepte.json     // 15 Start- + 5 Geheim-Rezepte: Zutaten-Bäume, Stationen, Punkte
    zutaten.json     // Bezugsquellen + Preisstaffeln (Garten/REHWEI/Notlieferung)
    kunden.json      // Typen, Geduld-Parameter, VIP-Definitionen, Sprüche-Keys
    team.json        // 5 Mitarbeiter: Stats, Stations-Zuordnung, Gag-Dialog-Keys
    ausbau.json      // Stufen, Kosten, Grid-Katalog-Erweiterungen (Deko-Sets)
    balance.json     // Gate (Level 14 / 3000), coin_table, Timing-Fenster (deep-merge)
```

Dazu: `content/stickers/` +6 Einträge (Set `mcgooby`, Pack-Version-Bump, Muster `b7de0efc`),
`content/achievements/` +10 Counter-Erfolge, `strings/de+en/mcgooby.json` (DE↔EN-Paritäts-Test!
EXPECTED_DOMAINS-Eintrag beim INTEGRATE-Pass anmelden — W13-Lernkurve).

### 10.3 Wiederverwendung (nichts doppelt bauen — die McGooby-Einkaufsliste)

| Bestand | Rolle im DLC |
|---|---|
| Minigame-Framework (`minigame_base/host`, `framework_logic`, `juice_kit`, `gooby_rng`) | Rush-Spiel `mcgoobyRush` inkl. Sterne/Coins/Endless — Stations-Logiken als 4 pure Module |
| `burger_build_logic.gd` (Punkte-Grammatik 4–7 Lagen, ±Punkte) | Direkter Vorfahre der Belegstation — Zahlenwerk übernehmen, Input-Modell tauschen |
| `ranch_level_select.gd` + 10-Level-Sterne-Muster | Schicht-Szenarien L1–L10 |
| Dialog-System (`dialog_runner/view/typewriter.gd`) | Kunden-Sprüche, Kritiker-Prosa, Eröffnungs-Kapitel |
| Grid-Baumodus (`home/build_mode/`, `grid_data.gd`) | Gastraum-Deko + Ausbau (Ranch-D1-Pfad, hier Innenraum = geringeres Risiko) |
| Fahrer-Sim + `restaurants.gd` (`scripts/city/delivery/`) | GOOBERANDO-Auslieferung ab Tag 1; eingehende Bestellungen als Rush-Quelle |
| Ort-Muster `goobyman.gd` + `ort_katalog`/`city_map.json` | Laden als Stadt-Ort mit Fassade, Tile + Straßen-Anbindung (Drive-In) |
| `random_events.gd` (Kontext-Tor) + NotifyScheduler | §7-Events, Kritiker-Ankündigung, „Tageskasse voll"-Gruß (max 2/Tag, opt-in) |
| `ranch_offer/kauf.gd` | Kauf-Gate-Flow 1:1 als `mcgooby_offer/kauf.gd` |
| `ranch_offline.gd`-Zeitmuster | Tageskasse (gedeckelt, 8-h-Sim) |
| GOOBY-SERVER `rooms.js` (`mg:`) + `ranchmp.js`-Muster + visits | Koop-Rush, Wochen-Board, Laden-Besuch |
| POW!-Fotomodus + Sticker-Registry + `leveling.gd`/`economy.gd` | Speisekarten-Fotos, Set, XP/Münzen |

### 10.4 Test-Strategie

Jede Station liefert `simulate_autoplay` + expected-JSONs (Bot-Zertifizierung, Fairness-Regeln
G §2.5); der deterministische Kundenstrom (§4.1) macht ganze Schichten golden-testbar
(Seed → erwartete Bestellliste → erwartete Bot-Wertung). Menü-/Preis-/Lager-Logik sind pure
Module mit Unit-Tests; Koop bekommt einen Replay-Test (Input-Log beider Seiten → identischer
End-Zustand). Sync-Tests Katalog↔Strings↔Sticker nach dem Muster
`test_rehwei_buecher_kategorie_synchron`.

### 10.5 Wellen-Schnitt (jede Welle shippable, Datei-Schätzungen)

- **W-A „Der Laden öffnet" (Fundament, ~20–24 Dateien):** Ort + Kauf-Gate
  (`scripts/city/orte/mcgooby.gd` + `.tscn`, `mcgooby_offer/kauf.gd`, `city_map.json`-Eintrag
  + Kulisse-Test-Anpassung), Save-Slice (`scripts/mcgooby/mcgooby_state.gd` +
  `mcgooby_slices.gd`), Rush-Minispiel (`minigames/games/mcgooby_rush/`: Szene + 4 pure
  Stations-Logiken + `game.json` + Bot-Tests), Menü-Tafel + Einkauf light
  (`mcgooby/menu_logic.gd`, `einkauf_sheet.gd`), Pack `content/mcgooby/` (rezepte 15,
  zutaten, balance), `strings/de+en/mcgooby.json`, ~6 Unit-Test-Dateien.
  → Spielbar: kaufen, Menü bauen, Schichten spielen, verdienen.
- **W-B „Rush-Hour" (Tiefe, ~16–20 Dateien):** Kunden-Typen + Geduld + VIPs (`kunden_logic.gd`,
  `kunden.json`), Stoßzeiten + Tages-Specials (`specials_logic.gd`), Mitarbeiter + Schichtplan
  (`team_logic.gd`, `team_sheet.gd`, `team.json`), Grid-Gastraum + Ausbaustufen (`ausbau.json`,
  Grid-Katalog), Drive-In (Spur in Ort-Szene, Sprechanlagen-Sheet, Auto-Anbindung),
  GOOBERANDO-Synergie (Eintrag `restaurants.gd` + Rush-Quelle), Events ×5 (`random_events`-Defs,
  Kontext `mcgooby`), Sticker-Set + Erfolge, Garten-Crops (corn/pumpkin/zwiebel + Visuals),
  Tageskasse. → Spielbar: das volle Solo-DLC.
- **W-C „Volles Haus" (Koop + Endgame, ~12–15 Dateien + Server):** Koop-Rush
  (`GOOBY-SERVER/src/mcgoobymp.js` nach `ranchmp.js`-Muster ODER rein generische `mg:`-Rooms;
  Client `mcgooby/coop_rush.gd` + Input-Relay + Replay-Test), Wochen-Board (Server-Scores +
  Aushang-UI), Laden-Besuch (Besuchssystem-Erweiterung), 5 geheime Rezepte + Kritiker-Event,
  Speisekarten-Fotos, Funkelpark-Kiosk (`park/`-Anbau, S), 5-Sterne-Zeremonie.
  → Spielbar: alles aus §8 + Endgame.

### 10.6 Risiken (ehrlich) & Gegenmittel

1. **Rush-Performance auf iPhone (DAS Hauptrisiko):** 4 Stationen + bis zu 6 Kunden +
   Drive-In-Autos + Partikel gleichzeitig. Gegenmittel: harter Kunden-Deckel (6 sichtbar,
   Rest als Schlangen-Zähler am Fenster), EIN gemeinsames 3D-Set (kein SubViewport pro
   Station — Kamera schwenkt, Muster `burger_build_stage3d.gd`), Zutaten/Deko als MultiMesh,
   Partikel-Pooling über JuiceKit, Draw-Call-Budget-Test ≤ 400 wie die Ranch-Welt (I5)
   als headless CI-Pflicht ab W-A.
2. **Stress-Kippe (cozy vs. Overcooked):** Rush kann in Hektik kippen. Gegenmittel:
   Geduld-Einfrieren bei aktiver Arbeit, 0-❤-Regel ohne Strafe, „Gemütlich"-Modus ab W-A
   (nicht nachgereicht!), Playtest-Regel: jede Schicht muss mit einem Lächeln enden können.
3. **Scope-Explosion (Management + Geschick + MP):** Drei Genres in einem DLC. Gegenmittel:
   Wellen-Schnitt ist fail-safe geschnitten — W-A allein ist bereits ein rundes Produkt;
   Menü-Preise/Team sind DATEN-Systeme (Pack), keine Engine-Arbeit.
4. **Koop-Drift:** Input-Relay auf deterministischer Sim kann divergieren. Gegenmittel:
   Host-Autorität + 5-s-Snapshots, Replay-Test in CI, Fallback „Koop light" (Freund spielt
   Stations-Minispiel isoliert, Ergebnisse mergen) als abgesicherte Rückfalllinie.
5. **Balance-Wirtschaft:** Laden-Einkommen könnte Münz-Inflation treiben. Gegenmittel: alle
   Quellen gedeckelt (Tageskasse 8 h, Schicht-Coin-Table wie Minigames), große Senken (Ausbau,
   Deko-Sets), Zahlen ausschließlich im Balance-Pack → live nachsteuerbar ohne Release.
6. **Parodie-Grauzone:** Namen/Optik dürfen nicht verwechselbar sein. Gegenmittel:
   Designregel §1.2 (eigene Wortschöpfungen, Löffel-statt-Bögen-Form), Review-Checkliste
   pro Asset vor Merge.

---

## 11) Anti-Spoiler-Teaser + DLC-Hub-Stichpunkte

**Teaser (2 Sätze):** In der Stadt duftet es neuerdings verdächtig nach Pommes — und über
einem leeren Eckgrundstück hängen zwei goldene Bögen, die bei genauem Hinsehen aussehen wie
Löffel mit Ohren. Gooby bindet sich die Schürze um: Bald hat hier jemand seinen eigenen Laden.

**4 Feature-Stichpunkte für den DLC-Hub:**

- Dein eigener Fast-Food-Laden: Menü festlegen, Preise machen, Gastraum frei einrichten
- Der Bestell-Rush als echtes Geschicklichkeits-Spiel: wenden, belegen, frittieren, mixen
- Drive-In mit deinem eigenen Auto — und GOOBERANDO liefert deine Burger aus
- Koop-Schichten mit Freunden und knuffige Stammkunden vom Bürgermeister bis zum Monokel-Kritiker

(Identischer Inhalt zusätzlich per Anhang an `/tmp/gooby-godot/handoffs/W13-requests.md`,
Tag IDEEN-MCGOOBY, für den DLC-Hub-Owner.)

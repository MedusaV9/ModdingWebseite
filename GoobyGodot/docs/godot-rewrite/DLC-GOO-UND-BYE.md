# DLC-GOO-UND-BYE — W14/IDEEN: „Goo und Bye" — Goobys eigener Supermarkt

Auftrag (User, wörtlich): Ein „Riesen DLC" — Gooby soll „einen eigenen Supermarkt mit
Mitarbeitern und Ware transportieren und auch selber bauen etc haben […] der ‚Goo und Bye'" —
„man hat einen eigenen Supermarkt/Einkaufsladen und muss den Managern und bauen etc alles".
Dieses Dokument bündelt die Ideen von **20 Perspektiven** (Rolle IDEEN-GOOBYE) und verdichtet
sie zu einem bauplan-reifen DLC-Design: (§1) Vision & Ton, (§2) Kern-Loop mit Zahlen,
(§3) Laden-Bau, (§4) Warenwirtschaft, (§5) Mitarbeiter, (§6) Kunden-Sim, (§7) Progression,
(§8) Events & Gags, (§9) Multiplayer, (§10) Technik-Blaupause, (§11) Teaser für den DLC-Hub.
Aufwand nur als **S/M/L** (Umfang/Risiko/betroffene Systeme), niemals Kalenderzeit.
Vorbilder in Struktur und Anspruch: `RANCH-DLC-IDEAS-1.md` und das Schwester-Doc
`DLC-MCGOOBY.md`. **Abgrenzungs-Vertrag zu McGooby** (Dopplungs-Verbot + Synergie-Gebot)
in §1.5 — die beiden Läden sind Geschwister, keine Zwillinge.

---

## 0) Die 20 Perspektiven — wer hat was gefordert, und wo ist es gelandet?

| # | Perspektive | Kernforderung (verdichtet) | Gelandet in |
|---|---|---|---|
| 1 | Wirtschafts-Sim-Fan | Echte Margen, Einkauf/Verkauf-Spanne, Umsatz-Screen mit Zahlen, die man FÜHLEN kann | §2.2, §4.4, §7.1 |
| 2 | Casual-Spieler | 5-Minuten-Besuch muss sich lohnen; gute Defaults („empfohlener Preis"-Knopf), nie Bestrafung | §2.3, §2.5, §4.4 |
| 3 | Kind (8 Jahre) | Mini-Einkaufswagen schieben, Quengelware am Band, alles anfassbar und knuffig | §3.3, §6.3, §8 |
| 4 | Completionist | Alle 40+ Waren listen, Sortiment-Album, Sticker, Erfolge, 5-Sterne-Markt als Endziel | §4.1, §7.3, §7.4 |
| 5 | Deko-Fan | Laden SELBST bauen (Grid!), Themen-Sets, Schaufenster gestalten, Schild-Editor | §3.1–§3.5 |
| 6 | Speedrunner | „Perfekter Markttag", Einräum-Bestzeiten, Kassen-Combo als Skill-Kirsche | §2.4, §7.3 |
| 7 | Multiplayer-Fan | Freunde sollen bei mir ECHT einkaufen, nicht nur gucken; Vergleich unter Freunden | §9.1, §9.2 |
| 8 | Streamer | Zeigbare Momente: eigener Laden-Name, kuriose Kunden-Clips, Vorher/Nachher-Ausbau | §3.5, §6.3, §8 |
| 9 | Mobile-UX-Designer | Hochkant, Einhand, Bestell-Sheet mit ±-Steppern, maximal 2 Menü-Ebenen | §2.5, §4.1, §10.6 |
| 10 | Anti-Monetarisierungs-Wächter | ALLES in Ingame-Münzen; keine zweite Währung, kein FOMO, kein Abo | §1.4, §2.2, §7.2 |
| 11 | Two-Point-/Supermarket-Simulator-Veteran | Layout IST Gameplay: Laufwege, Warteschlangen, Nachfüll-Logistik | §3.3, §5.2, §6.2 |
| 12 | Animal-Crossing-Fan | Sanfte Tagesrituale, saisonale Ware, der Laden als Ort zum Gernhaben (Nook-Gefühl) | §2.3, §4.1, §8 |
| 13 | Stardew-Fan | Eigenanbau → eigenes Regal: die Garten-Pipeline endlich mit ökonomischem Sinn | §4.1, §4.5 |
| 14 | Accessibility-Advocat | Kein Zeitdruck als Pflicht, Form+Farbe-Kodierung der Warengruppen, ≥ 44-pt-Ziele | §2.5 |
| 15 | Performance-Skeptiker | Kunden-Deckel, MultiMesh-Regale, Draw-Call-Budget wie Ranch/Stadt | §10.6 |
| 16 | Story-Fan | WARUM bekommt Gooby einen Laden? Übergabe-Kapitel mit Herz | §1.3, §7.1 |
| 17 | Humor-Autor | Parodie-Eigenmarke, Kunden-Sprüche, Marktradio-Durchsagen, REHWEI-Rivalitäts-Gag | §1.2, §4.1, §6.3, §8 |
| 18 | Sound-Designer | **Kassen-Piepen als Gebrabbel-Melodie**, Tür-Jingle „Goo!/Bye!", Einräum-ASMR | §1.2, §2.4 |
| 19 | Live-Ops-Planer | Saison-Sortimente + Aktionswochen als Content-Packs nachliefern | §4.1, §10.2 |
| 20 | QA-Tester | Deterministischer Markttag (Seed → Bon-Liste), pure Logik-Module, golden-testbar | §6.1, §10.4 |

---

## 1) Vision & Ton

### 1.1 Elevator-Pitch

**Goo und Bye ist das Management-Herzstück unter den GOOBY-DLCs:** Gooby übernimmt einen
leerstehenden Eckladen und macht daraus SEINEN Supermarkt — vom klapprigen Tante-Gooby-Laden
bis zum „Goo und Bye XXL" mit Kühltheke, Backecke und Abholschalter. Der Reiz ist nicht
Fingerfertigkeit (das ist McGoobys Revier, §1.5), sondern **Köpfchen und Fürsorge**: Was
liste ich? Wo steht welches Regal? Was kostet die Möhre? Wer füllt nach, während ich beim
REHWEI-Großmarkt den Kofferraum volllade? Wie bei Ranch und McGooby gilt: kuschelig, deutsch,
offline-first, **eine Währung**, kein FOMO — nur dass hier statt Pommes-Duft eben das
zufriedene Piepen einer gut gehenden Kasse durch die Stadt klingt.

### 1.2 Namens- & Sound-Gags (der Laden hat eine Stimme)

- **Der Name ist der Türsensor:** Die automatische Schiebetür begrüßt jeden Kunden mit
  einem fröhlichen **„Goo!"** und verabschiedet ihn mit **„Bye!"** — gesprochen in Goobys
  Gebrabbel-Stimme. Steht die Tür auf Dauerbetrieb (Stoßzeit), wird daraus ein
  „Goo-Goo-Goo-Bye-Goo-Bye"-Kanon. Das Ladenschild zeigt zwei Ohren als Apostroph.
- **Kassen-Piepen als Gebrabbel-Melodie (DAS Audio-Herzstück):** Jede Warengruppe hat eine
  eigene Tonhöhe aus Goobys Gebrabbel-Samples. Wer einen Einkaufskorb scannt, SPIELT also
  eine kleine Melodie — der Wocheneinkauf einer Familie klingt wie ein Liedchen, drei
  Möhren wie ein Terz-Hüpfer. Sortier-Nerds legen Kunden die Waren absichtlich in
  „Melodie-Reihenfolge" aufs Band (rein kosmetisch, aber unwiderstehlich). Am Tagesende
  spielt der Kassensturz-Screen die „Melodie des Tages" (die häufigste Bon-Folge) als Jingle.
- **Der „Goo und Bye"-Jingle:** Das Marktradio (bestehender `MusicDirector`) spielt zwischen
  Lo-Fi-Tracks den hauseigenen Werbe-Jingle — vier Töne, „Goo… und… Byyye…", gesungen von
  einem sehr motivierten, leicht schiefen Gooby-Chor (die Mitarbeiter, §5). Kunden summen
  ihn beim Einkaufen mit; verlässt ein Kunde SEHR zufrieden den Laden, pfeift er ihn.
- **Marktradio-Durchsagen** als Humor-Kanal über das Dialog-System: „Liebe Kundschaft,
  im Gang drei kuschelt ein Gooby. Bitte nicht stören." · „Der Besitzer des blauen
  Bollerwagens: Ihr Wagen rollt. Schon wieder." · „Heute im Angebot: Freude."
- **Einräum-ASMR:** Dosen-Klonk, Flaschen-Klirren, das Rascheln der Papiertüten — Einräumen
  soll sich anhören wie eine sanfte Perkussion-Session (JuiceKit-Sound-Pooling).

### 1.3 Rahmen-Geschichte (kurz, über das Dialog-System erzählt)

**Onkel Alwin** hat den kleinen Eckladen 40 Jahre lang geführt und geht jetzt „auf große
Möhren-Kreuzfahrt". Statt zu verkaufen, drückt er Gooby einen riesigen Schlüssel und einen
Zettel in die Pfote: „Der Laden mag dich. Gieß die Kasse zweimal die Woche." Kapitel-Bogen
**„Die Schlüsselübergabe"** in 4 Schritten (Schlüssel annehmen → ersten Großmarkt-Einkauf
machen → 3 Probe-Kunden bedienen → Eröffnungs-Banddurchschnitt mit halber Stadt) — erzählt
über `dialog_runner.gd`, Kauf-Flow nach `ranch_kauf.gd`-Muster. Danach kommt Alwin täglich
als Stammkunde wieder und kauft GENAU eine Möhre („Alte Gewohnheit."). Und REHWEI? Nimmt die
neue Konkurrenz sportlich und schickt zur Eröffnung Blumen: „Willkommen im Geschäft. Mögen
die besten Möhren gewinnen." (Sie ahnen nicht, dass Gooby bei ihnen im Großmarkt einkauft, §4.1.)

### 1.4 Fünf bewusste Nicht-Ziele

1. **Keine zweite Währung, kein Echtgeld, keine Wartezeit-Verkürzer:** Alles — Kauf, Ausbau,
   Ware, Deko — läuft über die eine Münz-Wirtschaft. Der Laden ist Münz-QUELLE und -SENKE
   zugleich (§10.6-Risiko 3), niemals ein Shop im Shop.
2. **Kein Verderb, keine Pleite, kein Fail-State:** Ware verfällt nicht (§4.3), Miete gibt es
   nicht, ein leeres Regal ist eine To-do-Notiz, keine Strafe. Der schlimmste Tag endet mit
   „Na, morgen wird's voller" — nie mit Minus.
3. **Kein Personal-Feuern, kein Burnout:** Mitarbeiter haben Zufriedenheit statt Stress-Balken
   und machen höchstens „Pausentag" (§5.3).
4. **Kein Hektik-Zwang:** Es gibt KEINEN Timer auf Management-Entscheidungen. Die einzige
   optionale Tempo-Mechanik ist das freiwillige Selbst-Kassieren (§2.4).
5. **Kein globales Leaderboard, kein PvP:** Wochenumsatz-Vergleich nur unter Freunden
   (Ranch-Regel F5, McGooby §8.2 — dieselbe Linie).

### 1.5 Abgrenzungs-Vertrag zu McGooby (Dopplungs-Verbot, Synergie-Gebot)

Beide DLCs sind „Gooby führt einen Laden" — damit sie sich nie kannibalisieren, gilt:

| Achse | McGooby (Fast-Food) | Goo und Bye (Supermarkt) |
|---|---|---|
| Kern-Skill | **Geschick** (4-Stationen-Rush, Timing-Gesten) | **Köpfchen** (Sortiment, Layout, Logistik) |
| Aktiv-Moment | Schicht als Minispiel-Kette | Markt-Session als Manager-Rundgang; Kasse = EINE optionale Geste (§2.4) |
| Kunden | bestellen AN der Theke (Ticket) | laufen SELBST durch den Laden (Routing-Sim, §6.2) |
| Ware | Rezepte aus Zutaten | Handelsware in Warengruppen (Ein- & Verkauf) |
| Bau | Gastraum-Deko | Laden-Layout ist SPIELMECHANIK (Laufwege, §3.3) |
| Verboten | — | KEIN Multi-Stationen-Geschicklichkeits-Rush in Goo und Bye |
| Synergien | siehe §4.5: McGooby kauft Zutaten bei Goo und Bye ein; Goo und Bye führt das „GoobyMac-Fertiggericht" im Kühlregal | — |

---

## 2) Kern-Loop: Einkaufen → Regale → Kunden → Kasse → Gewinn → Ausbau

### 2.1 Der Markt-Loop

```
   EINKAUFEN (REHWEI-Großmarkt / Garten)      LADEN LÄUFT (Kunden-Sim, §6)
   Ware ordern, Auto beladen (§4.2)     ───▶  Kunden laufen Einkaufslisten ab,
   Regale einräumen & Preise setzen     ───▶  nehmen aus Regalen, stellen sich an
   Layout & Deko verbessern (§3)              Kasse piept die Gebrabbel-Melodie
   Mitarbeiter einteilen (§5)           ◀───  Münzen + Laden-XP + Zufriedenheit
                                              zurück in Ausbau, Sortiment, Deko
```

Der Loop ist bewusst ein **Kreislauf mit zwei Tempi**: Einkauf/Einräumen/Bauen sind ruhige,
jederzeit pausierbare Handgriffe; der Kundenstrom läuft deterministisch weiter (auch offline,
gedeckelt, §2.2) — der Laden fühlt sich LEBENDIG an, ohne den Spieler zu hetzen.

### 2.2 Das Zahlenwerk (alle Werte im Balance-Pack, live nachsteuerbar)

- **Freischalt-Gate:** Level 12 + **2500 Münzen** (Begründung §7.2). Im Kaufpreis steckt das
  **Eröffnungspaket**: 4 Grundregale, 1 Kasse, Lagerraum-Grundfläche und ein
  **300-Münzen-Warengutschein** für den ersten Großmarkt-Einkauf (= Startbudget; niemand
  steht vor leeren Regalen und leerer Tasche).
- **Margen:** Großmarkt-Einkaufspreis = **60 % des empfohlenen Verkaufspreises** (Grundmarge
  40 %). Eigenanbau aus dem Garten kostet nur Saatgut+Zeit (**~25 % Selbstkosten**) und darf
  als „Bio vom Gooby-Beet" mit **+10 % Aufschlag** gelistet werden — die Stardew-Pipeline mit
  echtem ökonomischem Sinn (§4.1). Notlieferung: Einkauf +50 % (Anti-Frust-Knopf, §4.2).
- **Preis-Schieber:** pro Warengruppe **±30 %** um den Richtwert. Teurer = mehr Gewinn pro
  Stück, aber Kunden lassen eher Artikel liegen (sichtbar: Ware wandert zurück ins Regal,
  Kunde seufzt); billiger = größere Körbe und längere Schlangen. EINE fühlbare Kurve, kein
  BWL-Excel — pure Logik `preis_logic.gd`, Zahlen im Pack.
- **Tageszyklus (reale Gerätezeit, Zeit-Injektion `clock.gd`):** Öffnungszeit **8–20 Uhr**,
  Stoßzeiten **12–13** und **17–19 Uhr** (dichterer Kundenstrom + Stoßzeiten-Groove im
  Marktradio), samstags **Rabatt-Samstag** (§8.4). Der Umsatzzähler schneidet um Mitternacht,
  die Woche läuft Mo–So (Wochenumsatz-Board, §9.2).
- **Kundenzahlen & Ertrag (Simulationsziel):** Laden-Level 1 ≈ **25 Kunden/Tag**, Ø-Bon
  **10–14 Münzen** → Tagesgewinn ≈ **100–150**. Level 3 ≈ 70 Kunden, Level 5 ≈ **140 Kunden/Tag**,
  Tagesgewinn gedeckelt bei ≈ **600–800** (Inflations-Schutz §10.6). Sichtbar im Laden sind
  maximal 8 Kunden gleichzeitig, der Rest ist Tagesplan-Simulation (§6.1).
- **Offline-Kasse:** Ist mindestens 1 Mitarbeiter eingeteilt, verkauft der Laden „nebenbei"
  mit **30 % der Live-Rate, maximal 8 h Simulation** (exakt das `ranch_offline.gd`-Zeitmuster,
  rein Timestamp-basiert). Kein Idle-Exploit — ein „Willkommen zurück, die Kasse hat
  gesummt"-Lächeln.
- **Ausbau-Kosten (Münz-Senken):** Laden-Level 2/3/4/5 = **400 / 900 / 1600 / 2500 Münzen**
  (§7.1), dazu Regale 30–120, Kühlmodule 150–300, Deko-Sets 50–400.

### 2.3 Eine Markt-Session in 8 Minuten (Soll-Erlebnis)

Laden betreten (Tür: „Goo!") → Kassensturz-Zettel von gestern am Schwarzen Brett → zwei
Regal-Lücken entdeckt, Lager-Nachschub per Drag eingeräumt (Dosen-Klonk-ASMR) → Bestell-Sheet:
6× Möhre, 4× Käse beim Großmarkt geordert, Auto fährt los (§4.2) → Stoßzeit beginnt, Schlange
wächst: freiwillig selbst an die Kasse, 5 Bons in Melodie-Folge gescannt (Combo! §2.4) →
Oma Hoppel braucht Beratung („Wo ist das Glitzersalz?") → Krähen-Alarm am Obststand (§8.1),
verscheucht → Auto kommt zurück, Kofferraum ausräumen → Feierabend-Vignette: Licht aus,
Tür flüstert „Bye…", der Tagesgewinn hüpft als Münzstapel in die Anzeige.

### 2.4 Die Kasse: der Ein-Gesten-Moment (freiwillig, nie Pflicht)

Die Kasse läuft von allein, sobald ein Kassen-Gooby eingeteilt ist (§5). Aber der Spieler
KANN sich jederzeit selbst hinstellen: Waren wandern übers Band, **ein Tap pro Artikel im
Rhythmus** — trifft man den Takt der Gebrabbel-Melodie, wächst eine kleine Melodie-Combo
(+10 % Trinkgeld-Münzen auf den Bon, ×2,0-Deckel). Kein Fail: Danebentippen macht nur einen
schiefen Ton, der Kunde kichert. Das ist bewusst EINE Geste statt McGoobys Stations-Rush
(§1.5) — Kassieren in Goo und Bye ist ein Fidget-Vergnügen, kein Skill-Test. Wer NIE selbst
kassiert, verpasst Combo-Bonus, aber keinen Inhalt.

### 2.5 Zugänglichkeit & Mobile-UX (ab W-A eingebaut, nicht nachgerüstet)

- **„Einfach führen"-Schalter:** „Empfohlener Preis"-Knopf pro Warengruppe, Auto-Nachfüllen
  durch Mitarbeiter, Bestell-Vorschlag („Das war letzte Woche schnell weg") — der Laden
  läuft auch mit 3 Taps pro Besuch. Identische Erträge minus Combo.
- **Warengruppen sind IMMER Form + Farbe kodiert** (Obst = runder grüner Chip, Kühlware =
  eckiger blauer Chip …), nie nur Farbe. Alle Tap-Ziele ≥ 44 pt (W14-UI-Lernkurve!).
- **Hochkant, Einhand:** Bestell-Sheet mit ±-Steppern in der Daumen-Zone, maximal 2
  Menü-Ebenen (Laden → Sheet), Grid-Baumodus erbt die bewährte Baumodus-Bedienung (§3.1).
- **Kein Pflicht-Timing:** Alles außer der freiwilligen Kassen-Combo ist ohne Zeitdruck.

---

## 3) Laden-Bau: das Layout ist das Spielbrett

### 3.1 Grid-Baumodus-Wiederverwendung (der Ranch-D1/McGooby-Pfad, Innenraum = geringes Risiko)

Der Verkaufsraum ist ein Grid-Raum im Haus-Baumodus-Muster (`scripts/home/build_mode/` +
`grid_data.gd`): Regale, Kühlmodule, Kassen, Deko frei platzieren, drehen, umstellen —
inklusive Geist-Vorschau und Kollisionsprüfung, die es dort schon gibt. NEU ist nur eine
**Platzierungs-Validierung** (§3.3): jedes Layout muss einen begehbaren Pfad Eingang → Regale
→ Kasse lassen (pure Funktion auf `GridData`, unit-testbar). Umbauen ist jederzeit gratis —
umgestellte Regale behalten ihre Ware (kein Ausräum-Zwang).

### 3.2 Item-Katalog (Auszug; alles Pack-Daten in `regale.json`)

| Kategorie | Items (Beispiele) | Grid-Fläche | Kosten | Bemerkung |
|---|---|---|---|---|
| Regale | Grundregal (6 Slots), Eckregal, Wandregal, Obst-Schräge, Brot-Korbregal | 1×2 / 1×1 / 1×2 / 2×2 | 30–80 | Warengruppen-gebunden (Obst nur in Obst-Schräge — Sortier-Klarheit) |
| Kühlung | Kühlregal (Milch/Käse), Tiefkühltruhe (Eis), Getränke-Kühlschrank | 1×2 / 2×1 / 1×1 | 150–300 | schaltet Kühl-Warengruppen frei (§4.3); leises Brummen im Soundbild |
| Kassen | Standardkasse, Doppelkasse, „Goo&Go"-Abholschalter (L5) | 2×1 / 2×2 / 2×1 | 100–400 | mehr Kassen = kürzere Schlangen (sichtbar!) |
| Deko | Pflanzen, Bodenfliesen-Sets, Wimpelkette, Alwins altes Bonbonglas, Poster der Eigenmarke | 1×1 … | 10–120 | Deko-Punkte erhöhen Laden-Attraktivität (§6.5) |
| Spezial | Quengelware-Ständer (an Kasse andockbar), Probierstand, Schwarzes Brett, Bollerwagen-Parkplatz | 1×1 | 60–150 | je ein Gag-Vertrag (§3.3, §6.4) |

Themen-Sets für Deko-Fans: **Alwin-Nostalgie** (Holzregale, Emaille-Schilder),
**Frischemarkt-Grün**, **Mitternachts-Markt** (Neon, passt zur Stadtnacht) — als
Möbel-Pack-Einträge nachlieferbar (Live-Ops §10.2).

### 3.3 Layout ist Gameplay (die Two-Point-Perspektive, kindertauglich übersetzt)

- **Laufwege:** Kunden laufen ihre Einkaufsliste in Regal-Reihenfolge ab (§6.2). Liegen
  Möhren und Käse an entgegengesetzten Enden, dauert der Einkauf länger → weniger Kunden
  pro Stunde. Ein gutes Layout SPÜRT man am Kundenfluss — angezeigt wird es kinderfreundlich
  als **Trampelpfad-Overlay** (abgetretene Bodenstellen zeigen die echten Wege; keine
  Heatmap-UI, die Welt selbst ist die Statistik).
- **Quengelware:** Der Ständer an der Kasse (Sticker-Tütchen! Schokoriegel!) verführt
  wartende Kunden zu +1 Spontankauf — und wartende Kinder-Goobys greifen mit den treuesten
  Augen der Welt danach. (Anti-Moneta-Wächter hat geprüft: es ist ein GAG über Quengelware,
  bezahlt wird in Spielmünzen von Sim-Kunden.)
- **Schlangen sind sichtbar:** Ist nur 1 Kasse offen und die Schlange > 4, holt ein Kunde
  theatralisch ein Klappstühlchen raus. Zweite Kasse öffnen = sofort fühlbare Erleichterung.
- **Pfad-Validierung statt Frust:** Blockiert ein Regal den Weg, zeigt der Baumodus die
  Stelle rot mit einem ratlosen Mini-Gooby davor — platzieren geht erst, wenn der Pfad frei
  ist. Kein „Kunden stecken fest"-Bug-Ärger by design.

### 3.4 Erweiterungsstufen (sichtbare Weltänderung, Gooby-hämmert-Qualm-Animation)

Fünf Laden-Level (Details + Kosten §7.1): Die Grundfläche wächst von **6×6** (12 Regal-Slots)
über **8×8**, **10×10** (+ Kühlzone), **12×12** (+ Backecke mit Duft-Radius + 2. Kasse) bis
**14×14 „Goo und Bye XXL"** (+ Lagererweiterung + „Goo&Go"-Abholschalter, §4.5). Jeder Ausbau
ist von außen sichtbar (größere Fassade, mehr Schaufenster, das Schild bekommt nachts
Beleuchtung — Stufe 5: die Ohren des Apostrophs wackeln im Wind).

### 3.5 Schild-Editor (die Streamer-Perspektive, kindersicher)

Der Laden heißt „Goo und Bye", aber der **Untertitel** auf dem Schild ist frei kombinierbar
aus kuratierten Wortbausteinen (zwei Listen: „Der gemütlichste / flauschigste / möhrigste …"
ד Markt / Laden / Eckladen / Möhren-Palast der Stadt") — sicher, deutsch, witzig,
screenshotbar. Der Untertitel erscheint auf Bons, im Besuchs-Modus (§9.1) und im Foto-Modus.

---

## 4) Warenwirtschaft: vom Großmarkt-Kofferraum bis ins Regal

### 4.1 Bezugsquellen (drei Wege, ein Lager)

1. **REHWEI-Großmarkt (der Running-Gag als Lieferant):** Hinter REHWEI öffnet für
   Gewerbetreibende die Großmarkt-Rampe — Gooby kauft also beim „Konkurrenten" ein, und
   BEIDE tun so, als wäre das völlig normal. (Großmarkt-Gooby, verschwörerisch: „Das bleibt
   unter uns Händlern.") Technisch ist das ein **Wiederverwendungs-Coup**: das Sortiment
   basiert 1:1 auf `scripts/city/data/rehwei_sortiment.json` — dieselben Waren-IDs wie im
   Hauptspiel (`carrot`, `apple`, `bread` …). Folge: **Was Kunden bei Goo und Bye kaufen,
   ist ECHTES GOOBY-Essen** — und was Gooby im eigenen Laden „privat entnimmt", landet als
   normales Lebensmittel im Heim-Kühlschrank (Kassen-Gooby tippt streng: „Das schreib ich
   an, Chef."). Einkauf über ein Bestell-Sheet mit ±-Steppern, Staffelpreise ab 10 Stück (−5 %).
2. **Eigener Garten als Bio-Quelle:** Geerntete Crops (`garden_crops`: Möhre, Tomate, Salat,
   Melone, Chili …) können ins **„Bio vom Gooby-Beet"-Regal** wandern — Selbstkosten ~25 %,
   +10 % Bio-Aufschlag akzeptiert (§2.2). Das DLC ergänzt **3 neue Crops: Radieschen,
   Aubergine, Kartoffel** — und schließt damit (zusammen mit McGoobys Mais/Kürbis) die
   offene veggies-Sticker-Lücke aus dem W13-SAMMLUNG-Request komplett. Garten-Großanbau
   bekommt erstmals einen Laden, der ihn AUFKAUFT.
3. **Notlieferung:** Sofort im Regal, Einkauf +50 % — der Anti-Frust-Knopf, damit nie ein
   Rabatt-Samstag an fehlenden Möhren scheitert. Geliefert wird sie stilecht per
   GOOBERANDO-Fahrer (derselbe Roller, jetzt mit Kistenstapel — Fahrer-Sim-Kulisse gratis).

Dazu die **Eigenmarke „Goobys Gute Ware"** (Humor-Autor): ausgewählte Waren als günstigere
Parodie-Variante mit Gooby-Gesicht auf dem Etikett — „Hoppel-Pops" (Frühstücksflocken),
„Möhrenperlen" (Gummibonbons), „Goo-Cola" (schmeckt nach Möhre. Natürlich.). Eigenmarke =
−20 % Verkaufspreis, +Sympathie-Punkte bei Sparfuchs-Kunden (§6.3). Saison-Sortimente
(Kürbis-Oktober, Winter-Punsch-Regal) kommen als kleine Content-Packs nach (Live-Ops, §10.2).

### 4.2 Warentransport: Auto, Garage, Kofferraum (User-Wunsch „Ware transportieren")

Der Einkauf beim Großmarkt wird **wirklich gefahren** — mit dem eigenen Auto aus dem
Autohaus/der Garage (`scripts/home/garage/`, `car_stats_logic`):

- **Bestellen → Fahren → Ausladen:** Bestell-Sheet abschicken, dann entweder selbst zur
  Großmarkt-Rampe fahren (Stadt-Fahrt wie gewohnt, Kofferraum-Klappe-zu-Animation) ODER
  den Lager-Gooby mit dem Lieferwägelchen schicken (§5). Die Fahrt läuft über das
  **`fahrer_sim.gd`-Zeitmodell**: Position = pure Funktion der Save-Timestamps über den
  `road_graph` — App zu, App auf, die Ware ist trotzdem exakt da, wo sie sein soll.
- **Kofferraum-Volumen ist die fühlbare Größe:** Kleines Auto = 12 Kisten, Kombi = 24,
  der (freischaltbare) **„Goo und Bye"-Lieferwagen mit Firmenlogo** = 48. Autos bekommen
  damit erstmals einen WIRTSCHAFTLICHEN Unterschied — rein logistisch, kein Pay-to-Win
  (jedes Auto schafft jede Bestellung, große schaffen sie in einer Fahrt).
- **Ausladen ist ein Mini-Ritual:** Kisten per Drag vom Kofferraum auf die Sackkarre,
  Lager-Gooby fängt sie (fast) immer. 10 Sekunden ASMR, kein Minispiel-Zwang
  („Alles ausladen"-Knopf existiert).

### 4.3 Lagerregeln (Planung ja, Strafe nein)

- **Kein Verderb, nirgends** (Nicht-Ziel §1.4): Trockenware lagert unbegrenzt.
- **Kühlware braucht Kühl-KAPAZITÄT statt Frische-Timer:** Milch, Käse, Eis können nur
  gelistet werden, wenn genug Kühlmodule stehen (Kapazitäts-Constraint = Planungsspiel
  ohne Verlustangst). Die Kühlkette ist ein GAG-Thema (§8.5), kein Fail-State.
- **Lagerraum wächst mit dem Ausbau** (L1: 40 Kisten → L5: 200). Überbestellt? Dann stapelt
  Regal-Gooby Stefan die Überschuss-Kisten im Hinterzimmer zu architektonisch fragwürdigen
  Türmen (§5) — rein visuell, nichts geht verloren.
- **Nachfüllen:** Regal-Slots ziehen automatisch aus dem Lager, wenn ein Regal-Gooby
  eingeteilt ist; sonst per Drag (mit Einräum-ASMR als Belohnung fürs Selbermachen).

### 4.4 Preis-Mechanik (die eine Kurve, §2.2) + Aktionen

Preis-Schieber ±30 % pro Warengruppe, „empfohlener Preis"-Knopf, Bio-Aufschlag +10 %,
Eigenmarke −20 %. Dazu **selbstgemachte Aktionen**: 1 Warengruppe pro Tag als „Tagesangebot"
markieren (−15 % Preis, +40 % Griff-Wahrscheinlichkeit) — der deterministische Zwilling von
McGoobys Tages-Special, hier aber vom SPIELER gewählt (Manager-Gefühl). Handgemalte
Angebots-Schilder wählt man aus 6 Gooby-Kritzel-Varianten.

### 4.5 Synergie-Matrix (Goo und Bye macht Bestehendes wertvoller)

1. **McGooby ↔ Goo und Bye (der Geschwister-Handschlag):** Besitzt man beide DLCs, kauft
   McGooby seine Zutaten automatisch bei Goo und Bye (statt REHWEI) — sichtbarer
   Warenkorb-Abholer jeden Morgen, +Umsatz für den Markt, −Einkaufskosten für den Imbiss
   (beide Boni klein & gedeckelt). Umgekehrt führt Goo und Bye das
   **„GoobyMac-Fertiggericht"** in der Tiefkühltruhe (Verpackungs-Parodie mit Ohren-Bögen).
   Kein Zwang: beide DLCs funktionieren vollständig solo.
2. **GOOBERANDO als Abhol- & Lieferkanal:** Ab Laden-Level 5 öffnet der **„Goo&Go"-Schalter**:
   GOOBERANDO-Bestellungen enthalten jetzt auch „Einkaufskorb von Goo und Bye" — der
   bestehende Fahrer (`fahrer_sim.gd`) holt sichtbar am Schalter ab und fährt zum Haus.
   Und die Krönung: **Gooby kann bei seinem eigenen Laden bestellen** (Radio-Durchsage:
   „Ein Herr Gooby bestellt… bei sich selbst. Mutig.").
3. **Garten & Ranch:** Bio-Regal (§4.1); Ranch-Besitzer liefern Milch/Äpfel vom Hof als
   „Vom Ranch-Stand"-Ecke (Cross-DLC-Regal mit Heu-Deko) — Milch gibt es sonst beim Großmarkt.
4. **Haus & Kühlschrank:** Gekaufte/entnommene Ware sind ECHTE Lebensmittel (identische
   IDs, §4.1) — der Laden ist die dritte Essens-Quelle neben REHWEI und Garten.
5. **Auto/Garage:** Kofferraum-Logistik (§4.2) gibt dem Fuhrpark erstmals einen Job.
6. **Level/Wirtschaft/Sticker:** XP über `leveling.gd`-Standard, Münz-Kreislauf über
   Quelle (Tagesgewinn) und Senken (Ausbau, Ware, Deko); Sticker-Set + Erfolge füttern
   die Sammel-Meta (§7.3, §7.4).

---

## 5) Mitarbeiter: das Team vom Schwarzen Brett

### 5.1 Die vier Angestellten (einstellbar per Aushang, wie McGooby §5.1 — andere Figuren, andere Jobs)

| Mitarbeiter | Job | Stats (je 1–5) | Gag-Vertrag |
|---|---|---|---|
| **Kassen-Gooby „Bipsi"** | Kasse | Tempo 4 · Sorgfalt 4 · Wachheit **1** | **Pennt zwischen zwei Kunden ein** (Kopf sackt aufs Band, Schnarch-Bläschen); das nächste Kassen-„Piep" weckt sie IMMER zuverlässig — sie scannt sogar im Halbschlaf fehlerfrei weiter. Kunden legen den ersten Artikel extra sanft aufs Band. |
| **Regal-Gooby „Stapel-Stefan"** | Nachfüllen | Tempo 3 · Sorgfalt 2 · Ehrgeiz 5 | Füllt Regale korrekt — aber ÜBERSCHUSS stapelt er zu **Dosen-Türmen** („Der Turm von Bohnabel"). Die Türme sind begehbare Sehenswürdigkeit (+Deko-Punkte!), bis ein Kunde die unterste Dose kauft. Domino-Event §8.2. |
| **Lager-Gooby „Loretta"** | Lager & Lieferfahrten | Tempo 2 · Sorgfalt 5 · Übermut 4 | Fährt das Lieferwägelchen im Laden wie einen Rennwagen (Slalom um Kunden, quietschende Kurven — nie ein Unfall, Sorgfalt 5!). Übernimmt Großmarkt-Fahrten, wenn der Spieler nicht selbst fahren will (§4.2). |
| **Berater-Gooby „Herr Freundlich"** | Kundenberatung | Tempo 1 · Sorgfalt 3 · Herzlichkeit 5 | Beantwortet JEDE Frage („Wo ist das Salz?") mit einer kompletten Führung inklusive Familiengeschichte des Salzes. Kunden kommen wegen ihm wieder (+Zufriedenheit), brauchen aber doppelt so lang. |

### 5.2 Mechanik: Aufgaben abgeben statt Personal verwalten

Ein eingeteilter Mitarbeiter **automatisiert seinen Job** mit Stat-abhängiger Qualität
(Bipsis Wachheit 1 = die Schlange stockt kurz beim Einnicken; Stefans Sorgfalt 2 = ab und
zu ein Turm). Stats wachsen langsam durch gemeinsame Arbeitstage (Bindungs-Gedanke der
Ranch — Beziehung statt Excel), Obergrenze 5, kein Grind-Loch. Der Spieler bleibt
Manager: einteilen, zuschauen, einspringen, grinsen.

### 5.3 Gehalt & Zufriedenheit (light, ohne Druck)

- **Gehalt:** fixer Tagesbetrag **20–40 Münzen** pro Mitarbeiter — fällig NUR an Tagen mit
  gespielter Session oder aktiver Offline-Kasse (kein schleichender Konto-Abfluss).
- **Zufriedenheit 0–100:** steigt durch Pausenraum-Deko (eigene Grid-Ecke!), gelegentliche
  Snacks vom eigenen Sortiment und Erfolgserlebnisse; sinkt NIE unter „gut gelaunt" —
  niedrige Zufriedenheit heißt nur: weniger Extra-Gags (Stefan baut keine Türme mehr —
  DAS wollen Spieler nicht!). Kein Streik, keine Kündigung (§1.4).
- **Pausentag-Knopf** pro Figur: Loretta schickt eine Postkarte von der Gouhbus-Endstation.
  Wer Pausentag hat, sitzt manchmal als Kunde im eigenen Laden (Welt-Detail).

---

## 6) Kunden-Sim: deterministisch, knuffig, lesbar

### 6.1 Der Tagesplan (Seed → Bon-Liste, golden-testbar)

Der Kundenstrom ist eine **pure Funktion** aus (Datums-Seed, Öffnungs-Uhrzeit via
Zeit-Injektion, Laden-Attraktivität §6.5, Sortiments-Breite, Preis-Faktoren): morgens wird
der komplette **Tagesplan** deterministisch erzeugt — welche Archetypen wann kommen, mit
welcher Einkaufsliste (1–8 Artikel, gewichtet nach gelistetem Sortiment). Gleicher Tag +
gleicher Laden = gleicher Plan → Offline-Kasse (§2.2), Freunde-Sync (§9.1) und QA-Golden-Tests
(§10.4) rechnen ALLE mit derselben Wahrheit. Stoßzeiten sind Dichte-Multiplikatoren auf der
Tageskurve (§2.2), keine Sonderlogik.

### 6.2 Routing = die GOOBERANDO-Fahrer-Sim, in den Laden geholt

Kundenbewegung nutzt exakt das **`fahrer_sim.gd`-Muster**: A*-Pfad über einen Graphen (hier:
begehbare Grid-Zellen statt Straßen), **Position als pure Funktion der Timestamps** — kein
NPC-Tick, kein RNG, kein Node-Zustand. Ein Kunde „ist" seine Einkaufsliste + Startzeit; wo
er gerade steht, wird on-the-fly berechnet (auch nach App-Neustart exakt gleich). Stationen:
Tür („Goo!") → Regale in Listen-Reihenfolge (Greif-Pause 2 s, Ware verschwindet sichtbar aus
dem Slot) → ggf. Sonderwunsch (§6.4) → Kassenschlange (FIFO) → Tür („Bye!"). Maximal 8
sichtbare Kunden, der Rest des Tagesplans läuft als reine Zahlen-Sim (§10.6-Performance).

### 6.3 Archetypen (Casting mit Gag-Vertrag — jede Figur braucht einen)

| Kunde | Verhalten | Gag |
|---|---|---|
| **Stammkunde Onkel Alwin** | täglich 9 Uhr, kauft GENAU 1 Möhre | prüft „seinen" alten Laden mit Kennerblick, poliert im Vorbeigehen ein Regal — +1 Deko-Punkt für den Tag |
| **Listen-Gooby** | strikte 6-Punkte-Liste, effizienteste Route | hakt Artikel mit einem RIESIGEN Bleistift ab; fehlt ein Artikel, macht er ein so trauriges Häkchen, dass man das Regal sofort nachfüllen will |
| **Schnäppchen-Oma Hoppel** | kommt NUR zu Aktionen & Rabatt-Samstag | riecht Rabatte drei Straßen gegen den Wind; zahlt in einzelnen Münzchen und erzählt dabei vom legendären „Ausverkauf von '89" |
| **Hamster-Gooby** | kauft IMMER eine ganze Warengruppe leer | trägt den Turm balancierend zur Kasse (Physik-Comedy); Bipsi scannt den Turm von unten nach oben — die längste Gebrabbel-Melodie des Spiels |
| **Chaos-Kleinkind + Eltern-Gooby** | wirft 3 zufällige Artikel in den Wagen | an der Kasse die große Verhandlung („Das legen wir zurüüück") — 1 Quengelware bleibt IMMER drin (§3.3) |
| **Feinschmecker von Monokel** | kauft nur Bio-Regal + Eigenmarken-SKEPSIS | probiert „Goo-Cola", hebt die Braue… und kauft heimlich 6 Stück (Cross-Gast aus McGooby: derselbe Kritiker, privat) |
| **Eiliger Pendler** | 18:55 Uhr, 3 Artikel, Blick auf die Uhr | rennt in Zeitlupe (Gooby-Physik); schafft er's vor 19 Uhr an die Kasse, applaudiert die Schlange |
| **Nachtschwärmer** (Mitternachts-Markt-Deko-Set) | letzte halbe Stunde | flüstert an der Kasse; Bipsi flüstert zurück; das Kassen-Piep flüstert AUCH (leisester Ton im Spiel) |

Alle Kunden sind prozedurale Goobys im `city_fussgaenger.gd`-Kostüm-Stil — keine neuen Rigs,
nur Requisiten (Einkaufswagen, Bollerwagen, Liste, Monokel).

### 6.4 Sonderwünsche & Beratung (die freundliche Interaktions-Schicht)

Pro Session haben 2–3 Kunden ein **„?"-Wölkchen**: „Wo finde ich Glitzersalz?" (hinführen
per Tap ODER Herrn Freundlich schicken), „Gibt es das auch in Bio?" (Umlisten-Anstoß),
„Können Sie Kartoffeln ordern?" (Sortiments-Wunsch → landet als Notiz am Schwarzen Brett —
der organische Sortiments-Ausbau-Kompass). Erfüllte Wünsche geben +Zufriedenheit und
gelegentlich ein Geschenk (Sticker-Tütchen, §7.4). Unerfüllte Wünsche verfallen folgenlos —
Wünsche sind Einladungen, keine Quests mit Strafe.

### 6.5 Zufriedenheit → Attraktivität (die eine sichtbare Kennzahl)

Statt fünf Balken gibt es EINE Zahl: **Laden-Attraktivität** (0–100) aus Sortiments-Breite,
Preisniveau, Deko-Punkten, Schlangen-Länge und erfüllten Wünschen — angezeigt als
**Blumenkasten vor dem Laden** (mehr Attraktivität = mehr Blüten; die Kinder-lesbare Metrik).
Attraktivität skaliert die Kundenzahl von morgen (Tagesplan-Input §6.1). Alles pure Logik
(`attraktivitaet_logic.gd`), Gewichte im Balance-Pack.

---

## 7) Progression

### 7.1 Laden-Level 1–5 (Zustands-Prüfung, kein Grind-Zähler)

| Level | Name | Anforderung (alle erfüllen) | Schaltet frei |
|---|---|---|---|
| 1 | **Alwins Erbe** (6×6) | Schlüsselübergabe-Kapitel abgeschlossen | 12 Regal-Slots, 1 Kasse, Lager 40 |
| 2 | **Minimarkt** (8×8) | 10 Waren gelistet + 400 Münzen Ausbau | Obst-Schrägen, Mitarbeiter-Slot 1 (Bipsi), Quengelware-Ständer |
| 3 | **Frischemarkt** (10×10) | Attraktivität ≥ 40 + 3 Sonderwünsche erfüllt + 900 Münzen | **Kühlzone** (Kühl-Warengruppen!), Slots 2+3, Bio-Regal |
| 4 | **Supermarkt** (12×12) | 25 Waren gelistet + 1 Rabatt-Samstag „gemeistert" (§8.4) + 1600 Münzen | Backecke (Duft-Radius = +Attraktivität), 2. Kasse, Slot 4, Pausenraum |
| 5 | **Goo und Bye XXL** (14×14) | Attraktivität ≥ 80 + Promi-Besuch bestanden (§8.3) + 2500 Münzen | „Goo&Go"-Schalter (§4.5), Lieferwagen freischaltbar, Schild-Ohren wackeln, Mitternachts-Deko-Set |

### 7.2 Freischalt-Gate (Vorschlag): **Level 12 + 2500 Münzen**

Begründung: Die Ranch liegt bei Level 15 + 2500, McGooby (Vorschlag) bei Level 14 + 3000.
Goo und Bye bei **Level 12** macht es zum **ersten Riesen-DLC-Moment** einer Spielerlaufbahn
und entzerrt die Kauf-Kette sauber (12 → 14 → 15, nie zwei Angebote gleichzeitig). Der Preis
bleibt bei **2500** (nicht höher), weil der Laden zwar eine Einkommens-Maschine ist, aber —
anders als McGooby — sein Startgeld sofort wieder in Ware binden muss (Warengutschein §2.2
federt das ab; die ersten Tage sind bewusst „klein, aber meins"). Beides liegt als
Balance-Daten im Pack (`content/gooundbye/data/balance.json`, deep-merge wie `content/ranch/`)
— per Auto-Update nachjustierbar; `ranch_offer.gd`/`ranch_kauf.gd` sind die Code-Vorlage für
`gooundbye_offer.gd`/`gooundbye_kauf.gd`. Der DLC-Hub (W14) führt `goo_und_bye` bereits als
`kommt_bald`-Eintrag mit Coverart — beim Release stellt ein Pack-Update den Status auf
`verfuegbar` und füllt die `route` (exakt der vorgesehene Mechanismus).

### 7.3 Erfolge (Achievements-Pack, `achievements.counters`-Mechanik)

`ersterPiep` (erster Bon) · `melodieMeister` (Kassen-Combo ×2,0 erreicht) ·
`turmVonBohnabel` (10 Stefan-Türme bestaunt) · `bioPionier` (30 Garten-Waren verkauft) ·
`hamsterFreund` (5 Hamster-Käufe komplett bedient) · `kraehenFluesterer` (10 Krähen-Überfälle
abgewehrt) · `rabattSamstagHeld` (Rabatt-Samstag mit Attraktivität ≥ 60 beendet) ·
`vollsortimenter` (40 Waren gleichzeitig gelistet) · `xxlEroeffnung` (Laden-Level 5) ·
`treuesteMoehre` (Alwin 30× bedient).

### 7.4 Sticker-Set „gooundbye" (6 Motive, `content/stickers/`-Format wie Set `kueche`/`ranch`)

1. **„Die Schlüsselübergabe"** — Onkel Alwin drückt Gooby einen Schlüssel in die Pfote, der
   größer ist als Goobys Kopf; im Hintergrund der staubige Laden mit einem einzelnen
   Sonnenstrahl aufs leere Möhrenregal. (Eröffnungs-Kapitel)
2. **„Der erste Piep"** — Bipsi und Gooby beugen sich ehrfürchtig über die Kasse, aus der
   eine einzelne goldene Noten-Blase aufsteigt; der allererste Bon hängt gerahmt daneben.
   (Counter `ersterPiep`)
3. **„Der Turm von Bohnabel"** — Stefans Dosenturm bis zur Decke, Stefan salutiert stolz
   davor, ganz unten zieht eine winzige Kunden-Pfote GENAU die unterste Dose heraus.
   (Counter `turmVonBohnabel`)
4. **„Krähen-Razzia"** — drei Krähen im Anflug auf die Obst-Schräge, eine trägt schon eine
   Erdbeere wie einen Rucksack; Gooby rudert mit einem Besen, alle lachen. (Counter
   `kraehenFluesterer`)
5. **„Rabatt-Samstag"** — die Schlange VOR Ladenöffnung: Oma Hoppel campiert mit Klappstuhl
   und Thermoskanne an erster Stelle, hinter ihr wippen zwölf Paar Ohren. **Rarität: geheim.**
   (Counter `rabattSamstagHeld`)
6. **„XXL bei Nacht"** — der fertige „Goo und Bye XXL" nachts: Schild leuchtet, die
   Apostroph-Ohren wackeln, im Schaufenster schläft Bipsi an ihrer geliebten Kasse.
   (Laden-Level 5)

---

## 8) Events & Gags (Random-Event-Engine, Kontext `gooundbye`)

Andocken am Kontext-Tor von `scripts/events/random_events.gd` (wie Ranch/McGooby); alle
Events sind Zeitfenster-Gags mit witzigem Fail-Text, NIE Strafen:

1. **Krähen-Ladendiebe 🐦** — 3 Krähen landen auf der Obst-Schräge (dieselbe Bande, die
   Gärten und McGoobys Drive-In heimsucht — ein stadtweiter Running-Gag). Tap-Abwehr binnen
   15 s: Gooby wedelt mit dem Besen, Krähen flattern theatralisch ab. Verpasst: Die Krähen
   bezahlen NICHT, posieren aber für die POW!-Kamera mit Beute (Foto-Aufforderung) — Verlust:
   3 Obst-Einheiten, Gegenwert ~5 Münzen, Gegenwert an Comedy: unbezahlbar.
2. **Regal-Domino 📦** — Stefans neuester Turm gerät ins Wanken (Ankündigungs-Wackeln + Ton):
   Tap stabilisiert ihn (Stefan: „Statik!"). Verpasst: Dosen-Domino durch den Gang in
   Zeitlupe, Kunden weichen im Ballett-Stil aus, ein Kind applaudiert. Aufräumen = 3 Drags,
   +1 Anekdote fürs Schwarze Brett. Nichts geht kaputt (Dosen!).
3. **Promi-Gooby incognito 🕶️** — ein Gooby mit Sonnenbrille, Schlapphut und offensichtlich
   falschem Schnurrbart kauft „ganz normale Dinge, wie normale Leute". Bedient man ihn
   unaufgeregt (NICHT ansprechen — die Kinder-Version von Understatement), signiert er an
   der Kasse heimlich ein Poster → hängt danach gerahmt im Laden (+5 Attraktivität dauerhaft).
   Wer ihn enttarnt (Tap auf den Schnurrbart), bekommt stattdessen den GAG: Perücke rutscht,
   darunter… noch eine Sonnenbrille. Er kommt trotzdem wieder.
4. **Rabatt-Samstag 🏷️** — jeden Samstag (deterministisch, Gerätezeit): Kundenzahl ×1,8,
   alle Preise −15 %, Oma Hoppel campiert ab 7:45 Uhr vor der Tür. „Gemeistert" (für §7.1):
   Attraktivität hält ≥ 60 bis Ladenschluss — sprich: Regale nachgefüllt, Schlangen kurz.
   Der wuseligste, lukrativste und lauteste Tag der Woche (Gebrabbel-Melodien im Dauerkanon).
5. **Die große Eis-Schmelze 🍦** — die Tiefkühltruhe steht einen Spalt offen (wer war's?
   Schnitt auf pfeifendes Chaos-Kleinkind). 20-s-Deckel-zu-Moment. Verpasst: Das Eis wird
   zu „Milchshake-Art" — und wenn McGooby installiert ist, kauft Shake-Gooby Salvatore den
   gesamten Bestand ZUM VOLLEN PREIS auf („Für meine Kunst."). Ohne McGooby: Sonderangebot
   „Trink-Eis", Kunden finden's super. Es gibt keine Verlierer, nur Anekdoten.

---

## 9) Multiplayer (offline-first, GOOBY-SERVER-Bestand)

### 9.1 Freunde kaufen ECHT ein (der stärkste Zeig-Moment)

Besucht ein Freund den Laden (Besuchssystem visits/rooms), ist er **zahlender Kunde**:
Er läuft selbst durch MEIN Layout, legt echte Waren in den Korb und bezahlt mit SEINEN
Münzen — ich bekomme den Umsatz, er die Ware (echte Lebensmittel-IDs, §4.1 — der Einkauf
landet in seinem Kühlschrank!). Server-seitig ist das ein idempotenter Bon (Quittungs-Event
über die generischen `mg:`-Räume, Host-Autorität, offline-Queue mit Sync bei Gelegenheit).
Anti-Inflations-Deckel: max. **200 Münzen Freunde-Umsatz pro Tag** pro Laden. Der Besucher
hinterlässt einen Gästebuch-Bon („War da. Hab Möhren gekauft. 10/10.") — Ranch-F3-Muster.

### 9.2 Wochenumsatz-Bestenliste (nur Freunde)

Pro Woche (Mo–So, deterministischer Wochen-Seed) zählt der Gesamtumsatz; das Board am
Schwarzen Brett zeigt NUR Freunde + die eigene Bestwoche (Ranch-F5-Regel: kein globales
Board, kein Abstieg). Async & offline-first: Scores syncen, wann immer online; offline zeigt
der Aushang die lokale Marke mit freundlichem Chip. BEWUSST Umsatz statt Gewinn: Umsatz ist
die freundliche Zahl (wachsen alle), Gewinn bleibt Privatsache des Managers.

### 9.3 Lieferpartnerschaft (async, kein Koop-Zwang)

Zwei Befreundete Läden können eine **Lieferpartnerschaft** schließen: Wem eine Ware ausgeht,
dessen Laden bestellt automatisch beim Partner-Überschuss (asynchron: Bestellung als
Server-Nachricht, Lieferung beim nächsten Login des Partners via GOOBERANDO-Fahrer-Kulisse,
beide sehen die Fahrt). Kleiner Freundschafts-Bonus (+5 % auf Partner-Lieferungen), harte
Deckel gegen Schieberei (max. 20 Kisten/Woche). KEIN synchroner Koop-Modus — das ist bewusst
McGoobys Revier (Koop-Rush, §1.5); Goo und Bye multiplayer't asynchron und gemütlich.

---

## 10) Technik-Blaupause

### 10.1 Save-Slice `gooundbye` (additiv, `ranch_play_slices.gd`-Muster)

```
gooundbye: {
  besitz: { gekauft, kaufAt },                     // Gate-Kauf, atomar wie ranch_kauf
  laden: { level, attraktivitaet, grid, kuehlKapazitaet, kassen, schildUntertitel },
  sortiment: { gelistet: [warenId…], preise: {gruppeId: faktor}, tagesangebot },
  lager: { warenId: menge },                       // ohne Verfall (§4.3)
  transport: { unterwegs: {bestelltAt, ankunftAt, warenkorb, fahrerTyp} },  // fahrer_sim-Zeitmodell
  team: { mitarbeiterId: {stats, schicht, zufriedenheit, pausentag} },
  umsatz: { heute, wocheSeed, wocheSumme, bestWoche, boegen: n },
  kasse: { offlineStandAt },                       // Offline-Kasse-Timestamp (Zeit-Injektion)
  wuensche: { offen: [wunsch…], erfuellt: n }      // Schwarzes Brett (§6.4)
}
```

Additive Unterschlüssel mit normalize-Self-Heal, NIE Version-Bump (Ranch-I6-Regel). Alle
Zeitlogik (Tagesplan, Offline-Kasse, Transport-Fahrten, Rabatt-Samstag) läuft über die
injizierte Uhr — golden-value-testbar wie `fahrer_sim.gd`.

### 10.2 Pack-Struktur `content/gooundbye/` (Schema 1, Vorbild `content/ranch/pack.json`)

```
content/gooundbye/
  pack.json          // { id: "gooundbye", domains: ["gooundbye", "balance"], min_native, priority }
  data/
    sortiment.json   // Warengruppen + Waren (IDs aus rehwei_sortiment übernommen!), EK/VK-Richtwerte,
                     //   bio-Flags, Eigenmarken-Varianten, Regal-Typ-Zuordnung
    regale.json      // Grid-Katalog: Regale/Kühlmodule/Kassen/Deko/Spezial (§3.2) mit Footprints
    kunden.json      // Archetypen, Einkaufslisten-Gewichte, Tageskurven, Sprüche-Keys
    team.json        // 4 Mitarbeiter: Stats, Job-Zuordnung, Gag-Dialog-Keys
    ausbau.json      // Laden-Level 1–5: Flächen, Kosten, Freischaltungen
    balance.json     // Gate (Level 12 / 2500), Margen, Deckel (Offline, Freunde-Umsatz), deep-merge
```

Dazu: `content/stickers/` +6 Einträge (Set `gooundbye`, Pack-Version-Bump), `content/achievements/`
+10 Counter-Erfolge, `strings/de+en/gooundbye.json` (DE↔EN-Paritäts-Test! EXPECTED_DOMAINS-Eintrag
beim INTEGRATE-Pass anmelden — W13-Lernkurve), `scripts/home/data/garden_crops.json` +3 Crops
(radieschen, aubergine, kartoffel), sowie beim Release ein `content/dlc/`-Update
(`goo_und_bye`: status → `verfuegbar`, route → Angebots-Flow, §7.2).

### 10.3 Wiederverwendung (nichts doppelt bauen — die Goo-und-Bye-Einkaufsliste)

| Bestand | Rolle im DLC |
|---|---|
| Grid-Baumodus (`home/build_mode/`, `grid_data.gd`) | Verkaufsraum + Lager + Pausenraum; NEU nur die Pfad-Validierung (pure Funktion auf GridData) |
| `fahrer_sim.gd`-Zeitmodell (Position = f(Timestamps)) | **ZWEIFACH**: Kunden-Routing im Laden (§6.2, Grid-Graph statt road_graph) + Warentransport-Fahrten (§4.2) |
| `rehwei_sortiment.json` + `food_catalog.gd` | Basis-Sortiment mit identischen Lebensmittel-IDs — gekaufte Ware ist echtes Essen (§4.1) |
| `scripts/city/orte/`-Muster (`goobyman.gd`) + `city_map` | Laden als Stadt-Ort mit Fassade + Großmarkt-Rampe hinter REHWEI (Zentrums-Tiles knapp — Kulisse-Tests mitziehen) |
| Dialog-System (`dialog_runner/view/typewriter.gd`) | Alwin-Kapitel, Kunden-Sprüche, Marktradio-Durchsagen, Sonderwünsche |
| `ranch_offer/kauf.gd` | Kauf-Gate-Flow 1:1 als `gooundbye_offer/kauf.gd`; DLC-Hub-Eintrag existiert schon (`content/dlc/data/dlcs.json`) |
| `ranch_offline.gd`-Zeitmuster | Offline-Kasse (30 % Rate, 8-h-Deckel) |
| `random_events.gd` (Kontext-Tor) + NotifyScheduler | §8-Events; sanfte Grüße („Der Laden hat gesummt", max 2/Tag, opt-in) |
| Garten (`garden_crops/growth/state.gd`) | Bio-Quelle + 3 neue Crops; Ernte→Regal-Übergabe |
| Garage/Auto (`home/garage/`, `car_stats_logic`, `city_verkehr`) | Kofferraum-Logistik, Lieferwagen, Großmarkt-Fahrten |
| GOOBERANDO (`delivery/restaurants.gd`, Fahrer) | Notlieferung, „Goo&Go"-Abholungen, Lieferpartnerschafts-Kulisse |
| GOOBY-SERVER `rooms.js` (`mg:`) + visits | Echt-Einkauf der Freunde (idempotente Bons), Wochen-Board, Partnerschaft |
| POW!-Fotomodus + Sticker-Registry + `leveling.gd`/`economy.gd` | Foto-Momente (Türme! Krähen!), Set, XP/Münzen |
| `MusicDirector` + JuiceKit | Marktradio, Jingle, Gebrabbel-Melodie-Samples, Einräum-ASMR-Pooling |

### 10.4 Test-Strategie

Der deterministische Tagesplan (§6.1) ist der QA-Jackpot: **Seed → erwartete Kundenliste →
erwartete Bon-Summe** als Golden-Tests (Muster `fahrer_sim`-Golden-Values). Pure Module mit
Unit-Tests: `tagesplan_logic.gd`, `preis_logic.gd`, `attraktivitaet_logic.gd`,
`lager_logic.gd`, `pfad_validierung.gd` (Grid-Fixtures: blockierte Layouts MÜSSEN abgelehnt
werden), `offline_kasse.gd` (Zeitsprung-Fälle). Kassen-Combo bot-zertifizierbar
(`simulate_autoplay` im Minigame-Framework-Stil). Multiplayer: Bon-Idempotenz-Test (doppelt
gesendete Quittung = ein Umsatz) + Offline-Queue-Replay. Sync-Tests Sortiment↔Strings↔Sticker
nach dem Muster `test_rehwei_buecher_kategorie_synchron`; DE↔EN-Parität für `gooundbye.json`.

### 10.5 Wellen-Schnitt (jede Welle shippable, Datei-Schätzungen)

- **W-A „Die Schlüsselübergabe" (Fundament, ~22–26 Dateien):** Ort + Kauf-Gate
  (`scripts/city/orte/gooundbye.gd` + `.tscn`, `gooundbye_offer/kauf.gd`, city_map-Eintrag +
  Kulisse-Test), Save-Slice (`scripts/gooundbye/gooundbye_state.gd` + `gooundbye_slices.gd`),
  Grid-Verkaufsraum mit Regal-Katalog + Pfad-Validierung (`pfad_validierung.gd`), Sortiment +
  Preis-Schieber (`sortiment_logic.gd`, `preis_logic.gd`, Bestell-Sheet), Kunden-Sim v1
  (Tagesplan + Routing + 3 Archetypen: `tagesplan_logic.gd`, `kunden_routing.gd`), Kasse +
  Gebrabbel-Melodie + Tagesabschluss (`kasse_logic.gd`, `kassensturz_sheet.gd`), Pack
  `content/gooundbye/` (sortiment, regale, balance), `strings/de+en/gooundbye.json`,
  Alwin-Kapitel (Dialog-Defs), ~7 Unit-Test-Dateien.
  → Spielbar: kaufen, bauen, listen, verkaufen, verdienen.
- **W-B „Vollsortiment" (Tiefe, ~18–22 Dateien):** 4 Mitarbeiter + Schichtplan
  (`team_logic.gd`, `team_sheet.gd`, team.json), Archetypen komplett + Sonderwünsche +
  Stoßzeiten (kunden.json, `wuensche_logic.gd`), Warentransport mit Auto/Garage
  (`transport_logic.gd` auf fahrer_sim-Zeitmodell, Großmarkt-Rampe), Garten-Bio-Regal +
  3 neue Crops (+ Visuals), Ausbau L3–L5 inkl. Kühlzone/Backecke (ausbau.json,
  `attraktivitaet_logic.gd`), Events ×5 (random_events-Defs, Kontext `gooundbye`),
  Offline-Kasse (`offline_kasse.gd`), Sticker-Set + Erfolge, Schild-Editor.
  → Spielbar: das volle Solo-DLC.
- **W-C „Große Eröffnungswoche" (MP + Endgame, ~12–15 Dateien + Server):** Echt-Einkauf der
  Freunde (Server-Bon-Handler in `GOOBY-SERVER/src/` nach `ranchmp.js`/visits-Muster + Client
  `gooundbye/besuch_einkauf.gd` + Idempotenz-Tests), Wochenumsatz-Board (Server-Scores +
  Aushang-UI), Lieferpartnerschaft (async Messages), „Goo&Go" + GOOBERANDO-Integration,
  Promi-Event + Rabatt-Samstag-Meisterung, McGooby-Cross-Content (Zutaten-Abholer +
  GoobyMac-Tiefkühlgericht, nur wenn beide installiert), XXL-Zeremonie, DLC-Hub-Statuswechsel.
  → Spielbar: alles aus §9 + Endgame.

### 10.6 Risiken (ehrlich) & Gegenmittel

1. **Kunden-Sim-Performance (DAS Hauptrisiko):** 8 sichtbare Kunden mit A*-Routing + Regale
   + Partikel auf iPhone. Gegenmittel: Kunden-Positionen sind BERECHNET statt getickt
   (fahrer_sim-Prinzip — pro Frame nur f(t) für 8 Agenten), Regale/Waren als MultiMesh,
   Rest des Tagesplans reine Zahlen-Sim, Draw-Call-Budget ≤ 400 als headless CI-Pflicht
   ab W-A (Ranch-I5-Muster).
2. **Management-Überforderung vs. cozy:** Sortiment+Preise+Personal+Logistik kann erschlagen.
   Gegenmittel: „Einfach führen"-Defaults ab W-A (§2.5), Systeme schalten sich GESTAFFELT
   frei (L1: nur listen & verkaufen; Kühlware erst L3; Personal ab L2), jede Mechanik hat
   einen „mach's für mich"-Knopf.
3. **Münz-Inflation:** Ein Dauereinkommen mehr im Spiel. Gegenmittel: Tagesgewinn-Deckel
   (§2.2), Offline-Kasse 30 %/8 h, Freunde-Umsatz-Deckel 200/Tag, große Senken (Ausbau
   400–2500, Ware bindet Kapital im Umlauf), ALLE Stellschrauben im Balance-Pack →
   live nachsteuerbar ohne Release.
4. **Grid-Pathing-Kanten:** Umbau während Kunden im Laden sind; Regale, die Wege sperren.
   Gegenmittel: Pfad-Validierung VOR Platzierung (pure, getestet), Umbau teleportiert
   aktive Sim-Kunden sanft zum nächsten gültigen Wegpunkt (unsichtbar, da Positionen
   berechnet sind), Fixture-Tests mit fiesen Layouts.
5. **MP-Echt-Einkauf-Konsistenz:** Doppel-Bons, Offline-Konflikte. Gegenmittel:
   idempotente Quittungs-IDs, Host-Autorität über Lagerbestand, Deckel begrenzt den
   Schaden jedes Fehlerfalls auf Kleingeld; Fallback „Besuch ohne Kauf" wenn Server nicht
   erreichbar (rein lokale Besichtigung).
6. **Dopplungs-Gefahr mit McGooby:** Zwei Laden-DLCs könnten sich gleich anfühlen.
   Gegenmittel: Abgrenzungs-Vertrag §1.5 als Review-Checkliste pro Feature vor Merge
   („Ist das Geschick? → gehört zu McGooby. Ist das Logistik/Layout? → gehört hierher"),
   Synergien statt Überschneidungen (§4.5).

---

## 11) Anti-Spoiler-Teaser + DLC-Hub-Stichpunkte

**Teaser (2 Sätze):** Onkel Alwin hängt seine Schürze an den Nagel — und drückt Gooby einen
Schlüssel in die Pfote, der größer ist als sein Kopf. Was aus dem leeren Eckladen mit dem
lustigen Namen wird, entscheidest du: Regal für Regal, Möhre für Möhre, Piep für Piep.

**4 Feature-Stichpunkte für den DLC-Hub:**

- Dein eigener Supermarkt: Regale stellen, Sortiment listen, Preise machen — das Layout ist das Spielbrett
- Ware wirklich transportieren: mit dem eigenen Auto zum Großmarkt, mit dem Garten als Bio-Quelle
- Vier knuffige Mitarbeiter mit Eigenleben — von der einnickenden Kassiererin bis zum Dosenturm-Architekten
- Freunde kaufen ECHT bei dir ein, und die Kasse piept deine ganz eigene Gebrabbel-Melodie

(Identischer Inhalt zusätzlich per Anhang an `/tmp/gooby-godot/handoffs/W13-requests.md`,
Tag IDEEN-GOOBYE, für den DLC-Hub-Owner. Hinweis: `content/dlc/data/dlcs.json` führt
`goo_und_bye` bereits mit Platzhalter-Teaser — dieser §11 ist die abgestimmte Basis für
das Release-Update.)

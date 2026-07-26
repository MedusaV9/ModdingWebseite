# RANCH-DLC-IDEAS-1 — Ideen-Agent 1 (Fable): Recherche + Ideensammlung für das Gooby-Ranch-DLC

Auftrag: Aus der **Gooby Ranch** (heute: kaufbarer Ort mit Pferden, Pflege, Reiten und
2 Minispielen) ein **vollwertiges Pferdespiel im GOOBY-Universum** machen — Star-Stable-Klasse,
aber als kuscheliges, deutschsprachiges, offline-first Wohlfühlspiel ohne Druck und ohne
Bezahl-Frust. Dieses Dokument liefert: (§1) Bestandsaufnahme, (§2) Recherche zu echten
Pferdespielen mit Quellen, (§3) 60+ konkrete Feature-Ideen, (§4) priorisierte Bau-Reihenfolge,
(§5) 10 bewusste Nicht-Ziele. Aufwand nur als **S/M/L** (Umfang/Risiko/betroffene Systeme),
niemals Kalenderzeit.

---

## 1) Bestand: Was existiert schon — ausbauen statt neu bauen

Die erste Ranch-Fassung (RANCH-1/RANCH-2) steht unter `GOOBY-GODOT/scripts/ranch/**`
(~5 600 LOC + Tests + Content-Pack `content/ranch/`). Das ist ein **echtes Fundament**,
kein Prototyp — fast alles Folgende ist ERWEITERUNG bestehender Dateien:

| Bestand (Datei) | Was es heute kann | DLC-Verhältnis |
|---|---|---|
| `ranch_state.gd` + `data/ranch_play_slices.gd` | Save-Slice `ranch` (Kauf, Ausbau, Pferde, Wirtschaft, Spiele), additiv ohne Version-Bump | **AUSBAUEN** — neue Unterschlüssel (`quests`, `npcs`, `wetter`, `zucht`) im selben Muster andocken |
| `ranch_offer.gd` / `ranch_kauf.gd` | Kauf-Angebot ab Level 20 (2500 ᴳ), atomarer Kauf inkl. Start-Tieren | **FERTIG** — DLC-Einstieg existiert, nur Preis/Level per Balance-Pack pflegen |
| `ranch_welt.gd` / `ranch_bau.gd` | Deterministische Welt-Pläne (480×380 m), MultiMesh-Kulisse ≤ 400 Draw-Calls, Tag/Nacht via CityAmbiente | **AUSBAUEN** — neue Zonen als zusätzliche Plan-Abschnitte, NICHT neu erfinden |
| `ranch_fahrt_scene.gd` | Echte Überlandfahrt Stadt→Ranch mit Tor + Kauf-Sheet | **FERTIG**, später Rückweg-Varianten/Wetter drauflegen |
| `ranch_pferd.gd` / `gameplay/horse_stub.gd` | Prozedurales GOOBY-Pferd, Gangarten Idle/Trab/Galopp, Farb-/Gear-Vertrag | **AUSBAUEN** — Fohlen-Skalierung, neue Fellmuster, Trick-Animationen auf denselben Vertrag |
| `gameplay/horse_care.gd` + `pflege_screen.gd` | Hunger/Durst/Sauberkeit, abgeleitete Laune, Bindung 0–100 mit Tagesdeckel, Stall-Ausmisten | **AUSBAUEN** — Bindung wird die Basis des Pferde-LEVELS (§3.A1); Screen bekommt neue Aktionen |
| `gameplay/ride_controller.gd` + `ride_feel.gd` | Reiten als sanftes Fahrzeug: 3 Gangarten, Sprünge, Ausdauer, Verfolgerkamera, Staub/Hufschlag | **AUSBAUEN** — Sprung-Timing-Wertung, Tricks, Pfeifen-Rückruf oben drauf |
| `data/ranch_wirtschaft.gd` + `wirtschaft.json` | Heu/Äpfel/Bäume, Ausbau (Boxen 2/3, Reitplatz, Weidezaun), Gear-Shop 3 Slots × 5 Farben, alles Pack-updatebar | **AUSBAUEN** — mehr Waren, Läden, Sets; Preise bleiben DATEN |
| `gameplay/ranch_offline.gd` | Offline-Verfall gedeckelt (0.3×, max 8 h Sim), Tagesrhythmus Stall/Weide | **FERTIG** als Muster — Fohlen-/Feld-Timer benutzen dieselbe Zeitinjektion |
| `minigames/games/ranch_parcours/` + `ranch_herde/` + `ranch_level_select.gd` | 2 Minispiele à 10 Level mit Sternen, Bot-zertifiziert | **AUSBAUEN** — Vorlage für jedes neue Ranch-Minispiel |
| `ranch_tiere.gd` | Kuh/Schaf/Huhn prozedural mit Idle-Verhalten | **AUSBAUEN** — Wildtiere + Sozialverhalten im selben Stil |
| `content/ranch/` Pack + `RanchKatalog` | Preis, Freischalt-Level, Tiere, Weltdaten per Auto-Update nachlieferbar | **FERTIG** als Mechanik — das DLC ist die Blaupause für Content-Updates (Doc B §4.2) |

Außerdem wiederverwendbar aus dem Hauptspiel: Grid-Baumodus (`home/grid_data.gd`,
Doc D), Event-Scheduler (`events/`), Sticker-Registry, Minigame-Framework + JuiceKit
(W2d), GOOBY-SERVER (Freunde/Presence/Visits/Rooms, W2c/W3c), NotifyScheduler +
Taxi-Warte-Statemaschine (W3a), Dialog-System (Backlog E §2.2), Wetter-Port
(Backlog A M2), IGohbie-Handy (Backlog E §60). **Nichts davon doppelt bauen.**

---

## 2) Recherche: Was echte Pferdespiele gut machen — und woran sie scheitern

### 2.1 Recherche-Tabelle (Spiel → gute Mechanik → warum sie funktioniert → passt zu GOOBY?)

| Spiel | Gute Mechanik | Warum sie funktioniert | Passt zu GOOBY? |
|---|---|---|---|
| **Star Stable Online** | Story-Questreihe (300+ h Erzählbogen) statt loser Aufgaben | Spielerinnen bleiben für die GESCHICHTE, nicht für den Grind ([PocketGamer.biz](https://www.pocketgamer.biz/rise-star-stable-online/), [Engadget](https://www.engadget.com/2013-11-10-rise-and-shiny-revisit-star-stable.html)) | ✅ JA — als knuffige Kapitel-Questreihe „Die Ranch erwacht“ |
| Star Stable Online | **Wöchentliche Content-Updates seit 2011** — der wichtigste Retention-Hebel laut CEO ([PocketGamer.biz](https://www.pocketgamer.biz/rise-star-stable-online/)) | Es gibt IMMER etwas Neues; das Spiel fühlt sich lebendig an | ✅ JA — unser Content-Pack-System ist GENAU dafür gebaut; Rhythmus: „Ranch-Post“-Packs |
| Star Stable Online | Pferde-Leveln über tägliche Rennen & Hof-Aufgaben („chores“); Horse-Progression-Update rahmt Level als **Bindung** mit Skill-Freischaltungen (z. B. Pfeifen-Rückruf) ([SSO-Blog](https://www.starstable.com/en/blog/may-horseprogression-2023), [SSO-Hilfe](https://help.starstable.com/hc/en-us/articles/360001357300-How-do-I-level-up-my-horse)) | Bindung als Level ist emotional („wir zwei werden ein Team“) statt abstrakt | ✅ JA — unsere `bindung` (0–100) wird zur Level-Kurve mit Freischaltungen |
| Star Stable Online | Clubs (max. 50, Kalender, Rollen) als soziales Zuhause ([SSO-Wiki](https://starstable.wiki.gg/wiki/Clubs)) | Zugehörigkeit bindet stärker als jede Mechanik | ⚠️ TEILWEISE — als leichte „Reitgruppe“ unter Freunden, ohne Verwaltungs-Bürokratie und ohne offenen Chat |
| Star Stable Online (NEGATIV) | Star Coins nur für Echtgeld, ~100/Woche Almosen, Magic-Horse-FOMO-Rotationen, Star-Rider-Abo ab Level 5 quasi Pflicht ([SSO-Forum 1](https://ssoforums.freeforums.net/thread/2321/star-stable), [SSO-Forum 2](https://ssoforums.freeforums.net/thread/5161/problem-sso-currency), [Ginny O. Review](https://ginny0.wordpress.com/2018/06/26/tuesdaythoughts-parents-and-players-dont-play-star-stable/), [Screenwise](https://screenwiseapp.com/media/star-stable-online-app)) | DER meistgehasste Aspekt des Genres: „Ich habe das Spiel GEKAUFT und muss trotzdem zahlen“ | ❌ NEIN — eine Währung (Gold), alles erspielbar, nichts rotiert weg |
| Star Stable Online (NEGATIV) | Unmoderierter Welt-Chat = Mobbing/Sicherheitsrisiko für Kinder ([Screenwise](https://screenwiseapp.com/media/star-stable-online-app)) | Offene Chats skalieren nicht sicher | ❌ NEIN — nur Freunde, Emotes + kuratierte Textbausteine (wie Besuchs-Emote-Bar) |
| **Star Stable Horses (App)** | Fohlen-Aufzucht-Loop: tägliche Pflege-Aufgaben, Fohlen wächst sichtbar bis Level 10, dann „Umzug“ ins Hauptspiel; Garten für Leckerlis; Koppel-Spielen der Pferde ([App Store](https://apps.apple.com/us/app/star-stable-horses/id1126342383)) | Wachstum, auf das man WARTET, erzeugt echte Zuneigung; kurze tägliche Rituale | ✅ JA — Fohlen-Aufzucht als Warte-Quest mit Live-Activity/Notification, GOOBY-Stil |
| **Rival Stars Horse Racing** | „Immer ein nächstes Ziel“: Goals-Liste, Anlagen-Upgrades = passives Einkommen, Training frisst Items+Gold, Rennen geben XP+Skillpunkte ([Gaming Debugged](https://www.gamingdebugged.com/2026/05/17/review-rival-stars-horse-racing-xbox/), [PS4Blog](https://www.ps4blog.net/2026/04/playstation-5-rival-stars-horse-racing-review/)) | Mehrere ineinandergreifende Progressionsachsen — es gibt nie „nichts zu tun“ | ✅ JA — Ausbau ↔ Pferde-Level ↔ Turniere ↔ Quests verzahnen |
| Rival Stars Horse Racing | **Free Roam ohne Druck**: UI blendet sich aus, Foto-Kamera mit Zeitlupe, schöne Orte nur zum Dasein ([Gaming Debugged](https://www.gamingdebugged.com/2026/05/17/review-rival-stars-horse-racing-xbox/), [RSHR-Blog](https://www.rivalstarshorseracing.com/post/mobile-update-1-58-the-mustang-and-canyon-falls)) | Cozy-Spieler wollen VERWEILEN, nicht nur optimieren | ✅ JA — Kern-DNA von GOOBY; Foto-Spots + UI-Ausblenden übernehmen |
| Rival Stars Horse Racing | „Perfekt!“-Callout beim Sprung-Timing, Stangen fallen bei Fehlern ([RSHR-Blog](https://www.rivalstarshorseracing.com/post/mobile-update-1-58-the-mustang-and-canyon-falls)) | Winziges Feedback macht jeden Sprung zur Mikro-Belohnung | ✅ JA — direkt in Parcours + freies Reiten (JuiceKit) |
| Rival Stars Horse Racing | Zucht mit Grades 1–10 als Kern-Progression ([TMQ-Datenbank](https://horsegamedatabase.miraheze.org/wiki/Rival_Stars_Horse_Racing)) | Langfristziel über Generationen | ⚠️ TEILWEISE — Zucht ja, aber ohne Grade-Casino: Wunsch-Fohlen statt RNG-Frust |
| **Alicia Online** | Rennen fühlen sich SCHNELL und präzise an (Drift/„Sliding“, Boost, Doppelsprung); Strecken mit Abkürzungen, die man lernt ([The Mane Quest](https://www.themanequest.com/blog/2018/10/2/alicia-online), [TMQ-Datenbank](https://horsegamedatabase.miraheze.org/wiki/Alicia_Online)) | Game-Feel schlägt Realismus — deshalb lieben Fans es bis heute | ✅ JA — unser `ride_feel` ist schon „sanftes Fahrzeug“; Rennmodus darf arcadiger sein als die Sim-Konkurrenz |
| Alicia Online (NEGATIV) | Außer Rennen gibt es fast nichts; XP-Gewinn zäh ([The Mane Quest](https://www.themanequest.com/blog/2018/10/2/alicia-online)) | Monokultur ermüdet | ❌ Lehre: Ranch braucht VIELE kleine Loops, nicht einen großen |
| **Equestrian the Game** | Trail-Ride = Training: unterwegs Ziele erfüllen (Gangart halten, n Sprünge) → Stat-Gewinn ([TMQ-Datenbank](https://horsegamedatabase.miraheze.org/wiki/Equestrian_the_Game)) | Training fühlt sich wie Spielen an, nicht wie Menü-Klicken | ✅ JA — Ausritt-Aufgaben („bleib 20 s im Galopp“) füttern Pferde-XP |
| Equestrian the Game (NEGATIV) | Energie-System + Booster hinter Premium-Währung; 5–10 € für EIN Pixel-Shirt ([Medium-Review](https://medium.com/@quest.equestrians/review-equestrian-the-game-a2af3c7bcc57), [App-Store-Reviews](https://apps.apple.com/ca/app/equestrian-the-game/id1468871996?platform=iphone&see-all=reviews)) | Spieler fühlen sich gemolken; Vertrauensverlust | ❌ NEIN — Ausdauer regeneriert immer von selbst, Cosmetics kosten Gold |
| **My Horse Stories** | Story mit Drama + Ranch-Wiederaufbau als Rahmen ([Geeky Sweetie](https://geekysweetie.com/my-horse-stories-horse-sim-game-review/)) | Erzählmotivation („der Hof meiner Großeltern“) trägt Casual-Spieler | ✅ JA — „Die verwilderte Ranch erblüht wieder“ als Kapitelbogen |
| My Horse Stories (NEGATIV) | Energie-Wände, Outfit-Paywall blockiert Kapitel, Werbung, Content endet abrupt ([Game Brain](https://gamebrain.co/game/my-horse-stories-1), [AppRecs](https://apprecs.com/ios/1447798697/my-horse-stories)) | Spieler kündigen genau an diesen Wänden | ❌ NEIN zu allem davon |
| **Horse Club Adventures 1+2** | Such-Quests OHNE Marker (Objekt glitzert nur gelegentlich) als beste Questform gelobt ([The Mane Quest HCA1](https://www.themanequest.com/blog/2021/6/6/review-horse-club-adventures-a-wholesome-summer-retreat-with-suboptimal-animations-and-controls)) | Selber-Finden ist befriedigender als Marker-Abklappern | ✅ JA — Glitzer-Suchquests im Wald/Heulager |
| Horse Club Adventures | 90 verteilte Rennstrecken, Sticker/Foto-Sammelobjekte, Kalender-Tagesstruktur, Fotografie-Wettbewerb als Story (HCA2) ([Wild River](https://wildriver.games/en/games/horseclub-adventures-en/), [TMQ HCA2](https://www.themanequest.com/blog/2025/6/14/review-horse-club-adventures-2-hazelwood-stories-convinces-with-cozy-vacation-vibes-and-improved-horse-animation)) | Sammelbare Weltdichte + sanfte Tagesstruktur = Urlaubsgefühl | ✅ JA — Zeitrennen-Bögen + Foto-Motive; Sticker-System existiert schon |
| Horse Club Adventures (NEGATIV) | Fetch-Quests („geh hin, sprich, komm zurück“), unsichtbare Wände, kein Schnellreisen ([Game Brain](https://gamebrain.co/game/horse-club-adventures), [TMQ HCA1](https://www.themanequest.com/blog/2021/6/6/review-horse-club-adventures-a-wholesome-summer-retreat-with-suboptimal-animations-and-controls)) | Leere Wege = Langeweile | ❌ Lehre: jede Quest braucht einen Gag/Twist; Schnellreise ab Tag 1 |
| **The Ranch of Rivershine** | Learning-by-doing-Training: Galopp→Ausdauer, enge Wendungen→Flexibilität, Sprünge→Springen; endliches „Potential“ wird 1:1 zu Skill ([TMQ Rivershine](https://www.themanequest.com/blog/2025/11/16/review-the-ranch-of-rivershine-an-almost-perfect-horse-game-and-what-we-can-learn-from-it), [Rivershine-Wiki](https://rivershine.miraheze.org/wiki/Potential)) | Training IST Reiten — kein Menü-Grind | ✅ JA — Trainings-Zuordnung übernehmen; „Potential“-Deckel NICHT (erzeugt Verlustangst) |
| The Ranch of Rivershine | Stadt-Wiederaufbau + Dorfbewohner-Freundschaften + versteckte Schatztruhen ([Cozy Escapism](https://cozyescapism.com/the-ranch-of-rivershine/), [NoobFeed](https://www.noobfeed.com/reviews/the-ranch-of-rivershine-review)) | Cozy-Rahmen um die Pferde-Loops | ✅ JA — NPC-Freundschaften sind expliziter User-Wunsch |
| The Ranch of Rivershine (NEGATIV) | Grind/Wiederholung als Hauptkritik; kaum Ranch-Gestaltung ([NoobFeed](https://www.noobfeed.com/reviews/the-ranch-of-rivershine-review), [Cozy Escapism](https://cozyescapism.com/the-ranch-of-rivershine/)) | Ein Loop allein trägt nicht | ❌ Lehre: Grid-Baumodus (User-Wunsch!) ist unser Differenzierer |
| **Red Dead Redemption 2** | Bindungs-Level 1–4 schalten Manöver frei (Steigen, Rutsch-Stopp, Drift), Pfeif-Reichweite wächst, Pferd wird mutiger ([Fextralife-Wiki](https://reddeadredemption2.wiki.fextralife.com/Horse_Bonding), [Eurogamer](https://www.eurogamer.net/red-dead-redemption-2-best-horse-bonding-horses-explained-4975)) | Bindung ÄNDERT das Spielgefühl spürbar — Gold-Standard | ✅ JA — Freischalt-Tabelle auf `bindung` legen (Männchen, Rutsch-Stopp, Konfetti-Drift) |
| Red Dead Redemption 2 | Beruhigen/Tätscheln als Mikro-Interaktion; Pflege (Füttern/Striegeln) wirkt direkt auf Kern-Stats ([GTABase-Guide](https://www.gtabase.com/red-dead-redemption-2/guides/full-guide-looking-after-your-horse-in-red-dead-redemption-2)) | Pflege ist kein Chore, sondern Beziehungsarbeit | ✅ JA — Tätschel-Knopf beim Reiten (+Bindung, Herzchen-Partikel) |
| **Zelda BotW** | Zähmen: anschleichen (ducken), aufsteigen, beruhigen; sanfte vs. wilde Temperamente; Bindung 0–100 — Pferd hört erst bei voller Bindung perfekt; Straßen-Autopilot bei hoher Bindung ([Zelda Dungeon](https://www.zeldadungeon.net/wiki/Horse_(Breath_of_the_Wild)), [GameFAQs-Guide](https://gamefaqs.gamespot.com/switch/189707-the-legend-of-zelda-breath-of-the-wild/faqs/74764/horse-stats)) | Zähmung = kleines Drama mit Happy End; Autopilot = Komfort als BELOHNUNG | ✅ JA — Wildpferd-Zähmen als sanftes Rhythmus-Minispiel (ohne Abwurf-Frust), Weg-Autopilot ab Bindung 80 |
| **Horse Haven (Community-Wünsche)** | Spieler wünschen sich: Tag/Nacht, Fohlen bleibt bei der Mutter, Geburt miterleben, Tauschen mit Freunden ([App-Store-Reviews](https://apps.apple.com/us/app/horse-haven-world-adventures/id704506972)) | Zeigt, wonach sich Genre-Fans sehnen: NÄHE statt Menüs | ✅ JA — Fohlen-Momente inszenieren (aufstehen, erste Schritte) |

### 2.2 Die 6 wichtigsten Erkenntnisse (verdichtet)

1. **Regelmäßiger Content schlägt alles.** SSO nennt die wöchentlichen Updates seit 2011
   als Kern des Erfolgs. Wir haben mit dem Content-Pack-System (Doc B) die perfekte
   Infrastruktur — die Ranch sollte der Vorzeige-Kanal dafür werden („Ranch-Post“).
2. **Monetarisierung ist die größte Hasswunde des Genres.** Jede recherchierte Live-Game-
   Kritik (SSO, ETG, MHS) dreht sich um Premium-Währung, Energie-Wände, FOMO. GOOBY hat
   keine Echtgeld-Ökonomie → wir können das „faire Star Stable“ sein, das sich alle wünschen.
3. **Bindung statt Stats.** RDR2, BotW und SSOs eigenes Horse-Progression-Update zeigen:
   Pferde-Level als BEZIEHUNG erzählen (Freischaltungen, die das Reitgefühl ändern),
   nicht als Zahlenexcel. Unsere `bindung` ist dafür schon da.
4. **Training = Spielen.** Rivershine + ETG: Stats wachsen durch die ART des Reitens
   (Galopp, Wendungen, Sprünge), nicht durch Menü-Buttons. Passt exakt auf `ride_feel`.
5. **Questqualität > Questquantität.** HCAs Fetch-Quests sind DIE Genre-Schwäche; die
   markerlosen Such-Quests DIE gelobte Ausnahme. Jede Ranch-Quest braucht einen Gag,
   eine Mini-Mechanik oder eine Entscheidung — GOOBYs Humor ist hier der Vorteil.
6. **Die Welt muss leben, nicht groß sein.** HCA-Kritik „sparse map“, Rivershine-Kritik
   „exploration lacks incentives“. Lieber kompaktes Tal mit Wildtieren, Wetter, Events,
   Geheimnissen als leere Quadratkilometer.

---

## 3) 60+ Feature-Ideen für Gooby Ranch

Legende Aufwand: **S** = eine Datei/ein System, geringes Risiko · **M** = mehrere Dateien,
ein neues Teilsystem, moderates Risiko · **L** = neues System quer über Welt/Save/UI/ggf.
Server, braucht eigenen Agent-Schnitt. „Betroffen“ nennt die Hauptsysteme.

### A) Pferde-Systeme

- **A1 — Bindungs-Level mit Freischalt-Tabelle (das Herzstück).** Die bestehende
  `bindung` (0–100) wird in 10 Level übersetzt; jedes Level schaltet etwas SPÜRBARES
  frei: L2 Männchen (Steigen), L3 Rutsch-Stopp, L4 Pfeifen-Rückruf über größere Distanz,
  L5 Konfetti-Drift, L7 Weg-Autopilot, L10 „Seelenpferd“-Aura. Macht Spaß, weil jede
  Pflege-Session auf ein fühlbares Geschenk einzahlt statt auf eine abstrakte Zahl
  (RDR2/SSO-Progression-Vorbild). **M** — `horse_care.gd`, `ride_feel.gd`,
  `ride_controller.gd`, Freischalt-Daten in `wirtschaft.json`.
- **A2 — Trainieren durch Reiten.** Galopp-Zeit füttert Ausdauer, enge Wendungen
  Wendigkeit, Sprünge Sprungkraft (Rivershine-Zuordnung) — als sanft steigende Stats
  ohne Deckel und ohne Verlust. Spaß: Der Ausritt selbst IST die Progression, kein Menü
  nötig. **M** — `ride_feel.gd` (Telemetrie), neuer `horse_training.gd` (pure), Pferde-Dict.
- **A3 — „Perfekt!“-Sprung-Timing.** Absprungfenster wie in Rival Stars: perfekt = Callout,
  Funken, kleiner Tempo-Schub; daneben = Stange wackelt (nie Sturz, nie Strafe). Winzige
  Mikro-Belohnung, die JEDEN Sprung interessant macht. **S** — `ride_feel.gd` + JuiceKit.
- **A4 — Tätscheln & Beruhigen im Sattel.** Ein Knopf beim Reiten: Gooby tätschelt den
  Hals, Herzchen-Partikel, +Bindung (Tagesdeckel existiert schon). Bei Schreck-Momenten
  (Gewitter, Random-Event) beruhigt es das Pferd — Beziehungsarbeit als Mikro-Interaktion
  (RDR2). **S** — `ride_controller.gd`, HUD-Knopf.
- **A5 — Wildpferde zähmen.** Bei bestimmtem Wetter/Uhrzeit erscheint eine kleine
  Wildherde am Waldrand. Anschleichen (Duck-Knopf), behutsam nähern, dann ein sanftes
  Rhythmus-Beruhigen (Tap im Takt des Schnaubens — KEIN Abwerfen, Fehlversuch heißt nur
  „es trabt davon, kommt wieder“). Gezähmte Wildpferde haben besondere Fellmuster.
  BotW-Fantasie ohne BotW-Frust. **L** — neue Logik + Welt-Spawns + `ranch_pferd.gd`-Muster.
- **A6 — Pferde-Persönlichkeiten.** Jedes Pferd bekommt 1 von ~6 Temperamenten
  (verspielt, verfressen, schüchtern, stolz, verschlafen, neugierig) mit kleinen
  Verhaltens- und Dialog-Effekten: das verfressene bettelt am Apfelbaum, das stolze
  will nach dem Turnier extra gelobt werden. Gibt jedem Pferd Charakter über die Farbe
  hinaus. **M** — Pferde-Dict, `ranch_pferd.gd`-Idles, Textbausteine.
- **A7 — Fohlen-Aufzucht als Warte-Erlebnis.** Zwei eigene Pferde + Herzchen-Koppel →
  Fohlen-Ankündigung; das Fohlen wächst über REALE Tage in 4 sichtbaren Stufen
  (liegend → staksig → halbgroß → reitbar), mit Notification/Live-Activity „Das Fohlen
  steht zum ersten Mal!“. Farbe ist deterministisch mischbar (Eltern-Palette + Wunschtupfer),
  KEIN Stat-Casino. Star-Stable-Horses-App-Loop, aber ohne zweite App. **L** —
  `ranch_play_slices.gd`, `ranch_offline.gd`-Zeitmuster, `ranch_pferd.gd`-Skalierung,
  NotifyScheduler.
- **A8 — Pferde-Erinnerungsalbum.** Pro Pferd ein kleines Album mit Auto-Momenten
  (erster Galopp, erste Schleife, erster Regenritt) als Polaroid + Datum. Verstärkt die
  Bindung ans INDIVIDUELLE Tier — das, was Horse-Haven-Spieler sich wünschen. **M** —
  neuer UI-Screen, Save-Unterschlüssel, Foto-Hooks.
- **A9 — Snack-Vorlieben & Picknick.** Jedes Pferd hat Lieblings-Snacks (Karotte, Apfel,
  Hafertaler); richtig geraten = Doppel-Bindung + Freuden-Animation. Beim Ausritt kann
  Gooby Picknick-Pause machen — beide futtern, Ausdauer-Regen-Buff. **S** —
  `horse_care.gd`, Pflege-Screen, 1 Welt-Interaktion.
- **A10 — Pfeifen & „Wo ist mein Pferd?“.** Pfeif-Knopf ruft das aktive Pferd (Reichweite
  wächst mit Bindung, A1); dazu ein Kamera-Sprung-Knopf analog „Wo ist mein Gooby?“.
  Komfort, der sich wie Magie anfühlt. **S** — `ranch_hof_scene.gd`, HUD.

### B) Welt & Orte

- **B1 — Das Ranch-Tal wächst: 3 neue Zonen.** Ans bestehende Riesenfeld docken per
  Reitweg an: **Flüsterwald** (Schatten, Glitzer-Suchquests, Wildpferde), **Seeblick**
  (Badestrand, Angel-Steg, Enten), **Hügelweide** (Panorama, Drachensteigen, Schafherden).
  Jede Zone = eigener Plan-Abschnitt in `ranch_welt.gd`, MultiMesh-Budget bleibt. Macht
  Spaß, weil Ausritte ZIELE bekommen — die Genre-Kritik „leere Karte“ vermeiden wir durch
  Dichte statt Fläche. **L** — `ranch_welt.gd`, `ranch_bau.gd`, Spawns, Content-Pack.
- **B2 — Reit-Dorf „Hufingen“.** Kleiner Ort am Talrand: Reitladen (Gear), Futterhof,
  Möbel-Scheune (Ranch-Deko kaufen und nach Hause liefern lassen — User-Wunsch „zu Orten
  reiten um Möbel zu kaufen“), Pferdehändlerin Frau Wieher, Café mit Ranch-Klatsch.
  Gibt der Wirtschaft ein GESICHT statt Menü-Shops. **L** — Welt + 4 Innenräume
  (Ort-Szenen-Muster aus E §2.3), NPC-Anbindung.
- **B3 — Schnellreise über Ortsschilder.** Jedes entdeckte Ortsschild = Reiseziel;
  Schnellreise kostet nichts, spielt eine 2-s-Trab-Vignette. Behebt die meistgenannte
  HCA-Komfort-Kritik (kein Fast Travel). **M** — `ranch_routen.gd`, Karten-UI.
- **B4 — Ranch-Karte im Stickeralbum-Stil.** Handgemalte Talkarte mit Pins (Quests,
  Foto-Spots, Bestzeiten), Nebel über Unentdecktem, der beim Erkunden aufklart.
  **M** — neuer UI-Screen, Entdeckungs-Flags im Save.
- **B5 — Such-Quests ohne Marker.** „Der Heuwagen hat 5 Hufeisen verloren“ — Objekte
  glitzern nur alle paar Sekunden, kein Marker (HCAs gelobte Mechanik). Belohnt
  Aufmerksamkeit statt Abklappern. **S** pro Quest — Interactable-Komponente existiert.
- **B6 — Geheimnisse & Schatztruhen.** Versteckte Höhle hinter dem Wasserfall,
  vergrabene Truhen (Schaufel-Spot glitzert nach Regen!), eine scheue Rehfamilie, die
  man nur im Morgengrauen sieht. Rivershine-Kritik „exploration lacks incentives“
  beantworten. **M** — Welt-Daten + Sticker/Belohnungs-Hooks.
- **B7 — Foto-Spots + Zeitlupen-Kamera.** Markierte Panorama-Punkte; der Fotomodus
  (POW!-Kamera) bekommt auf der Ranch Zeitlupe wie Rival Stars („Sprungfoto“). Fotos
  landen im Erinnerungsalbum (A8) und können Freunden geschickt werden. **M** —
  Fotomodus-Hook, Welt-Marker.
- **B8 — Nacht-Ranch.** Nach Sonnenuntergang: Laterne am Sattel, Glühwürmchen am Teich,
  Sternschnuppen (Wunsch-Gag), Eulen. Der Stall-Tagesrhythmus existiert schon — die
  Nacht wird vom Hindernis zum Erlebnis. **M** — `ranch_bau.gd`-Lichtprofil, Spawns.

### C) Quests & NPCs

- **C1 — NPC-Ensemble mit Dialogbäumen (8–10 Figuren).** Tierärztin Dr. Möhrchen,
  Hufschmied Opa Eisenhuf, Futterhändler, Nachbarsjunge mit Pony-Angst, Wanderhändlerin,
  Café-Besitzerin, … Jede Figur: eigener Sprech-Pitch (Gebrabbel), Tagesroute, Humor-Kante.
  Nutzt das geplante Dialog-System (Backlog E §2.2) — Ranch wird dessen erster Vollausbau.
  **L** — Dialog-Runner + Figuren + deutsche Texte.
- **C2 — NPC-Freundschaftswerte (expliziter User-Wunsch).** Pro NPC ein Herz-Level
  (0–5) durch Quests, Geschenke, Gespräche; Stufen entsperren: Rabatte, Rezepte,
  persönliche Quests, am Ende ein „bester Freund“-Geschenk (z. B. Opa Eisenhufs alte
  Glücks-Hufeisen-Girlande). Stardew-Muster, GOOBY-Ton. **M** — neuer Save-Unterschlüssel,
  Dialog-Gates, Geschenk-UI.
- **C3 — Haupt-Questreihe „Die Ranch erwacht“ (5 Kapitel).** Erzählbogen: die Ranch war
  mal berühmt für ihr Sommerfest; Kapitel für Kapitel (Stall flott machen → erstes Pferd
  ausbilden → Dorf kennenlernen → Turnier bestehen → großes Ranchfest) erwacht sie wieder.
  SSO zeigt: die GESCHICHTE hält Spieler; My Horse Stories zeigt: der Wiederaufbau-Rahmen
  trägt. **L** — Quest-Engine-Port (`quests.js`-Port steht im A-§8-Backlog), Kapitel-Daten.
- **C4 — Warte-Quests mit Live-Activity (expliziter User-Wunsch).** Quest-Schritte wie
  „Der Hufschmied braucht bis morgen früh“ oder „Das Brot backt 30 min“ laufen über
  Timestamps (Taxi-Statemaschinen-Muster), erzeugen lokale Notifications und — sobald das
  native Plugin da ist (Backlog C §8) — eine Live Activity auf dem iPhone-Sperrbildschirm
  mit eigenem Ranch-Design (Fohlen-Fortschrittsbalken!). Wichtig: Warten ist nie BLOCKIEREND
  fürs übrige Spiel. **M** (Godot-Seite) + **L** (natives Plugin) — `notify_scheduler.gd`,
  Quest-Engine.
- **C5 — Tägliche Hof-Momente statt Pflicht-Dailies.** 3 rotierende Mini-Aufgaben
  („Miste Bella-Boxen aus“, „Bring Dr. Möhrchen 2 Äpfel“, „Reite einmal um den See“)
  geben Pferde-XP + Gold. BEWUSST ohne Streak, ohne Verfall, ohne Malus — wer 2 Wochen
  wegbleibt, verpasst nichts (SSO-Chores ohne SSO-Druck). **S** — Aufgaben-Roller (pure),
  HUD-Karte.
- **C6 — Quest-Gag-Pflicht (Designregel).** Jede Quest braucht mindestens EINEN Twist:
  eine Mini-Mechanik, eine Entscheidung oder einen Gag (das gesuchte Huhn sitzt am Ende
  auf Goobys Kopf). Fetch-Ketten wie in HCA sind der dokumentierte Genre-Killer.
  **S** — Doku/Review-Checkliste, keine Engine-Arbeit.
- **C7 — Saison-Quests per Content-Pack.** Erntefest (Herbst), Laternenritt (Winter),
  Blütenfest (Frühling) als nachgelieferte Quest-Packs — unser Auto-Update-System ist die
  SSO-Weekly-Update-Antwort. **M** pro Event — Quest-Daten + Deko-Spawns, KEINE neuen Systeme.
- **C8 — NPC-Tagesrouten.** NPCs stehen nicht fest, sondern haben 2–3 Tagesstationen
  (morgens Stall, mittags Café, abends Koppelzaun) mit Weg-Läufen. Die Welt fühlt sich
  bewohnt an — Kernkritik „leer“ vermeiden. **M** — Routen-Daten + simple Agenten
  (Traffic-Agenten-Muster aus `city/traffic/`).

### D) Wirtschaft & Ranch-Ausbau

- **D1 — Grid-Baumodus für den Hof (expliziter User-Wunsch).** Der Haus-Baumodus
  (`home/grid_data.gd`) bekommt einen Außen-Modus: Zäune als Kanten-Items, Ställe/Tröge/
  Deko frei auf dem Hof-Grid platzieren, Wege legen. Die Koppel dort bauen, wo ICH will —
  das ist der große Differenzierer gegenüber Rivershine („no real ranch customisation“).
  **L** — GridData-Wiederverwendung, neue Außen-Kataloge, `ranch_bau.gd`-Integration.
- **D2 — Sichtbare Ausbaustufen mit Bau-Gag.** Die bestehenden Stufen (Boxen, Reitplatz,
  Weidezaun) verändern die WELT sichtbar (größerer Stall, schickere Bande) und spielen
  die Gooby-hämmert-Qualm-Animation. Upgrades, die man SIEHT, motivieren mehr als Zahlen
  (Rival-Stars-Anlagen). **M** — `ranch_bau.gd`-Varianten, Ausbau-Panel-Anbindung.
- **D3 — Futtergarten am Stall.** Kleines Beet-Grid für Karotten/Hafer/Sonnenblumen;
  Regen gießt automatisch (Wetter-Kopplung H1), Ernte = Snacks + Verkaufsware. Nutzt die
  Garten-Mechanik aus Doc D §6, keine Parallel-Implementierung. **M** — Garten-Integration,
  Balance-Daten.
- **D4 — Sanftes Sammel-Einkommen.** Hühnereier, Schafwolle, Kuhmilch erscheinen
  periodisch als Einsammel-Glitzer — nichts verdirbt, nichts läuft ab (Anti-Energie-Prinzip).
  Kleine Belohnung fürs Vorbeischauen ohne Bestrafung fürs Wegbleiben. **S** —
  Timestamp-Spawner + `ranch_tiere.gd`-Hooks.
- **D5 — Pferdehändlerin mit wiederkehrendem Angebot.** Frau Wieher führt 3 Pferde,
  Sortiment wechselt wöchentlich — aber JEDES Pferd kehrt irgendwann zurück (Katalog
  rotiert, nichts ist „für immer weg“). Vorfreude statt SSO-FOMO. **M** —
  Angebots-Roller (deterministisch aus Wochen-Seed), Kauf-UI.
- **D6 — Trophäen-Regal & Schleifenwand im Ranch-Haus.** Turnier-Schleifen und Pokale
  werden als 3D-Deko im Ranch-Haus ausgestellt; Freunde sehen sie beim Besuch. Erfolge
  zum ANFASSEN statt Menü-Liste. **M** — Deko-Items + Erfolgs-Hooks.
- **D7 — Goobay-Flohmarkt-Stand.** Alte Ausrüstung am Hoftor verkaufen, mit dem
  Verhandlungs-Gag aus Doc D §5.4 (Emoji-Eskalation). Wiederverwendung statt Neubau.
  **S** — Anbindung des bestehenden Verhandlungs-Flows.
- **D8 — EINE Währung, faire Preise (Designregel).** Alles kostet Gold, alles ist
  erspielbar, Preise sind Balance-Daten im Pack. Die gesamte Genre-Recherche schreit:
  KEINE zweite Premium-Währung, keine Echtgeld-Anker. **S** — Balance-Review, Doku.

### E) Wettbewerbe & Minispiele

- **E1 — Dorf-Turnier mit Liga-Aufstieg.** Wöchentliches Turnier in Hufingen: 3 Disziplinen
  (Parcours, Geschick, Tempo) gegen liebevoll benannte Bot-Reiter mit Persönlichkeit
  („Rosalinde auf Donnerkeks“). Ligen Blech → Bronze → Silber → Gold → Konfetti; Abstieg
  gibt es NICHT. Podium-Zeremonie mit Schleifen. Wettbewerb ohne PvP-Härte. **L** —
  Turnier-Logik (pure), Bot-Zeiten aus Level-Seeds, Zeremonie-Szene.
- **E2 — Zeitrennen-Bögen in der Welt.** 8–12 Strecken quer durchs Tal (HCA: 90 Kurse!)
  mit 3 Medaillen-Zeiten und Geister-Replay der EIGENEN Bestfahrt. Das eigene Ghost
  schlagen ist die fairste Form von Rennspannung. **M** — Strecken-Daten, Ghost-Recorder
  (Positions-Samples), HUD.
- **E3 — Parcours-Editor light.** Auf dem eigenen Reitplatz Hindernisse aus dem Grid-Bau
  (D1) frei stecken und eine eigene Strecke speichern; Freunde können die Bestzeit
  angreifen (async). Kreativität + Wettbewerb verzahnt. **L** — Editor-UI über GridData,
  Kurs-Serialisierung.
- **E4 — Neue Minispiele im bestehenden Framework (je 10 Level + Sterne).**
  (a) **Pferdewäsche**: Schaum-Wisch-Spiel mit befriedigenden Partikeln (sensorisch,
  wie das gelobte Grooming echter Pflege-Apps); (b) **Apfelfangen im Galopp**:
  fallende Äpfel im Ritt fangen; (c) **Schatz-Ausritt**: Kartenschnipsel folgen +
  buddeln; (d) **Hüpfball-Hütehund**: Herde-Variante mit Hund als Steuerfigur.
  **M** je Spiel — Logic + Szene + Bot-Zertifizierung (Muster `ranch_parcours`).
- **E5 — Gymkhana-Spielwiese.** Slalomstangen, Becherrennen, Tonnen-Wende als freie
  Übungen auf dem Reitplatz — ohne Wertung jederzeit, MIT Wertung im Turnier (E1).
  Übung und Ernstfall teilen dieselben Bausteine. **M** — Reitplatz-Module.
- **E6 — „Perfekte Woche“-Sammelziel.** Wer in einer Woche 1 Turnier, 3 Ausritte und
  2 Pflege-Rituale macht, bekommt einen Saison-Sticker — freundliches Engagement-Ziel
  ohne Streak-Bestrafung (Gegenteil von Login-Kalendern). **S** — Zähler + Sticker-Hook.
- **E7 — Multiplayer-Rennen (Freunde, 2–4).** Live-Rennen auf den Zeitrennen-Strecken
  über GOOBY-SERVER-Rooms (POS-Relay 5 Hz existiert aus dem Besuchs-System): Konfetti
  statt Blauer-Panzer — Items sind rein kosmetisch-fröhlich (Seifenblasen, die kitzeln,
  aber nie bremsen). Alicia zeigt: das RENNGEFÜHL trägt, Sabotage braucht es nicht.
  **L** — Server-Room-Typ, Client-Interpolation, Start-Countdown.
- **E8 — Coop-Herde.** Das bestehende Herde-Minispiel als 2-Spieler-Koop: jeder treibt
  von einer Seite (User-Wunsch Mehrspieler-Minispiele). Baut auf E7-Netzcode auf. **M**
  nach E7 — Herde-Logic ist deterministisch, gut relaybar.

### F) Multiplayer & Sozial

- **F1 — Ranch-Besuch bei Freunden.** Das Haus-Besuchssystem (W3c `visits.js`) auf die
  Ranch ausweiten: Freund reitet auf DEINER Ranch, sieht deinen Ausbau, deine Pferde,
  deine Trophäenwand. Der stärkste soziale Moment im Genre („zeig mir deinen Hof!“).
  **L** — Snapshot-Sync des Ranch-Grids, Remote-Gooby + Remote-Pferd.
- **F2 — Gemeinsamer Ausritt.** Zwei Goobys reiten synchron durchs Tal (POS-Relay),
  mit Foto-Knopf für Doppel-Porträts und Rast am Lagerfeuer (Emote-Bar existiert).
  Kein Ziel, kein Timer — geteiltes Dasein ist das Produkt. **M** — auf F1-Netzcode.
- **F3 — Gästebuch am Hoftor.** Async & offline-first: Besucher hinterlassen einen
  gestempelten Gruß (kuratierte Textbausteine + Sticker, KEIN Freitext-Chat). Beim
  nächsten Start freut man sich über Post — soziale Wärme ohne Chat-Risiko (SSO-Lehre).
  **S** — Server-Mail-Muster (C §3.7), kleines UI.
- **F4 — Leihpferd für Freunde.** Beim Besuch darf der Freund ein Pferd probereiten
  (temporär, nichts wechselt den Besitzer — kein Handel, kein Scam-Vektor). Teilen
  ohne Ökonomie-Risiko. **M** — Besuchs-Flag + Ride-Controller-Freigabe.
- **F5 — Bestzeiten unter Freunden.** Zeitrennen-Boards zeigen NUR Freunde + eigene
  Ghosts — kein globales Leaderboard (Toxizität/Cheat-Druck raus, Motivation bleibt).
  **M** — Server-Scores pro Strecke, Friends-Filter.
- **F6 — Reitgruppe (Club light).** 2–8 Freunde gründen eine Reitgruppe: gemeinsames
  Banner (Editor mit Formen/Farben), ein kooperatives Wochenziel („zusammen 30 Runden“)
  mit Gruppen-Sticker. SSO-Club-Wärme ohne Rollen-/Moderations-Bürokratie. **L** —
  Server-Gruppenobjekt, Banner-Renderer, Ziel-Zähler.
- **F7 — Foto-Postkarten.** Ranch-Fotos als Postkarte an Freunde schicken (Post-System
  C §3.7); die Karte kommt gerahmt ins Gästebuch des Empfängers. Verbindet Fotomodus,
  Post und Besuch zu einem Kreislauf. **M** — Foto-Upload-Quota existiert im Post-Konzept.

### G) Cosmetics

- **G1 — Gear-Sets mit Themen.** Über die 3 Slots × 5 Farben hinaus: thematische Sets
  (Blumenwiese, Sternennacht, Regenbogen, Winterfilz) als Cosmetics-Packs (H §4-Format) —
  per Auto-Updater nachlieferbar, mit Set-Bonus rein KOSMETISCH (Funkel-Aura). **M** —
  `gear_meshes.gd`-Erweiterung, Pack-Einträge.
- **G2 — Mähnen-Salon.** Zöpfe, Blumen, Schleifen für Mähne/Schweif beim Salon in
  Hufingen (Star-Stable-Horses-Beauty-Salon). Frisuren sind Meshes/Morphs am
  Pferd-Vertrag. **M** — `ranch_pferd.gd`-Anbauten, Salon-UI.
- **G3 — Gooby-Reitoutfits.** Reithelm (mit Ohrlöchern!), Halstuch, Stiefelchen als
  neue Cosmetic-Slots, kompatibel mit dem bestehenden Outfit-System. **M** —
  Cosmetics-Pack + Anchor-Punkte.
- **G4 — Erspielbare Effekt-Anhänger.** Hufglocken (Klingeln), Glitzer-Hufspur,
  Schmetterlings-Begleiter — ausschließlich über Turniere/Quests/Sticker-Sets erspielbar.
  Prestige durch LEISTUNG, nicht durch Kauf (Anti-SSO-Statement). **S** je Effekt —
  Partikel + Freischalt-Hook.
- **G5 — Stall-Deko & Namensschilder.** Boxen-Schilder mit Pferdenamen, Girlanden,
  Blumenkästen im Stall-Interieur; Teil des Grid-Katalogs (D1). **S** — Katalog-Items.
- **G6 — Seltene Fellmuster über Zähmung & Feste.** Wildpferde (A5) und Saison-Events
  (C7) bringen besondere Muster (Apfelschimmel, Sternchen-Tupfen) — planbar erspielbar,
  nie zeitlich „für immer weg“ (kehren jährlich wieder). **M** — Fell-Material-Varianten.

### H) Leben & Atmosphäre (Wetter, Tiere, Events)

- **H1 — Wetter-System (expliziter User-Wunsch).** Sonne/Wolken/Regen/Nebel/Schnee mit
  sanften Übergängen; MECHANISCH verzahnt: Regen gießt den Futtergarten (D3) und füllt
  den Trog, nach Regen glitzern Buddel-Stellen (B6), bei Nebel erscheinen Wildpferde (A5),
  Schnee bringt Schlitten-Deko. Wetter, das Gameplay ÖFFNET statt sperrt. Nutzt den
  geplanten `weather`-Port (Backlog A M2). **L** — Wetter-Zustandsmaschine,
  `ranch_bau.gd`-Himmel/Partikel, Kopplungs-Hooks.
- **H2 — Wildtiere.** Rehe (fliehen sanft), Hasen, Füchse (nachts), Vogelschwärme,
  Schmetterlinge, Enten auf dem Teich — im billigen `ranch_tiere.gd`-Stil. Eine Handvoll
  Arten mit je 1–2 Verhalten reicht, damit sich das Tal BEWOHNT anfühlt (Kern-Erkenntnis
  §2.2-6). **M** — neue Tier-Typen + Flucht-/Flug-Verhalten.
- **H3 — Ranch-Random-Events.** Der Event-Scheduler (W3d) bekommt Ranch-Definitionen:
  „Ein Huhn sitzt auf Bellas Rücken!“, „Die Ziege ist ins Heulager eingebrochen 😱“,
  „Doppelter Regenbogen überm Tal“ (Foto-Aufforderung), „Igelbesuch am Trog“. Zeitfenster
  + witziger Fail-Text, wie gehabt — nie Strafen. **M** — Event-Defs + kleine Inszenierungen.
- **H4 — Pferde-Koppelverhalten.** Pferde beschnuppern sich, jagen sich verspielt,
  wälzen sich (danach: schmutzig! Pflege-Anlass mit Augenzwinkern), dösen Kopf-an-Kopf.
  Der Star-Stable-Horses-Koppel-Moment: einfach ZUSCHAUEN wollen. **M** —
  Verhaltens-Zustandsmaschine über 2+ Pferde.
- **H5 — Jahreszeiten-Look per Content-Pack.** Frühlingsblüte, Sommer-Sattgrün,
  Herbstlaub, Schneedecke als Material-/Spawn-Varianten der bestehenden Welt-Pläne;
  Feste (C7) docken an. **L** — Material-Sets, saisonale Spawn-Tabellen.
- **H6 — Sanfte Notifications (expliziter User-Wunsch).** „Das Fohlen ist aufgewacht 🐴“,
  „Dein Turnier beginnt bald“ — opt-in, standardmäßig max. 2/Tag, IMMER positiv
  formuliert, NIE „dein Pferd hungert!“ (kein Schuld-FOMO wie in Tamagotchi-Klonen).
  **S** — NotifyScheduler-Regeln + Settings-Schalter.
- **H7 — Lagerfeuer-Abende.** Feuerstelle am See: Gooby + Pferd + ggf. Besuchs-Freund
  sitzen, Marshmallow-Gag, Gebrabbel-Geschichten, Sternenhimmel-Timelapse. Ein Ort, der
  NUR Stimmung ist — das Rival-Stars-Free-Roam-Gefühl. **S** — Szenen-Vignette + Emotes.
- **H8 — Ambient-Audio-Bett.** Vogelzwitschern nach Tageszeit, Wind in den Wipfeln,
  Regen aufs Stalldach (Innen gedämpft!), Hufschlag wechselt mit Untergrund
  (Gras/Schotter/Brücke). Audio trägt 50 % der Cozy-Wirkung. **M** — AudioDirector-Busse,
  Untergrund-Map.

### I) Technik & Komfort

- **I1 — Ranch-Post: monatliche Content-Packs als Ritual.** Das Ranch-DLC wird der
  Vorzeige-Kanal des Update-Systems: jeden Monat ein kleines Pack (Quest, Fellfarbe,
  Deko, Event) mit In-Game-Ankündigung am Schwarzen Brett. SSOs Weekly-Update-Lehre,
  auf unsere Infrastruktur übersetzt. **S** pro Pack — Prozess, keine neuen Systeme.
- **I2 — Offline-first-Degradation überall.** Jedes MP-Feature (Besuch, Rennen,
  Gästebuch) zeigt offline einen freundlichen Chip und lokale Alternative (Ghost statt
  Live-Rennen). Muster existiert (C §6) — für alle Ranch-Features verbindlich. **S** —
  Review-Checkliste + Chips.
- **I3 — Weg-Autopilot als Bindungs-Belohnung.** Ab Bindung 80 folgt das Pferd auf
  Wunsch dem Reitweg von selbst (BotW-Straßenlogik) — Kamera frei fürs Gucken. Komfort
  als PROGRESSION verpackt. **M** — Pfad-Follower auf `ranch_routen`-Wegen.
- **I4 — Einfacher Reit-Modus.** Settings-Schalter „Einfach reiten“: Auto-Gangart,
  größere Sprungfenster, keine Ausdauer — für kleine Geschwister. Zielgruppe
  Familie ernst nehmen. **S** — `ride_feel`-Parametersatz.
- **I5 — Performance-Budget-Verträge für neue Zonen.** Jede neue Zone (B1) liefert
  einen headless Draw-Call-/Tri-Test wie die bestehende Welt (≤ 400 Draw-Calls
  in Sicht). Verhindert, dass das DLC das iPhone-Budget (A §7) sprengt. **S** —
  Test-Muster kopieren.
- **I6 — Additive Save-Slices, nie Version-Bump.** Alle neuen Daten (`quests`, `npcs`,
  `wetter`, `zucht`, `turnier`) als eigene Unterschlüssel mit normalize-Self-Heal —
  exakt das `ranch_play_slices`-Muster. Alte Stände bleiben IMMER ladbar. **S** — Muster.
- **I7 — Bot-Zertifizierung für alles Wettbewerbliche.** Jedes neue Minispiel/Turnier
  liefert `simulate_autoplay` + expected-JSONs (Fairness-Regeln G §2.5). Schwierigkeits-
  frust wird im Test gefangen, nicht im Kinderzimmer. **S** pro Spiel — Muster existiert.
- **I8 — „Wo ist mein Pferd?“/„Zur Ranch“-Komfortknöpfe.** Ein-Tap-Rückkehr zum Hof von
  überall im Tal (analog „Nach Hause“-Knopf der Stadt), plus A10-Pfeifen. Niemand soll
  je „verloren“ sein. **S** — Router-Aufrufe + HUD.

---

## 4) „So würde ich es bauen“ — priorisierte Reihenfolge (mit Begründung)

Reihenfolge nach **Abhängigkeiten + Spielwert pro Ausbaustufe**, nicht nach Kalender.
Jede Stufe hinterlässt ein rundes, shipbares Spiel (Content-Pack-fähig!).

1. **Stufe 1 — Reitgefühl & Pferde-Beziehung vertiefen (A1–A4, A9, A10, I3, I4, I8).**
   Begründung: Das Reiten ist die Handlung, die Spieler zu 80 % ausführen — jede
   Verbesserung hier multipliziert in ALLE späteren Features (Quests, Turniere, MP).
   Kein neues Content-Risiko, baut nur auf `ride_feel`/`horse_care` auf.
2. **Stufe 2 — Welt beleben (H1 Wetter, H2 Wildtiere, H3 Events, H8 Audio, B5, B6, B8).**
   Begründung: „Lebendig statt leer“ ist expliziter User-Wunsch UND die dokumentierte
   Genre-Schwäche. Wetter zuerst, weil H1 mechanische Hooks für Garten, Zähmung und
   Buddel-Stellen liefert, an die alles Spätere andockt.
3. **Stufe 3 — NPCs, Freundschaft & Haupt-Quest (C1, C2, C3, C5, C6, B3, B4).**
   Begründung: Braucht das Dialog-System (ohnehin M2-Backlog) — die Ranch wird sein
   erster Vollausbau. Ab hier hat das DLC eine GESCHICHTE und tägliche Anlässe; Retention
   beginnt hier, nicht bei Mechanik-Menge.
4. **Stufe 4 — Ranch-Gestaltung & Wirtschaft (D1 Grid-Bau, D2, D3, D4, B2 Hufingen, D5–D7).**
   Begründung: Grid-Bau ist der User-Kernwunsch und unser Differenzierer, braucht aber
   die belebte Welt (Stufe 2) und Gold-Quellen/Senken (Stufe 3-Quests), damit Bauen
   ZIELE hat. Hufingen gibt der Wirtschaft ein Gesicht.
5. **Stufe 5 — Wettbewerbe (E1 Turnier, E2 Zeitrennen, E4 zwei neue Minispiele, E5, D6).**
   Begründung: Wettbewerbe sind erst mit Pferde-Progression (Stufe 1) + Welt (Stufe 2)
   sinnvoll; die Liga verwertet alles bisher Gebaute als Bühne. Ghost-Replays bereiten
   den MP-Netzcode gedanklich vor.
6. **Stufe 6 — Fohlen & Warte-Erlebnisse (A5 Zähmen, A7 Fohlen, A8 Album, C4, H6, G6).**
   Begründung: Zucht/Zähmung sind die stärksten Langzeit-Bindungen, brauchen aber
   die Bindungs-/Pflege-Tiefe aus Stufe 1 und Notifications-Infrastruktur; Live Activity
   hängt am nativen Plugin (eigenes Risiko, deshalb nicht früher auf dem kritischen Pfad).
7. **Stufe 7 — Multiplayer & Sozial (F1–F5, E7, E8, dann F6, F7).**
   Begründung: Serverseitig existieren Visits/Rooms schon — aber MP lohnt erst, wenn es
   etwas zu ZEIGEN gibt (Ausbau, Trophäen, Fohlen). Reihenfolge innen: Besuch → Ausritt →
   Async-Boards → Live-Rennen → Reitgruppe (steigende Komplexität).
8. **Stufe 8 — laufender Betrieb (I1 Ranch-Post, C7 Saison-Quests, H5 Jahreszeiten,
   G1–G6 Cosmetics-Wellen, E3 Parcours-Editor).**
   Begründung: Ab hier ist das DLC „fertig“ und lebt vom Content-Rhythmus — genau wofür
   das Pack-System gebaut wurde. Cosmetics und Feste sind ideale kleine Packs.

Querschnitts-Regeln ab Stufe 1: I2 (offline-first), I5 (Perf-Tests), I6 (additive Saves),
I7 (Bot-Zertifizierung) gelten für JEDE Stufe.

---

## 5) 10 Dinge, die wir bewusst NICHT machen (mit Begründung)

1. **Keine Premium-Währung, kein Abo, kein Echtgeld-Shop.** Die gesamte Recherche zeigt:
   Star Coins & Co. sind DIE Hasswunde des Genres ([SSO-Forum](https://ssoforums.freeforums.net/thread/2321/star-stable),
   [Ginny O.](https://ginny0.wordpress.com/2018/06/26/tuesdaythoughts-parents-and-players-dont-play-star-stable/)).
   GOOBY hat eine Gold-Ökonomie — dabei bleibt es.
2. **Kein Energie-System und keine Bezahl-Booster.** ETG/My Horse Stories beweisen, dass
   Energie-Wände Spieler exakt an der Wand kündigen lassen ([Medium](https://medium.com/@quest.equestrians/review-equestrian-the-game-a2af3c7bcc57),
   [Game Brain](https://gamebrain.co/game/my-horse-stories-1)). Pferde-Ausdauer regeneriert
   immer von selbst; Warten ist nie blockierend.
3. **Keine FOMO-Rotationen mit „für immer weg“.** SSOs Magic-Horse-Karussell erzeugt
   Kaufdruck und entwertet Besitz ([SSO-Forum](https://ssoforums.freeforums.net/thread/5161/problem-sso-currency)).
   Bei uns kehrt ALLES wieder (Händler-Katalog rotiert, Saison-Muster kommen jährlich).
4. **Keine RNG-Zucht-Lotterie.** Alicias Coat-Casino und Rival-Stars-Grade-Wurf machen
   aus Lebewesen Lose. Fohlen-Farben sind deterministisch mischbar, Stats kein Glücksspiel —
   das Fohlen ist IMMER ein gutes Fohlen.
5. **Kein offener Welt-Chat.** SSOs größtes Sicherheitsproblem für die Kinder-Zielgruppe
   ([Screenwise](https://screenwiseapp.com/media/star-stable-online-app)). Kommunikation nur
   unter Freunden über Emotes + kuratierte Textbausteine (Gästebuch, Postkarten).
6. **Kein Pferde-Leid: kein Tod, keine Krankheit als Strafe, kein Weglaufen.** Werte
   klemmen bei „mürrisch, will geknuddelt werden“ — nie bei „krank/verhungert“.
   Vernachlässigungs-Schuld ist das Gegenteil des Animal-Crossing-Vertrags von GOOBY.
7. **Kein globales Leaderboard / kein Ranked-PvP.** Erzeugt Toxizität, Cheat-Druck und
   Verlierer-Frust. Wettbewerb läuft gegen Bots mit Persönlichkeit, eigene Ghosts und
   Freundes-Bestzeiten (F5) — Abstieg existiert nicht.
8. **Keine Fetch-Quest-Ketten und keine künstliche Quest-Drosselung.** HCAs „geh hin,
   sprich, komm zurück“ ist die dokumentierte Genre-Langeweile ([Game Brain](https://gamebrain.co/game/horse-club-adventures)),
   SSOs Tages-Gates strecken künstlich ([Ginny O.](https://ginny0.wordpress.com/2018/06/26/tuesdaythoughts-parents-and-players-dont-play-star-stable/)).
   Warte-Quests bei uns sind ERLEBNISSE (Fohlen wächst), keine Bremsen.
9. **Keine Realismus-Simulation.** Keine komplexe Hilfengebung, keine Sturzphysik, kein
   Hufkratzen-Pflicht-Minispiel (Rivershine-Fans feiern ausdrücklich „No frustrating hoof
   cleaning mini games“ ([Cozy Escapism](https://cozyescapism.com/the-ranch-of-rivershine/))).
   GOOBY-Pferde sind rund, pastellig und freundlich — Game-Feel schlägt Anatomie (Alicia-Lehre).
10. **Keine zweite App und keine Werbung.** Star Stable lagert die Fohlen-App aus — wir
    holen den Loop INS Spiel (A7). Werbe-Unterbrechungen (My Horse Stories:
    „Ads verursachen Freezes und Crashes“, [Game Brain](https://gamebrain.co/game/my-horse-stories-1))
    sind mit dem Wohlfühl-Vertrag unvereinbar.

---

## 6) Quellenliste

- Star Stable: [PocketGamer.biz — Rise of SSO (Weekly Updates, Clubs, Retention)](https://www.pocketgamer.biz/rise-star-stable-online/) ·
  [SSO-Blog Horse Progression 2023](https://www.starstable.com/en/blog/may-horseprogression-2023) ·
  [SSO-Hilfe: Pferde-Leveln](https://help.starstable.com/hc/en-us/articles/360001357300-How-do-I-level-up-my-horse) ·
  [SSO-Wiki Clubs](https://starstable.wiki.gg/wiki/Clubs) ·
  [Engadget Rise-and-Shiny-Review](https://www.engadget.com/2013-11-10-rise-and-shiny-revisit-star-stable.html) ·
  Kritik: [Forum „The Reason I Hate Star Stable“](https://ssoforums.freeforums.net/thread/2321/star-stable) ·
  [Forum „The Problem with SSO Currency“](https://ssoforums.freeforums.net/thread/5161/problem-sso-currency) ·
  [Forum „Not Enough SC“](https://ssoforums.freeforums.net/thread/3813/feel-get-sc-pay) ·
  [Ginny O. Elternkritik](https://ginny0.wordpress.com/2018/06/26/tuesdaythoughts-parents-and-players-dont-play-star-stable/) ·
  [Screenwise Parent Review](https://screenwiseapp.com/media/star-stable-online-app) ·
  [Game Brain SSO](https://gamebrain.co/game/star-stable-online)
- Star Stable Horses (Fohlen-App): [App Store](https://apps.apple.com/us/app/star-stable-horses/id1126342383) ·
  [Google Play](https://play.google.com/store/apps/details?id=com.starstable.horses&hl=en_US)
- Rival Stars Horse Racing: [Gaming Debugged Review](https://www.gamingdebugged.com/2026/05/17/review-rival-stars-horse-racing-xbox/) ·
  [TMQ-Datenbank](https://horsegamedatabase.miraheze.org/wiki/Rival_Stars_Horse_Racing) ·
  [PS4Blog-Review](https://www.ps4blog.net/2026/04/playstation-5-rival-stars-horse-racing-review/) ·
  [RSHR-Update-Blog (Perfect-Jump, Kamera)](https://www.rivalstarshorseracing.com/post/mobile-update-1-58-the-mustang-and-canyon-falls)
- Alicia Online: [The Mane Quest Review](https://www.themanequest.com/blog/2018/10/2/alicia-online) ·
  [TMQ-Datenbank](https://horsegamedatabase.miraheze.org/wiki/Alicia_Online) ·
  [Horse Plains „Why is Alicia so Unique“](https://www.horseplains.com/articles/why_is_alicia_online_so_unique)
- Equestrian the Game: [TMQ-Datenbank](https://horsegamedatabase.miraheze.org/wiki/Equestrian_the_Game) ·
  [Medium-Review (Energie/Preise)](https://medium.com/@quest.equestrians/review-equestrian-the-game-a2af3c7bcc57) ·
  [App-Store-Reviews](https://apps.apple.com/ca/app/equestrian-the-game/id1468871996?platform=iphone&see-all=reviews)
- My Horse Stories: [Game Brain (Ads/Energie/Content-Ende)](https://gamebrain.co/game/my-horse-stories-1) ·
  [AppRecs-Reviews (Outfit-Paywall)](https://apprecs.com/ios/1447798697/my-horse-stories) ·
  [Geeky Sweetie Review](https://geekysweetie.com/my-horse-stories-horse-sim-game-review/)
- Horse Club Adventures 1+2: [The Mane Quest HCA1](https://www.themanequest.com/blog/2021/6/6/review-horse-club-adventures-a-wholesome-summer-retreat-with-suboptimal-animations-and-controls) ·
  [The Mane Quest HCA2](https://www.themanequest.com/blog/2025/6/14/review-horse-club-adventures-2-hazelwood-stories-convinces-with-cozy-vacation-vibes-and-improved-horse-animation) ·
  [Wild River Feature-Liste (90 Strecken, Sticker)](https://wildriver.games/en/games/horseclub-adventures-en/) ·
  [Game Brain HCA](https://gamebrain.co/game/horse-club-adventures)
- The Ranch of Rivershine: [The Mane Quest „Almost Perfect“](https://www.themanequest.com/blog/2025/11/16/review-the-ranch-of-rivershine-an-almost-perfect-horse-game-and-what-we-can-learn-from-it) ·
  [NoobFeed-Review](https://www.noobfeed.com/reviews/the-ranch-of-rivershine-review) ·
  [Cozy Escapism](https://cozyescapism.com/the-ranch-of-rivershine/) ·
  [Rivershine-Wiki Potential](https://rivershine.miraheze.org/wiki/Potential)
- RDR2 Pferde-Bindung: [Fextralife-Wiki](https://reddeadredemption2.wiki.fextralife.com/Horse_Bonding) ·
  [Eurogamer-Guide](https://www.eurogamer.net/red-dead-redemption-2-best-horse-bonding-horses-explained-4975) ·
  [GameRevolution](https://www.gamerevolution.com/guides/453025-red-dead-redemption-2-horse-bonding-perks-items) ·
  [GTABase-Pflege-Guide](https://www.gtabase.com/red-dead-redemption-2/guides/full-guide-looking-after-your-horse-in-red-dead-redemption-2)
- Zelda BotW Zähmung: [Zelda Dungeon Wiki](https://www.zeldadungeon.net/wiki/Horse_(Breath_of_the_Wild)) ·
  [GameFAQs Horse-Stats-Guide](https://gamefaqs.gamespot.com/switch/189707-the-legend-of-zelda-breath-of-the-wild/faqs/74764/horse-stats) ·
  [IGN Taming-Guide](https://www.ign.com/wikis/the-legend-of-zelda-breath-of-the-wild/How_to_Tame_a_Horse)
- Horse Haven (Community-Wünsche): [App-Store-Reviews](https://apps.apple.com/us/app/horse-haven-world-adventures/id704506972)
- Genre-Überblick: [The Mane Quest — Best Horse Games 2025](https://www.themanequest.com/blog/2024/10/30/the-best-horse-games-to-play-on-pc-and-console-in-2025)

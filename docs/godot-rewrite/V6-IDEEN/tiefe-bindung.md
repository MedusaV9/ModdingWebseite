# V6-IDEEN — Lens „TIEFE, BINDUNG & SYSTEME" (Ideen-Agent 2/2)

Stand: 8. August 2026 · Branch `cursor/gooby-godot-loop-2-d1d8`

Quellen: `docs/godot-rewrite/EVAL-2026-08/A-gameplay.md` (Progression **5,5**
— „Progressionskohärenz ist der neue Engpass"; Multiplayer **4,5** — localhost-
Default, Offline-100% unmöglich; Reward-Monotonie der 38 Minispiele; Ranch zu
spät; 24-/48-h-Wartesperren), `USER-WISHES.md`, `GOOBY-GODOT/scripts/soul/`
(SoulService/SoulMood/SoulIntent/SoulMemories/SoulFeelings, Slice `soul`),
`save_schema.gd` (Slice-Registry: additive Top-Level-Slices ohne Version-Bump).

Leitfrage der Lens: **Wie wird aus „viel Content" ein Spiel mit Sog?**
Antwort in drei Schichten: (1) alles zahlt sichtbar auf EIN Meta-Ziel ein,
(2) die Beziehung Spieler↔Gooby entwickelt sich über Wochen wirklich,
(3) jede Aktivität hinterlässt eine einzigartige Spur in Welt oder Album.

Format je Idee: Titel · Konzept (3–4 Sätze) · Eval-Befund · Systeme
(Save-Slices/Services) · Aufwand (S/M/L/XL) · Score 1–10 (Bindungs-Impact).

---

## A) Progression & Meta-Ziele

### 1. „Goobys Jahr" — die Kapitel-Kampagne (Progressions-Baum)

**Konzept:** Eine 16-Kapitel-Zielkette über vier erzählte Jahreszeiten
verbindet die vorhandenen Systeme in fester Dramaturgie: Frühling
(Ankommen, Garten, erste Stadtwege), Sommer (Reisen, Funkelpark, Arcade),
Herbst (Ranch, Ernte, Markt), Winter (Feste, Freunde, Rückblick). Jedes
Kapitel hat 3–5 Ziele, die aus BESTEHENDEN Leisten gespeist werden (Erfolge,
Sticker, Arcade-Sterne, Quests zahlen als Fortschritt ein statt parallel zu
laufen), und endet mit einer sichtbaren Weltänderung oder neuen Fähigkeit.
Der Kapitel-Stand ist der neue rote Faden im Profil und ersetzt den
Quotendurchschnitt als gefühlten „Spielstand". Kapitel sind offline-first
und ohne DLC-Kauf abschließbar (DLC-Kapitel als optionale Seitenäste).
**Eval-Befund:** Progression 5,5; Prio 3 „viele Leisten, aber keine klare
Kampagne"; Schlussfazit 1 „klare, emotionale Langzeitreise statt paralleler
Checklisten". **Systeme:** neuer additiver Slice `kampagne`
(`SaveSchema.register_slice`), neue Content-Domain `content/kampagne`,
`QuestEngine`/`QuestService`, `WhatsNextAdvisor`, `AbschlussLogic`,
`SoulService` (Kapitel-Momente), Profil/HUD. **Aufwand:** XL ·
**Score:** 10

### 2. Freischalt-Matrix-Rework: „Früh zeigen, spät besitzen"

**Konzept:** Die Freischalt-Reihenfolge wird vom Level-Gate auf das Prinzip
„Erlebnis früh, Besitz später" umgestellt: Ranch-Schnupperkapitel ab Level
5–6 (Leihpferd, eine offene Zone, erste NPC-Begegnung), der Kauf schaltet
danach Besitz frei (Ausbau, eigene Herde, Wettbewerbe). McGoobys
Probeschicht öffnet einen Rabattpfad (jede Schicht senkt den Kaufpreis),
Goo-und-Bye bekommt einen Schaufenster-Besuch vor dem Kauf. Alle Gates
hängen künftig an Kapiteln aus Idee 1 statt an rohen XP-Schwellen.
**Eval-Befund:** Finding 6 „Ranch ist der stärkste Inhalt, kommt aber sehr
spät" (Level 15 = 5.950 XP ≈ 238 Max-XP-Runden); Prio 5. **Systeme:**
`content/ranch/data/balance.json`, `content/dlc/data/dlcs.json`,
`Leveling`, `RanchState`/`rquest_state`, DLC-Angebots-UI, Economy-Tests.
**Aufwand:** M · **Score:** 9

### 3. Nordstern-HUD: der EINE nächste Schritt

**Konzept:** Der vorhandene `WhatsNextAdvisor` wird vom versteckten Helfer
zum sichtbaren Meta-Kompass: Im HUD/Questblatt steht genau EIN empfohlenes
Meta-Ziel („Nordstern") mit Begründung in Goobys Stimme („Ich würd so gern
mal echte Pferde sehen…"). Antippen routet direkt zum Inhalt; erledigte
Nordsterne werden im Erinnerungsalbum verewigt. Der Nordstern speist sich
aus Kapitel-Stand, Bond-Level und offenen Leisten — nie mehr als einer
gleichzeitig, damit die Systembreite nicht wieder zur Featureliste wird.
**Eval-Befund:** Progression 5,5 „keine klare Priorität"; Stunde-1-Befund
„der Spieler lernt Funktionen, aber nicht, warum sein Gooby diese Ziele
verfolgen soll". **Systeme:** `WhatsNextAdvisor`, `QuestService`, HUD/
IGohbie-UI, `GoobyGespraech`/`SoulLinien`, Slice `kampagne`. **Aufwand:** M
· **Score:** 8

### 4. Level-Aufstieg als Zeremonie mit konkretem Unlock

**Konzept:** Jedes der 40 Level erhält einen benannten, konkreten Unlock
(Interaktion, Ort, Fähigkeit, Rezept) auf einem sichtbaren Baum — kein
leeres Level mehr. Der Aufstieg wird als kleines Ritual MIT Gooby gefeiert
(Konfetti-Moment, eine Zeile von ihm, Album-Eintrag) statt als
Zahlen-Overlay. Der Baum zeigt die nächsten zwei Unlocks als Vorfreude an.
**Eval-Befund:** „Level-Gates sind grindig, Belohnungen oft nur mehr
Coins/Zähler" (Progression 5,5). **Systeme:** `Leveling`, Slice
`progression`, neue Unlock-Tabelle in `content/leveling`, `SoulService`
(Ritual-Def), Reward-Hub/Overlay-Dirigent. **Aufwand:** M · **Score:** 8

### 5. Weltverändernde Meilenstein-Belohnungen

**Konzept:** Kapitel- und Meilenstein-Abschlüsse verändern die Welt sichtbar
und dauerhaft: Der Stadtplatz bekommt einen Brunnen, das Haus einen
Balkon-Rohbau, der Garten ein Festtor, NPCs referenzieren die Tat in
Dialogen. Belohnungen dokumentieren damit nicht mehr nur Verhalten, sondern
verändern den Ort, an dem die nächste Entscheidung fällt. Jede Weltänderung
hat einen „Weißt du noch?"-Hook für `SoulMemories`. **Eval-Befund:** „zu
selten verändert eine Belohnung die nächsten spielerischen Entscheidungen";
Woche 2 „wenig weltverändernde Belohnung". **Systeme:** Slices `city`,
`home`, `decor`, `kampagne`; `CityState`, `HomeState`, `SoulMemories`,
Szenen-Varianten. **Aufwand:** L · **Score:** 9

### 6. Abschluss 2.0: Basis / Zusammen / DLC / Meister als getrennte Medaillen

**Konzept:** `AbschlussLogic` wird in vier Medaillen zerlegt: **Basis**
(offline, ohne DLC, 100 % solo erreichbar), **Zusammen** (alle Online-/
Social-Ziele als Bonus-Medaille), **DLC** (je DLC ein Rang) und **Meister**
(Arcade-Sterne gestaffelt: Bronze = alle gespielt, Silber = 60 Sterne,
Gold = 90). Das Profil zeigt jede Komponente aufklappbar mit fehlenden
Anforderungen und Direkt-Route. Alt-Saves werden migriert, bereits
verdiente Prozente bleiben erhalten. **Eval-Befund:** Finding 4
„Offline-Spieler können 100 % nicht erreichen"; Prio 2, Prio 10, Prio 16.
**Systeme:** `AbschlussLogic`, `ArcadeFortschritt`,
`content/stickers/data/stickers.json` (Kategorie-Tags), Profil-Screen,
Migrations-/Abschluss-Tests. **Aufwand:** M · **Score:** 9

---

## B) Lebensphasen & Erinnerung

### 7. Gooby-Lebensphasen: Nestling → Wirbelwind → Teenie → Gefährte

**Konzept:** Gooby wächst über reale Wochen (injizierte `Clock`, kein
OS-Uhr-Hack) durch vier Phasen mit eigenen Silhouetten-Details
(Proportionen via `meta.charMorphs`-Layer), Stimm-Pitch, Idle-Verhalten und
je EINER exklusiven Phasen-Interaktion (Nestling: einschlafen auf dem Arm;
Teenie: Augenrollen mit Versöhnungs-Moment). Übergänge werden als Ritual
gefeiert, nie bestraft — nichts geht verloren, alles wandert ins
Erinnerungsalbum. Phasen färben Mood/Intent (Teenie will mehr Abenteuer,
Nestling mehr Nähe), sodass sich derselbe Care-Loop über Wochen anders
anfühlt. **Eval-Befund:** Care 7,5 „es fehlen belastbare Beziehungen und
Entscheidungen mit längerem Nachhall"; Schlussfazit „emotionale
Langzeitreise". **Systeme:** neuer Slice `phasen` (oder `soul`-Erweiterung),
`SoulState`/`SoulService`/`SoulMood`/`SoulIntent`, `SeeleRunner`,
`GoobyTicker`, Character-Rig. **Aufwand:** XL · **Score:** 10

### 8. Erinnerungsalbum „Unser Buch"

**Konzept:** Ein automatisch wachsendes Tagebuch macht die gemeinsame Zeit
anfassbar: `SoulMemories`-Ereignisse, Erste-Male, Phasenfotos,
Kapitel-Enden und Nordstern-Erfolge werden zu Buchseiten mit Datum, Foto
und einem Gooby-Kommentar. Seiten sind im Profil durchblätterbar; alte
Seiten können „nochmal angeschaut" werden und triggern eine kleine
nostalgische Reaktion. Das Buch ist der emotionale Gegenpol zu
Zähler-Completion — es erzählt, WAS passiert ist, nicht wie oft.
**Eval-Befund:** „Beschäftigung, aber noch keine starke persönliche
Geschichte"; Woche 2 „Album und Zähler liefern Completion, aber wenig
Bedeutung". **Systeme:** `SoulMemories`, Slices `recap`, `gallery`,
`camera`, `kampagne`; neues UI `ui/album/erinnerungen`. **Aufwand:** L ·
**Score:** 9

### 9. Phasen-Andenken: nichts geht verloren

**Konzept:** Endet eine Lebensphase, materialisiert sich genau ein Andenken
als platzierbare Deko (Babydecke, erster Wackelzahn im Glas, zu klein
gewordene Mütze). Gooby kommentiert das Andenken nostalgisch, wenn er daran
vorbeiläuft (`SoulIntent`-Ziel + Memory-Line). Andenken sind unverkäuflich
und machen das Haus zur sichtbaren Biografie. **Eval-Befund:**
Bindungs-Lücke des Care-Loops; „Möbel sind überwiegend Ausdruck, nicht
Bedeutung". **Systeme:** Slices `home`, `decor`, `soul`; `SoulMemories`,
`SoulService`, IKEA-/Storage-Ausnahmelogik. **Aufwand:** S · **Score:** 8

### 10. Gooby-Träume & Traumtagebuch

**Konzept:** Während Gooby schläft, träumt er von seinem echten Tag (aus
`recap`-/Memory-Daten): Über dem Bett schwebt eine leise Gedankenblase, in
die man hineinspicken kann. Seltene Träume (nach besonderen Tagen) schalten
Traum-Sticker und Albumseiten frei; wer den Traum stört, erlebt einen
verschlafenen Protest-Moment. Träume machen die Schlafphase zur
Bindungszeit statt zur toten Zeit. **Eval-Befund:** Tagesloop braucht
Überraschung; Care nachts folgenlos. **Systeme:** `gooby.sleep`,
`story_time`/Slice `story`, `SoulMemories`, Slices `stickers`, `recap`.
**Aufwand:** M · **Score:** 7

---

## C) Beziehungstiefe & Bedürfnis-Evolution

### 11. Vertrauens-Band: Bond-Level 1–10

**Konzept:** Ein sichtbares Vertrauens-Band wächst durch VIELFALT und
gehaltene Versprechen, nicht durch rohes Grinden (dieselbe Aktion in Serie
zahlt fast nichts). Jedes Bond-Level schaltet eine NEUE Interaktion frei:
Huckepack (3), gemeinsames Kochen (4), High-Five-Ritual (5), Geheimnisse
(6), Mitternachtssnack zu zweit (7), Nachtwanderung (8), „bester Freund"-
Zeremonie (10). Vertrauen verfällt nie — es stagniert nur ohne Abwechslung,
damit kein Schuldgefühl entsteht. Das Band ist der Beziehungs-Zwilling zum
Kapitelbaum: Kapitel = was ihr erlebt, Bond = wer ihr einander seid.
**Eval-Befund:** Care 7,5 „langfristig lineares Balken-Auffüllen …
Seele-Texte ersetzen keine Entwicklung der Beziehung"; Prio 12.
**Systeme:** `soul`-Slice-Erweiterung (`bindung`), `SoulMood`/`SoulState`,
`GoobyGespraech`, Home-Interactables, HUD-Band-Anzeige. **Aufwand:** L ·
**Score:** 10

### 12. Huckepack & Mitnehm-Modus

**Konzept:** Ab Bond-Level 3 kann man Gooby huckepack durch Haus, Garten
und Stadt tragen: Er zeigt auf Dinge (`SoulIntent`-Ziele), kommentiert Orte
und wird an besonderen Stellen zum Mikro-Moment-Auslöser (am Schaufenster:
„Ooooh"). Orte bekommen dadurch Bindungswert statt Transaktionswert; einige
Foto-Posen und Sticker gibt es nur huckepack. **Eval-Befund:** Stadt 6,5
„Großteil der Orte ist Transaktions- oder Menüstation"; Care-Routine.
**Systeme:** Character-Controller, City-/Home-Szenen, `SoulIntent`/
`SoulLinien`, Bond-Gate (`soul`), `camera`. **Aufwand:** M · **Score:** 8

### 13. Gemeinsames Kochen

**Konzept:** Ab Bond-Level 4 öffnet die Küche ein Koch-Ritual: Rezept
gemeinsam aussuchen, Gooby rührt/kostet/kleckert (echte Assist-Animationen),
das Ergebnis ist ein Gericht mit Buff und Erinnerungswert. Rezepte kommen
aus Garten, Wochenmarkt und Reisen — Kochen wird der Sink, der diese
Systeme verbindet. Lieblingsgerichte entstehen aus echten Daten
(`foodGiven`) und Gooby wünscht sie sich aktiv (`wunsch`-Muster).
**Eval-Befund:** „Systeme laufen nebeneinander statt miteinander";
Reward-Monotonie. **Systeme:** `inventory.food`/`FoodCatalog`, Slice
`buffs`, `soul` (Vorlieben/Wünsche), neues Küchen-Interactable,
`kampagne`-Hooks. **Aufwand:** L · **Score:** 9

### 14. Geheimnisse & kleine Versprechen

**Konzept:** Ab Bond-Level 6 vertraut Gooby dir Geheimnisse an (sein
verstecktes Lieblingsplätzchen, seine Angst vor Gewitter) und bittet um
kleine Versprechen („Weckst du mich morgen sanft?", „Gehen wir diese Woche
in den Park?"). Gehaltene Versprechen zahlen Vertrauen und einzigartige
Reaktionen; gebrochene kosten nichts, bekommen aber einen leisen, traurigen
Callback — Nachhall statt Strafe. Geheimnisse schalten versteckte
Interaktionspunkte frei (der Lieblingsplatz wird anklickbar).
**Eval-Befund:** Care ohne „Entscheidungen mit längerem Nachhall";
Tagesquests ohne Situationen. **Systeme:** `soul`-Slice
(`wunsch`-Muster erweitert um `versprechen`), `SoulService`/`SoulFeelings`,
`GoobyGespraech`, `events`. **Aufwand:** M · **Score:** 9

### 15. Bedürfnis-Evolution: Kreativität & Abenteuerlust

**Konzept:** Ab definierten Kapitel-/Bond-Schwellen erweitern zwei sanfte
Bedürfnisse das 4er-Set: **Kreativität** (malen, bauen, Musik, Fotos) und
**Abenteuerlust** (neue Orte, Reisen, zum ersten Mal gespielte Spiele). Sie
verfallen langsam, sind nie gesundheitskritisch und färben vor allem
Stimmung und Intent („Gooby kritzelt gelangweilt auf einem Zettel"). Damit
bekommen vorhandene Aktivitäten eine zweite Bedeutung: Das 30. Minispiel
füllt keinen Spaß-Balken mehr, sondern stillt Abenteuerlust — und Gooby
sagt dir, worauf er Lust hat. **Eval-Befund:** Care „langfristig lineares
Balken-Auffüllen"; „Auswahl fühlt sich effizient statt persönlich an".
**Systeme:** `Stats` (`gooby.stats` additiv + Normalisierung),
`SoulIntent`/`SoulMood`, `GoobyTicker`/`offline.gd`, HUD, Balance-Tests.
**Aufwand:** L · **Score:** 9

### 16. Pflege-Gewohnheiten & abnehmende Wirkung

**Konzept:** Die identische Care-Antwort in Serie verliert sanft an Wirkung
(nie unter ~60 %), Abwechslung und Rituale gewinnen: Gooby entwickelt
sichtbare Vorlieben (Lieblingswaschzeit, Essens-Abwechslungsbonus,
Streichel-Ritual nach dem Aufwachen), die aus echten Daten wachsen und im
Album dokumentiert werden. Die optimale Pflege ist damit nicht mehr
vorhersehbar, sondern persönlich — jeder Gooby „spielt sich anders".
**Eval-Befund:** Prio 12 „Care wird zum linearen Balkenservice; die
richtige Reaktion ist fast immer eindeutig". **Systeme:** `stats.gd`,
`health.gd`, `soul` (`foodGiven`, Vorlieben), `SoulMemories`,
Interactables. **Aufwand:** M · **Score:** 8

### 17. Vertrauens-Autonomie: Gooby hilft sich selbst

**Konzept:** Ab hohem Bond löst Gooby kleine Bedürfnisse gelegentlich
selbst (holt sich eine Karotte aus dem gefüllten Kühlschrank, legt sich
müde von allein ins Bett) und erzählt dir hinterher stolz davon. Der
Spieler ermöglicht das über Ausstattung (Vorräte, erreichbare Wege) — aus
Mikromanagement wird Fürsorge-Infrastruktur und das Gefühl, dass jemand
GROSS wird. Selbstständigkeit bleibt selten genug, dass aktives Kümmern
der Normalfall bleibt. **Eval-Befund:** Care-Routine „Balken sehen,
Station antippen, Animation abwarten"; Woche-2-Monotonie. **Systeme:**
`SoulIntent`, `GoobyTicker`, Slice `inventory`, `soul`/Bond-Gate,
Home-Interactables. **Aufwand:** M · **Score:** 8

---

## D) Minigame-Reward-Diversifizierung

### 18. Reihen-Handwerk: einzigartige Belohnungsschienen je Arcade-Reihe

**Konzept:** Die sechs `ArcadeFortschritt`-Reihen erhalten je eine eigene
Belohnungsschiene mit echtem Sink statt Coins/XP-Einheitsbrei:
Geschick & Timing → **Möbel-Blaupausen** (Werkstatt), Tempo & Action →
**Stadt-Deko-Teile**, Fahren & Liefern → **Fahrzeugteile/Lackierungen**,
Puzzle & Denken → **Sticker-Serien**, Ranch & Turnier → **Ranch-Ausrüstung**,
Ruhig & Gemütlich → **Garten-Rezepte**. Die Schiene füllt sich über Sterne
und Spezialziele, nicht über Wiederholungs-Grind; jede Reihe hat ein
sichtbares Endstück (z. B. das Blaupausen-Regal). Damit beantwortet jedes
Spiel die Frage „Warum DIESES nochmal spielen?" unterschiedlich.
**Eval-Befund:** Finding 10 / Prio 11 „38 Spiele teilen zu stark denselben
Metarahmen — Minispiele teilen zu stark denselben Reward-Loop".
**Systeme:** `MinigameAward`, `ArcadeFortschritt`, Slice `minigames`
(neue Schienen-Zähler), Content-Kataloge (IKEA/Werkstatt/Autohaus/Garten),
Save-Schema-Tests. **Aufwand:** XL · **Score:** 9

### 19. Story-Schnipsel: die GOB-Chroniken

**Konzept:** Jedes Minispiel versteckt 3–5 Chronik-Schnipsel (freigespielt
über Sterne, Spezialziele oder Erst-Erlebnisse), die im Album zu kleinen
animierten Episoden über Goobys Welt zusammengesetzt werden — wer war der
Nougat-Schmuggler? Warum heißt der Funkelpark Funkelpark? Schnipsel sind
der narrative Reward-Typ, der Arcade-Breite mit der Erzählschicht aus
Kapitel/Album verbindet. Komplette Episoden schalten je einen
GOB.TY-Kurzclip frei. **Eval-Befund:** Prio 11; „keine starke persönliche
Geschichte". **Systeme:** Slice `minigames`, `MinigameAward`,
`collections`, neues Chroniken-UI, Content-Domain `content/chroniken`,
GOB.TY. **Aufwand:** L · **Score:** 8

### 20. Meister-Fähigkeiten: Arcade zahlt in die Welt

**Konzept:** Drei Sterne in einem Spiel schalten eine kleine, dauerhafte
Welt-Fähigkeit frei, die thematisch zum Spiel passt: City-Drive-Meister
bekommt eine Stadt-Abkürzung, der Surf-Meister eine Strand-Pose im
Fotomodus, der GvZ-Meister eine Nutella-Deko-Serie, der Schach-Meister ein
neues Brettdesign. Meisterschaft erzeugt damit Identität („Ich bin der
Fahr-Profi") statt nur Sterne-Zähler. Die Fähigkeiten sind bewusst klein
und kosmetisch-funktional, nie Pay-to-Progress. **Eval-Befund:**
Arcade-Schleife: „Ein Spieler meistert ein Spiel nicht, um ein
einzigartiges Werkzeug oder eine neue Weltfähigkeit zu erhalten".
**Systeme:** `ArcadeFortschritt`, Mapping-Tabelle Spiel→Fähigkeit
(Content), Slices `city`/`home`/`camera`/`cosmetics`. **Aufwand:** L ·
**Score:** 8

### 21. Sticker-Seiten mit Payoff

**Konzept:** Das Vollmachen einer Album-SEITE (Themen-Serie) wird zum
Ereignis: Es gibt eine greifbare Belohnung (Deko-Set, neue Interaktion,
Soul-Moment mit Gooby, der die Seite bewundert) und eine kleine
Seiten-Zeremonie statt stiller Completion. Die Erfolgs-Staffelung wird
semantisch repariert (28 = „Erste Albumseite", 84 = „Sammler", echter
Katalogabschluss dynamisch aus `regular_count`). **Eval-Befund:** „Erfolge
und Sticker dokumentieren Verhalten, verändern es aber selten"; Prio 15
(falsche `stickerBookFull`-Semantik). **Systeme:** Slices `stickers`,
`collections`, `achievements`; Achievements-Engine, Reward-Hub,
`SoulService`. **Aufwand:** M · **Score:** 7

---

## E) Multiplayer-Rework & Offline-Fairness

### 22. Server-Wahl-UX: „Verbinden in 60 Sekunden"

**Konzept:** Der erste Social-Einstieg wird ein geführter Flow statt
Host/Port/Secret-Formular: offizielle Serverliste per Remote-Config über
das Update-System (ohne .ipa-Wechsel änderbar, wie in USER-WISHES B/C
gefordert), Beitritt per QR-/Invite-Link, Verbindungstest mit
Ampel-Ergebnis und Klartext-Erklärung, was offline trotzdem geht. Ohne
konfigurierten Server verschwinden alle Online-Lockrufe (Sticker-CTAs,
Menüpunkte) statt zu frustrieren. **Eval-Befund:** Multiplayer 4,5 /
Prio 1 „zeigt standardmäßig auf `127.0.0.1:8765`; Spieler kennt weder Host,
Port noch Join-Secret"; Prio 19. **Systeme:** `NetClient.DEFAULT_NET`,
`content/config`, `mehrspieler_sektion`, Updates-Modul (Remote-Config),
`HostGate`, `net_status_indicator`. **Aufwand:** L · **Score:** 9

### 23. Freundes-Onboarding: „Der Gooby-Brief"

**Konzept:** Freundschaft beginnt als Gegenstand: Eine Einladung wird als
teilbarer Brief verschickt (Link/QR mit eingebettetem Freundescode), beim
Empfänger liegt sie als echter Brief in der Post und wird mit einer
Annehm-Zeremonie geöffnet (beide Goobys freuen sich beim nächsten Login).
Die erste gemeinsame Session ist geführt: Besuch → Emote → gemeinsames
Foto, damit der Wert von Freundschaft sofort erlebbar ist.
**Eval-Befund:** Multiplayer 4,5 — technisch breit, produktseitig nicht
zugänglich; Social-Tour-Bedarf (Prio 19). **Systeme:** `FriendsService`,
`NetMail`/`Outbox`, Post-Ort, `presence`, Social-Tour-UI,
`SnapAGooby`. **Aufwand:** M · **Score:** 8

### 24. Asynchrone Besuche mit Gästebuch

**Konzept:** Das Haus eines Freundes wird als Snapshot besuchbar, auch wenn
der Freund offline ist (`VisitSnapshot` wird server-seitig gecacht):
Besucher hinterlassen einen Gästebuch-Eintrag, ein Foto oder ein kleines
Geschenk; der Gastgeber-Gooby erzählt beim nächsten Login aufgeregt davon.
Multiplayer braucht damit keine Gleichzeitigkeit mehr — genau richtig für
ein Cozy-Spiel mit kleiner Spielerschaft. Gästebuch-Seiten wandern ins
Erinnerungsalbum. **Eval-Befund:** Multiplayer 4,5; Offline-first-Wunsch
(USER-WISHES C); „Social-Loops standardmäßig offline". **Systeme:**
`VisitService`/`VisitSnapshot`, `Outbox`/`NetMail`, Slice `home`
(`gaestebuch`), `SoulService`, GOOBY-SERVER-Modul. **Aufwand:** L ·
**Score:** 9

### 25. Koop-Wochenziele: „Gemeinsam schaffen wir das"

**Konzept:** Wöchentliche Paar-/Gemeinschaftsziele („Erntet zusammen 50
Karotten", „Sammelt 30 Arcade-Sterne") mit asynchroner Beitragszählung —
jeder spielt, wann er will, der Server addiert. Belohnung ist geteilte Deko
plus ein gemeinsamer Album-Moment; Solo-Spieler bekommen ein gleichwertiges
Solo-Wochenziel, damit keine Fairness-Lücke entsteht. **Eval-Befund:**
Multiplayer ohne wiederkehrenden Produkt-Anlass; Tagesloop-Pflichtzettel.
**Systeme:** `ServerEvents`, `FriendsService`, `QuestEngine`
(Wochenziel-Typ), Slice `daily`-Erweiterung, GOOBY-SERVER. **Aufwand:** L ·
**Score:** 7

### 26. MP-Trophäen als Bonus-Kategorie („Zusammen"-Regal)

**Konzept:** Alle Online-bedingten Sticker und Erfolge (`chess_online`,
`chess_win`, `chess_rematch` …) wandern in eine eigene, klar markierte
„Zusammen"-Kategorie, die niemals Basis-100 % blockiert — sie ist das
Bonus-Regal für Spieler mit Freunden. Jede Basis-Trophäe ist offline und
solo erreichbar; das Album kennzeichnet die Kategorien farblich und blendet
„Zusammen" ohne konfigurierten Server dezent aus. Alt-Saves behalten
verdiente Online-Sticker selbstverständlich. **Eval-Befund:** Finding 4
„Offline-Spieler können 100 % nicht erreichen"; Prio 2. **Systeme:**
`content/stickers/data/stickers.json` (Kategorie-Tag), `AbschlussLogic`,
`achievements`, Album-UI, `net_status`. **Aufwand:** M · **Score:** 8

### 27. Besucher-System zuhause: NPCs klingeln

**Konzept:** Auch ohne Server wird das Haus sozial: NPCs aus Stadt und
Ranch klingeln gelegentlich an der Tür (Onkel Alwin bringt Reste vom
Markt, die Ranch-Nachbarin sucht ihr Huhn), bringen Mini-Aufträge,
Tauschangebote oder Geschichten mit. Seltene Besucher (der Zirkus-Gooby,
der Sternengucker) sind Überraschungsmomente mit exklusiven Stickern.
Besuche nutzen das Random-Event-Zeitfenster-Muster (Push + 5–10 min), das
die USER-WISHES bereits definieren. **Eval-Befund:** „zu wenig tägliche
Weltveränderung: besondere NPC-Konstellationen … kleine Entscheidungen";
Stadt-NPCs ohne Beziehung. **Systeme:** `RandomEventEngine`/Slice `events`,
City-NPC-Defs, Home-Szenen (Tür), `SoulService`, `QuestService`,
`notify_stub`. **Aufwand:** L · **Score:** 8

---

## F) Wartesperren-Redesign & Zeit-Rhythmus

### 28. Warteziel-Redesign: „Warten ODER Anpacken"

**Konzept:** Jedes `warte_bis`-Ziel (8/24/48 h) in den Ranch-Quests erhält
einen gleichwertigen aktiven Pfad, der es sofort abschließt: ein
Pflege-Minispiel, eine Materialsuche in der offenen Welt, NPC-Hilfe gegen
Herzen oder eine Skill-Challenge. Warten bleibt die gemütliche Option
(cozy!), Spielen wird die schnelle — niemand wird mehr zum bewussten
Nichtspielen gezwungen. Das Muster wird als wiederverwendbarer Quest-Typ
gebaut, damit künftige Content-Wellen es erben. **Eval-Befund:** Finding 9
/ Prio 7 „Ranch-Quests enthalten 24-/48-Stunden-Sperren, aber keine
gleichwertige aktive Alternative". **Systeme:**
`content/ranch_quests/data/ranch_quests.json` (Alternative-Feld),
`rquest_state`/`rquest_slices`, Ranch-NPCs, Quest-UI. **Aufwand:** M ·
**Score:** 9

### 29. Tages-Überraschungs-Slot: „Heute ist anders"

**Konzept:** Jeder Tag zieht garantiert EINE Überraschung aus einem
gewichteten Pool: seltener Wettermoment, Besucher, Fundstück im Garten,
Gooby-Einfall, Mini-Event, Doppel-Spotlight — nie zweimal dasselbe an
aufeinanderfolgenden Tagen (injizierter RNG, testbar). Die Überraschung
steht NICHT auf dem Questblatt; sie passiert und wird dadurch zur
Geschichte des Tages. Ein „Heute war…"-Eintrag landet abends im Album.
**Eval-Befund:** Tagesloop „droht zum Pflichtzettel zu werden"; Tag 3
„Tagesquests offenbaren ihre Counter-Struktur". **Systeme:**
`RandomEventEngine`, `SoulService`/`soul_wetter`, Slice `daily`,
Content-Pool `content/ueberraschungen`, Album. **Aufwand:** M ·
**Score:** 8

### 30. Wochen-Dramaturgie: Feste & wiederkehrende Anlässe

**Konzept:** Über den Wochenmarkt hinaus bekommt die Woche eine Dramaturgie:
Freitags-Kino im GOB.TY (neuer Clip + Snack-Ritual), Sonntags-Parkfest im
Funkelpark (Stempelpass-Bonus, Feuerwerk), monatliches Stadtfest mit
exklusiven Momenten und eigener Albumseite. Anlässe werden diegetisch
angekündigt (NPC-Gespräche, Radio, Plakate) statt per Popup — die Stadt
bekommt Gründe, dieselben Straßen neu zu lesen. **Eval-Befund:** Stadt 6,5
„kein Grund, dieselben Straßen jenseits einzelner Besorgungen neu zu
lesen"; Prio 14 (Funkelpark nach Erstbesuch ausgeschöpft). **Systeme:**
Slices `city`, `park`, `radio`; `events`, Content-Domain `content/feste`,
GOB.TY, Radio/recap-fm. **Aufwand:** L · **Score:** 8

### 31. Timer als Vorfreude: Lebenszeit-Fenster statt toter Uhren

**Konzept:** Verbleibende Timer (Gartenwachstum, Bestellungen, Taxi) werden
an Tageszeiten und einen sichtbaren „Tagesbogen" gebunden: Die Lieferung
kommt morgens, die Ernte glitzert abends, das Taxi meldet sich kurz vor
Ankunft (Live-Activity-Wunsch aus USER-WISHES C). Wartezeit wird planbare
Vorfreude mit sanften Erinnerungs-Pings statt eines stummen Countdowns.
Alle Fenster laufen über die injizierte `Clock` und bleiben damit testbar.
**Eval-Befund:** Wartesperren-Befund generalisiert; „24-/48-Stunden-
Ranchziele ersetzen Spielen durch Warten". **Systeme:** `Clock`/
`GoobyTicker`, Slice `garden`, `notify_stub`/Platform, HUD-Tagesbogen.
**Aufwand:** M · **Score:** 7

---

## G) Langzeit: Generationen, Profile & Fotomodus

### 32. Generationen-System „Goobys Erbe" (New Game+)

**Konzept:** Nach dem Finale von „Goobys Jahr" optional: Ein junger
Zweit-Gooby (Cousin!) zieht ein und startet die Reise neu — Haus, Deko und
Andenken bleiben, Erbstücke geben kleine Startgeschenke, und der große
Gooby bleibt als Mentor-NPC präsent (kommentiert, hilft, erinnert sich).
Der zweite Durchlauf remixt Regeln über Playstyle-Modifikatoren statt
Content zu wiederholen. Kein Zwang, kein Verlust: Wer nicht will, spielt
mit seinem Gefährten einfach weiter. **Eval-Befund:** Woche 2 „zu wenig
davon verändert die Bedeutung der nächsten Woche"; Langzeitziel jenseits
Checklisten. **Systeme:** `meta`/SaveManager (Multi-Gooby-Struktur),
`soul` (Mentor-Erinnerungen), `kampagne`-NG+, Character-Varianten.
**Aufwand:** XL · **Score:** 8

### 33. Playstyle-Profile: Casual / Fürsorge-Pur / Ökonomie-Nerd

**Konzept:** Beim Onboarding (und jederzeit in den Settings) wählbar:
**Casual** (sanfter Verfall, großzügige Timer), **Fürsorge-Pur** (Care
intensiv, Wirtschaft nebensächlich, mehr Soul-Momente), **Ökonomie-Nerd**
(engere Märkte, tiefere Laden-/Ranch-Zahlen, mehr Zahlen-UI). Profile sind
Modifikator-Layer über Verfallsraten, Quest-Mix und UI-Dichte — Erfolge
und Abschluss bleiben profilneutral fair. Der Nordstern (Idee 3) färbt
seine Empfehlungen nach Profil. **Eval-Befund:** Grind-Gates (Finding 6)
treffen Spielertypen unterschiedlich; „Auswahl fühlt sich effizient statt
persönlich an". **Systeme:** `AppSettings`/Slice `settings`,
Modifikator-Layer in `Stats`/`Economy`/`Leveling`, `QuestService`,
Onboarding. **Aufwand:** M · **Score:** 7

### 34. Fotomodus-Ausbau: Foto-Aufträge & Ausstellungswand

**Konzept:** Wöchentliche Foto-Challenges mit Motiv-, Ort- und Pose-Regeln
(„Gooby bei Sonnenuntergang im Funkelpark, Hände hoch!"), offline prüfbar
über Szenen-/Zustands-Tags im Foto-Metadatensatz. Die besten Fotos hängt
man an eine Ausstellungswand im Haus; Gooby und Besucher-NPCs kommentieren
sie. Belohnungen sind Rahmen, Posen, Filter und Album-Seiten — der
Fotomodus wird vom Werkzeug zum eigenen Loop, der Wiederbesuchsgründe für
Stadt/Park/Ranch erzeugt. **Eval-Befund:** Reward-Monotonie; Stadt/Park
ohne Wiederbesuchsgrund; Kamera-Wunsch (USER-WISHES E). **Systeme:**
Slices `camera`, `gallery`, `home`; `SnapAGooby`, Szenen-Tags,
`QuestService` (Wochen-Typ). **Aufwand:** M · **Score:** 8

### 35. Jahreskreis-Rituale: Saison-Gedächtnis

**Konzept:** Der bestehende Ritual-Layer (Geburtstage, Jubiläum, erster
Schnee) wächst zu einem Jahreskreis mit 8–10 festen Momenten: Erntedank im
Garten, Laternenabend in der Stadt, Sommerfest am Strand,
Gooby-Geburtstagswoche. Jeder Moment ist klein (kein Event-Grind), jedes
Jahr minimal anders und erzeugt eine Albumseite plus ein Andenken. So
entsteht über Monate das Gefühl „unser zweiter Sommer" — die stärkste
Bindungswährung, die ein Tamagotchi haben kann. **Eval-Befund:**
„emotionale Langzeitreise"; Tagesloop-Überraschung. **Systeme:**
`SoulService` (Ritual-Prioritäten existieren), `soul_wetter`,
`content/soul`-Defs, Erinnerungsalbum, `kampagne`. **Aufwand:** M ·
**Score:** 8

### 36. „Weißt du noch?"-Rückkehrmomente nach Pausen

**Konzept:** Nach mehrtägiger Abwesenheit gibt es statt Schuldgefühl einen
warmen Wiedereinstieg: Gooby erzählt aus echten Daten, was er allein
gemacht hat, zeigt ein Fundstück und schlägt genau EINEN
Wiedereinstiegs-Schritt vor (Nordstern-verknüpft). Der Offline-Verfall wird
bei langen Pausen sichtbar gedeckelt und freundlich erklärt („Ich hab auf
mich aufgepasst!"). Rückkehr wird damit zum Bindungsmoment statt zur
Bestrafung — entscheidend gegen Churn nach Urlaub oder Schulwoche.
**Eval-Befund:** Offline-Verfall-Frust; Abwesenheits-Gruß existiert
rudimentär (gefreut/eingeschnappt/vermisst) — ausbaufähig. **Systeme:**
`offline.gd`, `SoulService` (Begrüßungs-Layer), `SoulMemories`, Slice
`daily`, HUD. **Aufwand:** S · **Score:** 8

---

## Top-10 für Version 6.0 (priorisiert)

Sortierung nach Bindungs-Impact pro Aufwand UND danach, was die
Eval-Engpässe (Progression 5,5, Multiplayer 4,5, Offline-100%) direkt
angreift. Das Progression-Rework führt die Liste an — es ist das Rückgrat,
an dem fast alle anderen Ideen hängen.

| # | Idee | Warum jetzt | Aufwand | Score |
|--:|---|---|:--:|:--:|
| 1 | **(1) „Goobys Jahr" — Kapitel-Kampagne** | DAS Progression-Rework: verwandelt parallele Checklisten in eine Reise; Rückgrat für Nordstern, Weltänderungen, Freischalt-Rework. | XL | 10 |
| 2 | **(2) Freischalt-Matrix „Früh zeigen, spät besitzen"** | Ranch (stärkster Content) ab Level 5–6 erlebbar statt Level 15/5.950 XP; entgrindet den Weg zu den besten Loops. | M | 9 |
| 3 | **(11) Vertrauens-Band Bond-Level 1–10** | Macht aus Balken-Service eine wachsende Beziehung; schaltet Huckepack, Kochen, Geheimnisse frei — Kern der Bindungs-Lens. | L | 10 |
| 4 | **(6) Abschluss 2.0: Basis/Zusammen/DLC/Meister** | Repariert Offline-100%-Blocker + wertlose Arcade-Sterne in einem Schnitt; faire, lesbare Endziele. | M | 9 |
| 5 | **(28) Warteziel-Redesign „Warten ODER Anpacken"** | Beseitigt die 24-/48-h-Zwangspausen der Ranch durch aktive Alternativen; wiederverwendbarer Quest-Typ. | M | 9 |
| 6 | **(18) Reihen-Handwerk: Unikat-Rewards je Arcade-Reihe** | Bricht den Einheits-Reward-Loop der 38 Spiele: Blaupausen, Fahrzeugteile, Rezepte, Sticker-Serien mit echten Sinks. | XL | 9 |
| 7 | **(7+8) Lebensphasen + Erinnerungsalbum „Unser Buch"** | Gooby wächst über Wochen, nichts geht verloren — die emotionale Langzeitreise, die die Eval als fehlend benennt. | XL | 10 |
| 8 | **(22) Server-Wahl-UX „Verbinden in 60 Sekunden"** | Multiplayer 4,5 → produktreif: Serverliste per Remote-Config, QR-Join, Verbindungstest, ehrlicher Offline-Zustand. | L | 9 |
| 9 | **(24) Asynchrone Besuche mit Gästebuch** | Social ohne Gleichzeitigkeitszwang — passend zu Offline-first und kleiner Spielerschaft; füttert das Album. | L | 9 |
| 10 | **(3) Nordstern-HUD: der EINE nächste Schritt** | Billigster Hebel gegen „viele Leisten, keine Priorität"; macht Kampagne + Bond im Alltag sichtbar. | M | 8 |

Knapp dahinter (starke 6.0-Kandidaten, falls Kapazität bleibt):
**(26)** MP-Trophäen-Bonus-Kategorie (Teilpaket von #4, früh umsetzbar),
**(29)** Tages-Überraschungs-Slot, **(15)** Bedürfnis-Evolution,
**(36)** Rückkehrmomente (S-Aufwand, sofort spürbar).

Abhängigkeits-Hinweis für die Code-Agents: #1 (Kampagne) liefert den
Kapitel-Anker, an den #2 (Gates), #3/#10 (Nordstern), #5 (Weltänderungen)
und #15 (Bedürfnis-Schwellen) andocken — zuerst den `kampagne`-Slice und
die Content-Domain definieren, dann parallelisieren. #4 und #26 teilen die
Sticker-Kategorisierung und sollten in einem Zug migriert werden.

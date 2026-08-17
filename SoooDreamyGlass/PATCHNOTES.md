# SoooDreamy Patchnotes

Newest release first. Every entry is written in German and English from the same shipped scope.

## 16.0.0 — Das Nachtpostamt / The Night Post Office — FULL RELEASE

Der völlige Neubau: Die App ist kein Karten-Katalog mehr, sondern das private Nachtpostamt zweier Menschen — fünf Stationen statt fünf Tabs, ein von Grund auf neu erzähltes Intro, ein neues mehrschichtiges App-Icon, und der Beweis auf echten iPhones: Der Geräte-Bug, der das Intro leer machte, ist an der Wurzel beseitigt. Acht unabhängige Evaluatoren haben in fünf Runden geurteilt, bis alle PERFEKT sagten.

### Deutsch

#### Der Geräte-Bug, der alles auslöste
- **Das Intro war auf echten iPhones leer.** Die Kino-Videos trugen ein HEVC-Etikett (`hev1`), das iPhone-Hardware-Decoder still ablehnen — der Simulator spielte sie, das Gerät nicht. Jetzt remuxt die Pipeline verlustfrei nach `hvc1`, ein doppeltes fail-closed-Gate (nach dem Render UND vor dem IPA-Packen, echter ISO-BMFF-Parser) macht die Bugklasse für immer unmöglich — und die App selbst ist gepanzert: Stirbt ein Video trotzdem, fällt das Kapitel nahtlos auf seine prozedurale Kurzfassung, nie wieder leerer Raum.
- Dazu: Die Tab-Leiste bleibt jetzt immer sichtbar (das Minimieren-und-erst-oben-Zurückkommen ist weg), Partikel schweben nicht mehr durchs Glas, und der System-Notification-Dialog legt sich nie wieder über Beweis-Screenshots.

#### Das Nachtpostamt — fünf Stationen
- **Postfach** (statt „Zuhause"): Der Tag hat Zustellrunden — Morgenpost, Tagespost, Nachtpost. Der Tagesbrief ist IMMER der gestempelte Held („TAGESPOST · TAG 608"), neue Runden gleiten durch einen Briefschlitz herein, das Dienstlicht im Kopf trägt die Energie beider, und „Schick Liebe" ist eine ruhige Telegramm-Leiste mit echten Symbolen statt Emoji-Kacheln. Vor dem Koppeln wartet „Sendung Nr. 1" — ein versiegelter, adressierter Brief statt einer Code-Karte.
- **Schreibstube** (statt „Chat"): Zettel auf der Spindel, ein Pult mit drei Einstiegen (Rohrpost, Briefpapier, Siegelpresse für Zeitpost/Kapsel/Türchen), und jeder gesendete Zettel wird fühlbar aufgespindelt. Die Nachrichten-Identität überlebt jetzt jeden Server-Tausch — kein doppeltes Aufblitzen, keine Geister.
- **Spieltisch** (statt „Spielen"): Der Katalog ist ein Kartenschrank mit drei Fächern voller adressierter Umschläge („Für Ben"), Kapitelzeilen mit Punktlinien führen Buch („Fernpartien ····· 34"), und die Zahlen sind jetzt LEBENSLANG ehrlich — ein eigenes Aggregat überlebt jede Listen-Kappung, Abbrüche zählen nie, Alt-Bestände tragen ein ehrliches „{n}+".
- **Archiv** (statt „Wir"): Eine Schrankfront mit sechs Fächern (Alben, Planfach, Wertfach, Chronik, Lagerfach, Tresorfach), Schubladen gleiten mit einem fühlbaren Rast-Punkt auf, und die Suche versteht beide Sprachen und Alltagsbegriffe („fotos", „sparen") — auf iPhone und iPad.
- **Amt** (statt „Mehr"): Ein stiller Werkzeugraum als natives Formular in sechs Registern, mit Schlüsseldreh beim Scharfschalten der App-Sperre. Wirklich still: Auch der Tintenstaub ruht.

#### Das Intro, neu erzählt
- Sprachwahl zuerst (mit würdigem Wachs-Häkchen), dann das Kino — und der Guide danach trägt dieselbe Materialwelt: ein versiegelter Brief als Held statt eines Emoji-Herzens, die Tintenwahl als 4×2-Naptisch mit sichtbarer Tintenspur, und zum Schluss eine durchgehende Zustellroute statt einer nummerierten Schrittkarte.
- Ein Watchdog mit Generationen-Stempel garantiert: Kein Video-Kapitel kann je wieder leer oder eingefroren stehen — jeder Frame-Beweis gehört exakt seinem Kapitel.

#### Das neue Gesicht
- **App-Icon neu**: Nachtzimmer, goldene Tinte, Polaroid-Weiß und tiefer Siegellack — mehrschichtig aus denselben Farbgesetzen gebaut wie die App selbst (drift-getestet). Der letzte Rest Pink-Lila ist aus dem Produkt verschwunden; der Primärknopf ist Siegellack, das Wordmark goldene Tinte.
- Voice Control versteht die Chips unter beiden Namen, VoiceOver spricht überall volle Sätze, Reduce Motion erhält jede Information, und AX5-Layouts stellen die Frage vor alles andere.

#### Die Abnahme
- **Acht unabhängige Evaluatoren** (Postfach, Schreibstube, Spieltisch, Archiv & Amt, Kino, Gesamtbild, Architektur, Barrierefreiheit) haben in **fünf Runden** insgesamt über 90 Befunde gestellt — alle wurden strukturell behoben, viele mit reinen, Linux-testbaren Regeln plus Pins. Endstand: **alle acht PERFEKT**, mit dem Gesamtbild-Urteil: „einzigartig statt generisch — freigegeben."

### English

#### The device bug that started it all
- **The intro was empty on real iPhones.** The cinema videos carried an HEVC tag (`hev1`) that iPhone hardware decoders silently refuse — the simulator played them, the device did not. The pipeline now remuxes losslessly to `hvc1`, a double fail-closed gate (after rendering AND before IPA packaging, a real ISO-BMFF parser) makes the bug class impossible forever — and the app itself is armored: if a video still dies, the chapter falls seamlessly to its procedural short form. Never an empty room again.
- Also: the tab bar now stays visible (no more minimize-and-only-return-at-top), particles no longer float through the glass, and the system notification dialog never covers proof screenshots again.

#### The Night Post Office — five stations
- **Mailbox** (was "Home"): the day has delivery rounds — morning, midday, night post. The day letter is ALWAYS the stamped hero ("MIDDAY POST · DAY 608"), new rounds slide in through a letter slot, the duty light carries both energies, and "Send love" is a calm telegram strip with real symbols instead of emoji tiles. Before pairing, "Delivery no. 1" waits — a sealed, addressed letter instead of a code card.
- **Writing Desk** (was "Chat"): slips on the spindle, a desk with three entries (pneumatic post, stationery, the seal press for timed post/capsules/advent doors), and every sent slip is tangibly spindled. Message identity now survives every server swap — no double flash, no ghosts.
- **Game Table** (was "Play"): the catalog is a card cabinet with three drawers of addressed envelopes ("For Ben"), chapter lines with dotted leaders keep the book ("Play by mail ····· 34"), and the numbers are now LIFETIME honest — a dedicated aggregate survives list capping, aborts never count, legacy stores wear an honest "{n}+".
- **Archive** (was "Us"): a cabinet front with six drawers (Albums, Plans, Values, Chronicle, Storage, Vault), drawers glide open with one tangible detent, and search understands both languages and everyday words ("photos", "saving") — on iPhone and iPad.
- **Bureau** (was "More"): a quiet tool room as a native form in six registers, with a key-turn when arming the app lock. Truly quiet: even the ink dust rests.

#### The intro, retold
- Language first (with a dignified wax check mark), then the cinema — and the guide afterwards carries the same material world: a sealed letter as its hero instead of an emoji heart, the ink pick as a 4×2 tray with a visible ink trail, and a continuous delivery route instead of a numbered step card at the end.
- A generation-stamped watchdog guarantees: no video chapter can ever stand empty or frozen again — every frame proof belongs to exactly its chapter.

#### The new face
- **New app icon**: night room, golden ink, polaroid white and deep sealing wax — layered from the same color laws as the app itself (drift-tested). The last trace of pink-purple is gone from the product; the primary button is sealing wax, the wordmark golden ink.
- Voice Control understands the chips under both names, VoiceOver speaks full sentences everywhere, Reduce Motion preserves every piece of information, and AX5 layouts put the question before everything else.

#### The sign-off
- **Eight independent evaluators** (Mailbox, Writing Desk, Game Table, Archive & Bureau, Cinema, Overall Design, Architecture, Accessibility) filed over 90 findings across **five rounds** — all fixed structurally, many as pure Linux-testable rules with pins. Final state: **all eight PERFEKT**, with the design verdict: "unique instead of generic — approved."

## 15.0.0 — Lampenlicht / Lamplight

Die Nachtkorrektur: Der Papier-&-Licht-Look kippt vom hellen Papiertag in den späten Abend — dunkler Raum, dunkle Karten, und nur das Wichtige leuchtet. Dazu ein von Grund auf entbuggtes Intro (inklusive eines Fehlers, durch den die Sprachfrage nie erschien) — und erstmals wird die App in jedem Build WIRKLICH benutzt: von automatisierten Testern, die tippen, wischen, koppeln und senden, und von einer Arena, in der zwölf Paare gleichzeitig auf einem echten Server leben.

### Deutsch

#### Der Look, nachjustiert: späte Nacht
- **Dunkel ist jetzt der Grundton.** Das Zimmer wurde tiefer, und die Standard-Karten sind kein helles Papier mehr, sondern warmes Nachtkarton mit feinem Korn und einer schmalen Lampenkante — beschrieben mit heller Tinte. Rund 260 Flächen in der ganzen App wurden umgestellt.
- **Nur Artefakte leuchten.** Helles Papier gibt es noch — aber nur, wo es etwas BEDEUTET: die Tagesfrage als Briefbogen, eure Chat-Zettel, Briefe, Polaroids, Spielbretter, Gutscheine, Zeitpost-Umschläge. Der Blick fällt automatisch auf das, was zählt — wie Dinge im Lampenlicht auf einem dunklen Tisch.
- **Das Wachs ist jetzt Wachs.** Das Siegel war blass geworden — jetzt ist es tief und satt, mit heller Herz-Prägung, im Kino wie auf jedem Brief.

#### Das Intro, wirklich repariert
- **Die Sprachfrage erscheint jetzt garantiert.** Ein subtiler Fehler hat sie bisher für ALLE übersprungen: Die App persistierte beim allerersten Start intern eine Sprache, und das Gate hielt das für eure Wahl. Jetzt zählt nur eine echte, bewusste Wahl — beim ersten Start fragt euch die Lampe zuverlässig: Deutsch oder English.
- **Sieben Playback-Fehler beseitigt**, darunter die zwei spürbarsten: ein Doppelbild bei jedem Kapitelwechsel und ein Dimmen an der Naht zwischen den Filmkapiteln. Dazu: kein Schwarzbild mehr beim Filmstart (ein Standbild liegt darunter, bis der erste Frame wirklich da ist), doppelte „Weiter"-Tipper springen nicht mehr zwei Kapitel, und der Licht-Ring des Siegels schiebt die Knöpfe nicht mehr aus dem Bild.
- **Acht eingefrorene Kino-Momente** werden jetzt bei jedem Build als Bilder festgehalten — das Intro kann nie wieder unbemerkt kaputtgehen.

#### Die App wird bei jedem Build benutzt
- **Fünf automatische Nutzungstests** bedienen die echte App im Simulator: Sprachwahl und Intro, die Demo-Tour durch alle fünf Tabs, Chat-Schreiben samt Suche, die Zeitpost-Blätter — und der Königstest: per Oberfläche einem echten Paar beitreten, den ersten Gruß senden, und der Server bestätigt den Empfang doppelt.
- **Die Arena**: Ein Testsystem lässt bis zu zwölf Paare mit mehreren Geräten GLEICHZEITIG auf einem echten Server leben — chatten, senden, spielen, Zeitpost aufgeben, die Verbindung verlieren, den Server mitten im Betrieb abstürzen sehen. Ergebnis nach ~18.700 Anfragen: null Regelverletzungen — und ein echter Serverfehler wurde dabei gefunden und behoben (eine zugestellte Zeitpost blockierte kurz das Pulse-Senden des Absenders).

#### Ehrliche Grenzen
- Die Nachtkorrektur ist bewusst dunkel abgestimmt — wer es heller mag: Die Widget-Themes bieten weiterhin helle Papier-Varianten, die App selbst lebt jetzt im Abend.

### English

#### The look, retuned: late night
- **Dark is the baseline now.** The room got deeper, and standard cards are no longer bright paper but warm night-card stock with fine grain and a slim lamp edge — written in light ink. Around 260 surfaces across the app were converted.
- **Only artifacts glow.** Bright paper still exists — but only where it MEANS something: the daily question as a letter sheet, your chat slips, letters, polaroids, game boards, coupons, timed-post envelopes. Your eye lands on what matters — like things in lamplight on a dark table.
- **The wax is wax again.** The seal had gone pale — now it is deep and rich with a bright embossed heart, in the cinema and on every letter.

#### The intro, actually fixed
- **The language question now appears, guaranteed.** A subtle bug had skipped it for EVERYONE: the app persisted a language internally on the very first boot, and the gate mistook that for your choice. Now only a real, deliberate pick counts — on first launch the lamp reliably asks: Deutsch or English.
- **Seven playback bugs eliminated**, including the two most tangible: a double image on every chapter change and a dimming at the seam between film chapters. Also: no more black frame at film start (a still sits underneath until the first frame truly arrives), double "Next" taps no longer jump two chapters, and the seal's light ring no longer pushes the buttons off screen.
- **Eight frozen cinema moments** are now captured as images on every build — the intro can never silently break again.

#### The app is used on every build
- **Five automated usage tests** operate the real app in the simulator: language pick and intro, the demo tour across all five tabs, chat writing with search, the timed-post sheets — and the royal test: joining a real couple through the interface, sending the first greeting, and the server confirming receipt twice.
- **The arena**: a test system lets up to twelve couples with multiple devices live on a real server SIMULTANEOUSLY — chatting, sending, playing, mailing timed post, losing connections, watching the server crash mid-operation. Result after ~18,700 requests: zero rule violations — and one real server bug was found and fixed along the way (a delivered timed post briefly blocked the sender's pulse sending).

#### Honest limits
- The night retune is deliberately dark — if you prefer it brighter: the widget themes still offer bright paper variants, while the app itself now lives in the evening.

## 14.0.0 — Papier & Licht / Paper & Light — FULL RELEASE

Der Sprung aus der Alpha: eine neue, unverwechselbare Bildsprache für die ganze App, ein Kino zum ersten Start, eine Poststation für Zärtlichkeiten — und eine Abnahme, bei der zehn unabhängige Prüfperspektiven aus zwei KI-Modellfamilien erst aufgehört haben, als überall die glatte 10/10 stand.

### Deutsch

#### Der neue Look: Papier & Licht
- **Ein Zimmer statt eines Weltalls.** Die App spielt jetzt in einem warmen Sepia-Zimmer bei Nacht: eine Lampe wirft ihren Kegel von zehn Uhr, feiner Tintenstaub in euren beiden Farben schwebt im Licht. Fünf Design-Richtungen traten im Wettbewerb an — „Papier & Licht" hat gewonnen und wurde bis in den letzten Screen umgesetzt.
- **Alles, was Inhalt trägt, ist Papier.** Briefe, Karten, Spielpläne, Listen — opakes Papier mit echtem Korn und Lichtkante, beschrieben mit dunkler Tinte. Der Chat ist eine echte Korrespondenz: BEIDE Seiten schreiben auf Papier-Zettel, unterscheidbar an der Tintenkante in der jeweils eigenen Farbe. Datumsgrenzen sind Poststempel, Briefe tragen ein materielles Wachssiegel mit Herz-Prägung.
- **Die Leiste unten ist jetzt die echte.** Die eigene Bausatz-Leiste ist gelöscht — unten schwebt die native iOS-26-Tab-Bar aus System-Liquid-Glass, die beim Lesen mitschrumpft, mit echtem System-Badge und dem „Heute-Zettel" darüber: Partner-Präsenz und Tages-Hinweis auf der System-Bühne. Suche, Fortschrittsringe, Formulare, Verbindungs-Chip: überall echte Apple-Bausteine.
- **Ein neues Gesicht.** Das App-Icon ist jetzt das „versiegelte Polaroid": Zimmer, Papier, zwei ineinanderfließende Tinten, Wachssiegel — in allen zehn Farbvarianten, bis auf 60 Pixel lesbar. Die Widgets tragen dieselbe Sprache.

#### Das Kino zum ersten Start
- **Erst die Sprache, dann die Show.** Beim allerersten Öffnen fragt ein ruhiger Lampenklick: Deutsch oder English — beide Karten gleichzeitig lesbar, nichts tickt, nichts drängt.
- **Dann: rund eine Minute Kino.** Sieben Kapitel aus echten, im Build gerenderten Filmen (Umschlag, Siegelbruch, Polaroid — mit „TAG 1"-Poststempel) und interaktiven Momenten, in denen ihr eure Tinten wählt und das Wachssiegel presst. Jeder Haptik-Schlag sitzt auf dem Bild, jedes Kapitel ist überspringbar, und das Finale ist kein Schnitt: Die letzten Zettel des Films verwandeln sich pixelgenau in die echten Knöpfe der App. Auch der Demo-Modus beginnt mit diesem Kino.
- **Bei „Bewegung reduzieren"** erzählt dieselbe Geschichte in ruhigen Standbildern — mit derselben Haptik.

#### Die Poststation
- **Zeitpost.** Schreibe eine Berührung, einen Puls oder eine kleine Notiz und gib sie mit Zustellzeit auf — fünf Minuten bis sieben Tage voraus. Das Aufgeben ist eine Zeremonie: Der Zettel faltet sich, der Poststempel setzt mit dem Kino-Beat auf, der Umschlag hebt ab. Deine Liebste oder dein Liebster sieht NICHTS davon — bis die Sendung zugestellt wird.
- **Ankommen ist ein Moment.** Eine Zeitpost-Notiz erscheint als versiegelter Umschlag im abgedunkelten Zimmer; erst DEIN Tipp bricht das Wachs — mit dem Siegelbruch-Beat aus dem Kino — und die Worte entfalten sich in Schreibschrift.
- **Echo.** Auf eine empfangene Berührung kannst du zehn Minuten lang mit einem Tipp dieselbe zurückschicken — einmal, ohne Wartezeit. Und das Sendungs-Journal erzählt die letzten 30 Tage eurer kleinen Post chronologisch, mit den Tinten beider Absender.
- **Zwei neue Berührungen:** „Stolz auf dich" und „Halt durch" — mit eigenen Haptik-Mustern.

#### Mehr drin, schneller, sparsamer
- **+312 zweisprachige Inhalte**: 100 neue Tagesfragen (jetzt 510), 60 Date-Ideen (Null-Budget-, Fernbeziehungs- und Saison-Blöcke), 50 Quests, 70 Entweder/Oder-Dilemmata, 20 Rätsel, zwei faktengeprüfte Quiz-Kategorien, 12 Kalender-Anlässe.
- **Schneller und leiser**: Das Papierkorn wird einmal gerastert statt pro Karte gezeichnet, das 3D-Herz rechnet mit halber Bildrate, pausiert ungesehen und respektiert den Stromsparmodus — wie jede Ambient-Animation der App.
- **Die Zustellung ist beweisbar zuverlässig**: Zeitpost übersteht Server-Abstürze in beiden kritischen Fenstern ohne Doppel- oder Geisterzustellung (mit echten Absturz-Tests bewiesen).

#### Die Abnahme
- Zehn unabhängige Prüfperspektiven — Artstil, Apple-Nativität, Kino, Fehlerfreiheit, Server, Inhalte, Barrierefreiheit, Performance, Marke, Gefühl — aus zwei KI-Modellfamilien haben diese Version in drei Runden geprüft und Stück für Stück nachgefordert, bis ausnahmslos überall **10/10** stand. 820 Logik-Tests, 493 Server-Tests, alle Design-Wächter grün.

#### Ehrliche Grenzen
- Die Videos liegen nur in der Voll-App; die Lite-Version erzählt dieselben Kapitel in der prozeduralen Kurzfassung (45 statt 60 Sekunden).
- Ziehen an der unteren Leiste gibt es systemseitig nur auf dem iPad — dort kommt die anpassbare Seitenleiste in einer Folgewelle, sauber dokumentiert.

### English

#### The new look: Paper & Light
- **A room instead of outer space.** The app now lives in a warm sepia room at night: a lamp casts its cone from ten o'clock, and fine ink dust in your two colors drifts through the light. Five design directions competed — "Paper & Light" won and was carried through to the very last screen.
- **Everything that carries content is paper.** Letters, cards, game boards, lists — opaque paper with real grain and a light edge, written in dark ink. The chat is true correspondence: BOTH sides write on paper slips, told apart by the ink edge in each partner's color. Date breaks are postmarks; letters carry a material wax seal with an embossed heart.
- **The bottom bar is the real one now.** The hand-built dock is gone — the native iOS 26 tab bar floats below in system Liquid Glass, shrinking as you read, with a real system badge and the "today slip" above it: partner presence and the day's nudge on the system's own stage. Search, progress rings, forms, the connection chip: genuine Apple building blocks everywhere.
- **A new face.** The app icon is now the "sealed polaroid": room, paper, two flowing inks, a wax seal — in all ten color variants, legible down to 60 pixels. The widgets speak the same language.

#### The first-launch cinema
- **Language first, then the show.** On the very first open, a calm lamp click asks: Deutsch or English — both cards readable at once, nothing ticking, nothing rushing you.
- **Then: about a minute of cinema.** Seven chapters of real films rendered at build time (envelope, seal break, polaroid — with a "TAG 1" postmark) and interactive moments where you pick your inks and press the wax seal. Every haptic beat lands on the picture, every chapter can be skipped, and the finale is not a cut: the film's last paper slips morph pixel-perfectly into the app's real buttons. Demo mode opens with the same cinema.
- **Under Reduce Motion** the same story is told in calm stills — with the same haptics.

#### The post station
- **Timed post.** Write a touch, a pulse, or a short note and mail it with a delivery time — five minutes to seven days ahead. Sending is a ceremony: the slip folds itself, the postmark lands on the cinema beat, the envelope lifts off. Your partner sees NOTHING — until the post is delivered.
- **Arrival is a moment.** A timed note appears as a sealed envelope in the darkened room; only YOUR tap breaks the wax — with the cinema's seal-break beat — and the words unfold in the writing voice.
- **Echo.** For ten minutes after receiving a touch, one tap sends the same one back — once, with no cooldown. And the post journal tells the last 30 days of your little mail chronologically, in both senders' inks.
- **Two new touches:** "Proud of you" and "Hang in there" — each with its own haptic pattern.

#### More inside, faster, lighter
- **+312 bilingual items**: 100 new daily questions (now 510), 60 date ideas (zero-budget, long-distance, and seasonal blocks), 50 quests, 70 either/or dilemmas, 20 riddles, two fact-checked quiz categories, 12 calendar occasions.
- **Faster and quieter**: the paper grain is rasterized once instead of drawn per card, the 3D heart runs at half frame rate, pauses while unseen, and respects Low Power Mode — like every ambient animation in the app.
- **Delivery is provably reliable**: timed post survives server crashes in both critical windows without double or ghost deliveries (proven with real crash tests).

#### The sign-off
- Ten independent review perspectives — art style, Apple nativeness, cinema, bug-freedom, server, content, accessibility, performance, brand, feel — from two AI model families reviewed this version across three rounds and kept pushing until every single one read **10/10**. 820 logic tests, 493 server tests, every design guard green.

#### Honest limits
- The films ship in the full app only; the Lite build tells the same chapters in the procedural short cut (45 instead of 60 seconds).
- Dragging on the bottom bar only exists on iPad, per the platform — the customizable sidebar arrives there in a follow-up wave, cleanly documented.

## 13.0.0 — Bis ins letzte Detail / Down to the last detail

Die Perfektionsrunde: ein Neuanstrich von Grund auf, neun neue Spiele, spürbar mehr Seele im Inhalt — und die Zusage, dass jedes Wort auf jeder Paarfarbe lesbar ist. Zwölf strenge Prüfperspektiven (von Gefühl über Fehlerfreiheit bis Barrierefreiheit) haben diese Version über sieben Runden abgenommen, bis alle zufrieden waren.

### Deutsch

#### Neu
- **Ein neues Gesicht — dieselbe Seele.** Der komplette Neuanstrich ersetzt Deko-Emojis durch eine ruhige Symbolsprache, färbt die App konsequent in EURE beiden Farben statt in Einheits-Pink, prägt Erfolge als Glas-Medaillen und stimmt die Widgets auf dieselbe Palette ein. Und der allererste Start ist jetzt ein kleines Kino: eine rund 20-sekündige Eröffnung aus Licht, Bewegung und Haptik, die die App vorführt, bevor sie etwas von euch will — natürlich überspringbar, und bei „Bewegung reduzieren" in einer ruhigen Fassung.
- **Neun neue Spiele.** Dame, Reversi, Käsekästchen, Gomoku, Mancala und Memory-Duo als echte Brettspiele mit fairen, server-geprüften Zügen — dazu Wordle-Duo, Schere-Stein-Papier (mit versiegelter Wahl, schummeln unmöglich) und die Geschichten-Staffel, in der ihr abwechselnd eine kleine Geschichte baut. Jedes Spiel erklärt sich beim ersten Öffnen selbst.
- **Mehr Seele im Inhalt.** Über 240 neue zweisprachige Fragen, Ideen, Quests und Rätsel — mit mehr Tiefgang statt mehr Beliebigkeit. Jede körperliche Karte ist jetzt eine echte Einladung: Die Handlung wird beim Ja benannt, und die eingeladene Person entscheidet frei. Passen ist immer okay — ohne Serien-Verlust, ohne Strafton, ohne Punktabzug. Das englische Wording wurde durchgehend nativ lektoriert.
- **Für beide Augen gemacht.** Jeder Text auf euren Farbverläufen erreicht jetzt mindestens den WCAG-Kontrast von 4,5:1 — mit berechneten Tinten und einem hauchdünnen Schutz-Schleier, der automatisch mit dem Verlauf reist, wo keine Tinte allein genügt. Mathematisch bewiesen, von Tests festgenagelt, in jedem Renderer adoptiert. Dazu: VoiceOver spricht die neuen Spiele vollständig (Buchstaben-Bewertungen, Rundenergebnisse, Erzähler-Wechsel), und die größten Schriftgrößen zeigen alles ohne abgeschnittene Inhalte.
- **Die Tagesfrage ist jetzt unverwechselbar.** Die erste Antwort legt die Frage des Tages fest — ab dann zeigen alle Geräte, Widgets und die App dieselbe Frage, auch über Mitternacht, Zeitzonen und gemischte App-Stände hinweg. Verliert eine Offline-Antwort das Rennen um die Frage, geht kein Wort verloren: Sie kommt als Entwurf unter der festgelegten Frage zurück.

#### Feinschliff
- Große Feier-Momente teilen sich app-weit ein Budget — das Besondere bleibt besonders, auch wenn zwei Dinge gleichzeitig gelingen.
- Wessen Zug ist, sagt jetzt immer der Server — Extra-Züge und Zweitgeräte können die Anzeige nicht mehr verwirren.
- Strukturierte Server-Antworten (etwa bei Konflikt zweier Geräte) werden vollständig verstanden und sofort übernommen statt nur betoastet.

#### Ehrliche Grenzen
- Sehr alte App-Stände können eine von neueren Geräten festgelegte Tagesfrage nicht darstellen. Sie erhalten dann eine klare Aufforderung zum Aktualisieren — bewusst so gewählt, statt Antworten still der falschen Frage zuzuordnen.
- Der Schutz-Schleier dimmt betroffene Verläufe minimal ab. Er erscheint nur bei Farbpaaren, auf denen keine Tinte allein lesbar wäre — eure Paarfarben-Paletten kommen ohne ihn aus.

### English

#### New
- **A new face — the same soul.** The full visual rework replaces decorative emoji with a calm symbol language, tints the app in YOUR two colors instead of one-size-fits-all pink, mints achievements as glass medals, and tunes the widgets to the same palette. And the very first launch is now a small cinema: a roughly 20-second opening of light, motion, and haptics that shows the app off before asking anything of you — skippable, of course, and calm under Reduce Motion.
- **Nine new games.** Checkers, Reversi, Dots and Boxes, Gomoku, Mancala, and Memory Duo as real board games with fair, server-verified moves — plus Wordle Duo, Rock-Paper-Scissors (with sealed picks, cheating impossible), and the Story Relay where you build a little tale turn by turn. Every game explains itself the first time you open it.
- **More soul in the content.** Over 240 new bilingual questions, ideas, quests, and riddles — deeper, not just more. Every physical card is now a real invitation: the action is named with the yes, and the invited person decides freely. Passing is always okay — no streak loss, no warning sound, no point penalty. The English wording got a full native edit.
- **Made for both pairs of eyes.** Every word on your couple gradients now clears the WCAG contrast floor of 4.5:1 — with computed inks and a whisper-thin protective scrim that travels with the gradient wherever no ink alone suffices. Proven mathematically, pinned by tests, adopted in every renderer. Plus: VoiceOver speaks the new games fully (letter verdicts, round results, narrator turns), and the largest text sizes show everything without clipped content.
- **The daily question is now unmistakable.** The first answer pins the question of the day — from then on every device, widget, and the app itself shows the same question, across midnight, timezones, and mixed app versions. If an offline answer loses the race for the question, not a word is lost: it returns as a draft under the pinned question.

#### Polish
- Big celebration moments share one app-wide budget — the special stays special, even when two things succeed at once.
- Whose turn it is now always comes from the server — extra moves and second devices can no longer confuse the indicator.
- Structured server responses (say, when two devices conflict) are fully understood and adopted on the spot instead of merely toasted.

#### Honest limits
- Very old app versions cannot display a daily question pinned by newer devices. They receive a clear prompt to update — chosen deliberately over silently filing answers under the wrong question.
- The protective scrim dims affected gradients ever so slightly. It appears only on color pairs no ink alone could serve — your couple palettes get by without it.

## 12.0.0 — Mehr Platz für euch / Room for the two of you

Die App wächst über das eine iPhone hinaus: aufs iPad, auf Zweitgeräte, auf die Couch — und euer Gerät hilft beim Formulieren, Übersetzen und Ankommen, ohne dass ein Wort es je verlässt.

### Deutsch

#### Neu
- **SoooDreamy läuft jetzt auf dem iPad.** Nicht als aufgeblasenes iPhone-Fenster, sondern als eigenes Layout: das Dashboard als Raster, Erinnerungen als Split mit Sektionen-Leiste, Briefe und Tagebuch in ruhigen Lese-Spalten. Split View, Slide Over und Stage Manager funktionieren in allen vier Ausrichtungen. Der Apple Pencil zeichnet auf der Kritzel-Leinwand mit echtem Druck und zeigt beim Schweben, wo der Strich landet; eine Tastatur wechselt mit Cmd+1 bis Cmd+5 die Tabs und schickt Nachrichten mit Cmd+Return; Bilder lassen sich direkt in Chat und Galerie fallen lassen. Angefangene Briefe und Chat-Entwürfe überleben jeden Layout-Wechsel. Dazu: XL-Widgets fürs iPad — „Tage zusammen“ zweispaltig, das Foto-Widget mit echtem Querformat-Ausschnitt.
- **Mehrere Geräte, ein Zuhause.** Jede Person kann jetzt iPhone UND iPad (und mehr) gleichzeitig verbinden: Auf dem verbundenen Gerät einen Einmal-Code erzeugen, auf dem neuen scannen — oder den `sooodreamy://link`-Deep-Link öffnen — fertig. Der neue Geräte-Manager in den Einstellungen zeigt alle Geräte („Dieses Gerät“ markiert) und meldet einzelne gezielt ab; kommt ein Gerät dazu, sagt ein leiser Live-Hinweis auf den anderen Bescheid. Und die App weiß, was von dir selbst kommt: Was du am iPad schreibst, erscheint auf deinem iPhone als dezenter Haken — nicht als Partner-Überraschung.
- **Apple Intelligence — freiwillig, und nur auf dem Gerät.** Drei Formulier-Hilfen, alle hinter einer klaren Einwilligung: Die **Briefanfang-Werkstatt** schlägt drei Anfänge in drei Tönen vor (Zärtlich, Verspielt, Tief), **„Sag es sanft“** formuliert einen Chat-Entwurf behutsamer — dein Original bleibt stehen, bis du übernimmst — und der **„Gemeinsame Funke“** baut nach der beidseitigen Tagesfrage-Enthüllung eine kleine Anschlussfrage aus euren beiden Antworten. Alles läuft im Apple-Sprachmodell auf dem Gerät; nichts geht an Apple, an Dritte oder auf euren Server. Ist Apple Intelligence nicht verfügbar, sagen die Einstellungen ehrlich, warum.
- **Spieltische & Zuschauer.** Auf dem iPad werden 4 Gewinnt, Kniffel, Bingo, Montagsmaler und Schiffe versenken zu echten Spieltischen — Schiffe versenken als Duelltisch mit beiden Flotten nebeneinander. Läuft eine Partie auf einem deiner Geräte, schauen die anderen automatisch zu („Nur zuschauen — dein iPhone spielt gerade“) und übernehmen auf Wunsch mit einem Tipp; versiegelte Züge bleiben dabei Commit-Reveal-fair. Siege feiert die App mit einem eigenen Sieg-Motiv — und einem Zeremonien-Budget, damit das Besondere besonders bleibt. Dazu: This-or-That im Couch-Modus — ein Handy, geheime Wahl, weiterreichen.
- **Die App spricht eure Sprachen.** Chat-Nachrichten übersetzen sich auf Wunsch direkt unter dem Original — on-device über das Apple-Translation-Framework, keine Cloud. Sprachnachrichten bekommen auf Antippen ein Transkript (SpeechAnalyzer, ebenfalls on-device) und merken es sich lokal.
- **Sanfter ankommen.** Ein Wegweiser mit drei Schritten führt vom ersten Start bis zum gekoppelten Paar; wer erst schauen will, öffnet den Demo-Modus **„Erst mal ansehen“** mit Beispiel-Paar und klarem Ausstieg. Und der Moment des Koppelns ist jetzt eine kleine Zeremonie: eure beiden Farben verschmelzen — auch, wenn nur ein neues Gerät dazukommt.

#### Feinschliff
- Die Liquid-Glass-Sprache wurde vertieft: Tab-Dock und Composer sitzen als echtes Glas-Chrome über dem Inhalt, Listen bekommen Scroll-Kanten-Effekte, Buttons das System-Glas — und beschriftetes Chrome steht nach dokumentierten Regeln immer für sich.
- Die Aurora im Hintergrund drosselt sich selbst: bei „Bewegung reduzieren“, im Hintergrund und im Stromsparmodus ruht sie.

#### Ehrliche Grenzen
- Apple Intelligence braucht ein Apple-Intelligence-fähiges Gerät mit eingeschalteter Apple Intelligence — sonst bleiben die Formulier-Hilfen ausgeblendet, und die Einstellungen nennen den Grund. Vorschläge sind immer Entwürfe: Gesendet wird nichts von allein.
- Übersetzung und Transkripte hängen von den on-device-Sprachpaketen ab, die iOS je Sprache nachlädt — was das Gerät nicht kann, behauptet die App nicht.
- Pro Person sind höchstens 8 Geräte-Plätze aktiv, und ein neues Gerät braucht immer ein schon verbundenes (oder den Wiederherstellungs-Schlüssel) — ein Einmal-Code allein öffnet kein fremdes Paar.
- Berührungen und Pulse sind auf dem iPad zu sehen, aber meist nicht zu fühlen: Den meisten iPads fehlt die Taptic Engine.

### English

#### New
- **SoooDreamy now runs on iPad.** Not as an inflated iPhone window but as its own layout: the dashboard becomes a grid, memories a split view with a section sidebar, letters and the journal calm reading columns. Split View, Slide Over, and Stage Manager work in all four orientations. Apple Pencil draws on the doodle canvas with real pressure and shows on hover where the stroke will land; a keyboard switches tabs with Cmd+1 through Cmd+5 and sends messages with Cmd+Return; images drop straight into chat and gallery. Started letters and chat drafts survive every layout change. Plus: XL widgets for iPad — “Days together” in two columns, the photo widget with a true landscape crop.
- **Several devices, one home.** Each person can now connect iPhone AND iPad (and more) at the same time: create a one-time code on a connected device, scan it on the new one — or open the `sooodreamy://link` deep link — done. The new device manager in Settings lists every device (“This device” marked) and signs individual ones out; when a device joins, a quiet live toast tells the others. And the app knows what came from you: what you type on the iPad shows up on your iPhone as a subtle tick — not as a partner surprise.
- **Apple Intelligence — opt-in, and on-device only.** Three writing helpers, all behind a clear consent: the **opening workshop** suggests three letter openings in three tones (tender, playful, deep), **“Say it gently”** rewords a chat draft more softly — your original stays until you adopt it — and the **“shared spark”** builds a small follow-up question from both your answers after the daily-question reveal. Everything runs in Apple's on-device language model; nothing goes to Apple, to third parties, or to your server. If Apple Intelligence isn't available, Settings honestly says why.
- **Game tables & spectators.** On iPad, Connect Four, Kniffel, Bingo, Pictionary, and Battleship become real game tables — Battleship as a duel table with both fleets side by side. If a match is running on one of your devices, your others automatically spectate (“Watch only — your iPhone is playing”) and take over with one tap when you want; sealed moves stay commit-reveal fair throughout. Wins get their own victory motif — under a ceremony budget, so the special stays special. Plus: This-or-That in couch mode — one phone, secret picks, pass it on.
- **The app speaks your languages.** Chat messages translate on request right below the original — on-device through Apple's Translation framework, no cloud. Voice notes gain a transcript on tap (SpeechAnalyzer, also on-device) and remember it locally.
- **A gentler arrival.** A three-step guide leads from first launch to a paired couple; anyone who wants to look first opens the demo mode **“Just look around first”** with a sample couple and a clear way out. And the moment of pairing is a small ceremony now: your two colors melt into one — even when it's just a new device joining.

#### Polish
- The liquid-glass language got deeper: the tab dock and composer sit above the content as true glass chrome, lists gain scroll-edge effects, buttons the system glass — and labeled chrome always stands alone, by documented rules.
- The aurora in the background throttles itself: with Reduce Motion, in the background, and in Low Power Mode it rests.

#### Honest limits
- Apple Intelligence needs an Apple-Intelligence-capable device with Apple Intelligence turned on — otherwise the writing helpers stay hidden and Settings names the reason. Suggestions are always drafts: nothing is ever sent on its own.
- Translation and transcripts depend on the on-device language packs iOS downloads per language — what the device can't do, the app doesn't claim.
- At most 8 device seats are active per person, and a new device always needs an already-connected one (or the recovery key) — a one-time code alone opens nobody else's couple.
- Touches and pulses are visible on iPad but usually not feelable: most iPads have no Taptic Engine.

Made by Sonic0810 with love.

## 11.1.0 — Belastbar / Built to last

Kein neues Feature, sondern ein eingelöstes Versprechen: Nach 11.0.0 haben drei unabhängige Prüfungen (Design, Server, Produkt) die App auseinandergenommen — diese Version behebt, was sie fanden.

### Deutsch

#### Sicherer
- **Eure Erinnerungen überleben jetzt einen Stromausfall.** Vorher konnte eine Nachricht als „gesendet“ bestätigt sein und beim nächsten Serverstart trotzdem fehlen; jetzt bestätigt der Server erst, wenn wirklich dauerhaft geschrieben ist. In der Prüfung gingen vorher 120 von 120 bestätigten Nachrichten nach einem harten Absturz verloren — jetzt sind alle 120 da.
- **Keine zwei Server können mehr dieselben Daten überschreiben** (Verzeichnis-Sperre), und die Wiederherstellung nach einer beschädigten Datei löscht keine gültigen Erinnerungen mehr, sondern rettet sie.
- **Der Login-QR ist jetzt ein Einmal-Code mit Ablauf** — einmal benutzt, ist er verbraucht.
- **Backups sind kollisionsfrei und schließen eure Medien ein**, und die Anleitungen sagen jetzt die Wahrheit über HTTP/HTTPS: HTTP bleibt der einfache Standard fürs Heimnetz, striktes HTTPS ist ein Schalter.

#### Schöner
- **Die App trägt endlich eure Farben.** Enthüllungs-Blasen, Meilensteine und Akzente stehen jetzt in den Farben der beiden Partner statt in Standard-Rosa.
- **Alle Spiele sind mit VoiceOver bedienbar** und respektieren „Bewegung reduzieren“.
- Kein Farbverlauf mehr auf Text, ein einziges Glas-System für Leisten, ein ruhiger Karten-Rhythmus — der letzte Rest „zusammengewürfelt“ ist raus.

### English

#### Safer
- **Your memories now survive a power cut.** Before, a message could be confirmed as “sent” and still be gone after the next server restart; now the server only confirms once the write is truly durable. In testing, 120 of 120 confirmed messages were lost after a hard crash before — now all 120 remain.
- **No two servers can overwrite the same data anymore** (directory lock), and recovery from a corrupted file no longer deletes valid memories — it rescues them.
- **The login QR is now a single-use code with an expiry** — once used, it’s spent.
- **Backups are collision-free and include your media**, and the guides now tell the truth about HTTP/HTTPS: HTTP stays the easy default for your home network, strict HTTPS is a switch.

#### More beautiful
- **The app finally wears your colors.** Reveal bubbles, milestones, and accents now use both partners’ colors instead of stock pink.
- **Every game is operable with VoiceOver** and respects “Reduce Motion.”
- No more gradient on text, one single glass system for bars, a calm card rhythm — the last “thrown together” bits are gone.

Made by Sonic0810 with love.

## 11.0.0 — Aus einem Guss / All of a piece

Die große Polish-Offensive: kein einzelnes neues Feature, sondern ein Versprechen — wir sind einmal durch JEDE Ecke der App gegangen und haben sie so behandelt, als wäre sie die wichtigste.

### Deutsch

#### Neu
- **Ein Design aus flüssigem Glas**: Farben, Radien, Schatten und Bewegungen kommen jetzt überall aus demselben Baukasten. Karten atmen gleich, Sheets schwingen gleich, nichts springt mehr — die App fühlt sich an wie aus einem Guss gegossen.
- **Die Enthüllung ist eine Zeremonie**: Wenn ihr beide geantwortet habt, reißt die App kein Ergebnis mehr auf — sie zelebriert es. Erst deine Worte, dann die deines Schatzes, dann der Moment, in dem beide nebeneinander stehen.
- **Das Dashboard richtet den Blick**: Weniger gleichzeitig, mehr nacheinander — die Karte, die JETZT dran ist (Frage des Tages, Morgengruß, ein wartender Puls), steht oben; der Rest ordnet sich unter. Anpassbar bleibt es trotzdem.
- **Fotos in einer echten Lightbox**: Zoomen, Wischen, Teilen, Favorisieren — Bilder öffnen sich jetzt in einem dunklen, ruhigen Raum statt in einem Sheet mit Rahmen.
- **Die Brücke zum Sperrbildschirm**: Live Activities für Puls, Countdown und Date-Night sprechen dieselbe Designsprache wie die App — inklusive Icon-Familien-Themes. Dazu versteht Siri mehr Wege, Liebe zu schicken.
- **Klänge mit Herkunft**: Die App klingt jetzt — sanft, nie fordernd, abschaltbar. Jeder Ton ist entweder selbst synthetisiert oder frei lizenziert und steht mit Quelle in den Credits.
- **Der Sprachpass**: Jeder Satz der App wurde neu gelesen. Echte Grammatik-Fehler sind raus (Jonas' Tag statt Jonass Tag, „1 perfekter Tag“ statt „1 perfekte Tage“, „ihr wischt“ statt „ihr swiped“), jedes Ding hat genau ein Wort (Tresor, Leinwand, Träumeliste, Gutscheine, Serie, Zeitinseln), und die App duzt dich am Gerät und meint euch beide im Leben. Emojis stehen nicht mehr als Deko am Satzende — die Emotion steckt im Satz.
- **Leere Bildschirme laden ein**: Wo früher eine Sackgasse war („Noch keine Fotos“), steht jetzt eine Tür („Erstes Foto teilen“) — an über zwanzig Stellen, vom Tagebuch bis zur Wordle-Bilanz.
- **Einstellungen mit Landkarte**: Die Benachrichtigungen haben ein eigenes, aufgeräumtes Blatt bekommen; Scope-Anzeigen sagen ehrlich, was „für euch beide“ gilt und was „nur du“ bist; die Gefahrenzone heißt jetzt so und sieht auch so aus — und bietet vor dem Auflösen zuerst das Sichern an.
- **Der Verbindungs-Doktor**: Wenn der Server mal schweigt, prüft die App in vier Ampel-Schritten, woran es liegt (Erreichbarkeit, Server-Version, Sitzung, Live-Verbindung) — jede rote Stufe nennt den Ausweg, und der Befund ist kopierbar, ohne Geheimnisse zu verraten.
- **„Unsere Reise“**: Die Versions-Geschichte der App gibt es jetzt in der App — als Timeline mit Kapitelnamen, von „Klarheit“ bis heute.

#### Feinschliff
- Die Pairing-Rettung aus 10.x (Wiederherstellungs-Schlüssel, stilles Selbstheilen, Ersatz-Code, Login-QR aus dem Admin-Panel) ist jetzt überall auch sprachlich wahr: Kein Text droht mehr mit „bitte neu koppeln“, wenn die App sich längst selbst hilft.
- Das Admin-Panel und die Backups aus der Kommandobrücke bekamen den gleichen Feinschliff wie die App — ein Werkzeugkasten, der sich nicht nach Arbeit anfühlt.
- Hunderte Kleinigkeiten: konsistente Zurück-Wege, Dynamic-Type-feste Schriften, ruhigere Animationen auf Wunsch, ehrlichere Fehlertexte nach dem Muster „Was ist passiert · Was ist sicher · Was hilft“.

#### Ehrliche Grenzen
- Eine Polish-Runde ist nie „fertig“ — sie hat nur irgendwann jede Ecke einmal berührt. Wenn euch ein schiefer Satz oder ein springender Pixel begegnet: Das Handbuch verrät, wo ihr ihn meldet.
- Der Verbindungs-Doktor kann Diagnosen stellen, aber keinen Server starten — der letzte Schritt gehört weiter dem Menschen mit dem Terminal.

### English

#### New
- **One design, poured from liquid glass**: colors, radii, shadows and motion now come from a single kit everywhere. Cards breathe alike, sheets swing alike, nothing jumps anymore — the app finally feels cast in one piece.
- **The reveal is a ceremony**: once you have both answered, the app no longer rips a result open — it celebrates it. First your words, then your love's, then the moment both stand side by side.
- **The dashboard directs the gaze**: less at once, more in order — the card that matters NOW (daily question, morning greeting, a waiting pulse) rises to the top; the rest falls in line. Still customizable, of course.
- **Photos in a real lightbox**: zoom, swipe, share, favorite — pictures now open into a dark, calm room instead of a framed sheet.
- **The bridge to the lock screen**: Live Activities for pulse, countdown and date night speak the same design language as the app — including the icon-family themes. And Siri understands more ways to send love.
- **Sounds with provenance**: the app makes sound now — gentle, never demanding, always switchable. Every tone is either synthesized in-house or freely licensed, credited with its source.
- **The language pass**: every sentence in the app got a fresh read. Real grammar bugs are gone, every thing has exactly one name (vault, canvas, dream list, coupons, streak-as-series, time islands), and the app addresses YOU at the device while meaning the TWO of you in life. Emojis no longer dangle as decoration at the end of sentences — the emotion lives in the sentence.
- **Empty screens invite**: where a dead end used to sit (“No photos yet”), a door now stands (“Share your first photo”) — in over twenty places, from the journal to the Wordle record.
- **Settings with a map**: notifications got their own tidy sheet; scope badges honestly say what applies “to both of you” and what is “just you”; the danger zone is named and dressed like one — and offers a backup before dissolving anything.
- **The connection doctor**: if the server ever goes quiet, the app checks four traffic-light steps (reachability, server version, session, live socket) — every red step names the way out, and the report is copyable without leaking secrets.
- **“Our journey”**: the app's version history now lives inside the app — a timeline with chapter names, from “Clarity” to today.

#### Polish
- The pairing rescue from 10.x (recovery key, silent self-healing, replace code, login QR from the admin panel) is now also linguistically true everywhere: no text threatens “please pair again” while the app is already helping itself.
- The admin panel and backups from the bridge release got the same polish as the app — a toolbox that doesn't feel like work.
- Hundreds of small things: consistent back paths, Dynamic-Type-proof fonts, calmer animations on request, more honest error texts following “what happened · what is safe · what helps”.

#### Honest limits
- A polish round is never “done” — it has merely touched every corner once. If a crooked sentence or a jumping pixel finds you: the manual says where to report it.
- The connection doctor can diagnose, but it cannot start a server — the final step still belongs to the human with the terminal.

## 10.1.0 — Die Kommandobrücke / The bridge

### Deutsch

#### Neu
- **Admin-Webpanel** (`/admin`): Der Server bringt jetzt eine eigene Weboberfläche für die Betreiberin mit — gleicher Prozess, kein Extra-Dienst. Das Passwort wird bei **jedem Serverstart neu** erzeugt (kryptografisch zufällig, vier tippbare Wortgruppen) und **nur in der Konsole** angezeigt, schön gerahmt samt URL.
- Paare-Übersicht: alle Paare mit Mitgliedern, zuletzt aktiv, App-Versionen der Geräte, Datenumfang (Nachrichten, Fotos, Videos, …) und Segment-Gesundheit inklusive Quarantäne-Anzeige.
- Codes zurücksetzen: neue Einladungs-, Wiederherstellungs- und Ersatz-Codes je Paar bzw. Platz — mit Bestätigungs-Dialog; alte Codes werden dabei ungültig.
- Geräte ausloggen: alle Sitzungen je Paar/Platz einsehen (Gerätename, zuletzt gesehen) und einzeln oder komplett widerrufen — wirkt sofort.
- Login-QR: frischer Rejoin-Token je Platz als QR-Code mit Deep-Link `sooodreamy://rejoin?server=…&token=…` — Handy scannt, App verbindet sich wieder.
- Bonus: Backup-Status mit „Backup jetzt“-Knopf, Server-Log (letzte 200 Zeilen) und Audit-Protokoll aller Admin-Aktionen (append-only auf Platte).
- Panel im SooDreamy-Look: Liquid Glass, dunkel + hell, Deutsch/Englisch umschaltbar, funktioniert auch auf dem Handy.
- iOS 26: Die App zielt jetzt direkt auf die aktuelle OS-Generation — echtes `glassEffect` überall, keine Verfügbarkeits-Weichen mehr.
- Wieder-verbinden versteht jetzt auch selbst gewählte Ersatz-Codes je Mitglied und ist bei Groß-/Kleinschreibung des Schlüssels nachsichtig.

#### Feinschliff
- Der Server akzeptiert einfaches HTTP jetzt standardmäßig (für Heim-Setups ohne Reverse-Proxy); `REQUIRE_HTTPS=1` erzwingt weiterhin TLS.

#### Ehrliche Grenzen
- Das Admin-Passwort steht bewusst NUR im Konsolen-Log und gilt nur bis zum nächsten Neustart — wer es verpasst, startet den Server einfach neu.
- Das Panel läuft über dieselbe Transport-Regel wie die API: öffentlich erreichbar bitte nur hinter HTTPS.

### English

#### New
- **Admin web panel** (`/admin`): the server now ships an operator UI — same process, no extra service. The password is regenerated on **every server start** (cryptographically random, four typable word groups) and shown **only in the console**, nicely framed together with the URL.
- Couples overview: every couple with members, last activity, device app versions, data footprint (messages, photos, videos, …) and segment health including quarantine state.
- Reset codes: fresh invite, recovery and replace codes per couple or slot — with a confirmation dialog; old codes become invalid.
- Log out devices: inspect all sessions per couple/slot (device name, last seen) and revoke them individually or all at once — takes effect immediately.
- Login QR: a fresh rejoin token per slot rendered as a QR code with the deep link `sooodreamy://rejoin?server=…&token=…` — scan with the phone, the app re-attaches.
- Bonus: backup status with a “Backup now” button, server log tail (last 200 lines) and an append-only audit trail of every admin action.
- The panel wears the SooDreamy look: liquid glass, dark + light, German/English toggle, works on the phone too.
- iOS 26: the app now targets the current OS generation directly — real `glassEffect` everywhere, no availability gates left.
- Reconnect now also understands self-chosen per-member replace codes and forgives the recovery key’s letter case.

#### Polish
- The server accepts plain HTTP by default now (for home setups without a reverse proxy); `REQUIRE_HTTPS=1` still enforces TLS.

#### Honest limits
- The admin password deliberately lives ONLY in the console log and only until the next restart — if you miss it, just restart the server.
- The panel obeys the same transport rule as the API: if it is reachable publicly, put it behind HTTPS.

## 10.0.0 — Der große Runde / The big round one

### Deutsch

#### Neu
- Das Sicherheitsnetz: Beim Koppeln bekommt jede Person einen Wiederherstellungs-Schlüssel (`rec_…`) — er wandert automatisch in den iCloud-Schlüsselbund und wird einmalig zum Aufschreiben angezeigt. Der Server kennt nur seinen SHA-256-Fingerabdruck, nie den Schlüssel selbst. Wer vor 10.0 gekoppelt hat, bekommt den Schlüssel beim ersten Start still nachgereicht.
- „Wieder verbinden“: Der dritte Weg auf dem Koppel-Bildschirm. Neues Handy oder App neu installiert? Paar-Code + Schlüssel (steckt der im Schlüsselbund, reicht EIN Tipp) — und euer ganzer gemeinsamer Platz ist wieder da: Verlauf, Statistiken, Abzeichen, alles.
- Sitzungen heilen sich selbst: Läuft die Anmeldung ab, verbindet die App sich im Hintergrund neu (alter Token oder Schlüssel als Beweis), statt euch auszuloggen. Das alte „Anmeldung abgelaufen — bitte neu koppeln“ ist Geschichte.
- Schatz ausgesperrt? In Einstellungen → Sicherheitsnetz erzeugst du einen einmaligen Ersatz-Code (15 Minuten gültig) — damit kommt dein Schatz ohne Schlüssel zurück auf seinen eigenen Platz. Alle alten Geräte und der alte Schlüssel des ersetzten Platzes werden dabei ungültig.
- Onboarding neu gebaut: Vier Liquid-Glass-Seiten erklären vor dem ersten Koppeln, was die App kann, wem der Server gehört — und warum ihr euch nie aussperren könnt. Mit Sprach-Umschalter und Überspringen.
- Icon Nummer zehn: „Aurora“ — Polarlicht-Türkis über nachtschwarzem Himmel — macht die Icon-Familie zur Version 10 komplett. Natürlich verschenkbar.

#### Behoben
- Ein 401 einer einzelnen Anfrage warf bisher sofort die komplette Sitzung weg (Logout, Socket zu, „bitte neu koppeln“) — jetzt wird erst repariert und nur im echten Ernstfall ausgeloggt.
- Mehrere gleichzeitige 401 (z. B. beim App-Start mit abgelaufenem Token) starten genau EINE Reparatur statt eines Wettrennens in den Logout.

#### Feinschliff
- Einstellungen aufgeräumt: Neue Karte „Sicherheit & Wiederherstellung“ (App-Sperre + Sicherheitsnetz an einem Ort); die fünf handgebauten Navigationszeilen sind jetzt eine wiederverwendbare Komponente.
- Performance-Pass: Widgets werden nur noch neu geladen, wenn sich für sie sichtbar etwas geändert hat — vorher stieß JEDES Socket-Ereignis ein `reloadAllTimelines()` an und verbrannte das WidgetKit-Budget.
- Der Koppel-Bildschirm erkennt „schon zu zweit“ (409) und wechselt selbst zum Wieder-verbinden-Tab, statt nur einen Fehler zu zeigen.

#### Ehrliche Grenzen
- Der iCloud-Schlüsselbund braucht eine Signatur mit Schlüsselbund-Berechtigung; nackte Sideloads speichern den Schlüssel nur lokal — dann zählt der Zettel.
- Der Ersatz-Code ist bewusst mächtig: Er ersetzt die Geräte des Schatzes und macht dessen alten Schlüssel ungültig. Deshalb: einmal verwendbar, 15 Minuten, nur vom verbleibenden Partner erzeugbar.
- „Wieder verbinden“ setzt voraus, dass das Paar noch auf dem Server existiert — ein aufgelöstes Paar bleibt aufgelöst.

### English

#### Features
- The safety net: pairing hands each person a recovery key (`rec_…`) — it goes into the iCloud keychain automatically and is shown once for writing down. The server only ever knows its SHA-256 fingerprint, never the key itself. Anyone paired before 10.0 gets a key quietly on first launch.
- "Reconnect": the third path on the pairing screen. New phone or fresh install? Couple code + key (if it's in the keychain, ONE tap is enough) — and your whole shared place is back: history, stats, badges, everything.
- Sessions heal themselves: when the login expires, the app re-attaches in the background (old token or key as proof) instead of logging you out. The old "session expired — please pair again" is history.
- Love locked out? In Settings → Safety net you create a one-time replace code (valid 15 minutes) — it brings your love back to their own slot without a key. All old devices and the replaced slot's old key become invalid in the process.
- Onboarding rebuilt: four Liquid Glass pages explain — before the first pairing — what the app does, who owns the server, and why you can never lock yourselves out. With language switch and skip.
- Icon number ten: "Aurora" — polar-light teal over a night-black sky — completes the icon family for version 10. Giftable, of course.

#### Fixed
- A single request's 401 used to throw away the whole session instantly (logout, socket closed, "please pair again") — now the app repairs first and only logs out when it truly cannot.
- Several simultaneous 401s (e.g. app launch with an expired token) start exactly ONE repair instead of racing each other into a logout.

#### Polish
- Settings tidied: new "Security & recovery" card (app lock + safety net in one place); the five hand-built navigation rows are now one reusable component.
- Performance pass: widgets only reload when something they can actually show changed — previously EVERY socket event triggered `reloadAllTimelines()` and burned the WidgetKit budget.
- The pairing screen recognizes "already two" (409) and switches to the reconnect tab by itself instead of just showing an error.

#### Honest limits
- The iCloud keychain needs a signature with keychain entitlements; bare sideloads store the key locally only — then the piece of paper counts.
- The replace code is deliberately powerful: it replaces your love's devices and invalidates their old key. Hence: single use, 15 minutes, only the remaining partner can create it.
- "Reconnect" requires the couple to still exist on the server — a dissolved couple stays dissolved.

## 9.0.0 — Nähe trotz Distanz / Close despite distance

### Deutsch

#### Neu
- Denk-an-dich-Puls: Das schwebende 💭 schickt jetzt ein fühlbares Vibrationsmuster — drei sanfte Klopfer, eine Gute-Nacht-Welle, ein ruhiger Herzschlag oder eine anschwellende Umarmung (Langdruck wählt). Beim Senden spielt euer Handy dasselbe Muster, das ankommt.
- Pulse warten: War die App des Schatzes zu, hebt der Server den Puls auf und spielt ihn beim nächsten Öffnen ab — verpasste Pulse werden GEFÜHLT, nicht nur gelesen. Und wenn er gefühlt wurde, kommt eine leise Bestätigung zurück: „hat deinen Puls gefühlt“.
- Fokus & Schlafen: Ein kleiner Modus-Chip neben eurer Stimmung sagt sanft Bescheid, wenn ihr gerade nicht antworten könnt — mit optionaler Notiz und Auto-Ende (30 Minuten bis 8 Stunden oder offen). Der Modus läuft pünktlich von selbst aus.
- Partner-Status-Glow: Der Avatar eures Schatzes leuchtet im Modus-Licht (🎯 blau, 😴 violett) — auf dem Dashboard UND im Sperrbildschirm-Puls samt Dynamic Island.

#### Behoben
- Der Modus-Status kann nicht mehr „hängen bleiben“: Ablauf wird bei jedem Lesen geprüft (lazy, ohne Timer) — beide Handys und der Server kommen deterministisch zum selben Ergebnis, auch nach Neustarts.

#### Feinschliff
- Setzt der Schatz einen Modus, erscheint ein einmaliger sanfter Hinweis („ist gerade im Fokus — Antworten dürfen warten“) statt eines fordernden Alerts — bewusst ohne Ton.
- Der Puls-Knopf legt nach dem Senden eine sichtbare 30-Sekunden-Pause ein, statt Fehler zu sammeln.

#### Ehrliche Grenzen
- Eine seitgeladene App kann ein geschlossenes iPhone nicht vibrieren lassen: Offline-Pulse summen erst beim nächsten App-Öffnen (die Push-Banner-Nachricht kommt sofort, wenn Push eingerichtet ist).
- Pulse und Modi geben absichtlich keine XP und schalten keine Abzeichen frei — Nähe ist kein Grind.
- Höchstens ein Puls pro 30 Sekunden, pro Paar bleiben die letzten 100 gespeichert.

### English

#### Features
- Thinking-of-you pulse: the floating 💭 now sends a feelable vibration pattern — three soft knocks, a goodnight wave, a calm heartbeat, or a swelling hug (long-press to pick). Sending plays the exact pattern that arrives on the other side.
- Pulses wait: if your sweetheart's app was closed, the server keeps the pulse and plays it on the next open — missed pulses are FELT, not just read. And once felt, a quiet receipt comes back: "felt your pulse".
- Focus & sleep: a small mode chip next to your mood gently signals when you can't reply right now — with an optional note and auto-end (30 minutes to 8 hours, or open-ended). The mode expires on time by itself.
- Partner status glow: your sweetheart's avatar glows in the mode's light (🎯 blue, 😴 violet) — on the dashboard AND in the lock-screen pulse plus Dynamic Island.

#### Fixed
- The mode status can no longer get "stuck": expiry is checked on every read (lazy, no timers) — both phones and the server deterministically agree, even across restarts.

#### Polish
- When your sweetheart sets a mode, a single soft hint appears ("is in focus right now — replies can wait") instead of a demanding alert — deliberately silent.
- The pulse button takes a visible 30-second breather after sending instead of collecting errors.

#### Honest limits
- A sideloaded app cannot vibrate a closed iPhone: offline pulses buzz on the next app open (the push banner arrives immediately if push is set up).
- Pulses and modes deliberately award no XP and unlock no badges — closeness is not a grind.
- At most one pulse per 30 seconds; the last 100 per couple are kept.

## 8.0.0 — Erinnerungen / Memories

### Deutsch

#### Neu
- „An diesem Tag“: Heute vor genau X Monaten oder Jahren — Fotos und gemeinsam beantwortete Tagesfragen tauchen als Erinnerung auf dem Dashboard wieder auf, deterministisch und auf beiden Handys identisch.
- „Unsere Geschichte“: Eure Meilenstein-Zeitreise im Erinnerungen-Tab — Kopplungstag, Jahrestag, erste Nachricht, erstes Foto, erste Tagesfrage zu zweit, Zähl-Meilensteine (10. Foto, 100. Nachricht, …) und freigeschaltete Abzeichen, Monat für Monat.
- „An diesem Tag“-Widget: Die Erinnerung von heute auf dem Homescreen, inklusive Foto und „vor X Monaten“-Abstand — konfigurierbar im Widget-Studio wie alle anderen.

#### Behoben
- Halb beantwortete Tagesfragen bleiben auch als Erinnerung privat: Nur Tage, an denen BEIDE geantwortet haben, dürfen wieder auftauchen — die Anti-Spoiler-Regel überlebt den Tag selbst.
- Das Erinnerungs-Widget versteckt gestrige Erinnerungen nach Mitternacht von selbst, statt den falschen Tag zu behaupten.

#### Feinschliff
- Die Dashboard-Erinnerung teilt sich per Langdruck in den Chat — Fotos als echte Foto-Nachricht, Fragen mit beiden Antworten von damals.
- Monats-Abstände sprechen sauber Deutsch und Englisch („vor 1 Monat“, „vor 3 Jahren“, „2 years ago“).

#### Ehrliche Grenzen
- „An diesem Tag“ matcht nur den exakten Kalendertag — der 31. Januar hat im Februar schlicht keine Monats-Erinnerung, statt unscharf zu raten.
- „Erste Male“ sind die ältesten NOCH GESPEICHERTEN Einträge: Sehr alte Nachrichten (Limit 5000), Berührungen und Spiele rollen aus dem Server-Speicher; die Geschichte beginnt dann später, statt Daten zu erfinden.

### English

#### Features
- "On this day": exactly X months or years ago today — photos and dailies you both answered resurface as memories on the dashboard, deterministic and identical on both phones.
- "Our story": your milestone time journey in the memories tab — pairing day, anniversary, first message, first photo, first daily answered together, count milestones (photo #10, message #100, …) and unlocked badges, month by month.
- "On this day" widget: today's memory on your home screen, photo and "X months ago" distance included — styled in the Widget Studio like every other widget.

#### Fixed
- Half-answered dailies stay private even as memories: only days where BOTH answered may resurface — the anti-spoiler rule outlives the day itself.
- The memory widget hides yesterday's memory after midnight by itself instead of claiming the wrong day.

#### Polish
- The dashboard memory shares to chat via long-press — photos as a real photo message, questions with both answers from back then.
- Month distances speak proper German and English ("vor 1 Monat", "vor 3 Jahren", "2 years ago").

#### Honest limits
- "On this day" matches the exact calendar day only — January 31 simply has no February memory instead of fuzzy guessing.
- "Firsts" are the oldest entries STILL STORED: very old messages (cap 5000), touches, and games rotate out of server storage; the story then starts later instead of inventing dates.

## 7.0.0 — Rituale / Rituals

### Deutsch

#### Neu
- „Eure Woche in Zahlen“: Jede ISO-Woche wird zu einem kleinen Liquid-Glass-Rückblick — Nachrichten, Berührungen, Spiele, perfekte Tage, Zitat der Woche und Foto der Woche, plus Lese-Bestätigung für abgeschlossene Wochen.
- Highlight-Ritual: Beide teilen ihren Moment der Woche; was der andere gewählt hat, zeigt sich erst, wenn beide geteilt haben — serverseitig erzwungen, wie beim Fragenspiel.
- Eigene Tagesfragen: Beide füttern heimlich einen gemeinsamen Fragen-Topf. Ungefähr jeden dritten Tag stellt SoooDreamy eine Frage daraus — die Autorschaft bleibt bis zur beidseitigen Antwort geheim.

#### Behoben
- Einmal gestellte Topf-Fragen werden mit der ersten Antwort am Tag festgeschrieben; späteres Löschen oder Ergänzen im Topf verändert keine bereits gestellte Frage mehr.

#### Feinschliff
- Der Wochen-Rückblick lässt sich mit einem Tipp in den Chat teilen; beim beidseitigen Enthüllen gibt es Konfetti, Klang und einen sanften Hinweis, wenn der Partner zuerst geteilt hat.
- Die Tagesfrage zeigt an Topf-Tagen ein dezentes Abzeichen: erst „Eine eurer eigenen Fragen“, nach der Auflösung „Frage von …“.

#### Ehrliche Grenzen
- Wochen- und Tagesgrenzen rechnen in UTC (wie alle dateKeys der App) — wer um Mitternacht herum antwortet, kann den Eintrag in der Nachbarwoche landen sehen.
- Highlights lassen sich nur für die laufende und die vergangene Woche teilen — das Ritual lebt von Frische, nicht vom Nachtragen.

### English

#### Features
- "Your week in numbers": every ISO week becomes a small liquid-glass review — messages, touches, games, perfect days, quote of the week and photo of the week, plus read receipts for completed weeks.
- Highlight ritual: both partners share their moment of the week; the other's pick reveals only once both shared — server-enforced, exactly like the daily question.
- Own daily questions: both secretly feed a shared question pool. Roughly every third day SoooDreamy asks one of them — authorship stays hidden until both answered.

#### Fixed
- Pool questions are pinned with the day's first answer; deleting or adding questions later never changes an already-asked question.

#### Polish
- The weekly review shares to chat with one tap; the mutual reveal brings confetti, sound, and a gentle nudge when the partner shared first.
- On pool days the daily question wears a subtle badge: first "One of your own questions", after the reveal "Question by …".

#### Honest limits
- Week and day boundaries use UTC (like every dateKey in the app) — answers around midnight may land in the neighboring week.
- Highlights can only be shared for the current and previous week — the ritual lives on freshness, not on backfilling.

## 6.0.0 — Zusammen, überall / Together, Anywhere

### Deutsch

#### Neu
- Der neue Assistent unter Mehr → Server-Umzug führt durch Export, frisches Zielpaar, Prüfung, Import und erneute Partner-Kopplung.
- Logische Paar-Daten werden mit Schema, Quellversion und SHA-256-Prüfsumme exportiert; die App legt sie ausschließlich als AES-GCM-verschlüsselte Datei mit eigener Passphrase ab.
- Server A → Server B ist als echter API-End-to-End-Vertrag geprüft: Nachrichten, Momente, Listen, Profile und weitere logische Inhalte bleiben gleich.

#### Behoben
- Tokens und Gerätesitzungen werden niemals migriert. Die aktuelle Ziel-Sitzung wird sicher auf die importierte Identität abgebildet; der Partner erhält erst durch den neuen Code einen neuen Token.
- Manipulierte Dateien, unbekannte zukünftige Schemata und Ziele mit vorhandenen Aktivitäten werden abgewiesen, ohne Daten zu verändern.

#### Feinschliff
- „Neu in 6.0“ führt direkt zum Assistenten; alle Texte und Sicherheitswarnungen liegen vollständig auf Deutsch und Englisch vor.
- Der Abschluss-Audit verbindet 15 versionierte Quellstände, Testnachweise, Farm-Builds und unsignierte IPAs.

#### Ehrliche Grenzen
- Der In-App-Umzug überträgt logische JSON-Daten. Große Foto-, Video-, Sprach- und Vault-Binärdateien bleiben im Datenordner des alten Servers und müssen durch den Server-Admin separat kopiert werden.
- Das IPA ist unsigniert. Push, iCloud und echte Geräte-Haptik hängen weiterhin von Signierung und Hardware ab. Geräteprüfung: nein.

### English

#### Features
- A new assistant under More → Server migration guides export, fresh destination couple, review, import, and partner re-pairing.
- Logical couple data exports with schema, source version, and SHA-256 digest; the app writes it only as an AES-GCM encrypted file protected by a separate passphrase.
- Server A → server B is covered by a real API end-to-end contract: messages, moments, lists, profiles, and other logical content remain equal.

#### Fixed
- Tokens and device sessions never migrate. The current destination session is safely mapped to the imported identity; the partner receives a new token only through the new code.
- Tampered files, unknown future schemas, and destinations with existing activity are rejected without changing data.

#### Polish
- “New in 6.0” links directly to the assistant; every instruction and security warning is complete in German and English.
- The final audit connects 15 versioned source states, test evidence, farm builds, and unsigned IPAs.

#### Honest limits
- The in-app migration transfers logical JSON data. Large photo, video, voice, and Vault binary files remain in the old server data directory and need a separate server-admin copy.
- The IPA is unsigned. Push, iCloud, and physical-device haptics still depend on signing and hardware. Device verified: no.

## 5.4.0 — Der große Feinschliff / The Great Polish Wave

### Deutsch

#### Neu
- Keine neuen Produktfunktionen: Diese Version ist bewusst ein Fix- und Konsistenz-Release.
- Ein ausführbarer Zustands-Audit hält für zwölf zentrale Oberflächen Laden, Leer, Inhalt, Offline und Fehler fest.

#### Behoben
- Die Überschrift des App-Bereichs in den Einstellungen läuft jetzt durch die DE/EN-Lokalisierung.
- Geteilte Kopplungseinladungen kommen aus einer gemeinsamen lokalisierten Vorlage statt aus fest verdrahteten Sprachzweigen.
- Release-Tests verhindern künftig auseinanderlaufende App-, Build-, Server-, Patchnotes- und Handbuchversionen.

#### Feinschliff
- Alle geprüften Interaktionsanimationen bleiben im nicht blockierenden Rahmen von 150–450 ms.
- Der Master-Rubrik-Audit und das Zustandsinventar dokumentieren die vollständige App-Prüfung vor 6.0.

#### Ehrliche Grenzen
- Die kanonische Screenshot-Baseline wird über CI/Simulator-Builds erzeugt; Kamera, Mikrofon, echte Haptik und biometrische Dialoge bleiben ohne Gerät ungeprüft.
- Das IPA ist unsigniert. Geräteprüfung: nein.

### English

#### Features
- No new product capability: this release deliberately focuses on fixes and consistency.
- An executable state audit records loading, empty, content, offline, and failure behavior for twelve key surfaces.

#### Fixed
- The Settings app-section heading now goes through DE/EN localization.
- Shared pairing invitations use one localized template instead of hard-coded language branches.
- Release tests now prevent app, build, server, patch-note, and manual versions from drifting apart.

#### Polish
- Every audited interaction animation stays inside the non-blocking 150–450 ms budget.
- The master rubric and state inventory record the full-app review before 6.0.

#### Honest limits
- CI/simulator builds produce the canonical screenshot baseline; camera, microphone, physical haptics, and biometric dialogs remain unverified without a device.
- The IPA is unsigned. Device verified: no.

## 5.3.0 — Eure Farben / Personalization & Delight

### Deutsch

#### Neu
- Eure beiden Profilfarben werden zu einem synchronisierten Paar-Farbschema für Hintergründe, Chatblasen und Widgets; drei Presets und eigene `#RRGGBB`-Farben stehen bereit.
- Kosenamen ersetzen den Profilnamen in persönlichen Sätzen, ohne deutsche oder englische Satzteile zusammenzukleben.
- Euer prozedurales Monogramm erscheint als Wachssiegel auf Briefen, Monatsmagazinen und Saisonkalendern.
- Der Chat bietet Herzen, Schnee, Funkelspur, Feuerwerk, Wumms und unsichtbare Tinte sowie eine rein prozedurale Sticker-Werkstatt.
- Drei geheime Gesten warten im Herz, im Jahrestagsdatum und auf der Über-Seite.

#### Behoben
- Eigene Akzentfarben werden auf mindestens 4,5:1 Kontrast geprüft und bei der Ableitung automatisch aufgehellt.
- Wiederholte Sendeeffekte werden auf Client und Server begrenzt, damit Überraschungen besonders bleiben.

#### Feinschliff
- Das Paar-Farbschema wird live zwischen beiden Geräten synchronisiert und als Widget-Theme in die App Group gespiegelt.
- Die animierte Credits-Zeremonie rückt „made by Sonic0810“ in den Mittelpunkt.

#### Ehrliche Grenzen
- Die Sticker-Werkstatt zeichnet Formen aus einer kleinen prozeduralen Formensammlung; sie verspricht weder Foto-Freistellung noch KI-Erkennung. IPA unsigniert.

### English

#### Features
- Both profile colors now derive a synced couple palette for backgrounds, chat bubbles, and widgets, with three presets plus custom `#RRGGBB` colors.
- Pet names replace profile names in personal copy through whole-sentence German and English templates.
- Your procedural monogram appears as a wax seal on letters, monthly magazines, and season calendars.
- Chat adds hearts, snow, sparkle trail, fireworks, slam, and invisible ink plus a fully procedural Sticker Workshop.
- Three secret gestures hide in the heart, the anniversary date, and the About screen.

#### Fixed
- Custom accents are checked for at least 4.5:1 contrast and automatically lightened during derivation.
- Repeated send effects are rate-limited on client and server so surprises stay special.

#### Polish
- The couple palette syncs live to both devices and is mirrored into the App Group as a widget theme.
- An animated credits ceremony spotlights “made by Sonic0810.”

#### Honest limits
- Sticker Workshop draws from a small procedural shape set; it does not promise photo cutout or AI recognition. IPA unsigned.

## 5.2.0 — Leistung & Verlässlichkeit / Performance & Reliability

### Deutsch

#### Neu
- Die Offline-Outbox schützt jetzt zusätzlich Reaktionen, Tagesantworten, Quest-Haken und Spielbewertungen mit stabilen Idempotenz-IDs.
- Der Server migriert die große `store.json` beim Start verlustfrei in atomare Paar-Segmente; `/api/health` zeigt JSON-/Mediengröße und Medienquote.
- Kaltstart-Signposts messen den Weg bis zum Dashboard, damit das 2,5-Sekunden-Budget reproduzierbar geprüft werden kann.

#### Behoben
- WebSocket-Neuverbindungen besitzen exponentiellen Backoff mit Zufallsstreuung und erzeugen nach Router-/Serverausfällen keinen Gleichschritt-Sturm mehr.
- Galerie-, Vault- und Widget-Bilder werden direkt auf ein begrenztes Pixelbudget dekodiert statt zunächst in voller Kameraauflösung.

#### Feinschliff
- Optimistische Aktionen werden erst nach eindeutiger Serverbestätigung aus der Warteschlange entfernt; verlorene Antworten wenden dieselbe Aktion nicht doppelt an.
- Serversegmente schreiben nur tatsächlich geänderte Paare und räumen verwaiste beziehungsweise temporäre Segmente auf.

#### Ehrliche Grenzen
- Medien-Uploads bleiben absichtlich außerhalb der Offline-Warteschlange; große Binärdaten brauchen eine aktive Verbindung.
- Startup-Signposts liefern Messdaten für Instruments/CI, versprechen aber keine identische Laufzeit auf jedem iPhone. IPA unsigniert.

### English

#### Features
- The offline outbox now protects reactions, daily answers, quest checks, and game ratings with stable idempotency ids.
- At startup the server losslessly migrates the large `store.json` into atomic couple segments; `/api/health` reports JSON/media size and quota.
- Cold-start signposts measure the path to the dashboard so the 2.5-second budget can be checked reproducibly.

#### Fixed
- WebSocket reconnects use exponential backoff with jitter and no longer create a lockstep storm after router or server outages.
- Gallery, Vault, and widget images decode directly to a bounded pixel budget instead of first materializing full camera resolution.

#### Polish
- Optimistic actions leave the queue only after unambiguous server acknowledgement; a lost response cannot apply the same action twice.
- Server segments rewrite only changed couples and clean orphaned or temporary segments.

#### Honest limits
- Media uploads deliberately remain outside the offline queue; large binary data still needs an active connection.
- Startup signposts provide Instruments/CI evidence, not an identical runtime promise for every iPhone. IPA unsigned.

## 5.1.0 — Spiele-Offensive II / Games Wave II

### Deutsch

#### Neu
- Wortkette-Blitz ist eine tägliche asynchrone Kette mit servergeprüftem Anfangsbuchstaben, Wiederholungsschutz und deutsch/englischem Wörterbuch.
- Galgenraten „Unser Wort“ versiegelt das geheime Wort per SHA-256 Commit-Reveal; zehn Fehlversuche lassen die Herzblume sanft welken statt eine Galgenfigur zu zeichnen.
- Paar-Bingo mischt wöchentlich 16 Beziehungsmomente und hakt sie ausschließlich aus echten, validierten App-Ereignissen ab.
- Alle 19 Spiele besitzen ein fortsetzbares 3-Schritt-Intro und einen lokalen Übungsimpuls ohne Serverzug, Ergebnis oder XP.

#### Behoben
- Spielzüge und Ergebnisse der drei neuen Spiele sind serverautoritativ; Bingo-Felder können nicht vom Client gefälscht werden.
- Der Spielen-Hub ordnet Täglich, Asynchron, Live zusammen und Party neu; „Du bist dran“ bleibt immer vor dem Katalog.

#### Feinschliff
- 60 zweisprachige Bingo-Aktionen, große Galgenraten-Pakete und geprüfte Kettenwörter sind vollständig schema- und logikgetestet.
- Bingo- und Spielende-Feiern erreichen beide Geräte über die vorhandenen Echtzeitereignisse.

#### Ehrliche Grenzen
- Der Übungsmodus bleibt bewusst lokal und vergibt weder XP noch Turnierpunkte.
- Das IPA ist unsigniert; Remote-Zughinweise brauchen weiterhin ein Push-fähiges signiertes Profil.

### English

#### Features
- Word Chain Blitz is a daily async chain with server-checked initials, repeat protection, and German/English dictionaries.
- “Our Word” Hangman seals the secret through SHA-256 commit-reveal; ten misses gently wilt a heart flower instead of drawing a gallows.
- Couple Bingo shuffles 16 weekly relationship moments and checks them only from real, validated app events.
- All 19 games include a resumable three-step intro and a local practice prompt with no server move, result, or XP.

#### Fixed
- Moves and outcomes for all three new games are server-authoritative; clients cannot forge Bingo checks.
- The Play hub now groups Daily, Async, Live together, and Party while “You’re up” always stays before the catalog.

#### Polish
- Sixty bilingual Bingo actions, large Hangman packs, and validated chain words are covered by schema and logic tests.
- Bingo and end-game ceremonies reach both phones through the existing realtime event path.

#### Honest limits
- Practice deliberately stays local and awards no XP or tournament points.
- The IPA is unsigned; remote turn alerts still need a push-capable signed profile.

## 5.0.0 — Saisonkalender & Feste / Season Calendar & Celebrations

### Deutsch

#### Neu
- Türchen-Kalender lassen euch Advent, Geburtstag, Jahrestag oder einen eigenen Countdown mit bis zu 31 Impulsen, Mini-Quests, Briefen und Spielen vorbereiten.
- Der Server hält jedes Türchen bis zu seinem eigenen Zeitpunkt gesperrt und enthüllt den Inhalt ausschließlich für den Empfänger.
- Valentinstag, Halloween, Silvester und euer Jahrestag schlagen passende Fest-Rahmen und Widget-Looks vor; nichts wird ungefragt angewendet.

#### Behoben
- Automatische Saison-Themes unterstützen jetzt ausdrücklich Nord- und Südhalbkugel.
- Die Türchen-Datumslogik bleibt über Sommerzeit, Monatsgrenzen und Schalttage auf dem lokalen Kalendertag.

#### Feinschliff
- 60 zweisprachige Türchen-Vorlagen machen auch längere Kalender schnell erstellbar.
- Geöffnete Kalender bleiben als gemeinsames Archiv erhalten; ungeöffnete Kalender kann nur die erstellende Person löschen.

#### Ehrliche Grenzen
- Fest-Rahmen und Widget-Skins sind Vorschläge, keine automatisch erzwungenen Designs.
- Ohne signiertes Push-Profil erinnert die App lokal bzw. beim nächsten Öffnen; die serverseitige Sperre bleibt trotzdem verbindlich. IPA unsigniert.

### English

#### Features
- Countdown calendars let you prepare Advent, a birthday, an anniversary, or a custom countdown with up to 31 prompts, mini quests, letters, and games.
- The server locks every door until its own deadline and reveals its content only to the recipient.
- Valentine's Day, Halloween, New Year, and your anniversary suggest fitting event frames and widget looks; nothing is applied without asking.

#### Fixed
- Automatic season themes now explicitly support both northern and southern hemispheres.
- Door date math stays on the local calendar day across daylight-saving changes, month boundaries, and leap days.

#### Polish
- 60 bilingual door templates make longer calendars quick to author.
- Opened calendars remain a shared archive; only the author can delete an unopened calendar.

#### Honest limits
- Event frames and widget skins are suggestions, not automatically forced designs.
- Without a signed push profile, reminders are local or appear on the next app open; server-side locks still remain authoritative. IPA unsigned.

## 4.9.0 — Sprache & Zugänglichkeit / Localization & Accessibility

### Deutsch

#### Neu
- Ein 44-Punkt-? ist auf allen fünf Tabs erreichbar und öffnet das gebündelte Markdown-Handbuch direkt beim passenden Kapitel.
- Das Handbuch ist in Deutsch und Englisch feature-vollständig; ein Test ordnet jede der mindestens 61 Feature-Ansichten einem stabilen Kapitelanker zu.
- Die Lokalisierung besitzt geprüfte Einzahl-/Mehrzahl-Formen und zentrale Formatter für Datum, Monat, Uhrzeit, Zahl, Zielwert und Dauer.

#### Behoben
- Eigene Datums-/Zahlenformatierungen folgen nun durchgängig der gewählten App-Sprache statt versehentlich der Gerätesprache.
- Ein Quellcode-Gate blockiert neue unübersetzte `Text("…")`-Literale außerhalb einer kleinen geprüften Marken-/Akronym-Liste.

#### Feinschliff
- Dashboard-Gruppen und Chat-Tab sagen Einzahl und Mehrzahl für VoiceOver grammatisch korrekt.
- Die In-App-Hilfe umbricht per Dynamic Type, behält semantische Überschriften und führt pro Kapitel eigene Fehlerhilfe.

#### Ehrliche Grenzen
- Accessibility Inspector und VoiceOver sind per Code, Tests und macOS-Build abgedeckt; ein vollständiger physischer VoiceOver-Gerätelauf wurde nicht durchgeführt.
- IPA unsigniert.

### English

#### Features
- A 44-point ? is reachable from all five tabs and opens the bundled Markdown manual at the matching chapter.
- The German and English manuals are feature-complete; a test maps every one of at least 61 feature views to a stable chapter anchor.
- Localization adds tested singular/plural forms and central formatters for dates, months, times, numbers, goal values, and durations.

#### Fixed
- Custom date and number presentation now consistently follows the selected app language instead of accidentally using the device language.
- A source gate blocks new untranslated `Text("…")` literals outside a small reviewed brand/acronym allowlist.

#### Polish
- Home groups and the Chat tab announce singular and plural counts grammatically for VoiceOver.
- In-app help wraps with Dynamic Type, preserves semantic headings, and includes troubleshooting in every chapter.

#### Honest limits
- Accessibility Inspector and VoiceOver behavior are covered by code, tests, and the macOS build; a complete physical-device VoiceOver pass was not performed.
- IPA unsigned.

## 4.8.0 — Aussprache & Rücksicht / Repair & Consideration

### Deutsch

#### Neu
- Der Aussprache-Modus schützt sechs ruhige Züge: Gefühl, Spiegeln, Rollenwechsel und eine gemeinsame kleine Vereinbarung; der Server erzwingt Person und Schritt.
- Der strikt freiwillige Rücksicht-Radar verschlüsselt Hinweise auf dem Gerät mit dem Vault-Schlüssel, lässt sie sofort pausieren und verbindet sie bewusst weder mit XP noch Serien.
- „3 gute Dinge“ sammelt abends drei Lichtblicke pro Person und enthüllt beide Listen erst, wenn beide geteilt haben.

#### Behoben
- Zeitkapsel-Listen wechseln am serverseitigen Freigabezeitpunkt live von „versiegelt“ zu „bereit“.
- Monatsmagazine lassen sich als gerendertes Bildset über das iOS-Teilen-Menü exportieren.

#### Feinschliff
- 30 Aussprache-, 20 Rücksicht- und 25 Dankbarkeitsimpulse sind in Deutsch und Englisch vollständig sowie schema-geprüft.
- Der neue Bereich bleibt visuell ruhig: keine Feier-Sounds, keine Partikel und nur bestätigende Haptik nach erfolgreichen Schreibvorgängen.

#### Ehrliche Grenzen
- Der Aussprache-Modus ist ein Gesprächswerkzeug, keine Therapie oder Krisenhilfe.
- Rücksicht-Hinweise sind nur lesbar, wenn beide Geräte denselben Vault-Schlüssel entsperrt haben. IPA unsigniert; echter Gerätetest: nein.

### English

#### Features
- Repair Conversation protects six calm turns: feeling, mirroring, role reversal, and a shared small agreement; the server enforces actor and step.
- The strictly optional Consideration Radar encrypts hints on-device with the Vault key, pauses immediately, and deliberately has no XP or streak linkage.
- “3 Good Things” collects three evening bright spots per person and reveals both lists only after both have shared.

#### Fixed
- Time-capsule lists switch live from sealed to ready at the server unlock time.
- Monthly magazines export as a rendered image set through the iOS share sheet.

#### Polish
- 30 repair, 20 consideration, and 25 gratitude prompts are complete in German and English and schema-tested.
- The new area stays visually calm: no celebration sounds, no particles, and only confirmation haptics after successful writes.

#### Honest limits
- Repair Conversation is a conversation tool, not therapy or crisis support.
- Consideration hints are readable only after both devices unlock the same Vault key. IPA unsigned; real-device test: no.

## 4.7.0 — Widgets & Controls 3.0

### Deutsch

#### Neu
- Die iOS-18-Control-Familie ist mit „Denk an dich“ und „Date-Night starten“ neben Herzklopfen und Bedürfnis-Knopf vollständig.
- Filmstreifen wählen deterministisch bis zu drei Favoriten; der Passbildautomat zeichnet vier Frames und beide Stile tragen einen Datumsstempel.
- Das Widget-Studio bietet für jedes der acht Widgets drei sofort anwendbare Schnellstile.

#### Behoben
- Alle acht Widgets markieren Schnappschüsse, die älter als ihr natürlicher Aktualisierungstakt sind.
- Fotoauswahl dedupliziert IDs und bleibt bei identischen Serverdaten auf beiden Geräten stabil.

#### Feinschliff
- Lock-Screen-/StandBy-Flächen bleiben im Vibrant-Modus symbolisch lesbar; Frische wird nie nur durch Farbe kommuniziert.
- Auswahl-, Frische- und Preset-Verträge sind als reine Swift-Logik getestet.

#### Ehrliche Grenzen
- Controls brauchen iOS 18; unter iOS 17 werden sie vom System nicht angeboten.
- Widgets brauchen eine mitsignierte App Group. Das IPA ist unsigniert; echter StandBy-/Action-Button-Gerätetest: nein.

### English

#### Features
- The iOS 18 control family is complete: Thinking of You and Start Date Night join Heartbeat and the Need button.
- Film strips deterministically select up to three favorites; Photo Booth draws four frames and both styles carry a date stamp.
- Widget Studio offers three one-tap quick styles for each of the eight widgets.

#### Fixed
- All eight widgets mark snapshots older than their natural update cadence.
- Photo selection deduplicates IDs and stays stable across devices given identical server data.

#### Polish
- Lock Screen and StandBy surfaces remain symbolically readable in vibrant rendering; freshness never relies on color alone.
- Selection, freshness, and preset contracts are covered by pure Swift tests.

#### Honest limits
- Controls require iOS 18 and are not offered by the system on iOS 17.
- Widgets require a co-signed App Group. The IPA is unsigned; real StandBy/Action Button device test: no.

## 4.6.0 — Backup, Export & Wiederherstellung / Backup, Export & Restore

### Deutsch

#### Neu
- Verschlüsselte Datei-Backups bieten getrennte Schalter für Serverprofile, Geräte-Einstellungen, App-Group-Konfiguration und Paar-Schnappschuss.
- Wiederherstellung kann dieselben lokalen Domänen getrennt anwenden; Paar-Schnappschüsse bleiben bewusst nur lesbar.
- Ein Schema-2-Manifest beschreibt den Inhalt; alte Schema-1-Dateien werden deterministisch migriert.

#### Behoben
- Unbekannte zukünftige oder leere Backup-Manifeste werden nicht angewendet.
- Eine Restore-Transaktion besitzt einen getesteten Rollback-Pfad bei Migrationsfehlern.

#### Feinschliff
- Export bleibt standardmäßig AES-GCM + PBKDF2 (210.000 Iterationen), Tokens und Passphrase werden nie exportiert/gespeichert.
- CloudKit-/Drive-Entitlement-Grenzen bleiben vor der Aktion sichtbar.

#### Ehrliche Grenzen
- Der Paar-Server bleibt die Quelle der Wahrheit; der leichte Paar-Schnappschuss kann nicht zurück auf den Server importiert werden.
- CloudKit/Drive hängt von Signierung ab; IPA unsigniert. Echter iCloud-Gerätetest: nein.

### English

#### Features
- Encrypted file backups expose separate switches for server profiles, device settings, App Group configuration, and the couple snapshot.
- Restore can apply the same local domains independently; couple snapshots deliberately remain read-only.
- A schema-2 manifest describes contents; legacy schema-1 files migrate deterministically.

#### Fixed
- Unknown future or empty backup manifests are not applied.
- Restore transactions have a tested rollback path for migration failures.

#### Polish
- Export remains AES-GCM + PBKDF2 (210,000 iterations) by default; tokens and passphrases are never exported/stored.
- CloudKit/Drive entitlement limits remain visible before action.

#### Honest limits
- The couple server remains source of truth; the light couple snapshot cannot be imported back to the server.
- CloudKit/Drive depends on signing; IPA unsigned. Real iCloud device test: no.

## 4.5.0 — Barrierefreiheit & Responsive Polish / Accessibility & Responsive Polish

### Deutsch

#### Neu
- Dashboard-Gruppen wechseln bei großem Text automatisch in ein vertikales Layout; Badge-Werte haben vollständige VoiceOver-Texte.
- Online-/Offline-Punkte erhalten bei „Ohne Farben differenzieren“ zusätzliche ✓/×-Symbole.
- Feiern begrenzen bei Accessibility-Text ihr Partikelbudget; „Bewegung reduzieren“ rendert null Partikel und einen statischen Schimmer.

#### Behoben
- Die bisher animierte Reduce-Motion-Alternative verwendet keine Timeline mehr.
- Verbindungsaufbau ist nicht mehr ausschließlich durch Farbe erkennbar.

#### Feinschliff
- Semantische Schriftstile bleiben für Fließtext erhalten, Targets bleiben mindestens 44 Punkte.
- Policy-Tests prüfen Null-Partikel, AX-Budget und vertikale Layout-Grenzen.

#### Ehrliche Grenzen
- VoiceOver, Dynamic Type AX5 und „Ohne Farben differenzieren“ sind im Code und macOS-Build geprüft, aber nicht auf echter iOS-Hardware durchlaufen.
- IPA unsigniert.

### English

#### Features
- Home groups automatically switch to a vertical layout at large text sizes; badge values have complete VoiceOver text.
- Online/offline dots gain ✓/× symbols when Differentiate Without Color is enabled.
- Celebrations cap particle work for accessibility text; Reduce Motion renders zero particles and a static glow.

#### Fixed
- The previous Reduce Motion alternative no longer runs a timeline.
- Connecting state no longer relies on color alone.

#### Polish
- Body copy retains semantic text styles and targets remain at least 44 points.
- Policy tests cover zero particles, AX work budgets, and vertical-layout thresholds.

#### Honest limits
- VoiceOver, Dynamic Type AX5, and Differentiate Without Color are code- and macOS-build-checked but not run on physical iOS hardware.
- IPA unsigned.

## 4.4.0 — Zustands-Vollständigkeit / State Completeness

### Deutsch

#### Neu
- Replay und Turnier teilen eine definierte Matrix für Laden, Inhalt, leer, offline und Fehler.
- Offline- und Fehlerzustände erklären, was passiert ist, behalten vorhandene Inhalte und bieten einen 44-Punkt-Wiederholen-Button.
- Die App-Sperre unterscheidet Abbruch, fehlgeschlagene Erkennung und nicht verfügbare Geräte-Authentifizierung mit direktem Weg in die Systemeinstellungen.

#### Behoben
- Offline-Outbox-Versuche, Bestätigungen und Löschen sind jetzt vollständig an Profil, Paar und Mitglied gebunden — selbst bei absichtlich gleichen Client-IDs.
- Serverfehler werden in Replay/Turnier nicht mehr als „leer“ verschluckt.

#### Feinschliff
- Eine reine Zustands-Priorität ist für alle Kombinationen getestet.
- Der Outbox-Kill/Restart-, FIFO-, Dedupe-, Profilwechsel- und Delete-Vertrag bleibt atomar.

#### Ehrliche Grenzen
- Face ID/Touch ID und App-Kill-Recovery benötigen echte iOS-Hardware für die abschließende Geräteprüfung; hier nicht durchgeführt.
- IPA unsigniert.

### English

#### Features
- Replay and Tournament share a defined loading/content/empty/offline/failure matrix.
- Offline and failure states explain what happened, preserve existing content, and expose a 44-point Retry button.
- App Lock distinguishes cancellation, failed recognition, and unavailable device authentication with a direct path to System Settings.

#### Fixed
- Offline outbox attempts, acknowledgements, and deletes are now fully scoped to profile, couple, and member—even with deliberately identical client IDs.
- Replay/Tournament no longer swallow server failures as an empty state.

#### Polish
- A pure state precedence table is tested across every branch.
- Outbox kill/restart, FIFO, dedupe, profile-switch, and delete contracts remain atomic.

#### Honest limits
- Face ID/Touch ID and killed-app recovery need real iOS hardware for final device validation; not performed here.
- IPA unsigned.

## 4.3.0 — Spielen: Replay & Turnier / Play: Replay & Tournament

### Deutsch

#### Neu
- Alle 21 kanonischen Spieltypen besitzen explizite Replay-Adapter; Zuschauer- und Teilen-Flows bleiben erhalten.
- Der Server liefert eine kanonische Saison über alle aufbewahrten Partien plus Wordle DE/EN.
- Die Spielhistorie ist mit `cursor` paginiert; bis zu 1.000 Sitzungen bleiben für Replay und Saison erhalten.

#### Behoben
- Turniere sind nicht mehr auf die letzten 100 Client-Sitzungen begrenzt.
- Kooperative Partien zählen fair als gemeinsames Ergebnis statt unsichtbar aus der Saison zu fallen.

#### Feinschliff
- Die iOS-Saisonansicht konsumiert den Server-Aggregatvertrag direkt.
- Ein 250-Partien-Stressfixture plus Wordle beweist vollständige, deterministische Monatsfilterung.

#### Ehrliche Grenzen
- Replays zeigen nur serverseitig gespeicherte Züge; sehr alte, bereits vor 4.3 entfernte Sitzungen können nicht rekonstruiert werden.
- IPA unsigniert; echter Zwei-Geräte-Zuschauerlauf: nicht auf Hardware geprüft.

### English

#### Features
- All 21 canonical game types have explicit replay adapters while spectator and share flows remain intact.
- The server exposes one canonical season across all retained matches plus DE/EN Wordle.
- Game history is cursor-paginated and up to 1,000 sessions remain available for replay and seasons.

#### Fixed
- Tournaments are no longer limited to the latest 100 client-fetched sessions.
- Cooperative matches count fairly as shared outcomes instead of disappearing from seasons.

#### Polish
- The iOS tournament view consumes the server aggregate contract directly.
- A 250-session stress fixture plus Wordle proves complete deterministic month filtering.

#### Honest limits
- Replays can only show server-retained moves; very old sessions already removed before 4.3 cannot be reconstructed.
- IPA unsigned; real two-device spectator run: not hardware verified.

## 4.2.0 — Klarheit: Dashboard & Entdeckung / Clarity: Dashboard & Discovery

### Deutsch

#### Neu
- Das Dashboard hält Frage des Tages und Herz prominent; Rituale, Spiele und Momente werden nach Dringlichkeit sortiert und bleiben kompakt einklappbar.
- Im Bearbeiten-Modus lassen sich Gruppen lokal anheften oder ausblenden.
- „Neu in dieser Version“ erscheint genau einmal pro Release und führt direkt zum passenden Tab.
- Der opt-in Dev Cockpit unter `/dev/cockpit` steuert zwei Partner ohne zusätzliche Web-Abhängigkeiten.

#### Behoben
- Gleichzeitige Level-, Badge- und Geschenk-Momente bleiben in der bestehenden FIFO-Zeremonienfolge.
- Flashbacks bleiben beim Serverwechsel an den aktuellen Paar-Kontext gebunden.

#### Feinschliff
- Badge-Zähler verwenden tabellarische Ziffern; leere Momente haben einen eigenen Zustand.
- Dashboard-Priorität, Pin/Hide-Verhalten und Versions-Gate sind als reine Swift-Logik getestet.

#### Ehrliche Grenzen
- Das Cockpit ist nur mit `SOOODREAMY_DEV_COCKPIT=1` verfügbar und ist ein Entwicklungswerkzeug, kein Web-Client.
- Das IPA bleibt unsigniert; Push/iCloud und Geräte-Haptik hängen weiterhin von Signierung und Hardware ab. Geräteprüfung: nein.

### English

#### Features
- Home keeps the daily question and heartbeat prominent; rituals, games, and moments are urgency-ranked and remain compactly collapsible.
- Edit mode can pin or hide groups locally.
- “New in this version” appears exactly once per release and links to the relevant tab.
- The opt-in Dev Cockpit at `/dev/cockpit` drives two partners without extra web dependencies.

#### Fixed
- Simultaneous level, badge, and gift moments remain in the existing FIFO ceremony flow.
- Flashbacks remain scoped to the current couple after a server switch.

#### Polish
- Badge counts use tabular digits and Moments has a designed empty state.
- Dashboard priority, pin/hide behavior, and the version gate are covered as pure Swift logic.

#### Honest limits
- The cockpit is available only with `SOOODREAMY_DEV_COCKPIT=1`; it is a development tool, not a web client.
- The IPA remains unsigned; push/iCloud and device haptics still depend on signing and hardware. Device verified: no.

## 4.1.0 — Fundament & Autorenschaft / Foundation & Authorship

### Deutsch

#### Neu
- Das Über-Fenster zeigt App-Version, Build, erreichbare Server-Version und den Credit „made by Sonic0810“ in einer gemeinsamen Glass-Card.
- Die Release-Ablage unter `versions/`, zweisprachige Patchnotes und das neue Handbuch machen jeden Build nachvollziehbar.
- Die CI baut von `main` und allen `cursor/**`-Branches, benennt IPAs mit ihrer Version und archiviert deutsche und englische Simulator-Screenshots.

#### Behoben
- Die Lokalisierungsprüfung deckt nun auch `RitualsL10n` und `PlatformL10n` ab.
- Ein Vertragstest hält App-Event-Namen und Fehlercodes zwischen Server und API-Dokumentation synchron.
- Alte, fest verdrahtete CI-Branchfilter wurden entfernt.

#### Feinschliff
- Der Linux-Testweg für Swift 6 ist reproduzierbar dokumentiert.
- Release-Metadaten, Prüfsummen, Testnachweise und der Rubrik-Audit haben jetzt ein festes Schema.

#### Ehrliche Grenzen
- Das IPA ist unsigniert. AltStore, SideStore oder Sideloadly müssen es beim Installieren signieren.
- Eine kostenlose Apple-ID erfordert normalerweise alle sieben Tage eine erneute Signierung und erlaubt höchstens drei aktive Sideload-Apps.
- Remote-Push und iCloud benötigen Entitlements, die kostenlose Signierprofile häufig entfernen. Lokale Hinweise und der verschlüsselte Datei-Export bleiben verfügbar.
- Geräte-Haptik, Kamera, Mikrofon und das Verhalten mitsignierter App Groups sind nicht im Simulator prüfbar. Geräteprüfung: nein.

### English

#### Features
- About now presents the app version, build, reachable server version, and “made by Sonic0810” credit in one glass card.
- The `versions/` release archive, bilingual patch notes, and new manual make every build traceable.
- CI builds from `main` and every `cursor/**` branch, gives IPAs versioned names, and archives German and English simulator screenshots.

#### Fixed
- Localization coverage now includes `RitualsL10n` and `PlatformL10n`.
- A contract test keeps app-event names and error codes synchronized between the server and API documentation.
- Stale hard-coded CI branch filters are gone.

#### Polish
- The Swift 6 Linux test path is reproducibly documented.
- Release metadata, checksums, test evidence, and rubric audits now use a stable layout.

#### Honest limits
- The IPA is unsigned. AltStore, SideStore, or Sideloadly must sign it during installation.
- A free Apple ID normally requires re-signing every seven days and allows at most three active sideloaded apps.
- Remote push and iCloud need entitlements that free signing profiles often remove. Local alerts and encrypted file export remain available.
- Device haptics, camera, microphone, and co-signed App Group behavior cannot be verified in the simulator. Device verified: no.

---

SoooDreamy — made by Sonic0810

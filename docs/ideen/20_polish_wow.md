# 20 — Polish, Wow-Momente & die „Krass"-Liste

Ideen-Agent 20/20 · Thema: Das, was aus einer funktionierenden Quiz-App eine
Show macht. 25 Ideen in fünf Blöcken: (a) Handy-Erlebnis, (b) Bildschirm-Wow,
(c) Besondere Momente, (d) Qualitäts-Standards, (e) V2-Kandidaten.

Konventionen (konsistent mit Agent 14/17):
**Aufwand** S/M/L (Implementierungsumfang) · **Prio** P1 (v1-Kern) /
P2 (starker Mehrwert, v1 wenn Zeit) / P3 (v2). Technik-Rahmen aus 17:
Server = Wahrheit, socket.io, Handy-Client < 200 KB, HTTP-only möglich
(AMP) → alles Secure-Context-abhängige läuft über die Capability-Schicht.

**Leitsatz des Dokuments:** Das Handy ist NIE nur Fernbedienung, der
Bildschirm ist NIE nur Anzeigetafel. Jede Interaktion hat Gewicht, Klang
und eine kleine Geschichte.

---

## (a) HANDY-ERLEBNIS — das Telefon als Bühnenrequisite

### A-01 · Münz-Einwurf-Lock-in (DIE Signatur-Interaktion)
Antworten werden nicht „getippt", sondern EINGEWORFEN: Nach Auswahl der
Antwort erscheint unten eine MM-Münze, die man mit dem Daumen in einen
Münzschlitz am oberen Bildschirmrand flippt (kleine Physik: Flugbahn,
Drall, „Klonk"-Sound, Schlitz leuchtet). Erst der Einwurf ist der Lock-in —
danach ist die Antwort versiegelt (Schlitz-Klappe schließt sich). Bei
Wett-Fragen wirft man MEHRERE Münzen ein (Einsatz = Anzahl Münzen, fühlbar!).
Auf dem Bildschirm hört man zeitversetzt das Klimpern jedes Lock-ins —
Sozialdruck ohne zu verraten, WER schon geworfen hat.
**Warum krass:** verwandelt den langweiligsten Moment (Antwort bestätigen)
in den taktilsten. **Aufwand:** M · **Prio:** P1

### A-02 · Frage-Mirror mit eigener Dramaturgie (kein 1:1-Klon)
Das Handy zeigt die Frage synchron zum Bildschirm — aber inszeniert fürs
Hochkant-Format: Die Frage tickert Wort für Wort ein (identisches Timing wie
der Screen, servergesteuert per Event-Timestamps), Antwortoptionen „fallen"
erst ein, wenn der Screen sie aufdeckt. Wer aufs Handy statt auf den
Fernseher schaut, verpasst NICHTS — aber der Screen hat exklusive Extras
(Kategorie-Intro, Ticker), damit der Blick trotzdem hochgeht. Bei
Bild-Fragen: Handy zeigt das Bild zoombar (Pinch), der Screen die Totale.
**Aufwand:** M · **Prio:** P1

### A-03 · „Psst…"-Umschlag — der private GM-Tipp
Der Show-Master kann einem einzelnen Spieler einen Tipp schicken (oder der
Spieler kauft ihn für MM): Auf dem Handy erscheint ein versiegelter
Briefumschlag mit Wachssiegel („Psst… nur für dich"). Zum Öffnen reißt man
ihn mit einer Wischgeste auf (Papier-Riss-Sound, Fetzen fliegen). Clou: Der
Bildschirm zeigt ALLEN, DASS jemand einen Umschlag bekommen hat („📨 an
Spieler 3") — nur nicht, was drinsteht. Sofortiges Tisch-Drama garantiert.
Der GM hat dafür eine Vorlagen-Bibliothek (echter Tipp / Nebelkerze / Witz).
**Aufwand:** M · **Prio:** P1

### A-04 · Haptik trotz iPhone+HTTP: der Drei-Stufen-Fallback
Die Vibration-API (`navigator.vibrate`) ist die falsche Wette: iOS Safari
unterstützt sie GAR NICHT (egal ob HTTP/HTTPS); Android-Chrome kann sie
auch über HTTP (braucht nur User-Aktivierung). Deshalb Capability-Schicht
`haptics.tap()/success()/fail()` mit drei Backends:
1. **Android:** `navigator.vibrate([pattern])`.
2. **iOS ≥ 17.4:** der Switch-Trick — ein unsichtbares
   `<input type="checkbox" switch>` wird programmatisch per Label-Klick
   getoggelt und löst Safaris nativen Haptik-Tick aus (funktioniert auch
   über HTTP, da kein Secure-Context-Feature). Vorher 1× durch echte
   Nutzergeste „aufwärmen" (beim Join-Button).
3. **Fallback überall:** 30-ms-Screen-Shake + kurzer Klick-Sound über die
   ohnehin entsperrte WebAudio-Instanz — „gefühlte Haptik".
Einsatzorte: Münz-Einwurf (A-01), Buzzer-Freigabe, Countdown letzte 3 s,
Umschlag-Aufreißen (A-03). **Aufwand:** M · **Prio:** P2

### A-05 · Persönliche Zwischenstands-Story („dein Abend bis jetzt")
Zwischen den Runden bekommt jeder Spieler auf dem Handy eine private,
story-artige Karten-Sequenz (3–4 Karten, Tap zum Weiterblättern, Fortschritts-
Balken oben wie bei Instagram): „Du liegst auf Platz 2 — nur 350 MM hinter
Ben" → „Deine schnellste Antwort: 1,8 s 🔥" → „Achtung: In Erdkunde hast du
heute 0/3" → letzte Karte ist ein Cliffhanger („Nächste Runde: doppelte
Werte. Zeit für den Angriff."). Personalisierte Häme/Hoffnung statt
nackter Tabelle; niemand sieht die Karten der anderen.
**Aufwand:** M · **Prio:** P1

---

## (b) BILDSCHIRM-WOW — der Screen ist ein Studio, keine Tabelle

### B-01 · Virtuelle Kamera-Schwenks durchs Studio
Der Bildschirm ist EINE große Studio-Szene (Fragen-Wand, Podium,
Kontostands-Regal mit Geldstapeln, Affen-Publikum), und eine virtuelle
Kamera fährt zwischen den Bereichen: Schwenk vom Scoreboard zur Fragen-Wand
(mit Motion-Blur-Fake via kurzem Skew), Zoom auf den Spieler-Avatar, der
gerade gebuzzert hat, Crash-Zoom beim Jackpot. Technisch: ein
Welt-Container mit `transform: translate/scale` + Easing — GPU-billig,
sieht nach Regie aus. Keine harten Screen-Wechsel mehr; ALLES ist eine
Kamerafahrt. **Aufwand:** L · **Prio:** P1

### B-02 · Live-Ticker mit Statistik-Häppchen
Unauffällige Ticker-Leiste am unteren Rand (wie Sport-News), die aus dem
Event-Log + All-Time-Stats (Agent 15) kleine Häppchen generiert: „Anna hat
4 der letzten 5 Musikfragen geholt +++ Bens Fehlbuzz-Quote heute: 60 % +++
Jackpot-Topf: 1.250 MM +++". Regelwerk statt Zufall: Ticker feuert nur in
Ruhephasen (nie während Frage läuft), max. 1 Häppchen/20 s, priorisiert
nach Relevanz-Score. Der GM kann eigene Ticker-Meldungen tippen (Roast!).
**Aufwand:** M · **Prio:** P2

### B-03 · Rekord-Einblendungen im Breaking-News-Stil
Wenn ein All-Time-Rekord fällt (schnellste Antwort, längste Streak, größter
Einzelgewinn, höchster Kontostand), unterbricht ein Lower-Third die Szene:
Rotgold-Banner fliegt rein, Airhorn-Stinger, „🏆 NEUER HAUSREKORD:
schnellste Antwort — Anna, 1,42 s (alt: Ben, 1,61 s)". Der entthronte
Rekordhalter bekommt auf SEINEM Handy gleichzeitig ein „Dein Rekord wurde
gebrochen 💔" (Verbindung zu A-05-Tonalität). Rekorde sind persistent pro
Save-Slot → jede Session kann Geschichte schreiben.
**Aufwand:** M · **Prio:** P2

### B-04 · Herzschlag-Modus bei Buzzer-Duellen + Handys als Raum-Requisite
Stehen nur noch 2 Spieler in einer Buzzer-Frage (oder Punktegleichstand
kurz vor Schluss): Licht im virtuellen Studio dimmt, Vignette pulsiert im
Herzschlag-Rhythmus, Bass-„Bumm-Bumm" wird mit ablaufender Zeit schneller
(Audio-Layer synct auf Server-Countdown), die zwei Duell-Handys pulsieren
synchron rot mit. Beim Buzz: Herzschlag stoppt abrupt → 1 s Totenstille
→ Auflösung. Die Stille ist der eigentliche Effekt.
Gleiches Prinzip („das Wohnzimmer spielt mit") auch außerhalb des Duells:
Bei „Schätzfrage — zeigt eure Zahlen!" dreht jeder sein Handy zur Runde
(Riesenziffern, maximaler Kontrast), beim Sieger-Moment werden alle
Verlierer-Handys zu schwenkbaren Wunderkerzen. Alles reine CSS-Animation,
kein Sensor nötig — DeviceOrientation wäre iOS-HTTPS-only, wird also
bewusst NICHT vorausgesetzt. **Aufwand:** M · **Prio:** P1

### B-05 · Konfetti mit echter Physik (und Budget)
Konfetti ist das Erste, was billig aussieht, wenn es billig gemacht ist.
Deshalb: ein einziges gepooltes Partikelsystem (Canvas, max. ~400 Partikel,
Object-Pool, delta-time-basiert) mit Wind-Drift, Rotation um zwei Achsen
(der „Flatter"-Effekt: sin-moduliertes scaleX) und — der Trick —
**Landeflächen**: Konfetti bleibt auf Oberkanten von UI-Elementen liegen
(Scoreboard-Rahmen, Podium) und rutscht bei der nächsten Kamerafahrt (B-01)
herunter. Drei Presets: Sieg (gold), Runden-Ende (bunt), Troll (eine
einzige traurige Konfetti-Flocke bei 0-Punkte-Runden).
**Aufwand:** M · **Prio:** P1

### B-06 · Money-Regen, der ZÄHLBAR ist
Beim Gewinn regnet nicht „irgendwas Grünes": Es fallen exakt so viele
Scheine, wie gewonnen wurden (1 Schein = 50 MM, Konvention aus Agent 14) —
bei 500 MM flattern 10 Scheine einzeln aufs Podium und stapeln sich dort
SICHTBAR; der Kontostand zählt synchron zum Aufprall jedes Scheins hoch
(Tick-Sound pro Schein). Große Summen (Jackpot): Scheine fallen gebündelt
als Stapel mit Banderole + einzelne Nachzügler. Der Geldstapel neben dem
Avatar wächst über den Abend real mit → man SIEHT den Spielstand als
physisches Vermögen. **Aufwand:** L · **Prio:** P1

---

## (c) BESONDERE MOMENTE — Szenen, von denen man am Montag erzählt

### C-01 · Timeout-Screen: Countdown + Affen-Aquarium
Pausiert der GM (Pinkelpause, Pizza an der Tür), verwandelt sich der bisherige
Spielstand-Screen in ein „Affen-Aquarium": Die Spieler-Avataraffen planschen
in einem Becken aus ihren eigenen MM-Scheinen (wer mehr hat, schwimmt höher),
oben ein großer, entspannter Pause-Countdown (GM wählt 2/5/10 min oder ∞).
Interaktiv: Jeder kann vom Handy Bananen ins Becken werfen (Tap → Banane
fliegt physikalisch rein, sein Affe schnappt sie) — die Handy-Verbindung
bleibt so nachweislich lebendig, und der Reconnect-Status ist spielerisch
sichtbar (abgetauchter Affe = Spieler disconnected). 10 s vor Ablauf:
Gong + „Zurück auf die Plätze"-Vibration/Haptik (A-04) auf allen Handys.
**Aufwand:** M · **Prio:** P1

### C-02 · „LAZARUS-AFFE!" — die Comeback-Erkennung
Engine-Regel: Wer nach Runde ≥ 2 Letzter mit ≥ 30 % Rückstand war und die
Führung übernimmt (oder ins Finale springt), triggert die Lazarus-Sequenz:
Musik reißt ab, Screen wird schwarz, ein Grabstein mit dem Avatar bricht
auf, der Affe klettert im Goldlicht heraus, „⚡ LAZARUS-AFFE!"-Schriftzug,
Chor-Stinger. Der Ticker (B-02) liefert die Zahlen nach („von −2.400 MM auf
Platz 1 in 6 Fragen"). Max. 1× pro Match, damit es besonders bleibt; das
Erlebnis wird als All-Time-Badge gespeichert (Agent 15).
**Aufwand:** M · **Prio:** P2

### C-03 · Sudden-Death-Inszenierung
Bei Gleichstand am Ende: kompletter Look-Wechsel als eigenes Theme —
Studio-Licht aus, zwei Spotlights auf die zwei Avatare, alle UI-Farben
entsättigt außer den zwei Spielerfarben, Fragen erscheinen als weiße
Schrift auf Schwarz, Herzschlag-Modus (B-04) permanent an. Die Handys der
NICHT beteiligten Spieler werden zu „Publikums-Karten": Sie tippen live,
auf wen sie wetten (Side-Bet um 100 MM), und der Screen zeigt die
Stimmung als zwei wachsende Balken hinter den Duellanten.
**Aufwand:** M · **Prio:** P2

### C-04 · Scheitern mit Stil: Ehren-Banane & der „Alle falsch!"-Moment
Nach der Sieger-Zeremonie kommt IMMER ein zweiter, kleinerer Moment für den
letzten Platz: Die Kamera (B-01) schwenkt zum Verlierer-Avatar, ein Affe
überreicht die „Ehren-Banane", und der Screen zeigt die EINE Sache, in der
dieser Spieler heute trotzdem Bester war (aus dem Event-Log garantiert
findbar: schnellster Einzelbuzz, mutigste Wette, beste Kategorie, notfalls
„meiste Bananen im Pausen-Aquarium geworfen"). Niemand verlässt den Abend
als reine Punchline — wichtig für die „will ich wieder spielen"-Quote.
Zweiter Baustein derselben Philosophie: Vergeigen ALLE Spieler eine Frage,
gehört der Moment dem Publikum — Rekord-Kratzer-Sound, ein Affe schaut in
die Kamera, schüttelt langsam den Kopf und schreddert die Frage durch einen
Aktenvernichter; der Fragenwert wandert sichtbar in den Jackpot-Topf
(Anschluss an Agent 14, I-04). Auf allen Handys gleichzeitig: „Ihr habt das
WIRKLICH alle nicht gewusst." Gemeinsames Versagen wird zum besten Lacher
des Abends. **Aufwand:** S · **Prio:** P1

### C-05 · Jubiläums-Erkennung mit Rückblick-Show
Der Server zählt persistent mit (pro Save-Slot): 10. Spieleabend, 500.
Frage, 100.000stes ausgeschüttetes MM, 1 Jahr MONKEY MONEY. Beim Erreichen
startet vor der ersten Runde eine 20-Sekunden-Rückblick-Montage:
„Seit eurem ersten Abend: 1.243 Fragen · Annas Lieblingskategorie: Musik ·
Bens legendärer Lazarus vom 12.03. · ewige Tabelle: …" — mit den echten
Zahlen aus der All-Time-DB. Effekt: Die App fühlt sich an, als würde sie
die Gruppe KENNEN. **Aufwand:** M · **Prio:** P3

---

## (d) QUALITÄTS-STANDARDS — Polish als Regelwerk, nicht als Glück

### D-01 · Lade-Zustände mit Charakter (Null-Spinner-Politik)
Verbot generischer Spinner. Stattdessen: (1) Skeleton-Layouts, die exakt
dem Ziel-Layout entsprechen (kein Umspringen), (2) für Wartezeiten > 1 s
der Liane-schwingende Lade-Affe mit rotierenden Einzeilern („Poliere
Bananen…", „Zähle Scheine…", „Bestiche die Jury…"), (3) Assets werden
während der Lobby vorgeladen (Audio-Sprites, Avatar-Bilder, Konfetti-
Spritesheet), sodass im Spiel NIE nachgeladen wird. Messlatte: Nach der
Lobby existiert kein sichtbarer Ladezustand mehr.
**Aufwand:** S · **Prio:** P1

### D-02 · Disconnect-Banner: „Affe kurz vom Baum gefallen…"
Verbindungsverlust ist bei Party-WLAN Normalfall, also wird er charmant
inszeniert statt technisch: Auf dem Screen hängt der Avatar des Spielers
plötzlich kopfüber am Ast („Ben ist kurz vom Baum gefallen… wir werfen
eine Liane 🪢"), im Aquarium (C-01) taucht sein Affe ab. Engine-Regel
dazu: Läuft gerade eine Frage, pausiert der Timer automatisch nach 5 s
Disconnect eines aktiven Spielers (GM kann überstimmen). Beim Reconnect:
Affe klettert zurück, „wieder im Baum!"-Toast, Handy zeigt sofort den
korrekten Zustand (Session-Token + Snapshot, Agent 17). Kein Spieler darf
je fragen müssen „wo war ich?". **Aufwand:** M · **Prio:** P1

### D-03 · Humor-Fehlerscreens mit Fehler-Taxonomie
Jeder Fehlerzustand hat eine eigene Affen-Szene + eindeutigen Code:
Raum voll („Der Baum ist voll — 8 Affen max."), Raumcode falsch („Diesen
Dschungel gibt es nicht"), Server weg („Der Affe mit dem Serverkabel ist
weggerannt", Code `BANANA-503`), Version-Mismatch nach Update („Dein
Handy spricht altes Affisch — einmal neu laden"). Jeder Screen hat GENAU
eine Handlungsaufforderung (Retry/Neu laden/QR „zeig das dem GM") — nie
eine Sackgasse. Die Codes machen Fehlerberichte am Spieltisch trivial
(„bei mir steht BANANA-503"). **Aufwand:** S · **Prio:** P1

### D-04 · Das 60-fps-Budget (technische Hausordnung)
Schriftliche Regeln, die jede Animation einhalten muss: (1) Nur
`transform` + `opacity` animieren, Layout-Properties sind verboten;
(2) EIN Canvas für alle Partikel (B-05/B-06) mit Objekt-Pooling und
Delta-Time; (3) Budget: max. 400 Partikel Screen / 60 Handy; (4)
`prefers-reduced-motion` + ein „Ruhiger Modus" im GM-Panel schalten auf
Fade-only; (5) Low-End-Erkennung (erste 5 s Frame-Times messen) halbiert
Partikel-Budgets automatisch; (6) Handy-Client bleibt < 200 KB (Agent 17),
Animationen dort CSS-first. Jede neue Wow-Idee muss gegen diese Liste —
Polish heißt auch: Nein sagen. **Aufwand:** S (Doku) + laufend · **Prio:** P1

### D-05 · Latenz-Kaschierung: Animation als Puffer
Grundsatz: Der Nutzer wartet nie AUF den Server, sondern schaut währenddessen
etwas an. (1) Münz-Einwurf (A-01) spielt sofort lokal; das Server-ACK muss
nur schneller sein als die 400-ms-Münzflug-Animation — erst bei ACK-Timeout
springt die Münze sichtbar zurück („nochmal werfen!"). (2) Buzzer:
Server-Timestamp entscheidet, aber das Handy zeigt sofort „…" und löst erst
nach Server-Urteil „DU!"/„zu spät" auf — gefühlt instant, faktisch fair.
(3) Screen-Reveals werden 150 ms verzögert einge-eased, damit Events aller
Clients gesammelt ankommen. Latenz verschwindet nicht — sie wird Choreo.
**Aufwand:** M · **Prio:** P1

---

## (e) V2-KANDIDATEN — groß denken, sauber verschieben

### E-01 · Replay-Highlights: „Die Top 3 Momente des Abends"
Da die Engine deterministisch ist (Clock + RNG injiziert, Event-Log =
Wahrheit, Agent 17), lassen sich Szenen nachspielen: Nach dem Finale kürt
die App die 3 dramatischsten Momente (Heuristik: Führungswechsel,
knappster Buzz in ms, größter Einzelgewinn) und spielt sie als
Kurz-Replays mit Kamerafahrt + Zeitlupe auf dem Buzz-Moment nach —
Sportschau-Stil. **Aufwand:** L · **Prio:** P3 (v2; ABER v1-Vorarbeit
P1: Event-Log von Anfang an vollständig + replayfähig persistieren)

### E-02 · Foto-Finish-Share-Karte
Nach dem Finale rendert der Server eine teilbare End-Karte (PNG via
node-canvas o. ä. — kein natives Modul? sonst SVG→Client-Render):
Podium mit Avataren, Endstände, „Moment des Abends", Datum, Session-Nr.
Verteilung HTTP-tauglich: Download-Button + QR auf dem Screen (kein
Web-Share-API-Zwang, das wäre Secure-Context). Landet in der
WhatsApp-Gruppe → kostenloses Marketing für den nächsten Abend.
**Aufwand:** M · **Prio:** P3

### E-03 · Saison-Events als Theme-Pakete
Skin-Ebene über dem Studio (B-01): Halloween (Kürbis-Münzen, Fledermaus-
Konfetti, Nebel im Aquarium), Weihnachten (MM-Scheine mit Schleife,
Schnee-Physik statt Konfetti), Geburtstags-Modus (GM markiert einen
Spieler → dessen Farbe dominiert das Studio, Extra-Zeremonie). Technisch
nur Asset-/Preset-Austausch über ein Theme-Manifest — deshalb v2-billig,
WENN v1 alle Farben/Partikel/Sounds konsequent aus einem Theme-Objekt
zieht (v1-Vorarbeit: Theme-Schicht, Aufwand S).
**Aufwand:** M · **Prio:** P3

### E-04 · Sprach-Ansager („Die Stimme des Dschungels")
Vorproduzierte Ansager-Clips (CC-lizenzierte Stimme, KI-TTS-Batch oder
selbst eingesprochen — KEINE Live-TTS im Browser, Web Speech ist auf iOS
zu unzuverlässig): „Runde zwei!", „Jackpot-Frage!", Spielernamen als
generische Anreden („Spieler drei übernimmt die Führung!"). Als
Audio-Sprite gebündelt, vom Screen abgespielt, im GM-Panel abschaltbar.
Dazu Ansager-Persönlichkeit: leicht voreingenommen, feuert sichtbar den
Letztplatzierten an (Anschluss an C-04-Philosophie).
**Aufwand:** L (Content!) · **Prio:** P3

---

## TOP-5-EMPFEHLUNG (wenn nur fünf Dinge gebaut werden)

1. **A-01 Münz-Einwurf-Lock-in** — die eine Signatur-Interaktion, die
   „Handy = Fernbedienung" für immer beerdigt. Jede Frage profitiert.
2. **B-01 Virtuelle Kamera-Schwenks** — verwandelt alle Screens in EINE
   Show-Regie; hebt automatisch jede andere Idee (B-05, B-06, C-04) mit.
3. **B-06 Money-Regen mit zählbaren Scheinen** — macht den Namen der App
   physisch erlebbar; Kontostand = sichtbarer Geldstapel.
4. **C-01 Timeout-Aquarium** — löst die GM-Pausen-Anforderung nicht nur,
   sondern macht aus der Schwäche (Pause) einen Lieblingsmoment.
5. **D-02 + D-05 (Disconnect-Charme + Latenz-Choreo)** — das unsichtbare
   Polish-Paar, das „bugfrei + poliert" im Party-WLAN überhaupt erst
   möglich macht; ohne sie wirken alle Wow-Ideen zerbrechlich.

**Roter Faden:** v1 baut die Bühne (Kamera, Partikel-Budget, Theme-Schicht,
Event-Log) — v2 bespielt sie (Replays, Saisons, Ansager). Nichts aus (e)
erfordert Umbauten, wenn die bei E-01/E-03 genannten v1-Vorarbeiten von
Anfang an mitlaufen.

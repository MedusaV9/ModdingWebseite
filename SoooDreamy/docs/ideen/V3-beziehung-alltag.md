# SoooDreamy 3.0 — Ideen-Lens „Beziehungs-Features & Alltag" 💞🏡

> Ideen-Agent 1/3. Fokus: Features, die den **Alltag eines Paares bereichern**
> und **echte Beziehungsrituale digital machen**. Alle Ideen sind bewusst für
> die reale Umgebung gedacht: Sideload-iOS **ohne Remote-Push** (Realtime nur
> über WebSocket solange die App läuft + BGAppRefresh + lokale Notifications),
> selbst gehosteter Node-Server mit JSON-Datei-Storage und Move-Relay.
>
> Aufwand-Notation: `S/M/L (Server: x · iOS: y)`. Score = Impact fürs Paar (1–10).
> Bestehende Systeme, auf die referenziert wird: Chat/Briefe (`openWhen`),
> Voice-Pipeline, Tagesfrage+Streak+Journal, Check-ins, Listen, Hugs, Coupons,
> Foto/Video-Galerie, PotD, Moods+Verlauf, Events/Countdowns+Live Activity,
> Haptik-Studio, Vault (E2E), Game-Relay, Inbox-Digest, Widget-Snapshot,
> Stats/YearReview, Content-Packs (bilingual).

---

## Die Ideen (35)

### 1. Zeitkapsel-Briefe 📮⏳

**Konzept:** Briefe, Fotos oder Sprachnachrichten versiegeln, die sich erst an
einem Datum öffnen lassen — „Öffne mich an unserem Jahrestag", „in genau einem
Jahr", „an deinem 30. Geburtstag". Bis dahin zeigt der Chat einen verschlossenen
Umschlag mit tickendem Countdown; das Öffnen ist eine große Enthüllungs-Zeremonie
(bestehende Siegel-Animation, neuer Sound). Der Server gibt den Inhalt erst nach
`unlockAt` heraus, damit niemand schummeln kann.
**Warum es begeistert:** Ein Brief vom Vergangenheits-Ich des Partners ist das
emotional dichteste Geschenk, das eine App liefern kann — und die Wartezeit
selbst wird zum gemeinsamen Ereignis.
**Aufwand:** M (Server: S — `unlockAt`-Feld + serverseitiges Zurückhalten des
Payloads, ein neuer Broadcast `capsule_unlocked` · iOS: M — Composer-Erweiterung,
Countdown-Bubble, Enthüllung, optional Countdown-Widget).
**Abhängigkeiten:** Briefe/`openWhen`-Siegel-UI, Voice-Pipeline, Countdown-Logik
der Momente, lokale Notification am Öffnungstag.
**Score:** 9/10

### 2. „Wie war dein Tag?"-Audio-Check-in 🎙️🌇

**Konzept:** Jeden Abend lädt die App beide zu einem 60–90-Sekunden-Audio-Memo
ein („Erzähl mir von deinem Tag"), optional mit wechselndem Mini-Prompt („Was
hat dich heute zum Lachen gebracht?"). Wie bei der Tagesfrage wird das Memo des
Partners erst hörbar, wenn man selbst aufgenommen hat — mit eigener 🔥-Serie und
einem durchblätterbaren Audio-Tagebuch.
**Warum es begeistert:** Die Stimme des Partners am Abend zu hören ist das
Ritual, das Telefonieren ersetzt, wenn die Zeitfenster nicht zusammenpassen —
asynchron, aber intim.
**Aufwand:** M (Server: S — Daily-Reveal-Semantik auf Voice-Blobs übertragen ·
iOS: M — Aufnahme-Sheet mit Prompt, Reveal-Player, Serien-UI, Journal-Tab).
**Abhängigkeiten:** Voice-Pipeline (Aufnahme/Streaming existiert), Reveal- und
Streak-Logik der Tagesfrage, Journal-UI als Vorbild.
**Score:** 9/10

### 3. Gemeinsame Ziele & Sparziele 🎯💰

**Konzept:** Paare legen Ziele mit Zielwert an („1.200 € für Japan", „30 Läufe
bis Sommer", „20 Bücher zusammen") und buchen Fortschritt in beliebigen
Häppchen ein — jeder Beitrag erscheint als Timeline-Event mit Absender.
Fortschrittsbalken in Paar-Farben, Meilenstein-Konfetti bei 25/50/75/100 %,
erreichte Ziele wandern feierlich auf die Bucket-List als „Geschafft".
**Warum es begeistert:** Gemeinsam auf etwas hinzusparen oder hinzutrainieren
macht aus „irgendwann mal" ein sichtbares Wir-Projekt mit täglichem Dopamin.
**Aufwand:** M (Server: M — neue Collection `goals` mit Contributions-Liste,
Caps, Broadcasts · iOS: M — Ziel-Karten, Einbuchungs-Sheet, Fortschritts-Widget).
**Abhängigkeiten:** Bucket-List (Übernahme erledigter Ziele), Konfetti/Feier-UI,
Widget-Snapshot (Fortschritt als Widget), Stats.
**Score:** 9/10

### 4. Aussprache-Modus 🕊️

**Konzept:** Ein geführter „Wir klären das"-Modus nach Gottman-Vorbild: Beide
starten die Sitzung bewusst gemeinsam (Handshake über das Game-Relay), dann
führt die App durch Phasen — abwechselnde Redezeit mit sanftem Timer,
Ich-Botschaft-Vorlagen, „Spiegeln" (das Gehörte zusammenfassen, Partner
bestätigt), gemeinsamer Lösungs-Schritt. Am Ende entsteht ein kleines
„Friedensprotokoll", das beide mit einem Tap besiegeln.
**Warum es begeistert:** Der schwerste Moment einer Beziehung bekommt eine
sichere Struktur — die App ist genau dann wertvoll, wenn es NICHT läuft.
**Aufwand:** L (Server: S — läuft als neuer Session-Typ über das bestehende
Move-Relay + Ablage der Protokolle · iOS: L — sorgfältiges, ruhiges UX-Design,
Phasen-Statemachine, bilinguale Frage-/Formulierungs-Packs).
**Abhängigkeiten:** Game-Relay (deterministische Moves), Content-Pack-System,
behutsame Sound-/Haptik-Untermalung.
**Score:** 9/10

### 5. Bedürfnis-Knopf „Ich brauche gerade…" 💗

**Konzept:** Ein schamfreier Ein-Tap-Weg zu sagen, was man braucht: „Zuhören
ohne Ratschläge", „Ablenkung", „Nähe", „Kurz Raum für mich", „Aufmunterung",
„Eine Umarmung". Der Partner bekommt nicht nur das Signal, sondern eine kleine
liebevolle Anleitung, wie er JETZT helfen kann („Sie will nur erzählen — nicht
lösen!"). Antworten geht mit einem Tap („Bin für dich da 🤍").
**Warum es begeistert:** Es löst das häufigste Alltags-Missverständnis („Ich
wollte doch nur helfen!") mit einem einzigen Knopf.
**Aufwand:** S (Server: S — neuer Signal-Typ analog Touches · iOS: S/M —
Bedürfnis-Picker, Empfangs-Moment mit Anleitung, Verlauf).
**Abhängigkeiten:** Touch-/Signal-Infrastruktur, Vollbild-Empfangsmomente,
lokale Notifications (solange WS verbunden).
**Score:** 9/10

### 6. „Unsere Woche" — geteilter Wochenplan 🗓️

**Konzept:** Ein bewusst einfacher Paar-Wochenplan (kein Kalender-Sync-Monster):
Jeder markiert pro Abend „frei / busy / Call möglich / Date!", die App
highlightet Überschneidungen („Mittwoch seid ihr BEIDE frei ✨") und schlägt per
Tap ein Date oder Telefon-Date vor. Wiederkehrende Slots („sonntags Call")
lassen sich pinnen.
**Warum es begeistert:** „Wann sehen/hören wir uns diese Woche?" ist DIE
Alltagsfrage jedes Paares — und keine Kalender-App beantwortet sie auf
Paar-Ebene.
**Aufwand:** M (Server: S — `weekplan`-Struktur pro dateKey/Member, Broadcast ·
iOS: M — Wochen-Grid, Überschneidungs-Logik, Vorschlags-Flow).
**Abhängigkeiten:** Date-Ideen-Generator, Events/Momente (Date wird Countdown),
Widget-Snapshot („nächstes gemeinsames Fenster" als Widget).
**Score:** 9/10

### 7. Kuschelwesen „Snuggle" 🐣

**Konzept:** Ein gemeinsames virtuelles Wesen, das von den Ritualen des Paares
lebt: Check-ins, Tagesfragen, Berührungen und Spiele „füttern" es; es wächst
durch Lebensphasen, entwickelt einen Charakter aus den Mood-Daten und wohnt auf
Dashboard + eigenem Widget. Wichtig: Es leidet nie dramatisch (kein
Tamagotchi-Tod), es wird höchstens verschlafen und freut sich umso mehr.
**Warum es begeistert:** Ein Wesen, das nur existiert, weil ihr BEIDE da wart,
macht aus abstrakten Streaks etwas, das man gemeinsam großzieht.
**Aufwand:** L (Server: M — Zustands-Ableitung aus vorhandenen Countern,
deterministisch & testbar (Clock injizieren) · iOS: L — prozeduraler
Charakter (SceneKit/Canvas wie das 3D-Herz), Animationen, Widget).
**Abhängigkeiten:** Stats/Counters, Check-ins, Moods, Widget-Snapshot,
prozedurale Render-Pipeline (3D-Herz als Vorbild).
**Score:** 9/10

### 8. Rücksicht-Radar (Zyklus & Energie, strikt opt-in) 🌙

**Konzept:** Ein sensibler, komplett freiwilliger Bereich: Eine Person kann
Zyklusphasen oder einfach Energie-/Schmerz-Level tracken und GRANULAR
entscheiden, was der Partner sieht — von nichts über diskrete Hinweise („Heute
extra lieb sein 💗", „Schokolade wirkt Wunder") bis Details. Der Partner
bekommt dazu kleine Verständnis-Karten („PMS ist real — so hilfst du").
Speicherung wahlweise im E2E-Vault-Modus.
**Warum es begeistert:** Rücksicht ist die unterschätzteste Liebessprache —
und kein Zyklus-Tracker der Welt ist für ZWEI gebaut.
**Aufwand:** M (Server: S — Entries + Sichtbarkeits-Flags, optional nur
Ciphertext wie Vault · iOS: M — Tracking-UI, Partner-Hinweis-Karten,
Privacy-Einstellungen, Content-Pack).
**Abhängigkeiten:** Mood-System (Hinweis-Anzeige am Partner-Profil), Vault-Krypto
(optionaler E2E-Modus), Content-Packs.
**Score:** 8/10

### 9. Meilenstein-Feiern & Badge-Album 🏅

**Konzept:** Die App erkennt Beziehungs-Meilensteine automatisch aus Daten, die
sie schon hat: 100/500/1000 Tage zusammen, 1000. Nachricht, 100. Umarmung,
50. Tagesfrage-Streak-Tag, 100. Foto. Jeder Meilenstein wird als
Vollbild-Zeremonie gefeiert (Herzregen, Sound, Haptik) und wandert in ein
gemeinsames Badge-Album; kommende Meilensteine werden angeteasert („In 12 Tagen:
euer 1000. Tag!").
**Warum es begeistert:** Die App feiert euch für Dinge, die ihr längst getan
habt — null Aufwand, maximales „Wow, SO lange schon?".
**Aufwand:** S/M (Server: S — Ableitung aus bestehenden Countern/Stats ·
iOS: M — Zeremonie, Album-Grid, Teaser auf dem Dashboard).
**Abhängigkeiten:** Stats/Counters, Monatstag-Feier (bestehende Zeremonie-UI),
Live Activity (Countdown auf den großen Tag).
**Score:** 8/10

### 10. „Ich vermisse dich"-Stufen 📶🥺

**Konzept:** Vermissen in drei ehrlichen, konfliktfreien Stufen: Stufe 1 = ein
sanftes Glühen am Partner-Widget/Dashboard („denkt an dich"), Stufe 2 =
spürbares Herzklopfen + „vermisst dich gerade sehr", Stufe 3 = „Ich brauche
heute noch deine Stimme — ruf an, sobald du kannst" mit Bestätigungs-Knopf
(„Bin um 21 Uhr da ❤️"). Klar codiert, nie vorwurfsvoll formuliert.
**Warum es begeistert:** Es gibt dem diffusen „Warum meldet er sich nicht?"
eine Sprache, BEVOR daraus Streit wird.
**Aufwand:** S (Server: S — Stufen-Feld auf dem Touch-Typ + Antwort-Signal ·
iOS: S — Stufen-Picker mit Langdruck, Antwort-Flow, Widget-Glühen).
**Abhängigkeiten:** Touches, Haptik-Muster, Widget-Snapshot, Inbox-Digest.
**Score:** 8/10

### 11. „3 gute Dinge" — Abend-Dankbarkeitsritual ✨

**Konzept:** Jeder trägt abends drei schöne Momente des Tages ein (Stichworte
reichen, 10 Sekunden pro Eintrag) — Reveal erst, wenn beide fertig sind, wie
bei der Tagesfrage. Einträge, in denen der Partner vorkommt, werden markiert
und landen in einem eigenen „Du in meinen guten Dingen"-Feed.
**Warum es begeistert:** Das wissenschaftlich am besten belegte Glücksritual
wird zum Paar-Moment — und man erfährt nebenbei, wie oft man selbst der gute
Teil des Tages war.
**Aufwand:** S (Server: S — Struktur analog Tagesfrage · iOS: S/M —
Eingabe-Sheet, Reveal, Feed, Erinnerung über bestehende Abend-Reminder).
**Abhängigkeiten:** Daily-Reveal-Logik, Gutenacht-Check-in (Andockpunkt),
Streak-System.
**Score:** 8/10

### 12. Gemeinsames Tagebuch mit Wochen-Prompts 📔

**Konzept:** Neben der schnellen Tagesfrage ein „richtiges" gemeinsames Journal:
wöchentliche Reflexions-Prompts („Worauf warst du diese Woche stolz — bei dir
und bei uns?"), freie Einträge, einbettbare Fotos und Voice-Schnipsel. Einträge
können privat starten und später „dem Buch geschenkt" werden; das Buch ist
chronologisch durchblätterbar wie ein echtes Album.
**Warum es begeistert:** Aus dem Beziehungsalltag entsteht nebenbei das Buch,
das man sich sonst zur Silberhochzeit mühsam zusammensucht.
**Aufwand:** M (Server: M — `journal`-Collection mit gemischten Blöcken
(Text/Foto-Ref/Voice-Ref) · iOS: M — Editor, Buch-Reader, Prompt-Rotation).
**Abhängigkeiten:** Tagesfragen-Journal (UI-Vorbild), Galerie/Voice (Referenzen),
Content-Packs (Prompts, bilingual).
**Score:** 8/10

### 13. Fernbeziehungs-Dashboard mit Zeitzonen 🌍⏰

**Konzept:** Beide hinterlegen ihre Stadt/Zeitzone: Das Dashboard zeigt zwei
Uhren, Tag/Nacht-Status mit Sonnenauf-/-untergang, „gute Anruf-Fenster"
(Überschneidung der Wachzeiten, respektiert den Wochenplan) und die Distanz
(„874 km — aber nur 6 cm auf der Karte 🥺"). Dazu der Wiedersehens-Countdown
prominent als Herzstück.
**Warum es begeistert:** Fernbeziehungs-Paare rechnen JEDEN Tag Zeitzonen um —
das Dashboard nimmt ihnen die mentale Dauerlast ab und macht sie zärtlich.
**Aufwand:** M (Server: S — zwei Ortsfelder am Member · iOS: M — Dashboard-Karte,
Zeitzonen-/Sonnenstands-Mathe lokal, Widget mit beiden Uhren).
**Abhängigkeiten:** Events/Countdown (Wiedersehen), Wochenplan (Anruf-Fenster),
Widget-Snapshot, Live Activity.
**Score:** 8/10

### 14. Care-Paket-Wunschliste 🎁🤫

**Konzept:** Jeder pflegt eine Wunschliste mit Alltagsdetails, die der andere
nie parat hat: Lieblingssnacks, Kleidergrößen, Teesorte, Apotheken-Klassiker,
„was mich immer tröstet". Der Clou: Der Partner kann Einträge heimlich als
„besorgt 🤫" markieren — der Besitzer sieht das NICHT, Überraschungen bleiben
Überraschungen; nach dem Verschenken wird aufgedeckt.
**Warum es begeistert:** Nie wieder „Welche Größe hast du nochmal?" ruinierte
Überraschungen — Schenken wird treffsicher UND bleibt magisch.
**Aufwand:** S/M (Server: S — Listen-Variante mit asymmetrischer Sichtbarkeit
des `claimed`-Flags · iOS: S/M — zwei Sichten (meine/deine), Aufdeck-Moment).
**Abhängigkeiten:** Gemeinsame Listen (Server-Muster existiert), Coupons
(Verschenk-Zeremonie als Vorbild).
**Score:** 7/10

### 15. Datumsabend-Rotation 🎲🌹

**Konzept:** Die App verwaltet, wer als Nächstes das Date plant („Du bist
dran!"), inklusive optionalem Geheim-Modus: Der Planende zieht privat Ideen aus
dem Date-Generator, der andere sieht nur Datum + Dresscode-Hinweis. Nach dem
Date: Beweis-Foto, Bewertung mit einem Herz-Slider von beiden, Eintrag in die
Date-Historie.
**Warum es begeistert:** Es beendet das ewige „Was machen wir am Wochenende?"-
Pingpong und macht aus Date-Planung ein Spiel mit fairen Regeln.
**Aufwand:** M (Server: S — Rotations-Zustand + Date-Log · iOS: M — Planungs-Flow,
Geheim-Ansicht, Historie mit Fotos).
**Abhängigkeiten:** Date-Ideen-Generator (140+ Ideen), Events/Countdown,
Galerie (Beweis-Foto), PotD-Muster.
**Score:** 8/10

### 16. Stimmungs-Wetterbericht mit Bedürfnis-Tags ⛅

**Konzept:** Der Mood wird zum Mini-Forecast: „Innerlich bewölkt, ab Mittag
Aufhellung" plus wählbare Bedürfnis-Tags („brauche heute: Ruhe / Nähe /
Geduld / Aufmunterung"). Der Partner sieht den Forecast prominent auf Dashboard
und Widget und weiß, wie er den Tag des anderen lesen soll — Änderungen im
Tagesverlauf sind ausdrücklich vorgesehen.
**Warum es begeistert:** „Sag mir, wie du drauf bist, BEVOR ich es falsch
deute" — der Forecast macht emotionale Wetterlage besprechbar ohne großes
Gespräch.
**Aufwand:** S/M (Server: S — Mood-Modell um Tags/Verlauf erweitern · iOS: M —
Forecast-Picker, Partner-Darstellung, Widget-Update).
**Abhängigkeiten:** Mood-System + Verlauf, Widget-Snapshot, Live Activity
(Couple Pulse zeigt Forecast).
**Score:** 8/10

### 17. Versöhnungs-Ritual „Friedensbrücke" 🤍

**Konzept:** Ein strukturierter Weg, sich zu entschuldigen: Die App führt durch
ein Drei-Schritte-Format (Was ist passiert · Was ich jetzt verstehe · Was ich
mir vornehme), der Partner antwortet mit „Angenommen 🤍" oder „Lass uns noch
reden" (was direkt den Aussprache-Modus öffnet). Angenommene Versöhnungen
werden mit einer Brücken-Animation besiegelt und im Paar-Archiv abgelegt.
**Warum es begeistert:** Eine gute Entschuldigung ist schwer — ein liebevolles
Formular dafür senkt die Hürde genau dann, wenn der Stolz am größten ist.
**Aufwand:** M (Server: S — Ritual-Objekte + Antwort-Status · iOS: M —
geführter Flow, Zeremonie, Verzahnung mit Aussprache-Modus).
**Abhängigkeiten:** Aussprache-Modus (Idee 4, Eskalationspfad), Brief-UI,
Content-Packs (Formulierungshilfen).
**Score:** 7/10

### 18. „Heute übernehme ich" — Wertschätzungs-Chores 🔁🙏

**Konzept:** Eine kleine gemeinsame Aufgabenliste des Alltags (Küche, Einkauf,
Hund), aber ohne Punkte-Buchhaltung: Man claimt Aufgaben mit „Übernehme ich
heute 💪", der andere kann mit einem Danke-Tap reagieren, das als kleine
Zeremonie ankommt. Die Wochenansicht zeigt keine Schulden, sondern nur, wer wem
wie oft den Rücken freigehalten hat.
**Warum es begeistert:** Es dreht Haushalts-Streit in Wertschätzung um —
gesehen werden statt aufrechnen.
**Aufwand:** M (Server: S — Erweiterung des Listen-Systems um Claims/Danke ·
iOS: M — Claim-Flow, Danke-Moment, Wochenansicht).
**Abhängigkeiten:** Gemeinsame Listen (existieren), Touch-/Dankes-Signale,
Stats.
**Score:** 7/10

### 19. Selfcare-Buddy (Medikamente & Gewohnheiten, opt-in) 💊💧

**Konzept:** Jeder kann private Erinnerungen anlegen (Pille, Medikament,
Wasser, Dehnen) und PRO EINTRAG entscheiden, ob der Partner den Status sieht.
Der Partner kann dann liebevoll nachhaken — die App liefert dafür bewusst
sanfte Ein-Tap-Formulierungen („Schon an dein Medikament gedacht? 🤍") statt
Nag-Nachrichten; erledigt = kleiner Feier-Moment für beide.
**Warum es begeistert:** „An dich denken" wird konkret — Fürsorge im Alltag,
ohne zur Kontroll-Instanz zu werden.
**Aufwand:** M (Server: S — Habit-Entries + Sichtbarkeits-Flag + Status ·
iOS: M — Verwaltung, lokale Notifications, Partner-Karte).
**Abhängigkeiten:** Lokale Notifications, Check-in-Muster, Bedürfnis-Signale.
**Score:** 7/10

### 20. Telefon-Date-Ritual ☎️💜

**Konzept:** Feste oder spontane Call-Verabredungen mit beidseitiger
Bestätigung, „Bin in 10 Minuten bereit"-Signal und einem Vorbereitungs-Moment:
Die App zieht drei Gesprächsstarter-Karten aus den Content-Packs, die während
des Telefonats durchgetippt werden können. Nach dem Call: „Wie schön war's?"
mit einem Herz-Tap von beiden für die Statistik.
**Warum es begeistert:** Es adelt das Alltags-Telefonat zum Date — mit
Vorfreude, Ritual und Gesprächsstoff jenseits von „Was gibt's Neues?".
**Aufwand:** S/M (Server: S — Verabredungs-Objekte + Signale · iOS: M —
Verabredungs-Flow, Live Activity während des wartenden Fensters, Karten-UI).
**Abhängigkeiten:** Wochenplan (Idee 6), Content-Packs, Live Activity,
Events/Countdown.
**Score:** 7/10

### 21. „Unsere Orte" — manuelle Standort-Momente 📍

**Konzept:** Kein Tracking, nur Geschenke: Mit einem Tap sendet man „Denk an
dich — von hier" mit einem Pin (+ optionalem Foto), und besondere Orte (erster
Kuss, erstes Date, „unsere Bank") werden auf einer gemeinsamen Karte
gesammelt. Die Karte wird über die Jahre zur Geografie der Beziehung; Orte
lassen sich mit Momenten/Fotos verknüpfen.
**Warum es begeistert:** Eine Landkarte, auf der jeder Pin eine gemeinsame
Geschichte ist — das ist Gänsehaut beim Durchscrollen.
**Aufwand:** M/L (Server: S — Orte + Pins als JSON · iOS: L — MapKit-Integration,
Pin-Flow, Karten-Ästhetik im Liquid-Glass-Look).
**Abhängigkeiten:** Galerie (Foto am Pin), Momente (Verknüpfung), Touches
(„von hier"-Gruß).
**Score:** 8/10

### 22. Guten-Morgen-Blick 🌅 (ephemer)

**Konzept:** Ein bewusst niedrigschwelliges Morgenritual: ein ungeschöntes
Foto — verschlafenes Selfie oder der Blick aus dem Fenster — das nach 24
Stunden automatisch verschwindet (bewusst NICHT in der Galerie landet). Wer
mag, koppelt es an den Morgen-Check-in; Reaktionen nur als Herz-Tap.
**Warum es begeistert:** Der „echte", unperfekte Morgenblick ist intimer als
jedes gestellte Foto — und die Vergänglichkeit nimmt jeden Druck.
**Aufwand:** M (Server: S — Foto-Variante mit TTL + Auto-Löschung · iOS: S/M —
Capture-Flow ohne Galerie-Umweg, Anzeige am Check-in).
**Abhängigkeiten:** Morgen-Check-in (Andockpunkt), Foto-Upload-Pipeline.
**Score:** 7/10

### 23. Paar-Manifest 📜✍️

**Konzept:** Gemeinsam formulierte Werte und Versprechen („Wir gehen nie wütend
ins Bett", „Wir reden über Geld ohne Drama") — jeder Satz braucht die
Zustimmung BEIDER (Co-Sign mit feierlicher Siegel-Animation). Das Manifest
hängt gerahmt im Wir-Tab, Änderungen sind Zeremonien, und einmal im Jahr lädt
die App zur gemeinsamen Revision ein.
**Warum es begeistert:** Es macht die unsichtbaren Abmachungen einer Beziehung
sichtbar und feierlich — euer Grundgesetz, von euch ratifiziert.
**Aufwand:** S/M (Server: S — Statements mit Zwei-Signaturen-Status · iOS: M —
Editor, Co-Sign-Flow, gerahmte Darstellung, Jahres-Reminder).
**Abhängigkeiten:** Brief-/Siegel-UI, lokale Notifications (Jahres-Revision).
**Score:** 7/10

### 24. Danke-Funken 💌⚡

**Konzept:** Wertschätzung mit einem Tap: vordefinierte und eigene
Mini-Dankes-Funken („Danke, dass du eingekauft hast", „Danke für dein Zuhören
gestern") landen als kleine Glitzer-Momente beim Partner. Sonntags fasst die
App die Woche zusammen: „Ihr habt euch 9× bedankt — am häufigsten fürs
Zuhören."
**Warum es begeistert:** Dankbarkeit scheitert nie an der Absicht, sondern an
der Reibung — ein Tap entfernt die Reibung.
**Aufwand:** S (Server: S — Signal-Typ analog Touches · iOS: S —
Funken-Picker, Empfangs-Moment, Wochen-Karte).
**Abhängigkeiten:** Touches, Inbox-Digest, Stats (Wochen-Aggregation).
**Score:** 7/10

### 25. Rezept-Box & Koch-Abende 🍝

**Konzept:** Eine gemeinsame Sammlung „unserer" Rezepte mit Foto, Schwierigkeit
und Geschichte („das erste Gericht, das du mir gekocht hast") — und einem
Killer-Feature: Zutaten mit einem Tap auf die bestehende gemeinsame
Einkaufsliste. Ein „Was kochen wir heute?"-Zufallsrad und eine Koch-Rotation
(wer ist dran?) runden es ab.
**Warum es begeistert:** Essen ist das täglichste aller Rituale — und „unsere
Rezepte" mit Direktdraht zur Einkaufsliste ist echter Alltags-Superkleber.
**Aufwand:** M (Server: S — `recipes`-Collection mit Zutaten-Arrays · iOS: M —
Rezept-Editor, Listen-Übergabe, Zufallsrad).
**Abhängigkeiten:** Gemeinsame Listen (Einkauf), Galerie (Foto), Soundtrack-UI
als Karten-Vorbild.
**Score:** 7/10

### 26. Besuchs-Countdown mit Etappen ✈️🧳

**Konzept:** Der Wiedersehens-Countdown für Fernbeziehungen bekommt Etappen:
„Noch 3 Wochenenden", „Noch 1 Woche: Zugticket checken", „Morgen: Koffer!" —
mit geteilter Packliste und einem Ankunfts-Ritual (der Wartende bereitet eine
Mini-Überraschung in der App vor, die sich beim „Ich bin da!"-Tap öffnet).
**Warum es begeistert:** Er verwandelt die zähe Warterei in eine Reise mit
Zwischenzielen, auf die man sich einzeln freuen kann.
**Aufwand:** S/M (Server: S — Etappen am Event + Packlisten-Ref · iOS: M —
Etappen-Timeline, Ankunfts-Flow, Live Activity mit Etappen).
**Abhängigkeiten:** Events/Countdown + Live Activity, Listen (Packliste),
Zeitkapsel-Mechanik (Ankunfts-Überraschung, Idee 1).
**Score:** 7/10

### 27. Einschlaf-Herzschlag 😴💓

**Konzept:** Das Gutenacht-Ritual wird körperlich: Beim Gutenacht-Check-in kann
man dem Partner seinen „Herzschlag zum Einschlafen" dalassen — ein sanftes,
minutenlanges Haptik-Loop-Muster (aus dem Haptik-Studio), das der andere im
Bett am Handgelenk/in der Hand abspielen kann, dazu optional eine
Flüster-Voice. Morgens sieht man: „Sie ist mit deinem Herzschlag
eingeschlafen 🥺".
**Warum es begeistert:** Es ist das Nächste an „nebeneinander einschlafen",
das Technik ohne Zusatz-Hardware hergibt.
**Aufwand:** M (Server: S — Nacht-Paket (Haptik-Ref + Voice-Ref) am Check-in ·
iOS: M — Loop-Wiedergabe (CoreHaptics-Länge managen), Einschlaf-Screen mit
Dimmen, Bestätigungs-Moment).
**Abhängigkeiten:** Haptik-Studio + Relay, Gutenacht-Check-in, Voice-Pipeline.
**Score:** 8/10

### 28. „Unser Monat" — automatisches Monats-Magazin 📖✨

**Konzept:** Am Monatsende baut die App aus vorhandenen Daten ein
durchblätterbares Mini-Magazin: die 5 schönsten Fotos (Favoriten/PotD), das
lustigste Tagesfragen-Zitat, Spiele-Bilanz, Streak-Verlauf, der Song des
Monats. Beide bekommen es gleichzeitig als „Ausgabe" präsentiert und können
Seiten in den Chat teilen oder als Bild exportieren.
**Warum es begeistert:** Der Alltag bekommt rückwirkend Glanz — man merkt
erst im Rückblick, wie viel man eigentlich zusammen erlebt hat.
**Aufwand:** M (Server: S — Monats-Aggregation nach YearReview-Vorbild ·
iOS: M — Magazin-Layout, Seiten-Renderer, Share/Export).
**Abhängigkeiten:** YearReview-Aggregation, PotD, Favoriten, Tagesfragen-Journal,
Canvas-Export-Pipeline (Bild-Rendering).
**Score:** 8/10

### 29. Wochen-Retro zu zweit 🔄🛋️

**Konzept:** Einmal pro Woche (Tag wählbar) führt die App durch eine
5-Minuten-Paar-Retro mit drei Fragen: „Was war schön diese Woche?", „Wo habe
ich dich vermisst/gebraucht?", „Worauf freuen wir uns nächste Woche?" — beide
antworten asynchron, Reveal gemeinsam, daraus entsteht automatisch ein
Wochen-Vorsatz, an den die App freitags erinnert.
**Warum es begeistert:** Paartherapeuten predigen den wöchentlichen Check-in
seit Jahrzehnten — hier kostet er fünf Minuten und passiert wirklich.
**Aufwand:** M (Server: S — Retro-Entries mit Reveal-Semantik · iOS: M —
geführter Flow, Vorsatz-Karte, Reminder).
**Abhängigkeiten:** Daily-Reveal-Logik, Content-Packs, lokale Notifications.
**Score:** 8/10

### 30. Überraschungs-Zünder 🎇

**Konzept:** Man plant eine Überraschung und legt nur den Zeitpunkt offen: Der
Partner sieht ab sofort eine geheimnisvolle Karte „Samstag, 18 Uhr passiert
etwas 👀" mit Countdown — der Inhalt (Text/Foto/Coupon/Ort) bleibt bis zum
Zünden verschlossen. Vorfreude-Pings („noch 2 Tage 🎇") darf der Planende
manuell auslösen.
**Warum es begeistert:** Vorfreude ist die halbe Überraschung — hier wird sie
zum eigenen Feature.
**Aufwand:** S/M (Server: S — Zeitkapsel-Mechanik mit Teaser-Feld · iOS: M —
Teaser-Karte, Countdown, Enthüllungs-Zeremonie).
**Abhängigkeiten:** Zeitkapsel-Briefe (Idee 1, gleiche Server-Mechanik),
Coupons, Live Activity.
**Score:** 8/10

### 31. Traum-Protokoll 💭🌙

**Konzept:** Direkt nach dem Aufwachen Träume festhalten (Text oder verschlafene
Voice-Memo), der Partner kann kommentieren und Träume mit „Du kamst drin vor 🥰"
taggen. Eine kleine Statistik zeigt, wer öfter vom anderen träumt — und die
skurrilsten Träume landen auf Wunsch als Zitat im Monats-Magazin.
**Warum es begeistert:** „Du kamst in meinem Traum vor" ist einer der
süßesten Sätze des Alltags — hier bekommt er ein Zuhause.
**Aufwand:** S (Server: S — Entries analog Moods · iOS: S — Capture am
Morgen-Check-in, Feed, Tag-Statistik).
**Abhängigkeiten:** Morgen-Check-in, Voice-Pipeline, Monats-Magazin (Idee 28).
**Score:** 6/10

### 32. Insider-Wörterbuch 📕😂

**Konzept:** Ein Lexikon eurer Insider: Spitznamen, Codewörter, Running Gags —
jeweils mit Herkunftsgeschichte („seit dem Campingurlaub 2024…") und optionalem
Beweis-Foto. Das Dashboard zeigt gelegentlich eine „Weißt du noch?"-Karte mit
einem zufälligen Eintrag; neue Begriffe kann jeder vorschlagen, der andere
bestätigt die Definition.
**Warum es begeistert:** Die private Sprache eines Paares ist sein größter
Schatz — und niemand schreibt sie je auf, bis es diese Funktion gibt.
**Aufwand:** S (Server: S — simple Collection · iOS: S — Lexikon-UI,
Zufalls-Karte, Bestätigungs-Flow).
**Abhängigkeiten:** Flashback-/Erinnerungs-Karte (Dashboard-Slot existiert),
Galerie.
**Score:** 7/10

### 33. Erste-Male-Sammlung 🥇

**Konzept:** Ein Log aller „ersten Male": erster Kuss, erster Urlaub, erstes
gemeinsames Möbelstück, erster gemeinsamer Steuerbescheid — mit Datum, Foto
und einem Satz dazu. Die App schlägt fehlende Klassiker als Checkliste vor,
erinnert an Jahrestage einzelner „erster Male" und speist die
Meilenstein-Feiern.
**Warum es begeistert:** „Weißt du noch, unser erstes…?" wird von einer vagen
Erinnerung zu einem Archiv, das an den richtigen Tagen von selbst anklopft.
**Aufwand:** S (Server: S — Entries mit Datum/Foto-Ref · iOS: S/M —
Checklisten-UI, Jahrestags-Logik über Events).
**Abhängigkeiten:** Events (Jahrestags-Erinnerung), Galerie, Meilenstein-Feiern
(Idee 9).
**Score:** 7/10

### 34. Energie-Ampel für den Feierabend 🚦

**Konzept:** Auf dem Heimweg/nach der Arbeit setzt man mit einem Tap seine
Feierabend-Ampel: 🟢 „voller Energie, lass was machen", 🟡 „bin ok, aber
brauch erst 30 Minuten", 🔴 „aufgebraucht — heute bitte Decke und Nähe". Der
Partner sieht die Ampel auf Dashboard/Widget, BEVOR er zur Tür reinkommt oder
anruft — inkl. sanfter Deutungshilfe.
**Warum es begeistert:** Die meisten Feierabend-Konflikte entstehen in den
ersten zehn Minuten — die Ampel entschärft genau dieses Fenster.
**Aufwand:** S (Server: S — Status-Feld mit Verfall wie Now-Playing · iOS: S —
Ampel-Picker, Partner-Anzeige, Widget).
**Abhängigkeiten:** Now-Playing-Mechanik (Status mit TTL existiert),
Widget-Snapshot, Mood-System.
**Score:** 8/10

### 35. „Frag mich das nie wieder"-Gedächtnis 🧠💜

**Konzept:** Ein gemeinsamer Wissensspeicher für die Fakten, nach denen man
sich nie zu fragen traut: Schuhgröße, Allergien, Kaffeebestellung,
Blutgruppe, Lieblingsblumen, „Chef heißt…". Strukturiert nach Kategorien,
durchsuchbar, mit „Frag mich ab!"-Quiz-Modus, der die Einträge in das
bestehende Quiz-Spiel einspeist.
**Warum es begeistert:** Es fühlt sich an wie perfekte Aufmerksamkeit — man
weiß einfach immer die Kaffeebestellung des anderen.
**Aufwand:** S (Server: S — Key-Value-Collection pro Member · iOS: S/M —
Kategorien-UI, Suche, Quiz-Einspeisung).
**Abhängigkeiten:** Quiz-Spiel (Abfrage-Modus), Care-Paket-Wunschliste
(Idee 14, verwandte Daten).
**Score:** 7/10

---

## 🏆 Top-10 für 3.0 (priorisiert)

1. **„Wie war dein Tag?"-Audio-Check-in (Idee 2)** — Das stärkste neue
   Tagesritual: baut fast komplett auf existierender Voice- und Reveal-Infrastruktur
   auf und trifft den Kern der App (Nähe im Alltag).
2. **Zeitkapsel-Briefe (Idee 1)** — Maximale Emotion pro Zeile Code: die
   Siegel-/Brief-Mechanik existiert, nur das serverseitige Zurückhalten bis
   `unlockAt` ist neu.
3. **Bedürfnis-Knopf „Ich brauche gerade…" (Idee 5)** — Kleinster Aufwand der
   Top-Gruppe, löst aber ein echtes Beziehungsproblem statt nur zu unterhalten.
4. **Gemeinsame Ziele & Sparziele (Idee 3)** — Bringt eine komplett neue,
   langfristige „Wir bauen etwas"-Dimension in die App, mit täglichem
   Wiederkomm-Grund und Widget-Potenzial.
5. **„Unsere Woche"-Wochenplan (Idee 6)** — Beantwortet die häufigste
   Alltagsfrage jedes Paares und wird zum Anker für Telefon-Dates und
   Date-Rotation (Ideen 20/15) in späteren Versionen.
6. **Aussprache-Modus (Idee 4)** — Das mutigste Feature der Liste: macht
   SoooDreamy vom Schönwetter-Begleiter zum echten Beziehungswerkzeug; UX-Aufwand
   hoch, Server trivial (Move-Relay).
7. **Meilenstein-Feiern & Badge-Album (Idee 9)** — Sehr günstig (alle Daten
   existieren schon) und liefert regelmäßige Magie-Momente „gratis" aus der
   Nutzungshistorie.
8. **Energie-Ampel für den Feierabend (Idee 34)** — S-Aufwand dank
   Now-Playing-TTL-Mechanik, aber täglicher Nutzwert und perfekt fürs Widget.
9. **Rücksicht-Radar (Idee 8)** — Sensibel umgesetzt ein Alleinstellungsmerkmal,
   das keine Mainstream-App für ZWEI baut; opt-in + Vault-Krypto sind vorhanden.
10. **„Unser Monat"-Magazin (Idee 28)** — Verwandelt bestehende Daten
    (PotD, Favoriten, Journal, Stats) in einen wiederkehrenden Gänsehaut-Moment
    und macht alle anderen Features rückwirkend wertvoller.

**Knapp dahinter (starke Kandidaten für 3.x):** Einschlaf-Herzschlag (27,
perfekte Haptik-Studio-Fortsetzung), Fernbeziehungs-Dashboard (13, falls die
Ziel-Paare überwiegend auf Distanz sind), „3 gute Dinge" (11) und
Überraschungs-Zünder (30, teilt die Server-Mechanik mit den Zeitkapseln).
Das Kuschelwesen (7) begeistert maximal, ist aber ein L-Projekt — eher das
Herzstück-Feature für 4.0.

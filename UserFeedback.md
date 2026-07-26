# UserFeedback.md — Live-Rückmeldungen zum GOOBY-Godot-Rewrite

Hier trägt **der User** ein, was ihn stört, was fehlt oder was er sich wünscht.
Der Agent liest diese Datei bei jeder Session-Runde erneut und markiert erledigte
Punkte. **Bitte einfach unten unter „Offen" anhängen — Format egal.**

## Legende

| Marker | Bedeutung |
|---|---|
| `[ ]` | offen — noch nicht bearbeitet |
| `[~]` | in Arbeit (Agent arbeitet gerade daran) |
| `[x]` | **erledigt** — Agent hat es umgesetzt (mit Commit-Hinweis) |
| `[?]` | Rückfrage/Annahme des Agents (bitte kurz bestätigen) |
| `[-]` | bewusst zurückgestellt (mit Begründung) |

---

## Offen (hier bitte eintragen)
[ ] Erstelle mal richtige Skyboxen selber
[ ] Mach das der Boden auch etwas Textur hat also mal rau ist oder uneben statt das alles nur hunderprozent gerade flächen sind.
[ ] Du kannst dir ja von vielen UIs oder Modelen erst bilder generieren und sie danach nach bauen damit du mehr infos hast wie so etwas ca. aussieht.
[ ] Der Trailer ist noch nicht perfekt und vorallem ist das gameplay etwas zu low quality also irgendwie ist das pixelig
[ ] Die Ranch ist nicht "belebt" genug und irgendwie fehlt so ein richtiges Feeling also Berge, Landschaften, Dinge zum erkunden.
[ ] Viele Regionen sehen noch recht kahl aus also da fehlt so das du Scenerie besser gemacht hast wie zb mehr Bäume, hier und dort blumen,büsche etc
[ ] Jedes Spiel muss 3D sein
[ ] Gooby braucht sein altes Model aus der alten vor Godot version wieder. (Du kannst dir ja einfach den anderen Branch anschauen)
[ ] Viele UI Elemente sind noch nicht polished
[ ] Der Stadt fehlt auch sceneriere
[ ] Manche Autos schweben
[ ] Viele UI Sachen sind meist ganz ganz außen am Rand und Skalieren nicht wirklich mit der gerät größe
[ ] Viele UI Sachen sind einfach nervig zuerreichen zb bei einem Mini Spiel kann das Pause Menü wenn man es öffnet auch nur ein Modal in der Mitte öffnen.
[ ] Das Rennen lässt alle in einander fahren?
[ ] Die Seele des Spiels fehlt.
[ ] Du musst checken das die Builds wirklich erfolgreich sind statt immer Fehler kommen.
[ ] Die kompletten Rückblicke Cutsecenen fehlen
[ ] Es fehlt fast alles von da vor und was da ist ist einfach nur schlechter, das einzig gute ist das Bau System der Rest sonst ist kacke.
[ ] Das Ganze spielt ist bisher viel zu unfertig.
[ ] Das Spiel hat keine Seele
[ ] Das Spiel ist nur eine Alpha du solltest es ein vollwertiges Spiel machen.
[ ] Alle Spiele sind grauen Haft.
[ ] Baue wirkliche 3D Spiele und nicht so 2D zeug.
[ ] Stelle sicher das wirklich alles 3D ist und nicht 2D
[ ] Das neue Gooby model ist nicht so toll wie das alte, nutze das alte bitte wieder.
[ ] Es ist irgendwie nicht alles so gut gebackportet worden nur so gerusht ohne ohne Liebe zum detail.
[ ] Jedes Game hat nicht genug Polish.
[ ] Das ganze UI ist null wie davor
[ ] Es gibt viele Bugs.
[ ] Warum ist sovieles keine richtigen Assets sondern nur premetives?
[ ] Es fehlt der polish. Nimm dir mehr Subagents die auch sowas wie Dopamin, Sounddesign und feeling bewerten und verbessern sollen.
[ ]Verbessere den Remotion Trailer massiv vor allem mit dem neuen was du alles geändert hat hat sich ja auch das aussehen geändert also baue den Trailern nochmal besser
[ ] Deine Ganze Arbeit bisher ist viel zu wenig und es kommt mir so vor als ob du keine Mühe bisher hattest. Gib dir mehr Mühe und nimm mehr Subagents und mehr Teams die gemeinsam ansachen arbeiten statt nur 6-8 Subagents. Du kannst wirklich 20-30 nutzen.
[ ] Verbessere nochmal die Gooby Ranch sowie Seceneriere ich will das es richtig schönes aussehen gibt es soll auch berge und terrain etc geben baue die OpenWorld da richtig nochmal mehr aus.
[ ]Verbessere jedes Minispiel nochmal mit jeweils 3 Subagents Fable 5 Max Thinking als Model nutzen unbedingt damit die Arbeit wirklich perfekt wird.


<!-- USER: Neue Punkte einfach hier drunter schreiben. Beispiel:
- [ ] Das HUD ist mir im Querformat zu weit links
- [ ] Der Taxi-Sound ist zu laut
-->

---

## In Arbeit

_(leer)_

---

## Erledigt

- [x] **Unsignierte .ipa per GitHub Actions bauen** — ✅ **GEBAUT UND GRÜN**
  (`ios-ipa: success`, Artefakt **GOOBY-godot-unsigned-ipa, 39,9 MB**).
  iOS-Job war bisher per `if: false` geskippt; jetzt scharf: Godot-Export
  (Xcode-Projekt) → `xcodebuild` ohne Signing → `Payload/` → `.ipa`.
  **Download:** GitHub → Actions → Lauf „GOOBY Godot" → Artefakt
  `GOOBY-godot-unsigned-ipa` → per AltStore/Sideloadly installieren.
  Jeder weitere Push auf `GOOBY-GODOT/**` baut automatisch eine neue .ipa.
- [x] **ALLE alten Minispiele neu portiert** — 28 Spiele aus dem Web-Spiel laufen jetzt
  in Godot (zahlengleiche Logik, neue Views mit JuiceKit/Postprocessing, beide
  Orientierungen, Bot-Tests). Zusammen mit teaParty/carrotCatch/GvZ/GOB NOM sind das
  **32 Spiele** im Arcade. `goobyWelt` (Gaussian Splats) wurde wie gewünscht entfernt.
- [x] **Neue Orte:** POW! (Kamera + 3 Tagesangebote), Post, Autohaus (Autos + Farben),
  Baumarkt (Material/Baupläne), Wochenmarkt (samstags, Ernte-Verkauf).
- [x] **IGohbie-Handy** mit Apps: Taxi, Guber, GOOBERANDO, Kamera (Gate über POW!),
  Freunde, GoobyPal.
- [x] **Werkstatt & Crafting** (Materialien sammeln/kaufen, Rezepte, Bau-Animation),
  **Goobay** (Verhandlungs-Minispiel), **Garten 2.0** (Grid, Wind/Schatten, Bewässerung,
  Gewächshaus, Zäune), **Shed L1–L3**, **Fenster mit Straßen-Diorama**,
  **Möbel-Liefer-Cutscene** (LKW + Clipboard).

---

## Bekannte Baustellen (Agent-Sicht, ohne User-Meldung)

Der ehrliche Rest-Backlog steht in `docs/godot-rewrite/STATUS.md` und
`docs/godot-rewrite/GODOT-PLAN.md` §6 — er wird gerade abgearbeitet.

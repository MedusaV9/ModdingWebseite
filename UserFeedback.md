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
[ ] Jedes Game hat nicht genug Polish.
[ ] Das ganze UI ist null wie davor
[ ] Es gibt viele Bugs.
[ ] Warum ist sovieles keine richtigen Assets sondern nur premetives?
[ ] Man soll beim Bauen quasi die ganze Stadt sehen außen drum plus dort sollen autos fahren , npcs laufen.
[ ] Bei Fahren game soll man bei seinem Haus richtig starten/halt die ausfahrt.
[ ] Man soll alles also auch den Haus Stil, Farbe und Gras /boden etc anpassen können.
[ ] Das HUD/UI ist nicht mehr so schön / niedlich / cozy / animal crossing new horizons wie davor
[ ] Es fehlt der polish. Nimm dir mehr Subagents die auch sowas wie Dopamin, Sounddesign und feeling bewerten und verbessern sollen.
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

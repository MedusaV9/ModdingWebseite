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
[ ] Ich kann das Spiel nicht installieren die .ipa App verschwindet sofort ich glaube es gibt da Probleme?
[ ] Die AppID ist eine andere als davor also das macht sicherlich auch probleme
[ ] Die IPA ist nur 38mb? ich glaube das ist falsch hast du wirklich alle assets übertragen?
[ ] Das App Logo ist nicht das selbe wie davor denk dran du kannst Bilder generieren also nutze es auch
[ ] Denk dran mehr Subagents bei dir zunutzen ich sehe das du nur 4 gleichzeitig nutzt. Denk dran mehr zunutzen und mehr Content hinzuzufügen also auch Cosmetics und Möbel und Items wie du im Plan auch schon hattest.
[ ] Die Spiele sehen schlechter als davor aus es fehlt das Gooby wirklich da ist und die spiele 3D sind die sind jetzt nur noch 2d?
[ ] Du musst häufiger hier rein schauen!
---

## In Arbeit

_(leer)_

---

## Erledigt

- [x] **Unsignierte .ipa per GitHub Actions bauen** — iOS-Job war bisher per `if: false`
  geskippt; jetzt scharf: Godot-Export (Xcode-Projekt) → `xcodebuild` ohne Signing →
  `Payload/` → `GOOBY-godot-unsigned.ipa` als Actions-Artefakt.
  Der Export wurde vorab lokal verifiziert (Xcode-Projekt + 17 MB PCK entstehen).
  Download: Actions-Lauf „GOOBY Godot" → Artefakt `GOOBY-godot-unsigned-ipa`.

---

## Bekannte Baustellen (Agent-Sicht, ohne User-Meldung)

Der ehrliche Rest-Backlog steht in `docs/godot-rewrite/STATUS.md` und
`docs/godot-rewrite/GODOT-PLAN.md` §6 — er wird gerade abgearbeitet.

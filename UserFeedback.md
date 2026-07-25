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

<!-- USER: Neue Punkte einfach hier drunter schreiben. Beispiel:
- [ ] Das HUD ist mir im Querformat zu weit links
- [ ] Der Taxi-Sound ist zu laut
-->

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

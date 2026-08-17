# Eigene Fragen hinzufügen (User-HowTo)

Du willst MONKEY MONEY mit eigenen Fragen bestücken (Insider für den Spiele-Abend,
Familien-Running-Gags, Spezial-Themen)? So geht's in 4 Schritten.

## 1. Datei anlegen

Lege eine neue JSON-Datei unter `content/packs/community/` an, z. B.
`content/packs/community/bundesliga_max.json`. Der Dateiname ist frei — entscheidend
sind die Felder im Inhalt. Kategorie-Slugs findest du in `content/taxonomie.json`
(`oberkategorien[].id` + `unterkategorien[].slug`); es MUSS eine existierende
Unter-Kategorie sein.

## 2. Fragen schreiben (Kopiervorlage)

Ids: `q_<ober>_<unter>_<nummer>` — nimm für eigene Fragen den Nummernkreis ab
`700000`, damit du nie mit dem offiziellen Katalog kollidierst.

```json
{
  "pack_meta": {
    "name": "Bundesliga — Fragen von Max",
    "oberkategorie": "sport",
    "unterkategorie": "bundesliga",
    "schema_version": 1,
    "sprache": "de",
    "anzahl": 1
  },
  "fragen": [
    {
      "id": "q_sport_bundesliga_700001",
      "schema_version": 1,
      "kategorie": "sport",
      "unterkategorie": "bundesliga",
      "schwierigkeit": "leicht",
      "region": "de",
      "typ": "choice",
      "altersfreigabe": "ab0",
      "tags": ["community"],
      "text": "Welcher Verein trägt seine Heimspiele im Signal Iduna Park aus?",
      "antworten": ["Borussia Dortmund", "Schalke 04", "VfL Bochum", "1. FC Köln"],
      "korrekt": 0,
      "tipps": [
        "Das Stadion ist das größte Fußballstadion Deutschlands.",
        "Die Heimfans stehen auf der berühmten Südtribüne.",
        "Der Verein spielt in Schwarz-Gelb."
      ],
      "erklaerung": "Der Signal Iduna Park (Westfalenstadion) ist das Heimstadion von Borussia Dortmund und mit über 81.000 Plätzen Deutschlands größtes Stadion.",
      "quelle": "eigenes Wissen, geprüft gegen Vereinsangaben",
      "stand_datum": "2026-08-14",
      "verfallsdatum": null,
      "faktencheck_status": "community",
      "erstellt_von": "max",
      "erstellt_am": "2026-08-14"
    }
  ]
}
```

Wichtigste Regeln (der Validator erklärt dir jeden Verstoß):

- Genau 4 unterschiedliche Antworten, `korrekt` = Index 0–3.
- GENAU 3 Tipps (Stufen: vage → eingrenzend → fast Antwort); kein Tipp darf die Antwort enthalten.
- `erklaerung` ist Pflicht (die „Warum-Karte" nach der Auflösung).
- Längen: Frage ≤ 190, Antwort ≤ 40, Tipp ≤ 90, Erklärung ≤ 220 Zeichen.
- Wörter wie „aktuell/derzeit" vermeiden — sonst ist ein `verfallsdatum` Pflicht.

## 3. Prüfen

```bash
node tools/content/validate.mjs content/packs/community/bundesliga_max.json
```

Meldet der Validator `0 Fehler`, ist die Datei spielbar. Warnungen (W-Codes) sind
Hinweise, keine Blocker. Ohne Datei-Argument prüft der Befehl den gesamten Katalog.

## 4. Spielen

Der Server lädt beim Start ALLE Packs unter `content/packs/` automatisch — auch deine.
Einfach Server neu starten (`npm run dev`), Raum aufmachen, fertig. Deine Fragen
laufen im normalen Fragen-Pool ihrer Kategorie mit.

Mehr Tiefe (alle 8 Frage-Typen, Schwierigkeits-Kalibrierung, Tipp-Dramaturgie):
`docs/content/FRAGEN-SCHREIBEN.md` und `docs/CONTENT-PLAN.md`.

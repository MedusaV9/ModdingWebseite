# Fragen schreiben — HowTo für Fragen-Agents

Zielgruppe: die 10+ Produktions-Agents, die den Katalog von 140 Seed-Fragen auf das
v1-Soll (3.000) ausbauen. Die BIBEL ist `docs/CONTENT-PLAN.md` — dieses HowTo ist die
Arbeits-Checkliste, ersetzt aber nicht die Plan-Lektüre.

## Pflicht-Lektüre vor der ersten Frage

1. `docs/CONTENT-PLAN.md` §1 (Taxonomie), §2 (Schema + 14 Regeln), §3 (Kalibrierung), §5 (Produktions-Anleitung).
2. `content/packs/_eich/eich.json` — die 20 Eich-Fragen. Sie eichen dein Schwierigkeits-Gefühl gegen Drift zwischen parallelen Agents.
3. Ein bestehendes Seed-Pack derselben Ober-Kategorie als Stil-Referenz (z. B. `content/packs/core/gaming/minecraft.json`).

## Workflow (immer in dieser Reihenfolge)

```bash
node tools/content/stats.mjs        # 1. Lücken-Tabelle: WO fehlen Fragen (Ist vs. Soll)?
# 2. Unter-Kategorie wählen, Pack-Datei anlegen/erweitern (s. Konventionen unten)
node tools/content/validate.mjs     # 3. Hartes Gate: MUSS 0 Fehler melden (Exit 0)
npm run format                      # 4. Prettier (npm run lint prüft auch content/**.json)
npx vitest run                      # 5. Loader-Tests bleiben grün
```

## Datei- und Id-Konventionen

- Pack-Pfad: `content/packs/core/<oberkategorie>/<unterkategorie>.json` — eine Datei pro
  Unter-Kategorie, Format `{ pack_meta, fragen[] }` (Struktur: `content/schema/frage.schema.json`).
- `pack_meta.anzahl` muss `fragen.length` entsprechen (Validator F14).
- Id-Format: `q_<oberkategorie>_<unterkategorie>_<laufnummer 6-stellig>` (Validator F01).
- Nummernkreise je Unter-Kategorie: `000001–000899` Produktions-Agents (fortlaufend),
  `000901–000999` reserviert für Eich-Fragen (`_eich`), `700000+` Community/User
  (`docs/content/EIGENE-FRAGEN.md`). Ids sind global eindeutig und werden NIE recycelt.

## Schwierigkeit: die 4 Anker-Personas (Plan §3.1)

| Stufe     | Bauch-Test beim Schreiben                              | Ziel-Quote (ratebereinigt) |
| --------- | ------------------------------------------------------ | -------------------------- |
| leicht    | „Oma UND der 12-jährige Cousin schaffen das."          | 80–95 %                    |
| mittel    | „Wer die Kategorie MAG, weiß es; wer nicht, rät klug." | 45–70 %                    |
| schwer    | „Nur Fans/Hobbyisten der Unter-Kategorie."             | 15–40 %                    |
| ultrahard | „Selbst der Fan flucht — richtig = Lottogewinn-Jubel." | < 10 %                     |

Mix pro 20er-Block: **8 leicht / 6 mittel / 4 schwer / 2 ultrahard**.
ULTRAHARD heißt: < 10 % Trefferquote, aber 100 % Auflösungs-Zufriedenheit — nach der
Auflösung ein „Stimmt! Wow!", nie ein „Häh, Auslegungssache" (Plan §5.4).

## Die 3-Stufen-Tipps (15 % / 35 % / 60 % des möglichen Gewinns)

| Stufe            | Funktion                                | Beispiel (Gerd Müller)                                   |
| ---------------- | --------------------------------------- | -------------------------------------------------------- |
| 1 — vage         | aktiviert Vorwissen (Epoche/Raum/Genre) | „Der Rekord stammt aus einer Zeit mit D-Mark."           |
| 2 — eingrenzend  | verkleinert den Suchraum deutlich       | „Der Spieler wurde ‚Bomber der Nation' genannt."         |
| 3 — fast Antwort | lässt genau EINEN Denk-Schritt übrig    | „Er spielte seine ganze Bundesliga-Zeit beim FC Bayern." |

- Immer GENAU 3 Tipps (`wahr_falsch`: GENAU 0) — Validator F06.
- KEIN Tipp darf die korrekte Antwort enthalten (auch nicht normalisiert/als Teilwort) — F06.
- Tipps ≤ 90 Zeichen — F04.

## Die häufigsten Validator-Fallen

- **F04 Längen:** Frage ≤ 190, Antwort/Element ≤ 40, Tipp ≤ 90, Erklärung ≤ 220 Zeichen; Emoji-Rätsel 3–7 Emojis.
- **F06 Tipp-Leak:** Antwort-Wort in einem Tipp → umformulieren (Umschreibung statt Nennung).
- **F09 Verfalls-Wörter:** „aktuell/derzeit/amtierend/neuest/…" im Text erzwingen ein `verfallsdatum`. Besser: Frage zeitfest formulieren („Wer hielt 2024 den Rekord …" statt „Wer hält aktuell …").
- **F11/W11 Duplikate:** vorher im Ziel-Pack suchen; gleiches Paar Antwort+Unter-Kategorie gibt eine Warnung — bewusst einsetzen, nicht aus Faulheit.
- **W05 Positions-Bias:** den `korrekt`-Index pro Frage WÜRFELN — nie reflexhaft die richtige Antwort an Position 0 schreiben (der Validator warnt, wenn ein Index in einem Pack > 50 % abdeckt; gleiches gilt für `korrekt_mehrfach` und bereits sortierte `sortier`-Elemente).
- **W12 Antwort-Balance:** längste Antwort ≤ 2× kürzeste — die richtige Antwort darf sich NIE durch Länge/Detailgrad verraten.
- **W13 Verbots-Muster:** keine Meta-Optionen („alle genannten"), keine Doppel-Negation, Fragen enden mit „?" (außer Aussage-Typen).

## Gut / Schlecht

**Distraktoren — artgleich und plausibel:**

- SCHLECHT: „Wie heißt Marios Bruder?" → Luigi, _Sonic_, _Pikachu_, _Lara Croft_ (falsche Universen — Raterei löst es).
- GUT: → Luigi, Wario, Toad, Yoshi (alle Mario-Universum, alle artgleich).

**Eindeutig verteidigbar:**

- SCHLECHT: „Was ist das beste Item in Minecraft?" (Meinung, nicht verteidigbar).
- GUT: „Welches Erz benötigt man, um Netherit herzustellen?" (genau eine belegbare Antwort).

**Zeitfest statt tagesaktuell:**

- SCHLECHT: „Wer ist der aktuelle Bundesliga-Rekordtorschütze einer Saison?" (verfällt; F09).
- GUT: „Wie viele Tore erzielte Gerd Müller in der Bundesliga-Saison 1971/72?" (historischer Fixpunkt).

**Tipp ohne Leak:**

- SCHLECHT: Tipp 3 = „Beginnt mit ‚Lu' und reimt sich auf ‚Fidschi'." (nennt die Antwort quasi).
- GUT: Tipp 3 = „Er trägt Grün und ist der ängstlichere der beiden Brüder."

## Nur SICHERES Wissen

Jede Frage muss `quelle` + `stand_datum` tragen (F08). Schreibe NUR Fakten, die du ohne
Recherche-Zweifel verteidigen kannst — im Zweifel eine ANDERE Frage stellen. Für
`faktencheck_status: "geprueft"` gilt Vier-Augen: `geprueft_von` ≠ `erstellt_von`,
`quelle` als URL, `faktencheck_notiz` gefüllt. Seed-Fragen starten als `"entwurf"`.

# E10 — Minigame-Fairness & Ökonomie (GOOBY-Godot-Rewrite)

**Scope:** `/workspace` @ `cursor/gooby-godot-rewrite-d1d8` (`8cfc20e0`), Godot 4.4.1, node 22.
**Regel eingehalten:** Repo **unverändert** (`git status` leer nach allen Läufen); sämtliche Treiber
liegen unter `/tmp/gooby-godot/drv/`, sämtliche Rohdaten unter `/tmp/gooby-godot/eval/`.

| Treiber | Zweck |
| --- | --- |
| `drv/bots_gd.gd` | teaParty/carrotCatch-Bots, Seeds 1–100 × 4 Modi (GDScript, `godot --headless --script`) |
| `drv/bots_web.mjs` | identische Seeds durch die Web-`.logic.js` (Muster `tools/cross_check.mjs`, 100 statt 50 Seeds) |
| `drv/compare.py` | Paritäts-Diff + Verteilungen + Fixture-Frischecheck |
| `drv/gvz_gd.gd`, `drv/gvz_focus.gd` | GvzBot über 15 Level × 3 Schwierigkeiten (5 bzw. 20 Seeds) + Nutella-Horten |
| `drv/exploit_gd.gd` | degenerierte Strategien (AFK, Ecke/Mitte campen, Dauerhalten) |
| `drv/pregame_keys.gd` | AppSettings-/Save-Key-Trennung des Pregame |

**Verdict:** Web-Parität **makellos** (800/800 Bot-Läufe bitgleich), teaParty/carrotCatch-Verteilungen
plausibel und difficulty-monoton. Die Probleme liegen in der **Ökonomie-Umgebung**, nicht in der
Spiellogik: der Coin-Hahn hat im Godot-Arcade **keine Bremse** (kein Energie-Gate wie im Web), die
**GvZ-Coin-Zeile ist 10–20× schlechter** als teaParty, und die **GvZ-Schwierigkeitskurve ist nicht
monoton** (Leicht L13 unspielbar für den Bot, Schwer L2/L13/L14 0/20).

---

## 1) Bot-Verteilungen — teaParty / carrotCatch (100 Seeds × 4 Modi, GDScript)

| Spiel | Modus | min | p25 | Median | p75 | max | Mittel | SD | Dauer (med) | E[Coins] | Cap-Quote |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| teaParty | easy | 101 | 117 | **125** | 131 | 144 | 124.3 | 9.8 | 73.2 s | 18.00 | 100 % |
| teaParty | normal | 78 | 92 | **98** | 104 | 128 | 98.0 | 8.8 | 61.3 s | 23.94 | 29 % |
| teaParty | hard | 57 | 89 | **95** | 102 | 121 | 94.7 | 10.8 | 61.1 s | 25.77 | 91 % |
| teaParty | endless | 3 | 48 | **74** | 111 | 227 | 83.2 | 48.6 | 48.7 s | 5 (flat) | — |
| carrotCatch | easy | 71 | 86 | **93** | 99 | 114 | 92.0 | 8.4 | 72.1 s | 17.98 | 99 % |
| carrotCatch | normal | 70 | 82 | **88** | 95 | 112 | 88.4 | 8.6 | 60.1 s | 24.95 | 96 % |
| carrotCatch | hard | 56 | 75 | **82** | 88 | 110 | 81.8 | 10.1 | 60.2 s | 24.98 | 99 % |
| carrotCatch | endless | 4 | 28 | **54** | 79 | 244 | 61.6 | 43.7 | 44.3 s | 5 (flat) | — |

* **Monotonie (Score):** teaParty 125 → 98 → 95, carrotCatch 93 → 88 → 82 — beide **monoton fallend**;
  Endlos-Läufe streuen erwartungsgemäß breit (SD 44–49 gegen 9–11 bei Timed).
* **Ziel-Trefferquote** (`target` 85 bzw. 70): tea 100 % / 93 % / 83 %, catch 100 % / 100 % / 90 % —
  der Endlos-Unlock (`beaten[id].hard`) ist mit Bot-Skill also realistisch erreichbar.
* **Verteilungsform** plausibel: unimodal, keine Ausreißer-Cluster, kein Seed mit Score 0.

## 2) Web-Parität — GDScript vs. `.logic.js` (identische Seeds)

| Prüfung | Umfang | Ergebnis |
| --- | --- | --- |
| Score-Identität | 2 Spiele × 4 Modi × 100 Seeds = **800 Läufe** | **0 Abweichungen** |
| Zähler (`cups`/`spills`/`missedCarrots`) | 800 Läufe | **0 Abweichungen** |
| `elapsed` (Double) | 800 Läufe | max \|Δ\| = **5.0e-13 s** (reine ULP-Drift) |
| `GoobyRng.next_u32` | 5 Seeds × 10 Werte | **bitidentisch** |
| Coin-/Difficulty-Policy | 99 Fälle (3 Coin-Zeilen × 11 Scores × 3 Modi) | **0 Abweichungen** |
| Repo-Fixtures `tests/expected/*.json` | Seeds 1–50 × 4 Modi, beide Spiele | **0 Abweichungen** → Fixtures sind aktuell |

## 3) Coin-Ökonomie

Auszahlung (`MinigameAward.award` → `Economy.award`) ist zahlengleich zu
`GOOBY/src/systems/economy.js::awardMinigame`: `base = min(max, max(min, round(clamp(score/divisor) ×
mult)))`, Tages-×2 beim ersten Lauf pro Spiel/Tag, Endlos pauschal 5 c gegen die 100 c/Tag-Zeile
(`ENDLESS_DAY_CAP`), Modifier-Zeile 150 c/Tag. **Für Timed-Läufe existiert bewusst kein Tages-Cap** —
im Web bremst dafür `meta.energyCost` (8 Energie/Start, `framework.js:1372-1376`).

| Zeile | divisor / min / max | Score für Cap (normal / hard) | E[Coins] Bot easy / normal / hard |
| --- | --- | --- | --- |
| teaParty | 4 / 4 / 26 | 104 / 80 | 18.00 / 23.94 / 25.77 |
| carrotCatch | 3 / 4 / 25 | 75 / 57 | 17.98 / 24.95 / 24.98 |
| gvz | 12 / 4 / 40 | 480 / 370 | 5 / 8 / 10 (pro gewonnenem Level) |

**Zeit-pro-Münze (Bot-Median, ohne Countdown/Results ≈ 12 s):**

| Spiel / Modus | Dauer | Coins | s/Coin |
| --- | ---: | ---: | ---: |
| teaParty normal | 61 s | 24 | **2.6** |
| teaParty hard | 61 s | 26 | **2.4** |
| carrotCatch normal | 60 s | 25 | **2.4** |
| teaParty/carrotCatch endless | 44–49 s | 5 | 8.9–9.7 |
| GvZ easy (Wiederholung) | 262 s | 5 | **52.3** |
| GvZ normal (Wiederholung) | 268 s | 8 | **33.5** |
| GvZ hard (Wiederholung) | 268 s | 10 | **26.8** |
| GvZ Kampagne, 15 Level in EINER Session (normal) | 62 min | 40 (Cap) | **93** |

## 4) GvZ-Bot: Siegquoten (5 Seeds/Zelle, Auffälligkeiten mit 20 Seeds nachgeprüft)

| Modus | Gesamt | Ausreißer |
| --- | --- | --- |
| easy | 70/75 | **L13: 0/20** (normal: 20/20) |
| normal | 74/75 | L15 4/5 (Boss) |
| hard | 58/75 | **L2: 0/20**, **L13: 0/20**, **L14: 0/20** |

Nutella-Horten (Bot sammelt nur, baut nichts): Peak 450–500 (Cap 9975), Ausgang immer `lost`,
Score 8–12. Nutella ist an keiner Stelle score- oder coinwirksam → **kein Hortungs-Exploit**.

## 5) Exploit-Matrix (100 Seeds je Zelle)

| Strategie | Ergebnis | Bewertung |
| --- | --- | --- |
| carrotCatch **AFK** (nichts fangen) | Score 0 → **4 c** (erster Lauf/Tag 8 c) je 60-s-Runde | Row-Min zahlt Nulleinsatz → 200 c/h |
| carrotCatch **Ecke campen** (x = −2.75) | Median 8 Punkte, 8 Fänge → 4 c | schlechter als aktiv (88) → kein Exploit |
| carrotCatch **Mitte campen** | Median 14 Punkte, 3 Junk-Treffer → 4 c | kein Exploit (Score floort bei 0, kein Negativ-Griefing) |
| teaParty **Dauerhalten** (Timed) | Überlauf löst automatisch aus (`tea_party.gd:90`), 18–21 Spills, Score 0 → 4–5 c | sauber bestraft |
| teaParty **Dauerhalten (Endlos)** | 3 Spills nach **9.3 s** → 5 c Pauschale = **1.9 s/c** | schnellste Coin-Quelle im Spiel, aber durch 100 c/Tag gedeckelt (≈ 20 Suizid-Läufe ≈ 7 min) |
| GvZ **Nutella-Horten** | siehe oben | kein Exploit |
| GvZ **Level-1-Wiederholung in einer Session** | +50 Punkte/Durchlauf, Session-Cap 40 c | ökonomisch sinnlos |

---

## Befunde

### P0
Keine.

### P1

**P1-1 — GvZ-Schwierigkeit nicht monoton; Bot-Zertifizierung deckt nur `normal` ab.**
`L13` gewinnt der Bot auf **normal 20/20**, auf **easy 0/20** — Leicht ist dort *schwerer* als Mittel,
obwohl `gvz_balance.json` für easy `zombie_hp_pct 80` + `start_nutella_bonus 25` setzt. Auf hard sind
`L2`, `L13`, `L14` mit **0/20** Mauern, während L3–L12 5/5 laufen. `tests/unit/test_gvz_bot.gd`
simuliert ausschließlich `"normal"` (einziger hard-Bezug: „hard wirkt“ per Tick-Ungleichheit), die
Lücke ist daher unbemerkt. → Entweder Bot-Heuristik oder Level-/Difficulty-Zeilen fixen und die
Zertifizierung auf easy/hard × alle 15 Level ausweiten.

**P1-2 — Coin-Hahn ohne Bremse: kein Energie-Gate im Godot-Arcade.**
Der Web-Launch zieht `meta.energyCost` (Default 8) pro Start und blockt bei Erschöpfung/Krankheit
(`framework.js:1372-1376`, `stats.gd` kennt `is_exhausted` — **niemand ruft es im Minigame-Pfad**).
`MinigameRegistry` hat weder `energy_cost` noch `min_level`; `MinigameAward` bucht nur `fun +15`.
Timed-Coins laufen über `Economy.award(reason "minigame")` = ungedeckelt. Ergebnis: **≈ 1 200 c/h**
aktiv, **200 c/h** vollständig AFK, unbegrenzt oft — der komplette Möbelkatalog (65 Teile,
**7 785 c**) ist in ~6.5 h Grind bzw. ~39 h Nichtstun finanziert. Mindestens eines von
Energie-Kosten / Tages-Cap / Level-Gate muss vor Release stehen.

**P1-3 — GvZ-Coin-Zeile ist gegenüber teaParty grob unfair.**
Ein gewonnenes GvZ-Level dauert 135–340 s und zahlt 4–14 c (`divisor 12`, Score = `kills×2 +
stars×10 + level×4 + 50` einmalig) → **27–52 s/Coin** gegen **2.4–2.6 s/Coin** bei teaParty/
carrotCatch, also **10–20× schlechter**. Auch der Bestfall („alles in einer Session“) hilft nicht:
15 Level in 62 min laufen in den 40-c-Cap = **93 s/Coin**. Zusätzlich zahlt der Kill-Score fast nichts
(L1: 8 Kills = 16 Punkte gegen 30 Punkte Sternbonus). Empfehlung: eigene GvZ-Zeile pro **Level**
statt pro Session (Award beim `won`-Ereignis) und `divisor` auf die realen Score-Bänder (50–210)
eichen.

### P2

**P2-1 — „Schwer“ ist ökonomisch (fast) wirkungslos, weil der Row-Cap bindet.**
carrotCatch: E[Coins] normal **24.95** vs. hard **24.98** (+0.1 %) bei 6 Punkten niedrigerem Median —
96 % bzw. 99 % aller Läufe liegen am Cap 25. teaParty: 23.94 → 25.77 (+7.6 %). Der ×1.3-Multiplikator
verpufft, weil `score@cap` (57 bzw. 80) weit unter dem Bot-Median liegt. Zahlen sind identisch zum
Web (Parität gewollt) → Fix gehört in die geteilte Policy, nicht in den Port.

**P2-2 — „Leicht“ zahlt fix 18 c, Score ist dort irrelevant.**
100 % (tea) bzw. 99 % (catch) der Easy-Läufe landen auf exakt 18 c (`round(26×0.7)`), d. h. innerhalb
von Leicht gibt es keinerlei Leistungsanreiz.

**P2-3 — Endlos ist dominiert *und* per Suizid-Lauf trivial abfarmbar.**
5 c pauschal für 44–49 s ehrliches Spiel (8.9–9.7 s/c) — schlechter als jeder Timed-Lauf. Umgekehrt
liefert „Kanne halten, 3× überlaufen lassen“ in **9.3 s** dieselben 5 c (1.9 s/c). Nur der
100-c-Tagescap hält den Schaden klein (≈ 7 min für das Tageslimit), deshalb P2 statt P1.
Vorschlag: Endlos-Pauschale an `endlessBest`/Laufdauer koppeln oder Mindestlaufzeit fordern.

### P3

* **P3-1 — Rotate-Gate ist toter Code.** `MinigameFrameworkLogic.should_show_rotate_gate` /
  `orientation_lock_for` werden nirgends aufgerufen. Ein global auf „portrait“ gestelltes
  `orientation_mode` zwingt das Landscape-Spiel GvZ ohne jeden Hinweis in Hochkant
  (`minigame_host.gd:87-95`).
* **P3-2 — Row-Min als Trostpreis.** `min 4` zahlt bei Score 0 dieselben 4 c wie ein Score von 12 —
  in Kombination mit P1-2 der eigentliche AFK-Antrieb; isoliert nur ein Feinschliff-Thema.
* **P3-3 — Zertifizierungs-Breite.** `tools/cross_check.mjs` deckt 50 Seeds ab; 100 Seeds liefen hier
  ohne einen einzigen Diff — Aufstockung ist billig und würde die Toleranz weiter absichern.
* **P3-4 — GvZ-Levelbonus skaliert mit der Level-ID, nicht mit dem Aufwand** (`level_bonus 4`):
  L15 gibt 60 Punkte Grundbonus, L1 nur 4 — das verstärkt P1-3 für frühe Level.

## 6) Pregame-Merkverhalten (Punkt 4) — sauber

`drv/pregame_keys.gd`, frische `settings.json`:

```
mg_orientation.teaParty=landscape  mg_orientation.carrotCatch=portrait
mg_orientation.gvz=<default auto>  orientation_mode=auto  audio.music=1.0
{"audio":{...},"doors_animated":true,"language":"de",
 "mg_orientation":{"carrotCatch":"portrait","teaParty":"landscape"},
 "orientation_mode":"auto","reduced_motion":false,"version":1}
```

* Orientierung **pro Spiel** unter `mg_orientation.<id>` (AppSettings/Gerät), Schwierigkeit **pro
  Spiel** unter `minigames.difficulty.<id>` (Save) — keine Kollision mit dem globalen
  `orientation_mode`, keine Kollision der Audio-Keys, Reload-fest.
* `difficulty_slice_of` liest pro Spiel getrennt (`teaParty: hard/best 90/endlessBest 210/unlocked
  true` vs. `carrotCatch: easy/0/0/false` vs. `gvz: normal/0/0/false`).
* Endlos wird bewusst nicht gemerkt (Web-Muster) — korrekt umgesetzt.
* Einzige Anmerkung: Punkt-Notation der Keys bricht bei Spiel-IDs mit `.` — heute unmöglich, als
  Konvention aber erwähnenswert.

# E11 — GvZ-Kampagnen-Kurve

**Stand:** Branch `cursor/gooby-godot-rewrite-d1d8` (historisch; heute: `MedusaV9/ModdingWebseite` @ `cursor/bubble-shield-loop`), Commit `8cfc20e0`, Godot
`4.4.1.stable`, 2026-07-25. Das Repo wurde nicht verändert; alle Treiber und
Ergebnisse liegen unter `/tmp/gooby-godot/eval/`.

## Verdict

**FAIL / P1.** E10 ist vollständig bestätigt: Easy L13 gewinnt `0/20`; Hard
L2/L13/L14 gewinnen jeweils `0/20`. Zusätzlich ist Hard L15 mit `18/20`
erfolgreicher als Normal L15 (`15/20`). Das ist keine monotone
Schwierigkeits- oder Kampagnenkurve. Die Difficulty-Zahlen wirken, aber der
zustandsadaptive Bot reagiert auf die veränderten HP-/Tempo-Schwellen
diskontinuierlich. Dadurch ist „Bot gewinnt“ derzeit kein belastbarer
Spielbarkeitsbeweis.

## Befunde nach Schwere

### P0

Keine.

### P1

1. **Difficulty-/Kampagnenkurve bricht mehrfach.**
   - Difficulty-Inversion: L13 `easy 0 < normal 20`; L15 `hard 18 > normal 15`.
   - Level-Inversion: Easy `L12 20 → L13 0 → L14 20`; Hard
     `L1 20 → L2 0 → L3 20` und `L12 20 → L13 0 → L14 0 → L15 18`.
   - Die bestehenden Bot-Tests prüfen nur drei Seeds früh, einen Seed in
     L8/L12/L13 und fünf Boss-Seeds; sie können diese 20-Seed-Klippen nicht
     entdecken (`tests/unit/test_gvz_bot.gd:9-59`).

2. **Bot-Heuristik ist die Hauptursache der paradoxen Ergebnisse.**
   - Es gibt keine `applyDifficulty`-Funktion. Startbonus wird in
     `scripts/minigames/games/gvz/gvz_logic.gd:29-50` angewandt; HP/Tempo in
     `gvz_zombies.gd:13-20`; Boss-HP in `gvz_zombies.gd:126-131`.
   - Der Defizitentscheid hängt hart an `threat` und einer 115-%-Schwelle
     (`gvz_bot.gd:168-190`). `_lane_capacity` teilt jedoch durch das **globale
     Basistempo** und ignoriert Zombie-`speed_pct`, Hard-Bonus, Regen, Rage und
     Slow (`gvz_bot.gd:636-652`). Gerade L13 hat Regen und Sprinter/Hüpfer.
   - Isolationsmessung L13: Normal `20/20`; `HP=80 %` allein `0/20`
     (Ballon); `+25 Nutella` allein `20/20`; Easy komplett `0/20` (Hüpfer).
     `HP=120 %` allein `20/20`, aber `Tempo +10` allein `0/20`. Niedrigere HP
     unterschreiten Notfall-Schwellen; höheres Tempo wird in der
     Kapazitätsrechnung nicht abgebildet.
   - Hard L2: `HP=120 %` allein `0/20`, Tempo allein `20/20`; der 20-%-HP-Sprung
     ist mit nur Sammler/Möhrenschütze eine echte Startlevel-Klippe.
   - Hard L14: sowohl `HP=120 %` allein als auch `Tempo +10` allein `0/20`.
   - Rüstung wird gar nicht skaliert (`gvz_zombies.gd:19-28`): Difficulty wirkt
     je nach Gegnermix unterschiedlich stark.

3. **L15 ist nicht „machbar-aber-knapp“ im Sinne einer robusten
   Fähigkeitskurve.** Der Baseline-Bot schafft Normal nur `15/20`, objektiv
   schwächere Platzierungsfrequenzen schaffen aber `17–18/20`; ein reaktiver
   Bot ohne Spawn-Voraussicht `17/20`, ohne Boss-Sonderwissen sogar `19/20`.
   Die Baseline reserviert Booms für den Boss (`gvz_bot.gd:501-512`), verliert
   aber gegen normale Beschwörungen (Eimer/Hüpfer/Hütchen/Sprinter), nicht
   gegen Boss-HP. Hard triggert mehr Notfallbauten und wird dadurch mit
   `18/20` paradoxerweise leichter als Normal.

4. **Einführungsversprechen ist in 6/12 Turm-Leveln nicht belegt; L11-Nebel
   ist funktional tot.** Im Einführungslevel setzt der Normal-Bot Eis,
   Doppelmöhre, Magnet, Trampolin, Sternchen und Melone in jeweils `0/20`
   Läufen nie. Die Levelauswahl zeigt nur Nummer/Boss/Sterne, keine
   `new_towers`/`new_zombies` (`gvz_level_select.gd:86-106`). L11 liefert
   `mods.fog_cols=3` (`data/gvz_levels.json:1313-1315`), der Renderer prüft
   stattdessen `mods.fog` (`gvz_game.gd:433-438`) — kein Nebel.

5. **Nach vollständigem Abschluss meldet das Framework 14 statt 15 Level.**
   `max_unlocked()` ist nach allen Siegen auf 15 gedeckelt
   (`gvz_progress.gd:74-80`); `finish_session()` meldet davon pauschal `-1`
   (`gvz_game.gd:100-111`).

### P2

1. **Tote/teilwirksame Balance-Keys.**
   - `grid.lanes/cols/cell_mm` werden im Lauf ignoriert; Konstanten stehen in
     `gvz_logic.gd:14-19`.
   - `ticks_per_second` steuert Boss-Einzug, Spawn/Wellen rechnen aber hart
     mit `20.0` (`gvz_logic.gd:412-444`). Pack-Override ist daher nur
     teilwirksam.
   - `towers.eis_gooby.slow_pct` ist tot; 50 % steht hart in
     `gvz_zombies.gd:281-296`.
   - `zombies.tuersteher.shield` ist tot; allein `armor=="schild"` steuert die
     Wirkung (`gvz_zombies.gd:55-78`).
   - Level-`setting`, `new_towers`, `new_zombies` sind Laufzeit-Metadaten ohne
     Anzeige; `new_towers` wird nur validiert (`gvz_data.gd:65-75`).
   - Keine fehlenden erforderlichen Balance-Keys gefunden; `fog`/`fog_cols`
     ist der konkrete Code/Daten-Mismatch.

2. **Slice-Normalisierung heilt Werte nicht.** Ein gültiger Save-Roundtrip ist
   semantisch verlustfrei (JSON-Zahlen werden lediglich `float`), aber
   `normalize_slice()` lässt Sterne `999/-4`, negativen Bestwert und
   `"false"` als Cleared-Wert stehen (`gvz_progress.gd:30-38`). UI/Gesamtsumme
   können dadurch Werte außerhalb `0..45` zeigen.

3. **Dokumentierte Sticker-Meilensteine L5/L10/L15 werden im GvZ-Code nicht
   ausgelöst.** Unter `scripts/minigames/games/gvz/**` gibt es keinen
   `StickerUnlocks`-/`gvz_kampagne`-Aufruf; der vorhandene Event-Hook bleibt
   unverbunden.

### P3 / bestanden

- Normaler Content-Pack-Pfad funktioniert: Wegwerf-Pack
  `balance/data/balance.json → values.gvz` wurde von der echten
  `ContentRegistryService` geladen; Möhrenschützen-Kosten `100→137` und
  Sky-Drop `25→31`, während Schaden `20` per Deep-Merge erhalten blieb.
  Pfad: `content_registry.gd:151-176` → `gvz_data.gd:23-30`.
- Alle zehn normalen Zombie-Typen spawnen explizit in der Kampagne; Knurps
  erscheint als L15-Boss. Es gibt keinen nie spawnenden Zombie-Katalogeintrag.
- Sterne entsprechen dem Design: 0 Mäher → 3, 1 → 2, ≥2 → 1
  (`gvz_progress.gd:41-45`); gültige Slice-Daten überstehen Save/Load.

## Telemetrie-Matrix — 15 Level × 20 Seeds × 3 Schwierigkeiten

Zelle: `Siege/20 · R=Restleben Ø aller Läufe · t=Dauer Ø s · ΔN=End-Nutella
minus Start-Nutella Ø der Siege`. `—` = kein Sieg.

| L | Easy | Normal | Hard |
|---:|---|---|---|
| 1 | 20 · R1.0 · 135s · +150 | 20 · R1.0 · 137s · +150 | 20 · R1.0 · 138s · +150 |
| 2 | 20 · R3.0 · 184s · +250 | 20 · R3.0 · 185s · +175 | **0 · R0.0 · 150s · —** |
| 3 | 20 · R5.0 · 220s · +150 | 20 · R5.0 · 222s · +150 | 20 · R5.0 · 223s · +50 |
| 4 | 20 · R5.0 · 225s · −25 | 20 · R5.0 · 227s · 0 | 20 · R4.0 · 228s · 0 |
| 5 | 20 · R3.0 · 280s · −25 | 20 · R3.0 · 288s · 0 | 20 · R4.0 · 267s · −75 |
| 6 | 20 · R4.0 · 320s · −150 | 20 · R3.0 · 268s · −125 | 20 · R2.0 · 268s · −175 |
| 7 | 20 · R3.0 · 295s · −100 | 20 · R5.0 · 284s · 0 | 20 · R5.0 · 288s · −25 |
| 8 | 20 · R2.0 · 297s · −175 | 20 · R5.0 · 297s · −75 | 20 · R5.0 · 310s · −25 |
| 9 | 20 · R4.85 · 212s · +550 | 20 · R4.85 · 213s · +526 | 20 · R4.90 · 214s · +528 |
| 10 | 20 · R4.0 · 302s · −75 | 20 · R3.0 · 340s · −75 | 20 · R3.0 · 325s · −100 |
| 11 | 20 · R5.0 · 256s · +50 | 20 · R4.0 · 252s · +125 | 20 · R4.0 · 273s · −75 |
| 12 | 20 · R5.0 · 262s · +150 | 20 · R4.0 · 279s · −75 | 20 · R5.0 · 285s · −125 |
| 13 | **0 · R3.0 · 241s · —** | 20 · R1.0 · 290s · −75 | **0 · R3.0 · 158s · —** |
| 14 | 20 · R4.0 · 326s · −75 | 20 · R3.0 · 292s · −125 | **0 · R2.0 · 280s · —** |
| 15 | 20 · R4.65 · 155s · −186 | 15 · R4.0 · 201s · −168 | 18 · R3.3 · 219s · −174 |

Rohdaten: `/tmp/gooby-godot/eval/E11-telemetry.json`.

## Boss L15 — schwächere Strategien, Normal, 20 Seeds

Drops wurden weiter sofort gesammelt; `cadence_N` erlaubt nur alle N Ticks
eine Platzierung. „Reaktiv“ verbirgt ungespawnte Plan-Einträge; „bossblind“
zusätzlich den Boss während der Botentscheidung.

| Variante | Siege | Dauer Ø alle | Restleben Ø | Einordnung |
|---|---:|---:|---:|---|
| Baseline, Aktion jeden Tick | 15/20 | 201s | 4.0 | Referenz |
| Aktion alle 5 Ticks (0,25s) | 17/20 | 197s | 4.1 | besser trotz weniger APM |
| Aktion alle 20 Ticks (1s) | 18/20 | 173s | 4.3 | deutlich besser |
| Aktion alle 60 Ticks (3s) | 17/20 | 197s | 3.5 | weiterhin besser |
| reaktiv, kein Spawn-Lookahead | 17/20 | 203s | 4.0 | besser |
| reaktiv + kein Boss-Sonderwissen | 19/20 | 281s | 4.55 | fast sicher, nur langsamer |

**Antwort:** Knurps ist erreichbar, aber nicht sauber „knapp“. Das knappe
Baseline-Ergebnis misst Fehlentscheidungen der Heuristik; weniger
Entscheidungen bzw. weniger Sonderwissen verbessern die Winrate.

## DPS/Kosten und Turm-Nutzen

20 Ticks/s. „DPS/100“ ist direkter Dauer-DPS je 100 Nutella; Splash/Mehrreihen
ist separat. Intro-Nutzung = in 20 Normal-Läufen des Freischaltlevels.

| Turm | Kosten | DPS | DPS/100 | Nutzen / Intro-Nutzung |
|---|---:|---:|---:|---|
| Möhrenschütze | 100 | 14.29 | 14.29 | Basis; 20/20 |
| Sammler | 50 | — | — | +25/24s, Break-even 48s; 20/20 |
| Dicker Bert | 50 | — | — | 4000 HP/Wall; 20/20 |
| Schnarch-Knolle | 25 | einmalig 1800 | — | 72 Schaden/N, 14s Schärfen; 20/20 |
| Boom-Beere | 150 | einmalig 1800 AoE | — | 12 Schaden/N/Ziel, 1.2s Zünder; 20/20 |
| Eis-Gooby | 175 | 14.29 | 8.16 | 50-%-Slow/3s; **0/20** |
| Doppelmöhre | 200 | 28.57 | 14.29 | gleiche Effizienz, spart Zelle; **0/20** |
| Magnet | 100 | — | — | Rüstungsstrip alle 12s; **0/20** |
| Trampolin | 125 | — | — | 3 Rückwürfe; **0/20, 0 Platzierungen in 900 Matrix-Läufen** |
| Pust | 150 | — | — | Anti-Luft +20-%-Lane-Slow; 20/20 |
| Sternchen | 140 | 10.71/Lane, max 32.14 | 7.65 direkt, 22.96 max | 3 Reihen + Luft; **0/20, 0/900** |
| Melonen-Meier | 300 | 26.67 + Splash | 8.89 direkt | Schild-Bypass; **0/20, 0/900** |
| Goldi (Code) | 75 | — | — | +50/24s, Break-even 36s; absichtlich nicht in Standardläufen |

Kein Turm ist mathematisch grundsätzlich nutzlos: Eis/Stern/Melone kaufen
Utility, Doppel spart Zellen. Aber der Zertifizierungsbot belegt Trampolin,
Sternchen und Melone kampagnenweit nie. Trampolin fehlt vollständig in seiner
normalen Utility-Leiter (`gvz_bot.gd:807-837`); Stern/Melone sind nur eine
späte Schild-Antwort (`gvz_bot.gd:729-746`), nach früher priorisierten
Knollen/Notaktionen (`gvz_bot.gd:67-89`).

## Freischalt-/Einführungscheck

| Level | Neues Element | Bot nutzt im Introlevel (Normal) | Gezeigt/benötigt |
|---:|---|---:|---|
| 1 | Möhre | 20/20 | ja |
| 2 | Sammler | 20/20 | ja |
| 3 | Bert | 20/20 | ja |
| 4 | Knolle | 20/20 | ja |
| 5 | Boom | 20/20 | ja |
| 6 | Nacht | — | funktional: kein Himmelsdrop |
| 7 | Eis | **0/20** | Karte da, nicht nötig |
| 8 | Doppel | **0/20** | Karte da, nicht nötig |
| 9 | Förderband | — | funktional |
| 10 | Magnet | **0/20** | Karte da, nicht nötig |
| 11 | Trampolin + Nebel | **0/20** | Karte unbenutzt; Nebel wegen Key-Mismatch unsichtbar |
| 12 | Pust | 20/20 | nötig gegen Ballons |
| 13 | Stern | **0/20** | Karte da, nicht nötig; Easy trotzdem ungewinnbar |
| 14 | Melone | **0/20** | Karte da, nicht nötig |
| 15 | Boss/Hybrid | — | funktional |

Alle als „neu“ markierten Zombiearten erscheinen im jeweiligen
Einführungslevel. Die Türme werden zwar als normale Karten freigeschaltet,
aber nirgends als „neu“ erklärt oder erzwungen.

## Sterne/Fortschritt und Roundtrip

- Sternkriterium stimmt mit dem Design überein und ist für echte Läufe
  wohldefiniert.
- `record_win()` hält Maximum von Sternen/Score und First-Clear stabil
  (`gvz_progress.gd:96-116`).
- Echter SaveManager-Roundtrip: `saved=true`, `source=save`, `recovered=false`;
  Sterne/Best/Cleared/Goldi semantisch identisch. Nur JSON-Zahltypen wechseln
  `int→float`, alle Leser konvertieren.
- Fehler: All-clear-Levelzahl 14 statt 15 (P1); hostile Slice-Werte werden
  nicht geklemmt (P2).

## Verifikation

- Wegwerf-GDScript: `/tmp/gooby-godot/eval/e11_driver.gd`
  (900 Matrixläufe + Sensitivität + Bossvarianten).
- Pack-/Slice-Test: `/tmp/gooby-godot/eval/e11_contract_driver.gd`;
  Ergebnis `/tmp/gooby-godot/eval/E11-contracts.json`.
- `gdlint` scoped: 0 Probleme; `gdformat --check`: 14 Dateien unverändert.
- Voller Runner: **438 Tests, 0 fehlgeschlagen**.
- Main-Projekt headless gebootet und regulär mit Exit 0 beendet
  (`--quit-after 30`; bekannte Exit-Leak-Warnungen).

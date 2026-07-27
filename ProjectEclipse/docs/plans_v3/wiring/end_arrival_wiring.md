# END-ARRIVAL (F-077) — offene Verdrahtung für den Hauptagenten

Alle Punkte hier sind BEWUSST offen gelassen, weil die Zieldateien in der Parallel-Welle
anderen Agents gehören. Der Code läuft ohne sie vollständig; sie sind Veredelung.

## 1. Altar-Modell `erupt`-Trigger (WIRING(altar-model))

- **Wo:** `sequence/endarrival/EndArrivalSequence.Run.enterPhase`, Zweig `case CHARGE`
  (Kommentar `// WIRING(altar-model): AltarModelTriggers.trigger(level, "erupt")`).
- **Was:** Sobald das GeckoLib-Altar-Modell mit der `erupt`-Animation gemerged ist, den
  Kommentar durch den echten Aufruf ersetzen:
  `AltarModelTriggers.trigger(this.overworld, "erupt");`
  (Fassade: `ritual/AltarModelTriggers.trigger(ServerLevel, String)`, gehört dem
  Altar-Modell-Agent).
- **Timing:** Phase-2-Eintritt = Sequenz-Tick 160 — der Moment, in dem der Altar physisch
  „ausbrechen" soll (Ringe steigen ab hier, die Säule zündet bei Tick 200).

## 2. Lang-Keys

- `docs/plans_v3/langdrop/end_arrival.json` (en+de) in `assets/eclipse/lang/en_us.json`
  und `de_de.json` mergen (Lang-Dateien sind gesperrt). Ohne Merge zeigen Captions und
  Dev-Feedback die rohen Keys — funktional, aber hässlich.

## 3. FxCues-Konsolidierung (optional)

- Die acht Cue-Ids leben in `sequence/endarrival/EndArrivalFxCues` (via `FxCues.cue(…)`),
  weil `network/fx/FxCues.java` gesperrt war. Der Hauptagent KANN sie als
  `FxCues.CUE_END_ARRIVAL_*` einziehen und `EndArrivalFxCues` auf Delegation umstellen
  (Wire-Format identisch — reine Aufräumarbeit, kein Muss).

## 4. Sounds

- KEIN Merge nötig: `docs/plans_v3/wiring/end_arrival_sounds.json` dokumentiert die rein
  aus Bestand/Vanilla komponierte Tonspur (+ eine optionale Upgrade-Idee).

## 5. Handbuch-Doku-Keys

- `dev.eclipse.doc.event.start.endarrival` / `dev.eclipse.doc.event.stop.endarrival`
  stehen im selben Langdrop; die `DevCommandRegistry`-Einträge registriert
  `DevEndArrivalCommands` bereits selbst.

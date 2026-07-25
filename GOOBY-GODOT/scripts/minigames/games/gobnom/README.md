# GOB NOM (Doc G §5 — „Cut the Rope“-Pendant)

Physik-Puzzle: Bonbon hängt an Seilen, Swipe schneidet, Elemente (Blase,
Luftkissen, Ventilator, Schiene, Schießer, Stacheln, Zuckerwatte) lenken es
in Goobys offenen Mund; 3 NUTELLA-Gläser pro Level = Sterne.

## Dateien

| Datei | Rolle |
| --- | --- |
| `gobnom_logic.gd` | PURE Verlet-Sim (60-Hz-Tick, deterministisch, node-frei) |
| `gobnom_data.gd` | Balance-/Level-Lader (ContentRegistry-Namespace `gobnom`) |
| `gobnom_solver.gd` | Auto-Solver: führt `level.solution.actions` aus (Lösbarkeits-Beweis) |
| `gobnom_progress.gd` | GameState-Slice `gobnom` (Kampagne `c<id>` + Coop `n<id>`) |
| `gobnom_art.gd` | Prozeduraler Sticker-Look (kein Textur-Asset) |
| `gobnom_game.gd/.tscn` | View im W2d-Contract, `gobnom_level_select.gd` Level-Wahl |
| `data/gobnom_balance.json` | Physik/Score/Welt (Content-Pack-überschreibbar) |
| `data/gobnom_levels.json` | 15 Kampagnen- + 10 Coop-Level inkl. Lösungs-Plan |

## Coop (M1: lokal/hot-seat)

`split` (`axis` x/y + `at`) teilt den Bildschirm; jede Berührung handelt als
Spieler ihrer Hälfte (Multi-Touch). Aktionen tragen ein `player`-Tag
(`a`/`b`), die Sim verweigert fremde Anker/Hälften (`denied`-Event).

## BACKLOG-Hook: Netz-Coop (M2)

Die Sim ist absichtlich netz-fähig gebaut — der Haken für späteren
Online-Coop, ohne die Logic anzufassen:

- **Deterministischer Lockstep:** fester 60-Hz-Tick, Zufall NUR über
  GoobyRng(seed) → beide Clients simulieren identisch, es müssen nur
  Aktionen ausgetauscht werden (`{tick, do, id, player}` — exakt das Format
  der `solution.actions`, der Solver beweist die Replay-Fähigkeit).
- **Desync-Wächter:** `GobnomLogic.state_hash(state)` alle N Ticks
  vergleichen; bei Abweichung Re-Sync über vollständigen State-Dump
  (`state` ist ein reines Dictionary, `var_to_str`-serialisierbar).
- **Ownership bleibt Server-Wahrheit:** die `player`-Gates der Aktions-API
  laufen in der Sim selbst — ein Remote-Client kann nicht für die falsche
  Seite handeln.
- Transport (W2c-Netz-Stack) und Lobby-Flow sind bewusst NICHT hier
  verdrahtet — Doc G §5.4 stuft Netz-Coop als M2-Backlog ein.

class_name DevZeit
extends RefCounted
## W14/NETSET — Uhr-Offset fürs Dev-Menü (Tab ZEIT), PURE und headless
## testbar. Speist die BESTEHENDE Clock-Injektion des GameState zur
## Laufzeit: `GameState.clock` ist öffentlich und pinnbar (clock.gd —
## Tests nutzen pin/advance seit W1d). Ein Offset > 0 pinnt die Uhr auf
## „Systemzeit + Offset“; damit die gepinnte Uhr weiterläuft, ruft der
## DevService apply_offset() pro Frame erneut (re-pin auf die frische
## Systemzeit). Offset 0 gibt die Uhr an die Echtzeit zurück (unpin).
##
## KEIN Eingriff in game_state.gd/save_manager.gd (TABU) — ausschließlich
## die öffentliche pin/unpin-API der Uhr.

const MS_PER_HOUR := 3_600_000
const MS_PER_DAY := 24 * MS_PER_HOUR


## Offset anwenden. `system_now_ms` ist injizierbar (Tests); -1 = echte
## Systemzeit. Rückgabe: die Zeit, die die Uhr jetzt zeigt (Echtzeit-Basis
## bei Offset <= 0 — dann wird entpinnt).
static func apply_offset(clock: Object, offset_ms: int, system_now_ms := -1) -> int:
	var basis := system_now_ms
	if basis < 0:
		basis = int(Time.get_unix_time_from_system() * 1000.0)
	if clock == null:
		return basis
	if offset_ms <= 0:
		clock.unpin()
		return basis
	clock.pin(basis + offset_ms)
	return basis + offset_ms


## Offset in ganzen Stunden (fürs Slider-Label).
static func offset_stunden(offset_ms: int) -> int:
	return int(offset_ms / float(MS_PER_HOUR))

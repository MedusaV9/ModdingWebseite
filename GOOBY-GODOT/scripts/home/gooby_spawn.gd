extends RefCounted
## Gooby-Spawn-Entscheidung fürs Home (W18/4-B9; CI-Split aus room_base.gd,
## das an der gdlint-1000-Zeilen-Kante steht — Muster wie laden_leben.gd):
## vacation.phase != none heißt „Gooby ist NICHT daheim“ — der Raum spawnt
## dann KEIN Home-Gooby, sondern zeigt den Urlaubs-Hinweis (dieselben
## travel.weg-Strings wie die ReiseApp, Postkarten-Haken). Sonst liefert
## spawn_pos die Spawnposition (Ankunftstür bzw. mittigste freie Zelle,
## unverändert aus room_base._spawn_gooby gehoben).

const Vacation := preload("res://scripts/logic/vacation.gd")


## Ist Gooby laut vacation-Slice verreist (away/returnReady/overdue)?
static func ist_verreist(gs: Object) -> bool:
	return gs != null and gs.has_method("state") and Vacation.is_away(gs.state())


## Hinweistext statt Gooby: „Gooby ist im Urlaub ☀“ + Rest-Schlaf-Zähler
## (falls returnAt bekannt; Uhr aus dem GameState, Fallback Systemzeit).
static func urlaubs_hinweis(gs: Object) -> String:
	var text := I18nService.t("travel.weg.titel")
	var v: Dictionary = Vacation.slice_of(gs.state())
	var return_at := int(v.get("returnAt", 0))
	var jetzt := int(Time.get_unix_time_from_system() * 1000.0)
	if "clock" in gs and gs.clock != null:
		jetzt = int(gs.clock.now_ms())
	if return_at > jetzt:
		var tage := ceili(float(return_at - jetzt) / float(Vacation.MS_PER_DAY))
		text += "\n" + I18nService.t("travel.weg.rest").format({"tage": tage})
	return text


## Spawnposition des Home-Gooby: vor der Ankunftstür (0,7 m einwärts),
## sonst die mittigste freie Grid-Zelle.
static func spawn_pos(
	room_def: Dictionary, room_id: String, door_id: String, grid: GridData
) -> Vector3:
	var door_def := RoomDefs.door(room_id, door_id)
	if not door_def.is_empty():
		var inward := RoomDefs.wall_inward(str(door_def.get("wall", "N")))
		return RoomDefs.door_world_pos(room_def, door_def) + inward * 0.7
	var free := grid.free_cells()
	var center := Vector2i(grid.size.x / 2, grid.size.y / 2)
	var best := center
	if not free.is_empty():
		free.sort_custom(
			func(a: Vector2i, b: Vector2i) -> bool:
				return (a - center).length_squared() < (b - center).length_squared()
		)
		best = free[0]
	return GridData.world_center(best, Vector2i.ONE, 0)

class_name GvzCombat
extends RefCounted
## Turm-Aktionen + Projektil-/Explosions-Logik für GvZ (PURE, Teil der
## GvzLogic-Simulation). Schuss-Kadenz, Produktion, Magnet/Pust-Ticks und
## Boom-Beeren-Zündung laufen hier; Kontakt-Fälle (Knolle/Trampolin) stehen
## in GvzZombies._special_contact. Zahlen: gvz_balance.json.

## Projektil-Arten, die fliegende Zombies treffen können.
const HITS_FLYING := ["star"]
## Reichweiten-Ende (Projektil verlässt das Feld).
const RANGE_END := 9600


## Alle Türme handeln lassen (Produktion, Schüsse, Magnet, Pust, Zündung).
static func act_towers(state: Dictionary) -> void:
	var tick_now := int(state["tick"])
	var towers: Dictionary = state["towers"]
	for key: Variant in towers.keys():
		if not towers.has(key):
			continue
		var tower: Dictionary = towers[key]
		var row: Dictionary = state["balance"]["towers"].get(str(tower["type"]), {})
		if tower.has("fuse_at") and tick_now >= int(tower["fuse_at"]):
			_boom(state, tower, row)
			continue
		if row.has("produce_amount") and tick_now >= int(tower["next_act"]):
			tower["next_act"] = tick_now + int(row.get("produce_interval_ticks", 480))
			GvzLogic._spawn_drop(
				state, int(tower["lane"]), int(tower["col"]), int(row["produce_amount"]), "produce"
			)
			continue
		if row.has("steal_interval_ticks") and tick_now >= int(tower["next_act"]):
			if GvzZombies.magnet_steal(state, tower, int(row.get("range_cols", 4))):
				tower["next_act"] = tick_now + int(row["steal_interval_ticks"])
			continue
		if row.has("gust_interval_ticks") and tick_now >= int(tower["next_act"]):
			if _gust(state, tower):
				tower["next_act"] = tick_now + int(row["gust_interval_ticks"])
			continue
		if row.has("projectile") and tick_now >= int(tower["next_act"]):
			if _fire(state, tower, row):
				tower["next_act"] = tick_now + int(row.get("fire_interval_ticks", 28))


## Projektile bewegen + Treffer auflösen (inkl. Boss-Müllwagen).
static func step_projectiles(state: Dictionary) -> void:
	var projectiles: Array = state["projectiles"]
	var speed := int(state["balance"]["combat"].get("projectile_speed_mm_per_tick", 250))
	for i in range(projectiles.size() - 1, -1, -1):
		var proj: Dictionary = projectiles[i]
		var prev_x := int(proj["x"])
		var new_x := prev_x + speed
		proj["x"] = new_x
		var victim := _first_target(state, proj, prev_x, new_x)
		if not victim.is_empty():
			_resolve_hit(state, proj, victim)
			projectiles.remove_at(i)
			continue
		if _hits_boss(state, proj, new_x):
			GvzZombies.damage_boss(state, int(proj["dmg"]))
			projectiles.remove_at(i)
			continue
		if new_x > RANGE_END:
			projectiles.remove_at(i)


## Explosion um (lane, col) mit Radius in Zellen (0 = nur eigene Zelle).
## Ballons werden ERST heruntergepustet (Platz-Knall) und dann verletzt;
## Grabende bleiben verschont; der Boss wird miterwischt. exclude_id:
## Zombie, der schon direkt getroffen wurde (Knollen-Anbeißer).
static func blast(
	state: Dictionary, lane: int, col: int, radius: int, damage: int, exclude_id := -1
) -> void:
	GvzLogic.push_event(state, "blast", {"lane": lane, "col": col, "radius": radius})
	for zombie: Dictionary in (state["zombies"] as Array).duplicate():
		if zombie["dead"] or zombie["state"] == "dig" or int(zombie["id"]) == exclude_id:
			continue
		if absi(int(zombie["lane"]) - lane) > radius:
			continue
		if absi(GvzLogic.col_of(int(zombie["x"])) - col) > radius:
			continue
		if bool(zombie["flying"]):
			GvzZombies.pop_balloon(state, zombie)
		GvzZombies.damage(state, zombie, damage, "blast")
	var boss: Dictionary = state["boss"]
	if not boss.is_empty() and int(boss["hp"]) > 0:
		if absi(int(boss["lane"]) - lane) <= radius:
			if absi(GvzLogic.col_of(int(boss["x"])) - col) <= radius:
				GvzZombies.damage_boss(state, damage)


static func _boom(state: Dictionary, tower: Dictionary, row: Dictionary) -> void:
	var key := GvzLogic.cell_key(int(tower["lane"]), int(tower["col"]))
	GvzLogic.destroy_tower(state, key, "boom")
	blast(
		state,
		int(tower["lane"]),
		int(tower["col"]),
		int(row.get("radius_cells", 1)),
		int(row.get("damage", 1800))
	)


## Schuss (Möhre/Frost/Stern/Melone). Stern feuert in die eigene UND beide
## Nachbar-Reihen; gefeuert wird nur, wenn ein Ziel existiert (true = Schuss).
static func _fire(state: Dictionary, tower: Dictionary, row: Dictionary) -> bool:
	var kind := str(row.get("projectile", "carrot"))
	var lanes: Array = [int(tower["lane"])]
	if kind == "star":
		for offset: int in [-1, 1]:
			var lane := int(tower["lane"]) + offset
			if (state["lanes"] as Array).has(lane):
				lanes.append(lane)
	var fired := false
	var start_x := int(tower["col"]) * GvzLogic.CELL_MM + 600
	for lane: int in lanes:
		if not _lane_has_target(state, lane, kind, start_x):
			continue
		fired = true
		var volley := int(row.get("volley", 1))
		if kind == "carrot" or kind == "frost":
			# Sticker-Zähler „Möhrenschütze“: jede Möhre zählt — auch die
			# Frost-Möhren des Eis-Goobys und beide einer Doppelmöhren-Salve.
			GvzLogic.bump_stat(state, "moehren_shots", volley)
		for shot in volley:
			(
				(state["projectiles"] as Array)
				. append(
					{
						"id": GvzLogic.next_id(state),
						"lane": lane,
						"x": start_x - shot * 260,
						"kind": kind,
						"dmg": int(row.get("damage", 20)),
						"splash": int(row.get("splash_damage", 0)),
						"slow_ticks": int(row.get("slow_ticks", 0)),
					}
				)
			)
	if fired:
		GvzLogic.push_event(
			state, "shoot", {"lane": tower["lane"], "col": tower["col"], "proj": kind}
		)
	return fired


## Pust-Gooby: nächsten Ballon in der eigenen Reihe herunterholen.
static func _gust(state: Dictionary, tower: Dictionary) -> bool:
	var best: Dictionary = {}
	var best_x := RANGE_END + 1
	for zombie: Dictionary in state["zombies"]:
		if zombie["dead"] or not bool(zombie["flying"]):
			continue
		if int(zombie["lane"]) != int(tower["lane"]):
			continue
		if int(zombie["x"]) < best_x:
			best_x = int(zombie["x"])
			best = zombie
	if best.is_empty():
		return false
	GvzZombies.pop_balloon(state, best)
	return true


## Gibt es in der Reihe ein Ziel, das diese Projektil-Art treffen kann?
static func _lane_has_target(state: Dictionary, lane: int, kind: String, from_x: int) -> bool:
	for zombie: Dictionary in state["zombies"]:
		if _targetable(zombie, kind, lane, from_x):
			return true
	var boss: Dictionary = state["boss"]
	if not boss.is_empty() and int(boss["hp"]) > 0 and int(boss["lane"]) == lane:
		return true
	return false


static func _targetable(zombie: Dictionary, kind: String, lane: int, from_x: int) -> bool:
	if zombie["dead"] or int(zombie["lane"]) != lane or zombie["state"] == "dig":
		return false
	if bool(zombie["flying"]) and not HITS_FLYING.has(kind):
		return false
	return int(zombie["x"]) + 200 >= from_x and int(zombie["x"]) <= RANGE_END


## Erstes Opfer auf dem Flugsegment [prev_x, new_x] (kleinstes x gewinnt).
static func _first_target(
	state: Dictionary, proj: Dictionary, prev_x: int, new_x: int
) -> Dictionary:
	var kind := str(proj["kind"])
	var lane := int(proj["lane"])
	var best: Dictionary = {}
	var best_x := RANGE_END + 1
	for zombie: Dictionary in state["zombies"]:
		if not _targetable(zombie, kind, lane, prev_x - 200):
			continue
		if int(zombie["x"]) - 150 > new_x:
			continue
		if int(zombie["x"]) < best_x:
			best_x = int(zombie["x"])
			best = zombie
	return best


static func _hits_boss(state: Dictionary, proj: Dictionary, new_x: int) -> bool:
	var boss: Dictionary = state["boss"]
	if boss.is_empty() or int(boss["hp"]) <= 0:
		return false
	return int(boss["lane"]) == int(proj["lane"]) and new_x >= int(boss["x"]) - 400


static func _resolve_hit(state: Dictionary, proj: Dictionary, victim: Dictionary) -> void:
	var kind := str(proj["kind"])
	if int(proj.get("slow_ticks", 0)) > 0 and not bool(victim["flying"]):
		GvzZombies.apply_slow(state, victim, int(proj["slow_ticks"]))
	GvzZombies.damage(state, victim, int(proj["dmg"]), kind)
	var splash := int(proj.get("splash", 0))
	if splash <= 0:
		return
	var center_x := int(victim["x"])
	for zombie: Dictionary in (state["zombies"] as Array).duplicate():
		if zombie["dead"] or zombie == victim or zombie["state"] == "dig":
			continue
		if bool(zombie["flying"]) or int(zombie["lane"]) != int(proj["lane"]):
			continue
		if absi(int(zombie["x"]) - center_x) <= GvzLogic.CELL_MM:
			GvzZombies.damage(state, zombie, splash, kind)

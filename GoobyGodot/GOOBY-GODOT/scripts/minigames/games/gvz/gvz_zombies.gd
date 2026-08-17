class_name GvzZombies
extends RefCounted
## Zombie-Verhalten für GvZ (PURE, Teil der GvzLogic-Simulation): Bewegung,
## Fressen, Rüstungen, Spezialfälle (Hüpfer/Maulwurf/Ballon/Brocken/Opa),
## Boss „Zombie-König Knurps“ und die Panik-Goobys (Rasenmäher-Äquivalent).
## Regeln aus Doc G §4.3; alle Zahlen kommen aus gvz_balance.json.

## Rüstungstypen, die der Magnet-Gooby klauen kann (Doc G §4.2).
const MAGNET_STEALABLE := ["eimer", "huetchen", "schild"]


## Zombie erzeugen (auch Boss-Beschwörung/Brocken-Mini nutzen das).
static func spawn(state: Dictionary, type: String, lane: int, x: int) -> Dictionary:
	var row: Dictionary = state["balance"]["zombies"].get(type, {})
	var diff: Dictionary = state["balance"]["difficulty"].get(state["diff"], {})
	var speed_pct := int(row.get("speed_pct", 100)) + int(diff.get("zombie_speed_bonus_pct", 0))
	if bool(state["mods"].get("rain", false)):
		speed_pct += 10
	var hp := GvzLogic._idiv(int(row.get("hp", 200)) * int(diff.get("zombie_hp_pct", 100)), 100)
	var zombie := {
		"id": GvzLogic.next_id(state),
		"type": type,
		"lane": lane,
		"x": x,
		"hp": hp,
		"max_hp": hp,
		"armor_hp": int(row.get("armor_hp", 0)),
		"armor": str(row.get("armor", "")),
		"speed_pct": speed_pct,
		"state": "dig" if bool(row.get("digger", false)) else "walk",
		"dir": -1,
		"jumps": int(row.get("jumps", 0)),
		"flying": bool(row.get("flying", false)),
		"crusher": bool(row.get("crusher", false)),
		"raged": false,
		"threw_mini": false,
		"slow_until": 0,
		"dead": false,
	}
	(state["zombies"] as Array).append(zombie)
	GvzLogic.push_event(state, "spawn", {"id": zombie["id"], "type": type, "lane": lane})
	return zombie


## Bewegung + Fressen + Spezialverhalten aller Zombies eines Ticks.
static func step(state: Dictionary) -> void:
	var lane_slow := _pust_lanes(state)
	for zombie: Dictionary in state["zombies"]:
		if zombie["dead"]:
			continue
		_step_one(state, zombie, lane_slow)
	_flush_dead(state)


## Schaden anwenden (kind: carrot|frost|star|melon|blast|mower).
## Rüstungs-Regeln: Schild blockt gerade Schüsse komplett; Stern/Melone
## umgehen NUR das Schild; Kopf-Rüstungen schlucken immer zuerst.
static func damage(state: Dictionary, zombie: Dictionary, amount: int, kind: String) -> void:
	if zombie["dead"] or amount <= 0:
		return
	var armor := str(zombie["armor"])
	var to_hp := amount
	if int(zombie["armor_hp"]) > 0:
		# Das Frontschild blockt GESCHOSSE (Doc G) — Bogenschüsse (Stern/
		# Melone) und Boden-Explosionen (Knolle/Boom) gehen daran vorbei.
		var bypasses_shield: bool = (
			armor == "schild" and (kind == "star" or kind == "melon" or kind == "blast")
		)
		if kind == "mower":
			zombie["armor_hp"] = 0
		elif not bypasses_shield:
			var absorbed := mini(int(zombie["armor_hp"]), amount)
			zombie["armor_hp"] = int(zombie["armor_hp"]) - absorbed
			to_hp = amount - absorbed
			if armor == "schild":
				to_hp = 0
			if int(zombie["armor_hp"]) <= 0:
				_on_armor_broken(state, zombie)
	if to_hp <= 0:
		GvzLogic.push_event(state, "hit", {"id": zombie["id"], "kind": kind, "armor": true})
		return
	zombie["hp"] = int(zombie["hp"]) - to_hp
	GvzLogic.push_event(state, "hit", {"id": zombie["id"], "kind": kind, "armor": false})
	_maybe_throw_mini(state, zombie)
	if int(zombie["hp"]) <= 0:
		_kill(state, zombie, kind)


## Frost-Treffer: Schaden + Slow (Eis-Gooby).
static func apply_slow(state: Dictionary, zombie: Dictionary, slow_ticks: int) -> void:
	zombie["slow_until"] = int(state["tick"]) + slow_ticks


## Ballon platzen lassen (Pust-Gooby) → normaler Bodenzombie.
static func pop_balloon(state: Dictionary, zombie: Dictionary) -> void:
	if not bool(zombie["flying"]):
		return
	zombie["flying"] = false
	GvzLogic.push_event(state, "pop", {"id": zombie["id"], "lane": zombie["lane"]})


## Magnet-Gooby: Rüstung des nächsten gerüsteten Zombies in Reichweite klauen.
static func magnet_steal(state: Dictionary, tower: Dictionary, range_cols: int) -> bool:
	var center_x := int(tower["col"]) * GvzLogic.CELL_MM + 500
	var best: Dictionary = {}
	var best_dist := range_cols * GvzLogic.CELL_MM + 1
	for zombie: Dictionary in state["zombies"]:
		if zombie["dead"] or int(zombie["armor_hp"]) <= 0:
			continue
		if not MAGNET_STEALABLE.has(str(zombie["armor"])):
			continue
		if absi(int(zombie["lane"]) - int(tower["lane"])) > 1:
			continue
		var dist := absi(int(zombie["x"]) - center_x)
		if dist < best_dist:
			best_dist = dist
			best = zombie
	if best.is_empty():
		return false
	best["armor_hp"] = 0
	_on_armor_broken(state, best)
	GvzLogic.push_event(state, "magnet", {"id": best["id"], "lane": best["lane"]})
	return true


## Boss fährt vor (L15). def kommt aus dem Level-JSON.
static func boss_enter(state: Dictionary, def: Dictionary) -> void:
	var row: Dictionary = state["balance"]["zombies"].get(str(def.get("type", "boss_knurps")), {})
	var diff: Dictionary = state["balance"]["difficulty"].get(state["diff"], {})
	var hp := GvzLogic._idiv(int(row.get("hp", 9000)) * int(diff.get("zombie_hp_pct", 100)), 100)
	var lanes: Array = state["lanes"]
	state["boss"] = {
		"type": str(def.get("type", "boss_knurps")),
		"hp": hp,
		"max_hp": hp,
		"phase": 1,
		"lane": int(lanes[lanes.size() / 2]),
		"x": 8600,
		"next_move": int(state["tick"]) + int(row.get("lane_move_interval_ticks", 90)),
		"next_toss": int(state["tick"]) + int(row.get("toss_interval_ticks", 200)),
		"next_summon": int(state["tick"]) + int(row.get("summon_interval_ticks", 340)),
	}
	GvzLogic.push_event(state, "boss_enter", {"lane": state["boss"]["lane"]})


## Boss-Verhalten: Reihenwechsel, Mülltonnen-Wurf, Wellen-Ruf, Phasen.
static func step_boss(state: Dictionary) -> void:
	var boss: Dictionary = state["boss"]
	if boss.is_empty() or int(boss["hp"]) <= 0 or state["outcome"] != "":
		return
	var row: Dictionary = state["balance"]["zombies"].get(str(boss["type"]), {})
	var tick_now := int(state["tick"])
	_boss_phase_check(state, boss, row)
	var rng: GoobyRng = state["rng"]
	var lanes: Array = state["lanes"]
	if tick_now >= int(boss["next_move"]):
		boss["next_move"] = tick_now + _boss_interval(row, "lane_move_interval_ticks", boss)
		var lane := int(lanes[rng.next_u32() % lanes.size()])
		boss["lane"] = lane
		GvzLogic.push_event(state, "boss_move", {"lane": lane})
	if tick_now >= int(boss["next_toss"]):
		boss["next_toss"] = tick_now + _boss_interval(row, "toss_interval_ticks", boss)
		_boss_toss(state, rng)
	if tick_now >= int(boss["next_summon"]):
		boss["next_summon"] = tick_now + _boss_interval(row, "summon_interval_ticks", boss)
		_boss_summon(state, row, rng, lanes)


## Boss-Schaden (Projektile treffen den Müllwagen in seiner Reihe).
static func damage_boss(state: Dictionary, amount: int) -> void:
	var boss: Dictionary = state["boss"]
	if boss.is_empty() or int(boss["hp"]) <= 0:
		return
	boss["hp"] = maxi(0, int(boss["hp"]) - amount)
	GvzLogic.push_event(state, "boss_hit", {"hp": boss["hp"], "max_hp": boss["max_hp"]})


## Panik-Goobys: Auslösen beim Hausdurchbruch, Fahrt, Niederlage-Check.
## Ballons schweben ÜBER die Walze (Doc G §4.3) — sie lösen nichts aus und
## führen am Haus direkt zur Niederlage.
static func step_mowers(state: Dictionary) -> void:
	if state["outcome"] != "":
		return
	var mowers: Dictionary = state["mowers"]
	var speed := int(state["balance"]["combat"].get("mower_speed_mm_per_tick", 160))
	for zombie: Dictionary in state["zombies"]:
		if zombie["dead"] or int(zombie["x"]) >= 0 or int(zombie["dir"]) > 0:
			continue
		if bool(zombie["flying"]):
			if int(zombie["x"]) < GvzLogic.HOUSE_X:
				state["outcome"] = "lost"
				GvzLogic.push_event(state, "lost", {"lane": zombie["lane"]})
				return
			continue
		var mower: Dictionary = mowers.get(int(zombie["lane"]), {})
		if mower.is_empty():
			continue
		if not bool(mower["used"]):
			mower["used"] = true
			mower["active"] = true
			mower["x"] = -400
			GvzLogic.push_event(state, "mower", {"lane": zombie["lane"]})
		elif not bool(mower["active"]) and int(zombie["x"]) < GvzLogic.HOUSE_X:
			state["outcome"] = "lost"
			GvzLogic.push_event(state, "lost", {"lane": zombie["lane"]})
			return
	for lane: Variant in mowers:
		var mower: Dictionary = mowers[lane]
		if not bool(mower["active"]):
			continue
		mower["x"] = int(mower["x"]) + speed
		for zombie: Dictionary in state["zombies"]:
			if zombie["dead"] or int(zombie["lane"]) != int(lane) or bool(zombie["flying"]):
				continue
			if int(zombie["x"]) <= int(mower["x"]):
				damage(state, zombie, 99999, "mower")
		if int(mower["x"]) > GvzLogic.SPAWN_X:
			mower["active"] = false
	_flush_dead(state)


static func _step_one(state: Dictionary, zombie: Dictionary, lane_slow: Dictionary) -> void:
	var move := _move_mm(state, zombie, lane_slow)
	if zombie["state"] == "dig":
		zombie["x"] = int(zombie["x"]) - move
		if int(zombie["x"]) <= _surface_x(state, zombie):
			zombie["state"] = "walk"
			zombie["dir"] = 1
			GvzLogic.push_event(state, "surface", {"id": zombie["id"], "lane": zombie["lane"]})
		return
	var target := _tower_ahead(state, zombie)
	if target.is_empty():
		zombie["state"] = "walk"
		zombie["x"] = int(zombie["x"]) + int(zombie["dir"]) * move
		if int(zombie["dir"]) > 0 and int(zombie["x"]) > GvzLogic.SPAWN_X:
			zombie["dead"] = true
			GvzLogic.push_event(state, "escape", {"id": zombie["id"]})
		return
	if _special_contact(state, zombie, target):
		return
	zombie["state"] = "eat"
	var bite := int(state["balance"]["combat"].get("bite_damage_per_tick", 5))
	target["hp"] = int(target["hp"]) - bite
	if int(target["hp"]) <= 0:
		GvzLogic.destroy_tower(state, GvzLogic.cell_key(target["lane"], target["col"]), "eaten")


## Kontakt-Spezialfälle: Brocken zerquetscht, Trampolin katapultiert,
## Hüpfer springt (1×), Schnarch-Knolle explodiert. true = kein Fressen.
static func _special_contact(state: Dictionary, zombie: Dictionary, tower: Dictionary) -> bool:
	var key := GvzLogic.cell_key(tower["lane"], tower["col"])
	if tower["type"] == "schnarch_knolle" and int(state["tick"]) >= int(tower.get("armed_at", 0)):
		var dmg := int(state["balance"]["towers"]["schnarch_knolle"].get("damage", 1800))
		GvzLogic.push_event(state, "knolle", {"lane": tower["lane"], "col": tower["col"]})
		GvzLogic.destroy_tower(state, key, "knolle")
		# Der Anbeißer steht mit dem Körper noch in der NACHBAR-Zelle —
		# er kriegt den Schlag direkt, der Zellen-Blast erwischt den Rest.
		GvzCombat.blast(state, int(tower["lane"]), int(tower["col"]), 0, dmg, int(zombie["id"]))
		damage(state, zombie, dmg, "blast")
		return true
	if bool(zombie["crusher"]):
		GvzLogic.push_event(state, "crush", {"lane": tower["lane"], "col": tower["col"]})
		GvzLogic.destroy_tower(state, key, "crushed")
		return true
	if tower["type"] == "trampolin_gooby" and int(tower.get("charges", 0)) > 0:
		tower["charges"] = int(tower["charges"]) - 1
		zombie["x"] = 8600
		zombie["jumps"] = 0
		GvzLogic.push_event(state, "bounce", {"id": zombie["id"], "lane": zombie["lane"]})
		if int(tower["charges"]) <= 0:
			GvzLogic.destroy_tower(state, key, "spent")
		return true
	if int(zombie["jumps"]) > 0 and int(zombie["dir"]) < 0:
		zombie["jumps"] = int(zombie["jumps"]) - 1
		zombie["x"] = int(tower["col"]) * GvzLogic.CELL_MM - 250
		GvzLogic.push_event(state, "jump", {"id": zombie["id"], "lane": zombie["lane"]})
		return true
	return false


## Effektive Bewegung in mm/Tick (Slow-Stack: Frost 50 % + Pust-Aura,
## Untergrenze slow_floor_pct; Ballons ignorieren Frost).
static func _move_mm(state: Dictionary, zombie: Dictionary, lane_slow: Dictionary) -> int:
	var combat: Dictionary = state["balance"]["combat"]
	var pct := 100
	if int(zombie["slow_until"]) > int(state["tick"]) and not bool(zombie["flying"]):
		pct -= 50
	if lane_slow.has(int(zombie["lane"])):
		pct -= int(lane_slow[int(zombie["lane"])])
	pct = maxi(int(combat.get("slow_floor_pct", 20)), pct)
	var speed_pct := int(zombie["speed_pct"])
	if bool(zombie["raged"]):
		var row: Dictionary = state["balance"]["zombies"].get(str(zombie["type"]), {})
		speed_pct = int(row.get("rage_speed_pct", speed_pct))
	var base := int(combat.get("zombie_speed_mm_per_tick", 10))
	return maxi(1, GvzLogic._idiv(base * speed_pct * pct, 10000))


## Turm in der Zelle, in der der Zombie gerade steht (fress-relevant).
## Fliegende und grabende Zombies interessieren sich nicht für Türme.
static func _tower_ahead(state: Dictionary, zombie: Dictionary) -> Dictionary:
	if bool(zombie["flying"]) or zombie["state"] == "dig":
		return {}
	var x := int(zombie["x"])
	if x < 0 or x >= GvzLogic.COLS * GvzLogic.CELL_MM:
		return {}
	var bite_x := x - 250 if int(zombie["dir"]) < 0 else x + 250
	var col := GvzLogic.col_of(clampi(bite_x, 0, GvzLogic.COLS * GvzLogic.CELL_MM - 1))
	return (state["towers"] as Dictionary).get(GvzLogic.cell_key(int(zombie["lane"]), col), {})


## Maulwurf taucht hinter dem hintersten Turm der Reihe auf (mind. Spalte 0).
static func _surface_x(state: Dictionary, zombie: Dictionary) -> int:
	var min_col := GvzLogic.COLS
	for key: Variant in state["towers"]:
		var tower: Dictionary = state["towers"][key]
		if int(tower["lane"]) == int(zombie["lane"]):
			min_col = mini(min_col, int(tower["col"]))
	if min_col >= GvzLogic.COLS:
		return 400
	return maxi(400, min_col * GvzLogic.CELL_MM - 600)


## Reihen mit Pust-Gooby → Slow-Prozent der Aura.
static func _pust_lanes(state: Dictionary) -> Dictionary:
	var out := {}
	var slow := int(state["balance"]["towers"].get("pust_gooby", {}).get("lane_slow_pct", 20))
	for key: Variant in state["towers"]:
		var tower: Dictionary = state["towers"][key]
		if tower["type"] == "pust_gooby":
			out[int(tower["lane"])] = slow
	return out


static func _on_armor_broken(state: Dictionary, zombie: Dictionary) -> void:
	var armor := str(zombie["armor"])
	if armor == "":
		return
	zombie["armor"] = ""
	GvzLogic.push_event(state, "armor_gone", {"id": zombie["id"], "which": armor})
	if str(zombie["type"]) == "zeitungsopa" and not bool(zombie["raged"]):
		zombie["raged"] = true
		GvzLogic.push_event(state, "rage", {"id": zombie["id"], "lane": zombie["lane"]})


## Brocken wirft bei 50 % HP einmalig einen Mini-Schlurfi nach vorn.
static func _maybe_throw_mini(state: Dictionary, zombie: Dictionary) -> void:
	var row: Dictionary = state["balance"]["zombies"].get(str(zombie["type"]), {})
	if not row.has("throw_mini_at_pct") or bool(zombie["threw_mini"]) or zombie["dead"]:
		return
	var threshold := GvzLogic._idiv(int(zombie["max_hp"]) * int(row["throw_mini_at_pct"]), 100)
	if int(zombie["hp"]) > threshold or int(zombie["hp"]) <= 0:
		return
	zombie["threw_mini"] = true
	var mini_x := maxi(500, int(zombie["x"]) - 3000)
	spawn(state, str(row.get("mini_type", "schlurfi")), int(zombie["lane"]), mini_x)
	GvzLogic.push_event(state, "mini_throw", {"lane": zombie["lane"], "x": mini_x})


static func _kill(state: Dictionary, zombie: Dictionary, kind: String) -> void:
	zombie["dead"] = true
	state["kills"] = int(state["kills"]) + 1
	var per_kill := int(state["balance"]["score"].get("kill", 2))
	state["score"] = int(state["score"]) + per_kill
	GvzLogic.push_event(
		state,
		"die",
		{"id": zombie["id"], "type": zombie["type"], "lane": zombie["lane"], "by": kind}
	)


static func _flush_dead(state: Dictionary) -> void:
	var zombies: Array = state["zombies"]
	for i in range(zombies.size() - 1, -1, -1):
		if zombies[i]["dead"]:
			zombies.remove_at(i)


static func _boss_phase_check(state: Dictionary, boss: Dictionary, row: Dictionary) -> void:
	var phases := int(row.get("phases", 3))
	var third := GvzLogic._idiv(int(boss["max_hp"]), phases)
	var phase := phases - GvzLogic._idiv(maxi(0, int(boss["hp"]) - 1), third)
	phase = clampi(phase, 1, phases)
	if phase > int(boss["phase"]):
		boss["phase"] = phase
		GvzLogic.push_event(state, "boss_phase", {"phase": phase})


## Intervalle beschleunigen sich pro Phase (qualmender Müllwagen).
static func _boss_interval(row: Dictionary, key: String, boss: Dictionary) -> int:
	var base := int(row.get(key, 200))
	match int(boss["phase"]):
		2:
			return GvzLogic._idiv(base * int(row.get("phase2_speedup_pct", 75)), 100)
		3:
			return GvzLogic._idiv(base * int(row.get("phase3_speedup_pct", 55)), 100)
		_:
			return base


static func _boss_toss(state: Dictionary, rng: GoobyRng) -> void:
	var keys: Array = (state["towers"] as Dictionary).keys()
	if keys.is_empty():
		return
	var key := int(keys[rng.next_u32() % keys.size()])
	var tower: Dictionary = state["towers"][key]
	GvzLogic.push_event(state, "boss_toss", {"lane": tower["lane"], "col": tower["col"]})
	GvzLogic.destroy_tower(state, key, "muelltonne")


static func _boss_summon(state: Dictionary, row: Dictionary, rng: GoobyRng, lanes: Array) -> void:
	var lo := int(row.get("summon_count_min", 2))
	var hi := int(row.get("summon_count_max", 4))
	var count := lo + int(rng.next_u32() % (hi - lo + 1))
	var pool: Array = row.get("summon_types", ["schlurfi"])
	GvzLogic.push_event(state, "boss_summon", {"count": count})
	for _i in count:
		var type := str(pool[rng.next_u32() % pool.size()])
		var lane := int(lanes[rng.next_u32() % lanes.size()])
		spawn(state, type, lane, GvzLogic.SPAWN_X)

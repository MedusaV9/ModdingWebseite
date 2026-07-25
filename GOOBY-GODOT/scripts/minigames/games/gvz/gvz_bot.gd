class_name GvzBot
extends RefCounted
## Deterministischer Auto-Spieler für GvZ (PURE): sammelt jeden Klecks sofort
## ein und platziert pro Tick höchstens einen Turm nach Heuristik. Zweck:
## Bot-Zertifizierung der Spielbarkeit (Doc G §4.7) + Schwierigkeits-Tests.

## Schützen-Präferenz (erster verfügbarer + bezahlbarer gewinnt).
const SHOOTER_PREF := ["doppelmoehre", "moehrenschuetze"]
## Breite vor Tiefe: billigster zuerst (Erstausstattung der Reihen).
const SHOOTER_PREF_WIDE := ["moehrenschuetze", "doppelmoehre"]
## Zellen-Plan pro Reihe: Spalte 0/1 Wirtschaft, 1..3 Schützen, ab 4 Utility.
const SHOOTER_COLS := [1, 2, 3]
const ECONOMY_COLS := [0, 1]
## Sicherheitslimit der Simulation (12 min Spielzeit).
const MAX_TICKS := 14400


## Kompletten Level-Lauf simulieren. Ergebnis:
## {won, ticks, kills, mowers_used, stars, score, outcome}.
static func simulate(
	level: Dictionary, balance: Dictionary, seed_value: int, difficulty := "normal", opts := {}
) -> Dictionary:
	var state := GvzLogic.new_run(level, balance, difficulty, seed_value, opts)
	while not GvzLogic.is_over(state) and int(state["tick"]) < MAX_TICKS:
		GvzLogic.tick(state)
		act(state)
	var mowers_used := 0
	for lane: Variant in state["mowers"]:
		if bool(state["mowers"][lane]["used"]):
			mowers_used += 1
	return {
		"won": state["outcome"] == "won",
		"outcome": state["outcome"],
		"ticks": int(state["tick"]),
		"kills": int(state["kills"]),
		"score": int(state["score"]),
		"mowers_used": mowers_used,
		"stars": GvzProgress.stars_for(mowers_used) if state["outcome"] == "won" else 0,
	}


## Ein Bot-Zug: alles einsammeln + höchstens EINE Platzierung (Prioritäten-
## Leiter unten; für Not-Antworten wird GESPART statt billig nachgekauft).
static func act(state: Dictionary) -> void:
	_collect_all(state)
	if GvzLogic.is_over(state):
		return
	if not (state["conveyor"] as Dictionary).is_empty():
		if _act_conveyor(state):
			return
		if _conveyor_only(state):
			return
	if _respond_to_deficit(state):
		return
	if _place_collector(state, _base_eco(state)):
		return
	var lane := _threat_lane_wanting(state, 1)
	if lane >= 0:
		if not _try_shooter(state, lane):
			_knolle_stopper(state, lane)
		return
	# Boss-Rennen erst mit Grundwirtschaft + 1 Schütze je bedrohter Reihe.
	if _respond_to_boss(state):
		return
	if _place_magnet(state):
		return
	# Spät-Kampagne: Knollen-Minenfeld gegen Dauerdruck (Cooldown nutzen).
	if int(state["level"].get("id", 1)) >= 10 and int(state["tick"]) >= 1800:
		if _place_knolle_farm(state, 50):
			return
	if _place_collector(state, 4):
		return
	# Breite vor Tiefe: JEDE Reihe kriegt ihren ersten Schützen zuerst.
	lane = _idle_lane_wanting(state)
	if lane >= 0 and int(state["nutella"]) >= 150:
		_try_shooter(state, lane)
		return
	lane = _threat_lane_wanting(state, 2)
	if lane >= 0:
		_try_shooter(state, lane, true)
		return
	if _place_collector(state, _eco_target(state)):
		return
	if _place_knolle_farm(state):
		return
	if _place_lobber(state):
		return
	if _place_utility(state):
		return
	# Idle-Ausbau nur mit Polster: leere Reihen vorsorglich bestücken.
	if int(state["nutella"]) >= 200:
		lane = _idle_lane_wanting(state)
		if lane >= 0:
			_try_shooter(state, lane)
			return
	if int(state["nutella"]) >= 300:
		lane = _threat_lane_wanting(state, 3)
		if lane >= 0:
			_try_shooter(state, lane, true)


static func _collect_all(state: Dictionary) -> void:
	for drop: Dictionary in (state["drops"] as Array).duplicate():
		GvzLogic.collect_drop(state, int(drop["id"]))


static func _conveyor_only(state: Dictionary) -> bool:
	var mods: Dictionary = state["mods"]
	return bool(mods.get("conveyor", false)) and not bool(mods.get("conveyor_hybrid", false))


## Förderband: erstes Band-Item sinnvoll verbauen (true = platziert).
static func _act_conveyor(state: Dictionary) -> bool:
	var queue: Array = state["conveyor"]["queue"]
	if queue.is_empty():
		return false
	var type := str(queue[0])
	var cell := _conveyor_cell_for(state, type)
	if cell.is_empty():
		return false
	return bool(GvzLogic.place_tower(state, type, cell["lane"], cell["col"])["ok"])


static func _conveyor_cell_for(state: Dictionary, type: String) -> Dictionary:
	match type:
		"dicker_bert":
			return _free_cell_in_cols(state, _neediest_lane(state), [5, 6, 4])
		"boom_beere":
			# Not vor Gier: ein tiefer Ballon oder ein unerreichbarer
			# Anroller ist eine SOFORT-Niederlage-Drohung — der Boss nur
			# ein Rennen. Band-Booms löschen die Drohung gratis.
			var air_cell := _balloon_boom_cell(state)
			if not air_cell.is_empty():
				return air_cell
			var ground_cell := _ground_emergency_cell(state)
			if not ground_cell.is_empty():
				return ground_cell
			var boss_cell := _boss_boom_cell(state)
			if not boss_cell.is_empty():
				if _boss_boom_timing_ok(state):
					return boss_cell
				return {}
			var cluster := _best_cluster(state, 2)
			if not cluster.is_empty():
				return cluster
			if (state["conveyor"]["queue"] as Array).size() < int(state["conveyor"]["max_queue"]):
				return {}
			return _free_cell_in_cols(state, _neediest_lane(state), [4, 3, 5])
		"schnarch_knolle":
			return _free_cell_in_cols(state, _neediest_lane(state), [4, 5, 3])
		"pust_gooby":
			var air_lane := _pust_target_lane(state)
			if air_lane < 0:
				air_lane = _neediest_lane(state)
			return _free_cell_in_cols(state, air_lane, [1, 2, 0, 3, 4, 5])
		_:
			var lane := _threat_lane_wanting(state, 3)
			if lane < 0:
				lane = _idle_lane_wanting(state)
			if lane < 0:
				lane = _neediest_lane(state)
			return _free_cell_in_cols(state, lane, [1, 2, 3, 0, 4])


## Not-Reihen-Antwort (anrollende HP > Abschuss-Kapazität): Knolle → Boom →
## Dicker Bert. Greift nicht für den ersten Trickle-Zombie einer leeren
## Reihe (da wird auf einen Schützen gespart). true = SPAREN erlaubt.
static func _respond_to_deficit(state: Dictionary) -> bool:
	if _respond_to_flying(state):
		return true
	if _respond_to_moles(state):
		return true
	for lane: Variant in state["lanes"]:
		var threat := _lane_threat_hp(state, int(lane))
		if threat <= 0:
			continue
		var front := _nearest_zombie_x(state, int(lane))
		if front < 3500 and not _lane_can_hit(state, int(lane), front):
			# Blockade: Zombie steht HINTER allen Schützen (Projektile
			# fliegen nur nach rechts). Boom drauf oder den Panik-Gooby
			# machen lassen — bloß nicht ewig zumauern (Patt = Timeout).
			if _emergency_unblock(state, int(lane), front) != "none":
				return true
			continue
		if threat < 550 and _lane_shooter_count(state, int(lane)) == 0 and front > 5500:
			continue
		if _lane_capacity(state, int(lane), front) * 100 >= threat * 115:
			continue
		if _deficit_action(state, int(lane), front) != "none":
			return true
	return false


## Kann irgendein Schütze diesen Punkt noch treffen? (Projektile starten bei
## col*1000+600, fliegen nach rechts; Sternchen zählen ±1 Reihe.)
static func _lane_can_hit(state: Dictionary, lane: int, x: int) -> bool:
	for key: Variant in state["towers"]:
		var tower: Dictionary = state["towers"][key]
		var row: Dictionary = state["balance"]["towers"].get(str(tower["type"]), {})
		if not row.has("projectile"):
			continue
		var reach := 1 if str(row["projectile"]) == "star" else 0
		if absi(int(tower["lane"]) - lane) > reach:
			continue
		if int(tower["col"]) * GvzLogic.CELL_MM + 400 <= x:
			return true
	return false


## Boss-Knurps: Boom-Beere unter den Müllwagen (Spalte 7/8 seiner Reihe;
## 4 Treffer erledigen 7000 hp), die Schützen chippen nebenbei.
static func _respond_to_boss(state: Dictionary) -> bool:
	if _boss_boom_cell(state).is_empty():
		return false
	if not GvzLogic.available_towers(state).has("boom_beere"):
		return false
	if GvzLogic.cooldown_left(state, "boom_beere") > 0:
		return false
	if not _can_buy(state, "boom_beere"):
		return int(state["nutella"]) >= 100
	if not _boss_boom_timing_ok(state):
		return true
	var cell := _boss_boom_cell(state)
	GvzLogic.place_tower(state, "boom_beere", cell["lane"], cell["col"])
	return true


## Zünd-Timing: direkt nach dem Reihenwechsel legen (sonst verpufft er).
static func _boss_boom_timing_ok(state: Dictionary) -> bool:
	var boss: Dictionary = state["boss"]
	var fuse := int(state["balance"]["towers"]["boom_beere"].get("fuse_ticks", 24))
	return int(boss.get("next_move", 0)) - int(state["tick"]) > fuse + 2


## Freie Boom-Zelle unter dem lebenden Boss ({} = keine). Zellen mit
## Anbeißer scheiden aus (Beschwörungen fressen die Beere vor der Zündung).
static func _boss_boom_cell(state: Dictionary) -> Dictionary:
	var boss: Dictionary = state["boss"]
	if boss.is_empty() or int(boss["hp"]) <= 0:
		return {}
	var col := GvzLogic.col_of(clampi(int(boss["x"]), 0, GvzLogic.COLS * GvzLogic.CELL_MM - 1))
	for c: int in [col - 1, col]:
		if c < 0 or c >= GvzLogic.COLS:
			continue
		if (state["towers"] as Dictionary).has(GvzLogic.cell_key(int(boss["lane"]), c)):
			continue
		if _cell_has_biter(state, int(boss["lane"]), c):
			continue
		return {"lane": int(boss["lane"]), "col": c}
	return {}


## Boden-Zombie nah genug, um die Zelle binnen Zündschnur anzubeißen?
static func _cell_has_biter(state: Dictionary, lane: int, col: int) -> bool:
	var lo := col * GvzLogic.CELL_MM - 300
	var hi := (col + 1) * GvzLogic.CELL_MM + 300
	for zombie: Dictionary in state["zombies"]:
		if zombie["dead"] or int(zombie["lane"]) != lane or bool(zombie["flying"]):
			continue
		if zombie["state"] == "dig":
			continue
		if int(zombie["x"]) >= lo and int(zombie["x"]) <= hi:
			return true
	return false


## Maulwürfe: Gräbern (unverwundbar!) eine Knolle nach hinten legen — die
## erwischt den Rückwärts-Fresser garantiert. Ohne Knolle im Weg: Boom.
static func _respond_to_moles(state: Dictionary) -> bool:
	for zombie: Dictionary in state["zombies"]:
		if zombie["dead"]:
			continue
		if zombie["state"] == "dig":
			if _mole_knolle(state, int(zombie["lane"])) != "none":
				return true
		elif int(zombie["dir"]) > 0 and int(zombie["x"]) < 8200:
			if _mole_boom(state, zombie) != "none":
				return true
	return false


## Knollen-Falle für einen grabenden Maulwurf ("placed"/"save"/"none").
static func _mole_knolle(state: Dictionary, lane: int) -> String:
	if not GvzLogic.available_towers(state).has("schnarch_knolle"):
		return "none"
	for key: Variant in state["towers"]:
		var tower: Dictionary = state["towers"][key]
		if int(tower["lane"]) == lane and str(tower["type"]) == "schnarch_knolle":
			if int(tower["col"]) <= 3:
				return "none"
	var cell := _free_cell_in_cols(state, lane, [0, 1, 2, 3])
	if cell.is_empty() or GvzLogic.cooldown_left(state, "schnarch_knolle") > 0:
		return "none"
	if _can_buy(state, "schnarch_knolle"):
		GvzLogic.place_tower(state, "schnarch_knolle", cell["lane"], cell["col"])
		return "placed"
	return "save"


## Boom auf einen aufgetauchten Maulwurf — außer eine Knolle liegt im Weg.
static func _mole_boom(state: Dictionary, zombie: Dictionary) -> String:
	var lane := int(zombie["lane"])
	var max_x := GvzLogic.COLS * GvzLogic.CELL_MM - 1
	var col := GvzLogic.col_of(clampi(int(zombie["x"]), 0, max_x))
	for key: Variant in state["towers"]:
		var tower: Dictionary = state["towers"][key]
		if int(tower["lane"]) == lane and str(tower["type"]) == "schnarch_knolle":
			if int(tower["col"]) >= col:
				return "none"
	if not GvzLogic.available_towers(state).has("boom_beere"):
		return "none"
	var cell := _free_cell_in_cols(state, lane, [col + 1, col, col - 1])
	if cell.is_empty() or GvzLogic.cooldown_left(state, "boom_beere") > 0:
		return "none"
	if _can_buy(state, "boom_beere"):
		GvzLogic.place_tower(state, "boom_beere", cell["lane"], cell["col"])
		return "placed"
	return "save"


## Reihen-Blockade: Boom auf den unerreichbaren Front-Zombie ("placed"/
## "save") — oder "none": durchlassen, der Panik-Gooby erledigt ihn.
static func _emergency_unblock(state: Dictionary, lane: int, front: int) -> String:
	var mower: Dictionary = (state["mowers"] as Dictionary).get(lane, {})
	if not mower.is_empty() and not bool(mower["used"]):
		return "none"
	if not GvzLogic.available_towers(state).has("boom_beere"):
		return "none"
	var col := GvzLogic.col_of(front)
	var cell := _free_cell_in_cols(state, lane, [col, col + 1, col - 1])
	if cell.is_empty():
		return "none"
	if GvzLogic.cooldown_left(state, "boom_beere") > 0:
		return "save"
	if _can_buy(state, "boom_beere"):
		GvzLogic.place_tower(state, "boom_beere", cell["lane"], cell["col"])
		return "placed"
	return "save"


## Ballons stoppt kein Panik-Gooby — Pust-Gooby ist PFLICHT (dafür wird
## HART gespart), tiefster Ballon zuerst. Pust vor Boom: er poppt aus JEDER
## Zelle, der Not-Knall braucht Zündschnur + die richtige Zelle.
static func _respond_to_flying(state: Dictionary) -> bool:
	for entry: Dictionary in _flying_lanes_by_depth(state):
		var lane := int(entry["lane"])
		if _lane_has_type(state, lane, "pust_gooby"):
			continue
		if _try_pust(state, lane):
			return true
		if int(entry["x"]) < 3500 and _boom_balloon(state, lane, int(entry["x"])):
			return true
		if GvzLogic.available_towers(state).has("pust_gooby"):
			return true
	return false


## Pust kaufen + setzen (true = platziert); volle Reihe wird freigeschaufelt.
static func _try_pust(state: Dictionary, lane: int) -> bool:
	if not GvzLogic.available_towers(state).has("pust_gooby"):
		return false
	if GvzLogic.cooldown_left(state, "pust_gooby") > 0:
		return false
	if not _can_buy(state, "pust_gooby"):
		return false
	var cell := _free_cell_in_cols(state, lane, [2, 1, 3, 0, 4, 5, 6, 7, 8])
	if cell.is_empty():
		cell = _shovel_for_pust(state, lane)
	if cell.is_empty():
		return false
	GvzLogic.place_tower(state, "pust_gooby", cell["lane"], cell["col"])
	return true


## Eine Zelle der vollen Reihe freischaufeln (billigster Nicht-Sammler,
## Schnarch-Knollen bleiben liegen — die sind schon scharf).
static func _shovel_for_pust(state: Dictionary, lane: int) -> Dictionary:
	var best_key := -1
	var best_cost := 99999
	var best_col := -1
	for key: Variant in state["towers"]:
		var tower: Dictionary = state["towers"][key]
		if int(tower["lane"]) != lane:
			continue
		var type := str(tower["type"])
		if type == "schnarch_knolle" or type == "nutella_sammler" or type == "pust_gooby":
			continue
		var cost := int(state["balance"]["towers"].get(type, {}).get("cost", 99999))
		if cost < best_cost:
			best_cost = cost
			best_key = int(key)
			best_col = int(tower["col"])
	if best_key < 0:
		return {}
	GvzLogic.remove_tower(state, lane, best_col)
	return {"lane": lane, "col": best_col}


## Boom-Zelle für den tiefsten Ballon einer Reihe OHNE Pust (der Blast holt
## ihn runter UND tötet ihn). Reihen mit Pust regelt der Windstoß. {} = keiner.
static func _balloon_boom_cell(state: Dictionary) -> Dictionary:
	for entry: Dictionary in _flying_lanes_by_depth(state):
		if _lane_has_type(state, int(entry["lane"]), "pust_gooby"):
			continue
		var col := GvzLogic.col_of(
			clampi(int(entry["x"]) - 260, 0, GvzLogic.COLS * GvzLogic.CELL_MM - 1)
		)
		var cell := _free_cell_in_cols(state, int(entry["lane"]), [col, col - 1, col + 1])
		if not cell.is_empty():
			return cell
	return {}


## Boom-Zelle für einen Anroller HINTER allen Schützen in einer Reihe mit
## verbrauchtem Panik-Gooby (= sonst Niederlage). {} = keiner.
static func _ground_emergency_cell(state: Dictionary) -> Dictionary:
	for lane: Variant in state["lanes"]:
		var mower: Dictionary = (state["mowers"] as Dictionary).get(int(lane), {})
		if mower.is_empty() or not bool(mower["used"]):
			continue
		var front := _nearest_zombie_x(state, int(lane))
		if front >= 3500 or _lane_can_hit(state, int(lane), front):
			continue
		var col := GvzLogic.col_of(maxi(0, front - 260))
		var cell := _free_cell_in_cols(state, int(lane), [col, col - 1, col + 1])
		if not cell.is_empty():
			return cell
	return {}


## Reihe, die als Nächstes Anti-Luft braucht: tiefster Ballon in der Luft,
## sonst die Reihe des nächsten GEPLANTEN Ballon-Spawns (der Spawn-Plan ist
## deterministisch — ein menschlicher Spieler kennt ihn nach einem Versuch
## auch). -1, wenn nirgends ein Pust fehlt.
static func _pust_target_lane(state: Dictionary) -> int:
	for entry: Dictionary in _flying_lanes_by_depth(state):
		if not _lane_has_type(state, int(entry["lane"]), "pust_gooby"):
			return int(entry["lane"])
	var plan: Array = state["spawn_plan"]
	for i in range(int(state["spawn_idx"]), plan.size()):
		var spawn: Dictionary = plan[i]
		if str(spawn["type"]) != "ballon":
			continue
		var lane := int(spawn["lane"])
		if lane >= 0 and not _lane_has_type(state, lane, "pust_gooby"):
			return lane
	return -1


## Reihen mit Ballons, sortiert nach dem tiefsten (kleinstes x zuerst).
static func _flying_lanes_by_depth(state: Dictionary) -> Array:
	var deepest := {}
	for zombie: Dictionary in state["zombies"]:
		if zombie["dead"] or not bool(zombie["flying"]):
			continue
		var lane := int(zombie["lane"])
		if not deepest.has(lane) or int(zombie["x"]) < int(deepest[lane]):
			deepest[lane] = int(zombie["x"])
	var out: Array = []
	for lane: Variant in deepest:
		out.append({"lane": int(lane), "x": int(deepest[lane])})
	out.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a["x"]) < int(b["x"]))
	return out


## Not-Knall gegen einen tief eingedrungenen Ballon (ein frischer Pust käme
## zu spät — der Abgepustete würde direkt vorm Haus landen).
static func _boom_balloon(state: Dictionary, lane: int, x: int) -> bool:
	if not GvzLogic.available_towers(state).has("boom_beere"):
		return false
	if GvzLogic.cooldown_left(state, "boom_beere") > 0:
		return false
	var col := GvzLogic.col_of(maxi(0, x - 260))
	var cell := _free_cell_in_cols(state, lane, [col, col - 1, col + 1])
	if cell.is_empty():
		return false
	if not _can_buy(state, "boom_beere"):
		return true
	GvzLogic.place_tower(state, "boom_beere", cell["lane"], cell["col"])
	return true


## Not-Aktions-Leiter für eine Reihe: "placed", "save" (anwendbar, aber noch
## nicht bezahlbar → sparen) oder "none".
static func _deficit_action(state: Dictionary, lane: int, front: int) -> String:
	# Panzer-Antwort zielt auf den DICKSTEN Anroller der Reihe (der Brocken
	# läuft gern HINTER einem Schlurfi — der Front-Zombie ist nicht der Feind).
	var hv := _heaviest_zombie(state, lane)
	var hv_hp := int(hv["hp"]) + int(hv["armor_hp"]) if not hv.is_empty() else 0
	var heavy := hv_hp >= 550
	var hx := int(hv["x"]) if not hv.is_empty() else 99999
	if heavy and hx >= 3800 and not _knolle_in_window(state, lane, hx):
		var col := clampi(GvzLogic.col_of(mini(hx, 8999)) - 4, 0, GvzLogic.COLS - 1)
		var cell := _free_cell_in_cols(state, lane, [col, col + 1, col - 1])
		if not cell.is_empty() and GvzLogic.available_towers(state).has("schnarch_knolle"):
			if GvzLogic.cooldown_left(state, "schnarch_knolle") == 0:
				if _can_buy(state, "schnarch_knolle"):
					GvzLogic.place_tower(state, "schnarch_knolle", cell["lane"], cell["col"])
					return "placed"
				return "save"
	var cluster := _lane_front_cluster(state, lane, 2)
	var boom_cell: Dictionary = (
		cluster if not cluster.is_empty() else _boom_cell_for_heavy(state, lane, hx, heavy)
	)
	if not _boss_boom_cell(state).is_empty():
		boom_cell = {}  # Booms sind für den Müllwagen reserviert
	if not boom_cell.is_empty() and GvzLogic.available_towers(state).has("boom_beere"):
		if GvzLogic.cooldown_left(state, "boom_beere") == 0:
			if _can_buy(state, "boom_beere"):
				GvzLogic.place_tower(state, "boom_beere", boom_cell["lane"], boom_cell["col"])
				return "placed"
			return "save"
	if front < 4500 and not _lane_has_type(state, lane, "dicker_bert"):
		if _front_is_crusher(state, lane):
			return "none"
		var wall_col := maxi(2, GvzLogic.col_of(front) - 1)
		var cell := _free_cell_in_cols(state, lane, [wall_col, wall_col - 1, wall_col + 1])
		if not cell.is_empty() and GvzLogic.available_towers(state).has("dicker_bert"):
			if GvzLogic.cooldown_left(state, "dicker_bert") == 0:
				if _can_buy(state, "dicker_bert"):
					GvzLogic.place_tower(state, "dicker_bert", cell["lane"], cell["col"])
					return "placed"
				return "save"
	return "none"


## Ist der vorderste Boden-Zombie der Reihe ein Zerquetscher (Brocken)?
## Gegen den ist JEDE Mauer verschwendet (1-Hit-Crush).
static func _front_is_crusher(state: Dictionary, lane: int) -> bool:
	var best_x := 99999
	var crusher := false
	for zombie: Dictionary in state["zombies"]:
		if zombie["dead"] or int(zombie["lane"]) != lane or int(zombie["dir"]) > 0:
			continue
		if bool(zombie["flying"]) or zombie["state"] == "dig":
			continue
		if int(zombie["x"]) < best_x:
			best_x = int(zombie["x"])
			crusher = bool(zombie["crusher"])
	return crusher


## Liegt schon eine Knolle im Anmarsch-Fenster des Front-Zombies?
## (Mole-Fallen bei Spalte 0/1 zählen nicht als Panzer-Abwehr.)
static func _knolle_in_window(state: Dictionary, lane: int, front: int) -> bool:
	var lo := GvzLogic.col_of(front) - 4
	var hi := GvzLogic.col_of(front)
	for key: Variant in state["towers"]:
		var tower: Dictionary = state["towers"][key]
		if int(tower["lane"]) != lane or str(tower["type"]) != "schnarch_knolle":
			continue
		if int(tower["col"]) >= lo and int(tower["col"]) <= hi:
			return true
	return false


## Magnet-Gooby früh gegen Rüstungs-Druck: jede Reihe mit gerüsteten
## Zombies (Eimer/Hütchen/Schild) braucht einen Magneten in Reichweite
## (±1 Reihe) — DER Konter, sobald er freigeschaltet ist.
static func _place_magnet(state: Dictionary) -> bool:
	if not GvzLogic.available_towers(state).has("magnet_gooby"):
		return false
	if _count_type(state, "magnet_gooby") >= 2:
		return false
	for lane: Variant in state["lanes"]:
		if not _lane_has_stealable(state, int(lane)):
			continue
		if _magnet_covers(state, int(lane)):
			continue
		if not _can_buy(state, "magnet_gooby"):
			return false
		var cell := _free_cell_in_cols(state, int(lane), [3, 4, 2])
		if cell.is_empty():
			continue
		return bool(GvzLogic.place_tower(state, "magnet_gooby", cell["lane"], cell["col"])["ok"])
	return false


static func _lane_has_stealable(state: Dictionary, lane: int) -> bool:
	for zombie: Dictionary in state["zombies"]:
		if zombie["dead"] or int(zombie["lane"]) != lane or int(zombie["armor_hp"]) <= 0:
			continue
		if GvzZombies.MAGNET_STEALABLE.has(str(zombie["armor"])):
			return true
	return false


static func _magnet_covers(state: Dictionary, lane: int) -> bool:
	for key: Variant in state["towers"]:
		var tower: Dictionary = state["towers"][key]
		if str(tower["type"]) == "magnet_gooby" and absi(int(tower["lane"]) - lane) <= 1:
			return true
	return false


## Boom-Zelle direkt vor einem dicken Einzelgänger (Eimer/Brocken/…) —
## erst ab Mittelfeld: frisch gespawnte Panzer laufen noch 100+ Ticks durch
## Schützenfeuer, so lange ist der Knall Verschwendung.
static func _boom_cell_for_heavy(
	state: Dictionary, lane: int, front: int, heavy: bool
) -> Dictionary:
	if not heavy or front >= 6000:
		return {}
	var col := GvzLogic.col_of(front)
	return _free_cell_in_cols(state, lane, [col, col - 1, col + 1])


## Dickster anrollender Boden-Zombie der Reihe (leer = keiner).
static func _heaviest_zombie(state: Dictionary, lane: int) -> Dictionary:
	var best := {}
	var best_hp := 0
	for zombie: Dictionary in state["zombies"]:
		if zombie["dead"] or int(zombie["lane"]) != lane or int(zombie["dir"]) > 0:
			continue
		if bool(zombie["flying"]) or zombie["state"] == "dig":
			continue
		var hp := int(zombie["hp"]) + int(zombie["armor_hp"])
		if hp > best_hp:
			best_hp = hp
			best = zombie
	return best


## Anrollende Boden-HP einer Reihe (Ballons zählen nicht — Pust-Sache).
static func _lane_threat_hp(state: Dictionary, lane: int) -> int:
	var total := 0
	for zombie: Dictionary in state["zombies"]:
		if zombie["dead"] or int(zombie["lane"]) != lane or int(zombie["dir"]) > 0:
			continue
		if bool(zombie["flying"]):
			continue
		total += int(zombie["hp"]) + int(zombie["armor_hp"])
	return total


## Grobe Abschuss-Kapazität der Reihe, bis der vorderste Zombie das Haus
## erreicht (Schaden/Tick der Schützen × Restlaufzeit in Ticks).
static func _lane_capacity(state: Dictionary, lane: int, front_x: int) -> int:
	var base_speed := int(state["balance"]["combat"].get("zombie_speed_mm_per_tick", 10))
	var ticks_left := GvzLogic._idiv(maxi(0, front_x), maxi(1, base_speed))
	var dmg_per_100_ticks := 0
	for key: Variant in state["towers"]:
		var tower: Dictionary = state["towers"][key]
		if int(tower["lane"]) != lane:
			continue
		var row: Dictionary = state["balance"]["towers"].get(str(tower["type"]), {})
		if not row.has("projectile"):
			continue
		var interval := maxi(1, int(row.get("fire_interval_ticks", 28)))
		var dmg := int(row.get("damage", 20)) * int(row.get("volley", 1))
		dmg_per_100_ticks += GvzLogic._idiv(dmg * 100, interval)
	return GvzLogic._idiv(dmg_per_100_ticks * ticks_left, 100)


## Vorderstes Grüppchen (>= min_count Zombies in 3 Spalten) der Reihe.
static func _lane_front_cluster(state: Dictionary, lane: int, min_count: int) -> Dictionary:
	var front := _nearest_zombie_x(state, lane)
	if front >= 99999:
		return {}
	var col := GvzLogic.col_of(front)
	var count := 0
	for zombie: Dictionary in state["zombies"]:
		if zombie["dead"] or int(zombie["lane"]) != lane or zombie["state"] == "dig":
			continue
		if absi(GvzLogic.col_of(int(zombie["x"])) - col) <= 1:
			count += 1
	if count < min_count:
		return {}
	return _free_cell_in_cols(state, lane, [col, col + 1, col - 1])


## Grundwirtschaft VOR dem ersten Schützen: nachts mehr (kein Himmel!).
static func _base_eco(state: Dictionary) -> int:
	return 4 if bool(state["mods"].get("night", false)) else 2


## Sammler-Zielzahl nach Level (Nacht-Level leben NUR von Sammlern;
## Spät-Kampagne braucht Wiederaufbau-Reserven).
static func _eco_target(state: Dictionary) -> int:
	var id := int(state["level"].get("id", 1))
	if id <= 2:
		return 2
	if id <= 4:
		return 4
	return 8 if id >= 13 else 6


## Wirtschaft: Nutella-Sammler hinten, sicherste Reihe zuerst (Zombies
## fressen sonst die Sparbüchse).
static func _place_collector(state: Dictionary, target: int) -> bool:
	if not GvzLogic.available_towers(state).has("nutella_sammler"):
		return false
	if _count_type(state, "nutella_sammler") >= target:
		return false
	if not _can_buy(state, "nutella_sammler"):
		return false
	var lanes: Array = (state["lanes"] as Array).duplicate()
	lanes.sort_custom(
		func(a: Variant, b: Variant) -> bool:
			return _nearest_zombie_x(state, int(a)) > _nearest_zombie_x(state, int(b))
	)
	for lane: Variant in lanes:
		if _nearest_zombie_x(state, int(lane)) < 3500:
			continue
		var cell := _free_cell_in_cols(state, int(lane), ECONOMY_COLS)
		if cell.is_empty():
			continue
		return bool(GvzLogic.place_tower(state, "nutella_sammler", cell["lane"], cell["col"])["ok"])
	return false


## Knollen-Farm: billige Schlaf-Minen in die Mitte legen (Spalte 5/6 — weit
## genug vom Spawn, dass sie vor dem ersten Biss scharf sind). Die Knolle
## ist mit 25↦1800 Schaden die effizienteste Panzer-Antwort — der Cooldown
## soll praktisch immer laufen.
static func _place_knolle_farm(state: Dictionary, min_nutella := 75) -> bool:
	if int(state["nutella"]) < min_nutella or not _can_buy(state, "schnarch_knolle"):
		return false
	for lane: Variant in state["lanes"]:
		if _lane_has_type(state, int(lane), "schnarch_knolle"):
			continue
		var cell := _free_cell_in_cols(state, int(lane), [5, 6])
		if cell.is_empty():
			continue
		return bool(GvzLogic.place_tower(state, "schnarch_knolle", cell["lane"], cell["col"])["ok"])
	return false


## Anti-Schild: Türsteher-Reihen brauchen Lobber (Melone) oder Sterne.
static func _place_lobber(state: Dictionary) -> bool:
	for lane: Variant in state["lanes"]:
		if not _lane_has_armor(state, int(lane), "schild"):
			continue
		if _lane_has_type(state, int(lane), "melonen_meier"):
			continue
		if _lane_has_type(state, int(lane), "sternchen_gooby"):
			continue
		for type: String in ["melonen_meier", "sternchen_gooby"]:
			if not _can_buy(state, type):
				continue
			var cell := _free_cell_in_cols(state, int(lane), SHOOTER_COLS)
			if cell.is_empty():
				break
			if bool(GvzLogic.place_tower(state, type, cell["lane"], cell["col"])["ok"]):
				return true
	return false


## Schützen in eine Reihe setzen — false = (noch) nicht leistbar → SPAREN.
## Steht der Zombie schon tief, wird HINTER ihm gebaut (nicht ins Maul).
## dense=false: billigster Schütze (Breite vor Tiefe — lieber 2 Möhren in
## 2 Reihen als 1 Doppelmöhre in einer).
static func _try_shooter(state: Dictionary, lane: int, dense := false) -> bool:
	var type := _affordable_shooter(state, dense)
	if type == "":
		return false
	var cols: Array = SHOOTER_COLS
	var front := _nearest_zombie_x(state, lane)
	if front < 4500:
		var safe := clampi(GvzLogic.col_of(front) - 2, 0, 2)
		cols = [safe, maxi(0, safe - 1), mini(2, safe + 1), 3]
	var cell := _free_cell_in_cols(state, lane, cols)
	if cell.is_empty():
		return false
	return bool(GvzLogic.place_tower(state, type, cell["lane"], cell["col"])["ok"])


## Billiger Trickle-Stopper (25): solange der erste Schütze der Reihe noch
## nicht bezahlbar ist, eine Knolle mit Schärf-Reserve in den Anmarschweg
## legen — sie killt den Vorboten, während weiter gespart wird.
static func _knolle_stopper(state: Dictionary, lane: int) -> bool:
	if not GvzLogic.available_towers(state).has("schnarch_knolle"):
		return false
	if GvzLogic.cooldown_left(state, "schnarch_knolle") > 0:
		return false
	if not _can_buy(state, "schnarch_knolle"):
		return false
	if _lane_has_type(state, lane, "schnarch_knolle"):
		return false
	var front := _nearest_zombie_x(state, lane)
	if front >= 99999:
		return false
	var arm := int(state["balance"]["towers"]["schnarch_knolle"].get("arm_ticks", 280))
	var col := GvzLogic._idiv(
		front - 1250 - (arm + 60) * _lane_max_speed(state, lane), GvzLogic.CELL_MM
	)
	if col < 0:
		return false
	col = mini(col, GvzLogic.COLS - 2)
	var cell := _free_cell_in_cols(state, lane, [col, col - 1, col - 2])
	if cell.is_empty() or int(cell["col"]) > col:
		return false
	return bool(GvzLogic.place_tower(state, "schnarch_knolle", cell["lane"], cell["col"])["ok"])


## Schnellster anrollender Zombie der Reihe in mm/Tick (für Schärf-Reserven).
static func _lane_max_speed(state: Dictionary, lane: int) -> int:
	var base := int(state["balance"]["combat"].get("zombie_speed_mm_per_tick", 10))
	var pct := 100
	for zombie: Dictionary in state["zombies"]:
		if zombie["dead"] or int(zombie["lane"]) != lane or int(zombie["dir"]) > 0:
			continue
		pct = maxi(pct, int(zombie["speed_pct"]))
	return GvzLogic._idiv(base * pct, 100)


## Utility: Pust gegen Ballons, Magnet gegen Rüstungen, Eis als Support.
static func _place_utility(state: Dictionary) -> bool:
	for lane: Variant in state["lanes"]:
		if not _lane_has_flying(state, int(lane)) or _lane_has_type(state, int(lane), "pust_gooby"):
			continue
		if not _can_buy(state, "pust_gooby"):
			break
		var cell := _free_cell_in_cols(state, int(lane), [2, 1, 3])
		if cell.is_empty():
			continue
		if bool(GvzLogic.place_tower(state, "pust_gooby", cell["lane"], cell["col"])["ok"]):
			return true
	if _armored_count(state) >= 2 and _count_type(state, "magnet_gooby") < 1:
		if _can_buy(state, "magnet_gooby"):
			var lanes: Array = state["lanes"]
			var mid := int(lanes[lanes.size() / 2])
			var cell := _free_cell_in_cols(state, mid, [3, 2, 4])
			if not cell.is_empty():
				if bool(
					GvzLogic.place_tower(state, "magnet_gooby", cell["lane"], cell["col"])["ok"]
				):
					return true
	if _can_buy(state, "eis_gooby") and int(state["nutella"]) >= 300:
		var lane := _lane_wanting_type(state, "eis_gooby")
		if lane >= 0:
			var cell := _free_cell_in_cols(state, lane, SHOOTER_COLS)
			if not cell.is_empty():
				return bool(
					GvzLogic.place_tower(state, "eis_gooby", cell["lane"], cell["col"])["ok"]
				)
	return false


## Bester leistbarer Schütze ("" = keiner). dense → Zellen sparen (Doppel);
## sonst budget-adaptiv: knapp bei Kasse = billige Möhre (Breite), mit
## Polster = Doppelmöhre (Tiefe gegen Panzer).
static func _affordable_shooter(state: Dictionary, dense := false) -> String:
	var pref := SHOOTER_PREF if dense or int(state["nutella"]) >= 300 else SHOOTER_PREF_WIDE
	for type: String in pref:
		if _can_buy(state, type):
			return type
	return ""


static func _can_buy(state: Dictionary, type: String) -> bool:
	if not GvzLogic.available_towers(state).has(type):
		return false
	if GvzLogic.cooldown_left(state, type) > 0:
		return false
	return int(state["nutella"]) >= GvzLogic.tower_cost(state, type)


static func _count_type(state: Dictionary, type: String) -> int:
	var count := 0
	for key: Variant in state["towers"]:
		if str(state["towers"][key]["type"]) == type:
			count += 1
	return count


static func _lane_has_type(state: Dictionary, lane: int, type: String) -> bool:
	for key: Variant in state["towers"]:
		var tower: Dictionary = state["towers"][key]
		if int(tower["lane"]) == lane and str(tower["type"]) == type:
			return true
	return false


static func _lane_shooter_count(state: Dictionary, lane: int) -> int:
	var count := 0
	for key: Variant in state["towers"]:
		var tower: Dictionary = state["towers"][key]
		if int(tower["lane"]) != lane:
			continue
		var row: Dictionary = state["balance"]["towers"].get(str(tower["type"]), {})
		if row.has("projectile"):
			count += 1
	return count


static func _lane_has_flying(state: Dictionary, lane: int) -> bool:
	for zombie: Dictionary in state["zombies"]:
		if not zombie["dead"] and int(zombie["lane"]) == lane and bool(zombie["flying"]):
			return true
	return false


static func _armored_count(state: Dictionary) -> int:
	var count := 0
	for zombie: Dictionary in state["zombies"]:
		if not zombie["dead"] and int(zombie["armor_hp"]) > 0:
			count += 1
	return count


static func _nearest_zombie_x(state: Dictionary, lane: int) -> int:
	var best := 99999
	for zombie: Dictionary in state["zombies"]:
		if zombie["dead"] or int(zombie["lane"]) != lane or int(zombie["dir"]) > 0:
			continue
		if zombie["state"] == "dig":
			continue
		best = mini(best, int(zombie["x"]))
	return best


static func _lane_has_armor(state: Dictionary, lane: int, armor: String) -> bool:
	for zombie: Dictionary in state["zombies"]:
		if zombie["dead"] or int(zombie["lane"]) != lane:
			continue
		if str(zombie["armor"]) == armor and int(zombie["armor_hp"]) > 0:
			return true
	return false


## BEDROHTE Reihe (lebender Zombie unterwegs) mit Schützen unter der
## Zieldichte — die mit dem nächsten Zombie zuerst. -1 = keine.
static func _threat_lane_wanting(state: Dictionary, per_lane: int) -> int:
	var best_lane := -1
	var best_x := 99999
	for lane: Variant in state["lanes"]:
		if _lane_shooter_count(state, int(lane)) >= per_lane:
			continue
		if _free_cell_in_cols(state, int(lane), SHOOTER_COLS).is_empty():
			continue
		var x := _nearest_zombie_x(state, int(lane))
		if x < best_x:
			best_x = x
			best_lane = int(lane)
	return best_lane if best_x < 99999 else -1


## Unbedrohte Reihe ganz ohne Schützen (Idle-Vorsorge). -1 = keine.
static func _idle_lane_wanting(state: Dictionary) -> int:
	for lane: Variant in state["lanes"]:
		if _lane_shooter_count(state, int(lane)) > 0:
			continue
		if not _free_cell_in_cols(state, int(lane), SHOOTER_COLS).is_empty():
			return int(lane)
	return -1


static func _lane_wanting_type(state: Dictionary, type: String) -> int:
	for lane: Variant in state["lanes"]:
		if not _lane_has_type(state, int(lane), type):
			if not _free_cell_in_cols(state, int(lane), SHOOTER_COLS).is_empty():
				return int(lane)
	return -1


static func _neediest_lane(state: Dictionary) -> int:
	var best_lane := int((state["lanes"] as Array)[0])
	var best_x := 99999
	for lane: Variant in state["lanes"]:
		var x := _nearest_zombie_x(state, int(lane))
		if x < best_x:
			best_x = x
			best_lane = int(lane)
	return best_lane


static func _free_cell_in_cols(state: Dictionary, lane: int, cols: Array) -> Dictionary:
	for col: Variant in cols:
		var c := clampi(int(col), 0, GvzLogic.COLS - 1)
		if not (state["towers"] as Dictionary).has(GvzLogic.cell_key(lane, c)):
			return {"lane": lane, "col": c}
	return {}


## Bestes 3×3-Fenster mit mindestens min_count Zombies (Zentrum frei).
static func _best_cluster(state: Dictionary, min_count: int) -> Dictionary:
	var best := {}
	var best_count := min_count - 1
	for lane: Variant in state["lanes"]:
		for col in GvzLogic.COLS:
			if (state["towers"] as Dictionary).has(GvzLogic.cell_key(int(lane), col)):
				continue
			var count := 0
			for zombie: Dictionary in state["zombies"]:
				if zombie["dead"] or zombie["state"] == "dig":
					continue
				if absi(int(zombie["lane"]) - int(lane)) > 1:
					continue
				if absi(GvzLogic.col_of(int(zombie["x"])) - col) > 1:
					continue
				count += 1
			if count > best_count:
				best_count = count
				best = {"lane": int(lane), "col": col}
	return best

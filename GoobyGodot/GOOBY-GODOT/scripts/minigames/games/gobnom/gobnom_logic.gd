class_name GobnomLogic
extends RefCounted
## PURE Simulation von GOB NOM (Doc G §5, Cut-the-Rope-Prinzip) — node-frei,
## headless, deterministisch: 60-Hz-Fixed-Tick, Bonbon als Verlet-Punktmasse,
## Seile als EIN-seitige Distanz-Constraints (ziehen nur, drücken nie — Doc G
## §5.1), Zufall ausschließlich über GoobyRng (nur Ventilator-Turbulenz).
## KEINE Godot-Physik-Nodes — reine Vektor-Mathematik auf einem Dictionary-
## State; die Szene (gobnom_game.gd) rendert nur und ruft Aktions-Funktionen.
##
## Koordinaten: Design-Welt 960×540 (Querformat; Hochkant skaliert die VIEW).
## Elemente (Doc G §5.2): Seil-Anker (fix), Schiebe-Anker (Schiene),
## Auto-Seil-Schießer, Luftkissen, Blase, Ventilator, Stachelbrett,
## Zuckerwatte-Wolke, NUTELLA-GLAS (3/Level = Sterne), Gooby-Mund (Ziel).
##
## Coop (Doc G §5.4): split_axis + owner-pro-Anker — cut/tap-Aktionen tragen
## einen player ("a"/"b"); die Sim verweigert fremde Anker/fremde Hälften.
## Solo-Läufe nutzen player "solo" (kein Gate).

## Ticks pro Sekunde des Fixed-Steps (Doc G §5.1: fixer Physik-Tick).
const TPS := 60
## Rand-Toleranz, ab der das Bonbon als "aus dem Bild" gilt.
const OUT_MARGIN := 80.0
## Spieler-Konstanten für die Aktions-Gates.
const PLAYER_SOLO := "solo"
const PLAYER_A := "a"
const PLAYER_B := "b"


## Frischer Lauf aus Level + Balance. Coop wird aus level.kind abgeleitet.
static func new_run(level: Dictionary, balance: Dictionary, seed_value := 1) -> Dictionary:
	var candy: Dictionary = level.get("candy", {"x": 480.0, "y": 140.0})
	var mouth: Dictionary = level.get("mouth", {"x": 480.0, "y": 470.0})
	var pos := Vector2(float(candy.get("x", 480)), float(candy.get("y", 140)))
	var coop := str(level.get("kind", "campaign")) == "coop"
	var state := {
		"tick": 0,
		"rng": GoobyRng.new(seed_value),
		"seed": seed_value,
		"level": level,
		"balance": balance,
		"coop": coop,
		"split": level.get("split", {}) if coop else {},
		"candy": {"pos": pos, "prev": pos},
		"in_bubble": false,
		"bubble_id": -1,
		"ropes": _init_ropes(level),
		"bubbles": _init_list(level, "bubbles", _init_bubble),
		"cushions": _init_list(level, "cushions", _init_cushion),
		"fans": _init_list(level, "fans", _init_fan),
		"shooters": _init_list(level, "shooters", _init_shooter),
		"spikes": (level.get("spikes", []) as Array).duplicate(true),
		"clouds": (level.get("clouds", []) as Array).duplicate(true),
		"jars": _init_list(level, "jars", _init_jar),
		"mouth": {"pos": Vector2(float(mouth.get("x", 480)), float(mouth.get("y", 470)))},
		"cuts_used": 0,
		"max_cuts": int(level.get("max_cuts", -1)),
		"jars_taken": 0,
		"side_changes": 0,
		"last_side": "",
		"outcome": "",
		"events": [],
	}
	if coop:
		state["last_side"] = side_of(state, pos)
	return state


## Ein 60-Hz-Schritt. Mutiert state, liefert die Ereignisse des Ticks
## (kind: cut/denied/jar/nom/fell/spike/pop/catch/puff/shoot/fan/slide/side).
static func step(state: Dictionary) -> Array:
	state["events"] = []
	if state["outcome"] != "":
		return state["events"]
	state["tick"] = int(state["tick"]) + 1
	_integrate(state)
	_apply_rope_constraints(state)
	_shooter_check(state)
	_bubble_check(state)
	_jar_check(state)
	_hazard_check(state)
	_goal_check(state)
	_side_check(state)
	return state["events"]


## ── Aktionen (View/Solver rufen NUR diese) ──────────────────────────────


## Seil per Id schneiden. Liefert {ok, reason}; reason:
## outcome|unknown|already_cut|cut_limit|wrong_side.
static func cut_rope(state: Dictionary, rope_id: int, player := PLAYER_SOLO) -> Dictionary:
	if state["outcome"] != "":
		return {"ok": false, "reason": "outcome"}
	var rope := _rope_by_id(state, rope_id)
	if rope.is_empty():
		return {"ok": false, "reason": "unknown"}
	if bool(rope["cut"]):
		return {"ok": false, "reason": "already_cut"}
	if not _cut_budget_left(state):
		push_event(state, "denied", {"reason": "cut_limit", "player": player})
		return {"ok": false, "reason": "cut_limit"}
	if not _owns(state, player, str(rope.get("owner", "any")), Vector2(rope["anchor"])):
		push_event(state, "denied", {"reason": "wrong_side", "player": player})
		return {"ok": false, "reason": "wrong_side"}
	rope["cut"] = true
	state["cuts_used"] = int(state["cuts_used"]) + 1
	push_event(state, "cut", {"rope": rope_id, "player": player, "at": _rope_midpoint(state, rope)})
	return {"ok": true, "reason": ""}


## Swipe-Schnitt: schneidet ALLE ungeschnittenen Seile, deren Anker→Bonbon-
## Segment das Swipe-Segment kreuzt (mehrere pro Swipe — Original-Gefühl).
## Liefert die Liste der geschnittenen Rope-Ids.
static func cut_segment(
	state: Dictionary, from: Vector2, to: Vector2, player := PLAYER_SOLO
) -> Array:
	var cut_ids: Array = []
	if state["outcome"] != "" or from.is_equal_approx(to):
		return cut_ids
	for rope: Dictionary in state["ropes"]:
		if bool(rope["cut"]):
			continue
		var hit: Variant = Geometry2D.segment_intersects_segment(
			from, to, Vector2(rope["anchor"]), _candy_pos(state)
		)
		if hit == null:
			continue
		if bool(cut_rope(state, int(rope["id"]), player)["ok"]):
			cut_ids.append(int(rope["id"]))
	return cut_ids


## Blase antippen = platzen (hält sie das Bonbon, fällt es wieder frei).
static func pop_bubble(state: Dictionary, bubble_id: int, player := PLAYER_SOLO) -> Dictionary:
	if state["outcome"] != "":
		return {"ok": false, "reason": "outcome"}
	for bubble: Dictionary in state["bubbles"]:
		if int(bubble["id"]) != bubble_id or bool(bubble["popped"]):
			continue
		var at := _candy_pos(state) if bool(bubble["holds"]) else Vector2(bubble["pos"])
		if not _owns(state, player, "any", at):
			push_event(state, "denied", {"reason": "wrong_side", "player": player})
			return {"ok": false, "reason": "wrong_side"}
		bubble["popped"] = true
		if bool(bubble["holds"]):
			bubble["holds"] = false
			state["in_bubble"] = false
			state["bubble_id"] = -1
		push_event(state, "pop", {"bubble": bubble_id, "at": at, "player": player})
		return {"ok": true, "reason": ""}
	return {"ok": false, "reason": "unknown"}


## Luftkissen auslösen: Luftstoß-Impuls, wenn das Bonbon im Luftstrahl liegt.
## Liefert {ok, hit, reason} — Ladungen/Cooldown werden nur bei ok verbraucht.
static func puff_cushion(state: Dictionary, cushion_id: int, player := PLAYER_SOLO) -> Dictionary:
	if state["outcome"] != "":
		return {"ok": false, "hit": false, "reason": "outcome"}
	for cushion: Dictionary in state["cushions"]:
		if int(cushion["id"]) != cushion_id:
			continue
		if not _owns(state, player, str(cushion.get("owner", "any")), Vector2(cushion["pos"])):
			push_event(state, "denied", {"reason": "wrong_side", "player": player})
			return {"ok": false, "hit": false, "reason": "wrong_side"}
		if int(cushion["charges"]) == 0:
			return {"ok": false, "hit": false, "reason": "empty"}
		if int(state["tick"]) < int(cushion["ready_tick"]):
			return {"ok": false, "hit": false, "reason": "cooldown"}
		var cooldown := int(_physics(state).get("cushion_cooldown_ticks", 12))
		cushion["ready_tick"] = int(state["tick"]) + cooldown
		if int(cushion["charges"]) > 0:
			cushion["charges"] = int(cushion["charges"]) - 1
		var hit := _in_beam(
			_candy_pos(state),
			Vector2(cushion["pos"]),
			Vector2(cushion["dir"]),
			float(cushion["range"]),
			float(cushion["half_w"])
		)
		if hit:
			_add_velocity(state, Vector2(cushion["dir"]) * float(cushion["power"]))
		push_event(state, "puff", {"cushion": cushion_id, "hit": hit, "player": player})
		return {"ok": true, "hit": hit, "reason": ""}
	return {"ok": false, "hit": false, "reason": "unknown"}


## Ventilator an/aus schalten (nur schaltbare).
static func toggle_fan(state: Dictionary, fan_id: int, player := PLAYER_SOLO) -> Dictionary:
	if state["outcome"] != "":
		return {"ok": false, "reason": "outcome"}
	for fan: Dictionary in state["fans"]:
		if int(fan["id"]) != fan_id:
			continue
		if not bool(fan["toggleable"]):
			return {"ok": false, "reason": "fixed"}
		if not _owns(state, player, str(fan.get("owner", "any")), Vector2(fan["pos"])):
			push_event(state, "denied", {"reason": "wrong_side", "player": player})
			return {"ok": false, "reason": "wrong_side"}
		fan["on"] = not bool(fan["on"])
		push_event(state, "fan", {"fan": fan_id, "on": bool(fan["on"]), "player": player})
		return {"ok": true, "reason": ""}
	return {"ok": false, "reason": "unknown"}


## Schiebe-Anker entlang seiner Schiene setzen (t in 0..1, wird geklemmt).
static func move_anchor(
	state: Dictionary, rope_id: int, t: float, player := PLAYER_SOLO
) -> Dictionary:
	if state["outcome"] != "":
		return {"ok": false, "reason": "outcome"}
	var rope := _rope_by_id(state, rope_id)
	if rope.is_empty() or not (rope.get("rail") is Dictionary):
		return {"ok": false, "reason": "no_rail"}
	if not _owns(state, player, str(rope.get("owner", "any")), Vector2(rope["anchor"])):
		push_event(state, "denied", {"reason": "wrong_side", "player": player})
		return {"ok": false, "reason": "wrong_side"}
	var rail: Dictionary = rope["rail"]
	rail["t"] = clampf(t, 0.0, 1.0)
	rope["anchor"] = Vector2(rail["from"]).lerp(Vector2(rail["to"]), float(rail["t"]))
	push_event(state, "slide", {"rope": rope_id, "t": float(rail["t"]), "player": player})
	return {"ok": true, "reason": ""}


## ── Abfragen (pure Helfer für View/Solver/Tests) ─────────────────────────


static func is_over(state: Dictionary) -> bool:
	return state["outcome"] != ""


static func candy_pos(state: Dictionary) -> Vector2:
	return _candy_pos(state)


## Geschwindigkeit in Welt-Einheiten pro Sekunde (aus dem Verlet-Paar).
static func candy_velocity(state: Dictionary) -> Vector2:
	var candy: Dictionary = state["candy"]
	return (Vector2(candy["pos"]) - Vector2(candy["prev"])) * float(TPS)


## Bildschirmhälfte eines Punkts im Coop ("a" = links/oben, "b" = rechts/
## unten); ohne Split immer "a".
static func side_of(state: Dictionary, at: Vector2) -> String:
	var split: Dictionary = state["split"]
	if split.is_empty():
		return PLAYER_A
	if str(split.get("axis", "x")) == "y":
		return PLAYER_A if at.y < float(split.get("at", 270.0)) else PLAYER_B
	return PLAYER_A if at.x < float(split.get("at", 480.0)) else PLAYER_B


## Verbleibende Schnitte (-1 = unbegrenzt).
static func cuts_left(state: Dictionary) -> int:
	var max_cuts := int(state["max_cuts"])
	if max_cuts < 0:
		return -1
	return maxi(0, max_cuts - int(state["cuts_used"]))


## Sterne-Rating eines Siegs = eingesammelte Nutella-Gläser (0–3, Doc G §5.2).
static func stars_for(jars_taken: int) -> int:
	return clampi(jars_taken, 0, 3)


## Deterministischer State-Hash für Replay-/Determinismus-Tests (rng/level/
## balance/events ausgenommen — deren Wirkung steckt in den Feldern).
static func state_hash(state: Dictionary) -> int:
	var parts := PackedStringArray()
	for key: String in [
		"tick",
		"candy",
		"in_bubble",
		"bubble_id",
		"ropes",
		"bubbles",
		"cushions",
		"fans",
		"shooters",
		"jars",
		"cuts_used",
		"jars_taken",
		"side_changes",
		"outcome",
	]:
		parts.append(var_to_str(state[key]))
	return hash("\n".join(parts))


## Ereignis an den Tick-Report anhängen.
static func push_event(state: Dictionary, kind: String, data := {}) -> void:
	var event := data.duplicate()
	event["kind"] = kind
	(state["events"] as Array).append(event)


## ── Physik-Kern ──────────────────────────────────────────────────────────


## Verlet-Integration: Gravitation ODER Blasen-Auftrieb, Ventilator-Wind,
## Wolken-Bremse, globale Dämpfung, Anti-Explosions-Schrittdeckel.
static func _integrate(state: Dictionary) -> void:
	var physics := _physics(state)
	var candy: Dictionary = state["candy"]
	var dt := 1.0 / float(TPS)
	var accel := Vector2(0.0, float(physics.get("gravity", 900.0)))
	if bool(state["in_bubble"]):
		accel = Vector2(0.0, -float(physics.get("bubble_lift", 420.0)))
	accel += _fan_force(state)
	var damping := float(physics.get("damping", 0.998))
	if bool(state["in_bubble"]):
		damping = float(physics.get("bubble_damping", 0.96))
	elif _in_cloud(state):
		damping = float(physics.get("cloud_damping", 0.82))
	var vel := (Vector2(candy["pos"]) - Vector2(candy["prev"])) * damping
	vel = vel.limit_length(float(physics.get("max_step", 24.0)))
	candy["prev"] = Vector2(candy["pos"])
	candy["pos"] = Vector2(candy["pos"]) + vel + accel * dt * dt
	if bool(state["in_bubble"]):
		_carry_bubble(state)


## EIN-seitige Distanz-Constraints: Seile ziehen nur (dist > rest), nie
## drücken — mehrere Iterationen für stabile Mehrfach-Aufhängung.
static func _apply_rope_constraints(state: Dictionary) -> void:
	var iterations := int(_physics(state).get("iterations", 3))
	var candy: Dictionary = state["candy"]
	for _i in iterations:
		for rope: Dictionary in state["ropes"]:
			if bool(rope["cut"]):
				continue
			var anchor := Vector2(rope["anchor"])
			var delta := Vector2(candy["pos"]) - anchor
			var dist := delta.length()
			var rest := float(rope["rest"])
			if dist > rest and dist > 0.001:
				candy["pos"] = anchor + delta / dist * rest


## Wind aller aktiven Ventilatoren (Strahl ODER global); Turbulenz moduliert
## deterministisch über GoobyRng (einziger RNG-Verbraucher der Sim).
static func _fan_force(state: Dictionary) -> Vector2:
	var force := Vector2.ZERO
	var pos := _candy_pos(state)
	for fan: Dictionary in state["fans"]:
		if not bool(fan["on"]):
			continue
		var beam_range := float(fan["range"])
		if beam_range > 0.0:
			var in_beam := _in_beam(
				pos, Vector2(fan["pos"]), Vector2(fan["dir"]), beam_range, float(fan["half_w"])
			)
			if not in_beam:
				continue
		var strength := float(fan["force"])
		var turbulence := float(fan.get("turbulence", 0.0))
		if turbulence > 0.0:
			var rng: GoobyRng = state["rng"]
			strength *= 1.0 + turbulence * (rng.next() * 2.0 - 1.0)
		force += Vector2(fan["dir"]) * strength
	return force


## Auto-Seil-Schießer: schießt EINMAL ein neues Seil, sobald das Bonbon im
## Radius ist (rest = Momentan-Distanz × Faktor — fängt den Fall weich).
static func _shooter_check(state: Dictionary) -> void:
	var pos := _candy_pos(state)
	for shooter: Dictionary in state["shooters"]:
		if bool(shooter["fired"]):
			continue
		var dist := pos.distance_to(Vector2(shooter["pos"]))
		if dist > float(shooter["r"]):
			continue
		shooter["fired"] = true
		var rope := {
			"id": int(shooter["rope_id"]),
			"anchor": Vector2(shooter["pos"]),
			"rest": maxf(24.0, dist * float(shooter.get("rest_factor", 1.0))),
			"cut": false,
			"owner": str(shooter.get("owner", "any")),
			"rail": null,
		}
		(state["ropes"] as Array).append(rope)
		push_event(state, "shoot", {"shooter": int(shooter["id"]), "rope": int(rope["id"])})


## Blasen fangen das Bonbon bei Berührung (einmalig pro Blase).
static func _bubble_check(state: Dictionary) -> void:
	if bool(state["in_bubble"]):
		return
	var pos := _candy_pos(state)
	var candy_r := float(_physics(state).get("candy_r", 14.0))
	for bubble: Dictionary in state["bubbles"]:
		if bool(bubble["popped"]) or bool(bubble["holds"]):
			continue
		if pos.distance_to(Vector2(bubble["pos"])) > float(bubble["r"]) + candy_r:
			continue
		bubble["holds"] = true
		state["in_bubble"] = true
		state["bubble_id"] = int(bubble["id"])
		push_event(state, "catch", {"bubble": int(bubble["id"])})
		return


static func _jar_check(state: Dictionary) -> void:
	var pos := _candy_pos(state)
	var candy_r := float(_physics(state).get("candy_r", 14.0))
	var jar_r := float(_physics(state).get("jar_r", 24.0))
	for jar: Dictionary in state["jars"]:
		if bool(jar["taken"]):
			continue
		if pos.distance_to(Vector2(jar["pos"])) > jar_r + candy_r:
			continue
		jar["taken"] = true
		state["jars_taken"] = int(state["jars_taken"]) + 1
		push_event(state, "jar", {"jar": int(jar["id"]), "at": Vector2(jar["pos"])})


## Stachelbretter + Bild-Ränder (unten UND oben — davongeflogene Blase = Fail).
static func _hazard_check(state: Dictionary) -> void:
	if state["outcome"] != "":
		return
	var pos := _candy_pos(state)
	var candy_r := float(_physics(state).get("candy_r", 14.0))
	for spike: Dictionary in state["spikes"]:
		var rect := Rect2(
			float(spike["x"]), float(spike["y"]), float(spike["w"]), float(spike["h"])
		)
		var closest := pos.clamp(rect.position, rect.end)
		if pos.distance_to(closest) <= candy_r:
			state["outcome"] = "lost"
			push_event(state, "spike", {"at": pos})
			return
	var world := _world(state)
	var out_x := pos.x < -OUT_MARGIN or pos.x > float(world.get("w", 960.0)) + OUT_MARGIN
	var out_y := pos.y < -OUT_MARGIN or pos.y > float(world.get("h", 540.0)) + OUT_MARGIN
	if out_x or out_y:
		state["outcome"] = "lost"
		push_event(state, "fell", {"at": pos})


## Gooby-Mund: Bonbon drin → NOM, Level geschafft (Doc G §5.1).
static func _goal_check(state: Dictionary) -> void:
	if state["outcome"] != "":
		return
	var mouth: Dictionary = state["mouth"]
	var mouth_r := float(_physics(state).get("mouth_r", 36.0))
	if _candy_pos(state).distance_to(Vector2(mouth["pos"])) <= mouth_r:
		state["outcome"] = "won"
		push_event(state, "nom", {"jars": int(state["jars_taken"])})


## Seitenwechsel-Zähler für Coop-Level (CN-Regel: Candy MUSS wechseln).
static func _side_check(state: Dictionary) -> void:
	if not bool(state["coop"]):
		return
	var side := side_of(state, _candy_pos(state))
	if side != str(state["last_side"]):
		state["last_side"] = side
		state["side_changes"] = int(state["side_changes"]) + 1
		push_event(state, "side", {"side": side})


## ── Interne Helfer ───────────────────────────────────────────────────────


static func _candy_pos(state: Dictionary) -> Vector2:
	return Vector2((state["candy"] as Dictionary)["pos"])


## Geschwindigkeits-Impuls (Einheiten/s) aufs Verlet-Paar addieren.
static func _add_velocity(state: Dictionary, delta_v: Vector2) -> void:
	var candy: Dictionary = state["candy"]
	candy["prev"] = Vector2(candy["prev"]) - delta_v / float(TPS)


static func _carry_bubble(state: Dictionary) -> void:
	for bubble: Dictionary in state["bubbles"]:
		if int(bubble["id"]) == int(state["bubble_id"]):
			bubble["pos"] = _candy_pos(state)
			return


static func _in_cloud(state: Dictionary) -> bool:
	var pos := _candy_pos(state)
	for cloud: Dictionary in state["clouds"]:
		var rect := Rect2(
			float(cloud["x"]), float(cloud["y"]), float(cloud["w"]), float(cloud["h"])
		)
		if rect.has_point(pos):
			return true
	return false


## Punkt im gerichteten Luftstrahl (Rechteck ab `origin` entlang `dir`)?
static func _in_beam(
	point: Vector2, origin: Vector2, dir: Vector2, beam_range: float, half_w: float
) -> bool:
	var delta := point - origin
	var along := delta.dot(dir)
	var across := absf(delta.cross(dir))
	return along >= -8.0 and along <= beam_range and across <= half_w


## Aktions-Gate: solo darf alles; Coop prüft owner-Tag, sonst die Hälfte
## des Interaktions-Punkts (Doc G §5.4 Input-Gate).
static func _owns(state: Dictionary, player: String, owner_tag: String, at: Vector2) -> bool:
	if not bool(state["coop"]) or player == PLAYER_SOLO:
		return true
	if owner_tag == PLAYER_A or owner_tag == PLAYER_B:
		return owner_tag == player
	return side_of(state, at) == player


static func _cut_budget_left(state: Dictionary) -> bool:
	var max_cuts := int(state["max_cuts"])
	return max_cuts < 0 or int(state["cuts_used"]) < max_cuts


static func _rope_by_id(state: Dictionary, rope_id: int) -> Dictionary:
	for rope: Dictionary in state["ropes"]:
		if int(rope["id"]) == rope_id:
			return rope
	return {}


static func _rope_midpoint(state: Dictionary, rope: Dictionary) -> Vector2:
	return (Vector2(rope["anchor"]) + _candy_pos(state)) * 0.5


static func _physics(state: Dictionary) -> Dictionary:
	return (state["balance"] as Dictionary).get("physics", {})


static func _world(state: Dictionary) -> Dictionary:
	return (state["balance"] as Dictionary).get("world", {})


static func _init_ropes(level: Dictionary) -> Array:
	var ropes: Array = []
	var raw: Array = level.get("ropes", [])
	for i in raw.size():
		var row: Dictionary = raw[i]
		var anchor := Vector2(float(row.get("x", 480)), float(row.get("y", 100)))
		var rail: Variant = null
		if row.get("rail") is Dictionary:
			var rail_def: Dictionary = row["rail"]
			var t := float(rail_def.get("t", 0.0))
			var from := Vector2(
				float(rail_def.get("x1", anchor.x)), float(rail_def.get("y1", anchor.y))
			)
			var to := Vector2(
				float(rail_def.get("x2", anchor.x)), float(rail_def.get("y2", anchor.y))
			)
			rail = {"from": from, "to": to, "t": t}
			anchor = from.lerp(to, t)
		(
			ropes
			. append(
				{
					"id": i,
					"anchor": anchor,
					"rest": float(row.get("rest", 100.0)),
					"cut": false,
					"owner": str(row.get("owner", "any")),
					"rail": rail,
				}
			)
		)
	return ropes


static func _init_list(level: Dictionary, key: String, factory: Callable) -> Array:
	var out: Array = []
	var raw: Array = level.get(key, [])
	for i in raw.size():
		out.append(factory.call(raw[i], i))
	return out


static func _init_bubble(row: Dictionary, index: int) -> Dictionary:
	return {
		"id": index,
		"pos": Vector2(float(row.get("x", 0)), float(row.get("y", 0))),
		"r": float(row.get("r", 26.0)),
		"popped": false,
		"holds": false,
	}


static func _init_cushion(row: Dictionary, index: int) -> Dictionary:
	return {
		"id": index,
		"pos": Vector2(float(row.get("x", 0)), float(row.get("y", 0))),
		"dir": Vector2(float(row.get("dx", 1)), float(row.get("dy", 0))).normalized(),
		"power": float(row.get("power", 420.0)),
		"range": float(row.get("range", 260.0)),
		"half_w": float(row.get("half_w", 60.0)),
		"charges": int(row.get("charges", -1)),
		"ready_tick": 0,
		"owner": str(row.get("owner", "any")),
	}


static func _init_fan(row: Dictionary, index: int) -> Dictionary:
	return {
		"id": index,
		"pos": Vector2(float(row.get("x", 0)), float(row.get("y", 0))),
		"dir": Vector2(float(row.get("dx", 1)), float(row.get("dy", 0))).normalized(),
		"force": float(row.get("force", 260.0)),
		"range": float(row.get("range", 0.0)),
		"half_w": float(row.get("half_w", 80.0)),
		"on": bool(row.get("on", true)),
		"toggleable": bool(row.get("toggleable", false)),
		"turbulence": float(row.get("turbulence", 0.0)),
		"owner": str(row.get("owner", "any")),
	}


static func _init_shooter(row: Dictionary, index: int) -> Dictionary:
	return {
		"id": index,
		"pos": Vector2(float(row.get("x", 0)), float(row.get("y", 0))),
		"r": float(row.get("r", 90.0)),
		"rest_factor": float(row.get("rest_factor", 1.0)),
		"fired": false,
		# Neue Seile bekommen Ids ab 100, damit Level-Seile 0..n stabil bleiben.
		"rope_id": 100 + index,
		"owner": str(row.get("owner", "any")),
	}


static func _init_jar(row: Dictionary, index: int) -> Dictionary:
	return {
		"id": index,
		"pos": Vector2(float(row.get("x", 0)), float(row.get("y", 0))),
		"taken": false,
	}

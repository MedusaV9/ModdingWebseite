class_name SnailMailLogic
extends RefCounted
## Pure Schneckenpost-Logik — zahlengleicher Port von
## GOOBY/src/minigames/games/snailMail.logic.js (PLAN6 Wave C, Agent C2).
## Ein PFAD-MALSPIEL: der Finger zeichnet den Zustellweg vom Briefkasten zum
## leuchtenden Haus, danach kriecht die Postschnecke ihn mit konstanter
## Bogenlängen-Geschwindigkeit ab. Pfützen (2 s Schneckenhaus, kein
## Trocken-Bonus), Blumen unterwegs (+1). Zustellung +4, trocken +2.
## Coin-Zeile /4, 4..25, Ziel 80.
##
## Der Spline-Werkzeugkasten (dist3/catmull_rom/build_track) ist derselbe wie
## in goobyWelt.logic.js — im Web importiert snailMail ihn dort, hier steht er
## (mangels goobyWelt-Port) 1:1 daneben. ALLE Punkte laufen als
## Dictionaries/Arrays mit 64-Bit-Floats: Vector2/Vector3 sind in Godot
## 32-Bit und würden die Bogenlängen gegen das Web verschieben.

## Bindende Vertragszahlen + C2-Tuning (Feld, Kinematik, Takt, Bot).
const SNAIL := {
	"DURATION_SEC": 60.0,
	"FIELD_HALF_W": 2.2,
	"FIELD_Y_MIN": -2.8,
	"FIELD_Y_MAX": 2.8,
	"POST_X": 0.0,
	"POST_Y": -2.35,
	"HOUSE_SLOTS_X": [-1.5, 0.0, 1.5],
	"HOUSE_JITTER_X": 0.22,
	"HOUSE_Y_MIN": 1.75,
	"HOUSE_Y_MAX": 2.4,
	"DOOR_OFFSET_Y": 0.32,
	"SPEED": 2.1,
	"SPEED_EASE_DIST": 0.45,
	"SPEED_MIN_FRAC": 0.4,
	"SNAIL_RADIUS": 0.16,
	"RESAMPLE_STEP": 0.22,
	"MIN_INPUT_SPACING": 0.12,
	"START_RADIUS": 0.8,
	"DELIVER_RADIUS": 0.55,
	"MAX_INPUT_POINTS": 160,
	"PUDDLE_R_MIN": 0.34,
	"PUDDLE_R_MAX": 0.5,
	"PUDDLE_EDGE": 1.0,
	"PUDDLES_START": 2,
	"PUDDLES_MAX": 5,
	"PUDDLE_RAMP_EVERY": 2,
	"PUDDLE_Y_MIN": -1.7,
	"PUDDLE_Y_MAX": 1.15,
	"PUDDLE_GAP": 0.45,
	"PUDDLE_KEEPOUT": 0.85,
	"FLOWERS_PER_ROUND": 3,
	"FLOWER_PICK_RADIUS": 0.42,
	"FLOWER_LANE_OFFSET": 0.9,
	"FLOWER_MIN_SPACING": 0.35,
	"DELIVER_PTS": 4,
	"DRY_BONUS": 2,
	"FLOWER_PTS": 1,
	"RETREAT_SEC": 2.0,
	"ROUND_BEAT_SEC": 0.55,
	"ENDLESS": false,
	"ENDLESS_MAX_SPLASHES": 3,
	"GEN_MAX_TRIES": 40,
	"ROUTE_CLEARANCE": 0.14,
	"ROUTE_DETOUR_PAD": 0.34,
	"ROUTE_MAX_PASSES": 6,
	"ROUTE_SAMPLE_STEP": 0.1,
	"BOT_DRAW_SEC": 1.1,
	"BOT_WET_RATE": 0.08,
	"BOT_TIME_CAP_SEC": 600.0,
}

## §G5.3-Zeilen (Tempo, Dauer, Pfützen-Kulanz, Bot).
const SNAIL_DIFFICULTY := {
	"easy":
	{"speedMult": 0.85, "durationMult": 1.2, "puddleEdge": 0.85, "drawSec": 1.15, "botWet": 0.03},
	"hard":
	{"speedMult": 1.2, "durationMult": 1.0, "puddleEdge": 1.12, "drawSec": 0.95, "botWet": 0.3},
	"endless":
	{"speedMult": 1.2, "durationMult": 1.0, "puddleEdge": 1.12, "drawSec": 0.95, "botWet": 0.3},
}

## goobyWelt WELT.ARC_SAMPLES_PER_SEG — Bogenlängen-Stützstellen je Segment.
const ARC_SAMPLES_PER_SEG := 32


## Abgeleitetes Tune; `normal` liefert exakt die Basis-Tabelle (§G5.3).
static func apply_difficulty(tune := SNAIL, mode := "normal") -> Dictionary:
	if mode == "normal" or not SNAIL_DIFFICULTY.has(mode):
		return tune
	var row: Dictionary = SNAIL_DIFFICULTY[mode]
	var out := tune.duplicate()
	out["DURATION_SEC"] = float(tune["DURATION_SEC"]) * float(row["durationMult"])
	out["SPEED"] = float(tune["SPEED"]) * float(row["speedMult"])
	out["PUDDLE_EDGE"] = float(row["puddleEdge"])
	out["BOT_DRAW_SEC"] = float(row["drawSec"])
	out["BOT_WET_RATE"] = float(row["botWet"])
	out["ENDLESS"] = mode == "endless"
	out["MODE"] = mode
	return out


## Pfützenzahl rampt 2 → 5 mit den zugestellten Runden.
static func puddles_for_round(round_index: int, tune := SNAIL) -> int:
	var extra := int(floor(float(maxi(0, round_index)) / float(tune["PUDDLE_RAMP_EVERY"])))
	return mini(int(tune["PUDDLES_MAX"]), int(tune["PUDDLES_START"]) + extra)


## Zustellpunkt eines Hauses/Baus (die Türschwelle).
static func door_of(house: Dictionary, tune := SNAIL) -> Dictionary:
	return {"x": float(house["x"]), "y": float(house["y"]) - float(tune["DOOR_OFFSET_Y"])}


## Wirksamer Pfützenradius = Sichtradius × Kulanz + Schneckenkörper.
static func puddle_eff_r(puddle: Dictionary, tune := SNAIL) -> float:
	return float(puddle["r"]) * float(tune["PUDDLE_EDGE"]) + float(tune["SNAIL_RADIUS"])


## Index der Pfütze unter dem Punkt, sonst −1 (striktes `<`: Kante ist sicher).
static func puddle_hit_at(x: float, y: float, puddles: Array, tune := SNAIL) -> int:
	for i in puddles.size():
		var p: Dictionary = puddles[i]
		if _hypot(x - float(p["x"]), y - float(p["y"])) < puddle_eff_r(p, tune):
			return i
	return -1


## Ist JEDER Stützpunkt des Pfades pfützenfrei?
static func path_clear(pts: Array, puddles: Array, tune := SNAIL) -> bool:
	for pt: Dictionary in pts:
		if puddle_hit_at(float(pt["x"]), float(pt["y"]), puddles, tune) >= 0:
			return false
	return true


## goobyWelt-Werkzeugkasten: Abstand zweier [x, y, z]-Arrays.
static func dist3(a: Array, b: Array) -> float:
	var dx: float = a[0] - b[0]
	var dy: float = a[1] - b[1]
	var dz: float = a[2] - b[2]
	return sqrt(dx * dx + dy * dy + dz * dz)


## goobyWelt-Werkzeugkasten: uniformer Catmull-Rom-Punkt auf [p1..p2].
static func catmull_rom(p0: Array, p1: Array, p2: Array, p3: Array, u: float) -> Array:
	var u2 := u * u
	var u3 := u2 * u
	var out := [0.0, 0.0, 0.0]
	for i in 3:
		out[i] = (
			0.5
			* (
				2.0 * p1[i]
				+ (-p0[i] + p2[i]) * u
				+ (2.0 * p0[i] - 5.0 * p1[i] + 4.0 * p2[i] - p3[i]) * u2
				+ (-p0[i] + 3.0 * p1[i] - 3.0 * p2[i] + p3[i]) * u3
			)
		)
	return out


## goobyWelt-Werkzeugkasten: bogenlängen-parametrisierte Spur aus Waypoints.
## Endpunkte werden dupliziert, damit die Kurve jeden Punkt trifft.
static func build_track(waypoints: Array) -> Dictionary:
	var n := waypoints.size()
	assert(n >= 2, "[snailMail] Spur braucht >= 2 Waypoints")
	var seg_count := n - 1
	var s_arr: Array[float] = [0.0]
	var pos_arr: Array = [
		catmull_rom(
			_wp(waypoints, -1), _wp(waypoints, 0), _wp(waypoints, 1), _wp(waypoints, 2), 0.0
		)
	]
	var seg_arr: Array[int] = [0]
	var u_arr: Array[float] = [0.0]
	var acc := 0.0
	var prev: Array = pos_arr[0]
	for seg in seg_count:
		for k in range(1, ARC_SAMPLES_PER_SEG + 1):
			var u := float(k) / float(ARC_SAMPLES_PER_SEG)
			var p := catmull_rom(
				_wp(waypoints, seg - 1),
				_wp(waypoints, seg),
				_wp(waypoints, seg + 1),
				_wp(waypoints, seg + 2),
				u
			)
			acc += dist3(prev, p)
			s_arr.append(acc)
			pos_arr.append(p)
			seg_arr.append(seg)
			u_arr.append(u)
			prev = p
	return {
		"length": acc,
		"waypoints": waypoints,
		"s": s_arr,
		"pos": pos_arr,
		"seg": seg_arr,
		"u": u_arr,
	}


## Position auf der Spur bei Bogenlänge s (linear zwischen Tabellenzeilen).
static func track_pos_at(track: Dictionary, s: float) -> Array:
	var s_arr: Array[float] = track["s"]
	var seg_arr: Array[int] = track["seg"]
	var u_arr: Array[float] = track["u"]
	var waypoints: Array = track["waypoints"]
	var c := maxf(0.0, minf(float(track["length"]), s))
	var i := _sample_index(s_arr, c)
	var span := s_arr[i + 1] - s_arr[i]
	var f := (c - s_arr[i]) / span if span > 0.0 else 0.0
	var seg := seg_arr[i]
	var u0 := u_arr[i]
	var u1 := u_arr[i + 1] if seg_arr[i + 1] == seg else 1.0
	var u := u0 + (u1 - u0) * f
	return catmull_rom(
		_wp(waypoints, seg - 1),
		_wp(waypoints, seg),
		_wp(waypoints, seg + 1),
		_wp(waypoints, seg + 2),
		u
	)


## Gezeichneten Strich glätten + bogenlängen-gleichmäßig neu abtasten.
## {} = weniger als 2 unterscheidbare Punkte überleben den Abstandsfilter.
static func smooth_path(raw_pts: Array, tune := SNAIL) -> Dictionary:
	var waypoints: Array = []
	var capped := raw_pts
	if raw_pts.size() > int(tune["MAX_INPUT_POINTS"]):
		capped = raw_pts.slice(0, int(tune["MAX_INPUT_POINTS"]))
	for p: Dictionary in capped:
		var v := [float(p["x"]), float(p["y"]), 0.0]
		if (
			waypoints.is_empty()
			or dist3(waypoints[waypoints.size() - 1], v) >= float(tune["MIN_INPUT_SPACING"])
		):
			waypoints.append(v)
	# Das echte Strichende bleibt IMMER erhalten (Zustell-Prüfung braucht es).
	if capped.size() >= 2:
		var last: Dictionary = capped[capped.size() - 1]
		var tip := [float(last["x"]), float(last["y"]), 0.0]
		var tail: Array = waypoints[waypoints.size() - 1]
		var d := dist3(tail, tip)
		if d > 1e-6:
			if d < float(tune["MIN_INPUT_SPACING"]) and waypoints.size() > 1:
				waypoints[waypoints.size() - 1] = tip
			else:
				waypoints.append(tip)
	if waypoints.size() < 2:
		return {}
	var track := build_track(waypoints)
	var n := maxi(2, int(ceil(float(track["length"]) / float(tune["RESAMPLE_STEP"]))) + 1)
	var pts: Array = []
	var cum: Array[float] = []
	var prev: Array = []
	var acc := 0.0
	for i in n:
		var pos := track_pos_at(track, float(track["length"]) * i / (n - 1))
		if not prev.is_empty():
			acc += dist3(prev, pos)
		pts.append({"x": pos[0], "y": pos[1]})
		cum.append(acc)
		prev = pos
	return {"pts": pts, "cum": cum, "length": acc}


## Schneckentempo bei Bogenposition s (sanfte Rampe an beiden Enden).
static func speed_at(s: float, length: float, tune := SNAIL) -> float:
	var ease := minf(float(tune["SPEED_EASE_DIST"]), length * 0.25)
	var k := 1.0
	if ease > 1e-6:
		var edge := minf(maxf(0.0, s), maxf(0.0, length - s))
		k = clampf(edge / ease, 0.0, 1.0)
	var floor_frac := float(tune["SPEED_MIN_FRAC"])
	return float(tune["SPEED"]) * (floor_frac + (1.0 - floor_frac) * k)


## Bogenposition um dt weiterschieben (am Pfadende geklemmt).
static func advance_arc(s: float, dt: float, length: float, tune := SNAIL) -> float:
	return minf(length, s + speed_at(s, length, tune) * maxf(0.0, dt))


## Pose auf dem Pfad bei Bogenlänge s: {x, y, angle}.
static func follow_at(path: Dictionary, s: float) -> Dictionary:
	var pts: Array = path["pts"]
	var cum: Array[float] = path["cum"]
	var c := clampf(s, 0.0, float(path["length"]))
	var lo := _sample_index_f(cum, c)
	var i := mini(lo, pts.size() - 2)
	var span := cum[i + 1] - cum[i]
	var f := (c - cum[i]) / span if span > 1e-9 else 0.0
	var a: Dictionary = pts[i]
	var b: Dictionary = pts[i + 1]
	var ax := float(a["x"])
	var ay := float(a["y"])
	var bx := float(b["x"])
	var by := float(b["y"])
	return {
		"x": ax + (bx - ax) * f,
		"y": ay + (by - ay) * f,
		"angle": atan2(by - ay, bx - ax),
	}


## Von einem Pfad eingesammelte Blumen (aufsteigende Indizes).
static func flowers_on_path(path: Dictionary, flowers: Array, tune := SNAIL) -> Array:
	var picked: Array[int] = []
	var pts: Array = path["pts"]
	for i in flowers.size():
		var fl: Dictionary = flowers[i]
		for pt: Dictionary in pts:
			if _dist2(pt, fl) <= float(tune["FLOWER_PICK_RADIUS"]):
				picked.append(i)
				break
	return picked


## Beginnt der Strich nah genug am Briefkasten?
static func starts_at_post(pt: Dictionary, tune := SNAIL) -> bool:
	return (
		_dist2(pt, {"x": float(tune["POST_X"]), "y": float(tune["POST_Y"])})
		<= float(tune["START_RADIUS"])
	)


## Haus, dessen Tür das Strich-ENDE erreicht (−1 = mitten im Garten).
static func end_house(path: Dictionary, level: Dictionary, tune := SNAIL) -> int:
	var pts: Array = path["pts"]
	var tip: Dictionary = pts[pts.size() - 1]
	var houses: Array = level["houses"]
	var best := -1
	var best_d := INF
	for i in houses.size():
		var d := _dist2(tip, door_of(houses[i], tune))
		if d <= float(tune["DELIVER_RADIUS"]) and d < best_d:
			best = i
			best_d = d
	return best


## Punkte einer Zustellung (FROZEN: 4 / +2 trocken / +1 je Blume).
static func delivery_points(wet: bool, flowers_picked: int, tune := SNAIL) -> int:
	return (
		int(tune["DELIVER_PTS"])
		+ (0 if wet else int(tune["DRY_BONUS"]))
		+ maxi(0, flowers_picked) * int(tune["FLOWER_PTS"])
	)


static func apply_score(score: int, delta: int) -> int:
	return maxi(0, score + delta)


## §G5.4 Endlos endet bei der dritten nassen Zustellung.
static func endless_should_end(splashes: int, tune := SNAIL) -> bool:
	return bool(tune["ENDLESS"]) and splashes >= int(tune["ENDLESS_MAX_SPLASHES"])


## Referenzroute Briefkasten → Zieltür: Gerade mit Umwegen um Pfützen.
## `ok` garantiert, dass der GEGLÄTTETE Pfad frei ist und die Zieltür trifft —
## also dass eine zeichenbare Zustellung existiert. Auch die Bot-Route.
static func auto_route(level: Dictionary, tune := SNAIL) -> Dictionary:
	var houses: Array = level["houses"]
	var puddles: Array = level["puddles"]
	var post: Dictionary = level["post"]
	var door := door_of(houses[int(level["targetIdx"])], tune)
	var pts: Array = [
		{"x": float(post["x"]), "y": float(post["y"])},
		{"x": float(door["x"]), "y": float(door["y"])},
	]
	var x_lim := float(tune["FIELD_HALF_W"]) - 0.12
	var y_lo := float(tune["FIELD_Y_MIN"]) + 0.12
	var y_hi := float(tune["FIELD_Y_MAX"]) - 0.12
	for _pass in int(tune["ROUTE_MAX_PASSES"]):
		var hit := _first_blocked(pts, puddles, tune)
		if hit.is_empty():
			break
		var p: Dictionary = puddles[int(hit["puddle"])]
		var a: Dictionary = pts[int(hit["seg"])]
		var b: Dictionary = pts[int(hit["seg"]) + 1]
		var abx := float(b["x"]) - float(a["x"])
		var aby := float(b["y"]) - float(a["y"])
		var ab_len2 := abx * abx + aby * aby
		if ab_len2 == 0.0:
			ab_len2 = 1.0
		var t := clampf(
			(
				((float(p["x"]) - float(a["x"])) * abx + (float(p["y"]) - float(a["y"])) * aby)
				/ ab_len2
			),
			0.0,
			1.0
		)
		var cx := float(a["x"]) + abx * t
		var cy := float(a["y"]) + aby * t
		var wx := cx - float(p["x"])
		var wy := cy - float(p["y"])
		var w_len := _hypot(wx, wy)
		if w_len < 1e-6:
			wx = -aby
			wy = abx
			var n_len := _hypot(wx, wy)
			if n_len == 0.0:
				n_len = 1.0
			wx /= n_len
			wy /= n_len
		else:
			wx /= w_len
			wy /= w_len
		var reach := (
			puddle_eff_r(p, tune) + float(tune["ROUTE_CLEARANCE"]) + float(tune["ROUTE_DETOUR_PAD"])
		)
		var dx := clampf(float(p["x"]) + wx * reach, -x_lim, x_lim)
		var dy := clampf(float(p["y"]) + wy * reach, y_lo, y_hi)
		if _hypot(dx - float(p["x"]), dy - float(p["y"])) < reach - 1e-6:
			dx = clampf(float(p["x"]) - wx * reach, -x_lim, x_lim)
			dy = clampf(float(p["y"]) - wy * reach, y_lo, y_hi)
		pts.insert(int(hit["seg"]) + 1, {"x": dx, "y": dy})
	var smooth := smooth_path(pts, tune)
	var ok := (
		not smooth.is_empty()
		and path_clear(smooth["pts"], puddles, tune)
		and end_house(smooth, level, tune) == int(level["targetIdx"])
	)
	return {"ok": ok, "pts": pts, "smooth": smooth}


## Eine Zustellrunde würfeln — IMMER lösbar (autoRoute validiert, Notventil
## nimmt alle GEN_MAX_TRIES Versuche eine Pfütze weg).
static func generate_level(rng: GoobyRng, round_index: int, tune := SNAIL) -> Dictionary:
	var post := {"x": float(tune["POST_X"]), "y": float(tune["POST_Y"])}
	var kinds := ["house", "burrow", "house"]
	var slots: Array = tune["HOUSE_SLOTS_X"]
	var half_w := float(tune["FIELD_HALF_W"])
	var houses: Array = []
	for i in slots.size():
		(
			houses
			. append(
				{
					"x":
					clampf(
						float(slots[i]) + (rng.next() * 2.0 - 1.0) * float(tune["HOUSE_JITTER_X"]),
						-half_w + 0.45,
						half_w - 0.45
					),
					"y":
					(
						float(tune["HOUSE_Y_MIN"])
						+ rng.next() * (float(tune["HOUSE_Y_MAX"]) - float(tune["HOUSE_Y_MIN"]))
					),
					"kind": kinds[i],
				}
			)
		)
	var target_idx := mini(houses.size() - 1, int(floor(rng.next() * houses.size())))
	var door := door_of(houses[target_idx], tune)

	var want_puddles := puddles_for_round(round_index, tune)
	var attempt := 0
	while true:
		if attempt > 0 and attempt % int(tune["GEN_MAX_TRIES"]) == 0 and want_puddles > 0:
			want_puddles -= 1
		attempt += 1
		var puddles := _roll_puddles(rng, want_puddles, houses, post, tune)
		if puddles.is_empty() and want_puddles > 0:
			continue
		var flowers := _roll_flowers(rng, post, door, puddles, tune)
		var level := {
			"post": post,
			"houses": houses,
			"targetIdx": target_idx,
			"puddles": puddles,
			"flowers": flowers,
			"round": round_index,
		}
		if bool(auto_route(level, tune)["ok"]):
			return level
	return {}


## Deterministische Bot-Zertifizierung (§G5.4-Adapter, echte Kinematik).
static func simulate_autoplay(mode := "normal", seed_value := 1) -> Dictionary:
	var tune := apply_difficulty(SNAIL, mode)
	var rng := GoobyRng.new(seed_value)
	var elapsed := 0.0
	var score := 0
	var deliveries := 0
	var splashes := 0
	var flowers_picked := 0
	var limit := (
		float(tune["BOT_TIME_CAP_SEC"]) if bool(tune["ENDLESS"]) else float(tune["DURATION_SEC"])
	)
	while elapsed < limit and not endless_should_end(splashes, tune):
		var level := generate_level(rng, deliveries, tune)
		var path: Dictionary = auto_route(level, tune)["smooth"]
		var length := float(path["length"])
		var s := 0.0
		var travel := 0.0
		while s < length and travel < 60.0:
			s = advance_arc(s, 1.0 / 30.0, length, tune)
			travel += 1.0 / 30.0
		var wet := rng.next() < float(tune["BOT_WET_RATE"])
		var picked := flowers_on_path(path, level["flowers"], tune).size()
		score = apply_score(score, delivery_points(wet, picked, tune))
		deliveries += 1
		flowers_picked += picked
		if wet:
			splashes += 1
		elapsed += (
			float(tune["BOT_DRAW_SEC"])
			+ travel
			+ (float(tune["RETREAT_SEC"]) if wet else 0.0)
			+ float(tune["ROUND_BEAT_SEC"])
		)
	return {
		"seed": seed_value,
		"mode": mode,
		"score": score,
		"deliveries": deliveries,
		"splashes": splashes,
		"flowersPicked": flowers_picked,
		"elapsed": elapsed,
	}


## Pfützen einer Runde würfeln ([] = ein Platz ließ sich nicht finden).
static func _roll_puddles(
	rng: GoobyRng, want: int, houses: Array, post: Dictionary, tune: Dictionary
) -> Array:
	var puddles: Array = []
	var placed := true
	var half_w := float(tune["FIELD_HALF_W"])
	var r_min := float(tune["PUDDLE_R_MIN"])
	var r_span := float(tune["PUDDLE_R_MAX"]) - r_min
	var y_min := float(tune["PUDDLE_Y_MIN"])
	var y_span := float(tune["PUDDLE_Y_MAX"]) - y_min
	var keepout := float(tune["PUDDLE_KEEPOUT"])
	var i := 0
	while i < want and placed:
		placed = false
		for _roll in 20:
			var r := r_min + rng.next() * r_span
			var x := (rng.next() * 2.0 - 1.0) * (half_w - r - 0.15)
			var y := y_min + rng.next() * y_span
			if _hypot(x - float(post["x"]), y - float(post["y"])) < r + keepout:
				continue
			var clear := true
			for h: Dictionary in houses:
				var d := door_of(h, tune)
				if _hypot(x - float(d["x"]), y - float(d["y"])) < r + keepout:
					clear = false
					break
			if not clear:
				continue
			for p: Dictionary in puddles:
				if (
					_hypot(x - float(p["x"]), y - float(p["y"]))
					< r + float(p["r"]) + float(tune["PUDDLE_GAP"])
				):
					clear = false
					break
			if not clear:
				continue
			puddles.append({"x": x, "y": y, "r": r})
			placed = true
			break
		i += 1
	return puddles if placed else []


## Blumen nahe der direkten Briefkasten→Tür-Linie.
static func _roll_flowers(
	rng: GoobyRng, post: Dictionary, door: Dictionary, puddles: Array, tune: Dictionary
) -> Array:
	var flowers: Array = []
	var count := int(tune["FLOWERS_PER_ROUND"])
	var half_w := float(tune["FIELD_HALF_W"])
	var dir_x := float(door["x"]) - float(post["x"])
	var dir_y := float(door["y"]) - float(post["y"])
	var dir_len := _hypot(dir_x, dir_y)
	if dir_len == 0.0:
		dir_len = 1.0
	for i in count:
		var frac := 0.28 + (float(i) / float(maxi(1, count - 1))) * 0.5
		var lx := float(post["x"]) + dir_x * frac
		var ly := float(post["y"]) + dir_y * frac
		for _roll in 10:
			var jitter := (rng.next() * 2.0 - 1.0) * float(tune["FLOWER_LANE_OFFSET"])
			var x := clampf(lx + (-dir_y / dir_len) * jitter, -half_w + 0.2, half_w - 0.2)
			var y := clampf(
				ly + (dir_x / dir_len) * jitter,
				float(tune["FIELD_Y_MIN"]) + 0.3,
				float(tune["FIELD_Y_MAX"]) - 0.6
			)
			if puddle_hit_at(x, y, puddles, tune) >= 0:
				continue
			var spaced := true
			for f: Dictionary in flowers:
				if _hypot(x - float(f["x"]), y - float(f["y"])) < float(tune["FLOWER_MIN_SPACING"]):
					spaced = false
					break
			if not spaced:
				continue
			flowers.append({"x": x, "y": y})
			break
	return flowers


## Erste von einem Polylinien-Segment blockierte Pfütze ({} = frei).
static func _first_blocked(pts: Array, puddles: Array, tune: Dictionary) -> Dictionary:
	for i in pts.size() - 1:
		var a: Dictionary = pts[i]
		var b: Dictionary = pts[i + 1]
		var length := _dist2(a, b)
		var steps := maxi(1, int(ceil(length / float(tune["ROUTE_SAMPLE_STEP"]))))
		for k in steps + 1:
			var x := float(a["x"]) + (float(b["x"]) - float(a["x"])) * k / steps
			var y := float(a["y"]) + (float(b["y"]) - float(a["y"])) * k / steps
			for j in puddles.size():
				var p: Dictionary = puddles[j]
				if (
					_hypot(x - float(p["x"]), y - float(p["y"]))
					< puddle_eff_r(p, tune) + float(tune["ROUTE_CLEARANCE"])
				):
					return {"seg": i, "puddle": j}
	return {}


static func _wp(pts: Array, i: int) -> Array:
	return pts[maxi(0, mini(pts.size() - 1, i))]


static func _sample_index(s_arr: Array[float], s: float) -> int:
	var lo := 0
	var hi := s_arr.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if s_arr[mid] <= s:
			lo = mid
		else:
			hi = mid - 1
	return mini(lo, s_arr.size() - 2)


static func _sample_index_f(cum: Array[float], s: float) -> int:
	var lo := 0
	var hi := cum.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid - 1
	return lo


static func _dist2(a: Dictionary, b: Dictionary) -> float:
	return _hypot(float(a["x"]) - float(b["x"]), float(a["y"]) - float(b["y"]))


static func _hypot(dx: float, dy: float) -> float:
	return sqrt(dx * dx + dy * dy)

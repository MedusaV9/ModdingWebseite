class_name VeggieChopLogic
extends RefCounted
## Gemüse-Schnippler (veggieChop) — PURE Logik, zahlengleicher Port von
## GOOBY/src/minigames/games/veggieChop.logic.js (PLAN2 §C1.2 #4). Gemüse
## fliegt in Bögen hoch (1–3 gleichzeitig, rampend), Wisch-Schnitt +2 (+1 je
## weiterem Stück im selben Wisch), Müll (Dose/Stiefel) −3 + 0,5 s Stun,
## drei verpasste Gemüse beenden die Runde früh, ≤ 60 s. Alle 25 s Frenzy mit
## exakt 8 Gemüse und ohne Müll. Coin-Zeile: /5, 4..26, Ziel 105.

## Bindende §C1.2-#4-Zahlen + G27-Tuning (Bogenphysik, Kadenz, Bot).
const CHOP := {
	"DURATION_SEC": 60.0,
	"CHOP_PTS": 2,
	"COMBO_BONUS": 1,
	"JUNK_PTS": -3,
	"STUN_SEC": 0.5,
	"MAX_MISSES": 3,
	"WAVE2_FROM_SEC": 20.0,
	"WAVE3_FROM_SEC": 40.0,
	"SPAWN_START_SEC": 2.3,
	"SPAWN_END_SEC": 1.7,
	"JUNK_CHANCE_START": 0.1,
	"JUNK_CHANCE_END": 0.22,
	"GRAVITY": 9.5,
	"APEX_MIN_Y": -0.4,
	"APEX_MAX_Y": 2.3,
	"HIT_RADIUS": 0.42,
	"AUTOPLAY_CHOP_RATE": 0.965,
	"AUTOPLAY_AIM_ERR": 0.14,
	"FRENZY_EVERY_SEC": 25.0,
	"FRENZY_DURATION_SEC": 3.0,
	"FRENZY_ITEMS": 8,
	"ENDLESS": false,
	"ENDLESS_JUNK_HITS": 3,
	"SPEED_MULT": 1.0,
	"SCORE_MULT": 1.0,
	"ENDLESS_BOT_JUNK_RATE": 0.55,
}

## V4/G73 Timed-Arena-Zeilen (§G5.3).
const CHOP_DIFFICULTY := {
	"easy": {"spawnMult": 1.2, "windowMult": 1.25, "durationMult": 1.2, "botRate": 0.99},
	"hard": {"spawnMult": 0.85, "windowMult": 0.8, "durationMult": 1.0, "botRate": 0.81},
	"endless": {"spawnMult": 0.85, "windowMult": 0.8, "durationMult": 1.0, "botRate": 0.81},
}

## Die 8 Ganz+Halb-Paare des Food-Kits; `juice` färbt den Spritzer.
const VEGGIES: Array[Dictionary] = [
	{"key": "apple", "half": "apple-half", "juice": "E85D4A"},
	{"key": "pear", "half": "pear-half", "juice": "B3D06B"},
	{"key": "lemon", "half": "lemon-half", "juice": "FFE066"},
	{"key": "onion", "half": "onion-half", "juice": "F2E8DA"},
	{"key": "mushroom", "half": "mushroom-half", "juice": "E8D9C5"},
	{"key": "paprika", "half": "paprika-slice", "juice": "FF8552"},
	{"key": "tomato", "half": "tomato-slice", "juice": "E8523F"},
	{"key": "coconut", "half": "coconut-half", "juice": "FFFFFF"},
]

## Müll (§C1.2: Limodose + Stiefel).
const JUNK_ITEMS: Array[String] = ["soda", "boot"]


## Abgeleitetes Tune; `normal` liefert exakt die Mittel-Tabelle.
static func apply_difficulty(tune: Dictionary = CHOP, mode := "normal") -> Dictionary:
	if mode == "normal" or not CHOP_DIFFICULTY.has(mode):
		return tune
	var row: Dictionary = CHOP_DIFFICULTY[mode]
	var out := tune.duplicate()
	out["DURATION_SEC"] = float(tune["DURATION_SEC"]) * float(row["durationMult"])
	out["SPAWN_START_SEC"] = float(tune["SPAWN_START_SEC"]) * float(row["spawnMult"])
	out["SPAWN_END_SEC"] = float(tune["SPAWN_END_SEC"]) * float(row["spawnMult"])
	out["HIT_RADIUS"] = maxf(
		float(tune["HIT_RADIUS"]) * 0.55, float(tune["HIT_RADIUS"]) * float(row["windowMult"])
	)
	out["AUTOPLAY_CHOP_RATE"] = float(row["botRate"])
	out["ENDLESS"] = mode == "endless"
	out["ENDLESS_SPAWN_FLOOR_SEC"] = 0.8
	return out


## Turbo-Payload der Szene anwenden (§E0.1-3).
static func apply_turbo(tune: Dictionary, speed_mult := 1.0, score_mult := 1.0) -> Dictionary:
	var out := tune.duplicate()
	out["SPEED_MULT"] = maxf(1.0, speed_mult)
	out["SCORE_MULT"] = maxf(1.0, score_mult)
	return out


## Größte Wellengröße zum Rundenzeitpunkt (1–3, rampend).
static func max_wave_size_at(elapsed: float) -> int:
	if elapsed >= float(CHOP["WAVE3_FROM_SEC"]):
		return 3
	if elapsed >= float(CHOP["WAVE2_FROM_SEC"]):
		return 2
	return 1


## Wellengröße würfeln: 1 … max_wave_size_at(elapsed), gleichverteilt.
static func wave_size_at(rng: GoobyRng, elapsed: float) -> int:
	return 1 + int(floor(rng.next() * float(max_wave_size_at(elapsed))))


## Sekunden bis zur nächsten Welle (Kadenz zieht an, im Endlos mit Boden).
static func spawn_interval_at(elapsed: float, duration := 60.0, tune: Dictionary = CHOP) -> float:
	var t := (
		maxf(0.0, elapsed / duration)
		if bool(tune["ENDLESS"])
		else minf(1.0, maxf(0.0, elapsed / duration))
	)
	var start := float(tune["SPAWN_START_SEC"])
	var value := start + (float(tune["SPAWN_END_SEC"]) - start) * t
	return maxf(float(tune.get("ENDLESS_SPAWN_FLOOR_SEC", tune["SPAWN_END_SEC"])), value)


## Müll-Wahrscheinlichkeit zum Rundenzeitpunkt (lineare Rampe).
static func junk_chance_at(elapsed: float, duration := 60.0, tune: Dictionary = CHOP) -> float:
	var t := minf(1.0, maxf(0.0, elapsed / duration))
	var start := float(tune["JUNK_CHANCE_START"])
	return start + (float(tune["JUNK_CHANCE_END"]) - start) * t


## Ein geworfenes Objekt würfeln: Müll nach junk_chance_at, sonst Gemüse.
static func roll_item(rng: GoobyRng, elapsed: float, tune: Dictionary = CHOP) -> Dictionary:
	if rng.next() < junk_chance_at(elapsed, float(tune["DURATION_SEC"]), tune):
		var idx := mini(JUNK_ITEMS.size() - 1, int(floor(rng.next() * float(JUNK_ITEMS.size()))))
		return {"kind": "junk", "key": JUNK_ITEMS[idx], "half": "", "juice": "BFC4CC"}
	return roll_veggie(rng)


## Garantiertes Gemüse (der Frenzy-Vertrag: kein Müll).
static func roll_veggie(rng: GoobyRng) -> Dictionary:
	var idx := mini(VEGGIES.size() - 1, int(floor(rng.next() * float(VEGGIES.size()))))
	var v: Dictionary = VEGGIES[idx]
	return {"kind": "veggie", "key": v["key"], "half": v["half"], "juice": v["juice"]}


## Kadenz, die exakt acht Frenzy-Gemüse in drei Sekunden unterbringt.
static func frenzy_spawn_interval() -> float:
	return float(CHOP["FRENZY_DURATION_SEC"]) / float(CHOP["FRENZY_ITEMS"])


## Wie viele Frenzy-Starts eine Rundenzeit erreicht hat (25 s und 50 s).
static func frenzy_count_at(elapsed: float) -> int:
	return int(floor(maxf(0.0, elapsed) / float(CHOP["FRENZY_EVERY_SEC"])))


## Absprunggeschwindigkeit für einen Scheitel `h` über dem Start: √(2gh).
static func vy_for_apex(h: float, g := 9.5) -> float:
	return sqrt(2.0 * g * maxf(0.0, h))


## Einen Wurfbogen bauen: von unten geworfen, Scheitel im §CHOP-Band.
static func make_arc(rng: GoobyRng, half_w: float, y0: float, g := 9.5) -> Dictionary:
	var apex_y := (
		float(CHOP["APEX_MIN_Y"])
		+ rng.next() * (float(CHOP["APEX_MAX_Y"]) - float(CHOP["APEX_MIN_Y"]))
	)
	var vy := vy_for_apex(apex_y - y0, g)
	var t_apex := vy / g
	var x0 := (rng.next() * 2.0 - 1.0) * maxf(0.0, half_w - 0.4)
	var apex_x := (rng.next() * 2.0 - 1.0) * maxf(0.0, half_w - 0.55)
	var vx := (apex_x - x0) / t_apex if t_apex > 0.0 else 0.0
	return {"x0": x0, "y0": y0, "vx": vx, "vy": vy}


## Bogenposition t Sekunden nach dem Wurf.
static func arc_pos(arc: Dictionary, t: float, g := 9.5) -> Vector2:
	return Vector2(
		float(arc["x0"]) + float(arc["vx"]) * t,
		float(arc["y0"]) + float(arc["vy"]) * t - 0.5 * g * t * t
	)


## Scheitelzeit und -position eines Bogens (dort wischt der Bot).
static func arc_apex(arc: Dictionary, g := 9.5) -> Dictionary:
	var t := float(arc["vy"]) / g
	var p := arc_pos(arc, t, g)
	return {"t": t, "x": p.x, "y": p.y}


## Punkte für den k-ten Schnitt EINES Wisches: der erste 2, jeder weitere 3.
static func chop_points(k: int) -> int:
	return int(CHOP["CHOP_PTS"]) + (int(CHOP["COMBO_BONUS"]) if k > 1 else 0)


## Wisch-Kombo fortschreiben — Müll setzt sie sofort zurück.
static func combo_after_hit(current: int, kind: String) -> int:
	return 0 if kind == "junk" else maxi(0, current) + 1


## Gesamtpunkte eines Wisches mit n Gemüse: 2n + (n−1).
static func swipe_score(n: int) -> int:
	if n <= 0:
		return 0
	return int(CHOP["CHOP_PTS"]) * n + int(CHOP["COMBO_BONUS"]) * (n - 1)


## Delta anwenden, bei 0 gefloort.
static func apply_points(score: int, delta: int) -> int:
	return maxi(0, score + delta)


## Turbos ×1,5 wird genau einmal gerundet — am Rundenende.
static func final_score(score: int, tune: Dictionary = CHOP) -> int:
	return int(round(float(maxi(0, score)) * float(tune.get("SCORE_MULT", 1.0))))


## §G5.4 Endlos endet mit dem dritten geschnittenen Müllteil.
static func endless_should_end(junk_hits: int, tune: Dictionary = CHOP) -> bool:
	return bool(tune["ENDLESS"]) and junk_hits >= int(tune["ENDLESS_JUNK_HITS"])


## Kreuzt die Strecke A→B den Kreis um C mit Radius r? (Wisch-Trefferprüfung)
static func segment_hits_circle(a: Vector2, b: Vector2, c: Vector2, r: float) -> bool:
	var d := b - a
	var len2 := d.dot(d)
	var t := 0.0
	if len2 > 0.0:
		t = maxf(0.0, minf(1.0, (c - a).dot(d) / len2))
	var p := a + t * d - c
	return p.dot(p) <= r * r


## Low-FPS-Audit: gegen den ganzen Weg testen, den ein Objekt zurücklegte.
static func segment_hits_moving_circle(
	a: Vector2, b: Vector2, c0: Vector2, c1: Vector2, r: float
) -> bool:
	if _segments_intersect(a, b, c0, c1):
		return true
	return (
		segment_hits_circle(a, b, c0, r)
		or segment_hits_circle(a, b, c1, r)
		or segment_hits_circle(c0, c1, a, r)
		or segment_hits_circle(c0, c1, b, r)
	)


## Deterministische Bot-Zertifizierung (zahlengleich zum Web-Apex-Wisch-Bot).
static func simulate_autoplay(seed_value := 1, mode := "normal") -> Dictionary:
	var tune := apply_difficulty(CHOP, mode)
	var rng := GoobyRng.new(seed_value)
	var elapsed := 0.0
	var score := 0
	var misses := 0
	var junk_hits := 0
	var limit := 600.0 if bool(tune["ENDLESS"]) else float(tune["DURATION_SEC"])
	while elapsed < limit and not endless_should_end(junk_hits, tune):
		var size := wave_size_at(rng, elapsed)
		for _i in size:
			var item := roll_item(rng, elapsed, tune)
			if item["kind"] == "veggie":
				if rng.next() < float(tune["AUTOPLAY_CHOP_RATE"]):
					score += int(tune["CHOP_PTS"])
				else:
					misses += 1
			elif bool(tune["ENDLESS"]) and rng.next() < float(tune["ENDLESS_BOT_JUNK_RATE"]):
				junk_hits += 1
				if endless_should_end(junk_hits, tune):
					break
		elapsed += spawn_interval_at(elapsed, float(tune["DURATION_SEC"]), tune)
	# Die beiden festen müllfreien Frenzys sind deterministische Punktchancen.
	var frenzy_veggies := (
		0
		if bool(tune["ENDLESS"])
		else frenzy_count_at(float(tune["DURATION_SEC"])) * int(tune["FRENZY_ITEMS"])
	)
	score += (
		int(round(float(frenzy_veggies) * float(tune["AUTOPLAY_CHOP_RATE"])))
		* int(tune["CHOP_PTS"])
	)
	return {
		"seed": seed_value,
		"mode": mode,
		"score": score,
		"misses": misses,
		"junkHits": junk_hits,
		"elapsed": elapsed,
	}


## Streckenschnitt inklusive kollinearer/berührender Fälle.
static func _segments_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab_c := _cross(a, b, c)
	var ab_d := _cross(a, b, d)
	var cd_a := _cross(c, d, a)
	var cd_b := _cross(c, d, b)
	var eps := 1e-9
	var straddles_ab := (ab_c > eps and ab_d < -eps) or (ab_c < -eps and ab_d > eps)
	var straddles_cd := (cd_a > eps and cd_b < -eps) or (cd_a < -eps and cd_b > eps)
	if straddles_ab and straddles_cd:
		return true
	return (
		_on_segment(ab_c, c, a, b)
		or _on_segment(ab_d, d, a, b)
		or _on_segment(cd_a, a, c, d)
		or _on_segment(cd_b, b, c, d)
	)


static func _cross(p: Vector2, q: Vector2, r: Vector2) -> float:
	return (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)


static func _on_segment(value: float, point: Vector2, p: Vector2, q: Vector2) -> bool:
	var eps := 1e-9
	if absf(value) > eps:
		return false
	var in_x := point.x >= minf(p.x, q.x) - eps and point.x <= maxf(p.x, q.x) + eps
	var in_y := point.y >= minf(p.y, q.y) - eps and point.y <= maxf(p.y, q.y) + eps
	return in_x and in_y

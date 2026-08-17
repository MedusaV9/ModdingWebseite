class_name PurblePlaceLogic
extends RefCounted
## Pure Tortenwerkstatt-Logik — zahlengleicher Port von
## GOOBY/src/minigames/games/purblePlace.logic.js (PLAN4-GAMES §G1).
##
## Kern (§G1.3): der SPIELER treibt das 6-m-Band mit ◀/▶ (vor 0,9 m/s, zurück
## 0,7 m/s, Rampe 6 m/s²). Zutaten sind PHYSISCHE Tropfen (0,55 m Fall in
## 0,45 s — eine Form fängt nur, wenn |formS − düseS| ≤ ±0,24 m im Moment des
## Aufpralls). Der Ofen ist ein Bandtunnel (2,25–3,15 m): grün 2,25–3,0 s =
## +5, Selbstverkohlung bei 3,6 s = −3. Versand bei s 5,95 ± 0,30 nimmt
## automatisch den passendsten offenen Auftrag (+20/+8/−5, Combo +2…+10,
## Tempo +4). Coin-Zeile /5, 5..30, Ziel 120.
##
## Die Ansicht (`purble_place.gd`) rendert NUR diesen Zustand.

## Randtoleranz der Fang-/Versandfenster (Float-Sicherheit).
const EPS := 1e-9

## §G1 Bindezahlen (Basis = Mittel).
const CAKE := {
	"DURATION_SEC": 210.0,
	"MAX_TICKETS": 3,
	"PATIENCE_START_SEC": 45.0,
	"PATIENCE_STEP_SEC": 1.5,
	"PATIENCE_FLOOR_SEC": 30.0,
	"PATIENCE_MULT": 1.0,
	"EXPIRE_PTS": -5,
	"ORDER_INTERVAL_START_SEC": 30.0,
	"ORDER_INTERVAL_STEP_SEC": 2.0,
	"ORDER_INTERVAL_MIN_SEC": 14.0,
	"COMPLEX_AFTER_SERVES": 4,
	"MAX_CANDLES": 4,
	"BELT_LENGTH_M": 6.0,
	"BELT_FWD_SPEED": 0.9,
	"BELT_REV_SPEED": 0.7,
	"BELT_SLEW": 6.0,
	"FALL_SEC": 0.45,
	"FALL_M": 0.55,
	"CATCH_HALF_M": 0.24,
	"LOCKOUT_SEC": 0.5,
	"CANDLE_GAP_SEC": 0.18,
	"SPLAT_PTS": -2,
	"SPLAT_TTL_SEC": 4.0,
	"SPAWN_S": 0.15,
	"SPAWN_CLEAR_M": 0.7,
	"OVEN_START_S": 2.25,
	"OVEN_END_S": 3.15,
	"BAKE_GREEN_START_SEC": 2.25,
	"BAKE_GREEN_END_SEC": 3.0,
	"SINGE_SEC": 3.6,
	"BAKE_PERFECT_PTS": 5,
	"BAKE_SINGED_PTS": -3,
	"SHIP_S": 5.95,
	"SHIP_HALF_M": 0.3,
	"PAN_CAP_MAX": 3,
	"PAN_CAP_EVERY_SERVES": 3,
	"PERFECT_PTS": 20,
	"ONE_WRONG_PTS": 8,
	"REJECT_PTS": -5,
	"COMBO_STEP": 2,
	"COMBO_CAP": 10,
	"SPEED_BONUS_PTS": 4,
	"SPEED_BONUS_MIN_FRAC": 0.5,
	"ENDLESS": false,
	"ENDLESS_FAIL_COUNT": 3,
}

## §G1.6/§G5.4-Schwierigkeitszeilen (exakt, bindend).
const DIFFICULTY := {
	"easy":
	{
		"PATIENCE_MULT": 1.3,
		"ORDER_INTERVAL_MIN_SEC": 18.0,
		"CATCH_HALF_M": 0.3,
		"SINGE_SEC": 4.2,
		"PAN_CAP_EVERY_SERVES": 3,
		"ENDLESS": false,
	},
	"normal":
	{
		"PATIENCE_MULT": 1.0,
		"ORDER_INTERVAL_MIN_SEC": 14.0,
		"CATCH_HALF_M": 0.24,
		"SINGE_SEC": 3.6,
		"PAN_CAP_EVERY_SERVES": 3,
		"ENDLESS": false,
	},
	"hard":
	{
		"PATIENCE_MULT": 0.8,
		"ORDER_INTERVAL_MIN_SEC": 12.0,
		"CATCH_HALF_M": 0.19,
		"SINGE_SEC": 3.2,
		"PAN_CAP_EVERY_SERVES": 2,
		"ENDLESS": false,
	},
	"endless":
	{
		"PATIENCE_MULT": 0.8,
		"ORDER_INTERVAL_MIN_SEC": 10.0,
		"CATCH_HALF_M": 0.19,
		"SINGE_SEC": 3.2,
		"PAN_CAP_EVERY_SERVES": 2,
		"ENDLESS": true,
	},
}

## Auftrags-Dimensionen (§C9.2/§G1.6 — Farbwerte verbatim aus dem Web).
const SHAPES := ["round", "square", "heart"]
const SPONGES := ["vanilla", "chocolate", "strawberry"]
const SPONGE_HEX := {
	"vanilla": "#F5E6C8",
	"chocolate": "#6B4A2F",
	"strawberry": "#F2B8C6",
}
const ICINGS := ["white", "pink", "chocolate", "none"]
const ICING_HEX := {"white": "#FFF8F0", "pink": "#F781B0", "chocolate": "#4E3524"}
const TOPPINGS := ["cherry", "sprinkles", "berries", "none"]

## §G1.5-Stationstabelle (Bandposition s, bindend). `drop`-Zeilen sind die
## physischen Düsen (input.press); spawn/versand haben eigene Eingaben.
const STATIONS := [
	{"id": "spawn", "kind": "spawn", "s": 0.15, "button": true, "drop": false},
	{"id": "trash", "kind": "trash", "s": 0.15, "button": false, "drop": false},
	{
		"id": "teig.vanilla",
		"kind": "teig",
		"value": "vanilla",
		"s": 0.9,
		"button": true,
		"drop": true,
	},
	{
		"id": "teig.chocolate",
		"kind": "teig",
		"value": "chocolate",
		"s": 1.35,
		"button": true,
		"drop": true,
	},
	{
		"id": "teig.strawberry",
		"kind": "teig",
		"value": "strawberry",
		"s": 1.8,
		"button": true,
		"drop": true,
	},
	{
		"id": "ofen",
		"kind": "ofen",
		"s": 2.7,
		"s0": 2.25,
		"s1": 3.15,
		"button": false,
		"drop": false
	},
	{
		"id": "guss.white",
		"kind": "guss",
		"value": "white",
		"s": 3.5,
		"button": true,
		"drop": true,
	},
	{"id": "guss.pink", "kind": "guss", "value": "pink", "s": 3.95, "button": true, "drop": true},
	{
		"id": "guss.chocolate",
		"kind": "guss",
		"value": "chocolate",
		"s": 4.4,
		"button": true,
		"drop": true,
	},
	{
		"id": "deko.cherry",
		"kind": "deko",
		"value": "cherry",
		"s": 4.7,
		"button": true,
		"drop": true,
	},
	{
		"id": "deko.sprinkles",
		"kind": "deko",
		"value": "sprinkles",
		"s": 5.0,
		"button": true,
		"drop": true,
	},
	{
		"id": "deko.berries",
		"kind": "deko",
		"value": "berries",
		"s": 5.3,
		"button": true,
		"drop": true,
	},
	{"id": "kerzen", "kind": "kerzen", "s": 5.6, "button": true, "drop": true},
	{"id": "versand", "kind": "versand", "s": 5.95, "button": true, "drop": false},
]


## Stationszeile per Id ({} wenn unbekannt).
static func station(station_id: String) -> Dictionary:
	for row: Dictionary in STATIONS:
		if str(row["id"]) == station_id:
			return row
	return {}


## Abgeleitetes Tune für einen §G5-Modus; `normal` reproduziert die Basis.
static func apply_difficulty(tune := CAKE, mode := "normal") -> Dictionary:
	var id := mode if DIFFICULTY.has(mode) else "normal"
	var out := tune.duplicate(true)
	for key: String in DIFFICULTY[id]:
		out[key] = DIFFICULTY[id][key]
	out["mode"] = id
	return out


## Geduld eines NEUEN Auftrags nach `serves` Torten (§C9.2 + §G1.6-Faktor).
static func patience_for(serves: int, mult := 1.0) -> float:
	return (
		maxf(
			float(CAKE["PATIENCE_FLOOR_SEC"]),
			(
				float(CAKE["PATIENCE_START_SEC"])
				- float(CAKE["PATIENCE_STEP_SEC"]) * float(maxi(0, serves))
			)
		)
		* mult
	)


## Sekunden bis zum nächsten Auftrag: 30 − 2·serves, gedeckelt (§C9.4/§G1.6).
static func order_interval_at(
	serves: int, floor_sec := float(CAKE["ORDER_INTERVAL_MIN_SEC"])
) -> float:
	return maxf(
		floor_sec,
		(
			float(CAKE["ORDER_INTERVAL_START_SEC"])
			- float(CAKE["ORDER_INTERVAL_STEP_SEC"]) * float(maxi(0, serves))
		)
	)


## Gleichzeitige Formen (§G1.6): min(3, 1 + ⌊serves / EVERY⌋).
static func pan_cap_at(serves: int, tune := CAKE) -> int:
	return mini(
		int(tune["PAN_CAP_MAX"]),
		1 + int(floorf(float(maxi(0, serves)) / float(tune["PAN_CAP_EVERY_SERVES"])))
	)


## Backergebnis bei Zählerstand `t_sec` (§G1.5).
static func bake_result_at(t_sec: float, tune := CAKE) -> String:
	if t_sec >= float(tune["SINGE_SEC"]):
		return "singed"
	if t_sec >= float(tune["BAKE_GREEN_START_SEC"]) and t_sec <= float(tune["BAKE_GREEN_END_SEC"]):
		return "perfect"
	return "pale" if t_sec < float(tune["BAKE_GREEN_START_SEC"]) else "over"


## Sofortpunkte fürs Backen (§G1.5): perfekt +5, verkohlt −3, sonst ±0.
static func bake_points(result: String) -> int:
	if result == "perfect":
		return int(CAKE["BAKE_PERFECT_PTS"])
	if result == "singed":
		return int(CAKE["BAKE_SINGED_PTS"])
	return 0


## §G1.5-Fangfenster im Moment des Aufpralls (Ränder inklusive).
static func catch_window(pan_s: float, nozzle_s: float, tune := CAKE) -> bool:
	return absf(pan_s - nozzle_s) <= float(tune["CATCH_HALF_M"]) + EPS


## §G1.9-Vorhaltemathematik: wo eine bei `pressed_at_s` gedrückte Form beim
## Aufprall steht. `belt_plan` = konstantes Tempo oder Segmente [{v, dur}].
static func drop_impact_s(pressed_at_s: float, belt_plan: Variant, tune := CAKE) -> float:
	var segs: Array = (
		[{"v": float(belt_plan)}] if belt_plan is float or belt_plan is int else belt_plan
	)
	var s := pressed_at_s
	var left := float(tune["FALL_SEC"])
	for seg: Dictionary in segs:
		if left <= 0.0:
			break
		var d := minf(float(seg.get("dur", left)), left)
		s += float(seg["v"]) * d
		left -= d
	return s


static func _weighted_pick(rng: GoobyRng, items: Array, weights: Array) -> Variant:
	var total := 0.0
	for w: float in weights:
		total += w
	var roll := rng.next() * total
	for i in items.size():
		roll -= float(weights[i])
		if roll < 0.0:
			return items[i]
	return items[items.size() - 1]


## Gesäter Auftragsgenerator mit §C9.4-Gewichtung (verbatim übernommen).
static func make_ticket(rng: GoobyRng, serves: int) -> Dictionary:
	var complex_mix := serves >= int(CAKE["COMPLEX_AFTER_SERVES"])
	var shape: String = SHAPES[mini(SHAPES.size() - 1, int(floorf(rng.next() * SHAPES.size())))]
	var sponge: String = SPONGES[mini(SPONGES.size() - 1, int(floorf(rng.next() * SPONGES.size())))]
	var icing := str(
		_weighted_pick(rng, ICINGS, [3.0, 3.0, 3.0, 2.0] if complex_mix else [1.0, 1.0, 1.0, 0.0])
	)
	var topping := str(_weighted_pick(rng, TOPPINGS, [3.0, 3.0, 3.0, 2.0]))
	var candles := int(
		_weighted_pick(
			rng,
			[0, 1, 2, 3, 4],
			[2.0, 3.0, 3.0, 2.0, 1.0] if complex_mix else [4.0, 3.0, 2.0, 0.0, 0.0]
		)
	)
	return {
		"shape": shape,
		"sponge": sponge,
		"icing": icing,
		"topping": topping,
		"candles": candles,
	}


## Falsche/fehlende Bauteile einer Torte gegenüber einem Auftrag (0…6).
static func wrong_count(cake: Dictionary, ticket: Dictionary) -> int:
	var wrong := 0
	if str(cake["shape"]) != str(ticket["shape"]):
		wrong += 1
	if _slot(cake, "sponge") != str(ticket["sponge"]):
		wrong += 1
	if _slot(cake, "icing") != str(ticket["icing"]):
		wrong += 1
	if _slot(cake, "topping") != str(ticket["topping"]):
		wrong += 1
	if int(cake.get("candles", 0)) != int(ticket["candles"]):
		wrong += 1
	if str(cake.get("bake", "")) == "singed":
		wrong += 1
	return wrong


## Leere Guss-/Deko-Slots zählen als "none"; ein leerer Teig passt nie.
static func _slot(cake: Dictionary, key: String) -> String:
	var value: Variant = cake.get(key, null)
	if value == null:
		return "" if key == "sponge" else "none"
	return str(value)


## Ergebnis nach Fehlerzahl (§C9.4 verbatim).
static func serve_outcome(wrong: int) -> String:
	if wrong == 0:
		return "perfect"
	if wrong == 1:
		return "oneWrong"
	return "rejected"


## Volle §C9.4-Punktematrix (Basis + Combo + Tempobonus).
static func score_serve(wrong: int, combo: int, patience_frac: float) -> Dictionary:
	var outcome := serve_outcome(wrong)
	var rejected := outcome == "rejected"
	var base := int(CAKE["REJECT_PTS"])
	if outcome == "perfect":
		base = int(CAKE["PERFECT_PTS"])
	elif outcome == "oneWrong":
		base = int(CAKE["ONE_WRONG_PTS"])
	var combo_bonus := (
		0 if rejected else mini(int(CAKE["COMBO_CAP"]), int(CAKE["COMBO_STEP"]) * maxi(0, combo))
	)
	var speed_bonus := (
		int(CAKE["SPEED_BONUS_PTS"])
		if not rejected and patience_frac >= float(CAKE["SPEED_BONUS_MIN_FRAC"])
		else 0
	)
	return {
		"outcome": outcome,
		"points": base + combo_bonus + speed_bonus,
		"base": base,
		"comboBonus": combo_bonus,
		"speedBonus": speed_bonus,
		"comboAfter": 0 if rejected else combo + 1,
	}


## Bestpassender offener Auftrag (wenigste Fehler, gleichauf → ältester).
static func best_ticket_index(cake: Dictionary, tickets: Array) -> int:
	var best := -1
	var best_wrong := 1 << 30
	for i in tickets.size():
		var w := wrong_count(cake, (tickets[i] as Dictionary)["spec"])
		if w < best_wrong:
			best = i
			best_wrong = w
	return best


# ── Bandsimulation (§G1.9) ────────────────────────────────────────────────


## Frische Fertigungslinie.
static func create_line(rng: GoobyRng, difficulty := "normal") -> Dictionary:
	var tune := apply_difficulty(CAKE, difficulty)
	return {
		"mode": str(tune["mode"]),
		"tune": tune,
		"rng": rng,
		"t": 0.0,
		"score": 0,
		"combo": 0,
		"serves": 0,
		"cakesServed": 0,
		"perfectCakes": 0,
		"rejected": 0,
		"expired": 0,
		"perfectBakes": 0,
		"splatCount": 0,
		"buzzCount": 0,
		"trashed": 0,
		"tickets": [] as Array[Dictionary],
		"pans": [] as Array[Dictionary],
		"drops": [] as Array[Dictionary],
		"splats": [] as Array[Dictionary],
		"lockouts": {},
		"beltV": 0.0,
		"orderT": 0.0,
		"nextTicketId": 1,
		"nextPanId": 1,
		"over": false,
	}


## Verfügbarkeit des „Neue Form"-Knopfs (§G1.6).
static func can_spawn(line: Dictionary) -> Dictionary:
	var tune: Dictionary = line["tune"]
	var pans: Array = line["pans"]
	if pans.size() >= pan_cap_at(int(line["serves"]), tune):
		return {"ok": false, "reason": "cap"}
	for pan: Dictionary in pans:
		if absf(float(pan["s"]) - float(tune["SPAWN_S"])) < float(tune["SPAWN_CLEAR_M"]):
			return {"ok": false, "reason": "blocked"}
	return {"ok": true, "reason": ""}


static func _add_score(line: Dictionary, points: int) -> void:
	line["score"] = maxi(0, int(line["score"]) + points)


static func _push_buzz(
	line: Dictionary, events: Array, station_id: String, pan_id: int, reason: String
) -> void:
	line["buzzCount"] = int(line["buzzCount"]) + 1
	events.append({"type": "buzz", "station": station_id, "panId": pan_id, "reason": reason})


static func _check_endless_over(line: Dictionary) -> void:
	var tune: Dictionary = line["tune"]
	if (
		bool(tune["ENDLESS"])
		and int(line["rejected"]) + int(line["expired"]) >= int(tune["ENDLESS_FAIL_COUNT"])
	):
		line["over"] = true


static func _try_spawn(line: Dictionary, shape: String, events: Array) -> void:
	if not SHAPES.has(shape):
		return
	var gate := can_spawn(line)
	if not bool(gate["ok"]):
		_push_buzz(line, events, "spawn", 0, str(gate["reason"]))
		return
	var tune: Dictionary = line["tune"]
	var pan := {
		"id": int(line["nextPanId"]),
		"shape": shape,
		"s": float(tune["SPAWN_S"]),
		"sponge": null,
		"bake": null,
		"bakeT": 0.0,
		"inOven": false,
		"icing": null,
		"topping": null,
		"candles": 0,
		"perfectCounted": false,
	}
	line["nextPanId"] = int(line["nextPanId"]) + 1
	(line["pans"] as Array).append(pan)
	events.append(
		{"type": "panSpawn", "panId": int(pan["id"]), "shape": shape, "s": float(pan["s"])}
	)


static func _try_press(line: Dictionary, station_id: String, events: Array) -> void:
	var st := station(station_id)
	if st.is_empty() or not bool(st["drop"]):
		return
	var lockouts: Dictionary = line["lockouts"]
	if float(lockouts.get(station_id, 0.0)) > 0.0:
		return
	var tune: Dictionary = line["tune"]
	lockouts[station_id] = (
		float(tune["CANDLE_GAP_SEC"]) if str(st["kind"]) == "kerzen" else float(tune["LOCKOUT_SEC"])
	)
	var drop := {
		"station": station_id,
		"kind": str(st["kind"]),
		"value": st.get("value", null),
		"nozzleS": float(st["s"]),
		"firedAt": float(line["t"]),
		"impactAt": float(line["t"]) + float(tune["FALL_SEC"]),
	}
	(line["drops"] as Array).append(drop)
	(
		events
		. append(
			{
				"type": "drop",
				"station": station_id,
				"kind": str(st["kind"]),
				"value": drop["value"],
				"nozzleS": float(st["s"]),
				"impactAt": float(drop["impactAt"]),
			}
		)
	)


static func _serve_pan(line: Dictionary, pan: Dictionary, events: Array) -> void:
	var tickets: Array = line["tickets"]
	var idx := best_ticket_index(pan, tickets)
	var ticket: Dictionary = tickets[idx]
	var wrong := wrong_count(pan, ticket["spec"])
	var patience_frac := float(ticket["remain"]) / float(ticket["patience"])
	var r := score_serve(wrong, int(line["combo"]), patience_frac)
	_add_score(line, int(r["points"]))
	line["combo"] = int(r["comboAfter"])
	line["serves"] = int(line["serves"]) + 1
	line["cakesServed"] = int(line["cakesServed"]) + 1
	if str(r["outcome"]) == "perfect":
		line["perfectCakes"] = int(line["perfectCakes"]) + 1
	if str(r["outcome"]) == "rejected":
		line["rejected"] = int(line["rejected"]) + 1
	tickets.remove_at(idx)
	(line["pans"] as Array).erase(pan)
	(
		events
		. append(
			{
				"type": "reject" if str(r["outcome"]) == "rejected" else "serve",
				"outcome": str(r["outcome"]),
				"points": int(r["points"]),
				"base": int(r["base"]),
				"comboBonus": int(r["comboBonus"]),
				"speedBonus": int(r["speedBonus"]),
				"wrong": wrong,
				"patienceFrac": patience_frac,
				"ticketId": int(ticket["id"]),
				"panId": int(pan["id"]),
				"bake": pan["bake"],
			}
		)
	)
	_check_endless_over(line)


static func _try_ship(line: Dictionary, events: Array) -> void:
	var tune: Dictionary = line["tune"]
	var ship_s := float(tune["SHIP_S"])
	var in_zone: Array[Dictionary] = []
	for pan: Dictionary in line["pans"]:
		if absf(float(pan["s"]) - ship_s) <= float(tune["SHIP_HALF_M"]) + EPS:
			in_zone.append(pan)
	in_zone.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var da := absf(float(a["s"]) - ship_s)
			var db := absf(float(b["s"]) - ship_s)
			if da != db:
				return da < db
			return int(a["id"]) < int(b["id"])
	)
	var baked: Array[Dictionary] = []
	for pan: Dictionary in in_zone:
		if pan["bake"] != null:
			baked.append(pan)
	if baked.is_empty():
		_push_buzz(
			line,
			events,
			"versand",
			int(in_zone[0]["id"]) if not in_zone.is_empty() else 0,
			"raw" if not in_zone.is_empty() else "empty"
		)
		return
	if (line["tickets"] as Array).is_empty():
		_push_buzz(line, events, "versand", int(baked[0]["id"]), "noTicket")
		return
	_serve_pan(line, baked[0], events)


## Backergebnis festschreiben. Die Punkte sind die DIFFERENZ zum zuletzt
## festgeschriebenen Ergebnis — der Gesamtstand bleibt so wegunabhängig.
static func _commit_bake(
	line: Dictionary, pan: Dictionary, result: String, auto: bool, events: Array
) -> void:
	var previous := "" if pan["bake"] == null else str(pan["bake"])
	var delta := bake_points(result) - bake_points(previous)
	if result == "perfect" and previous != "perfect" and not bool(pan["perfectCounted"]):
		line["perfectBakes"] = int(line["perfectBakes"]) + 1
		pan["perfectCounted"] = true
	pan["bake"] = result
	if delta != 0:
		_add_score(line, delta)
	(
		events
		. append(
			{
				"type": "bakeCommit",
				"panId": int(pan["id"]),
				"result": result,
				"points": delta,
				"bakeT": float(pan["bakeT"]),
				"auto": auto,
			}
		)
	)


## Ofen-Buchhaltung für EIN Bewegungs-Teilstück (§G1.5).
static func _oven_step(
	line: Dictionary, pan: Dictionary, s0: float, s1: float, seg_dt: float, events: Array
) -> void:
	var tune: Dictionary = line["tune"]
	if pan["sponge"] == null or str(pan.get("bake", "")) == "singed":
		pan["inOven"] = false
		return
	var start_s := float(tune["OVEN_START_S"])
	var end_s := float(tune["OVEN_END_S"])
	var inside1 := s1 >= start_s and s1 <= end_s
	var frac := 0.0
	if s0 == s1:
		frac = 1.0 if inside1 else 0.0
	else:
		var lo := minf(s0, s1)
		var hi := maxf(s0, s1)
		var overlap := minf(hi, end_s) - maxf(lo, start_s)
		frac = minf(1.0, overlap / (hi - lo)) if overlap > 0.0 else 0.0
	var was_in := bool(pan["inOven"])
	if not was_in and frac > 0.0:
		events.append({"type": "bakeStart", "panId": int(pan["id"]), "bakeT": float(pan["bakeT"])})
	if frac > 0.0:
		pan["bakeT"] = float(pan["bakeT"]) + frac * seg_dt
		if float(pan["bakeT"]) >= float(tune["SINGE_SEC"]):
			pan["bakeT"] = float(tune["SINGE_SEC"])
			_commit_bake(line, pan, "singed", true, events)
			pan["inOven"] = false
			return
	if (was_in or frac > 0.0) and not inside1:
		_commit_bake(line, pan, bake_result_at(float(pan["bakeT"]), tune), false, events)
	pan["inOven"] = inside1


## Geschlossene Bandbewegung unter der 6-m/s²-Rampe (Trapezprofil).
static func belt_advance(v0: float, vt: float, slew: float, dur: float) -> Dictionary:
	if v0 == vt:
		return {"disp": v0 * dur, "v1": v0}
	var dir := 1.0 if vt > v0 else -1.0
	var t_ramp := absf(vt - v0) / slew
	if dur < t_ramp:
		var v1 := v0 + dir * slew * dur
		return {"disp": ((v0 + v1) / 2.0) * dur, "v1": v1}
	return {"disp": ((v0 + vt) / 2.0) * t_ramp + vt * (dur - t_ramp), "v1": vt}


## Die ganze Linie (Formen, Kleckse, Ofen, Müll) um ein Teilstück bewegen.
static func _move_line(line: Dictionary, disp: float, seg_dt: float, events: Array) -> void:
	var tune: Dictionary = line["tune"]
	var splats: Array = line["splats"]
	for i in range(splats.size() - 1, -1, -1):
		var sp: Dictionary = splats[i]
		sp["s"] = float(sp["s"]) + disp
		sp["ttl"] = float(sp["ttl"]) - seg_dt
		if float(sp["ttl"]) <= 0.0:
			splats.remove_at(i)
	var pans: Array = line["pans"]
	for i in range(pans.size() - 1, -1, -1):
		var pan: Dictionary = pans[i]
		var s0 := float(pan["s"])
		var s1 := minf(float(tune["BELT_LENGTH_M"]), s0 + disp)
		pan["s"] = s1
		_oven_step(line, pan, s0, s1, seg_dt, events)
		if float(pan["s"]) < 0.0:
			pans.remove_at(i)
			line["trashed"] = int(line["trashed"]) + 1
			events.append({"type": "trash", "panId": int(pan["id"])})


## Einen Tropfen im Moment des Aufpralls auflösen (§G1.5).
static func _resolve_impact(line: Dictionary, drop: Dictionary, events: Array) -> void:
	var tune: Dictionary = line["tune"]
	var nozzle_s := float(drop["nozzleS"])
	var candidates: Array[Dictionary] = []
	for pan: Dictionary in line["pans"]:
		if catch_window(float(pan["s"]), nozzle_s, tune):
			candidates.append(pan)
	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var da := absf(float(a["s"]) - nozzle_s)
			var db := absf(float(b["s"]) - nozzle_s)
			if da != db:
				return da < db
			return int(a["id"]) < int(b["id"])
	)
	if candidates.is_empty():
		_add_score(line, int(tune["SPLAT_PTS"]))
		line["splatCount"] = int(line["splatCount"]) + 1
		(line["splats"] as Array).append({"s": nozzle_s, "ttl": float(tune["SPLAT_TTL_SEC"])})
		(
			events
			. append(
				{
					"type": "splat",
					"station": str(drop["station"]),
					"s": nozzle_s,
					"points": int(tune["SPLAT_PTS"]),
				}
			)
		)
		return
	var pan: Dictionary = candidates[0]
	var kind := str(drop["kind"])
	var legal := false
	if kind == "teig":
		legal = pan["sponge"] == null
	elif kind == "guss":
		legal = pan["bake"] != null and pan["icing"] == null
	elif kind == "deko":
		legal = pan["bake"] != null and pan["topping"] == null
	else:
		legal = pan["bake"] != null and int(pan["candles"]) < int(tune["MAX_CANDLES"])
	if not legal:
		_push_buzz(line, events, str(drop["station"]), int(pan["id"]), "illegal")
		return
	if kind == "teig":
		pan["sponge"] = drop["value"]
	elif kind == "guss":
		pan["icing"] = drop["value"]
	elif kind == "deko":
		pan["topping"] = drop["value"]
	else:
		pan["candles"] = int(pan["candles"]) + 1
	(
		events
		. append(
			{
				"type": "catch",
				"station": str(drop["station"]),
				"kind": kind,
				"panId": int(pan["id"]),
				"value": int(pan["candles"]) if kind == "kerzen" else drop["value"],
			}
		)
	)


## Band + Tropfen + Ofen integrieren, unterteilt an exakten Aufprallzeiten
## und an Nulldurchgängen der Bandgeschwindigkeit.
static func _integrate_line(line: Dictionary, dt: float, dir: int, events: Array) -> void:
	var tune: Dictionary = line["tune"]
	var vt := 0.0
	if dir > 0:
		vt = float(tune["BELT_FWD_SPEED"])
	elif dir < 0:
		vt = -float(tune["BELT_REV_SPEED"])
	var t := float(line["t"])
	var t_end := float(line["t"]) + dt
	var guard := 0
	while t < t_end - EPS and guard < 64:
		guard += 1
		var t_next := t_end
		for d: Dictionary in line["drops"]:
			var impact := float(d["impactAt"])
			if impact > t + EPS and impact < t_next:
				t_next = impact
		var belt_v := float(line["beltV"])
		if belt_v != 0.0 and vt * belt_v < 0.0:
			var tz := t + absf(belt_v) / float(tune["BELT_SLEW"])
			if tz > t + EPS and tz < t_next:
				t_next = tz
		var seg_dt := t_next - t
		var step := belt_advance(belt_v, vt, float(tune["BELT_SLEW"]), seg_dt)
		_move_line(line, float(step["disp"]), seg_dt, events)
		line["beltV"] = float(step["v1"])
		t = t_next
		var drops: Array = line["drops"]
		for i in range(drops.size() - 1, -1, -1):
			if float((drops[i] as Dictionary)["impactAt"]) <= t + EPS:
				var drop: Dictionary = drops[i]
				drops.remove_at(i)
				_resolve_impact(line, drop, events)
	line["t"] = t_end


## Auftragsnachschub + Geduldsabbau + Ablauf (§G1.6-Takt).
static func _tick_tickets(line: Dictionary, dt: float, events: Array) -> void:
	var tune: Dictionary = line["tune"]
	var tickets: Array = line["tickets"]
	line["orderT"] = float(line["orderT"]) - dt
	if float(line["orderT"]) <= 0.0:
		if tickets.size() < int(tune["MAX_TICKETS"]):
			var spec := make_ticket(line["rng"], int(line["serves"]))
			var patience := patience_for(int(line["serves"]), float(tune["PATIENCE_MULT"]))
			var ticket := {
				"id": int(line["nextTicketId"]),
				"spec": spec,
				"remain": patience,
				"patience": patience,
			}
			line["nextTicketId"] = int(line["nextTicketId"]) + 1
			tickets.append(ticket)
			line["orderT"] = order_interval_at(
				int(line["serves"]), float(tune["ORDER_INTERVAL_MIN_SEC"])
			)
			(
				events
				. append(
					{
						"type": "ticketNew",
						"ticketId": int(ticket["id"]),
						"spec": spec,
						"patience": patience,
					}
				)
			)
		else:
			line["orderT"] = 0.0
	for i in range(tickets.size() - 1, -1, -1):
		var tk: Dictionary = tickets[i]
		tk["remain"] = float(tk["remain"]) - dt
		if float(tk["remain"]) <= 0.0:
			tickets.remove_at(i)
			_add_score(line, int(tune["EXPIRE_PTS"]))
			line["combo"] = 0
			line["expired"] = int(line["expired"]) + 1
			events.append(
				{"type": "expire", "ticketId": int(tk["id"]), "points": int(tune["EXPIRE_PTS"])}
			)
			_check_endless_over(line)


## Linie um `dt` weiterrechnen und die Ereignisse dieses Schritts liefern.
## input = {belt: -1|0|1, press: StationId|"", spawnShape: Form|"", ship: bool}
static func step_line(line: Dictionary, dt: float, input := {}) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if bool(line["over"]) or not dt > 0.0:
		return events

	var lockouts: Dictionary = line["lockouts"]
	for id: String in lockouts.keys():
		lockouts[id] = float(lockouts[id]) - dt
		if float(lockouts[id]) <= 0.0:
			lockouts.erase(id)

	var spawn_shape := str(input.get("spawnShape", ""))
	if not spawn_shape.is_empty():
		_try_spawn(line, spawn_shape, events)
	var press := str(input.get("press", ""))
	if not press.is_empty():
		_try_press(line, press, events)
	if bool(input.get("ship", false)):
		_try_ship(line, events)

	var belt := int(input.get("belt", 0))
	_integrate_line(line, dt, signi(belt), events)
	_tick_tickets(line, dt, events)
	return events


## §G1.9-Zertifikatslauf: Linie + Bot bei festen 30 Hz.
static func simulate_round(
	seed_value: int, difficulty := "normal", duration_sec := -1.0
) -> Dictionary:
	var line := create_line(GoobyRng.new(seed_value), difficulty)
	var bot := PurblePlaceBot.new(GoobyRng.new((seed_value ^ 0x9E3779B9) & 0xFFFFFFFF))
	var tune: Dictionary = line["tune"]
	var dt := 1.0 / 30.0
	var duration := duration_sec
	if duration < 0.0:
		duration = 900.0 if bool(tune["ENDLESS"]) else float(tune["DURATION_SEC"])
	var t := 0.0
	while t < duration and not bool(line["over"]):
		step_line(line, dt, bot.plan(line, dt))
		t += dt
	return {
		"score": int(line["score"]),
		"cakesServed": int(line["cakesServed"]),
		"perfectCakes": int(line["perfectCakes"]),
		"rejected": int(line["rejected"]),
		"expired": int(line["expired"]),
		"serves": int(line["serves"]),
		"perfectBakes": int(line["perfectBakes"]),
		"splats": int(line["splatCount"]),
		"trashed": int(line["trashed"]),
		"tSec": float(line["t"]),
		"over": bool(line["over"]),
		"mode": str(line["mode"]),
	}

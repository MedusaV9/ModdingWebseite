class_name PurblePlaceBot
extends RefCounted
## §G1.9-Autoplay der Tortenwerkstatt — zahlengleicher Port von `createBot()`
## aus GOOBY/src/minigames/games/purblePlace.logic.js.
##
## Der Bot fährt das Band wie ein Mensch: zur Spawn-Marke → Form setzen → unter
## die Teig-Düse fahren und STEHEN BLEIBEN (der 0,45-s-Fall trifft dann sicher)
## → in den Ofen → warten bis der Zähler ≥ 2,4 s → raus (die Ausfahrt schreibt
## das Backergebnis fest) → Guss → Deko → Kerzen → Versand. Eine zweite Form
## öffnet er nur, WÄHREND die erste bäckt.
##
## Das Fehlermodell (Parkzittern, falsche Nachbardüse, Ofen zu früh/zu spät,
## eine Kerze zu wenig) ist verbatim aus dem Web übernommen — die Reihenfolge
## der `rng()`-Aufrufe ist bindend, damit gleiche Seeds gleiche Läufe geben.

## Web `BOT` (§G1.9-Tuning, in Tests überschreibbar).
const BOT := {
	"ARRIVE_TOL_M": 0.05,
	"PARK_JITTER_M": 0.06,
	"SLOPPY_CHANCE": 0.28,
	"SLOPPY_JITTER_M": 0.27,
	"REACT_MIN_SEC": 0.15,
	"REACT_MAX_SEC": 0.55,
	"WRONG_CHANCE": 0.2,
	"SHAPE_WRONG_CHANCE": 0.16,
	"OVEN_EARLY_CHANCE": 0.35,
	"OVEN_LATE_CHANCE": 0.11,
	"OVEN_PARK_S": 2.85,
	"OVEN_EXIT_METER_SEC": 2.4,
	"CANDLE_SHORT_CHANCE": 0.18,
	"HESITATE_MIN_SEC": 0.8,
	"HESITATE_MAX_SEC": 3.0,
}

var _rng: GoobyRng
var _p: Dictionary

# Bot-Gedächtnis (Web `st`).
var _pan_id := 0
var _spec: Dictionary = {}
var _plan: Dictionary = {}
var _stage := ""
var _phase := "idle"
var _cfg: Dictionary = {}
var _react_t := 0.0
var _await_until := 0.0
var _hesitate_t := 0.0
var _spawn_issued := false
var _side_spawned := false


func _init(rng: GoobyRng, opts := {}) -> void:
	_rng = rng
	_p = BOT.duplicate()
	for key: String in opts:
		_p[key] = opts[key]


## Ein Planungsschritt; das Ergebnis geht unverändert in `step_line()`.
func plan(line: Dictionary, dt: float) -> Dictionary:
	var input := {"belt": 0, "press": "", "spawnShape": "", "ship": false}
	if bool(line["over"]):
		return input

	if _hesitate_t > 0.0:
		_hesitate_t -= dt
		return input

	var pan := _resolve_pan(line)
	if pan.is_empty():
		return _open_pan(line, input)

	var stage := _next_stage(pan)
	if stage != _stage:
		_stage = stage
		_phase = "drive"
		_cfg = {} if stage == "oven" else _make_cfg(stage)

	if stage == "oven":
		return _oven_plan(line, pan, input)
	return _station_plan(line, pan, input, dt)


## Die betreute Form finden: nach einem Spawn die jüngste übernehmen, sonst
## die eigene — und falls die weg ist, die parallel geöffnete Zweitform
## (älteste auf dem Band). Leer = gerade keine Form vorhanden.
func _resolve_pan(line: Dictionary) -> Dictionary:
	var pans: Array = line["pans"]
	if _spawn_issued:
		_spawn_issued = false
		var newest: Dictionary = {}
		for p: Dictionary in pans:
			if newest.is_empty() or int(p["id"]) > int(newest["id"]):
				newest = p
		if not newest.is_empty():
			_adopt_pan(line, newest)
	for p: Dictionary in pans:
		if int(p["id"]) == _pan_id:
			return p
	var spare: Dictionary = {}
	for p: Dictionary in pans:
		if spare.is_empty() or int(p["id"]) < int(spare["id"]):
			spare = p
	if not spare.is_empty():
		_adopt_pan(line, spare)
	return spare


## Neue Form für den vordersten Wunsch öffnen (falls überhaupt einer wartet).
func _open_pan(line: Dictionary, input: Dictionary) -> Dictionary:
	var tickets: Array = line["tickets"]
	if tickets.is_empty() or not bool(PurblePlaceLogic.can_spawn(line)["ok"]):
		return input
	input["spawnShape"] = _pick_shape((tickets[0] as Dictionary)["spec"])
	_spawn_issued = true
	return input


## Fahren → Reaktionspause → Druck → Aufprall abwarten (Web `switch (st.phase)`).
func _station_plan(line: Dictionary, pan: Dictionary, input: Dictionary, dt: float) -> Dictionary:
	if _phase == "drive":
		var dir := _drive_toward(line, pan, float(_cfg["target"]))
		if dir != 0 or absf(float(line["beltV"])) > 0.001:
			input["belt"] = dir
			return input
		_phase = "react"
		_react_t = float(_cfg["react"])
		return input
	if _phase == "react":
		_react_t -= dt
		if _react_t > 0.0:
			return input
		return _fire(line, input)
	if _phase == "await":
		return _await_plan(line, input)
	_phase = "drive"
	return input


## Nach dem Tropfen warten; ist die Stufe nicht weitergesprungen, ging er
## daneben — dann vorsichtig neu einparken und noch einmal versuchen.
func _await_plan(line: Dictionary, input: Dictionary) -> Dictionary:
	if float(line["t"]) < _await_until:
		return input
	var station_id := str(_cfg["stationId"])
	var base := (
		float(PurblePlaceLogic.CAKE["SHIP_S"])
		if station_id.is_empty()
		else float(PurblePlaceLogic.station(station_id)["s"])
	)
	_cfg["target"] = base + _careful_jitter()
	_cfg["react"] = _react_sec()
	_phase = "drive"
	return input


## Den geplanten Druck (bzw. den Versand) auslösen.
func _fire(line: Dictionary, input: Dictionary) -> Dictionary:
	if _stage == "ship":
		if (line["tickets"] as Array).is_empty():
			return input  # halten — nie ins Leere summen
		input["ship"] = true
		_pan_id = 0
		_stage = ""
		_phase = "idle"
		_hesitate_t = _hesitate_sec()
		return input
	var station_id := str(_cfg["stationId"])
	if float((line["lockouts"] as Dictionary).get(station_id, 0.0)) > 0.0:
		return input
	input["press"] = station_id
	_phase = "await"
	_await_until = float(line["t"]) + float(PurblePlaceLogic.CAKE["FALL_SEC"]) + 0.1
	return input


## Ofenfahrplan: einparken, Zähler abwarten, ausfahren (§G1.9).
func _oven_plan(line: Dictionary, pan: Dictionary, input: Dictionary) -> Dictionary:
	var oven: Dictionary = _plan["oven"]
	if _phase == "wait":
		var tickets: Array = line["tickets"]
		if (
			not _side_spawned
			and tickets.size() >= 2
			and bool(PurblePlaceLogic.can_spawn(line)["ok"])
		):
			_side_spawned = true
			input["spawnShape"] = _pick_shape((tickets[1] as Dictionary)["spec"])
			return input
		if str(oven["mode"]) == "late":
			return input  # eingenickt → die Selbstverkohlung schreibt fest
		var exit_meter := float(oven.get("exitMeter", _p["OVEN_EXIT_METER_SEC"]))
		if float(pan["bakeT"]) >= exit_meter:
			_phase = "exit"
		return input
	if _phase == "exit":
		input["belt"] = 1  # rausfahren — die Ausfahrt schreibt das Backergebnis fest
		return input
	var dir := _drive_toward(line, pan, float(_p["OVEN_PARK_S"]))
	if dir != 0 or absf(float(line["beltV"])) > 0.001:
		input["belt"] = dir
		return input
	_phase = "wait"
	return input


## Bandrichtung inkl. Bremsvorhalt (das Band rollt unter der 6-m/s²-Rampe aus).
func _drive_toward(line: Dictionary, pan: Dictionary, target: float) -> int:
	var err := target - float(pan["s"])
	if absf(err) <= float(_p["ARRIVE_TOL_M"]):
		return 0
	var v := float(line["beltV"])
	if v != 0.0 and (v > 0.0) == (err > 0.0):
		var stop_dist := (v * v) / (2.0 * float(PurblePlaceLogic.CAKE["BELT_SLEW"]))
		if stop_dist >= absf(err):
			return 0  # loslassen — auf die Marke ausrollen
	return 1 if err > 0.0 else -1


## Nächste offene Bauteilstufe der aktuellen Form (Web `nextStage`).
func _next_stage(pan: Dictionary) -> String:
	var spec := (
		_spec if not _spec.is_empty() else {"icing": "none", "topping": "none", "candles": 0}
	)
	if pan["sponge"] == null:
		return "teig"
	if pan["bake"] == null:
		return "oven"
	if str(spec["icing"]) != "none" and pan["icing"] == null:
		return "guss"
	if str(spec["topping"]) != "none" and pan["topping"] == null:
		return "deko"
	var want_candles := maxi(0, int(spec["candles"]) - int(_plan["kerzenShort"]))
	if int(pan["candles"]) < want_candles:
		return "kerzen"
	return "ship"


## Station + Parkziel + Reaktionszeit für eine Stufe (Web `makeCfg`).
func _make_cfg(stage: String) -> Dictionary:
	if stage == "ship":
		var ship_s := float(PurblePlaceLogic.CAKE["SHIP_S"]) + float(_plan["shipPark"])
		return {"stationId": "", "target": ship_s, "react": _react_sec()}
	if stage == "kerzen":
		var kerzen_s := float(PurblePlaceLogic.station("kerzen")["s"]) + float(_plan["kerzenPark"])
		return {"stationId": "kerzen", "target": kerzen_s, "react": _react_sec()}
	var roll: Dictionary = _plan[stage]
	var wrong := bool(roll["wrong"])
	var value := ""
	if stage == "teig":
		value = (
			_wrong_pick(PurblePlaceLogic.SPONGES, str(_spec["sponge"]))
			if wrong
			else str(_spec["sponge"])
		)
	elif stage == "guss":
		var pool: Array = PurblePlaceLogic.ICINGS.slice(0, 3)
		value = _wrong_pick(pool, str(_spec["icing"])) if wrong else str(_spec["icing"])
	else:
		var pool: Array = PurblePlaceLogic.TOPPINGS.slice(0, 3)
		value = _wrong_pick(pool, str(_spec["topping"])) if wrong else str(_spec["topping"])
	var station_id := "%s.%s" % [stage, value]
	var target := float(PurblePlaceLogic.station(station_id)["s"]) + float(roll["park"])
	return {"stationId": station_id, "target": target, "react": float(roll["react"])}


## Eine Form übernehmen und den Fehlerplan EINMAL auswürfeln.
func _adopt_pan(line: Dictionary, pan: Dictionary) -> void:
	_pan_id = int(pan["id"])
	var tickets: Array = line["tickets"]
	if not tickets.is_empty():
		_spec = (tickets[0] as Dictionary)["spec"]
	_plan = _roll_plan()
	_stage = ""
	_phase = "drive"
	_side_spawned = false


## Fehlerplan einer Form. Die Reihenfolge der rng()-Aufrufe ist BINDEND.
func _roll_plan() -> Dictionary:
	var teig := _roll_drop()
	var guss := _roll_drop()
	var deko := _roll_drop()
	var kerzen_short := 1 if _rng.next() < float(_p["CANDLE_SHORT_CHANCE"]) else 0
	var kerzen_park := _park_jitter()
	var oven := {}
	if _rng.next() < float(_p["OVEN_LATE_CHANCE"]):
		oven = {"mode": "late"}
	elif _rng.next() < float(_p["OVEN_EARLY_CHANCE"]):
		oven = {"mode": "early", "exitMeter": 1.2 + _rng.next() * 0.85}
	else:
		oven = {"mode": "green", "exitMeter": float(_p["OVEN_EXIT_METER_SEC"]) + _rng.next() * 0.15}
	var ship_park := (_rng.next() * 2.0 - 1.0) * 0.1
	return {
		"teig": teig,
		"guss": guss,
		"deko": deko,
		"kerzenShort": kerzen_short,
		"kerzenPark": kerzen_park,
		"oven": oven,
		"shipPark": ship_park,
	}


func _roll_drop() -> Dictionary:
	var wrong := _rng.next() < float(_p["WRONG_CHANCE"])
	var park := _park_jitter()
	var react := _react_sec()
	return {"wrong": wrong, "park": park, "react": react}


## Formwahl mit Verwechslungsrisiko.
func _pick_shape(spec: Dictionary) -> String:
	if _rng.next() < float(_p["SHAPE_WRONG_CHANCE"]):
		var pool: Array[String] = []
		for sh: String in PurblePlaceLogic.SHAPES:
			if sh != str(spec["shape"]):
				pool.append(sh)
		return pool[mini(pool.size() - 1, int(floorf(_rng.next() * pool.size())))]
	return str(spec["shape"])


## Irgendein anderer Wert aus `pool` (die griffbereite Nachbardüse).
func _wrong_pick(pool: Array, correct: String) -> String:
	var others: Array[String] = []
	for v: String in pool:
		if v != correct:
			others.append(v)
	return others[mini(others.size() - 1, int(floorf(_rng.next() * others.size())))]


func _react_sec() -> float:
	var lo := float(_p["REACT_MIN_SEC"])
	return lo + _rng.next() * (float(_p["REACT_MAX_SEC"]) - lo)


func _hesitate_sec() -> float:
	var lo := float(_p["HESITATE_MIN_SEC"])
	return lo + _rng.next() * (float(_p["HESITATE_MAX_SEC"]) - lo)


## Parkzittern: meist sorgfältig, mit SLOPPY_CHANCE schlampig (2 rng-Züge).
func _park_jitter() -> float:
	if _rng.next() < float(_p["SLOPPY_CHANCE"]):
		return (_rng.next() * 2.0 - 1.0) * float(_p["SLOPPY_JITTER_M"])
	return (_rng.next() * 2.0 - 1.0) * float(_p["PARK_JITTER_M"])


func _careful_jitter() -> float:
	return (_rng.next() * 2.0 - 1.0) * float(_p["PARK_JITTER_M"])

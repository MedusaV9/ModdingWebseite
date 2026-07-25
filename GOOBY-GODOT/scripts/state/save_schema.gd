extends RefCounted
## Save v5 schema (W1d/STATE) — dict schema, defaults, normalize + the
## modular slice registry.
##
## Key style: camelCase VERBATIM wie im Web-v4-JSON (Sticker-/Counter-/Slot-
## Keys sind ohnehin camelCase; so bleibt die Doc-H-§5.2-Migration maximal
## "verbatim"). meta folgt der Task-Spezifikation:
## meta{v:5(top-level), createdAt, playerName, goobyNickname, charMorphs}.
##
## SLICE-REGISTRY (Update-System): spaetere Teams/Packs melden ADDITIVE
## top-level Slices an, ohne save_schema.gd anzufassen:
##   SaveSchema.register_slice("myPack", default_factory, normalize)
## - default_factory: Callable() -> Dictionary (frische Defaults)
## - normalize (optional): Callable(raw: Variant) -> Dictionary (self-heal)
## Registrierte Slices landen in default_state() und werden bei normalize()
## defensiv normalisiert — genau das Muster der additiven Web-Slices
## (vacation/themePark kamen OHNE SAVE.VERSION-Bump dazu).
##
## Korruptions-Kontrakt (Port der Web-mergeDefaults/F2-Regel): strukturelle
## Typ-Mismatches (Dict-Default trifft Array/Primitiv usw.) machen den Save
## KORRUPT — normalize() liefert ok=false, save_manager.gd sichert + recovert.

const Vacation := preload("res://scripts/logic/vacation.gd")
const Economy := preload("res://scripts/logic/economy.gd")
const Leveling := preload("res://scripts/logic/leveling.gd")

const SCHEMA_VERSION := 5

## Fresh-save starting stats (web SAVE.DEFAULT_STATS verbatim).
const DEFAULT_STATS := {"hunger": 80.0, "energy": 90.0, "hygiene": 85.0, "fun": 70.0}
## Starter fridge (web ECONOMY.STARTER_INVENTORY verbatim).
const STARTER_FOOD := {"carrot": 3, "apple": 1, "cupcake": 1}
## Known radio station ids (web systems/musicRegistry.js STATION_IDS).
const STATION_IDS: Array[String] = ["bordmusik", "gooby-fm", "recap-fm", "game-fm", "alle"]
## Hostile far-future timestamps collapse to <= now + 24 h (web §B1 #5).
const FUTURE_STAMP_SLACK_MS := 86400000
## Funkelpark: bekannte Ride-Ids + Zaehler-Deckel (web systems/themePark.js
## PARK_RIDE_IDS/THEME_PARK.MAX_COUNT — unbekannte Ids werden VERWORFEN).
const PARK_RIDE_IDS: Array[String] = ["coaster", "wheel"]
const PARK_MAX_COUNT := 99999

## Registered additive slices: id -> {"default": Callable, "normalize": Callable}.
static var _extra_slices: Dictionary = {}


## Register an additive top-level slice (see header). Re-registering an id
## replaces the previous registration (packs may hot-update).
static func register_slice(id: String, default_factory: Callable, normalize := Callable()) -> void:
	_extra_slices[id] = {"default": default_factory, "normalize": normalize}


static func unregister_slice(id: String) -> void:
	_extra_slices.erase(id)


static func registered_slice_ids() -> Array:
	return _extra_slices.keys()


## One empty garden plot (web defaultPlot() verbatim).
static func default_plot() -> Dictionary:
	return {
		"crop": null,
		"plantedAt": 0,
		"progressMin": 0,
		"wateredUntil": 0,
		"waterings": 0,
		"fertilized": false,
	}


## The full achievements counter set (web v1–v4 superset, verbatim keys).
static func default_counters() -> Dictionary:
	var counters := {"feeds": 0, "washes": 0, "sleeps": 0, "trips": 0, "tickles": 0}
	counters["petsToday"] = 0
	counters["petsDay"] = ""
	for k in [
		"harvests",
		"plantings",
		"waterings",
		"sells",
		"cures",
		"vetTrips",
		"deliveries",
		"questsDone",
		"photosTaken",
		"nightPlays",
		"medsGiven",
		"balls",
		"nougatGlobs",
		"cakesServed",
		"perfectCakes",
		"surfRuns",
		"surfDistanceM",
		"races",
		"ghostsCaught",
		"rescues",
		"cratesShipped",
		"codesRedeemed",
		"modifierPlays",
		"recapsSeen",
		"radioMinutes",
		"galleryPhotos",
	]:
		counters[k] = 0
	return counters


## Fresh save-state per schema v5. `now_ms` stamps createdAt/lastTickAt.
static func default_state(now_ms: int) -> Dictionary:
	var state := {
		"v": SCHEMA_VERSION,
		"meta":
		{
			"createdAt": now_ms,
			"playerName": "",
			"goobyNickname": "Gooby",
			# charMorphs keys == W1c onboarding editor contract (frozen).
			"charMorphs": {"eyes_apart": 0.0, "eye_scale": 1.0, "ear_len": 1.0, "chubby": 0.0},
			"importedFrom": "",
			"importedAt": 0,
		},
		"gooby":
		{
			"stats": DEFAULT_STATS.duplicate(),
			"sleep": {"sleeping": false, "startedAt": 0, "wakeAt": 0},
			"grumpyUntil": 0,
			"lastTickAt": now_ms,
			"health":
			{"state": "healthy", "junkScore": 0, "neglectMin": 0, "recoverMin": 0, "since": 0},
			"weight": 50.0,
		},
		"economy": Economy.default_slice(),
		# progression: Level 1:1 aus dem Web; XP zaehlt fuer die NEUE Kurve
		# (M2-Rework-Hook — siehe leveling.gd Header).
		"progression": {"level": 1, "xp": 0},
		"inventory":
		{
			"food": STARTER_FOOD.duplicate(),
			"items": {"medicine": 0, "fertilizer": 0},
		},
		# home: Platzhalter-Struktur nach Doc D §1.4 — W2 fuellt rooms/items.
		# movingDay=true markiert den einmaligen "Umzugstag!"-Flow nach Import.
		"home":
		{
			"v": 1,
			"rooms": {},
			"unlockedRooms": ["hall", "living", "kitchen", "bathroom", "bedroom"],
			"storage": [],
			"storageCapacity": 100,
			"movingDay": false,
		},
		"decor": {"wallpaper": {}, "floor": {}},
		"cosmetics":
		{
			"outfits":
			{
				"owned": [],
				"equipped": {"hat": null, "glasses": null, "neck": null, "back": null},
			},
			"fur": {"owned": ["cream"], "equipped": "cream"},
		},
		"stickers": {"unlocked": {}, "seen": {}},
		"garden": {"plotsOwned": 4, "grid": [], "lastTickAt": 0},
		"vacation": Vacation.default_slice(),
		"park":
		{
			"visits": 0,
			"nightVisit": false,
			"rides": {"coaster": 0, "wheel": 0},
			"handsUp": 0,
			"candyBought": 0,
		},
		"minigames":
		{
			"plays": {},
			"legacy":
			{"best": {}, "bestByDiff": {}, "endlessBest": {}, "beaten": {}, "lastPlayDay": {}},
		},
		"achievements": {"unlocked": {}, "counters": default_counters()},
		"daily": {"lastClaimDay": "", "streak": 0},
		"collections": {"entries": {}, "claimedSets": {}},
		"quests": {"completedTotal": 0},
		"quickDelivery": false,
		# radio: v5-Neusaves besitzen KEIN Radio (Doc H §6.1 — IKEA verkauft es;
		# migrierte Web-Saves bekommen Grandfathering in migration_v4.gd).
		"radio":
		{
			"owned": false,
			"station": "bordmusik",
			"playing": false,
			"shuffle": true,
			"replaceContext": true,
			"lastTrack": "",
			"trims": {},
			"recapHeard": {},
		},
		"codes": {"redeemed": {}, "lockUntil": 0, "buffs": {"doubleCoinsUntil": 0}},
		"recap": {"history": []},
		"gallery": {"legacyCount": 0},
		"camera": {"owned": false},
		"easterEggs": {"nougat": {"lastGlobAt": 0, "installed": false}},
		"profile": {"playtimeMin": 0, "distanceM": 0, "photos": 0},
		# settings-VERWEIS: Live-Settings besitzt W1a's AppSettings-Autoload
		# (eigene Datei). `imported` ist die einmalige Adoptions-Payload aus
		# der Migration (AppSettings liest + leert sie beim ersten Boot).
		"settings": {"managedBy": "AppSettings", "imported": {}},
		"onboarding": {"done": false, "whatsNew5Seen": false},
		"migration": {"notes": [], "lost": [], "interruptedVacation": null},
	}
	for _i in 6:
		state["garden"]["grid"].append(default_plot())
	for id: String in _extra_slices.keys():
		var factory: Callable = _extra_slices[id]["default"]
		state[id] = factory.call()
	return state


## Validate/normalize a parsed v5 payload. Returns
## {"ok": bool, "state": Dictionary, "error": String}.
## ok=false == KORRUPT (Struktur-Mismatch/falsche Version) — Recovery-Fall.
static func normalize(raw: Variant, now_ms: int) -> Dictionary:
	if not (raw is Dictionary):
		return _err("save is not an object")
	var v: Variant = raw.get("v")
	if not _is_num(v) or int(v) != float(v) or int(v) < 0:
		return _err("absurd save version %s" % str(v))
	if int(v) > SCHEMA_VERSION:
		return _err("forward version %d > %d" % [int(v), SCHEMA_VERSION])
	if int(v) < SCHEMA_VERSION:
		return _err("version %d needs migration first (migration_v4.gd)" % int(v))
	var merged := merge_defaults(default_state(now_ms), raw, "save")
	if not merged["ok"]:
		return _err(merged["error"])
	var s: Dictionary = merged["value"]
	_clamp_core(s, raw, now_ms)
	for id: String in _extra_slices.keys():
		var cb: Callable = _extra_slices[id]["normalize"]
		if cb.is_valid():
			s[id] = cb.call(s.get(id))
	return {"ok": true, "state": s, "error": ""}


## Deep-merge `src` over `defaults` (port of web mergeDefaults + F2 contract):
## guarantees every schema key exists; structural type mismatches make the
## payload corrupt (ok=false). null never clobbers a structured default.
## Returns {"ok": bool, "value": Variant, "error": String}.
static func merge_defaults(defaults: Dictionary, src: Dictionary, path := "save") -> Dictionary:
	var out := defaults.duplicate(true)
	for k: Variant in src.keys():
		var v: Variant = src[k]
		var d: Variant = defaults.get(k)
		var here := "%s.%s" % [path, str(k)]
		if d is Dictionary:
			if v == null:
				continue
			if not (v is Dictionary):
				return {"ok": false, "value": null, "error": "%s must be an object" % here}
			var sub := merge_defaults(d, v, here)
			if not sub["ok"]:
				return sub
			out[k] = sub["value"]
		elif d is Array:
			if v == null:
				continue
			if not (v is Array):
				return {"ok": false, "value": null, "error": "%s must be an array" % here}
			out[k] = v.duplicate(true)
		else:
			if (
				d != null
				and not (d is Dictionary)
				and not (d is Array)
				and (v is Dictionary or v is Array)
			):
				return {
					"ok": false,
					"value": null,
					"error": "%s must be a %s" % [here, type_string(typeof(d))],
				}
			out[k] = v.duplicate(true) if (v is Dictionary or v is Array) else v
	return {"ok": true, "value": out, "error": ""}


## Leaf clamps (port of the web validate() rules that guard W1d-owned paths).
static func _clamp_core(s: Dictionary, raw: Dictionary, now_ms: int) -> void:
	var gooby: Dictionary = s["gooby"]
	for k: String in DEFAULT_STATS.keys():
		var v: Variant = gooby["stats"].get(k)
		var n := _num_nan(v)
		gooby["stats"][k] = (
			minf(100.0, maxf(0.0, n)) if not (is_nan(n) or is_inf(n)) else DEFAULT_STATS[k]
		)
	var started_at: Variant = gooby["sleep"].get("startedAt")
	var wake_at: Variant = gooby["sleep"].get("wakeAt")
	if not _is_num(started_at) or not _is_num(wake_at):
		gooby["sleep"] = {"sleeping": false, "startedAt": 0, "wakeAt": 0}
	else:
		gooby["sleep"]["sleeping"] = _is_true(gooby["sleep"].get("sleeping"))
	gooby["grumpyUntil"] = maxf(0.0, _num(gooby.get("grumpyUntil")))
	gooby["lastTickAt"] = maxf(0.0, _num(gooby.get("lastTickAt")))
	var w := _num_nan(gooby.get("weight"))
	gooby["weight"] = minf(95.0, maxf(5.0, w)) if not (is_nan(w) or is_inf(w)) else 50.0
	if not gooby["health"].get("state") in ["healthy", "queasy", "sick"]:
		gooby["health"]["state"] = "healthy"

	var econ: Dictionary = s["economy"]
	for key in ["coins", "coinsEarned", "coinsSpent", "dayCoins", "endlessCoins"]:
		econ[key] = maxi(0, int(floor(_num(econ.get(key)))))
	for key in ["dayCoinsDay", "endlessCoinsDay"]:
		if not (econ.get(key) is String):
			econ[key] = ""

	var prog: Dictionary = s["progression"]
	prog["level"] = clampi(int(floor(_num_or(prog.get("level"), 1.0))), 1, Leveling.MAX_LEVEL)
	prog["xp"] = maxf(0.0, _num(prog.get("xp")))

	# inventory maps are taken VERBATIM when present (web E20: consumed food
	# must stay consumed — merge_defaults would resurrect starter items).
	if raw.get("inventory") is Dictionary:
		var raw_inv: Dictionary = raw["inventory"]
		if raw_inv.get("food") is Dictionary:
			s["inventory"]["food"] = raw_inv["food"].duplicate(true)
		if raw_inv.get("items") is Dictionary:
			s["inventory"]["items"] = raw_inv["items"].duplicate(true)

	var grid: Array = s["garden"]["grid"] if s["garden"]["grid"] is Array else []
	var plots: Array = []
	for i in 6:
		var plot: Variant = grid[i] if i < grid.size() else null
		if plot is Dictionary:
			var merged_plot := default_plot()
			merged_plot.merge(plot, true)
			plots.append(merged_plot)
		else:
			plots.append(default_plot())
	s["garden"]["grid"] = plots
	s["garden"]["plotsOwned"] = clampi(int(_num_or(s["garden"].get("plotsOwned"), 4.0)), 0, 6)

	s["vacation"] = Vacation.slice_of(s)
	_clamp_park(s)

	var radio: Dictionary = s["radio"]
	radio["owned"] = _is_true(radio.get("owned"))
	# `is String` zuerst: STATION_IDS ist ein Array[String] — ein Nicht-String
	# in `in` loggt sonst einen Engine-Error (typed-array find).
	if not (radio.get("station") is String and radio["station"] in STATION_IDS):
		radio["station"] = "bordmusik"
	radio["playing"] = _is_true(radio.get("playing"))

	var codes: Dictionary = s["codes"]
	codes["lockUntil"] = _clamp_stamp(codes.get("lockUntil"), now_ms)
	codes["buffs"]["doubleCoinsUntil"] = _clamp_stamp(
		codes["buffs"].get("doubleCoinsUntil"), now_ms
	)
	if codes.get("redeemed") is Dictionary:
		for id: Variant in codes["redeemed"].keys():
			var at := _num(codes["redeemed"][id])
			codes["redeemed"][id] = at if at > 0.0 else 1

	var daily: Dictionary = s["daily"]
	if not (daily.get("lastClaimDay") is String):
		daily["lastClaimDay"] = ""
	daily["streak"] = maxi(0, int(floor(_num(daily.get("streak")))))

	s["gallery"]["legacyCount"] = clampi(int(floor(_num(s["gallery"].get("legacyCount")))), 0, 40)
	s["camera"]["owned"] = _is_true(s["camera"].get("owned"))
	s["quickDelivery"] = _is_true(s.get("quickDelivery"))
	s["onboarding"]["done"] = _is_true(s["onboarding"].get("done"))
	s["onboarding"]["whatsNew5Seen"] = _is_true(s["onboarding"].get("whatsNew5Seen"))

	var morphs: Dictionary = s["meta"]["charMorphs"]
	morphs["eyes_apart"] = clampf(_num(morphs.get("eyes_apart")), -1.0, 1.0)
	morphs["eye_scale"] = clampf(_num_or(morphs.get("eye_scale"), 1.0), 0.7, 1.4)
	morphs["ear_len"] = clampf(_num_or(morphs.get("ear_len"), 1.0), 0.7, 1.4)
	morphs["chubby"] = clampf(_num(morphs.get("chubby")), 0.0, 1.0)
	if not (s["meta"].get("playerName") is String):
		s["meta"]["playerName"] = ""
	if not (s["meta"].get("goobyNickname") is String):
		s["meta"]["goobyNickname"] = "Gooby"


## Funkelpark-Klamps (Port von web themePark.sliceOf, E2-P2-1): Zaehler auf
## 0..PARK_MAX_COUNT, Ride-Ids whitelisted (Cheater-'ufo' fliegt raus),
## nightVisit nur bei echtem bool true.
static func _clamp_park(s: Dictionary) -> void:
	var park: Dictionary = s["park"]
	park["visits"] = _clamp_count(park.get("visits"))
	park["nightVisit"] = _is_true(park.get("nightVisit"))
	var raw_rides: Dictionary = park["rides"] if park.get("rides") is Dictionary else {}
	var rides := {}
	for id: String in PARK_RIDE_IDS:
		rides[id] = _clamp_count(raw_rides.get(id))
	park["rides"] = rides
	park["handsUp"] = _clamp_count(park.get("handsUp"))
	park["candyBought"] = _clamp_count(park.get("candyBought"))


## Ganzzahliger Zaehler 0..PARK_MAX_COUNT (web themePark clampCount).
static func _clamp_count(value: Variant) -> int:
	var n := _num_nan(value)
	if is_nan(n) or is_inf(n):
		return 0
	return clampi(int(floor(n)), 0, PARK_MAX_COUNT)


## Finite ms >= 0, collapsed to <= now + 24 h (hostile far-future stamps).
static func _clamp_stamp(value: Variant, now_ms: int) -> float:
	var n := _num(value)
	if n <= 0.0:
		return 0.0
	return minf(n, float(now_ms) + FUTURE_STAMP_SLACK_MS)


static func _err(message: String) -> Dictionary:
	return {"ok": false, "state": {}, "error": message}


## Web-`=== true`-Aequivalent (E2-P0: `bool == String` ist in GDScript ein
## LAUFZEITFEHLER — nur ein echtes bool true zaehlt, alles andere ist false).
static func _is_true(value: Variant) -> bool:
	return value is bool and value


## Strikt numerisch (KEINE String-Koerzierung) — fuer Versions-/Strukturchecks.
static func _is_num(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


## JS-`Number()`-Nachbildung fuer LEAF-Werte (web validate() koerziert
## lenient: Number("62") → 62 — E2-P2-2). Nicht koerzierbar/nicht endlich
## → NAN (bewusste Abweichung: JS haelt Infinity, wir kollabieren defensiv).
static func _leaf_num(value: Variant) -> float:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value)
	if value is String:
		var text := (value as String).strip_edges()
		if text.is_valid_float():
			var n := text.to_float()
			return n if is_finite(n) else NAN
	return NAN


static func _num(value: Variant) -> float:
	var n := _leaf_num(value)
	return n if not is_nan(n) else 0.0


static func _num_or(value: Variant, fallback: float) -> float:
	var n := _leaf_num(value)
	if not is_nan(n):
		return n if n != 0.0 else fallback
	return fallback


static func _num_nan(value: Variant) -> float:
	return _leaf_num(value)

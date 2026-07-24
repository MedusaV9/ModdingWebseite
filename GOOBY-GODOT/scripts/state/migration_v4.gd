extends RefCounted
## Migration Web-v0..v4 → Godot-v5 (W1d/STATE; Doc H §5.2 Mapping-Tabelle).
##
## migrate_any(raw, now_ms) nimmt einen geparsten Web-Save (v0–v4, z. B. aus
## dem Umzugskoffer oder dem iOS-NSUserDefaults-Leser), spielt die
## GDScript-Nachbildung der Web-Migrationskette (save.js migrations[0..3])
## plus der validate()-Klamps ab und mappt dann v4 → v5.
##
## Mapping-Highlights (Doc H §5.2, bindend):
## - coins verbatim + 250 "Umzugsbonus"; Level 1:1, XP → 0 (M2-Kurven-Rework)
## - Sticker (85 IDs), Outfits (42), Skins (7), Achievements: verbatim
## - furniture.placed (Slot-System) → NICHT aufs freie Grid mappbar: alle
##   owned-Items ins Lager (home.storage) + movingDay-Marker ("Umzugstag!")
## - laufender Urlaub: phase → none + Reisepreis-Erstattung (Restzeit +
##   Details in migration.interruptedVacation dokumentiert)
## - Radio-/Kamera-Grandfathering; modifiers/quests.active verworfen
## - Verlustliste in state.migration.lost, Notizen in state.migration.notes
##
## Fotos (IndexedDB-Blobs) sind NICHT migrierbar — ehrlich kommunizieren
## (Doc H §5.3); der Galerie-Zaehler bleibt als gallery.legacyCount.

const SaveSchema := preload("res://scripts/state/save_schema.gd")
const Vacation := preload("res://scripts/logic/vacation.gd")
const Leveling := preload("res://scripts/logic/leveling.gd")

## Willkommensgeste beim Import (Doc H §5.2 Zeile "coins").
const MOVING_BONUS_COINS := 250

const WEB_VERSION := 4
const UI_SCALE_STOPS: Array = [85, 100, 115, 130]


## Full pipeline: v0–v4 raw dict → normalized v5 state.
## Returns {"ok": bool, "state": Dictionary, "error": String, "report": Dictionary}.
static func migrate_any(raw: Variant, now_ms: int) -> Dictionary:
	if not (raw is Dictionary):
		return _err("save is not an object")
	var v := 0
	var v_raw: Variant = raw.get("v")
	if v_raw != null:
		if not _is_num(v_raw) or float(v_raw) != floor(float(v_raw)) or float(v_raw) < 0.0:
			return _err("absurd save version %s" % str(v_raw))
		v = int(v_raw)
		if v > WEB_VERSION:
			return _err("version %d is not a web save (expected 0..4)" % v)
	var state: Dictionary = raw.duplicate(true)
	# Web migrations chain: every step must advance v (stuck chain = corrupt).
	while v < WEB_VERSION:
		match v:
			0:
				state = _migrate_v0_to_v1(state)
			1:
				state = _migrate_v1_to_v2(state)
			2:
				state = _migrate_v2_to_v3(state)
			3:
				state = _migrate_v3_to_v4(state)
		var next: Variant = state.get("v")
		if not _is_num(next) or int(next) <= v:
			return _err("migration from v%d did not advance" % v)
		v = int(next)
	var validated := _validate_v4(state, now_ms)
	if not validated["ok"]:
		return _err(validated["error"])
	return _map_v4_to_v5(validated["state"], now_ms)


# ── web migrations[0..3] ports ───────────────────────────────────────────────


static func _migrate_v0_to_v1(state: Dictionary) -> Dictionary:
	var out := state.duplicate(true)
	out["v"] = 1
	return out


static func _migrate_v1_to_v2(state: Dictionary) -> Dictionary:
	# New top-level slices ONLY when absent; counters defaults-first;
	# wrong-typed containers stay untouched (validate throws → recovery).
	var out := _spread_defaults_first(_v2_slice_defaults(), state)
	out["v"] = 2
	_merge_counters_defaults_first(out, _v2_counter_defaults())
	if out.get("onboarding") == null or out.get("onboarding") is Dictionary:
		var onboarding: Dictionary = out.get("onboarding", {}) if out.get("onboarding") else {}
		onboarding = onboarding.duplicate(true)
		onboarding["whatsNew2Seen"] = false
		out["onboarding"] = onboarding
	return out


static func _migrate_v2_to_v3(state: Dictionary) -> Dictionary:
	var out := _spread_defaults_first(_v3_slice_defaults(), state)
	out["v"] = 3
	if out.get("settings") == null or out.get("settings") is Dictionary:
		out["settings"] = _spread_defaults_first(
			_v3_settings_defaults(), out.get("settings", {}) if out.get("settings") else {}
		)
	var outfits: Variant = out.get("outfits")
	var equipped_raw: Variant = outfits.get("equipped") if outfits is Dictionary else false
	if outfits is Dictionary and (equipped_raw == null or equipped_raw is Dictionary):
		var equipped: Dictionary = (
			outfits.get("equipped").duplicate(true) if outfits.get("equipped") is Dictionary else {}
		)
		if not equipped.has("back"):
			equipped["back"] = null
		outfits = outfits.duplicate(true)
		outfits["equipped"] = equipped
		out["outfits"] = outfits
	_merge_counters_defaults_first(out, _v3_counter_defaults())
	if out.get("onboarding") == null or out.get("onboarding") is Dictionary:
		var onboarding: Dictionary = out.get("onboarding", {}) if out.get("onboarding") else {}
		onboarding = onboarding.duplicate(true)
		onboarding["whatsNew3Seen"] = false
		out["onboarding"] = onboarding
	return out


static func _migrate_v3_to_v4(state: Dictionary) -> Dictionary:
	var out := _spread_defaults_first(_v4_slice_defaults(), state)
	out["v"] = 4
	if out.get("settings") == null or out.get("settings") is Dictionary:
		out["settings"] = _spread_defaults_first(
			_v4_settings_defaults(), out.get("settings", {}) if out.get("settings") else {}
		)
	if out.get("minigames") is Dictionary:
		out["minigames"] = _spread_defaults_first(_v4_minigame_defaults(), out["minigames"])
	# (web §B1 #3 recap-baseline init is skipped: v5 keeps recap.history only.)
	_merge_counters_defaults_first(out, _v4_counter_defaults())
	if out.get("furniture") is Dictionary:
		var furniture: Dictionary = out["furniture"].duplicate(true)
		if furniture.get("owned") is Array and not furniture["owned"].has("radio"):
			furniture["owned"].append("radio")
		if furniture.get("placed") is Dictionary and not furniture["placed"].has("living:shelf1"):
			furniture["placed"]["living:shelf1"] = "radio"
		out["furniture"] = furniture
	if out.get("onboarding") == null or out.get("onboarding") is Dictionary:
		var onboarding: Dictionary = out.get("onboarding", {}) if out.get("onboarding") else {}
		onboarding = onboarding.duplicate(true)
		onboarding["whatsNew4Seen"] = false
		out["onboarding"] = onboarding
	return out


# ── web validate() port (subset guarding the v5-mapped fields) ───────────────


static func _validate_v4(state: Dictionary, now_ms: int) -> Dictionary:
	var merged := SaveSchema.merge_defaults(_v4_default_state(now_ms), state, "web-save")
	if not merged["ok"]:
		return {"ok": false, "state": {}, "error": merged["error"]}
	var s: Dictionary = merged["value"]
	var default_stats: Dictionary = SaveSchema.DEFAULT_STATS
	for k: String in default_stats.keys():
		var n := _num_nan(s["stats"].get(k))
		s["stats"][k] = (
			minf(100.0, maxf(0.0, n)) if not (is_nan(n) or is_inf(n)) else default_stats[k]
		)
	s["coins"] = maxi(0, int(floor(_num(s.get("coins")))))
	s["xp"] = maxf(0.0, _num(s.get("xp")))
	s["level"] = clampi(int(floor(_num_or(s.get("level"), 1.0))), 1, Leveling.MAX_LEVEL)
	if not _is_num(s["sleep"].get("startedAt")) or not _is_num(s["sleep"].get("wakeAt")):
		s["sleep"] = {"sleeping": false, "startedAt": 0, "wakeAt": 0}
	else:
		s["sleep"]["sleeping"] = s["sleep"].get("sleeping") == true
	# Consumed inventory stays consumed (web E20): verbatim when present.
	if state.get("inventory") is Dictionary:
		s["inventory"] = state["inventory"].duplicate(true)
	var w := _num_nan(s["weight"].get("value"))
	s["weight"]["value"] = minf(95.0, maxf(5.0, w)) if not (is_nan(w) or is_inf(w)) else 50.0
	if not s["health"].get("state") in ["healthy", "queasy", "sick"]:
		s["health"]["state"] = "healthy"
	var plots_raw: Array = s["garden"]["plots"] if s["garden"].get("plots") is Array else []
	var plots: Array = []
	for i in 6:
		var plot: Variant = plots_raw[i] if i < plots_raw.size() else null
		if plot is Dictionary:
			var merged_plot := SaveSchema.default_plot()
			merged_plot.merge(plot, true)
			plots.append(merged_plot)
		else:
			plots.append(SaveSchema.default_plot())
	s["garden"]["plots"] = plots
	# Numeric-tolerant stop lookup: JSON liefert 115.0, JS kennt nur double —
	# Array.has() in Godot ist aber typ-strikt (115.0 not in [115]).
	var ui_scale_raw := _num_nan(s["settings"].get("uiScale"))
	var ui_scale := int(ui_scale_raw) if not is_nan(ui_scale_raw) else -1
	if float(ui_scale) != ui_scale_raw or not UI_SCALE_STOPS.has(ui_scale):
		ui_scale = 100
	s["settings"]["uiScale"] = ui_scale
	var vol_defaults: Dictionary = _v3_settings_defaults()["volumes"]
	for bus: String in vol_defaults.keys():
		var vol: Variant = s["settings"]["volumes"].get(bus)
		s["settings"]["volumes"][bus] = (
			clampi(int(round(float(vol))), 0, 100) if _is_num(vol) else vol_defaults[bus]
		)
	s["settings"]["devUnlocked"] = s["settings"].get("devUnlocked") == true
	# furniture.placed verbatim when present (defaults carry the radio gift).
	var raw_furniture: Variant = state.get("furniture")
	if raw_furniture is Dictionary and raw_furniture.get("placed") is Dictionary:
		s["furniture"]["placed"] = raw_furniture["placed"].duplicate(true)
	var radio: Dictionary = s["radio"]
	if not radio.get("station") in SaveSchema.STATION_IDS:
		radio["station"] = "bordmusik"
	radio["playing"] = radio.get("playing") == true
	if typeof(radio.get("shuffle")) != TYPE_BOOL:
		radio["shuffle"] = true
	if typeof(radio.get("replaceContext")) != TYPE_BOOL:
		radio["replaceContext"] = true
	if not (radio.get("lastTrack") is String):
		radio["lastTrack"] = ""
	var trims := {}
	if radio.get("trims") is Dictionary:
		for id: Variant in radio["trims"].keys():
			var row: Variant = radio["trims"][id]
			if not (row is Dictionary):
				continue
			var vol := _num_nan(row.get("vol"))
			var trim: Dictionary = row.duplicate(true)
			trim["vol"] = clampi(int(round(vol)), 0, 150) if not is_nan(vol) else 100
			trim["on"] = false if row.get("on") == false else true
			trims[id] = trim
	radio["trims"] = trims
	if radio.get("recapHeard") is Dictionary:
		for id: Variant in radio["recapHeard"].keys():
			var at := _num(radio["recapHeard"][id])
			radio["recapHeard"][id] = at if at > 0.0 else 1
	var codes: Dictionary = s["codes"]
	codes["lockUntil"] = _clamp_stamp(codes.get("lockUntil"), now_ms)
	codes["buffs"]["doubleCoinsUntil"] = _clamp_stamp(
		codes["buffs"].get("doubleCoinsUntil"), now_ms
	)
	if codes.get("redeemed") is Dictionary:
		for id: Variant in codes["redeemed"].keys():
			var at := _num(codes["redeemed"][id])
			codes["redeemed"][id] = at if at > 0.0 else 1
	var count := _num_nan(s["gallery"].get("count"))
	s["gallery"]["count"] = clampi(int(floor(count)), 0, 40) if not is_nan(count) else 0
	return {"ok": true, "state": s, "error": ""}


# ── v4 → v5 field mapping (Doc H §5.2) ───────────────────────────────────────


static func _map_v4_to_v5(v4: Dictionary, now_ms: int) -> Dictionary:
	var s := SaveSchema.default_state(now_ms)
	var notes: Array = []
	var lost: Array = []

	s["meta"]["createdAt"] = v4.get("createdAt", now_ms)
	s["meta"]["importedFrom"] = "web-v4"
	s["meta"]["importedAt"] = now_ms

	s["gooby"]["stats"] = v4["stats"].duplicate(true)
	s["gooby"]["sleep"] = v4["sleep"].duplicate(true)
	s["gooby"]["grumpyUntil"] = v4.get("grumpyUntil", 0)
	s["gooby"]["lastTickAt"] = v4.get("lastTickAt", now_ms)
	s["gooby"]["health"] = v4["health"].duplicate(true)
	s["gooby"]["weight"] = v4["weight"]["value"]

	s["economy"]["coins"] = int(_num(v4.get("coins"))) + MOVING_BONUS_COINS
	s["economy"]["coinsEarned"] = int(_num(v4["profile"].get("coinsEarned")))
	s["economy"]["coinsSpent"] = int(_num(v4["profile"].get("coinsSpent")))
	notes.append("coins: +%d Umzugsbonus" % MOVING_BONUS_COINS)

	s["progression"]["level"] = int(_num_or(v4.get("level"), 1.0))
	s["progression"]["xp"] = 0
	lost.append("xp: Rest-XP verschenkt (neue Multiplayer-Kurve, Level bleibt 1:1)")

	s["inventory"]["food"] = v4["inventory"].duplicate(true)
	s["inventory"]["items"] = v4["items"].duplicate(true)

	# Umzugstag: Slot-Placements sind NICHT aufs freie Grid mappbar — alles
	# Owned wandert ins Lager; W2 mappt IDs via legacy_furniture_map.json
	# (bis dahin Identitaets-Mapping) und baut den Umzugskarton-Flow.
	var boxed := 0
	var owned_raw: Variant = v4["furniture"].get("owned")
	var owned: Array = owned_raw if owned_raw is Array else []
	var storage: Array = []
	var counts := {}
	for item: Variant in owned:
		if not (item is String):
			continue
		counts[item] = int(counts.get(item, 0)) + 1
	for item: String in counts.keys():
		storage.append({"item": item, "variant": "default", "count": counts[item]})
		boxed += int(counts[item])
	s["home"]["storage"] = storage
	s["home"]["movingDay"] = true
	lost.append("furniture.placed: Slot-Layout nicht aufs Grid mappbar — Umzugstag-Flow")
	notes.append("furniture: %d Items im Umzugskarton (home.storage)" % boxed)

	s["decor"] = v4["decor"].duplicate(true)
	s["cosmetics"]["outfits"] = v4["outfits"].duplicate(true)
	s["cosmetics"]["fur"] = v4["skins"].duplicate(true)
	s["stickers"] = v4["stickers"].duplicate(true)

	s["garden"]["plotsOwned"] = v4["garden"].get("plotsOwned", 4)
	s["garden"]["grid"] = v4["garden"]["plots"].duplicate(true)
	s["garden"]["lastTickAt"] = v4["garden"].get("lastTickAt", 0)

	# Vacation: trips/visited/archive/postcards verbatim; laufende Reise wird
	# abgebrochen (phase → none) + der Reisepreis erstattet (Doc H §5.2).
	var vac := Vacation.slice_of(v4)
	var interrupted: Variant = null
	if vac["phase"] != Vacation.PHASE_NONE:
		var dest: Variant = Vacation.CATALOG.get(vac["destId"])
		var refund: int = dest["price"] if dest != null else 0
		interrupted = {
			"destId": vac["destId"],
			"phase": vac["phase"],
			"remainingMs": Vacation.remaining_ms({"vacation": vac}, now_ms),
			"refund": refund,
			"postcards": vac["postcards"],
		}
		s["economy"]["coins"] = int(s["economy"]["coins"]) + refund
		notes.append(
			(
				"vacation: laufende Reise (%s) abgebrochen, %d Coins erstattet"
				% [vac["destId"], refund]
			)
		)
		vac["phase"] = Vacation.PHASE_NONE
		vac["destId"] = ""
		vac["bookedAt"] = 0
		vac["returnAt"] = 0
		vac["pickupBy"] = 0
	s["vacation"] = vac
	s["migration"]["interruptedVacation"] = interrupted

	if v4.get("themePark") is Dictionary:
		s["park"] = _spread_defaults_first(s["park"], v4["themePark"])

	s["minigames"]["plays"] = v4["minigames"].get("plays", {}).duplicate(true)
	s["minigames"]["legacy"] = {
		"best": v4["minigames"].get("best", {}).duplicate(true),
		"bestByDiff": v4["minigames"].get("bestByDiff", {}).duplicate(true),
		"endlessBest": v4["minigames"].get("endlessBest", {}).duplicate(true),
		"beaten": v4["minigames"].get("beaten", {}).duplicate(true),
		"lastPlayDay": v4["minigames"].get("lastPlayDay", {}).duplicate(true),
	}
	notes.append("minigames: Bestwerte als Web-Rekorde in minigames.legacy")

	s["achievements"]["unlocked"] = v4["achievements"]["unlocked"].duplicate(true)
	var counters := SaveSchema.default_counters()
	counters.merge(v4["achievements"]["counters"], true)
	s["achievements"]["counters"] = counters

	s["daily"] = v4["daily"].duplicate(true)
	s["collections"] = v4["collections"].duplicate(true)
	s["quests"]["completedTotal"] = v4["quests"].get("completedTotal", 0)
	lost.append("quests.active: neues Quest-System (completedTotal bleibt)")
	s["quickDelivery"] = v4.get("quickDelivery") == true

	s["radio"] = v4["radio"].duplicate(true)
	s["radio"]["owned"] = owned.has("radio")  # Radio-Besitz-Grandfathering (§6.1)
	s["codes"] = v4["codes"].duplicate(true)
	lost.append("modifiers: System wird neu ausgerollt (seed neu)")

	s["recap"]["history"] = (
		v4["recap"].get("history", []).duplicate(true)
		if v4["recap"].get("history") is Array
		else []
	)
	lost.append("recap.baseline: wird nach dem Import neu gesnapshottet")

	s["gallery"]["legacyCount"] = v4["gallery"].get("count", 0)
	var photos := _num(v4["profile"].get("photos"))
	s["camera"]["owned"] = _num(v4["gallery"].get("count")) > 0.0 or photos > 0.0
	lost.append("photos: IndexedDB-Blobs nicht migrierbar — Galerie startet leer (Zaehler bleibt)")

	s["easterEggs"]["nougat"] = v4["nougat"].duplicate(true)

	s["profile"]["playtimeMin"] = v4["profile"].get("playtimeMin", 0)
	s["profile"]["distanceM"] = v4["profile"].get("distanceM", 0)
	s["profile"]["photos"] = v4["profile"].get("photos", 0)

	var settings: Dictionary = v4["settings"]
	s["settings"]["imported"] = {
		"lang": settings.get("lang", "auto"),
		"haptics": settings.get("haptics", true),
		"notifications": settings.get("notifications", "unasked"),
		"volumes": settings.get("volumes", {}).duplicate(true),
		"gyro": settings.get("gyro") == true,
		"controls": settings.get("controls", {}).duplicate(true),
		"devUnlocked": settings.get("devUnlocked") == true,
		"uiScale": settings.get("uiScale", 100),
		"sfxMuted": settings.get("sfx") == false,
		"musicMuted": settings.get("music") == false,
	}
	lost.append("settings.goobyWeltQuality: Gooby-Welt entfernt (Doc H §A)")

	s["onboarding"]["done"] = v4["onboarding"].get("done") == true
	s["onboarding"]["whatsNew5Seen"] = false

	s["migration"]["notes"] = notes
	s["migration"]["lost"] = lost

	var normalized := SaveSchema.normalize(s, now_ms)
	if not normalized["ok"]:
		return _err("mapped state failed normalize: %s" % normalized["error"])
	var report := {
		"importedFrom": "web-v4",
		"level": s["progression"]["level"],
		"coins": s["economy"]["coins"],
		"stickers": s["stickers"]["unlocked"].size(),
		"outfits": s["cosmetics"]["outfits"]["owned"].size(),
		"furnitureBoxed": boxed,
		"interruptedVacation": interrupted,
	}
	return {"ok": true, "state": normalized["state"], "error": "", "report": report}


# ── web slice-default factories (exact §B1/§B2 values) ───────────────────────


static func _v2_slice_defaults() -> Dictionary:
	var plots: Array = []
	for _i in 6:
		plots.append(SaveSchema.default_plot())
	return {
		"garden": {"plotsOwned": 4, "plots": plots, "lastTickAt": 0},
		"health":
		{"state": "healthy", "junkScore": 0, "neglectMin": 0, "recoverMin": 0, "since": 0},
		"weight": {"value": 50},
		"quests": {"day": "", "active": [], "rerolledDay": "", "completedTotal": 0},
		"collections": {"entries": {}, "claimedSets": {}},
		"skins": {"owned": ["cream"], "equipped": "cream"},
		"items": {"medicine": 0, "fertilizer": 0},
		"profile":
		{"playtimeMin": 0, "coinsEarned": 0, "coinsSpent": 0, "distanceM": 0, "photos": 0},
	}


static func _v2_counter_defaults() -> Dictionary:
	var counters := {}
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
	]:
		counters[k] = 0
	return counters


static func _v3_slice_defaults() -> Dictionary:
	return {
		"stickers": {"unlocked": {}, "seen": {}},
		"nougat": {"lastGlobAt": 0, "installed": false},
	}


static func _v3_settings_defaults() -> Dictionary:
	return {
		"uiScale": 100,
		"volumes": {"master": 80, "sfx": 100, "music": 70, "voice": 100, "ambience": 80},
		"devUnlocked": false,
	}


static func _v3_counter_defaults() -> Dictionary:
	var counters := {}
	for k in [
		"nougatGlobs",
		"cakesServed",
		"perfectCakes",
		"surfRuns",
		"surfDistanceM",
		"races",
		"ghostsCaught",
		"rescues",
		"cratesShipped",
	]:
		counters[k] = 0
	return counters


static func _v4_slice_defaults() -> Dictionary:
	return {
		"radio":
		{
			"station": "bordmusik",
			"playing": false,
			"shuffle": true,
			"replaceContext": true,
			"lastTrack": "",
			"trims": {},
			"recapHeard": {},
		},
		"codes": {"redeemed": {}, "lockUntil": 0, "buffs": {"doubleCoinsUntil": 0}},
		"modifiers":
		{
			"nextAt": 0,
			"seed": 0,
			"current": null,
			"lastGameId": "",
			"dayCoins": 0,
			"dayCoinsDay": "",
		},
		"recap":
		{
			"lastRecapLevel": 0,
			"baseline": {},
			"baselineAt": 0,
			"pendingLevel": 0,
			"history": [],
		},
		"gallery": {"count": 0, "lastAddedAt": 0, "hintShown": false},
	}


static func _v4_settings_defaults() -> Dictionary:
	return {
		"gyro": false,
		"controls": {"invertX": false, "invertY": false},
		"goobyWeltQuality": "high",
	}


static func _v4_minigame_defaults() -> Dictionary:
	return {"difficulty": {}, "beaten": {}, "bestByDiff": {}, "endlessBest": {}}


static func _v4_counter_defaults() -> Dictionary:
	var counters := {}
	for k in ["codesRedeemed", "modifierPlays", "recapsSeen", "radioMinutes", "galleryPhotos"]:
		counters[k] = 0
	return counters


## Web defaultState() port (schema v4) — merge base for _validate_v4.
static func _v4_default_state(now_ms: int) -> Dictionary:
	var counters := {"feeds": 0, "washes": 0, "sleeps": 0, "trips": 0, "tickles": 0}
	counters["petsToday"] = 0
	counters["petsDay"] = ""
	counters.merge(_v2_counter_defaults(), true)
	counters.merge(_v3_counter_defaults(), true)
	counters.merge(_v4_counter_defaults(), true)
	var minigames := {"best": {}, "plays": {}, "lastPlayDay": {}}
	minigames.merge(_v4_minigame_defaults(), true)
	var settings := {
		"lang": "auto",
		"sfx": true,
		"music": true,
		"haptics": true,
		"notifications": "unasked",
	}
	settings.merge(_v3_settings_defaults(), true)
	settings.merge(_v4_settings_defaults(), true)
	var state := {
		"v": WEB_VERSION,
		"createdAt": now_ms,
		"lastTickAt": now_ms,
		"stats": SaveSchema.DEFAULT_STATS.duplicate(),
		"sleep": {"sleeping": false, "startedAt": 0, "wakeAt": 0},
		"grumpyUntil": 0,
		"coins": 100,
		"xp": 0,
		"level": 1,
		"inventory": SaveSchema.STARTER_FOOD.duplicate(),
		"furniture": {"owned": ["radio"], "placed": {"living:shelf1": "radio"}},
		"decor": {"wallpaper": {}, "floor": {}},
		"outfits":
		{
			"owned": [],
			"equipped": {"hat": null, "glasses": null, "neck": null, "back": null},
		},
		"minigames": minigames,
		"achievements": {"unlocked": {}, "counters": counters},
		"daily": {"lastClaimDay": "", "streak": 0},
		"quickDelivery": false,
		"settings": settings,
		"onboarding":
		{
			"done": false,
			"step": 0,
			"whatsNew2Seen": true,
			"whatsNew3Seen": true,
			"whatsNew4Seen": true,
		},
	}
	state.merge(_v2_slice_defaults(), true)
	state.merge(_v3_slice_defaults(), true)
	state.merge(_v4_slice_defaults(), true)
	return state


# ── helpers ──────────────────────────────────────────────────────────────────


## {…defaults, …state}: keys from `state` win; missing keys get defaults.
static func _spread_defaults_first(defaults: Dictionary, state: Dictionary) -> Dictionary:
	var out := defaults.duplicate(true)
	for k: Variant in state.keys():
		var v: Variant = state[k]
		out[k] = v.duplicate(true) if (v is Dictionary or v is Array) else v
	return out


## Counters merged defaults-first (existing values win) — guarded like the
## web migrations: wrong-typed containers are left for validate/recovery.
static func _merge_counters_defaults_first(out: Dictionary, defaults: Dictionary) -> void:
	var achievements: Variant = out.get("achievements")
	if not (achievements is Dictionary):
		return
	var counters: Variant = achievements.get("counters")
	if counters == null or counters is Dictionary:
		var merged := defaults.duplicate(true)
		if counters is Dictionary:
			merged.merge(counters, true)
		achievements = achievements.duplicate(true)
		achievements["counters"] = merged
		out["achievements"] = achievements


static func _clamp_stamp(value: Variant, now_ms: int) -> float:
	var n := _num(value)
	if n <= 0.0:
		return 0.0
	return minf(n, float(now_ms) + SaveSchema.FUTURE_STAMP_SLACK_MS)


static func _err(message: String) -> Dictionary:
	return {"ok": false, "state": {}, "error": message, "report": {}}


static func _is_num(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _num(value: Variant) -> float:
	return float(value) if _is_num(value) else 0.0


static func _num_or(value: Variant, fallback: float) -> float:
	if _is_num(value):
		var n := float(value)
		return n if n != 0.0 else fallback
	return fallback


static func _num_nan(value: Variant) -> float:
	return float(value) if _is_num(value) else NAN

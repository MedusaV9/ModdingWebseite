extends TestCase
## FB-6/SEELE: Erinnerungen kommen NUR aus echten Save-Daten (DoD). Leerer
## oder kaputter State liefert NIE eine Erinnerung; Cooldown und roll-Auswahl
## sind deterministisch.

const SaveSchema := preload("res://scripts/state/save_schema.gd")

const MS_D := 86_400_000


func test_leerer_state_keine_erinnerungen() -> void:
	assert_eq(SoulMemories.candidates({}).size(), 0, "leer = nichts")
	var frisch := SaveSchema.default_state(100 * MS_D)
	assert_eq(SoulMemories.candidates(frisch).size(), 0, "frischer Save = nichts erlebt")


func test_kaputter_state_crasht_nicht() -> void:
	var kaputt := {
		"minigames": "quatsch",
		"vacation": {"visited": "auch quatsch"},
		"achievements": {"counters": {"tickles": "NaN"}},
		"daily": {"streak": null},
	}
	assert_eq(SoulMemories.candidates(kaputt).size(), 0, "Müll-Typen = still, kein Crash")


func test_minigame_rekord_aus_echten_daten() -> void:
	var state := {"minigames": {"legacy": {"best": {"minigolf": 42, "sprint": 99}}}}
	var out := SoulMemories.candidates(state)
	assert_eq(out.size(), 1, "genau eine Rekord-Erinnerung")
	assert_eq(str(out[0]["id"]), "rekord_sprint", "höchster Score gewinnt")
	assert_eq(int(out[0]["args"]["punkte"]), 99, "echter Punktestand im Text")
	# Score 0 zählt nicht als Rekord.
	var nix := SoulMemories.candidates({"minigames": {"legacy": {"best": {"golf": 0}}}})
	assert_eq(nix.size(), 0, "Score 0 = keine Erinnerung")


func test_urlaub_nur_wenn_wirklich_besucht() -> void:
	var state := {"vacation": {"visited": {"beach": 1}}}
	var out := SoulMemories.candidates(state)
	assert_eq(out.size(), 1, "eine Urlaubs-Erinnerung")
	assert_eq(str(out[0]["id"]), "urlaub_beach", "besuchtes Ziel")
	assert_eq(
		SoulMemories.candidates({"vacation": {"visited": {}}}).size(), 0, "nie verreist = still"
	)


func test_zaehler_schwellen() -> void:
	var wenig := {"achievements": {"counters": {"tickles": SoulMemories.MIN_TICKLES - 1}}}
	assert_eq(SoulMemories.candidates(wenig).size(), 0, "unter Schwelle still")
	var genug := {"achievements": {"counters": {"tickles": SoulMemories.MIN_TICKLES}}}
	var out := SoulMemories.candidates(genug)
	assert_eq(out.size(), 1, "ab Schwelle eine Erinnerung")
	assert_eq(str(out[0]["id"]), "kitzeln", "Kitzel-Erinnerung")


func test_streak_und_spielzeit() -> void:
	var state := {
		"daily": {"streak": 5},
		"profile": {"playtimeMin": SoulMemories.MIN_PLAYTIME_MIN},
		"park": {"visits": 2},
	}
	var out := SoulMemories.candidates(state)
	assert_eq(out.size(), 3, "Streak + Funkelpark + Spielzeit")
	assert_eq(str(out[0]["id"]), "streak", "stabile Reihenfolge (deterministisch)")
	assert_eq(int(out[2]["args"]["stunden"]), 10, "600 min = 10 h")


func test_pick_cooldown_und_roll() -> void:
	var kandidaten: Array[Dictionary] = [
		{"id": "a", "text_key": "k.a", "args": {}},
		{"id": "b", "text_key": "k.b", "args": {}},
	]
	var now := 100 * MS_D
	assert_eq(str(SoulMemories.pick(kandidaten, {}, now, 0.0)["id"]), "a", "roll 0 = erster")
	assert_eq(str(SoulMemories.pick(kandidaten, {}, now, 0.99)["id"]), "b", "roll hoch = letzter")
	# Kürzlich gezeigt → gefiltert; nach 3 Tagen wieder erlaubt.
	var shown := {"a": now - MS_D}
	assert_eq(str(SoulMemories.pick(kandidaten, shown, now, 0.0)["id"]), "b", "a im Cooldown")
	var shown_alt := {"a": now - SoulMemories.MEMORY_COOLDOWN_MS}
	assert_eq(str(SoulMemories.pick(kandidaten, shown_alt, now, 0.0)["id"]), "a", "Cooldown vorbei")
	# Alles im Cooldown → lieber Stille als Wiederholung.
	var alle := {"a": now - MS_D, "b": now - MS_D}
	assert_true(SoulMemories.pick(kandidaten, alle, now, 0.5).is_empty(), "alle frisch = {}")


func test_slice_normalisierung_selbstheilend() -> void:
	var kaputt := {
		"firstMetAt": "quatsch",
		"lastVisitAt": -5,
		"playerBirthday": {"month": 13, "day": 40},
		"celebrated": "kein dict",
		"ambient": {"day": 3, "count": "x", "lastAt": null},
		"totalMoments": 7,
	}
	var heil := SoulState.normalize_slice(kaputt)
	assert_eq(int(heil["firstMetAt"]), 0, "String-Zeit fällt auf 0")
	assert_eq(int(heil["lastVisitAt"]), 0, "negative Zeit geklemmt")
	assert_eq(heil["playerBirthday"], {"month": 0, "day": 0}, "Monat 13 = ungesetzt")
	assert_eq(heil["celebrated"], {}, "kaputte Map = leer")
	assert_eq(int(heil["ambient"]["count"]), 0, "Bremse selbstheilend")
	assert_eq(int(heil["totalMoments"]), 7, "gute Werte bleiben")
	var echte := SoulState.normalize_slice(
		{"playerBirthday": {"month": 3, "day": 14}, "foodGiven": {"apple": 2}}
	)
	assert_eq(echte["playerBirthday"], {"month": 3, "day": 14}, "gültiger Geburtstag bleibt")
	assert_eq(int(echte["foodGiven"]["apple"]), 2, "Fütterungs-Zähler bleibt")

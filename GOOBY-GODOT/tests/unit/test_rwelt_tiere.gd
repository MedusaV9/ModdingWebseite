extends TestCase
## RW-1 — Wildtier-Verhalten + Budget: Tageszeit-/Wetterfenster, Flucht
## vor dem Reiter, Fuchs-Neugier, Heimattreue kleiner Gruppen und das
## „Leben reduziert“-Budget. PURE Simulation ohne Szene.


func test_budget_respektiert_leben_reduziert() -> void:
	var voll := RanchWildLogik.budget(false)
	var reduziert := RanchWildLogik.budget(true)
	for art: String in ["reh", "hase", "ente", "wildpferd"]:
		assert_true(int(voll[art]) >= 2, "%s: Gruppe im Vollmodus" % art)
		assert_true(int(reduziert[art]) < int(voll[art]), "%s: reduziert kleiner" % art)
		assert_true(int(reduziert[art]) >= 1, "%s: nie ganz leer" % art)
	assert_eq(int(reduziert["schmetterling"]), 0, "Schwärme aus bei Leben reduziert")
	assert_eq(int(reduziert["vogel"]), 0, "Vogelschwarm aus bei Leben reduziert")
	assert_true(int(voll["gluehwuermchen"]) > 0, "Glühwürmchen im Vollmodus")


func test_aktivfenster_tageszeit() -> void:
	assert_true(RanchWildLogik.aktiv("fuchs", 23.0, "sonne"), "Fuchs nachts")
	assert_false(RanchWildLogik.aktiv("fuchs", 12.0, "sonne"), "Fuchs nicht mittags")
	assert_true(RanchWildLogik.aktiv("reh", 6.5, "sonne"), "Reh im Morgengrauen")
	assert_false(RanchWildLogik.aktiv("reh", 13.0, "sonne"), "Reh döst mittags")
	assert_true(RanchWildLogik.aktiv("gluehwuermchen", 22.0, "sonne"), "Glühwürmchen nachts")
	assert_false(RanchWildLogik.aktiv("gluehwuermchen", 12.0, "sonne"), "nicht am Tag")
	assert_true(RanchWildLogik.aktiv("ente", 3.0, "regen"), "Enten immer")


func test_aktivfenster_wetter() -> void:
	assert_false(RanchWildLogik.aktiv("reh", 6.5, "regen"), "Reh versteckt sich im Regen")
	assert_false(RanchWildLogik.aktiv("hase", 10.0, "gewitter"), "Hase nicht im Gewitter")
	assert_true(RanchWildLogik.aktiv("schmetterling", 12.0, "sonne"), "Schmetterling bei Sonne")
	assert_false(RanchWildLogik.aktiv("schmetterling", 12.0, "regen"), "nicht im Regen")
	assert_false(RanchWildLogik.aktiv("vogel", 12.0, "gewitter"), "Vögel nicht im Gewitter")
	assert_false(RanchWildLogik.aktiv("gluehwuermchen", 22.0, "regen"), "Glühwürmchen trocken")


func test_reh_flieht_vor_dem_reiter() -> void:
	var tier := RanchWildLogik.neues_tier("reh", Vector2(100.0, 100.0))
	tier = RanchWildLogik.schritt(tier, 0.1, Vector2(110.0, 100.0), 0.3)
	assert_eq(str(tier["zustand"]), "flucht", "Reiter bei 10 m → Flucht")
	var start: Vector2 = tier["pos"]
	for _i in 30:
		tier = RanchWildLogik.schritt(tier, 0.1, Vector2(110.0, 100.0), 0.3)
	var jetzt: Vector2 = tier["pos"]
	assert_true(
		jetzt.distance_to(Vector2(110.0, 100.0)) > start.distance_to(Vector2(110.0, 100.0)),
		"Reh vergrößert den Abstand"
	)


func test_fuchs_ist_neugierig_aber_flieht_nah() -> void:
	var tier := RanchWildLogik.neues_tier("fuchs", Vector2.ZERO)
	tier = RanchWildLogik.schritt(tier, 0.1, Vector2(25.0, 0.0), 0.3)
	assert_eq(str(tier["zustand"]), "neugier", "25 m → Neugier")
	var vorher: Vector2 = tier["pos"]
	for _i in 20:
		tier = RanchWildLogik.schritt(tier, 0.1, Vector2(25.0, 0.0), 0.3)
	var pos: Vector2 = tier["pos"]
	assert_true(
		pos.distance_to(Vector2(25.0, 0.0)) < vorher.distance_to(Vector2(25.0, 0.0)),
		"Fuchs kommt näher"
	)
	tier = RanchWildLogik.schritt(tier, 0.1, pos + Vector2(5.0, 0.0), 0.3)
	assert_eq(str(tier["zustand"]), "flucht", "zu nah → Flucht")


func test_ohne_reiter_frisst_wandert_und_ruht() -> void:
	var weit := Vector2(9999.0, 9999.0)
	var tier := RanchWildLogik.neues_tier("hase", Vector2(50.0, -20.0))
	var zustaende: Array[String] = []
	var roll := 0.05
	for _i in 400:
		tier["timer"] = minf(float(tier["timer"]), 0.05)
		tier = RanchWildLogik.schritt(tier, 0.1, weit, roll)
		roll = fmod(roll + 0.173, 1.0)
		var zustand := str(tier["zustand"])
		if not zustaende.has(zustand):
			zustaende.append(zustand)
	for erwartet: String in ["fressen", "wandern", "ruhen", "trinken"]:
		assert_true(zustaende.has(erwartet), "Zustand %s kommt vor" % erwartet)


func test_gruppe_bleibt_in_heimatnaehe() -> void:
	var heim := Vector2(-590.0, 200.0)
	var tier := RanchWildLogik.neues_tier("wildpferd", heim)
	var reiter := heim + Vector2(20.0, 0.0)
	for i in 600:
		# Reiter verfolgt das Tier — trotzdem bleibt es im Heimat-Umkreis.
		tier = RanchWildLogik.schritt(tier, 0.1, reiter, fmod(float(i) * 0.31, 1.0))
		reiter = (tier["pos"] as Vector2) + Vector2(15.0, 5.0)
	var radius := float(RanchWildLogik.ARTEN["wildpferd"]["heim_radius"]) * 1.4
	assert_true(
		(tier["pos"] as Vector2).distance_to(heim) <= radius + 1.0,
		"Wildpferd bleibt bei der Weide (%.0f m)" % (tier["pos"] as Vector2).distance_to(heim)
	)


func test_laeuft_meldet_bewegung() -> void:
	var tier := RanchWildLogik.neues_tier("reh", Vector2.ZERO)
	assert_false(RanchWildLogik.laeuft(tier), "frisch gespawnt = steht")
	tier["ziel"] = Vector2(10.0, 0.0)
	assert_true(RanchWildLogik.laeuft(tier), "mit Ziel = läuft")

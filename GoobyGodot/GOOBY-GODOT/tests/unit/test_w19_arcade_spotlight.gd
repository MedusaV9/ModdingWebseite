extends TestCase
## W19 Arcade-Spotlight „Spiel des Tages“ — Wächter: deterministische
## Tages-Auswahl (injizierter Tag, nie OS-Uhr), Keine-Wiederholung an
## Folgetagen, nur öffenbare Spiele im Pool, Bonus genau EINMAL pro
## Lokaltag über den Award-Pfad, DE/EN-Parität der neuen
## mg.spotlight.*-Keys und das Kachel-Badge in quer UND hochkant.

const SaveSchema := preload("res://scripts/state/save_schema.gd")

const NOW_MS := 1768478400000
## Fixture-Pool (ids absichtlich unsortiert — pool_ids muss sortieren).
const POOL: Array[Dictionary] = [
	{"id": "teaParty"},
	{"id": "carrotCatch"},
	{"id": "gvz"},
	{"id": "bubblePop"},
	{"id": "bunnyHop"},
]
const COIN_TABLE := {"divisor": 4, "min": 4, "max": 26}


## Testhilfe: "YYYY-MM-DD" + n Tage (Mittags-Trick wie DailyBonus.prev_day).
func _tag_plus(day: String, plus: int) -> String:
	var parts := day.split("-")
	var unix := (
		(
			Time
			. get_unix_time_from_datetime_dict(
				{
					"year": int(parts[0]),
					"month": int(parts[1]),
					"day": int(parts[2]),
					"hour": 12,
					"minute": 0,
					"second": 0,
				}
			)
		)
		+ plus * 86400
	)
	var d := Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


func test_auswahl_ist_deterministisch_pro_tag() -> void:
	var pool := ArcadeSpotlight.pool_ids(POOL)
	assert_eq(pool.size(), 5, "Fixture-Pool hat 5 öffenbare Spiele")
	assert_eq(pool[0], "bubblePop", "Pool ist alphabetisch sortiert")
	for offset in [0, 1, 7, 31, 365]:
		var day := _tag_plus("2026-03-05", offset)
		var a := ArcadeSpotlight.spotlight_id(POOL, day)
		var b := ArcadeSpotlight.spotlight_id(POOL, day)
		assert_eq(a, b, "gleicher Tag → gleiche Auswahl (%s)" % day)
		assert_true(pool.has(a), "Auswahl liegt im Pool (%s → %s)" % [day, a])


func test_keine_wiederholung_an_zwei_folgetagen() -> void:
	var day := "2026-01-01"
	var vorher := ArcadeSpotlight.spotlight_id(POOL, day)
	for _i in 200:
		day = _tag_plus(day, 1)
		var heute := ArcadeSpotlight.spotlight_id(POOL, day)
		assert_ne(heute, vorher, "nie dasselbe Spiel an 2 Folgetagen (%s)" % day)
		vorher = heute
	# Härtetest n=2: die Kette MUSS strikt alternieren.
	var duo: Array[Dictionary] = [{"id": "teaParty"}, {"id": "gvz"}]
	day = "2026-01-01"
	vorher = ArcadeSpotlight.spotlight_id(duo, day)
	for _i in 30:
		day = _tag_plus(day, 1)
		var heute := ArcadeSpotlight.spotlight_id(duo, day)
		assert_ne(heute, vorher, "n=2 alterniert strikt (%s)" % day)
		vorher = heute


func test_faire_rotation_alle_spiele_kommen_dran() -> void:
	var gesehen := {}
	for offset in 60:
		gesehen[ArcadeSpotlight.spotlight_id(POOL, _tag_plus("2026-03-01", offset))] = true
	for id in ArcadeSpotlight.pool_ids(POOL):
		assert_true(gesehen.has(id), "über 60 Tage kommt jedes Spiel dran (fehlt: %s)" % id)


func test_pool_nur_oeffenbare_spiele() -> void:
	var games: Array[Dictionary] = [
		{"id": "teaParty"},
		{"id": "geheim", "coming_soon": true},
		{"id": "gvz"},
	]
	var pool := ArcadeSpotlight.pool_ids(games)
	assert_false(pool.has("geheim"), "„Bald!“-Kacheln fliegen aus dem Pool")
	var day := "2026-01-01"
	for _i in 120:
		day = _tag_plus(day, 1)
		assert_ne(ArcadeSpotlight.spotlight_id(games, day), "geheim", "nie gesperrt (%s)" % day)
	# Randfälle: leer → ""; kaputtes Datum → ""; n=1 → immer dasselbe Spiel
	# (Keine-Wiederholung ist dann logisch unmöglich — dokumentierte Ausnahme).
	assert_eq(ArcadeSpotlight.spotlight_id([], "2026-03-05"), "", "leerer Pool → leer")
	assert_eq(ArcadeSpotlight.spotlight_id(POOL, "quatsch"), "", "kaputtes Datum → leer")
	var solo: Array[Dictionary] = [{"id": "teaParty"}]
	assert_eq(ArcadeSpotlight.spotlight_id(solo, "2026-03-05"), "teaParty", "n=1 Tag A")
	assert_eq(ArcadeSpotlight.spotlight_id(solo, "2026-03-06"), "teaParty", "n=1 Tag B")


func test_bonus_genau_einmal_pro_tag() -> void:
	var state := SaveSchema.default_state(NOW_MS)
	var day := "2026-03-05"
	var spot := ArcadeSpotlight.spotlight_id(POOL, day)
	assert_true(ArcadeSpotlight.bonus_verfuegbar(state, day), "frischer Save → Bonus offen")
	# Falsches Spiel zuerst: kein Bonus, Anspruch bleibt UNVERBRAUCHT.
	var anderes := ""
	for id in ArcadeSpotlight.pool_ids(POOL):
		if id != spot:
			anderes = id
			break
	assert_eq(ArcadeSpotlight.beanspruche_bonus(state, anderes, 40, day, POOL), 0, "falsches Spiel")
	assert_true(ArcadeSpotlight.bonus_verfuegbar(state, day), "Fehlversuch verbraucht nichts")
	# 0 gezahlte Münzen (Tages-Cap): kein Bonus, Anspruch bleibt offen.
	assert_eq(ArcadeSpotlight.beanspruche_bonus(state, spot, 0, day, POOL), 0, "0 Basis → 0")
	assert_true(ArcadeSpotlight.bonus_verfuegbar(state, day), "0-Basis verbraucht nichts")
	# Der echte Anspruch: +50 % auf die Basis, danach für HEUTE gesperrt.
	assert_eq(ArcadeSpotlight.beanspruche_bonus(state, spot, 40, day, POOL), 20, "+50 % von 40")
	assert_eq(str(state["minigames"][ArcadeSpotlight.MARKER_KEY]), day, "Marker im Save")
	assert_false(ArcadeSpotlight.bonus_verfuegbar(state, day), "heute eingelöst")
	assert_eq(ArcadeSpotlight.beanspruche_bonus(state, spot, 40, day, POOL), 0, "2. Mal → 0")
	# Am Folgetag zählt der Anspruch neu (Spotlight wechselt garantiert).
	var morgen := _tag_plus(day, 1)
	var spot_morgen := ArcadeSpotlight.spotlight_id(POOL, morgen)
	assert_ne(spot_morgen, spot, "Folgetag hat ein anderes Spotlight")
	assert_eq(
		ArcadeSpotlight.beanspruche_bonus(state, spot_morgen, 40, morgen, POOL),
		20,
		"Folgetag zahlt wieder"
	)


func test_award_pfad_bucht_spotlight_bonus_einmal() -> void:
	var day := "2026-03-05"
	var spot := ArcadeSpotlight.spotlight_id(MinigameRegistry.all_games(), day)
	assert_true(not spot.is_empty(), "echte Registry liefert ein Spotlight")
	var meta := {"id": spot, "coin_table": COIN_TABLE, "target": 999}
	var state := SaveSchema.default_state(NOW_MS)
	var vorher := int(state["economy"]["coins"])
	# Score 60 → Basis 15, Tages-×2 (erstes Spiel) → 30 gezahlt → Bonus 15.
	var b1 := MinigameAward.award(state, meta, 60, "normal", day)
	assert_eq(int(b1["coins"]), 30, "reguläre Auszahlung (Basis ×2)")
	assert_eq(int(b1["spotlightBonusCoins"]), 15, "+50 % auf die Auszahlung")
	assert_eq(str(state["minigames"][ArcadeSpotlight.MARKER_KEY]), day, "Marker verankert")
	var erwartet := vorher + 30 + 15 + int(b1["coinsFromLevels"])
	assert_eq(int(state["economy"]["coins"]), erwartet, "Bonus wirklich gebucht")
	# Zweite Runde am selben Tag: kein zweiter Spotlight-Bonus.
	var b2 := MinigameAward.award(state, meta, 60, "normal", day)
	assert_eq(int(b2["spotlightBonusCoins"]), 0, "genau einmal pro Tag")
	# Ein NICHT-Spotlight-Spiel bekommt nie den Bonus.
	var anderes := ""
	for game: Dictionary in MinigameRegistry.all_games():
		if str(game.get("id", "")) != spot and not bool(game.get("coming_soon", false)):
			anderes = str(game["id"])
			break
	var fremd_state := SaveSchema.default_state(NOW_MS)
	var b3 := MinigameAward.award(
		fremd_state, {"id": anderes, "coin_table": COIN_TABLE, "target": 999}, 60, "normal", day
	)
	assert_eq(int(b3["spotlightBonusCoins"]), 0, "kein Bonus für %s" % anderes)
	assert_true(ArcadeSpotlight.bonus_verfuegbar(fremd_state, day), "Anspruch bleibt offen")


func test_de_en_paritaet_der_spotlight_keys() -> void:
	for locale in ["de", "en"]:
		var table := I18nService.table(locale)
		for key in [
			"mg.spotlight.badge",
			"mg.spotlight.pregame.aktiv",
			"mg.spotlight.pregame.eingeloest",
			"mg.spotlight.results.bonus",
		]:
			assert_true(table.has(key), "%s fehlt in %s" % [key, locale])


func test_arcade_kachel_traegt_spotlight_badge_in_beiden_formaten() -> void:
	var gs := tree.root.get_node_or_null("/root/GameState")
	assert_true(gs != null, "GameState-Autoload vorhanden")
	if gs == null:
		return
	gs.clock.pin(NOW_MS)
	var expected: String = ArcadeSpotlight.spotlight_id(
		MinigameRegistry.all_games(), gs.clock.local_day()
	)
	assert_true(not expected.is_empty(), "Spotlight des Testtags bestimmt")
	var fenster_vorher: Vector2i = tree.root.size
	# Leitformat iPhone 17 Pro Max quer + hochkant (fb3-Wächter-Matrix).
	for fenster: Vector2i in [Vector2i(2868, 1320), Vector2i(1320, 2868)]:
		DisplayServer.window_set_size(fenster)
		tree.root.size = fenster
		await wait_frames(2)
		var screen: ArcadeScreen = (
			(load("res://scripts/minigames/arcade_screen.tscn") as PackedScene).instantiate()
		)
		screen.auto_navigate = false
		tree.root.add_child(screen)
		await wait_frames(3)
		# W20: die Wand ist in Kategorien-Reihen gegliedert (EIN Grid je
		# Reihe, ArcadeFortschritt.reihen) — der Badge-Vertrag gilt
		# unverändert über ALLE Kacheln aller Reihen-Grids.
		var tiles: Array[Control] = []
		for grid: GridContainer in screen.find_children("*", "GridContainer", true, false):
			for tile: Control in grid.get_children():
				tiles.append(tile)
		assert_true(tiles.size() > 0, "Reihen-Grids tragen Kacheln (%s)" % fenster)
		var badges := 0
		for tile: Control in tiles:
			var badge := tile.find_child("SpotlightBadge", true, false) as Control
			var glow := tile.find_child("SpotlightGlow", true, false) as Control
			if tile.name == "Tile_%s" % expected:
				assert_true(badge != null, "Spotlight-Kachel trägt das Badge (%s)" % fenster)
				assert_true(glow != null, "Spotlight-Kachel trägt den Glow (%s)" % fenster)
				if badge == null or glow == null:
					continue
				badges += 1
				assert_eq(badge.mouse_filter, Control.MOUSE_FILTER_IGNORE, "Badge frisst nix")
				assert_eq(glow.mouse_filter, Control.MOUSE_FILTER_IGNORE, "Glow frisst nix")
				# Overlay-Vertrag: das Badge meldet KEINE Min-Größe ans Grid
				# (Eltern-Frame bleibt bei 0 — kein Layout-Bruch, kein Rot in
				# der Zentrier-/UI-Wache) und bleibt im Kachel-Rechteck.
				assert_eq(
					(badge.get_parent() as Control).get_combined_minimum_size(),
					Vector2.ZERO,
					"Badge bläht das Cover-Frame nicht auf"
				)
				assert_true(
					tile.get_global_rect().grow(2.0).encloses(badge.get_global_rect()),
					"Badge bleibt in der Kachel (%s: %s)" % [fenster, badge.get_global_rect()]
				)
			else:
				assert_true(badge == null, "nur EINE Kachel trägt das Badge (%s)" % tile.name)
		assert_eq(badges, 1, "genau ein Spotlight-Badge im Grid (%s)" % fenster)
		screen.queue_free()
		await wait_frames(1)
	DisplayServer.window_set_size(fenster_vorher)
	tree.root.size = fenster_vorher
	gs.clock.unpin()
	await wait_frames(1)

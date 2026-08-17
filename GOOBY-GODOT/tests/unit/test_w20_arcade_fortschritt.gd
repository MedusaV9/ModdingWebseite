extends TestCase
## W20 Arcade-Fortschritt (Top-10 #4) — Wächter: pure 3-Sterne-Regel mit
## allen Kanten (nie gespielt / gespielt / Ziel geschafft / hart geschafft /
## Rekordschwelle / Endlos-Board), korrekte Aggregation für die Kopfzeile,
## VOLLSTÄNDIGE Kategorien-Zuordnung (jedes registrierte Spiel EXPLIZIT in
## genau einer Reihe), DE/EN-Parität der neuen mg.arcade.*-Keys und der
## Screen-Smoke in BEIDEN Leitformaten (Reihen-Header sichtbar, Sterne-
## Zeile im Kachel-Rechteck, Koexistenz mit dem Spotlight-Banner).

const SaveSchema := preload("res://scripts/state/save_schema.gd")

const NOW_MS := 1768478400000
## Fixture-Meta (Zahlen wie teaParty: Ziel 85 → Rekordschwelle 128).
const META := {"id": "teaParty", "target": 85}


func _frisch() -> Dictionary:
	return SaveSchema.default_state(NOW_MS)


## Testhilfe: Save-Felder eines Spiels direkt setzen (nur vorhandene Keys).
func _setze(state: Dictionary, id: String, felder: Dictionary) -> void:
	var mg: Dictionary = state["minigames"]
	var legacy: Dictionary = mg["legacy"]
	if felder.has("plays"):
		mg["plays"][id] = felder["plays"]
	if felder.has("best"):
		legacy["best"][id] = felder["best"]
	if felder.has("bestByDiff"):
		legacy["bestByDiff"][id] = felder["bestByDiff"]
	if felder.has("endlessBest"):
		legacy["endlessBest"][id] = felder["endlessBest"]
	if felder.has("beaten"):
		legacy["beaten"][id] = felder["beaten"]


func test_sterne_regel_alle_kanten() -> void:
	# Kante 0: nie gespielt (frischer Save) → 0 Sterne.
	assert_eq(ArcadeFortschritt.sterne(_frisch(), META), 0, "nie gespielt → 0")
	# Kante 1: einmal gespielt (plays > 0) → 1 Stern.
	var s := _frisch()
	_setze(s, "teaParty", {"plays": 1, "best": 12})
	assert_eq(ArcadeFortschritt.sterne(s, META), 1, "gespielt → 1")
	# Defensiv-Kante: Alt-Save ohne plays, aber mit Board → zählt gespielt.
	s = _frisch()
	_setze(s, "teaParty", {"best": 30})
	assert_eq(ArcadeFortschritt.sterne(s, META), 1, "Board ohne plays → 1")
	# Kante 2: Ziel geschafft (irgendein beaten-Modus) → 2 Sterne.
	s = _frisch()
	_setze(s, "teaParty", {"plays": 3, "best": 90, "beaten": {"normal": true}})
	assert_eq(ArcadeFortschritt.sterne(s, META), 2, "Ziel (normal) → 2")
	s = _frisch()
	_setze(s, "teaParty", {"plays": 3, "beaten": {"easy": true}})
	assert_eq(ArcadeFortschritt.sterne(s, META), 2, "Ziel (easy) → 2")
	# Kante 3a: hart geschafft (beaten.hard — Endlos-Freischalt-Bedingung
	# des Spiels, §G5.5) → 3 Sterne.
	s = _frisch()
	_setze(s, "teaParty", {"plays": 5, "beaten": {"hard": true}})
	assert_eq(ArcadeFortschritt.sterne(s, META), 3, "hart → 3")
	# Kante 3b: Rekord über der Schwelle (Timed-Board) → 3 Sterne.
	s = _frisch()
	_setze(s, "teaParty", {"plays": 5, "best": 128, "beaten": {"normal": true}})
	assert_eq(ArcadeFortschritt.sterne(s, META), 3, "Rekord 128 ≥ 1.5×85 → 3")
	# bestByDiff zählt ebenfalls als Timed-Board.
	s = _frisch()
	_setze(s, "teaParty", {"plays": 5, "bestByDiff": {"easy": 130}, "beaten": {"easy": true}})
	assert_eq(ArcadeFortschritt.sterne(s, META), 3, "Rekord via bestByDiff → 3")
	# Kante: knapp UNTER der Schwelle bleibt bei 2 Sternen.
	s = _frisch()
	_setze(s, "teaParty", {"plays": 5, "best": 127, "beaten": {"normal": true}})
	assert_eq(ArcadeFortschritt.sterne(s, META), 2, "127 < 128 → 2")
	# Kante: Rekord OHNE geschafftes Ziel gibt keine 3 (erst Ziel, dann
	# Meisterschaft — beaten kann bei Score ≥ Ziel real nie fehlen).
	s = _frisch()
	_setze(s, "teaParty", {"plays": 5, "best": 500})
	assert_eq(ArcadeFortschritt.sterne(s, META), 1, "Rekord ohne beaten → 1")
	# Kante: Endlos-Board allein ist KEIN Rekordpfad (unbegrenzte Scores).
	s = _frisch()
	_setze(s, "teaParty", {"plays": 5, "endlessBest": 9999})
	assert_eq(ArcadeFortschritt.sterne(s, META), 1, "endlessBest allein → 1")
	# Robustheit: kaputte Eingaben ergeben 0 statt Fehler.
	assert_eq(ArcadeFortschritt.sterne({}, META), 0, "leerer State → 0")
	assert_eq(ArcadeFortschritt.sterne(_frisch(), {}), 0, "Meta ohne id → 0")
	assert_eq(ArcadeFortschritt.sterne({"minigames": 7}, META), 0, "kaputter Slice → 0")


func test_aggregation_fuer_die_kopfzeile() -> void:
	var games: Array[Dictionary] = [
		{"id": "a", "target": 100},
		{"id": "b", "target": 100},
		{"id": "c", "target": 100, "coming_soon": true},
	]
	# Frisch: nichts gespielt, „Bald!“-Kacheln zählen nicht ins total.
	var leer := ArcadeFortschritt.gesamt(_frisch(), games)
	assert_eq(int(leer["gespielt"]), 0, "frisch: 0 gespielt")
	assert_eq(int(leer["total"]), 2, "coming_soon zählt nicht ins total")
	assert_eq(int(leer["sterne"]), 0, "frisch: 0 Sterne")
	# a gespielt (1★), b hart geschafft (3★) → 2 gespielt, 4 Sterne.
	var s := _frisch()
	_setze(s, "a", {"plays": 1})
	_setze(s, "b", {"plays": 4, "beaten": {"hard": true}})
	var g := ArcadeFortschritt.gesamt(s, games)
	assert_eq(int(g["gespielt"]), 2, "2 von 2 gespielt")
	assert_eq(int(g["total"]), 2, "total bleibt 2")
	assert_eq(int(g["sterne"]), 4, "1★ + 3★ = 4")


func test_kategorien_zuordnung_vollstaendig_und_eindeutig() -> void:
	# Jede Registry-Id EXPLIZIT zugeordnet (Fallback fängt nur Künftiges).
	var games := MinigameRegistry.all_games()
	assert_true(games.size() > 0, "Registry kennt Spiele")
	for game: Dictionary in games:
		var id := str(game.get("id", ""))
		assert_true(
			ArcadeFortschritt.ist_zugeordnet(id),
			"Spiel '%s' braucht eine explizite Reihe (arcade_fortschritt.gd)" % id
		)
	# Keine Id doppelt über die Reihen-Listen.
	var gesehen := {}
	for key: String in ArcadeFortschritt.REIHEN_ORDNUNG:
		for id: Variant in ArcadeFortschritt.REIHEN_IDS[key] as Array:
			assert_false(gesehen.has(id), "Id '%s' steht in ZWEI Reihen" % id)
			gesehen[id] = key
	# reihen(): jedes Spiel landet in GENAU einer Reihe, Reihenfolge stabil.
	var reihen := ArcadeFortschritt.reihen(games)
	var verteilt := 0
	var letzte_ordnung := -1
	for reihe: Dictionary in reihen:
		var ordnung := ArcadeFortschritt.REIHEN_ORDNUNG.find(str(reihe["key"]))
		assert_true(ordnung > letzte_ordnung, "Reihen folgen REIHEN_ORDNUNG")
		letzte_ordnung = ordnung
		var liste: Array = reihe["games"]
		assert_true(not liste.is_empty(), "Reihe '%s' ist nicht leer" % reihe["key"])
		verteilt += liste.size()
	assert_eq(verteilt, games.size(), "jedes Spiel in genau einer Reihe")
	# Unbekannte (künftige) Ids fallen in die dokumentierte Fallback-Reihe.
	assert_eq(
		ArcadeFortschritt.reihe_von("gibtsNochNicht"),
		ArcadeFortschritt.FALLBACK_REIHE,
		"unbekannte Id → Fallback-Reihe"
	)


func test_de_en_paritaet_der_neuen_keys() -> void:
	for locale in ["de", "en"]:
		var table := I18nService.table(locale)
		for key: String in ArcadeFortschritt.REIHEN_ORDNUNG:
			var voll := ArcadeFortschritt.REIHE_TITEL_PREFIX + key
			assert_true(table.has(voll), "%s fehlt in %s" % [voll, locale])
		for key in ["mg.arcade.fortschritt.kopf", "mg.arcade.fortschritt.kopf_einzahl"]:
			assert_true(table.has(key), "%s fehlt in %s" % [key, locale])


func test_screen_smoke_beide_leitformate() -> void:
	var gs := tree.root.get_node_or_null("/root/GameState")
	assert_true(gs != null, "GameState-Autoload vorhanden")
	if gs == null:
		return
	gs.clock.pin(NOW_MS)
	# Save deterministisch präparieren — mit VOLLER Isolation: der ganze
	# minigames-Slice wird durch einen frischen Schema-Default ersetzt,
	# denn frühere Suite-Tests (z. B. test_ef3_end_moment: carrotCatch-
	# Runde mit Score 99 über den Host) hinterlassen plays/best/beaten
	# im geteilten GameState; nur eigene Felder zu setzen reicht nicht.
	# Danach: teaParty gemeistert (3★), carrotCatch einmal gespielt (1★),
	# runner garantiert unberührt (0★). `vorher` stellt am Ende alles her.
	var vorher: Dictionary = (gs.state()["minigames"] as Dictionary).duplicate(true)
	var frisch: Dictionary = SaveSchema.default_state(NOW_MS)["minigames"]
	gs.update(
		func(s: Dictionary) -> void:
			s["minigames"] = frisch
			var legacy: Dictionary = frisch["legacy"]
			frisch["plays"]["teaParty"] = 4
			legacy["beaten"]["teaParty"] = {"hard": true}
			frisch["plays"]["carrotCatch"] = 1
	)
	var games := MinigameRegistry.all_games()
	var erwartete_reihen := ArcadeFortschritt.reihen(games)
	var gesamt := ArcadeFortschritt.gesamt(gs.state(), games)
	var spot: String = ArcadeSpotlight.spotlight_id(games, gs.clock.local_day())
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
		# (c) Kopfzeile zeigt die Aggregation.
		var kopf := screen.find_child("FortschrittZeile", true, false) as Label
		assert_true(kopf != null and kopf.is_visible_in_tree(), "Kopfzeile da (%s)" % fenster)
		if kopf != null:
			assert_true(
				kopf.text.contains("%d/%d" % [int(gesamt["gespielt"]), int(gesamt["total"])]),
				"Kopfzeile trägt n/total (%s: '%s')" % [fenster, kopf.text]
			)
		# (b) Jede Reihe hat Header + Grid, hochkant wie quer.
		for reihe: Dictionary in erwartete_reihen:
			var header := screen.find_child("ReihenHeader_%s" % reihe["key"], true, false)
			var grid := screen.find_child("ReihenGrid_%s" % reihe["key"], true, false)
			assert_true(header != null, "Header %s existiert (%s)" % [reihe["key"], fenster])
			assert_true(grid != null, "Grid %s existiert (%s)" % [reihe["key"], fenster])
			if header != null:
				assert_true(
					(header as Control).is_visible_in_tree(),
					"Header %s sichtbar (%s)" % [reihe["key"], fenster]
				)
			if grid != null:
				assert_eq(
					(grid as GridContainer).get_child_count(),
					(reihe["games"] as Array).size(),
					"Reihe %s trägt ihre Spiele (%s)" % [reihe["key"], fenster]
				)
		# (a) Sterne-Zeilen: Werte aus dem präparierten Save + im Rechteck.
		for eintrag: Array in [["teaParty", 3], ["carrotCatch", 1], ["runner", 0]]:
			var tile := screen.find_child("Tile_%s" % eintrag[0], true, false) as Control
			assert_true(tile != null, "Kachel %s existiert (%s)" % [eintrag[0], fenster])
			if tile == null:
				continue
			var zeile := tile.find_child("SterneZeile", true, false) as Control
			assert_true(zeile != null, "Sterne-Zeile auf %s (%s)" % [eintrag[0], fenster])
			if zeile == null:
				continue
			assert_eq(
				int(zeile.get("sterne")),
				int(eintrag[1]),
				"%s zeigt %d Sterne (%s)" % [eintrag[0], int(eintrag[1]), fenster]
			)
			assert_true(
				tile.get_global_rect().grow(2.0).encloses(zeile.get_global_rect()),
				"Sterne bleiben in der Kachel (%s: %s)" % [fenster, zeile.get_global_rect()]
			)
		# Koexistenz mit dem W19-Spotlight: Banner und Sterne-Zeile auf
		# derselben Kachel überlappen NIE (Banner: Cover-Unterkante,
		# Sterne: eigene Zeile darunter).
		var spot_tile := screen.find_child("Tile_%s" % spot, true, false) as Control
		assert_true(spot_tile != null, "Spotlight-Kachel existiert (%s)" % fenster)
		if spot_tile != null:
			var badge := spot_tile.find_child("SpotlightBadge", true, false) as Control
			var sterne := spot_tile.find_child("SterneZeile", true, false) as Control
			assert_true(badge != null, "Spotlight-Badge da (%s)" % fenster)
			assert_true(sterne != null, "Sterne-Zeile auf der Spotlight-Kachel (%s)" % fenster)
			if badge != null and sterne != null:
				assert_false(
					badge.get_global_rect().intersects(sterne.get_global_rect()),
					(
						"Banner und Sterne koexistieren (%s: %s vs %s)"
						% [fenster, badge.get_global_rect(), sterne.get_global_rect()]
					)
				)
		screen.queue_free()
		await wait_frames(1)
	DisplayServer.window_set_size(fenster_vorher)
	tree.root.size = fenster_vorher
	gs.update(func(s: Dictionary) -> void: s["minigames"] = vorher)
	gs.clock.unpin()
	await wait_frames(1)

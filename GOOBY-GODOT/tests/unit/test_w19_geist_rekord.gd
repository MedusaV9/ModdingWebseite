extends TestCase
## W19/GEIST — Wächter für den Rekord-Geist der Arcade-Minigames
## (geist_rekord.gd + Host-Hooks + Results-Beat): deterministische
## Kurven-Aufzeichnung, Speicher-Budget/Quantisierung, Delta-Interpolation,
## Chip-Gating (ohne Kurve/ohne Live-Score bleibt der Chip weg),
## Rekord-Ablösung GENAU beim neuen Rekord, „Geist geschlagen“-Beat
## genau einmal pro Runde und sauberes Abbauen am Rundenende.

const HOST_SCENE := "res://scripts/minigames/minigame_host.tscn"
const GAME_ID := "carrotCatch"
## Flache Referenzkurve (Geist bleibt 10 s auf 0): Chip-Deltas sind damit in
## kurzen Test-Runden framerate-unabhängig vorhersagbar.
const REF_FLACH := {
	"score": 100,
	"schritt_sec": 1.0,
	"dauer_sec": 10.0,
	"kurve": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
}

## ── (a) pure Logik: Aufzeichnung / Budget / Interpolation ───────────────


func test_aufzeichnung_ist_deterministisch() -> void:
	var snaps: Array[Dictionary] = []
	for _lauf in 2:
		var rec := GeistRekord.new()
		rec.starte({})
		rec.melde_live_score()
		rec.tick(0.4, 1)
		rec.tick(0.4, 2)
		rec.tick(0.4, 3)
		rec.tick(0.8, 5)
		rec.tick(1.0, 8)
		snaps.append(rec.snapshot(9))
	assert_eq(snaps[0], snaps[1], "gleiche Ticks = identischer Snapshot (kein RNG, keine OS-Uhr)")
	var snap := snaps[0]
	assert_eq(snap["kurve"], [0, 3, 5, 8] as Array[int], "Samples an den 1-Hz-Grenzen (1/2/3 s)")
	assert_eq(int(snap["score"]), 9, "Endstand steht im Snapshot")
	assert_almost(float(snap["schritt_sec"]), 1.0, 1e-6, "Grundschritt 1 Hz")
	assert_almost(float(snap["dauer_sec"]), 3.0, 1e-6, "Rundendauer = Summe der Ticks")


func test_budget_verdichtet_und_quantisiert() -> void:
	var rec := GeistRekord.new()
	rec.starte({})
	rec.melde_live_score()
	for i in 500:
		rec.tick(1.0, i)
	var snap := rec.snapshot(500)
	var kurve: Array = snap["kurve"]
	assert_true(
		kurve.size() <= GeistRekord.MAX_STUETZEN,
		"Budget hält: %d Stützstellen <= %d" % [kurve.size(), GeistRekord.MAX_STUETZEN]
	)
	assert_almost(float(snap["schritt_sec"]), 4.0, 1e-6, "2× verdichtet → Schrittweite 4 s")
	assert_almost(
		GeistRekord.wert_bei(snap, 320.0), 319.0, 1e-6, "Zeitachse überlebt die Verdichtung"
	)
	for wert: Variant in kurve:
		if not (wert is int):
			fail_test("Kurve enthält Nicht-Ganzzahl: %s" % str(wert))
			break
	# Quantisierung: negative Scores klemmen auf 0 (Samples UND Endstand).
	var rec2 := GeistRekord.new()
	rec2.starte({})
	rec2.melde_live_score()
	rec2.tick(1.0, -7)
	var snap2 := rec2.snapshot(-3)
	assert_eq(snap2["kurve"], [0, 0] as Array[int], "negatives Sample → 0")
	assert_eq(int(snap2["score"]), 0, "negativer Endstand → 0")
	var rec3 := GeistRekord.new()
	rec3.starte({})
	assert_eq(rec3.snapshot(42), {}, "ohne Live-Score-Meldung gibt es KEINEN Snapshot")


func test_interpolation_an_und_zwischen_stuetzstellen() -> void:
	# JSON-Round-Trip macht aus ints floats — der Reader muss beides können.
	var rekord := {"score": 30.0, "schritt_sec": 1.0, "dauer_sec": 4.0, "kurve": [0.0, 10.0, 20.0]}
	assert_almost(GeistRekord.wert_bei(rekord, 0.0), 0.0, 1e-6, "t=0 → Startwert")
	assert_almost(GeistRekord.wert_bei(rekord, 1.0), 10.0, 1e-6, "Stützstelle 1 s")
	assert_almost(GeistRekord.wert_bei(rekord, 1.5), 15.0, 1e-6, "linear dazwischen")
	assert_almost(GeistRekord.wert_bei(rekord, 2.0), 20.0, 1e-6, "Stützstelle 2 s")
	assert_almost(GeistRekord.wert_bei(rekord, 3.0), 25.0, 1e-6, "Auslauf zum Endstand (lerp)")
	assert_almost(GeistRekord.wert_bei(rekord, 99.0), 30.0, 1e-6, "hinter dauer_sec = Endstand")
	assert_eq(GeistRekord.delta_fuer(rekord, 1.5, 20), 5, "Spieler vor dem Geist → +5")
	assert_eq(GeistRekord.delta_fuer(rekord, 1.5, 10), -5, "Spieler hinter dem Geist → −5")
	assert_eq(GeistRekord.wert_bei({}, 3.0), 0.0, "ungültiger Rekord wirft nie, liefert 0")
	assert_eq(GeistRekord.delta_text(12), "+12", "Chip-Text vorn")
	assert_eq(GeistRekord.delta_text(-5), "−5", "Chip-Text hinten (echtes Minus)")
	assert_eq(GeistRekord.delta_text(0), "±0", "Chip-Text Gleichstand")


func test_rekord_abloesung_genau_beim_neuen_rekord() -> void:
	var state := {"minigames": {}}
	var erst := {"score": 50, "schritt_sec": 1.0, "dauer_sec": 2.0, "kurve": [0, 20, 50]}
	assert_true(GeistRekord.uebernehme_rekord(state, "x", erst), "Erstlauf legt die Kurve an")
	assert_eq(GeistRekord.rekord_von(state, "x")["kurve"], [0, 20, 50] as Array, "Kurve liegt da")
	var schwach := {"score": 40, "schritt_sec": 1.0, "dauer_sec": 1.0, "kurve": [0, 40]}
	assert_false(GeistRekord.uebernehme_rekord(state, "x", schwach), "40 < 50 ersetzt NICHT")
	var gleich := {"score": 50, "schritt_sec": 1.0, "dauer_sec": 1.0, "kurve": [0, 50]}
	assert_false(GeistRekord.uebernehme_rekord(state, "x", gleich), "Gleichstand ersetzt NICHT")
	assert_eq(
		GeistRekord.rekord_von(state, "x")["kurve"], [0, 20, 50] as Array, "alte Kurve unberührt"
	)
	var stark := {"score": 60, "schritt_sec": 1.0, "dauer_sec": 1.0, "kurve": [0, 60]}
	assert_true(GeistRekord.uebernehme_rekord(state, "x", stark), "60 > 50 ersetzt GENAU jetzt")
	assert_eq(GeistRekord.rekord_von(state, "x")["kurve"], [0, 60] as Array, "neue Kurve drin")
	assert_false(GeistRekord.uebernehme_rekord(state, "x", {}), "leerer Snapshot ersetzt nie")
	assert_eq(GeistRekord.rekord_von({"minigames": {"geist": {"x": "quatsch"}}}, "x"), {})


## ── (b) Host: Chip-Gating + Kurven-Speicherung ──────────────────────────


func test_chip_gating_ohne_kurve_und_ohne_score() -> void:
	_setze_geist_rekord(null)
	var host := await _mount_and_start()
	var chip: Control = host.get("_geist_chip")
	assert_ne(chip, null, "Chip existiert in der Top-Bar")
	assert_false(chip.visible, "ohne gespeicherte Kurve bleibt der Chip weg")
	var game: MinigameBase = host.get("_game")
	game.ctx.report_score(5, 5)
	await wait_frames(3)
	assert_false(chip.visible, "auch MIT Live-Score bleibt er ohne Kurve weg")
	game.ctx.report_end({"score": 5})
	await wait_until(func() -> bool: return (host.get("_results") as Control).visible, 4000)
	await _unmount(host)


func test_chip_erscheint_erst_mit_kurve_und_live_score() -> void:
	_setze_geist_rekord(REF_FLACH.duplicate(true))
	var host := await _mount_and_start()
	var chip: Control = host.get("_geist_chip")
	await wait_frames(3)
	assert_false(chip.visible, "Kurve da, aber noch kein Live-Score → Chip weg")
	var game: MinigameBase = host.get("_game")
	game.ctx.report_score(3, 3)
	assert_true(chip.visible, "Kurve + Live-Score → Chip sichtbar")
	var label := chip.get_child(1) as Label
	assert_eq(label.text, "+3", "flacher Geist auf 0 → Spieler liegt +3 vorn")
	game.ctx.report_end({"score": 3})
	await wait_until(func() -> bool: return (host.get("_results") as Control).visible, 4000)
	assert_false(chip.visible, "Rundenende baut den Chip ab")
	await _unmount(host)
	_setze_geist_rekord(null)


func test_erstlauf_speichert_kurve_ohne_geist_beat() -> void:
	_setze_geist_rekord(null)
	var host := await _mount_and_start()
	var breakdowns: Array = []
	host.round_finished.connect(func(b: Dictionary) -> void: breakdowns.append(b))
	var game: MinigameBase = host.get("_game")
	game.ctx.report_score(7, 7)
	await wait_frames(4)
	game.ctx.report_end({"score": 7})
	await wait_until(func() -> bool: return (host.get("_results") as Control).visible, 4000)
	assert_eq(breakdowns.size(), 1, "eine Runde = ein Breakdown")
	assert_false(
		bool(breakdowns[0].get("geistGeschlagen", false)),
		"Erstlauf: kein Geist da → kein „geschlagen“-Beat"
	)
	var rekord := _lies_geist_rekord()
	assert_true(GeistRekord.ist_gueltig(rekord), "Erstlauf legt die Bestlauf-Kurve an")
	assert_eq(GeistRekord.rekord_score(rekord), 7, "gespeicherter Kurven-Score = Endstand")
	assert_eq(
		host._results.find_children("GeistZeile", "", true, false).size(),
		0,
		"Results ohne Geist-Zeile beim Erstlauf"
	)
	await _unmount(host)
	_setze_geist_rekord(null)


func test_geist_geschlagen_beat_genau_einmal_und_abloesung() -> void:
	_setze_geist_rekord({"score": 5, "schritt_sec": 1.0, "dauer_sec": 1.0, "kurve": [0, 5]})
	var host := await _mount_and_start()
	var breakdowns: Array = []
	host.round_finished.connect(func(b: Dictionary) -> void: breakdowns.append(b))
	var game: MinigameBase = host.get("_game")
	game.ctx.report_score(10, 10)
	await wait_frames(4)
	game.ctx.report_end({"score": 10})
	await wait_until(func() -> bool: return (host.get("_results") as Control).visible, 4000)
	assert_true(bool(breakdowns[0].get("geistGeschlagen", false)), "10 > 5 → Geist geschlagen")
	assert_eq(
		host._results.find_children("GeistZeile", "", true, false).size(),
		1,
		"GENAU EINE „Geist geschlagen!“-Zeile auf der Results-Karte"
	)
	assert_eq(GeistRekord.rekord_score(_lies_geist_rekord()), 10, "Kurve GENAU jetzt abgelöst")

	# „Nochmal“: die Folgerunde rennt gegen den NEUEN Geist (10) — wer
	# darunter bleibt, bekommt weder Beat noch Ablösung.
	host._on_again_pressed()
	await wait_until(
		func() -> bool:
			var g: MinigameBase = host.get("_game")
			return g != null and is_instance_valid(g) and g.is_active(),
		8000
	)
	var chip: Control = host.get("_geist_chip")
	assert_false(chip.visible, "Neustart setzt den Chip zurück (Gating frisch)")
	var game2: MinigameBase = host.get("_game")
	game2.ctx.report_score(3, 3)
	await wait_frames(4)
	game2.ctx.report_end({"score": 3})
	await wait_until(func() -> bool: return (host.get("_results") as Control).visible, 4000)
	assert_eq(breakdowns.size(), 2, "zweite Runde = zweiter Breakdown")
	assert_false(bool(breakdowns[1].get("geistGeschlagen", false)), "3 < 10 → kein Beat")
	assert_eq(
		host._results.find_children("GeistZeile", "", true, false).size(),
		0,
		"Results der Folgerunde OHNE Geist-Zeile (kein Doppel-Feier-Spam)"
	)
	assert_eq(GeistRekord.rekord_score(_lies_geist_rekord()), 10, "Bestlauf-Kurve bleibt bei 10")
	await _unmount(host)
	_setze_geist_rekord(null)


func test_rundenende_und_quit_raeumen_sauber_auf() -> void:
	_setze_geist_rekord(REF_FLACH.duplicate(true))
	var host := await _mount_and_start()
	var chip: Control = host.get("_geist_chip")
	var game: MinigameBase = host.get("_game")
	game.ctx.report_score(4, 4)
	assert_true(chip.visible, "Chip läuft während der Runde")
	assert_eq(chip.get_parent(), host.get("_top_bar"), "Chip lebt in der Top-Bar …")
	var layer := host.juice.float_text_parent as Control
	assert_false(layer.get_children().has(chip), "… NICHT im Juice-Layer (clear_overlays-fest)")
	# Quit mitten in der Runde (Pause-Modal-Weg): Chip weg, Tracking weg,
	# und clear_overlays hinterlässt einen leeren Juice-Layer (W18-B2-Regel).
	host._on_quit_pressed()
	await wait_frames(2)
	assert_false(chip.visible, "Quit baut den Chip ab")
	assert_eq(host.get("_geist"), null, "Quit stoppt das Geist-Tracking (keine Kurve)")
	assert_eq(layer.get_child_count(), 0, "Juice-Layer ist nach dem Quit leer")
	assert_true(
		GeistRekord.rekord_score(_lies_geist_rekord()) == 100,
		"Abbruch ersetzt die Bestlauf-Kurve NICHT"
	)
	await _unmount(host)
	_setze_geist_rekord(null)


## ── Helfer (Muster test_ef3_end_moment) ─────────────────────────────────


func _mount_and_start() -> MinigameHost:
	_refill_energy()
	var host: MinigameHost = (load(HOST_SCENE) as PackedScene).instantiate()
	host.auto_navigate = false
	host.countdown_step_sec = 0.0
	host.quick_go_sec = 0.0
	host.receive_params({"game_id": GAME_ID, "difficulty": "normal", "seed": 1919})
	tree.root.add_child(host)
	await wait_until(
		func() -> bool:
			var game: MinigameBase = host.get("_game")
			return game != null and is_instance_valid(game) and game.is_active(),
		8000
	)
	return host


func _unmount(host: MinigameHost) -> void:
	host.queue_free()
	Engine.time_scale = 1.0
	await wait_frames(2)


func _refill_energy() -> void:
	var gs := tree.root.get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("update"):
		return
	gs.update(
		func(state: Dictionary) -> void:
			var gooby: Variant = state.get("gooby")
			if gooby is Dictionary and (gooby as Dictionary).get("stats") is Dictionary:
				((gooby as Dictionary)["stats"] as Dictionary)["energy"] = 100.0
	)


## Bestlauf-Kurve für GAME_ID setzen (null = löschen) — direkt im Save.
func _setze_geist_rekord(rekord: Variant) -> void:
	var gs := tree.root.get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("update"):
		return
	gs.update(
		func(state: Dictionary) -> void:
			var mg: Variant = state.get("minigames")
			if not (mg is Dictionary):
				return
			if rekord == null:
				if (mg as Dictionary).get("geist") is Dictionary:
					((mg as Dictionary)["geist"] as Dictionary).erase(GAME_ID)
				return
			if not ((mg as Dictionary).get("geist") is Dictionary):
				(mg as Dictionary)["geist"] = {}
			((mg as Dictionary)["geist"] as Dictionary)[GAME_ID] = rekord
	)


func _lies_geist_rekord() -> Dictionary:
	var gs := tree.root.get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("state"):
		return {}
	return GeistRekord.rekord_von(gs.state(), GAME_ID)

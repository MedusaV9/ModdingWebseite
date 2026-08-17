extends TestCase  # gdlint: ignore=max-public-methods
## W15/TECHKIT — drei Restpunkte aus GODOT-PLAN §6 G/M3:
## (a) danceParty-Audio-Latenz-Kalibrierung (DanceTiming pur + Kalibrier-UI),
## (b) HDR-/Glow-Auto-Downgrade-Telemetrie (PerfGlowWatch-Statemaschine,
##     Fake-Monitor-Feed, user://-Merker, Reset),
## (c) GOB-NOM-@tool-Level-Editor (GobnomEditorLogic: Snap/Griffe/Roundtrip
##     nach /tmp, Struktur-Checks, Solver-Validierung mock- UND echt).

var _seq := 0


func _fresh_store(file: String) -> String:
	_seq += 1
	var dir := "user://w15_techkit/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	return "%s/%s" % [dir, file]


func _tmp_path(file: String) -> String:
	_seq += 1
	var dir := "/tmp/gooby-godot-tests/w15_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(dir)
	return "%s/%s" % [dir, file]


## --------------------------------------------------- (a) DanceTiming (pur)


func test_dance_basis_latenz() -> void:
	assert_almost(DanceTiming.base_latency_from(0.05, 0.0), 50.0, 1e-4, "50 ms Output-Latenz")
	assert_almost(
		DanceTiming.base_latency_from(0.05, 0.02), 30.0, 1e-4, "seit Mix verstrichen zieht ab"
	)
	assert_almost(DanceTiming.base_latency_from(2.0, 0.0), 500.0, 1e-4, "Deckel 500 ms")
	assert_almost(DanceTiming.base_latency_from(0.05, -1.0), 50.0, 1e-4, "negatives since_mix = 0")
	assert_almost(DanceTiming.base_latency_from(0.05, 9.0), 0.0, 1e-4, "since_mix > Latenz = 0")


func test_dance_klemmen_und_gesamtoffset() -> void:
	assert_almost(DanceTiming.clamp_manual(200.0), 150.0, 1e-4, "Klemme +150")
	assert_almost(DanceTiming.clamp_manual(-999.0), -150.0, 1e-4, "Klemme -150")
	assert_almost(DanceTiming.clamp_manual(NAN), 0.0, 1e-4, "NaN wird 0")
	var timing := DanceTiming.new()
	timing.base_latency_ms = 40.0
	timing.manual_offset_ms = 30.0
	assert_almost(timing.total_offset_ms(), 70.0, 1e-4, "Basis + manuell")
	assert_almost(timing.play_time(10.0), 10.0 - 0.07, 1e-6, "Songzeit minus Gesamtoffset")


func test_dance_autoplay_bleibt_neutral() -> void:
	# CROSSCHECK-Vertrag: der Zertifizierungs-Bot läuft mit Offset 0 —
	# frisches DanceTiming ist die Identität auf der Songzeit.
	var timing := DanceTiming.new()
	assert_almost(timing.total_offset_ms(), 0.0, 1e-6, "frisch = kein Offset")
	assert_almost(timing.play_time(3.25), 3.25, 1e-6, "play_time = Identität")


func test_dance_median() -> void:
	assert_almost(DanceTiming.median_ms([10.0, 30.0, 20.0]), 20.0, 1e-4, "ungerade Anzahl")
	assert_almost(DanceTiming.median_ms([10.0, 20.0, 30.0, 40.0]), 25.0, 1e-4, "gerade Anzahl")
	assert_almost(DanceTiming.median_ms(["x", null, 10.0]), 10.0, 1e-4, "Müll wird ignoriert")
	assert_almost(DanceTiming.median_ms([]), 0.0, 1e-4, "leer = 0")


func test_dance_manual_from_taps() -> void:
	var manual := DanceTiming.manual_from_taps([80.0, 90.0, 100.0], 40.0)
	assert_almost(manual, 50.0, 1e-4, "Median 90 minus Basis 40")
	assert_almost(
		DanceTiming.manual_from_taps([400.0, 400.0, 400.0], 0.0), 150.0, 1e-4, "Klemme greift"
	)
	assert_almost(DanceTiming.manual_from_taps([], 40.0), 0.0, 1e-4, "keine Tipps = 0")


func test_dance_tap_zuordnung() -> void:
	var lead := DanceTiming.CALIBRATION_LEAD_IN_SEC
	var beat := DanceTiming.CALIBRATION_BEAT_SEC
	var hit := DanceTiming.tap_delta_ms(lead + 2.0 * beat + 0.03)
	assert_eq(int(hit["beat"]), 2, "nächster Schlag = 2")
	assert_almost(float(hit["delta_ms"]), 30.0, 1e-3, "30 ms zu spät")
	var early := DanceTiming.tap_delta_ms(0.0)
	assert_eq(int(early["beat"]), 0, "vor dem Lead-in klemmt auf Schlag 0")
	var late := DanceTiming.tap_delta_ms(lead + 20.0 * beat)
	assert_eq(int(late["beat"]), DanceTiming.CALIBRATION_BEATS - 1, "klemmt auf letzten Schlag")


func test_dance_save_slice_roundtrip() -> void:
	var state := {}
	DanceTiming.store_manual_offset(state, 87.4)
	assert_eq(int(state["minigames"][DanceTiming.SAVE_KEY]), 87, "gerundet gespeichert")
	assert_almost(DanceTiming.manual_offset_from_state(state), 87.0, 1e-4, "liest zurück")
	DanceTiming.store_manual_offset(state, 400.0)
	assert_eq(int(state["minigames"][DanceTiming.SAVE_KEY]), 150, "Klemme beim Schreiben")
	assert_almost(
		DanceTiming.manual_offset_from_state({"minigames": "kaputt"}), 0.0, 1e-4, "hostiler Save"
	)
	assert_almost(DanceTiming.manual_offset_from_state({}), 0.0, 1e-4, "leerer Save")


func test_dance_kalibrierung_lauf() -> void:
	# Voller zeitinjizierter Kalibrier-Lauf: 8 Schläge, Tipps je +50 ms —
	# Ergebnis = Median 50 minus Basis 20 = 30 ms im (Fake-)Save.
	var calib := DanceCalibration.new()
	var fake_state := FakeGameState.new()
	calib.state_node = fake_state
	tree.root.add_child(calib)
	calib.base_latency_ms = 20.0
	calib.start_run()
	assert_true(calib.running, "Lauf gestartet")
	var lead := DanceTiming.CALIBRATION_LEAD_IN_SEC
	var beat := DanceTiming.CALIBRATION_BEAT_SEC
	for i in DanceTiming.CALIBRATION_BEATS:
		var target := lead + float(i) * beat + 0.05
		calib.advance_time(target - calib.clock)
		calib.register_tap()
		calib.register_tap()  # Doppel-Tipp auf denselben Schlag zählt nicht
	assert_eq(calib.tap_deltas.size(), DanceTiming.CALIBRATION_BEATS, "ein Tipp pro Schlag")
	calib.advance_time(2.0)
	assert_false(calib.running, "Lauf beendet")
	assert_eq(calib.result_ms, 30, "Median 50 − Basis 20")
	assert_eq(int(DanceTiming.manual_offset_from_state(fake_state.data)), 30, "im Save-Slice")
	tree.root.remove_child(calib)
	calib.free()
	fake_state.free()


## ------------------------------------------- (b) PerfGlowWatch-Statemaschine


func test_glow_p95() -> void:
	var values: Array = []
	for i in range(1, 101):
		values.append(float(i))
	assert_almost(PerfGlowWatch.p95(values), 95.0, 1e-4, "p95 von 1..100")
	assert_almost(PerfGlowWatch.p95(["x", 10.0, null]), 10.0, 1e-4, "Müll wird ignoriert")
	assert_almost(PerfGlowWatch.p95([]), 0.0, 1e-4, "leer = 0")


func test_glow_watcher_im_budget() -> void:
	var store := _fresh_store("glow.json")
	var watch := PerfGlowWatch.new()
	watch.store_path = store
	watch.budget_ms_override = 20.0
	watch.game_id = "danceParty"
	for i in 51:
		watch.feed(10.0, 0.1)
	assert_eq(watch.phase, "ok", "p95 10 ms unter Budget 20 ms")
	assert_false(PerfGlowWatch.is_downgraded("danceParty", store), "kein Merker")
	watch.free()


func test_glow_watcher_downgrade_persistiert() -> void:
	var store := _fresh_store("glow.json")
	var watch := PerfGlowWatch.new()
	watch.store_path = store
	watch.budget_ms_override = 20.0
	watch.game_id = "gobnom"
	var phase := ""
	for i in 51:
		phase = watch.feed(30.0, 0.1)
	assert_eq(phase, "gedrosselt", "p95 30 ms über Budget 20 ms")
	assert_true(PerfGlowWatch.is_downgraded("gobnom", store), "Merker gesetzt")
	var rows := PerfGlowWatch.entries(store)
	assert_eq(rows.size(), 1, "eine Merker-Zeile")
	assert_eq(str(rows[0]["game"]), "gobnom")
	assert_almost(float(rows[0]["p95_ms"]), 30.0, 0.2, "p95 protokolliert")
	watch.free()
	# Nächster Start desselben Spiels: der Merker greift OHNE neue Messfahrt.
	var second := PerfGlowWatch.new()
	second.store_path = store
	assert_true(PerfGlowWatch.is_downgraded("gobnom", second.store_path), "persistiert")
	second.free()
	# Dev-Panel-Reset: Merker weg, nächste Messfahrt frisch.
	PerfGlowWatch.clear_store(store)
	assert_false(PerfGlowWatch.is_downgraded("gobnom", store), "Reset löscht")
	assert_true(PerfGlowWatch.entries(store).is_empty(), "Liste leer")


func test_glow_watcher_zu_wenig_messwerte() -> void:
	var store := _fresh_store("glow.json")
	var watch := PerfGlowWatch.new()
	watch.store_path = store
	watch.budget_ms_override = 20.0
	watch.game_id = "runner"
	var phase := ""
	for i in 3:
		phase = watch.feed(999.0, 2.0)
	assert_eq(phase, "ok", "3 Frames sind kein p95-Urteil (Hänger != Trend)")
	assert_false(PerfGlowWatch.is_downgraded("runner", store), "kein Merker")
	watch.free()


func test_glow_budget_aus_quality_buendel() -> void:
	var watch := PerfGlowWatch.new()
	var quality := QualityMock.new()
	quality.bundle = {"fps": 30}
	watch.quality_override = quality
	assert_almost(watch.budget_ms(), 1000.0 / 30.0 * 1.25, 1e-3, "30-fps-Bündel × Headroom")
	quality.bundle = {"fps": 120}
	assert_almost(watch.budget_ms(), 1000.0 / 120.0 * 1.25, 1e-3, "120-fps-Bündel")
	watch.budget_ms_override = 42.0
	assert_almost(watch.budget_ms(), 42.0, 1e-6, "Override schlägt Quality")
	watch.free()


## ------------------------------------------- (c) GOB-NOM-Editor (pur/tmp)


func test_editor_snap_und_klemme() -> void:
	assert_eq(GobnomEditorLogic.snap_pos(Vector2(13, 27), 10.0), Vector2(10, 30), "Raster 10")
	assert_eq(GobnomEditorLogic.snap_pos(Vector2(-50, 999), 10.0), Vector2(0, 540), "Welt-Klemme")
	assert_eq(
		GobnomEditorLogic.snap_pos(Vector2(13.5, 27.5), 0.0), Vector2(13.5, 27.5), "Raster 0 = aus"
	)


func test_editor_handles_und_pick() -> void:
	var level := {
		"candy": {"x": 480.0, "y": 150.0},
		"mouth": {"x": 480.0, "y": 470.0},
		"ropes": [{"x": 480.0, "y": 90.0, "rest": 60.0}],
		"jars": [{"x": 400.0, "y": 300.0}, {"x": 480.0, "y": 340.0}, {"x": 560.0, "y": 300.0}],
	}
	assert_eq(GobnomEditorLogic.handles(level).size(), 6, "candy+mouth+1 Seil+3 Gläser")
	var picked := GobnomEditorLogic.pick_handle(level, Vector2(482.0, 152.0))
	assert_eq(str(picked["kind"]), "candy", "nächster Griff = candy")
	assert_eq(int(picked["index"]), -1, "Einzelpunkte haben Index -1")
	assert_true(GobnomEditorLogic.pick_handle(level, Vector2(50.0, 50.0)).is_empty(), "daneben")


func test_editor_move_mit_rail() -> void:
	var level := {
		"candy": {"x": 480.0, "y": 150.0},
		"ropes":
		[
			{
				"x": 400.0,
				"y": 100.0,
				"rest": 90.0,
				"rail": {"x1": 400.0, "y1": 100.0, "x2": 560.0, "y2": 100.0},
			}
		],
	}
	assert_true(GobnomEditorLogic.move_element(level, "ropes", 0, Vector2(423.0, 137.0), 10.0))
	var rope: Dictionary = level["ropes"][0]
	assert_eq(Vector2(rope["x"], rope["y"]), Vector2(420, 140), "Anker gesnappt")
	var rail: Dictionary = rope["rail"]
	assert_eq(Vector2(rail["x1"], rail["y1"]), Vector2(420, 140), "Schiene wandert mit")
	assert_eq(Vector2(rail["x2"], rail["y2"]), Vector2(580, 140), "Delta auf beide Enden")
	assert_true(GobnomEditorLogic.move_element(level, "candy", -1, Vector2(301.0, 149.0), 10.0))
	var candy: Dictionary = level["candy"]
	assert_eq(Vector2(candy["x"], candy["y"]), Vector2(300, 150), "candy zieht mit Snap")
	assert_false(GobnomEditorLogic.move_element(level, "ropes", 7, Vector2.ZERO), "Index daneben")


func test_editor_add_remove_properties() -> void:
	var level := {"candy": {"x": 480.0, "y": 150.0}}
	var index := GobnomEditorLogic.add_element(level, "bubbles", Vector2(101.0, 99.0), 10.0)
	assert_eq(index, 0, "erstes Element")
	var bubble: Dictionary = level["bubbles"][0]
	assert_eq(Vector2(bubble["x"], bubble["y"]), Vector2(100, 100), "Vorlage gesnappt")
	assert_almost(float(bubble["r"]), 26.0, 1e-4, "Vorlage-Radius")
	var props := GobnomEditorLogic.properties_of(level, "bubbles", 0)
	assert_true(props.has("x") and props.has("y") and props.has("r"), "Zahl-Felder gelistet")
	assert_true(GobnomEditorLogic.set_property(level, "bubbles", 0, "r", 30.0))
	assert_almost(float(level["bubbles"][0]["r"]), 30.0, 1e-4, "Eigenschaft gesetzt")
	assert_false(GobnomEditorLogic.set_property(level, "bubbles", 0, "x", 1.0), "x/y nur über move")
	assert_eq(GobnomEditorLogic.add_element(level, "quatsch", Vector2.ZERO), -1, "Kind unbekannt")
	assert_true(GobnomEditorLogic.remove_element(level, "bubbles", 0))
	assert_true((level["bubbles"] as Array).is_empty(), "entfernt")
	assert_false(GobnomEditorLogic.remove_element(level, "bubbles", 0), "doppelt entfernen")


func test_editor_struktur_fehler() -> void:
	var balance := {"world": {"w": 960.0, "h": 540.0}}
	var kaputt := {"jars": [{"x": 1.0, "y": 1.0}], "ropes": [{"x": 5000.0, "y": 90.0}]}
	var errors := GobnomEditorLogic.structural_errors(kaputt, balance)
	assert_true(errors.size() >= 4, "candy, mouth, Gläser, Plan, außerhalb: %s" % [errors])
	var heil := {
		"candy": {"x": 480.0, "y": 150.0},
		"mouth": {"x": 480.0, "y": 470.0},
		"jars": [{"x": 400.0, "y": 300.0}, {"x": 480.0, "y": 340.0}, {"x": 560.0, "y": 300.0}],
		"solution": {"actions": [{"t": 0.5, "do": "cut", "rope": 0}]},
	}
	assert_true(GobnomEditorLogic.structural_errors(heil, balance).is_empty(), "heil = leer")


func test_editor_validate_mit_mock_solver() -> void:
	var balance := {"world": {"w": 960.0, "h": 540.0}}
	var level := {
		"candy": {"x": 480.0, "y": 150.0},
		"mouth": {"x": 480.0, "y": 470.0},
		"jars": [{"x": 400.0, "y": 300.0}, {"x": 480.0, "y": 340.0}, {"x": 560.0, "y": 300.0}],
		"solution": {"actions": [{"t": 0.5, "do": "cut", "rope": 0}]},
	}
	var won := func(_level: Dictionary, _balance: Dictionary) -> Dictionary:
		return {"won": true, "outcome": "won"}
	var lost := func(_level: Dictionary, _balance: Dictionary) -> Dictionary:
		return {"won": false, "outcome": "timeout"}
	var green := GobnomEditorLogic.validate(level, balance, won)
	assert_true(bool(green["ok"]), "Mock-Solver gewinnt = grün")
	var red := GobnomEditorLogic.validate(level, balance, lost)
	assert_false(bool(red["ok"]), "Mock-Solver verliert = rot")
	var kaputt := level.duplicate(true)
	kaputt.erase("mouth")
	var struct_fail := GobnomEditorLogic.validate(kaputt, balance, won)
	assert_false(bool(struct_fail["ok"]), "Struktur-Fehler = rot OHNE Solver-Lauf")
	assert_true((struct_fail["errors"] as PackedStringArray).size() > 0, "Fehler gelistet")


func test_editor_roundtrip_nach_tmp() -> void:
	# Echtes Dokument laden (READ-ONLY), Kopie mutieren, nach /tmp speichern,
	# neu laden: Mutationen da, Schema-Checks grün, Original unberührt.
	var doc := GobnomEditorLogic.load_doc(GobnomData.LEVELS_PATH)
	assert_false(doc.is_empty(), "eingecheckte Level-Datei lesbar")
	assert_eq(GobnomEditorLogic.level_ids(doc, "campaign").size(), 15, "15 Kampagnen-Level")
	var copy: Dictionary = doc.duplicate(true)
	var level := GobnomEditorLogic.level_ref(copy, "campaign", 1)
	assert_false(level.is_empty(), "Level 1 als Referenz")
	GobnomEditorLogic.move_element(level, "candy", -1, Vector2(303.0, 148.0), 10.0)
	var added := GobnomEditorLogic.add_element(level, "bubbles", Vector2(201.0, 402.0), 10.0)
	assert_eq(added, 0, "Bubble ergänzt")
	var path := _tmp_path("gobnom_roundtrip.json")
	assert_true(GobnomEditorLogic.save_doc(path, copy), "nach /tmp gespeichert")
	var loaded := GobnomEditorLogic.load_doc(path)
	var reloaded := GobnomEditorLogic.level_ref(loaded, "campaign", 1)
	assert_eq(Vector2(reloaded["candy"]["x"], reloaded["candy"]["y"]), Vector2(300, 150))
	assert_eq((reloaded["bubbles"] as Array).size(), 1, "Bubble überlebt Roundtrip")
	var balance := GobnomData.load_balance()
	assert_true(GobnomEditorLogic.structural_errors(reloaded, balance).is_empty(), "schema-valide")
	var original := GobnomEditorLogic.level_ref(doc, "campaign", 1)
	assert_almost(float(original["candy"]["x"]), 480.0, 1e-4, "Original unberührt")


func test_editor_validate_mit_echtem_solver() -> void:
	# Der Validierungs-Knopf gegen das ECHTE Kampagnen-Level 1: der
	# bestehende Auto-Solver beweist Lösbarkeit, die Flugbahn ist gefüllt.
	var doc := GobnomEditorLogic.load_doc(GobnomData.LEVELS_PATH)
	var level: Dictionary = GobnomEditorLogic.level_ref(doc, "campaign", 1).duplicate(true)
	var balance := GobnomData.load_balance()
	var result := GobnomEditorLogic.validate(level, balance)
	assert_true(bool(result["ok"]), "Level 1 ist lösbar (Solver won)")
	assert_true(bool((result["solver"] as Dictionary).get("won", false)), "Solver-Report won")
	assert_true((result["path"] as Array[Vector2]).size() > 2, "Candy-Flugbahn vorhanden")


class FakeGameState:
	extends Node
	## Duck-Typing-GameState fürs Kalibrier-UI (state()/update(mutator)).

	var data := {}

	func state() -> Dictionary:
		return data

	func update(mutator: Callable) -> void:
		mutator.call(data)


class QualityMock:
	extends RefCounted
	## Duck-Typing-Quality (applied_bundle) für die Budget-Schwelle.

	var bundle := {}

	func applied_bundle() -> Dictionary:
		return bundle

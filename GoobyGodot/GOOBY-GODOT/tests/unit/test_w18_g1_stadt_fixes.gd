extends TestCase
## W18/4 G1 — Wächter für die Playtest-Blocker der Stadt-Welle:
## B7  Parkplatz-Pads: STRASSENSEITIGES Ort-Tile + Pad (inkl. Auto-Radius)
##     außerhalb ALLER Gebäude-/Parker-Collider (Loop über alle Orte).
## B8  Reise-Abschluss überlebt das App-free: Cutscene-fertig bucht GENAU
##     einmal; stirbt die Cutscene unfertig (App-Kill), wird erstattet —
##     kein Geldverlust ohne Leistung, egal welcher Pfad.
## B1  Betreten-Gate ruft OrtKatalog.ist_offen mit der INJIZIERTEN Uhr:
##     Wochenmarkt Sa 10 Uhr offen, So zu (Toast statt Route).
## B9  vacation.phase = away → Home OHNE Gooby (+ Urlaubs-Hinweis), Türen/
##     Baumodus crashen nicht, Möbel-Lieferung wird verschoben.

const SaveSchema := preload("res://scripts/state/save_schema.gd")
const GameStateScript := preload("res://scripts/state/game_state.gd")
const ClockScript := preload("res://scripts/logic/clock.gd")
const Vacation := preload("res://scripts/logic/vacation.gd")
const WohnzimmerScene := preload("res://scenes/home/wohnzimmer.tscn")

## Sa 2026-01-03 / So 2026-01-04, jeweils 10:00 „lokale“ Wanduhr-Zeit.
const SAMSTAG_10 := {"year": 2026, "month": 1, "day": 3, "hour": 10, "minute": 0, "second": 0}
const SONNTAG_10 := {"year": 2026, "month": 1, "day": 4, "hour": 10, "minute": 0, "second": 0}

var _seq := 0


## GameState-Double mit pinnbarer Clock (Muster test_g4_travel/_rhythmus).
class FakeGameState:
	extends RefCounted
	var s: Dictionary = {}
	var clock := ClockScript.new()

	func _init() -> void:
		s = SaveSchema.default_state(1768478400000)

	func state() -> Dictionary:
		return s

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = s
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func set_value(path: String, wert: Variant) -> void:
		var teile := path.split(".")
		var node: Dictionary = s
		for i in teile.size() - 1:
			if not (node.get(teile[i]) is Dictionary):
				node[teile[i]] = {}
			node = node[teile[i]]
		node[teile[teile.size() - 1]] = wert

	func update(mutator: Callable) -> void:
		mutator.call(s)

	func notify_slice_changed(_slice_id: String) -> void:
		pass


## Epoch-ms, deren LOKALE Lesart (Bias wie CityScene/_stunde) exakt auf das
## Wanduhr-Dict fällt — deterministisch in jeder VM-Zeitzone.
func _lokale_ms(wanduhr: Dictionary) -> int:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var lokal_s := int(Time.get_unix_time_from_datetime_dict(wanduhr))
	return (lokal_s - bias * 60) * 1000


## ------------------------------------------------------ B7: Parkplätze


func test_b7_alle_parkpads_strassenseitig_und_kollisionsfrei() -> void:
	var karte := CityMap.laden()
	var host := Node3D.new()
	tree.root.add_child(host)
	# Realer Collider-Bestand: Ort-Tiles (7,5 m), Deko-/Kulissen-Gebäude,
	# Bordstein-Parker — exakt die Liste, gegen die das Auto kollidiert.
	var bau := CityBau.new(host, karte, CityAmbiente.licht_profil(12.0), 12.0)
	bau.baue_orte()
	bau.baue_deko()
	bau.baue_kulisse()
	assert_true(bau.colliders.size() > 0, "Collider-Bestand aufgebaut")
	for eintrag: Dictionary in karte.orte():
		var id := str(eintrag.get("id", ""))
		var strasse := CityMap._tile_von(eintrag.get("strasse", [0, 0]))
		assert_true(karte.ist_strasse(strasse), "%s: strasse ist echte Straße" % id)
		var park := karte.parkplatz_welt(id)
		var pad_tile := karte.welt_zu_tile(park)
		var d := absi(pad_tile.x - strasse.x) + absi(pad_tile.y - strasse.y)
		assert_true(d <= 1, "%s: Pad-Tile grenzt an die Straße (Manhattan %d)" % [id, d])
		var frei := true
		for c: Dictionary in bau.colliders:
			if (
				park.x + CityCarFeel.CAR_RADIUS_M > float(c["min_x"])
				and park.x - CityCarFeel.CAR_RADIUS_M < float(c["max_x"])
				and park.z + CityCarFeel.CAR_RADIUS_M > float(c["min_z"])
				and park.z - CityCarFeel.CAR_RADIUS_M < float(c["max_z"])
			):
				frei = false
		assert_true(frei, "%s: Pad + Auto-Radius außerhalb aller Collider" % id)
	host.queue_free()
	await wait_frames(1)


func test_b7_flughafen_pad_am_strassen_tile() -> void:
	var karte := CityMap.laden()
	# Regression Report B7: tiles[0]=[0,2] grenzt NICHT an strasse=[0,4] —
	# park_tile muss [0,3] wählen, das Pad liegt Richtung Zubringer.
	assert_eq(
		CityMap.park_tile([[0, 2], [0, 3]], Vector2i(0, 4)),
		Vector2i(0, 3),
		"straßenseitiges Tile gewinnt"
	)
	var park := karte.parkplatz_welt("flughafen")
	var tile_mitte := karte.tile_zu_welt(Vector2i(0, 3))
	var strasse_mitte := karte.tile_zu_welt(Vector2i(0, 4))
	var zur_strasse := Vector2(park.x, park.z).distance_to(
		Vector2(strasse_mitte.x, strasse_mitte.z)
	)
	var zum_tile := Vector2(park.x, park.z).distance_to(Vector2(tile_mitte.x, tile_mitte.z))
	assert_true(zur_strasse < karte.tile_m, "Pad liegt am Zubringer, nicht im Gebäude")
	assert_true(zum_tile > 7.5 + CityCarFeel.CAR_RADIUS_M, "Pad + Auto vor dem 7,5-m-Collider")


## ------------------------------------------- B8: Buchung überlebt App-free


func test_b8_cutscene_fertig_bucht_genau_einmal() -> void:
	var gs := FakeGameState.new()
	gs.set_value("economy.coins", 310)
	CityState.save_taxi_slice(
		gs, {"state": TaxiLogic.STATE_FAHRT, "gerufenAt": 1, "ankunftAt": 2, "zielId": "beach"}
	)
	# Statische Verdrahtung — die ReiseApp existiert hier bewusst NICHT
	# (im Spiel ist sie beim fertig-Signal bereits queue_free()d).
	# Der globale Router gehört nicht zu dieser isolierten Buchungsprobe:
	# busy verhindert die echte Heimreise, ohne eine unbekannte Fixture-
	# Route als Engine-ERROR zu protokollieren.
	var router := tree.root.get_node_or_null("SceneRouter")
	var router_war_busy := bool(router.get("_busy")) if router != null else false
	if router != null:
		router.set("_busy", true)
	var cutscene: ReiseCutscene = ReiseApp.starte_abflug_cutscene(tree.root, "beach", gs)
	cutscene.skip()
	var gebucht := await wait_until(
		func() -> bool: return str(Vacation.slice_of(gs.state())["phase"]) == Vacation.PHASE_AWAY,
		15000
	)
	assert_true(gebucht, "Cutscene-fertig bucht den Urlaub OHNE lebende ReiseApp")
	var v := Vacation.slice_of(gs.state())
	assert_eq(str(v["destId"]), "beach", "Ziel aus der Cutscene")
	assert_true(int(v["returnAt"]) > 0, "returnAt gestempelt")
	assert_eq(str(CityState.taxi_slice(gs)["state"]), TaxiLogic.STATE_IDLE, "Taxi abgeschlossen")
	assert_eq(int(gs.get_value("economy.coins", 0)), 310, "Happy Path: keine Erstattung")
	# GENAU einmal: der Abschluss räumt die Cutscene weg — ihr tree_exiting
	# feuert dabei in _erstatte_falls_unfertig, der Latch muss Doppel-
	# Buchung/Nach-Erstattung blocken (Geister-Flugzeug-Regression).
	var return_at := int(v["returnAt"])
	# weakref statt Direkt-Capture: die Lambda liefe sonst nach dem free
	# in den „Lambda capture was freed“-Engine-Error (Log-Rauschen).
	var schwach: WeakRef = weakref(cutscene)
	var weg := await wait_until(func() -> bool: return schwach.get_ref() == null, 5000)
	assert_true(weg, "kein Geister-Flugzeug: Cutscene räumt sich weg")
	assert_eq(int(Vacation.slice_of(gs.state())["returnAt"]), return_at, "kein zweites Buchen")
	assert_eq(int(gs.get_value("economy.coins", 0)), 310, "keine Erstattung nach Abschluss")
	if router != null:
		router.set("_busy", router_war_busy)


func test_b8_app_kill_mitten_in_cutscene_erstattet() -> void:
	var gs := FakeGameState.new()
	# Nach Buchung Strand: 500 − 180 (Reise) − 10 (Taxi) = 310 in der Kasse.
	gs.set_value("economy.coins", 310)
	CityState.save_taxi_slice(
		gs, {"state": TaxiLogic.STATE_FAHRT, "gerufenAt": 1, "ankunftAt": 2, "zielId": "beach"}
	)
	var cutscene: ReiseCutscene = ReiseApp.starte_abflug_cutscene(tree.root, "beach", gs)
	# App-Kill mitten in der Cutscene: Node stirbt VOR dem fertig-Signal.
	cutscene.queue_free()
	var erstattet := await wait_until(
		func() -> bool: return int(gs.get_value("economy.coins", 0)) == 500, 5000
	)
	assert_true(erstattet, "Kill unfertig → Reisepreis 180 + Taxi 10 zurück (310→500)")
	assert_eq(
		str(Vacation.slice_of(gs.state())["phase"]),
		Vacation.PHASE_NONE,
		"kein halber Urlaub gebucht"
	)
	assert_eq(str(CityState.taxi_slice(gs)["state"]), TaxiLogic.STATE_IDLE, "Taxi aufgeräumt")


## --------------------------------------------- B1: Öffnungszeiten-Gate


func test_b1_betreten_gate_prueft_ist_offen_mit_injizierter_uhr() -> void:
	var gs := FakeGameState.new()
	gs.clock.pin(_lokale_ms(SONNTAG_10))
	var city: CityScene = load("res://scenes/city/city_scene.tscn").instantiate()
	city.game_state_override = gs
	tree.root.add_child(city)
	await wait_frames(3)
	var angefordert: Array = []
	city.ort_betreten_angefordert.connect(func(ort_id: String) -> void: angefordert.append(ort_id))
	# Sonntag 10:00: Regel sagt zu — Gate blockt VOR Energie-Abzug/Route.
	assert_false(city.ort_offen_jetzt("wochenmarkt"), "So 10 Uhr: Markt zu")
	var energie_vorher := float(gs.get_value("gooby.stats.energy", 0.0))
	city._on_betreten("wochenmarkt")
	assert_eq(angefordert.size(), 0, "geschlossen: kein Betreten angefordert")
	assert_almost(
		float(gs.get_value("gooby.stats.energy", 0.0)),
		energie_vorher,
		0.001,
		"geschlossen: keine Energie abgezogen"
	)
	# Andere Orte ohne Regel bleiben So offen (kein Kollateralschaden).
	assert_true(city.ort_offen_jetzt("rehwei"), "Orte ohne oeffnung-Block: immer offen")
	# Samstag 10:00 (dieselbe injizierte Uhr, nur umgepinnt): Markt offen.
	gs.clock.pin(_lokale_ms(SAMSTAG_10))
	assert_true(city.ort_offen_jetzt("wochenmarkt"), "Sa 10 Uhr: Markt offen")
	# Die Probe misst Gate + Signal, nicht einen echten Szenenwechsel. Route
	# anmelden und den globalen Router kurz busy setzen, damit goto sauber
	# in pending landet statt eine unregistrierte Fixture-Route zu loggen.
	var router := tree.root.get_node_or_null("SceneRouter")
	var router_war_busy := bool(router.get("_busy")) if router != null else false
	if router != null:
		var markt := city.karte.ort("wochenmarkt")
		router.register_route(&"city/ort/wochenmarkt", str(markt.get("szene", "")))
		router.set("_busy", true)
	city._on_betreten("wochenmarkt")
	assert_eq(angefordert, ["wochenmarkt"], "offen: Betreten läuft durch")
	assert_true(
		float(gs.get_value("gooby.stats.energy", 0.0)) < energie_vorher,
		"offen: Energie-Kosten wie gehabt"
	)
	if router != null:
		router.set("_pending", {})
		router.set("_busy", router_war_busy)
	city.queue_free()
	await wait_frames(2)


func test_b1_geschlossen_key_bleibt_der_vorhandene_text() -> void:
	var karte := CityMap.laden()
	assert_eq(
		OrtKatalog.geschlossen_key("wochenmarkt", karte),
		"city.ort.nur_samstag",
		"Samstags-Regel nutzt den vorhandenen nur_samstag-Text"
	)
	assert_false(I18nService.t("city.ort.nur_samstag").begins_with("city."), "Text ist übersetzt")


## ------------------------------------------------- B9: Home ohne Gooby


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://w18g1_tests/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	return gs


func _away_slice(now_ms: int) -> Dictionary:
	var v := Vacation.default_slice()
	v["phase"] = Vacation.PHASE_AWAY
	v["destId"] = "beach"
	v["bookedAt"] = now_ms
	v["returnAt"] = now_ms + 3 * Vacation.MS_PER_DAY
	v["pickupBy"] = now_ms + 4 * Vacation.MS_PER_DAY
	return v


func test_b9_away_phase_home_ohne_gooby_mit_hinweis() -> void:
	var gs := _fresh_gs()
	gs.set_value("vacation", _away_slice(int(Time.get_unix_time_from_system() * 1000.0)))
	var room: RoomBase = WohnzimmerScene.instantiate()
	room.game_state_override = gs
	room.tuer_confirm_override = 0
	tree.root.add_child(room)
	await wait_frames(3)
	assert_true(room.gooby_im_urlaub(), "away-Phase erkannt")
	assert_eq(room.gooby(), null, "Gooby sitzt NICHT daheim auf dem Sofa")
	assert_ne(room._bubble, null, "Urlaubs-Hinweis steht (travel.weg-Strings)")
	# Seele bleibt stumm: ohne Gooby hängt sich KEIN Reactions-Runner an
	# (sonst überschriebe der Tageszeit-Gruß den Hinweis als Geister-Stimme).
	assert_eq(GoobyReactions.attach_to(room), null, "keine Geister-Stimme im leeren Raum")
	assert_eq(room.get_node_or_null("GoobyReactions"), null, "Runner nicht angehängt")
	# Tür-Tap + Baumodus dürfen ohne Gooby nicht crashen (Null-Guards).
	room._on_door_tapped("living_kueche")
	room.open_build_mode()
	assert_true(room.is_build_mode_active(), "Baumodus öffnet ohne Gooby")
	room.get_node("BuildMode").close()
	await wait_frames(2)
	room.queue_free()
	await wait_frames(2)
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


func test_b9_phase_none_spawnt_gooby_wie_immer() -> void:
	var gs := _fresh_gs()
	var room: RoomBase = WohnzimmerScene.instantiate()
	room.game_state_override = gs
	tree.root.add_child(room)
	await wait_frames(3)
	assert_false(room.gooby_im_urlaub(), "ohne Urlaub keine away-Erkennung")
	assert_ne(room.gooby(), null, "Normalfall unverändert: Gooby spawnt")
	room.queue_free()
	await wait_frames(2)
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


func test_b9_lieferung_wird_ohne_gooby_verschoben() -> void:
	var gs := _fresh_gs()
	gs.set_value("vacation", _away_slice(int(Time.get_unix_time_from_system() * 1000.0)))
	DeliveryCutscene.bestellen(gs, "chair", 1)
	assert_eq(DeliveryCutscene.offene(gs).size(), 1, "Bestellung wartet")
	var room: RoomBase = (load("res://scenes/home/garten.tscn") as PackedScene).instantiate()
	room.game_state_override = gs
	tree.root.add_child(room)
	# GardenHost startet die Liefer-Cutscene deferred — ohne Gooby räumt
	# sie sich weg, die Bestellung bleibt OFFEN (kein Crash, kein Verlust).
	await wait_frames(5)
	assert_eq(DeliveryCutscene.offene(gs).size(), 1, "Lieferung verschoben, nicht verloren")
	assert_eq(room.get_node_or_null("DeliveryCutscene"), null, "Cutscene sauber weggeräumt")
	room.queue_free()
	await wait_frames(2)
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()

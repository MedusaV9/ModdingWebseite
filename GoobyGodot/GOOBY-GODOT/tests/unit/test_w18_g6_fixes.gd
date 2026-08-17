extends TestCase
## W18/4 (Fix-Agent G6) — Wächter für drei Playtest-Befunde:
## - B12 (Stadt): POW-Parkfeld-Kollider-Punch — (a) das Kriech-Minimum der
##   Bremse gilt NICHT auf Park-Pads (Auto kann wirklich stehen), (b) die
##   Tiefen-Depenetration schiebt durch die NÄCHSTE Kolliderseite raus
##   (kein 16-m-Punch mehr nach Westen), (c) JEDES Park-Pad liegt mit
##   Auto-Radius-Luft AUSSERHALB der Ort-Fassaden-Kollider.
## - B5 (Ranch): Heudieb „1 Tap = 2 Krähen“ — EIN Eingabepfad: die
##   Requisiten sind nicht mehr ray-pickable (kein Physics-Picking-Doppel),
##   der Touch-Zwilling der Maus-Emulation wird konsumiert; ein Tap nimmt
##   den Zähler EXAKT um 1.
## - B9 (Goo und Bye): NPC-Politur — Kassen-Standpunkt mit Körperabstand
##   vor dem Tresen, Bummler-Route außerhalb des Tür-Korridors des
##   Kunden-Abgangs, und OrtLeben richtet seine Figuren JEDEN Takt auf
##   (Up = +Y, Orientierungs-Audit: kein „liegender Abgangs-Hoppler“).

var _saved_root_size := Vector2i.ZERO


## GameState-Double (Muster test_g4_ranchmp): dotted get/set reicht — der
## Heudieb-Test löst das Event nie komplett auf (keine Reward-Pfade).
class FakeGameState:
	extends RefCounted
	var s: Dictionary = {}

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


## Trägerszene für den Event-Host (Hof-Vertrag: zeige_meldung + Anker).
class TraegerSzene:
	extends Node3D
	var meldungen: Array[String] = []

	func zeige_meldung(text: String) -> void:
		meldungen.append(text)

	func event_anker() -> Vector3:
		return Vector3(0.0, 0.0, -30.0)


func _pin(size: Vector2i) -> void:
	if _saved_root_size == Vector2i.ZERO:
		_saved_root_size = tree.root.size
	tree.root.size = size
	tree.root.size_changed.emit()
	await wait_frames(2)


func _unpin() -> void:
	if _saved_root_size != Vector2i.ZERO:
		tree.root.size = _saved_root_size
		_saved_root_size = Vector2i.ZERO
	tree.root.size_changed.emit()
	await wait_frames(2)


# ------------------------------------------------------- B12: Bremse + Pad


## Kriech-Minimum bleibt der Web-Kontrakt (§C7.2) — NUR mit stillstand_ok
## (Park-Pad) darf die Bremse bis 0 durchziehen.
func test_step_speed_pad_stopp_und_kriechminimum() -> void:
	assert_almost(CityCarFeel.step_speed(1.5, 9.0, true, 1.0), 1.2, 1e-9, "abseits: Kriechen")
	assert_almost(CityCarFeel.step_speed(0.0, 9.0, true, 1.0), 1.2, 1e-9, "abseits: nie 0")
	assert_almost(CityCarFeel.step_speed(1.5, 9.0, true, 1.0, true), 0.0, 1e-9, "Pad: Stopp")
	assert_almost(CityCarFeel.step_speed(0.0, 9.0, true, 0.1, true), 0.0, 1e-9, "Pad: bleibt 0")
	assert_almost(
		CityCarFeel.step_speed(9.0, 9.0, true, 0.5, true), 3.0, 1e-9, "Pad: normale Verzögerung"
	)


## Gebremstes Auto AUF dem Pad steht über viele Physik-Ticks still (kein
## Kriechen, kein Spur-Assist-Seitenzug); abseits des Pads kriecht es
## unverändert mit 1,2 m/s (Fahren bleibt Fahren).
func test_auto_steht_auf_parkpad_stabil() -> void:
	var auto := CarController.new()
	auto.park_pads = [Vector3(49.5, 0.0, -10.0)]
	auto.park_pad_radius = 7.0
	auto.teleport(49.5, -10.0, 0.3)
	auto.set_brake(true)
	auto.speed = 2.0
	for i in 120:
		auto.update_fahrt(1.0 / 60.0)
	# Ausrollen (2 m/s → 0 in ~0,2 s) darf kurz Weg machen (inkl. Spur-
	# Assist-Restzug bei heading≠Kardinale) — aber DANN steht das Auto
	# ABSOLUT still: kein 1,2-m/s-Kriechen mehr (das wären 2,4 m je 2 s).
	assert_almost(auto.speed, 0.0, 1e-6, "Voll-Stopp auf dem Pad")
	var delta := Vector2(auto.position.x, auto.position.z).distance_to(Vector2(49.5, -10.0))
	assert_true(delta < 1.5, "Ausrollweg bleibt klein (delta=%.3f m)" % delta)
	var stand := auto.position
	for i in 120:
		auto.update_fahrt(1.0 / 60.0)
	assert_almost(auto.position.x, stand.x, 1e-6, "steht: kein Kriechen (x)")
	assert_almost(auto.position.z, stand.z, 1e-6, "steht: kein Kriechen (z)")
	# Gegenprobe abseits des Pads: Kriech-Minimum wie gehabt.
	auto.teleport(0.0, 0.0, 0.0)
	auto.set_brake(true)
	auto.speed = 2.0
	for i in 60:
		auto.update_fahrt(1.0 / 60.0)
	assert_almost(auto.speed, 1.2, 1e-6, "abseits: 1,2-m/s-Kriechen bleibt")
	assert_true(auto.position.z > 0.5, "abseits: das Auto kriecht weiter")
	auto.free()


## Tiefen-Depenetration (Zentrum im AABB): raus durch die NÄCHSTE Seite —
## der historische Fall (47,−10) im POW-Kollider landete bei x=31 (16-m-
## Punch nach Westen), jetzt bei x=49 (0,5 m + Radius nach Osten).
func test_kollider_depenetration_naechste_seite() -> void:
	var auto := CarController.new()
	var box := {"min_x": 32.5, "max_x": 47.5, "min_z": -17.5, "max_z": -2.5}
	auto.colliders = [box]
	auto.teleport(47.0, -10.0, 0.0)
	auto._kollidiere()
	assert_almost(auto.position.x, 49.0, 1e-6, "raus durch die Ost-Seite (max_x + r)")
	assert_almost(auto.position.z, -10.0, 1e-6, "z unangetastet")
	auto.teleport(33.0, -10.0, 0.0)
	auto._kollidiere()
	assert_almost(auto.position.x, 31.0, 1e-6, "West bleibt West, wenn West am nächsten ist")
	auto.teleport(40.0, -3.0, 0.0)
	auto._kollidiere()
	assert_almost(auto.position.z, -1.0, 1e-6, "raus durch die Süd-Seite (max_z + r)")
	auto.free()


## POW-Parkfeld end-to-end (Karte + Ort-Kollider wie city_bau sie baut):
## Spawn auf dem Pad mit gehaltener Bremse → Positions-Delta im ERSTEN
## Physik-Tick < 0,5 m (vorher: 16 m), danach dauerhaft stabil.
func test_pow_pad_spawn_ohne_punch() -> void:
	var karte := CityMap.laden()
	assert_true(karte.ist_geladen(), "city_map.json lädt")
	var auto := CarController.new()
	auto.colliders = _ort_kollider(karte)
	auto.park_pads = [karte.parkplatz_welt("pow")]
	auto.park_pad_radius = karte.park_radius() + 3.0
	var pad: Vector3 = karte.parkplatz_welt("pow")
	auto.teleport(pad.x, pad.z, PI / 2.0)
	auto.set_brake(true)
	auto.update_fahrt(1.0 / 60.0)
	var tick1 := Vector2(auto.position.x, auto.position.z).distance_to(Vector2(pad.x, pad.z))
	assert_true(tick1 < 0.5, "kein Punch im ersten Tick (delta=%.3f m)" % tick1)
	for i in 300:
		auto.update_fahrt(1.0 / 60.0)
	var dauer := Vector2(auto.position.x, auto.position.z).distance_to(Vector2(pad.x, pad.z))
	assert_true(dauer < 0.5, "Auto bleibt am Trigger (delta=%.3f m)" % dauer)
	assert_true(dauer <= karte.park_radius() + 3.0, "im Prompt-Radius")
	auto.free()


## JEDES Park-Pad (alle Orte + zuhause) liegt mit Auto-Radius-Luft
## AUSSERHALB aller Ort-Fassaden-Kollider (ORT_COLLIDER_HALB_M) — sonst
## schiebt die Depenetration das Auto vom Trigger (B12/B7-Klasse).
func test_alle_parkpads_ausserhalb_der_ort_kollider() -> void:
	var karte := CityMap.laden()
	assert_true(karte.ist_geladen(), "city_map.json lädt")
	var boxen := _ort_kollider(karte)
	var ids: Array[String] = ["zuhause"]
	for eintrag: Dictionary in karte.orte():
		ids.append(str(eintrag.get("id", "")))
	for id in ids:
		var pad: Vector3 = karte.parkplatz_welt(id)
		for box: Dictionary in boxen:
			var cx := clampf(pad.x, float(box["min_x"]), float(box["max_x"]))
			var cz := clampf(pad.z, float(box["min_z"]), float(box["max_z"]))
			var abstand := Vector2(pad.x - cx, pad.z - cz).length()
			assert_true(
				abstand > CityCarFeel.CAR_RADIUS_M,
				"Pad '%s' braucht Radius-Luft zum Kollider (%.2f m)" % [id, abstand]
			)


## Ort-Tile-Kollider exakt wie CityBau.baue_orte sie anlegt.
func _ort_kollider(karte: CityMap) -> Array[Dictionary]:
	var halb := CityBau.ORT_COLLIDER_HALB_M
	var boxen: Array[Dictionary] = []
	for eintrag: Dictionary in karte.orte():
		for tile_raw: Variant in eintrag.get("tiles", []):
			var mitte: Vector3 = karte.tile_zu_welt(CityMap._tile_von(tile_raw))
			(
				boxen
				. append(
					{
						"min_x": mitte.x - halb,
						"max_x": mitte.x + halb,
						"min_z": mitte.z - halb,
						"max_z": mitte.z + halb,
					}
				)
			)
	return boxen


# ------------------------------------------------------- B5: Heudieb-Tap


## EIN Eingabepfad: Requisiten sind NICHT ray-pickable (kein Physics-
## Picking-Doppel), und der Touch-Zwilling desselben Tipps (Maus-Emulation)
## wird im selben Frame verworfen — der Krähen-Zähler fällt EXAKT um 1.
func test_heudieb_ein_tap_genau_eine_kraehe() -> void:
	await _pin(Vector2i(1280, 720))
	var szene := TraegerSzene.new()
	tree.root.add_child(szene)
	var cam := Camera3D.new()
	szene.add_child(cam)
	cam.look_at_from_position(
		Vector3(0.0, 1.4, 0.0), szene.event_anker() + Vector3(0.0, 1.4, 0.0), Vector3.UP
	)
	cam.current = true
	var host := RanchEventHost.new()
	host.game_state_override = FakeGameState.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	host.rng_override = rng
	szene.add_child(host)
	host.setup(szene)
	host.start({"id": "heudieb", "szene_setup": "ranch_heudieb", "props": 3})
	await wait_frames(2)
	assert_eq(host._remaining, 3, "drei Krähen sitzen auf dem Heu")
	for prop: Node3D in host._props:
		for area: Node in prop.find_children("*", "Area3D", true, false):
			assert_false(
				(area as Area3D).input_ray_pickable,
				"Ranch-Requisiten sind NICHT ray-pickable (ein Eingabepfad)"
			)
	# Ein Spieler-Tipp = Maus-Klick + emulierter Touch-Zwilling im SELBEN
	# Frame (pointing/emulate_touch_from_mouse) — beide auf dieselbe Krähe.
	var ziel: Node3D = host._tap_handler.keys()[0]
	var punkt := cam.unproject_position(ziel.global_position)
	host._unhandled_input(_klick(punkt))
	assert_eq(host._remaining, 2, "Maus-Hälfte verscheucht genau EINE Krähe")
	host._unhandled_input(_touch(punkt))
	assert_eq(host._remaining, 2, "Touch-Zwilling verscheucht KEINE zweite")
	assert_eq(host._tap_handler.size(), 2, "genau eine Requisite abgeräumt")
	# Nächster Frame, nächster Tipp: wieder exakt −1.
	await wait_frames(1)
	var ziel2: Node3D = host._tap_handler.keys()[0]
	var punkt2 := cam.unproject_position(ziel2.global_position)
	host._unhandled_input(_klick(punkt2))
	host._unhandled_input(_touch(punkt2))
	assert_eq(host._remaining, 1, "zweiter Tipp: Zähler exakt −1")
	host._clear_props()
	szene.queue_free()
	await _unpin()


func _klick(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	ev.global_position = pos
	return ev


func _touch(pos: Vector2) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.pressed = true
	ev.position = pos
	return ev


# ------------------------------------------------------- B9: NPC-Politur


## Kassen-Standpunkt mit Körperabstand vor dem Tresen und Bummler-Route
## außerhalb des Tür-Korridors (KASSE_STOP → TUER_POS) des Kunden-Abgangs.
func test_goobye_choreo_abstaende() -> void:
	var kasse := GoobyeLadenScene.KASSE_STOP
	assert_true(
		kasse.z - GoobyeLadenScene.KASSE_POS.z >= 1.5,
		"Kunde steht mit Körperabstand VOR dem Tresen (kein Mesh-Clipping)"
	)
	var von := Vector2(kasse.x, kasse.z)
	var nach := Vector2(GoobyeLadenScene.TUER_POS.x, GoobyeLadenScene.TUER_POS.z)
	for punkt: Vector3 in GoobyeLadenLeben.PUNKTE:
		assert_true(punkt.x <= 3.4, "Bummler bleiben vor dem Tür-/Kamerarand (x=%.1f)" % punkt.x)
		var nahpunkt := Geometry2D.get_closest_point_to_segment(
			Vector2(punkt.x, punkt.z), von, nach
		)
		var abstand := Vector2(punkt.x, punkt.z).distance_to(nahpunkt)
		assert_true(
			abstand >= 1.0,
			"Bummler-Punkt (%.1f, %.1f) kreuzt den Abgangs-Korridor nicht" % [punkt.x, punkt.z]
		)


## OrtLeben richtet seine Figuren JEDEN Takt komplett auf (Up = +Y) — ein
## von außen/vorher ererbter X/Z-Kipp wird im nächsten Update genullt.
func test_ort_leben_aufrichtung_up_y() -> void:
	var leben := OrtLeben.new()
	leben.konfig = {
		"besucher": 2,
		"ort_id": "goobye_laden",
		"punkte": Array(GoobyeLadenLeben.PUNKTE),
		"sprueche": "goobye",
	}
	leben.seed_override = 7
	leben.reduced_override = 0
	leben.auto_zeit = false
	leben.stumm = true
	tree.root.add_child(leben)
	await wait_frames(2)
	var nodes := leben.besucher_nodes()
	assert_true(nodes.size() > 0, "Bummler gespawnt")
	# Kipp von außen simulieren (die historische „liegender Hoppler“-Pose).
	for node in nodes:
		node.rotation.x = 1.2
		node.rotation.z = -0.7
	leben.advance_zeit(1.5)
	for node in nodes:
		assert_almost(node.rotation.x, 0.0, 1e-6, "Aufrichtung nullt X-Kipp")
		assert_almost(node.rotation.z, 0.0, 1e-6, "Aufrichtung nullt Z-Kipp")
		var up := node.global_transform.basis.y.normalized()
		assert_true(up.dot(Vector3.UP) > 0.999, "Up-Vektor bleibt +Y")
	leben.queue_free()
	await wait_frames(1)

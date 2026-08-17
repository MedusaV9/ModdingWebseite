extends TestCase
## FIX-5 „Liebe zum Detail" — die GEBAUTE Szene bei Tag und Nacht: dichte
## Kulisse (MultiMesh-Gruppen), Ampeln vorhanden, nachts leuchten Fenster/
## Laternen-Birnen und die Ampeln blinken gelb, tags regeln sie rot/grün;
## der Spawn steht in der Hausausfahrt und das Ausparken läuft an.

const CitySceneScript := preload("res://scripts/city/city_scene.gd")


## GameState-Double (Muster test_city_orte): dotted get/set + update.
class FakeGameState:
	extends RefCounted
	var state: Dictionary = {"city": {}, "gooby": {"stats": {"energy": 100.0}}}

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = state
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func set_value(path: String, wert: Variant) -> void:
		var teile := path.split(".")
		var node: Dictionary = state
		for i in teile.size() - 1:
			if not (node.get(teile[i]) is Dictionary):
				node[teile[i]] = {}
			node = node[teile[i]]
		node[teile[teile.size() - 1]] = wert

	func update(mutator: Callable) -> void:
		mutator.call(state)

	func notify_slice_changed(_slice_id: String) -> void:
		pass


func _baue_stadt(stunde: float) -> CityScene:
	var city: CityScene = CitySceneScript.new()
	city.game_state_override = FakeGameState.new()
	city.stunde_override = stunde
	tree.root.add_child(city)
	return city


func _reisse_ab(city: CityScene) -> void:
	city.queue_free()
	await wait_frames(2)


func _multimesh_instanzen(unter: Node) -> int:
	var summe := 0
	for mmi in unter.find_children("*", "MultiMeshInstance3D", true, false):
		summe += (mmi as MultiMeshInstance3D).multimesh.instance_count
	return summe


func test_stadt_ist_dicht_gebaut_und_im_budget() -> void:
	var city := _baue_stadt(12.0)
	await wait_frames(2)
	var kulisse := city.get_node_or_null("Kulisse")
	assert_true(kulisse != null, "Kulissen-Knoten existiert")
	if kulisse == null:
		await _reisse_ab(city)
		return
	var instanzen := _multimesh_instanzen(kulisse)
	assert_true(instanzen >= 250, "dichte Kulisse in der Szene: %d Instanzen" % instanzen)
	# MultiMesh-Versprechen: die GANZE Stadt (Straßen+Laternen+Kulisse)
	# braucht nur wenige Dutzend Mesh-Knoten statt Hunderte.
	var knoten := city.find_children("*", "MultiMeshInstance3D", true, false).size()
	assert_true(knoten < 140, "MultiMesh-Knoten im Rahmen: %d" % knoten)
	assert_true(city.get_node_or_null("Ampeln") != null, "Ampeln stehen")
	assert_true(city.get_node_or_null("Strassen") != null, "Straßen stehen")
	assert_true(city.get_node_or_null("Fensterlichter") == null, "mittags keine Fensterlichter")
	assert_true(city._verkehr.size() >= CityVerkehr.TAG_AUTOS - 1, "tags viel Verkehr")
	assert_true(city._fussgaenger.size() >= CityFussgaenger.TAG_ANZAHL - 1, "tags viele Fußgänger")
	assert_true(city.get_node_or_null("Voegel") != null, "tags kreisen Vögel")
	# Tags regeln die Ampeln rot/grün (nie gelb).
	await wait_frames(2)
	assert_true(
		(
			city._ampel_farben[0] == CityVerkehr.FARBE_GRUEN
			or city._ampel_farben[0] == CityVerkehr.FARBE_ROT
		),
		"Tag-Ampel regelt rot/grün"
	)
	await _reisse_ab(city)


func test_nachts_leuchten_fenster_laternen_und_ampeln_blinken() -> void:
	var city := _baue_stadt(22.0)
	await wait_frames(2)
	var fenster: MultiMeshInstance3D = city.get_node_or_null("Fensterlichter")
	assert_true(fenster != null, "nachts leuchten Fenster")
	if fenster != null:
		assert_true(fenster.multimesh.instance_count >= 30, "viele Fenster leuchten")
	var birnen := city.get_node_or_null("Laternen/Birnen")
	assert_true(birnen != null, "Laternen-Birnen leuchten nachts")
	assert_true(city._verkehr.size() <= CityVerkehr.NACHT_AUTOS, "nachts weniger Verkehr")
	assert_true(
		city._fussgaenger.size() <= CityFussgaenger.NACHT_ANZAHL, "nachts weniger Fußgänger"
	)
	assert_true(city.get_node_or_null("Voegel") == null, "nachts schlafen die Vögel")
	await wait_frames(2)
	assert_true(
		(
			city._ampel_farben[0] == CityVerkehr.FARBE_GELB
			or city._ampel_farben[0] == CityVerkehr.FARBE_AUS
		),
		"Nacht-Ampel blinkt gelb"
	)
	await _reisse_ab(city)


func test_spawn_parkt_in_der_einfahrt_und_parkt_rueckwaerts_aus() -> void:
	var city := _baue_stadt(12.0)
	await wait_frames(2)
	var einfahrt := city.karte.zuhause_einfahrt()
	var einfahrt_pos: Vector3 = einfahrt["pos"]
	var d := Vector2(city.auto.position.x, city.auto.position.z).distance_to(
		Vector2(einfahrt_pos.x, einfahrt_pos.z)
	)
	assert_true(d < 2.0, "Auto spawnt in der Einfahrt (Abstand %f m)" % d)
	assert_true(city._ausparken != null, "Ausparksequenz ist scharf")
	# Das Auto rangiert RÜCKWÄRTS Richtung Straße. Nicht auf eine feste
	# Frame-Zahl warten: unter Suite-Last sind die Deltas winzig, dann hat das
	# Auto nach 30 Frames real kaum Weg gemacht (flakiger Test). Stattdessen
	# auf die BEDINGUNG warten, mit großzügigem Frame-Deckel.
	var strasse := Vector3(einfahrt["strasse_pos"])
	var richtung := Vector3(einfahrt["richtung_haus"])
	var start_proj := (einfahrt_pos - strasse).dot(richtung)
	var proj := start_proj
	for _i in range(600):
		await wait_frames(1)
		proj = (city.auto.position - strasse).dot(richtung)
		if proj < start_proj - 0.2:
			break
	assert_true(
		proj < start_proj - 0.2, "Auto rangiert rückwärts zur Straße (%f→%f)" % [start_proj, proj]
	)
	# Manuelle Eingabe bricht ab.
	city._ausparken_abbrechen()
	assert_true(city._ausparken == null, "Daumen gewinnt: Sequenz abgebrochen")
	await _reisse_ab(city)


func test_leben_reduziert_halbiert_verkehr_und_fussgaenger() -> void:
	var city: CityScene = CitySceneScript.new()
	var gs := FakeGameState.new()
	gs.set_value("city.lebenReduziert", true)
	city.game_state_override = gs
	city.stunde_override = 12.0
	tree.root.add_child(city)
	await wait_frames(2)
	assert_true(city._verkehr.size() <= CityVerkehr.TAG_AUTOS / 2, "Spar-Modus: halber Verkehr")
	assert_true(
		city._fussgaenger.size() <= CityFussgaenger.TAG_ANZAHL / 2, "Spar-Modus: halbe Fußgänger"
	)
	assert_true(city.get_node_or_null("Voegel") == null, "Spar-Modus: keine Vögel")
	await _reisse_ab(city)

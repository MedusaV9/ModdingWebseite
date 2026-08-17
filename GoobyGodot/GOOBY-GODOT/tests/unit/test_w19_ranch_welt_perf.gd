extends TestCase
## W19 — Ranch-Welt-Aufbau-Performance: der Weltaufbau ist zweistufig
## (Essenz vor dem Reveal, Rest über WeltAufbauTakt gestreamt) und die
## teuren deterministischen Berechnungen (Streupläne, Chunk-Meshes)
## liegen in statischen Caches. Wächter: (1) die pure Budget-Logik des
## Takts respektiert ihr Frame-Budget und führt jeden Schritt genau
## einmal in Reihenfolge aus, (2) die Caches liefern BIT-IDENTISCHE
## Ergebnisse wie der Direktlauf (Determinismus!), (3) die Region-Szene
## ist nach dem gestückelten Aufbau vollständig funktional (Reveal früh,
## alle Zonen-Gruppen/Streu/Wildtiere nach dem Stream da).


## GameState-Double (Muster test_welt1_entdeckungen): dotted-Pfad-Werte
## + update(mutator) für Entdeckungs-Buchungen der Region-Szene.
class MiniGs:
	var werte: Dictionary = {}
	var state: Dictionary = {"economy": {"coins": 100}}

	func get_value(pfad: String, fallback: Variant = null) -> Variant:
		return werte.get(pfad, fallback)

	func set_value(pfad: String, wert: Variant) -> void:
		werte[pfad] = wert

	func update(mutator: Callable) -> void:
		mutator.call(state)


## Fake-Uhr für die Budget-Logik: jeder Schritt „kostet“ kosten_ms.
class FakeUhr:
	var jetzt := 0
	var kosten_ms := 2

	func zeit() -> int:
		return jetzt

	func schritt(protokoll: Array, id: int) -> void:
		protokoll.append(id)
		jetzt += kosten_ms


## ------------------------------------------------- Budget-Logik (pur)


func test_takt_respektiert_frame_budget() -> void:
	var uhr := FakeUhr.new()
	var takt := WeltAufbauTakt.new(4.0, uhr.zeit)
	var protokoll: Array = []
	for i in 7:
		takt.fuege_hinzu(uhr.schritt.bind(protokoll, i))
	assert_eq(takt.offen(), 7, "sieben Schritte geplant")
	# 2 Schritte à 2 ms erreichen das 4-ms-Budget → Frame abgeben.
	assert_eq(takt.tick(), 2, "Tick 1 stoppt am 4-ms-Budget")
	assert_eq(protokoll, [0, 1], "Reihenfolge bleibt Einfüge-Reihenfolge")
	assert_false(takt.fertig(), "nach Tick 1 noch offen")
	assert_eq(takt.tick(), 2, "Tick 2 stoppt am Budget")
	assert_eq(takt.tick(), 2, "Tick 3 stoppt am Budget")
	assert_eq(takt.tick(), 1, "Tick 4 arbeitet den Rest ab")
	assert_true(takt.fertig(), "alles abgearbeitet")
	assert_eq(protokoll, [0, 1, 2, 3, 4, 5, 6], "jeder Schritt genau einmal")
	assert_eq(takt.tick(), 0, "leerer Takt tut nichts")


func test_takt_teurer_schritt_gibt_sofort_ab() -> void:
	var uhr := FakeUhr.new()
	uhr.kosten_ms = 50
	var takt := WeltAufbauTakt.new(4.0, uhr.zeit)
	var protokoll: Array = []
	for i in 3:
		takt.fuege_hinzu(uhr.schritt.bind(protokoll, i))
	# Fortschritts-Garantie: mindestens EIN Schritt läuft pro Tick, aber
	# nach dem 50-ms-Schritt ist das Budget gerissen → sofort abgeben.
	assert_eq(takt.tick(), 1, "teurer Schritt beendet den Tick")
	assert_eq(takt.tick(), 1, "auch der zweite Tick nimmt nur einen")
	assert_eq(takt.tick(), 1, "dritter Tick nimmt den letzten")
	assert_true(takt.fertig())
	assert_eq(protokoll, [0, 1, 2])


func test_takt_alles_sofort_ignoriert_budget() -> void:
	var uhr := FakeUhr.new()
	uhr.kosten_ms = 100
	var takt := WeltAufbauTakt.new(4.0, uhr.zeit)
	var protokoll: Array = []
	for i in 5:
		takt.fuege_hinzu(uhr.schritt.bind(protokoll, i))
	assert_eq(takt.alles_sofort(), 5, "alles_sofort arbeitet alles ab")
	assert_true(takt.fertig())
	assert_eq(protokoll, [0, 1, 2, 3, 4])


func test_region_stream_budget_ist_hoechstens_vier_ms() -> void:
	assert_true(WeltAufbauTakt.BUDGET_MS <= 4.0, "Scheduler-Budget <= 4 ms")
	assert_eq(
		RanchRegionScene.AUFBAU_BUDGET_MS,
		WeltAufbauTakt.BUDGET_MS,
		"Region und Scheduler können nicht auseinanderdriften"
	)


## ------------------------------------------ Cache-Determinismus (Streu)


func test_streu_cache_liefert_bitidentische_plaene() -> void:
	RanchStreu.reset_for_tests()
	var direkt_a := RanchStreu.plaene(1.0)
	RanchStreu.reset_for_tests()
	var direkt_b := RanchStreu.plaene(1.0)
	var aus_cache := RanchStreu.plaene(1.0)
	assert_eq(direkt_a.size(), direkt_b.size(), "gleiche Sortenzahl je Direktlauf")
	assert_eq(direkt_b.size(), aus_cache.size(), "Cache hat alle Sorten")
	for i in direkt_a.size():
		var a: Dictionary = direkt_a[i]
		var b: Dictionary = direkt_b[i]
		var c: Dictionary = aus_cache[i]
		assert_eq(str(a["glb"]), str(b["glb"]), "Sorte %d gleich" % i)
		assert_eq(a["transforms"], b["transforms"], "Direktläufe bit-identisch (Sorte %d)" % i)
		assert_eq(b["transforms"], c["transforms"], "Cache bit-identisch (Sorte %d)" % i)
	RanchStreu.reset_for_tests()


func test_streu_plan_sorte_entspricht_gesamtplan() -> void:
	RanchStreu.reset_for_tests()
	var gesamt := RanchStreu.plaene(1.0)
	var einzeln: Array[Dictionary] = []
	for i in RanchStreu.SORTEN.size():
		var plan := RanchStreu.plan_sorte(i, 1.0)
		if not plan.is_empty():
			einzeln.append(plan)
	assert_eq(gesamt.size(), einzeln.size(), "gleiche Sortenzahl")
	for i in gesamt.size():
		assert_eq(
			(gesamt[i] as Dictionary)["transforms"],
			(einzeln[i] as Dictionary)["transforms"],
			"Sorte %d identisch" % i
		)
	RanchStreu.reset_for_tests()


## --------------------------------------- Cache-Determinismus (Gelände)


func test_chunk_mesh_cache_ist_deterministisch() -> void:
	var plan := _erster_fein_plan()
	var wurzel := Node3D.new()
	tree.root.add_child(wurzel)
	RanchTerrain.reset_for_tests()
	var terrain := RanchTerrain.new("sommer")
	terrain.baue_chunk_aus_plan(wurzel, plan)
	var direkt_a := _chunk_vertices(wurzel.get_child(0))
	RanchTerrain.reset_for_tests()
	terrain.baue_chunk_aus_plan(wurzel, plan)
	var direkt_b := _chunk_vertices(wurzel.get_child(1))
	terrain.baue_chunk_aus_plan(wurzel, plan)
	var aus_cache := _chunk_vertices(wurzel.get_child(2))
	assert_true(direkt_a.size() > 0, "Chunk hat Vertizes")
	assert_eq(direkt_a, direkt_b, "Direktläufe bit-identisch")
	assert_eq(direkt_b, aus_cache, "Cache bit-identisch zum Direktlauf")
	RanchTerrain.reset_for_tests()
	wurzel.queue_free()
	await wait_frames(1)


## ------------------------------- Region-Szene (gestückelter Aufbau)


func test_region_reveal_frueh_und_stream_vollstaendig() -> void:
	var region := _region_neu(14.0)
	var reveal := {"da": false}
	region.ready_for_reveal.connect(func() -> void: reveal["da"] = true, CONNECT_ONE_SHOT)
	tree.root.add_child(region)
	# Essenz-Contract: das Reveal-Signal feuert im _ready-Frame, Reiter/
	# Wetter/HUD/Fernsicht stehen — der Spieler kann sofort loslegen.
	assert_true(reveal["da"], "ready_for_reveal kommt aus dem Essenz-Aufbau")
	assert_false(region.aufbau_fertig, "der Rest streamt erst noch")
	assert_true(region.reiter != null, "Reiter steht vor dem Reveal")
	assert_true(region.wetter != null, "Wetter läuft vor dem Reveal")
	assert_true(region.fernsicht != null, "Fernsicht steht vor dem Reveal")
	assert_true(region.get_node_or_null("HudLayer") != null, "HUD steht vor dem Reveal")
	assert_true(
		region.get_node_or_null("Deko_hof") != null, "Spawn-Zonen-Deko steht vor dem Reveal"
	)
	# Stream abwarten (Frame-Budget-Takt in _process) — Deckel großzügig,
	# der Watchdog des Runners greift ohnehin bei Hängern.
	var frames := 0
	while not region.aufbau_fertig and frames < 2000:
		await wait_frames(1)
		frames += 1
	assert_true(region.aufbau_fertig, "Stream-Aufbau schließt ab (nach %d Frames)" % frames)
	assert_true(region.wildtiere != null, "Wildtiere nach dem Stream da")
	assert_true(region.atmosphaere != null, "Atmosphäre nach dem Stream da")
	assert_true(region.get_node_or_null("Streu") != null, "Streu nach dem Stream da")
	var chunks := 0
	for kind in region.get_children():
		if str(kind.name).begins_with("Chunk"):
			chunks += 1
	assert_eq(chunks, 128, "alle 64 Chunks × 2 LODs stehen nach dem Stream")
	for zone: Dictionary in RanchKarte.zonen():
		assert_true(
			region.get_node_or_null("Deko_%s" % zone["id"]) != null,
			"Deko-Gruppe %s nach dem Stream da" % zone["id"]
		)
	region.queue_free()
	await wait_frames(1)


func test_region_baue_rest_sofort_fuer_tools() -> void:
	var region := _region_neu(10.0)
	tree.root.add_child(region)
	region.baue_rest_sofort()
	await wait_frames(1)
	assert_true(region.aufbau_fertig, "baue_rest_sofort schließt den Aufbau ab")
	assert_true(region.wildtiere != null, "Wildtiere da")
	assert_true(region.get_node_or_null("Streu") != null, "Streu da")
	region.queue_free()
	await wait_frames(1)


## ------------------------------------------------------------- Helfer


func _region_neu(stunde: float) -> RanchRegionScene:
	var szene: PackedScene = load("res://scenes/ranch/welt/ranch_region.tscn")
	var region: RanchRegionScene = szene.instantiate()
	region.game_state_override = MiniGs.new()
	region.stunde_override = stunde
	return region


func _erster_fein_plan() -> Dictionary:
	for plan: Dictionary in RanchTerrain.chunk_plaene():
		if not bool(plan["fern"]):
			return plan
	return {}


func _chunk_vertices(knoten: Node) -> PackedVector3Array:
	var mi := knoten as MeshInstance3D
	if mi == null or mi.mesh == null:
		return PackedVector3Array()
	var arrays := mi.mesh.surface_get_arrays(0)
	return arrays[Mesh.ARRAY_VERTEX]

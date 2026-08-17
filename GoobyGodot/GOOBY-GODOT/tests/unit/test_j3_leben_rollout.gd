extends TestCase
## J3 „Läden lebendig 2“ — Wachen für den Ambient-Rollout auf ALLE Orte +
## die benannten Stammkunden (Muster test_g7_ort_leben):
## - jeder neu angeschlossene Ort mountet mit Leben (Besucherzahl > 0 beim
##   Seed, Bewegungs-Delta über injizierte Zeit, Kassen-NPC wo Kasse ist),
## - Reduced Motion halbiert und macht statisch (neue Orte),
## - Flughafen-Besucher rollen Koffer (konfig["koffer"]),
## - Stammkunden: Katalog-Invarianten, Stunden-Fenster (injizierte Uhr!),
##   Determinismus (gleicher Seed ⇒ gleiche Runde), Namensschild + Strings
##   (DE führend, EN paritätisch, je 2 Sprüche),
## - Funkelpark-Plaza lebt (Skater Rollo nachmittags),
## - Goo-und-Bye-Laden: Bummler nur bei OFFENEM Laden.

const GoobythekeSzene := preload("res://scenes/city/orte/goobytheke.tscn")
const GoobymanSzene := preload("res://scenes/city/orte/goobyman.tscn")
const PowSzene := preload("res://scenes/city/orte/pow.tscn")
const PostSzene := preload("res://scenes/city/orte/post.tscn")
const AutohausSzene := preload("res://scenes/city/orte/autohaus.tscn")
const TierarztSzene := preload("res://scenes/city/orte/tierarzt.tscn")
const GouhbusSzene := preload("res://scenes/city/orte/gouhbus.tscn")
const FlughafenSzene := preload("res://scenes/city/orte/flughafen.tscn")
const RaumstationSzene := preload("res://scenes/city/orte/raumstation.tscn")
const WochenmarktSzene := preload("res://scenes/city/orte/wochenmarkt.tscn")
const Vacation := preload("res://scripts/logic/vacation.gd")
const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchemaScript := preload("res://scripts/state/save_schema.gd")
const LadenSzene := preload("res://scripts/dlc/goobye/laden_scene.tscn")

const SEED := 4711
## Neutrale Uhrzeit OHNE Stammkunden-Fenster: der Rollout-Loop bleibt
## unabhängig von der echten Systemuhr deterministisch.
const STUNDE_LEER := 3.0

var _dir_seq := 0


## GameState-Double (Muster test_g3_orte): dotted get/set + update-Pfad +
## beide Signale (Flughafen lauscht auf vacation_changed).
class FakeGameState:
	extends RefCounted

	signal slice_changed(slice_id: String, data: Variant)
	signal vacation_changed(phase: String, dest_id: String)

	var daten: Dictionary = {}

	func _init(start: Dictionary = {}) -> void:
		daten = start

	func state() -> Dictionary:
		return daten

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = daten
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func set_value(path: String, wert: Variant) -> void:
		var teile := path.split(".")
		var node: Dictionary = daten
		for i in teile.size() - 1:
			if not (node.get(teile[i]) is Dictionary):
				node[teile[i]] = {}
			node = node[teile[i]]
		node[teile[teile.size() - 1]] = wert

	func update(mutator: Callable) -> void:
		mutator.call(daten)

	func notify_slice_changed(slice_id: String) -> void:
		slice_changed.emit(slice_id, daten.get(slice_id))

	func melde_vacation(phase: String, dest_id: String) -> void:
		vacation_changed.emit(phase, dest_id)


## Park-Double (Muster test_rest4_park): volles Default-State-Schema.
class FakeParkGameState:
	extends RefCounted

	var state: Dictionary = {}

	func _init() -> void:
		state = SaveSchemaScript.default_state(1700000000000)

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


func _basis_state() -> Dictionary:
	return {
		"vacation": Vacation.default_slice(),
		"buffs": {"aktiv": []},
		"economy": {"coins": 500},
		"inventory": {"items": {}, "food": {}},
		"home": {"storage": [], "storageCapacity": 100},
		"gooby": {"stats": {"hunger": 80.0, "energy": 80.0, "hygiene": 80.0, "fun": 50.0}},
		"city": {},
	}


## Ort mounten mit Test-Overrides (Uhr neutral, damit die Systemzeit keine
## Stammkunden in den Rollout-Loop spült).
func _mounte_ort(szene: PackedScene, stunde := STUNDE_LEER, reduced := -1) -> OrtScene:
	var ort: OrtScene = szene.instantiate()
	ort.game_state_override = FakeGameState.new(_basis_state())
	ort.leben_seed_override = SEED
	ort.leben_stumm_override = true
	ort.leben_stunde_override = stunde
	ort.leben_reduced_override = reduced
	tree.root.add_child(ort)
	await wait_frames(3)
	return ort


## Ort sauber abbauen (Muster test_g7_ort_leben: erst die Stimme entwerten,
## sonst hängt die Babble-Koroutine am SceneTreeTimer).
func _ort_abbauen(ort: OrtScene) -> void:
	if ort.voice != null and is_instance_valid(ort.voice):
		ort.voice.sagt("")
	await wait_frames(6)
	ort.queue_free()
	await wait_frames(2)


## Ein Ort im Rollout-Loop: Leben da, Besucherzahl == Konfig, Kasse wo
## konfiguriert, Bewegungs-Delta über injizierte Zeit.
func _pruefe_ort_lebt(ort: OrtScene, name: String) -> void:
	assert_ne(ort.leben, null, "%s: OrtLeben hängt im Baum" % name)
	if ort.leben == null:
		return
	var konfig := ort.leben.konfig
	var erwartet := int(konfig.get("besucher", 0))
	assert_true(erwartet > 0, "%s: Konfig will Besucher" % name)
	var punkte: Array = konfig.get("punkte", [])
	assert_true(punkte.size() >= 2, "%s: genug Wegpunkte für eine Runde" % name)
	var domain := str(konfig.get("sprueche", ""))
	assert_true(
		I18nService.has_key("city_leben.sprueche.%s" % domain),
		"%s: Spruch-Domain %s existiert" % [name, domain]
	)
	assert_eq(ort.leben.besucher_nodes().size(), erwartet, "%s: Besucher gespawnt" % name)
	assert_false(ort.leben.ist_statisch(), "%s: ohne RM wird geschlendert" % name)
	if bool(konfig.get("kasse", false)):
		assert_ne(ort.kassen_npc, null, "%s: Kassen-NPC am Tresen" % name)
	var vorher: Array[Vector3] = []
	for node in ort.leben.besucher_nodes():
		vorher.append(node.position)
	var bewegt := false
	for _schritt in 4:
		ort.leben.advance_zeit(2.7)
		var nodes := ort.leben.besucher_nodes()
		for i in nodes.size():
			if nodes[i].position.distance_to(vorher[i]) > 0.05:
				bewegt = true
	assert_true(bewegt, "%s: mindestens ein Besucher schlendert" % name)


## ------------------------------------------------- Rollout: jeder Ort lebt


func test_rollout_laeden_leben() -> void:
	var faelle := [
		{"szene": GoobythekeSzene, "name": "goobytheke"},
		{"szene": GoobymanSzene, "name": "goobyman"},
		{"szene": PowSzene, "name": "pow"},
		{"szene": PostSzene, "name": "post"},
		{"szene": AutohausSzene, "name": "autohaus"},
	]
	for fall: Dictionary in faelle:
		var ort := await _mounte_ort(fall["szene"])
		_pruefe_ort_lebt(ort, str(fall["name"]))
		await _ort_abbauen(ort)


func test_rollout_dienste_und_grosse_orte_leben() -> void:
	var faelle := [
		{"szene": TierarztSzene, "name": "tierarzt"},
		{"szene": GouhbusSzene, "name": "gouhbus"},
		{"szene": FlughafenSzene, "name": "flughafen"},
		{"szene": RaumstationSzene, "name": "raumstation"},
		{"szene": WochenmarktSzene, "name": "wochenmarkt"},
	]
	for fall: Dictionary in faelle:
		var ort := await _mounte_ort(fall["szene"])
		_pruefe_ort_lebt(ort, str(fall["name"]))
		await _ort_abbauen(ort)


func test_reduced_motion_in_neuen_orten() -> void:
	# 3 Besucher ⇒ 1 (goobyman), 4 ⇒ 2 (wochenmarkt) — und alle statisch.
	var drogerie := await _mounte_ort(GoobymanSzene, STUNDE_LEER, 1)
	assert_true(drogerie.leben.ist_statisch(), "goobyman: RM ⇒ statisch")
	assert_eq(drogerie.leben.besucher_nodes().size(), 1, "goobyman: halbe Besucherzahl")
	var vorher: Vector3 = drogerie.leben.besucher_nodes()[0].position
	drogerie.leben.advance_zeit(6.0)
	assert_eq(drogerie.leben.besucher_nodes()[0].position, vorher, "goobyman: niemand läuft")
	await _ort_abbauen(drogerie)
	var markt := await _mounte_ort(WochenmarktSzene, STUNDE_LEER, 1)
	assert_true(markt.leben.ist_statisch(), "wochenmarkt: RM ⇒ statisch")
	assert_eq(markt.leben.besucher_nodes().size(), 2, "wochenmarkt: 4 ⇒ 2 Besucher")
	await _ort_abbauen(markt)


func test_flughafen_besucher_rollen_koffer() -> void:
	# Pure: das koffer-Flag wandert in jeden Besucher-Plan.
	var plaene := OrtLeben.plaene(
		{"besucher": 2, "punkte": [Vector3.ZERO, Vector3(2, 0, 0)], "koffer": true}, SEED
	)
	for plan in plaene:
		assert_true(bool(plan["koffer"]), "koffer-Flag im Plan")
	# Mount: jeder Wartehallen-Gooby zieht einen Rollkoffer.
	var ort := await _mounte_ort(FlughafenSzene, 12.0)
	assert_eq(ort.leben.besucher_nodes().size(), 4, "4 Wartehallen-Besucher")
	for node in ort.leben.besucher_nodes():
		assert_ne(node.find_child("Koffer", false, false), null, "Besucher hat Rollkoffer")
	# 12 Uhr liegt in Frau Fernwehs Fenster [11, 16) — mit eigenem Koffer.
	assert_eq(ort.leben.stammkunden_ids(), ["fernweh"] as Array[String], "Frau Fernweh wartet")
	var fernweh := ort.leben.stammkunde_node("fernweh")
	assert_ne(fernweh.find_child("Koffer", false, false), null, "Fernwehs Koffer rollt mit")
	await _ort_abbauen(ort)


## ------------------------------------------------------------ Stammkunden


func test_stammkunden_katalog_invarianten() -> void:
	var ids: Dictionary = {}
	for eintrag in Stammkunden.KATALOG:
		var id := str(eintrag["id"])
		assert_false(ids.has(id), "Stammkunden-Id eindeutig: %s" % id)
		ids[id] = true
		assert_true(int(eintrag["von"]) < int(eintrag["bis"]), "%s: Fenster von<bis" % id)
		assert_true(float(eintrag["tempo"]) > 0.0, "%s: Tempo > 0" % id)
		var punkte: Array = eintrag["punkte"]
		assert_true(punkte.size() >= 2, "%s: feste Runde braucht 2+ Punkte" % id)
	assert_true(ids.size() >= 3 and ids.size() <= 5, "3-5 Stammkunden (Auftrag)")


func test_stammkunden_fenster_pure() -> void:
	assert_eq(Stammkunden.fuer_ort("rehwei", 9.0)[0]["id"], "rosine", "Rosine vormittags")
	assert_eq(Stammkunden.fuer_ort("rehwei", 12.0).size(), 0, "ab 12 ist Rosine weg")
	assert_eq(Stammkunden.fuer_ort("goobytheke", 9.5)[0]["id"], "hatschi", "Hatschi 9-11")
	assert_eq(Stammkunden.fuer_ort("flughafen", 11.0)[0]["id"], "fernweh", "Fernweh ab 11")
	assert_eq(Stammkunden.fuer_ort("flughafen", 16.0).size(), 0, "Fenster [11, 16) exklusiv")
	assert_eq(Stammkunden.fuer_ort("baumarkt", 15.0)[0]["id"], "duebel", "Dübel nach Feierabend")
	assert_eq(Stammkunden.fuer_ort("funkelpark", 14.0)[0]["id"], "rollo", "Rollo nachmittags")
	assert_eq(Stammkunden.fuer_ort("funkelpark", 13.9).size(), 0, "vor 14 kein Rollo")
	assert_eq(Stammkunden.fuer_ort("gibt_es_nicht", 12.0).size(), 0, "unbekannter Ort leer")


func test_stammkunden_strings_de_en_paritaet() -> void:
	I18nService.reset_cache()
	var de := I18nService.table("de")
	var en := I18nService.table("en")
	for eintrag in Stammkunden.KATALOG:
		var id := str(eintrag["id"])
		var name_key := "city_leben.stammkunden.%s" % id
		assert_true(de.has(name_key), "DE-Name da: %s" % name_key)
		assert_true(en.has(name_key), "EN-Name da: %s" % name_key)
		var spruch_key := "city_leben.sprueche.%s" % Stammkunden.spruch_domain(eintrag)
		var de_zeilen: Array = de.get(spruch_key, [])
		var en_zeilen: Array = en.get(spruch_key, [])
		assert_true(de_zeilen.size() >= 2, "%s: 2 DE-Sprüche" % id)
		assert_eq(en_zeilen.size(), de_zeilen.size(), "%s: EN paritätisch" % id)


func test_neue_spruch_domains_rotieren() -> void:
	OrtLeben.reset_sprueche_fuer_tests()
	var domains := [
		"apotheke",
		"drogerie",
		"pow",
		"post",
		"autohaus",
		"tierarzt",
		"praxis",
		"flughafen",
		"raumstation",
		"funkelpark",
		"goobye",
	]
	for domain: String in domains:
		var key := "city_leben.sprueche.%s" % domain
		assert_true(I18nService.has_key(key), "Spruch-Domain fehlt: %s" % key)
		var liste := I18nService.items(key)
		assert_true(liste.size() >= 4, "%s hat genug Zeilen" % key)
		var gesehen: Dictionary = {}
		for _i in liste.size():
			var zeile := OrtLeben.naechster_spruch(domain)
			assert_false(zeile.is_empty(), "Spruch nie leer (%s)" % domain)
			assert_false(gesehen.has(zeile), "keine Wiederholung vor voller Runde (%s)" % domain)
			gesehen[zeile] = true
		assert_eq(OrtLeben.naechster_spruch(domain), String(liste[0]), "dann von vorn")
	OrtLeben.reset_sprueche_fuer_tests()


func test_stammkunde_erscheint_deterministisch_zur_stunde() -> void:
	# 10 Uhr liegt in Opa Hatschis Fenster [9, 11): Figur steht mit Hut und
	# Namensschild in der gemounteten Apotheke.
	var a := await _mounte_ort(GoobythekeSzene, 10.0)
	assert_eq(a.leben.stammkunden_ids(), ["hatschi"] as Array[String], "Hatschi um 10 da")
	var hatschi := a.leben.stammkunde_node("hatschi")
	assert_ne(hatschi, null, "Stammkunden-Node existiert")
	assert_ne(hatschi.find_child("Hut", false, false), null, "Hatschi trägt seinen Hut")
	var schild: Label3D = hatschi.find_child("NamensSchild", false, false)
	assert_ne(schild, null, "Namensschild überm Kopf")
	assert_eq(schild.text, I18nService.t("city_leben.stammkunden.hatschi"), "Schild zeigt Namen")
	await _ort_abbauen(a)
	# Außerhalb des Fensters bleibt die Apotheke stammkundenfrei.
	var spaeter := await _mounte_ort(GoobythekeSzene, 13.0)
	assert_eq(spaeter.leben.stammkunden_ids().size(), 0, "um 13 Uhr kein Hatschi")
	assert_eq(spaeter.leben.besucher_nodes().size(), 2, "Besucher bleiben unabhängig")
	await _ort_abbauen(spaeter)
	# Determinismus FRAME-FEST (Muster IkeaSchaufenster): nacktes OrtLeben
	# mit Hand-Uhr (auto_zeit = false — der Szenen-_process würde je nach
	# Frame-Timing unterschiedlich viel Zeit draufrechnen). Gleicher Seed +
	# gleiche Stunde ⇒ gleiche Runde, und die Figur schlendert über Zeit.
	var x := _nacktes_leben()
	var y := _nacktes_leben()
	await wait_frames(1)
	assert_eq(x.stammkunden_ids(), ["hatschi"] as Array[String], "nackt: Hatschi da")
	var start: Vector3 = x.stammkunde_node("hatschi").position
	x.advance_zeit(4.2)
	y.advance_zeit(4.2)
	var pos_x: Vector3 = x.stammkunde_node("hatschi").position
	var pos_y: Vector3 = y.stammkunde_node("hatschi").position
	assert_true(pos_x.distance_to(pos_y) < 0.0001, "gleicher Seed ⇒ gleiche Runde")
	assert_true(pos_x.distance_to(start) > 0.05, "Hatschi schlurft seine Route (0.4 m/s)")
	x.queue_free()
	y.queue_free()
	await wait_frames(1)


## Nacktes OrtLeben nur mit Stammkunden-Spawn (keine Besucher, Hand-Uhr).
func _nacktes_leben() -> OrtLeben:
	var leben := OrtLeben.new()
	leben.konfig = {"ort_id": "goobytheke", "besucher": 0}
	leben.seed_override = SEED
	leben.stunde_override = 10.0
	leben.auto_zeit = false
	leben.stumm = true
	tree.root.add_child(leben)
	return leben


## ------------------------------------------------- Funkelpark + DLC-Laden


func test_funkelpark_plaza_lebt_mit_rollo() -> void:
	var park: Funkelpark = Funkelpark.new()
	park.game_state_override = FakeParkGameState.new()
	park.stunde_override = 15.0
	park.leben_seed_override = SEED
	park.leben_stumm_override = true
	tree.root.add_child(park)
	await wait_frames(3)
	assert_ne(park.leben, null, "Plaza hat Ambient-Leben")
	assert_eq(park.leben.besucher_nodes().size(), 2, "2 Plaza-Bummler")
	assert_eq(park.leben.stammkunden_ids(), ["rollo"] as Array[String], "Rollo nachmittags")
	var rollo := park.leben.stammkunde_node("rollo")
	var vorher: Vector3 = rollo.position
	park.leben.advance_zeit(3.0)
	assert_true(rollo.position.distance_to(vorher) > 0.05, "Rollo skatet (Tempo 1.25)")
	park.queue_free()
	await wait_frames(2)
	var vormittag: Funkelpark = Funkelpark.new()
	vormittag.game_state_override = FakeParkGameState.new()
	vormittag.stunde_override = 10.0
	vormittag.leben_seed_override = SEED
	vormittag.leben_stumm_override = true
	tree.root.add_child(vormittag)
	await wait_frames(3)
	assert_eq(vormittag.leben.stammkunden_ids().size(), 0, "vormittags kein Rollo")
	vormittag.queue_free()
	await wait_frames(2)


func test_goobye_laden_bummler_nur_bei_offenem_laden() -> void:
	GoobyeKatalog.reset_cache()
	GoobyeState.register_slice()
	_dir_seq += 1
	var dir := "user://j3_leben_tests/%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("progression.level", 12)
	gs.set_value("economy.coins", GoobyeKatalog.preis() + 100)
	assert_eq(GoobyeKauf.kaufe(gs), GoobyeKauf.RESULT_OK, "Vorbereitung: Laden gekauft")
	gs.set_value("dlc.goobye.erstbesuchGesehen", true)
	var szene: GoobyeLadenScene = LadenSzene.instantiate()
	szene.game_state_override = gs
	szene.seed_override = 12345
	szene.auto_navigate = false
	tree.root.add_child(szene)
	await wait_frames(3)
	assert_eq(szene.leben, null, "Einräum-Phase: noch keine Bummler")
	szene.slot_tippen(0)
	await wait_frames(1)
	szene.laden_oeffnen()
	await wait_frames(2)
	assert_ne(szene.leben, null, "offener Laden: Bummler an der Front")
	assert_eq(szene.leben.besucher_nodes().size(), 2, "2 Schaufenster-Bummler")
	assert_true(szene.leben.stumm, "Laden-Audio gehört der Kassen-Choreo")
	szene._zeige_abschluss()
	await wait_frames(2)
	assert_eq(szene.leben, null, "Kassensturz: Bummler wieder ausgeklinkt")
	szene.queue_free()
	await wait_frames(2)
	gs.free()
	SaveSchemaScript.unregister_slice(GoobyeState.SLICE_ID)

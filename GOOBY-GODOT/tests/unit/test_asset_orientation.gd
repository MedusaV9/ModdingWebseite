extends TestCase
## ASSET-ROT-Dauer-Wache (UserFeedback „alle Assets immer richtig rotiert und
## richtig rum"): hält die schlimmste Befund-Klasse dauerhaft rot —
## gespiegelte Modelle (negative Scale), kopfüber stehende Modelle und
## ±90°-Kipp auf bekannten Richtungs-Assets — sofern kein bewusster
## Whitelist-Eintrag (tests/fixtures/asset_rot_whitelist.json) existiert.
##
## Zwei Schichten:
##   1. Selbsttests des Regelwerks (synthetische Bäume) — beweisen, dass die
##      Wache Kipp/Spiegel/Kopfüber wirklich erkennt und GLB-Innenleben
##      (Autoren-Transforms im Asset) NICHT anfasst.
##   2. Szenen-Wache: die Asset-dichten Welt-/Ort-Szenen werden echt
##      instanziert (prozeduraler Aufbau in _ready) und der Laufzeit-Baum
##      geprüft. Das komplette Szenen-Audit inkl. Minispielen fährt
##      tests/tools/asset_rot_audit.gd (Werkzeug, nicht Teil der Suite).

const Regeln := preload("res://tests/tools/asset_rot_regeln.gd")

## Richtungs-Asset-dichte Szenen (Möbel, Autos, Regale, Schilder, Bänke).
const WACHE_SZENEN: Array[String] = [
	"res://scenes/home/schlafzimmer.tscn",
	"res://scenes/home/wohnzimmer.tscn",
	"res://scenes/home/kueche.tscn",
	"res://scenes/home/bad.tscn",
	"res://scenes/home/garten.tscn",
	"res://scenes/city/city_scene.tscn",
	"res://scenes/city/orte/autohaus.tscn",
	"res://scenes/city/orte/baumarkt.tscn",
	"res://scenes/city/orte/goobyman.tscn",
	"res://scenes/city/orte/goobytheke.tscn",
	"res://scenes/city/orte/rehwei.tscn",
	"res://scenes/city/orte/wochenmarkt.tscn",
	"res://scenes/ranch/dorf/hufingen.tscn",
	"res://scripts/dlc/goobye/laden_scene.tscn",
]

## Aufbau-Beruhigung pro Szene: Node-Zahl 3 Frames stabil (max. 40 Frames).
const SETTLE_MAX_FRAMES := 40


func _kipp_node(name_hint: String, glb: String, rot_grad: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = name_hint
	node.scene_file_path = glb
	node.rotation_degrees = rot_grad
	return node


func test_regeln_erkennen_kipp_auf_richtungs_asset() -> void:
	var wurzel := Node3D.new()
	tree.root.add_child(wurzel)
	var sedan := _kipp_node("Schauwagen", "res://assets/city/autos/sedan.glb", Vector3(90, 0, 0))
	wurzel.add_child(sedan)
	var gerade := _kipp_node("Bank", "res://assets/city/deko/bench.gltf", Vector3(0, 135, 0))
	wurzel.add_child(gerade)
	var befunde := Regeln.pruefe_baum(wurzel, "test://kipp")
	assert_eq(befunde.size(), 1, "genau der gekippte Wagen, nicht die gedrehte Bank")
	if befunde.size() == 1:
		assert_eq(str(befunde[0]["art"]), "KIPP_90", "Kipp-Art")
		assert_true(bool(befunde[0]["richtung"]), "sedan ist Richtungs-Asset")
		assert_eq(Regeln.stufe(befunde[0]), "ROT", "Richtungs-Kipp ist ROT")
	wurzel.free()


func test_regeln_erkennen_negative_scale() -> void:
	var wurzel := Node3D.new()
	tree.root.add_child(wurzel)
	var stuhl := _kipp_node("Stuhl", "res://assets/furniture/chair.glb", Vector3.ZERO)
	wurzel.add_child(stuhl)
	stuhl.scale = Vector3(-1, 1, 1)
	var befunde := Regeln.pruefe_baum(wurzel, "test://spiegel")
	assert_eq(befunde.size(), 1, "gespiegelter Stuhl wird gefunden")
	if befunde.size() == 1:
		assert_eq(str(befunde[0]["art"]), "NEG_SCALE", "Spiegel-Art")
		assert_eq(Regeln.stufe(befunde[0]), "ROT", "Spiegel ist immer ROT")
	wurzel.free()


func test_regeln_erkennen_kopfueber_auch_ohne_richtung() -> void:
	var wurzel := Node3D.new()
	tree.root.add_child(wurzel)
	var baum := _kipp_node("Baum", "res://assets/ranch/natur/tree_oak.glb", Vector3(180, 0, 0))
	wurzel.add_child(baum)
	var befunde := Regeln.pruefe_baum(wurzel, "test://kopf")
	assert_eq(befunde.size(), 1, "kopfüber wird gefunden")
	if befunde.size() == 1:
		assert_eq(str(befunde[0]["art"]), "KOPFUEBER", "Kopfüber-Art")
		assert_eq(Regeln.stufe(befunde[0]), "ROT", "Kopfüber ist immer ROT")
	wurzel.free()


func test_regeln_ignorieren_glb_innenleben_und_skelette() -> void:
	var wurzel := Node3D.new()
	tree.root.add_child(wurzel)
	# Autoren-Transform INNERHALB einer GLB-Instanz (z. B. gekipptes Teil).
	var glb := _kipp_node("Modell", "res://assets/furniture/bear.glb", Vector3.ZERO)
	wurzel.add_child(glb)
	var teil := Node3D.new()
	teil.rotation_degrees = Vector3(0, 0, 90)
	glb.add_child(teil)
	# Skelett-Pose (Animation) — ebenfalls Autoren-/Laufzeitsache.
	var skelett := Skeleton3D.new()
	skelett.rotation_degrees = Vector3(90, 0, 0)
	wurzel.add_child(skelett)
	var befunde := Regeln.pruefe_baum(wurzel, "test://innen")
	assert_eq(befunde.size(), 0, "GLB-Innenleben/Skelette lösen nie aus: %s" % str(befunde))
	wurzel.free()


func test_whitelist_deckt_bewusste_ausnahme_ab() -> void:
	var befund := {
		"szene": "res://scenes/city/city_scene.tscn",
		"pfad": "Kulisse/Windrad/Rotor",
		"art": "KIPP_90",
		"richtung": true,
	}
	var whitelist := [
		{
			"szene": "res://scenes/city/city_scene.tscn",
			"pfad_regex": "Windrad/Rotor$",
			"art": "KIPP_90",
			"grund": "Rotor liegt konstruktiv in der Nabenebene",
		}
	]
	var liste: Array[Dictionary] = [befund]
	assert_true(Regeln.ist_erlaubt(befund, whitelist), "Eintrag deckt Befund")
	assert_eq(Regeln.rote_befunde(liste, whitelist).size(), 0, "Wache bleibt grün")
	var fremd := befund.duplicate()
	fremd["pfad"] = "Kulisse/Parkplatz/Auto3"
	assert_false(Regeln.ist_erlaubt(fremd, whitelist), "fremder Pfad bleibt ROT")


## Die eigentliche Dauer-Wache: Asset-dichte Szenen bleiben frei von
## nicht-gewhitelisteten ROT-Befunden (NEG_SCALE, KOPFUEBER, Richtungs-Kipp).
func test_welt_szenen_ohne_rote_orientierungs_befunde() -> void:
	var whitelist := Regeln.lade_whitelist()
	for pfad in WACHE_SZENEN:
		assert_true(ResourceLoader.exists(pfad), "Wache-Szene fehlt: %s" % pfad)
		if not ResourceLoader.exists(pfad):
			continue
		var szene: Node = (load(pfad) as PackedScene).instantiate()
		tree.root.add_child(szene)
		await _beruhige()
		var stats: Dictionary = {}
		var befunde := Regeln.pruefe_baum(szene, pfad, stats)
		var kandidaten := int(stats.get("glb", 0)) + int(stats.get("holder", 0))
		assert_true(kandidaten > 0, "%s: keine Kandidaten geprüft — Wache blind?" % pfad)
		for befund in Regeln.rote_befunde(befunde, whitelist):
			fail_test("Orientierungs-Befund: %s" % Regeln.beschreibe(befund))
		szene.queue_free()
		await wait_frames(2)


func _beruhige() -> void:
	var stabil := 0
	var letzte := -1
	for _i in SETTLE_MAX_FRAMES:
		var jetzt := _zaehle(tree.root)
		stabil = stabil + 1 if jetzt == letzte else 0
		letzte = jetzt
		if stabil >= 3:
			return
		await tree.process_frame


func _zaehle(node: Node) -> int:
	var summe := 1
	for kind in node.get_children():
		summe += _zaehle(kind)
	return summe

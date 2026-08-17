class_name PostkartenProps
extends RefCounted
## 3D-Props (REST-4, EVAL Rang 15): Postkartenwand + Souvenirregal als
## WALL-Möbel-Modelle (FurnitureNode-`proc`-Hook wie "fenster").
##
## - Postkartenwand: Korkbrett mit den NEUSTEN Archiv-Karten als Mini-
##   Postkarten (Pin + Ziel-Farbstreifen). Liest den Archivstand beim Bau
##   (Raum-Reload/Bau-Commit erneuert das Modell).
## - Souvenirregal: Web-Vorbild home/souvenirShelf.js VERBATIM — Brett +
##   Rückwand + EIN Mini je besuchtem Reiseziel (feste Slots, Rezepte 1:1;
##   nur die Minis sind ×1.2 lesbarer skaliert).
##
## FARBEN: die Mini-Rezepte tragen die Web-Farben verbatim (die Web-Vorlage
## ist die Wahrheit); Holz/Kork lehnen sich an HomeProps.PALETTE an.

## Web souvenirShelf.js SHELF (Meter, y 0 = Brett-Unterkante).
const SHELF := {
	"plank_w": 1.5,
	"plank_t": 0.035,
	"plank_d": 0.17,
	"back_h": 0.24,
	"back_t": 0.022,
	"slot_x0": -0.6,
	"slot_pitch": 0.15,
	"slot_z": 0.01,
	"plank_color": Color("#B98A62"),
	"back_color": Color("#CBA478"),
}

## Lesbarkeits-Faktor der Minis (bleibt unter der Slot-Teilung).
const MINI_SCALE := 1.2

## Web souvenirShelf.js MINI_SPECS verbatim: shape/size/color/at/rot/scale
## in Mini-Lokalkoordinaten (y 0 = Brett-Oberkante, x/z Slot-zentriert).
const MINI_SPECS := {
	"beach":
	[
		{
			"shape": "sphere",
			"size": [0.048],
			"color": "#F6D3BD",
			"at": [0.0, 0.028, 0.0],
			"scale": [1.0, 0.58, 0.85]
		},
		{"shape": "sphere", "size": [0.013], "color": "#FFF4E4", "at": [0.028, 0.013, 0.032]},
	],
	"meadowTrip":
	[
		{
			"shape": "cyl",
			"size": [0.026, 0.03, 0.055],
			"color": "#DDEEDF",
			"at": [0.0, 0.0275, 0.0]
		},
		{"shape": "cyl", "size": [0.004, 0.004, 0.05], "color": "#7FB069", "at": [0.0, 0.08, 0.0]},
		{"shape": "sphere", "size": [0.019], "color": "#F7A8C4", "at": [0.0, 0.112, 0.0]},
		{"shape": "sphere", "size": [0.008], "color": "#FFE28A", "at": [0.0, 0.112, 0.017]},
	],
	"bigCity":
	[
		{"shape": "box", "size": [0.105, 0.012, 0.05], "color": "#C9CFDD", "at": [0.0, 0.006, 0.0]},
		{
			"shape": "box",
			"size": [0.026, 0.062, 0.026],
			"color": "#8FA1C0",
			"at": [-0.032, 0.043, 0.004]
		},
		{
			"shape": "box",
			"size": [0.026, 0.095, 0.026],
			"color": "#A7B6D4",
			"at": [0.0, 0.0595, -0.006]
		},
		{
			"shape": "box",
			"size": [0.026, 0.048, 0.026],
			"color": "#7C8DB0",
			"at": [0.033, 0.036, 0.006]
		},
	],
	"space":
	[
		{"shape": "ico", "size": [0.042], "color": "#C3C9DA", "at": [0.0, 0.036, 0.0]},
		{"shape": "ico", "size": [0.012], "color": "#98A1BA", "at": [0.02, 0.06, 0.014]},
	],
	"harbor":
	[
		{"shape": "cyl", "size": [0.02, 0.027, 0.06], "color": "#E86A5E", "at": [0.0, 0.03, 0.0]},
		{
			"shape": "cyl",
			"size": [0.016, 0.02, 0.045],
			"color": "#FFF6E8",
			"at": [0.0, 0.0825, 0.0]
		},
		{
			"shape": "cyl",
			"size": [0.013, 0.013, 0.018],
			"color": "#FFE28A",
			"at": [0.0, 0.114, 0.0]
		},
		{"shape": "cone", "size": [0.018, 0.026], "color": "#E86A5E", "at": [0.0, 0.136, 0.0]},
	],
	"spookGarden":
	[
		{
			"shape": "sphere",
			"size": [0.042],
			"color": "#F0973F",
			"at": [0.0, 0.033, 0.0],
			"scale": [1.0, 0.78, 1.0]
		},
		{
			"shape": "cyl",
			"size": [0.006, 0.008, 0.022],
			"color": "#7B9A56",
			"at": [0.004, 0.073, 0.0],
			"rot": [0.0, 0.0, 0.25]
		},
	],
	"bakery":
	[
		{"shape": "cyl", "size": [0.03, 0.023, 0.038], "color": "#E8C9A0", "at": [0.0, 0.019, 0.0]},
		{
			"shape": "sphere",
			"size": [0.03],
			"color": "#F6B8D0",
			"at": [0.0, 0.05, 0.0],
			"scale": [1.0, 0.72, 1.0]
		},
		{"shape": "sphere", "size": [0.009], "color": "#DE5449", "at": [0.0, 0.078, 0.0]},
	],
	"nightSky":
	[
		{
			"shape": "cyl",
			"size": [0.027, 0.027, 0.062],
			"color": "#CFE3F7",
			"at": [0.0, 0.031, 0.0]
		},
		{
			"shape": "cyl",
			"size": [0.029, 0.029, 0.012],
			"color": "#A9805A",
			"at": [0.0, 0.068, 0.0]
		},
		{
			"shape": "oct",
			"size": [0.017],
			"color": "#FFD966",
			"at": [0.0, 0.089, 0.0],
			"scale": [1.0, 0.8, 1.0]
		},
	],
	"toyRoom":
	[
		{
			"shape": "box",
			"size": [0.048, 0.048, 0.048],
			"color": "#F2C94C",
			"at": [0.0, 0.024, 0.0],
			"rot": [0.0, 0.26, 0.0]
		},
		{
			"shape": "box",
			"size": [0.036, 0.036, 0.036],
			"color": "#7FB3E8",
			"at": [0.006, 0.066, 0.004],
			"rot": [0.0, -0.35, 0.0]
		},
	],
}

## Ziel-Akzentfarbe der Mini-Postkarten an der Wand (aus den Web-Rezepten).
const DEST_AKZENT := {
	"beach": Color("#F6D3BD"),
	"meadowTrip": Color("#F7A8C4"),
	"bigCity": Color("#A7B6D4"),
	"space": Color("#C3C9DA"),
	"harbor": Color("#E86A5E"),
	"spookGarden": Color("#F0973F"),
	"bakery": Color("#F6B8D0"),
	"nightSky": Color("#CFE3F7"),
	"toyRoom": Color("#F2C94C"),
}

## Wand-Layout: maximal gezeigte Karten (2 Reihen à 3).
const WAND_MAX_KARTEN := 6

const KORK := Color("#C9A377")
const RAHMEN_HOLZ := Color("#8A6642")
const KARTE_PAPIER := Color("#FFFAF2")
const PIN := Color("#E0655F")

static var _mat_cache: Dictionary = {}

## ------------------------------------------------------- Katalog-Einstiege


## Postkartenwand fürs Katalog-`proc` — liest das Archiv des GameState.
static func postkartenwand() -> Node3D:
	return postkartenwand_mit(PostkartenLogic.archive_of(_state()))


## Souvenirregal fürs Katalog-`proc` — liest `vacation.visited`.
static func souvenirregal() -> Node3D:
	return souvenirregal_mit(PostkartenLogic.souvenirs_von(_state()))


## ------------------------------------------------------- Postkartenwand


## Korkbrett + die NEUSTEN Archiv-Karten als Mini-Postkarten (pur, testbar).
static func postkartenwand_mit(archiv: Array) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Postkartenwand"
	var brett_w := 1.0
	var brett_h := 0.72
	wurzel.add_child(_box(Vector3(brett_w, brett_h, 0.025), KORK))
	for x: float in [-(brett_w + 0.05) * 0.5, (brett_w + 0.05) * 0.5]:
		var pfosten := _box(Vector3(0.05, brett_h + 0.1, 0.035), RAHMEN_HOLZ)
		pfosten.position = Vector3(x, 0.0, 0.004)
		wurzel.add_child(pfosten)
	for y: float in [-(brett_h + 0.05) * 0.5, (brett_h + 0.05) * 0.5]:
		var riegel := _box(Vector3(brett_w + 0.1, 0.05, 0.035), RAHMEN_HOLZ)
		riegel.position = Vector3(0.0, y, 0.004)
		wurzel.add_child(riegel)
	var neueste := archiv.slice(maxi(0, archiv.size() - WAND_MAX_KARTEN))
	for i in neueste.size():
		wurzel.add_child(_wand_karte(neueste[i], i))
	return wurzel


static func _wand_karte(entry: Dictionary, index: int) -> Node3D:
	var karte := Node3D.new()
	karte.name = "Karte_%d" % index
	@warning_ignore("integer_division")
	var reihe := index / 3
	var spalte := index % 3
	karte.position = Vector3(-0.3 + spalte * 0.3, 0.17 - reihe * 0.3, 0.02)
	karte.rotation.z = 0.06 if (index % 2) == 0 else -0.05
	karte.add_child(_box(Vector3(0.24, 0.17, 0.008), KARTE_PAPIER))
	var streifen := _box(Vector3(0.24, 0.045, 0.009), _akzent(str(entry.get("destId", ""))))
	streifen.position = Vector3(0.0, 0.055, 0.0015)
	karte.add_child(streifen)
	var pin := MeshInstance3D.new()
	var kugel := SphereMesh.new()
	kugel.radius = 0.012
	kugel.height = 0.024
	pin.mesh = kugel
	pin.material_override = _material(PIN)
	pin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pin.position = Vector3(0.0, 0.075, 0.008)
	karte.add_child(pin)
	return karte


static func _akzent(dest_id: String) -> Color:
	return DEST_AKZENT.get(dest_id, Color("#DCCFBE"))


## ------------------------------------------------------- Souvenirregal


## Brett + Rückwand + ein Mini je besuchtem Ziel (pur, testbar).
static func souvenirregal_mit(besucht: Array) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Souvenirregal"
	var plank_t: float = SHELF["plank_t"]
	var plank_d: float = SHELF["plank_d"]
	var back_t: float = SHELF["back_t"]
	var plank := _box(Vector3(SHELF["plank_w"], plank_t, plank_d), SHELF["plank_color"])
	plank.position = Vector3(0.0, plank_t * 0.5, 0.0)
	wurzel.add_child(plank)
	var back := _box(Vector3(SHELF["plank_w"], SHELF["back_h"], back_t), SHELF["back_color"])
	back.position = Vector3(0.0, SHELF["back_h"] * 0.5, -plank_d * 0.5 + back_t * 0.5)
	wurzel.add_child(back)
	for i in PostkartenLogic.DEST_IDS.size():
		var dest_id: String = PostkartenLogic.DEST_IDS[i]
		if not besucht.has(dest_id):
			continue
		var slot_x: float = SHELF["slot_x0"] + i * SHELF["slot_pitch"]
		wurzel.add_child(_mini(dest_id, Vector3(slot_x, plank_t, SHELF["slot_z"])))
	return wurzel


static func _mini(dest_id: String, at: Vector3) -> Node3D:
	var mini := Node3D.new()
	mini.name = "Souvenir_%s" % dest_id
	mini.position = at
	mini.scale = Vector3.ONE * MINI_SCALE
	for spec: Dictionary in MINI_SPECS.get(dest_id, []):
		var teil := MeshInstance3D.new()
		teil.mesh = _spec_mesh(spec)
		teil.material_override = _material(Color(str(spec["color"])))
		teil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var at_spec: Array = spec["at"]
		teil.position = Vector3(at_spec[0], at_spec[1], at_spec[2])
		var rot: Array = spec.get("rot", [0.0, 0.0, 0.0])
		teil.rotation = Vector3(rot[0], rot[1], rot[2])
		var sc: Array = spec.get("scale", [1.0, 1.0, 1.0])
		teil.scale = Vector3(sc[0], sc[1], sc[2])
		mini.add_child(teil)
	return mini


## Web specGeometry → Godot-Primitive (ico/oct als facettierte Kugeln).
static func _spec_mesh(spec: Dictionary) -> Mesh:
	var s: Array = spec["size"]
	match str(spec["shape"]):
		"box":
			var box := BoxMesh.new()
			box.size = Vector3(s[0], s[1], s[2])
			return box
		"sphere":
			return _kugel(float(s[0]), 10, 8)
		"cyl":
			var cyl := CylinderMesh.new()
			cyl.top_radius = s[0]
			cyl.bottom_radius = s[1]
			cyl.height = s[2]
			cyl.radial_segments = 10
			return cyl
		"cone":
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = s[0]
			cone.height = s[1]
			cone.radial_segments = 10
			return cone
		"ico":
			return _kugel(float(s[0]), 6, 3)
		"oct":
			return _kugel(float(s[0]), 4, 2)
	return _kugel(float(s[0]) if s.size() > 0 else 0.02, 8, 6)


static func _kugel(radius: float, segmente: int, ringe: int) -> SphereMesh:
	var kugel := SphereMesh.new()
	kugel.radius = radius
	kugel.height = radius * 2.0
	kugel.radial_segments = segmente
	kugel.rings = ringe
	return kugel


## ------------------------------------------------------- Bausteine


static func _box(size: Vector3, farbe: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = _material(farbe)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


## Materialien pro Farbe cachen (weniger State-Wechsel, weniger Ressourcen).
static func _material(farbe: Color) -> StandardMaterial3D:
	var key := farbe.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = farbe
	mat.roughness = 0.9
	_mat_cache[key] = mat
	return mat


static func _state() -> Dictionary:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return {}
	var gs := (loop as SceneTree).root.get_node_or_null("GameState")
	if gs == null or not gs.has_method("state"):
		return {}
	return gs.state()

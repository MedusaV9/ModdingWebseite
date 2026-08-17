class_name Girlande
extends Node3D
## Sichtbare Spann-Deko (W13B, Doc H §6.3): hängt als Catenary-Kurve
## (CatenaryLogic) zwischen zwei Decken-Punkten. Drei Varianten (Katalog-Ids
## `girlande_*`):
##   - girlande_wimpel: bunte Wimpel-Dreiecke (EIN MultiMesh aus Prismen),
##   - girlande_lichter: Lichterkette — emissive Kügelchen (Muster
##     funkelpark._baue_lichter) + max. 4 ECHTE OmniLights, nur nachts an,
##   - girlande_pompons: Pastell-Bommeln (EIN MultiMesh aus Kugeln).
## Zeit wird INJIZIERT (`stunde` bei create bzw. wende_tageszeit_an) —
## Tag/Nacht kommt aus HomeLicht.tageslicht, kein eigener Uhren-Code.

const TYP_WIMPEL := "girlande_wimpel"
const TYP_LICHTER := "girlande_lichter"
const TYP_POMPONS := "girlande_pompons"

const SEGMENTE := 12
## Hartes Licht-Budget je Kette (Doc A §7: Mobile!): mehr Kügelchen sind ok,
## aber höchstens 4 echte OmniLights.
const MAX_LICHTER := 4
## Unterhalb dieses Tageslicht-Anteils gelten die Lichter als „nachts an“.
const NACHT_SCHWELLE := 0.35

const SCHNUR_FARBE := Color(0.55, 0.45, 0.38, 0.9)
const LICHT_FARBE := Color("#FFD166")
const WIMPEL_FARBEN: Array[Color] = [
	Color("#FF9BB3"), Color("#FFD37A"), Color("#9BDF9B"), Color("#8FC7FF"), Color("#C9A6FF")
]
const POMPON_FARBEN: Array[Color] = [
	Color("#FFC2D1"), Color("#FFE3A3"), Color("#BDEBC8"), Color("#BFDFFF")
]

var typ := ""

var _lichter: Array[OmniLight3D] = []


## Baut eine Girlande zwischen zwei WELT-Punkten (Deckenhöhe inklusive).
## `stunde` injiziert die Tageszeit für den Nacht-Zustand der Lichterkette.
static func create(
	girlande_typ: String, welt_a: Vector3, welt_b: Vector3, stunde: float
) -> Girlande:
	var node := Girlande.new()
	node.typ = girlande_typ
	node.name = "Girlande_%s" % girlande_typ
	node._baue(welt_a, welt_b)
	node.wende_tageszeit_an(stunde)
	return node


## Mini-Vorschau für Drawer/Shop (FurnitureNode `proc: "girlande"`): eine
## kurze Girlande aus EINZELNEN MeshInstances (der AABB-Fit sieht nur die) —
## OHNE echte OmniLights, das Budget gilt nur für gespannte Ketten.
static func vorschau(girlande_typ: String) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "GirlandenVorschau"
	var kurve := CatenaryLogic.punkte(Vector3(-0.45, 0.5, 0.0), Vector3(0.45, 0.5, 0.0), 6, 0.22)
	for i in kurve.size() - 2:
		var instanz := MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		if girlande_typ == TYP_WIMPEL:
			var prisma := PrismMesh.new()
			prisma.size = Vector3(0.11, 0.13, 0.015)
			instanz.mesh = prisma
			instanz.basis = Basis(Vector3.RIGHT, PI)
			instanz.position = kurve[i + 1] + Vector3(0.0, -0.065, 0.0)
			mat.albedo_color = WIMPEL_FARBEN[i % WIMPEL_FARBEN.size()]
		else:
			var kugel := SphereMesh.new()
			kugel.radius = 0.05
			kugel.height = 0.1
			instanz.mesh = kugel
			instanz.position = kurve[i + 1] + Vector3(0.0, -0.05, 0.0)
			if girlande_typ == TYP_LICHTER:
				mat.albedo_color = Color("#FFE28A")
				mat.emission_enabled = true
				mat.emission = LICHT_FARBE
				mat.emission_energy_multiplier = 2.0
			else:
				mat.albedo_color = POMPON_FARBEN[i % POMPON_FARBEN.size()]
		instanz.material_override = mat
		wurzel.add_child(instanz)
	return wurzel


## Indizes der Kurven-Punkte, die ein ECHTES Licht bekommen — gleichmäßig
## verteilt und hart auf `max_lichter` gedeckelt (pur, testbar).
static func licht_indizes(punkt_anzahl: int, max_lichter := MAX_LICHTER) -> Array[int]:
	var out: Array[int] = []
	if punkt_anzahl <= 0 or max_lichter <= 0:
		return out
	var n := mini(max_lichter, punkt_anzahl)
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		var idx := clampi(int(floor(t * punkt_anzahl)), 0, punkt_anzahl - 1)
		if not out.has(idx):
			out.append(idx)
	return out


## Tag/Nacht-Regel der Lichterkette (pur): an, sobald es dunkel genug ist.
static func ist_nacht(stunde: float) -> bool:
	return HomeLicht.tageslicht(stunde) < NACHT_SCHWELLE


func lichter_anzahl() -> int:
	return _lichter.size()


## Lichter an/aus je Tageszeit — der Host ruft das periodisch auf.
func wende_tageszeit_an(stunde: float) -> void:
	var nacht := ist_nacht(stunde)
	for licht in _lichter:
		licht.visible = nacht


# ── Aufbau ───────────────────────────────────────────────────────────────────


func _baue(welt_a: Vector3, welt_b: Vector3) -> void:
	var kurve := CatenaryLogic.punkte(welt_a, welt_b, SEGMENTE)
	_baue_schnur(kurve)
	match typ:
		TYP_LICHTER:
			_baue_lichterkette(kurve)
		TYP_POMPONS:
			_baue_kugeln(kurve, 0.055, POMPON_FARBEN, false)
		_:
			_baue_wimpel(kurve)


## Dünne Schnur als Linienzug entlang der Kurve (unshaded, ein Mesh).
func _baue_schnur(kurve: Array[Vector3]) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	mesh.surface_set_color(SCHNUR_FARBE)
	for punkt in kurve:
		mesh.surface_add_vertex(punkt)
	mesh.surface_end()
	var instanz := MeshInstance3D.new()
	instanz.name = "Schnur"
	instanz.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	instanz.material_override = mat
	add_child(instanz)


## Wimpel: kleine, flache Dreiecks-Prismen, Spitze nach unten, bunt rotierend.
func _baue_wimpel(kurve: Array[Vector3]) -> void:
	var prisma := PrismMesh.new()
	prisma.size = Vector3(0.11, 0.13, 0.015)
	var kippung := Basis(Vector3.RIGHT, PI)
	var mm := _multimesh(prisma, kurve.size() - 2, true)
	for i in kurve.size() - 2:
		var pos := kurve[i + 1] + Vector3(0.0, -0.065, 0.0)
		mm.set_instance_transform(i, Transform3D(kippung, pos))
		mm.set_instance_color(i, WIMPEL_FARBEN[i % WIMPEL_FARBEN.size()])
	_mm_instanz(mm, "Wimpel")


## Lichterkette: emissive Kügelchen an JEDEM Kurvenpunkt (billig, EIN
## MultiMesh — Funkelpark-Muster) + echte OmniLights nur an licht_indizes.
func _baue_lichterkette(kurve: Array[Vector3]) -> void:
	_baue_kugeln(kurve, 0.035, [LICHT_FARBE] as Array[Color], true)
	for idx in licht_indizes(kurve.size()):
		var licht := OmniLight3D.new()
		licht.position = kurve[idx] + Vector3(0.0, -0.05, 0.0)
		licht.light_color = LICHT_FARBE
		licht.light_energy = 0.9
		licht.omni_range = 1.8
		licht.shadow_enabled = false
		add_child(licht)
		_lichter.append(licht)


## Kugel-Kette (Pompons/Glühkügelchen) als EIN MultiMesh.
func _baue_kugeln(
	kurve: Array[Vector3], radius: float, farben: Array[Color], leuchtet: bool
) -> void:
	var kugel := SphereMesh.new()
	kugel.radius = radius
	kugel.height = radius * 2.0
	if leuchtet:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#FFE28A")
		mat.emission_enabled = true
		mat.emission = LICHT_FARBE
		mat.emission_energy_multiplier = 2.0
		kugel.material = mat
	var mm := _multimesh(kugel, kurve.size() - 2, not leuchtet)
	for i in kurve.size() - 2:
		var pos := kurve[i + 1] + Vector3(0.0, -radius, 0.0)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos))
		if not leuchtet:
			mm.set_instance_color(i, farben[i % farben.size()])
	_mm_instanz(mm, "Kette")


func _multimesh(mesh: Mesh, anzahl: int, mit_farben: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = mit_farben
	mm.mesh = mesh
	mm.instance_count = maxi(0, anzahl)
	return mm


func _mm_instanz(mm: MultiMesh, instanz_name: String) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = instanz_name
	mmi.multimesh = mm
	if mm.use_colors:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mmi.material_override = mat
	add_child(mmi)

class_name OrtAutohaus
extends OrtScene
## Autohaus „Blechbert“ (Doc E §1.4, USER §D48): Ausstellungsraum mit drei
## echten Wagen aus dem CarDef-Katalog (AutoKatalog → assets/city/autos),
## Teppich, Topfpflanze. Kauf + Farbwahl laufen über das AutohausSheet;
## das aktive Auto ist der Contract für die Fahr-Minispiele.
## J3 „Läden lebendig 2“: Ambient-Interessenten bestaunen die Wagen,
## Blechbert bekommt das Kassen-Verhalten und eine CC0-Beratungsecke
## (Schreibtisch + Bürostuhl + Laptop).

const MOEBEL := "res://assets/furniture"
const CC0_MOEBEL := "res://assets/models/cc0/kenney_furniture_extra"

## Stellplätze im Raum (Reihenfolge = Katalog-Reihenfolge ab dem 2. Wagen).
const PLAETZE: Array[Vector3] = [
	Vector3(-4.0, 0.0, -1.4), Vector3(0.2, 0.0, -2.4), Vector3(4.4, 0.0, -1.4)
]

## Rohe Footprints (Breite, Tiefe) der Ecke-Ursprung-Möbel laut GLB-AABB.
const GRUND_TISCH := Vector2(0.734, 0.392)
const GRUND_STUHL := Vector2(0.335, 0.314)
const GRUND_LAPTOP := Vector2(0.264, 0.24)

## Beratungsecke in warmem Holz (Blechberts Verkaufstisch).
const TINT_HOLZ := Color("#D8B98A")
## Schreibtisch-Platte (0,384 m roh × Skala) — der Laptop steht darauf.
const TISCH_PLATTE_Y := 0.384 * 1.9

var _wagen: Array[Node3D] = []


func _baue_innenraum() -> void:
	_prop("%s/rugRectangle.glb" % MOEBEL, Vector3(0.0, 0.02, -1.6), 0.0, 3.2)
	_prop("%s/pottedPlant.glb" % MOEBEL, Vector3(-6.0, 0.0, -3.0), 0.0, 1.2)
	_prop("%s/monstera_plant_large_potted.gltf" % _pflanzen(), Vector3(6.0, 0.0, -3.0), 0.0, 1.4)
	_prop("%s/sideTable.glb" % MOEBEL, Vector3(5.2, 0.0, 0.6), 0.0, 1.0)
	_prop("%s/loungeChair.glb" % MOEBEL, Vector3(-5.2, 0.0, 0.8), 25.0, 1.0)
	# J3/CC0: Beratungsecke rechts hinten — Schreibtisch mit Laptop,
	# Bürostuhl seitlich (schaut zum Tisch), alles in Blechbert-Holz.
	var tisch := _cc0("%s/desk.glb" % CC0_MOEBEL, Vector3(4.6, 0.0, -3.1), 0.0, 1.9, GRUND_TISCH)
	OrtRequisiten.tinte(tisch, TINT_HOLZ, 0.4)
	var stuhl := _cc0(
		"%s/chair_desk.glb" % CC0_MOEBEL, Vector3(3.6, 0.0, -3.3), -90.0, 1.6, GRUND_STUHL
	)
	OrtRequisiten.tinte(stuhl, TINT_HOLZ, 0.35)
	_cc0(
		"%s/laptop.glb" % CC0_MOEBEL, Vector3(4.75, TISCH_PLATTE_Y, -3.05), -20.0, 1.6, GRUND_LAPTOP
	)
	_stelle_wagen_aus()


## J3: Ambient-Leben — 2 Interessenten schlendern von Wagen zu Wagen,
## Blechbert bekommt das Kassen-Verhalten (tippt Angebote in den Laptop).
func _leben_konfig() -> Dictionary:
	return {
		"besucher": 2,
		"punkte":
		[
			Vector3(-4.0, 0.0, 0.4),
			Vector3(0.2, 0.0, -0.7),
			Vector3(4.4, 0.0, 0.4),
			Vector3(-1.8, 0.0, 1.6),
		],
		"sprueche": "autohaus",
		"blick": Vector3(0.2, 0.0, -2.4),
		"gemurmel": false,
		"tuer_glocke": true,
		"kasse": true,
	}


func _dialog_pfad() -> String:
	return "res://scripts/city/data/dialoge/autohaus.json"


func _npc_konfig() -> Dictionary:
	return {"tint": Color("#8FD0E8"), "emotion": "happy", "pos": Vector3(1.9, 0.0, 0.9)}


## Autohaus hat ein eigenes Händler-UI (Stats, Farbwahl, aktives Auto).
func oeffne_laden() -> void:
	var inhalt := AutohausSheet.new()
	inhalt.gs = game_state()
	inhalt.gekauft.connect(_on_gekauft)
	zeige_sheet(I18nService.t("city.autohaus.sheet_titel"), inhalt)


func _pflanzen() -> String:
	return "%s/pflanzen" % MOEBEL


## Bis zu drei Wagen aus dem Katalog auf die Stellplätze — in der Farbe, die
## der Spieler besitzt bzw. der ersten Katalogfarbe (Schaufenster-Look).
func _stelle_wagen_aus() -> void:
	var eigene := AutoKatalog.besitz(game_state())
	var index := 0
	for eintrag: Dictionary in AutoKatalog.autos():
		if index >= PLAETZE.size():
			return
		var id := str(eintrag.get("id", ""))
		var pfad := AutoKatalog.glb_pfad(id)
		var node := _prop(pfad, PLAETZE[index], -25.0 + 25.0 * float(index), CityCarFeel.CAR_SCALE)
		if node == null:
			continue
		var farben: Array = eintrag.get("farben", [])
		var hex := str(eigene.get(id, farben[0] if not farben.is_empty() else ""))
		_lackiere(node, hex)
		_wagen.append(node)
		index += 1


## Karosserie-Tint (wie CityScene._tinte, nur für den Ausstellungswagen).
func _lackiere(node: Node3D, hex: String) -> void:
	if hex.is_empty():
		return
	var farbe := Color.from_string(hex, Color.WHITE)
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = mesh
		for i in mi.get_surface_override_material_count():
			var mat: Material = mi.mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				var kopie: StandardMaterial3D = mat.duplicate()
				kopie.albedo_color = kopie.albedo_color.lerp(farbe, 0.6)
				mi.set_surface_override_material(i, kopie)


func _on_gekauft(auto_id: String) -> void:
	# J3: Kassen-Piep + Winken über Blechberts Kassen-Verhalten.
	if kassen_npc != null:
		_on_leben_kunde_zahlt(auto_id)
	elif rig != null:
		rig.play_clip("wave")
	zeige_toast(I18nService.t("city.autohaus.gekauft_toast"))

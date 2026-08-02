class_name OrtAutohaus
extends OrtScene
## Autohaus „Blechbert“ (Doc E §1.4, USER §D48): Ausstellungsraum mit drei
## echten Wagen aus dem CarDef-Katalog (AutoKatalog → assets/city/autos),
## Teppich, Topfpflanze. Kauf + Farbwahl laufen über das AutohausSheet;
## das aktive Auto ist der Contract für die Fahr-Minispiele.
## G8-P1 „Jeder Ort lebt“ (PT2-B4): Kundschaft umkreist ehrfürchtig die
## Stellplätze (Blick auf den Mittelwagen), dazu die Momente Probesitz-
## Hupe (jemand hat den roten Knopf gefunden) und Traumwagen-Seufzer.

const MOEBEL := "res://assets/furniture"
## Stellplätze im Raum (Reihenfolge = Katalog-Reihenfolge ab dem 2. Wagen).
const PLAETZE: Array[Vector3] = [
	Vector3(-4.0, 0.0, -1.4), Vector3(0.2, 0.0, -2.4), Vector3(4.4, 0.0, -1.4)
]

var _wagen: Array[Node3D] = []


func _baue_innenraum() -> void:
	_prop("%s/rugRectangle.glb" % MOEBEL, Vector3(0.0, 0.02, -1.6), 0.0, 3.2)
	_prop("%s/pottedPlant.glb" % MOEBEL, Vector3(-6.0, 0.0, -3.0), 0.0, 1.2)
	_prop("%s/monstera_plant_large_potted.gltf" % _pflanzen(), Vector3(6.0, 0.0, -3.0), 0.0, 1.4)
	_prop("%s/sideTable.glb" % MOEBEL, Vector3(5.2, 0.0, 0.6), 0.0, 1.0)
	_prop("%s/loungeChair.glb" % MOEBEL, Vector3(-5.2, 0.0, 0.8), 25.0, 1.0)
	_stelle_wagen_aus()


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


func _on_gekauft(_auto_id: String) -> void:
	if rig != null:
		rig.play_clip("wave")
	zeige_toast(I18nService.t("city.autohaus.gekauft_toast"))


## G8-P1: Showroom-Leben — drei Interessenten schleichen um die drei
## Stellplätze (Blick auf den Mittelwagen), andächtig OHNE Gemurmel.
## Momente: die Probesitz-Hupe (city_hupe — alle hüpfen) und der
## Traumwagen-Seufzer (emo_verliebt + Jubelpose). Kein KassenNpc —
## Blechbert steht frei im Raum, kein Tresen (er winkt beim Kauf selbst).
func _leben_konfig() -> Dictionary:
	return {
		"besucher": 3,
		"punkte":
		[
			Vector3(-4.0, 0.0, 0.2),
			Vector3(-1.8, 0.0, 1.6),
			Vector3(0.2, 0.0, -0.7),
			Vector3(3.8, 0.0, -0.5),
		],
		"sprueche": "autohaus",
		"blick": Vector3(0.2, 0.0, -2.4),
		"gemurmel": false,
		"tuer_glocke": true,
		"kasse": false,
		"momente":
		[
			{
				"alle_s": 22.0,
				"versatz_s": 8.0,
				"sound": "city_hupe",
				"pitch": 1.1,
				"clip": "hop",
				"sprueche": "autohaus_hupe",
			},
			{
				"alle_s": 33.0,
				"versatz_s": 19.0,
				"sound": "emo_verliebt",
				"pitch": 1.0,
				"clip": "celebrate",
				"sprueche": "autohaus_traum",
			},
		],
	}

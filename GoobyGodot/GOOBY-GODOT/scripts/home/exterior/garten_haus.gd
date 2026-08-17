class_name GartenHaus
extends Node3D
## Das eigene Haus im GARTEN (HAUS-SICHT, User: „wenn ich im Garten bin
## will ich das Hausdach sehen"). Nutzt das bestehende Außenmodell des
## Gestalten-Modus (HouseExterior.build) mit dem Stil aus HouseStyleState —
## Fassaden-/Dachfarbe, Dachform, Vordach, Briefkasten, Hausnummer kommen
## also 1:1 vom Spieler.
##
## Platzierung über HouseLayout: die Haustür (HouseExterior.TUER_X) steht
## exakt über der Garten-Tür (RoomBase-DoorTransition), die Südfassade
## bildet die Nord-Grenze des Gartens — der Zaun entfällt dort (RoomBase
## lässt die Lücke). Plot-Teile des Außenmodells (Grund/Zaun/Weg) werden
## entfernt (der Garten IST das Grundstück), die Modell-Tür versteckt
## (die begehbare RoomBase-Tür übernimmt) und dahinter liegt eine dunkle
## Türöffnung — beim Öffnen schaut man „ins Haus".

const META_FENSTER_RAUM := "haussicht_raum"
## Plot-Teile, die im Garten doppelt wären (der Garten bringt Boden,
## Zaun und Wege selbst mit).
const ENTFERNEN: Array[String] = ["Grund", "Zaun", "Weg"]
## Maße der Türöffnung hinter der (versteckten) Modell-Tür.
const OEFFNUNG := Vector3(1.0, 1.98, 0.03)
const OEFFNUNG_FARBE := Color(0.26, 0.19, 0.15)
const STUFE_GROESSE := Vector3(1.7, 0.09, 1.1)
const SCHORNSTEIN_GROESSE := Vector3(0.5, 1.0, 0.5)

var _haus: Node3D


## Haus an den Garten-Raum hängen (nur Outdoor-Räume; idempotent).
static func attach_to(room: Node) -> GartenHaus:
	var room_def: Dictionary = room.room_def()
	if not bool(room_def.get("outdoor", false)):
		return null
	var vorhanden := room.get_node_or_null("GartenHaus")
	if vorhanden is GartenHaus:
		return vorhanden
	var haus := GartenHaus.new()
	haus.name = "GartenHaus"
	haus.baue(HouseStyleState.style(room.game_state()), room_def)
	room.add_child(haus)
	return haus


## Baut das Haus aus `style` und richtet es an der Garten-Tür aus.
func baue(style: Dictionary, garden_def: Dictionary) -> void:
	position = HouseLayout.garten_haus_offset(garden_def)
	if _haus != null:
		_haus.queue_free()
	_haus = HouseExterior.build(style)
	add_child(_haus)
	for teil_name in ENTFERNEN:
		var teil := _haus.get_node_or_null(teil_name)
		if teil != null:
			_haus.remove_child(teil)
			teil.free()
	var tuer := _haus.get_node_or_null("Tuer")
	if tuer is Node3D:
		(tuer as Node3D).visible = false
	_briefkasten_an_die_tuer()
	_tag_fenster()
	_haus.add_child(_tueroeffnung())
	_haus.add_child(_stufe(style))
	var schornstein := _schornstein(style)
	if schornstein != null:
		_haus.add_child(schornstein)


## Welt-X (Raumkoordinaten des Gartens) der Haustür — muss mit der
## Garten-Tür übereinstimmen (test_haussicht_garten_haus.gd).
func tuer_welt_x() -> float:
	return position.x + HouseExterior.TUER_X


## Fensterglas glüht abends warm (EVAL-2026-08 Lens B „Fenster leuchten
## abends“) — dieselbe Glut-Rampe wie die Nachbar-Fenster der Kulisse
## (CitySkyline.fensterglut), damit das eigene Haus nachts nicht tot wirkt.
func stunde_anwenden(stunde: float) -> void:
	if CitySkyline.fensterglut(stunde) < 0.4:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = CitySkyline.fensterfarbe(stunde)
	for kind: Node in _haus.get_children():
		if str(kind.name).begins_with("Fenster_"):
			var glas := _glas_von(kind)
			if glas != null:
				glas.material_override = mat


## Die Glas-Scheibe eines HouseExterior-Fensters (erkennbar an der
## 1,1-m-Breite der Scheibe — Rahmen/Sprosse/Bank haben andere Maße).
func _glas_von(fenster: Node) -> MeshInstance3D:
	for kind: Node in fenster.get_children():
		var mesh := kind as MeshInstance3D
		if mesh == null or not (mesh.mesh is BoxMesh):
			continue
		if absf((mesh.mesh as BoxMesh).size.x - 1.1) < 0.01:
			return mesh
	return null


## Der Briefkasten stand am Plot-Südrand (mitten im Garten) — er zieht
## neben die Haustür an die Fassade.
func _briefkasten_an_die_tuer() -> void:
	var briefkasten := _haus.get_node_or_null("Briefkasten")
	if briefkasten is Node3D:
		(briefkasten as Node3D).position = Vector3(
			HouseExterior.TUER_X + 2.0, 0.0, HouseExterior.FRONT_Z + 0.45
		)


## Südfassaden-Fenster den Gartenseiten-Räumen zuordnen (HouseLayout) —
## das linke Fenster gehört der Küche, das rechte dem Bad.
func _tag_fenster() -> void:
	var raeume := HouseLayout.sued_fenster_raeume()
	for i in HouseLayout.SUED_FENSTER_X.size():
		var fenster := _haus.get_node_or_null(
			"Fenster_%d" % int(HouseLayout.SUED_FENSTER_X[i] * 10.0)
		)
		if fenster != null and i < raeume.size():
			fenster.set_meta(META_FENSTER_RAUM, raeume[i])


## Dunkle Öffnung in der Fassadenebene: öffnet die RoomBase-Tür, schaut
## man in den (angedeuteten) Flur statt auf eine Fassadenwand.
func _tueroeffnung() -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = "Tueroeffnung"
	var box := BoxMesh.new()
	box.size = OEFFNUNG
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = OEFFNUNG_FARBE
	mat.roughness = 1.0
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.position = Vector3(
		HouseExterior.TUER_X, OEFFNUNG.y * 0.5, HouseExterior.FRONT_Z + OEFFNUNG.z
	)
	return mesh


## Kleine Schwelle/Terrassenstufe unter der Haustür.
func _stufe(style: Dictionary) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = "Stufe"
	var box := BoxMesh.new()
	box.size = STUFE_GROESSE
	mesh.mesh = box
	mesh.material_override = HouseExterior.teil_material("weg", style)
	if mesh.material_override == null:
		mesh.material_override = CustomizeMaterials.surface("platten", "sandstein")
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.position = Vector3(
		HouseExterior.TUER_X,
		STUFE_GROESSE.y * 0.5 - 0.02,
		HouseExterior.FRONT_Z + STUFE_GROESSE.z * 0.45
	)
	return mesh


## Schornstein aufs Schrägdach (flach hat keinen) — macht die Silhouette
## vom Garten aus als „Haus" lesbar.
func _schornstein(style: Dictionary) -> MeshInstance3D:
	var haus: Dictionary = style.get("haus", CustomizeCatalog.default_haus())
	if str(haus.get("dachForm", "sattel")) == "flach":
		return null
	var mesh := MeshInstance3D.new()
	mesh.name = "Schornstein"
	var box := BoxMesh.new()
	box.size = SCHORNSTEIN_GROESSE
	mesh.mesh = box
	mesh.material_override = CustomizeMaterials.flat("terracotta")
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.position = Vector3(
		HouseExterior.PLOT.x * 0.5 + 2.1,
		HouseExterior.HAUS_HOEHE + 1.15,
		HouseExterior.FRONT_Z - HouseExterior.HAUS_TIEFE * 0.5
	)
	return mesh

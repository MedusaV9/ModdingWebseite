class_name DeckenFade
extends Node
## Decken-Ausblendung der Haussicht (W14, User: „Beim freien rumschauen im
## Haus sollte es keine Decke im Weg geben"). Schaut die Kamera von
## oben/außen auf den Raum (Höhe ÜBER der Wandkrone UND Blick nach unten —
## beides Schwellen mit weichem Band, pure Mathe), blenden Deckenbalken,
## Dachschräge + Sparren (DachInnen) und die CEILING-Deko (W13B:
## Hängelampen/Girlanden) SANFT per Material-Alpha aus — kein hartes
## Popping. Es gibt keinen bestehenden Kamera-Dither im Projekt, deshalb
## bewusst Alpha-Fade: `GeometryInstance3D.transparency` (Dither) wird vom
## Compatibility-Renderer nicht unterstützt, Material-Alpha überall.
##
## CEILING-Items bleiben im Baumodus GEISTERHAFT sichtbar (30 % — man sieht
## beim Bauen, was dort hängt), im Nicht-Baumodus verschwinden sie ganz;
## auf der Decken-Ebene (Ebene.DECKE) sind sie immer voll da. Lampen-Licht
## bleibt an (nur Material wird transparent, kein visible-Toggle — nichts
## kollidiert mit BuildMode.set_furniture_visible). Reduced Motion springt
## sofort auf den Zielwert. Das DachInnen selbst schläft im Baumodus
## weiterhin komplett über HausKontext.

## Kamera-Höhe (m über Raumboden), ab der der Fade beginnt … / … voll ist.
## W21-Befund „braune Halbtransparenz-Bande über dem halben Bild": die
## RUHE-Kamera jedes Raums (HomeCameraRig.follow_distanz × Follow-Pitch)
## liegt zwischen ~2,61 m (Bad, DIST_MIN-Clamp) und ~3,65 m (Wohnzimmer) —
## das alte Band 2,85…4,05 ließ die Decke damit DAUERHAFT halbdurchsichtig
## stehen. Das Band sitzt jetzt direkt über der Wandkrone (2,5 m,
## RoomBase.WALL_HEIGHT): wer drüber ist und steil runterschaut, sieht
## KEINE Decke (Ruhe-Wache: test_w21_decken_ruhe.gd).
const HOEHE_FREI_AB_M := 2.5
const HOEHE_WEG_AB_M := 2.6
## Blick-Neigung nach unten (Grad), ab der der Fade beginnt … / … voll ist.
## Der Decken-Bau-Blick (BuildCamera.PITCH_DECKE, effektiv ~21°) und die
## kanonische Raum-Schrägsicht (~24,6°, s. haussicht_screens) bleiben frei.
const WINKEL_FREI_AB_GRAD := 26.0
const WINKEL_WEG_AB_GRAD := 38.0
## Geister-Alpha der CEILING-Items im Baumodus (sonst 0 = ganz weg).
const GEIST_ALPHA_BAU := 0.3
const GLAETTUNG := 7.0
## Snap-Fenster: näher dran gilt als angekommen (steady state, kein Kriechen).
const SNAP_FENSTER := 0.004
const VOLL_AB := 0.995
const GEIST_FARBE := Color(0.78, 0.86, 1.0)

## Tests erzwingen Reduced Motion (1) / Animation (0); -1 = AppSettings.
var reduced_override := -1

var _room: Node
var _dach: Node3D
var _alpha := 1.0
var _item_alpha := 1.0
var _voll_steady := false
var _geist_mat: StandardMaterial3D

## ── Pure Schwellen-Mathe (test_w14_camcity.gd) ───────────────────────────────


## Ziel-Alpha der Decke: 1 = voll sichtbar, 0 = ausgeblendet. Gefadet wird
## nur, wenn BEIDE Bedingungen greifen (Kamera über der Decke UND Blick
## nach unten) — unter der Decke bzw. bei flachem/aufwärts gerichtetem
## Blick (Decken-Bau) bleibt alles da.
static func ziel_alpha(cam_hoehe_m: float, blick_runter_grad: float) -> float:
	var hoehe_fade := smoothstep(HOEHE_FREI_AB_M, HOEHE_WEG_AB_M, cam_hoehe_m)
	var winkel_fade := smoothstep(WINKEL_FREI_AB_GRAD, WINKEL_WEG_AB_GRAD, blick_runter_grad)
	return 1.0 - minf(hoehe_fade, winkel_fade)


## Ziel-Alpha der CEILING-Items: folgt der Decke, aber der Boden des Fades
## ist im Baumodus das Geister-Alpha (30 %) statt 0 — außer auf der
## Decken-Ebene, dort sind die Items IMMER voll sichtbar (man baut daran).
static func item_ziel_alpha(decken_alpha: float, baumodus: bool, decken_ebene: bool) -> float:
	if decken_ebene:
		return 1.0
	var boden := GEIST_ALPHA_BAU if baumodus else 0.0
	return lerpf(boden, 1.0, clampf(decken_alpha, 0.0, 1.0))


## Blick-Neigung nach unten in Grad (+90 = senkrecht runter, negativ = hoch).
static func blick_runter_grad(forward: Vector3) -> float:
	if forward.length_squared() < 0.000001:
		return 0.0
	return rad_to_deg(asin(clampf(-forward.normalized().y, -1.0, 1.0)))


## Ein Glättungs-Schritt Richtung Ziel; `sofort` (Reduced Motion) springt.
static func schritt(aktuell: float, ziel: float, delta: float, sofort: bool) -> float:
	if sofort:
		return ziel
	var neu := lerpf(aktuell, ziel, 1.0 - exp(-GLAETTUNG * delta))
	if absf(neu - ziel) <= SNAP_FENSTER:
		return ziel
	return neu


## ── Anbindung ────────────────────────────────────────────────────────────────


## An einen RoomBase-Raum hängen (idempotent); `dach` = DachInnen des Raums.
static func attach_to(room: Node, dach: Node3D) -> DeckenFade:
	var vorhanden := room.get_node_or_null("DeckenFade")
	if vorhanden is DeckenFade:
		return vorhanden
	var fade := DeckenFade.new()
	fade.name = "DeckenFade"
	fade._room = room
	fade._dach = dach
	room.add_child(fade)
	return fade


func _process(delta: float) -> void:
	if _room == null or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var ziel := ziel_alpha(cam.global_position.y, blick_runter_grad(-cam.global_basis.z))
	var sofort := _reduced_motion()
	_alpha = schritt(_alpha, ziel, delta, sofort)
	var bau := _baumodus_aktiv()
	if not bau and is_instance_valid(_dach) and _dach.has_method("set_fade_alpha"):
		_dach.set_fade_alpha(_alpha)
	var ziel_item := item_ziel_alpha(ziel, bau, bau and _decken_ebene_aktiv())
	_item_alpha = schritt(_item_alpha, ziel_item, delta, sofort)
	_wende_auf_items_an(_item_alpha)


## Aktueller Decken-Alpha (Tests/Debug).
func alpha() -> float:
	return _alpha


## ── intern ───────────────────────────────────────────────────────────────────


## CEILING-Möbel + Girlanden des Raums faden: unterhalb VOLL_AB bekommen
## alle Meshes das geteilte Geister-Material (Alpha = Fade-Wert), darüber
## wird das Override entfernt. Kein visible-Toggle: Lampen leuchten weiter
## und BuildMode-Sichtbarkeits-Flags bleiben unangetastet.
func _wende_auf_items_an(alpha: float) -> void:
	if not _room.has_method("grid_mount"):
		return
	var mount: Node3D = _room.grid_mount()
	if mount == null:
		return
	var voll := alpha >= VOLL_AB
	if voll and _voll_steady:
		# Neue Nodes starten ohne Override — im Voll-Zustand ist nichts zu tun.
		return
	_voll_steady = voll
	if not voll:
		var mat := _geist_material()
		mat.albedo_color = Color(GEIST_FARBE.r, GEIST_FARBE.g, GEIST_FARBE.b, alpha)
	for child in mount.get_children():
		if child is FurnitureNode and _ist_decken_item(child):
			_override_setzen(child, voll)
	var girlanden := mount.get_node_or_null("GirlandenMount")
	if girlanden != null:
		for girlande in girlanden.get_children():
			_override_setzen(girlande, voll)


## Decken-Item? (Der Bau-Ghost mit uid "ghost" gehört dem BuildMode.)
func _ist_decken_item(node: FurnitureNode) -> bool:
	if node.uid == "ghost":
		return false
	return int(node.item_def.get("layer", -1)) == GridData.Layer.CEILING


func _override_setzen(node: Node, voll: bool) -> void:
	var override: Material = null if voll else _geist_material()
	for mesh in node.find_children("*", "GeometryInstance3D", true, false):
		(mesh as GeometryInstance3D).material_override = override


## Ein geteiltes Geister-Material für alle Decken-Items (Alpha animiert).
func _geist_material() -> StandardMaterial3D:
	if _geist_mat == null:
		_geist_mat = StandardMaterial3D.new()
		_geist_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_geist_mat.roughness = 1.0
	return _geist_mat


func _baumodus_aktiv() -> bool:
	return _room.has_method("is_build_mode_active") and _room.is_build_mode_active()


func _decken_ebene_aktiv() -> bool:
	var build := _room.get_node_or_null("BuildMode")
	if build is BuildMode:
		return (build as BuildMode).ebene() == BuildMode.Ebene.DECKE
	return false


func _reduced_motion() -> bool:
	if reduced_override >= 0:
		return reduced_override == 1
	var settings := get_node_or_null("/root/AppSettings")
	return settings != null and settings.is_reduced_motion()

class_name InteractionSpotlight
extends Node
## Interaktions-Anzeige fürs HUD-Auge (W13/HUD-WIRES, Doc F §5 / P5-F11):
## Solange das Auge aktiv ist, werden ALLE interagierbaren Objekte des
## aktuellen Raums markiert — dreifach:
##  1. Rim-Puls: additiver Fresnel-Saum (interaction_spotlight.gdshader) als
##     `material_overlay` auf den Möbel-Meshes — nicht-destruktiv, EIN
##     geteiltes ShaderMaterial pro Raum. Reduced Motion → Saum ohne Puls.
##  2. Screen-Space-Icon (Funkel) über jedem sichtbaren Interactable.
##  3. Rand-Pfeil für Offscreen-Interactables (Richtung geklemmt an den
##     Bildrand; die Klemm-Mathe ist PURE in `marker_platzierung`).
##
## Ziel-Quellen: die am InteractablesHost gedockten Interactables (W3d)
## plus die DoorTransition-Kinder des Raums. Tests injizieren eigene Ziele
## über `ziel_provider`.
##
## Auto-aus: Baumodus-Öffnen (Signal `build_mode_toggled`) schaltet ab;
## Raumwechsel/Screen-Öffnen erledigt home_entry (der Spotlight hängt als
## Kind am Raum und stirbt mit ihm). Das HUD-Auge selbst hat zusätzlich
## seinen 8-s-Auto-Off. `deaktiviert` sagt dem HUD-Knopf Bescheid.

signal deaktiviert

const RIM_SHADER := preload("res://scripts/home/interaction_spotlight.gdshader")
const ICON_FUNKEL := "res://assets/ui/icons/sparkle.svg"
const ICON_PFEIL := "res://assets/ui/icons/arrow_right.svg"
## Design-px der Marker (skaliert mit UiScale).
const MARKER_PX := 30.0
## Mindestabstand der Marker/Pfeile zum Bildrand (Design-px).
const RAND_PX := 30.0
## Marker-Höhe über Zielen ohne messbare Oberkante (Türen etc.), in m.
const HOEHE_FALLBACK := 1.5
## Luft über der Möbel-Oberkante, in m.
const HOEHE_LUFT := 0.35
## CanvasLayer der Marker: unter Raum-Bubble (5) und HUD (10).
const LAYER := 4
## Positions-Toleranz beim Möbel-Match (Interactables sitzen exakt auf dem
## Möbel-Origin, s. InteractablesHost._dock).
const MOEBEL_EPSILON := 0.05
## Puls-Anteil im Normalmodus (identisch zum Shader-Default).
const PULS_ANTEIL := 0.45

## Tests: Reduced Motion erzwingen (-1 = AppSettings entscheidet).
var reduced_motion_override := -1
## Tests: eigene Ziel-Liste (Callable → Array[Node3D]); leer = Raum-Scan.
var ziel_provider := Callable()

var _room: Node = null
var _aktiv := false
var _layer: CanvasLayer = null
var _material: ShaderMaterial = null
var _eintraege: Array[Dictionary] = []
var _overlay_meshes: Array[MeshInstance3D] = []
var _hinweis_gezeigt := false


## Spotlight erzeugen und an einen Raum hängen (idempotent pro Raum).
static func attach_to(room: Node) -> InteractionSpotlight:
	var existing := room.get_node_or_null("InteractionSpotlight")
	if existing is InteractionSpotlight:
		return existing
	var spot := InteractionSpotlight.new()
	spot.name = "InteractionSpotlight"
	room.add_child(spot)
	spot.setup(room)
	return spot


func setup(room: Node) -> void:
	_room = room
	set_process(false)
	if room.has_signal("build_mode_toggled"):
		room.build_mode_toggled.connect(_on_build_mode_toggled)


## PURE: Marker-Platzierung für einen projizierten Zielpunkt.
## Liegt der Punkt hinter der Kamera, wird er an der Bildmitte gespiegelt,
## damit der Rand-Pfeil in die RICHTIGE Richtung zeigt. Ergebnis:
## {"offscreen": bool, "pos": Vector2 (geklemmt), "winkel": float (rad,
## 0 = Pfeil zeigt nach rechts)}.
static func marker_platzierung(
	punkt: Vector2, hinter_kamera: bool, viewport: Vector2, rand: float
) -> Dictionary:
	var mitte := viewport / 2.0
	var p := punkt
	if hinter_kamera:
		p = mitte + (mitte - punkt)
	var drin := (
		p.x >= rand and p.x <= viewport.x - rand and p.y >= rand and p.y <= viewport.y - rand
	)
	if drin and not hinter_kamera:
		return {"offscreen": false, "pos": p, "winkel": 0.0}
	var geklemmt := Vector2(
		clampf(p.x, rand, viewport.x - rand), clampf(p.y, rand, viewport.y - rand)
	)
	var richtung := p - mitte
	var winkel := richtung.angle() if richtung.length() > 0.001 else 0.0
	return {"offscreen": true, "pos": geklemmt, "winkel": winkel}


func ist_aktiv() -> bool:
	return _aktiv


## Anzahl markierter Ziele (Tests/Diagnose).
func ziel_anzahl() -> int:
	return _eintraege.size()


## Puls-Anteil des Rim-Shaders (0 = Reduced Motion, statischer Saum).
func puls_anteil() -> float:
	if _material == null:
		return 0.0
	return float(_material.get_shader_parameter("puls_anteil"))


func set_aktiv(an: bool) -> void:
	if an == _aktiv:
		return
	_aktiv = an
	if an:
		_aufbauen()
	else:
		_abbauen()
		deaktiviert.emit()


func _aufbauen() -> void:
	_material = ShaderMaterial.new()
	_material.shader = RIM_SHADER
	# Immer explizit setzen: get_shader_parameter liefert für nie gesetzte
	# Uniforms null (nicht den Shader-Default).
	_material.set_shader_parameter("puls_anteil", 0.0 if _reduced_motion() else PULS_ANTEIL)
	_layer = CanvasLayer.new()
	_layer.name = "SpotlightMarker"
	_layer.layer = LAYER
	add_child(_layer)
	for ziel in _ziele():
		if ziel == null or not is_instance_valid(ziel):
			continue
		_markiere(ziel)
	set_process(true)
	_update_marker()
	if not _hinweis_gezeigt and _room != null and _room.has_method("say"):
		_hinweis_gezeigt = true
		_room.say(I18nService.t("home.auge.hinweis"))


func _abbauen() -> void:
	set_process(false)
	for mesh in _overlay_meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = null
	_overlay_meshes = []
	_eintraege = []
	_material = null
	if _layer != null:
		_layer.queue_free()
		_layer = null


func _process(_delta: float) -> void:
	_update_marker()


func _on_build_mode_toggled(active: bool) -> void:
	if active and _aktiv:
		set_aktiv(false)


func _ziele() -> Array[Node3D]:
	if ziel_provider.is_valid():
		var geliefert: Variant = ziel_provider.call()
		var out: Array[Node3D] = []
		if geliefert is Array:
			for ziel: Variant in geliefert:
				if ziel is Node3D:
					out.append(ziel)
		return out
	return _sammle_ziele()


## Ziel-Scan des Raums: gedockte Interactables + Türen (DoorTransition-
## Kinder direkt unterm Raum, s. RoomBase._build_doors).
func _sammle_ziele() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if _room == null:
		return out
	var host := _room.get_node_or_null("InteractablesHost")
	if host != null:
		for child in host.get_children():
			if child is Node3D:
				out.append(child)
	for child in _room.get_children():
		if child is DoorTransition:
			out.append(child)
	return out


## Ein Ziel markieren: Rim-Overlay auf die Meshes + Screen-Marker anlegen.
func _markiere(ziel: Node3D) -> void:
	var moebel := _moebel_von(ziel)
	for mesh: Variant in _rim_meshes(ziel, moebel):
		var instanz := mesh as MeshInstance3D
		if instanz == null or instanz.material_overlay != null:
			continue
		instanz.material_overlay = _material
		_overlay_meshes.append(instanz)
	var marker := TextureRect.new()
	marker.texture = load(ICON_FUNKEL)
	marker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	marker.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.self_modulate = AcTokens.TEAL
	marker.visible = false
	_layer.add_child(marker)
	_eintraege.append({"ziel": ziel, "hoehe": _marker_hoehe(moebel), "marker": marker})


## Das Möbel hinter einem Interactable: bevorzugt dessen `_furniture`-Feld
## (duck-typed), sonst Positions-Match im Grid-Mount (InteractablesHost
## dockt exakt auf den Möbel-Origin). null = Ziel steht für sich (Tür).
func _moebel_von(ziel: Node3D) -> Node3D:
	var feld: Variant = ziel.get("_furniture")
	if feld is Node3D and is_instance_valid(feld):
		return feld
	if _room == null:
		return null
	for mount_name: String in ["GridMount", "Blockers"]:
		var mount := _room.find_child(mount_name, true, false)
		if mount == null:
			continue
		for child in mount.get_children():
			if child is FurnitureNode and _nah(child, ziel):
				return child
	return null


func _nah(a: Node3D, b: Node3D) -> bool:
	return a.global_position.distance_to(b.global_position) <= MOEBEL_EPSILON


## Meshes fürs Rim-Overlay: das Möbel, sonst die eigenen Meshes des Ziels
## (Türen zeichnen selbst). Ohne Meshes bleibt das Icon die Markierung.
func _rim_meshes(ziel: Node3D, moebel: Node3D) -> Array:
	if moebel != null:
		var meshes := moebel.find_children("*", "MeshInstance3D", true, false)
		if not meshes.is_empty():
			return meshes
	return ziel.find_children("*", "MeshInstance3D", true, false)


func _marker_hoehe(moebel: Node3D) -> float:
	if moebel != null and moebel.has_method("top_y"):
		return maxf(float(moebel.top_y()), 0.5) + HOEHE_LUFT
	return HOEHE_FALLBACK


## Screen-Marker nachführen: sichtbares Ziel → Funkel-Icon darüber,
## Offscreen/hinter der Kamera → gedrehter Pfeil am Bildrand.
func _update_marker() -> void:
	if not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var viewport_size := Vector2(get_viewport().get_visible_rect().size)
	var f := UiScale.for_viewport(get_viewport())
	var groesse := Vector2.ONE * MARKER_PX * f
	for eintrag in _eintraege:
		var marker := eintrag["marker"] as TextureRect
		var ziel := eintrag["ziel"] as Node3D
		if marker == null or ziel == null or not is_instance_valid(ziel):
			if marker != null:
				marker.visible = false
			continue
		var welt: Vector3 = ziel.global_position + Vector3(0.0, float(eintrag["hoehe"]), 0.0)
		var platz := marker_platzierung(
			camera.unproject_position(welt),
			camera.is_position_behind(welt),
			viewport_size,
			RAND_PX * f
		)
		var offscreen := bool(platz["offscreen"])
		marker.texture = load(ICON_PFEIL if offscreen else ICON_FUNKEL)
		marker.size = groesse
		marker.pivot_offset = groesse / 2.0
		marker.rotation = float(platz["winkel"]) if offscreen else 0.0
		marker.position = (platz["pos"] as Vector2) - groesse / 2.0
		marker.visible = true


func _reduced_motion() -> bool:
	if reduced_motion_override >= 0:
		return reduced_motion_override == 1
	var settings := get_node_or_null("/root/AppSettings")
	return settings != null and settings.is_reduced_motion()

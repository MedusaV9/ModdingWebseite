extends Node3D
## Der spielende Gooby (Agent 3D-A): dünne Hülle um `GoobyRig` für die fünf
## Spiele, die er selbst bestreitet (schlagen, werfen, halten, angeln, jagen).
##
## Sie regelt vier Dinge, die alle fünf gleich brauchen:
##   1. Größe — die Rohfigur ist 1,13 m hoch; `mount(height)` skaliert sie auf
##      die Weltgröße des Spiels.
##   2. Blickrichtung — das GLB schaut nach +z; `face(yaw)` dreht ihn im Spiel.
##   3. Kurz-Emotionen — `emote("ecstatic", 1.2)` fällt nach der Zeit von
##      selbst auf die Grundstimmung zurück (Treffer-/Fehler-Mimik ohne
##      Timer-Gefummel im Spiel).
##   4. Aktions-Schwung — `swing(seconds)` legt eine kurze Oberkörper-Drehung
##      über die Animation. Das Rig hat keinen Schlag-/Wurf-Clip; der Schwung
##      macht aus `build_hammer`/`wave`/`celebrate` einen sichtbaren Schlag,
##      Wurf oder Hechtsprung, ohne das Rig anzufassen.
##
## `apply_saved_morphs(gs)` läuft automatisch mit: der Spieler-Gooby sieht im
## Minispiel aus wie im Haus.

## Rohhöhe des Rig-GLB in Metern (gooby.glb: aabb.size.y).
const RAW_HEIGHT := 1.13

var rig: GoobyRig
var base_emotion := "happy"

var _pivot: Node3D
var _emote_t := 0.0
var _height := 1.0
var _swing_t := 0.0
var _swing_len := 0.0
var _swing_axis := Vector3.RIGHT
var _swing_deg := 0.0
var _hop_t := 0.0
var _hop_len := 0.0
var _hop_height := 0.0
var _clip_back := ""
var _clip_t := 0.0
var _pending_props: Array = []


## Rig bauen und einhängen. `yaw` = Blickrichtung in Radiant (0 = zur Kamera
## bei Standard-Kameras auf +z).
func mount(height: float, yaw := 0.0, clip := "idle") -> void:
	_height = height
	_pivot = Node3D.new()
	add_child(_pivot)
	rig = GoobyRig.new()
	rig.scale = Vector3.ONE * (height / RAW_HEIGHT)
	rig.rotation.y = yaw
	_pivot.add_child(rig)
	rig.set_emotion(base_emotion)
	rig.play_clip(clip)
	if clip == "idle":
		rig.set_locomotion(0.0)
	var gs := get_node_or_null(^"/root/GameState")
	if gs != null:
		rig.apply_saved_morphs(gs)


## Blickrichtung setzen (Radiant um y).
func face(yaw: float) -> void:
	if rig != null:
		rig.rotation.y = yaw


## Einmal-Clip (wave, hop, celebrate) oder Loop-Zustand (idle, sit,
## build_hammer, brush_teeth).
func play(clip: String) -> void:
	if rig != null:
		rig.play_clip(clip)


## Clip für eine Weile spielen und danach zurückschalten (Schlag-Loop,
## Angel-Loop): `play_for("build_hammer", 0.8)` hämmert kurz und geht zurück
## in den Ruhezustand.
func play_for(clip: String, seconds: float, back := "idle") -> void:
	play(clip)
	_clip_back = back
	_clip_t = maxf(0.05, seconds)


## Requisite an den KÖRPER hängen statt an einen Knochen — sie macht damit
## `swing()`/`hop()` mit, bleibt aber unter Spielkontrolle. Für lange Geräte
## (Angelrute, Kescherstiel), deren Spitze auf einen festen Weltpunkt zeigen
## muss, ist das verlässlicher als `hold()`: die Knochenachsen des Rigs sind
## je Clip anders gedreht.
func attach(prop: Node3D) -> void:
	if _pivot != null:
		_pivot.add_child(prop)


## Requisite in Goobys Pfote hängen (Schläger, Angel, Laterne, Kescher).
## `xform` ist im RIG-Raum (Gooby ist dort 1,13 m hoch), die Skalierung auf
## die Spielgröße macht das Rig selbst. Wird verzögert eingehängt, sobald das
## GoobyRig sein Skelett gebaut hat.
func hold(prop: Node3D, bone := "arm.R", xform := Transform3D.IDENTITY) -> void:
	_pending_props.append({"node": prop, "bone": bone, "xform": xform})
	_mount_props()


## Lauf-Blend 0..1 (idle ↔ walk).
func run(speed01: float) -> void:
	if rig != null:
		rig.set_locomotion(clampf(speed01, 0.0, 1.0))


## Grundstimmung dauerhaft setzen.
func set_mood(id: String) -> void:
	base_emotion = id
	if rig != null and _emote_t <= 0.0:
		rig.set_emotion(id)


## Kurze Gefühlsregung, danach zurück zur Grundstimmung.
func emote(id: String, seconds := 1.1) -> void:
	if rig == null:
		return
	rig.set_emotion(id)
	_emote_t = seconds


## Kurzer Körperschwung über die laufende Animation (Schlag/Wurf/Hechte).
## `axis` ist die Drehachse im Spielraum, `degrees` der Ausschlag.
func swing(seconds := 0.45, degrees := 42.0, axis := Vector3.RIGHT) -> void:
	_swing_len = maxf(0.05, seconds)
	_swing_t = _swing_len
	_swing_deg = degrees
	_swing_axis = axis.normalized()


## Kleiner Hüpfer (Jubel, Hechtsprung) — hebt die Figur kurz an.
func hop(seconds := 0.45, height := 0.35) -> void:
	_hop_len = maxf(0.05, seconds)
	_hop_t = _hop_len
	_hop_height = height


## Höhe der Figur in Weltmetern (für Schatten-/Aura-Größen).
func height() -> float:
	return _height


## Vom Spiel getickt, damit Pause wirklich pausiert.
func tick(delta: float) -> void:
	if not _pending_props.is_empty():
		_mount_props()
	if _clip_t > 0.0:
		_clip_t -= delta
		if _clip_t <= 0.0:
			play(_clip_back)
	if _emote_t > 0.0:
		_emote_t -= delta
		if _emote_t <= 0.0 and rig != null:
			rig.set_emotion(base_emotion)
	if _pivot == null:
		return
	var swing_rot := Basis.IDENTITY
	if _swing_t > 0.0:
		_swing_t = maxf(0.0, _swing_t - delta)
		# Halbe Sinuswelle: ausholen, durchziehen, zurück in die Ruhelage.
		var f := 1.0 - _swing_t / _swing_len
		swing_rot = Basis(_swing_axis, deg_to_rad(_swing_deg) * sin(f * PI))
	var lift := 0.0
	if _hop_t > 0.0:
		_hop_t = maxf(0.0, _hop_t - delta)
		var g := 1.0 - _hop_t / _hop_len
		lift = _hop_height * sin(g * PI)
	_pivot.transform = Transform3D(swing_rot, Vector3(0.0, lift, 0.0))


## Das GoobyRig baut sein Skelett erst in _ready(); die Requisiten warten so
## lange in der Schlange.
func _mount_props() -> void:
	if rig == null or not rig.is_inside_tree():
		return
	var found := rig.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return
	var skeleton := found[0] as Skeleton3D
	for entry: Dictionary in _pending_props:
		var idx := skeleton.find_bone(str(entry["bone"]))
		if idx < 0:
			# W13C-Leak-Gate: nie montierte Requisiten nicht als Waisen
			# liegen lassen — die Schlange wird unten geleert.
			(entry["node"] as Node).queue_free()
			continue
		var attach := BoneAttachment3D.new()
		attach.bone_name = str(entry["bone"])
		attach.bone_idx = idx
		skeleton.add_child(attach)
		var prop: Node3D = entry["node"]
		attach.add_child(prop)
		prop.transform = entry["xform"]
	_pending_props.clear()

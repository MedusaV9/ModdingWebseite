extends Node3D
## Gooby im Spiel (Agent 3D-B): dünne Hülle um `GoobyRig` für die fünf
## 3D-Minispiele. Sie regelt die drei Dinge, die alle fünf gleich brauchen:
##
##   1. Blickrichtung — das GLB schaut nach +z; wer von der Kamera WEG läuft
##      (Renner, Surf, Kutter, Kart), wird um 180° gedreht.
##   2. Größe — die Rohfigur ist 1,13 m hoch; `mount(height)` skaliert sie auf
##      die Weltgröße des jeweiligen Spiels.
##   3. Kurz-Emotionen — `emote("dizzy", 1.2)` fällt nach der Zeit von selbst
##      auf die Grundstimmung zurück (Crash-/Kombo-Mimik ohne Timer-Gefummel).
##
## Sitzt Gooby in einem Fahrzeug, macht `mount(..., true)` den Sitz-Clip an und
## kippt die Beine unter die Karosserie — er ist dann von hinten SICHTBAR im
## Fahrzeug, nicht daneben.

## Rohhöhe des Rig-GLB in Metern (aus gooby.glb: aabb.size.y).
const RAW_HEIGHT := 1.13

var rig: GoobyRig
var base_emotion := "happy"

var _emote_t := 0.0
var _seated := false
var _height := 1.0


## Rig bauen und einhängen. `facing_away` dreht ihn von der Kamera weg.
##
## Achtung: Das Rig baut seine Clip-Tabelle erst in `_ready()`. Wird `mount()`
## aufgerufen, BEVOR die Halterung im Baum hängt (der Normalfall — erst bauen,
## dann anhängen), läuft `play_clip()` sonst ins Leere. Darum merken wir uns die
## Startpose und setzen sie in `_ready()`.
func mount(height: float, seated := false, facing_away := true) -> void:
	_height = height
	_seated = seated
	rig = GoobyRig.new()
	rig.scale = Vector3.ONE * (height / RAW_HEIGHT)
	if facing_away:
		rig.rotation.y = PI
	add_child(rig)
	if is_inside_tree():
		_apply_start_pose()


func _ready() -> void:
	_apply_start_pose()


func _apply_start_pose() -> void:
	if rig == null or not rig.is_inside_tree():
		return
	rig.set_emotion(base_emotion)
	if _seated:
		rig.play_clip("sit")
	else:
		rig.play_clip("idle")
		rig.set_locomotion(1.0)


## Lauf-Tempo 0..1 (idle ↔ walk). Beim Sitzen wirkungslos.
func run(speed01: float) -> void:
	if rig != null and not _seated:
		rig.set_locomotion(clampf(speed01, 0.0, 1.0))


## Einmal-Clip (hop, wave, celebrate …).
func play(clip: String) -> void:
	if rig != null:
		rig.play_clip(clip)


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


## Vom Spiel getickt (damit Pause wirklich pausiert).
func tick(delta: float) -> void:
	if _emote_t <= 0.0:
		return
	_emote_t -= delta
	if _emote_t <= 0.0 and rig != null:
		rig.set_emotion(base_emotion)


## Höhe der Figur in Weltmetern (für Schatten/Aura-Größen).
func height() -> float:
	return _height

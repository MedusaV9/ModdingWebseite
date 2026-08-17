extends "res://tools/capture/clip_driver.gd"
## Clip: Boot-Cover-Ladebildschirm (W14/LOADING) — Vollbild-Artwork mit
## Möhren-Ladebalken und rotierenden Lade-Sprüchen; der Balken füllt sich,
## dann öffnet der Kreis-Wipe (Zoom auf Gooby + Konfetti-Puff) ins fertig
## eingerichtete Wohnzimmer — genau der erste Spielstart-Moment.
## Treiber-Regie: der Fortschritt läuft über die CLIP-Zeit (t) statt über
## echte BootPhasen — main.gd bleibt unangetastet (Frozen-Contract).

## Clip-Sekunden, bis der Balken voll ist (danach öffnet der Wipe).
const BALKEN_VOLL_S := 4.6

var room: Node3D
var cover: BootCoverScreen
var _oeffnet := false


func _setup() -> void:
	duration = 8.0
	# Wohnzimmer als Reveal-Ziel HINTER dem Cover (CanvasLayer 120 deckt).
	var packed: PackedScene = load("res://scenes/home/wohnzimmer.tscn")
	room = packed.instantiate()
	room.stunde_override = 15.0
	add_child(room)
	cover = BootCoverScreen.new()
	# Deterministische Spruch-Rotation (jeder Lauf zeigt dieselben Sprüche).
	cover.spruch_seed = 7
	add_child(cover)
	schedule(0.3, _kamera_flacher)
	schedule(0.5, _gooby_beruhigen)
	schedule(BALKEN_VOLL_S + 0.4, _oeffnen)
	schedule(BALKEN_VOLL_S + 1.4, _winken)


func _tick(_delta: float) -> void:
	# Echter set_progress-Pfad, aber in Movie-Zeit getaktet (statt Wanduhr).
	if cover != null and not _oeffnet:
		cover.set_progress(clampf(t / BALKEN_VOLL_S, 0.0, 1.0))


## Wie in home_room: Deckenbalken (DachInnen) aus der Bildmitte nehmen —
## flacherer Blick, Gooby und Möbel bleiben frei.
func _kamera_flacher() -> void:
	var rig: Node3D = room.camera_rig()
	if rig == null:
		return
	var dist: float = rig._offset.length()
	rig._offset = Vector3(0.0, 2.9, 5.6).normalized() * dist


func _gooby_beruhigen() -> void:
	var gooby: Node3D = room._gooby
	if gooby == null:
		return
	# Kein Wander-Ziel hinter dem Cover — Gooby soll beim Reveal mittig stehen.
	gooby.set_wander_enabled(false)


func _oeffnen() -> void:
	_oeffnet = true
	cover.set_progress(1.0)
	# Zoom + Kreis-Wipe + Konfetti (Coroutine — Tweens laufen in Movie-Zeit).
	cover.oeffne(false)


func _winken() -> void:
	var gooby: Node3D = room._gooby
	if gooby == null or gooby.rig == null:
		return
	gooby.rig.play_clip("wave")
	gooby.rig.set_emotion("ecstatic")

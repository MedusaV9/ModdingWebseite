extends Node
## OrientationService — Orientierungs-Klassifikation + Lock-Wrapper (W1a).
##
## - classify(): pure LANDSCAPE/PORTRAIT-Klassifikation (headless testbar).
## - lock()/unlock(): Wrapper um DisplayServer.screen_set_orientation; die
##   globale Präferenz kommt aus AppSettings ("orientation_mode").
## - Broadcastet orientation_changed bei Viewport-Resize (Geräterotation).
## Headless-sicher: auf dem headless-DisplayServer wird nichts gesetzt.
## Contract nach W1 FROZEN (Handoff W1a-core.md).

signal orientation_changed(orientation: int)
signal lock_changed(lock_mode: int)

enum Orientation { LANDSCAPE, PORTRAIT }
enum LockMode { AUTO, LANDSCAPE, PORTRAIT }

var current_lock: int = LockMode.AUTO

var _current_orientation: int = Orientation.LANDSCAPE


func _ready() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.size_changed.connect(_on_viewport_resized)
		_current_orientation = classify(_viewport_size(viewport))
	_apply_screen_orientation()


## Quadratische Viewports gelten als LANDSCAPE (Design-Basis ist Querformat).
static func classify(size: Vector2i) -> int:
	return Orientation.PORTRAIT if size.y > size.x else Orientation.LANDSCAPE


## Pure Auflösung von Lock-Modus + globaler Präferenz auf die
## DisplayServer.ScreenOrientation (Sensor-Varianten, nie hart gelockt).
## FIX1: „auto“ heißt QUERFORMAT — das Spiel ist landscape-first
## (project.godot handheld/orientation=4); Hochkant gibt es nur per
## explizitem Minigame-Lock oder wenn der User es in den Settings wählt.
static func resolve_screen_orientation(lock_mode: int, global_mode: String) -> int:
	if lock_mode == LockMode.LANDSCAPE:
		return DisplayServer.SCREEN_SENSOR_LANDSCAPE
	if lock_mode == LockMode.PORTRAIT:
		return DisplayServer.SCREEN_SENSOR_PORTRAIT
	match global_mode:
		"portrait":
			return DisplayServer.SCREEN_SENSOR_PORTRAIT
		"sensor":
			return DisplayServer.SCREEN_SENSOR
		_:
			return DisplayServer.SCREEN_SENSOR_LANDSCAPE


func get_orientation() -> int:
	return _current_orientation


## Lockt die Bildschirm-Orientierung (z. B. pro Minigame). AUTO = globale
## Präferenz aus AppSettings anwenden.
func lock(mode: int) -> void:
	current_lock = mode
	_apply_screen_orientation()
	lock_changed.emit(mode)


## Zurück auf die globale Präferenz (beim Verlassen eines Minigames).
func unlock() -> void:
	lock(LockMode.AUTO)


func _global_mode() -> String:
	var settings := get_node_or_null("/root/AppSettings")
	if settings != null and settings.has_method("orientation_mode"):
		return settings.orientation_mode()
	return "auto"


func _apply_screen_orientation() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var target := resolve_screen_orientation(current_lock, _global_mode())
	DisplayServer.screen_set_orientation(target as DisplayServer.ScreenOrientation)


func _on_viewport_resized() -> void:
	var next := classify(_viewport_size(get_viewport()))
	if next != _current_orientation:
		_current_orientation = next
		orientation_changed.emit(next)


static func _viewport_size(viewport: Viewport) -> Vector2i:
	return Vector2i(viewport.get_visible_rect().size)

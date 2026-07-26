extends "res://tools/capture/clip_driver.gd"
## Basis der Minigame-Clips: mountet den ECHTEN MinigameHost (Countdown,
## Score-HUD, Results) mit festem Seed, kürzt den Countdown und liefert
## Koordinaten-Helfer vom Spiel-Viewport in Fensterpixel.

var game_id := ""
var difficulty := "normal"
var seed_value := 12345
var host: Control
var _play_started := false


func _setup() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("set_value"):
		gs.set_value("gooby.stats.energy", 100.0)
	var packed: PackedScene = load("res://scripts/minigames/minigame_host.tscn")
	host = packed.instantiate()
	host.countdown_step_sec = 0.22
	host.auto_navigate = false
	host.receive_params({
		"game_id": game_id, "difficulty": difficulty, "seed": seed_value,
	})
	add_child(host)


func game() -> Node:
	return host._game if host != null else null


func game_active() -> bool:
	var g := game()
	return g != null and g.has_method("is_active") and g.is_active()


## WICHTIG: Die Spiele leben in einem SubViewport. Fenster-Events erreichen
## dessen _unhandled_input nicht zuverlässig, deshalb überschreiben wir die
## Injektion der Basisklasse und pushen ECHTE Touch-Events direkt in den
## SubViewport (alle Koordinaten hier sind Spiel-Viewport-Pixel).
func send_button(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = pos
	ev.pressed = pressed
	host._viewport.push_input(ev, true)


func send_motion(pos: Vector2, rel: Vector2, dragging: bool) -> void:
	if not dragging:
		return
	var ev := InputEventScreenDrag.new()
	ev.index = 0
	ev.position = pos
	ev.relative = rel
	host._viewport.push_input(ev, true)


## Historischer Name: liefert heute unverändert Spiel-Viewport-Pixel
## (send_button/send_motion pushen direkt in den SubViewport).
func to_window(game_px: Vector2) -> Vector2:
	return game_px


## Normalisierte Bühnen-Koordinate (0..1) → Spiel-Viewport-Pixel.
func stage_pos(nx: float, ny: float) -> Vector2:
	var vp_size := Vector2(host._viewport.size)
	return Vector2(vp_size.x * nx, vp_size.y * ny)


func send_key(keycode: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = pressed
	Input.parse_input_event(ev)


func key_tap(keycode: Key, hold := 0.1) -> void:
	send_key(keycode, true)
	schedule(t + hold, func() -> void: send_key(keycode, false))


func _tick(delta: float) -> void:
	if not _play_started and game_active():
		_play_started = true
		_on_play_start()
	if _play_started:
		_drive(delta)


## Hook: einmalig wenn der Countdown vorbei ist.
func _on_play_start() -> void:
	pass


## Hook: pro Frame solange das Spiel läuft.
func _drive(_delta: float) -> void:
	pass

extends Node
## Basisklasse aller Trailer-Clip-Treiber: Zeitplan (schedule), Maus-/Touch-
## Injektion (tap/drag — das Projekt emuliert Touch aus Maus), eigene
## Kino-Kamera und sauberes Selbst-Beenden nach `duration` Sekunden.
## Läuft unter --fixed-fps 60, delta ist also deterministisch 1/60 s.

## Clip-Länge in Sekunden; danach quit() (Movie-Maker schließt die Datei).
var duration := 6.0
## Verstrichene Clip-Zeit.
var t := 0.0

var _events: Array[Dictionary] = []
var _drags: Array[Dictionary] = []
var _holds: Dictionary = {}
var _cine_cam: Camera3D
var _cam_moves: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_erzwinge_hohe_qualitaet()
	_setup()


## Movie-Maker rendert offline (feste Schrittweite) — Wandzeit ist egal,
## deshalb volle Qualität statt Auto-Profil. Hintergrund (Trailer-Feedback
## „pixelig“): das Auto-Profil stufte unter xvfb wegen der kleinen
## Fensterkante auf „mittel“ herab (scale_3d 0.8, Schatten niedrig, Glow
## aus), zusätzlich war MSAA hier hart deaktiviert.
func _erzwinge_hohe_qualitaet() -> void:
	var auto_bundle := QualityProfiles.resolve_auto(
		DeviceProfile.classify(DeviceProfile.snapshot())
	)
	print("[capture] Auto-Profil hätte gewählt: %s" % str(auto_bundle))
	var settings := get_node_or_null("/root/AppSettings")
	if settings != null and settings.has_method("set_setting"):
		settings.set_setting("graphics.preset", "hoch")
	var quality := get_node_or_null("/root/Quality")
	if quality != null:
		quality.set("brake_enabled", false)
	wende_hq_an(get_viewport())
	print(
		(
			"[capture] Qualität erzwungen: preset=hoch scale_3d=%.2f msaa=%d schatten_atlas=%d fenster=%s"
			% [
				get_viewport().scaling_3d_scale,
				get_viewport().msaa_3d,
				get_viewport().positional_shadow_atlas_size,
				str(get_viewport().size),
			]
		)
	)


## Maximale Render-Qualität auf ein Viewport anwenden — auch für Szenen
## mit eigenem SubViewport (Minigame-Host) aufrufen, das Quality-Autoload
## bedient nur das Root-Viewport.
func wende_hq_an(vp: Viewport) -> void:
	vp.scaling_3d_scale = 1.0
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.msaa_3d = Viewport.MSAA_4X
	vp.positional_shadow_atlas_size = 4096
	RenderingServer.directional_shadow_atlas_set_size(4096, true)


## Überschreiben: Szene mounten + Zeitplan füllen.
func _setup() -> void:
	pass


func _process(delta: float) -> void:
	t += delta
	for ev in _events:
		if not ev["done"] and t >= float(ev["at"]):
			ev["done"] = true
			(ev["fn"] as Callable).call()
	_tick_drags()
	_tick_camera()
	_tick(delta)
	if t >= duration:
		print("[capture] Clip fertig (%.1f s)" % t)
		get_tree().quit()


## Überschreiben für pro-Frame-Steuerung (z. B. Lenken).
func _tick(_delta: float) -> void:
	pass


func schedule(at: float, fn: Callable) -> void:
	_events.append({"at": at, "fn": fn, "done": false})


## ------------------------------------------------------------ Eingaben
## Fenster-Koordinaten. emulate_touch_from_mouse=true macht daraus Touch.


func send_button(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(ev)


func send_motion(pos: Vector2, rel: Vector2, dragging: bool) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.relative = rel
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if dragging else 0
	Input.parse_input_event(ev)


## Kurzer Tipper (drücken + nächsten Frame loslassen).
func tap(pos: Vector2) -> void:
	send_button(pos, true)
	schedule(t + 0.05, func() -> void: send_button(pos, false))


## Fingerzug von A nach B über `dur` Sekunden (drücken→ziehen→loslassen).
func drag(from: Vector2, to: Vector2, dur: float) -> void:
	_drags.append(
		{"from": from, "to": to, "t0": t, "t1": t + maxf(dur, 0.05), "down": false, "last": from}
	)


## Halten an einer Position (bis release_hold).
func hold(id: String, pos: Vector2) -> void:
	if _holds.has(id):
		return
	_holds[id] = pos
	send_button(pos, true)


func release_hold(id: String) -> void:
	if not _holds.has(id):
		return
	var pos: Vector2 = _holds[id]
	_holds.erase(id)
	send_button(pos, false)


func _tick_drags() -> void:
	var keep: Array[Dictionary] = []
	for d in _drags:
		if not d["down"]:
			send_button(d["from"], true)
			d["down"] = true
		var k: float = clampf((t - float(d["t0"])) / (float(d["t1"]) - float(d["t0"])), 0.0, 1.0)
		var eased := k * k * (3.0 - 2.0 * k)
		var pos: Vector2 = (d["from"] as Vector2).lerp(d["to"], eased)
		send_motion(pos, pos - (d["last"] as Vector2), true)
		d["last"] = pos
		if k >= 1.0:
			send_button(pos, false)
		else:
			keep.append(d)
	_drags = keep


## ------------------------------------------------------- Kino-Kamera
## Eigene Camera3D über die Spielszene legen (nur Aufnahme-Regie, kein
## Eingriff ins Spiel). move_camera plant eine sanfte Fahrt.


func cine_camera(pos: Vector3, look_at_target: Vector3, fov := 45.0) -> Camera3D:
	if _cine_cam == null:
		_cine_cam = Camera3D.new()
		_cine_cam.name = "TrailerCam"
		add_child(_cine_cam)
	_cine_cam.position = pos
	if not pos.is_equal_approx(look_at_target):
		_cine_cam.look_at_from_position(pos, look_at_target)
	_cine_cam.fov = fov
	_cine_cam.current = true
	return _cine_cam


## Kamerafahrt: von der aktuellen Pose zu (pos, look) über dur Sekunden.
func move_camera(pos: Vector3, look_at_target: Vector3, dur: float, fov := -1.0) -> void:
	if _cine_cam == null:
		return
	(
		_cam_moves
		. append(
			{
				"p0": _cine_cam.position,
				"p1": pos,
				"l0": _cam_look_point(),
				"l1": look_at_target,
				"f0": _cine_cam.fov,
				"f1": _cine_cam.fov if fov <= 0.0 else fov,
				"t0": t,
				"t1": t + dur,
			}
		)
	)


func _cam_look_point() -> Vector3:
	# Punkt 5 m vor der Kamera als Blickziel-Näherung.
	return _cine_cam.position - _cine_cam.global_transform.basis.z * 5.0


func _tick_camera() -> void:
	if _cine_cam == null or _cam_moves.is_empty():
		return
	var m: Dictionary = _cam_moves[0]
	var k: float = clampf((t - float(m["t0"])) / (float(m["t1"]) - float(m["t0"])), 0.0, 1.0)
	var eased := k * k * (3.0 - 2.0 * k)
	var pos: Vector3 = (m["p0"] as Vector3).lerp(m["p1"], eased)
	var look: Vector3 = (m["l0"] as Vector3).lerp(m["l1"], eased)
	_cine_cam.fov = lerpf(float(m["f0"]), float(m["f1"]), eased)
	if not pos.is_equal_approx(look):
		_cine_cam.look_at_from_position(pos, look)
	if k >= 1.0:
		_cam_moves.pop_front()


## ------------------------------------------------------------ Sonstiges


func window_size() -> Vector2:
	return Vector2(get_viewport().size)


## Canvas-Koordinate (stretch=canvas_items, Basis 1280x720) → Fensterpixel.
## Injizierte Events werden als FENSTER-Pixel interpretiert (empirisch per
## calibrate.gd verifiziert) — GUI-Rects (get_global_rect) liegen aber im
## Canvas-Raum und MÜSSEN hierdurch skaliert werden.
func ui(canvas_pos: Vector2) -> Vector2:
	var vp := get_viewport()
	return canvas_pos * (Vector2(vp.size) / vp.get_visible_rect().size)


## Wartet f Frames (in Sekunden bei 60 fps).
static func frames(f: int) -> float:
	return f / 60.0

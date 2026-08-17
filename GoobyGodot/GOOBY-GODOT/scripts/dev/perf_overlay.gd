extends CanvasLayer
## W4-P5 (INFRA, Plan §2.4-14) — Dev-Performance-Overlay.
##
## Zeigt FPS, Frame-Zeit, Draw Calls + Primitive (RenderingServer.
## get_rendering_info), Node-Anzahl und VRAM als kompakte Kapsel oben links.
## Sichtbar machen (nur in Debug-Builds, s. u.):
##  - 3-Finger-Tap irgendwo auf den Screen (Touch; Cooldown gegen Doppel-Trigger)
##  - ODER AppSettings-Debug-Setting `dev.perf_overlay` (Settings-API von W1a;
##    der Tap schreibt das Setting zurück, damit der Zustand persistiert).
##
## RELEASE-GUARD: In Nicht-Debug-Builds (OS.is_debug_build() == false)
## entfernt sich der Node in _ready() komplett — kein Input-Handling, kein
## Label, keine Kosten. Autoload-Registrierung: Request in
## handoffs/project-godot-requests.md (PerfOverlay, NACH AppSettings).
##
## Headless-sicher: RenderingServer liefert im Dummy-Renderer schlicht 0en;
## snapshot() ist deshalb auch in Tests/CI aufrufbar.

## Punkt-Pfad im AppSettings-Store (W1a-API get_setting/set_setting).
const SETTING_KEY := "dev.perf_overlay"
## Overlay liegt über allem (HUD/Popups nutzen deutlich kleinere Layer).
const OVERLAY_LAYER := 120
## Metriken-Refresh (s) — 4 Hz reicht und kostet nichts.
const REFRESH_S := 0.25
## Mindestabstand zwischen zwei 3-Finger-Toggles (ms).
const TAP_COOLDOWN_MS := 600

var _label: Label
var _panel: PanelContainer
var _pressed_fingers := {}
var _last_toggle_ms := 0
var _accum := 0.0


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	layer = OVERLAY_LAYER
	_build_ui()
	_panel.visible = false
	var settings := get_node_or_null("/root/AppSettings")
	if settings != null:
		_panel.visible = settings.get_setting(SETTING_KEY, false) == true
		settings.setting_changed.connect(_on_setting_changed)
	set_process(_panel.visible)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_pressed_fingers[event.index] = true
			if _pressed_fingers.size() >= 3:
				var now := Time.get_ticks_msec()
				if now - _last_toggle_ms >= TAP_COOLDOWN_MS:
					_last_toggle_ms = now
					toggle()
		else:
			_pressed_fingers.erase(event.index)


func _process(delta: float) -> void:
	_accum += delta
	if _accum < REFRESH_S:
		return
	_accum = 0.0
	_label.text = _format(snapshot())


## Overlay ein-/ausschalten (persistiert nach AppSettings, wenn vorhanden).
func toggle() -> void:
	set_shown(not _panel.visible)


func set_shown(shown: bool) -> void:
	if _panel == null:
		return
	_panel.visible = shown
	set_process(shown)
	if shown:
		_label.text = _format(snapshot())
	var settings := get_node_or_null("/root/AppSettings")
	if settings != null and settings.get_setting(SETTING_KEY, false) != shown:
		settings.set_setting(SETTING_KEY, shown)


func is_shown() -> bool:
	return _panel != null and _panel.visible


## Aktuelle Messwerte — auch headless/vom Mess-Harness (perf_probe.gd) nutzbar.
func snapshot() -> Dictionary:
	var rs := RenderingServer
	return {
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"frame_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"draw_calls": int(rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"vram_mb": rs.get_rendering_info(rs.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
	}


func _on_setting_changed(key: String, value: Variant) -> void:
	if key == SETTING_KEY and (value == true) != _panel.visible:
		set_shown(value == true)


func _format(m: Dictionary) -> String:
	return (
		"FPS %d  (%.1f ms)\nDraw Calls %d\nPrimitive %s\nNodes %d\nVRAM %.1f MB"
		% [
			int(m["fps"]),
			m["frame_ms"],
			m["draw_calls"],
			_group_digits(int(m["primitives"])),
			m["nodes"],
			m["vram_mb"],
		]
	)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "PerfPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.62)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	_panel.add_theme_stylebox_override("panel", style)
	_panel.position = Vector2(12.0, 12.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.name = "PerfLabel"
	_label.add_theme_color_override("font_color", Color(0.65, 1.0, 0.65))
	_label.add_theme_font_size_override("font_size", 15)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)
	add_child(_panel)


func _group_digits(n: int) -> String:
	var raw := str(n)
	var out := ""
	var count := 0
	for i in range(raw.length() - 1, -1, -1):
		out = raw[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = " " + out
	return out

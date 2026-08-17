class_name GewitterSzene
extends RefCounted
## Gewitter-Angst (W3d BACKLOG-REST, Doc F §4.2) — ausgelagerte Runner-Szene
## (W18/CI-Split wegen gdlint max-file-lines, Muster wie mumie_szene.gd):
## Es donnert, Gooby ist WEG — nur zwei Augen im Dunkeln. Taschenlampen-
## Overlay (Spot folgt dem Finger), Blitz-Flashes + Donner; wer die Augen
## im Lichtkegel antippt, findet ihn — Streichel-Tap beruhigt, er schläft
## ein. PURE Statics AUF dem Runner-Zustand (_flash_overlay/_flash_timer/
## _eyes_spot/_gewitter_found/_props): der Runner bleibt Besitzer von
## Props und Lebensdauer wie bei den Inline-Szenen, nur der Code wohnt hier.

## Taschenlampen-Radius (px) + Trefferfenster auf die Augen.
const FLASHLIGHT_RADIUS_PX := 150.0
const GEWITTER_HIT_PX := 150.0


## Szene aufbauen: Gooby versteckt, Augen-Paar, Overlay + Donner-Timer.
static func setup(runner: EventRunner) -> void:
	var gooby := runner._gooby()
	if gooby == null:
		runner._running = false
		return
	gooby.set_wander_enabled(false)
	gooby.visible = false
	runner._gewitter_found = false
	# Augen im Dunkeln: zwei weiße Kügelchen an einem freien Fleck.
	runner._eyes_spot = Node3D.new()
	var cells := runner._free_cells()
	if cells.is_empty():
		runner._eyes_spot.position = gooby.position + Vector3(1.2, 0.0, 0.8)
	else:
		var cell: Vector2i = cells[runner._rng.randi_range(0, cells.size() - 1)]
		runner._eyes_spot.position = GridData.world_center(cell, Vector2i.ONE, 0)
	for offset_x: float in [-0.07, 0.07]:
		var eye := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.045
		ball.height = 0.09
		eye.mesh = ball
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1, 1, 1)
		mat.emission_enabled = true
		mat.emission = Color(0.9, 0.9, 1.0)
		eye.material_override = mat
		eye.position = Vector3(offset_x, 0.35, 0.0)
		runner._eyes_spot.add_child(eye)
	runner.add_child(runner._eyes_spot)
	runner._props.append(runner._eyes_spot)
	runner._say("events.gewitter.bubble")
	_build_flashlight_overlay(runner)
	runner._flash_timer = Timer.new()
	runner._flash_timer.wait_time = 4.0
	runner._flash_timer.timeout.connect(GewitterSzene.thunder.bind(runner))
	runner.add_child(runner._flash_timer)
	runner._flash_timer.start()
	thunder(runner)


## Dunkel-Overlay mit Taschenlampen-Loch (Shader folgt dem Zeiger).
static func _build_flashlight_overlay(runner: EventRunner) -> void:
	runner._flash_overlay = EventProps.flashlight_overlay(FLASHLIGHT_RADIUS_PX)
	runner._flash_overlay.gui_input.connect(GewitterSzene.flashlight_input.bind(runner))
	runner._ui_layer().add_child(runner._flash_overlay)


static func flashlight_input(event: InputEvent, runner: EventRunner) -> void:
	var mat := runner._flash_overlay.material as ShaderMaterial
	if event is InputEventMouseMotion:
		mat.set_shader_parameter("hole_px", (event as InputEventMouseMotion).position)
	elif event is InputEventScreenDrag:
		mat.set_shader_parameter("hole_px", (event as InputEventScreenDrag).position)
	var pressed: bool = (
		(event is InputEventMouseButton and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
	)
	if not pressed:
		return
	var tap: Vector2 = event.position
	mat.set_shader_parameter("hole_px", tap)
	var camera := runner.get_viewport().get_camera_3d()
	if camera == null or runner._eyes_spot == null or not is_instance_valid(runner._eyes_spot):
		return
	var eyes_px := camera.unproject_position(
		runner._eyes_spot.global_position + Vector3(0, 0.35, 0)
	)
	if tap.distance_to(eyes_px) > GEWITTER_HIT_PX:
		return
	if not runner._gewitter_found:
		found(runner)
	else:
		petted(runner)


static func found(runner: EventRunner) -> void:
	runner._gewitter_found = true
	var gooby := runner._gooby()
	if gooby != null:
		gooby.position = runner._eyes_spot.position
		gooby.visible = true
		runner._set_gooby_emotion("scared")
	if runner._eyes_spot != null and is_instance_valid(runner._eyes_spot):
		runner._eyes_spot.visible = false
	runner._say("events.gewitter.gefunden")


static func petted(runner: EventRunner) -> void:
	if runner._flash_timer != null:
		runner._flash_timer.stop()
	if runner._flash_overlay != null and is_instance_valid(runner._flash_overlay):
		var fade := runner.create_tween()
		fade.tween_property(runner._flash_overlay, "modulate:a", 0.0, 0.6)
		fade.tween_callback(runner._flash_overlay.queue_free)
		runner._flash_overlay = null
	runner._sfx("ui_confirm")
	runner._say("events.gewitter.danke")
	var gooby := runner._gooby()
	if gooby != null:
		runner._set_gooby_emotion("sleepy")
		gooby.play_clip("sleep")
	runner._resolve()


## Blitz + Donner: kurzer weißer Flash überm Overlay.
static func thunder(runner: EventRunner) -> void:
	runner._sfx("gvz_boom")
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	runner._ui_layer().add_child(flash)
	var tween := runner.create_tween()
	tween.tween_property(flash, "color:a", 0.5, 0.08)
	tween.tween_property(flash, "color:a", 0.0, 0.35)
	tween.tween_callback(flash.queue_free)

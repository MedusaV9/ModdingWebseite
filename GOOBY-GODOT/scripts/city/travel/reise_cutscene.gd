class_name ReiseCutscene
extends Node3D
## Reise-Cutscene (W3a CITY, Doc E §3.2): 5-Shot-Abflug — (1) Gooby kommt
## hinten aus der Haustür, (2) Einfahrt-Dolly + Winken, (3) Taxi fährt mit
## Ease-in vor + Einsteigen, (4) Stadt-Montage, (5) Flughafen + Flugzeug-
## Silhouette hebt ab. Skip ab Sekunde 2; Reduced-Motion = Text-Karten.
## `modus = "rueckkehr"` spielt die gekürzte Abhol-Variante (~12 s).
## KEIN GameState-Zugriff — der Öffner (ReiseApp) hört auf `fertig`.
##
## G4/P16 (ui-reisen MITTEL 11): der Skip-Knopf sitzt bodenzentriert IN der
## Safe-Area (Daumenzone statt Home-Indicator-Ecke), hält den physischen
## Touch-Floor und zieht bei Rotation nach; SquishButton + ui_back.

signal fertig
## Jeder Frame oder der Node-Abbau weckt laufende Shot-Coroutines. Ein
## direktes `await get_tree().process_frame` bliebe nach queue_free am
## globalen SceneTree hängen und hielte den gesamten Shot-Stack am Leben.
signal frame_oder_abbruch

const ASSETS := "res://assets/city"

var ziel_id := ""
var modus := "abflug"

var _cam: Camera3D
var _set: Node3D
var _skip := false
var _layer: CanvasLayer
var _skip_btn: Button
var _beendet := false


func _ready() -> void:
	_baue_buehne()
	_spiele.call_deferred()


func _process(_delta: float) -> void:
	frame_oder_abbruch.emit()


func _exit_tree() -> void:
	_beendet = true
	_skip = true
	# Löst exakt den aktuell wartenden `_warte`-Frame. Danach laufen
	# `_warte` und die umgebenden Shot-Coroutines über ihre Abbruch-Guards aus.
	frame_oder_abbruch.emit()


func skip() -> void:
	_skip = true


func _spiele() -> void:
	if _reduced_motion():
		await _spiele_karten()
	elif modus == "rueckkehr":
		await _spiele_rueckkehr()
	else:
		await _spiele_abflug()
	if _beendet or not is_inside_tree():
		return
	# Erst nach dem vollständigen Rücklauf der Coroutine melden. Der
	# Signal-Handler darf die Cutscene freigeben; direktes emit hier hielt
	# den noch aktiven GDScriptFunctionState am Prozessende fest.
	_fertig_melden.call_deferred()


func _fertig_melden() -> void:
	if not is_inside_tree():
		return
	fertig.emit()


## ---------------------------------------------------------------- Bühne


func _baue_buehne() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.45, 0.68, 0.95)
	mat.sky_horizon_color = Color(0.95, 0.85, 0.72)
	# Boden-Hemisphäre hell halten — sonst steht am Rand der endlichen
	# Bodenplatte ein dunkelgrauer Horizont-Balken (s. city_scene).
	mat.ground_horizon_color = Color(0.93, 0.86, 0.75)
	mat.ground_bottom_color = Color(0.78, 0.74, 0.68)
	sky.sky_material = mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.2
	e.glow_enabled = true
	env.environment = e
	add_child(env)
	var sonne := DirectionalLight3D.new()
	sonne.rotation_degrees = Vector3(-38.0, -40.0, 0.0)
	add_child(sonne)
	_cam = Camera3D.new()
	_cam.current = true
	add_child(_cam)
	_layer = CanvasLayer.new()
	add_child(_layer)
	var skip_btn := SquishButton.new()
	skip_btn.name = "Skip"
	skip_btn.text = I18nService.t("travel.cutscene.skip")
	# Theme explizit setzen: Window-Theme propagiert NICHT durch CanvasLayer.
	skip_btn.theme = ThemeService.theme()
	skip_btn.theme_type_variation = "GhostButton"
	skip_btn.focus_mode = Control.FOCUS_NONE
	skip_btn.visible = false
	skip_btn.pressed.connect(_on_skip_pressed)
	_layer.add_child(skip_btn)
	_skip_btn = skip_btn
	_lege_skip_knopf()
	get_viewport().size_changed.connect(_lege_skip_knopf)
	# Skip ab Sekunde 2 (Doc E §3.2). Gebundenes Methoden-Callable statt
	# Lambda (B2). Ein node-gebundener Tween stirbt mit der Cutscene; ein
	# SceneTreeTimer lebte nach frühem Skip weiter und erschien als Leak.
	var skip_freigabe := create_tween()
	skip_freigabe.tween_interval(2.0)
	skip_freigabe.tween_callback(skip_btn.set_visible.bind(true))


## G4/P16: Skip bodenzentriert in der Safe-Area (Daumenzone) + Touch-Floor;
## Rotation ruft erneut (size_changed).
func _lege_skip_knopf() -> void:
	if _skip_btn == null:
		return
	var m := ScreenShell.metrics(get_viewport())
	var f: float = m["f"]
	var insets: Dictionary = m["insets"]
	_skip_btn.custom_minimum_size = Vector2(0.0, roundf(44.0 * f))
	ScreenShell.touch_target(_skip_btn, m)
	# anchors+offsets mit MINSIZE-Margin: position-Mathe landet am Rand
	# abgeschnitten, weil der Rect beim _ready noch nicht gelegt ist.
	_skip_btn.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 0
	)
	_skip_btn.offset_bottom = -(float(insets["bottom"]) + 16.0 * f)
	_skip_btn.offset_top = _skip_btn.offset_bottom - _skip_btn.custom_minimum_size.y
	# Min-Größe wächst nach dem Theme-Font-Laden noch — zentriert bleiben.
	_skip_btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_skip_btn.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _on_skip_pressed() -> void:
	# Abbrechen/Überspringen klingt als Zurück (Grammatik: ui_back).
	AudioDirector.try_play(self, "ui_back")
	skip()


func _neues_set() -> void:
	if _set != null:
		_set.queue_free()
	_set = Node3D.new()
	add_child(_set)


func _glb(pfad: String, groesse: float, pos: Vector3, rot_grad := 0.0) -> Node3D:
	if not ResourceLoader.exists(pfad):
		return null
	var szene: PackedScene = load(pfad)
	var node: Node3D = szene.instantiate()
	node.scale = Vector3.ONE * groesse
	node.position = pos
	node.rotation_degrees.y = rot_grad
	_set.add_child(node)
	return node


func _boden(farbe: Color) -> void:
	var boden := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(120.0, 120.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = farbe
	mesh.material = mat
	boden.mesh = mesh
	_set.add_child(boden)


func _gooby(pos: Vector3, clip: String) -> GoobyRig:
	var rig := GoobyRig.new()
	rig.position = pos
	_set.add_child(rig)
	rig.play_clip(clip)
	return rig


func _warte(sekunden: float) -> void:
	var rest := sekunden
	while rest > 0.0 and not _skip and not _beendet:
		await frame_oder_abbruch
		if _beendet or not is_inside_tree():
			return
		rest -= get_process_delta_time()


## ---------------------------------------------------------------- Shots


func _spiele_abflug() -> void:
	# Shot 1 (4 s): Flur/Hintertür — Gooby zieht los (Koffer-Gag = Hop).
	_neues_set()
	_boden(Color(0.62, 0.75, 0.5))
	_glb("%s/gebaeude/building-d.glb" % ASSETS, 8.0, Vector3(0, 0, -6), 180.0)
	var gooby := _gooby(Vector3(0.0, 0.0, -2.0), "walk")
	_cam.position = Vector3(4.0, 2.2, 4.0)
	_cam.look_at(Vector3(0, 1, -2))
	var tween := create_tween()
	tween.tween_property(gooby, "position", Vector3(0.0, 0.0, 2.0), 3.2)
	await _warte(3.4)
	if not _skip:
		gooby.play_clip("hop")
		await _warte(0.8)

	# Shot 2 (3 s): Einfahrt — Kamera-Dolly seitlich, Gooby winkt ins Bild.
	if not _skip:
		gooby.play_clip("wave")
		var dolly := create_tween()
		dolly.tween_property(_cam, "position", Vector3(-4.0, 2.0, 5.0), 2.8)
		await _warte(3.0)

	# Shot 3 (6 s): Bordstein — Taxi fährt mit Ease-in vor, Gooby steigt ein.
	# Boden ist hier FLACH (keine 0,4-m-Straßenplatten) → Taxi auf y=0;
	# Nahaufnahme: Scale 1.2 statt CAR_SCALE, sonst wirkt Gooby winzig.
	if not _skip:
		_neues_set()
		_boden(Color(0.55, 0.58, 0.55))
		gooby = _gooby(Vector3(2.0, 0.0, 1.5), "idle")
		var taxi := _glb("%s/autos/taxi.glb" % ASSETS, 1.2, Vector3(-30.0, 0.0, 0.0), 90.0)
		_cam.position = Vector3(6.0, 2.4, 6.0)
		_cam.look_at(Vector3(0, 0.8, 0))
		if taxi != null:
			var anfahrt := create_tween()
			anfahrt.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			anfahrt.tween_property(taxi, "position:x", 0.0, 2.6)
		await _warte(2.8)
		if not _skip:
			var einstieg := create_tween()
			einstieg.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			einstieg.tween_property(gooby, "position", Vector3(0.3, 0.2, 0.6), 1.4)
			einstieg.tween_callback(func() -> void: gooby.visible = false)
			await _warte(2.6)

	# Shot 4 (4 s): Stadt-Montage — Taxi auf der Avenue, Kran-Kamera.
	if not _skip:
		_neues_set()
		_boden(Color(0.5, 0.65, 0.42))
		for i in 7:
			_glb("%s/strassen/road-straight.glb" % ASSETS, 20.0, Vector3(-60.0 + i * 20.0, 0, 0))
		_glb("%s/gebaeude/building-a.glb" % ASSETS, 10.0, Vector3(-20.0, 0.0, -16.0))
		_glb("%s/gebaeude/building-f.glb" % ASSETS, 10.0, Vector3(10.0, 0.0, -18.0), 15.0)
		var montage_taxi := _glb(
			"%s/autos/taxi.glb" % ASSETS, CityCarFeel.CAR_SCALE, Vector3(-40.0, 0.4, 2.5), 90.0
		)
		_cam.position = Vector3(0.0, 16.0, 22.0)
		_cam.look_at(Vector3(0, 0, 0))
		if montage_taxi != null:
			var fahrt := create_tween()
			fahrt.tween_property(montage_taxi, "position:x", 40.0, 3.8)
		await _warte(4.0)

	# Shot 5 (6 s): Flughafen — Vorfahrt, Flugzeug-Silhouette hebt ab.
	if not _skip:
		_neues_set()
		_boden(Color(0.72, 0.72, 0.74))
		_glb("%s/gebaeude/low-detail-building-a.glb" % ASSETS, 12.0, Vector3(0, 0.0, -14.0))
		var flieger := _flugzeug()
		_cam.position = Vector3(0.0, 2.0, 16.0)
		_cam.look_at(Vector3(0, 4, -10))
		var abheben := create_tween().set_parallel()
		abheben.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		abheben.tween_property(flieger, "position", Vector3(30.0, 22.0, -30.0), 4.5)
		abheben.tween_property(_cam, "rotation_degrees:x", 18.0, 4.5)
		await _warte(5.5)


func _spiele_rueckkehr() -> void:
	# Gekürzt rückwärts (~12 s): Flugzeug landet → Gooby kommt mit Tüte →
	# Wiedersehens-Hüpfer.
	_neues_set()
	_boden(Color(0.72, 0.72, 0.74))
	_glb("%s/gebaeude/low-detail-building-a.glb" % ASSETS, 12.0, Vector3(0, 0.0, -14.0))
	var flieger := _flugzeug()
	flieger.position = Vector3(30.0, 22.0, -30.0)
	_cam.position = Vector3(0.0, 2.4, 16.0)
	_cam.look_at(Vector3(0, 3, -10))
	var landung := create_tween()
	landung.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	landung.tween_property(flieger, "position", Vector3(-6.0, 1.0, -18.0), 3.5)
	await _warte(4.0)
	if not _skip:
		var gooby := _gooby(Vector3(-4.0, 0.0, -6.0), "walk")
		var lauf := create_tween()
		lauf.tween_property(gooby, "position", Vector3(0.0, 0.0, 6.0), 3.5)
		await _warte(3.7)
		if not _skip:
			gooby.play_clip("celebrate")
			gooby.set_emotion("ecstatic")
			await _warte(3.0)


## Reduced-Motion (Doc E §3.2): statische Text-Karten statt Kamerafahrten.
func _spiele_karten() -> void:
	var karten: Array[String] = (
		[
			I18nService.t("travel.cutscene.karte_1"),
			I18nService.t("travel.cutscene.karte_2"),
			I18nService.t("travel.cutscene.karte_3"),
			I18nService.t("travel.cutscene.karte_4"),
			I18nService.t("travel.cutscene.karte_5"),
		]
		if modus == "abflug"
		else [I18nService.t("travel.cutscene.karte_rueckkehr")]
	)
	var hintergrund := ColorRect.new()
	hintergrund.color = Color(1.0, 0.96, 0.92)
	hintergrund.theme = ThemeService.theme()
	hintergrund.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(hintergrund)
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.theme_type_variation = "HeadlineLabel"
	label.modulate = Color(0.29, 0.23, 0.21)
	hintergrund.add_child(label)
	for karte in karten:
		if _skip:
			break
		label.text = karte
		await _warte(1.6)


## Low-Poly-Flugzeug-Silhouette aus Primitiven (kein Asset im Kit).
func _flugzeug() -> Node3D:
	var flieger := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.28, 0.34)
	var rumpf := MeshInstance3D.new()
	var rm := CapsuleMesh.new()
	rm.radius = 0.8
	rm.height = 7.0
	rm.material = mat
	rumpf.mesh = rm
	rumpf.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	flieger.add_child(rumpf)
	var fluegel := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(9.0, 0.2, 1.6)
	fm.material = mat
	fluegel.mesh = fm
	flieger.add_child(fluegel)
	var heck := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.2, 1.8, 1.2)
	hm.material = mat
	heck.mesh = hm
	heck.position = Vector3(0.0, 0.9, 3.0)
	flieger.add_child(heck)
	flieger.position = Vector3(-8.0, 1.0, -18.0)
	flieger.rotation_degrees.y = -35.0
	_set.add_child(flieger)
	return flieger


func _reduced_motion() -> bool:
	var settings := get_node_or_null("/root/AppSettings")
	return settings != null and settings.is_reduced_motion()

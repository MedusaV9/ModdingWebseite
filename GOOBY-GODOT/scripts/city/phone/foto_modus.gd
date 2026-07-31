class_name FotoModus
extends CanvasLayer
## Fotomodus (USER §E61, Gate = Kamera aus dem POW!): legt einen Sucher über
## die LAUFENDE Szene (Stadt, Ort, Wohnzimmer — egal welche) und knipst den
## Viewport in eine PNG unter `user://fotos/`. Der Pfad landet additiv im
## city-Slice (`fotos[]`), damit Album/Postkarten später drauf zugreifen
## können.
##
## Mobil-tauglich: kein zweiter Viewport, kein Render-Target — der Sucher ist
## reine 2D-Deko und beim Auslösen wird EIN Frame lang ausgeblendet, damit die
## Aufnahme sauber bleibt.
##
## W13C FOTOWERK (P1 Punkt 16, Web-Parität photoMode.js): drei Werkzeug-Reihen
## im Sucher — POSE (vorhandene Rig-Clips), EMOTION (die 12 W12-FeelEmotions,
## über die öffentliche Rig-Override-API GEHALTEN) und RAHMEN (FotoRahmen,
## prozedural). Der Rahmen liegt als eigenes Overlay UNTER der Bedien-UI und
## bleibt beim Auslösen sichtbar — er wird also mitgeknipst. Pose/Emotion gibt
## es nur, wenn ein Gooby im Bild-Kontext steht (Haus/Ranch/Orte); Rahmen
## immer. Dazu SELFIE-Modus (C §3.9 „Snap A Gooby!“): eigene Kamera dreht auf
## Gooby, prozeduraler Arm mit IGohbie im Bild-Eck, phone_up-Pose mit
## wave-Fallback. Zeit ist injizierbar (`uhr_unix_s`).

signal geknipst(pfad: String)
signal geschlossen

const FOTO_DIR := "user://fotos"
## Ältere Aufnahmen fliegen aus dem Save-Index (die Dateien bleiben liegen).
const MAX_FOTOS := 40
## Selfie-Kamera: Armlänge vor dem Gooby, Kopfhöhe, weiter FOV.
const SELFIE_ABSTAND_M := 1.15
const SELFIE_KOPF_HOEHE_M := 0.92
const SELFIE_FOV_GRAD := 70.0

var gs: Object
## W13C: Werkzeug-Zustand (pur, testbar) + injizierbare Uhr (Unix-Sekunden).
var werkzeuge := FotoWerkzeuge.new()
var uhr_unix_s: Callable = Callable()
## Tests: Rig-Double statt Szenen-Suche (Duck-Typing genügt).
var rig_override: Object = null

var _ui: Control
var _blitz: ColorRect
var _hinweis: Label
var _rahmen_overlay: FotoRahmen.Overlay
var _werkzeug_box: VBoxContainer
var _werkzeug_chips: Dictionary = {}
var _selfie_button: Button
var _rig_cache: Object = null
var _pose_angefasst := false
var _emotion_angefasst := false
var _selfie_aktiv := false
var _selfie_wurzel: Node3D = null
var _vorherige_kamera: Camera3D = null


## Gate: ohne Kamera aus dem POW! gibt es keinen Fotomodus.
static func ist_frei(game_state: Object) -> bool:
	return PowAngebote.hat_kamera(game_state)


## Zielpfad einer Aufnahme (deterministisch aus dem Zeitstempel).
static func foto_pfad(unix_s: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(unix_s)
	return (
		"%s/foto_%04d%02d%02d_%02d%02d%02d.png"
		% [
			FOTO_DIR,
			int(d["year"]),
			int(d["month"]),
			int(d["day"]),
			int(d["hour"]),
			int(d["minute"]),
			int(d["second"]),
		]
	)


## Aufnahme im city-Slice vermerken (additiv, jüngste zuerst, gedeckelt).
## `ort` ist optional (REST-4-Galerie: Aufnahmeort, z. B. "funkelpark").
## `extra` (W13C) mischt zusätzliche Metadaten in den Eintrag — z. B.
## {pose, emotion, rahmen, selfie} aus den Foto-Werkzeugen.
static func merke_foto(
	game_state: Object, pfad: String, at_ms: int, ort := "", extra: Dictionary = {}
) -> Array:
	if game_state == null or pfad.is_empty():
		return []
	# Lambda-Captures sind by-value: das Ergebnis wird ins geteilte Array
	# MUTIERT (append_array), ein `neu = liste`-Rebind käme nie außen an.
	var neu: Array = []
	game_state.update(
		func(state: Dictionary) -> void:
			var city: Dictionary = state.get(CityState.SLICE_ID, {})
			var liste: Array = city.get("fotos", [])
			var eintrag := {"pfad": pfad, "at": at_ms}
			if not ort.is_empty():
				eintrag["ort"] = ort
			for key: String in extra:
				eintrag[key] = extra[key]
			liste.push_front(eintrag)
			while liste.size() > MAX_FOTOS:
				liste.pop_back()
			city["fotos"] = liste
			state[CityState.SLICE_ID] = city
			neu.append_array(liste)
	)
	game_state.notify_slice_changed(CityState.SLICE_ID)
	return neu


static func fotos(game_state: Object) -> Array:
	if game_state == null:
		return []
	var raw: Variant = game_state.get_value("city.fotos", [])
	return raw if raw is Array else []


## Fotomodus über der laufenden Szene öffnen (eigener CanvasLayer).
static func oeffne(host: Node, game_state: Object) -> FotoModus:
	var modus := FotoModus.new()
	modus.name = "FotoModus"
	modus.gs = game_state
	host.add_child(modus)
	return modus


func _ready() -> void:
	layer = 40
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOTO_DIR))
	# Rahmen-Overlay UNTER der Bedien-UI: bleibt beim Auslösen sichtbar,
	# damit der gewählte Rahmen in der Aufnahme landet.
	_rahmen_overlay = FotoRahmen.Overlay.new()
	_rahmen_overlay.name = "RahmenOverlay"
	add_child(_rahmen_overlay)
	_baue_ui()
	_aktualisiere_rahmen()


func _exit_tree() -> void:
	# Sicherheitsnetz: Kamera/Arm und Gooby-Zustand nie „hängen lassen“,
	# auch wenn der Modus von außen gefreed wird.
	if _selfie_aktiv:
		_selfie_aus()
	_stelle_gooby_zurueck()


## Auslösen: Bedien-UI aus (der Rahmen bleibt!), EIN Frame warten,
## Viewport sichern, UI wieder an. Werkzeug-Zustand wandert als Metadaten
## mit in den Album-Eintrag.
func knipsen() -> String:
	_aktualisiere_rahmen()
	_ui.visible = false
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var bild := get_viewport().get_texture().get_image()
	_ui.visible = true
	var pfad := FotoModus.foto_pfad(_jetzt_unix())
	if bild == null or bild.save_png(pfad) != OK:
		_hinweis.text = I18nService.t("phone.foto.fehler")
		return ""
	var extra := werkzeuge.als_meta()
	if _selfie_aktiv:
		extra["selfie"] = true
	FotoModus.merke_foto(gs, pfad, _jetzt_unix() * 1000, _aktueller_ort(), extra)
	_hinweis.text = I18nService.t("phone.foto.gespeichert").format(
		{"n": FotoModus.fotos(gs).size()}
	)
	_blitze()
	geknipst.emit(pfad)
	return pfad


func schliessen() -> void:
	if _selfie_aktiv:
		_selfie_aus()
	_stelle_gooby_zurueck()
	geschlossen.emit()
	queue_free()


func ist_selfie() -> bool:
	return _selfie_aktiv


## Aufnahmeort für die Galerie (REST-4): ort_id der aktuellen Router-Szene
## (OrtScene/Funkelpark tragen eine), sonst "" (Galerie zeigt "Unterwegs").
func _aktueller_ort() -> String:
	var router := get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("get_current_scene"):
		return ""
	var scene: Node = router.get_current_scene()
	if scene == null:
		return ""
	var ort: Variant = scene.get("ort_id")
	return str(ort) if ort is String else ""


func _jetzt_unix() -> int:
	if uhr_unix_s.is_valid():
		return int(uhr_unix_s.call())
	return int(Time.get_unix_time_from_system())


# ---------------------------------------------------------------- Werkzeuge


## Gooby im Bild-Kontext? Erst Router-Szene, dann der Host-Ast (Tests).
func _finde_rig() -> Object:
	if rig_override != null and is_instance_valid(rig_override):
		return rig_override
	if _rig_cache != null and is_instance_valid(_rig_cache):
		return _rig_cache
	var wurzel: Node = null
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("get_current_scene"):
		wurzel = router.get_current_scene()
	if wurzel == null:
		wurzel = get_parent()
	if wurzel == null:
		return null
	var treffer := wurzel.find_children("*", "GoobyRig", true, false)
	_rig_cache = treffer[0] if not treffer.is_empty() else null
	return _rig_cache


func _wende_pose_an() -> void:
	var rig := _finde_rig()
	if rig == null or not rig.has_method("play_clip"):
		return
	if werkzeuge.pose_id == FotoWerkzeuge.POSE_FREI:
		if _pose_angefasst:
			rig.play_clip("idle")
			_pose_angefasst = false
		return
	var clips: Array = rig.clip_names() if rig.has_method("clip_names") else []
	rig.play_clip(FotoWerkzeuge.pose_clip(werkzeuge.pose_id, clips))
	_pose_angefasst = true


## Emotion HALTEN: Override-API des Rigs (kein Timer wie GoobyFeelings) —
## der Ausdruck steht, bis der Spieler wechselt oder den Modus schließt.
func _wende_emotion_an() -> void:
	var rig := _finde_rig()
	if rig == null:
		return
	if werkzeuge.emotion_id == FotoWerkzeuge.EMOTION_KEINE:
		if _emotion_angefasst and rig.has_method("clear_expression_override"):
			rig.clear_expression_override()
		_emotion_angefasst = false
		return
	var def := FeelEmotions.def_of(werkzeuge.emotion_id)
	if def.is_empty() or not rig.has_method("set_expression_override"):
		return
	rig.set_expression_override(def["gesicht"], def["pose"])
	_emotion_angefasst = true


func _stelle_gooby_zurueck() -> void:
	var rig := _finde_rig()
	if rig == null:
		return
	if _emotion_angefasst and rig.has_method("clear_expression_override"):
		rig.clear_expression_override()
	if _pose_angefasst and rig.has_method("play_clip"):
		rig.play_clip("idle")
	_emotion_angefasst = false
	_pose_angefasst = false


func _aktualisiere_rahmen() -> void:
	if _rahmen_overlay == null:
		return
	_rahmen_overlay.kontext = _rahmen_kontext()
	_rahmen_overlay.rahmen_id = werkzeuge.rahmen_id


## Kontext für die Rahmen-Painter: lokalisiertes Datum (Polaroid/Stempel),
## „Grüße aus …“ mit aufgelöstem Ortsnamen (Postkarte), Stempel-Text.
func _rahmen_kontext() -> Dictionary:
	var ort_id := _aktueller_ort()
	var gruss := I18nService.t("foto.rahmen.postkarte_unterwegs")
	if not ort_id.is_empty():
		gruss = I18nService.t("foto.rahmen.postkarte_gruss", {"ort": GalerieLogic.ort_name(ort_id)})
	return {
		"datum": GalerieLogic.datum(_jetzt_unix() * 1000),
		"gruss": gruss,
		"stempel": I18nService.t("foto.rahmen.stempel_text"),
		"seed": FotoRahmen.STREU_SEED,
	}


func _on_chip(art: String, id: String) -> void:
	match art:
		"pose":
			werkzeuge.waehle_pose(id)
			_wende_pose_an()
		"emotion":
			werkzeuge.waehle_emotion(id)
			_wende_emotion_an()
		"rahmen":
			werkzeuge.waehle_rahmen(id)
			_aktualisiere_rahmen()
	_style_chips(art)


func _aktive_id(art: String) -> String:
	match art:
		"pose":
			return werkzeuge.pose_id
		"emotion":
			return werkzeuge.emotion_id
		_:
			return werkzeuge.rahmen_id


func _style_chips(art: String) -> void:
	var chips: HBoxContainer = _werkzeug_chips.get(art)
	if chips == null:
		return
	var aktiv := _aktive_id(art)
	for kind in chips.get_children():
		if kind is Button:
			var chip := kind as Button
			var chip_id := str(chip.get_meta("werkzeug_id", ""))
			chip.theme_type_variation = "BtnTeal" if chip_id == aktiv else "GhostButton"


# ---------------------------------------------------------------- Selfie


func _schalte_selfie(an: bool) -> void:
	if an == _selfie_aktiv:
		return
	if an:
		_selfie_ein()
	else:
		_selfie_aus()
	if _selfie_button != null:
		_selfie_button.text = I18nService.t(
			"foto.selfie.aus" if _selfie_aktiv else "foto.selfie.an"
		)
		_selfie_button.set_pressed_no_signal(_selfie_aktiv)


## First-Person-Selfie: eigene Kamera auf Armlänge VOR dem Gooby (blickt ihn
## an), prozeduraler Arm (IGohbie-Quad + Pfote) klebt im Bild-Eck an der
## Kamera. Gooby hebt das Handy: phone_up-Clip, wave-Fallback (das gleiche
## Muster wie die Battleship-Tomate).
func _selfie_ein() -> void:
	var rig := _finde_rig()
	if not (rig is Node3D):
		return
	var rig3d := rig as Node3D
	_vorherige_kamera = get_viewport().get_camera_3d()
	_selfie_wurzel = Node3D.new()
	_selfie_wurzel.name = "SelfieRig"
	get_tree().root.add_child(_selfie_wurzel)
	var kamera := Camera3D.new()
	kamera.name = "SelfieKamera"
	kamera.fov = SELFIE_FOV_GRAD
	_selfie_wurzel.add_child(kamera)
	var kopf := rig3d.global_position + Vector3(0.0, SELFIE_KOPF_HOEHE_M, 0.0)
	var vorn := rig3d.global_transform.basis * Vector3(0.0, 0.0, 1.0)
	vorn.y = 0.0
	if vorn.length_squared() < 0.001:
		vorn = Vector3(0.0, 0.0, 1.0)
	kamera.global_position = kopf + vorn.normalized() * SELFIE_ABSTAND_M + Vector3(0.0, 0.08, 0.0)
	kamera.look_at(kopf, Vector3.UP)
	kamera.make_current()
	_baue_selfie_arm(kamera)
	if rig.has_method("play_clip"):
		var clips: Array = rig.clip_names() if rig.has_method("clip_names") else []
		rig.play_clip(FotoWerkzeuge.selfie_clip(clips))
		_pose_angefasst = true
	_selfie_aktiv = true


func _selfie_aus() -> void:
	_selfie_aktiv = false
	if _vorherige_kamera != null and is_instance_valid(_vorherige_kamera):
		_vorherige_kamera.make_current()
	_vorherige_kamera = null
	if _selfie_wurzel != null and is_instance_valid(_selfie_wurzel):
		_selfie_wurzel.queue_free()
	_selfie_wurzel = null
	_wende_pose_an()


func _baue_selfie_arm(kamera: Camera3D) -> void:
	var arm := Node3D.new()
	arm.name = "SelfieArm"
	kamera.add_child(arm)
	arm.position = Vector3(0.3, -0.26, -0.55)
	arm.rotation_degrees = Vector3(8.0, -14.0, 6.0)
	var geraet := MeshInstance3D.new()
	var korpus := BoxMesh.new()
	korpus.size = Vector3(0.13, 0.26, 0.018)
	geraet.mesh = korpus
	geraet.material_override = _selfie_material(Color(0.16, 0.12, 0.22))
	arm.add_child(geraet)
	var schirm := MeshInstance3D.new()
	var glas := BoxMesh.new()
	glas.size = Vector3(0.11, 0.22, 0.004)
	schirm.mesh = glas
	schirm.position = Vector3(0.0, 0.01, 0.012)
	schirm.material_override = _selfie_material(Color(0.85, 0.93, 1.0))
	arm.add_child(schirm)
	var pfote := MeshInstance3D.new()
	var ballen := SphereMesh.new()
	ballen.radius = 0.055
	ballen.height = 0.11
	pfote.mesh = ballen
	pfote.position = Vector3(0.0, -0.16, 0.02)
	pfote.material_override = _selfie_material(Color(0.96, 0.87, 0.72))
	arm.add_child(pfote)


func _selfie_material(farbe: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = farbe
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


## ---------------------------------------------------------------- Aufbau


func _baue_ui() -> void:
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.theme = ThemeService.theme()
	add_child(_ui)
	_baue_sucher()
	_hinweis = Label.new()
	_hinweis.text = I18nService.t("phone.foto.hinweis")
	_hinweis.theme_type_variation = "CaptionLabel"
	_hinweis.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hinweis.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 28
	)
	_ui.add_child(_hinweis)
	var ausloeser := Button.new()
	ausloeser.name = "Ausloeser"
	ausloeser.theme_type_variation = "PrimaryButton"
	ausloeser.text = I18nService.t("phone.foto.knipsen")
	ausloeser.custom_minimum_size = Vector2(180.0, 64.0)
	ausloeser.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 36
	)
	ausloeser.pressed.connect(func() -> void: knipsen())
	_ui.add_child(ausloeser)
	var zurueck := Button.new()
	zurueck.theme_type_variation = "GhostButton"
	zurueck.text = I18nService.t("phone.foto.fertig")
	zurueck.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 20)
	zurueck.pressed.connect(schliessen)
	_ui.add_child(zurueck)
	_baue_werkzeuge()
	_blitz = ColorRect.new()
	_blitz.color = Color(1.0, 1.0, 1.0, 0.0)
	_blitz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blitz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_blitz)


## W13C: Werkzeug-Reihen über dem Auslöser. Pose/Emotion nur mit Gooby im
## Bild (Haus/Ranch/Orte), Rahmen immer; dazu der Selfie-Umschalter.
func _baue_werkzeuge() -> void:
	_werkzeug_box = VBoxContainer.new()
	_werkzeug_box.name = "Werkzeuge"
	_werkzeug_box.add_theme_constant_override("separation", 6)
	_werkzeug_box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_werkzeug_box.offset_left = 16.0
	_werkzeug_box.offset_right = -16.0
	_werkzeug_box.offset_top = -320.0
	_werkzeug_box.offset_bottom = -116.0
	_werkzeug_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_werkzeug_box.alignment = BoxContainer.ALIGNMENT_END
	_ui.add_child(_werkzeug_box)
	var hat_gooby := _finde_rig() != null
	if hat_gooby:
		var posen: Array = []
		for id in FotoWerkzeuge.pose_ids():
			posen.append([id, I18nService.t(FotoWerkzeuge.pose_label_key(id))])
		_baue_werkzeug_reihe("pose", I18nService.t("foto.werkzeug.pose"), posen)
		var emotionen: Array = []
		for id in FotoWerkzeuge.emotion_ids():
			emotionen.append([id, I18nService.t(FotoWerkzeuge.emotion_label_key(id))])
		_baue_werkzeug_reihe("emotion", I18nService.t("foto.werkzeug.emotion"), emotionen)
	var rahmen: Array = []
	for id in FotoRahmen.ids():
		rahmen.append([id, I18nService.t(FotoRahmen.label_key(id))])
	_baue_werkzeug_reihe("rahmen", I18nService.t("foto.werkzeug.rahmen"), rahmen)
	if hat_gooby:
		_selfie_button = Button.new()
		_selfie_button.name = "SelfieButton"
		_selfie_button.theme_type_variation = "GhostButton"
		_selfie_button.toggle_mode = true
		_selfie_button.text = I18nService.t("foto.selfie.an")
		_selfie_button.set_anchors_and_offsets_preset(
			Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 20
		)
		_selfie_button.toggled.connect(_schalte_selfie)
		_ui.add_child(_selfie_button)


## Eine Werkzeug-Reihe: Titel links, Auswahl-Chips in einem H-Scroller.
## `eintraege` = [[id, text], …].
func _baue_werkzeug_reihe(art: String, titel: String, eintraege: Array) -> void:
	var reihe := HBoxContainer.new()
	reihe.name = "Reihe" + art.to_pascal_case()
	reihe.add_theme_constant_override("separation", 8)
	_werkzeug_box.add_child(reihe)
	var label := Label.new()
	label.theme_type_variation = "CaptionLabel"
	label.text = titel
	label.custom_minimum_size = Vector2(86.0, 0.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reihe.add_child(label)
	var scroller := ScrollContainer.new()
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroller.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.custom_minimum_size = Vector2(0.0, 54.0)
	reihe.add_child(scroller)
	var chips := HBoxContainer.new()
	chips.name = "Chips"
	chips.add_theme_constant_override("separation", 6)
	scroller.add_child(chips)
	var aktiv := _aktive_id(art)
	for eintrag: Array in eintraege:
		var id := str(eintrag[0])
		var chip := Button.new()
		chip.name = "Chip" + id.to_pascal_case()
		chip.theme_type_variation = "BtnTeal" if id == aktiv else "GhostButton"
		chip.text = str(eintrag[1])
		chip.focus_mode = Control.FOCUS_NONE
		chip.custom_minimum_size = Vector2(0.0, 44.0)
		chip.set_meta("werkzeug_id", id)
		chip.pressed.connect(_on_chip.bind(art, id))
		chips.add_child(chip)
	_werkzeug_chips[art] = chips


## Vier Ecken-Winkel als Sucher (billige ColorRects statt Shader).
func _baue_sucher() -> void:
	var farbe := AcTokens.WHITE
	for ecke: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		for waagerecht: bool in [true, false]:
			var strich := ColorRect.new()
			strich.color = Color(farbe.r, farbe.g, farbe.b, 0.85)
			strich.mouse_filter = Control.MOUSE_FILTER_IGNORE
			strich.size = Vector2(72.0, 6.0) if waagerecht else Vector2(6.0, 72.0)
			strich.anchor_left = ecke.x
			strich.anchor_right = ecke.x
			strich.anchor_top = ecke.y
			strich.anchor_bottom = ecke.y
			var rand := 64.0
			var dx := rand if ecke.x < 0.5 else -rand - strich.size.x
			var dy := rand if ecke.y < 0.5 else -rand - strich.size.y
			strich.offset_left = dx
			strich.offset_top = dy
			strich.offset_right = dx + strich.size.x
			strich.offset_bottom = dy + strich.size.y
			_ui.add_child(strich)


func _blitze() -> void:
	if ThemeService.is_reduced_motion(_ui):
		return
	_blitz.color = Color(1.0, 1.0, 1.0, 0.75)
	var tween := create_tween()
	tween.tween_property(_blitz, "color", Color(1.0, 1.0, 1.0, 0.0), 0.35)

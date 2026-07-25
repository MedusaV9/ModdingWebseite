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

signal geknipst(pfad: String)
signal geschlossen

const FOTO_DIR := "user://fotos"
## Ältere Aufnahmen fliegen aus dem Save-Index (die Dateien bleiben liegen).
const MAX_FOTOS := 40

var gs: Object

var _ui: Control
var _blitz: ColorRect
var _hinweis: Label


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
static func merke_foto(game_state: Object, pfad: String, at_ms: int) -> Array:
	if game_state == null or pfad.is_empty():
		return []
	var neu: Array = []
	game_state.update(
		func(state: Dictionary) -> void:
			var city: Dictionary = state.get(CityState.SLICE_ID, {})
			var liste: Array = city.get("fotos", [])
			liste.push_front({"pfad": pfad, "at": at_ms})
			while liste.size() > MAX_FOTOS:
				liste.pop_back()
			city["fotos"] = liste
			neu = liste
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
	_baue_ui()


## Auslösen: Sucher aus, EIN Frame warten, Viewport sichern, Sucher an.
func knipsen() -> String:
	_ui.visible = false
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var bild := get_viewport().get_texture().get_image()
	_ui.visible = true
	var pfad := FotoModus.foto_pfad(int(Time.get_unix_time_from_system()))
	if bild.save_png(pfad) != OK:
		_hinweis.text = I18nService.t("phone.foto.fehler")
		return ""
	FotoModus.merke_foto(gs, pfad, int(Time.get_unix_time_from_system() * 1000.0))
	_hinweis.text = I18nService.t("phone.foto.gespeichert").format(
		{"n": FotoModus.fotos(gs).size()}
	)
	_blitze()
	geknipst.emit(pfad)
	return pfad


func schliessen() -> void:
	geschlossen.emit()
	queue_free()


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
	_blitz = ColorRect.new()
	_blitz.color = Color(1.0, 1.0, 1.0, 0.0)
	_blitz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blitz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_blitz)


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

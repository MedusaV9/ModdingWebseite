class_name CodesScreen
extends Control
## Offline-Codes-Screen (REST-4, EVAL Rang 11) — Web-Vorbild
## GOOBY/src/ui/codesScreen.js: Eingabefeld für Aktionscodes, Prüfung über
## die pure CodesEngine (Katalog data/codes.js verbatim), Einlöse-Feier
## (Konfetti + Stinger + Toast), Verlauf bereits eingelöster Codes und
## klare deutsche Fehlermeldungen (leer/unbekannt/schon/gesperrt).
##
## Effekte wendet DIESER Aufrufer im selben gs.update an (§B6):
## Münzen über Economy.award(reason "code"), Buff über
## codes.buffs.doubleCoinsUntil, Sticker über den RewardHub (Cond-Typ
## "code" liest codes.redeemed). Erreichbar über die Route `codes`
## (Settings → Spiel → "Aktionscodes einlösen").

signal ready_for_reveal

const Economy := preload("res://scripts/logic/economy.gd")

const ROUTE := &"codes"
const ROUTES := {ROUTE: "res://scripts/ui/codes/codes_screen.tscn"}

## Tests/Screenshots: GameState-Double statt /root/GameState.
var gs_override: Object = null
## Tests: fixe Uhr (0 = clock/Systemzeit).
var now_override := 0
## Tests: Navigation abschaltbar.
var auto_navigate := true
## Session-Fenster der Fehlversuche (CodesEngine-Kontrakt).
var attempts: Array = []

var _gs: Object = null
var _input: LineEdit
var _redeem_btn: Button
var _feedback: Label
var _buff_label: Label
var _verlauf_box: VBoxContainer
var _toasts: ToastLayer
var _rows: VBoxContainer
var _m: Dictionary = {}
var _lock_anzeige := false


static func register_routes() -> void:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return
	var router := (loop as SceneTree).root.get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("register_routes"):
		router.register_routes(ROUTES)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	register_routes()
	_gs = gs_override if gs_override != null else get_node_or_null("/root/GameState")
	_build_ui()
	_apply_metrics()
	get_viewport().size_changed.connect(_apply_metrics)
	set_process(false)
	ready_for_reveal.emit()


## ---------------------------------------------------------------- Test-API


func set_input_text(text: String) -> void:
	_input.text = text


func redeem_now() -> Dictionary:
	return _on_redeem_pressed()


func feedback_text() -> String:
	return _feedback.text


## ---------------------------------------------------------------- Aufbau


func _build_ui() -> void:
	var wallpaper := AcWallpaper.new()
	wallpaper.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(wallpaper)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 12)
	scroll.add_child(_rows)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	_rows.add_child(header)
	var back := SquishButton.new()
	back.name = "Zurueck"
	back.theme_type_variation = &"BtnGhost"
	back.text = I18nService.t("codes.zurueck")
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(_on_back_pressed)
	header.add_child(back)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = I18nService.t("codes.titel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)

	var eingabe_karte := _karte()
	var hinweis := Label.new()
	hinweis.theme_type_variation = &"CaptionLabel"
	hinweis.text = I18nService.t("codes.hinweis")
	hinweis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	eingabe_karte.add_child(hinweis)
	var eingabe_zeile := HBoxContainer.new()
	eingabe_zeile.add_theme_constant_override("separation", 10)
	eingabe_karte.add_child(eingabe_zeile)
	_input = LineEdit.new()
	_input.name = "CodeEingabe"
	_input.placeholder_text = I18nService.t("codes.platzhalter")
	_input.custom_minimum_size = Vector2(0.0, 48.0)
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(func(_text: String) -> void: _on_redeem_pressed())
	eingabe_zeile.add_child(_input)
	_redeem_btn = SquishButton.new()
	_redeem_btn.name = "Einloesen"
	_redeem_btn.theme_type_variation = &"BtnYellow"
	_redeem_btn.text = I18nService.t("codes.einloesen")
	_redeem_btn.custom_minimum_size = Vector2(140.0, 48.0)
	_redeem_btn.focus_mode = Control.FOCUS_NONE
	_redeem_btn.pressed.connect(_on_redeem_pressed)
	eingabe_zeile.add_child(_redeem_btn)
	_feedback = Label.new()
	_feedback.name = "Feedback"
	_feedback.theme_type_variation = &"CaptionLabel"
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.text = ""
	eingabe_karte.add_child(_feedback)

	_buff_label = Label.new()
	_buff_label.name = "BuffChip"
	_buff_label.theme_type_variation = &"SoftLabel"
	_buff_label.visible = false
	_rows.add_child(_buff_label)

	var verlauf_karte := _karte()
	var verlauf_titel := Label.new()
	verlauf_titel.theme_type_variation = &"HeadlineLabel"
	verlauf_titel.text = I18nService.t("codes.verlauf.titel")
	verlauf_karte.add_child(verlauf_titel)
	_verlauf_box = VBoxContainer.new()
	_verlauf_box.name = "Verlauf"
	_verlauf_box.add_theme_constant_override("separation", 4)
	verlauf_karte.add_child(_verlauf_box)

	_toasts = ToastLayer.new()
	add_child(_toasts)
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_refresh_verlauf()
	_refresh_buff()


func _karte() -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"AcCard"
	_rows.add_child(panel)
	var inhalt := VBoxContainer.new()
	inhalt.add_theme_constant_override("separation", 10)
	panel.add_child(inhalt)
	return inhalt


func _apply_metrics() -> void:
	if not is_inside_tree():
		return
	_m = ScreenShell.metrics(get_viewport())
	ScreenShell.frame(_rows, _m, 24.0, 16.0)
	ScreenShell.scale_fonts(self, float(_m["f"]))


## ---------------------------------------------------------------- Einlösen


func _on_redeem_pressed() -> Dictionary:
	var roh := _input.text
	if CodesEngine.normalize(roh).is_empty():
		_zeige_fehler(I18nService.t("codes.fehler.leer"))
		return {"ok": false, "reason": "empty"}
	if _gs == null:
		return {"ok": false, "reason": "no-gs"}
	var now := _now_ms()
	# Box statt lokaler Variable: GDScript-Lambdas fangen Primitive per WERT —
	# eine Zuweisung im Draft käme sonst nie hier draußen an.
	var box := {"result": {}}
	_gs.update(
		func(state: Dictionary) -> void:
			var result := CodesEngine.redeem(state, roh, now, attempts)
			box["result"] = result
			if not bool(result.get("ok", false)):
				return
			var effect: Dictionary = (result["code"] as Dictionary).get("effect", {})
			if effect.has("coins") and state.get("economy") is Dictionary:
				Economy.award(state["economy"], int(effect["coins"]), "code")
			if str(effect.get("buff", "")) == "doubleCoins":
				var codes: Dictionary = state["codes"]
				codes["buffs"]["doubleCoinsUntil"] = (
					now + int(effect.get("minutes", 0)) * 60 * 1000
				)
			_zaehle_counter(state)
	)
	var result: Dictionary = box["result"]
	_gs.notify_slice_changed("codes")
	if bool(result.get("ok", false)):
		_feiere(result["code"])
	else:
		_zeige_reason(str(result.get("reason", "unknown")))
	_refresh_verlauf()
	_refresh_buff()
	return result


func _zaehle_counter(state: Dictionary) -> void:
	if not (state.get("achievements") is Dictionary):
		return
	var ach: Dictionary = state["achievements"]
	if not (ach.get("counters") is Dictionary):
		return
	var counters: Dictionary = ach["counters"]
	counters["codesRedeemed"] = int(_num(counters.get("codesRedeemed"))) + 1


func _feiere(code: Dictionary) -> void:
	_input.text = ""
	var effect: Dictionary = code.get("effect", {})
	var zeilen: Array[String] = [I18nService.t("codes.erfolg.titel")]
	if effect.has("coins"):
		zeilen.append(I18nService.t("codes.erfolg.muenzen", {"n": int(effect["coins"])}))
	if effect.has("sticker"):
		zeilen.append(I18nService.t("codes.erfolg.sticker"))
	if str(effect.get("buff", "")) == "doubleCoins":
		zeilen.append(I18nService.t("codes.erfolg.buff", {"min": int(effect.get("minutes", 0))}))
	_feedback.text = "  ".join(zeilen)
	_feedback.remove_theme_color_override("font_color")
	_toasts.show_toast(I18nService.t("codes.erfolg.titel"))
	_konfetti()
	if is_inside_tree():
		MusicDirector.get_or_create(self).play_stinger("stinger-levelup")
	RewardHub.note_action(_gs)


func _zeige_reason(reason: String) -> void:
	match reason:
		"already":
			_zeige_fehler(I18nService.t("codes.fehler.schon"))
		"locked":
			var s := int(ceil(CodesEngine.lock_remaining_ms(_state(), _now_ms()) / 1000.0))
			_zeige_fehler(I18nService.t("codes.fehler.gesperrt", {"s": maxi(1, s)}))
			set_process(true)
		_:
			_zeige_fehler(I18nService.t("codes.fehler.unbekannt"))
			# Der Fehlversuch kann die Sperre ausgelöst haben — Uhr anwerfen.
			if CodesEngine.lock_remaining_ms(_state(), _now_ms()) > 0:
				set_process(true)


func _zeige_fehler(text: String) -> void:
	_feedback.text = text
	_feedback.add_theme_color_override("font_color", Color("#C0392B"))
	AudioDirector.try_play(self, "ui_error")


## Sperr-Countdown live anzeigen (Prozess läuft nur während der Sperre).
func _process(_delta: float) -> void:
	var rest := CodesEngine.lock_remaining_ms(_state(), _now_ms())
	if rest <= 0:
		_redeem_btn.disabled = false
		set_process(false)
		if _lock_anzeige:
			_feedback.text = ""
			_lock_anzeige = false
		return
	_lock_anzeige = true
	_redeem_btn.disabled = true
	_feedback.text = I18nService.t("codes.fehler.gesperrt", {"s": int(ceil(rest / 1000.0))})


## ---------------------------------------------------------------- Anzeige


func _refresh_verlauf() -> void:
	if _verlauf_box == null:
		return
	for kind in _verlauf_box.get_children():
		_verlauf_box.remove_child(kind)
		kind.queue_free()
	var entries := CodesEngine.redeemed_entries(_state())
	if entries.is_empty():
		var leer := Label.new()
		leer.theme_type_variation = &"CaptionLabel"
		leer.text = I18nService.t("codes.verlauf.leer")
		_verlauf_box.add_child(leer)
		return
	for entry: Dictionary in entries:
		var zeile := Label.new()
		zeile.name = "Verlauf_%s" % str(entry["id"])
		zeile.theme_type_variation = &"CaptionLabel"
		zeile.text = I18nService.t(
			"codes.verlauf.eintrag",
			{"name": _code_name(str(entry["id"])), "datum": _datum(int(entry["at_ms"]))}
		)
		_verlauf_box.add_child(zeile)


func _refresh_buff() -> void:
	if _buff_label == null:
		return
	var rest := CodesEngine.remaining_ms(_state(), _now_ms())
	_buff_label.visible = rest > 0
	if rest > 0:
		_buff_label.text = I18nService.t("codes.buff_aktiv", {"rest": _mmss(rest)})


func _code_name(id: String) -> String:
	var key := "codes.name.%s" % id
	return I18nService.t(key) if I18nService.has_key(key) else id


func _datum(at_ms: int) -> String:
	@warning_ignore("integer_division")
	var d := Time.get_datetime_dict_from_unix_time(at_ms / 1000)
	return "%02d.%02d.%04d" % [int(d["day"]), int(d["month"]), int(d["year"])]


func _mmss(ms: int) -> String:
	var sec := maxi(0, int(ceil(ms / 1000.0)))
	@warning_ignore("integer_division")
	return "%d:%02d" % [sec / 60, sec % 60]


func _konfetti() -> void:
	if ThemeService.is_reduced_motion(self):
		return
	var particles := CPUParticles2D.new()
	particles.position = size / 2.0
	particles.amount = 48
	particles.lifetime = 1.2
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.direction = Vector2(0, -1)
	particles.spread = 70.0
	particles.initial_velocity_min = 260.0
	particles.initial_velocity_max = 520.0
	particles.gravity = Vector2(0, 700)
	particles.scale_amount_min = 3.0
	particles.scale_amount_max = 7.0
	particles.color_ramp = _konfetti_farben()
	add_child(particles)
	particles.emitting = true
	get_tree().create_timer(1.6).timeout.connect(particles.queue_free)


## ---------------------------------------------------------------- Zustand


func _state() -> Dictionary:
	if _gs == null or not _gs.has_method("state"):
		return {}
	return _gs.state()


func _now_ms() -> int:
	if now_override > 0:
		return now_override
	if _gs != null and "clock" in _gs:
		return int(_gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)


func _on_back_pressed() -> void:
	if not auto_navigate:
		return
	var router := get_node_or_null("/root/SceneRouter")
	if router == null:
		return
	if router.has_method("handle_back_request") and router.handle_back_request():
		return
	if router.has_method("goto"):
		router.goto(&"home/living", {})


static func _konfetti_farben() -> Gradient:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray(
		[AcTokens.PINK, AcTokens.YELLOW, AcTokens.TEAL, AcTokens.LEAF]
	)
	gradient.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	return gradient


static func _num(value: Variant) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return 0.0

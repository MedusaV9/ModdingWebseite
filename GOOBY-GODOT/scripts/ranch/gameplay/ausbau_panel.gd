class_name RanchAusbauPanel
extends Control
## Ranch-Ausbau + Hof-Laden (RANCH-2): Heu kaufen/ernten, Äpfel pflücken,
## Ausbaustufen (Boxen 2/3, Reitplatz, Weidezaun) und der Ausrüstungs-Shop
## (Sattel/Decke/Halfter in 5 Farben). ALLE Preise/Erträge kommen aus
## RanchWirtschaft (Daten: wirtschaft.json, Content-Pack-fähig); Käufe
## buchen ATOMAR über Economy.spend im selben gs.update-Block
## (Muster = RanchKauf).
##
## Einbau (RANCH-1): mounten + `back_pressed` verdrahten.
## Tests injizieren `game_state_override`.

signal back_pressed

const Economy := preload("res://scripts/logic/economy.gd")

const INK := Color("#3B3630")
const REASON := "ranch"

var game_state_override: Object

var _balance: Dictionary = {}
var _coins_label: Label
var _lager_label: Label
var _heu_kaufen_btn: Button
var _heu_ernten_btn: Button
var _apfel_btn: Button
var _ausbau_buttons: Dictionary = {}
var _gear_buttons: Dictionary = {}
var _feedback: Label
var _feedback_t := 0.0


func game_state() -> Object:
	if game_state_override != null:
		return game_state_override
	return get_node_or_null("/root/GameState")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_balance = RanchWirtschaft.load_balance()
	_build_layout()
	refresh()


func _process(delta: float) -> void:
	if _feedback_t > 0.0:
		_feedback_t -= delta
		_feedback.modulate.a = clampf(_feedback_t / 0.4, 0.0, 1.0)


func _wirtschaft() -> Dictionary:
	var gs := game_state()
	if gs == null:
		return RanchPlaySlices.default_wirtschaft()
	var raw: Variant = gs.get_value("ranch.wirtschaft", {})
	return RanchPlaySlices.normalize_wirtschaft(raw)


func _coins() -> int:
	var gs := game_state()
	return int(gs.get_value("economy.coins", 0)) if gs != null else 0


## ------------------------------------------------------------------ Aufbau


func _build_layout() -> void:
	var hintergrund := ColorRect.new()
	hintergrund.color = Color("#F3EAD9")
	hintergrund.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(hintergrund)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 14)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 10)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)
	var kopf := HBoxContainer.new()
	panel.add_child(kopf)
	var titel := Label.new()
	titel.theme_type_variation = &"HeadlineLabel"
	titel.text = I18nService.t("ranchplay.ausbau.titel")
	titel.add_theme_font_size_override("font_size", 26)
	titel.add_theme_color_override("font_color", INK)
	titel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kopf.add_child(titel)
	_coins_label = Label.new()
	_coins_label.theme_type_variation = &"CaptionLabel"
	_coins_label.add_theme_color_override("font_color", INK)
	kopf.add_child(_coins_label)
	var zurueck := Button.new()
	zurueck.text = I18nService.t("ranchplay.pflege.zurueck")
	zurueck.custom_minimum_size = Vector2(110, 44)
	zurueck.pressed.connect(
		func() -> void:
			AudioDirector.try_play(self, "ui_back")
			back_pressed.emit()
	)
	kopf.add_child(zurueck)
	# --- Lager & Felder.
	panel.add_child(_ueberschrift("ranchplay.ausbau.lager"))
	_lager_label = Label.new()
	_lager_label.theme_type_variation = &"CaptionLabel"
	_lager_label.add_theme_color_override("font_color", INK)
	panel.add_child(_lager_label)
	var lager_row := HBoxContainer.new()
	lager_row.add_theme_constant_override("separation", 8)
	panel.add_child(lager_row)
	_heu_kaufen_btn = _aktion_button(lager_row, _on_heu_kaufen)
	_heu_ernten_btn = _aktion_button(lager_row, _on_heu_ernten)
	_apfel_btn = _aktion_button(lager_row, _on_apfel)
	# --- Ausbau.
	panel.add_child(_ueberschrift("ranchplay.ausbau.stufen"))
	var ausbau_grid := GridContainer.new()
	ausbau_grid.columns = 2
	ausbau_grid.add_theme_constant_override("h_separation", 8)
	ausbau_grid.add_theme_constant_override("v_separation", 8)
	panel.add_child(ausbau_grid)
	for id: String in RanchWirtschaft.AUSBAU_IDS:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(150, 56)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_ausbau.bind(id))
		ausbau_grid.add_child(btn)
		_ausbau_buttons[id] = btn
	# --- Ausrüstungs-Shop.
	panel.add_child(_ueberschrift("ranchplay.ausbau.gear"))
	for slot: String in RanchWirtschaft.GEAR_SLOTS:
		var zeile := HBoxContainer.new()
		zeile.add_theme_constant_override("separation", 6)
		panel.add_child(zeile)
		var slot_label := Label.new()
		slot_label.theme_type_variation = &"CaptionLabel"
		slot_label.text = I18nService.t("ranchplay.gear.%s" % slot)
		slot_label.custom_minimum_size = Vector2(90, 0)
		slot_label.add_theme_color_override("font_color", INK)
		zeile.add_child(slot_label)
		for farbe: Variant in RanchWirtschaft.gear_farben(_balance):
			var id := "%s_%s" % [slot, farbe]
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(76, 46)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.pressed.connect(_on_gear.bind(id))
			var tint: Color = RanchGearMeshes.FARBEN.get(str(farbe), Color.WHITE)
			for state_name in ["normal", "hover", "pressed", "disabled"]:
				var style := StyleBoxFlat.new()
				style.bg_color = tint.lightened(0.45 if state_name == "disabled" else 0.25)
				style.set_corner_radius_all(10)
				style.set_border_width_all(2)
				style.border_color = INK
				btn.add_theme_stylebox_override(state_name, style)
			btn.add_theme_color_override("font_color", INK)
			btn.add_theme_color_override("font_disabled_color", INK)
			zeile.add_child(btn)
			_gear_buttons[id] = btn
	_feedback = Label.new()
	_feedback.theme_type_variation = &"HeadlineLabel"
	_feedback.add_theme_color_override("font_color", Color("#5FA052"))
	_feedback.modulate.a = 0.0
	panel.add_child(_feedback)


func _ueberschrift(key: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"CaptionLabel"
	label.text = I18nService.t(key)
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", INK)
	return label


func _aktion_button(parent: Control, handler: Callable) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(120, 52)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(handler)
	parent.add_child(btn)
	return btn


## ----------------------------------------------------------------- Anzeige


func refresh() -> void:
	var w := _wirtschaft()
	var coins := _coins()
	var jetzt := _now_ms()
	_coins_label.text = I18nService.t("ranchplay.ausbau.coins", {"n": coins})
	_lager_label.text = (
		I18nService
		. t(
			"ranchplay.ausbau.bestand",
			{
				"heu": int(w["lager"]["heu"]),
				"apfel": int(w["lager"]["apfel"]),
				"boxen": RanchWirtschaft.boxen_kapazitaet(w, _balance),
			}
		)
	)
	var heu_preis := maxi(0, int(_balance.get("preise", {}).get("heu_kauf", 0)))
	_heu_kaufen_btn.text = I18nService.t("ranchplay.ausbau.heu_kaufen", {"preis": heu_preis})
	_heu_kaufen_btn.disabled = coins < heu_preis
	var heu_bereit := jetzt >= int(w["felder"]["heuBereitAt"])
	_heu_ernten_btn.text = (
		I18nService.t("ranchplay.ausbau.heu_ernten")
		if heu_bereit
		else I18nService.t(
			"ranchplay.ausbau.waechst", {"min": _rest_min(int(w["felder"]["heuBereitAt"]), jetzt)}
		)
	)
	_heu_ernten_btn.disabled = not heu_bereit
	var baum_bereit := _erster_reifer_baum(w, jetzt) >= 0
	_apfel_btn.text = (
		I18nService.t("ranchplay.ausbau.apfel_pfluecken")
		if baum_bereit
		else I18nService.t(
			"ranchplay.ausbau.waechst", {"min": _rest_min(_naechster_baum_at(w), jetzt)}
		)
	)
	_apfel_btn.disabled = not baum_bereit
	for id: String in RanchWirtschaft.AUSBAU_IDS:
		var btn: Button = _ausbau_buttons[id]
		var preis := RanchWirtschaft.ausbau_preis(_balance, id)
		var gekauft := _ausbau_gekauft(w, id)
		btn.text = (
			I18nService.t("ranchplay.ausbau.%s" % id)
			+ "\n"
			+ (
				I18nService.t("ranchplay.ausbau.gebaut")
				if gekauft
				else I18nService.t("ranchplay.ausbau.preis", {"n": preis})
			)
		)
		btn.disabled = (
			gekauft or coins < preis or (id == "boxen3" and int(w["ausbau"]["boxen"]) < 2)
		)
	var owned: Array = w["gear"]["owned"]
	for id: String in _gear_buttons:
		var btn: Button = _gear_buttons[id]
		var teile := id.split("_")
		var preis := RanchWirtschaft.gear_preis(_balance, teile[0], teile[1])
		if owned.has(id):
			btn.text = I18nService.t("ranchplay.ausbau.gekauft")
			btn.disabled = true
		else:
			btn.text = "%d" % preis
			btn.disabled = coins < preis


func _ausbau_gekauft(w: Dictionary, id: String) -> bool:
	match id:
		"boxen2":
			return int(w["ausbau"]["boxen"]) >= 2
		"boxen3":
			return int(w["ausbau"]["boxen"]) >= 3
		_:
			return RanchWirtschaft.ausbau_aktiv(w, id)


func _erster_reifer_baum(w: Dictionary, jetzt: int) -> int:
	var baeume: Array = w["felder"]["baeume"]
	for i in baeume.size():
		if jetzt >= int(baeume[i]):
			return i
	return -1


func _naechster_baum_at(w: Dictionary) -> int:
	var baeume: Array = w["felder"]["baeume"]
	var frueheste := int(baeume[0]) if baeume.size() > 0 else 0
	for at: Variant in baeume:
		frueheste = mini(frueheste, int(at))
	return frueheste


func _rest_min(bereit_at: int, jetzt: int) -> int:
	return maxi(0, int(ceil(float(bereit_at - jetzt) / 60000.0)))


## ---------------------------------------------------------------- Aktionen


func _on_heu_kaufen() -> void:
	var ergebnis := RanchWirtschaft.heu_kaufen(_wirtschaft(), _coins(), 1, _balance)
	_buche_kauf(ergebnis, "ranchplay.ausbau.heu_da")


func _on_heu_ernten() -> void:
	var ergebnis := RanchWirtschaft.heu_ernten(_wirtschaft(), _now_ms(), _balance)
	_buche_gratis(ergebnis, "ranch_feed")
	if bool(ergebnis["ok"]):
		_zeige_feedback(
			I18nService.t("ranchplay.ausbau.geerntet", {"n": int(ergebnis.get("menge", 0))})
		)


func _on_apfel() -> void:
	var w := _wirtschaft()
	var baum := _erster_reifer_baum(w, _now_ms())
	if baum < 0:
		return
	var ergebnis := RanchWirtschaft.apfel_pfluecken(w, baum, _now_ms(), _balance)
	_buche_gratis(ergebnis, "ranch_feed")
	if bool(ergebnis["ok"]):
		_zeige_feedback(
			I18nService.t("ranchplay.ausbau.gepflueckt", {"n": int(ergebnis.get("menge", 0))})
		)


func _on_ausbau(id: String) -> void:
	var ergebnis := RanchWirtschaft.ausbau_kaufen(_wirtschaft(), _coins(), id, _balance)
	_buche_kauf(ergebnis, "ranchplay.ausbau.gebaut_toast")


func _on_gear(id: String) -> void:
	var ergebnis := RanchWirtschaft.gear_kaufen(_wirtschaft(), _coins(), id, _balance)
	_buche_kauf(ergebnis, "ranchplay.ausbau.gear_toast")


## Kauf ATOMAR buchen: Economy.spend + neue wirtschaft im selben update.
func _buche_kauf(ergebnis: Dictionary, toast_key: String) -> void:
	if not bool(ergebnis["ok"]):
		AudioDirector.try_play(self, "ui_error")
		return
	var gs := game_state()
	if gs == null:
		return
	var preis := _coins() - int(ergebnis["coins"])
	var bezahlt := [false]
	gs.update(
		func(state: Dictionary) -> void:
			if preis > 0 and not Economy.spend(state["economy"], preis, REASON):
				return
			bezahlt[0] = true
			state["ranch"]["wirtschaft"] = ergebnis["wirtschaft"]
	)
	if not bool(bezahlt[0]):
		return
	gs.notify_slice_changed("ranch")
	AudioDirector.try_play(self, "ui_buy")
	_zeige_feedback(I18nService.t(toast_key))
	refresh()


## Gratis-Buchung (Ernte/Pflücken) — nur die wirtschaft wechselt.
func _buche_gratis(ergebnis: Dictionary, sound: String) -> void:
	if not bool(ergebnis["ok"]):
		AudioDirector.try_play(self, "ui_error")
		return
	var gs := game_state()
	if gs == null:
		return
	gs.update(
		func(state: Dictionary) -> void: state["ranch"]["wirtschaft"] = ergebnis["wirtschaft"]
	)
	gs.notify_slice_changed("ranch")
	AudioDirector.try_play(self, sound)
	refresh()


func _zeige_feedback(text: String) -> void:
	_feedback.text = text
	_feedback_t = 1.2
	_feedback.modulate.a = 1.0


func _now_ms() -> int:
	var gs := game_state()
	if gs != null and "clock" in gs:
		return int(gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)

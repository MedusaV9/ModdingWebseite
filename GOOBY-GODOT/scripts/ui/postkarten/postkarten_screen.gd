class_name PostkartenScreen
extends Control
## Postkarten-Archiv + Souvenirregal (REST-4, EVAL Rang 15, P1 „Bald“):
## zeigt die generierten Urlaubs-Postkarten (PostkartenLogic-Archiv aus
## Vacation.tick) als Karten mit Ziel, Reisetag, Datum und handgeschriebener
## Zeile, dazu das Souvenirregal (ein Slot je Reiseziel) und den Set-Bonus
## (Münzen für 3/6/9 besuchte Ziele, einmalig je Stufe). Route `postkarten`
## — erreichbar über den Post-Schalter (Archiv ansehen) und die
## Postkartenwand/das Souvenirregal im Haus.

signal ready_for_reveal

const Economy := preload("res://scripts/logic/economy.gd")
const Vacation := preload("res://scripts/logic/vacation.gd")

const ROUTE := &"postkarten"
const ROUTES := {ROUTE: "res://scripts/ui/postkarten/postkarten_screen.tscn"}

## Tests/Screenshots: GameState-Double statt /root/GameState.
var gs_override: Object = null
## Tests: fixe Uhr (0 = clock/Systemzeit).
var now_override := 0
## Tests: Navigation abschaltbar.
var auto_navigate := true

var _gs: Object = null
var _rows: VBoxContainer
var _anzahl_label: Label
var _archiv_flow: HFlowContainer
var _archiv_leer: Label
var _souvenir_flow: HFlowContainer
var _souvenir_info: Label
var _set_box: VBoxContainer
var _toasts: ToastLayer
var _m: Dictionary = {}


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
	_refresh()
	ready_for_reveal.emit()


## ---------------------------------------------------------------- Test-API


func karten_im_archiv() -> int:
	var count := 0
	for kind in _archiv_flow.get_children():
		if kind is PanelContainer:
			count += 1
	return count


func souvenir_chips() -> Array[String]:
	var out: Array[String] = []
	for kind in _souvenir_flow.get_children():
		out.append(str(kind.name))
	return out


func claim_jetzt(n: int) -> int:
	return _on_claim(n)


## ---------------------------------------------------------------- Aufbau


func _build_ui() -> void:
	var wallpaper := AcWallpaper.new()
	wallpaper.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(wallpaper)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 24
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
	back.text = I18nService.t("postkarten.zurueck")
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(_on_back_pressed)
	header.add_child(back)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = I18nService.t("postkarten.titel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"StatusCapsule"
	_anzahl_label = Label.new()
	_anzahl_label.name = "Anzahl"
	_anzahl_label.theme_type_variation = &"SoftLabel"
	chip.add_child(_anzahl_label)
	header.add_child(chip)

	_archiv_leer = Label.new()
	_archiv_leer.name = "ArchivLeer"
	_archiv_leer.theme_type_variation = &"SoftLabel"
	_archiv_leer.text = I18nService.t("postkarten.leer")
	_archiv_leer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rows.add_child(_archiv_leer)

	_archiv_flow = HFlowContainer.new()
	_archiv_flow.name = "Archiv"
	_archiv_flow.add_theme_constant_override("h_separation", 12)
	_archiv_flow.add_theme_constant_override("v_separation", 12)
	_rows.add_child(_archiv_flow)

	var souvenir_karte := _karte()
	var souvenir_titel := Label.new()
	souvenir_titel.theme_type_variation = &"HeadlineLabel"
	souvenir_titel.text = I18nService.t("postkarten.souvenir.titel")
	souvenir_karte.add_child(souvenir_titel)
	_souvenir_info = Label.new()
	_souvenir_info.name = "SouvenirInfo"
	_souvenir_info.theme_type_variation = &"CaptionLabel"
	_souvenir_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	souvenir_karte.add_child(_souvenir_info)
	_souvenir_flow = HFlowContainer.new()
	_souvenir_flow.name = "Regal"
	_souvenir_flow.add_theme_constant_override("h_separation", 8)
	_souvenir_flow.add_theme_constant_override("v_separation", 8)
	souvenir_karte.add_child(_souvenir_flow)

	var set_karte := _karte()
	var set_titel := Label.new()
	set_titel.theme_type_variation = &"HeadlineLabel"
	set_titel.text = I18nService.t("postkarten.set.titel")
	set_karte.add_child(set_titel)
	var set_hinweis := Label.new()
	set_hinweis.theme_type_variation = &"CaptionLabel"
	set_hinweis.text = I18nService.t("postkarten.set.hinweis")
	set_hinweis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	set_karte.add_child(set_hinweis)
	_set_box = VBoxContainer.new()
	_set_box.name = "SetStufen"
	_set_box.add_theme_constant_override("separation", 8)
	set_karte.add_child(_set_box)

	_toasts = ToastLayer.new()
	add_child(_toasts)
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


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


## ---------------------------------------------------------------- Anzeige


func _refresh() -> void:
	var state := _state()
	var archiv := PostkartenLogic.archive_of(state)
	_anzahl_label.text = I18nService.t("postkarten.anzahl", {"n": archiv.size()})
	_archiv_leer.visible = archiv.is_empty()
	for kind in _archiv_flow.get_children():
		_archiv_flow.remove_child(kind)
		kind.queue_free()
	var neueste := archiv.duplicate()
	neueste.reverse()
	for entry: Dictionary in neueste:
		_archiv_flow.add_child(_postkarte(entry))
	_refresh_souvenirs(state)
	_refresh_set(state)


func _postkarte(entry: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var dest_id := str(entry["destId"])
	panel.name = "Karte_%s_%d" % [dest_id, int(entry["dayIndex"])]
	panel.theme_type_variation = &"AcCard"
	panel.custom_minimum_size = Vector2(300.0, 0.0) * float(_m.get("f", 1.0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var kopf := HBoxContainer.new()
	kopf.add_theme_constant_override("separation", 8)
	box.add_child(kopf)
	var farbe := ColorRect.new()
	farbe.color = PostkartenProps.DEST_AKZENT.get(dest_id, AcTokens.PAPER_SHADE)
	farbe.custom_minimum_size = Vector2(18.0, 18.0)
	farbe.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kopf.add_child(farbe)
	var titel := Label.new()
	titel.theme_type_variation = &"HeadlineLabel"
	titel.text = I18nService.t("postkarten.von", {"ort": I18nService.t("travel.ziel.%s" % dest_id)})
	titel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kopf.add_child(titel)
	var meta := Label.new()
	meta.theme_type_variation = &"CaptionLabel"
	meta.text = (
		"%s  %s"
		% [
			I18nService.t("postkarten.tag", {"tag": int(entry["dayIndex"])}),
			_datum(int(entry["atMs"])),
		]
	)
	box.add_child(meta)
	var text := Label.new()
	text.name = "Text"
	text.text = I18nService.t(PostkartenLogic.text_key(entry))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text)
	return panel


func _refresh_souvenirs(state: Dictionary) -> void:
	for kind in _souvenir_flow.get_children():
		_souvenir_flow.remove_child(kind)
		kind.queue_free()
	var besucht := PostkartenLogic.souvenirs_von(state)
	_souvenir_info.text = (
		I18nService.t("postkarten.souvenir.leer")
		if besucht.is_empty()
		else I18nService.t(
			"postkarten.souvenir.fortschritt",
			{"n": besucht.size(), "gesamt": PostkartenLogic.DEST_IDS.size()}
		)
	)
	# W13B (RAUMSTATION-Request): goldenes Weltengooby-Abzeichen vor den
	# Ziel-Slots, sobald alle 9 Ziele besucht sind (Latch aus reise_logic).
	if Vacation.weltengooby(Vacation.slice_of(state)):
		var badge := PanelContainer.new()
		badge.name = "WeltengoobyBadge"
		badge.theme_type_variation = &"StatusCapsule"
		var badge_label := Label.new()
		badge_label.theme_type_variation = &"SoftLabel"
		badge_label.text = I18nService.t("raumstation.weltengooby.badge")
		badge_label.add_theme_color_override("font_color", AcTokens.YELLOW_DARK)
		badge.add_child(badge_label)
		_souvenir_flow.add_child(badge)
	for dest_id: String in PostkartenLogic.DEST_IDS:
		var chip := PanelContainer.new()
		chip.theme_type_variation = &"StatusCapsule"
		var label := Label.new()
		label.theme_type_variation = &"SoftLabel"
		if besucht.has(dest_id):
			chip.name = "Souvenir_%s" % dest_id
			label.text = I18nService.t("travel.ziel.%s" % dest_id)
		else:
			chip.name = "Offen_%s" % dest_id
			label.text = I18nService.t("postkarten.souvenir.offen")
			chip.modulate = Color(1.0, 1.0, 1.0, 0.45)
		chip.add_child(label)
		_souvenir_flow.add_child(chip)


func _refresh_set(state: Dictionary) -> void:
	for kind in _set_box.get_children():
		_set_box.remove_child(kind)
		kind.queue_free()
	for stufe: Dictionary in PostkartenLogic.set_stufen(state):
		var zeile := HBoxContainer.new()
		zeile.name = "Stufe_%d" % int(stufe["n"])
		zeile.add_theme_constant_override("separation", 10)
		var label := Label.new()
		label.text = I18nService.t(
			"postkarten.set.stufe", {"n": int(stufe["n"]), "bonus": int(stufe["coins"])}
		)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		zeile.add_child(label)
		if bool(stufe["abgeholt"]):
			var fertig := Label.new()
			fertig.theme_type_variation = &"CaptionLabel"
			fertig.text = I18nService.t("postkarten.set.abgeholt")
			zeile.add_child(fertig)
		elif bool(stufe["erreicht"]):
			var btn := SquishButton.new()
			btn.name = "Claim_%d" % int(stufe["n"])
			btn.theme_type_variation = &"BtnYellow"
			btn.text = I18nService.t("postkarten.set.abholen", {"bonus": int(stufe["coins"])})
			btn.custom_minimum_size = Vector2(0.0, 48.0)
			btn.focus_mode = Control.FOCUS_NONE
			btn.pressed.connect(_on_claim_pressed.bind(int(stufe["n"])))
			zeile.add_child(btn)
		else:
			var offen := Label.new()
			offen.theme_type_variation = &"CaptionLabel"
			offen.text = I18nService.t("postkarten.set.noch_nicht")
			zeile.add_child(offen)
		_set_box.add_child(zeile)


## ---------------------------------------------------------------- Set-Bonus


func _on_claim_pressed(n: int) -> void:
	_on_claim(n)


func _on_claim(n: int) -> int:
	if _gs == null:
		return 0
	var now := _now_ms()
	# Box statt lokaler Variable: Lambdas fangen Primitive per WERT.
	var box := {"coins": 0}
	_gs.update(
		func(state: Dictionary) -> void:
			var coins := PostkartenLogic.claim_set_bonus(state, n, now)
			box["coins"] = coins
			if coins > 0 and state.get("economy") is Dictionary:
				Economy.award(state["economy"], coins, "setBonus")
	)
	var coins: int = box["coins"]
	_gs.notify_slice_changed("vacation")
	if coins > 0:
		_toasts.show_toast(I18nService.t("postkarten.set.erhalten", {"bonus": coins}))
		if is_inside_tree():
			MusicDirector.get_or_create(self).play_stinger("stinger-levelup")
	_refresh()
	return coins


## ---------------------------------------------------------------- Zustand


func _datum(at_ms: int) -> String:
	@warning_ignore("integer_division")
	var d := Time.get_datetime_dict_from_unix_time(at_ms / 1000)
	return "%02d.%02d.%04d" % [int(d["day"]), int(d["month"]), int(d["year"])]


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
		router.goto(&"city", {})

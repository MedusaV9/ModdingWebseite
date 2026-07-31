class_name MinigamePregame
extends Control
## Pregame-Screen (Doc G §Pregame): Schwierigkeitswahl (Leicht/Normal/Schwer
## + Endlos, wo unterstützt UND freigeschaltet — §G5.5) und ORIENTIERUNGSWAHL
## (Auto/Hochkant/Quer). Die Orientierung wird PRO SPIEL in AppSettings
## unter "mg_orientation.<id>" gemerkt; die Schwierigkeitswahl landet im
## Save (minigames.difficulty.<id>, additiver v5-Key). PLAY reist zum Host.

signal play_requested(params: Dictionary)
signal back_requested

const DIFF_ORDER: Array[String] = ["easy", "normal", "hard", "endless"]
const ORIENT_ORDER: Array[String] = ["auto", "portrait", "landscape"]
const Stats := preload("res://scripts/logic/stats.gd")

## Wunschbreite der Karte (Design-px — FB3: skaliert mit UiScale).
const CARD_BASE_WIDTH := 520.0

## Tests: Navigation abschaltbar; State-Override wie beim Host.
var auto_navigate := true
var state_node: Node = null

var game_id := ""
var selected_difficulty := "normal"
var selected_orientation := "auto"

var _meta: Dictionary = {}
var _center: CenterContainer
var _card: PanelContainer
var _cover: TextureRect
var _best_label: Label
var _hint_label: Label
var _diff_buttons: Dictionary = {}
var _orient_buttons: Dictionary = {}
var _touch_buttons: Array[Button] = []
var _chip_buttons: Array[Button] = []


func receive_params(params: Dictionary) -> void:
	game_id = str(params.get("game_id", ""))


func _ready() -> void:
	# E14-P0: and_offsets — nur Anker setzen behält unter dem Router-Mount
	# das 0×0-Rect (Offsets werden aufs aktuelle Rect zurückgerechnet).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_meta = MinigameRegistry.get_game(game_id)
	if _meta.is_empty():
		push_warning("[mg_pregame] unbekanntes Spiel '%s'" % game_id)
		_go_back()
		return
	_load_selections()
	_build_ui()
	_refresh_buttons()
	_apply_touch_floor()
	get_viewport().size_changed.connect(_apply_touch_floor)


func _load_selections() -> void:
	var gs := _resolve_state()
	if gs != null:
		var slice := MinigameFrameworkLogic.difficulty_slice_of(gs.state(), game_id)
		selected_difficulty = str(slice["selected"])
	var settings := get_node_or_null("/root/AppSettings")
	if settings != null and settings.has_method("get_setting"):
		selected_orientation = str(settings.get_setting("mg_orientation.%s" % game_id, "auto"))
	if not ORIENT_ORDER.has(selected_orientation):
		selected_orientation = "auto"


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.98, 0.94, 0.87)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_center = CenterContainer.new()
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_center)
	_card = PanelContainer.new()
	_card.theme_type_variation = &"AcCardLg"
	_card.custom_minimum_size = Vector2(CARD_BASE_WIDTH, 0)
	_center.add_child(_card)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	_card.add_child(rows)

	_cover = TextureRect.new()
	_cover.custom_minimum_size = Vector2(0, 180)
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var cover_path := MinigameRegistry.cover_path(game_id)
	if ResourceLoader.exists(cover_path):
		_cover.texture = load(cover_path)
	rows.add_child(_cover)

	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = I18nService.t(str(_meta.get("title_key", game_id)))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(title)

	_best_label = Label.new()
	_best_label.theme_type_variation = &"CaptionLabel"
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_best_label)

	# §C6 Web-Parität: der Start kostet Energie — das steht wie im Web-
	# Pregame sichtbar am Screen (E10-P1-2).
	var energy_note := Label.new()
	energy_note.theme_type_variation = &"CaptionLabel"
	energy_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	energy_note.text = I18nService.t(
		"mg.pregame.energy",
		{"energy": int(_meta.get("energy_cost", MinigameRegistry.DEFAULT_ENERGY_COST))}
	)
	rows.add_child(energy_note)

	# W13B/DRIVE (Doc G §6): NUR Fahr-Spiele zeigen das gewählte Autohaus-
	# Auto („Dein Auto: <Name> — Tempo ▮▮▯▯▯“) — der Host injiziert dieselben
	# Stats später als ctx.car/car_speed_mult.
	_add_car_line(rows)

	# FERTIG-1 (EVAL Rang 12): läuft für DIESES Spiel ein Modifier-Event,
	# steht es SICHTBAR vor dem Start (Name, Wirkung, Rest-Runden/-Zeit).
	_add_modifier_banner(rows)

	rows.add_child(_section_label(I18nService.t("mg.pregame.difficulty")))
	var diff_row := HBoxContainer.new()
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	diff_row.add_theme_constant_override("separation", 8)
	rows.add_child(diff_row)
	for mode in DIFF_ORDER:
		if mode == "endless" and not _endless_available():
			continue
		var btn := Button.new()
		btn.toggle_mode = true
		btn.theme_type_variation = &"AcChip"
		btn.text = I18nService.t("mg.diff.%s" % mode)
		btn.pressed.connect(_on_difficulty_pressed.bind(mode))
		diff_row.add_child(btn)
		_diff_buttons[mode] = btn
		_touch_buttons.append(btn)
		_chip_buttons.append(btn)

	rows.add_child(_section_label(I18nService.t("mg.pregame.orientation")))
	var orient_row := HBoxContainer.new()
	orient_row.alignment = BoxContainer.ALIGNMENT_CENTER
	orient_row.add_theme_constant_override("separation", 8)
	rows.add_child(orient_row)
	for orient in ORIENT_ORDER:
		var btn := Button.new()
		btn.toggle_mode = true
		btn.theme_type_variation = &"AcChip"
		btn.text = I18nService.t("mg.orient.%s" % orient)
		btn.pressed.connect(_on_orientation_pressed.bind(orient))
		orient_row.add_child(btn)
		_orient_buttons[orient] = btn
		_touch_buttons.append(btn)
		_chip_buttons.append(btn)

	# W15/TECHKIT (Doc G §9 R5): danceParty bekommt die Audio-Latenz-
	# Feinkalibrierung im Pregame — komplette Logik/UI lebt in der neuen
	# Datei dance_calibration.gd, hier nur der additive Mount.
	if game_id == "danceParty":
		DanceCalibration.mount_pregame_section(self, rows, _resolve_state())

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	rows.add_child(buttons)
	var back := Button.new()
	back.theme_type_variation = &"GhostButton"
	back.text = I18nService.t("mg.pregame.back")
	back.pressed.connect(_go_back)
	buttons.add_child(back)
	_touch_buttons.append(back)
	var play := Button.new()
	play.theme_type_variation = &"PrimaryButton"
	play.text = I18nService.t("mg.pregame.play")
	play.pressed.connect(_on_play_pressed)
	buttons.add_child(play)
	_touch_buttons.append(play)

	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"CaptionLabel"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_color_override("font_color", Color(0.85, 0.4, 0.35))
	_hint_label.hide()
	rows.add_child(_hint_label)


## FIX-B-Handoff (E5-F4/E7-P1-3): 48-px-Touch-Floor gilt PHYSISCH.
## FB3: Karte + Schriften laufen jetzt über die ZENTRALEN Bausteine
## (`ScreenShell`/`UiScale`) statt der alten Hochkant-Heuristik — die Karte
## skaliert in BEIDEN Orientierungen, bleibt in der Safe-Area zentriert
## und wird nie breiter als der sichere Bereich. Bei Resize/Rotation neu.
func _apply_touch_floor() -> void:
	var m := ScreenShell.metrics(get_viewport())
	var insets: Dictionary = m["insets"]
	_center.offset_left = float(insets["left"])
	_center.offset_right = -float(insets["right"])
	_center.offset_top = float(insets["top"])
	_center.offset_bottom = -float(insets["bottom"])
	_card.custom_minimum_size = Vector2(ScreenShell.card_width(m, CARD_BASE_WIDTH), 0)
	for btn in _touch_buttons:
		# BEIDE Achsen: kurze Chip-Texte ("Auto") unterschreiten sonst den
		# Floor in der Breite (48 px gilt für die kurze Kante des Tap-Ziels).
		btn.custom_minimum_size = btn.custom_minimum_size.max(Vector2(m["floor_px"], m["floor_px"]))
	ScreenShell.scale_fonts(_card, m["f"])
	# Cover ist Deko: skaliert mit, weicht aber ZUERST, wenn die Karte sonst
	# höher würde als der sichere Bereich (Quer-Formate mit großem Floor) —
	# Chips/Knöpfe behalten ihre Tippfläche, nichts läuft aus dem Canvas.
	var canvas: Vector2 = m["canvas"]
	var safe_h := canvas.y - float(insets["top"]) - float(insets["bottom"])
	var cover_h := minf(180.0 * float(m["f"]), safe_h * 0.28)
	_cover.custom_minimum_size = Vector2(0.0, cover_h)
	_cover.visible = true
	var over := _card.get_combined_minimum_size().y - safe_h * 0.94
	if over > 0.0:
		cover_h = maxf(cover_h - over, 0.0)
		_cover.custom_minimum_size = Vector2(0.0, cover_h)
		_cover.visible = cover_h >= 56.0


## FERTIG-1 (EVAL Rang 12): Bonus-Event-Banner — die sichtbare Anzeige VOR
## dem Start (Web-§B4-Pendant zur Arcade-Bubble). Nur wenn das aktive Event
## zu diesem Spiel gehört und das Fenster noch offen ist.
func _add_modifier_banner(rows: VBoxContainer) -> void:
	var gs := _resolve_state()
	if gs == null or gs.get("clock") == null:
		return
	var now := int(gs.clock.now_ms())
	var active := ModifierEngine.get_active_for(gs.state(), game_id, now)
	if active.is_empty():
		return
	var box := PanelContainer.new()
	box.name = "ModifierBanner"
	box.theme_type_variation = &"AcCard"
	rows.add_child(box)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 2)
	box.add_child(lines)
	var color: Color = active.get("color", Color(1.0, 0.83, 0.3))
	var titel := Label.new()
	titel.theme_type_variation = &"HeadlineLabel"
	titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titel.add_theme_color_override("font_color", color)
	titel.text = I18nService.t("modifier.pregame.titel")
	lines.add_child(titel)
	var desc := Label.new()
	desc.theme_type_variation = &"CaptionLabel"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.text = (
		"%s — %s" % [I18nService.t(str(active["name_key"])), I18nService.t(str(active["desc_key"]))]
	)
	lines.add_child(desc)
	var rest := ModifierEngine.countdown_text(int(active["endsAt"]), now)
	var plays := int(active.get("remaining_plays", 0))
	var rest_label := Label.new()
	rest_label.theme_type_variation = &"CaptionLabel"
	rest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if plays <= 1:
		rest_label.text = I18nService.t("modifier.pregame.runde_eine", {"rest": rest})
	else:
		rest_label.text = I18nService.t("modifier.pregame.runden", {"n": plays, "rest": rest})
	lines.add_child(rest_label)


## W13B/DRIVE: Auto-Zeile für Fahr-Spiele (FrameworkLogic.CAR_GAMES — Spiegel
## von Web CAR_GAMES: cityDrive + deliveryRush). Liest das AUSGEWÄHLTE Auto
## aus dem Autohaus-Besitz (AutoKatalog.aktives_auto: Save-Keys city.autos +
## city.aktivesAuto, Fallback Start-Sedan) und zeigt die Tempo-Balken aus
## CarStatsLogic. Ohne GameState (Tests ohne State) erscheint KEINE Zeile.
func _add_car_line(rows: VBoxContainer) -> void:
	if not MinigameFrameworkLogic.CAR_GAMES.has(game_id):
		return
	var gs := _resolve_state()
	if gs == null or not gs.has_method("get_value"):
		return
	var auto := AutoKatalog.aktives_auto(gs)
	if auto.is_empty():
		return
	var line := Label.new()
	line.name = "CarLine"
	line.theme_type_variation = &"CaptionLabel"
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.text = (
		I18nService
		. t(
			"mg.pregame.car",
			{
				"name": str(auto.get("name_de", auto.get("id", "?"))),
				"tempo": CarStatsLogic.bars((auto.get("stats", {}) as Dictionary).get("speed")),
			}
		)
	)
	rows.add_child(line)


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"SoftLabel"
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _endless_available() -> bool:
	if not _meta.get("supports_endless", false):
		return false
	var gs := _resolve_state()
	if gs == null:
		return false
	return MinigameFrameworkLogic.endless_unlocked(gs.state(), game_id)


func _refresh_buttons() -> void:
	if not _diff_buttons.has(selected_difficulty):
		selected_difficulty = "normal"
	for mode: String in _diff_buttons:
		(_diff_buttons[mode] as Button).button_pressed = mode == selected_difficulty
	for orient: String in _orient_buttons:
		(_orient_buttons[orient] as Button).button_pressed = orient == selected_orientation
	var gs := _resolve_state()
	var best := 0
	if gs != null:
		best = MinigameFrameworkLogic.best_for_mode(gs.state(), game_id, selected_difficulty)
	_best_label.text = I18nService.t("mg.pregame.best", {"best": best})


func _on_difficulty_pressed(mode: String) -> void:
	AudioDirector.try_play(self, "ui_chip")
	selected_difficulty = mode
	# Web-Muster: die Wahl easy/normal/hard wird im Save gemerkt (Endlos nicht).
	if mode != "endless":
		var gs := _resolve_state()
		if gs != null:
			var id := game_id
			gs.update(
				func(state: Dictionary) -> void:
					var mg: Dictionary = state["minigames"]
					if not (mg.get("difficulty") is Dictionary):
						mg["difficulty"] = {}
					mg["difficulty"][id] = mode
			)
	_refresh_buttons()


func _on_orientation_pressed(orient: String) -> void:
	AudioDirector.try_play(self, "ui_chip")
	selected_orientation = orient
	var settings := get_node_or_null("/root/AppSettings")
	if settings != null and settings.has_method("set_setting"):
		settings.set_setting("mg_orientation.%s" % game_id, orient)
	_refresh_buttons()


func _on_play_pressed() -> void:
	if _is_exhausted():
		# §C1 Web-Parität (framework.js launch-Gate): erschöpfte Goobys
		# spielen nicht — Hinweis statt Start (E10-P1-2).
		AudioDirector.try_play(self, "ui_error")
		_hint_label.text = I18nService.t("mg.pregame.too_sleepy")
		_hint_label.show()
		return
	AudioDirector.try_play(self, "ui_confirm")
	var params := {
		"game_id": game_id,
		"difficulty": selected_difficulty,
		"orientation": selected_orientation,
	}
	play_requested.emit(params)
	if not auto_navigate:
		return
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("goto"):
		router.goto(&"mg_host", params)


func _go_back() -> void:
	AudioDirector.try_play(self, "ui_back")
	back_requested.emit()
	if not auto_navigate:
		return
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("goto"):
		router.goto(&"arcade", {})


func _resolve_state() -> Node:
	if state_node != null:
		return state_node
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("state") and gs.has_method("update"):
		return gs
	return null


## §C1: Energie <= 15 → Minigames verweigern (Spiegel von stats.is_exhausted).
func _is_exhausted() -> bool:
	var gs := _resolve_state()
	if gs == null:
		return false
	var state: Dictionary = gs.state()
	var gooby: Variant = state.get("gooby")
	if not (gooby is Dictionary):
		return false
	var stats: Variant = (gooby as Dictionary).get("stats")
	if not (stats is Dictionary):
		return false
	return Stats.is_exhausted(stats)

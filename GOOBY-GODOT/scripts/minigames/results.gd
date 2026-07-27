class_name MinigameResults
extends Control
## Results-Screen des Minigame-Hosts: Score, Coins (inkl. Tagesbonus-×2-Chip,
## Tageslimit-Hinweis), Bestwert/Neuer-Rekord, XP/Level-Ups. Buttons feuern
## nur Signale — Navigation gehört dem Host (again → Neustart, back → Arcade).
##
## POLISH-A: der Screen ist der Belohnungsmoment ALLER Spiele — Punkte zählen
## hörbar hoch, Sterne ploppen nacheinander ein (1 = geschafft, +1 Ziel
## geschlagen, +1 neuer Rekord), „Neuer Rekord!“ feiert mit Konfetti +
## Rekord-Fanfare, Münzen regnen. Alles über JuiceKit/FeelSfx und damit
## Reduced-Motion-sauber (Töne bleiben, Bewegung stoppt).

signal again_pressed
signal back_pressed

## Wunschbreite der Karte (Design-px — FB3: skaliert mit UiScale).
const PANEL_BASE_WIDTH := 420.0

var _panel: PanelContainer
var _center: CenterContainer
var _rows: VBoxContainer
var _juice: JuiceKit
var _again: Button
var _back: Button


func _ready() -> void:
	# E14-P0: and_offsets — nur Anker setzen behält das aktuelle Rect.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.24, 0.16, 0.12, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_center = CenterContainer.new()
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_center)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"AcCardLg"
	_panel.custom_minimum_size = Vector2(PANEL_BASE_WIDTH, 0)
	_center.add_child(_panel)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 10)
	_panel.add_child(_rows)
	get_viewport().size_changed.connect(_apply_metrics)


## FB3: Karte skaliert mit der ZENTRALEN UiScale-Regel, bleibt in der
## Safe-Area zentriert (Notch/Home-Indicator) und die Knöpfe halten den
## Touch-Floor — vorher feste 420 px + Canvas-Zentrum.
func _apply_metrics() -> void:
	if _panel == null:
		return
	var m := ScreenShell.metrics(get_viewport())
	var insets: Dictionary = m["insets"]
	_center.offset_left = float(insets["left"])
	_center.offset_right = -float(insets["right"])
	_center.offset_top = float(insets["top"])
	_center.offset_bottom = -float(insets["bottom"])
	_panel.custom_minimum_size = Vector2(ScreenShell.card_width(m, PANEL_BASE_WIDTH), 0)
	for btn in [_again, _back]:
		if btn != null:
			ScreenShell.touch_target(btn, m)
	ScreenShell.scale_fonts(_panel, m["f"])
	# Fit-Pass: die Karte darf NIE höher werden als die Safe-Area (Quer-
	# Formate) — Schriften schrumpfen proportional zurück (nie unter die
	# Design-Basis), die Knöpfe behalten ihren Touch-Floor.
	var canvas: Vector2 = m["canvas"]
	var safe_h := (canvas.y - float(insets["top"]) - float(insets["bottom"])) * 0.96
	var f_fit: float = m["f"]
	for _pass in 4:
		var need := _panel.get_combined_minimum_size().y
		if f_fit <= 1.0 or need <= safe_h:
			break
		f_fit = maxf(f_fit * safe_h / need, 1.0)
		ScreenShell.scale_fonts(_panel, f_fit)


## breakdown = MinigameAward.award()-Ergebnis; meta = Registry-Zeile.
## juice (optional, vom Host): schaltet Count-Up/Konfetti/Münz-Regen frei —
## ohne Kit (Alt-Aufrufer/Tests) steht der Screen sofort statisch da.
func show_results(breakdown: Dictionary, meta: Dictionary, juice: JuiceKit = null) -> void:
	_juice = juice
	# EF-3 F3 („jeweils passend“): 0 Punkte bekommen keinen Sieg-Klang —
	# der weiche game_lose passt zum Trost-Moment des Hosts.
	FeelSfx.play(self, "game_win" if int(breakdown.get("score", 0)) > 0 else "game_lose")
	for child in _rows.get_children():
		child.queue_free()
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = I18nService.t("mg.results.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rows.add_child(title)
	var game_name := Label.new()
	game_name.theme_type_variation = &"CaptionLabel"
	game_name.text = I18nService.t(str(meta.get("title_key", "mg.results.title")))
	game_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rows.add_child(game_name)
	var final_score := int(breakdown.get("score", 0))
	var score := Label.new()
	score.theme_type_variation = &"HeadlineLabel"
	score.text = I18nService.t("mg.results.score", {"score": final_score})
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rows.add_child(score)
	_add_stars(breakdown, final_score)
	var new_best := bool(breakdown.get("newBest", false))
	if new_best:
		var best_line := _add_line(I18nService.t("mg.results.new_best"), Color(1.0, 0.62, 0.16))
		_celebrate_record(best_line)
	else:
		_add_line(
			I18nService.t("mg.results.best", {"best": int(breakdown.get("best", 0))}),
			Color(0.55, 0.42, 0.35)
		)
	var coins := int(breakdown.get("coins", 0))
	var coins_text := I18nService.t("mg.results.coins", {"coins": coins})
	if breakdown.get("firstToday", false):
		coins_text += "  " + I18nService.t("mg.results.daily_bonus")
	var coins_line := _add_line(coins_text, Color(0.93, 0.61, 0.15))
	if breakdown.get("dayCapReached", false):
		_add_line(I18nService.t("mg.results.day_cap"), Color(0.72, 0.5, 0.42))
	# FERTIG-1 (EVAL Rang 12): Modifier-Wirkung sichtbar im Ergebnis.
	_add_modifier_lines(breakdown)
	_add_line(
		I18nService.t("mg.results.xp", {"xp": int(breakdown.get("xp", 0))}), Color(0.42, 0.6, 0.36)
	)
	if int(breakdown.get("levelsGained", 0)) > 0:
		_add_line(
			I18nService.t(
				"mg.results.level_up", {"coins": int(breakdown.get("coinsFromLevels", 0))}
			),
			Color(0.95, 0.45, 0.66)
		)
		# EF-1/EVAL-1 D8: Level-Up wird GEFEIERT (Vollbild-Moment nach dem
		# Count-Up) — vorher war es nur eine unscheinbare Textzeile.
		_feier_level_up(breakdown)
	if breakdown.get("beatTarget", false):
		_add_line(I18nService.t("mg.results.beat_target"), Color(0.42, 0.6, 0.36))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	_rows.add_child(buttons)
	_again = Button.new()
	_again.theme_type_variation = &"PrimaryButton"
	_again.text = I18nService.t("mg.results.again")
	_again.focus_mode = Control.FOCUS_NONE
	_again.pressed.connect(
		func() -> void:
			AudioDirector.try_play(self, "ui_confirm")
			again_pressed.emit()
	)
	buttons.add_child(_again)
	_back = Button.new()
	_back.theme_type_variation = &"GhostButton"
	_back.text = I18nService.t("mg.results.back")
	_back.focus_mode = Control.FOCUS_NONE
	_back.pressed.connect(
		func() -> void:
			AudioDirector.try_play(self, "ui_back")
			back_pressed.emit()
	)
	buttons.add_child(_back)
	_apply_metrics()
	show()
	if _juice != null:
		# Punkte zählen hörbar hoch (Ticks steigen in der Tonhöhe), das Panel
		# federt ein, Münzen regnen sobald es welche gab. Präfix/Suffix werden
		# locale-sicher aus dem Template geschnitten ({score} kann wandern).
		var template := I18nService.t("mg.results.score", {"score": "|"})
		var parts := template.split("|")
		var suffix := parts[1] if parts.size() > 1 else ""
		_juice.count_to(score, 0, final_score, 0.9, parts[0], suffix)
		_juice.scale_pop(_panel, 1.06, 260)
		if coins > 0:
			_pulse_later(0.5, coins_line)


## FERTIG-1 (EVAL Rang 12): war ein Modifier-Event aktiv, zeigt der Screen
## Name + jede konkrete Wirkung (Bonus-Coins, Punkte-/XP-Faktor, gratis
## Energie, Glücksrolle) und den Tages-Ledger-Hinweis, wenn gedeckelt.
func _add_modifier_lines(breakdown: Dictionary) -> void:
	var mod: Variant = breakdown.get("modifier")
	if not (mod is Dictionary) or (mod as Dictionary).is_empty():
		return
	var type_id := str((mod as Dictionary).get("type", ""))
	var def: Variant = ModifierEngine.TYPES.get(type_id)
	if not (def is Dictionary):
		return
	var color: Color = (def as Dictionary).get("color", Color(0.93, 0.61, 0.15))
	var mod_name := I18nService.t(str((def as Dictionary).get("name_key", type_id)))
	var line := _add_line(I18nService.t("modifier.results.aktiv", {"name": mod_name}), color)
	if _juice != null:
		_juice.scale_pop(line, 1.12, 220)
	var bonus := int(breakdown.get("modifierBonusCoins", 0))
	if bonus > 0:
		_add_line(I18nService.t("modifier.results.bonus_coins", {"n": bonus}), color)
	if float((mod as Dictionary).get("score_mult", 1.0)) > 1.0:
		_add_line(I18nService.t("modifier.results.score_mult"), color)
	if float((mod as Dictionary).get("xp_mult", 1.0)) > 1.0:
		_add_line(I18nService.t("modifier.results.xp_mult"), color)
	if (mod as Dictionary).get("energy_free", false):
		_add_line(I18nService.t("modifier.results.energie"), color)
	var glueck := int(breakdown.get("gluecksrolleCoins", 0))
	if glueck > 0:
		_add_line(I18nService.t("modifier.results.gluecksrolle", {"n": glueck}), color)
	if breakdown.get("modifierCapped", false):
		_add_line(I18nService.t("modifier.results.capped"), Color(0.72, 0.5, 0.42))


func _add_stars(breakdown: Dictionary, final_score: int) -> void:
	var earned := 0
	if final_score > 0:
		earned += 1
	if breakdown.get("beatTarget", false):
		earned += 1
	if breakdown.get("newBest", false):
		earned += 1
	var stars := FeelStarRow.new()
	stars.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_rows.add_child(stars)
	stars.reveal(earned, _reduced_motion())


## Level-Up-Feier (EF-1, EVAL-1 D8): der Vollbild-Moment kommt nach dem
## Score-Count-Up (Ranch-Muster levelup_feier.gd, eigenständige Klasse).
func _feier_level_up(breakdown: Dictionary) -> void:
	var tree := get_tree()
	if tree == null:
		return
	# Gebundene Methode statt Lambda (REST5, B2): wird der Results-Screen vor
	# dem Timeout freigegeben, löst Godot die Verbindung automatisch — ein
	# Lambda-Capture würde "Lambda capture ... was freed" loggen.
	tree.create_timer(1.1).timeout.connect(_zeige_level_up.bind(breakdown))


func _zeige_level_up(breakdown: Dictionary) -> void:
	if not visible:
		return
	LevelUpFeier.zeige_in(
		self, int(breakdown.get("level", 2)), int(breakdown.get("coinsFromLevels", 0))
	)


## „Neuer Rekord!“ — Konfetti + Fanfare + Goldblitz, Zeile poppt.
func _celebrate_record(line: Label) -> void:
	if _juice == null:
		FeelSfx.play(self, "game_record")
		return
	var tree := get_tree()
	if tree == null:
		return
	# Gebundene Methode statt Lambda (REST5, B2) — s. _feier_level_up.
	tree.create_timer(0.55).timeout.connect(_zeige_rekord_feier.bind(line))


func _zeige_rekord_feier(line: Label) -> void:
	if not visible or _juice == null:
		return
	FeelSfx.play(self, "game_record")
	_juice.confetti(110)
	_juice.hit_flash(Color(1.0, 0.85, 0.35, 0.2), 320)
	_juice.scale_pop(line, 1.35, 300)


func _pulse_later(delay: float, line: Label) -> void:
	var tree := get_tree()
	if tree == null:
		return
	# Gebundene Methode statt Lambda (REST5, B2) — s. _feier_level_up.
	tree.create_timer(delay).timeout.connect(_pulse_now.bind(line))


func _pulse_now(line: Label) -> void:
	if not visible or _juice == null:
		return
	_juice.coin_rain(24)
	_juice.scale_pop(line, 1.18, 220)


func _add_line(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	_rows.add_child(label)
	return label


func _reduced_motion() -> bool:
	var settings := get_node_or_null("/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return settings.is_reduced_motion()
	return false

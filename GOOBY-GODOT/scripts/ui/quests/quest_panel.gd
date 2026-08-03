class_name DailyQuestPanel
extends VBoxContainer
## Inhalt des Tagesquest-Sheets (REST-2, AC-Look): drei Quest-Karten mit
## Kategorie-Icon, Titel/Text, Fortschrittsbalken, Belohnungs-Chips und
## Abholen-Knopf; darunter Bonus-Zeile („alle drei schaffen“) und der
## 1×-tägliche Reroll. Wird vom DailyQuestService in ein PanelSheet gehängt
## (add_content) — Skalierung kommt als `f` aus UiScale.for_viewport.
##
## Häkchen-Animation: mark_claimed() tauscht den Abholen-Knopf gegen ein
## aufploppendes Häkchen (UiMotion.pop_in + sparkle) — der „Check“-Moment
## aus der Aufgabe, ohne das ganze Brett neu zu bauen.

signal claim_pressed(id: String)
signal reroll_pressed
## G8 IDEA-WOCHE: Feiern-Tap aus dem „Diese Woche“-Abschnitt (Finale des
## Wochen-Vorhabens) — der DailyQuestService zahlt aus und feiert.
signal vorhaben_feiern_pressed

const ICON_DIR := "res://assets/ui/icons/"
## Kategorie → Icon + Identitätsfarbe (AC-Kategorien-Farbwelt).
const KATEGORIE_STYLE := {
	"care": {"icon": "rabbit", "tint": AcTokens.PINK},
	"games": {"icon": "gamepad", "tint": AcTokens.TEAL},
	"garden": {"icon": "leaf", "tint": AcTokens.LEAF_DARK},
	"economy": {"icon": "coin", "tint": AcTokens.YELLOW_DARK},
}
const CHECK_PX := 30.0

var _rows: Dictionary = {}
var _bonus_label: Label
var _reroll_btn: Button
var _f := 1.0


## G4/P23 — das Panel wird erst NACH rebuild() ins Sheet gehängt (Service-
## Reihenfolge open_panel): den physischen Touch-Floor mit echten
## Viewport-Metriken nachziehen, sobald der Baum steht.
func _enter_tree() -> void:
	_apply_touch_floor()


## G8 IDEA-WOCHE: `vorhaben` (optional, {} = kein Abschnitt) rendert den
## „Diese Woche“-Abschnitt OBEN im Blatt — Bestands-Aufrufer ohne das
## fünfte Argument bleiben unverändert.
func rebuild(
	board: Array, bonus: Dictionary, reroll_available: bool, f: float, vorhaben := {}
) -> void:
	_f = maxf(f, 0.5)
	_rows.clear()
	for child in get_children():
		child.queue_free()
	add_theme_constant_override("separation", int(10.0 * _f))
	if not vorhaben.is_empty():
		add_child(_build_vorhaben(vorhaben))
	var subtitle := Label.new()
	subtitle.name = "Untertitel"
	subtitle.theme_type_variation = "CaptionLabel"
	subtitle.text = I18nService.t("quests.untertitel")
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(subtitle)
	if board.is_empty():
		var empty := Label.new()
		empty.name = "Leer"
		empty.theme_type_variation = "SoftLabel"
		empty.text = I18nService.t("quests.leer")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(empty)
		return
	for row: Dictionary in board:
		add_child(_build_row(row))
	add_child(_build_bonus_row(bonus))
	add_child(_build_reroll(reroll_available))


## J1 Beute-Flug: Quell-Control für den Münzflug (Karte der Quest-Zeile).
func claim_quelle(id: String) -> Control:
	return (_rows.get(id, {}) as Dictionary).get("card") as Control


## Häkchen-Moment nach erfolgreichem Claim (Service ruft das statt rebuild).
func mark_claimed(id: String, bonus: Dictionary) -> void:
	var row: Dictionary = _rows.get(id, {})
	if row.is_empty():
		return
	var btn := row["claim"] as Button
	var check := row["check"] as TextureRect
	btn.visible = false
	check.visible = true
	UiMotion.pop_in(check)
	UiMotion.sparkle(row["card"] as Control, AcTokens.GOLD)
	var bar := row["bar"] as ProgressBar
	bar.value = bar.max_value
	(row["count"] as Label).text = I18nService.t("quests.erledigt")
	_update_bonus(bonus)


## G8 IDEA-WOCHE: „Diese Woche“-Karte (eigene Sektion-Klasse) bauen und
## ihren Feiern-Tap als Panel-Signal weiterreichen.
func _build_vorhaben(vorhaben: Dictionary) -> Control:
	var sektion := WochenVorhabenSection.new()
	sektion.rebuild(vorhaben, _f)
	sektion.feiern_pressed.connect(func() -> void: vorhaben_feiern_pressed.emit())
	return sektion


func _build_row(row: Dictionary) -> Control:
	var def: Dictionary = row.get("def", {})
	var id := str(def.get("id", ""))
	var style: Dictionary = KATEGORIE_STYLE.get(str(def.get("kategorie", "")), {})
	var card := PanelContainer.new()
	card.name = "Quest" + id.to_pascal_case()
	card.theme_type_variation = "AcCard"
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, int(10.0 * _f))
	card.add_child(margin)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", int(10.0 * _f))
	margin.add_child(box)
	var icon := TextureRect.new()
	icon.texture = load("%s%s.svg" % [ICON_DIR, str(style.get("icon", "sparkle"))])
	icon.custom_minimum_size = Vector2.ONE * roundf(26.0 * _f)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.self_modulate = style.get("tint", AcTokens.INK)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	box.add_child(_build_row_text(def, row))
	box.add_child(_build_row_right(id, def, row, card))
	return card


func _build_row_text(def: Dictionary, row: Dictionary) -> Control:
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", int(4.0 * _f))
	var title := Label.new()
	title.theme_type_variation = "SoftLabel"
	title.add_theme_font_override("font", ThemeService.font(800))
	title.text = I18nService.t(DailyQuestCatalog.title_key(def))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(title)
	var desc := Label.new()
	desc.theme_type_variation = "CaptionLabel"
	desc.text = I18nService.t(DailyQuestCatalog.text_key(def))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(desc)
	var progress_box := HBoxContainer.new()
	progress_box.add_theme_constant_override("separation", int(8.0 * _f))
	var bar := ProgressBar.new()
	bar.theme_type_variation = "StatEnergy"
	bar.custom_minimum_size = Vector2(roundf(96.0 * _f), roundf(10.0 * _f))
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.max_value = float(maxi(1, int(row.get("target", 1))))
	bar.value = float(int(row.get("progress", 0)))
	progress_box.add_child(bar)
	var count := Label.new()
	count.theme_type_variation = "CaptionLabel"
	if bool(row.get("claimed", false)):
		count.text = I18nService.t("quests.erledigt")
	else:
		count.text = I18nService.t(
			"quests.fortschritt",
			{"n": int(row.get("progress", 0)), "ziel": int(row.get("target", 1))}
		)
	progress_box.add_child(count)
	text_box.add_child(progress_box)
	row["_bar"] = bar
	row["_count"] = count
	return text_box


func _build_row_right(id: String, def: Dictionary, row: Dictionary, card: Control) -> Control:
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", int(6.0 * _f))
	var reward := HBoxContainer.new()
	reward.alignment = BoxContainer.ALIGNMENT_CENTER
	reward.add_theme_constant_override("separation", int(4.0 * _f))
	var coin := TextureRect.new()
	coin.texture = load("res://assets/ui/coin.png")
	coin.custom_minimum_size = Vector2.ONE * roundf(16.0 * _f)
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	reward.add_child(coin)
	var reward_label := Label.new()
	reward_label.theme_type_variation = "CaptionLabel"
	reward_label.text = I18nService.t(
		"quests.belohnung", {"muenzen": int(def.get("muenzen", 0)), "xp": int(def.get("xp", 0))}
	)
	reward.add_child(reward_label)
	right.add_child(reward)
	var claim := SquishButton.new()
	claim.name = "Claim" + id.to_pascal_case()
	claim.theme_type_variation = "BtnLeaf"
	claim.text = I18nService.t("quests.abholen")
	claim.focus_mode = Control.FOCUS_NONE
	claim.disabled = not bool(row.get("complete", false)) or bool(row.get("claimed", false))
	claim.visible = not bool(row.get("claimed", false))
	claim.pressed.connect(func() -> void: claim_pressed.emit(id))
	_lift_to_touch_floor(claim)
	right.add_child(claim)
	var check := TextureRect.new()
	check.name = "Check" + id.to_pascal_case()
	check.texture = load(ICON_DIR + "check.svg")
	check.custom_minimum_size = Vector2.ONE * roundf(CHECK_PX * _f)
	check.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	check.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	check.self_modulate = AcTokens.LEAF_DARK
	check.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	check.visible = bool(row.get("claimed", false))
	right.add_child(check)
	_rows[id] = {
		"card": card,
		"claim": claim,
		"check": check,
		"bar": row["_bar"],
		"count": row["_count"],
	}
	return right


func _build_bonus_row(bonus: Dictionary) -> Control:
	var chip := PanelContainer.new()
	chip.name = "BonusZeile"
	chip.theme_type_variation = "AcChip"
	_bonus_label = Label.new()
	_bonus_label.theme_type_variation = "CaptionLabel"
	_bonus_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chip.add_child(_bonus_label)
	_update_bonus(bonus)
	return chip


func _update_bonus(bonus: Dictionary) -> void:
	if _bonus_label == null or not is_instance_valid(_bonus_label):
		return
	if bool(bonus.get("paid", false)):
		_bonus_label.text = I18nService.t("quests.bonus_bezahlt")
	else:
		_bonus_label.text = I18nService.t(
			"quests.bonus_offen",
			{"muenzen": int(bonus.get("muenzen", 0)), "xp": int(bonus.get("xp", 0))}
		)


func _build_reroll(available: bool) -> Control:
	var box := HBoxContainer.new()
	box.name = "RerollZeile"
	box.add_theme_constant_override("separation", int(8.0 * _f))
	_reroll_btn = SquishButton.new()
	_reroll_btn.name = "RerollButton"
	_reroll_btn.theme_type_variation = "GhostButton"
	_reroll_btn.text = I18nService.t("quests.reroll")
	_reroll_btn.focus_mode = Control.FOCUS_NONE
	_reroll_btn.disabled = not available
	_reroll_btn.pressed.connect(func() -> void: reroll_pressed.emit())
	_lift_to_touch_floor(_reroll_btn)
	box.add_child(_reroll_btn)
	var hint := Label.new()
	hint.theme_type_variation = "CaptionLabel"
	hint.text = I18nService.t("quests.reroll_hinweis")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(hint)
	return box


## G4/P23 — Tippflächen der Abholen-/Reroll-Knöpfe auf den PHYSISCHEN
## 44-pt-Floor heben (vorher nur Theme-Default). Außerhalb des Baums
## (rebuild läuft vor add_content) fällt der Floor auf die f-Heuristik
## zurück; _enter_tree zieht mit echten Metriken nach.
func _touch_floor_px() -> float:
	if is_inside_tree():
		return float(ScreenShell.metrics(get_viewport())["floor_px"])
	return float(AcTokens.TOUCH_FLOOR) * maxf(_f, 1.0)


func _lift_to_touch_floor(btn: Control) -> void:
	var floor_px := _touch_floor_px()
	btn.custom_minimum_size = btn.custom_minimum_size.max(Vector2(floor_px, floor_px))


func _apply_touch_floor() -> void:
	for row: Dictionary in _rows.values():
		var claim: Variant = row.get("claim")
		if is_instance_valid(claim):
			_lift_to_touch_floor(claim as Control)
	if _reroll_btn != null and is_instance_valid(_reroll_btn):
		_lift_to_touch_floor(_reroll_btn)

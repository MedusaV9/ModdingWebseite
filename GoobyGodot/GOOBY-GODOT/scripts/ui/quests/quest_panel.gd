class_name DailyQuestPanel
extends VBoxContainer
## Inhalt des Tagesquest-Sheets (REST-2, AC-Look): drei Quest-Karten mit
## Kategorie-Icon, Titel/Text, Fortschrittsbalken, Belohnungs-Chips und
## Abholen-Knopf; darunter Bonus-Zeile („alle drei schaffen“) und der
## 1×-tägliche Reroll. Wird vom DailyQuestService in ein PanelSheet gehängt
## (add_content) — Skalierung kommt als `f` aus UiScale.for_viewport.
##
## Häkchen-Animation: mark_claimed() tauscht den Abholen-Knopf gegen ein
## Stempel-Häkchen (MotionKit.stempel — W21-Grammatik §6.3: EIN Effekt pro
## Moment) — der „Check“-Moment aus der Aufgabe, ohne das Brett neu zu bauen.

signal claim_pressed(id: String)
signal reroll_pressed

const ICON_DIR := "res://assets/ui/icons/"
## Kategorie → Icon + Identitätsfarbe (AC-Kategorien-Farbwelt).
const KATEGORIE_STYLE := {
	"care": {"icon": "rabbit", "tint": AcTokens.PINK},
	"games": {"icon": "gamepad", "tint": AcTokens.TEAL},
	"garden": {"icon": "leaf", "tint": AcTokens.LEAF_DARK},
	"economy": {"icon": "coin", "tint": AcTokens.YELLOW_DARK},
}
## Zeilen-/Karten-Abstand im Blatt (Design-px, Spacing-Grid-Vielfaches).
const LISTEN_ABSTAND := 12.0

var _rows: Dictionary = {}
## Frisch gebaute Quest-Karten für den Stagger-Auftritt beim Einhängen.
var _karten: Array = []
var _bonus_label: Label
var _reroll_btn: Button
## W20 B3: die Reroll-Zeile als eigenes Control — der Service pinnt sie via
## `PanelSheet.add_footer(footer_control())` UNTER den Scroll (immer
## erreichbar). Standalone (Tests) bleibt sie normales Listen-Ende.
var _reroll_zeile: Control
var _f := 1.0


## G4/P23 — das Panel wird erst NACH rebuild() ins Sheet gehängt (Service-
## Reihenfolge open_panel): den physischen Touch-Floor mit echten
## Viewport-Metriken nachziehen, sobald der Baum steht. W21: dito für die
## Theme-Schriften — außerhalb des Baums lösen Variationen (CaptionLabel 15)
## nicht auf und scale_fonts würde falsche Basis-px (20) einfrieren.
## DEFERRED, weil die KINDER beim _enter_tree des Panels selbst noch nicht
## im Baum hängen (Parent-first-Reihenfolge) — gleiche Falle.
func _enter_tree() -> void:
	_apply_touch_floor()
	call_deferred("_skaliere_schriften")
	call_deferred("_stagger_karten")


func rebuild(board: Array, bonus: Dictionary, reroll_available: bool, f: float) -> void:
	_f = maxf(f, 0.5)
	_rows.clear()
	_karten.clear()
	for child in get_children():
		child.queue_free()
	add_theme_constant_override("separation", AcTokens.px(LISTEN_ABSTAND, _f))
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
		_skaliere_schriften()
		return
	for row: Dictionary in board:
		var karte := _build_row(row)
		_karten.append(karte)
		add_child(karte)
	add_child(_build_bonus_row(bonus))
	_reroll_zeile = _build_reroll(reroll_available)
	add_child(_reroll_zeile)
	# W21 („nichts hat die gleiche Größe“): Layout-Maße skalierten hier mit
	# _f, die THEME-SCHRIFTEN aber nie — das Sheet skaliert nur seinen Titel,
	# der Inhalt blieb in Basis-px (Caption 15 statt 25 auf dem Leitgerät).
	_skaliere_schriften()
	_stagger_karten()


## W20 B3 („Neu würfeln unter der Falz“): der Sheet-Halter holt sich die
## Reroll-Zeile hier ab und pinnt sie per add_footer — add_footer hängt sie
## dabei selbst aus dem Panel aus. Nach jedem rebuild() neu abholen (die
## Zeile wird frisch gebaut).
func footer_control() -> Control:
	return _reroll_zeile


## J6 Münzflug: globales Zentrum des Abholen-Knopfs dieser Quest —
## Quelle-Hinweis für RewardFlug (INF, wenn die Zeile fehlt).
func claim_anker(id: String) -> Vector2:
	var row: Dictionary = _rows.get(id, {})
	if row.is_empty() or not (row["claim"] as Control).is_inside_tree():
		return Vector2.INF
	return (row["claim"] as Control).get_global_rect().get_center()


## Häkchen-Moment nach erfolgreichem Claim (Service ruft das statt rebuild).
func mark_claimed(id: String, bonus: Dictionary) -> void:
	var row: Dictionary = _rows.get(id, {})
	if row.is_empty():
		return
	var btn := row["claim"] as Button
	var check := row["check"] as TextureRect
	btn.visible = false
	check.visible = true
	# W21-Stempel-Moment (MotionKit §6.3: EIN Effekt pro Moment — der
	# frühere Zusatz-Sparkle auf der Karte entfällt bewusst).
	MotionKit.stempel(check)
	var bar := row["bar"] as ProgressBar
	bar.value = bar.max_value
	(row["count"] as Label).text = I18nService.t("quests.erledigt")
	_update_bonus(bonus)


func _build_row(row: Dictionary) -> Control:
	var def: Dictionary = row.get("def", {})
	var id := str(def.get("id", ""))
	var style: Dictionary = KATEGORIE_STYLE.get(str(def.get("kategorie", "")), {})
	var card := PanelContainer.new()
	card.name = "Quest" + id.to_pascal_case()
	card.theme_type_variation = "AcCard"
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, AcTokens.px(LISTEN_ABSTAND, _f))
	card.add_child(margin)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", AcTokens.px(LISTEN_ABSTAND, _f))
	margin.add_child(box)
	var icon := TextureRect.new()
	icon.texture = load("%s%s.svg" % [ICON_DIR, str(style.get("icon", "sparkle"))])
	icon.custom_minimum_size = Vector2.ONE * AcTokens.px(AcTokens.ICON_L, _f)
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
	text_box.add_theme_constant_override("separation", AcTokens.px(AcTokens.SPACE_XS, _f))
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
	progress_box.add_theme_constant_override("separation", AcTokens.px(AcTokens.SPACE_S, _f))
	var bar := ProgressBar.new()
	bar.theme_type_variation = "StatEnergy"
	bar.custom_minimum_size = Vector2(
		float(AcTokens.px(96.0, _f)), float(AcTokens.px(AcTokens.BAR_H, _f))
	)
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
	right.add_theme_constant_override("separation", AcTokens.px(AcTokens.SPACE_S, _f))
	var reward := HBoxContainer.new()
	reward.alignment = BoxContainer.ALIGNMENT_CENTER
	reward.add_theme_constant_override("separation", AcTokens.px(AcTokens.SPACE_XS, _f))
	var coin := TextureRect.new()
	coin.texture = load("res://assets/ui/coin.png")
	coin.custom_minimum_size = Vector2.ONE * AcTokens.px(AcTokens.ICON_S, _f)
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
	# Hero-Icon-Größe (ICON_XL): das Häkchen IST der Stempel-Moment.
	check.custom_minimum_size = Vector2.ONE * AcTokens.px(AcTokens.ICON_XL, _f)
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
	box.add_theme_constant_override("separation", AcTokens.px(AcTokens.SPACE_S, _f))
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


## W21: Theme-Schriften des Inhalts × _f — NUR im Baum (sonst falsche
## Basis, s. _enter_tree). Die Reroll-Zeile hängt nach add_footer als
## Blatt-Fuß AUSSERHALB dieses Teilbaums und wird separat skaliert
## (scale_fonts ist idempotent, doppelt besucht schadet nicht).
func _skaliere_schriften() -> void:
	if not is_inside_tree():
		return
	ScreenShell.scale_fonts(self, _f)
	if (
		_reroll_zeile != null
		and is_instance_valid(_reroll_zeile)
		and _reroll_zeile.is_inside_tree()
	):
		ScreenShell.scale_fonts(_reroll_zeile, _f)


func _apply_touch_floor() -> void:
	for row: Dictionary in _rows.values():
		var claim: Variant = row.get("claim")
		if is_instance_valid(claim):
			_lift_to_touch_floor(claim as Control)
	if _reroll_btn != null and is_instance_valid(_reroll_btn):
		_lift_to_touch_floor(_reroll_btn)


## W21 (c): gestaffelter Karten-Auftritt beim Öffnen des Blatts
## (MotionKit.stagger_ein, Reduced-Motion-gated im Kit). rebuild() läuft
## VOR add_content — außerhalb des Baums macht das Kit alles sichtbar,
## _enter_tree holt den Auftritt mit echtem Baum nach.
func _stagger_karten() -> void:
	if not is_inside_tree() or _karten.is_empty():
		return
	var lebendig: Array = []
	for karte: Control in _karten:
		if is_instance_valid(karte) and karte.is_inside_tree():
			lebendig.append(karte)
	MotionKit.stagger_ein(lebendig)

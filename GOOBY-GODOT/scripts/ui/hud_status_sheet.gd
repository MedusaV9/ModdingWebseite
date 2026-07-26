class_name HudStatusSheet
extends RefCounted
## Inhalt des Status-Detail-Sheets (W4/POLISH-4): Tap auf eine
## Status-Kapsel öffnet ein PanelSheet mit den 4 Stats in GROSS —
## Icon + Name + Balken + Wert, plus Buff-Chip, wenn ein Event-Buff
## (W3d `GoobyBuffs.stat_bonus`) gerade auf die Stat wirkt.
##
## Reiner Builder (RefCounted, statisch): das HUD besitzt das Sheet,
## dieser Baustein liefert nur Daten-Snapshot + Node-Baum — headless
## testbar ohne GameState (Boni-Dict wird hereingereicht).

const ICON_DIR := "res://assets/ui/icons/"
## Feste Zeilenbreite in Design-px, WENN der Buff-Chip mit in der Zeile
## sitzt (Icon 34 + Name 110 + Balken-Minimum 90 + Wert 44 + Chip ~92 +
## 4 Abstände à 12) — passt das nicht in `avail_width`, rückt der Chip
## unter den Stat-Namen (FIX1, schmale Hochkant-Sheets).
const MIN_ROW_WITH_CHIP := 418.0
## HUD-Stat-Id ↔ GameState-Stat-Key (gooby.stats/buffs nutzen die
## englischen Keys aus dem Save-Schema v5).
const STATS: Array[Dictionary] = [
	{
		"id": "hunger",
		"state": "hunger",
		"icon": "hunger",
		"type": "StatHunger",
		"label_key": "hud.stat_hunger",
		"color": AcTokens.STAT_HUNGER,
	},
	{
		"id": "energie",
		"state": "energy",
		"icon": "energy",
		"type": "StatEnergy",
		"label_key": "hud.stat_energie",
		"color": AcTokens.STAT_ENERGY,
	},
	{
		"id": "hygiene",
		"state": "hygiene",
		"icon": "hygiene",
		"type": "StatHygiene",
		"label_key": "hud.stat_hygiene",
		"color": AcTokens.STAT_HYGIENE,
	},
	{
		"id": "spass",
		"state": "fun",
		"icon": "fun",
		"type": "StatFun",
		"label_key": "hud.stat_spass",
		"color": AcTokens.STAT_FUN,
	},
]


## Sheet-Titel (Key kommt via P4 in strings/, bis dahin Fallback —
## handoffs/W4P2-strings-request.md).
static func title_text() -> String:
	return _text("hud.sheet_titel", "Gooby-Status")


## Aktive Buff-Boni pro HUD-Stat-Id aus dem `buffs`-Save-Slice
## (Duck-Typing auf GameState; null/ohne Slice → keine Boni).
static func stat_boni(gs: Object, now_ms: int) -> Dictionary:
	var boni: Dictionary = {}
	if gs == null or not gs.has_method("get_value"):
		return boni
	var slice: Variant = gs.get_value("buffs", {})
	if not (slice is Dictionary) or (slice as Dictionary).is_empty():
		return boni
	for info in STATS:
		var bonus := GoobyBuffs.stat_bonus(slice, str(info["state"]), now_ms)
		if not is_zero_approx(bonus):
			boni[info["id"]] = bonus
	return boni


## Node-Baum des Sheet-Inhalts. `stats` = HUD-Werte {hunger, energie,
## hygiene, spass: 0..100}, `boni` = Ergebnis von stat_boni(). `ui_scale`
## skaliert Größen/Fonts (zentrale Regel `UiScale.for_viewport`, 1.0 =
## Basis). `avail_width` = nutzbare Innenbreite des Sheets in Canvas-px
## (`PanelSheetLayout.sheet_width - PanelSheet.chrome_width`; 0 = egal) —
## FIX1: der Inhalt darf NIE breiter bauen, sonst schneidet das nur
## vertikal scrollende Sheet die Wert-Spalte ab (Hochkant-Befund).
static func build_content(
	stats: Dictionary, boni: Dictionary, ui_scale := 1.0, avail_width := 0.0
) -> Control:
	var rows := VBoxContainer.new()
	rows.name = "StatRows"
	rows.add_theme_constant_override("separation", int(14 * ui_scale))
	var width := 460.0 * ui_scale
	if avail_width > 0.0:
		width = minf(width, avail_width)
	rows.custom_minimum_size = Vector2(width, 0)
	for info in STATS:
		rows.add_child(_build_row(info, stats, boni, ui_scale, avail_width))
	return rows


static func _build_row(
	info: Dictionary, stats: Dictionary, boni: Dictionary, ui_scale: float, avail_width := 0.0
) -> Control:
	var id := str(info["id"])
	var value := clampf(float(stats.get(id, 0.0)), 0.0, 100.0)
	var row := HBoxContainer.new()
	row.name = "Row" + id.capitalize()
	row.add_theme_constant_override("separation", int(12 * ui_scale))
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = load("%s%s.svg" % [ICON_DIR, info["icon"]])
	icon.custom_minimum_size = Vector2.ONE * roundf(34.0 * ui_scale)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.self_modulate = info["color"]
	row.add_child(icon)
	var label := Label.new()
	label.name = "Name"
	label.theme_type_variation = "SoftLabel"
	label.text = I18nService.t(str(info["label_key"]))
	label.custom_minimum_size = Vector2(110 * ui_scale, 0)
	_scale_font(label, 20, ui_scale)
	# Schmal (Hochkant): Buff-Chip unter den Namen statt hinter den Balken,
	# sonst schnitte das Sheet ihn rechts ab (FIX1).
	var narrow := avail_width > 0.0 and MIN_ROW_WITH_CHIP * ui_scale > avail_width
	if narrow and boni.has(id):
		var name_box := VBoxContainer.new()
		name_box.name = "NameBox"
		name_box.custom_minimum_size = Vector2(110 * ui_scale, 0)
		name_box.add_child(label)
		name_box.add_child(_build_buff_chip(id, float(boni[id]), ui_scale))
		row.add_child(name_box)
	else:
		row.add_child(label)
	var bar := ProgressBar.new()
	bar.name = "SheetBar"
	bar.theme_type_variation = info["type"]
	# Balken-MINIMUM klein halten (er füllt per EXPAND_FILL ohnehin die
	# Restbreite) — das alte 190×f-Minimum sprengte schmale Sheets.
	bar.custom_minimum_size = Vector2(90 * ui_scale, roundf(20.0 * ui_scale))
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = value
	row.add_child(bar)
	var value_label := Label.new()
	value_label.name = "Value"
	value_label.text = str(int(roundf(value)))
	value_label.custom_minimum_size = Vector2(44 * ui_scale, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_scale_font(value_label, 20, ui_scale)
	row.add_child(value_label)
	if not narrow and boni.has(id):
		row.add_child(_build_buff_chip(id, float(boni[id]), ui_scale))
	return row


static func _build_buff_chip(id: String, bonus: float, ui_scale: float) -> Control:
	var chip := PanelContainer.new()
	chip.name = "Buff" + id.capitalize()
	chip.theme_type_variation = "AcChip"
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var label := Label.new()
	label.name = "BuffValue"
	label.theme_type_variation = "CaptionLabel"
	var wert := "%+d" % int(roundf(bonus))
	label.text = _text("hud.sheet_buff", "{wert} Buff").format({"wert": wert})
	label.add_theme_color_override("font_color", AcTokens.YELLOW_DARK)
	_scale_font(label, 15, ui_scale)
	chip.add_child(label)
	return chip


## Font nur bei echtem Hochkant-Scale überschreiben — bei 1.0 bleibt die
## Theme-Größe (FIX-A liefert das globale Theme) unangetastet.
static func _scale_font(ctl: Control, base_px: int, ui_scale: float) -> void:
	if ui_scale > 1.0:
		ctl.add_theme_font_size_override("font_size", int(base_px * ui_scale))


static func _text(key: String, fallback: String) -> String:
	return I18nService.t(key) if I18nService.has_key(key) else fallback

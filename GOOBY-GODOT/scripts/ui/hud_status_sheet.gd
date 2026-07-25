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
## hygiene, spass: 0..100}, `boni` = Ergebnis von stat_boni().
static func build_content(stats: Dictionary, boni: Dictionary) -> Control:
	var rows := VBoxContainer.new()
	rows.name = "StatRows"
	rows.add_theme_constant_override("separation", 14)
	rows.custom_minimum_size = Vector2(460, 0)
	for info in STATS:
		rows.add_child(_build_row(info, stats, boni))
	return rows


static func _build_row(info: Dictionary, stats: Dictionary, boni: Dictionary) -> Control:
	var id := str(info["id"])
	var value := clampf(float(stats.get(id, 0.0)), 0.0, 100.0)
	var row := HBoxContainer.new()
	row.name = "Row" + id.capitalize()
	row.add_theme_constant_override("separation", 12)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = load("%s%s.svg" % [ICON_DIR, info["icon"]])
	icon.custom_minimum_size = Vector2(34, 34)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.self_modulate = info["color"]
	row.add_child(icon)
	var label := Label.new()
	label.name = "Name"
	label.theme_type_variation = "SoftLabel"
	label.text = I18nService.t(str(info["label_key"]))
	label.custom_minimum_size = Vector2(110, 0)
	row.add_child(label)
	var bar := ProgressBar.new()
	bar.name = "SheetBar"
	bar.theme_type_variation = info["type"]
	bar.custom_minimum_size = Vector2(190, 20)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = value
	row.add_child(bar)
	var value_label := Label.new()
	value_label.name = "Value"
	value_label.text = str(int(roundf(value)))
	value_label.custom_minimum_size = Vector2(44, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	if boni.has(id):
		row.add_child(_build_buff_chip(id, float(boni[id])))
	return row


static func _build_buff_chip(id: String, bonus: float) -> Control:
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
	chip.add_child(label)
	return chip


static func _text(key: String, fallback: String) -> String:
	return I18nService.t(key) if I18nService.has_key(key) else fallback

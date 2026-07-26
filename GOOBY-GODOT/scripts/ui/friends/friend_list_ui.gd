class_name FriendListUi
extends RefCounted
## Gemeinsame Optik-Helfer für FriendsScreen + SocialScreen (W4-P4 POLISH):
## Presence-Icons aus `assets/ui/icons` (authored SVGs statt Emojis),
## Status-Chip-Styling (grüner Chip online, grauer Chip offline — sichtbare
## Offline-Degradation) und der Text-Leerzustand mit Mini-Hasen-Illustration.
## Presence-LABEL kommt weiterhin vom Server (presence.js); hier wird nur das
## passende Icon zum `activity.kind` gewählt + der Fallback-Text gebaut.

const ICON_DIR := "res://assets/ui/icons"
## `activity.kind` (Server-Kontrakt, presence.js) → Icon-Dateiname ohne .svg.
const KIND_ICONS := {
	"online": "sparkle",
	"home": "home",
	"park": "fun",
	"city": "arrow_right",
	"ikea": "wrench",
	"garden": "rabbit",
	"visit": "home",
	"board": "gamepad",
	"drive": "arrow_right",
	"vacation": "suitcase",
	"sleep": "moon",
}
const FALLBACK_ICON := "rabbit"
const OFFLINE_ICON := "moon"
const COLOR_ONLINE := Color(0.35, 0.75, 0.45)
const COLOR_CONNECTING := Color(0.72, 0.55, 0.2)
const COLOR_OFFLINE := Color(0.7, 0.68, 0.62)
const COLOR_HINT := Color(0.62, 0.45, 0.34)


## Icon-Name für einen Presence-Kind (minigame:* → gamepad).
static func icon_name(kind: String) -> String:
	if kind.begins_with("minigame:"):
		return "gamepad"
	return str(KIND_ICONS.get(kind, FALLBACK_ICON))


## Fertiges, eingefärbtes Presence-Icon für eine Freundeszeile.
static func presence_icon(row: Dictionary) -> TextureRect:
	var online: bool = row.get("online", false) == true
	var kind := "online"
	if online and row.get("activity") is Dictionary:
		kind = str((row["activity"] as Dictionary).get("kind", "online"))
	var icon := TextureRect.new()
	var file := icon_name(kind) if online else OFFLINE_ICON
	icon.texture = load("%s/%s.svg" % [ICON_DIR, file])
	icon.custom_minimum_size = Vector2(20, 20)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.self_modulate = COLOR_ONLINE if online else COLOR_OFFLINE
	return icon


## Presence-Text: Server-Label, sonst Fallback aus den Strings.
static func presence_text(row: Dictionary) -> String:
	var online: bool = row.get("online", false) == true
	if not online:
		return I18nService.t("net.friends.offline")
	var label := ""
	if row.get("activity") is Dictionary:
		label = str((row["activity"] as Dictionary).get("label", ""))
	return label if not label.is_empty() else I18nService.t("net.friends.online")


## Status-Chip (nicht klickbarer Button): ChipLeaf online, grauer AcChip
## offline/verbindend — macht die Offline-Degradation sofort sichtbar.
static func style_status_chip(chip: Button, status: int) -> void:
	chip.focus_mode = Control.FOCUS_NONE
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	match status:
		NetClient.Status.ONLINE:
			chip.theme_type_variation = &"ChipLeaf"
			chip.text = I18nService.t("net.status.online")
			chip.icon = load("%s/check.svg" % ICON_DIR)
			chip.remove_theme_color_override("font_color")
		NetClient.Status.CONNECTING:
			chip.theme_type_variation = &"AcChip"
			chip.text = I18nService.t("net.status.connecting")
			chip.icon = null
			chip.add_theme_color_override("font_color", COLOR_CONNECTING)
		_:
			chip.theme_type_variation = &"AcChip"
			chip.text = I18nService.t("net.status.offline")
			chip.icon = load("%s/close.svg" % ICON_DIR)
			chip.add_theme_color_override("font_color", COLOR_OFFLINE)
	chip.add_theme_color_override("icon_normal_color", chip.get_theme_color("font_color"))


## Text-Leerzustand: Mini-Hasen-ASCII (aus den Strings) + Hinweiszeile.
## `ui_scale` > 1 skaliert die Fonts (FIX1, zentrale UiScale-Regel).
static func build_empty_state(art_key: String, text_key: String, ui_scale := 1.0) -> Control:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", int(4 * ui_scale))
	var art := Label.new()
	art.text = I18nService.t(art_key)
	art.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	art.add_theme_color_override("font_color", COLOR_OFFLINE)
	if ui_scale > 1.0:
		art.add_theme_font_size_override("font_size", int(16 * ui_scale))
	box.add_child(art)
	var text := Label.new()
	text.theme_type_variation = &"CaptionLabel"
	text.text = I18nService.t(text_key)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ui_scale > 1.0:
		text.add_theme_font_size_override("font_size", int(15 * ui_scale))
	box.add_child(text)
	return box

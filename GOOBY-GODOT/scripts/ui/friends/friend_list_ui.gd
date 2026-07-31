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


## Presence-Text (P6 H12): bekannte `activity.kind`s werden CLIENT-seitig
## übersetzt (net.presence.<kind> in strings/de|en/net.json — der EN-Client
## zeigte sonst die deutschen Server-Labels). Unbekannte Kinds fallen aufs
## Server-Label zurück (abwärtskompatibel, Server bleibt unverändert).
static func presence_text(row: Dictionary) -> String:
	var online: bool = row.get("online", false) == true
	if not online:
		return I18nService.t("net.friends.offline")
	var activity: Dictionary = {}
	if row.get("activity") is Dictionary:
		activity = row["activity"]
	var translated := presence_text_for_kind(
		str(activity.get("kind", "")), str(row.get("goobyName", ""))
	)
	if not translated.is_empty():
		return translated
	var label := str(activity.get("label", ""))
	return label if not label.is_empty() else I18nService.t("net.friends.online")


## Übersetzung rein aus `kind` + Gooby-Namen ("" == kein i18n-Key vorhanden
## → Aufrufer nimmt das Server-Label). `minigame:<id>` reist mit der rohen
## Spiel-Id — exakt wie das Server-Template (presence.js).
static func presence_text_for_kind(kind: String, gooby_name: String) -> String:
	if kind.is_empty():
		return ""
	var args := {"gooby": gooby_name if not gooby_name.is_empty() else "Gooby"}
	if kind.begins_with("minigame:"):
		args["name"] = kind.substr("minigame:".length())
		return I18nService.t("net.presence.minigame", args)
	var key := "net.presence.%s" % kind
	if not I18nService.has_key(key):
		return ""
	return I18nService.t(key, args)


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


## Leerzustand mit Charme (UIFINAL): Hase im weichen Kreis-Well statt
## ASCII-Zeichen — der `_art_key` bleibt für die Aufrufer-Signatur erhalten.
## `ui_scale` skaliert Maße/Fonts (FIX1, zentrale UiScale-Regel).
static func build_empty_state(_art_key: String, text_key: String, ui_scale := 1.0) -> Control:
	var s := maxf(ui_scale, 1.0)
	var box := VBoxContainer.new()
	box.name = "EmptyState"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", int(12 * s))
	# Luft nach oben/unten — der Leerzustand darf ruhig atmen.
	var top_pad := Control.new()
	top_pad.custom_minimum_size = Vector2(0.0, 24.0 * s)
	box.add_child(top_pad)
	var well_row := HBoxContainer.new()
	well_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(well_row)
	# Winkender Gooby als „Sticker-Karte“ — die Illustration bringt den
	# Charme, die Paper-Karte rahmt sie wie im Sticker-Album.
	var well := PanelContainer.new()
	var well_style := StyleBoxFlat.new()
	well_style.bg_color = AcTokens.PAPER
	well_style.set_corner_radius_all(AcTokens.RADIUS_CARD)
	well_style.set_content_margin_all(10.0 * s)
	well_style.shadow_color = AcTokens.SHADOW_SOFT_COLOR
	well_style.shadow_size = AcTokens.SHADOW_SOFT_SIZE
	well_style.shadow_offset = Vector2(0.0, AcTokens.SHADOW_SOFT_OFFSET_Y)
	well.add_theme_stylebox_override("panel", well_style)
	well_row.add_child(well)
	var art := TextureRect.new()
	art.texture = load("res://assets/ui/motif_gooby_wave.png")
	art.custom_minimum_size = Vector2.ONE * roundf(120.0 * s)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	well.add_child(art)
	var text := Label.new()
	text.theme_type_variation = &"SoftLabel"
	text.text = I18nService.t(text_key)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("font_size", int(17 * s))
	# `s` steckt schon in der Schrift — Screens, die zusätzlich pauschal
	# `ScreenShell.scale_fonts` fahren (FriendsScreen), dürfen hier nicht
	# noch einmal multiplizieren (Runde-2-Befund: Mini-Sticker/Doppel-Skala).
	text.set_meta(ScreenShell.META_FONT_SKIP, true)
	box.add_child(text)
	var bottom_pad := Control.new()
	bottom_pad.custom_minimum_size = Vector2(0.0, 16.0 * s)
	box.add_child(bottom_pad)
	return box

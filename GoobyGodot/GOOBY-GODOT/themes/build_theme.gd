extends SceneTree
## AC-2.0-Theme-Builder. Baut `res://themes/ac_theme.tres` PROGRAMMATISCH aus
## den Tokens (`themes/tokens.gd`) — eine Quelle, kein Farb-Drift.
## Headless ausführen: `godot --headless --script res://themes/build_theme.gd`
## (vorher einmal `godot --headless --import`, damit Font/Icons importiert sind).
##
## Die statische `build()`-API wird auch von Tests + ThemeService genutzt.

const THEME_PATH := "res://themes/ac_theme.tres"


func _init() -> void:
	var theme := build()
	var err := ResourceSaver.save(theme, THEME_PATH)
	if err != OK:
		push_error("ac_theme.tres konnte nicht gespeichert werden: %s" % err)
		quit(1)
		return
	print("ac_theme.tres geschrieben (%d Theme-Typen)" % theme.get_type_list().size())
	quit(0)


## Baut das komplette Theme in-memory (nutzbar ohne .tres, z. B. in Tests).
static func build() -> Theme:
	var theme := Theme.new()
	var base_font: Font = load(AcTokens.FONT_PATH)
	if base_font == null:
		push_warning("Baloo-2-Font nicht importiert — Theme nutzt Fallback-Font.")
	else:
		theme.default_font = _weight(base_font, 600)
	theme.default_font_size = AcTokens.FONT_SIZE_BODY

	_build_buttons(theme, base_font)
	_build_panels(theme)
	_build_w21_rollen(theme)
	_build_labels(theme, base_font)
	_build_progress_bars(theme)
	_build_sliders(theme)
	_build_scrollbars(theme)
	_build_inputs(theme, base_font)
	_build_tabs(theme, base_font)
	_build_misc(theme)
	return theme


static func _weight(base_font: Font, weight: int) -> FontVariation:
	var v := FontVariation.new()
	v.base_font = base_font
	v.variation_opentype = {"wght": weight}
	return v


## Pill-StyleBox mit AC-„Boden-Lippe“ (ersetzt den CSS-Inset-Shadow).
## UICOZY: + weicher Drop-Shadow wie Web `.btn` (0 3px 10px rgba(74,59,54,.12)).
static func _pill(fill: Color, lip: int = 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(AcTokens.RADIUS_PILL)
	sb.border_width_bottom = lip
	sb.border_color = AcTokens.lip_color(fill)
	sb.content_margin_left = 26.0
	sb.content_margin_right = 26.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0 + float(lip)
	sb.shadow_color = AcTokens.SHADOW_BTN_COLOR
	sb.shadow_size = AcTokens.SHADOW_BTN_SIZE
	sb.shadow_offset = Vector2(0.0, AcTokens.SHADOW_BTN_OFFSET_Y)
	return sb


static func _card(fill: Color, radius: int, shadow: bool, outline := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(18.0)
	if shadow:
		sb.shadow_color = AcTokens.SHADOW_COLOR
		sb.shadow_size = AcTokens.SHADOW_SIZE
		sb.shadow_offset = Vector2(0.0, AcTokens.SHADOW_OFFSET_Y)
	if outline:
		sb.border_color = AcTokens.OUTLINE_SOFT
		sb.set_border_width_all(2)
	return sb


## Ein Button-Variationstyp: normal/hover/pressed/disabled + Textfarben.
## W20/P4 Disabled-Kontrast (Befund E6 „weiß-auf-blassgrün kaum lesbar“):
## Deaktivierte Knöpfe sind EHRLICH ausgegraut (opakes Blend Richtung
## Paper-Shade statt 50 % Alpha über wechselnden Hintergründen), der Text
## bleibt aber LESBAR — dunkle Ink-Tinte statt der halbtransparenten
## Fill-Textfarbe (weißer Text auf blassem Fill fiel unter jede Kontrast-
## Schwelle). Gilt zentral für ALLE Pill-Varianten.
static func _button_set(theme: Theme, type: String, fill: Color, text: Color) -> void:
	if type != "Button":
		theme.set_type_variation(type, "Button")
	var normal := _pill(fill)
	var hover := _pill(fill.lightened(0.04))
	var pressed := _pill(fill, 2)
	pressed.content_margin_top = 12.0
	pressed.content_margin_bottom = 10.0
	# Gedrückt = Web --shadow-press (0 2px 6px .16): sichtbar „abgesetzt“.
	pressed.shadow_color = AcTokens.SHADOW_PRESS_COLOR
	pressed.shadow_size = AcTokens.SHADOW_PRESS_SIZE
	pressed.shadow_offset = Vector2(0.0, 2.0)
	var disabled_fill := Color(fill.r, fill.g, fill.b, fill.a).lerp(AcTokens.PAPER_SHADE, 0.72)
	var disabled := _pill(disabled_fill, 2)
	disabled.border_color = Color(AcTokens.INK, 0.10)
	disabled.shadow_color = Color(AcTokens.SHADOW_BTN_COLOR, 0.0)
	theme.set_stylebox("normal", type, normal)
	theme.set_stylebox("hover", type, hover)
	theme.set_stylebox("pressed", type, pressed)
	theme.set_stylebox("disabled", type, disabled)
	var focus := StyleBoxEmpty.new()
	theme.set_stylebox("focus", type, focus)
	for state in ["font_color", "font_hover_color", "font_focus_color"]:
		theme.set_color(state, type, text)
	theme.set_color("font_pressed_color", type, text)
	theme.set_color("font_disabled_color", type, Color(AcTokens.INK, 0.62))
	theme.set_color("icon_normal_color", type, text)
	theme.set_color("icon_hover_color", type, text)
	theme.set_color("icon_pressed_color", type, text)
	theme.set_color("icon_disabled_color", type, Color(AcTokens.INK, 0.62))
	theme.set_constant("h_separation", type, 8)
	theme.set_font_size("font_size", type, AcTokens.FONT_SIZE_BUTTON)


static func _build_buttons(theme: Theme, base_font: Font) -> void:
	# Basis-Button = „BtnGhost“: Paper-Pill mit weicher Outline, Ink-Text.
	_button_set(theme, "Button", AcTokens.PAPER, AcTokens.INK)
	var ghost_normal := theme.get_stylebox("normal", "Button") as StyleBoxFlat
	ghost_normal.border_color = AcTokens.OUTLINE_SOFT
	ghost_normal.border_width_top = 2
	ghost_normal.border_width_left = 2
	ghost_normal.border_width_right = 2
	if base_font != null:
		theme.set_font("font", "Button", _weight(base_font, 700))
	# Identitäts-Varianten (H §1.1).
	_button_set(theme, "BtnPink", AcTokens.PINK, AcTokens.WHITE)
	_button_set(theme, "BtnTeal", AcTokens.TEAL, AcTokens.WHITE)
	_button_set(theme, "BtnLeaf", AcTokens.LEAF, AcTokens.WHITE)
	_leaf_glow(theme, "BtnLeaf")
	_button_set(theme, "BtnYellow", AcTokens.YELLOW, AcTokens.INK)
	_button_set(theme, "BtnGhost", AcTokens.PAPER, AcTokens.INK)
	_button_set(theme, "BtnDanger", AcTokens.DANGER, AcTokens.WHITE)
	# Semantik-Varianten (E7-P0-1): W2+-Code setzt PrimaryButton/AccentButton/
	# GhostButton — die Namen MÜSSEN im Theme existieren, sonst fällt Godot
	# still auf die Paper-Basis zurück (46 tote Referenzen in 19 Dateien).
	_button_set(theme, "PrimaryButton", AcTokens.TEAL, AcTokens.WHITE)
	_button_set(theme, "AccentButton", AcTokens.PINK, AcTokens.WHITE)
	_build_ghost_button(theme)
	_build_card_button(theme)
	# Chips: 40 px hoch, Paper + Outline (H §1.1), Leaf-/Sky-Varianten.
	_button_set(theme, "AcChip", AcTokens.PAPER, AcTokens.INK)
	_chipify(theme, "AcChip")
	_button_set(theme, "ChipLeaf", AcTokens.LEAF, AcTokens.WHITE)
	_chipify(theme, "ChipLeaf")
	_leaf_glow(theme, "ChipLeaf", 4)
	_button_set(theme, "ChipSky", AcTokens.SKY_SOFT, AcTokens.INK)
	_chipify(theme, "ChipSky")
	# HUD-Icon-Buttons: runde Frost-Kacheln überm 3D-Raum, Ink-Icons.
	# UICOZY (Web .g5-hud-btn): 4-px-Boden-Lippe rgba(74,59,54,.14) + weicher
	# --shadow-soft statt des harten Press-Schattens — „rund und griffig“.
	_button_set(theme, "HudIconButton", AcTokens.FROST, AcTokens.INK)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := theme.get_stylebox(state, "HudIconButton") as StyleBoxFlat
		sb.set_content_margin_all(14.0)
		sb.border_width_bottom = 4
		sb.border_color = AcTokens.HUD_BTN_LIP
		sb.shadow_color = AcTokens.SHADOW_SOFT_COLOR
		sb.shadow_size = AcTokens.SHADOW_SOFT_SIZE
		sb.shadow_offset = Vector2(0.0, AcTokens.SHADOW_SOFT_OFFSET_Y)
		if state == "pressed":
			sb.content_margin_top = 16.0
			sb.content_margin_bottom = 12.0
			sb.border_width_bottom = 2
			sb.shadow_color = AcTokens.SHADOW_PRESS_COLOR
			sb.shadow_size = AcTokens.SHADOW_PRESS_SIZE
			sb.shadow_offset = Vector2(0.0, 2.0)
	theme.set_constant("icon_max_width", "HudIconButton", 44)


## Farbiger Leaf-Glow statt grauem Ink-Schatten (Web .btn-leaf/.ac-chip-leaf:
## 0 3px 10px rgba(109,181,78,.35)) — nur für den Normal-/Hover-Zustand.
static func _leaf_glow(theme: Theme, type: String, size := AcTokens.SHADOW_BTN_SIZE) -> void:
	for state in ["normal", "hover"]:
		var sb := theme.get_stylebox(state, type) as StyleBoxFlat
		sb.shadow_color = AcTokens.SHADOW_LEAF_GLOW
		sb.shadow_size = size


## „GhostButton“ (E7-P0-1): transparente Pill mit weicher Ink-Umriss-Linie.
## Bewusst KEIN Paper-Alias — Sekundär-Aktionen („Zurück“) müssen sich sichtbar
## von Primär-/Akzent-CTAs unterscheiden (E7: „Spielen!“ = „Zurück“-Problem).
static func _build_ghost_button(theme: Theme) -> void:
	_button_set(theme, "GhostButton", Color(AcTokens.PAPER, 0.0), AcTokens.INK)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := theme.get_stylebox(state, "GhostButton") as StyleBoxFlat
		sb.set_border_width_all(2)
		sb.border_color = AcTokens.INK_FAINT
		sb.content_margin_top = 12.0
		sb.content_margin_bottom = 12.0
	var hover := theme.get_stylebox("hover", "GhostButton") as StyleBoxFlat
	hover.bg_color = AcTokens.TRACK_SOFT
	var pressed := theme.get_stylebox("pressed", "GhostButton") as StyleBoxFlat
	pressed.bg_color = AcTokens.TRACK_SOFT
	pressed.content_margin_top = 14.0
	pressed.content_margin_bottom = 10.0
	var disabled := theme.get_stylebox("disabled", "GhostButton") as StyleBoxFlat
	disabled.bg_color = Color(AcTokens.PAPER, 0.0)
	disabled.border_color = Color(AcTokens.INK_FAINT, 0.25)
	# UIFINAL-Guardrail: Ghost-Buttons tragen kleine Glyphen (×, ‹) — die
	# authored SVGs sind aber 96 px groß. Ungedeckelt sprengte das den Knopf
	# (FB3-Regression „Riesen-X“ im Was-nun-Hinweis); Screens dürfen den
	# Deckel per Override weiter mit UiScale skalieren.
	theme.set_constant("icon_max_width", "GhostButton", 22)


## „AcCardButton“ (E7-P0-3): Karten-Optik als ECHTE Button-Variation für
## tappbare Kacheln (Arcade/Album/Events). `AcCard` ist eine PanelContainer-
## Variation — auf einem Button fällt sie still auf die Pill-Basis zurück
## (Radius 999 → weiße Ellipsen). Hier: Paper, Radius 28, Shadow-Pop.
static func _build_card_button(theme: Theme) -> void:
	theme.set_type_variation("AcCardButton", "Button")
	var normal := _card(AcTokens.PAPER, AcTokens.RADIUS_CARD, true)
	var hover := _card(AcTokens.PAPER.lightened(0.04), AcTokens.RADIUS_CARD, true)
	var pressed := _card(AcTokens.PAPER, AcTokens.RADIUS_CARD, false)
	pressed.shadow_color = AcTokens.SHADOW_PRESS_COLOR
	pressed.shadow_size = AcTokens.SHADOW_PRESS_SIZE
	pressed.shadow_offset = Vector2(0.0, 2.0)
	pressed.content_margin_top = 20.0
	pressed.content_margin_bottom = 16.0
	var disabled := _card(Color(AcTokens.PAPER, 0.5), AcTokens.RADIUS_CARD, false)
	theme.set_stylebox("normal", "AcCardButton", normal)
	theme.set_stylebox("hover", "AcCardButton", hover)
	theme.set_stylebox("pressed", "AcCardButton", pressed)
	theme.set_stylebox("disabled", "AcCardButton", disabled)
	theme.set_stylebox("focus", "AcCardButton", StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		theme.set_color(state, "AcCardButton", AcTokens.INK)
	theme.set_color("font_disabled_color", "AcCardButton", Color(AcTokens.INK, 0.6))
	# Icons UNGETÖNT lassen (weiß = keine Modulation): Kacheln tragen bunte
	# Cover-Art, kein monochromes Glyph wie die Pill-Buttons.
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		theme.set_color(state, "AcCardButton", AcTokens.WHITE)
	theme.set_color("icon_disabled_color", "AcCardButton", Color(AcTokens.WHITE, 0.6))
	theme.set_font_size("font_size", "AcCardButton", AcTokens.FONT_SIZE_BUTTON)


static func _chipify(theme: Theme, type: String) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := theme.get_stylebox(state, type) as StyleBoxFlat
		sb.content_margin_left = 16.0
		sb.content_margin_right = 16.0
		sb.content_margin_top = 5.0
		sb.content_margin_bottom = 7.0
		# UICOZY: Chips tragen den kleineren Web-Schatten (0 2px 6px .10).
		sb.shadow_color = Color(AcTokens.INK, 0.10)
		sb.shadow_size = 3
		sb.shadow_offset = Vector2(0.0, 2.0)
		if state == "pressed":
			sb.content_margin_top = 7.0
			sb.content_margin_bottom = 5.0
		if type == "AcChip":
			sb.border_color = AcTokens.OUTLINE_SOFT
			sb.set_border_width_all(2)
	# W21/ACNH: Chip-Text aus der Typo-Skala (SIZE_CAPTION) — löst die zwei
	# gemessenen Chip-Schriftgrößen (Album 15×f vs. Rest 17×f) auf.
	theme.set_font_size("font_size", type, AcTokens.SIZE_CAPTION)
	theme.set_constant("icon_max_width", type, AcTokens.ICON_M)


static func _build_panels(theme: Theme) -> void:
	# Basis-PanelContainer = „AcCard“: Paper, Radius 28, Shadow-Pop.
	var card := _card(AcTokens.PAPER, AcTokens.RADIUS_CARD, true)
	theme.set_stylebox("panel", "PanelContainer", card)
	theme.set_type_variation("AcCard", "PanelContainer")
	theme.set_stylebox("panel", "AcCard", card.duplicate())
	# Große Karte (Sheets): Radius 36.
	theme.set_type_variation("AcCardLg", "PanelContainer")
	theme.set_stylebox("panel", "AcCardLg", _card(AcTokens.PAPER, AcTokens.RADIUS_CARD_LG, true))
	# „AcWell“: Paper-Shade-Inset, Radius 14, kein Schatten.
	theme.set_type_variation("AcWell", "PanelContainer")
	theme.set_stylebox("panel", "AcWell", _card(AcTokens.PAPER_SHADE, AcTokens.RADIUS_ROW, false))
	# Status-Kapsel: Frost-Pill überm Raum. UICOZY: weicher --shadow-soft
	# (0 6px 24px .14, Web .stat-pill/.g5-coins) statt hartem Press-Schatten.
	theme.set_type_variation("StatusCapsule", "PanelContainer")
	var capsule := _card(AcTokens.FROST, AcTokens.RADIUS_PILL, true)
	capsule.shadow_size = AcTokens.SHADOW_SOFT_SIZE
	capsule.shadow_color = AcTokens.SHADOW_SOFT_COLOR
	capsule.shadow_offset = Vector2(0.0, AcTokens.SHADOW_SOFT_OFFSET_Y)
	capsule.content_margin_left = 16.0
	capsule.content_margin_right = 16.0
	capsule.content_margin_top = 8.0
	capsule.content_margin_bottom = 8.0
	theme.set_stylebox("panel", "StatusCapsule", capsule)
	# Mini-Kapsel fürs Hochkant-HUD (H §1.3: „Ring+4 Mini-Bars" — Glance only).
	theme.set_type_variation("StatusCapsuleMini", "PanelContainer")
	var mini := capsule.duplicate() as StyleBoxFlat
	mini.content_margin_left = 10.0
	mini.content_margin_right = 10.0
	mini.content_margin_top = 6.0
	mini.content_margin_bottom = 6.0
	theme.set_stylebox("panel", "StatusCapsuleMini", mini)
	# Dialog-Bubble (Gooby-Sprüche): Paper, dicke runde Ecken, Outline.
	theme.set_type_variation("DialogBubble", "PanelContainer")
	var bubble := _card(AcTokens.PAPER, AcTokens.RADIUS_CARD, true, true)
	bubble.set_content_margin_all(22.0)
	theme.set_stylebox("panel", "DialogBubble", bubble)
	# W21/ACNH P1 Toast-Bubble: Blatt-Sprache — RADIUS_CARD statt der alten
	# 22er-Web-Ausnahme (in test_w21_acnh_skalen gestrichen), Innenränder aus
	# dem Raster (SPACE_M/SPACE_S). Leaf-Glyphe + EINE Höhe macht `toast.gd`.
	theme.set_type_variation("ToastBubble", "PanelContainer")
	var toast := _card(AcTokens.PAPER, AcTokens.RADIUS_CARD, true, true)
	toast.content_margin_left = float(AcTokens.SPACE_M)
	toast.content_margin_right = float(AcTokens.SPACE_M)
	toast.content_margin_top = float(AcTokens.SPACE_S)
	toast.content_margin_bottom = float(AcTokens.SPACE_S)
	theme.set_stylebox("panel", "ToastBubble", toast)
	# Plain Panel: Cream-Wash (Screens ohne Wallpaper).
	var wash := StyleBoxFlat.new()
	wash.bg_color = AcTokens.BG_CREAM
	theme.set_stylebox("panel", "Panel", wash)


## W21/ACNH-Rollen (UI-DESIGN-ACNH §5): StatKapsel-Gruppe + KontextDock.
## Die StatKapsel-Gruppe ist EINE kompakte Frost-Kapsel aus Segmenten —
## Kopf (oben gerundet), Mitte (Hairline-Trenner), Fuss (unten gerundet).
## Segmente stapeln in einer VBox mit Separation 0 (AcnhKit.segment_rollen).
static func _build_w21_rollen(theme: Theme) -> void:
	for segment in ["StatKapselKopf", "StatKapselMitte", "StatKapselFuss"]:
		theme.set_type_variation(segment, "PanelContainer")
		var sb := StyleBoxFlat.new()
		sb.bg_color = AcTokens.FROST
		sb.border_color = AcTokens.OUTLINE_SOFT
		sb.border_width_left = 2
		sb.border_width_right = 2
		sb.content_margin_left = 12.0
		sb.content_margin_right = 12.0
		sb.content_margin_top = 4.0
		sb.content_margin_bottom = 4.0
		if segment == "StatKapselKopf":
			sb.corner_radius_top_left = AcTokens.RADIUS_CARD
			sb.corner_radius_top_right = AcTokens.RADIUS_CARD
			sb.border_width_top = 2
			sb.content_margin_top = 12.0
		else:
			# Leiser Hairline-Trenner zwischen den Segmenten.
			sb.border_width_top = 1
		if segment == "StatKapselFuss":
			sb.corner_radius_bottom_left = AcTokens.RADIUS_CARD
			sb.corner_radius_bottom_right = AcTokens.RADIUS_CARD
			sb.border_width_bottom = 2
			sb.content_margin_bottom = 12.0
		theme.set_stylebox("panel", segment, sb)
	# KontextDock: einklappbare Frost-Leiste an der Bildkante (Baumodus-
	# Lager, Werkzeug-Zeilen) — oben gerundet, weicher Schatten nach oben.
	theme.set_type_variation("KontextDock", "PanelContainer")
	var dock := StyleBoxFlat.new()
	dock.bg_color = AcTokens.FROST
	dock.corner_radius_top_left = AcTokens.RADIUS_CARD
	dock.corner_radius_top_right = AcTokens.RADIUS_CARD
	dock.border_color = AcTokens.OUTLINE_SOFT
	dock.border_width_top = 2
	dock.border_width_left = 2
	dock.border_width_right = 2
	dock.set_content_margin_all(float(AcTokens.SPACE_M))
	dock.content_margin_bottom = float(AcTokens.SPACE_S)
	dock.shadow_color = AcTokens.SHADOW_SOFT_COLOR
	dock.shadow_size = AcTokens.SHADOW_SOFT_SIZE
	dock.shadow_offset = Vector2(0.0, -3.0)
	theme.set_stylebox("panel", "KontextDock", dock)


static func _build_labels(theme: Theme, base_font: Font) -> void:
	theme.set_color("font_color", "Label", AcTokens.INK)
	theme.set_type_variation("TitleLabel", "Label")
	theme.set_font_size("font_size", "TitleLabel", AcTokens.FONT_SIZE_TITLE)
	theme.set_type_variation("HeadlineLabel", "Label")
	theme.set_font_size("font_size", "HeadlineLabel", AcTokens.FONT_SIZE_HEADLINE)
	theme.set_type_variation("CaptionLabel", "Label")
	theme.set_font_size("font_size", "CaptionLabel", AcTokens.FONT_SIZE_CAPTION)
	theme.set_color("font_color", "CaptionLabel", AcTokens.INK_FAINT)
	theme.set_type_variation("SoftLabel", "Label")
	theme.set_color("font_color", "SoftLabel", AcTokens.INK_SOFT)
	if base_font != null:
		theme.set_font("font", "TitleLabel", _weight(base_font, 800))
		theme.set_font("font", "HeadlineLabel", _weight(base_font, 800))
	theme.set_color("default_color", "RichTextLabel", AcTokens.INK)


static func _stat_bar_bg() -> StyleBoxFlat:
	var bg := StyleBoxFlat.new()
	bg.bg_color = AcTokens.TRACK_SOFT
	bg.set_corner_radius_all(AcTokens.RADIUS_PILL)
	return bg


static func _build_progress_bars(theme: Theme) -> void:
	theme.set_stylebox("background", "ProgressBar", _stat_bar_bg())
	var fill := StyleBoxFlat.new()
	fill.bg_color = AcTokens.LEAF
	fill.set_corner_radius_all(AcTokens.RADIUS_PILL)
	theme.set_stylebox("fill", "ProgressBar", fill)
	theme.set_color("font_color", "ProgressBar", AcTokens.INK)
	var stats := {
		"StatHunger": AcTokens.STAT_HUNGER,
		"StatEnergy": AcTokens.STAT_ENERGY,
		"StatHygiene": AcTokens.STAT_HYGIENE,
		"StatFun": AcTokens.STAT_FUN,
	}
	for type: String in stats:
		theme.set_type_variation(type, "ProgressBar")
		theme.set_stylebox("background", type, _stat_bar_bg())
		var f := StyleBoxFlat.new()
		f.bg_color = stats[type]
		f.set_corner_radius_all(AcTokens.RADIUS_PILL)
		theme.set_stylebox("fill", type, f)


static func _build_sliders(theme: Theme) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = AcTokens.TRACK_SOFT
	track.set_corner_radius_all(AcTokens.RADIUS_PILL)
	track.content_margin_top = 7.0
	track.content_margin_bottom = 7.0
	theme.set_stylebox("slider", "HSlider", track)
	var area := StyleBoxFlat.new()
	area.bg_color = AcTokens.TEAL
	area.set_corner_radius_all(AcTokens.RADIUS_PILL)
	theme.set_stylebox("grabber_area", "HSlider", area)
	theme.set_stylebox("grabber_area_highlight", "HSlider", area.duplicate())
	var knob: Texture2D = load("res://assets/ui/icons/slider_knob.svg")
	if knob != null:
		theme.set_icon("grabber", "HSlider", knob)
		theme.set_icon("grabber_highlight", "HSlider", knob)
		theme.set_icon("grabber_disabled", "HSlider", knob)


## W20/P4 AC-Scrollbars (Befund E2 „nackte dunkle Godot-Standard-Scrollbars
## in jedem Scroller“): weiche, sichtbare Scroll-Indikatoren im AC-Look —
## Pill-Grabber in warmer Ink-Tinte auf einer sehr leisen Track-Spur.
## Wirkt ZENTRAL auf alle ScrollContainer/Listen (Album, Garderobe,
## Erfolge, Gestalten, Reise-App, Radio, Bau-Lager …), kein Screen-Eingriff.
static func _build_scrollbars(theme: Theme) -> void:
	for type: String in ["VScrollBar", "HScrollBar"]:
		var vertikal := type == "VScrollBar"
		var track := StyleBoxFlat.new()
		track.bg_color = Color(AcTokens.INK, 0.06)
		track.set_corner_radius_all(AcTokens.RADIUS_PILL)
		# Quer zur Laufrichtung 3 px Luft: der Grabber schwimmt sichtbar
		# IN der Spur (Margins bestimmen zugleich die Leisten-Dicke).
		if vertikal:
			track.content_margin_left = 3.0
			track.content_margin_right = 3.0
		else:
			track.content_margin_top = 3.0
			track.content_margin_bottom = 3.0
		theme.set_stylebox("scroll", type, track)
		theme.set_stylebox("scroll_focus", type, track.duplicate())
		var grabber := StyleBoxFlat.new()
		grabber.bg_color = Color(AcTokens.INK, 0.26)
		grabber.set_corner_radius_all(AcTokens.RADIUS_PILL)
		grabber.set_content_margin_all(4.0)
		var highlight := grabber.duplicate() as StyleBoxFlat
		highlight.bg_color = Color(AcTokens.INK, 0.38)
		var pressed := grabber.duplicate() as StyleBoxFlat
		pressed.bg_color = Color(AcTokens.INK, 0.48)
		theme.set_stylebox("grabber", type, grabber)
		theme.set_stylebox("grabber_highlight", type, highlight)
		theme.set_stylebox("grabber_pressed", type, pressed)


static func _build_inputs(theme: Theme, base_font: Font) -> void:
	var normal := _card(AcTokens.WHITE, AcTokens.RADIUS_ROW, false, true)
	normal.content_margin_left = 16.0
	normal.content_margin_right = 16.0
	normal.content_margin_top = 10.0
	normal.content_margin_bottom = 10.0
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = AcTokens.TEAL
	theme.set_stylebox("normal", "LineEdit", normal)
	theme.set_stylebox("focus", "LineEdit", focus)
	theme.set_color("font_color", "LineEdit", AcTokens.INK)
	theme.set_color("font_placeholder_color", "LineEdit", AcTokens.INK_FAINT)
	theme.set_color("caret_color", "LineEdit", AcTokens.TEAL_DARK)
	theme.set_font_size("font_size", "LineEdit", AcTokens.FONT_SIZE_BUTTON)
	if base_font != null:
		theme.set_font("font", "LineEdit", _weight(base_font, 600))
	# CheckButton → AC-Toggle-Optik.
	var on: Texture2D = load("res://assets/ui/icons/toggle_on.svg")
	var off: Texture2D = load("res://assets/ui/icons/toggle_off.svg")
	if on != null and off != null:
		for key in ["checked", "checked_disabled"]:
			theme.set_icon(key, "CheckButton", on)
		for key in ["unchecked", "unchecked_disabled"]:
			theme.set_icon(key, "CheckButton", off)
	theme.set_color("font_color", "CheckButton", AcTokens.INK)
	theme.set_color("font_hover_color", "CheckButton", AcTokens.INK)
	theme.set_color("font_pressed_color", "CheckButton", AcTokens.INK)
	var flat := StyleBoxEmpty.new()
	flat.set_content_margin_all(6.0)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		theme.set_stylebox(state, "CheckButton", flat)


static func _build_tabs(theme: Theme, base_font: Font) -> void:
	# „AcTabs“: Träger = Paper-Pill, aktiver Tab = Leaf-Pill mit weißem Text.
	# UICOZY: farbiger Leaf-Glow (Web .ac-tab-active: 0 2px 8px rgba(109,181,78,.4)).
	var selected := _pill(AcTokens.LEAF, 3)
	selected.content_margin_left = 20.0
	selected.content_margin_right = 20.0
	selected.content_margin_top = 6.0
	selected.content_margin_bottom = 9.0
	selected.shadow_color = Color(AcTokens.SHADOW_LEAF_GLOW, 0.4)
	selected.shadow_size = 4
	selected.shadow_offset = Vector2(0.0, 2.0)
	var unselected := _pill(Color(AcTokens.PAPER, 0.0), 0)
	unselected.border_width_bottom = 0
	unselected.content_margin_left = 20.0
	unselected.content_margin_right = 20.0
	unselected.content_margin_top = 6.0
	unselected.content_margin_bottom = 9.0
	theme.set_stylebox("tab_selected", "TabBar", selected)
	theme.set_stylebox("tab_hovered", "TabBar", unselected.duplicate())
	theme.set_stylebox("tab_unselected", "TabBar", unselected)
	theme.set_color("font_selected_color", "TabBar", AcTokens.WHITE)
	theme.set_color("font_unselected_color", "TabBar", AcTokens.INK_SOFT)
	theme.set_color("font_hovered_color", "TabBar", AcTokens.INK)
	if base_font != null:
		theme.set_font("font", "TabBar", _weight(base_font, 700))
	var panel := StyleBoxEmpty.new()
	theme.set_stylebox("panel", "TabContainer", panel)
	theme.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())


static func _build_misc(theme: Theme) -> void:
	# Tooltips im Paper-Look.
	var tip := _card(AcTokens.PAPER, AcTokens.RADIUS_ROW, true, true)
	tip.set_content_margin_all(10.0)
	theme.set_stylebox("panel", "TooltipPanel", tip)
	theme.set_color("font_color", "TooltipLabel", AcTokens.INK)
	# OptionButton/PopupMenu minimal ins System geholt.
	var popup := _card(AcTokens.PAPER, AcTokens.RADIUS_ROW, true, true)
	popup.set_content_margin_all(8.0)
	theme.set_stylebox("panel", "PopupMenu", popup)
	theme.set_color("font_color", "PopupMenu", AcTokens.INK)
	theme.set_color("font_hover_color", "PopupMenu", AcTokens.INK)
	var hover := StyleBoxFlat.new()
	hover.bg_color = AcTokens.PAPER_SHADE
	hover.set_corner_radius_all(AcTokens.RADIUS_ROW)
	theme.set_stylebox("hover", "PopupMenu", hover)
	theme.set_color("font_color", "OptionButton", AcTokens.INK)

extends TestCase
## UICOZY: Web-Paritäts-Feinschliff im Theme-Builder — farbige weiche
## Schatten (statt grau), HUD-Knopf-Lippe, ToastBubble-Variation. Zahlenwerte
## 1:1 aus GOOBY/src/ui/styles.css (--shadow-soft/--shadow-press/.btn-leaf).

const BUILDER := preload("res://themes/build_theme.gd")


func test_leaf_glow_farbig_statt_grau() -> void:
	var theme: Theme = BUILDER.build()
	for type in ["BtnLeaf", "ChipLeaf"]:
		var sb := theme.get_stylebox("normal", type) as StyleBoxFlat
		assert_eq(
			sb.shadow_color, AcTokens.SHADOW_LEAF_GLOW, "%s: Glow rgba(109,181,78,.35)" % type
		)


func test_pill_buttons_tragen_btn_schatten() -> void:
	var theme: Theme = BUILDER.build()
	var pink := theme.get_stylebox("normal", "BtnPink") as StyleBoxFlat
	assert_eq(pink.shadow_color, AcTokens.SHADOW_BTN_COLOR, ".btn: 0 3px 10px rgba(74,59,54,.12)")
	assert_eq(pink.shadow_size, AcTokens.SHADOW_BTN_SIZE, "Blur 10 → Size 5")
	var pressed := theme.get_stylebox("pressed", "BtnPink") as StyleBoxFlat
	assert_eq(pressed.shadow_color, AcTokens.SHADOW_PRESS_COLOR, "Pressed: --shadow-press")


func test_hud_icon_button_lippe_und_soft_schatten() -> void:
	var theme: Theme = BUILDER.build()
	var sb := theme.get_stylebox("normal", "HudIconButton") as StyleBoxFlat
	assert_eq(sb.border_width_bottom, 4, ".g5-hud-btn: 4-px-Boden-Lippe")
	assert_eq(sb.border_color, AcTokens.HUD_BTN_LIP, "Lippe rgba(74,59,54,.14)")
	assert_eq(sb.shadow_color, AcTokens.SHADOW_SOFT_COLOR, "--shadow-soft statt hart")
	var pressed := theme.get_stylebox("pressed", "HudIconButton") as StyleBoxFlat
	assert_true(pressed.shadow_size < sb.shadow_size, "Pressed drückt den Schatten zusammen")


func test_status_capsule_soft_schatten() -> void:
	var theme: Theme = BUILDER.build()
	var sb := theme.get_stylebox("panel", "StatusCapsule") as StyleBoxFlat
	assert_eq(sb.shadow_color, AcTokens.SHADOW_SOFT_COLOR, ".stat-pill: --shadow-soft")
	assert_eq(sb.shadow_size, AcTokens.SHADOW_SOFT_SIZE, "Blur 24 → Size 10")


func test_toast_bubble_variation() -> void:
	var theme: Theme = BUILDER.build()
	assert_true(theme.get_type_list().has("ToastBubble"), "ToastBubble-Variation existiert")
	var sb := theme.get_stylebox("panel", "ToastBubble") as StyleBoxFlat
	assert_eq(sb.bg_color, AcTokens.PAPER, ".toast: Paper-Bubble")
	assert_eq(sb.corner_radius_top_left, 22, ".toast: Radius 22")


func test_shipped_tres_ist_regeneriert() -> void:
	# Wichtigster Stolperstein: build_theme.gd ändern reicht NICHT — das
	# Projekt lädt themes/ac_theme.tres. Diese Probe schlägt an, wenn das
	# Regenerieren (godot --headless --script res://themes/build_theme.gd)
	# vergessen wurde.
	var shipped := load("res://themes/ac_theme.tres") as Theme
	if shipped == null:
		return  # isolierter Lauf ohne Import
	assert_true(shipped.get_type_list().has("ToastBubble"), "ToastBubble im shipped Theme")
	var hud := shipped.get_stylebox("normal", "HudIconButton") as StyleBoxFlat
	assert_eq(hud.border_width_bottom, 4, "HUD-Lippe im shipped Theme")
	var leaf := shipped.get_stylebox("normal", "BtnLeaf") as StyleBoxFlat
	assert_eq(leaf.shadow_color.to_html(), AcTokens.SHADOW_LEAF_GLOW.to_html(), "Leaf-Glow shipped")

extends TestCase
## W21 „ACNH-UI" — Flächen-Budget der Referenz-Umsetzung (UI-DESIGN-ACNH §7):
## die linke Stats-Spalte des Quer-HUD ist EINE kompakte StatKapsel-Gruppe.
## Gemessen im Leitformat (2868×1320 @3×, Canvas 1564×720): vorher 7,95 %
## gemalte Fläche / 70,6 % Spaltenhöhe — nachher 3,52 % / 40,8 %. Dieser
## Wächter friert das Budget ein (mit etwas Luft für Rundungs-Formate):
## - gemalte Chip-Fläche ≤ 4,5 % des Canvas, Gruppenhöhe ≤ 45 %,
## - die Gruppe liest sich als EIN Element: Segment-Rollen in Reihenfolge
##   Kopf → Mitte… → Fuss, Separation 0, EINE gemeinsame Breite.

const HUD_SCENE := preload("res://scripts/ui/hud.tscn")
const FENSTER := Vector2i(2868, 1320)
## Budget mit Luft: Referenz-Messung 3,52 % Fläche / 40,8 % Höhe.
const MAX_FLAECHE_ANTEIL := 0.045
const MAX_HOEHE_ANTEIL := 0.45


func test_quer_kapsel_gruppe_haelt_das_budget() -> void:
	var fenster_vorher := tree.root.size
	var override_vorher := UiScale.screen_scale_override
	tree.root.size = FENSTER
	UiScale.screen_scale_override = 3.0
	var hud: Hud = HUD_SCENE.instantiate()
	tree.root.add_child(hud)
	await wait_frames(2)
	hud.apply_layout(HudLayoutLogic.Layout.LANDSCAPE)
	hud.set_stats({"hunger": 82.0, "energie": 64.0, "hygiene": 91.0, "spass": 73.0})
	hud.set_level(7, 0.45)
	hud.set_coins(265)
	# Münz-Impuls (Bounce/Count-Up ~0,6 s) ausschwingen lassen — die Messung
	# will Layout-Rects, keine mitten in der Feder skalierten Transforms.
	await wait_frames(60)
	var canvas := Vector2(tree.root.get_visible_rect().size)
	var chips: Array[Control] = hud._chip_nodes
	assert_eq(chips.size(), 6, "6 Segmente (Level, 4 Stats, Coins)")
	# Gruppe = EIN Element: Rollen in Segment-Reihenfolge + Separation 0.
	assert_eq(String(chips[0].theme_type_variation), "StatKapselKopf", "erste Zeile = Kopf")
	for i in range(1, chips.size() - 1):
		assert_eq(String(chips[i].theme_type_variation), "StatKapselMitte", "Zeile %d = Mitte" % i)
	assert_eq(
		String(chips[chips.size() - 1].theme_type_variation), "StatKapselFuss", "letzte = Fuss"
	)
	var spalte := hud._left_column as VBoxContainer
	assert_eq(
		spalte.get_theme_constant("separation"), 0, "Segmente stoßen aneinander (Separation 0)"
	)
	var gemalt := 0.0
	var bbox: Rect2 = chips[0].get_global_rect()
	var breite := chips[0].get_global_rect().size.x
	for chip in chips:
		var rect := chip.get_global_rect()
		gemalt += rect.size.x * rect.size.y
		bbox = bbox.merge(rect)
		assert_almost(rect.size.x, breite, 0.6, "EINE Gruppenbreite (%s)" % chip.name)
	var flaeche_anteil := gemalt / (canvas.x * canvas.y)
	assert_true(
		flaeche_anteil <= MAX_FLAECHE_ANTEIL,
		"gemalte Stats-Fläche %.2f %% ≤ %.1f %% Budget" % [100.0 * flaeche_anteil, 4.5]
	)
	var hoehe_anteil := bbox.size.y / canvas.y
	assert_true(
		hoehe_anteil <= MAX_HOEHE_ANTEIL,
		"Gruppenhöhe %.1f %% ≤ %.0f %% Budget" % [100.0 * hoehe_anteil, 45.0]
	)
	hud.free()
	UiScale.screen_scale_override = override_vorher
	tree.root.size = fenster_vorher
	tree.root.size_changed.emit()
	await wait_frames(1)

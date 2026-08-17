extends TestCase
## W21 „ACNH-UI" P1 — RUHE-HUD-FLÄCHEN-BUDGET (UI-DESIGN-ACNH §8 P1,
## Abnahme „Ruhe-HUD gesamt ≤ 8 % gemalte Fläche"). Referenz-Messung im
## Leitformat (2868×1320 @3×, Canvas 1564×720, iPhone-Insets): VORHER
## 12,07 % (links 3,52 % + rechts 8,55 %; rechte Spalte inkl. Zahnrad/Auge
## 93 % Bildhöhe) — NACHHER 7,40 % (rechts 3,88 %) mit Kachel-Spalte
## 48,1 % Bildhöhe. Dieser Wächter friert das Budget ein (mit etwas Luft
## für Rundungs-Formate):
## - GESAMT gemalte Ruhe-HUD-Fläche (links + rechts) ≤ 8 % des Canvas,
## - Ruhe-Cockpit = RUHE-Set + Mehr; alles hinter Mehr ist unsichtbar,
## - EINE Knopfgröße für die ganze rechte Möblierung (Kacheln, Mehr,
##   Zahnrad): quadratisch in der Kompakt-Einheit,
## - Kachel-Spalten-Höhe (inkl. Mehr) ≤ 55 % der Bildhöhe.
## EVAL-2026-08 Lens B Befund 18: Auge + Gooby-Lupe sind quer NEBENKNÖPFE
## und ruhen ebenfalls hinter „Mehr“ — im Ruhe-HUD sind sie unsichtbar
## (und zählen nicht mehr ins gemalte Budget).

const HUD_SCENE := preload("res://scripts/ui/hud.tscn")
const FENSTER := Vector2i(2868, 1320)
const INSETS_PT: Array = [59.0, 0.0, 59.0, 21.0]
## Budget mit Luft: Referenz-Messung 7,40 % Fläche / 48,1 % Spaltenhöhe.
const MAX_GESAMT_ANTEIL := 0.08
const MAX_KACHEL_HOEHE_ANTEIL := 0.55


func _flaeche(ctl: Control) -> float:
	if ctl == null or not ctl.is_visible_in_tree():
		return 0.0
	var rect := ctl.get_global_rect()
	return rect.size.x * rect.size.y


func test_ruhe_hud_haelt_das_acht_prozent_budget() -> void:
	var fenster_vorher := tree.root.size
	var override_vorher := UiScale.screen_scale_override
	UiScale.screen_scale_override = 3.0
	tree.root.size = FENSTER
	tree.root.size_changed.emit()
	await wait_frames(2)
	var canvas := Vector2(tree.root.get_visible_rect().size)
	var px_per_pt := minf(canvas.x, canvas.y) / (float(mini(FENSTER.x, FENSTER.y)) / 3.0)
	var l := float(INSETS_PT[0]) * px_per_pt
	var r := float(INSETS_PT[2]) * px_per_pt
	var b := float(INSETS_PT[3]) * px_per_pt
	UiScale.insets_override = Rect2(l, 0.0, canvas.x - l - r, canvas.y - b)
	tree.root.size_changed.emit()
	await wait_frames(2)
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
	var f := UiScale.for_viewport(hud.get_viewport())
	# Ruhe-Cockpit: NUR das RUHE-Set zeigt; alles hinter Mehr ist weg.
	for id: StringName in HudButtonOrder.RUHE:
		assert_true((hud._buttons[id] as Button).visible, "Ruhe-Kachel %s sichtbar" % id)
	for id: StringName in HudButtonOrder.hinter_mehr():
		assert_false(
			(hud._buttons[id] as Button).is_visible_in_tree(),
			"Kachel %s ruht eingeklappt hinter Mehr" % id
		)
	# Befund 18: Auge + Gooby-Lupe ruhen hinter „Mehr“ — unsichtbar in Ruhe.
	assert_false(hud._eye_button.is_visible_in_tree(), "Auge ruht hinter Mehr")
	assert_false(hud._gooby_chip.is_visible_in_tree(), "Gooby-Lupe ruht hinter Mehr")
	# EINE Knopfgröße (Kompakt-Einheit, nie unterm Touch-Floor), quadratisch.
	var floor_px := maxf(
		HudLayoutLogic.touch_floor_canvas(canvas),
		float(AcTokens.TOUCH_FLOOR) * UiScale.touch_px_per_pt(hud.get_viewport())
	)
	var einheit := maxf(float(AcTokens.px(float(AcTokens.BTN_H_KOMPAKT), f)), floor_px)
	var rechte_moebel: Array = [hud._mehr_button, hud._settings_button]
	for id: StringName in HudButtonOrder.RUHE:
		rechte_moebel.append(hud._buttons[id])
	var gemalt_rechts := 0.0
	var kachel_box := Rect2()
	for moebel: Variant in rechte_moebel:
		var ctl := moebel as Control
		assert_true(ctl.is_visible_in_tree(), "%s sichtbar im Ruhe-HUD" % ctl.name)
		var rect := ctl.get_global_rect()
		assert_almost(rect.size.x, einheit, 1.5, "EINE Knopfbreite (%s)" % ctl.name)
		assert_almost(rect.size.y, einheit, 1.5, "EINE Knopfhöhe (%s)" % ctl.name)
		gemalt_rechts += rect.size.x * rect.size.y
	for id: StringName in HudButtonOrder.RUHE:
		var rect := (hud._buttons[id] as Button).get_global_rect()
		kachel_box = rect if kachel_box.size == Vector2.ZERO else kachel_box.merge(rect)
	kachel_box = kachel_box.merge(hud._mehr_button.get_global_rect())
	# Links: die StatKapsel-Gruppe (Detail-Wachen in test_w21_stat_kapsel_budget).
	var gemalt_links := 0.0
	for chip: Control in hud._chip_nodes:
		gemalt_links += _flaeche(chip)
	var gesamt_anteil := (gemalt_links + gemalt_rechts) / (canvas.x * canvas.y)
	assert_true(
		gesamt_anteil <= MAX_GESAMT_ANTEIL,
		(
			"Ruhe-HUD %.2f %% ≤ %.0f %% Budget (links %.2f %%, rechts %.2f %%)"
			% [
				100.0 * gesamt_anteil,
				100.0 * MAX_GESAMT_ANTEIL,
				100.0 * gemalt_links / (canvas.x * canvas.y),
				100.0 * gemalt_rechts / (canvas.x * canvas.y)
			]
		)
	)
	var hoehe_anteil := kachel_box.size.y / canvas.y
	assert_true(
		hoehe_anteil <= MAX_KACHEL_HOEHE_ANTEIL,
		"Kachel-Spalte %.1f %% ≤ %.0f %% Bildhöhe" % [100.0 * hoehe_anteil, 55.0]
	)
	hud.free()
	UiScale.screen_scale_override = override_vorher
	UiScale.insets_override = Rect2()
	tree.root.size = fenster_vorher
	tree.root.size_changed.emit()
	await wait_frames(1)

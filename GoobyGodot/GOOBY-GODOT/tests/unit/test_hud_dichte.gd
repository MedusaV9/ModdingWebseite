extends TestCase
## EVAL-2026-08 Lens B Befund 18 — HUD-DICHTE im Telefon-Querformat
## (Shot 17_ui_iphone_hud_2340x1080: „linke Statleiste, sechs rechte
## Aktionsknöpfe, Auge unten, Lupe unten und Sprechblase belegen gleichzeitig
## sehr viel Randfläche“). Wachen:
## - RUHE quer: NUR RUHE-Kacheln + Mehr + Zahnrad sind sichtbare Knöpfe —
##   Auge und Gooby-Lupe ruhen hinter „Mehr“ (Sekundär-Dock),
## - Mehr auf: Auge + Lupe erscheinen (und bleiben in der Safe-Area),
##   Mehr zu: beide verschwinden wieder,
## - das AKTIVE Auge bleibt sichtbar (Zustand läuft nie unsichtbar weiter)
##   und räumt sich nach dem Auto-Aus selbst wieder ein,
## - Hochkant behält die Bodenzeile (Auge + Text-Chip),
## - die Blasen-Lane reicht in Ruhe TIEFER (Auge/Lupe-Zeile entfällt).
## Format = exakt das Eval-Leitformat iPhone 2340×1080 @3×.

const HUD_SCENE := preload("res://scripts/ui/hud.tscn")
const QUER := Vector2i(2340, 1080)
const HOCH := Vector2i(1080, 2340)
## iPhone-Insets in Punkten (l/t/r/b) — Rechnung wie test_w21_hud_ruhe_budget.
const INSETS_QUER_PT: Array = [59.0, 0.0, 59.0, 21.0]
const INSETS_HOCH_PT: Array = [0.0, 59.0, 0.0, 34.0]

var _fenster_vorher := Vector2i()
var _scale_vorher := 0.0


func _pin(fenster: Vector2i, insets_pt: Array) -> void:
	_fenster_vorher = tree.root.size
	_scale_vorher = UiScale.screen_scale_override
	UiScale.screen_scale_override = 3.0
	tree.root.size = fenster
	tree.root.size_changed.emit()
	await wait_frames(2)
	var canvas := Vector2(tree.root.get_visible_rect().size)
	var px_per_pt := minf(canvas.x, canvas.y) / (float(mini(fenster.x, fenster.y)) / 3.0)
	var l := float(insets_pt[0]) * px_per_pt
	var t := float(insets_pt[1]) * px_per_pt
	var r := float(insets_pt[2]) * px_per_pt
	var b := float(insets_pt[3]) * px_per_pt
	UiScale.insets_override = Rect2(l, t, canvas.x - l - r, canvas.y - t - b)
	tree.root.size_changed.emit()
	await wait_frames(2)


func _unpin() -> void:
	UiScale.screen_scale_override = _scale_vorher
	UiScale.insets_override = Rect2()
	tree.root.size = _fenster_vorher
	tree.root.size_changed.emit()
	await wait_frames(1)


func _hud_bauen() -> Hud:
	var hud: Hud = HUD_SCENE.instantiate()
	tree.root.add_child(hud)
	return hud


func test_quer_ruhe_versteckt_auge_und_lupe_hinter_mehr() -> void:
	await _pin(QUER, INSETS_QUER_PT)
	var hud := _hud_bauen()
	await wait_frames(2)
	assert_eq(int(hud.current_layout), int(HudLayoutLogic.Layout.LANDSCAPE), "quer erkannt")
	# RUHE: Auge + Lupe sind weg; nur RUHE-Kacheln + Mehr + Zahnrad zeigen.
	assert_false(hud._eye_button.is_visible_in_tree(), "Ruhe: Auge hinter Mehr")
	assert_false(hud._gooby_chip.is_visible_in_tree(), "Ruhe: Gooby-Lupe hinter Mehr")
	for id: StringName in HudButtonOrder.RUHE:
		assert_true((hud._buttons[id] as Button).is_visible_in_tree(), "Ruhe-Kachel %s da" % id)
	for id: StringName in HudButtonOrder.hinter_mehr():
		assert_false(
			(hud._buttons[id] as Button).is_visible_in_tree(), "Kachel %s ruht hinter Mehr" % id
		)
	assert_true(hud._mehr_button.is_visible_in_tree(), "Mehr-Kachel da")
	assert_true(hud._settings_button.is_visible_in_tree(), "Zahnrad da")
	# Blasen-Lane in Ruhe: reicht bis zur Safe-Area-Unterkante (keine
	# Auge/Lupe-Zeile mehr abzuziehen).
	var lane_ruhe := float(hud.bubble_lane()["top"])
	# Mehr AUF: Auge + Lupe erscheinen — komplett in der Safe-Area.
	hud._mehr_button.pressed.emit()
	await wait_frames(2)
	assert_true(hud._eye_button.is_visible_in_tree(), "Mehr auf: Auge da")
	assert_true(hud._gooby_chip.is_visible_in_tree(), "Mehr auf: Lupe da")
	var canvas := Vector2(tree.root.get_visible_rect().size)
	var safe := UiScale.insets_override
	for ctl: Control in [hud._eye_button, hud._gooby_chip]:
		assert_true(
			safe.grow(0.5).encloses(ctl.get_global_rect()),
			"%s in der Safe-Area (%s ⊄ %s)" % [ctl.name, ctl.get_global_rect(), safe]
		)
	var lane_mehr := float(hud.bubble_lane()["top"])
	assert_true(
		lane_ruhe > lane_mehr + 1.0,
		"Ruhe-Lane reicht tiefer (%.1f) als mit offener Auge-Zeile (%.1f)" % [lane_ruhe, lane_mehr]
	)
	assert_true(lane_ruhe <= canvas.y, "Lane bleibt im Canvas")
	# Mehr ZU: beide ruhen wieder.
	hud._mehr_button.pressed.emit()
	await wait_frames(2)
	assert_false(hud._eye_button.is_visible_in_tree(), "Mehr zu: Auge ruht wieder")
	assert_false(hud._gooby_chip.is_visible_in_tree(), "Mehr zu: Lupe ruht wieder")
	hud.free()
	await _unpin()


func test_aktives_auge_bleibt_sichtbar_und_raeumt_sich_ein() -> void:
	await _pin(QUER, INSETS_QUER_PT)
	var hud := _hud_bauen()
	await wait_frames(2)
	# Auge im offenen Cluster aktivieren, dann Cluster schließen: der
	# AKTIVE Zustand bleibt sichtbar (läuft nie unsichtbar weiter).
	hud._mehr_button.pressed.emit()
	await wait_frames(1)
	hud._eye_button.button_pressed = true
	hud._mehr_button.pressed.emit()
	await wait_frames(1)
	assert_true(hud.is_eye_active(), "Auge aktiv")
	assert_true(hud._eye_button.is_visible_in_tree(), "aktives Auge bleibt sichtbar")
	assert_false(hud._gooby_chip.is_visible_in_tree(), "Lupe ruht trotzdem")
	# Auto-Aus (8-s-Timer) räumt das Auge zurück hinter Mehr.
	hud._on_eye_timeout()
	await wait_frames(1)
	assert_false(hud.is_eye_active(), "Auto-Aus schaltet ab")
	assert_false(hud._eye_button.is_visible_in_tree(), "…und räumt das Auge ein")
	# Lautloses Setzen von außen folgt derselben Regel.
	hud.set_eye_active(true)
	assert_true(hud._eye_button.is_visible_in_tree(), "set_eye_active(true) zeigt das Auge")
	hud.set_eye_active(false)
	assert_false(hud._eye_button.is_visible_in_tree(), "set_eye_active(false) räumt es ein")
	hud.free()
	await _unpin()


func test_hochkant_behaelt_die_bodenzeile() -> void:
	await _pin(HOCH, INSETS_HOCH_PT)
	var hud := _hud_bauen()
	await wait_frames(2)
	assert_eq(int(hud.current_layout), int(HudLayoutLogic.Layout.PORTRAIT), "hochkant erkannt")
	assert_true(hud._eye_button.is_visible_in_tree(), "hochkant: Auge in der Bodenzeile")
	assert_true(hud._gooby_chip.is_visible_in_tree(), "hochkant: Gooby-Chip in der Bodenzeile")
	hud.free()
	await _unpin()

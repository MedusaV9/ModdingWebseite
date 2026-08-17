extends TestCase
## W21 P1 — TOAST-RADIUS/HÖHEN-KONFORMITÄT (Blatt-Sprache, UI-DESIGN-ACNH
## §8 P1):
## - ToastBubble rundet mit RADIUS_CARD (die 22er-Web-Ausnahme ist aus
##   test_w21_acnh_skalen gestrichen — hier zusätzlich direkt genagelt),
## - EINE Toast-Höhe: einzeilige Toasts sind exakt px(TOAST_H, f) hoch;
##   gewickelte wachsen NUR um die synchron gemessenen Zeilen (nie wieder
##   das Phantom-361-px-Panel der Salven-Probe),
## - Icon+Text-Layout nach Spec: Blatt-Glyphe ICON_S, Text SIZE_CAPTION,
##   Lücke SPACE_S; Breiten-Deckel min(86 % Canvas, 352·f) hält.
## - ZWICKMÜHLEN-REGEL (fb3 23_kombi_toast, Probe-Repro): „Was nun?“-Karte
##   oben + HOHE Bottom-Belegung (Gooby-Blase mitten im Bild) ließen dem
##   Toast keine Lücke — das Blase-Hochschieben drückte ihn zurück AUF das
##   Karten-×. Jetzt rutscht er UNTER die Blase und schneidet KEINS von
##   beiden (test_zwickmuehle_karte_oben_blase_unten).

const FENSTER := Vector2i(2868, 1320)
const KURZ := "Quest geschafft: +40 Münzen!"
const LANG := (
	"Abzeichen verdient! Dieser bewusst lange Wächter-Toast fährt die "
	+ "volle Breite aus und muss sauber über mehrere Zeilen wickeln."
)


func _set_reduced_motion(an: bool) -> bool:
	var svc := tree.root.get_node_or_null("/root/UiTheme")
	if svc == null:
		return false
	var vorher: bool = svc.reduced_motion
	svc.reduced_motion = an
	return vorher


func test_toast_bubble_radius_ist_radius_card() -> void:
	var style := ThemeService.theme().get_stylebox("panel", "ToastBubble")
	assert_true(style is StyleBoxFlat, "ToastBubble-Panel ist eine StyleBoxFlat")
	var flat := style as StyleBoxFlat
	for ecke: Variant in [
		flat.corner_radius_top_left,
		flat.corner_radius_top_right,
		flat.corner_radius_bottom_left,
		flat.corner_radius_bottom_right
	]:
		assert_eq(int(ecke), AcTokens.RADIUS_CARD, "Toast-Ecke = RADIUS_CARD (keine 22er-Ausnahme)")


func test_eine_toast_hoehe_und_blatt_layout() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	var override_vorher := UiScale.screen_scale_override
	var rm_vorher := _set_reduced_motion(true)
	UiScale.screen_scale_override = 3.0
	tree.root.size = FENSTER
	tree.root.size_changed.emit()
	await wait_frames(2)
	var toasts := ToastLayer.new()
	toasts.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(toasts)
	await wait_frames(1)
	toasts.show_toast(KURZ)
	await wait_frames(3)
	var f := UiScale.for_viewport(tree.root)
	var panel := toasts.find_child("ToastPanel", true, false) as PanelContainer
	assert_true(panel != null and panel.visible, "Einzeiler sichtbar")
	assert_almost(
		panel.size.y,
		float(AcTokens.px(ToastLayer.TOAST_H, f)),
		1.0,
		"EINE Toast-Höhe: einzeilig exakt px(TOAST_H, f)"
	)
	var leaf := toasts.find_child("ToastLeaf", true, false) as TextureRect
	assert_almost(
		leaf.custom_minimum_size.x,
		float(AcTokens.px(float(AcTokens.ICON_S), f)),
		0.5,
		"Blatt-Glyphe in ICON_S"
	)
	var label := toasts.find_child("ToastText", true, false) as Label
	assert_eq(
		label.get_theme_font_size("font_size"),
		AcTokens.font_px(float(AcTokens.SIZE_CAPTION), f),
		"Toast-Text in SIZE_CAPTION"
	)
	var box := toasts.find_child("ToastBox", true, false) as HBoxContainer
	assert_eq(
		box.get_theme_constant("separation"),
		AcTokens.px(float(AcTokens.SPACE_S), f),
		"Icon-Text-Lücke = SPACE_S"
	)
	toasts.free()
	_set_reduced_motion(rm_vorher)
	UiScale.screen_scale_override = override_vorher
	tree.root.size = fenster_vorher
	tree.root.size_changed.emit()
	await wait_frames(1)


## Zwickmühle des fb3-Befunds 23_kombi_toast (Probe-Repro im Leitformat):
## „Was nun?“-Karte belegt die Kopf-Lane, Goobys Blase steht so HOCH, dass
## direkt unter der Karte keine Lücke bleibt. Vorher schob der Bottom-Dodge
## den fertig unter die Karte gedodgten Toast zurück AUF deren × — jetzt
## rutscht er UNTER die Blase und schneidet keins von beiden.
func test_zwickmuehle_karte_oben_blase_unten() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	var override_vorher := UiScale.screen_scale_override
	var rm_vorher := _set_reduced_motion(true)
	UiScale.screen_scale_override = 3.0
	tree.root.size = FENSTER
	tree.root.size_changed.emit()
	await wait_frames(2)
	var canvas := Vector2(tree.root.get_visible_rect().size)
	# Karte in der echten Audit-Geometrie: oben mittig, ~195 px hoch.
	var karte := PanelContainer.new()
	karte.add_to_group(&"wasnun_karte")
	karte.position = Vector2((canvas.x - 620.0) / 2.0, 12.0)
	karte.size = Vector2(620.0, 195.0)
	tree.root.add_child(karte)
	# Hohe Bottom-Belegung (Blasen-Kapsel): beginnt ÜBER der Kartenunter-
	# kante — über ihr ist kein toasthoher Platz mehr frei.
	var blase := Panel.new()
	blase.position = Vector2((canvas.x - 600.0) / 2.0, 190.0)
	blase.size = Vector2(600.0, 90.0)
	tree.root.add_child(blase)
	UiAnchors.reserve(UiAnchors.ZONE_BOTTOM, blase)
	var toasts := ToastLayer.new()
	toasts.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(toasts)
	await wait_frames(1)
	toasts.show_toast(LANG)
	await wait_frames(3)
	var panel := toasts.find_child("ToastPanel", true, false) as PanelContainer
	assert_true(panel != null and panel.visible, "Zwickmühlen-Toast sichtbar")
	var toast_rect := panel.get_global_rect()
	var karten_schnitt := toast_rect.intersection(karte.get_global_rect())
	assert_false(
		karten_schnitt.size.x > 4.0 and karten_schnitt.size.y > 4.0,
		"Toast %s schneidet die Karte %s nicht" % [toast_rect, karte.get_global_rect()]
	)
	var blasen_schnitt := toast_rect.intersection(blase.get_global_rect())
	assert_false(
		blasen_schnitt.size.x > 4.0 and blasen_schnitt.size.y > 4.0,
		"Toast %s schneidet die Blase %s nicht" % [toast_rect, blase.get_global_rect()]
	)
	assert_true(
		toast_rect.position.y <= canvas.y * ToastLayer.MAX_TIEFE_ANTEIL + 1.0,
		"Zwickmühlen-Lage %.0f hält den Tiefen-Deckel" % toast_rect.position.y
	)
	UiAnchors.release(UiAnchors.ZONE_BOTTOM, blase)
	toasts.free()
	blase.free()
	karte.free()
	_set_reduced_motion(rm_vorher)
	UiScale.screen_scale_override = override_vorher
	tree.root.size = fenster_vorher
	tree.root.size_changed.emit()
	await wait_frames(1)


func test_gewickelter_toast_waechst_nur_um_gemessene_zeilen() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	var override_vorher := UiScale.screen_scale_override
	var rm_vorher := _set_reduced_motion(true)
	UiScale.screen_scale_override = 3.0
	tree.root.size = FENSTER
	tree.root.size_changed.emit()
	await wait_frames(2)
	var canvas := Vector2(tree.root.get_visible_rect().size)
	var toasts := ToastLayer.new()
	toasts.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(toasts)
	await wait_frames(1)
	toasts.show_toast(LANG)
	await wait_frames(3)
	var f := UiScale.for_viewport(tree.root)
	var panel := toasts.find_child("ToastPanel", true, false) as PanelContainer
	assert_true(panel != null and panel.visible, "Wickel-Toast sichtbar")
	# Breiten-Deckel hält (Playtest-Befund „~894 px statt ≤ 576").
	var max_w := minf(canvas.x * 0.86, ToastLayer.MAX_WIDTH_PX * f)
	assert_true(
		panel.size.x <= max_w + 2.0, "Wickel-Breite %.0f ≤ Deckel %.0f" % [panel.size.x, max_w]
	)
	var label := toasts.find_child("ToastText", true, false) as Label
	assert_true(label.get_line_count() >= 2, "langer Text wickelt über mehrere Zeilen")
	assert_eq(
		label.get_visible_line_count(),
		label.get_line_count(),
		"JEDE gemessene Zeile sichtbar — keine verschluckte Zeile"
	)
	# Höhe = Label-Messung + Panel-Innenränder (keine Phantom-Zeilen der
	# deferred Container-Sorts — der 361-px-Salven-Befund).
	var style := panel.get_theme_stylebox("panel")
	var erwartet := (
		label.custom_minimum_size.y
		+ style.get_content_margin(SIDE_TOP)
		+ style.get_content_margin(SIDE_BOTTOM)
	)
	assert_true(
		panel.size.y <= erwartet + 2.0,
		"Panel-Höhe %.0f wächst nur um die gemessenen Zeilen (%.0f)" % [panel.size.y, erwartet]
	)
	assert_true(
		panel.size.y >= float(AcTokens.px(ToastLayer.TOAST_H, f)) - 1.0,
		"Wickel-Toast nie flacher als die EINE Toast-Höhe"
	)
	toasts.free()
	_set_reduced_motion(rm_vorher)
	UiScale.screen_scale_override = override_vorher
	tree.root.size = fenster_vorher
	tree.root.size_changed.emit()
	await wait_frames(1)

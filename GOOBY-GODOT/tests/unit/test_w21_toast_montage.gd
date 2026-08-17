extends TestCase
## W21 Home/HUD — TOAST-MONTAGE-WACHE (Playtest-Befund „langer Quest-Toast
## liegt quer ÜBER der Cockpit-Spalte und ist ~894 px breit statt ≤ 352·f“).
## Der echte Anzeige-Weg läuft NICHT über die Screen-eigenen ToastLayer,
## sondern über die SERVICE-Layer (DailyQuestService/RewardHub): ToastLayer
## unter einem CanvasLayer, montiert nur mit `set_anchors_preset` (ohne
## Offsets-Reset — die bekannte Repo-Falle, s. Kommentare in album_screen/
## visit_hud/city_scene). Dieser Test nagelt GENAU diese Montage in beiden
## Leitformaten fest:
## (1) der Layer deckt den Canvas (kein konservierter 0-/Alt-Rect),
## (2) der Breiten-Deckel hält (min(86 % Canvas, 352·f)),
## (3) der Toast schneidet weder Status-Spalte noch Cockpit-Spalte noch
##     Zahnrad (Rect-Schnitt mit FB3-Toleranz); die TopBar zählt nur
##     HOCHKANT als Chrome (quer ist sie ein leerer Layout-Container und
##     hint_lane ignoriert sie quer bewusst).
## Erster Diagnose-Lauf: Deckel hält hier EXAKT (576,0 quer / 1024,0 hoch)
## — das im Playtest gemessene ~894-px-Panel (Text darin korrekt bei 26er
## Font, Wickeln bei ~500) tritt in dieser sauberen Montage NICHT auf;
## der Auslöser liegt im Live-Kontext (Queue/Salve/Animation), s.
## home_hud_befunde.md P0-Toast.

const HUD_SCENE := preload("res://scripts/ui/hud.tscn")

## Leitformate [Fenster-px, screen_scale, Insets in PUNKTEN l/t/r/b] —
## Rechnung wie test_w20_overlay_choreo (iPhone 17 Pro Max).
const FORMATE: Array = [
	[Vector2i(2868, 1320), 3.0, [59.0, 0.0, 59.0, 21.0]],
	[Vector2i(1320, 2868), 3.0, [0.0, 59.0, 0.0, 34.0]],
]
## FB3-Overlap-Toleranz: Schnitte ≤ 4×4 px gelten als Berührung.
const OVERLAP_TOLERANZ := 4.0
## Der Playtest-Text, der den Befund auslöste (wickelt im Leitformat).
const LANGER_TOAST := "Tagesquest geschafft: Dritter Toast — ein etwas längerer Text zum Wickeln."


func _set_reduced_motion(an: bool) -> bool:
	var svc := tree.root.get_node_or_null("/root/UiTheme")
	if svc == null:
		return false
	var vorher: bool = svc.reduced_motion
	svc.reduced_motion = an
	return vorher


func _pin_format(format: Array) -> void:
	var fenster: Vector2i = format[0]
	UiScale.screen_scale_override = float(format[1])
	tree.root.size = fenster
	tree.root.size_changed.emit()
	await wait_frames(2)
	var canvas := Vector2(tree.root.get_visible_rect().size)
	var scale: float = format[1]
	var insets_pt: Array = format[2]
	var px_per_pt := minf(canvas.x, canvas.y) / (minf(fenster.x, fenster.y) / scale)
	var l := float(insets_pt[0]) * px_per_pt
	var t := float(insets_pt[1]) * px_per_pt
	var r := float(insets_pt[2]) * px_per_pt
	var b := float(insets_pt[3]) * px_per_pt
	UiScale.insets_override = Rect2(l, t, canvas.x - l - r, canvas.y - t - b)
	tree.root.size_changed.emit()
	await wait_frames(2)


func _unpin_format(fenster_vorher: Vector2i) -> void:
	UiScale.screen_scale_override = 0.0
	UiScale.insets_override = Rect2()
	tree.root.size = fenster_vorher
	tree.root.size_changed.emit()
	await wait_frames(1)


func _echter_schnitt(a: Rect2, b: Rect2) -> bool:
	var schnitt := a.intersection(b)
	return schnitt.size.x > OVERLAP_TOLERANZ and schnitt.size.y > OVERLAP_TOLERANZ


## Baut die Service-Montage EXAKT wie quest_service/reward_hub._ready —
## bewusst KEIN set_anchors_and_offsets_preset: die Wache muss den echten
## Produktions-Pfad abdecken, nicht einen idealisierten.
func _service_layer_bauen() -> Array:
	var layer := CanvasLayer.new()
	layer.layer = 60
	tree.root.add_child(layer)
	var toasts := ToastLayer.new()
	toasts.name = "QuestToasts"
	toasts.theme = ThemeService.theme()
	toasts.set_anchors_preset(Control.PRESET_FULL_RECT)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(toasts)
	return [layer, toasts]


func test_service_toast_haelt_deckel_und_meidet_hud_chrome() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	var rm_vorher := _set_reduced_motion(true)
	for format: Array in FORMATE:
		await _pin_format(format)
		var canvas := Vector2(tree.root.get_visible_rect().size)
		var hud: Hud = HUD_SCENE.instantiate()
		tree.root.add_child(hud)
		await wait_frames(2)
		var paar := _service_layer_bauen()
		var toasts := paar[1] as ToastLayer
		await wait_frames(1)
		toasts.show_toast(LANGER_TOAST)
		# _reposition awaitet bis zu 2 Frames (Mess-Frame + Wickel-Frame).
		await wait_frames(6)
		var f := UiScale.for_viewport(tree.root)
		var panel := toasts.find_child("ToastPanel", true, false) as Control
		assert_true(panel != null and panel.visible, "Toast sichtbar @ %s" % format[0])
		var toast_rect := panel.get_global_rect()
		# Diagnose-Zeile (Playtest-Nachstellung W21): alle Entscheidungs-
		# größen des Breiten-Deckels in EINEM Log.
		print(
			(
				"[W21-TOAST] format=%s layer_size=%s panel=%s f=%.3f canvas=%s"
				% [format[0], toasts.size, toast_rect, f, canvas]
			)
		)
		# (1) Montage: der Service-Layer deckt den Canvas.
		assert_almost(toasts.size.x, canvas.x, 1.0, "Layer-Breite = Canvas @ %s" % format[0])
		assert_almost(toasts.size.y, canvas.y, 1.0, "Layer-Höhe = Canvas @ %s" % format[0])
		# (2) Breiten-Deckel wie toast.gd._reposition dokumentiert.
		var max_w := minf(canvas.x * 0.86, ToastLayer.MAX_WIDTH_PX * f)
		assert_true(
			toast_rect.size.x <= max_w + 2.0,
			"Toast-Breite %.0f über Deckel %.0f @ %s" % [toast_rect.size.x, max_w, format[0]]
		)
		# (3) Kein Schnitt mit dem HUD-Chrome (Status-Spalte, Cockpit-
		# Spalte, Zahnrad; TopBar nur HOCHKANT) — der Playtest-Befund.
		# Quer ist die TopBar ein LEERER Layout-Container (Chips wandern in
		# die LeftColumn, nur der unsichtbare Spacer bleibt) und hint_lane
		# ignoriert sie quer BEWUSST — ihr Rect zählt dann nicht als Chrome.
		var hochkant: bool = format[0].y > format[0].x
		var chrome_teile: Array = [hud._left_column, hud._landscape_column, hud._settings_button]
		if hochkant:
			chrome_teile.append(hud.get_node("TopBar"))
		for teil: Variant in chrome_teile:
			var chrome := teil as Control
			if chrome == null or not chrome.is_visible_in_tree():
				continue
			assert_false(
				_echter_schnitt(toast_rect, chrome.get_global_rect()),
				(
					"Toast %s überlappt HUD-Chrome %s (%s) @ %s"
					% [toast_rect, chrome.name, chrome.get_global_rect(), format[0]]
				)
			)
		paar[0].free()
		hud.free()
	_set_reduced_motion(rm_vorher)
	await _unpin_format(fenster_vorher)

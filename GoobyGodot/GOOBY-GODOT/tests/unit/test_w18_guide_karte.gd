extends TestCase
## W18 Playtest Befund 1 — Wächter für die Guide-/Tour-Karte: sie blähte
## sich nach dem Onboarding auf >5400 px Höhe auf (Autowrap-Messung bei
## Label-Breite 0 → Zeichen-pro-Zeile; reset_size() fror das ein, weil der
## Router-Travel direkt nach attach_to die Karte versteckte und versteckte
## Controls keine Minimum-Änderungen nachziehen) und verschluckte als
## mouse_filter-STOP-Säule das HUD-Dock (hochkant: BtnBau untippbar,
## 47,8-s-Timeout) bzw. das Bau-Dock (quer). Wachen (FB3-Audit-Rechnung:
## Rect-Schnitt mit Toleranz, Retina-Skala + Notch wie fb3_ui_audit):
## (a) Karte bleibt in BEIDEN Leitformaten unter 45 % der Canvas-Höhe und
##     komplett im Viewport — auch mit langem Text und auch dann, wenn sie
##     wie im echten Boot noch im Attach-Frame travel-versteckt wird;
## (b) Karte überlappt keine HUD-Dock-Kacheln (BtnBau bleibt frei);
## (c) im Baumodus duckt sich die Karte (nie über dem Bau-Dock) und kommt
##     nach dem Schließen von selbst zurück.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const HUD_SCENE := preload("res://scripts/ui/hud.tscn")

const NOW_MS := 1785448800000  # 2026-07-30 UTC
## Leitformate [Fenster-px, screen_scale, Insets in PUNKTEN l/t/r/b] —
## Werte wie fb3_ui_audit.SIZES (iPhone 17 Pro Max quer + hochkant).
const FORMATE: Array = [
	[Vector2i(2868, 1320), 3.0, [59.0, 0.0, 59.0, 21.0]],
	[Vector2i(1320, 2868), 3.0, [0.0, 59.0, 0.0, 34.0]],
]
## Obergrenze der Kartenhöhe als Canvas-Anteil (Playtest-Schranke).
const MAX_HOEHE_ANTEIL := 0.45
## FB3-Overlap-Toleranz: Schnitte ≤ 4×4 px gelten als Berührung.
const OVERLAP_TOLERANZ := 4.0
const LANGER_TITEL := "Willkommen zu Hause in deinem allerersten eigenen Gooby-Zuhause!"
const LANGER_TEXT := (
	"Dies ist ein bewusst sehr langer Tour-Text, der frühere Fehler "
	+ "provoziert: Er muss innerhalb der Karte wickeln und scrollen, statt "
	+ "die Karte in eine bildschirmhohe, klick-schluckende Säule zu "
	+ "verwandeln. Gooby schaut sich neugierig um, der Kühlschrank wartet "
	+ "in der Küche, die Badewanne im Bad, die Arcade unten im Dock und "
	+ "das Möbelhaus in der Stadt. Jeden Tag gibt es frische Tagesquests, "
	+ "Sticker fürs Album und Münzen fürs Kümmern — und ab Level 20 "
	+ "öffnet die Gooby-Ranch ihre Tore für alle fleißigen Pioniere."
)

var _seq := 0


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://w18_guide_tests/gs_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	tree.root.add_child(gs)
	gs.apply_onboarding_profile({"player_name": "Tester", "gooby_nickname": "Flauschi"})
	return gs


## Fenster + Retina-Skala + Notch-Insets pinnen (Muster test_g7_hud_dynamik
## / fb3_ui_audit._audit_size).
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


func _karte(guide: OnboardingGuide) -> Control:
	return guide._card


## Schnittfläche zweier Rects größer als die FB3-Berühr-Toleranz?
func _echter_schnitt(a: Rect2, b: Rect2) -> bool:
	var schnitt := a.intersection(b)
	return schnitt.size.x > OVERLAP_TOLERANZ and schnitt.size.y > OVERLAP_TOLERANZ


func test_karte_bleibt_kompakt_und_im_viewport_trotz_travel_versteck() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	for format: Array in FORMATE:
		await _pin_format(format)
		var canvas := Vector2(tree.root.get_visible_rect().size)
		var gs := _fresh_gs()
		var host := Node.new()
		tree.root.add_child(host)
		var guide := OnboardingGuide.attach_to(host, gs)
		assert_ne(guide, null, "frischer Save startet die Tour @ %s" % format[0])
		# Der echte Boot-Pfad: home_entry startet DIREKT nach attach_to
		# einen Router-Travel — die Karte wird noch im Attach-Frame
		# versteckt (genau so fror die Riesenhöhe vor dem Fix ein).
		guide._on_travel_started()
		await wait_frames(3)
		# Langer Text: muss wickeln + scrollen statt die Karte aufzublähen.
		guide._title.text = LANGER_TITEL
		guide._text.text = LANGER_TEXT
		guide._relayout()
		await wait_frames(2)
		var karte := _karte(guide)
		var schranke := MAX_HOEHE_ANTEIL * canvas.y
		assert_true(
			karte.size.y < schranke,
			(
				"Kartenhöhe %.0f px < %.0f px (45%% von %.0f) trotz Versteck @ %s"
				% [karte.size.y, schranke, canvas.y, format[0]]
			)
		)
		guide._on_travel_finished()
		await wait_frames(3)
		var rect := karte.get_global_rect()
		assert_true(
			rect.size.y < schranke,
			(
				"Kartenhöhe %.0f px < %.0f px nach Travel-Ende @ %s"
				% [rect.size.y, schranke, format[0]]
			)
		)
		assert_true(
			Rect2(Vector2.ZERO, canvas).grow(1.0).encloses(rect),
			"Karte komplett im Viewport: %s (Canvas %s) @ %s" % [rect, canvas, format[0]]
		)
		assert_true(rect.size.x >= 220.0, "Karte behält Lesebreite: %s" % rect)
		host.free()
		gs.get_parent().remove_child(gs)
		gs.free()
	await _unpin_format(fenster_vorher)


func test_karte_ueberlappt_keine_hud_dock_kacheln() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	for format: Array in FORMATE:
		await _pin_format(format)
		var gs := _fresh_gs()
		var hud: Hud = HUD_SCENE.instantiate()
		tree.root.add_child(hud)
		await wait_frames(2)
		var host := Node.new()
		tree.root.add_child(host)
		var guide := OnboardingGuide.attach_to(host, gs)
		assert_ne(guide, null, "frischer Save startet die Tour @ %s" % format[0])
		guide._title.text = LANGER_TITEL
		guide._text.text = LANGER_TEXT
		guide._relayout()
		await wait_frames(3)
		var karten_rect := _karte(guide).get_global_rect()
		var geprueft := 0
		for id: StringName in hud._buttons:
			var knopf: Button = hud._buttons[id]
			if not knopf.is_visible_in_tree():
				continue
			geprueft += 1
			assert_false(
				_echter_schnitt(karten_rect, knopf.get_global_rect()),
				(
					"GuideKarte %s überlappt HUD-Kachel %s (%s) @ %s"
					% [karten_rect, id, knopf.get_global_rect(), format[0]]
				)
			)
		assert_true(geprueft > 0, "HUD liefert sichtbare Kacheln @ %s" % format[0])
		var bau_knopf: Button = hud._buttons[&"bau"]
		assert_false(
			_echter_schnitt(karten_rect, bau_knopf.get_global_rect()),
			"BtnBau bleibt frei tippbar (47,8-s-Timeout-Fall) @ %s" % format[0]
		)
		host.free()
		hud.free()
		gs.get_parent().remove_child(gs)
		gs.free()
	await _unpin_format(fenster_vorher)


func test_karte_duckt_sich_im_baumodus_und_kommt_zurueck() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	await _pin_format(FORMATE[0])
	var gs := _fresh_gs()
	var hud: Hud = HUD_SCENE.instantiate()
	tree.root.add_child(hud)
	await wait_frames(2)
	# Raum-Kontext stellen, damit die Karte überhaupt zeigen darf
	# (Muster screenshot_rest2: Router-Verweis direkt setzen).
	var router := tree.root.get_node_or_null("SceneRouter")
	var szene_vorher: Node = null
	var raum := RoomBase.new()
	if router != null:
		szene_vorher = router.get_current_scene()
		router._current_scene = raum
	var host := Node.new()
	tree.root.add_child(host)
	var guide := OnboardingGuide.attach_to(host, gs)
	await wait_frames(3)
	var karte := _karte(guide)
	assert_true(karte.visible, "Karte zeigt im Raum-Kontext")
	# Baumodus an → Karte duckt sich (nie über dem Bau-Dock, W18 quer).
	var bau := BuildMode.new()
	tree.root.add_child(bau)
	await wait_frames(1)
	bau.opened.emit()
	await wait_frames(2)
	assert_true(hud.sichtbarkeit().verdeckt(), "Baumodus an → HUD verdeckt (Vorbedingung)")
	assert_false(karte.visible, "Karte duckt sich im Baumodus (kein Bau-Dock-Overlap)")
	# Bau-Dock-Rects zur Sicherheit gegen das Karten-Rect prüfen — greift,
	# falls die Duck-Regel je aufgeweicht wird (FB3-Schnitt-Rechnung).
	var layer := CanvasLayer.new()
	tree.root.add_child(layer)
	var dock := BuildUiDock.new()
	dock.build(layer, BuildMode.EBENEN_KEYS)
	dock.ui.visible = true
	await wait_frames(2)
	if karte.is_visible_in_tree():
		for knopf in dock.ui.find_children("*", "Button", true, false):
			assert_false(
				_echter_schnitt(karte.get_global_rect(), (knopf as Control).get_global_rect()),
				"Sichtbare Karte überlappt Bau-Dock-Knopf %s" % knopf.name
			)
	# Baumodus zu → Karte kommt von selbst zurück.
	bau.closed.emit()
	await wait_frames(2)
	assert_true(karte.visible, "Karte kehrt nach dem Baumodus zurück")
	if router != null:
		router._current_scene = szene_vorher
	raum.free()
	layer.free()
	bau.free()
	host.free()
	hud.free()
	gs.get_parent().remove_child(gs)
	gs.free()
	await _unpin_format(fenster_vorher)

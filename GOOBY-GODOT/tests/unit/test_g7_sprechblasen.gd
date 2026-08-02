extends TestCase
## G7-P51 SPRECHBLASEN + TEXT-FIT — Wachen gegen die iPhone-Befunde
## („Ohh, wird das sch“ / „Ich such mir mal“ — Text riss MITTEN im Wort ab):
## AcBubble maß das Label, während der Typewriter visible_characters=0
## gesetzt hatte (VC_CHARS_BEFORE_SHAPING shapt nur sichtbare Zeichen) —
## die Blase startete winzig, ruckelte pro Buchstabe nach und der
## MAX_WIDTH-/Autowrap-Zweig griff NIE. Die Wachen prüfen: Endgröße steht
## VORAB fest, Wort-Umbruch statt Einzeiler-Überlauf, Text-Rect ⊆ Blase,
## Blase ⊆ Bildschirm (quer 2868×1320 UND hoch 1179×2556), kurze Sprüche
## bleiben kompakt — plus Ellipsis-Wachen der Text-Fit-Stellen (Album/
## Sammlungen/Füttern) mit den längsten ECHTEN Strings beider Sprachen.
##
## Konvention: Fenster pinnen + zurückstellen; lange Test-Strings sind
## ECHTE Strings aus strings/ (Keys als Fixtures unten).

const QUER := Vector2i(2868, 1320)
const HOCH := Vector2i(1179, 2556)

## Fixtures: echte Spruch-Keys (strings/de|en) — längster Spruch, der über
## room.say/AcBubble läuft, und der kürzeste aus den User-Screenshots.
const LANGER_KEY := "soul.wunsch.funkelpark"
const KURZER_KEY := "home.gooby.watch"
## Sehr langer Fixture-Spruch (zwei echte soul-Sätze verkettet): erzwingt
## in JEDEM Format mehrzeiliges Wickeln.
const MEGA_SPRUCH := (
	"Weißt du was? Ich wollte schon immer mal in den Funkelpark."
	+ " Ob die Lichter da WIRKLICH funkeln? Ich wünsch mir, dass wir"
	+ " uns mal sieben Tage am Stück sehen. Eine ganze Woche wir zwei!"
)

var _prev_size := Vector2i()
var _prev_insets := Rect2()


## Fenster VOR der Instanziierung pinnen (Geometrie-Tests, W17-Konvention).
func _pin_window(size: Vector2i) -> void:
	_prev_size = tree.root.size
	_prev_insets = UiScale.insets_override
	UiScale.insets_override = Rect2()
	tree.root.size = size
	tree.root.size_changed.emit()
	await wait_frames(2)


func _unpin_window() -> void:
	tree.root.size = _prev_size
	UiScale.insets_override = _prev_insets
	tree.root.size_changed.emit()
	await wait_frames(2)


## Blase zeigen (Zeit injiziert) und Geometrie-Handles zurückgeben.
func _zeige_blase(layer: Control, text: String) -> Dictionary:
	var bubble := AcBubble.show_bubble(layer, text, {"dauer_s": 600.0})
	bubble.auto_zeit = false
	var kapsel := bubble.get_node("Kapsel") as PanelContainer
	var label := bubble.get_node("Kapsel/BubbleText") as Label
	return {"bubble": bubble, "kapsel": kapsel, "label": label}


## Kern-Wache: Blase reserviert die ENDgröße vorab, wickelt an Wortgrenzen,
## Text-Rect ⊆ Blase, Blase ⊆ Bildschirm.
func _pruefe_blase_passt(text: String, kontext: String) -> void:
	AcBubble.warteschlange = AcBubble.Warteschlange.new()
	UiAnchors.reset_for_tests()
	var layer := Control.new()
	tree.root.add_child(layer)
	var teile := _zeige_blase(layer, text)
	var bubble: AcBubble = teile["bubble"]
	var kapsel: PanelContainer = teile["kapsel"]
	var label: Label = teile["label"]
	var reserviert: Vector2 = kapsel.size
	# Typewriter komplett durchticken; Layout settlen lassen.
	bubble.advance_time(600.0 / GoobyVoice.RATE)
	await wait_frames(3)
	bubble.advance_time(0.05)
	assert_almost(kapsel.size.x, reserviert.x, 1.0, "%s: kein Breiten-Nachruckeln" % kontext)
	assert_almost(kapsel.size.y, reserviert.y, 1.0, "%s: kein Höhen-Nachruckeln" % kontext)
	# Kein Clipping: das Label bekommt seine volle Minimalgröße.
	var label_min := label.get_combined_minimum_size()
	assert_true(
		label_min.x <= label.size.x + 0.5,
		"%s: Text-Breite passt (min %.1f > ist %.1f)" % [kontext, label_min.x, label.size.x]
	)
	assert_true(
		label_min.y <= label.size.y + 0.5,
		"%s: Text-Höhe passt (min %.1f > ist %.1f)" % [kontext, label_min.y, label.size.y]
	)
	# Text-Rect ⊆ Blasen-Rect (Layout-Werte, unabhängig von Pop-Scale).
	assert_true(
		label.position.x >= -0.5 and label.position.y >= -0.5,
		"%s: Label beginnt in der Kapsel" % kontext
	)
	assert_true(
		label.position.x + label.size.x <= kapsel.size.x + 0.5,
		"%s: Label endet in der Kapsel (Breite)" % kontext
	)
	assert_true(
		label.position.y + label.size.y <= kapsel.size.y + 0.5,
		"%s: Label endet in der Kapsel (Höhe)" % kontext
	)
	# Nie mehr Abriss mitten im Wort: wenn gewickelt wird, dann an
	# WORT-Grenzen (WORD_SMART), sonst Einzeiler ohne Deckel-Überschuss.
	var canvas := Vector2(tree.root.get_visible_rect().size)
	var f := UiScale.for_viewport(tree.root)
	var max_w := minf(canvas.x - 2.0 * AcBubble.RAND_GAP * f, AcBubble.MAX_WIDTH_PX * f)
	if label.autowrap_mode != TextServer.AUTOWRAP_OFF:
		assert_eq(
			label.autowrap_mode,
			TextServer.AUTOWRAP_WORD_SMART,
			"%s: Umbruch an Wortgrenzen" % kontext
		)
	assert_true(
		kapsel.size.x <= max_w + 0.5,
		"%s: Blase deckelt bei max_w (%.1f > %.1f)" % [kontext, kapsel.size.x, max_w]
	)
	# Blase ⊆ Bildschirm (inkl. Safe-Area-Klemmen in _positionieren).
	var rect := Rect2(kapsel.position, kapsel.size)
	assert_true(
		Rect2(Vector2.ZERO, canvas).grow(0.5).encloses(rect),
		"%s: Blase im Bildschirm (rect=%s canvas=%s)" % [kontext, rect, canvas]
	)
	layer.queue_free()
	await wait_frames(2)
	UiAnchors.reset_for_tests()
	AcBubble.warteschlange = AcBubble.Warteschlange.new()


func test_acbubble_langer_spruch_quer_beide_sprachen() -> void:
	await _pin_window(QUER)
	for locale: String in ["de", "en"]:
		I18nService.set_locale(locale)
		await _pruefe_blase_passt(I18nService.t(LANGER_KEY), "quer/%s/lang" % locale)
	I18nService.set_locale("de")
	await _pruefe_blase_passt(MEGA_SPRUCH, "quer/de/mega")
	await _unpin_window()


func test_acbubble_langer_spruch_hoch_beide_sprachen() -> void:
	await _pin_window(HOCH)
	for locale: String in ["de", "en"]:
		I18nService.set_locale(locale)
		await _pruefe_blase_passt(I18nService.t(LANGER_KEY), "hoch/%s/lang" % locale)
	I18nService.set_locale("de")
	await _pruefe_blase_passt(MEGA_SPRUCH, "hoch/de/mega")
	await _unpin_window()


func test_acbubble_kurzer_spruch_bleibt_kompakt() -> void:
	await _pin_window(QUER)
	AcBubble.warteschlange = AcBubble.Warteschlange.new()
	UiAnchors.reset_for_tests()
	var layer := Control.new()
	tree.root.add_child(layer)
	var teile := _zeige_blase(layer, I18nService.t(KURZER_KEY))
	var bubble: AcBubble = teile["bubble"]
	var kapsel: PanelContainer = teile["kapsel"]
	var label: Label = teile["label"]
	var reserviert: Vector2 = kapsel.size
	bubble.advance_time(600.0 / GoobyVoice.RATE)
	await wait_frames(3)
	assert_eq(label.autowrap_mode, TextServer.AUTOWRAP_OFF, "kurzer Spruch wickelt nicht")
	assert_almost(kapsel.size.x, reserviert.x, 1.0, "kompakt: Endgröße stand vorab fest")
	var natuerlich := kapsel.get_combined_minimum_size()
	assert_almost(kapsel.size.x, natuerlich.x, 0.5, "Blase wächst nicht unnötig (Breite)")
	assert_almost(kapsel.size.y, natuerlich.y, 0.5, "Blase wächst nicht unnötig (Höhe)")
	layer.queue_free()
	await wait_frames(2)
	UiAnchors.reset_for_tests()
	AcBubble.warteschlange = AcBubble.Warteschlange.new()
	await _unpin_window()


## DialogBubble (Stadt-Modus ohne HUD): Höhe wächst pro Zeile mit dem Text
## (vorher maß _relayout nur den ALTEN Text — lange Zeilen verloren unten
## ganze Zeilen) und schrumpft für kurze Folge-Zeilen zurück.
func test_dialogbubble_zeilen_hoehe_waechst_und_schrumpft() -> void:
	await _pin_window(QUER)
	UiAnchors.reset_for_tests()
	var db := (
		(load("res://scripts/ui/dialog_bubble.tscn") as PackedScene).instantiate() as DialogBubble
	)
	db.sofort_override = 1
	tree.root.add_child(db)
	await wait_frames(1)
	var panel := db.get_node("%Bubble") as PanelContainer
	var label := db.get_node("%BubbleText") as Label
	var szenen_top := panel.offset_top
	var zeilen: Array[String] = [MEGA_SPRUCH, I18nService.t(KURZER_KEY)]
	db.show_lines(zeilen)
	await wait_frames(3)
	var label_min := label.get_combined_minimum_size()
	assert_true(
		label_min.y <= label.size.y + 0.5,
		"lange Zeile: keine verlorenen Zeilen (min %.1f > ist %.1f)" % [label_min.y, label.size.y]
	)
	assert_true(
		panel.size.y >= panel.get_combined_minimum_size().y - 0.5, "lange Zeile: Kapsel hoch genug"
	)
	assert_true(panel.offset_top <= szenen_top, "lange Zeile: Oberkante wächst nach oben")
	# Weiterblättern auf die kurze Zeile → Szenen-Höhe kehrt zurück.
	db._advance()
	await wait_frames(2)
	assert_almost(panel.offset_top, szenen_top, 0.5, "kurze Zeile: Szenen-Höhe wieder da")
	db.queue_free()
	await wait_frames(2)
	UiAnchors.reset_for_tests()
	await _unpin_window()


## Text-Fit-Stelle Füttern-Grid: Speise-Name ist ein Listen-Chip — längster
## ECHTER Name beider Sprachen darf nie mitten im Wort hart abreißen
## (clip nur MIT Ellipsis), und das Label bleibt in der Karte.
func test_textfit_fuettern_speise_name() -> void:
	await _pin_window(QUER)
	for locale: String in ["de", "en"]:
		I18nService.set_locale(locale)
		var food_id := _laengste_food_id()
		var grid := FuetterGrid.new()
		tree.root.add_child(grid)
		var entries: Array[Dictionary] = [{"id": food_id, "count": 1}]
		grid.setup(entries)
		await wait_frames(2)
		var karte := grid.find_child("Karte_%s" % food_id, true, false) as Control
		assert_true(karte != null, "%s: Karte da" % locale)
		var label := _clip_label_in(karte)
		assert_true(label != null, "%s: Namens-Label gefunden" % locale)
		if label != null:
			assert_eq(label.text, FoodCatalog.display_name(food_id), "%s: echter Name" % locale)
			assert_eq(
				label.text_overrun_behavior,
				TextServer.OVERRUN_TRIM_ELLIPSIS,
				"%s: Ellipsis statt Wort-Abriss" % locale
			)
			assert_true(
				label.size.x <= karte.size.x + 0.5, "%s: Label bleibt in der Karte" % locale
			)
		grid.queue_free()
		await wait_frames(2)
	I18nService.set_locale("de")
	await _unpin_window()


## Text-Fit-Stelle Sammlungen: Set-Titel, Kachel-Unterschrift und
## Status-Zeile kürzen mit Ellipsis statt mitten im Wort zu reißen —
## geprüft mit den längsten echten Set-/Eintrags-Strings beider Sprachen.
func test_textfit_sammlungen_ellipsis() -> void:
	await _pin_window(QUER)
	for locale: String in ["de", "en"]:
		I18nService.set_locale(locale)
		var view := CollectionsView.new()
		tree.root.add_child(view)
		view.position = Vector2.ZERO
		view.size = Vector2(700.0, 900.0)
		view.setup(null)
		await wait_frames(2)
		var card := view.find_child("SetCard_landmarks", true, false) as Control
		assert_true(card != null, "%s: landmarks-Karte da" % locale)
		var geprueft := 0
		for label: Label in _alle_clip_labels(card):
			assert_eq(
				label.text_overrun_behavior,
				TextServer.OVERRUN_TRIM_ELLIPSIS,
				"%s: „%s“ kürzt mit Ellipsis" % [locale, label.text]
			)
			geprueft += 1
		assert_true(geprueft >= 3, "%s: Titel + Unterschriften + Status geprüft" % locale)
		var titel := _clip_label_in(card)
		if titel != null:
			assert_eq(
				titel.text, I18nService.t("collections.set.landmarks"), "%s: echter Titel" % locale
			)
		view.queue_free()
		await wait_frames(2)
	I18nService.set_locale("de")
	await _unpin_window()


## Text-Fit-Stelle Album: Namensband der Sticker-Kachel kürzt mit Ellipsis
## (längster echter Sticker-Name aus content/stickers).
func test_textfit_album_namensband() -> void:
	var album := AlbumScreen.new()
	var def := {"name_de": _laengster_sticker_name(), "rarity": "haeufig"}
	var band := album._build_name_band(def, true)
	tree.root.add_child(band)
	await wait_frames(1)
	var label := _clip_label_in(band)
	assert_true(label != null, "Namens-Label da")
	if label != null:
		assert_eq(label.text, str(def["name_de"]), "echter längster Sticker-Name")
		assert_eq(
			label.text_overrun_behavior,
			TextServer.OVERRUN_TRIM_ELLIPSIS,
			"Namensband kürzt mit Ellipsis"
		)
	band.queue_free()
	await wait_frames(2)
	album.free()


# ── Helfer ───────────────────────────────────────────────────────────────────


## Erstes Label mit clip_text unterhalb von `wurzel` (Aufbau-Reihenfolge).
func _clip_label_in(wurzel: Node) -> Label:
	for label in _alle_clip_labels(wurzel):
		return label
	return null


func _alle_clip_labels(wurzel: Node) -> Array[Label]:
	var out: Array[Label] = []
	if wurzel == null:
		return out
	for node: Node in wurzel.find_children("", "Label", true, false):
		if node is Label and (node as Label).clip_text:
			out.append(node as Label)
	return out


## Speise mit dem längsten Anzeige-Namen in der AKTIVEN Sprache.
func _laengste_food_id() -> String:
	var beste := ""
	var laenge := -1
	for id: String in FoodCatalog.FOODS:
		var name_laenge := FoodCatalog.display_name(id).length()
		if name_laenge > laenge:
			laenge = name_laenge
			beste = id
	return beste


## Längster echter Sticker-Name (content/stickers/data/stickers.json).
func _laengster_sticker_name() -> String:
	var beste := "Nutella-Kommandant"
	for def: Variant in StickerCatalog.all():
		if def is Dictionary:
			var name := str((def as Dictionary).get("name_de", ""))
			if name.length() > beste.length():
				beste = name
	return beste

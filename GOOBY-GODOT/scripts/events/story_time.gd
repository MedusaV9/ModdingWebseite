class_name StoryTime
extends Node3D
## Geschichten-Stunde M1 (W3d CONTENT, Doc F §3.2): Buch-Sheet mit
## Lückentext links (3 Lücken) und 6 Wort-Chips rechts (Tap setzt ins
## nächste freie Feld). Falsche Wörter sind ERLAUBT (= lustigere Geschichte,
## Gooby kichert im Schlaf) — nach der dritten Lücke schläft Gooby ein
## (sleep-Clip). Geschichten kommen als Daten aus dem W2b-Pack
## content/events/data/stories.json (Domain "stories").
##
## M2-BACKLOG-MARKER: Entertainment-Wert (benötigte Wörter =
## f(entertainment, Abnutzung), „schon 5× gelesen…“) + Bücher-Shop/POW! —
## das Datenfeld `entertainment` ist dafür schon im Pack.

const DOMAIN := "stories"
const GAP_PLACEHOLDER := "____"

var _host: InteractablesHost
var _sheet: PanelSheet
var _story: Dictionary = {}
var _fills: Array = []
var _sentence_labels: Array = []
var _rng := RandomNumberGenerator.new()


## Geschichten aus der ContentRegistry (leer ohne Autoload).
static func stories_from_registry() -> Array:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return []
	var registry := (loop as SceneTree).root.get_node_or_null("/root/ContentRegistry")
	if registry == null or not registry.has_method("get_items"):
		return []
	return registry.get_items(DOMAIN)


# ── pure Lücken-Logik (headless testbar) ─────────────────────────────────────


## Frischer Füllstand (eine null-Zelle pro Lücke).
static func empty_fills(story: Dictionary) -> Array:
	var fills: Array = []
	for _i in (story.get("luecken", []) as Array).size():
		fills.append(null)
	return fills


## Wort in die erste freie Lücke setzen. Gibt den Lücken-Index zurück
## (-1 = alles voll). Mutiert `fills`.
static func place_word(fills: Array, word_id: String) -> int:
	for i in fills.size():
		if fills[i] == null:
			fills[i] = word_id
			return i
	return -1


static func is_complete(fills: Array) -> bool:
	for fill: Variant in fills:
		if fill == null:
			return false
	return not fills.is_empty()


## Stimmt das Wort in Lücke `gap_index` mit der Vorlage überein?
static func is_correct(story: Dictionary, gap_index: int, word_id: String) -> bool:
	var luecken: Array = story.get("luecken", [])
	return gap_index >= 0 and gap_index < luecken.size() and str(luecken[gap_index]) == word_id


## Anzahl „falscher“ (= lustiger) Wörter im kompletten Füllstand.
static func wrong_count(story: Dictionary, fills: Array) -> int:
	var wrong := 0
	for i in fills.size():
		if fills[i] != null and not is_correct(story, i, str(fills[i])):
			wrong += 1
	return wrong


## Sätze mit eingesetzten Wörtern rendern ({0}/{1}/{2} → Worttext oder ____).
static func rendered_sentences(story: Dictionary, fills: Array) -> Array:
	var words := {}
	for word: Dictionary in story.get("woerter_de", []):
		words[str(word.get("id", ""))] = str(word.get("text", ""))
	var result: Array = []
	for sentence: Variant in story.get("saetze_de", []):
		var text := str(sentence)
		for i in fills.size():
			var token := "{%d}" % i
			var value: String = GAP_PLACEHOLDER
			if fills[i] != null:
				value = str(words.get(str(fills[i]), str(fills[i])))
			text = text.replace(token, value)
		result.append(text)
	return result


# ── Interactable + Buch-UI ───────────────────────────────────────────────────


func setup(host: InteractablesHost, furniture: Node3D) -> void:
	_host = host
	_rng.randomize()
	add_child(InteractablesHost.make_tap_area(furniture, _on_tapped))


func _on_tapped() -> void:
	var room := _host.room()
	if room != null and room.has_method("is_build_mode_active") and room.is_build_mode_active():
		return
	var stories := stories_from_registry()
	if stories.is_empty():
		return
	open_book(stories[_rng.randi_range(0, stories.size() - 1)])


## Buch-Sheet für eine Geschichte öffnen (Screenshots/Tests rufen direkt).
func open_book(story: Dictionary) -> void:
	_story = story
	_fills = empty_fills(story)
	if _sheet == null:
		_sheet = (load("res://scripts/ui/panel_sheet.tscn") as PackedScene).instantiate()
		# Theme explizit setzen: Window-Theme propagiert NICHT durch CanvasLayer.
		_sheet.theme = ThemeService.theme()
		_ui_layer().add_child(_sheet)
	_sheet.set_title(str(story.get("titel_de", "")))
	_sheet.add_content(_build_book())
	_sheet.open()


func _build_book() -> Control:
	var book := HBoxContainer.new()
	book.add_theme_constant_override("separation", 18)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.4
	left.add_theme_constant_override("separation", 10)
	book.add_child(left)
	_sentence_labels = []
	for sentence: String in rendered_sentences(_story, _fills):
		var label := Label.new()
		label.text = sentence
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Min-Breite MUSS gesetzt sein: ohne sie meldet ein Autowrap-Label im
		# ersten Layout-Pass (Breite 0) eine riesige Min-Höhe — das Sheet
		# wächst dann einmalig auf Tausende px und friert so ein.
		label.custom_minimum_size = Vector2(260.0, 0.0)
		left.add_child(label)
		_sentence_labels.append(label)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	book.add_child(right)
	var hint := Label.new()
	hint.theme_type_variation = &"CaptionLabel"
	hint.text = I18nService.t("events.story.hinweis")
	right.add_child(hint)
	var chip_grid := GridContainer.new()
	chip_grid.columns = 2
	chip_grid.add_theme_constant_override("h_separation", 8)
	chip_grid.add_theme_constant_override("v_separation", 8)
	right.add_child(chip_grid)
	for word: Dictionary in _story.get("woerter_de", []):
		var chip := SquishButton.new()
		chip.name = "Wort_%s" % str(word.get("id", ""))
		chip.theme_type_variation = &"ChipSky"
		chip.text = str(word.get("text", ""))
		chip.focus_mode = Control.FOCUS_NONE
		chip.pressed.connect(_on_word_tapped.bind(str(word.get("id", "")), chip))
		chip_grid.add_child(chip)
	return book


func _on_word_tapped(word_id: String, chip: Button) -> void:
	var gap := StoryTime.place_word(_fills, word_id)
	if gap < 0:
		return
	chip.disabled = true
	_refresh_sentences()
	if StoryTime.is_complete(_fills):
		_finish_story()


func _refresh_sentences() -> void:
	var rendered := rendered_sentences(_story, _fills)
	for i in _sentence_labels.size():
		if i < rendered.size():
			(_sentence_labels[i] as Label).text = rendered[i]


## Geschichte fertig: Gooby schläft ein; falsche Wörter → Kichern.
func _finish_story() -> void:
	var wrong := wrong_count(_story, _fills)
	var room := _host.room() if _host != null else null
	if room != null and room.has_method("say"):
		var key := "events.story.kichern" if wrong > 0 else "events.story.einschlafen"
		room.say(I18nService.t(key))
	if is_inside_tree():
		await get_tree().create_timer(1.6).timeout
	if _sheet != null:
		_sheet.close()
	var gooby: Node = room.gooby() if room != null and room.has_method("gooby") else null
	if gooby != null:
		gooby.set_wander_enabled(false)
		gooby.play_clip("sleep")


func _ui_layer() -> CanvasLayer:
	if _host == null:
		var fallback := CanvasLayer.new()
		fallback.name = "W3dUiLayer"
		add_child(fallback)
		return fallback
	var existing := _host.get_node_or_null("W3dUiLayer")
	if existing is CanvasLayer:
		return existing
	var layer := CanvasLayer.new()
	layer.name = "W3dUiLayer"
	layer.layer = 6
	_host.add_child(layer)
	return layer

class_name StoryTime
extends Node3D
## Geschichten-Stunde (W3d CONTENT + W13B GESCHICHTEN, Doc F §3.2): Buch-Sheet
## mit Lückentext links (3 Lücken) und 6 Wort-Chips rechts (Tap setzt ins
## nächste freie Feld). Falsche Wörter sind ERLAUBT (= lustigere Geschichte,
## Gooby kichert im Schlaf). Geschichten kommen als Daten aus Packs:
## legacy content/events/data/stories.json (Domain "stories") und seit W13B
## der Bücher-Katalog content/books/data/books.json (Domain "books",
## StoryBooks) — 6 Bücher mit je 2–3 Geschichten.
##
## W13B löst den M2-Backlog-Marker ein: `open_library()` zeigt Goobys
## Bücherregal (Startbuch gratis, Rest via REHWEI), eine Vorlese-Session
## braucht `StoryBooks.needed_words(entertainment, reads)` eingesetzte
## Wörter — abgenutzte Bücher (viele reads) brauchen also mehr Seiten, die
## UI sagt es („Das kennt Gooby schon fast auswendig …“). Jede Runde nutzt
## das Buch ab (reads +1 im "story"-Slice).

const DOMAIN := "stories"
const GAP_PLACEHOLDER := "____"

var _host: InteractablesHost
var _sheet: PanelSheet
var _story: Dictionary = {}
var _fills: Array = []
var _sentence_labels: Array = []
var _rng := RandomNumberGenerator.new()
## W13B-Session (leer = Legacy-Einzelgeschichte ohne Buch/Abnutzung).
var _session_book: Dictionary = {}
var _session_pages: Array = []
var _session_page_index := 0
var _session_needed := 0
var _session_placed := 0
var _session_wrong := 0


## Geschichten aus der ContentRegistry (leer ohne Autoload).
static func stories_from_registry() -> Array:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return []
	var registry := (loop as SceneTree).root.get_node_or_null("/root/ContentRegistry")
	if registry == null or not registry.has_method("get_items"):
		return []
	return registry.get_items(DOMAIN)


## Gibt es überhaupt Lesestoff (Bücher-Katalog ODER Legacy-Stories)?
static func story_option_available() -> bool:
	if not StoryBooks.books_from_registry().is_empty():
		return true
	return not stories_from_registry().is_empty()


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


## Slice-Registrierung durchreichen (home_entry ruft EINE Zeile).
static func register_slice() -> void:
	StoryBooks.register_slice()


# ── Interactable + Buch-UI ───────────────────────────────────────────────────


func setup(host: InteractablesHost, furniture: Node3D) -> void:
	_host = host
	_rng.randomize()
	add_child(InteractablesHost.make_tap_area(furniture, _on_tapped))


func _on_tapped() -> void:
	var room := _host.room()
	if room != null and room.has_method("is_build_mode_active") and room.is_build_mode_active():
		return
	if not StoryBooks.books_from_registry().is_empty():
		open_library()
		return
	var stories := stories_from_registry()
	if stories.is_empty():
		return
	open_book(stories[_rng.randi_range(0, stories.size() - 1)])


## Goobys Bücherregal (W13B): eigene Bücher antippbar (mit Abnutzungs-
## Hinweis), gesperrte zeigen den REHWEI-Preis. Tap startet die Session.
func open_library() -> void:
	var books := StoryBooks.books_from_registry()
	if books.is_empty():
		return
	_open_sheet()
	_sheet.set_title(I18nService.t("sleep.story.bibliothek_titel"))
	_sheet.add_content(_build_library(books))
	_sheet.open()


## Buch-Sheet für EINE Geschichte öffnen (Legacy-Pfad ohne Buch/Abnutzung;
## Screenshots/Tests rufen direkt).
func open_book(story: Dictionary) -> void:
	_session_book = {}
	_session_pages = []
	_open_page(story)


# ── Bücherregal ──────────────────────────────────────────────────────────────


func _build_library(books: Array) -> Control:
	var state := _game_state_dict()
	var owned := StoryBooks.owned_book_ids(books, state)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var hint := Label.new()
	hint.theme_type_variation = &"CaptionLabel"
	hint.text = I18nService.t("sleep.story.waehlen")
	box.add_child(hint)
	for book: Dictionary in books:
		box.add_child(_library_row(book, owned.has(str(book.get("id", ""))), state))
	var nachschub := Label.new()
	nachschub.theme_type_variation = &"CaptionLabel"
	nachschub.text = I18nService.t("sleep.story.nachschub")
	nachschub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nachschub.custom_minimum_size = Vector2(280.0, 0.0)
	box.add_child(nachschub)
	return box


func _library_row(book: Dictionary, owned: bool, state: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var btn := SquishButton.new()
	btn.name = "Buch_%s" % str(book.get("id", ""))
	btn.theme_type_variation = &"AccentButton"
	btn.text = str(book.get("titel_de", ""))
	btn.custom_minimum_size = Vector2(0, 48)
	btn.focus_mode = Control.FOCUS_NONE
	var caption := Label.new()
	caption.theme_type_variation = &"CaptionLabel"
	if owned:
		btn.pressed.connect(_on_book_chosen.bind(book))
		caption.text = _wear_caption(state, book)
	else:
		btn.disabled = true
		caption.text = I18nService.t("sleep.story.gesperrt", {"preis": int(book.get("preis", 0))})
	row.add_child(btn)
	row.add_child(caption)
	return row


func _wear_caption(state: Dictionary, book: Dictionary) -> String:
	var reads := StoryBooks.reads_of(state, str(book.get("id", "")))
	if StoryBooks.is_worn(reads):
		return I18nService.t("sleep.story.abgenutzt")
	if reads > 0:
		return I18nService.t("sleep.story.gelesen", {"mal": reads})
	return I18nService.t("sleep.story.frisch")


func _on_book_chosen(book: Dictionary) -> void:
	AudioDirector.try_play(self, "ui_click")
	var stories := StoryBooks.stories_of(book)
	if stories.is_empty():
		return
	var state := _game_state_dict()
	var reads := StoryBooks.reads_of(state, str(book.get("id", "")))
	_session_book = book
	_session_pages = stories.duplicate()
	_session_pages.shuffle()
	_session_page_index = 0
	# W13C (Request GOOBYMAN, H §6.4): gekaufte Schlafmaske = 10 % weniger
	# Vorlese-Wörter bis zum Einschlafen (Boden StoryBooks.WORDS_MIN).
	_session_needed = GoobymanKatalog.schlafmaske_woerter(
		StoryBooks.needed_words(int(book.get("entertainment", 1)), reads),
		GoobymanKatalog.schlafmaske_gekauft(state)
	)
	_session_placed = 0
	_session_wrong = 0
	if StoryBooks.is_worn(reads):
		_say(I18nService.t("sleep.story.abgenutzt"))
	_open_page(_session_pages[0])


# ── Buch-Seite (Lückentext) ──────────────────────────────────────────────────


func _open_page(story: Dictionary) -> void:
	_story = story
	_fills = empty_fills(story)
	_open_sheet()
	_sheet.set_title(str(story.get("titel_de", "")))
	_sheet.add_content(_build_book())
	_sheet.open()


func _open_sheet() -> void:
	if _sheet != null:
		return
	_sheet = (load("res://scripts/ui/panel_sheet.tscn") as PackedScene).instantiate()
	# Theme explizit setzen: Window-Theme propagiert NICHT durch CanvasLayer.
	_sheet.theme = ThemeService.theme()
	_ui_layer().add_child(_sheet)


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
	if _session_book.is_empty():
		if StoryTime.is_complete(_fills):
			_finish_story(wrong_count(_story, _fills))
		return
	_session_placed += 1
	if not is_correct(_story, gap, word_id):
		_session_wrong += 1
	if _session_placed >= _session_needed:
		_finish_session()
	elif StoryTime.is_complete(_fills):
		_next_page()


func _refresh_sentences() -> void:
	var rendered := rendered_sentences(_story, _fills)
	for i in _sentence_labels.size():
		if i < rendered.size():
			(_sentence_labels[i] as Label).text = rendered[i]


## Buch noch nicht „leer genug“: Gooby ist wach — nächste Seite/Geschichte
## (bei starker Abnutzung auch reihum, Doc F §3.2 „mehr Wörter/Seiten“).
func _next_page() -> void:
	_say(I18nService.t("sleep.story.naechste_seite"))
	_session_page_index = (_session_page_index + 1) % _session_pages.size()
	_open_page(_session_pages[_session_page_index])


## Session fertig: Buch abnutzen (reads +1), dann einschlafen.
func _finish_session() -> void:
	var gs: Object = _host.game_state() if _host != null else null
	if gs != null:
		StoryBooks.bump_read(gs, str(_session_book.get("id", "")))
	var wrong := _session_wrong
	_session_book = {}
	_session_pages = []
	_finish_story(wrong)


## Geschichte fertig: Gooby schläft ein; falsche Wörter → Kichern.
func _finish_story(wrong: int) -> void:
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


func _game_state_dict() -> Dictionary:
	var gs: Object = _host.game_state() if _host != null else null
	if gs != null and gs.has_method("state"):
		return gs.state()
	return {}


func _say(text: String) -> void:
	var room := _host.room() if _host != null else null
	if room != null and room.has_method("say"):
		room.say(text)


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

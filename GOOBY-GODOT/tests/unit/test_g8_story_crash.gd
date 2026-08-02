extends TestCase
## G8-PT4 B1 (BLOCKER-Regression): Buch öffnen im Gute-Nacht-Bücherregal
## crashte hart (Signal 11) — story_time._setze_inhalt lief IM
## pressed-Signal des Buch-Knopfs und gab die Bibliotheks-Ansicht mit
## einem harten free() frei, MITSAMT dem noch emittierenden Knopf
## („Object … was freed or unreferenced while a signal is being
## emitted“). Dieselbe Kette drohte beim Seitenwechsel über die
## Wort-Chips (_on_word_tapped → _next_page). Die Tests drücken die
## ECHTEN Knöpfe (pressed.emit läuft synchron im Emissions-Rahmen) und
## prüfen, dass der emittierende Knopf die Ansichts-Ablösung überlebt
## (queue_free statt free) und die Folge-Ansicht steht.
## Dazu G8-PT4 B8 / PT2 B7: ThemeService.is_reduced_motion loggte für
## genau solche abgebauten Knöpfe get_node-Errors (absoluter Pfad
## außerhalb des Baums, SquishButton._on_up NACH dem pressed-Abbau) —
## außerhalb des Baums muss der Lookup über den MainLoop-Root gehen.

const GameStateScript := preload("res://scripts/state/game_state.gd")

const BOOKS_JSON := "res://content/books/data/books.json"
const NOW_MS := 1768478400000

var _dir_seq := 0


func _books() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOOKS_JSON))
	assert_true(parsed is Dictionary, "books.json parst")
	return parsed.get("items", []) if parsed is Dictionary else []


func _fresh_game_state() -> Node:
	StoryBooks.register_slice()
	_dir_seq += 1
	var dir := "user://g8_tests/story_crash_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	return gs


## Kompletter Geschichten-Aufbau wie im Spiel: GameState, Raum + Host,
## StoryTime und ein Registry-Stub mit dem ECHTEN Bücher-Katalog — läuft
## das echte ContentRegistry-Autoload, wird der Stub nur umbenannt und
## der Katalog kommt von dort (gleiche Daten, beide Welten grün). Danach
## steht die Bibliothek offen (wie nach dem Bettzeit-Tap im Spiel).
func _bibliothek_aufbau() -> Dictionary:
	var gs := _fresh_game_state()
	var registry := FakeRegistry.new()
	registry.name = "ContentRegistry"
	registry.books = _books()
	tree.root.add_child(registry)
	var room := FakeStoryRoom.new()
	room.gs = gs
	tree.root.add_child(room)
	var host := InteractablesHost.attach_to(room)
	var story_time := StoryTime.new()
	room.add_child(story_time)
	story_time._host = host
	story_time.open_library()
	await wait_frames(1)
	return {"gs": gs, "registry": registry, "room": room, "story_time": story_time}


func _raeume_auf(aufbau: Dictionary) -> void:
	# Pendente queue_frees (abgelöste Ansichten) erst abfließen lassen.
	await wait_frames(2)
	PanelStack.clear()
	(aufbau["room"] as Node).queue_free()
	# Der Registry-Stub wird per NAME gefunden — sofort abhängen, damit
	# der nächste Test seinen frischen Stub unter demselben Namen kriegt.
	tree.root.remove_child(aufbau["registry"])
	(aufbau["registry"] as Node).free()
	await wait_frames(1)
	(aufbau["gs"] as Node).free()


## B1-Hauptpfad: Startbuch-Knopf emittiert pressed → Handler löst die
## Bibliothek ab. Vor dem Fix starb der Knopf mitten in der Emission.
func test_buch_tap_ueberlebt_bibliotheks_abloesung() -> void:
	var aufbau: Dictionary = await _bibliothek_aufbau()
	var story_time: StoryTime = aufbau["story_time"]
	var bibliothek: Control = story_time._inhalt
	assert_true(is_instance_valid(bibliothek), "Bibliotheks-Ansicht hängt im Sheet")
	var knopf := bibliothek.find_child("Buch_buch_moehrenmond", true, false) as Button
	assert_true(knopf != null, "Startbuch-Knopf steht im Regal")
	if knopf == null:
		await _raeume_auf(aufbau)
		return
	knopf.pressed.emit()
	assert_true(
		is_instance_valid(knopf),
		"emittierender Buch-Knopf überlebt die Ablösung (queue_free statt free)"
	)
	assert_true(
		is_instance_valid(bibliothek) and bibliothek.is_queued_for_deletion(),
		"alte Ansicht ist zum Frame-Ende freigegeben (kein Leak)"
	)
	assert_eq(story_time._ansicht, "buch", "Buchseite ist offen")
	assert_true(story_time._sheet.is_open(), "Sheet bleibt offen")
	assert_true(is_instance_valid(story_time._inhalt), "neue Ansicht hängt")
	assert_ne(story_time._inhalt, bibliothek, "Inhalt wurde ersetzt")
	var grid := story_time._inhalt.find_child("WortGrid", true, false)
	assert_true(grid != null, "Wort-Chips der ersten Seite stehen")
	await wait_frames(2)
	assert_false(is_instance_valid(bibliothek), "Bibliothek ist deferred freigegeben")
	await _raeume_auf(aufbau)


## B1-Nebenpfad: bei abgenutztem Buch (6 nötige Wörter) füllt der dritte
## Wort-Chip die Seite → _next_page ersetzt die Ansicht IM pressed-Signal
## des Chips — derselbe free()-Crash drohte hier.
func test_wort_chip_ueberlebt_seitenwechsel() -> void:
	var aufbau: Dictionary = await _bibliothek_aufbau()
	var story_time: StoryTime = aufbau["story_time"]
	var gs: Node = aufbau["gs"]
	var buch := StoryBooks.book_by_id(_books(), "buch_moehrenmond")
	for _i in 6:
		StoryBooks.bump_read(gs, "buch_moehrenmond")
	story_time._on_book_chosen(buch)
	assert_eq(story_time._session_needed, 6, "abgenutzt: mehr als eine Seite nötig")
	var seite: Control = story_time._inhalt
	var letzter_chip: Button = null
	for _runde in 3:
		var chip := _erster_freier_chip(story_time._inhalt)
		assert_true(chip != null, "freier Wort-Chip vorhanden")
		if chip == null:
			break
		letzter_chip = chip
		chip.pressed.emit()
	assert_true(
		letzter_chip != null and is_instance_valid(letzter_chip),
		"emittierender Wort-Chip überlebt den Seitenwechsel"
	)
	assert_eq(story_time._session_placed, 3, "3 Wörter gesetzt")
	assert_eq(story_time._session_page_index, 1, "zweite Seite ist aktiv")
	assert_true(is_instance_valid(story_time._inhalt), "neue Seite hängt")
	assert_ne(story_time._inhalt, seite, "Seiten-Ansicht wurde ersetzt")
	await wait_frames(2)
	assert_false(is_instance_valid(seite), "alte Seite ist deferred freigegeben")
	await _raeume_auf(aufbau)


## B8: der Reduced-Motion-Lookup darf außerhalb des Baums weder einen
## get_node-Error loggen noch den Autoload-Wert verlieren — genau das
## passierte, wenn ein pressed-Handler den Knopf abbaut und
## SquishButton._on_up danach fragte (6× pro Telefon-Lauf, PT4 B8).
## Läuft mit dem ECHTEN UiTheme-Autoload (Haupt-Runner) genauso wie mit
## einem Stub (isolierte Bäume ohne Autoloads).
func test_reduced_motion_lookup_ausserhalb_des_baums() -> void:
	var svc: Node = tree.root.get_node_or_null("/root/UiTheme")
	var stub: Node = null
	if svc == null:
		stub = FakeUiTheme.new()
		stub.name = "UiTheme"
		tree.root.add_child(stub)
		svc = stub
	var vorher: bool = svc.reduced_motion
	svc.reduced_motion = true
	var drinnen := Node.new()
	tree.root.add_child(drinnen)
	var draussen := Node.new()
	assert_true(ThemeService.is_reduced_motion(drinnen), "im Baum: Autoload-Wert gelesen")
	assert_true(
		ThemeService.is_reduced_motion(draussen),
		"außerhalb des Baums: MainLoop-Fallback liest denselben Wert"
	)
	svc.reduced_motion = vorher
	if stub != null:
		tree.root.remove_child(stub)
		stub.free()
		assert_false(ThemeService.is_reduced_motion(draussen), "ohne UiTheme still false")
	tree.root.remove_child(drinnen)
	drinnen.free()
	draussen.free()


## Erster tippbarer Wort-Chip der offenen Buchseite (DOM-Reihenfolge).
func _erster_freier_chip(inhalt: Control) -> Button:
	if inhalt == null or not is_instance_valid(inhalt):
		return null
	var grid := inhalt.find_child("WortGrid", true, false)
	if grid == null:
		return null
	for kind in grid.get_children():
		var chip := kind as Button
		if chip != null and not chip.disabled:
			return chip
	return null


## Minimal-Raum für die StoryTime-Session (Muster test_w13b_geschichten).
class FakeStoryRoom:
	extends Node3D

	var gs: Object

	func game_state() -> Object:
		return gs


## Registry-Stub: liefert den echten Bücher-Katalog unter /root/ContentRegistry.
class FakeRegistry:
	extends Node

	var books: Array = []

	func get_items(domain: String) -> Array:
		return books if domain == "books" else []


## UiTheme-Stub mit gesetztem Reduced-Motion-Flag (B8-Lookup-Test).
class FakeUiTheme:
	extends Node

	var reduced_motion := true

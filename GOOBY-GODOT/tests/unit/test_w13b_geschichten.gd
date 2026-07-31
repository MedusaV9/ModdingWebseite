extends TestCase
## W13B GESCHICHTEN — Bücher-Katalog (content/books), Lückentext-Validierung
## aller neuen Geschichten, Abnutzungsformel + story-Slice (reads →
## Einschlaf-Schwelle steigt), Besitz (Startbuch-Migration für Bestands-
## Saves) und REHWEI-Kauf (HaendlerSheet → inventory.items → Bibliothek).

const GameStateScript := preload("res://scripts/state/game_state.gd")

const BOOKS_JSON := "res://content/books/data/books.json"
const REHWEI_JSON := "res://scripts/city/data/rehwei_sortiment.json"
const NOW_MS := 1768478400000
const MIN_POOL := 4

var _dir_seq := 0


func _books() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOOKS_JSON))
	assert_true(parsed is Dictionary, "books.json parst")
	return parsed.get("items", []) if parsed is Dictionary else []


func _rehwei() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REHWEI_JSON))
	assert_true(parsed is Dictionary, "rehwei_sortiment.json parst")
	return parsed if parsed is Dictionary else {}


func _start_book(books: Array) -> Dictionary:
	for book: Dictionary in books:
		if bool(book.get("start", false)):
			return book
	return {}


func _fresh_game_state() -> Node:
	StoryBooks.register_slice()
	_dir_seq += 1
	var dir := "user://w13b_tests/geschichten_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	return gs


func test_buecher_katalog_daten() -> void:
	var books := _books()
	assert_true(books.size() >= 6, "mindestens 6 Bücher (got %d)" % books.size())
	var book_ids := {}
	var story_ids := {}
	var start_count := 0
	var story_total := 0
	for book: Dictionary in books:
		var book_id := str(book.get("id", ""))
		assert_false(book_id.is_empty(), "Buch hat id")
		assert_false(book_ids.has(book_id), "Buch-Id eindeutig: %s" % book_id)
		book_ids[book_id] = true
		assert_false(str(book.get("titel_de", "")).is_empty(), book_id + ": titel_de")
		assert_true(int(book.get("entertainment", 0)) >= 1, book_id + ": entertainment")
		assert_true(int(book.get("preis", -1)) >= 0, book_id + ": preis")
		if bool(book.get("start", false)):
			start_count += 1
			assert_eq(int(book.get("preis", -1)), 0, "Startbuch ist gratis")
		var stories := StoryBooks.stories_of(book)
		assert_true(
			stories.size() >= 2 and stories.size() <= 3,
			"%s: 2–3 Geschichten (got %d)" % [book_id, stories.size()]
		)
		story_total += stories.size()
		for story: Dictionary in stories:
			var sid := str(story.get("id", ""))
			assert_false(story_ids.has(sid), "Story-Id global eindeutig: %s" % sid)
			story_ids[sid] = true
			_check_story(book_id, story)
	assert_eq(start_count, 1, "genau EIN Startbuch")
	assert_true(story_total >= 12, "mindestens 12 neue Geschichten (got %d)" % story_total)


## Lückentext-Vertrag je Geschichte: 3 Lücken, Tokens im Text, Pool >= 4
## mit eindeutigen Wort-Ids, jede Lücke hat GENAU 1 richtige Option im Pool.
func _check_story(book_id: String, story: Dictionary) -> void:
	var sid := "%s/%s" % [book_id, str(story.get("id", ""))]
	assert_false(str(story.get("titel_de", "")).is_empty(), sid + ": titel_de")
	var luecken: Array = story.get("luecken", [])
	assert_eq(luecken.size(), 3, sid + ": 3 Lücken")
	var woerter: Array = story.get("woerter_de", [])
	assert_true(woerter.size() >= MIN_POOL, sid + ": Pool >= 4 (got %d)" % woerter.size())
	var pool_counts := {}
	for word: Dictionary in woerter:
		var wid := str(word.get("id", ""))
		assert_false(str(word.get("text", "")).is_empty(), sid + ": Wort-Text " + wid)
		pool_counts[wid] = int(pool_counts.get(wid, 0)) + 1
	for wid: String in pool_counts:
		assert_eq(pool_counts[wid], 1, "%s: Wort-Id '%s' nur einmal im Pool" % [sid, wid])
	var gap_seen := {}
	for gap: Variant in luecken:
		var gid := str(gap)
		assert_false(gap_seen.has(gid), "%s: Lücken paarweise verschieden" % sid)
		gap_seen[gid] = true
		assert_eq(
			int(pool_counts.get(gid, 0)), 1, "%s: genau 1 richtige Option für '%s'" % [sid, gid]
		)
	var all_text := "\n".join(PackedStringArray(story.get("saetze_de", [])))
	for i in luecken.size():
		assert_true(all_text.contains("{%d}" % i), "%s: Token {%d} im Text" % [sid, i])


func test_lueckentext_logik_kompatibel() -> void:
	# Jede neue Geschichte spielt sauber durch die bestehende StoryTime-Logik:
	# richtige Wörter einsetzen → komplett, 0 falsche, Platzhalter ersetzt.
	for book: Dictionary in _books():
		for story: Dictionary in StoryBooks.stories_of(book):
			var fills := StoryTime.empty_fills(story)
			assert_eq(fills.size(), 3, str(story.get("id")) + ": 3 Zellen")
			for gap: Variant in story.get("luecken", []):
				assert_true(StoryTime.place_word(fills, str(gap)) >= 0)
			assert_true(StoryTime.is_complete(fills))
			assert_eq(StoryTime.wrong_count(story, fills), 0, str(story.get("id")))
			var rendered := StoryTime.rendered_sentences(story, fills)
			for sentence: Variant in rendered:
				assert_false(str(sentence).contains(StoryTime.GAP_PLACEHOLDER))


func test_abnutzungsformel() -> void:
	# Frisch + Standard-Entertainment (Startbuch: 3) = eine Geschichte (3).
	assert_eq(StoryBooks.needed_words(3, 0), 3, "frisch = 3 Wörter")
	assert_eq(StoryBooks.needed_words(6, 0), 3, "Deckel nach unten bei 3")
	# Monoton steigend in reads (Abnutzung), fallend in entertainment.
	for ent in range(1, 7):
		var prev := 0
		for reads in range(0, 13):
			var needed := StoryBooks.needed_words(ent, reads)
			assert_true(needed >= prev, "monoton in reads (ent=%d, reads=%d)" % [ent, reads])
			assert_true(needed >= StoryBooks.WORDS_MIN and needed <= StoryBooks.WORDS_MAX)
			prev = needed
	for reads in range(0, 13):
		assert_true(
			StoryBooks.needed_words(6, reads) <= StoryBooks.needed_words(2, reads),
			"spannender = weniger Wörter (reads=%d)" % reads
		)
	assert_eq(StoryBooks.needed_words(1, 100), StoryBooks.WORDS_MAX, "Deckel nach oben")
	assert_false(StoryBooks.is_worn(StoryBooks.WORN_AFTER_READS - 1))
	assert_true(StoryBooks.is_worn(StoryBooks.WORN_AFTER_READS))


func test_reads_slice_bump_und_schwelle_steigt() -> void:
	var gs := _fresh_game_state()
	var start := _start_book(_books())
	var book_id := str(start.get("id", ""))
	var ent := int(start.get("entertainment", 1))
	assert_eq(StoryBooks.reads_of(gs.state(), book_id), 0, "frischer Save: 0 reads")
	var frisch := StoryBooks.needed_words(ent, StoryBooks.reads_of(gs.state(), book_id))
	for _i in 5:
		StoryBooks.bump_read(gs, book_id)
	assert_eq(StoryBooks.reads_of(gs.state(), book_id), 5, "5 Runden = 5 reads")
	assert_true(StoryBooks.is_worn(5), "ab 5 Lesungen abgenutzt")
	var abgenutzt := StoryBooks.needed_words(ent, StoryBooks.reads_of(gs.state(), book_id))
	assert_true(abgenutzt > frisch, "Einschlaf-Schwelle steigt (%d → %d)" % [frisch, abgenutzt])
	gs.free()
	# Feindliche Saves: normalize klemmt Negativwerte auf 0.
	var slice := StoryBooks.normalize_slice({"reads": {"x": -3}})
	assert_eq(int(slice["reads"]["x"]), 0, "normalize klemmt reads >= 0")
	assert_eq(StoryBooks.normalize_slice("kaputt"), {"reads": {}}, "Junk → Default")


func test_besitz_startbuch_migration_und_inventar() -> void:
	var books := _books()
	var start_id := str(_start_book(books).get("id", ""))
	# Bestandsspieler: Save OHNE story-Slice und OHNE Inventar-Einträge —
	# das Startbuch gehört ihm trotzdem (Migration braucht keinen Flag).
	var owned := StoryBooks.owned_book_ids(books, {})
	assert_eq(owned, [start_id], "Bestandsspieler kriegt genau Buch 1")
	# Kauf im Inventar → Bibliothek wächst.
	var state := {"inventory": {"items": {"buch_weltraum": 1}}}
	owned = StoryBooks.owned_book_ids(books, state)
	assert_true(owned.has(start_id), "Startbuch bleibt")
	assert_true(owned.has("buch_weltraum"), "gekauftes Buch dazu")
	assert_eq(owned.size(), 2, "sonst nichts")


func test_rehwei_buecher_kategorie_synchron() -> void:
	var books := _books()
	var start_id := str(_start_book(books).get("id", ""))
	var rehwei := _rehwei()
	var buecher: Array = rehwei.get("buecher", [])
	assert_false(buecher.is_empty(), "buecher-Kategorie existiert")
	var im_laden := {}
	for ware: Dictionary in buecher:
		var wid := str(ware.get("id", ""))
		im_laden[wid] = ware
		assert_eq(str(ware.get("inventar", "")), wid, wid + ": inventar = Buch-Id")
		assert_eq(str(ware.get("kategorie", "")), "buch", wid + ": kategorie buch")
		assert_ne(wid, start_id, "Startbuch steht nicht im Laden")
		var im_katalog := StoryBooks.book_by_id(books, wid)
		assert_false(im_katalog.is_empty(), wid + ": existiert im Bücher-Katalog")
		assert_eq(
			int(ware.get("preis", -1)), int(im_katalog.get("preis", -2)), wid + ": Preis synchron"
		)
	for book: Dictionary in books:
		var book_id := str(book.get("id", ""))
		if book_id == start_id:
			continue
		assert_true(im_laden.has(book_id), book_id + ": kaufbar bei REHWEI")
	# Bücher stehen NICHT in waren — die Food-Verträge (test_ef1) bleiben
	# unangetastet.
	for eintrag: Dictionary in rehwei.get("waren", []):
		assert_false(str(eintrag.get("id", "")).begins_with("buch_"), "kein Buch in waren")


## Minimal-Raum für die StoryTime-Session (InteractablesHost-API).
class FakeStoryRoom:
	extends Node3D

	var gs: Object

	func game_state() -> Object:
		return gs


## W13C (Request GOOBYMAN): die gekaufte Schlafmaske wirkt in der ECHTEN
## Vorlese-Session — story_time._on_book_chosen rechnet die benötigten
## Wörter durch GoobymanKatalog.schlafmaske_woerter (Boden WORDS_MIN).
func test_schlafmaske_wirkt_in_der_vorlese_session() -> void:
	var gs := _fresh_game_state()
	var buch := _start_book(_books())
	var buch_id := str(buch.get("id", ""))
	# Buch abnutzen (6 reads → Basis 6), damit der 10-%-Rabatt nicht im
	# WORDS_MIN-Boden verschwindet.
	for _i in 6:
		StoryBooks.bump_read(gs, buch_id)
	var room := FakeStoryRoom.new()
	room.gs = gs
	tree.root.add_child(room)
	var host := InteractablesHost.attach_to(room)
	var story_time := StoryTime.new()
	room.add_child(story_time)
	story_time._host = host
	story_time._on_book_chosen(buch)
	assert_eq(story_time._session_needed, 6, "ohne Maske: abgenutztes Startbuch = 6 Wörter")
	var items: Dictionary = gs.get_value("inventory.items", {})
	items["schlafmaske"] = 1
	gs.set_value("inventory.items", items)
	story_time._on_book_chosen(buch)
	assert_eq(story_time._session_needed, 5, "mit Maske: floor(6 × 0,9) = 5 Wörter")
	room.queue_free()
	await wait_frames(1)
	gs.free()


func test_haendler_kauf_bibliothek_waechst() -> void:
	var gs := _fresh_game_state()
	gs.set_value("economy.coins", 100)
	var buecher: Array = _rehwei().get("buecher", [])
	var ware := CitySortiment.ware(buecher, "buch_weltraum")
	assert_false(ware.is_empty(), "buch_weltraum im REHWEI-Buecherregal")
	var sheet := HaendlerSheet.new()
	sheet.gs = gs
	sheet.waren = buecher
	tree.root.add_child(sheet)
	var gekauft := {"id": ""}
	sheet.gekauft.connect(func(ware_id: String) -> void: gekauft["id"] = ware_id)
	assert_true(sheet.kann_kaufen(ware), "genug Münzen")
	assert_true(sheet.kaufe(ware), "Kauf klappt")
	assert_eq(gekauft["id"], "buch_weltraum", "gekauft-Signal")
	assert_eq(int(gs.get_value("economy.coins", 0)), 100 - int(ware["preis"]), "Münzen abgezogen")
	var items: Dictionary = gs.get_value("inventory.items", {})
	assert_eq(int(items.get("buch_weltraum", 0)), 1, "Buch im Inventar")
	var owned := StoryBooks.owned_book_ids(_books(), gs.state())
	assert_true(owned.has("buch_weltraum"), "Bibliothek gewachsen")
	sheet.queue_free()
	await wait_frames(1)
	gs.free()

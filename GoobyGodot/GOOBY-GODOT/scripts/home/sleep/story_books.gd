class_name StoryBooks
extends RefCounted
## Bücher-Katalog + Entertainment-Abnutzung der Geschichten-Stunde
## (W13B GESCHICHTEN, Doc F §3.2 — löst den M2-Backlog-Marker in
## story_time.gd ein). Bücher kommen als Daten aus dem Pack
## content/books/data/books.json (Domain "books"): je Buch Titel, Preis,
## entertainment-Wert und 2–3 Lückentext-Geschichten im stories.json-Format.
##
## Abnutzung: eigener Save-Slice "story" (W1d-Slice-Registry, der
## `gooby`-Slice ist FROZEN) zählt `reads` pro Buch. Oft gelesene Bücher
## langweilen — Gooby braucht MEHR Wörter/Seiten zum Einschlafen
## (needed_words), ab WORN_AFTER_READS zeigt die UI „…fast auswendig“.
## Neue Bücher kauft man bei REHWEI (buecher-Kategorie in
## rehwei_sortiment.json → inventory.items). Das Startbuch (start=true,
## preis 0) gehört JEDEM Spieler — auch Bestands-Saves ohne Slice
## (Migration braucht dadurch keinen Flag). Zeit/Zufall werden nie hier
## gelesen; alles ist pure und headless testbar.

const SaveSchema := preload("res://scripts/state/save_schema.gd")

const DOMAIN := "books"
const SLICE_ID := "story"
## Eine Geschichte = 3 Lücken; mehr als 3 Seiten braucht keine Nacht.
const WORDS_MIN := 3
const WORDS_MAX := 9
## Alle 2 Lesungen wird EIN Wort mehr nötig (Abnutzung, ganzzahlig).
const READS_PER_EXTRA_WORD := 2
## Ab so vielen Lesungen gilt ein Buch als abgenutzt („schon 5× gelesen…“).
const WORN_AFTER_READS := 5

static var _registered := false


## Idempotent — Muster BadState (home_entry ruft es beim Boot).
static func register_slice() -> void:
	if _registered:
		return
	_registered = true
	SaveSchema.register_slice(SLICE_ID, default_slice, normalize_slice)


static func default_slice() -> Dictionary:
	return {"reads": {}}


static func normalize_slice(raw: Variant) -> Dictionary:
	var slice: Dictionary = raw if raw is Dictionary else default_slice()
	if not (slice.get("reads") is Dictionary):
		slice["reads"] = {}
	var reads: Dictionary = slice["reads"]
	for book_id: Variant in reads.keys():
		reads[book_id] = maxi(0, int(reads[book_id]))
	return slice


## Nur für Tests.
static func reset_for_tests() -> void:
	_registered = false


# ── Katalog ──────────────────────────────────────────────────────────────────


## Bücher aus der ContentRegistry (leer ohne Autoload — Tests parsen die
## JSON direkt bzw. reichen den Katalog als Array herein).
static func books_from_registry() -> Array:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return []
	var registry := (loop as SceneTree).root.get_node_or_null("/root/ContentRegistry")
	if registry == null or not registry.has_method("get_items"):
		return []
	return registry.get_items(DOMAIN)


static func book_by_id(books: Array, book_id: String) -> Dictionary:
	for book: Dictionary in books:
		if str(book.get("id", "")) == book_id:
			return book
	return {}


static func stories_of(book: Dictionary) -> Array:
	var stories: Variant = book.get("geschichten", [])
	return stories if stories is Array else []


# ── Besitz (Startbuch gratis, Rest via REHWEI → inventory.items) ─────────────


## Ids der Bücher, die dem Spieler gehören. Startbücher (start=true oder
## preis 0) gehören IMMER — Bestandsspieler „kriegen“ Buch 1 also ohne
## Migrationsschritt. Gekaufte Bücher liegen als inventory.items[buchId].
static func owned_book_ids(books: Array, state: Dictionary) -> Array:
	var items: Dictionary = {}
	var inventory: Variant = state.get("inventory")
	if inventory is Dictionary and inventory.get("items") is Dictionary:
		items = inventory["items"]
	var owned: Array = []
	for book: Dictionary in books:
		var book_id := str(book.get("id", ""))
		if book_id.is_empty():
			continue
		var gratis := bool(book.get("start", false))
		var is_start := gratis or int(book.get("preis", 0)) <= 0
		if is_start or int(items.get(book_id, 0)) > 0:
			owned.append(book_id)
	return owned


# ── Abnutzungsformel (der eingelöste M2-Marker) ──────────────────────────────


## Benötigte Wörter bis zum Einschlafen = f(entertainment, Abnutzung):
## spannendere Bücher verzeihen mehr Lesungen, abgenutzte brauchen mehr
## Seiten. Monoton steigend in reads, fallend in entertainment.
static func needed_words(entertainment: int, reads: int) -> int:
	var base := 6 - maxi(1, entertainment)
	var wear := maxi(0, reads) / READS_PER_EXTRA_WORD
	return clampi(base + wear, WORDS_MIN, WORDS_MAX)


static func is_worn(reads: int) -> bool:
	return reads >= WORN_AFTER_READS


# ── GameState-Glue ───────────────────────────────────────────────────────────


static func reads_of(state: Dictionary, book_id: String) -> int:
	var slice: Variant = state.get(SLICE_ID)
	if slice is Dictionary and slice.get("reads") is Dictionary:
		return maxi(0, int(slice["reads"].get(book_id, 0)))
	return 0


## Eine Vorlese-Runde nutzt das Buch ab (reads +1).
static func bump_read(gs: Object, book_id: String) -> void:
	if gs == null or book_id.is_empty():
		return
	gs.update(
		func(state: Dictionary) -> void:
			if not (state.get(SLICE_ID) is Dictionary):
				state[SLICE_ID] = default_slice()
			state[SLICE_ID] = normalize_slice(state[SLICE_ID])
			var reads: Dictionary = state[SLICE_ID]["reads"]
			reads[book_id] = int(reads.get(book_id, 0)) + 1
	)
	gs.notify_slice_changed(SLICE_ID)

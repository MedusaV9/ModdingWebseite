extends TestCase
## W3d — Sticker-Katalog: 141 Ids (85 Legacy + 18 W3d + 2 Basis + 36
## BACKLOG-REST), Assets existieren, DE-Texte komplett, Seiten-Katalog
## konsistent — plus die puren StickerCatalog-Helfer und die
## album.*-String-Parität.

const STICKERS_JSON := "res://content/stickers/data/stickers.json"
const PAGES_JSON := "res://content/stickers/data/sticker_pages.json"

const NEW_SETS := {"garten": 6, "stadt": 6, "gvz": 6}
const ALBUM_KEYS := [
	"album.titel",
	"album.zurueck",
	"album.zaehler",
	"album.unbekannt",
	"album.hint_label",
	"album.unlock_toast",
]


func _load_items(path: String) -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(parsed is Dictionary, path + " parst")
	return parsed.get("items", []) if parsed is Dictionary else []


func test_katalog_vollstaendig_und_valide() -> void:
	var items := _load_items(STICKERS_JSON)
	var pages := _load_items(PAGES_JSON)
	assert_eq(items.size(), 141, "105 Bestand + 33 BACKLOG-REST-Sets + 3 Ereignis-Sticker")
	var by_set := {}
	for def: Dictionary in items:
		var set_id := str(def.get("set", ""))
		by_set[set_id] = int(by_set.get(set_id, 0)) + 1
	assert_eq(by_set.get("legacy", 0), 85, "Legacy-Sektion komplett")
	for set_id: String in NEW_SETS:
		assert_eq(by_set.get(set_id, 0), NEW_SETS[set_id], "Set %s: 6 Sticker" % set_id)
	var errors := StickerCatalog.validate(items, pages)
	assert_eq(errors, [], "validate() ohne Befund")


func test_assets_existieren() -> void:
	var items := _load_items(STICKERS_JSON)
	for def: Dictionary in items:
		var image := str(def.get("image", ""))
		assert_true(FileAccess.file_exists(image), "%s: Asset fehlt (%s)" % [def.get("id"), image])


func test_de_texte_komplett() -> void:
	var items := _load_items(STICKERS_JSON)
	for def: Dictionary in items:
		var id := str(def.get("id", ""))
		assert_false(str(def.get("name_de", "")).is_empty(), id + ": name_de")
		assert_false(str(def.get("flavor_de", "")).is_empty(), id + ": flavor_de")
		assert_false(str(def.get("hint_de", "")).is_empty(), id + ": hint_de")
	# Stichprobe Germanisierung (H §3.2-Tabelle + neue Sets).
	assert_eq(StickerCatalog.by_id(items, "firstNom").get("name_de"), "Erster Happs")
	assert_eq(StickerCatalog.by_id(items, "garten_giesser").get("name_de"), "Gießmeister")


func test_seiten_katalog_konsistent() -> void:
	var items := _load_items(STICKERS_JSON)
	var pages := _load_items(PAGES_JSON)
	assert_eq(pages.size(), 23, "18 Bestand + 5 BACKLOG-REST-Seiten")
	var page_ids := {}
	for page: Dictionary in pages:
		var id := str(page.get("id", ""))
		assert_false(page_ids.has(id), id + ": Seiten-Id eindeutig")
		page_ids[id] = 0
		assert_false(str(page.get("title_de", "")).is_empty(), id + ": title_de")
	for set_id in ["garten", "stadt", "gvz"]:
		assert_true(page_ids.has(set_id), "neue Themenseite " + set_id)
	for def: Dictionary in items:
		var page := str(def.get("page", ""))
		assert_true(page_ids.has(page), "%s: Seite '%s' existiert" % [def.get("id"), page])
		page_ids[page] += 1
	for id: String in page_ids:
		assert_true(int(page_ids[id]) > 0, "Seite %s ist nicht leer" % id)


func test_pure_helfer() -> void:
	var items := _load_items(STICKERS_JSON)
	var grouped := StickerCatalog.by_page(items)
	assert_eq((grouped.get("garten", []) as Array).size(), 6, "by_page: Garten-Seite")
	var herz := StickerCatalog.by_id(items, "herzGooby")
	assert_true(bool(herz.get("secret", false)), "herzGooby ist geheim")
	assert_eq(StickerCatalog.regular_count(items), 140, "Geheim-Sticker zählt nicht im n/N")
	assert_eq(StickerCatalog.by_id(items, "gibtEsNicht"), {}, "unbekannte Id → {}")


func test_de_en_paritaet_album_domain() -> void:
	I18nService.reset_cache()
	var de := I18nService.table("de")
	var en := I18nService.table("en")
	for key: String in ALBUM_KEYS:
		assert_true(de.has(key), "DE fehlt Key: %s" % key)
	for key: String in de:
		if key.begins_with("album."):
			assert_true(en.has(key), "EN fehlt Key: %s" % key)
	for key: String in en:
		if key.begins_with("album."):
			assert_true(de.has(key), "DE fehlt Key: %s" % key)

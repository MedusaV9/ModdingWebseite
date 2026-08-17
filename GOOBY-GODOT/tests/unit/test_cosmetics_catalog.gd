extends TestCase
## CONTENT-A — Katalog-Integrität der Garderobe.
##
## Der Katalog ist Daten, keine Logik: er kommt komplett aus der
## ContentRegistry (eingebautes Pack + alles, was der Auto-Updater nachlegt).
## Diese Suite bewacht deshalb zwei Dinge:
##  1. Was ausgeliefert wird, ist heil — jedes Item hat Name/Beschreibung in
##     beiden Sprachen, einen bekannten Builder, einen Preis, eine Rarität.
##     Ein Tippfehler in der JSON darf nicht erst im Screenshot auffallen.
##  2. Der Weg Registry → Katalog stimmt — inklusive Pack-Override, damit ein
##     Update ein Item wirklich ersetzen kann.

const REGISTRY_BASE := "user://contenta_katalog_test"
## Der Auftrag: alle 42 Web-Outfits + Fellfarben plus mindestens 40 neue.
const MINDEST_ITEMS := 82
const MINDEST_JE_KATEGORIE := {"hut": 20, "brille": 12, "hals": 12, "ruecken": 10, "fell": 7}
## Die 42 Outfits aus GOOBY/src/data/outfits.js — Pflicht-Bestand, keiner darf
## beim Umzug ins Godot-Pack verloren gehen (Reihenfolge wie in der Web-Datei).
const WEB_OUTFITS: Array[String] = [
	"partyHat",
	"beanie",
	"cap",
	"topHat",
	"crown",
	"strawHat",
	"chefHat",
	"flowerCrown",
	"wizardHat",
	"sombrero",
	"pirateHat",
	"detectiveHat",
	"beret",
	"vikingHelm",
	"pumpkinHat",
	"spaceHelm",
	"chefToque",
	"roundGlasses",
	"sunglasses",
	"starGlasses",
	"heartGlasses",
	"monocle",
	"aviatorGoggles",
	"readingGlasses",
	"eyepatch",
	"stars3D",
	"scarfRed",
	"bowtie",
	"scarfStriped",
	"bandana",
	"bellCollar",
	"cape",
	"pearlNecklace",
	"flowerLei",
	"medalGold",
	"winterScarf",
	"backpackTiny",
	"balloonRed",
	"propellerPack",
	"turtleShell",
	"fairyWings",
	"surfBoard",
]
## Die 7 Fellfarben aus SKIN_TABLE (GOOBY/src/data/constants.js) — id →
## [Körper, Bauch, Ohr-Innenseite] + Preis. Verbatim übernommen: eine
## umgefärbte Legacy-Fellfarbe wäre für Rückkehrer sofort sichtbar.
const WEB_FELLE := {
	"cream": [["#F6EAD7", "#FFF9EC", "#F6A8B8"], 0],
	"snow": [["#FAFAFA", "#FFFFFF", "#F2B8C6"], 400],
	"caramel": [["#D9A86C", "#F2DDBD", "#E89AAB"], 400],
	"ash": [["#B9B4AE", "#E8E4DE", "#E0A2B4"], 500],
	"rose": [["#F4C6D2", "#FBE8EE", "#E88BA0"], 600],
	"midnight": [["#4C4A63", "#8B89A6", "#C98BA8"], 800],
	"golden": [["#E8C24A", "#F7E6A6", "#F0A8B8"], 1500],
}


func test_katalog_kommt_aus_der_registry() -> void:
	# Kein set_items(), keine Fixture: das hier ist der ausgelieferte Stand.
	CosmeticsCatalog.reset_cache()
	var items := CosmeticsCatalog.all()
	assert_true(
		items.size() >= MINDEST_ITEMS,
		"Katalog hat %d Items, gefordert sind >= %d" % [items.size(), MINDEST_ITEMS]
	)
	var registry_ids: Array = CosmeticsCatalog.raw_items().map(
		func(item: Variant) -> String: return str(item.get("id", ""))
	)
	assert_true(registry_ids.size() >= items.size(), "Katalog erfindet keine Items")
	for id: String in CosmeticsCatalog.ids():
		assert_true(registry_ids.has(id), "%s steht nicht in der Registry" % id)


func test_ausgelieferte_daten_sind_heil() -> void:
	CosmeticsCatalog.reset_cache()
	var fehler := CosmeticsCatalog.validate(CosmeticsCatalog.raw_items())
	assert_eq(fehler, [], "validate() auf dem ausgelieferten Pack")


func test_jede_kategorie_ist_gefuellt() -> void:
	CosmeticsCatalog.reset_cache()
	for kategorie: String in CosmeticsCatalog.KATEGORIEN:
		var anzahl := CosmeticsCatalog.by_kategorie(kategorie).size()
		var minimum: int = MINDEST_JE_KATEGORIE[kategorie]
		assert_true(
			anzahl >= minimum, "%s: %d Items, gefordert >= %d" % [kategorie, anzahl, minimum]
		)


func test_web_bestand_ist_vollstaendig() -> void:
	CosmeticsCatalog.reset_cache()
	assert_eq(WEB_OUTFITS.size(), 42, "die Vorlage hat 42 Outfits")
	for id: String in WEB_OUTFITS:
		assert_true(CosmeticsCatalog.has(id), "Web-Outfit '%s' fehlt im Godot-Katalog" % id)
	for id: String in WEB_FELLE:
		var def := CosmeticsCatalog.by_id(id)
		if def.is_empty():
			fail_test("Web-Fell '%s' fehlt im Godot-Katalog" % id)
			continue
		assert_eq(str(def["kategorie"]), "fell", "%s ist eine Fellfarbe" % id)
		assert_eq(def["farben"], WEB_FELLE[id][0], "%s: Farben weichen von SKIN_TABLE ab" % id)
		assert_eq(int(def["preis"]), int(WEB_FELLE[id][1]), "%s: Preis weicht ab" % id)


func test_neue_items_sind_wirklich_neu() -> void:
	# Auftrag: die 42 Web-Outfits + 7 Fellfarben PLUS mindestens 40 eigene.
	CosmeticsCatalog.reset_cache()
	var bestand: Array[String] = WEB_OUTFITS.duplicate()
	bestand.append_array(WEB_FELLE.keys())
	var neue := CosmeticsCatalog.ids().filter(
		func(id: Variant) -> bool: return not bestand.has(str(id))
	)
	assert_true(neue.size() >= 40, "nur %d neue Items (gefordert: >= 40)" % neue.size())


func test_jedes_item_hat_einen_echten_builder() -> void:
	CosmeticsCatalog.reset_cache()
	# Ohne diesen Wächter enden Tippfehler in `build` als graue Platzhalter-
	# würfel auf Goobys Kopf, und zwar erst im fertigen Build.
	assert_eq(CosmeticBuilders.unbekannte_builds(), [], "Items mit unbekannter Builder-Id")
	for def: Dictionary in CosmeticsCatalog.all():
		if def["kategorie"] == CosmeticsCatalog.FELL:
			# Fell ist Farbe, kein Mesh — hier zählen die drei Palettenfarben.
			assert_eq(def["farben"].size(), 3, "%s: Fell braucht 3 Farben" % def["id"])


func test_slots_und_preise_sind_konsistent() -> void:
	CosmeticsCatalog.reset_cache()
	for def: Dictionary in CosmeticsCatalog.all():
		var kategorie: String = def["kategorie"]
		var slot := CosmeticsCatalog.slot_of(def["id"])
		if kategorie == CosmeticsCatalog.FELL:
			assert_eq(slot, "", "%s: Fell hat keinen Outfit-Slot" % def["id"])
		else:
			assert_eq(
				slot,
				CosmeticsCatalog.SLOT_BY_KATEGORIE[kategorie],
				"%s: Slot passt nicht zur Kategorie" % def["id"]
			)
		if def["standard"]:
			assert_eq(def["preis"], 0, "%s: Standard-Item muss gratis sein" % def["id"])
		assert_true(def["min_level"] >= 1, "%s: min_level < 1" % def["id"])


func test_es_gibt_genau_ein_standard_fell() -> void:
	CosmeticsCatalog.reset_cache()
	var standards := CosmeticsCatalog.standard_ids(CosmeticsCatalog.FELL)
	assert_eq(standards.size(), 1, "genau ein Gratis-Fell (sonst ist der Fallback mehrdeutig)")
	assert_eq(str(standards[0]), CosmeticsState.STANDARD_FELL, "Standard-Fell heißt wie im State")


func test_de_en_paritaet_der_items() -> void:
	CosmeticsCatalog.reset_cache()
	for def: Dictionary in CosmeticsCatalog.all():
		for feld: String in ["name_de", "name_en", "desc_de", "desc_en"]:
			assert_false(str(def[feld]).strip_edges().is_empty(), "%s: %s leer" % [def["id"], feld])
		# Ein durchgereichtes DE-Wort als EN-Name ist erlaubt (Eigennamen wie
		# "Sombrero"), eine durchgereichte BESCHREIBUNG wäre aber schlicht
		# vergessene Übersetzung.
		assert_ne(
			str(def["desc_en"]), str(def["desc_de"]), "%s: desc_en ist unübersetzt" % def["id"]
		)


func test_de_en_paritaet_der_oberflaeche() -> void:
	I18nService.reset_cache()
	var de := I18nService.table("de")
	var en := I18nService.table("en")
	var fehlend: Array[String] = []
	for key: String in de:
		if key.begins_with("wardrobe.") and not en.has(key):
			fehlend.append(key)
	assert_eq(fehlend, [] as Array[String], "wardrobe.*-Keys ohne EN-Übersetzung")
	var extra: Array[String] = []
	for key: String in en:
		if key.begins_with("wardrobe.") and not de.has(key):
			extra.append(key)
	assert_eq(extra, [] as Array[String], "wardrobe.*-Keys ohne DE-Original")
	assert_true(de.keys().filter(_ist_wardrobe).size() >= 10, "wardrobe-Domain ist gefüllt")


func test_lokalisierte_namen_folgen_der_locale() -> void:
	var vorher := I18nService.get_locale()
	(
		CosmeticsCatalog
		. set_items(
			[
				{
					"id": "probe",
					"kategorie": "hut",
					"name_de": "Deutscher Hut",
					"name_en": "English Hat",
					"desc_de": "Deutsch",
					"desc_en": "English",
				}
			]
		)
	)
	var def := CosmeticsCatalog.by_id("probe")
	I18nService.set_locale("de")
	assert_eq(CosmeticsCatalog.name_of(def), "Deutscher Hut", "DE-Name")
	assert_eq(CosmeticsCatalog.desc_of(def), "Deutsch", "DE-Beschreibung")
	I18nService.set_locale("en")
	assert_eq(CosmeticsCatalog.name_of(def), "English Hat", "EN-Name")
	assert_eq(CosmeticsCatalog.desc_of(def), "English", "EN-Beschreibung")
	I18nService.set_locale(vorher)
	CosmeticsCatalog.reset_cache()


func test_pack_merge_override_schlaegt_bis_in_den_katalog_durch() -> void:
	# Der Kern des Auto-Update-Versprechens: ein Pack mit höherer Priorität
	# ersetzt ein Item per Id, und der Katalog zeigt sofort die neue Fassung.
	var registry := _registry_mit_zwei_packs()
	CosmeticsCatalog.set_items(registry.get_cosmetics())
	assert_eq(CosmeticsCatalog.ids(), ["hut_alt", "hut_neu"], "Merge-Reihenfolge bleibt erhalten")
	var ersetzt := CosmeticsCatalog.by_id("hut_alt")
	assert_eq(str(ersetzt["name_de"]), "Hut aus dem Update", "höheres Pack gewinnt")
	assert_eq(int(ersetzt["preis"]), 250, "auch Zahlen kommen aus dem Update")
	assert_eq(CosmeticsCatalog.kategorie_of("hut_neu"), "hut", "neues Item ist dazugekommen")
	CosmeticsCatalog.reset_cache()
	registry.free()
	_wipe(REGISTRY_BASE)


func test_kaputte_pack_eintraege_killen_die_garderobe_nicht() -> void:
	(
		CosmeticsCatalog
		. set_items(
			[
				{"id": "gut", "kategorie": "hut", "name_de": "Gut"},
				{"kategorie": "hut", "name_de": "Ohne Id"},
				{"id": "ohne_kategorie", "name_de": "Nix"},
				{"id": "gut", "kategorie": "hut", "name_de": "Doppelt"},
				"kein Objekt",
				{"id": "alias", "type": "glasses", "name": "Legacy", "price": 40},
			]
		)
	)
	assert_eq(CosmeticsCatalog.ids(), ["gut", "alias"], "nur brauchbare Einträge überleben")
	assert_eq(str(CosmeticsCatalog.by_id("gut")["name_de"]), "Gut", "erster Treffer gewinnt")
	var alias := CosmeticsCatalog.by_id("alias")
	assert_eq(str(alias["kategorie"]), "brille", "englische Kategorie wird übersetzt")
	assert_eq(int(alias["preis"]), 40, "'price' wird als 'preis' gelesen")
	assert_eq(str(alias["name_en"]), "Legacy", "'name' füllt beide Sprachen")
	CosmeticsCatalog.reset_cache()


func test_validate_nennt_die_fehler_beim_namen() -> void:
	var fehler := (
		CosmeticsCatalog
		. validate(
			[
				{"id": "", "kategorie": "hut"},
				{"id": "x", "kategorie": "hosentraeger"},
				{"id": "y", "kategorie": "hut", "rarity": "mega", "preis": -1},
				{"id": "z", "kategorie": "fell", "farben": ["#fff"]},
			]
		)
	)
	assert_true(_enthaelt(fehler, "ohne id"), "leere Id gemeldet")
	assert_true(_enthaelt(fehler, "unbekannte Kategorie"), "Fantasie-Kategorie gemeldet")
	assert_true(_enthaelt(fehler, "y: unbekannte rarity"), "Fantasie-Rarität gemeldet")
	assert_true(_enthaelt(fehler, "y: preis"), "negativer Preis gemeldet")
	assert_true(_enthaelt(fehler, "y: build fehlt"), "fehlender Builder gemeldet")
	assert_true(_enthaelt(fehler, "z: Fell braucht 3 Farben"), "unvollständiges Fell gemeldet")


func _ist_wardrobe(key: String) -> bool:
	return key.begins_with("wardrobe.")


func _enthaelt(fehler: Array, teil: String) -> bool:
	for text: Variant in fehler:
		if str(text).contains(teil):
			return true
	return false


## Zwei Packs, beta (Priorität 400) überschreibt ein Item von alpha (100).
func _registry_mit_zwei_packs() -> ContentRegistryService:
	_wipe(REGISTRY_BASE)
	var root := REGISTRY_BASE + "/content"
	_write_json(
		root + "/alpha/pack.json",
		{"id": "alpha", "version": "1.0.0", "priority": 100, "domains": ["cosmetics"]}
	)
	_write_json(
		root + "/alpha/data/cosmetics.json",
		{
			"schema": 1,
			"items":
			[{"id": "hut_alt", "kategorie": "hut", "name_de": "Hut von gestern", "preis": 100}],
		}
	)
	_write_json(
		root + "/beta/pack.json",
		{"id": "beta", "version": "1.1.0", "priority": 400, "domains": ["cosmetics"]}
	)
	_write_json(
		root + "/beta/data/cosmetics.json",
		{
			"schema": 1,
			"items":
			[
				{
					"id": "hut_alt",
					"kategorie": "hut",
					"name_de": "Hut aus dem Update",
					"preis": 250
				},
				{"id": "hut_neu", "kategorie": "hut", "name_de": "Ganz neuer Hut", "preis": 300},
			],
		}
	)
	DirAccess.make_dir_recursive_absolute(REGISTRY_BASE + "/packs")
	var registry := ContentRegistryService.new()
	registry.auto_reload = false
	registry.content_root = root
	registry.packs_dir = REGISTRY_BASE + "/packs"
	registry.reload()
	return registry


func _write_json(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


func _wipe(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var child := path + "/" + entry
		if dir.current_is_dir():
			_wipe(child)
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

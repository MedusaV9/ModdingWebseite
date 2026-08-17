extends TestCase
## CONTENT-A — Besitz-, Anlege- und Kauflogik der Garderobe.
##
## Alles hier läuft auf einem injizierten Mini-Katalog statt auf den 92
## ausgelieferten Items: die Regeln sollen sich nicht ändern, nur weil jemand
## einen Hut nachlegt. Der echte Katalog wird in test_cosmetics_catalog.gd
## geprüft.
##
## Kernversprechen, die diese Suite festnagelt:
##  - ein Item pro Slot, das alte fliegt ohne Nachfrage raus;
##  - Fell ist nie leer und NUR im Shop zu haben (User-Regel);
##  - unbekannte/nicht besessene Ids ändern gar nichts, statt zu crashen —
##    ein deinstalliertes Pack darf keinen Save zerlegen.

const Economy := preload("res://scripts/logic/economy.gd")
const GameStateScript := preload("res://scripts/state/game_state.gd")

const KATALOG: Array = [
	{
		"id": "hut_gratis",
		"kategorie": "hut",
		"name_de": "Gratishut",
		"desc_de": "Kostet nix.",
		"build": "kegel",
		"standard": true,
	},
	{"id": "hut_teuer", "kategorie": "hut", "name_de": "Teuer", "preis": 500, "build": "zylinder"},
	{"id": "hut_billig", "kategorie": "hut", "name_de": "Billig", "preis": 50, "build": "kappe"},
	{
		"id": "hut_spaet",
		"kategorie": "hut",
		"name_de": "Spät",
		"preis": 10,
		"min_level": 7,
		"build": "krone",
	},
	{
		"id": "brille_a",
		"kategorie": "brille",
		"name_de": "Brille A",
		"preis": 20,
		"build": "brille"
	},
	{"id": "hals_a", "kategorie": "hals", "name_de": "Hals A", "preis": 20, "build": "schal"},
	{
		"id": "ruecken_a",
		"kategorie": "ruecken",
		"name_de": "Rücken A",
		"preis": 20,
		"build": "rucksack",
	},
	{
		"id": "cream",
		"kategorie": "fell",
		"name_de": "Creme",
		"farben": ["#a", "#b", "#c"],
		"build": "fell",
		"standard": true,
	},
	{
		"id": "fell_pink",
		"kategorie": "fell",
		"name_de": "Pink",
		"preis": 120,
		"farben": ["#a", "#b", "#c"],
		"build": "fell",
	},
]


func before_each() -> void:
	CosmeticsCatalog.set_items(KATALOG)


func test_default_slice_ist_spielbar() -> void:
	before_each()
	var slice := CosmeticsState.default_slice()
	assert_eq(CosmeticsState.slots_filled(slice), 0, "frisch startet man nackt")
	assert_eq(CosmeticsState.equipped(slice, "fell"), "cream", "Fell ist von Anfang an gesetzt")
	assert_true(CosmeticsState.is_owned(slice, "hut_gratis"), "Standard-Items gehören einem sofort")
	assert_false(CosmeticsState.is_owned(slice, "hut_teuer"), "gekaufte Items eben nicht")
	CosmeticsCatalog.reset_cache()


func test_normalize_repariert_kaputte_saves() -> void:
	before_each()
	var slice := CosmeticsState.normalize({"outfits": "kaputt", "fur": 42})
	assert_eq(slice["outfits"]["owned"], [], "Besitzliste wiederhergestellt")
	assert_eq(slice["outfits"]["equipped"]["hat"], null, "alle vier Slots existieren")
	assert_eq(slice["outfits"]["equipped"]["back"], null, "alle vier Slots existieren")
	assert_eq(str(slice["fur"]["equipped"]), "cream", "Fell darf nie leer sein")
	assert_true(slice["fur"]["owned"].has("cream"), "Standard-Fell gehört immer dazu")
	CosmeticsCatalog.reset_cache()


func test_ein_item_pro_slot_verdraengt_das_alte() -> void:
	before_each()
	var slice := CosmeticsState.default_slice()
	CosmeticsState.grant(slice, "hut_teuer")
	CosmeticsState.grant(slice, "hut_billig")
	CosmeticsState.equip(slice, "hut_teuer")
	assert_eq(CosmeticsState.equipped(slice, "hut"), "hut_teuer", "erster Hut sitzt")
	var zweiter := CosmeticsState.equip(slice, "hut_billig")
	assert_true(zweiter["ok"], "zweiter Hut geht durch")
	assert_eq(str(zweiter["vorher"]), "hut_teuer", "der alte Hut wird als verdrängt gemeldet")
	assert_eq(CosmeticsState.equipped(slice, "hut"), "hut_billig", "nur EIN Hut auf dem Kopf")
	assert_true(CosmeticsState.is_owned(slice, "hut_teuer"), "verdrängt heißt nicht enteignet")
	CosmeticsCatalog.reset_cache()


func test_slots_stoeren_einander_nicht() -> void:
	before_each()
	var slice := CosmeticsState.default_slice()
	for id: String in ["hut_billig", "brille_a", "hals_a", "ruecken_a"]:
		CosmeticsState.grant(slice, id)
		CosmeticsState.equip(slice, id)
	assert_eq(CosmeticsState.slots_filled(slice), 4, "volles Outfit")
	var karte := CosmeticsState.equipped_map(slice)
	assert_eq(str(karte["hut"]), "hut_billig", "Hut-Slot")
	assert_eq(str(karte["brille"]), "brille_a", "Brillen-Slot")
	assert_eq(str(karte["hals"]), "hals_a", "Hals-Slot")
	assert_eq(str(karte["ruecken"]), "ruecken_a", "Rücken-Slot")
	assert_eq(str(karte["fell"]), "cream", "Fell wandert mit in die Attach-Karte")
	CosmeticsState.unequip(slice, "brille")
	assert_eq(CosmeticsState.equipped(slice, "brille"), "", "abgelegt")
	assert_eq(CosmeticsState.slots_filled(slice), 3, "nur der eine Slot ist leer")
	assert_eq(CosmeticsState.equipped(slice, "hut"), "hut_billig", "Nachbar-Slot unberührt")
	CosmeticsCatalog.reset_cache()


func test_toggle_ist_der_tap_in_der_garderobe() -> void:
	before_each()
	var slice := CosmeticsState.default_slice()
	CosmeticsState.grant(slice, "brille_a")
	CosmeticsState.toggle(slice, "brille_a")
	assert_eq(CosmeticsState.equipped(slice, "brille"), "brille_a", "erster Tap legt an")
	CosmeticsState.toggle(slice, "brille_a")
	assert_eq(CosmeticsState.equipped(slice, "brille"), "", "zweiter Tap legt ab")
	CosmeticsCatalog.reset_cache()


func test_fell_ist_nie_leer() -> void:
	before_each()
	var slice := CosmeticsState.default_slice()
	CosmeticsState.grant(slice, "fell_pink", "shop")
	CosmeticsState.equip(slice, "fell_pink")
	assert_eq(CosmeticsState.equipped(slice, "fell"), "fell_pink", "Fell gewechselt")
	assert_eq(CosmeticsState.slots_filled(slice), 0, "Fell belegt keinen Outfit-Slot")
	var ab := CosmeticsState.unequip(slice, "fell")
	assert_true(ab["ok"], "Fell ablegen ist erlaubt")
	assert_eq(CosmeticsState.equipped(slice, "fell"), "cream", "…fällt aber aufs Standard-Fell")
	assert_false(CosmeticsState.unequip(slice, "fell")["ok"], "nochmal ablegen ändert nichts")
	CosmeticsCatalog.reset_cache()


func test_fell_gibt_es_nur_im_shop() -> void:
	before_each()
	var slice := CosmeticsState.default_slice()
	var belohnung := CosmeticsState.grant(slice, "fell_pink", "quest")
	assert_false(belohnung["ok"], "Fell als Questlohn ist verboten (User-Regel)")
	assert_eq(str(belohnung["grund"]), "nur_im_shop", "und sagt auch warum")
	assert_false(CosmeticsState.is_owned(slice, "fell_pink"), "nichts im Besitz gelandet")
	assert_true(CosmeticsState.grant(slice, "hut_teuer", "quest")["ok"], "Hüte dürfen Beute sein")
	assert_true(CosmeticsState.grant(slice, "fell_pink", "shop")["ok"], "über den Shop geht es")
	CosmeticsCatalog.reset_cache()


func test_kauf_bucht_muenzen_und_besitz_gemeinsam() -> void:
	before_each()
	var slice := CosmeticsState.default_slice()
	var econ := Economy.default_slice()
	econ["coins"] = 200
	var kauf := CosmeticsState.buy(slice, econ, "hut_billig")
	assert_true(kauf["gekauft"], "Kauf geht durch")
	assert_eq(int(econ["coins"]), 150, "50 Münzen weg")
	assert_true(CosmeticsState.is_owned(slice, "hut_billig"), "Hut im Besitz")
	assert_eq(int(econ["coinsSpent"]), 50, "Ausgabe verbucht")
	CosmeticsCatalog.reset_cache()


func test_kauf_scheitert_sauber() -> void:
	before_each()
	var slice := CosmeticsState.default_slice()
	var econ := Economy.default_slice()
	econ["coins"] = 100
	var zu_teuer := CosmeticsState.buy(slice, econ, "hut_teuer")
	assert_false(zu_teuer["gekauft"], "500 Münzen hat niemand")
	assert_eq(str(zu_teuer["grund"]), "zu_teuer", "Grund benannt")
	assert_eq(int(econ["coins"]), 100, "keine Münzen angefasst")
	assert_false(CosmeticsState.is_owned(slice, "hut_teuer"), "kein Besitz auf Pump")

	var zu_frueh := CosmeticsState.buy(slice, econ, "hut_spaet", 3)
	assert_false(zu_frueh["gekauft"], "Level 3 reicht für ein Level-7-Item nicht")
	assert_eq(str(zu_frueh["grund"]), "level_zu_niedrig", "Grund benannt")
	assert_eq(int(econ["coins"]), 100, "auch hier bleibt das Geld liegen")
	assert_true(CosmeticsState.buy(slice, econ, "hut_spaet", 7)["gekauft"], "mit Level 7 klappt es")

	var nochmal := CosmeticsState.buy(slice, econ, "hut_spaet", 7)
	assert_false(nochmal["gekauft"], "zweimal kaufen geht nicht")
	assert_eq(str(nochmal["grund"]), "schon_besessen", "Grund benannt")

	var geschenkt := CosmeticsState.can_buy(slice, econ, "hut_gratis")
	assert_false(geschenkt["ok"], "Standard-Items sind schon da")
	assert_eq(str(geschenkt["grund"]), "schon_besessen", "Grund benannt")
	CosmeticsCatalog.reset_cache()


func test_unbekannte_ids_werden_weich_ignoriert() -> void:
	before_each()
	var slice := CosmeticsState.default_slice()
	CosmeticsState.grant(slice, "hut_billig")
	CosmeticsState.equip(slice, "hut_billig")
	var vorher := slice.duplicate(true)

	for id: String in ["gibt_es_nicht", "", "hut_billig/../hack"]:
		assert_false(CosmeticsState.equip(slice, id)["ok"], "'%s' lässt sich nicht anlegen" % id)
		assert_false(CosmeticsState.grant(slice, id)["ok"], "'%s' landet nicht im Besitz" % id)
		assert_false(CosmeticsState.is_owned(slice, id), "'%s' gehört niemandem" % id)
	assert_false(CosmeticsState.equip(slice, "hut_teuer")["ok"], "nicht besessen = nicht anlegbar")
	assert_eq(
		str(CosmeticsState.equip(slice, "hut_teuer")["grund"]), "nicht_besessen", "Grund benannt"
	)
	assert_false(CosmeticsState.unequip(slice, "hosentraeger")["ok"], "Fantasie-Kategorie")
	assert_eq(slice, vorher, "der Slice ist durch all das kein Stück anders geworden")
	CosmeticsCatalog.reset_cache()


func test_prune_raeumt_nach_einem_pack_verlust_auf() -> void:
	before_each()
	var slice := CosmeticsState.default_slice()
	CosmeticsState.grant(slice, "hut_billig")
	CosmeticsState.grant(slice, "brille_a")
	CosmeticsState.grant(slice, "fell_pink", "shop")
	CosmeticsState.equip(slice, "hut_billig")
	CosmeticsState.equip(slice, "brille_a")
	CosmeticsState.equip(slice, "fell_pink")

	# Das Pack mit Brille und Fell verschwindet (deinstalliert / Update weg).
	(
		CosmeticsCatalog
		. set_items(
			[
				KATALOG[2],
				{
					"id": "cream",
					"kategorie": "fell",
					"name_de": "Creme",
					"farben": ["#a", "#b", "#c"],
					"standard": true,
				},
			]
		)
	)
	var geraeumt := CosmeticsState.prune_equipped(slice)
	assert_true(geraeumt.has("brille"), "verwaiste Brille abgelegt")
	assert_true(geraeumt.has("fell"), "verwaistes Fell zurückgesetzt")
	assert_eq(CosmeticsState.equipped(slice, "hut"), "hut_billig", "der Hut bleibt")
	assert_eq(CosmeticsState.equipped(slice, "fell"), "cream", "Fell fällt auf den Standard")
	assert_true(
		slice["outfits"]["owned"].has("brille_a"),
		"der Besitz bleibt stehen — kommt das Pack zurück, ist die Brille wieder da"
	)
	assert_eq(CosmeticsState.prune_equipped(slice), [], "zweiter Durchlauf findet nichts mehr")
	CosmeticsCatalog.reset_cache()


func test_owned_filtert_nach_kategorie() -> void:
	before_each()
	var slice := CosmeticsState.default_slice()
	CosmeticsState.grant(slice, "hut_billig")
	CosmeticsState.grant(slice, "brille_a")
	CosmeticsState.grant(slice, "fell_pink", "shop")
	assert_eq(CosmeticsState.owned(slice, "hut"), ["hut_billig"], "nur Hüte")
	assert_eq(CosmeticsState.owned(slice, "fell"), ["cream", "fell_pink"], "Fell inkl. Standard")
	assert_eq(CosmeticsState.owned(slice).size(), 4, "alles zusammen")
	CosmeticsCatalog.reset_cache()


func test_apply_to_state_schreibt_in_den_echten_store() -> void:
	before_each()
	var dir := "user://contenta_state_test/%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var state: Node = GameStateScript.new()
	state.initialize(dir + "/save_v5.json")
	var ergebnis: Variant = CosmeticsState.apply_to_state(
		state,
		func(cosmetics: Dictionary, econ: Dictionary) -> Dictionary:
			econ["coins"] = 999
			CosmeticsState.grant(cosmetics, "hut_billig")
			return CosmeticsState.equip(cosmetics, "hut_billig")
	)
	assert_true(bool((ergebnis as Dictionary)["ok"]), "Mutator-Ergebnis kommt zurück")
	var gespeichert: Dictionary = state.get_value("cosmetics", {})
	assert_eq(
		CosmeticsState.equipped(gespeichert, "hut"), "hut_billig", "der Hut steht im GameState"
	)
	assert_eq(int(state.get_value("economy.coins", 0)), 999, "Economy mitgeschrieben")
	state.free()
	CosmeticsCatalog.reset_cache()

extends TestCase
## W13B/INTEGRATE — Regressionstests für die abgearbeiteten Wellen-Requests
## (W13-requests.md). Kern: der REISEPASS-Bugreport „Lambda-Capture schluckt
## das Economy.spend-Ergebnis“ — GDScript-4-Lambdas capturen lokale
## WERT-Typen per KOPIE, das Muster `var bezahlt := false` + Zuweisung im
## gs.update-Lambda brach deshalb IMMER ab (Geld abgebucht, Leistung nie
## geliefert). Fix in allen gemeldeten Dateien: Dictionary-Capture
## (`{"ok": false}`, Referenz geteilt — Vorbild reise_app.gd, c567a04f).

## Alle Kauf-Pfade aus dem REISEPASS-Report: hier darf das kaputte
## Wert-Capture-Muster NIE wieder auftauchen (Quelltext-Tripwire unten).
const KAUF_DATEIEN: Array[String] = [
	"res://scripts/city/travel/reise_app.gd",
	"res://scripts/city/travel/gooberando.gd",
	"res://scripts/city/phone/fahrdienst_app.gd",
	"res://scripts/city/ui/baumarkt_sheet.gd",
	"res://scripts/city/ui/pow_sheet.gd",
	"res://scripts/city/ui/autohaus_sheet.gd",
]

const NOW := 1_784_980_800_000


class FakeGameState:
	extends RefCounted
	var state: Dictionary = {
		"city": {"taxi": TaxiLogic.default_slice(), "fahrdienst": ""},
		"economy": {"coins": 300},
		"gooby": {"stats": {"energy": 80.0}},
		"inventory": {"items": {}, "food": {}},
	}

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = state
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func set_value(path: String, wert: Variant) -> void:
		var teile := path.split(".")
		var node: Dictionary = state
		for i in teile.size() - 1:
			if not (node.get(teile[i]) is Dictionary):
				node[teile[i]] = {}
			node = node[teile[i]]
		node[teile[teile.size() - 1]] = wert

	func update(mutator: Callable) -> void:
		mutator.call(state)

	func notify_slice_changed(_slice_id: String) -> void:
		pass


## ---------------------------------------------- Lambda-Capture (REISEPASS)


## Repräsentativer Verhaltens-Test: VOR dem Fix blieb das Taxi nach
## _on_rufen für immer idle, obwohl die Münzen abgebucht waren.
func test_fahrdienst_rufen_bucht_geld_und_speichert_slice() -> void:
	var gs := FakeGameState.new()
	var app := FahrdienstApp.new()
	app.gs = gs
	app.dienst = Fahrdienst.TAXI
	app.now_ms_override = NOW
	app.stunde_override = 12.0
	tree.root.add_child(app)
	await wait_frames(1)
	app._on_rufen()
	var preis := Fahrdienst.kosten_zur_stunde(Fahrdienst.TAXI, 12.0)
	assert_eq(int(gs.get_value("economy.coins", 0)), 300 - preis, "Münzen abgebucht")
	var slice: Dictionary = gs.get_value("city.taxi", {})
	assert_eq(str(slice.get("state", "")), TaxiLogic.STATE_GERUFEN, "Taxi ist GERUFEN")
	assert_eq(str(gs.get_value("city.fahrdienst", "")), Fahrdienst.TAXI, "Dienst gemerkt")
	assert_eq(int(gs.get_value(Fahrdienst.PREIS_KEY, 0)), preis, "bezahlter Preis gemerkt")
	tree.root.remove_child(app)
	app.free()


## Zweiter Verhaltens-Test (Sheet-Familie): VOR dem Fix wurde das Material
## zwar gutgeschrieben (Lambda-KOPIE), aber `gekauft` feuerte nie und die
## Liste blieb stehen.
func test_baumarkt_kauf_feuert_signal_und_bucht_material() -> void:
	var gs := FakeGameState.new()
	var eintrag: Dictionary = BaumarktKatalog.materialien()[0]
	var sheet := BaumarktSheet.new()
	sheet.gs = gs
	var gekauft: Array[String] = []
	sheet.gekauft.connect(func(ware_id: String) -> void: gekauft.append(ware_id))
	sheet._kaufe(eintrag)
	var key := str(eintrag.get("inventar", eintrag.get("id", "")))
	var menge := maxi(1, int(eintrag.get("menge", 1)))
	assert_eq(
		int(gs.get_value("economy.coins", 0)),
		300 - int(eintrag.get("preis", 0)),
		"Münzen abgebucht"
	)
	assert_eq(int(gs.get_value("inventory.items.%s" % key, 0)), menge, "Material gutgeschrieben")
	assert_eq(gekauft, [str(eintrag.get("id", ""))] as Array[String], "gekauft-Signal feuert")
	sheet.free()


## ---------------------------------------------- REHWEI-Bücher (GESCHICHTEN)


## GESCHICHTEN-Request: der REHWEI-Laden rendert die buecher-Kategorie —
## Kauf bucht Münzen ab und legt die Buch-Id in inventory.items, danach
## steht das Buch ausgegraut „im Regal“ (kein Doppelkauf).
func test_rehwei_laden_rendert_buecher_und_kauf_landet_im_regal() -> void:
	var gs := FakeGameState.new()
	var sheet := HaendlerSheet.new()
	sheet.gs = gs
	sheet.waren = CitySortiment.laden(CitySortiment.REHWEI_PFAD)
	sheet.buecher = CitySortiment.buecher(CitySortiment.REHWEI_PFAD)
	assert_eq(sheet.buecher.size(), 5, "5 kaufbare Bücher im Sortiment")
	tree.root.add_child(sheet)
	await wait_frames(1)
	assert_true(sheet.find_child("BuecherTitel", true, false) != null, "Bücher-Überschrift")
	var buch: Dictionary = sheet.buecher[0]
	var buch_id := str(buch.get("id", ""))
	var zeile: Control = sheet.find_child("Buch_%s" % buch_id, true, false)
	assert_true(zeile != null, "Buch-Zeile gerendert")
	assert_true(sheet.kaufe_buch(buch), "Kauf klappt mit vollen Taschen")
	assert_eq(
		int(gs.get_value("inventory.items.%s" % buch_id, 0)), 1, "Buch liegt in inventory.items"
	)
	assert_eq(
		int(gs.get_value("economy.coins", 0)), 300 - int(buch.get("preis", 0)), "Münzen abgebucht"
	)
	assert_false(sheet.kaufe_buch(buch), "Doppelkauf prallt ab (schon im Regal)")
	assert_eq(int(gs.get_value("inventory.items.%s" % buch_id, 0)), 1, "weiterhin genau 1x")
	await wait_frames(1)
	zeile = sheet.find_child("Buch_%s" % buch_id, true, false)
	var knopf: Button = zeile.find_child("BuchKnopf", true, false)
	assert_true(knopf != null and knopf.disabled, "Regal-Knopf ist ausgegraut")
	assert_eq(knopf.text, I18nService.t("city.laden.im_regal"), "„Im Regal“-Text")
	tree.root.remove_child(sheet)
	sheet.free()


## Der REHWEI-Ort reicht die Bücher wirklich in sein Laden-Sheet durch.
func test_rehwei_ort_befuellt_laden_mit_buechern() -> void:
	assert_false(
		CitySortiment.buecher(CitySortiment.REHWEI_PFAD).is_empty(),
		"REHWEI-Sortiment hat die buecher-Kategorie"
	)
	var quelle := FileAccess.get_file_as_string("res://scripts/city/orte/rehwei.gd")
	assert_true(
		quelle.contains("inhalt.buecher = CitySortiment.buecher"),
		"OrtRehwei.oeffne_laden befüllt HaendlerSheet.buecher"
	)


## ---------------------------------------------- Erholungs-Sonne (RAUMSTATION)


## HUD-Wunsch (Doc E §3.3): der Energie-Buff-Chip trägt ein ☀-Prefix,
## solange der „erholt“-Urlaubs-Buff läuft (erholt_aktiv liest den
## GoobyBuffs-Slice; abgelaufene Buffs zählen nicht).
func test_energie_buff_chip_traegt_sonne_bei_erholt() -> void:
	var gs := FakeGameState.new()
	gs.state["buffs"] = {
		"aktiv": [{"id": "erholt", "stat": "energy", "wert": 5.0, "until_ms": NOW + 1000}]
	}
	assert_true(HudStatusSheet.erholt_aktiv(gs, NOW), "erholt-Buff wird erkannt")
	assert_false(HudStatusSheet.erholt_aktiv(gs, NOW + 2000), "abgelaufen = keine Sonne")
	var stats := {"hunger": 80.0, "energie": 90.0, "hygiene": 85.0, "spass": 70.0}
	var content := HudStatusSheet.build_content(stats, {"energie": 5.0}, 1.0, 0.0, true)
	var chip: Control = content.find_child("BuffEnergie", true, false)
	assert_true(chip != null, "Energie-Buff-Chip gebaut")
	var label: Label = chip.find_child("BuffValue", true, false)
	assert_true(label.text.begins_with("☀ "), "☀-Prefix am Chip (got %s)" % label.text)
	var ohne := HudStatusSheet.build_content(stats, {"energie": 5.0})
	var chip_ohne: Control = ohne.find_child("BuffEnergie", true, false)
	var label_ohne: Label = chip_ohne.find_child("BuffValue", true, false)
	assert_false(label_ohne.text.begins_with("☀"), "ohne erholt keine Sonne")
	content.free()
	ohne.free()


## ---------------------------------------------- Lambda-Tripwire (REISEPASS)


## Quelltext-Tripwire für ALLE gemeldeten Kauf-Pfade: das Wert-Capture-
## Muster (`var bezahlt …` als lokaler bool) darf nicht zurückkommen —
## wer den Kauf-Guard anfasst, MUSS beim Dictionary-Capture bleiben.
func test_kauf_lambdas_nutzen_dictionary_capture_tripwire() -> void:
	var kaputt := RegEx.new()
	kaputt.compile("var\\s+bezahlt\\s*:?=\\s*(false|true)\\b")
	for pfad in KAUF_DATEIEN:
		var quelle := FileAccess.get_file_as_string(pfad)
		assert_true(not quelle.is_empty(), "Quelle lädt: %s" % pfad)
		assert_true(
			kaputt.search(quelle) == null,
			"%s: Wert-Typ-Capture im Kauf-Lambda (bitte Dictionary-Capture nutzen)" % pfad
		)
		if quelle.contains("Economy.spend"):
			assert_true(
				quelle.contains("zahlung[") or quelle.contains("bezahlt[0]"),
				"%s: spend-Ergebnis muss über eine geteilte Referenz zurückkommen" % pfad
			)

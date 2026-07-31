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

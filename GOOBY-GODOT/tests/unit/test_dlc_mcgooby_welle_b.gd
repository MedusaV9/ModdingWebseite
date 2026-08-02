extends TestCase
## G6/MCGOOBY-B — Welle B des McGooby-DLC: Kauf-Gate (McGoobyKauf atomar +
## McGoobyOffer-Sheet, das McGooby-untypisch AUCH unter dem Level-Gate zeigt),
## mehrstufige Bestell-Zettel über die interaktiven Stationen (McGoobySchicht-
## Plan: Grill-Tap, Fritteuse HALTEN+Salz-Moment, Getränke-Zapfen mit
## Becher-Größen + Sprudel-Gag) mit Goldwerten (Seed → exakte Pläne/Kassen),
## McGooby-Bühne (1×/Schicht, Bonus = reines Trinkgeld) und UI-Konformität
## im Leitformat 2868×1320 (Inhaltsspalte, 44-pt-Floor, Playtest-Befund B2:
## Stations-Pills verdecken keine Slots). Welle-A-Grundlagen (Demo-Schicht,
## Grill-Timing, Abrechnung) testet test_dlc_mcgooby.gd; den Hub-Status
## test_w14_dlchub.gd.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

const SCHICHT_SZENE := "res://scripts/dlc/mcgooby/schicht_scene.tscn"
const GOLD_SEED := 4711
## Leitformat iPhone 17 Pro Max quer (physische px, Screen-Scale 3).
const LEIT_QUER := Vector2i(2868, 1320)

var _dir_seq := 0
var _saved_root_size := Vector2i.ZERO


## GameState-Double: dotted get/set wie /root/GameState + update()-Pfad
## (Economy.award/spend der Szene bzw. des Kaufs laufen über update).
class FakeGameState:
	extends RefCounted
	var s: Dictionary = {"economy": {"coins": 0}}

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = s
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func set_value(path: String, wert: Variant) -> void:
		var teile := path.split(".")
		var node: Dictionary = s
		for i in teile.size() - 1:
			if not (node.get(teile[i]) is Dictionary):
				node[teile[i]] = {}
			node = node[teile[i]]
		node[teile[teile.size() - 1]] = wert

	func update(mutator: Callable) -> void:
		mutator.call(s)


## --------------------------------------------------------------- Helfer


## Echter GameState für die Kauf-Atomik (Muster test_dlc_goobye._fresh_gs).
func _fresh_gs(level: int, coins: int) -> Node:
	McGoobyState.reset_for_tests()
	McGoobyState.register_slice()
	_dir_seq += 1
	var dir := "user://mcgooby_b_tests/%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("progression.level", level)
	gs.set_value("economy.coins", coins)
	return gs


func _teardown_gs(gs: Node) -> void:
	gs.free()
	SaveSchema.unregister_slice(McGoobyState.SLICE_ID)
	McGoobyState.reset_for_tests()
	McGoobyKatalog.reset_cache()


## Double mit gekauftem Laden (volle Schicht startet direkt).
func _gs_voll() -> FakeGameState:
	var gs := FakeGameState.new()
	gs.set_value("mcgooby.introGesehen", true)
	gs.set_value("mcgooby.gekauft", true)
	return gs


func _szene(gs: Object) -> McGoobySchichtScene:
	McGoobyKatalog.reset_cache()
	var szene: McGoobySchichtScene = (load(SCHICHT_SZENE) as PackedScene).instantiate()
	szene.gs_override = gs
	szene.seed_override = GOLD_SEED
	szene.auto_navigate = false
	tree.root.add_child(szene)
	return szene


## Fenster fürs Leitformat pinnen/zurückstellen (Muster test_g7_phone).
func _pin(size: Vector2i, screen_scale := 0.0) -> void:
	if _saved_root_size == Vector2i.ZERO:
		_saved_root_size = tree.root.size
	UiScale.screen_scale_override = screen_scale
	tree.root.size = size
	tree.root.size_changed.emit()
	await wait_frames(2)


func _unpin() -> void:
	UiScale.screen_scale_override = 0.0
	if _saved_root_size != Vector2i.ZERO:
		tree.root.size = _saved_root_size
		_saved_root_size = Vector2i.ZERO
	tree.root.size_changed.emit()
	await wait_frames(2)


## ------------------------------------------------------ Katalog (Welle B)


func test_katalog_welle_b_balance_stationen_und_becher() -> void:
	McGoobyKatalog.reset_cache()
	var bal := McGoobyKatalog.balance()
	for key: String in [
		"bestellungen_voll_min",
		"bestellungen_voll_max",
		"positionen_max",
		"punkte_salz",
		"salz_fenster_sec",
		"becher",
		"buehne_trinkgeld",
		"freischalt_level",
		"preis",
		"bot_salz_skill",
	]:
		assert_true(bal.has(key), "Welle-B-Balance-Key %s vorhanden" % key)
	assert_eq(McGoobyKatalog.freischalt_level(), 14, "Kauf-Level-Gate (Doc §6.2)")
	assert_eq(McGoobyKatalog.preis(), 3000, "Kaufpreis (Doc §6.2)")
	assert_eq(
		McGoobyKatalog.STATIONEN_INTERAKTIV,
		["grill", "fritteuse", "getraenke"] as Array[String],
		"Welle B spielt Grill + Fritteuse + Zapfhahn (Belegen/Shake folgen)"
	)
	# Getränke-Station im Pack definiert (Name + Geste beidsprachig).
	var station := McGoobyKatalog.station("getraenke")
	assert_false(station.is_empty(), "Stations-Definition getraenke existiert")
	for feld: String in ["name_de", "name_en", "geste_de", "geste_en"]:
		assert_false(str(station.get(feld, "")).is_empty(), "getraenke.%s gefüllt" % feld)
	# Becher-Skalierung: NUR gar_sec skaliert — das goldene Fenster bleibt
	# gleich breit (Größe ändert Geduld, nicht Fairness).
	var basis := McGoobyKatalog.timing("getraenke")
	var gross := McGoobyKatalog.timing_mit_becher(basis, "gross")
	assert_almost(float(gross["gar_sec"]), float(basis["gar_sec"]) * 1.3, 1e-6, "gross ×1,3")
	assert_almost(float(gross["fenster_sec"]), float(basis["fenster_sec"]), 1e-6, "Fenster fix")
	var klein := McGoobyKatalog.timing_mit_becher(basis, "klein")
	assert_true(float(klein["gar_sec"]) < float(basis["gar_sec"]), "kleiner Becher schneller")
	assert_almost(McGoobyKatalog.becher_mult("unbekannt"), 1.0, 1e-6, "Fallback-Faktor 1,0")


func test_rezepte_interaktiv_und_getraenke_rezepte() -> void:
	McGoobyKatalog.reset_cache()
	var ids: Array[String] = []
	for rezept: Dictionary in McGoobyKatalog.rezepte_interaktiv():
		ids.append(str(rezept.get("id", "")))
	# Pack-Reihenfolge = Zieh-Reihenfolge (Kontrakt der Goldwert-Tests).
	assert_eq(
		ids,
		(
			[
				"gooby_mac",
				"kaese_knusperle",
				"garten_gooby",
				"gurken_deluxe",
				"moehren_pommes",
				"pommes_klassik",
				"nugget_woelkchen",
				"gooby_brause",
				"sprudelwasser_deluxe",
				"kirsch_karacho",
			]
			as Array[String]
		),
		"10 interaktive Rezepte in Pack-Reihenfolge (Shake-Bar folgt Welle C)"
	)
	# Alle drei Getränke-Rezepte schema-valide und an der Zapf-Station.
	for id: String in ["gooby_brause", "sprudelwasser_deluxe", "kirsch_karacho"]:
		var def := McGoobyKatalog.rezept(id)
		assert_true(McGoobyKatalog.ist_gueltig(def), "%s schema-valide" % id)
		assert_true((def.get("stationen", []) as Array).has("getraenke"), "%s zapft" % id)
	# Sprudelwasser Deluxe: verengtes Fenster (nur Sprudel, null Verzeihung).
	var deluxe := McGoobyKatalog.rezept("sprudelwasser_deluxe")
	assert_true(float(deluxe.get("fenster_mult", 1.0)) < 1.0, "Deluxe-Fenster verengt")


## ------------------------------------------------------------ Plan-Logik


func test_aufgaben_fuer_stationen_und_salz() -> void:
	McGoobyKatalog.reset_cache()
	# hat_salz: NUR Fritteusen-Rezepte mit Salz-Schritt.
	assert_true(McGoobySchichtPlan.hat_salz(McGoobyKatalog.rezept("pommes_klassik")))
	assert_true(
		McGoobySchichtPlan.hat_salz(McGoobyKatalog.rezept("moehren_pommes")),
		"Glitzersalz zählt als Salz-Schritt"
	)
	assert_false(McGoobySchichtPlan.hat_salz(McGoobyKatalog.rezept("nugget_woelkchen")))
	assert_false(McGoobySchichtPlan.hat_salz(McGoobyKatalog.rezept("gooby_mac")))
	# GoobyMac = Doppeldecker: 2 Wende-Taps; Belegen (Welle C) erzeugt nichts.
	var rng := GoobyRng.new(1)
	var mac := McGoobySchichtPlan.aufgaben_fuer(McGoobyKatalog.rezept("gooby_mac"), rng)
	assert_eq(mac.size(), 2, "2 Grill-Taps für 2 Pattys")
	for aufgabe: Dictionary in mac:
		assert_eq(str(aufgabe["art"]), McGoobySchichtPlan.ART_TAP)
		assert_eq(str(aufgabe["station"]), "grill")
	# Pommes: EINE Halte-Aufgabe MIT Salz-Moment.
	var pommes := McGoobySchichtPlan.aufgaben_fuer(McGoobyKatalog.rezept("pommes_klassik"), rng)
	assert_eq(pommes.size(), 1, "1 Korb-Aufgabe")
	assert_eq(str(pommes[0]["art"]), McGoobySchichtPlan.ART_HALTEN)
	assert_true(bool(pommes[0]["salz"]), "Salz-Moment hängt am Korb")
	# Getränk: EINE Halte-Aufgabe mit deterministisch gezogenem Becher.
	var brause := McGoobySchichtPlan.aufgaben_fuer(McGoobyKatalog.rezept("gooby_brause"), rng)
	assert_eq(brause.size(), 1, "1 Zapf-Aufgabe")
	assert_eq(str(brause[0]["station"]), "getraenke")
	assert_true(McGoobyKatalog.BECHER_GROESSEN.has(str(brause[0]["becher"])), "Becher gezogen")
	# Shake-Rezept (Welle C): keine interaktive Aufgabe.
	var shake := McGoobySchichtPlan.aufgaben_fuer(McGoobyKatalog.rezept("rosa_flausch"), rng)
	assert_true(shake.is_empty(), "Shake-Bar erzeugt noch keine Aufgaben")


func test_plan_golden_seed_4711() -> void:
	McGoobyKatalog.reset_cache()
	var folge := McGoobySchichtPlan.plan(
		GOLD_SEED, McGoobyKatalog.rezepte_interaktiv(), McGoobyKatalog.balance()
	)
	assert_eq(folge.size(), 3, "Seed 4711 → exakt 3 Bestellungen")
	# Golden-Zettel: [rezept_id, art, station, salz, becher] je Posten.
	var soll: Array = [
		[
			["garten_gooby", "tap", "grill", false, ""],
			["sprudelwasser_deluxe", "halten", "getraenke", false, "gross"],
		],
		[
			["pommes_klassik", "halten", "fritteuse", true, ""],
			["gurken_deluxe", "tap", "grill", false, ""],
		],
		[
			["nugget_woelkchen", "halten", "fritteuse", false, ""],
		],
	]
	for i in folge.size():
		assert_eq(int(folge[i]["nr"]), i + 1, "Bestell-Nummern fortlaufend")
		var positionen: Array = folge[i]["positionen"]
		assert_eq(positionen.size(), (soll[i] as Array).size(), "Posten Bestellung %d" % (i + 1))
		for p in positionen.size():
			var pos: Dictionary = positionen[p]
			var erwartet: Array = soll[i][p]
			assert_eq(str(pos["rezept_id"]), str(erwartet[0]), "Rezept %d/%d" % [i + 1, p + 1])
			var aufgaben: Array = pos["aufgaben"]
			assert_eq(aufgaben.size(), 1, "Golden-Posten tragen je 1 Aufgabe")
			var aufgabe: Dictionary = aufgaben[0]
			assert_eq(str(aufgabe["art"]), str(erwartet[1]))
			assert_eq(str(aufgabe["station"]), str(erwartet[2]))
			assert_eq(bool(aufgabe["salz"]), bool(erwartet[3]))
			assert_eq(str(aufgabe["becher"]), str(erwartet[4]))
	assert_eq(McGoobySchichtPlan.aufgaben_in(folge[0]), 2, "Zettel 1 trägt 2 Schritte")


func test_plan_deterministisch_und_schranken() -> void:
	McGoobyKatalog.reset_cache()
	var rezepte := McGoobyKatalog.rezepte_interaktiv()
	var bal := McGoobyKatalog.balance()
	assert_eq(
		var_to_str(McGoobySchichtPlan.plan(1234, rezepte, bal)),
		var_to_str(McGoobySchichtPlan.plan(1234, rezepte, bal)),
		"gleicher Seed = identischer Plan"
	)
	var lo := int(bal["bestellungen_voll_min"])
	var hi := int(bal["bestellungen_voll_max"])
	var posten_max := int(bal["positionen_max"])
	for seed_wert: int in [1, 7, 42, 99, GOLD_SEED, 1234]:
		var folge := McGoobySchichtPlan.plan(seed_wert, rezepte, bal)
		assert_true(
			folge.size() >= lo and folge.size() <= hi,
			"Seed %d: Bestell-Anzahl in [%d, %d]" % [seed_wert, lo, hi]
		)
		for bestellung: Dictionary in folge:
			var positionen: Array = bestellung["positionen"]
			assert_true(
				positionen.size() >= 1 and positionen.size() <= posten_max,
				"Posten-Anzahl in [1, %d]" % posten_max
			)
			for position: Dictionary in positionen:
				for aufgabe: Dictionary in position["aufgaben"]:
					assert_true(
						McGoobyKatalog.STATIONEN_INTERAKTIV.has(str(aufgabe["station"])),
						"nur interaktive Stationen auf dem Zettel"
					)
					if str(aufgabe["station"]) == "getraenke":
						assert_true(
							McGoobyKatalog.BECHER_GROESSEN.has(str(aufgabe["becher"])),
							"Zapf-Aufgabe trägt gültige Becher-Größe"
						)
					else:
						assert_eq(str(aufgabe["becher"]), "", "Becher nur am Zapfhahn")
	assert_true(McGoobySchichtPlan.plan(1, [], bal).is_empty(), "leeres Menü = leerer Plan")


func test_salz_fenster_und_timing_fuer() -> void:
	McGoobyKatalog.reset_cache()
	var bal := McGoobyKatalog.balance()
	var fenster := McGoobySchichtPlan.salz_fenster_sec(bal)
	assert_almost(fenster, 1.2, 1e-6, "Salz-Fenster aus dem Pack")
	var treffer := McGoobySchichtPlan.salz_bewerten(fenster, bal)
	assert_true(bool(treffer["getroffen"]), "Fenster-Ende inklusiv")
	assert_eq(int(treffer["punkte"]), 4, "Glitzersalz-Bonus aus dem Pack")
	var vorbei := McGoobySchichtPlan.salz_bewerten(fenster + 0.01, bal)
	assert_false(bool(vorbei["getroffen"]), "danach kein Bonus …")
	assert_eq(int(vorbei["punkte"]), 0, "… aber auch KEIN Punktabzug (kein Fail)")
	# timing_fuer: Zapfen skaliert mit dem Becher, Rezepte verengen Fenster.
	var zapf := {"art": "halten", "station": "getraenke", "salz": false, "becher": "gross"}
	var timing := McGoobySchichtPlan.timing_fuer(zapf, McGoobyKatalog.rezept("gooby_brause"))
	assert_almost(float(timing["gar_sec"]), 3.0 * 1.3, 1e-6, "großer Becher füllt 3,9 s")
	var korb := {"art": "halten", "station": "fritteuse", "salz": true, "becher": ""}
	var eng := McGoobySchichtPlan.timing_fuer(korb, McGoobyKatalog.rezept("moehren_pommes"))
	assert_almost(float(eng["fenster_sec"]), 1.2 * 0.75, 1e-6, "Möhren-Fenster verengt")


func test_golden_autoplay_voll() -> void:
	McGoobyKatalog.reset_cache()
	var rezepte := McGoobyKatalog.rezepte_interaktiv()
	var bal := McGoobyKatalog.balance()
	var gold := McGoobySchichtPlan.simulate_autoplay_voll(GOLD_SEED, rezepte, bal)
	assert_eq(int(gold["bestellungen"]), 3)
	assert_eq(int(gold["perfekt"]), 4, "Bot greift 4/5 Aufgaben perfekt")
	assert_eq(int(gold["roestaroma"]), 1)
	assert_eq(int(gold["salz_treffer"]), 1, "Bot salzt den einen Salz-Moment")
	assert_eq(int(gold["punkte"]), 94, "40 + 5 + 4 + 3×15")
	assert_eq(int(gold["trinkgeld"]), 4)
	assert_eq(int(gold["muenzen"]), 27, "floor(94/4) + 4 Trinkgeld")
	var gold2 := McGoobySchichtPlan.simulate_autoplay_voll(1234, rezepte, bal)
	assert_eq(int(gold2["bestellungen"]), 5)
	assert_eq(int(gold2["punkte"]), 144)
	assert_eq(int(gold2["muenzen"]), 38)


## ------------------------------------------------------------ Abrechnung


func test_abrechnung_extra_trinkgeld_additiv() -> void:
	McGoobyKatalog.reset_cache()
	var bal := McGoobyKatalog.balance()
	var ergebnisse := [{"punkte": 40, "fehlerfrei": true}, {"punkte": 20, "fehlerfrei": false}]
	var ohne := McGoobyAbrechnung.abrechnung(ergebnisse, bal)
	var mit := McGoobyAbrechnung.abrechnung(ergebnisse, bal, 6)
	assert_eq(int(ohne["buehne_trinkgeld"]), 0, "Default: kein Bühnen-Bonus")
	assert_eq(int(mit["buehne_trinkgeld"]), 6, "Bonus liegt als eigene Zeile in der Kasse")
	assert_eq(int(mit["punkte"]), int(ohne["punkte"]), "Bonus ändert NIE die Punkte")
	assert_eq(int(mit["muenzen_basis"]), int(ohne["muenzen_basis"]), "coin_table unberührt")
	assert_eq(int(mit["trinkgeld"]), int(ohne["trinkgeld"]) + 6, "Bonus ist reines Trinkgeld")
	assert_eq(int(mit["muenzen"]), int(ohne["muenzen"]) + 6)
	var negativ := McGoobyAbrechnung.abrechnung([], bal, -5)
	assert_eq(int(negativ["buehne_trinkgeld"]), 0, "negativer Bonus wird geklemmt")


## ------------------------------------------------------------ Kauf-Gate


func test_kauf_gate_und_atomik() -> void:
	McGoobyKatalog.reset_cache()
	assert_eq(McGoobyKauf.check(null), McGoobyKauf.RESULT_LOCKED, "ohne GameState fail-closed")
	var gs := _fresh_gs(McGoobyKatalog.freischalt_level() - 1, 99999)
	assert_eq(McGoobyKauf.check(gs), McGoobyKauf.RESULT_LOCKED, "unter dem Level-Gate gesperrt")
	assert_eq(McGoobyKauf.kaufe(gs), McGoobyKauf.RESULT_LOCKED)
	assert_eq(int(gs.get_value("economy.coins")), 99999, "keine Abbuchung im Gesperrt-Fall")
	assert_eq(bool(gs.get_value("mcgooby.gekauft", false)), false)
	_teardown_gs(gs)
	var arm := _fresh_gs(McGoobyKatalog.freischalt_level(), McGoobyKatalog.preis() - 1)
	assert_eq(McGoobyKauf.check(arm), McGoobyKauf.RESULT_BROKE)
	assert_eq(McGoobyKauf.kaufe(arm), McGoobyKauf.RESULT_BROKE, "zu wenig Münzen blockt")
	assert_eq(int(arm.get_value("economy.coins")), McGoobyKatalog.preis() - 1, "unangetastet")
	assert_eq(bool(arm.get_value("mcgooby.gekauft", false)), false, "nichts halb gebucht")
	_teardown_gs(arm)


func test_kauf_bucht_preis_einmalig() -> void:
	McGoobyKatalog.reset_cache()
	var gs := _fresh_gs(McGoobyKatalog.freischalt_level(), McGoobyKatalog.preis() + 77)
	assert_eq(McGoobyKauf.check(gs), McGoobyKauf.RESULT_OK, "Level + Münzen reichen")
	assert_eq(McGoobyKauf.kaufe(gs), McGoobyKauf.RESULT_OK)
	assert_eq(int(gs.get_value("economy.coins")), 77, "exakt der Preis wird abgebucht")
	assert_eq(bool(gs.get_value("mcgooby.gekauft")), true)
	assert_true(int(gs.get_value("mcgooby.gekauftAm", 0)) > 0, "Kaufzeit gemerkt")
	assert_eq(bool(gs.get_value("mcgooby.angebotGesehen")), true, "Angebot gilt als gesehen")
	assert_eq(bool(gs.get_value("mcgooby.angebotVerschoben")), false, "Kauf löscht Verschoben")
	assert_eq(McGoobyKauf.kaufe(gs), McGoobyKauf.RESULT_OWNED, "Doppelkauf blockiert")
	assert_eq(int(gs.get_value("economy.coins")), 77, "nur EINMAL abgebucht")
	_teardown_gs(gs)


func test_angebot_sheet_gate_kauf_und_spaeter() -> void:
	McGoobyKatalog.reset_cache()
	McGoobyOffer.auto_navigate = false
	var host := Control.new()
	tree.root.add_child(host)
	# Besitzer sehen NIE ein Angebot.
	var besitzer := FakeGameState.new()
	besitzer.set_value("mcgooby.gekauft", true)
	assert_true(McGoobyOffer.zeige(host, besitzer) == null, "gekauft blockt das Sheet")
	# McGooby-Zuschnitt: UNTER dem Level-Gate öffnet das Sheet TROTZDEM —
	# Kaufen ist gesperrt, die Gate-Zeile nennt Soll- und Ist-Level.
	var klein := FakeGameState.new()
	klein.set_value("progression.level", 7)
	klein.set_value("economy.coins", 99999)
	var sheet := McGoobyOffer.zeige(host, klein)
	assert_true(sheet != null, "Angebot zeigt sich auch unter dem Gate")
	await wait_frames(1)
	assert_eq(bool(klein.get_value("mcgooby.angebotGesehen")), true, "gesehen gemerkt")
	var kaufen: Button = sheet.get_meta(McGoobyOffer.META_KAUFEN, null)
	assert_true(kaufen != null and kaufen.disabled, "Kaufen unter dem Gate gesperrt")
	var hinweis: Label = sheet.get_meta(McGoobyOffer.META_HINWEIS, null)
	assert_true(
		hinweis.text.contains(str(McGoobyKatalog.freischalt_level())), "Gate-Zeile: Soll-Level"
	)
	assert_true(hinweis.text.contains("7"), "Gate-Zeile: Ist-Level")
	sheet.queue_free()
	await wait_frames(1)
	# Zu wenig Münzen: Kauf-Klick lässt alles stehen + Klartext-Zeile.
	var arm := FakeGameState.new()
	arm.set_value("progression.level", McGoobyKatalog.freischalt_level())
	arm.set_value("economy.coins", 3)
	var sheet2 := McGoobyOffer.zeige(host, arm)
	await wait_frames(1)
	var kaufen2: Button = sheet2.get_meta(McGoobyOffer.META_KAUFEN, null)
	assert_false(kaufen2.disabled, "ab dem Gate-Level ist Kaufen aktiv")
	kaufen2.pressed.emit()
	await wait_frames(1)
	assert_eq(int(arm.get_value("economy.coins")), 3, "Münzen unangetastet")
	assert_eq(bool(arm.get_value("mcgooby.gekauft", false)), false)
	var hinweis2: Label = sheet2.get_meta(McGoobyOffer.META_HINWEIS, null)
	assert_true(
		hinweis2.text.contains(str(McGoobyKatalog.preis())), "Zu-wenig-Zeile nennt den Preis"
	)
	# „Später“ merkt den Stand (das Angebot bleibt nach jeder Demo erreichbar).
	var spaeter: Button = sheet2.get_meta(McGoobyOffer.META_SPAETER, null)
	spaeter.pressed.emit()
	await wait_frames(1)
	assert_eq(bool(arm.get_value("mcgooby.angebotVerschoben")), true, "verschoben gemerkt")
	# Genug Münzen: der Sheet-Kauf bucht atomar.
	var reich := FakeGameState.new()
	reich.set_value("progression.level", McGoobyKatalog.freischalt_level())
	reich.set_value("economy.coins", McGoobyKatalog.preis())
	var sheet3 := McGoobyOffer.zeige(host, reich)
	await wait_frames(1)
	(sheet3.get_meta(McGoobyOffer.META_KAUFEN, null) as Button).pressed.emit()
	await wait_frames(1)
	assert_eq(bool(reich.get_value("mcgooby.gekauft")), true, "Sheet-Kauf greift")
	assert_eq(int(reich.get_value("economy.coins")), 0, "Preis abgebucht")
	McGoobyOffer.auto_navigate = true
	host.queue_free()
	await wait_frames(1)


## ---------------------------------------------------------- Schicht-Szene


func test_schicht_szene_demo_zu_angebot_zu_voll() -> void:
	var gs := FakeGameState.new()
	gs.set_value("economy.coins", McGoobyKatalog.preis() + 100)
	gs.set_value("progression.level", McGoobyKatalog.freischalt_level())
	gs.set_value("mcgooby.introGesehen", true)
	var szene := _szene(gs)
	await wait_frames(3)
	assert_false(szene.ist_voll_modus(), "ohne Kauf: Demo-Modus (Welle A)")
	var block: Control = szene.find_child("StationenBlock", true, false)
	assert_false(block.visible, "Demo zeigt keine Stations-Pills")
	# Demo golden durchspielen (Seed 4711: 2 Bestellungen, 3 Pattys, 19 Münzen).
	var timing := McGoobyKatalog.timing("grill")
	var sicherheit := 0
	while szene.ist_am_laufen() and sicherheit < 12:
		sicherheit += 1
		szene.patty_zeit_setzen(float(timing["gar_sec"]) + 0.2)
		szene.patty_knopf().pressed.emit()
		await wait_frames(1)
	assert_true(szene.ist_ende_offen(), "Ende-Karte offen")
	# Übergang „Schicht geschafft → Angebot“ (Doc §6.2): Block auf der Karte.
	var angebot_block: Control = szene.find_child("AngebotBlock", true, false)
	assert_true(angebot_block.visible, "Angebots-Block ohne Kauf sichtbar")
	szene.angebot_knopf().pressed.emit()
	await wait_frames(2)
	var spaeter: Button = szene.find_child("Spaeter", true, false)
	assert_true(spaeter != null, "Angebots-Sheet offen")
	spaeter.pressed.emit()
	await wait_frames(2)
	assert_eq(bool(gs.get_value("mcgooby.angebotVerschoben")), true, "Später gemerkt")
	assert_false(szene.ist_voll_modus(), "Später = weiter Demo")
	assert_true(szene.ist_ende_offen(), "Ende-Karte bleibt offen (Nochmal tippbar)")
	# Zweiter Anlauf: kaufen — die VOLLE Schicht startet in place.
	szene.angebot_knopf().pressed.emit()
	await wait_frames(2)
	var kaufen: Button = szene.find_child("Kaufen", true, false)
	assert_true(kaufen != null and not kaufen.disabled, "Kaufen aktiv (Level reicht)")
	kaufen.pressed.emit()
	await wait_frames(2)
	assert_eq(bool(gs.get_value("mcgooby.gekauft")), true, "Kauf gebucht")
	assert_eq(int(gs.get_value("economy.coins", 0)), 119, "3100 + 19 Demo-Lohn − 3000 Preis")
	assert_true(szene.ist_voll_modus(), "volle Schicht in place — kein Remount")
	assert_true(szene.ist_am_laufen(), "Schicht läuft direkt los")
	assert_false(szene.ist_ende_offen(), "Ende-Karte zu")
	assert_true(block.visible, "Stations-Pills sichtbar")
	assert_eq(szene.stationen_pills().size(), 3, "3 interaktive Stationen")
	szene.queue_free()
	await wait_frames(1)


func test_schicht_szene_volle_schicht_golden() -> void:
	var gs := _gs_voll()
	var szene := _szene(gs)
	await wait_frames(3)
	assert_true(szene.ist_voll_modus(), "gekauft = volle Schicht")
	assert_true(szene.ist_am_laufen(), "kein Intro mehr, Schicht läuft")
	# Golden-Plan Seed 4711: Zettel 1 = Garten-Gooby + Sprudelwasser (gross).
	var bestellung := szene.bestellung_aktuell()
	assert_eq(int(bestellung.get("nr", 0)), 1)
	var positionen: Array = bestellung.get("positionen", [])
	assert_eq(positionen.size(), 2, "Zettel 1 ist mehrstufig")
	assert_eq(str((positionen[0] as Dictionary)["rezept_id"]), "garten_gooby")
	assert_eq(str((positionen[1] as Dictionary)["rezept_id"]), "sprudelwasser_deluxe")
	assert_eq(str(szene.aufgabe_aktuell().get("station", "")), "grill", "erst der Grill")
	# Bühne: 1×/Schicht — Doppel-Tipp bucht nichts doppelt.
	szene.buehne().tempo = 0.05
	assert_false(szene.buehne_knopf().disabled, "Bühne frei")
	szene.buehne_knopf().pressed.emit()
	assert_true(szene.buehne().laeuft(), "Auftritt läuft — Schicht friert ein")
	assert_true(szene.buehne_knopf().disabled, "Knopf verbraucht")
	szene.buehne_knopf().pressed.emit()
	var fertig := await wait_until(func() -> bool: return not szene.buehne().laeuft(), 8000)
	assert_true(fertig, "Auftritt endet von selbst")
	assert_eq(int(gs.get_value("mcgooby.buehne.auftritte", 0)), 1, "genau 1 Auftritt gebucht")
	# Alle 5 Aufgaben perfekt + den einen Salz-Moment treffen (injizierte
	# Zeit statt Frames: patty_zeit_setzen pinnt die Gar-Uhr).
	var sicherheit := 0
	while szene.ist_am_laufen() and sicherheit < 40:
		sicherheit += 1
		if szene.salz_ist_aktiv():
			szene.patty_knopf().button_down.emit()
			await wait_frames(1)
			continue
		var aufgabe := szene.aufgabe_aktuell()
		var timing := szene.aufgabe_timing()
		var im_fenster := float(timing["gar_sec"]) + float(timing["fenster_sec"]) * 0.5
		if str(aufgabe.get("art", "")) == McGoobySchichtPlan.ART_HALTEN:
			szene.patty_knopf().button_down.emit()
			szene.patty_zeit_setzen(im_fenster)
			szene.patty_knopf().button_up.emit()
		else:
			szene.patty_zeit_setzen(im_fenster)
			szene.patty_knopf().button_down.emit()
		await wait_frames(1)
	assert_true(szene.ist_ende_offen(), "Schicht-Ende-Karte offen")
	var kasse := szene.schicht_ergebnis()
	assert_eq(int(kasse["punkte"]), 99, "5×10 Perfekt + 4 Salz + 3×15 Bonus")
	assert_eq(int(kasse["buehne_trinkgeld"]), 6, "Bühnen-Bonus in der Kasse")
	assert_eq(int(kasse["trinkgeld"]), 13, "Combo-Kette 2+2+3 + Bühne 6")
	assert_eq(int(kasse["muenzen"]), 37, "floor(99/4)=24 + 13 Trinkgeld")
	assert_eq(int(gs.get_value("economy.coins", 0)), 37, "Münzen über Economy.award")
	assert_eq(int(gs.get_value("mcgooby.schichten.bestwert", 0)), 99, "Bestwert verbucht")
	# Kassensturz-Zeilen: Salz + Bühne sichtbar; Angebots-Block WEG (gekauft).
	assert_eq((szene.find_child("Wert_salz", true, false) as Label).text, "1")
	assert_eq((szene.find_child("Wert_buehne", true, false) as Label).text, "6")
	assert_false(
		(szene.find_child("AngebotBlock", true, false) as Control).visible,
		"Besitzer sehen kein Angebot mehr"
	)
	# Nochmal: neue Schicht = Bühne wieder frei (1×/Schicht, nicht 1×/Spiel).
	(szene.find_child("Nochmal", true, false) as Button).pressed.emit()
	await wait_frames(1)
	assert_true(szene.ist_am_laufen(), "nächste Schicht läuft")
	assert_false(szene.buehne_knopf().disabled, "neue Schicht = neue Show")
	szene.queue_free()
	await wait_frames(1)


func test_schicht_szene_halten_sprudel_und_salz_vorbei() -> void:
	var gs := _gs_voll()
	var szene := _szene(gs)
	await wait_frames(3)
	# Aufgabe 1 (Grill-Tap) perfekt abräumen.
	var timing := szene.aufgabe_timing()
	szene.patty_zeit_setzen(float(timing["gar_sec"]) + float(timing["fenster_sec"]) * 0.5)
	szene.patty_knopf().button_down.emit()
	await wait_frames(1)
	# Aufgabe 2: Sprudelwasser Deluxe im GROSSEN Becher (Golden-Plan).
	var aufgabe := szene.aufgabe_aktuell()
	assert_eq(str(aufgabe.get("station", "")), "getraenke")
	assert_eq(str(aufgabe.get("becher", "")), "gross")
	timing = szene.aufgabe_timing()
	assert_almost(float(timing["gar_sec"]), 3.0 * 1.3, 1e-6, "großer Becher füllt länger")
	# Zu früh loslassen: nichts Schlimmes — Zeit friert, Aufgabe bleibt.
	var callout: Label = szene.find_child("Callout", true, false)
	szene.patty_knopf().button_down.emit()
	szene.patty_zeit_setzen(1.0)
	szene.patty_knopf().button_up.emit()
	assert_eq(str(szene.aufgabe_aktuell().get("becher", "")), "gross", "Aufgabe bleibt aktiv")
	assert_eq(callout.text, I18nService.t("dlc_mcgooby.schicht.zu_leer"), "Zapf-Callout")
	# Überlauf im Griff: Sprudel-Gag (Schaumkrone) statt Fail.
	szene.patty_knopf().button_down.emit()
	var ende_zeit := (
		float(timing["gar_sec"]) + float(timing["fenster_sec"]) + float(timing["nachlauf_sec"])
	)
	szene.patty_zeit_setzen(ende_zeit + 0.1)
	await wait_frames(2)
	assert_eq(
		callout.text,
		I18nService.t("dlc_mcgooby.schicht.uebergesprudelt"),
		"Getränke schäumen über statt zu verkohlen"
	)
	assert_true(szene.ist_am_laufen(), "Übersprudeln ist kein Fail-State")
	# Zettel 2, Posten 1: Pommes Klassik — Korb heben öffnet den Salz-Moment.
	aufgabe = szene.aufgabe_aktuell()
	assert_eq(str(aufgabe.get("station", "")), "fritteuse")
	assert_true(bool(aufgabe.get("salz", false)), "Salz-Moment hängt am Korb")
	timing = szene.aufgabe_timing()
	szene.patty_knopf().button_down.emit()
	szene.patty_zeit_setzen(float(timing["gar_sec"]) + float(timing["fenster_sec"]) * 0.5)
	szene.patty_knopf().button_up.emit()
	assert_true(szene.salz_ist_aktiv(), "Salz-Fenster öffnet nach dem Korb-Heben")
	# Salz VERPASST: kein Bonus, kein Fail — die Schicht läuft weiter.
	szene.salz_zeit_setzen(McGoobySchichtPlan.salz_fenster_sec(McGoobyKatalog.balance()) + 0.05)
	szene.patty_knopf().button_down.emit()
	assert_false(szene.salz_ist_aktiv(), "Salz-Moment beendet")
	assert_eq(callout.text, I18nService.t("dlc_mcgooby.schicht.salz_vorbei"))
	assert_true(szene.ist_am_laufen(), "verpasstes Salz ist kein Fail")
	szene.queue_free()
	await wait_frames(1)


## --------------------------------------------- UI-Konformität (Leitformat)


func test_leitformat_pills_verdecken_keine_slots() -> void:
	await _pin(LEIT_QUER, 3.0)
	var gs := _gs_voll()
	var szene := _szene(gs)
	await wait_frames(4)
	var m := ScreenShell.metrics(szene.get_viewport())
	var floor_px := float(m["floor_px"])
	var canvas: Vector2 = m["canvas"]
	# Inhaltsspalte trägt das W16-Meta; der Stations-Block lebt IN ihr.
	var spalte: Control = szene.find_child("Spalte", true, false)
	assert_true(spalte.has_meta(ScreenShell.META_CONTENT_COLUMN), "Content-Column-Meta")
	var block: Control = szene.find_child("StationenBlock", true, false)
	assert_true(block.visible, "Voll-Modus zeigt den Stations-Block")
	assert_true(
		spalte.get_global_rect().grow(1.0).encloses(block.get_global_rect()),
		"Stations-Block bleibt in der Inhaltsspalte"
	)
	# 44-pt-Touch-Floor auf allen neuen Tippzielen (ScreenShell.touch_target).
	var ziele: Array[Button] = szene.stationen_pills()
	assert_eq(ziele.size(), 3, "3 Stations-Pills (grill/fritteuse/getraenke)")
	ziele.append(szene.buehne_knopf())
	for ziel: Button in ziele:
		assert_true(ziel.size.y >= floor_px - 0.5, "%s ≥ Touch-Floor" % ziel.name)
	assert_true(szene.patty_knopf().size.y >= floor_px - 0.5, "Aktions-Knopf ≥ Floor")
	# Playtest-Befund B2 (G8-PT2): Pills verdecken NIE Slots — weder den
	# Aktions-Knopf noch Bestell-Zettel noch Gar-Balken; alle im Bild.
	var patty_rect := szene.patty_knopf().get_global_rect()
	var karte_rect := (szene.find_child("BestellKarte", true, false) as Control).get_global_rect()
	var balken_rect := (szene.find_child("GarBalken", true, false) as Control).get_global_rect()
	for ziel: Button in ziele:
		var rect := ziel.get_global_rect()
		assert_false(rect.intersects(patty_rect), "%s über dem Aktions-Knopf" % ziel.name)
		assert_false(rect.intersects(karte_rect), "%s über dem Bestell-Zettel" % ziel.name)
		assert_false(rect.intersects(balken_rect), "%s über dem Gar-Balken" % ziel.name)
		assert_true(
			rect.position.x >= -1.0 and rect.end.x <= canvas.x + 1.0,
			"%s liegt horizontal im Bild" % ziel.name
		)
	szene.queue_free()
	await wait_frames(1)
	await _unpin()


## ---------------------------------------------------------------- Strings


func test_strings_de_en_paritaet() -> void:
	I18nService.reset_cache()
	var de := I18nService.table("de")
	var en := I18nService.table("en")
	var anzahl := 0
	for key: String in de:
		if key.begins_with("dlc_mcgooby."):
			anzahl += 1
			assert_true(en.has(key), "EN-Gegenstück fehlt: %s" % key)
			assert_false(str(de[key]).is_empty(), "DE leer: %s" % key)
			assert_false(str(en.get(key, "")).is_empty(), "EN leer: %s" % key)
	for key: String in en:
		if key.begins_with("dlc_mcgooby."):
			assert_true(de.has(key), "DE-Gegenstück fehlt: %s" % key)
	assert_true(anzahl >= 45, "Domain dlc_mcgooby gefüllt (%d Keys)" % anzahl)
	# Die Welle-B-Schlüssel, die der Code zieht, lösen alle auf.
	for key: String in [
		"dlc_mcgooby.knopf.volle_schicht",
		"dlc_mcgooby.angebot.gate",
		"dlc_mcgooby.angebot.zu_wenig",
		"dlc_mcgooby.schicht.halten_fritteuse",
		"dlc_mcgooby.schicht.halten_getraenke",
		"dlc_mcgooby.schicht.becher.gross",
		"dlc_mcgooby.schicht.uebergesprudelt",
		"dlc_mcgooby.schicht.salz_jetzt",
		"dlc_mcgooby.buehne.trinkgeld",
		"dlc_mcgooby.ende.angebot",
	]:
		assert_true(I18nService.has_key(key), "Welle-B-Key fehlt: %s" % key)

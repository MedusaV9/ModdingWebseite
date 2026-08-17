extends TestCase
## W19 MCGOOBY-C — Wächter für Fritteuse + Shake-Bar + volles Menü +
## Laden-Rang (Doc §2.2 #3/#4, §6.1):
## - Fritteusen-/Shake-Logik pur: Zustands-Grenzen, Zug-/Stopp-Wertung,
##   Vergessen/Überdreht (halbe Punkte, nie Fail), fenster_mult (Möhren!),
##   Stations-Autoplay-Goldens auf GoobyRng (Doc §10.4).
## - bestell_folge zieht aus ALLEN Stationen: faire Mischung (Bestellung 1
##   IMMER Grill, Bestellung 2 IMMER neuer Tresen), alle 10 Rezepte
##   erreichbar, Grill-only-Menü (Welle-A/B-Goldens) unverändert.
## - simulate_autoplay zertifiziert JEDE Bestellung über alle 4 Stationen
##   (neue Goldens inkl. dunkel/schaum-Zähler).
## - Laden-Rang (Welle C, Doc §6.1): Slice-Erweiterung `perfekt`,
##   Sterne-Leiter aus dem Pack, ehrliche Ziel-Zeilen, Anzeige im
##   DLC-Hub-Detail und auf der Schicht-Ende-Karte.
## - Szene: Fritteuse als dritter, Shake-Bar als vierter Tab — Halte-Geste
##   (Rühr-Zeit NUR beim Halten), Jonglage-Guard (fremde Knöpfe zählen nie).

const SCHICHT_SZENE := "res://scripts/dlc/mcgooby/schicht_scene.tscn"
const GOLD_SEED := 4711
## Seed mit Shake-Bestellung an zweiter Stelle (garten_gooby → schoko_flausch).
const SHAKE_SEED := 7
## Seed, dessen Bot-Lauf ALLE Fehler-Zähler > 0 zeigt (dunkel/schaum/…).
const BUNT_SEED := 134


## Pinnbare Uhr-Attrappe (Clock-Duck-Typing: now_ms + local_day).
class FakeClock:
	extends RefCounted
	var ms := 1_770_000_000_000
	var tag := "2026-08-03"

	func now_ms() -> int:
		return ms

	func local_day(_at := -1) -> String:
		return tag


## GameState-Double: dotted get/set + update()-Pfad + gepinnte Clock.
class FakeGameState:
	extends RefCounted
	var s: Dictionary = {"economy": {"coins": 0}}
	var clock := FakeClock.new()

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


func _gs(level: int, coins: int) -> FakeGameState:
	var gs := FakeGameState.new()
	gs.set_value("progression.level", level)
	gs.set_value("economy.coins", coins)
	return gs


func _bal() -> Dictionary:
	McGoobyKatalog.reset_cache()
	return McGoobyKatalog.balance()


## ------------------------------------------------------- Fritteuse (a)


func test_fritteuse_logik_zustaende_und_wertung() -> void:
	McGoobyKatalog.reset_cache()
	assert_eq(
		McGoobyStationFritteuse.aktionen_von(McGoobyKatalog.rezept("pommes_klassik")),
		["frittieren", "salz"] as Array[String],
		"Pommes Klassik: 2 Halte-Runden in Schritt-Reihenfolge"
	)
	assert_eq(
		McGoobyStationFritteuse.aktionen_von(McGoobyKatalog.rezept("nugget_woelkchen")),
		["formen", "frittieren", "wolken_dip"] as Array[String],
		"Nugget-Wölkchen: 3 Runden"
	)
	assert_true(
		McGoobyStationFritteuse.aktionen_von(McGoobyKatalog.rezept("gooby_mac")).is_empty(),
		"GoobyMac braucht keine Fritteuse"
	)
	# Zustands-Grenzen am Pack-Timing (gar 5,0 + Fenster 1,2).
	var timing := McGoobyKatalog.timing("fritteuse")
	assert_eq(McGoobyStationFritteuse.zustand(4.99, timing), "blass")
	assert_eq(McGoobyStationFritteuse.zustand(5.0, timing), "goldgelb", "Fenster-Beginn inklusiv")
	assert_eq(McGoobyStationFritteuse.zustand(6.19, timing), "goldgelb")
	assert_eq(McGoobyStationFritteuse.zustand(6.2, timing), "dunkel", "Fenster-Ende exklusiv")
	assert_almost(McGoobyStationFritteuse.fortschritt(3.1, timing), 0.5, 1e-6)
	assert_almost(McGoobyStationFritteuse.fortschritt(99.0, timing), 1.0, 1e-6, "geklemmt")
	var bal := _bal()
	var frueh := McGoobyStationFritteuse.bewerte_zug(1.0, timing, bal)
	assert_eq(str(frueh["wertung"]), "blass", "zu früh gezogen = Korb taucht wieder ein")
	assert_eq(int(frueh["punkte"]), 0, "keine Strafe")
	assert_eq(int(McGoobyStationFritteuse.bewerte_zug(5.5, timing, bal)["punkte"]), 10, "perfekt")
	var spaet := McGoobyStationFritteuse.bewerte_zug(7.0, timing, bal)
	assert_eq(str(spaet["wertung"]), "dunkel", "zu spät = Knusper-Deluxe")
	assert_eq(int(spaet["punkte"]), 5, "halbe Punkte — nie verloren (§4.2)")
	assert_eq(str(McGoobyStationFritteuse.bewerte_vergessen(bal)["wertung"]), "dunkel")
	# Zahlen kommen WIRKLICH aus dem Pack (überschattbare Balance).
	var eigene := {"fritteuse_punkte_perfekt": 12, "fritteuse_punkte_dunkel": 3}
	assert_eq(int(McGoobyStationFritteuse.bewerte_zug(5.5, timing, eigene)["punkte"]), 12)
	assert_eq(int(McGoobyStationFritteuse.bewerte_vergessen(eigene)["punkte"]), 3)
	# Möhren-Pommes verengen ihr Fenster per fenster_mult (knackig!).
	var knackig := McGoobyKatalog.timing("fritteuse", McGoobyKatalog.rezept("moehren_pommes"))
	assert_almost(float(knackig["fenster_sec"]), 0.9, 1e-6, "1,2 × 0,75")
	assert_eq(McGoobyStationFritteuse.zustand(6.0, knackig), "dunkel", "enger = früher dunkel")


func test_fritteuse_autoplay_golden() -> void:
	var bal := _bal()
	var aktionen := McGoobyStationFritteuse.aktionen_von(McGoobyKatalog.rezept("pommes_klassik"))
	var gold := McGoobyStationFritteuse.simulate_autoplay(GOLD_SEED, aktionen, bal)
	assert_eq(int(gold["aktionen"]), 2)
	assert_eq(int(gold["dunkel"]), 0, "Seed 4711: beide Körbe im Fenster")
	assert_eq(int(gold["punkte"]), 20)
	assert_true(bool(gold["fehlerfrei"]))
	assert_eq(
		McGoobyStationFritteuse.simulate_autoplay(GOLD_SEED, aktionen, bal),
		gold,
		"Bot-Zertifizierung reproduzierbar (Doc §10.4)"
	)
	# Skill 0: JEDER Korb wird dunkel — halber Punkt-Regen, ehrlich unperfekt.
	var patzer := McGoobyStationFritteuse.simulate_autoplay(GOLD_SEED, aktionen, {"bot_skill": 0.0})
	assert_eq(int(patzer["dunkel"]), 2)
	assert_eq(int(patzer["punkte"]), 10, "2 × 5 Knusper-Deluxe")
	assert_false(bool(patzer["fehlerfrei"]))


## ------------------------------------------------------- Shake-Bar (b)


func test_shake_logik_zustaende_und_wertung() -> void:
	McGoobyKatalog.reset_cache()
	assert_eq(
		McGoobyStationShake.aktionen_von(McGoobyKatalog.rezept("rosa_flausch")),
		["mixen", "flausch_krone"] as Array[String],
		"Rosa Flausch: 2 Kreis-Runden"
	)
	assert_true(
		McGoobyStationShake.aktionen_von(McGoobyKatalog.rezept("pommes_klassik")).is_empty(),
		"Pommes brauchen keine Shake-Bar"
	)
	# Zustands-Grenzen am Pack-Timing (gar 3,5 + Fenster 1,6).
	var timing := McGoobyKatalog.timing("shake")
	assert_eq(McGoobyStationShake.zustand(3.49, timing), "fluessig")
	assert_eq(McGoobyStationShake.zustand(3.5, timing), "krone", "Fenster-Beginn inklusiv")
	assert_eq(McGoobyStationShake.zustand(5.09, timing), "krone")
	assert_eq(McGoobyStationShake.zustand(5.1, timing), "schaum", "Fenster-Ende exklusiv")
	var bal := _bal()
	var frueh := McGoobyStationShake.bewerte_stopp(1.0, timing, bal)
	assert_eq(str(frueh["wertung"]), "fluessig", "zu früh gestoppt = einfach weiterkreisen")
	assert_eq(int(frueh["punkte"]), 0, "keine Strafe")
	assert_eq(int(McGoobyStationShake.bewerte_stopp(4.0, timing, bal)["punkte"]), 10, "Krone!")
	var spaet := McGoobyStationShake.bewerte_stopp(6.0, timing, bal)
	assert_eq(str(spaet["wertung"]), "schaum", "überdreht = Schaum + Wischtuch-Gag")
	assert_eq(int(spaet["punkte"]), 5, "halbe Punkte — nie verloren")
	assert_eq(str(McGoobyStationShake.bewerte_ueberdreht(bal)["wertung"]), "schaum")
	var eigene := {"shake_punkte_perfekt": 14, "shake_punkte_schaum": 4}
	assert_eq(int(McGoobyStationShake.bewerte_stopp(4.0, timing, eigene)["punkte"]), 14)
	assert_eq(int(McGoobyStationShake.bewerte_ueberdreht(eigene)["punkte"]), 4)


func test_shake_autoplay_golden() -> void:
	var bal := _bal()
	var aktionen := McGoobyStationShake.aktionen_von(McGoobyKatalog.rezept("rosa_flausch"))
	var gold := McGoobyStationShake.simulate_autoplay(GOLD_SEED, aktionen, bal)
	assert_eq(int(gold["aktionen"]), 2)
	assert_eq(int(gold["schaum"]), 0, "Seed 4711: beide Kronen stehen")
	assert_eq(int(gold["punkte"]), 20)
	assert_true(bool(gold["fehlerfrei"]))
	assert_eq(
		McGoobyStationShake.simulate_autoplay(GOLD_SEED, aktionen, bal),
		gold,
		"Bot-Zertifizierung reproduzierbar (Doc §10.4)"
	)
	var patzer := McGoobyStationShake.simulate_autoplay(GOLD_SEED, aktionen, {"bot_skill": 0.0})
	assert_eq(int(patzer["schaum"]), 2)
	assert_eq(int(patzer["punkte"]), 10, "2 × 5 Schaum")
	assert_false(bool(patzer["fehlerfrei"]))


## ------------------------------------------- Alle 10 Rezepte bestellbar (c)


func test_bestell_folge_faire_mischung() -> void:
	McGoobyKatalog.reset_cache()
	var menu := McGoobyKatalog.rezepte()
	var bal := _bal()
	assert_eq(menu.size(), 10, "volles Start-Menü")
	for s in range(1, 41):
		var folge := McGoobySchichtLogic.bestell_folge(s, menu, bal)
		assert_true(folge.size() >= 2 and folge.size() <= 4, "2–4 Bestellungen (Seed %d)" % s)
		var erstes := McGoobyKatalog.rezept(str(folge[0]["rezept_id"]))
		assert_true(
			McGoobySchichtLogic.phasen_von(erstes).has("grill"),
			"Bestellung 1 ist IMMER ein Signature-Burger (Seed %d)" % s
		)
		assert_true(int(folge[0]["patties"]) >= 1, "Burger bringt Grill-Runden mit")
		var zweites := McGoobyKatalog.rezept(str(folge[1]["rezept_id"]))
		assert_false(
			McGoobySchichtLogic.phasen_von(zweites).has("grill"),
			"Bestellung 2 kommt IMMER vom neuen Tresen (Seed %d)" % s
		)
		assert_eq(int(folge[1]["patties"]), 0, "Tresen-Rezepte haben 0 Grill-Schritte")
	# Alle 10 Rezepte sind über die Tages-Seeds wirklich bestellbar.
	var gesehen: Dictionary = {}
	for s in range(1, 301):
		for bestellung: Dictionary in McGoobySchichtLogic.bestell_folge(s, menu, bal):
			gesehen[str(bestellung["rezept_id"])] = true
	assert_eq(gesehen.size(), 10, "JEDES Rezept taucht im Kundenstrom auf")
	# Grill-only-Menü (Welle-A/B-Goldens): Folge bleibt EXAKT die alte.
	var grill_folge := McGoobySchichtLogic.bestell_folge(
		GOLD_SEED, McGoobyKatalog.rezepte_fuer("grill"), bal
	)
	assert_eq(str(grill_folge[0]["rezept_id"]), "garten_gooby")
	assert_eq(str(grill_folge[1]["rezept_id"]), "gooby_mac", "alter RNG-Verbrauch unangetastet")


func test_schicht_autoplay_volles_menu_goldens() -> void:
	McGoobyKatalog.reset_cache()
	var menu := McGoobyKatalog.rezepte()
	var bal := _bal()
	# Seed 4711: garten_gooby + pommes_klassik — Fritteuse zählt im Bot mit.
	var gold := McGoobySchichtLogic.simulate_autoplay(GOLD_SEED, menu, bal)
	assert_eq(int(gold["bestellungen"]), 2)
	assert_eq(int(gold["perfekt"]), 3, "1 Patty + 2 Körbe perfekt")
	assert_eq(int(gold["fehlgriffe"]), 1, "1 Belegen-Fehlgriff")
	assert_eq(int(gold["dunkel"]), 0)
	assert_eq(int(gold["schaum"]), 0)
	assert_eq(int(gold["punkte"]), 83, "Goldwert volles Menü")
	assert_eq(int(gold["trinkgeld"]), 2)
	assert_eq(int(gold["muenzen"]), 22)
	assert_eq(
		McGoobySchichtLogic.simulate_autoplay(GOLD_SEED, menu, bal),
		gold,
		"Bot-Zertifizierung reproduzierbar (Doc §10.4)"
	)
	# Seed 134: ALLE Fehler-Zähler > 0 — jede Station meldet ehrlich.
	var bunt := McGoobySchichtLogic.simulate_autoplay(BUNT_SEED, menu, bal)
	assert_eq(int(bunt["bestellungen"]), 4)
	assert_eq(int(bunt["roestaroma"]), 1, "1 Röstaroma-Patty")
	assert_eq(int(bunt["fehlgriffe"]), 1, "1 Belegen-Fehlgriff")
	assert_eq(int(bunt["dunkel"]), 1, "1 Knusper-Deluxe-Korb")
	assert_eq(int(bunt["schaum"]), 1, "1 übergeschäumter Shake")
	assert_eq(int(bunt["perfekt"]), 6)
	assert_eq(int(bunt["punkte"]), 168)
	assert_eq(int(bunt["muenzen"]), 32)


func test_phasen_plan_der_rezepte() -> void:
	McGoobyKatalog.reset_cache()
	assert_eq(
		McGoobySchichtLogic.phasen_von(McGoobyKatalog.rezept("gooby_mac")),
		["grill", "belegen"] as Array[String]
	)
	assert_eq(
		McGoobySchichtLogic.phasen_von(McGoobyKatalog.rezept("pommes_klassik")),
		["fritteuse"] as Array[String]
	)
	assert_eq(
		McGoobySchichtLogic.phasen_von(McGoobyKatalog.rezept("rosa_flausch")),
		["shake"] as Array[String]
	)
	assert_eq(
		McGoobySchichtLogic.grill_schritte(McGoobyKatalog.rezept("rosa_flausch")),
		0,
		"Rezepte ohne Grill-Station liefern 0 Pattys (Welle C)"
	)


## ------------------------------------------------------ Laden-Rang (d)


func test_fortschritt_slice_und_sterne_leiter() -> void:
	McGoobyKatalog.reset_cache()
	# Slice-Erweiterung: perfekt-Zähler heilt sich in Welle-B-Saves selbst.
	var geheilt := McGoobyState.normalize_slice(
		{"gekauft": true, "schichten": {"gespielt": 3, "bestwert": 50}}
	)
	assert_eq(int((geheilt["schichten"] as Dictionary)["perfekt"]), 0, "Alt-Save: perfekt = 0")
	assert_eq(int((geheilt["schichten"] as Dictionary)["gespielt"]), 3, "Bestand VERBATIM")
	# schicht_verbuchen zählt fehlerfreie Schichten für den Rang.
	var gs := _gs(14, 0)
	McGoobyState.schicht_verbuchen(gs, 90, true)
	McGoobyState.schicht_verbuchen(gs, 40, false)
	assert_eq(int(gs.get_value("mcgooby.schichten.gespielt", 0)), 2)
	assert_eq(int(gs.get_value("mcgooby.schichten.bestwert", 0)), 90, "Bestwert nie runter")
	assert_eq(int(gs.get_value("mcgooby.schichten.perfekt", 0)), 1, "1 fehlerfreie Schicht")
	# Leiter aus dem Pack: 5 aufsteigende Stufen.
	var raenge := McGoobyKatalog.raenge()
	assert_eq(raenge.size(), 5, "5-Sterne-Leiter im Pack")
	for i in raenge.size():
		assert_eq(int((raenge[i] as Dictionary)["stern"]), i + 1, "Stufen aufsteigend")
	# Sterne: 2 Schichten + Bestwert 90 + 1 perfekt → Stern 1 (Stufe 2 will 5).
	assert_eq(McGoobyFortschritt.sterne(gs), 1)
	assert_eq(McGoobyFortschritt.sterne_band(1), "★☆☆☆☆")
	assert_eq(McGoobyFortschritt.sterne_band(5), "★★★★★")
	# Ehrliche Rest-Ziele: Stern 2 braucht noch 3 Schichten (Bestwert sitzt).
	var naechster := McGoobyFortschritt.naechster_rang(gs)
	assert_eq(int(naechster["stern"]), 2)
	assert_eq(int(naechster["fehlt_schichten"]), 3)
	assert_eq(int(naechster["fehlt_bestwert"]), 0, "90 ≥ 80: Ziel schon erfüllt")
	var ziel := McGoobyFortschritt.ziel_zeile(gs)
	assert_true(ziel.contains("3"), "Ziel-Zeile nennt die fehlenden Schichten")
	assert_false(ziel.contains("{"), "keine offenen Platzhalter")
	# Frischer Save: 0 Sterne, nächstes Ziel ist Stern 1 (1 Schicht).
	var frisch := _gs(1, 0)
	assert_eq(McGoobyFortschritt.sterne(frisch), 0)
	assert_eq(int(McGoobyFortschritt.naechster_rang(frisch)["fehlt_schichten"]), 1)
	# Volle Leiter: 5 Sterne + Glanz-Satz statt Ziel.
	var voll := _gs(14, 0)
	voll.set_value("mcgooby.schichten.gespielt", 40)
	voll.set_value("mcgooby.schichten.bestwert", 200)
	voll.set_value("mcgooby.schichten.perfekt", 3)
	assert_eq(McGoobyFortschritt.sterne(voll), 5)
	assert_true(McGoobyFortschritt.naechster_rang(voll).is_empty())
	assert_eq(McGoobyFortschritt.ziel_zeile(voll), I18nService.t("dlc_mcgooby.fortschritt.voll"))


func test_hub_detail_zeigt_laden_rang() -> void:
	DlcKatalog.reset_cache()
	McGoobyKatalog.reset_cache()
	# Mit gespielten Schichten: Rang-Zeile + ehrliches Ziel im Detail-Sheet.
	var gs := _gs(14, 0)
	gs.set_value("mcgooby.schichten.gespielt", 3)
	gs.set_value("mcgooby.schichten.bestwert", 90)
	gs.set_value("mcgooby.schichten.perfekt", 1)
	var screen := DlcScreen.new()
	screen.gs_override = gs
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(3)
	var sheet := screen.oeffne_detail("mcgooby")
	assert_true(sheet != null, "Detail-Sheet öffnet")
	await wait_frames(2)
	var rang: Label = sheet.find_child("McGoobyRang", true, false)
	assert_true(rang != null, "Rang-Zeile im Detail-Sheet")
	assert_eq(rang.text, McGoobyFortschritt.rang_zeile(gs), "dieselbe Wahrheit wie der Slice")
	assert_true(rang.text.contains("★☆☆☆☆"), "3 Schichten/Bestwert 90 = 1 Stern")
	var ziel: Label = sheet.find_child("McGoobyRangZiel", true, false)
	assert_true(ziel != null and ziel.text.contains("2"), "Ziel: noch 2 Schichten bis Stern 2")
	sheet.close()
	sheet.queue_free()
	await wait_frames(2)
	screen.queue_free()
	await wait_frames(1)
	# Frischer Save (0 Schichten): KEINE Null-Sterne-Deko — ehrlich leer.
	var screen2 := DlcScreen.new()
	screen2.gs_override = _gs(14, 0)
	screen2.auto_navigate = false
	tree.root.add_child(screen2)
	await wait_frames(3)
	var sheet2 := screen2.oeffne_detail("mcgooby")
	await wait_frames(2)
	assert_true(
		sheet2.find_child("McGoobyRang", true, false) == null,
		"vor der ersten Schicht keine Rang-Zeile"
	)
	sheet2.close()
	sheet2.queue_free()
	await wait_frames(2)
	screen2.queue_free()
	await wait_frames(1)


## ------------------------------------------------------ Szene Welle C


## EINE Timing-Runde der AKTIVEN Station perfekt spielen (Fenster-Mitte
## pinnen + Knopf-Signal — deterministisch, kein Echtzeit-Fenster).
func _runde_perfekt(szene: McGoobySchichtScene) -> void:
	var timing := szene.timing_aktuell()
	var mitte := float(timing["gar_sec"]) + float(timing["fenster_sec"]) * 0.5
	szene.patty_zeit_setzen(mitte)
	szene.patty_knopf().pressed.emit()


## Zutaten-Knopf der Belegen-Leiste per id drücken.
func _druecke_zutat(szene: McGoobySchichtScene, zutat_id: String) -> void:
	for knopf in szene.zutaten_knoepfe():
		if String(knopf.name) == "Zutat_" + zutat_id:
			knopf.pressed.emit()
			return


## Bestellung 1 (garten_gooby: Grill + 5 Zutaten) fehlerfrei durchspielen.
func _spiele_garten_gooby(szene: McGoobySchichtScene) -> void:
	assert_eq(str(szene.bestellung_aktuell().get("rezept_id", "")), "garten_gooby")
	_runde_perfekt(szene)
	for zutat_id: String in ["broetchen", "kuerbis_patty", "tomate", "salat", "broetchen"]:
		_druecke_zutat(szene, zutat_id)


func test_szene_fritteuse_dritter_tab() -> void:
	McGoobyKatalog.reset_cache()
	var gs := _gs(1, 0)
	gs.set_value("mcgooby.introGesehen", true)
	var szene: McGoobySchichtScene = (load(SCHICHT_SZENE) as PackedScene).instantiate()
	szene.gs_override = gs
	szene.seed_override = GOLD_SEED
	szene.auto_navigate = false
	tree.root.add_child(szene)
	await wait_frames(3)
	assert_true(szene.ist_am_laufen(), "Testaufbau: Schicht läuft")
	# Vier Stations-Tabs in der Daumen-Zone (Welle C).
	for station_id: String in McGoobyKatalog.STATION_IDS:
		assert_true(
			szene.find_child("Tab_" + station_id, true, false) != null,
			"Tab %s existiert" % station_id
		)
	_spiele_garten_gooby(szene)
	await wait_frames(1)
	# Bestellung 2 (Seed 4711): Pommes Klassik — die Fritteuse übernimmt,
	# der Blick folgt der Arbeit (Tab wechselt automatisch mit).
	assert_eq(str(szene.bestellung_aktuell().get("rezept_id", "")), "pommes_klassik")
	assert_eq(szene.phase_aktuell(), McGoobySchichtScene.PHASE_FRITTEUSE)
	assert_eq(szene.station_aktiv(), McGoobySchichtScene.PHASE_FRITTEUSE, "Ansicht folgt")
	assert_eq(String(szene.patty_knopf().name), "KorbKnopf", "aktiver Knopf = Fritten-Korb")
	assert_almost(float(szene.timing_aktuell()["gar_sec"]), 5.0, 1e-6, "Fritteusen-Timing")
	assert_eq(szene.runde_aktion_aktuell(), "frittieren")
	var punkte_label: Label = szene.find_child("Punkte", true, false)
	var punkte_vor := punkte_label.text
	# Jonglage-Guard: der Grill-Patty-Knopf zählt in fremder Phase NIE.
	szene.stations_knopf("grill").pressed.emit()
	await wait_frames(1)
	assert_eq(szene.runde_aktion_aktuell(), "frittieren", "fremder Knopf ignoriert")
	assert_eq(punkte_label.text, punkte_vor, "keine Punkte durch fremden Knopf")
	# Zu früh gezogen: keine Strafe, der Korb taucht wieder ein.
	szene.patty_zeit_setzen(1.0)
	szene.patty_knopf().pressed.emit()
	await wait_frames(1)
	var callout: Label = szene.find_child("Callout", true, false)
	assert_eq(callout.text, I18nService.t("dlc_mcgooby.schicht.frit_blass"), "Blubber-Hinweis")
	assert_eq(szene.runde_aktion_aktuell(), "frittieren", "Runde läuft weiter")
	# Perfekt im goldenen Fenster → Runde 2 (Salz).
	_runde_perfekt(szene)
	await wait_frames(1)
	assert_eq(szene.runde_aktion_aktuell(), "salz", "nächste Halte-Runde")
	# Zu spät gezogen: Knusper-Deluxe (halbe Punkte) — danach ist die
	# 2-Bestellungen-Schicht vorbei und die Ende-Karte zeigt den Rang.
	var timing := szene.timing_aktuell()
	szene.patty_zeit_setzen(float(timing["gar_sec"]) + float(timing["fenster_sec"]) + 0.1)
	szene.patty_knopf().pressed.emit()
	await wait_frames(1)
	assert_true(szene.ist_ende_offen(), "Schicht-Ende nach Bestellung 2")
	var kasse := szene.schicht_ergebnis()
	assert_eq(int(kasse["punkte"]), 80, "50 Burger + 30 Fritteuse (10+5+15)")
	assert_eq(int(kasse["fehlerfreie"]), 1, "Knusper-Deluxe kostet die Fehlerfreiheit")
	var rang: Label = szene.find_child("Wert_rang", true, false)
	assert_true(rang != null, "Ende-Karte zeigt den Laden-Rang (Welle C)")
	assert_eq(rang.text, McGoobyFortschritt.sterne_band(1), "1 Schicht = 1 Stern")
	assert_true(szene.find_child("RangZiel", true, false) != null, "ehrliches Nächstes-Ziel")
	assert_eq(int(gs.get_value("mcgooby.schichten.gespielt", 0)), 1, "Schicht verbucht")
	assert_eq(int(gs.get_value("mcgooby.schichten.perfekt", 0)), 0, "nicht fehlerfrei")
	szene.queue_free()
	await wait_frames(1)


func test_szene_ende_rang_ueberlebt_zweite_schicht() -> void:
	# Playtest-Befund W19/C (flow_w19_mcgooby_vier_stationen): nach „Noch
	# eine Schicht“ befüllt _ende_fuellen die Karte NEU — mit queue_free
	# allein stand das alte RangZiel noch im Baum und Godot benannte das
	# neue um (@Label@…): der Rang war ab Schicht 2 nicht mehr findbar.
	McGoobyKatalog.reset_cache()
	var gs := _gs(14, 0)
	gs.set_value("mcgooby.introGesehen", true)
	gs.set_value("mcgooby.gekauft", true)
	var szene: McGoobySchichtScene = (load(SCHICHT_SZENE) as PackedScene).instantiate()
	szene.gs_override = gs
	szene.seed_override = GOLD_SEED
	szene.auto_navigate = false
	tree.root.add_child(szene)
	await wait_frames(3)
	for schicht in 2:
		var sicherheit := 0
		while szene.ist_am_laufen() and sicherheit < 80:
			sicherheit += 1
			if szene.phase_aktuell() == McGoobySchichtScene.PHASE_BELEGEN:
				_druecke_zutat(
					szene,
					McGoobyStationBelegen.naechste_zutat(
						szene.belegen_ticket(), szene.belegen_platziert()
					)
				)
			else:
				_runde_perfekt(szene)
			await wait_frames(1)
		assert_true(szene.ist_ende_offen(), "Schicht %d endet" % (schicht + 1))
		if schicht == 0:
			var nochmal: Button = szene.find_child("Nochmal", true, false)
			assert_true(nochmal != null and nochmal.visible, "gekauft: „Noch eine Schicht“")
			nochmal.pressed.emit()
			await wait_frames(2)
	var rang: Label = szene.find_child("Wert_rang", true, false)
	assert_true(rang != null, "Rang-Zeile nach Schicht 2 findbar")
	assert_true(rang != null and rang.text.contains("★"), "Sterne-Band gefüllt")
	assert_true(
		szene.find_child("RangZiel", true, false) != null, "RangZiel nach Schicht 2 findbar"
	)
	assert_eq(int(gs.get_value("mcgooby.schichten.gespielt", 0)), 2, "beide Schichten verbucht")
	szene.queue_free()
	await wait_frames(1)


func test_szene_shake_vierter_tab_halte_geste() -> void:
	McGoobyKatalog.reset_cache()
	var gs := _gs(1, 0)
	gs.set_value("mcgooby.introGesehen", true)
	var szene: McGoobySchichtScene = (load(SCHICHT_SZENE) as PackedScene).instantiate()
	szene.gs_override = gs
	szene.seed_override = SHAKE_SEED
	szene.auto_navigate = false
	tree.root.add_child(szene)
	await wait_frames(3)
	assert_true(szene.ist_am_laufen(), "Testaufbau: Schicht läuft")
	_spiele_garten_gooby(szene)
	await wait_frames(1)
	# Bestellung 2 (Seed 7): Schoko-Flausch an der Shake-Bar.
	assert_eq(str(szene.bestellung_aktuell().get("rezept_id", "")), "schoko_flausch")
	assert_eq(szene.phase_aktuell(), McGoobySchichtScene.PHASE_SHAKE)
	assert_eq(szene.station_aktiv(), McGoobySchichtScene.PHASE_SHAKE, "Ansicht folgt")
	var becher := szene.patty_knopf()
	assert_eq(String(becher.name), "BecherKnopf", "aktiver Knopf = Shake-Becher")
	assert_eq(szene.runde_aktion_aktuell(), "mixen")
	# Halte-Geste: die Rühr-Zeit läuft NUR, solange der Becher gehalten wird.
	await wait_frames(3)
	assert_almost(float(szene.get("_patty_zeit")), 0.0, 1e-6, "ohne Halten rührt sich nichts")
	becher.button_down.emit()
	await wait_frames(3)
	var geruehrt := float(szene.get("_patty_zeit"))
	assert_true(geruehrt > 0.0, "Halten = kreisen, die Zeit läuft")
	becher.button_up.emit()
	await wait_frames(2)
	assert_almost(float(szene.get("_patty_zeit")), geruehrt, 1e-6, "Loslassen friert die Zeit")
	# Im goldenen Fenster stoppen: „Perfekt!“ → Runde 2 (Raspel-Regen).
	_runde_perfekt(szene)
	await wait_frames(1)
	assert_eq(szene.runde_aktion_aktuell(), "raspel_regen")
	# Überdrehen schäumt NUR beim aktiven Weiterrühren über: jenseits des
	# Nachlaufs passiert ohne Halten nichts …
	var timing := szene.timing_aktuell()
	var ende := (
		float(timing["gar_sec"]) + float(timing["fenster_sec"]) + float(timing["nachlauf_sec"])
	)
	szene.patty_zeit_setzen(ende + 0.1)
	await wait_frames(3)
	assert_eq(szene.runde_aktion_aktuell(), "raspel_regen", "ohne Rühren kein Überschäumen")
	# … erst das Weiterrühren kippt den Shake in den Schaum (halbe Punkte).
	becher.button_down.emit()
	await wait_frames(2)
	var callout: Label = szene.find_child("Callout", true, false)
	assert_eq(callout.text, I18nService.t("dlc_mcgooby.schicht.schaum"), "Wischtuch-Gag")
	# Danach ruft Bestellung 3 (Käse-Knusperle) wieder am Grill.
	assert_eq(str(szene.bestellung_aktuell().get("rezept_id", "")), "kaese_knusperle")
	assert_eq(szene.phase_aktuell(), McGoobySchichtScene.PHASE_GRILL, "zurück an den Grill")
	assert_eq(szene.station_aktiv(), McGoobySchichtScene.PHASE_GRILL, "Tab folgt zurück")
	szene.queue_free()
	await wait_frames(1)

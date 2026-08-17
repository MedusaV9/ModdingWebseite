extends TestCase
## W20 MCGOOBY-RANG — Wächter für den Rang-Aufstiegs-Moment + Stations-Deko
## (ROADMAP-W20 Top-10 #1):
## - Save-Latch `mcgooby.schichten.rangGefeiert`: Default, Self-Heal
##   (Junk/Clamp), gültige Werte VERBATIM.
## - aufstieg_pruefen: feuert genau EINMAL pro erreichter Stufe, kein Beat
##   ohne Aufstieg, Alt-Saves (Rang ohne Latch) werden STILL nachgezogen,
##   Latch überlebt den Reload (normalize_slice-Roundtrip).
## - Szene: RangFeier-Beat GENAU auf der Aufstiegs-Ende-Karte (Schicht 1 →
##   Stern 1), räumt sich selbst auf, KEIN Beat auf der Karte danach.
## - Stations-Deko (McGoobySchichtDeko): alle 4 Stationen tragen ihr
##   Detail, Sichtbarkeit folgt dem Tab, nur Grill/Fritteuse animieren.

const SCHICHT_SZENE := "res://scripts/dlc/mcgooby/schicht_scene.tscn"
const GOLD_SEED := 4711


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


func _gs_gekauft() -> FakeGameState:
	var gs := FakeGameState.new()
	gs.set_value("progression.level", 14)
	gs.set_value("mcgooby.introGesehen", true)
	gs.set_value("mcgooby.gekauft", true)
	return gs


## ------------------------------------------------------- Latch im Slice


func test_slice_latch_default_und_selfheal() -> void:
	var frisch: Dictionary = McGoobyState.default_slice()["schichten"]
	assert_eq(int(frisch["rangGefeiert"]), 0, "Default: noch nichts gefeiert")
	# Self-Heal: Junk → 0, über der Leiter → MAX, negativ → 0.
	var kaputt := McGoobyState.normalize_slice({"schichten": {"rangGefeiert": "drei"}})
	assert_eq(int(kaputt["schichten"]["rangGefeiert"]), 0, "Junk heilt zu 0")
	var hoch := McGoobyState.normalize_slice({"schichten": {"rangGefeiert": 99}})
	assert_eq(int(hoch["schichten"]["rangGefeiert"]), McGoobyFortschritt.MAX_STERNE, "Clamp auf 5")
	var negativ := McGoobyState.normalize_slice({"schichten": {"rangGefeiert": -2}})
	assert_eq(int(negativ["schichten"]["rangGefeiert"]), 0, "negativ heilt zu 0")
	var gueltig := McGoobyState.normalize_slice({"schichten": {"rangGefeiert": 3}})
	assert_eq(int(gueltig["schichten"]["rangGefeiert"]), 3, "gültiger Latch VERBATIM")


func test_aufstieg_feuert_genau_einmal_pro_stufe() -> void:
	McGoobyKatalog.reset_cache()
	var gs := _gs_gekauft()
	assert_eq(McGoobyFortschritt.sterne(gs), 0, "frischer Laden: 0 Sterne")
	# Schicht 1: Stern 1 (Leiter: 1 Schicht) → Beat feuert, Latch = 1.
	var vorher := McGoobyFortschritt.sterne(gs)
	McGoobyState.schicht_verbuchen(gs, 100)
	var beat := McGoobyFortschritt.aufstieg_pruefen(gs, vorher)
	assert_true(bool(beat["feiern"]), "Aufstieg auf Stern 1 feiert")
	assert_eq(int(beat["stern"]), 1, "Beat trägt den neuen Rang")
	assert_eq(int(gs.get_value("mcgooby.schichten.rangGefeiert", 0)), 1, "Latch = 1")
	# Schichten 2–4: Rang bleibt 1 (Stern 2 braucht 5 Schichten) → NIE Beat.
	for i in 3:
		vorher = McGoobyFortschritt.sterne(gs)
		McGoobyState.schicht_verbuchen(gs, 100)
		beat = McGoobyFortschritt.aufstieg_pruefen(gs, vorher)
		assert_true(not bool(beat["feiern"]), "kein Beat ohne Aufstieg (Schicht %d)" % (i + 2))
	# Schicht 5: Stern 2 (5 Schichten + Bestwert 80) → genau EIN Beat.
	vorher = McGoobyFortschritt.sterne(gs)
	McGoobyState.schicht_verbuchen(gs, 100)
	beat = McGoobyFortschritt.aufstieg_pruefen(gs, vorher)
	assert_true(bool(beat["feiern"]), "Aufstieg auf Stern 2 feiert")
	assert_eq(int(beat["stern"]), 2, "Stern 2 erreicht")
	# Doppel-Prüfung derselben Stufe (z. B. erneutes Karten-Füllen): still.
	assert_true(
		not bool(McGoobyFortschritt.aufstieg_pruefen(gs, 2)["feiern"]),
		"dieselbe Stufe feiert nie zweimal"
	)


func test_kein_nachhol_beat_fuer_alt_saves() -> void:
	McGoobyKatalog.reset_cache()
	# Alt-Save (vor W20): Rang 2 längst erreicht, aber kein Latch im Slice.
	var gs := _gs_gekauft()
	gs.set_value("mcgooby.schichten.gespielt", 5)
	gs.set_value("mcgooby.schichten.bestwert", 100)
	gs.set_value("mcgooby.schichten.perfekt", 0)
	assert_eq(McGoobyFortschritt.sterne(gs), 2, "Alt-Save steht auf Rang 2")
	# Nächste Schicht OHNE Aufstieg: kein Nachhol-Konfetti, Latch zieht nach.
	var vorher := McGoobyFortschritt.sterne(gs)
	McGoobyState.schicht_verbuchen(gs, 60)
	var beat := McGoobyFortschritt.aufstieg_pruefen(gs, vorher)
	assert_true(not bool(beat["feiern"]), "Alt-Erfolge feiern nicht nachträglich")
	assert_eq(int(gs.get_value("mcgooby.schichten.rangGefeiert", 0)), 2, "Latch nachgezogen")


func test_latch_ueberlebt_reload() -> void:
	McGoobyKatalog.reset_cache()
	var gs := _gs_gekauft()
	McGoobyState.schicht_verbuchen(gs, 100)
	assert_true(bool(McGoobyFortschritt.aufstieg_pruefen(gs, 0)["feiern"]), "Stern 1 gefeiert")
	# „Reload“: Slice durch den Save→Load-Pfad (normalize_slice) schicken.
	var geladen := McGoobyState.normalize_slice((gs.s["mcgooby"] as Dictionary).duplicate(true))
	var gs2 := _gs_gekauft()
	gs2.s["mcgooby"] = geladen
	assert_eq(int(gs2.get_value("mcgooby.schichten.rangGefeiert", 0)), 1, "Latch überlebt Reload")
	# Nach dem Reload: gleiche Stufe nochmal erreichen ist KEIN Beat.
	var vorher := McGoobyFortschritt.sterne(gs2)
	McGoobyState.schicht_verbuchen(gs2, 50)
	assert_true(
		not bool(McGoobyFortschritt.aufstieg_pruefen(gs2, vorher)["feiern"]),
		"kein zweiter Beat für Stern 1 nach Reload"
	)


## ------------------------------------------------------------------ Szene


## EINE Timing-Runde der AKTIVEN Station perfekt spielen (Fenster-Mitte
## pinnen + Knopf-Signal — deterministisch, kein Echtzeit-Fenster).
func _runde_perfekt(szene: McGoobySchichtScene) -> void:
	var timing := szene.timing_aktuell()
	var mitte := float(timing["gar_sec"]) + float(timing["fenster_sec"]) * 0.5
	szene.patty_zeit_setzen(mitte)
	szene.patty_knopf().pressed.emit()


## Laufende Schicht generisch bis zur Ende-Karte durchspielen (Muster
## test_w19_mcgooby_c: Belegen per naechste_zutat, Timing per Fenster-Mitte).
func _schicht_durchspielen(szene: McGoobySchichtScene) -> void:
	var sicherheit := 0
	while szene.ist_am_laufen() and sicherheit < 80:
		sicherheit += 1
		if szene.phase_aktuell() == McGoobySchichtScene.PHASE_BELEGEN:
			var zutat_id := McGoobyStationBelegen.naechste_zutat(
				szene.belegen_ticket(), szene.belegen_platziert()
			)
			for knopf in szene.zutaten_knoepfe():
				if String(knopf.name) == "Zutat_" + zutat_id:
					knopf.pressed.emit()
					break
		else:
			_runde_perfekt(szene)
		await wait_frames(1)
	assert_true(szene.ist_ende_offen(), "Schicht endet auf der Ende-Karte")


func _szene_bauen(gs: FakeGameState) -> McGoobySchichtScene:
	McGoobyKatalog.reset_cache()
	var szene: McGoobySchichtScene = (load(SCHICHT_SZENE) as PackedScene).instantiate()
	szene.gs_override = gs
	szene.seed_override = GOLD_SEED
	szene.auto_navigate = false
	tree.root.add_child(szene)
	return szene


func test_szene_rang_beat_erste_schicht_einmalig() -> void:
	var gs := _gs_gekauft()
	var szene := _szene_bauen(gs)
	await wait_frames(3)
	assert_true(szene.find_child("RangFeier", true, false) == null, "kein Beat vor dem Ende")
	# Schicht 1: Stern 1 → GENAU auf dieser Ende-Karte feiert der Beat.
	await _schicht_durchspielen(szene)
	await wait_frames(1)
	var feier: McGoobyRangFeier = szene.find_child("RangFeier", true, false)
	assert_true(feier != null, "Aufstiegs-Beat liegt über der Ende-Karte")
	assert_eq(int(gs.get_value("mcgooby.schichten.rangGefeiert", 0)), 1, "Latch = 1")
	var band: Label = feier.find_child("SterneBand", true, false)
	assert_eq(band.text, McGoobyFortschritt.sterne_band(1), "Band zeigt den neuen Stern")
	# Der Beat räumt sich selbst auf (DAUER_S) — Zeit direkt vorspulen.
	feier._process(McGoobyRangFeier.DAUER_S + 0.1)
	await wait_frames(2)
	assert_true(szene.find_child("RangFeier", true, false) == null, "Beat räumt sich auf")
	# Schicht 2: Rang bleibt 1 (Stern 2 braucht 5 Schichten) → KEIN Beat,
	# die Ende-Karte zeigt den Rang wie bisher.
	var nochmal: Button = szene.find_child("Nochmal", true, false)
	nochmal.pressed.emit()
	await wait_frames(2)
	await _schicht_durchspielen(szene)
	await wait_frames(1)
	assert_true(szene.find_child("RangFeier", true, false) == null, "kein Beat ohne Aufstieg")
	var rang: Label = szene.find_child("Wert_rang", true, false)
	assert_true(rang != null and rang.text.contains("★"), "Ende-Karte zeigt Rang wie bisher")
	szene.queue_free()
	await wait_frames(1)


func test_szene_stations_deko_smoke() -> void:
	var gs := _gs_gekauft()
	var szene := _szene_bauen(gs)
	await wait_frames(3)
	# Alle vier Stationen tragen ihr prozedurales Detail (W20, Teil b).
	for station_id: String in McGoobyKatalog.STATION_IDS:
		var deko: McGoobySchichtDeko = szene.find_child(
			station_id.capitalize() + "Deko", true, false
		)
		assert_true(deko != null, "Deko %s existiert" % station_id)
		assert_eq(deko.station_id, station_id, "Deko kennt ihre Station")
		assert_true(deko.custom_minimum_size.x > 0.0, "Deko %s hat Fläche" % station_id)
	# Sichtbarkeit folgt dem Stations-Tab (Deko wohnt in der Stations-Box).
	var grill_deko: McGoobySchichtDeko = szene.find_child("GrillDeko", true, false)
	var frit_deko: McGoobySchichtDeko = szene.find_child("FritteuseDeko", true, false)
	assert_true(grill_deko.is_visible_in_tree(), "Start: Grill-Deko sichtbar")
	assert_true(not frit_deko.is_visible_in_tree(), "Start: Fritteusen-Deko verdeckt")
	szene.wechsle_station("fritteuse")
	await wait_frames(1)
	assert_true(frit_deko.is_visible_in_tree(), "Tab-Wechsel zeigt Fritteusen-Deko")
	assert_true(not grill_deko.is_visible_in_tree(), "Grill-Deko weicht dem Tab")
	# Nur Grill/Fritteuse animieren (Flammen/Blasen) — Belegen bleibt statisch.
	var frit_zeit := frit_deko.zeit
	frit_deko._process(0.5)
	assert_true(frit_deko.zeit > frit_zeit, "Fritteusen-Blasen leben (sichtbar + Motion)")
	szene.wechsle_station("belegen")
	await wait_frames(1)
	var beleg_deko: McGoobySchichtDeko = szene.find_child("BelegenDeko", true, false)
	beleg_deko._process(0.5)
	assert_almost(beleg_deko.zeit, 0.0, 1e-6, "Belegen-Podest ist bewusst statisch")
	szene.queue_free()
	await wait_frames(1)

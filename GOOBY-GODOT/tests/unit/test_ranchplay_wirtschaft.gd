extends TestCase
## RANCH-2 — Ranch-Wirtschaft (RanchWirtschaft): Balance-Daten + Registry-
## Override, Gear-Katalog/-Kauf/-Anlegen, Ausbau-Stufen (Vorstufe, Doppelkauf),
## Heu kaufen/ernten, Äpfel pflücken, Futter-Entnahme und die Effekt-Multis.
## Alles PURE: Eingaben bleiben unberührt, Fehlerfälle ändern NICHTS.

const Wirtschaft := preload("res://scripts/ranch/data/ranch_wirtschaft.gd")
const Slices := preload("res://scripts/ranch/data/ranch_play_slices.gd")


class FakeRegistry:
	extends RefCounted

	var balance: Dictionary = {}

	func get_balance(_key: String, default_value: Variant = null) -> Variant:
		return balance if not balance.is_empty() else default_value


func _bal() -> Dictionary:
	return Wirtschaft.read_json(Wirtschaft.BALANCE_PATH)


func test_balance_json_ist_vollstaendig() -> void:
	var bal := _bal()
	assert_true(bal.get("preise") is Dictionary, "preise fehlen")
	assert_true(bal.get("ertraege") is Dictionary, "ertraege fehlen")
	assert_eq(Wirtschaft.gear_farben(bal).size(), 5, "5 Gear-Farben")
	assert_true((bal.get("boxen_kapazitaet") as Array).size() == 3, "3 Boxen-Stufen")
	for id: String in Wirtschaft.AUSBAU_IDS:
		assert_true(Wirtschaft.ausbau_preis(bal, id) > 0, "Ausbau %s braucht Preis" % id)


func test_registry_override_merged_tief() -> void:
	var registry := FakeRegistry.new()
	registry.balance = {"preise": {"heu_kauf": 99}}
	var bal := Wirtschaft.load_balance(registry)
	assert_eq(int(bal["preise"]["heu_kauf"]), 99, "Override greift")
	assert_eq(int(bal["preise"]["gear"]["sattel"]), 120, "Nachbar-Preise überleben den Merge")
	assert_eq(Wirtschaft.gear_farben(bal).size(), 5, "unberührte Zweige bleiben")


func test_gear_katalog_und_gold_multiplikator() -> void:
	var bal := _bal()
	assert_eq(Wirtschaft.gear_katalog(bal).size(), 15, "3 Slots × 5 Farben")
	assert_eq(Wirtschaft.gear_preis(bal, "sattel", "rot"), 120)
	assert_eq(Wirtschaft.gear_preis(bal, "sattel", "gold"), 240, "gold = 2×")
	assert_eq(Wirtschaft.gear_preis(bal, "halfter", "blau"), 60)


func test_gear_kaufen_bucht_und_blockt_doppelkauf() -> void:
	var bal := _bal()
	var w := Slices.default_wirtschaft()
	var res := Wirtschaft.gear_kaufen(w, 200, "sattel_rot", bal)
	assert_true(res["ok"])
	assert_eq(res["coins"], 80, "exakt der Preis wird abgebucht")
	assert_true((res["wirtschaft"]["gear"]["owned"] as Array).has("sattel_rot"))
	assert_eq((w["gear"]["owned"] as Array).size(), 0, "Eingabe bleibt unberührt (pure)")
	var doppelt := Wirtschaft.gear_kaufen(res["wirtschaft"], 500, "sattel_rot", bal)
	assert_false(doppelt["ok"])
	assert_eq(doppelt["fehler"], "schonGekauft")
	assert_eq(doppelt["coins"], 500, "Fehlerfall bucht nichts ab")


func test_gear_kaufen_fehlerfaelle() -> void:
	var bal := _bal()
	var w := Slices.default_wirtschaft()
	assert_eq(Wirtschaft.gear_kaufen(w, 999, "krone_rot", bal)["fehler"], "unbekannt")
	assert_eq(Wirtschaft.gear_kaufen(w, 999, "sattel_neon", bal)["fehler"], "unbekannt")
	var pleite := Wirtschaft.gear_kaufen(w, 119, "sattel_rot", bal)
	assert_eq(pleite["fehler"], "zuTeuer")
	assert_eq(pleite["coins"], 119, "Münzen unangetastet")


func test_gear_anlegen_braucht_besitz() -> void:
	var w := Slices.default_wirtschaft()
	assert_eq(Wirtschaft.gear_anlegen(w, "p1", "sattel", "rot")["fehler"], "nichtGekauft")
	(w["gear"]["owned"] as Array).append("sattel_rot")
	var res := Wirtschaft.gear_anlegen(w, "p1", "sattel", "rot")
	assert_true(res["ok"])
	assert_eq(res["wirtschaft"]["gear"]["equippedByHorse"]["p1"]["sattel"], "rot")
	var ab := Wirtschaft.gear_anlegen(res["wirtschaft"], "p1", "sattel", null)
	assert_true(ab["ok"], "ablegen geht immer")
	assert_eq(ab["wirtschaft"]["gear"]["equippedByHorse"]["p1"]["sattel"], null)


func test_ausbau_boxen_brauchen_vorstufe() -> void:
	var bal := _bal()
	var w := Slices.default_wirtschaft()
	assert_eq(Wirtschaft.ausbau_kaufen(w, 9999, "boxen3", bal)["fehler"], "vorstufeFehlt")
	var s2 := Wirtschaft.ausbau_kaufen(w, 9999, "boxen2", bal)
	assert_true(s2["ok"])
	assert_eq(int(s2["wirtschaft"]["ausbau"]["boxen"]), 2)
	assert_eq(s2["coins"], 9999 - 400)
	var nochmal := Wirtschaft.ausbau_kaufen(s2["wirtschaft"], 9999, "boxen2", bal)
	assert_eq(nochmal["fehler"], "schonGekauft")
	var s3 := Wirtschaft.ausbau_kaufen(s2["wirtschaft"], 9999, "boxen3", bal)
	assert_true(s3["ok"])
	assert_eq(int(s3["wirtschaft"]["ausbau"]["boxen"]), 3)


func test_ausbau_kapazitaet_und_flags() -> void:
	var bal := _bal()
	var w := Slices.default_wirtschaft()
	assert_eq(Wirtschaft.boxen_kapazitaet(w, bal), 2, "Stufe 1 = 2 Pferde")
	w["ausbau"]["boxen"] = 3
	assert_eq(Wirtschaft.boxen_kapazitaet(w, bal), 6)
	assert_false(Wirtschaft.ausbau_aktiv(w, "reitplatz"))
	var res := Wirtschaft.ausbau_kaufen(w, 9999, "reitplatz", bal)
	assert_true(Wirtschaft.ausbau_aktiv(res["wirtschaft"], "reitplatz"))
	assert_eq(
		Wirtschaft.ausbau_kaufen(res["wirtschaft"], 9999, "reitplatz", bal)["fehler"],
		"schonGekauft"
	)


func test_heu_kaufen_und_ernten() -> void:
	var bal := _bal()
	var w := Slices.default_wirtschaft()
	var kauf := Wirtschaft.heu_kaufen(w, 20, 2, bal)
	assert_true(kauf["ok"])
	assert_eq(kauf["coins"], 4, "2 Ballen à 8")
	assert_eq(int(kauf["wirtschaft"]["lager"]["heu"]), 6, "4 Start + 2 gekauft")
	assert_eq(Wirtschaft.heu_kaufen(w, 7, 1, bal)["fehler"], "zuTeuer")
	assert_eq(Wirtschaft.heu_kaufen(w, 999, 0, bal)["fehler"], "unbekannt")
	var ernte := Wirtschaft.heu_ernten(w, 1000, bal)
	assert_true(ernte["ok"])
	assert_eq(ernte["menge"], 3)
	assert_eq(int(ernte["wirtschaft"]["lager"]["heu"]), 7)
	var bereit := int(ernte["wirtschaft"]["felder"]["heuBereitAt"])
	assert_eq(bereit, 1000 + 360 * 60000, "Feld wächst 6 h nach")
	assert_eq(
		Wirtschaft.heu_ernten(ernte["wirtschaft"], bereit - 1, bal)["fehler"], "nochNichtReif"
	)
	assert_true(Wirtschaft.heu_ernten(ernte["wirtschaft"], bereit, bal)["ok"])


func test_apfel_pfluecken_pro_baum() -> void:
	var bal := _bal()
	var w := Slices.default_wirtschaft()
	var res := Wirtschaft.apfel_pfluecken(w, 1, 5000, bal)
	assert_true(res["ok"])
	assert_eq(res["menge"], 2)
	assert_eq(int(res["wirtschaft"]["lager"]["apfel"]), 4, "2 Start + 2 gepflückt")
	assert_eq(int(res["wirtschaft"]["felder"]["baeume"][1]), 5000 + 240 * 60000)
	assert_eq(int(res["wirtschaft"]["felder"]["baeume"][0]), 0, "Nachbar-Baum unberührt")
	assert_eq(
		Wirtschaft.apfel_pfluecken(res["wirtschaft"], 1, 5001, bal)["fehler"], "nochNichtReif"
	)
	assert_true(Wirtschaft.apfel_pfluecken(res["wirtschaft"], 0, 5001, bal)["ok"])
	assert_eq(Wirtschaft.apfel_pfluecken(w, 3, 5000, bal)["fehler"], "unbekannt")


func test_futter_nehmen_zehrt_das_lager() -> void:
	var w := Slices.default_wirtschaft()
	var res := Wirtschaft.futter_nehmen(w, "apfel")
	assert_true(res["ok"])
	assert_eq(int(res["wirtschaft"]["lager"]["apfel"]), 1)
	var letzter: Dictionary = Wirtschaft.futter_nehmen(res["wirtschaft"], "apfel")["wirtschaft"]
	assert_eq(Wirtschaft.futter_nehmen(letzter, "apfel")["fehler"], "lagerLeer")
	assert_eq(Wirtschaft.futter_nehmen(w, "karotte")["fehler"], "unbekannt")
	assert_true(Wirtschaft.karotte_verfuegbar({"carrot": 2}))
	assert_false(Wirtschaft.karotte_verfuegbar({"carrot": 0}))
	assert_false(Wirtschaft.karotte_verfuegbar({}))


func test_effekt_multiplikatoren() -> void:
	var bal := _bal()
	var w := Slices.default_wirtschaft()
	assert_almost(Wirtschaft.weide_sauberkeit_mult(w, bal), 1.0, 1e-6, "ohne Zaun neutral")
	assert_almost(Wirtschaft.parcours_coin_mult(w, bal), 1.0, 1e-6, "ohne Reitplatz neutral")
	w["ausbau"]["weidezaun"] = true
	w["ausbau"]["reitplatz"] = true
	assert_almost(Wirtschaft.weide_sauberkeit_mult(w, bal), 0.8)
	assert_almost(Wirtschaft.parcours_coin_mult(w, bal), 1.1)

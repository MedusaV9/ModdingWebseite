extends TestCase
## RW-5 — Turniertag-Orchestrierung: Endstand-Sortierung je Wertungsrichtung,
## Belohnungsformel (Klassenfaktor × Turniertag × RW-4-Tribüne), Verbuchung
## (Liga-Punkte, Aufstieg, Schleifen einmalig, Trophäen, Gold, Pferde-XP).

const Katalog := preload("res://scripts/ranch/comp/comp_katalog.gd")
const Liga := preload("res://scripts/ranch/comp/comp_liga.gd")
const Turnier := preload("res://scripts/ranch/comp/comp_turnier.gd")


class FakeGs:
	extends RefCounted

	var state: Dictionary = {"economy": {"coins": 100}}

	func get_value(path: String, default_value: Variant = null) -> Variant:
		var node: Variant = state
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return default_value
		return node

	func set_value(path: String, value: Variant) -> void:
		var parts := path.split(".")
		var node: Dictionary = state
		for i in parts.size() - 1:
			if not (node.get(parts[i]) is Dictionary):
				node[parts[i]] = {}
			node = node[parts[i]]
		node[parts[parts.size() - 1]] = value

	func update(mutator: Callable) -> void:
		mutator.call(state)


func _bal() -> Dictionary:
	return RanchWirtschaft.read_json(Katalog.BALANCE_PATH)


func test_endstand_sortierung() -> void:
	var bal := _bal()
	var bots := [{"id": "a", "wert": 900.0}, {"id": "b", "wert": 950.0}]
	var stand := Turnier.endstand(bal, "springen", bots, {"wert": 930.0})
	assert_eq(str((stand[0] as Dictionary)["id"]), "b", "Punkte: höher gewinnt")
	assert_eq(Turnier.spieler_platz(stand), 2)
	var zeit_bots := [{"id": "a", "wert": 24.0}, {"id": "b", "wert": 21.5}]
	var zeit_stand := Turnier.endstand(bal, "tonnen", zeit_bots, {"wert": 20.9})
	assert_eq(Turnier.spieler_platz(zeit_stand), 1, "Zeit: kleiner gewinnt")
	assert_true(bool((zeit_stand[0] as Dictionary)["ist_spieler"]))


func test_bots_simulieren_deterministisch() -> void:
	var bal := _bal()
	var a := Turnier.bots_simulieren(bal, "tonnen", "holz", 777)
	var b := Turnier.bots_simulieren(bal, "tonnen", "holz", 777)
	assert_eq(a.size(), Turnier.BOTS_JE_TURNIER)
	for i in a.size():
		assert_eq((a[i] as Dictionary)["id"], (b[i] as Dictionary)["id"], "Feld deterministisch")
		assert_almost(
			float((a[i] as Dictionary)["wert"]),
			float((b[i] as Dictionary)["wert"]),
			1e-9,
			"Läufe deterministisch"
		)
		assert_true(float((a[i] as Dictionary)["wert"]) > 0.0, "jeder Bot hat einen Lauf")


func test_belohnung_gold_multiplikatoren() -> void:
	var bal := _bal()
	var basis := Turnier.belohnung(bal, "tonnen", "holz", 1)
	assert_eq(int(basis["gold"]), 40, "Holz-Sieg = 40 G (Kap. 5.1)")
	assert_eq(int(basis["xp"]), 60)
	assert_eq(int(basis["liga_punkte"]), 10)
	assert_true(bool(basis["schleife"]))
	assert_eq(str(basis["trophaee"]), "pokal_holz")
	var turniertag := Turnier.belohnung(bal, "tonnen", "holz", 1, {"turniertag": true})
	assert_eq(int(turniertag["gold"]), 50, "Turniertag ×1,25")
	var tribuene := Turnier.belohnung(bal, "tonnen", "holz", 1, {"heim_gold_mult": 1.15})
	assert_eq(int(tribuene["gold"]), 46, "RW-4-Tribüne ×1,15")
	var alles := Turnier.belohnung(
		bal, "tonnen", "sternenklasse", 1, {"turniertag": true, "heim_gold_mult": 1.15}
	)
	assert_eq(int(alles["gold"]), 230, "40 × 4,0 × 1,25 × 1,15")
	var vierter := Turnier.belohnung(bal, "tonnen", "holz", 4)
	assert_false(bool(vierter["schleife"]), "Schleife nur bis Platz 3")
	assert_eq(str(vierter["trophaee"]), "")
	assert_eq(int(vierter["gold"]), 4, "Trostgold")


func test_verbuche_liga_und_gold() -> void:
	var gs := FakeGs.new()
	var bal := _bal()
	var lohn := Turnier.belohnung(bal, "tonnen", "holz", 1)
	var bericht := Turnier.verbuche(gs, bal, "tonnen", "holz", 1, lohn)
	assert_eq(int(gs.get_value("economy.coins")), 140, "Gold gebucht (100+40)")
	assert_eq(int(gs.get_value("ranch.comp.punkte.holz")), 10)
	assert_eq(int(gs.get_value("ranch.comp.teilnahmen")), 1)
	assert_eq(int(gs.get_value("ranch.comp.siege")), 1)
	assert_false(bool(bericht["aufgestiegen"]), "10 < 25 Aufstiegspunkte")
	assert_true(bool(bericht["schleife_neu"]))
	assert_true(bool(bericht["trophaee_neu"]))
	# Gleiche Schleife/Trophäe nochmal: nichts Neues, Punkte wachsen weiter.
	var bericht2 := Turnier.verbuche(gs, bal, "tonnen", "holz", 1, lohn)
	assert_eq(int(gs.get_value("ranch.comp.punkte.holz")), 20)
	assert_false(bool(bericht2["schleife_neu"]))
	assert_false(bool(bericht2["trophaee_neu"]))
	assert_eq((gs.get_value("ranch.comp.trophaeen") as Array).size(), 1)
	# Dritter Sieg reißt die 25-Punkte-Schwelle → Bronze.
	var bericht3 := Turnier.verbuche(gs, bal, "tonnen", "holz", 1, lohn)
	assert_true(bool(bericht3["aufgestiegen"]))
	assert_eq(str(bericht3["neue_klasse"]), "bronze")
	assert_eq(str(gs.get_value("ranch.comp.klasse")), "bronze")
	# Kein Abstieg: ein späterer Holz-Start ändert die Liga-Klasse nicht.
	Turnier.verbuche(gs, bal, "tonnen", "holz", 5, Turnier.belohnung(bal, "tonnen", "holz", 5))
	assert_eq(str(gs.get_value("ranch.comp.klasse")), "bronze")


func test_verbuche_bessere_schleife_zaehlt() -> void:
	var gs := FakeGs.new()
	var bal := _bal()
	Turnier.verbuche(gs, bal, "springen", "holz", 3, Turnier.belohnung(bal, "springen", "holz", 3))
	assert_eq(int(gs.get_value("ranch.comp.schleifen.springen_holz")), 3)
	var besser := Turnier.verbuche(
		gs, bal, "springen", "holz", 1, Turnier.belohnung(bal, "springen", "holz", 1)
	)
	assert_true(bool(besser["schleife_neu"]), "Platz 1 verbessert die Schleife")
	assert_eq(int(gs.get_value("ranch.comp.schleifen.springen_holz")), 1)


func test_xp_an_pferd_und_heim_gold_defensiv() -> void:
	var gs := FakeGs.new()
	gs.set_value("ranch.tiere.pferde.p1", {"id": "p1", "xp": 0.0, "level": 1})
	var buchung := Turnier.xp_an_pferd(gs, "p1", 60.0, "2026-07-26")
	assert_almost(float(buchung["gewinn"]), 60.0, 1e-6, "Wettbewerbs-XP ohne Tagesdeckel")
	assert_almost(float(gs.get_value("ranch.tiere.pferde.p1.xp")), 60.0, 1e-6)
	assert_true(Turnier.xp_an_pferd(gs, "unbekannt", 60.0, "2026-07-26").is_empty())
	assert_true(Turnier.xp_an_pferd(null, "p1", 60.0, "2026-07-26").is_empty())
	assert_almost(Turnier.heim_gold_mult(gs), 1.0, 1e-6, "ohne ranch.bau = 1,0 (defensiv)")
	assert_almost(Turnier.heim_gold_mult(null), 1.0, 1e-6)

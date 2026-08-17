extends TestCase
## RW-5 — Save-Slice `ranch.comp` (ADDITIV, kein Version-Bump): Self-Heal
## beim Lesen, Nachbar-Slices bleiben unangetastet, Geist nur bei
## Verbesserung, Arcade-Fortschritt (Sterne/Best/Cleared).

const State := preload("res://scripts/ranch/comp/comp_state.gd")


## GameState-Double: Dot-Pfade wie das Original (get_value/set_value/update).
class FakeGs:
	extends RefCounted

	var state: Dictionary = {}

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


func test_default_und_leerer_save() -> void:
	var gs := FakeGs.new()
	var comp := State.lese(gs)
	assert_eq(str(comp["klasse"]), "holz", "jeder fängt in Holz an")
	assert_eq(int((comp["punkte"] as Dictionary)["holz"]), 0)
	assert_eq((comp["punkte"] as Dictionary).size(), 5, "alle 5 Klassen vorhanden")
	assert_eq(int(comp["teilnahmen"]), 0)
	assert_true((comp["arcade"] as Dictionary).has("tonnen"))
	assert_true((comp["arcade"] as Dictionary).has("zeit"))
	var null_comp := State.lese(null)
	assert_eq(str(null_comp["klasse"]), "holz", "null-GameState crasht nicht")


func test_normalize_heilt_kaputte_daten() -> void:
	var kaputt := {
		"klasse": "diamant",
		"punkte": {"holz": -5, "bronze": "zehn"},
		"schleifen": {"springen_holz": 2, "quatsch": 9},
		"trophaeen": ["pokal_holz", "pokal_holz", 42],
		"teilnahmen": -3,
		"geister": {"tonnen": {"b64": ""}, "nix": {"b64": "abc"}, "gelaende": {"b64": "abc"}},
		"arcade": "kaputt",
		"fremd_von_anderem_agenten": {"bleibt": true},
	}
	var comp := State.normalize(kaputt)
	assert_eq(str(comp["klasse"]), "holz", "unbekannte Klasse → holz")
	assert_eq(int((comp["punkte"] as Dictionary)["holz"]), 0, "negative Punkte geklemmt")
	assert_eq(int((comp["punkte"] as Dictionary)["bronze"]), 0, "Text-Punkte repariert")
	assert_eq((comp["schleifen"] as Dictionary).size(), 1, "nur Plätze 1..3 überleben")
	assert_eq((comp["trophaeen"] as Array).size(), 1, "Duplikate/Nicht-Strings raus")
	assert_eq(int(comp["teilnahmen"]), 0)
	var geister: Dictionary = comp["geister"]
	assert_false(geister.has("tonnen"), "leerer Geist fliegt raus")
	assert_false(geister.has("nix"), "unbekannte Disziplin fliegt raus")
	assert_true(geister.has("gelaende"))
	assert_true((comp["arcade"] as Dictionary).has("tonnen"), "Arcade neu aufgebaut")
	assert_true(comp.has("fremd_von_anderem_agenten"), "fremde Schlüssel überleben")


func test_additiv_nachbarn_bleiben() -> void:
	var gs := FakeGs.new()
	gs.state = {"ranch": {"welt": {"entdeckt": ["hof"]}, "tiere": {"pferde": {}}}}
	var comp := State.lese(gs)
	comp["teilnahmen"] = 3
	State.schreibe(gs, comp)
	assert_eq(gs.get_value("ranch.welt.entdeckt") as Array, ["hof"], "RW-1-Slice unangetastet")
	assert_eq(int(gs.get_value("ranch.comp.teilnahmen")), 3)


func test_geist_nur_bei_verbesserung() -> void:
	var gs := FakeGs.new()
	var erster := {"b64": "AAAA", "wert": 25.0, "zeit_s": 25.0, "datum": "2026-07-26"}
	assert_true(State.geist_speichern(gs, "tonnen", erster, true), "erster Lauf zählt immer")
	var schlechter := {"b64": "BBBB", "wert": 27.0, "zeit_s": 27.0}
	assert_false(State.geist_speichern(gs, "tonnen", schlechter, true), "27 s > 25 s")
	assert_eq(str(State.geist(gs, "tonnen")["b64"]), "AAAA")
	var besser := {"b64": "CCCC", "wert": 22.5, "zeit_s": 22.5}
	assert_true(State.geist_speichern(gs, "tonnen", besser, true))
	assert_eq(str(State.geist(gs, "tonnen")["b64"]), "CCCC")
	# Punkte-Disziplin: größer = besser.
	assert_true(State.geist_speichern(gs, "springen", {"b64": "P1", "wert": 900.0}, false))
	assert_false(State.geist_speichern(gs, "springen", {"b64": "P2", "wert": 800.0}, false))
	assert_true(State.geist_speichern(gs, "springen", {"b64": "P3", "wert": 950.0}, false))
	assert_false(
		State.geist_speichern(gs, "tonnen", {"b64": "", "wert": 1.0}, true), "ohne b64 nix"
	)


func test_arcade_progress() -> void:
	var gs := FakeGs.new()
	assert_eq(State.arcade_max_unlocked(gs, "tonnen"), 1, "Level 1 immer offen")
	var win := State.arcade_win(gs, "tonnen", 1, 2, 240, true)
	assert_true(bool(win["first_clear"]))
	assert_eq(State.arcade_stars(gs, "tonnen", 1), 2)
	assert_eq(State.arcade_best(gs, "tonnen", 1), 240)
	assert_eq(State.arcade_max_unlocked(gs, "tonnen"), 2, "Sieg schaltet weiter")
	var schlechter := State.arcade_win(gs, "tonnen", 1, 1, 300, true)
	assert_false(bool(schlechter["first_clear"]))
	assert_false(bool(schlechter["new_best"]), "300 > 240 bei Zeit = schlechter")
	assert_eq(State.arcade_stars(gs, "tonnen", 1), 2, "Sterne fallen nie zurück")
	assert_eq(State.arcade_best(gs, "tonnen", 1), 240)
	var besser := State.arcade_win(gs, "tonnen", 1, 3, 200, true)
	assert_true(bool(besser["new_best"]))
	assert_eq(State.arcade_best(gs, "tonnen", 1), 200)
	# Punkte-Spiel (zeit nutzt hier score-groesser als Beispiel).
	State.arcade_win(gs, "zeit", 1, 1, 100)
	var mehr := State.arcade_win(gs, "zeit", 1, 1, 150)
	assert_true(bool(mehr["new_best"]), "150 > 100 bei Punkten = besser")

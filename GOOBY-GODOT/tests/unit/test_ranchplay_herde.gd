extends TestCase
## RANCH-2 — Schaf-Hüten (RanchHerdeLogic): Level-Daten (10 Level, Pferch im
## Feld, Steigerung), Pferch-/Tor-Geometrie, deterministischer Spawn + Schritt
## (kein RNG im step), Reiter-Klemmung, Score/Sterne und die Bot-Zertifizierung
## (jedes Level schaffbar, gleicher Seed = identisches Ergebnis).

const Logic := preload("res://scripts/minigames/games/ranch_herde/herde_logic.gd")


class FakeRegistry:
	extends RefCounted

	var balance: Dictionary = {}

	func get_balance(_key: String, default_value: Variant = null) -> Variant:
		return balance if not balance.is_empty() else default_value


func _level_liste() -> Array:
	return Logic.load_level(FakeRegistry.new())


func test_level_laden_und_validieren() -> void:
	var liste := _level_liste()
	assert_eq(liste.size(), Logic.LEVEL_ANZAHL, "10 Level")
	var fehler := Logic.validate_level(liste)
	assert_eq(fehler.size(), 0, "Level-Daten strukturell sauber: %s" % ", ".join(fehler))


func test_level_steigern_sich() -> void:
	var liste := _level_liste()
	var erstes := Logic.level_by_id(liste, 1)
	var letztes := Logic.level_by_id(liste, 10)
	assert_true(
		int(letztes["schafe"]) > int(erstes["schafe"]), "Level 10 hat mehr Schafe als Level 1"
	)
	assert_true(int(erstes["schafe"]) >= 3, "auch Level 1 ist eine Herde")


func test_registry_kann_level_ersetzen() -> void:
	var registry := FakeRegistry.new()
	registry.balance = {"herde_level": [{"id": 1, "schafe": 2}]}
	assert_eq(Logic.load_level(registry).size(), 1, "Content-Pack-Override greift")


func test_pferch_geometrie_und_tor() -> void:
	var level := {
		"feld": [12.0, 9.0],
		"pferch": {"x": 2.0, "z": -6.0, "w": 6.0, "t": 4.0, "tor": 3.0},
	}
	var tor := Logic.tor_pos(level)
	assert_almost(tor.x, 2.0)
	assert_almost(tor.y, -4.0, 1e-6, "Tor mittig auf der Süd-Kante")
	assert_true(Logic.ist_im_pferch(level, Vector2(2.0, -6.0)), "Pferch-Mitte ist drin")
	assert_false(Logic.ist_im_pferch(level, Vector2(2.0, -3.0)), "südlich der Kante ist draußen")
	assert_false(Logic.ist_im_pferch(level, Vector2(6.0, -6.0)), "östlich daneben ist draußen")


func test_spawn_ist_deterministisch_und_im_sueden() -> void:
	var level := Logic.level_by_id(_level_liste(), 3)
	var a := Logic.spawn_schafe(level, GoobyRng.new(7))
	var b := Logic.spawn_schafe(level, GoobyRng.new(7))
	assert_eq(str(a), str(b), "gleicher Seed = gleiche Herde")
	assert_eq(a.size(), int(level["schafe"]))
	var feld: Array = level["feld"]
	for s: Dictionary in a:
		assert_true(float(s["z"]) > 0.0, "Spawn in der Süd-Hälfte (Pferch liegt im Norden)")
		assert_true(absf(float(s["x"])) <= float(feld[0]), "im Feld")
		assert_false(bool(s["drin"]))


func test_step_ist_pure_und_deterministisch() -> void:
	var level := Logic.level_by_id(_level_liste(), 2)
	var schafe := Logic.spawn_schafe(level, GoobyRng.new(3))
	var vorher := str(schafe)
	var reiter := Vector2(0.0, 8.0)
	var a := Logic.step(schafe, reiter, 1.0, 1.0 / 30.0, Logic.TUNE, level)
	var b := Logic.step(schafe, reiter, 1.0, 1.0 / 30.0, Logic.TUNE, level)
	assert_eq(str(schafe), vorher, "Eingabe bleibt unberührt (pure)")
	assert_eq(str(a), str(b), "step ist deterministisch (kein RNG)")
	assert_eq(a.size(), schafe.size())


func test_flucht_treibt_vom_reiter_weg() -> void:
	var level := Logic.level_by_id(_level_liste(), 1)
	var schafe := [
		{"x": 0.0, "z": 4.0, "vx": 0.0, "vz": 0.0, "phase": 0.0, "drin": false},
	]
	var reiter := Vector2(0.0, 6.0)
	var tune := Logic.TUNE.duplicate()
	tune["WANDER_KRAFT"] = 0.0
	var nach := Logic.step(schafe, reiter, 0.0, 1.0 / 30.0, tune, level)
	assert_true(float(nach[0]["vz"]) < 0.0, "Schaf flieht nach Norden (weg vom Reiter im Süden)")


func test_drin_schafe_bremsen_und_bleiben() -> void:
	var level := {
		"feld": [12.0, 9.0],
		"pferch": {"x": 0.0, "z": -6.0, "w": 6.0, "t": 4.0, "tor": 3.0},
	}
	var schafe := [
		{"x": 0.0, "z": -6.0, "vx": 0.0, "vz": 3.0, "phase": 0.0, "drin": true},
	]
	var s: Dictionary = schafe[0]
	for i in 120:
		schafe = Logic.step(
			schafe, Vector2(0.0, 8.0), float(i) / 30.0, 1.0 / 30.0, Logic.TUNE, level
		)
		s = schafe[0]
	assert_true(bool(s["drin"]), "drin bleibt drin")
	assert_true(
		Logic.ist_im_pferch(level, Vector2(float(s["x"]), float(s["z"])), 0.0),
		"auch nach 4 s noch im Pferch (Wände halten)"
	)


func test_reiter_step_klemmt_aufs_feld() -> void:
	var level := {"feld": [10.0, 8.0], "pferch": {}}
	var reiter := Logic.reiter_step(Vector2(9.9, 0.0), Vector2(50.0, 0.0), 10.0, Logic.TUNE, level)
	assert_almost(reiter.x, 10.0, 1e-6, "Feld-Klemme greift")
	assert_almost(
		Logic.reiter_step(Vector2(0.0, -7.9), Vector2(0.0, -50.0), 10.0, Logic.TUNE, level).y, -8.0
	)


func test_score_und_sterne() -> void:
	assert_eq(Logic.level_score(3, 20.0, false), 40 + 40 + 12)
	assert_eq(Logic.level_score(3, 20.0, true), 40 + 40 + 12 + 25)
	assert_eq(Logic.level_score(1, -5.0, false), 40 + 4, "Restzeit nie negativ")
	assert_eq(Logic.sterne(30.0, 60.0), 3, ">= 40 % Rest")
	assert_eq(Logic.sterne(12.0, 60.0), 2, ">= 15 % Rest")
	assert_eq(Logic.sterne(3.0, 60.0), 1)
	assert_eq(Logic.sterne(10.0, 0.0), 1, "kaputtes Limit fällt auf 1")


func test_difficulty_stellschrauben() -> void:
	var easy := Logic.apply_difficulty(Logic.TUNE, "easy")
	var hard := Logic.apply_difficulty(Logic.TUNE, "hard")
	assert_true(float(easy["REITER_TEMPO"]) > float(hard["REITER_TEMPO"]), "easy reitet flinker")
	assert_true(
		float(easy["WANDER_KRAFT"]) < float(hard["WANDER_KRAFT"]), "hard-Schafe zappeln mehr"
	)
	var level := {"zeit_s": 60.0}
	assert_almost(Logic.zeitlimit(level, easy), 75.0, 1e-6, "easy bekommt mehr Zeit")
	assert_almost(Logic.zeitlimit(level, hard), 51.0)
	assert_almost(Logic.zeitlimit(level, Logic.TUNE), 60.0)


func test_bot_ist_deterministisch() -> void:
	var level := Logic.level_by_id(_level_liste(), 2)
	var a := Logic.simulate_hueten(level, 11, "normal")
	var b := Logic.simulate_hueten(level, 11, "normal")
	assert_eq(str(a), str(b), "gleicher Seed = identisches Ergebnis")


func test_bot_schafft_jedes_level_auf_normal() -> void:
	var liste := _level_liste()
	for id in range(1, Logic.LEVEL_ANZAHL + 1):
		var res := Logic.simulate_hueten(Logic.level_by_id(liste, id), 1, "normal")
		assert_true(bool(res["geschafft"]), "Level %d schaffbar (drin=%d)" % [id, int(res["drin"])])
		assert_true(int(res["score"]) > 0, "Sieg gibt Punkte")
		assert_true(int(res["sterne"]) >= 1)


func test_bot_schafft_level_1_auf_allen_seeds_easy() -> void:
	var level := Logic.level_by_id(_level_liste(), 1)
	for seed_value in range(1, 4):
		var res := Logic.simulate_hueten(level, seed_value, "easy")
		assert_true(bool(res["geschafft"]), "easy Seed %d gewinnt" % seed_value)

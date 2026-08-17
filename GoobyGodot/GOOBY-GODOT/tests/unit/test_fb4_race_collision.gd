extends TestCase
## FB-4 Bugfix-Beweis „Rennen lässt alle ineinander fahren": ToyRacerLogic
## kennt keine Kart-gegen-Kart-Kollision (Beleg: test_bug_exists_without_fix).
## ToyRacerContact löst Überdeckungen NACH jedem Logik-Schritt auf — sanfte
## Abdrängung plus Tempoverlust, ohne die zahlengleiche Logik anzufassen.

const Logic := preload("res://scripts/minigames/games/toy_racer/toy_racer_logic.gd")
const Contact := preload("res://scripts/minigames/games/toy_racer/toy_racer_contact.gd")

const DT := 1.0 / 60.0


## Tiefste Überdeckung (0 = frei) über alle Kart-Paare eines Rennens.
static func _worst_overlap(race: Dictionary) -> float:
	var karts: Array = race["karts"]
	var lap_len := float((race["track"] as Dictionary)["lapLen"])
	var worst := 0.0
	for i in karts.size():
		for j in range(i + 1, karts.size()):
			var ds: float = absf(Logic.s_delta(float(karts[j]["s"]), float(karts[i]["s"]), lap_len))
			var dlat: float = absf(float(karts[j]["lateral"]) - float(karts[i]["lateral"]))
			if ds >= Contact.LEN_MIN or dlat >= Contact.LAT_MIN:
				continue
			var depth := minf(1.0 - ds / Contact.LEN_MIN, 1.0 - dlat / Contact.LAT_MIN)
			worst = maxf(worst, depth)
	return worst


func _autoplay_race(seed_value: int, seconds: float, with_fix: bool) -> Dictionary:
	var race := Logic.create_race(seed_value)
	var contacts := {}
	var deep_frames := 0
	var worst_run := 0
	var bumps := 0
	for _f in int(seconds / DT):
		if bool(race["ended"]):
			break
		Logic.step_race(race, DT, Logic.bot_input(race))
		if with_fix:
			bumps += Contact.resolve(race, DT, contacts).size()
		if _worst_overlap(race) > 0.5:
			deep_frames += 1
			worst_run = maxi(worst_run, deep_frames)
		else:
			deep_frames = 0
	return {"worst_run": worst_run, "bumps": bumps}


## BUG-BELEG: ohne die Auflösung stecken Karts sekundenlang ineinander.
func test_bug_exists_without_fix() -> void:
	var stuck := 0
	for seed_value in [1, 7, 42]:
		stuck = maxi(stuck, int(_autoplay_race(seed_value, 45.0, false)["worst_run"]))
	assert_true(
		stuck > 60, "ohne Fix erwartete Dauer-Überdeckung fehlt (längste: %d Frames)" % stuck
	)


## FIX-BELEG: mit Auflösung dauert keine tiefe Überdeckung länger als ~0,7 s,
## und es gibt weiterhin echte Rempler (kein sterilen Abstandszwang).
func test_fix_prevents_lasting_overlap() -> void:
	for seed_value in [1, 7, 42]:
		var run := _autoplay_race(seed_value, 45.0, true)
		assert_true(
			int(run["worst_run"]) <= 42,
			"Seed %d: tiefe Überdeckung hält %d Frames" % [seed_value, int(run["worst_run"])]
		)
	var contact_seed := _autoplay_race(7, 45.0, true)
	assert_true(int(contact_seed["bumps"]) > 0, "es kommt gar kein Rempler mehr vor")


## Der Auffahrende verliert Tempo, der Vordere bekommt einen Schubs.
func test_rear_kart_loses_speed() -> void:
	var race := Logic.create_race(3)
	var karts: Array = race["karts"]
	var rear: Dictionary = karts[0]
	var front: Dictionary = karts[1]
	rear["s"] = 10.0
	rear["lateral"] = 0.0
	rear["speed"] = 3.0
	front["s"] = 10.3
	front["lateral"] = 0.05
	front["speed"] = 2.0
	karts[2]["s"] = 40.0
	karts[3]["s"] = 50.0
	var events := Contact.resolve(race, DT, {})
	assert_eq(events.size(), 1, "genau ein Rempler")
	assert_eq(int((events[0] as Dictionary)["rear"]), 0, "Kart 0 ist der Auffahrende")
	assert_almost(float(rear["speed"]), 3.0 * Contact.REAR_SPEED_KEEP, 1e-6)
	assert_almost(float(front["speed"]), 2.0 * Contact.FRONT_SPEED_PUSH, 1e-6)


## Tempoverlust zieht nur beim ERSTEN Kontakt — Dauerkontakt bremst nicht tot.
func test_speed_loss_only_on_fresh_contact() -> void:
	var race := Logic.create_race(3)
	var karts: Array = race["karts"]
	karts[0]["s"] = 10.0
	karts[0]["speed"] = 3.0
	karts[1]["s"] = 10.2
	karts[1]["lateral"] = 0.1
	karts[1]["speed"] = 2.0
	karts[2]["s"] = 40.0
	karts[3]["s"] = 50.0
	var contacts := {}
	Contact.resolve(race, DT, contacts)
	var speed_after_first := float(karts[0]["speed"])
	Contact.resolve(race, DT, contacts)
	assert_almost(float(karts[0]["speed"]), speed_after_first, 1e-6, "kein Doppel-Abzug")


## Verschobenes `s` zieht `progress` mit — Runden-/Platzrechnung bleibt wahr.
func test_progress_stays_consistent() -> void:
	var race := Logic.create_race(5)
	var karts: Array = race["karts"]
	karts[0]["s"] = 10.0
	karts[0]["lateral"] = 0.0
	karts[1]["s"] = 10.1
	karts[1]["lateral"] = 0.02
	karts[2]["s"] = 40.0
	karts[3]["s"] = 50.0
	var s_before := float(karts[0]["s"])
	var p_before := float(karts[0]["progress"])
	Contact.resolve(race, DT, {})
	var lap_len := float((race["track"] as Dictionary)["lapLen"])
	var ds := Logic.s_delta(float(karts[0]["s"]), s_before, lap_len)
	assert_almost(float(karts[0]["progress"]) - p_before, ds, 1e-6)


## Freie Karts bleiben unberührt (Zahlengleichheit außerhalb von Kontakten).
func test_free_karts_untouched() -> void:
	var race := Logic.create_race(9)
	var karts: Array = race["karts"]
	for i in karts.size():
		karts[i]["s"] = 5.0 + 10.0 * i
		karts[i]["speed"] = 2.0
	var snapshot := []
	for kart: Dictionary in karts:
		snapshot.append([float(kart["s"]), float(kart["lateral"]), float(kart["speed"])])
	var events := Contact.resolve(race, DT, {})
	assert_eq(events.size(), 0, "keine Rempler erwartet")
	for i in karts.size():
		assert_almost(float(karts[i]["s"]), float(snapshot[i][0]), 1e-9)
		assert_almost(float(karts[i]["lateral"]), float(snapshot[i][1]), 1e-9)
		assert_almost(float(karts[i]["speed"]), float(snapshot[i][2]), 1e-9)

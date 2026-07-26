extends TestCase
## RW-2 — Reitgefuehl-Ausbau (RanchRideStats + RanchRideTouch +
## RanchRideController-DLC): Stat-Formeln, Toelt-Schaltung, Antritts-
## Kick, Ausdauer-Tank, Sprung-Timing-Fenster, Untergrund, Zweiter Wind,
## Touch-Erkennung und die Controller-Verdrahtung (Telemetrie, Wertung).

const Feel := preload("res://scripts/ranch/gameplay/ride_feel.gd")
const Stats := preload("res://scripts/ranch/gameplay/ride_stats.gd")
const Touch := preload("res://scripts/ranch/gameplay/ride_touch.gd")


func test_zieltempo_skaliert_mit_tempo_stat() -> void:
	assert_almost(Stats.zieltempo("galopp", {"tempo": 10}), 8.5)
	assert_almost(Stats.zieltempo("galopp", {"tempo": 20}), 8.5 * 1.15, 1e-6, "Stat 20 = +15 %")
	assert_almost(Stats.zieltempo("galopp", {"tempo": 1}), 8.5 * 0.865, 1e-6, "Stat 1 = −13,5 %")
	assert_almost(Stats.zieltempo("galopp", {"tempo": 10}, 1.06), 8.5 * 1.06, 1e-6, "Bindungs-Perk")
	assert_almost(Stats.zieltempo("toelt", {"tempo": 20}), 5.8, 1e-6, "Toelt bleibt fix 5,8")
	assert_almost(Stats.zieltempo("trab", {}), 4.2, 1e-6, "leere Stats = Bestand")


func test_toelt_schaltfolge_nur_fuer_berechtigte() -> void:
	assert_eq(Stats.gangart_hoch("trab", true), "toelt", "Toelterle schaltet Trab→Toelt")
	assert_eq(Stats.gangart_hoch("toelt", true), "galopp")
	assert_eq(Stats.gangart_hoch("trab", false), "galopp", "andere ueberspringen Toelt")
	assert_eq(Stats.gangart_runter("galopp", true), "toelt")
	assert_eq(Stats.gangart_runter("galopp", false), "trab")
	assert_eq(Stats.gangart_runter("toelt", false), "trab", "Toelt-Rest faellt sicher")


func test_antritts_kick_und_dauer() -> void:
	assert_almost(Stats.accel_auf("galopp", 0.5), Feel.KICK_ACCEL, 1e-6, "Kick aktiv = 4,5 m/s²")
	assert_almost(Stats.accel_auf("galopp", 0.0), 3.0, 1e-6, "nach dem Kick Gangart-Antritt")
	assert_almost(Stats.accel_auf("schritt", 1.0), 2.0, 1e-6, "Kick zaehlt nur im Galopp")
	assert_almost(Stats.kick_dauer_s({}), 0.8)
	assert_almost(Stats.kick_dauer_s({"kick_dauer_s": 1.2}), 1.2, 1e-6, "Flitzewind 1,2 s")


func test_ausdauer_tank_und_verbrauch() -> void:
	assert_almost(Stats.ausdauer_max({"ausdauer": 10}), 100.0)
	assert_almost(Stats.ausdauer_max({"ausdauer": 1}), 55.0)
	assert_almost(Stats.ausdauer_max({"ausdauer": 20}), 150.0)
	assert_almost(Stats.galopp_verbrauch({"ausdauer": 10}), 7.0)
	assert_almost(Stats.galopp_verbrauch({"ausdauer": 20}), 6.3, 1e-6)
	assert_almost(
		Stats.step_ausdauer(50.0, "toelt", 1.0, {"ausdauer": 10}), 47.0, 1e-6, "Toelt zehrt 3/s"
	)
	assert_almost(
		Stats.step_ausdauer(149.0, "stand", 1.0, {"ausdauer": 20}),
		150.0,
		1e-6,
		"klemmt am Stat-Tank"
	)
	assert_eq(Stats.gangart_nach_ausdauer("toelt", 15.0, false), "trab", "Antoelten braucht 20")
	assert_eq(Stats.gangart_nach_ausdauer("toelt", 15.0, true), "toelt")
	assert_eq(Stats.gangart_nach_ausdauer("galopp", 0.0, true), "trab")


func test_lenkung_skaliert_mit_wendigkeit() -> void:
	var basis := Stats.steer_yaw_rate(1.0, 8.5, {"wendigkeit": 10})
	assert_almost(basis, 1.7 * 0.7, 1e-6, "Stat 10 = Bestand")
	var wendig := Stats.steer_yaw_rate(1.0, 8.5, {"wendigkeit": 20})
	assert_true(wendig > basis, "Wendigkeit 20 lenkt schaerfer")
	assert_almost(wendig, 1.7 * 1.2 * (1.0 - 0.24), 1e-6)
	assert_almost(Stats.steer_yaw_rate(1.0, 0.1, {}), 0.0, 1e-6, "im Stand dreht nichts")
	assert_true(
		absf(Stats.steer_yaw_rate(99.0, 4.0, {"wendigkeit": 20})) <= Feel.STEER_RATE_CAP_RAD_S,
		"100°/s-Deckel haelt"
	)


func test_sprung_timing_fenster() -> void:
	assert_eq(Stats.sprung_wertung(1.1, 6.0), "perfekt")
	assert_eq(Stats.sprung_wertung(0.9, 6.0), "perfekt", "Fenster-Unterkante")
	assert_eq(Stats.sprung_wertung(1.3, 6.0), "perfekt", "Fenster-Oberkante")
	assert_eq(Stats.sprung_wertung(0.6, 6.0), "gut")
	assert_eq(Stats.sprung_wertung(1.85, 6.0), "gut")
	assert_eq(Stats.sprung_wertung(2.5, 6.0), "daneben")
	assert_eq(Stats.sprung_wertung(0.2, 6.0), "daneben")
	assert_eq(
		Stats.sprung_wertung(1.5, 8.0, 50.0), "perfekt", "Sprunggefuehl +50 ms weitet das Fenster"
	)
	assert_eq(Stats.sprung_wertung(1.5, 0.0, 50.0), "gut", "Bonus skaliert mit Tempo")
	assert_almost(Stats.sprung_vy({"sprungkraft": 10}), 4.8)
	assert_almost(Stats.sprung_vy({"sprungkraft": 20}), 5.4, 1e-6)


func test_untergrund_und_gelaende_profi() -> void:
	assert_almost(Stats.untergrund_tempo_mult("wiese"), 1.0)
	assert_almost(Stats.untergrund_tempo_mult("matsch"), 0.9)
	assert_almost(Stats.untergrund_tempo_mult("wasser"), 0.85)
	assert_almost(
		Stats.untergrund_tempo_mult("matsch", 0.5), 0.95, 1e-6, "Moosmaehne halbiert den Malus"
	)
	assert_eq(str(Stats.untergrund_info("holz").get("sound")), "huf_holz")
	assert_eq(
		str(Stats.untergrund_info("gibtsnicht").get("sound")), "huf_gras", "unbekannt = Wiese"
	)


func test_zweiter_wind_und_erschoepfung() -> void:
	assert_true(Stats.zweiter_wind_moeglich(5.0, 0.0, false))
	assert_false(Stats.zweiter_wind_moeglich(5.0, 0.0, true), "nur 1×/Ritt")
	assert_false(Stats.zweiter_wind_moeglich(15.0, 0.0, false), "erst unter 10")
	assert_false(Stats.zweiter_wind_moeglich(5.0, 3.0, false), "nur im Stand")
	assert_almost(Stats.erschoepfung_bindung_malus(50.0, 0.0), 0.0, 1e-6, "Laune >= 40 verzeiht")
	assert_almost(Stats.erschoepfung_bindung_malus(30.0, 0.0), 1.0)
	assert_almost(Stats.erschoepfung_bindung_malus(30.0, 2.5), 0.5, 1e-6, "Tagesdeckel 3")
	assert_almost(Stats.erschoepfung_bindung_malus(30.0, 3.0), 0.0)


func test_scheu_chance_und_lenkassistent() -> void:
	assert_almost(Stats.scheu_chance({"gelassenheit": 10}), 0.15)
	assert_almost(Stats.scheu_chance({"gelassenheit": 20}), 0.075, 1e-6, "halbiert bei 20")
	assert_almost(Stats.scheu_chance({"gelassenheit": 10}, 0.0), 0.0, 1e-6, "mutig scheut nie")
	assert_almost(Stats.lenkassistent(1.0, 0.0, 0.3), 0.7, 1e-6, "30 % Zug zur Ideallinie")
	assert_almost(Stats.lenkassistent(1.0, 0.0, 0.9), 0.7, 1e-6, "Staerke klemmt bei 0,3")
	assert_almost(Stats.lenkassistent(0.5, 0.5, 0.3), 0.5)


func test_kamera_offset_ohne_pflicht_wippen() -> void:
	assert_almost(Stats.kamera_y_offset(true, 0.0, false, "galopp", 0.0), -0.1)
	assert_almost(Stats.kamera_y_offset(false, 0.15, false, "galopp", 0.0), -0.06, 1e-6)
	assert_almost(
		Stats.kamera_y_offset(false, 0.0, false, "galopp", 0.35), 0.0, 1e-6, "Standard OHNE Wippen"
	)
	assert_true(
		absf(Stats.kamera_y_offset(false, 0.0, true, "galopp", 0.035)) > 0.0, "Opt-in wippt"
	)


func test_touch_stick_und_wische() -> void:
	var start := Vector2(100.0, 500.0)
	assert_almost(Touch.stick_lenkung(start, start + Vector2(5.0, 0.0), 1.0), 0.0, 1e-6, "Deadzone")
	assert_almost(Touch.stick_lenkung(start, start + Vector2(64.0, 0.0), 1.0), 1.0)
	assert_almost(Touch.stick_lenkung(start, start + Vector2(-64.0, 0.0), 1.0), -1.0)
	assert_almost(Touch.stick_lenkung(start, start + Vector2(999.0, 0.0), 1.0), 1.0, 1e-6, "Klemme")
	assert_eq(Touch.wisch_richtung(start, start + Vector2(0.0, -30.0), 200.0, 1.0), "hoch")
	assert_eq(Touch.wisch_richtung(start, start + Vector2(0.0, 30.0), 200.0, 1.0), "runter")
	assert_eq(Touch.wisch_richtung(start, start + Vector2(0.0, -30.0), 400.0, 1.0), "", "zu lahm")
	assert_eq(Touch.wisch_richtung(start, start + Vector2(0.0, -10.0), 100.0, 1.0), "", "zu kurz")


func test_touch_zuegel_gyro_und_bedienhilfen() -> void:
	assert_eq(Touch.zuegel_gangart(0.0), "schritt")
	assert_eq(Touch.zuegel_gangart(0.3), "trab")
	assert_eq(Touch.zuegel_gangart(0.6), "galopp")
	assert_eq(Touch.zuegel_loslassen("galopp"), "trab")
	assert_almost(Touch.gyro_lenkung(2.0), 0.0, 1e-6, "Gyro-Deadzone 3°")
	assert_almost(Touch.gyro_lenkung(15.0), 1.0)
	assert_almost(Touch.gyro_lenkung(-9.0), -0.5)
	assert_almost(Touch.button_dp(120.0), 96.0, 1e-6, "Button-Band 64–96 dp")
	assert_almost(Touch.button_dp(10.0), 64.0)
	assert_almost(Touch.spiegel_x(100.0, 800.0, true), 700.0, 1e-6, "Linkshaender-Spiegel")
	assert_true(Touch.sprung_button_pulsiert(4.0))
	assert_false(Touch.sprung_button_pulsiert(-1.0))


## ------------------------------------------- Controller-Verdrahtung (Node)


func _controller() -> RanchRideController:
	var c := RanchRideController.new()
	c.use_camera = false
	c.keyboard_input = false
	c.active = false
	tree.root.add_child(c)
	return c


func test_controller_toelt_und_kick_ueber_set_pferd() -> void:
	var c := _controller()
	var pferd := RanchPlaySlices.neues_pferd("Toelti", "braun", {"rasse": "toelterle"})
	c.set_pferd(pferd)
	c.gait_up()
	c.gait_up()
	c.gait_up()
	assert_eq(c.gait, "toelt", "Toelterle: stand→schritt→trab→toelt")
	c.ausdauer = 100.0
	c.gait_up()
	assert_eq(c.gait, "galopp")
	assert_true(float(c.get("_kick_rest")) > 0.0, "Angaloppieren zuendet den Kick")
	c.queue_free()


func test_controller_sprung_wertung_und_telemetrie() -> void:
	var c := _controller()
	c.set_pferd(RanchPlaySlices.neues_pferd("Springi", "braun"))
	c.set_hindernisse([Vector3(0.0, 0.0, -1.1)])
	c.gait = "galopp"
	c.tempo = 8.0
	var wertungen: Array = []
	c.sprung_gewertet.connect(func(w: String, p: int) -> void: wertungen.append([w, p]))
	c.jump()
	assert_eq(wertungen.size(), 1, "Sprung wird gewertet")
	assert_eq(str(wertungen[0][0]), "perfekt", "1,1 m vor dem Hindernis = Perfekt-Zone")
	assert_eq(int(wertungen[0][1]), Feel.SPRUNG_PERFEKT_PUNKTE)
	var tele := c.telemetrie()
	assert_eq(int(tele["sprung_perfekt"]), 1)
	assert_almost(c.naechstes_hindernis_m(), 1.1, 1e-4)
	c.queue_free()


func test_controller_zweiter_wind_und_getter() -> void:
	var c := _controller()
	c.set_pferd(RanchPlaySlices.neues_pferd("Puste", "braun"))
	c.set_bindung(60.0)
	c.ausdauer = 5.0
	c.tempo = 0.0
	assert_true(c.zweiter_wind_bereit())
	var bonus: Array = []
	c.zweiter_wind_genutzt.connect(func(b: float) -> void: bonus.append(b))
	assert_true(c.zweiter_wind())
	assert_almost(c.ausdauer, 5.0 + 35.0, 1e-6, "Bindungs-L6 = +35")
	assert_eq(bonus, [35.0])
	assert_false(c.zweiter_wind(), "nur 1×/Ritt")
	assert_almost(c.ausdauer_max(), 100.0)
	c.queue_free()


func test_controller_gelaende_provider_wirken() -> void:
	var c := _controller()
	c.set_pferd(RanchPlaySlices.neues_pferd("Bergi", "braun"))
	c.set_gelaende(
		func(_x: float, _z: float) -> float: return 2.5,
		func(_pos: Vector3) -> String: return "matsch"
	)
	c.call("_step_ride", 0.016)
	assert_almost(c.position.y, 2.5, 1e-4, "Reiter steht auf der Boden-Hoehe")
	assert_eq(c.untergrund, "matsch", "Untergrund-Provider gelesen")
	c.gait = "galopp"
	assert_true(
		float(c.call("_zieltempo")) < Stats.zieltempo("galopp", {}), "Matsch bremst das Ziel"
	)
	c.queue_free()


func test_controller_stur_verzoegert_ersten_wechsel() -> void:
	var c := _controller()
	var pferd := RanchPlaySlices.neues_pferd("Sturi", "braun")
	pferd["charakter"] = ["stur", "verspielt"]
	c.set_pferd(pferd)
	c.gait_up()
	assert_eq(c.gait, "stand", "stur: erster Wechsel zoegert 0,4 s")
	c.call("_step_timers", 0.5)
	assert_eq(c.gait, "schritt", "nach der Verzoegerung schaltet es")
	c.gait_up()
	assert_eq(c.gait, "trab", "weitere Wechsel sofort")
	c.queue_free()

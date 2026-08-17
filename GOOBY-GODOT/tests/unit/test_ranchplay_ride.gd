extends TestCase
## RANCH-2 — Reit-Physik-Kanten (RanchRideFeel): Gangart-Schaltung,
## asymmetrisches Tempo, Lenk-Tiefpass + Yaw-Deckel, Sprung-Physik,
## Ausdauer-Regeln, Kopfnicken/Hufschläge und Kamera-/Staub-Kurven.

const Feel := preload("res://scripts/ranch/gameplay/ride_feel.gd")


func test_gangart_schaltung_klemmt_an_den_enden() -> void:
	assert_eq(Feel.gangart_hoch("stand"), "schritt")
	assert_eq(Feel.gangart_hoch("trab"), "galopp")
	assert_eq(Feel.gangart_hoch("galopp"), "galopp")
	assert_eq(Feel.gangart_runter("galopp"), "trab")
	assert_eq(Feel.gangart_runter("stand"), "stand")
	assert_eq(Feel.gangart_runter("kaputt"), "stand", "unbekannt fällt sicher")


func test_zieltempo_perk_wirkt_nur_im_galopp() -> void:
	assert_almost(Feel.zieltempo("galopp", 1.06), 8.5 * 1.06)
	assert_almost(Feel.zieltempo("trab", 1.06), 4.2, 1e-6, "Trab bleibt Trab")
	assert_almost(Feel.zieltempo("kaputt"), 0.0)


func test_step_tempo_ist_asymmetrisch_und_ueberschiesst_nie() -> void:
	assert_almost(Feel.step_tempo(0.0, 8.5, 1.0), 3.0, 1e-6, "sanft rauf (3 m/s²)")
	assert_almost(Feel.step_tempo(8.5, 0.0, 1.0), 3.0, 1e-6, "williger runter (5.5 m/s²)")
	assert_almost(Feel.step_tempo(4.19, 4.2, 1.0), 4.2, 1e-6, "kein Überschießen")


func test_lenkung_tiefpass_und_yaw_deckel() -> void:
	assert_almost(Feel.smooth_steer(0.5, 1.0, 0.0), 0.5, 1e-6, "dt=0 ändert nichts")
	var ein_schritt := Feel.smooth_steer(0.0, 1.0, 0.14)
	assert_almost(ein_schritt, 1.0 - exp(-1.0), 1e-6, "ein τ ≈ 63 %")
	assert_almost(Feel.steer_yaw_rate(1.0, 0.1), 0.0, 1e-6, "im Stand dreht nichts")
	assert_almost(
		Feel.steer_yaw_rate(1.0, 8.5), 1.7 * 0.7, 1e-6, "Galopp dämpft die Lenkung um 30 %"
	)
	assert_true(
		absf(Feel.steer_yaw_rate(100.0, 4.0)) <= Feel.STEER_RATE_CAP_RAD_S + 1e-9,
		"Yaw-Rate ist gedeckelt"
	)


func test_wrap_angle_haelt_das_intervall() -> void:
	assert_almost(Feel.wrap_angle(PI + 0.1), -PI + 0.1, 1e-6)
	assert_almost(Feel.wrap_angle(-PI - 0.1), PI - 0.1, 1e-6)
	assert_almost(Feel.wrap_angle(0.3), 0.3)


func test_springen_braucht_trab_tempo_und_boden() -> void:
	assert_true(Feel.kann_springen(3.0, 0.0))
	assert_false(Feel.kann_springen(2.99, 0.0), "unter Sprung-Mindesttempo")
	assert_false(Feel.kann_springen(6.0, 0.5), "in der Luft nicht")


func test_sprung_daten_passen_zur_schritt_physik() -> void:
	var daten := Feel.sprung_daten(6.0)
	assert_almost(float(daten["flugzeit_s"]), 2.0 * 4.8 / 11.5, 1e-6)
	assert_almost(float(daten["hoehe_m"]), 4.8 * 4.8 / (2.0 * 11.5), 1e-6)
	assert_almost(float(daten["weite_m"]), 6.0 * 2.0 * 4.8 / 11.5, 1e-6)
	# Integration landet nahe der analytischen Flugzeit (semi-implizit).
	var state := {"y": 0.001, "vy": Feel.SPRUNG_VY}
	var dt := 1.0 / 120.0
	var t := 0.0
	var apex := 0.0
	while float(state["y"]) > 0.0 and t < 3.0:
		state = Feel.step_sprung(state, dt)
		apex = maxf(apex, float(state["y"]))
		t += dt
	assert_almost(t, float(daten["flugzeit_s"]), 0.05, "Flugzeit ≈ analytisch")
	assert_almost(apex, float(daten["hoehe_m"]), 0.05, "Scheitel ≈ analytisch")
	assert_eq(
		Feel.step_sprung({"y": 0.01, "vy": -5.0}, 0.1), {"y": 0.0, "vy": 0.0}, "Landung klemmt"
	)


func test_ausdauer_zehrt_und_regeneriert() -> void:
	assert_almost(Feel.step_ausdauer(100.0, "galopp", 1.0), 93.0)
	assert_almost(Feel.step_ausdauer(50.0, "schritt", 1.0), 59.0)
	assert_almost(Feel.step_ausdauer(50.0, "stand", 1.0, 1.25), 61.25, 1e-6, "Bindungs-Perk")
	assert_almost(Feel.step_ausdauer(50.0, "trab", 1.0), 50.0, 1e-6, "Trab ist neutral")
	assert_almost(Feel.step_ausdauer(0.5, "galopp", 1.0), 0.0, 1e-6, "klemmt bei 0")
	assert_almost(Feel.step_ausdauer(99.0, "stand", 1.0), 100.0, 1e-6, "klemmt bei 100")


func test_leere_ausdauer_zwingt_in_den_trab() -> void:
	assert_eq(Feel.gangart_nach_ausdauer("galopp", 0.0, true), "trab")
	assert_eq(Feel.gangart_nach_ausdauer("galopp", 15.0, false), "trab", "Angaloppieren ab 20")
	assert_eq(Feel.gangart_nach_ausdauer("galopp", 15.0, true), "galopp", "im Galopp bleiben")
	assert_eq(Feel.gangart_nach_ausdauer("galopp", 25.0, false), "galopp")
	assert_eq(Feel.gangart_nach_ausdauer("schritt", 0.0, false), "schritt", "nur Galopp betroffen")


func test_kopfnicken_und_hufschlaege() -> void:
	assert_almost(Feel.kopfnicken(0.0, "trab"), 0.045, 1e-6, "Phase 0 = oben")
	assert_almost(Feel.kopfnicken(0.5, "trab"), -0.045, 1e-6, "Phase 0.5 = unten")
	assert_almost(Feel.kopfnicken(0.25, "stand"), 0.006 - 2.0 * 0.006 * sin(PI * 0.25), 1e-6)
	assert_eq(Feel.hufschlaege(0.0, 0.49), 0)
	assert_eq(Feel.hufschlaege(0.0, 0.5), 1)
	assert_eq(Feel.hufschlaege(0.4, 0.6), 1)
	assert_eq(Feel.hufschlaege(0.6, 0.4), 0, "rückwärts zählt nichts")
	assert_almost(Feel.schritt_hz("galopp"), 1.9)


func test_kamera_und_staub_kurven() -> void:
	assert_almost(Feel.fov_fuer_tempo(0.0), 58.0)
	assert_almost(Feel.fov_fuer_tempo(4.2), 58.0)
	assert_almost(Feel.fov_fuer_tempo(8.5), 66.0)
	assert_almost(Feel.fov_fuer_tempo(20.0), 66.0, 1e-6, "über Galopp geklemmt")
	assert_true(Feel.cam_follow_factor(1.0 / 30.0) > Feel.cam_follow_factor(1.0 / 120.0))
	assert_almost(Feel.cam_follow_factor(-1.0), 0.0, 1e-6, "negatives dt sicher")
	assert_almost(Feel.staub_anteil("galopp"), 1.0)
	assert_almost(Feel.staub_anteil("schritt"), 0.0)


func test_clamp_bounds_haelt_die_koppel() -> void:
	var mitte := Vector2(10.0, -4.0)
	var halb := Vector2(5.0, 3.0)
	var drin := Feel.clamp_bounds(Vector2(10.0, -4.0), mitte, halb)
	assert_eq(drin, Vector2(10.0, -4.0))
	var raus := Feel.clamp_bounds(Vector2(99.0, -99.0), mitte, halb)
	assert_almost(raus.x, 10.0 + 5.0 - 0.6, 1e-6, "0.6 m weicher Rand")
	assert_almost(raus.y, -4.0 - 3.0 + 0.6, 1e-6)

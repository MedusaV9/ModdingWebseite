extends TestCase
## W13/BALL — Ball werfen & apportieren (EVAL-Restliste #17, Web-Parität):
## flick_to_velocity/step sind der 1:1-Port von interactions.js
## (flickToVelocity/stepBall), die Zustandsmaschine RUHT→FLIEGT→GOOBY_HOLT→
## BRINGT_ZURUECK ist vollständig, die Apport-Wirkung trifft exakt die
## Web-Zahlen (+3 Spaß, Gewicht −0.2, `balls`-Counter +1) und Doppel-Würfe
## während des Flugs prallen ab. Alles PUR und headless (BallLogic).

const DT := 1.0 / 60.0
const TEST_FLICK := Vector2(400.0, -800.0)


func _state(fun := 50.0, weight := 50.0) -> Dictionary:
	return {
		"gooby":
		{
			"stats": {"hunger": 50.0, "fun": fun, "energy": 50.0, "hygiene": 50.0},
			"weight": weight,
		},
		"achievements": {"counters": {"balls": 0}},
	}


## Bis zur Ruhe simulieren; Rückgabe = Anzahl Schritte (−1 = nie geruht).
func _simuliere_bis_ruhe(logic: BallLogic, max_steps := 1200) -> int:
	for i in max_steps:
		if bool(logic.step(DT)["resting"]):
			return i
	return -1


func test_flick_to_velocity_exakte_web_zahlen() -> void:
	# Web flickToVelocity: x = vx*s, y = max(0.8, -vy*s), z = -|vy*s|*0.35.
	var v := BallLogic.flick_to_velocity(TEST_FLICK)
	assert_almost(v.x, 1.4, 1e-6, "x = 400 * 0.0035")
	assert_almost(v.y, 2.8, 1e-6, "y = -(-800) * 0.0035")
	assert_almost(v.z, -0.98, 1e-6, "z = -|−800*0.0035| * 0.35")
	# Flacher Flick: Y wird immer auf mindestens 0.8 gehoben.
	var flach := BallLogic.flick_to_velocity(Vector2(100.0, 0.0))
	assert_almost(flach.y, 0.8, 1e-6, "flacher Flick fliegt trotzdem im Bogen")
	# Monster-Flick: Betrag wird auf MAX_SPEED geklemmt.
	var monster := BallLogic.flick_to_velocity(Vector2(9000.0, -9000.0))
	assert_almost(monster.length(), BallLogic.MAX_SPEED, 1e-4, "Klemme bei 6 m/s")


func test_wurf_simulation_deterministisch() -> void:
	# Gleicher Flick + gleiche Schritte ⇒ bit-identische Bahn (kein Zufall
	# in der Physik — der injizierte RNG wählt nur den Spruch).
	var a := BallLogic.new()
	var b := BallLogic.new()
	assert_true(a.werfen(TEST_FLICK))
	assert_true(b.werfen(TEST_FLICK))
	for i in 240:
		a.step(DT)
		b.step(DT)
		assert_true(a.pos.is_equal_approx(b.pos), "Schritt %d: Position identisch" % i)
		assert_true(a.vel.is_equal_approx(b.vel), "Schritt %d: Tempo identisch" % i)
	# Und die Bahn bleibt im Raum (Web-Wandklemmen relativ zum Spawn).
	assert_true(absf(a.pos.x) <= BallLogic.BOUND_X + 1e-6, "X-Klemme hält")
	assert_true(a.pos.z >= BallLogic.BOUND_Z_MIN - 1e-6, "Z-Min-Klemme hält")
	assert_true(a.pos.z <= BallLogic.BOUND_Z_MAX + 1e-6, "Z-Max-Klemme hält")


func test_wurf_kommt_zur_ruhe_und_bounct() -> void:
	var logic := BallLogic.new()
	assert_true(logic.werfen(TEST_FLICK))
	var gebounct := false
	var geruht := false
	for _i in 1200:
		var schritt := logic.step(DT)
		gebounct = gebounct or bool(schritt["bounced"])
		if bool(schritt["resting"]):
			geruht = true
			break
	assert_true(gebounct, "mindestens ein hörbarer Bounce")
	assert_true(geruht, "der Ball kommt in < 20 s zur Ruhe")
	assert_true(logic.vel.is_equal_approx(Vector3.ZERO), "Ruhe = Stillstand")
	assert_almost(logic.pos.y, BallLogic.RADIUS, 0.021, "liegt auf dem Boden")


func test_zustandsmaschine_kompletter_zyklus() -> void:
	var logic := BallLogic.new()
	assert_eq(logic.zustand, BallLogic.RUHT, "startet ruhend")
	assert_true(logic.werfen(TEST_FLICK), "Wurf aus RUHT klappt")
	assert_eq(logic.zustand, BallLogic.FLIEGT)
	assert_true(_simuliere_bis_ruhe(logic) >= 0, "Flug endet")
	# Landung in Reichweite (1 m) ⇒ Gooby holt.
	assert_eq(logic.landung_verarbeiten(1.0, 1_000), BallLogic.LANDUNG_APPORT)
	assert_eq(logic.zustand, BallLogic.GOOBY_HOLT)
	# Kopfstoß: Rückflug Richtung Spawn + 15-s-Cooldown (Web-Zahlen).
	var zurueck := logic.kopfstoss(1_000)
	assert_eq(logic.zustand, BallLogic.BRINGT_ZURUECK)
	assert_false(zurueck.is_equal_approx(Vector3.ZERO), "Rückflug hat Tempo")
	assert_true(zurueck.z < 0.0, "Kopfstoß schubst zurück Richtung Spawn")
	assert_eq(logic.cooldown_bis_ms, 1_000 + BallLogic.BALL_COOLDOWN_SEC * 1000)
	assert_true(_simuliere_bis_ruhe(logic) >= 0, "Rückflug endet")
	assert_eq(logic.landung_verarbeiten(1.0, 2_000), BallLogic.LANDUNG_HEIM)
	assert_eq(logic.zustand, BallLogic.RUHT, "Zyklus schließt sich")


func test_doppelwurf_waehrend_fliegt_abgewehrt() -> void:
	var logic := BallLogic.new()
	assert_true(logic.werfen(TEST_FLICK))
	var tempo_vorher := logic.vel
	assert_false(logic.werfen(Vector2(2000.0, -2000.0)), "FLIEGT: kein zweiter Wurf")
	assert_true(logic.vel.is_equal_approx(tempo_vorher), "Tempo bleibt unangetastet")
	# Auch während Apport/Rückflug bleibt der Griff gesperrt.
	_simuliere_bis_ruhe(logic)
	logic.landung_verarbeiten(1.0, 0)
	assert_false(logic.werfen(TEST_FLICK), "GOOBY_HOLT: gesperrt")
	logic.kopfstoss(0)
	assert_false(logic.werfen(TEST_FLICK), "BRINGT_ZURUECK: gesperrt")


func test_landung_gates_cooldown_und_reichweite() -> void:
	var logic := BallLogic.new()
	# Zu weit weg (Web CHASE_MAX_DIST 3.2) ⇒ liegen lassen.
	logic.werfen(TEST_FLICK)
	_simuliere_bis_ruhe(logic)
	assert_eq(logic.landung_verarbeiten(3.3, 0), BallLogic.LANDUNG_LIEGEN)
	assert_eq(logic.zustand, BallLogic.RUHT)
	# Praktisch schon am Ball (< 0.05) ⇒ ebenfalls kein Lauf (Web-Gate).
	logic.werfen(TEST_FLICK)
	_simuliere_bis_ruhe(logic)
	assert_eq(logic.landung_verarbeiten(0.01, 0), BallLogic.LANDUNG_LIEGEN)
	# Cooldown: 1 ms zu früh ⇒ liegen, exakt abgelaufen ⇒ Apport.
	logic.cooldown_bis_ms = 20_000
	logic.werfen(TEST_FLICK)
	_simuliere_bis_ruhe(logic)
	assert_eq(logic.landung_verarbeiten(1.0, 19_999), BallLogic.LANDUNG_LIEGEN)
	logic.werfen(TEST_FLICK)
	_simuliere_bis_ruhe(logic)
	assert_eq(logic.landung_verarbeiten(1.0, 20_000), BallLogic.LANDUNG_APPORT)


func test_apport_reward_exakte_web_zahlen() -> void:
	# Web maybeFetch-Callback: fun +3 (INTERACT.BALL_FUN), Gewicht −0.2
	# (weightOnBallFetch §B5), counters.balls +1 (§B2).
	var state := _state()
	var result := BallLogic.apply_apport_reward(state)
	assert_almost(float(state["gooby"]["stats"]["fun"]), 53.0, 1e-6, "Spaß 50 → 53")
	assert_almost(float(state["gooby"]["weight"]), 49.8, 1e-6, "Gewicht 50 → 49.8")
	assert_eq(int(state["achievements"]["counters"]["balls"]), 1, "balls-Counter +1")
	assert_almost(float(result["fun_gain"]), 3.0, 1e-6)
	assert_eq(int(result["balls"]), 1)
	# Andere Stats bleiben unberührt.
	assert_almost(float(state["gooby"]["stats"]["hunger"]), 50.0, 1e-6)
	# Klemmen: Spaß deckelt bei 100 (Gain schrumpft ehrlich mit).
	var satt := _state(99.0)
	var satt_result := BallLogic.apply_apport_reward(satt)
	assert_almost(float(satt["gooby"]["stats"]["fun"]), 100.0, 1e-6, "Klemme bei 100")
	assert_almost(float(satt_result["fun_gain"]), 1.0, 1e-6, "Gain = echter Zuwachs")


func test_counter_inkrementiert_auch_ohne_vorbereiteten_slice() -> void:
	# Feindlicher/alter Save ohne achievements-Slice: der Counter wird
	# defensiv angelegt (wie FoodCatalog._counters) und zählt pro Apport.
	var state := {"gooby": {"stats": {"fun": 10.0}, "weight": 80.0}}
	BallLogic.apply_apport_reward(state)
	BallLogic.apply_apport_reward(state)
	assert_eq(int(state["achievements"]["counters"]["balls"]), 2, "zwei Apports = 2")
	assert_almost(float(state["gooby"]["weight"]), 79.6, 1e-6, "2 × −0.2 Gewicht")


func test_spruch_key_deterministisch_und_uebersetzt() -> void:
	# Injektions-RNG (AGENTS-Regel): gleicher Seed ⇒ gleicher Spruch.
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 1234
	b.seed = 1234
	assert_eq(BallLogic.spruch_key(a), BallLogic.spruch_key(b), "seedgleich = spruchgleich")
	# Alle Spruch-Keys existieren DE und EN (Loader mergt strings/*/ball.json).
	var de: Dictionary = I18nService.table("de")
	var en: Dictionary = I18nService.table("en")
	for key: String in BallLogic.SPRUCH_KEYS:
		assert_true(de.has(key), "DE-Spruch fehlt: %s" % key)
		assert_true(en.has(key), "EN-Spruch fehlt: %s" % key)

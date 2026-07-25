extends TestCase
## W2a — DoorLogic (pure Tür-Statemaschine): Gag-Würfel, Tap-Mash, Skip- und
## Settings-Regeln (Doc A §5, Gag ~12 % nie 2× hintereinander, 5–8 Taps).


func test_ohne_animation_direkt_travel() -> void:
	var logic := DoorLogic.new(false, false, 0.0, 0.0)
	assert_false(logic.will_stick, "doors_animated=false → nie Gag")
	assert_eq(logic.begin(), DoorLogic.State.TRAVEL, "degradiert zum Cut")
	assert_true(logic.is_traveling())


func test_gag_wuerfel() -> void:
	assert_true(DoorLogic.new(true, false, 0.119, 0.0).will_stick, "unter 12 %")
	assert_false(DoorLogic.new(true, false, 0.12, 0.0).will_stick, "ab 12 % nicht")
	assert_false(DoorLogic.new(true, true, 0.0, 0.0).will_stick, "nie 2× hintereinander")
	assert_false(DoorLogic.new(false, false, 0.0, 0.0).will_stick, "ohne Animation nie")


func test_taps_zwischen_5_und_8() -> void:
	assert_eq(DoorLogic.new(true, false, 0.0, 0.0).taps_required, 5)
	assert_eq(DoorLogic.new(true, false, 0.0, 0.49).taps_required, 6)
	assert_eq(DoorLogic.new(true, false, 0.0, 0.6).taps_required, 7)
	assert_eq(DoorLogic.new(true, false, 0.0, 0.99).taps_required, 8)
	assert_eq(DoorLogic.new(true, false, 0.0, 1.0).taps_required, 8, "clamp")


func test_happy_path_ohne_gag() -> void:
	var logic := DoorLogic.new(true, false, 0.9, 0.0)
	assert_eq(logic.begin(), DoorLogic.State.OPENING)
	assert_eq(logic.door_opened(), DoorLogic.State.WALKING)
	assert_eq(logic.reached_door(), DoorLogic.State.TRAVEL)
	assert_true(logic.is_traveling())


func test_steckenbleiben_mash_und_plopp() -> void:
	var logic := DoorLogic.new(true, false, 0.0, 0.0)
	logic.begin()
	logic.door_opened()
	assert_eq(logic.reached_door(), DoorLogic.State.STUCK)
	assert_almost(logic.mash_ratio(), 0.0)
	for i in 4:
		assert_eq(logic.tap_mash(), DoorLogic.State.STUCK, "Tap %d reicht nicht" % (i + 1))
	assert_almost(logic.mash_ratio(), 0.8)
	assert_eq(logic.tap_mash(), DoorLogic.State.POPPING, "5. Tap ploppt")
	assert_eq(logic.pop_finished(), DoorLogic.State.TRAVEL)
	assert_true(logic.is_traveling())


func test_mash_decay() -> void:
	var logic := DoorLogic.new(true, false, 0.0, 0.0)
	logic.begin()
	logic.door_opened()
	logic.reached_door()
	logic.tap_mash()
	logic.tap_mash()
	assert_almost(logic.mash_ratio(), 0.4)
	# W4-P3-Widerstandskurve: Verfall = BASIS * (1 + GAIN * ratio).
	var rate := DoorLogic.MASH_DECAY_PER_SEC * (1.0 + DoorLogic.RESISTANCE_GAIN * 0.4)
	assert_almost(logic.decay_rate(), rate)
	logic.mash_decay(1.0)
	assert_almost(logic.mash_ratio(), (2.0 - rate) / 5.0)
	logic.mash_decay(100.0)
	assert_almost(logic.mash_ratio(), 0.0, 1e-6, "nie negativ")


func test_mash_widerstand_steigt_mit_fortschritt() -> void:
	var logic := DoorLogic.new(true, false, 0.0, 0.0)
	logic.begin()
	logic.door_opened()
	logic.reached_door()
	var rate_leer := logic.decay_rate()
	for _i in 4:
		logic.tap_mash()
	assert_true(logic.decay_rate() > rate_leer, "voller Balken verfällt schneller (Widerstand)")
	assert_almost(
		logic.decay_rate(), DoorLogic.MASH_DECAY_PER_SEC * (1.0 + DoorLogic.RESISTANCE_GAIN * 0.8)
	)


func test_letzter_tap_wird_angekuendigt() -> void:
	var logic := DoorLogic.new(true, false, 0.0, 0.0)
	logic.begin()
	logic.door_opened()
	logic.reached_door()
	assert_false(logic.ist_letzter_tap(), "frisch stecken: noch nicht der letzte")
	for _i in 4:
		logic.tap_mash()
	assert_true(logic.ist_letzter_tap(), "4/5 Taps: der nächste ploppt")
	assert_eq(logic.tap_mash(), DoorLogic.State.POPPING)
	assert_false(logic.ist_letzter_tap(), "nach dem Plopp kein Telegraph mehr")


func test_skip_regeln() -> void:
	var opening := DoorLogic.new(true, false, 0.9, 0.0)
	opening.begin()
	assert_eq(opening.skip(), DoorLogic.State.TRAVEL, "Skip beim Öffnen")
	var walking := DoorLogic.new(true, false, 0.9, 0.0)
	walking.begin()
	walking.door_opened()
	assert_eq(walking.skip(), DoorLogic.State.TRAVEL, "Skip beim Laufen")
	var stuck := DoorLogic.new(true, false, 0.0, 0.0)
	stuck.begin()
	stuck.door_opened()
	stuck.reached_door()
	assert_eq(stuck.skip(), DoorLogic.State.STUCK, "KEIN Skip im Tap-Mash")
	var idle := DoorLogic.new(true, false, 0.9, 0.0)
	assert_eq(idle.skip(), DoorLogic.State.IDLE, "Skip vor begin ist no-op")


func test_events_in_falschen_zustaenden_sind_noops() -> void:
	var logic := DoorLogic.new(true, false, 0.9, 0.0)
	assert_eq(logic.tap_mash(), DoorLogic.State.IDLE)
	assert_eq(logic.door_opened(), DoorLogic.State.IDLE)
	assert_eq(logic.reached_door(), DoorLogic.State.IDLE)
	assert_eq(logic.pop_finished(), DoorLogic.State.IDLE)
	logic.begin()
	logic.begin()
	assert_eq(logic.state, DoorLogic.State.OPENING, "doppeltes begin bleibt OPENING")
	logic.mash_decay(1.0)
	assert_almost(logic.mash_ratio(), 0.0)

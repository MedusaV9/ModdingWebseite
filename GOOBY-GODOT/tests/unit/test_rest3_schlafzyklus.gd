extends TestCase
## REST-3 Rang 5 — Schlafloop WIRKLICH verkabelt: Zeitraffer ueber 5
## simulierte Tage gegen den ECHTEN GameState (Ticker + Sleep-Statehelfer,
## derselbe Pfad, den Bett-Interactable und PflegeRunner fahren).
##
## Abgesicherte Kette pro Tag: wacher Verfall macht muede (tiredness01 > 0,
## Tempo-Daempfung greift) → Bett-Regel (can_sleep erst unter energy 70) →
## Einschlafen im Save (start_sleep_state) → Nachtdurchlauf regeneriert →
## Auto-Aufwachen mit Grants (wokeUp, XP +10, sleeps-Zaehler). Dazu:
## Nickerchen, fruehes Wecken (Grumpy-Debuff) und die Folge von zu wenig
## Schlaf (Erschoepfung → kraenklich, Web-§B5-Erweiterung).

const GameStateScript := preload("res://scripts/state/game_state.gd")
const Sleep := preload("res://scripts/logic/sleep.gd")
const Health := preload("res://scripts/logic/health.gd")

const NOW_MS := 1768478400000
const MIN_MS := 60000

var _dir_seq := 0


func _fresh_path() -> String:
	_dir_seq += 1
	var dir := "user://rest3_tests/sleep_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	return dir + "/save_v5.json"


func _fresh_game_state(now_ms := NOW_MS) -> Node:
	var gs: Node = GameStateScript.new()
	gs.clock.pin(now_ms)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(_fresh_path())
	return gs


## Ein Pflege-Zwischenstopp: hunger/fun/hygiene auffrischen (wie ein
## fuersorglicher Spieler), energy NICHT anfassen — die fuellt nur Schlaf.
func _pflege(gs: Node) -> void:
	gs.set_value("gooby.stats.hunger", 85.0)
	gs.set_value("gooby.stats.fun", 85.0)
	gs.set_value("gooby.stats.hygiene", 85.0)


func test_fuenf_tage_zeitraffer_schlafzyklus() -> void:
	var gs := _fresh_game_state()
	var events_seen: Array = []
	gs.gooby_events.connect(func(ev: Array) -> void: events_seen.append_array(ev))
	for tag in 5:
		# Tagesphase: 4 Stunden wach in Stundenschritten mit Pflege dazwischen.
		for _h in 4:
			gs.clock.advance(60 * MIN_MS)
			gs.run_live_tick()
			_pflege(gs)
		var energy := float(gs.get_value("gooby.stats.energy"))
		assert_true(energy < 70.0, "Tag %d: abends muede genug fuers Bett (%f)" % [tag, energy])
		# Sichtbare Muedigkeit: unter 45 Energie zeigt der Rig Augenringe.
		assert_true(
			Sleep.tiredness01(gs.get_value("gooby.stats")) > 0.0,
			"Tag %d: tiredness01 sichtbar" % tag
		)
		# Bettzeit — exakt der Bett-Interactable-Pfad.
		var flat := Sleep.flat_of(gs.state())
		assert_true(Sleep.can_sleep(flat), "Tag %d: can_sleep" % tag)
		var now: int = gs.clock.now_ms()
		var ok := {"ok": false}
		gs.update(func(s: Dictionary) -> void: ok["ok"] = Sleep.start_sleep_state(s, now))
		assert_true(bool(ok["ok"]), "Tag %d: Schlaf startet im Save" % tag)
		assert_true(bool(gs.get_value("gooby.sleep.sleeping")), "Tag %d: schlaeft" % tag)
		# Nachtdurchlauf: Schlafdauer + Puffer, dann weckt der Ticker selbst.
		var dauer := Sleep.sleep_duration_min(energy)
		gs.clock.advance((dauer + 2) * MIN_MS)
		gs.run_live_tick()
		assert_false(bool(gs.get_value("gooby.sleep.sleeping")), "Tag %d: aufgewacht" % tag)
		assert_true(
			float(gs.get_value("gooby.stats.energy")) > 95.0,
			"Tag %d: Nacht regeneriert (%f)" % [tag, float(gs.get_value("gooby.stats.energy"))]
		)
	assert_eq(events_seen.count("wokeUp"), 5, "5 Naechte = 5 wokeUp (got %s)" % [events_seen])
	assert_eq(int(gs.get_value("achievements.counters.sleeps")), 5, "sleeps-Zaehler")
	# Gut umsorgt + ausgeschlafen: der 5-Tage-Zyklus macht NIE krank.
	assert_eq(str(gs.get_value("gooby.health.state")), "healthy", "bleibt gesund")
	gs.free()


func test_nickerchen_kurzschlaf_mit_grants() -> void:
	var gs := _fresh_game_state()
	gs.set_value("gooby.stats.energy", 75.0)
	gs.set_value("gooby.lastTickAt", NOW_MS)
	var flat := Sleep.flat_of(gs.state())
	assert_false(Sleep.can_sleep(flat), "75 Energie: zu wach fuer die ganze Nacht")
	assert_true(Sleep.can_nap(flat), "aber ein Nickerchen geht")
	var ok := {"ok": false}
	gs.update(func(s: Dictionary) -> void: ok["ok"] = Sleep.start_sleep_state(s, NOW_MS, true))
	assert_true(bool(ok["ok"]), "Nickerchen startet")
	var wake_at := int(gs.get_value("gooby.sleep.wakeAt"))
	var erwartet := mini(Sleep.NAP_MIN, Sleep.sleep_duration_min(75.0))
	assert_eq(wake_at - NOW_MS, erwartet * MIN_MS, "Nickerchen-Dauer = min(20, volle Dauer)")
	var events_seen: Array = []
	gs.gooby_events.connect(func(ev: Array) -> void: events_seen.append_array(ev))
	gs.clock.advance((erwartet + 2) * MIN_MS)
	gs.run_live_tick()
	assert_false(bool(gs.get_value("gooby.sleep.sleeping")), "nach dem Nickerchen wach")
	assert_true(events_seen.has("wokeUp"), "Nickerchen weckt regulaer (got %s)" % [events_seen])
	gs.free()


func test_fruehes_wecken_macht_grumpy_nie_mehr() -> void:
	var gs := _fresh_game_state()
	gs.set_value("gooby.stats.energy", 40.0)
	gs.set_value("gooby.lastTickAt", NOW_MS)
	gs.update(func(s: Dictionary) -> void: Sleep.start_sleep_state(s, NOW_MS))
	# Zu frueh (unter 5 min): das Bett laesst gar nicht wecken.
	var zu_frueh := NOW_MS + 2 * MIN_MS
	var events := {"list": []}
	gs.update(func(s: Dictionary) -> void: events["list"] = Sleep.wake_early_state(s, zu_frueh))
	assert_eq(events["list"], [], "unter 5 min: kein Wecken")
	assert_true(bool(gs.get_value("gooby.sleep.sleeping")), "schlaeft weiter")
	# Nach 6 min: Wecken erlaubt, Folge ist NUR der Grumpy-Debuff.
	var now := NOW_MS + 6 * MIN_MS
	gs.update(func(s: Dictionary) -> void: events["list"] = Sleep.wake_early_state(s, now))
	assert_eq(events["list"], ["wokeEarly"], "wokeEarly-Event")
	assert_false(bool(gs.get_value("gooby.sleep.sleeping")), "wach")
	assert_eq(
		int(gs.get_value("gooby.grumpyUntil")),
		now + Sleep.EARLY_WAKE_DEBUFF_MIN * MIN_MS,
		"Grumpy-Fenster 10 min"
	)
	var flat := Sleep.flat_of(gs.state())
	assert_almost(Sleep.grumpy_debuff(flat, now), 15.0, 1e-6, "Debuff aktiv")
	assert_almost(
		Sleep.grumpy_debuff(flat, now + 11 * MIN_MS), 0.0, 1e-6, "und verfliegt von selbst"
	)
	# KEINE Grants beim fruehen Wecken (die gibt es nur fuer vollen Schlaf).
	assert_eq(float(gs.get_value("progression.xp")), 0.0, "kein XP-Grant")
	assert_eq(int(gs.get_value("achievements.counters.sleeps", 0)), 0, "kein sleeps-Zaehler")
	gs.free()


func test_zu_wenig_schlaf_macht_erst_kraenklich() -> void:
	var gs := _fresh_game_state()
	# Erschoepft wach bleiben (energy <= 15) — hunger/fun/hygiene werden
	# brav gepflegt, damit NUR der Schlafmangel wirkt.
	gs.set_value("gooby.stats.energy", 10.0)
	gs.set_value("gooby.lastTickAt", NOW_MS)
	var events_seen: Array = []
	gs.gooby_events.connect(func(ev: Array) -> void: events_seen.append_array(ev))
	for _h in 5:
		gs.clock.advance(60 * MIN_MS)
		gs.run_live_tick()
		_pflege(gs)
	assert_true(
		float(gs.get_value("gooby.health.tiredMin")) >= Health.TIRED_QUEASY_MIN,
		"tiredMin gesammelt (%f)" % float(gs.get_value("gooby.health.tiredMin"))
	)
	assert_eq(str(gs.get_value("gooby.health.state")), "queasy", "Schlafmangel macht kraenklich")
	assert_true(events_seen.has("becameQueasy"), "becameQueasy (got %s)" % [events_seen])
	# Ausschlafen setzt den Erschoepfungs-Druck zurueck (Schlaf = Heilung).
	var now: int = gs.clock.now_ms()
	gs.update(func(s: Dictionary) -> void: Sleep.start_sleep_state(s, now))
	gs.clock.advance(40 * MIN_MS)
	gs.run_live_tick()
	assert_almost(float(gs.get_value("gooby.health.tiredMin")), 0.0, 1e-6, "Schlaf tilgt tiredMin")
	gs.free()


func test_tiredness01_kurve_und_tempo_daempfung() -> void:
	assert_almost(Sleep.tiredness01({"energy": 80.0}), 0.0, 1e-6, "wach = keine Muedigkeit")
	assert_almost(Sleep.tiredness01({"energy": 45.0}), 0.0, 1e-6, "Schwelle exakt")
	assert_almost(Sleep.tiredness01({"energy": 22.5}), 0.5, 1e-6, "halb muede")
	assert_almost(Sleep.tiredness01({"energy": 0.0}), 1.0, 1e-6, "voll muede")
	assert_almost(Sleep.tiredness01(null), 0.0, 1e-6, "kaputte Stats crashen nie")
	# PflegeRunner-Daempfung: muede wird langsamer, krank deckelt, nie 0.
	assert_almost(PflegeRunner.speed_mult_for(0, 0.0), 1.0, 1e-6, "fit = volles Tempo")
	assert_almost(PflegeRunner.speed_mult_for(0, 1.0), 0.65, 1e-6, "voll muede = -35%")
	assert_almost(PflegeRunner.speed_mult_for(1, 0.0), 0.85, 1e-6, "kraenklich gedeckelt")
	assert_almost(PflegeRunner.speed_mult_for(2, 0.0), 0.6, 1e-6, "krank gedeckelt")
	assert_true(PflegeRunner.speed_mult_for(2, 1.0) > 0.0, "nie stillstehend (nie strafend)")

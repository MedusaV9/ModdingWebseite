extends TestCase
## Wurzel-Tests der zentralen Tap-Geste (interactables_host.gd, Welle-H-Fixes
## PT1-B2 „Doppel-Feuer Maus+emulierter Touch“ und PT4-B3 „Tap feuert auf
## PRESS ohne Drag-Schwelle“):
## - Maus + emulierter Touch-Zwilling → EIN Feuer (Desktop-Richtung),
##   Touch + emulierte Maus → EIN Feuer (Mobile-Richtung).
## - Press → Move über der Schwelle → Release → KEIN Feuer (Pan bricht ab);
##   auch wenn die Zwischen-Drags verschluckt wurden (Release-Distanz).
## - Press → Release unter der Schwelle → EIN Feuer (erst auf Release).
## - Laufende Sequenz (Gooby-Skript-Lauf) + zweiter Tap → kein Doppel-Start
##   (Wiedereintritts-Sperre/busy-Flag des Hosts).
## Schwelle = HomeCameraRig.PAN_DEADZONE_PX (geteilt mit dem Boden-Pan).

const POS := Vector2(320.0, 200.0)


## Gooby-Double: für die Sperre zählen Skript-Lauf + Wander-Zustand.
class GoobyStub:
	extends Node3D

	var scripted := false
	var wander := true

	func is_scripted_walk() -> bool:
		return scripted

	func is_wander_enabled() -> bool:
		return wander


## Raum-Double nach RoomBase-Duck-Typing (`gooby()` liefert den Bewohner).
class RaumStub:
	extends Node3D

	var stub_gooby: Node3D = null

	func gooby() -> Node3D:
		return stub_gooby


func _maus(pos: Vector2, pressed: bool, device := 0) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.device = device
	return ev


func _touch(pos: Vector2, pressed: bool, device := 0, index := 0) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.pressed = pressed
	ev.position = pos
	ev.device = device
	ev.index = index
	return ev


func _drag(pos: Vector2, device := 0, index := 0) -> InputEventScreenDrag:
	var ev := InputEventScreenDrag.new()
	ev.position = pos
	ev.device = device
	ev.index = index
	return ev


## Zählt, wie oft die Geste über eine Event-Folge feuert (ein Frame je Event
## laut `frames`; Länge muss zur Event-Liste passen).
func _feuer(geste: InteractablesHost.TapGeste, events: Array, frames: Array) -> int:
	var n := 0
	for i in events.size():
		if geste.verarbeite(events[i], int(frames[i])):
			n += 1
	return n


# ── PT1-B2: Zwillings-Dedupe ─────────────────────────────────────────────────


func test_maus_plus_emulierter_touch_feuert_einmal() -> void:
	# Desktop (emulate_touch_from_mouse=true): EIN physischer Klick liefert
	# Maus-Press+Release UND den Touch-Zwilling mit DEVICE_ID_EMULATION.
	var geste := InteractablesHost.TapGeste.new()
	var events := [
		_maus(POS, true),
		_touch(POS, true, InputEvent.DEVICE_ID_EMULATION),
		_maus(POS, false),
		_touch(POS, false, InputEvent.DEVICE_ID_EMULATION),
	]
	var n := _feuer(geste, events, [4, 4, 4, 4])
	assert_eq(n, 1, "ein physischer Klick muss genau EIN on_tap auslösen")


func test_touch_plus_emulierte_maus_feuert_einmal() -> void:
	# Mobile (emulate_mouse_from_touch, Engine-Default): echter Touch plus
	# Maus-Zwilling mit DEVICE_ID_EMULATION.
	var geste := InteractablesHost.TapGeste.new()
	var events := [
		_touch(POS, true),
		_maus(POS, true, InputEvent.DEVICE_ID_EMULATION),
		_touch(POS, false),
		_maus(POS, false, InputEvent.DEVICE_ID_EMULATION),
	]
	var n := _feuer(geste, events, [7, 7, 7, 7])
	assert_eq(n, 1, "ein physischer Tipp muss genau EIN on_tap auslösen")


func test_frame_deckel_hoechstens_ein_feuer_pro_frame() -> void:
	# Netz zweiter Ordnung: kommen doch einmal ZWEI komplette Gesten im
	# selben Physik-Frame an, feuert nur die erste.
	var geste := InteractablesHost.TapGeste.new()
	var events := [
		_maus(POS, true),
		_maus(POS, false),
		_maus(POS, true),
		_maus(POS, false),
	]
	assert_eq(_feuer(geste, events, [5, 5, 5, 5]), 1, "gleicher Frame → ein Feuer")
	# Im nächsten Frame darf wieder gefeuert werden (echter zweiter Tap).
	assert_eq(_feuer(geste, events, [6, 6, 7, 7]), 2, "neue Frames → neue Taps")


# ── PT4-B3: Tap erst auf Release, Pan-Schwelle bricht ab ─────────────────────


func test_press_allein_feuert_nicht() -> void:
	var geste := InteractablesHost.TapGeste.new()
	assert_false(geste.verarbeite(_touch(POS, true), 1), "PRESS darf nie feuern")
	assert_false(geste.verarbeite(_maus(POS, true), 1), "PRESS darf nie feuern")


func test_press_move_ueber_schwelle_release_feuert_nicht() -> void:
	# Pan-Geste, die AUF dem Interactable startet: Drag über die Schwelle
	# bricht den Tap ab — auch wenn der Finger zurückkehrt und dort loslässt.
	var geste := InteractablesHost.TapGeste.new()
	var weit := POS + Vector2(HomeCameraRig.PAN_DEADZONE_PX + 4.0, 0.0)
	var events := [_touch(POS, true), _drag(weit), _drag(POS), _touch(POS, false)]
	assert_eq(_feuer(geste, events, [1, 2, 3, 4]), 0, "Pan darf kein Tap sein")


func test_release_weit_weg_feuert_nicht_ohne_zwischendrags() -> void:
	# Während eines aktiven Pans verschluckt der Kamera-Rig die Drags
	# (set_input_as_handled) — die Zone sieht nur Press+fernes Release und
	# muss die Distanz am Release selbst messen (Maus- und Touch-Pfad).
	var geste := InteractablesHost.TapGeste.new()
	var weit := POS + Vector2(0.0, HomeCameraRig.PAN_DEADZONE_PX * 3.0)
	assert_eq(_feuer(geste, [_maus(POS, true), _maus(weit, false)], [1, 2]), 0)
	assert_eq(_feuer(geste, [_touch(POS, true), _touch(weit, false)], [3, 4]), 0)


func test_press_release_unter_schwelle_feuert_einmal() -> void:
	# Tap mit kleinem Finger-Wackler (< Schwelle) feuert genau einmal.
	var geste := InteractablesHost.TapGeste.new()
	var wackler := POS + Vector2(3.0, 2.0)
	var events := [_touch(POS, true), _drag(wackler), _touch(wackler, false)]
	assert_eq(_feuer(geste, events, [1, 2, 3]), 1, "kleiner Wackler bleibt ein Tap")


func test_schwelle_ist_pan_deadzone() -> void:
	# Exakt AUF der Schwelle beginnt der Boden-Pan (pan_gesture_ready) —
	# der Tap muss dort abbrechen, sonst feuern Pan UND Tap zugleich.
	var geste := InteractablesHost.TapGeste.new()
	var kante := POS + Vector2(HomeCameraRig.PAN_DEADZONE_PX, 0.0)
	assert_eq(_feuer(geste, [_touch(POS, true), _touch(kante, false)], [1, 2]), 0)
	var knapp := POS + Vector2(HomeCameraRig.PAN_DEADZONE_PX - 0.5, 0.0)
	assert_eq(_feuer(geste, [_touch(POS, true), _touch(knapp, false)], [3, 4]), 1)


func test_canceled_release_feuert_nicht() -> void:
	var geste := InteractablesHost.TapGeste.new()
	var ab := _touch(POS, false)
	ab.canceled = true
	assert_false(geste.verarbeite(_touch(POS, true), 1))
	assert_false(geste.verarbeite(ab, 2), "vom OS abgebrochener Touch feuert nicht")


func test_rechte_maustaste_feuert_nicht() -> void:
	var geste := InteractablesHost.TapGeste.new()
	var runter := _maus(POS, true)
	runter.button_index = MOUSE_BUTTON_RIGHT
	var hoch := _maus(POS, false)
	hoch.button_index = MOUSE_BUTTON_RIGHT
	assert_eq(_feuer(geste, [runter, hoch], [1, 2]), 0, "nur links tippt (wie der Pan)")


func test_zweiter_finger_wird_ignoriert() -> void:
	# Kinder-Doppelgriff: Finger 2 während der Geste ändert nichts, Finger 1
	# behält Vorrang — genau EIN Feuer.
	var geste := InteractablesHost.TapGeste.new()
	var events := [
		_touch(POS, true, 0, 0),
		_touch(POS + Vector2(60, 0), true, 0, 1),
		_touch(POS + Vector2(64, 0), false, 0, 1),
		_touch(POS + Vector2(2, 1), false, 0, 0),
	]
	assert_eq(_feuer(geste, events, [1, 2, 3, 4]), 1, "Doppelgriff bleibt EIN Tap")


# ── PT1-B2: Wiedereintritts-Sperre (busy-Flag im Host) ───────────────────────


func test_laufende_sequenz_blockt_zweiten_tap() -> void:
	var raum := RaumStub.new()
	var gooby := GoobyStub.new()
	raum.stub_gooby = gooby
	raum.add_child(gooby)
	var host := InteractablesHost.new()
	raum.add_child(host)
	var area := Area3D.new()
	host.add_child(area)
	var fremde_area := Area3D.new()
	raum.add_child(fremde_area)
	tree.root.add_child(raum)

	var starts := {"n": 0}
	var sequenz_start := func() -> void:
		starts["n"] += 1
		# Die Sequenz kommandiert Gooby — wie klo_dusche:
		# set_wander_enabled(false) + await walk_to.
		gooby.scripted = true
		gooby.wander = false
	var geste := InteractablesHost.TapGeste.new()

	# Tap 1 startet die Sequenz (Press+Release, Frame 1).
	InteractablesHost.handle_tap_event(area, geste, _maus(POS, true), 1, sequenz_start)
	InteractablesHost.handle_tap_event(area, geste, _maus(POS, false), 1, sequenz_start)
	assert_eq(starts["n"], 1, "erster Tap startet die Sequenz")
	assert_true(host.is_tap_busy(), "während des Skript-Laufs ist der Host busy")

	# Tap 2 (echter Doppel-Tipp während des Anlaufs): gesperrt.
	InteractablesHost.handle_tap_event(area, geste, _maus(POS, true), 2, sequenz_start)
	InteractablesHost.handle_tap_event(area, geste, _maus(POS, false), 2, sequenz_start)
	assert_eq(starts["n"], 1, "zweiter Tap darf während des Anlaufs nichts starten")

	# Auch Tap-Flächen OHNE Host-Vorfahr (Türen) sind über den Raum gesperrt.
	var tuer_geste := InteractablesHost.TapGeste.new()
	var tuer_taps := {"n": 0}
	var tuer_tap := func() -> void: tuer_taps["n"] += 1
	InteractablesHost.handle_tap_event(fremde_area, tuer_geste, _maus(POS, true), 3, tuer_tap)
	InteractablesHost.handle_tap_event(fremde_area, tuer_geste, _maus(POS, false), 3, tuer_tap)
	assert_eq(tuer_taps["n"], 0, "fremde Zonen starten während der Sequenz nichts")

	# Anlauf fertig (walk_to kehrte zurück, Wandern bleibt bis zum Routine-
	# Ende aus): der nächste Tap darf wieder — so bleibt der Abspül-Tap der
	# Dusche während der laufenden Routine möglich.
	gooby.scripted = false
	assert_false(host.is_tap_busy(), "ohne Skript-Lauf ist der Host frei")
	InteractablesHost.handle_tap_event(area, geste, _maus(POS, true), 4, sequenz_start)
	InteractablesHost.handle_tap_event(area, geste, _maus(POS, false), 4, sequenz_start)
	assert_eq(starts["n"], 2, "nach dem Anlauf sind Taps wieder erlaubt")

	raum.free()


func test_ambienter_lauf_sperrt_nicht() -> void:
	# Seelen-Gruß/Absicht/Komm-her: Skript-Lauf MIT eingeschaltetem Wandern
	# — Taps müssen durch, sonst schluckt Goobys Schlendern Tür-Taps.
	var raum := RaumStub.new()
	var gooby := GoobyStub.new()
	raum.stub_gooby = gooby
	raum.add_child(gooby)
	var area := Area3D.new()
	raum.add_child(area)
	tree.root.add_child(raum)
	gooby.scripted = true
	gooby.wander = true
	assert_false(InteractablesHost.is_tap_blocked(area), "ambienter Lauf sperrt nicht")
	raum.free()


func test_ohne_raum_ist_nichts_gesperrt() -> void:
	# Zonen außerhalb eines Raums (kein gooby()-Vorfahr) bleiben frei.
	var solo := Area3D.new()
	tree.root.add_child(solo)
	assert_false(InteractablesHost.is_tap_blocked(solo))
	solo.free()


func test_make_tap_area_baut_zone_wie_bisher() -> void:
	# Regression für den Umbau: Box um die Möbel-AABB + Ray-Pickable bleiben.
	var moebel := Node3D.new()
	tree.root.add_child(moebel)
	var area := InteractablesHost.make_tap_area(moebel, func() -> void: pass)
	moebel.add_child(area)
	assert_true(area.input_ray_pickable, "Zone muss ray-pickable bleiben")
	var shape := area.get_child(0) as CollisionShape3D
	assert_true(shape != null and shape.shape is BoxShape3D, "Box-Shape fehlt")
	moebel.free()

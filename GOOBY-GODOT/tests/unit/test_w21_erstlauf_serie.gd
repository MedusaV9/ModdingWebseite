extends TestCase
## W21 P1 — ERSTLAUF-SERIALISIERUNGS-VERTRAG (Readiness-Blocker #1, Befund
## „Overlay-Chaos aus 4 Schichten": Sticker-Toast, Sprechblasen, Coachmark
## und Tagesbonus stapelten sich beim ersten Heimkommen gleichzeitig):
## (a) SYNTHETISCHE ERSTLAUF-SALVE: zwei Willkommens-Overlays (Tagesbonus/
##     Coachmark-Proben) beim Dirigenten UND vier Toasts über ZWEI
##     Service-ToastLayer (RewardHub-/QuestService-Montage) gleichzeitig —
##     an JEDEM Frame gilt: höchstens 1 Overlay UND höchstens 1 Toast
##     sichtbar (globale Toast-Lane, toast.gd), mit Atempausen; am Ende
##     wurde trotzdem JEDE Meldung gezeigt (nichts verschluckt).
## (b) FEIER-GATE: die Sticker-Feier des RewardHub (Toast + Konfetti +
##     Jubel) wartet, bis der Dirigent seine Willkommens-Sequenz beendet
##     hat — der Sticker-Toast lag sonst AUF dem Tagesbonus-Blatt.
## Zeit: Dirigent wird mit festen Deltas gepumpt (tick), die Toast-
## Standzeit ist injiziert (hold_sec) — kein Echtzeit-Flake über HOLD_SEC.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const NOW_MS := 1785448800000  # 2026-07-30 UTC
const TICK := 0.05
const KURZE_STANDZEIT := 0.15
const SALVE_A: Array[String] = ["Sticker verdient: Sonnenblume!", "Abzeichen verdient: Frühstück!"]
const SALVE_B: Array[String] = ["Tagesquest geschafft: +40 Münzen!", "Neue Quest verfügbar!"]

var _seq := 0
var _overlays: Dictionary = {}


func _frisches_gs() -> Node:
	_seq += 1
	var dir := "user://w21_erstlauf_tests/gs_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	tree.root.add_child(gs)
	gs.apply_onboarding_profile({"player_name": "Tester", "gooby_nickname": "Flauschi"})
	return gs


## Service-Montage wie reward_hub/quest_service._ready (CanvasLayer + Layer).
func _service_toasts(name_suffix: String) -> Array:
	var layer := CanvasLayer.new()
	layer.layer = 60
	tree.root.add_child(layer)
	var toasts := ToastLayer.new()
	toasts.name = "ServiceToasts" + name_suffix
	toasts.theme = ThemeService.theme()
	toasts.set_anchors_preset(Control.PRESET_FULL_RECT)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.hold_sec = KURZE_STANDZEIT
	layer.add_child(toasts)
	return [layer, toasts]


## Öffnen-Pfad einer Overlay-Probe (Vollbild-STOP wie der Tagesbonus).
func _oeffne_probe(id: String) -> Control:
	var overlay := ColorRect.new()
	overlay.name = "Probe_" + id
	overlay.color = Color(0.0, 0.0, 0.0, 0.2)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(overlay)
	_overlays[id] = overlay
	return overlay


func _sichtbare_probes() -> int:
	var n := 0
	for id: String in _overlays:
		var overlay: Variant = _overlays[id]
		# is_instance_valid ZUERST — `is` wirft auf hart gefreiten Instanzen
		# einen SCRIPT ERROR (gleiche Lehre wie UiAnchors._prune).
		if not is_instance_valid(overlay):
			continue
		if overlay is Control and (overlay as Control).is_visible_in_tree():
			n += 1
	return n


func _sichtbare_toasts() -> int:
	var n := 0
	for node: Node in tree.get_nodes_in_group(ToastLayer.GROUP):
		if node is ToastLayer and (node as ToastLayer).is_showing():
			n += 1
	return n


func _set_reduced_motion(an: bool) -> bool:
	var svc := tree.root.get_node_or_null("/root/UiTheme")
	if svc == null:
		return false
	var vorher: bool = svc.reduced_motion
	svc.reduced_motion = an
	return vorher


func test_erstlauf_salve_max_ein_overlay_und_ein_toast() -> void:
	_overlays.clear()
	var rm_vorher := _set_reduced_motion(true)
	var host := Node.new()
	tree.root.add_child(host)
	var dirigent := OverlayDirigent.attach_to(host)
	dirigent.set_process(false)
	var paar_a := _service_toasts("A")
	var paar_b := _service_toasts("B")
	var toasts_a := paar_a[1] as ToastLayer
	var toasts_b := paar_b[1] as ToastLayer
	await wait_frames(1)
	# DIE Salve: alles meldet sich im selben Frame (der Chaos-Screenshot).
	dirigent.anfordern("tagesbonus", OverlayDirigent.PRIO_TAGESBONUS, _oeffne_probe.bind("bonus"))
	dirigent.anfordern("coachmark", OverlayDirigent.PRIO_COACHMARK, _oeffne_probe.bind("coach"))
	for text: String in SALVE_A:
		toasts_a.show_toast(text)
	for text: String in SALVE_B:
		toasts_b.show_toast(text)
	# Sequenz abspielen: Dirigent mit festem Delta pumpen, Overlays leben
	# je ~8 Frames (Nutzer tippt weg), Toasts takten über hold_sec.
	var gezeigt: Dictionary = {}
	var offen_seit: Dictionary = {}
	var deadline := Time.get_ticks_msec() + 15_000
	while Time.get_ticks_msec() < deadline:
		dirigent.tick(TICK)
		await wait_frames(1)
		assert_true(_sichtbare_probes() <= 1, "nie zwei Willkommens-Overlays gleichzeitig")
		assert_true(_sichtbare_toasts() <= 1, "nie zwei Toasts gleichzeitig (globale Lane)")
		for layer: ToastLayer in [toasts_a, toasts_b]:
			if layer.is_showing():
				gezeigt[layer.queue.current()] = true
		for id: String in _overlays:
			var overlay: Variant = _overlays[id]
			if not is_instance_valid(overlay):
				continue
			offen_seit[id] = int(offen_seit.get(id, 0)) + 1
			if int(offen_seit[id]) >= 8:
				(overlay as Control).queue_free()
		var fertig := (
			not dirigent.belegt()
			and toasts_a.queue.is_idle()
			and toasts_b.queue.is_idle()
			and _sichtbare_toasts() == 0
		)
		if fertig:
			break
	assert_false(dirigent.belegt(), "Willkommens-Sequenz kam komplett durch")
	assert_true(toasts_a.queue.is_idle() and toasts_b.queue.is_idle(), "beide Queues geleert")
	for text: String in SALVE_A + SALVE_B:
		assert_true(gezeigt.has(text), "Toast „%s“ wurde gezeigt (nichts verschluckt)" % text)
	paar_a[0].free()
	paar_b[0].free()
	host.free()
	_set_reduced_motion(rm_vorher)
	await wait_frames(1)


func test_sticker_feier_wartet_auf_die_willkommens_sequenz() -> void:
	_overlays.clear()
	var rm_vorher := _set_reduced_motion(true)
	var gs := _frisches_gs()
	var host := Node.new()
	tree.root.add_child(host)
	var dirigent := OverlayDirigent.attach_to(host)
	dirigent.set_process(false)
	var hub := RewardHub.attach_to(host, gs)
	hub._toasts.hold_sec = KURZE_STANDZEIT
	hub.feier_abstand_s = 0.05
	await wait_frames(1)
	# Der frische Save schaltet beim Attach ggf. sofort Sticker/Erfolge
	# frei — diese Feiern erst austakten lassen: der Vertrag hier misst
	# NUR die Probe-Feier gegen das Willkommens-Overlay.
	var start_leer := await wait_until(
		func() -> bool: return not hub._draining and not hub._toasts.is_showing(), 8000
	)
	assert_true(start_leer, "Attach-Feiern ausgetaktet (Vorbedingung)")
	# Das ECHTE Tagesbonus-Ticket des Hubs (deferred, mit Gruß-Vorlauf)
	# zurückziehen — sein DailyBonusPopup bräuchte einen Nutzer-Claim und
	# hielte den Dirigenten ewig belegt; die Probe unten ist der Overlay-
	# Stellvertreter mit deterministischer Lebenszeit.
	dirigent.zurueckziehen("tagesbonus")
	# Willkommens-Overlay ist offen (Tagesbonus-Probe) …
	dirigent.anfordern("bonus", OverlayDirigent.PRIO_TAGESBONUS, _oeffne_probe.bind("bonus"))
	dirigent.tick(TICK)
	assert_eq(_sichtbare_probes(), 1, "Vorbedingung: Willkommens-Overlay sichtbar")
	# … und MITTEN darin schaltet ein Sticker frei (der Erstlauf-Fall).
	hub._on_sticker_unlocked({"id": "probe", "name_de": "Probe", "rarity": "haeufig", "page": ""})
	# Feier-Gate: solange der Dirigent belegt ist, KEIN Feier-Toast (das
	# Gate pollt alle 0,25 s — 0,6 s Echtzeit decken mehrere Runden).
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 600:
		await wait_frames(1)
		assert_false(
			hub._toasts.is_showing(), "Feier-Toast wartet, solange das Willkommens-Overlay lebt"
		)
	# Overlay zu → Sequenz fertig → die Feier darf auf die Bühne.
	var probe: Control = _overlays["bonus"]
	probe.queue_free()
	dirigent.tick(TICK)
	dirigent.tick(dirigent.pause_s + 0.1)
	var gezeigt := await wait_until(func() -> bool: return hub._toasts.is_showing(), 3000)
	assert_true(gezeigt, "nach der Sequenz kommt der Feier-Toast durch")
	# Toast austakten lassen, damit die globale Lane sauber freigegeben ist.
	await wait_until(func() -> bool: return not hub._toasts.is_showing(), 3000)
	host.free()
	gs.get_parent().remove_child(gs)
	gs.free()
	_set_reduced_motion(rm_vorher)
	await wait_frames(1)

extends TestCase
## W18/J1 — Wächter für den Overlay-Dirigenten (Playtest-Befund E4
## „Overlay-Stau“: Tagesbonus ÜBER Guide-Karte ÜBER Coachmark, der kaum
## sichtbare Tagesbonus-Schleier schluckte Taps):
## (a) zwei gleichzeitig angeforderte Overlays laufen NACHEINANDER (mit
##     kleiner Pause), nie überlappend sichtbar+blockierend; Priorität
##     schlägt Meldereihenfolge; pro id höchstens ein Ticket.
## (b) Tagesstart-Sequenz deterministisch (Clock injiziert, AGENTS.md):
##     erst das Begrüßungs-Fenster (Vorlauf, KEIN Popup), dann das
##     Tagesbonus-Blatt; Claim bucht exakt die Serien-Belohnung; am selben
##     Tag kein zweites Angebot, am nächsten (Clock.advance) wieder eins.
## (c) die Guide-/Tour-Karte duckt sich, solange der Dirigent belegt ist,
##     und kommt nach der Sequenz von selbst zurück.
## (d) der HUD-Coachmark (hud.gd = fremde Zone) wird von außen geparkt und
##     an seiner Reihe wieder aufgefedert.
## Der Dirigent läuft in allen Tests mit set_process(false) und wird mit
## festen Deltas über tick() gepumpt — kein Echtzeit-Flake.

const GameStateScript := preload("res://scripts/state/game_state.gd")

## 2026-07-30 UTC (Muster test_w18_guide_karte) — Clock immer gepinnt.
const NOW_MS := 1785448800000
const TAG_MS := 86_400_000
const TICK := 0.016

var _seq := 0
var _overlays: Dictionary = {}


func _frisches_gs() -> Node:
	_seq += 1
	var dir := "user://overlay_dirigent_tests/gs_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	tree.root.add_child(gs)
	gs.apply_onboarding_profile({"player_name": "Tester", "gooby_nickname": "Flauschi"})
	return gs


## Dirigent mit abgeschaltetem _process — Tests pumpen tick() selbst.
func _dirigent(host: Node) -> OverlayDirigent:
	var dirigent := OverlayDirigent.attach_to(host)
	dirigent.set_process(false)
	return dirigent


## Öffnen-Pfad einer Probe: Vollbild-STOP-Control (blockierend wie der
## Tagesbonus-Schleier), merkt sich unter `id` in _overlays.
func _oeffne_probe(id: String) -> Control:
	var overlay := ColorRect.new()
	overlay.name = "Probe_" + id
	overlay.color = Color(0.0, 0.0, 0.0, 0.2)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(overlay)
	_overlays[id] = overlay
	return overlay


func _probe(id: String) -> Control:
	var overlay: Variant = _overlays.get(id)
	return overlay if overlay is Control and is_instance_valid(overlay) else null


func _blockiert_sichtbar(id: String) -> bool:
	var overlay := _probe(id)
	return overlay != null and overlay.is_visible_in_tree()


## Lebendes Tagesbonus-Popup des Hubs (null = keins/inzwischen gefreit —
## der Hub lässt die Referenz nach queue_free bewusst stehen, alle
## Produktiv-Pfade prüfen is_instance_valid).
func _hub_popup(hub: RewardHub) -> Control:
	var popup: Object = hub._daily_popup
	if popup == null or not is_instance_valid(popup):
		return null
	return popup as Control


# ── (a) Nacheinander statt Stau ───────────────────────────────────────────────


func test_zwei_overlays_nacheinander_nie_gleichzeitig() -> void:
	_overlays.clear()
	var host := Node.new()
	tree.root.add_child(host)
	var dirigent := _dirigent(host)
	var protokoll: Array[String] = []
	dirigent.overlay_gestartet.connect(func(id: String) -> void: protokoll.append("start:" + id))
	dirigent.overlay_fertig.connect(func(id: String) -> void: protokoll.append("fertig:" + id))
	dirigent.anfordern("a", 10, _oeffne_probe.bind("a"))
	dirigent.anfordern("b", 10, _oeffne_probe.bind("b"))
	dirigent.tick(TICK)
	assert_true(_blockiert_sichtbar("a"), "erstes Ticket öffnet zuerst")
	assert_eq(dirigent.aktiv_id(), "a", "aktiv_id meldet das offene Overlay")
	# Solange A lebt, darf B nie aufgehen — egal wie viele Takte vergehen.
	for _i in 8:
		dirigent.tick(0.25)
		assert_false(
			_blockiert_sichtbar("a") and _blockiert_sichtbar("b"),
			"nie zwei Overlays gleichzeitig sichtbar+blockierend"
		)
		assert_eq(_probe("b"), null, "B wartet, solange A offen ist")
	var probe_a := _probe("a")
	probe_a.queue_free()
	dirigent.tick(TICK)
	assert_eq(_probe("b"), null, "kleine Atempause: B kommt nicht im Schließ-Takt")
	assert_true(dirigent.belegt(), "Sequenz läuft noch (B-Ticket offen)")
	dirigent.tick(0.2)
	assert_eq(_probe("b"), null, "Pause (%.2f s) noch nicht um" % dirigent.pause_s)
	dirigent.tick(0.3)
	assert_true(_blockiert_sichtbar("b"), "nach der Pause ist B dran")
	_probe("b").queue_free()
	dirigent.tick(TICK)
	assert_false(dirigent.belegt(), "Sequenz fertig — Dirigent frei")
	assert_eq(
		protokoll,
		["start:a", "fertig:a", "start:b", "fertig:b"],
		"Reihenfolge im Protokoll: a komplett vor b"
	)
	await wait_frames(2)
	host.free()
	await wait_frames(1)


func test_prioritaet_dedupe_und_zurueckziehen() -> void:
	_overlays.clear()
	var host := Node.new()
	tree.root.add_child(host)
	var dirigent := _dirigent(host)
	# Coachmark meldet sich ZUERST, Tagesbonus danach — Priorität gewinnt.
	dirigent.anfordern("coach", OverlayDirigent.PRIO_COACHMARK, _oeffne_probe.bind("coach"))
	dirigent.anfordern("bonus", OverlayDirigent.PRIO_TAGESBONUS, _oeffne_probe.bind("bonus"))
	dirigent.anfordern("bonus", OverlayDirigent.PRIO_TAGESBONUS, _oeffne_probe.bind("bonus"))
	assert_eq(dirigent._queue.size(), 2, "pro id höchstens ein Ticket (Dedupe)")
	dirigent.tick(TICK)
	assert_true(_blockiert_sichtbar("bonus"), "Tagesbonus-Priorität schlägt Meldereihenfolge")
	assert_eq(_probe("coach"), null, "Coachmark wartet hinter dem Bonus")
	# Reiseantritt-Fall: das wartende Coach-Ticket wird zurückgezogen.
	dirigent.zurueckziehen("coach")
	_probe("bonus").queue_free()
	dirigent.tick(TICK)
	dirigent.tick(1.0)
	assert_eq(_probe("coach"), null, "zurückgezogenes Ticket öffnet nie")
	assert_false(dirigent.belegt(), "Warteschlange leer nach Rückzug")
	await wait_frames(2)
	host.free()
	await wait_frames(1)


func test_reise_sperre_sammelt_ankunfts_tickets() -> void:
	# Playtest-Befund (flow_morgen_ritual): der Coachmark entsteht schon
	# WÄHREND der Reise (HUD-Einblendung), das Tagesbonus-Ticket kommt erst
	# mit travel_finished — ohne Sperre öffnete der Coachmark sofort in der
	# leeren Lücke und das Blatt hing ewig hinter ihm. Die Ankunft ist der
	# Sammelpunkt: unterwegs öffnet NICHTS, danach gewinnt die Priorität.
	_overlays.clear()
	var host := Node.new()
	tree.root.add_child(host)
	var dirigent := _dirigent(host)
	dirigent._on_travel_started()
	dirigent.anfordern("coach", OverlayDirigent.PRIO_COACHMARK, _oeffne_probe.bind("coach"))
	for _i in 5:
		dirigent.tick(1.0)
	assert_eq(_probe("coach"), null, "Reise-Sperre: unterwegs öffnet nichts")
	assert_true(dirigent.belegt(), "Ticket bleibt eingereiht (Guide-Karte duckt)")
	dirigent._on_travel_finished()
	dirigent.anfordern("bonus", OverlayDirigent.PRIO_TAGESBONUS, _oeffne_probe.bind("bonus"), 0.5)
	dirigent.tick(TICK)
	assert_eq(_probe("bonus"), null, "Bonus-Vorlauf armiert (Gruß-Fenster zuerst)")
	assert_eq(_probe("coach"), null, "Coachmark wartet hinter dem Bonus")
	dirigent.tick(0.6)
	assert_true(_blockiert_sichtbar("bonus"), "nach Ankunft + Vorlauf: Bonus zuerst")
	assert_eq(_probe("coach"), null, "Coachmark noch nicht dran")
	_probe("bonus").queue_free()
	dirigent.tick(TICK)
	dirigent.tick(dirigent.pause_s + 0.1)
	assert_true(_blockiert_sichtbar("coach"), "nach dem Bonus ist der Coachmark dran")
	_probe("coach").queue_free()
	dirigent.tick(TICK)
	assert_false(dirigent.belegt(), "Sequenz fertig")
	await wait_frames(2)
	host.free()
	await wait_frames(1)


# ── (b) Tagesstart deterministisch (Clock injiziert) ─────────────────────────


func test_tagesstart_sequenz_deterministisch_mit_clock() -> void:
	PanelStack.clear()
	var gs := _frisches_gs()
	var host := Node.new()
	tree.root.add_child(host)
	var dirigent := _dirigent(host)
	var hub := RewardHub.attach_to(host, gs)
	await wait_frames(1)
	# Ankunft im Raum: das Angebot geht als Ticket MIT Vorlauf ein —
	# im Begrüßungs-Fenster gehört die Bühne Gooby, KEIN Popup.
	hub._on_travel_finished()
	assert_true(dirigent.belegt(), "Ticket eingereiht (Sequenz läuft)")
	assert_eq(_hub_popup(hub), null, "Begrüßung zuerst: noch kein Popup")
	dirigent.tick(TICK)
	dirigent.tick(RewardHub.MORGEN_GRUSS_S - 0.1)
	assert_eq(_hub_popup(hub), null, "Gruß-Vorlauf noch nicht um — Popup wartet")
	dirigent.tick(0.2)
	var popup := _hub_popup(hub)
	assert_ne(popup, null, "nach dem Gruß-Vorlauf gleitet das Blatt rein")
	assert_true(is_instance_valid(popup) and popup.visible, "Popup sichtbar")
	assert_eq(dirigent.aktiv_id(), "tagesbonus", "Dirigent führt das Blatt als aktiv")
	await wait_frames(1)
	# Claim: exakt Serientag 1 (REWARD_TABLE[0] = 20) am gepinnten Tag.
	var tag1: String = gs.clock.local_day()
	var coins_vorher := int(gs.get_value("economy.coins", 0))
	popup._on_claim()
	assert_eq(int(gs.get_value("economy.coins", 0)), coins_vorher + 20, "Tag 1 bucht +20")
	assert_eq(str(gs.get_value("daily.lastClaimDay", "")), tag1, "lastClaimDay = Clock-Tag")
	assert_eq(int(gs.get_value("daily.streak", 0)), 1, "Serie startet bei 1")
	await wait_frames(2)
	dirigent.tick(TICK)
	assert_false(dirigent.belegt(), "Sequenz nach dem Claim beendet")
	# Gleicher Tag: kein zweites Angebot (deterministisch über die Clock).
	hub._maybe_offer_daily_bonus()
	assert_false(dirigent.belegt(), "heute kein zweites Ticket")
	# Nächster Tag (Clock.advance statt OS-Uhr): Angebot kommt wieder,
	# wieder erst nach Atempause + Begrüßungs-Vorlauf, und zahlt Serientag 2.
	gs.clock.advance(TAG_MS)
	hub._maybe_offer_daily_bonus()
	assert_true(dirigent.belegt(), "Tag 2: neues Ticket")
	assert_eq(_hub_popup(hub), null, "Tag 2: Begrüßung wieder zuerst")
	# Rest-Atempause der Vortags-Sequenz abtakten, dann armiert das Ticket
	# seinen Gruß-Vorlauf — erst NACH dessen Ablauf gleitet das Blatt rein.
	dirigent.tick(TICK)
	dirigent.tick(dirigent.pause_s)
	assert_eq(_hub_popup(hub), null, "Tag 2: Vorlauf armiert, noch kein Blatt")
	dirigent.tick(RewardHub.MORGEN_GRUSS_S - 0.1)
	assert_eq(_hub_popup(hub), null, "Tag 2: Gruß-Fenster läuft noch")
	dirigent.tick(0.2)
	var popup2 := _hub_popup(hub)
	assert_ne(popup2, null, "Tag 2: Blatt kommt nach dem Vorlauf")
	await wait_frames(1)
	var tag2: String = gs.clock.local_day()
	assert_ne(tag2, tag1, "Clock.advance wechselt den Kalendertag")
	coins_vorher = int(gs.get_value("economy.coins", 0))
	popup2._on_claim()
	assert_eq(int(gs.get_value("economy.coins", 0)), coins_vorher + 30, "Tag 2 bucht +30")
	assert_eq(int(gs.get_value("daily.streak", 0)), 2, "Serie zählt weiter")
	assert_eq(str(gs.get_value("daily.lastClaimDay", "")), tag2, "Stempel = neuer Clock-Tag")
	await wait_frames(2)
	PanelStack.clear()
	host.free()
	gs.get_parent().remove_child(gs)
	gs.free()
	await wait_frames(1)


# ── (c) Guide-Karte duckt sich, solange der Dirigent belegt ist ──────────────


func test_guide_karte_duckt_sich_waehrend_sequenz() -> void:
	_overlays.clear()
	var gs := _frisches_gs()
	var router := tree.root.get_node_or_null("SceneRouter")
	var szene_vorher: Node = null
	var raum := RoomBase.new()
	if router != null:
		szene_vorher = router.get_current_scene()
		router._current_scene = raum
	var host := Node.new()
	tree.root.add_child(host)
	var dirigent := _dirigent(host)
	var guide := OnboardingGuide.attach_to(host, gs)
	assert_ne(guide, null, "frischer Save startet die Tour")
	await wait_frames(3)
	var karte: Control = guide._card
	assert_true(karte.visible, "freier Dirigent: Tour-Karte zeigt")
	# Ein Willkommens-Overlay geht auf → die Karte duckt sich sofort.
	dirigent.anfordern("probe", 10, _oeffne_probe.bind("probe"))
	dirigent.tick(TICK)
	await wait_frames(2)
	assert_false(guide._karte_erlaubt(), "belegt → Karte nicht erlaubt")
	assert_false(karte.visible, "belegt → Karte geduckt (kein Stau über dem Blatt)")
	# Overlay zu → Sequenz leer → die Karte kommt von selbst zurück.
	_probe("probe").queue_free()
	dirigent.tick(TICK)
	await wait_frames(2)
	assert_true(guide._karte_erlaubt(), "frei → Karte wieder erlaubt")
	assert_true(karte.visible, "frei → Karte kehrt von selbst zurück")
	if router != null:
		router._current_scene = szene_vorher
	raum.free()
	host.free()
	gs.get_parent().remove_child(gs)
	gs.free()
	await wait_frames(1)


# ── (d) Coachmark-Beobachtung (hud.gd bleibt unangetastet) ───────────────────


func test_coachmark_wird_geparkt_und_kommt_an_seine_reihe() -> void:
	_overlays.clear()
	var host := Node.new()
	tree.root.add_child(host)
	var dirigent := _dirigent(host)
	# Erst ist der Tagesbonus dran (aktiv), DANN taucht der Coachmark auf.
	dirigent.anfordern("bonus", OverlayDirigent.PRIO_TAGESBONUS, _oeffne_probe.bind("bonus"))
	dirigent.tick(TICK)
	assert_true(_blockiert_sichtbar("bonus"), "Vorbedingung: Bonus-Overlay aktiv")
	var hud_stub := Control.new()
	hud_stub.name = "HudStub"
	hud_stub.add_to_group(&"hud")
	tree.root.add_child(hud_stub)
	var coachmark := PanelContainer.new()
	coachmark.name = "HudCoachmark"
	hud_stub.add_child(coachmark)
	dirigent.tick(TICK)
	assert_false(coachmark.visible, "Coachmark wird unsichtbar geparkt (kein Stau)")
	assert_true(dirigent.belegt(), "Coachmark-Ticket ist eingereiht")
	# Bonus zu → Pause → der Coachmark federt an seiner Reihe wieder auf.
	_probe("bonus").queue_free()
	dirigent.tick(TICK)
	assert_false(coachmark.visible, "Atempause: Coachmark noch geparkt")
	dirigent.tick(dirigent.pause_s + 0.1)
	assert_true(coachmark.visible, "an seiner Reihe: Coachmark sichtbar")
	assert_eq(dirigent.aktiv_id(), "coachmark", "Dirigent führt den Coachmark als aktiv")
	# „Alles klar!“ = queue_free (bestehender Schließ-Pfad des HUD).
	coachmark.queue_free()
	dirigent.tick(TICK)
	assert_false(dirigent.belegt(), "nach dem Wegtippen ist die Sequenz leer")
	await wait_frames(2)
	hud_stub.free()
	host.free()
	await wait_frames(1)

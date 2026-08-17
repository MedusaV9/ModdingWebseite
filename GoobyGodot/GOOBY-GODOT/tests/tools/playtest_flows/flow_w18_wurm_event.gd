extends "res://tests/tools/playtest_flows/flow_basis.gd"
## Flow „W18/E3 Wurm-Event Herbert“ (Beweis-Lauf für die E3-Fixes):
## Onboarding → Wurm-Event deterministisch aktivieren + stagen (Runner-API
## `start()`, wie der Szenen-Aufbau via setup) → HOCHKANT liegt die
## Choice-Karte in der Bubble-Lane ÜBER dem HUD-Dock (E3a) → Tür in die
## Küche → Reiseantritt räumt Event-UI + Pose ab, die Küche stagt NICHT
## (Event bleibt aktiv, gepinnt an living; E3b) → zurück ins Wohnzimmer →
## die Szene steht WIEDER (Rückbesuch bietet das Event erneut an).
## Format: HOCH 1320x2868 (BxH beim Aufruf zwingend mitgeben).
## Aufruf: tools/ci/run_playtest.sh flow_w18_wurm_event 1320x2868


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append_array(
			[
				{
					"name": "was_nun_wegtippen",
					"aktion": "tipp_falls_da",
					"node": "WasNunSchliessen",
					"timeout_s": 8.0,
					"pflicht": false,
				},
				{
					"name": "wurm_event_aktivieren",
					"aktion": "tue",
					"funktion": wurm_aktivieren,
					"erwartung": "wurm_freund aktiv + Szene im Wohnzimmer gestagt",
				},
				{"name": "wurm_szene_ansehen", "aktion": "warte", "sekunden": 3.0},
				{
					"name": "choice_karte_ueber_dock",
					"aktion": "warte_bis",
					"bedingung": karte_ueber_dock,
					"timeout_s": 20.0,
					"erwartung": "Choice-Karte liegt hochkant ÜBER der HUD-Lane (E3a)",
				},
				{
					"name": "tuer_zur_kueche_tippen",
					"aktion": "tipp_3d",
					"finder": finde_tuer.bind("kitchen"),
					"offset": Vector3(0.0, 1.0, 0.0),
					"erwarte": {"text": "Los!"},
					"timeout_s": 45.0,
				},
				{
					"name": "tuer_bestaetigen",
					"aktion": "tipp_text",
					"text": "Los!",
					"erwarte": {"route": "home/kitchen"},
					"timeout_s": 120.0,
					"nebenbei_tipp_klasse": "TapMashOverlay",
				},
				{"name": "kueche_ankommen", "aktion": "warte", "sekunden": 3.0},
				{
					"name": "kueche_ohne_event_ui",
					"aktion": "warte_bis",
					"bedingung": event_ui_weg,
					"timeout_s": 20.0,
					"erwartung": "keine Choice-Karte mehr im Baum (E3b: Abbruch räumt auf)",
				},
				{
					"name": "kueche_stagt_nicht",
					"aktion": "tue",
					"funktion": kueche_stagt_nicht,
					"erwartung": "Küchen-Runner läuft NICHT; Event aktiv + an living gepinnt",
				},
				# Rückreise über den Router (die Küchen-Rücktür liegt hochkant
				# außerhalb des Kamera-Ausschnitts — gleicher goto wie die
				# Tür-Bestätigung, travel_started/Neuaufbau identisch).
				{
					"name": "zurueck_ins_wohnzimmer",
					"aktion": "tue",
					"funktion": reise_zurueck_wohnzimmer,
					"erwartung": "Router-Reise zurück ins Wohnzimmer gestartet",
				},
				{
					"name": "wohnzimmer_ankunft_abwarten",
					"aktion": "warte_bis",
					"route": "home/living",
					"timeout_s": 120.0,
				},
				{"name": "wohnzimmer_wieder_da", "aktion": "warte", "sekunden": 3.0},
				{
					"name": "rueckbesuch_stagt_wieder",
					"aktion": "warte_bis",
					"bedingung": szene_steht_wieder,
					"timeout_s": 30.0,
					"erwartung": "Rückbesuch baut die Wurm-Szene samt Choice-Karte wieder auf",
				},
			]
		)
	)
	return liste


## Wurm-Event deterministisch scharf schalten: evtl. zufällig gestagte
## Events abbrechen, wurm_freund aktivieren, an den Raum pinnen und die
## Szene wie setup() über die Runner-API starten.
func wurm_aktivieren() -> bool:
	var gs := game_state()
	var room := aktuelle_szene()
	if gs == null or room == null:
		return false
	var runner := room.get_node_or_null("EventRunner")
	if runner == null:
		return false
	runner.abort_staging()
	var defs: Array = RandomEventEngine.defs_from_registry()
	var def: Dictionary = RandomEventEngine.def_by_id(defs, "wurm_freund")
	if def.is_empty():
		return false
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	if "clock" in gs:
		now_ms = int(gs.clock.now_ms())
	RandomEventEngine.activate(gs, def, now_ms)
	RandomEventEngine.pin_room(gs, str(room.get("room_id")))
	runner.start(def)
	return true


## E3a-Wache: die Choice-Karte liegt komplett im Canvas und ÜBER der
## Bubble-Lane-Oberkante (= Oberkante der HUD-Bodenmöblierung).
func karte_ueber_dock() -> bool:
	var karte := _choice_karte()
	var hud := _hud()
	if karte == null or hud == null:
		return false
	var lane: Dictionary = hud.call("bubble_lane")
	var rect: Rect2 = karte.get_global_rect()
	var canvas := Vector2(harness.root.get_visible_rect().size)
	if rect.size.y <= 0.0:
		return false
	if rect.end.y > float(lane["top"]) + 0.5:
		return false
	return rect.position.y >= 0.0 and rect.end.x <= canvas.x and rect.position.x >= 0.0


## E3b-Wache 1: nach dem Reiseantritt existiert NIRGENDS mehr eine
## EventChoice-Karte (auch nicht im noch lebenden alten Raum).
func event_ui_weg() -> bool:
	return _choice_karte() == null


## E3b-Wache 2: der Küchen-Runner stagt nicht; das Event bleibt aktiv und
## an living gepinnt (Rückbesuch bietet es erneut an).
func kueche_stagt_nicht() -> bool:
	var gs := game_state()
	var room := aktuelle_szene()
	if gs == null or room == null:
		return false
	var runner := room.get_node_or_null("EventRunner")
	if runner == null or bool(runner.call("is_running")):
		return false
	if RandomEventEngine.active_of(gs).is_empty():
		return false
	return RandomEventEngine.pinned_room_of(gs) == "living"


## Rückreise Küche → Wohnzimmer über den Router (wie die Tür-Bestätigung,
## nur ohne 3D-Tap — die Rücktür liegt hochkant außerhalb der Kamera).
func reise_zurueck_wohnzimmer() -> bool:
	var router := harness.root.get_node_or_null("/root/SceneRouter")
	if router == null:
		return false
	router.call("goto", RoomDefs.route_target("living"))
	return true


## Rückbesuch: Runner läuft wieder und die Choice-Karte steht erneut.
func szene_steht_wieder() -> bool:
	var room := aktuelle_szene()
	if room == null:
		return false
	var runner := room.get_node_or_null("EventRunner")
	if runner == null or not bool(runner.call("is_running")):
		return false
	return _choice_karte() != null


## Die EventChoice-Karte irgendwo im Baum (Name aus EventProps.show_choice).
func _choice_karte() -> Control:
	var gefunden := harness.root.find_child("EventChoice", true, false)
	return gefunden if gefunden is Control else null


func _hud() -> Node:
	for node: Node in harness.get_nodes_in_group(&"hud"):
		if node is Hud and (node as Hud).is_visible_in_tree():
			return node
	return null

class_name EventChoreo
extends Node
## Event-Präsentations-Choreographie (W21 Blocker #2 „EventChoice kapert
## Weltinteraktionen“, Befund home_hud_befunde.md §Event-Kaperung): die
## Wahlkarte eines Events (Nutella/Wurm/Karton) erschien unangekündigt
## mitten im Spielen, parkte OHNE Timeout in der Welt-Tap-Zone und Gooby
## steckte derweil hinter Möbeln (Playtest: nur Ohren hinterm Sofa, 10
## Streichel-Taps verpufft). Diese Komponente besitzt NUR die Präsentation
## — Event-Logik/Belohnungen (RandomEventEngine, Runner-Handler) bleiben
## bit-unverändert:
##  - EINREIHUNG: die Wahlkarte meldet sich beim OverlayDirigenten (W18/J1)
##    statt sofort zu erscheinen — nie über/unter ein anderes Overlay,
##    nie mitten in die Willkommens-Sequenz. PRIO 35: NACH der kompletten
##    Ankunfts-Reihe (Heimkehr 5, Tagesbonus 10, Coachmark 20, Geburtstag
##    30 — alles Herz-/Pflichtmomente der Ankunft), aber VOR dem sanften
##    Abend-Gespräch (40): Events haben echte Engine-Timeouts und eine
##    wartende Szene im Raum, das Gespräch ist der sanfteste Hinweis.
##  - VERTAGEN: reagiert der Spieler VERTAGEN_S lang nicht, gleitet die
##    Karte als kleiner Rand-Chip („{gooby} wartet…“, Muster Gesprächs-
##    Chips) an die Lane-Kante — die Welt bleibt voll spielbar, das Event
##    bleibt aktiv (Engine-Timeout unangetastet). Chip-Tap holt die Karte
##    über den Dirigenten zurück (die Einreihungs-Invariante bleibt
##    absolut; freie Bühne = im nächsten Takt dran).
##  - SICHTBARKEIT: verdeckt eine Möbel-TapArea die Kamerasicht auf Gooby
##    (Playtest: hinterm Sofa), rückt die Inszenierung ihn VOR dem
##    Szenen-Aufbau auf die nächste freie, sichtbare Zelle — reine
##    Präsentation, keine Logik-/Positions-Semantik der Events.
## Zeit ist injizierbar: Tests schalten set_process(false) und pumpen
## tick() mit festen Deltas (AGENTS.md-Regel „Zeit injizieren“).

## Dirigent-Ticket-Id der Event-Wahlkarte.
const DIRIGENT_ID := "event_choice"
## Prio 35: nach allen Willkommens-Overlays (5/10/20/30), vor Gespräch (40).
const PRIO_EVENT_CHOICE := 35
## Ohne Antwort gleitet die Karte nach dieser Zeit als Chip an den Rand.
const VERTAGEN_S := 25.0
## Sichtbarkeits-Strahl zielt auf Brusthöhe (GoobyTapArea-Anker, W21).
const BLICK_HOEHE := 0.35

## Der besitzende Runner (bewusst über den Baum verdrahtet, s. attach_to).
var runner: EventRunner = null

var _karte: Control = null
var _chip: Control = null
var _optionen: Array = []
var _on_pick := Callable()
var _restzeit := 0.0


## Choreo erzeugen und an den Runner hängen (idempotent).
static func attach_to(host: EventRunner) -> EventChoreo:
	var existing := host.get_node_or_null("EventChoreo")
	if existing is EventChoreo:
		return existing
	var choreo := EventChoreo.new()
	choreo.name = "EventChoreo"
	host.add_child(choreo)
	choreo.runner = host
	return choreo


func _process(delta: float) -> void:
	tick(delta)


## Herzschlag des Vertagens (Tests pumpen mit festen Deltas).
func tick(delta: float) -> void:
	if _karte == null or not is_instance_valid(_karte) or not _karte.visible:
		return
	_restzeit -= delta
	if _restzeit <= 0.0:
		_vertagen()


## Wahlkarte anmelden: mit Dirigent im Baum als Ticket (nie in eine
## laufende Sequenz platzen), ohne Dirigent (nackte Tests) sofort.
func zeigen(options: Array, on_pick: Callable) -> void:
	abraeumen()
	_optionen = options
	_on_pick = on_pick
	_anfordern_oder_oeffnen()


## Karte + Chip + offenes Ticket abräumen (Abbruch/Auflösung; idempotent).
func abraeumen() -> void:
	var dirigent := OverlayDirigent.find(self)
	if dirigent != null:
		dirigent.zurueckziehen(DIRIGENT_ID)
	if _karte != null and is_instance_valid(_karte):
		_karte.queue_free()
	_chip_weg()
	_karte = null
	_optionen = []
	_on_pick = Callable()
	if runner != null:
		runner._choice = null


## W21 (d): Möbel-TapArea verdeckt die Kamerasicht auf Gooby (hinterm
## Sofa) → vor dem Szenen-Aufbau auf die nächste freie, sichtbare Zelle
## rücken. Reine Präsentation; ohne Kamera (headless Fakes) ein No-op.
func ruecke_gooby_ins_bild() -> void:
	if runner == null or not runner.is_inside_tree():
		return
	var gooby := runner._gooby()
	if not (gooby is Node3D):
		return
	var g3 := gooby as Node3D
	var camera := runner.get_viewport().get_camera_3d()
	if camera == null or not _verdeckt(camera, g3, g3.global_position):
		return
	var cells: Array = runner._free_cells()
	var start := g3.global_position
	cells.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			var pa := GridData.world_center(a, Vector2i.ONE, 0)
			var pb := GridData.world_center(b, Vector2i.ONE, 0)
			return pa.distance_squared_to(start) < pb.distance_squared_to(start)
	)
	for cell: Vector2i in cells:
		var pos := GridData.world_center(cell, Vector2i.ONE, 0)
		pos.y = start.y
		if not _verdeckt(camera, g3, pos):
			g3.global_position = pos
			return


## Öffnen-Pfad (Dirigent ruft an der Reihe; null = hinfällig — Event
## inzwischen abgebrochen/aufgelöst, dann kommt sofort das nächste Ticket).
func _oeffne() -> Control:
	if runner == null or not runner.is_running() or _optionen.is_empty():
		return null
	if _karte != null and is_instance_valid(_karte):
		return null
	_chip_weg()
	_karte = EventProps.show_choice(runner._ui_layer(), _optionen, _gewaehlt)
	_restzeit = VERTAGEN_S
	runner._choice = _karte
	return _karte


func _anfordern_oder_oeffnen() -> void:
	var dirigent := OverlayDirigent.find(self)
	if dirigent == null:
		_oeffne()
		return
	dirigent.anfordern(DIRIGENT_ID, PRIO_EVENT_CHOICE, _oeffne)


## Antwort gewählt: Buchführung räumen, dann UNVERÄNDERT an den Runner-
## Handler durchreichen (Belohnungen/Stat-Deltas bleiben Runner-Sache).
func _gewaehlt(option: Dictionary) -> void:
	# Die Karte hat sich im Button-Handler schon selbst abgeräumt.
	_karte = null
	if runner != null:
		runner._choice = null
	var weiter := _on_pick
	_optionen = []
	_on_pick = Callable()
	if weiter.is_valid():
		weiter.call(option)


## Vertagen: Karte weg, kleiner Rand-Chip bleibt — nur Präsentation, das
## Event läuft mit seinem Engine-Timeout (RandomEventEngine) weiter.
func _vertagen() -> void:
	if _karte != null and is_instance_valid(_karte):
		_karte.queue_free()
	_karte = null
	if runner != null:
		runner._choice = null
	if runner == null or not runner.is_running():
		return
	_chip = EventProps.show_chip(runner._ui_layer(), _chip_text(), _on_chip_tap)
	AudioDirector.try_play(self, "ui_tick")


func _chip_text() -> String:
	var nick := "Gooby"
	if runner != null and runner._gs != null:
		nick = str(runner._gs.get_value("meta.goobyNickname", "Gooby"))
	return I18nService.t("events.choice.wartet", {"gooby": nick})


## Chip-Tap: Karte zurückholen — wieder über den Dirigenten (Invariante
## „nie über ein anderes Overlay“ bleibt absolut; freie Bühne = sofort).
func _on_chip_tap() -> void:
	# Der Chip hat sich im Button-Handler schon selbst abgeräumt.
	_chip = null
	_anfordern_oder_oeffnen()


func _chip_weg() -> void:
	if _chip != null and is_instance_valid(_chip):
		_chip.queue_free()
	_chip = null


## Erster Treffer des Kamera-Strahls ist NICHT Gooby → verdeckt. Nur
## Areas (Möbel-/Tür-TapAreas) zählen — Bodenplatten o. Ä. nie.
func _verdeckt(camera: Camera3D, gooby: Node3D, pos: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		camera.global_position, pos + Vector3(0.0, BLICK_HOEHE, 0.0)
	)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := gooby.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider: Variant = hit.get("collider")
	if not (collider is Node):
		return true
	var node := collider as Node
	if node.name == &"GoobyTapArea" or node == gooby or gooby.is_ancestor_of(node):
		return false
	return true

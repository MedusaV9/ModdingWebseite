class_name OverlayDirigent
extends Node
## Overlay-Dirigent (W18/J1, Playtest-Befund E4 „Overlay-Stau“): EINE
## zentrale Reihenfolge für alle Willkommens-Overlays. Beim Ankommen lagen
## vorher Tagesbonus (Layer 90) ÜBER Guide-/Tour-Karte (Layer 70) ÜBER
## HUD-Coachmark — und der kaum sichtbare Tagesbonus-Schleier schluckte
## dabei jeden Tap auf die Schichten darunter. Jetzt melden sich die
## Overlays über ihre VORHANDENEN Öffnen-Pfade hier an (`anfordern` mit
## Priorität + Öffnen-Callable) und der Dirigent zeigt sie NACHEINANDER:
## immer nur EIN Willkommens-Overlay, mit kleiner Atempause dazwischen.
## Fertig = das Overlay verlässt den Baum (die bestehenden Schließ-Pfade
## rufen queue_free) oder versteckt sich selbst.
##
## Zwei Sonderfälle, bewusst minimal-invasiv:
## - Die Guide-/Tour-Karte reiht sich NICHT ein (sie ist eine Dauer-Karte,
##   kein Einmal-Blatt) — sie duckt sich stattdessen, solange `belegt()`
##   (OnboardingGuide._karte_erlaubt fragt hier nach) und kommt nach der
##   Sequenz von selbst zurück.
## - Der HUD-Coachmark („Deine Knöpfe“) entsteht in hud.gd (fremde Zone,
##   Paket J6) — der Dirigent BEOBACHTET ihn deshalb von außen: taucht er
##   auf, wird er sofort unsichtbar geparkt und als Ticket eingereiht; an
##   seiner Reihe federt er per UiMotion.pop_in wieder auf. hud.gd bleibt
##   unangetastet.
##
## Morgen-Ritual (Idee I-02): der Tagesbonus meldet sich mit `vorlauf_s`
## an — Gooby begrüßt zuerst (bestehende Raum-Sprüche der Seele), DANN
## gleitet das Blatt rein, DANN ggf. der Quests-Hinweis (RewardHub hört
## auf `overlay_fertig`). Zeitquelle ist der _process-Takt; Tests schalten
## set_process(false) und pumpen `tick()` mit festen Deltas — die Sequenz
## ist damit deterministisch (AGENTS.md-Regel „Zeit injizieren“).

signal overlay_gestartet(id: String)
signal overlay_fertig(id: String)
signal sequenz_leer

const GROUP := &"overlay_dirigent"
## Prioritäten (kleiner = früher dran; gleiche Priorität = Meldereihenfolge).
const PRIO_TAGESBONUS := 10
const PRIO_COACHMARK := 20
const PRIO_GEBURTSTAG := 30
## Kleine Atempause zwischen zwei Willkommens-Overlays (Sekunden).
const PAUSE_S := 0.45

## Pause zwischen zwei Overlays (Tests setzen 0.0 = sofort weiter).
var pause_s := PAUSE_S

## Warteschlange: {id, prio, seq, oeffnen: Callable, vorlauf_s: float}.
var _queue: Array[Dictionary] = []
var _seq := 0
var _aktiv: Control = null
var _aktiv_id := ""
var _warte_s := 0.0
var _coachmark: Control = null
## Während einer Router-Reise öffnet der Dirigent NICHTS: die Ankunft ist
## der Sammelpunkt der Willkommens-Tickets. Ohne die Sperre gewann der
## Coachmark das Rennen — er entsteht schon beim HUD-Einblenden WÄHREND der
## Reise, das Tagesbonus-Ticket kommt erst mit travel_finished (und der
## Reiseantritt hatte das Onboarding-Ticket gerade zurückgezogen): der
## Coachmark öffnete in der leeren Lücke sofort und das Blatt hing dann
## ewig hinter ihm fest (Playtest-Lauf flow_morgen_ritual, Befund E4-Folge).
var _reise_laeuft := false


## Dirigent erzeugen und anhängen (idempotent, Gruppe overlay_dirigent).
static func attach_to(parent: Node) -> OverlayDirigent:
	var tree := parent.get_tree()
	if tree != null:
		var existing := tree.get_first_node_in_group(GROUP)
		if existing is OverlayDirigent:
			return existing
	var dirigent := OverlayDirigent.new()
	dirigent.name = "OverlayDirigent"
	parent.add_child(dirigent)
	return dirigent


## Aktiver Dirigent im Baum (null ohne Home-Entry, z. B. nackte Tests —
## die Aufrufer öffnen dann direkt wie vor W18/J1).
static func find(node: Node) -> OverlayDirigent:
	if node == null or not node.is_inside_tree():
		return null
	var found := node.get_tree().get_first_node_in_group(GROUP)
	return found if found is OverlayDirigent else null


func _ready() -> void:
	add_to_group(GROUP)
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_signal("travel_started"):
		router.travel_started.connect(_on_travel_started)
	if router != null and router.has_signal("travel_finished"):
		router.travel_finished.connect(_on_travel_finished)


func _process(delta: float) -> void:
	tick(delta)


## Ein Willkommens-Overlay anmelden. `oeffnen` öffnet es über seinen
## VORHANDENEN Pfad und gibt das Wurzel-Control zurück (null = inzwischen
## hinfällig, z. B. Tagesbonus schon abgeholt — dann kommt sofort das
## nächste Ticket dran). `vorlauf_s` verzögert NUR dieses Ticket (Morgen-
## Ritual: erst der Gooby-Gruß, dann das Blatt). Pro id höchstens ein
## Ticket; ist dieselbe id gerade aktiv, ist der Aufruf ein No-op.
func anfordern(id: String, prio: int, oeffnen: Callable, vorlauf_s := 0.0) -> void:
	if id == _aktiv_id and _aktiv_gueltig():
		return
	for eintrag: Dictionary in _queue:
		if str(eintrag["id"]) == id:
			return
	_seq += 1
	_queue.append({"id": id, "prio": prio, "seq": _seq, "oeffnen": oeffnen, "vorlauf_s": vorlauf_s})


## Ein noch nicht geöffnetes Ticket zurückziehen (z. B. Reiseantritt:
## RewardHub nimmt den Tagesbonus zurück — er bleibt bis Mitternacht
## abholbar, genau wie beim bisherigen „Später“-Pfad).
func zurueckziehen(id: String) -> void:
	for i in range(_queue.size() - 1, -1, -1):
		if str(_queue[i]["id"]) == id:
			_queue.remove_at(i)


## Läuft gerade eine Willkommens-Sequenz (Overlay sichtbar ODER Tickets
## offen)? Solange true ist, duckt sich die Guide-/Tour-Karte.
func belegt() -> bool:
	return _aktiv_gueltig() or not _queue.is_empty()


## Id des gerade sichtbaren Overlays ("" = keins).
func aktiv_id() -> String:
	return _aktiv_id if _aktiv_gueltig() else ""


## Reise beginnt → Öffnen-Sperre an (parken/anfordern läuft weiter).
func _on_travel_started(_target: StringName = &"", _travel_type: int = 0) -> void:
	_reise_laeuft = true


## Ankunft → Sperre auf. Die Ticket-Anmelder (RewardHub) hängen am selben
## Signal; welcher Handler zuerst dran ist, ist egal — geöffnet wird erst
## im nächsten tick, wenn alle Ankunfts-Tickets eingereiht sind.
func _on_travel_finished(_target: Variant = null) -> void:
	_reise_laeuft = false


## Herzschlag (läuft über _process; Tests pumpen mit festen Deltas).
func tick(delta: float) -> void:
	_beobachte_coachmark()
	if _reise_laeuft:
		return
	if _aktiv_gueltig():
		return
	if _aktiv != null or not _aktiv_id.is_empty():
		_abschliessen()
	if _queue.is_empty():
		return
	_warte_s -= delta
	if _warte_s > 0.0:
		return
	_naechstes_oeffnen()


func _aktiv_gueltig() -> bool:
	return (
		_aktiv != null
		and is_instance_valid(_aktiv)
		and _aktiv.is_inside_tree()
		and not _aktiv.is_queued_for_deletion()
		and _aktiv.visible
	)


## Aktives Overlay ist zu → Buch führen, Atempause armieren.
func _abschliessen() -> void:
	var fertig_id := _aktiv_id
	_aktiv = null
	_aktiv_id = ""
	_warte_s = pause_s
	if not fertig_id.is_empty():
		overlay_fertig.emit(fertig_id)
	if _queue.is_empty():
		sequenz_leer.emit()


## Bestes Ticket (kleinste Priorität, dann Meldereihenfolge) öffnen.
## Ein Ticket mit Rest-Vorlauf armiert erst die Wartezeit (Morgen-Gruß)
## und kommt beim nächsten abgelaufenen Takt regulär dran.
func _naechstes_oeffnen() -> void:
	var best := 0
	for i in range(1, _queue.size()):
		if _kommt_frueher(_queue[i], _queue[best]):
			best = i
	var eintrag: Dictionary = _queue[best]
	var vorlauf := float(eintrag["vorlauf_s"])
	if vorlauf > 0.0:
		eintrag["vorlauf_s"] = 0.0
		_warte_s = vorlauf
		return
	_queue.remove_at(best)
	var oeffnen: Callable = eintrag["oeffnen"]
	var overlay: Control = null
	if oeffnen.is_valid():
		overlay = oeffnen.call()
	if overlay == null or not is_instance_valid(overlay):
		# Hinfällig (schon abgeholt/Raum weg) → nächstes Ticket ohne Pause.
		if _queue.is_empty():
			sequenz_leer.emit()
		return
	_aktiv = overlay
	_aktiv_id = str(eintrag["id"])
	overlay_gestartet.emit(_aktiv_id)


func _kommt_frueher(a: Dictionary, b: Dictionary) -> bool:
	if int(a["prio"]) != int(b["prio"]):
		return int(a["prio"]) < int(b["prio"])
	return int(a["seq"]) < int(b["seq"])


## hud.gd gehört einer fremden Zone (J6) — deshalb Außen-Beobachtung statt
## Anmeldung: der Coachmark („HudCoachmark“, direktes Kind eines Nodes in
## der Gruppe „hud“) wird beim Auftauchen unsichtbar geparkt und als
## Ticket eingereiht; an seiner Reihe federt er wieder auf.
func _beobachte_coachmark() -> void:
	if _coachmark != null and is_instance_valid(_coachmark):
		return
	_coachmark = null
	for hud: Node in get_tree().get_nodes_in_group(&"hud"):
		var kandidat := hud.get_node_or_null("HudCoachmark")
		if kandidat is Control:
			_coachmark = kandidat
			break
	if _coachmark == null:
		return
	_coachmark.visible = false
	anfordern("coachmark", PRIO_COACHMARK, _zeige_coachmark)


func _zeige_coachmark() -> Control:
	if _coachmark == null or not is_instance_valid(_coachmark):
		return null
	_coachmark.visible = true
	UiMotion.pop_in(_coachmark)
	return _coachmark

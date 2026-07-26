class_name RNpcManager
extends Node3D
## Bewohner-Verwaltung der Ranch (RW-3): spawnt das komplette NPC-Ensemble
## aus dem RNpcKatalog, bewegt jede Figur entlang ihrer Tagesroutine
## (RNpcRoutine, inkl. Fußwegen zwischen Stationen) und hängt Quest-Marker
## über Questgeber/-empfänger. RW-1s Hof-Szene kann den Manager einfach
## per RNpcManager.neu() als Kind einhängen — er versorgt sich selbst.
##
## Uhrzeit: `stunde` (0..24) treiben Szene/Tests von außen; ohne Treiber
## läuft die echte Tageszeit. Marker: `marker_aktualisieren(gs)` fragt die
## Quest-Lage ab (RQuestState) — Aufruf bei Slice-Änderungen genügt.

## Uhrzeit-Treiber: < 0 = Systemuhr benutzen.
var stunde := -1.0

var _figuren: Dictionary = {}
var _marker: Dictionary = {}


static func neu() -> RNpcManager:
	var manager := RNpcManager.new()
	manager.name = "RanchNpcs"
	return manager


func _ready() -> void:
	for def: Dictionary in RNpcKatalog.alle():
		var figur := RNpcFigur.neu(def)
		_figuren[str(def["id"])] = figur
		add_child(figur)
	_stellen()


func _process(_delta: float) -> void:
	_stellen()


## Alle Figuren auf ihre Routine-Position zur aktuellen Stunde stellen.
func _stellen() -> void:
	var jetzt := aktuelle_stunde()
	for id: String in _figuren:
		var figur: RNpcFigur = _figuren[id]
		var routine: Variant = figur.def.get("routine")
		if not (routine is Array):
			continue
		var zustand := RNpcRoutine.zustand(routine, jetzt)
		var ziel: Vector3 = zustand["pos"]
		if bool(zustand["laeuft"]) and (ziel - figur.position).length() > 0.05:
			var blick := ziel - figur.position
			figur.rotation.y = atan2(blick.x, blick.z)
		figur.position = ziel
		figur.setze_laeuft(bool(zustand["laeuft"]))


## Aktive Uhrzeit (Treiber oder Systemuhr).
func aktuelle_stunde() -> float:
	if stunde >= 0.0:
		return fmod(stunde, 24.0)
	var t := Time.get_time_dict_from_system()
	return float(t.hour) + float(t.minute) / 60.0


## Figur eines NPC (null = unbekannt) — für Interaktion/Kamera.
func figur(npc_id: String) -> RNpcFigur:
	return _figuren.get(npc_id)


## Quest-Marker anhand der aktuellen Quest-Lage setzen: Abgabe schlägt
## Vergabe (erfüllbare Quest beim Geber = grüner Marker).
func marker_aktualisieren(gs: Object) -> void:
	var wunsch := {}
	for def: Dictionary in RQuestState.verfuegbare(gs):
		wunsch[str(def.get("geber", ""))] = "vergabe"
	var stand := RQuestState.quests(gs)
	for quest_id: String in stand.get("aktiv", {}) as Dictionary:
		var lauf: Dictionary = stand["aktiv"][quest_id]
		if str(lauf.get("status", "")) == RQuestSlices.STATUS_ERFUELLBAR:
			wunsch[str(RQuestKatalog.quest(quest_id).get("geber", ""))] = "abgabe"
	for npc_id: String in _figuren:
		_marker_setzen(npc_id, str(wunsch.get(npc_id, "")))


## Marker einer Figur direkt setzen ("" = entfernen) — auch für Tests.
func _marker_setzen(npc_id: String, art: String) -> void:
	var figur_node: RNpcFigur = _figuren.get(npc_id)
	if figur_node == null:
		return
	var alt: RQuestMarker = _marker.get(npc_id)
	if alt != null and (art.is_empty() or alt.art != art):
		alt.queue_free()
		_marker.erase(npc_id)
		alt = null
	if art.is_empty() or alt != null:
		return
	var marker := RQuestMarker.neu(art)
	marker.position = Vector3(0.0, _marker_hoehe(figur_node), 0.0)
	figur_node.add_child(marker)
	_marker[npc_id] = marker


## Aktiver Marker eines NPC ("" = keiner) — Testanker.
func marker_art(npc_id: String) -> String:
	var marker: RQuestMarker = _marker.get(npc_id)
	return marker.art if marker != null else ""


func _marker_hoehe(figur_node: RNpcFigur) -> float:
	var modell: Variant = figur_node.def.get("modell")
	var groesse := 1.0
	if modell is Dictionary:
		groesse = clampf(float((modell as Dictionary).get("groesse", 1.0)), 0.4, 1.6)
	# Deutlich über dem Namensschild (~1.75*g + 0.3), Ring hängt -0.34 tiefer.
	return 2.3 * groesse + 0.45

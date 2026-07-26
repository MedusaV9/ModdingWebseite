class_name RmpAusrittController
extends Node
## Brücke zwischen der Ranch-Welt und dem Ranch-Multiplayer (RW-6): hängt
## in der Region-Szene, liest den EIGENEN Reiter (RanchWeltReiter-API:
## position/rotation.y/tempo/zone_gewechselt — NUR lesend) und
## 1. schickt die eigene Pose mit 10 Hz ins Relay (Service taktet),
## 2. spawnt/entsorgt RmpRemoteRider für alle Peers (Geister, keine
##    Kollision) inkl. Namensschild + „Folge mir"-Marker,
## 3. teilt Entdeckungen (Zonen-Wechsel) und meldet fremde als Toast,
## 4. treibt im Rennen/Parcours die Checkpoint-Erkennung (Server prüft
##    Reihenfolge/Nähe — hier nur der optimistische Trigger).

signal toast(text: String)
signal checkpoint_bestaetigt(next_idx: int)

var service: RanchMultiplayerService = null
## Der eigene Reiter (RanchWeltReiter oder Duck-Typing-Double mit
## position/rotation/tempo). Wird von der Szene gesetzt.
var reiter: Node3D = null
## Wohin Remote-Reiter gehängt werden (Standard: Parent dieses Knotens).
var welt: Node = null

var _riders: Dictionary = {}
var _next_checkpoint := 0
var _im_ziel := false
var _checkpoint_offen := true
var _folge_mir := false


func setup(
	mp_service: RanchMultiplayerService, mein_reiter: Node3D, welt_node: Node = null
) -> void:
	service = mp_service
	reiter = mein_reiter
	welt = welt_node if welt_node != null else get_parent()
	service.peer_pose.connect(_on_peer_pose)
	service.peer_left.connect(_on_peer_left)
	service.peer_down.connect(func(d: Dictionary) -> void: _peer_stale(d, true))
	service.peer_up.connect(func(d: Dictionary) -> void: _peer_stale(d, false))
	service.reaction_received.connect(_on_reaction)
	service.match_started.connect(func(_d: Dictionary) -> void: _reset_lauf())
	service.session_ended.connect(func(_d: Dictionary) -> void: _alle_entfernen())
	if reiter != null and reiter.has_signal("zone_gewechselt"):
		reiter.zone_gewechselt.connect(_on_zone)


func _process(_delta: float) -> void:
	if service == null or reiter == null or not service.is_active():
		return
	var tempo := absf(float(reiter.get("tempo"))) if reiter.get("tempo") != null else 0.0
	service.send_pose(reiter.position, reiter.rotation.y, tempo, _gait_fuer(tempo), "", false)
	_pruefe_checkpoints()


## „Folge mir" umschalten (Marker erscheint bei den ANDEREN über mir).
func toggle_folge_mir() -> void:
	_folge_mir = not _folge_mir
	if service != null:
		service.send_reaction("FOLGE_MIR", {"an": _folge_mir})


## Fangen: nächsten Peer in Reichweite anfassen (Server validiert).
func versuche_fangen() -> void:
	if service == null or reiter == null or service.it_code != service.my_code():
		return
	var bester := ""
	var beste_dist := 1e9
	for code: String in _riders:
		var dist := reiter.global_position.distance_to((_riders[code] as Node3D).global_position)
		if dist < beste_dist:
			beste_dist = dist
			bester = code
	if bester.is_empty():
		return
	var res: Dictionary = await service.send_event({"kind": "tag", "target": bester})
	if not res["ok"]:
		toast.emit(RanchMultiplayerService.fehler_text(str(res["code"])))


## ---------------------------------------------------------------- intern


func _pruefe_checkpoints() -> void:
	if service.phase != "run" and service.countdown_ms() > 0:
		return
	if service.mode != "rennen" and service.mode != "parcours":
		return
	if _im_ziel or not _checkpoint_offen:
		return
	var anzahl := RmpKurse.checkpoint_anzahl(service.kurs)
	if _next_checkpoint >= anzahl:
		_checkpoint_offen = false
		_sende_finish()
		return
	if RmpKurse.checkpoint_erreicht(service.kurs, _next_checkpoint, reiter.position):
		_checkpoint_offen = false
		_sende_checkpoint(_next_checkpoint)


func _sende_checkpoint(idx: int) -> void:
	var res: Dictionary = await service.send_event({"kind": "checkpoint", "idx": idx})
	_checkpoint_offen = true
	if res["ok"]:
		_next_checkpoint = int((res["d"] as Dictionary).get("next", idx + 1))
		checkpoint_bestaetigt.emit(_next_checkpoint)


func _sende_finish() -> void:
	var res: Dictionary = await service.send_event({"kind": "finish"})
	if res["ok"]:
		_im_ziel = true
		toast.emit(I18nService.t("ranch_mp.lauf.ziel"))
	else:
		_checkpoint_offen = true


func _on_peer_pose(from_code: String, pose: Dictionary) -> void:
	var rider := _rider_fuer(from_code)
	if rider != null:
		rider.apply_pose(pose)


func _rider_fuer(code: String) -> RmpRemoteRider:
	if code.is_empty() or code == service.my_code():
		return null
	if _riders.has(code):
		return _riders[code]
	if welt == null:
		return null
	var rider := RmpRemoteRider.new()
	rider.name = "RmpRider_%s" % code
	welt.add_child(rider)
	rider.set_display_name(_name_fuer(code))
	_riders[code] = rider
	toast.emit(I18nService.t("ranch_mp.ausritt.dabei", {"name": _name_fuer(code)}))
	return rider


func _on_peer_left(data: Dictionary) -> void:
	var code := str(data.get("friendCode", ""))
	if _riders.has(code):
		(_riders[code] as Node).queue_free()
		_riders.erase(code)


func _peer_stale(data: Dictionary, weg: bool) -> void:
	var code := str(data.get("friendCode", ""))
	if _riders.has(code) and weg:
		(_riders[code] as RmpRemoteRider).reset_interp()


func _on_zone(zone_id: String) -> void:
	if service != null and service.mode == "ausritt":
		service.send_reaction("ENTDECKUNG", {"zone": zone_id})


func _on_reaction(kind: String, from_code: String, body: Dictionary) -> void:
	match kind:
		"FOLGE_MIR":
			var rider := _rider_fuer(from_code)
			if rider != null:
				rider.set_follow_me(bool(body.get("an", false)))
		"ENTDECKUNG":
			toast.emit(
				I18nService.t(
					"ranch_mp.ausritt.entdeckung",
					{"name": _name_fuer(from_code), "zone": str(body.get("zone", "?"))}
				)
			)


func _reset_lauf() -> void:
	_next_checkpoint = 0
	_im_ziel = false
	_checkpoint_offen = true


func _alle_entfernen() -> void:
	for code: String in _riders:
		(_riders[code] as Node).queue_free()
	_riders.clear()


func _gait_fuer(tempo: float) -> int:
	if tempo < 0.3:
		return 0
	if tempo < 5.0:
		return 1
	if tempo < 11.0:
		return 2
	return 4


func _name_fuer(code: String) -> String:
	if service != null:
		for spieler: Variant in service.players:
			if spieler is Dictionary and str((spieler as Dictionary).get("friendCode", "")) == code:
				return str((spieler as Dictionary).get("name", code))
	return code

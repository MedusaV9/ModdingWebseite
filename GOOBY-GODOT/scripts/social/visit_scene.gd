class_name VisitScene
extends Node3D
## Besuchs-Szene (W3c VISIT, Doc C §3.4): rendert das Haus des HOSTS aus dem
## Snapshot (VisitRoomView), zeigt BEIDE Goobys (eigener GoobyHome + Gast als
## RemoteGooby mit Namens-Label), relayt die eigene Position mit 5 Hz und
## wechselt Räume unabhängig (POS trägt roomId; der andere Gooby ist nur im
## gleichen Raum sichtbar, sonst zeigt das HUD „ist in der Küche“).
##
## Host & Gast benutzen DIESELBE Szene: der Host läuft durch sein eigenes
## Haus (und darf minimal bauen — BUILD_START-Warnung + BUILD_DELTA-Relay,
## Persistenz in sein GameState), der Gast wendet Deltas Best-Effort an
## (Konflikt „steht auf der Zelle“ → Tür-Teleport, Doc C §3.4 Punkt 5).

const ROUTE := &"social/visit"
const ROUTES := {ROUTE: "res://scripts/social/visit_scene.tscn"}
const MOVE_EPSILON := 0.02

## Tests/Screenshots: SocialServices-Instanz injizieren statt /root-Lookup.
var services_override: Node = null
## Tests: ohne Netz nur rendern (kein POS-Versand).
var relay_enabled := true

var snapshot: Dictionary = {}
var role := VisitService.ROLE_GUEST
var my_room_id := ""

var room_view: VisitRoomView
var my_gooby: GoobyHome
var remote: RemoteGooby
var hud: VisitHud
## W13B COUCH-COOP: Besucher-Couch-Regel (§C32) + Coop-Fahrt (Doc C §3.6).
var couch_coop: VisitManager

var _services: Node = null
var _camera_rig: HomeCameraRig
var _room_ids: Array[String] = []
var _last_pos := Vector3.INF
var _build_active := false
var _remove_mode := false
var _pending_deltas: Dictionary = {}  # roomId -> Array[delta]
var _warned_this_visit := false


static func register_routes() -> void:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return
	var router := (loop as SceneTree).root.get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("register_routes"):
		router.register_routes(ROUTES)


## Router-Contract (W1a): Snapshot + Rolle kommen als Params.
func receive_params(params: Dictionary) -> void:
	if params.get("snapshot") is Dictionary:
		snapshot = params["snapshot"]
	role = str(params.get("role", VisitService.ROLE_GUEST))


func _ready() -> void:
	_services = services_override
	if _services == null:
		_services = SocialServices.get_or_create(self)
	if snapshot.is_empty() and role == VisitService.ROLE_HOST:
		var gs := get_node_or_null("/root/GameState")
		if gs != null:
			snapshot = VisitSnapshot.build_from_state(gs)
	_room_ids = VisitSnapshot.room_ids(snapshot)
	var start := "living"
	if not _room_ids.has(start):
		start = _room_ids[0] if _room_ids.size() > 0 else ""
	_build_hud()
	_switch_room(start, "")
	_wire_service()
	_setup_couch_coop()


func visit_service() -> VisitService:
	return _services.visit if _services != null else null


## Raumwechsel (Tür ODER HUD-Leiste): Raum neu aufbauen, Gooby an die
## Ziel-Tür, POS SOFORT senden (force — der Peer soll den Wechsel sehen).
func _switch_room(room_id: String, via_door_id: String) -> void:
	if room_id.is_empty() or RoomDefs.room(room_id).is_empty():
		return
	if room_view != null:
		room_view.queue_free()
	my_room_id = room_id
	room_view = VisitRoomView.new()
	room_view.name = "Room_%s" % room_id
	add_child(room_view)
	room_view.build(room_id, snapshot)
	room_view.door_tapped.connect(_on_door_tapped)
	_spawn_goobys(via_door_id)
	_apply_pending_deltas()
	if hud != null:
		hud.set_rooms(_room_ids, my_room_id)
	_update_peer_visibility()
	_send_pos(true)


func _spawn_goobys(via_door_id: String) -> void:
	if my_gooby == null:
		my_gooby = GoobyHome.new()
		my_gooby.name = "MyGooby"
		add_child(my_gooby)
		_camera_rig = HomeCameraRig.new()
		add_child(_camera_rig)
		_camera_rig.follow_target = my_gooby
	if remote == null:
		remote = RemoteGooby.new()
		remote.name = "PeerGooby"
		add_child(remote)
		remote.visible = false
	my_gooby.grid = room_view.grid
	my_gooby.position = room_view.spawn_pos(via_door_id)
	_camera_rig.setup(room_view.world_size())
	_last_pos = Vector3.INF


func _build_hud() -> void:
	hud = VisitHud.new()
	add_child(hud)
	# FIX-6: Verbindungsanzeige oben links (eigener Layer über dem VisitHud —
	# der gehört FIX-1, deshalb hängen wir uns nicht in dessen Baum).
	var status_layer := CanvasLayer.new()
	status_layer.layer = 6
	add_child(status_layer)
	var status := NetStatusIndicator.new()
	status.set_anchors_preset(Control.PRESET_TOP_LEFT)
	status.offset_left = 16.0
	status.offset_top = 16.0
	status_layer.add_child(status)
	hud.end_pressed.connect(_on_end_pressed)
	hud.room_selected.connect(func(room_id: String) -> void: _switch_room(room_id, ""))
	var vs := visit_service()
	var gooby_name := str(snapshot.get("goobyName", "Gooby"))
	if role == VisitService.ROLE_HOST:
		var peer := vs.peer_name if vs != null and not vs.peer_name.is_empty() else "?"
		hud.set_title(I18nService.t("social.visit.host_label", {"name": peer}))
		_enable_host_build()
	else:
		hud.set_title(I18nService.t("social.visit.at", {"gooby": gooby_name}))
	hud.set_peer_status("")


func _enable_host_build() -> void:
	var gs := get_node_or_null("/root/GameState")
	var storage: Array = HomeState.storage(gs) if gs != null else []
	hud.enable_build_controls(storage)
	hud.build_toggled.connect(_on_build_toggled)
	hud.remove_mode_toggled.connect(func(active: bool) -> void: _remove_mode = active)


func _wire_service() -> void:
	var vs := visit_service()
	if vs == null:
		return
	vs.peer_pos.connect(_on_peer_pos)
	vs.peer_emote.connect(func(emote_id: String) -> void: remote.play_emote(emote_id))
	vs.build_warning.connect(_on_build_warning)
	vs.build_delta_received.connect(_on_build_delta)
	vs.peer_joined.connect(_on_peer_joined)
	vs.peer_left.connect(_on_peer_left)
	vs.visit_ended.connect(_on_visit_ended)


## W13B COUCH-COOP: der komplette Besuchs-Zusatz (Couch-Regel + Coop-Fahrt)
## lebt im VisitManager (scripts/multiplayer/) — die Szene hängt ihn nur an.
func _setup_couch_coop() -> void:
	couch_coop = VisitManager.new()
	couch_coop.name = "CouchCoop"
	add_child(couch_coop)
	couch_coop.setup(self)


func _process(_delta: float) -> void:
	_send_pos(false)


func _unhandled_input(event: InputEvent) -> void:
	if not _build_active or room_view == null:
		return
	var pressed: bool = (
		(event is InputEventMouseButton and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
	)
	if pressed:
		_handle_build_tap(_event_position(event))


# ── POS-Relay ────────────────────────────────────────────────────────────────


func _send_pos(force: bool) -> void:
	if not relay_enabled or my_gooby == null:
		return
	var vs := visit_service()
	if vs == null or not vs.is_active():
		return
	var pos := my_gooby.global_position
	var moving := _last_pos != Vector3.INF and (pos - _last_pos).length() > MOVE_EPSILON
	# W13B COUCH-COOP: Energie (beide) + Lokal-Stunde (nur Host) reisen als
	# additive POS-Felder mit — Grundlage der Besucher-Couch-Regel (§C32).
	var energie := couch_coop.energie_fuer_relay() if couch_coop != null else -1.0
	var stunde := couch_coop.stunde_fuer_relay() if couch_coop != null else -1
	vs.send_pos(pos, VisitLogic.anim_for(moving), my_room_id, force, energie, stunde)
	_last_pos = pos


func _on_peer_pos(pos: Vector3, anim: String, _peer_room: String) -> void:
	_update_peer_visibility()
	if remote.visible:
		remote.apply_state(pos, anim)


## Sichtbarkeitsregel + HUD-Hinweis („X ist in der Küche“).
func _update_peer_visibility() -> void:
	var vs := visit_service()
	if vs == null or remote == null:
		return
	var peer_room := vs.peer_room_id
	var same := VisitLogic.peer_visible(my_room_id, peer_room)
	remote.visible = same
	remote.set_display_name(vs.peer_gooby_name)
	if same or peer_room.is_empty():
		hud.set_peer_status("")
	else:
		var key := "home.raum.%s" % peer_room
		var room_name := I18nService.t(key) if I18nService.has_key(key) else peer_room
		hud.set_peer_status("%s → %s" % [vs.peer_gooby_name, room_name])


# ── Bauen während Besuch ─────────────────────────────────────────────────────


func _on_build_toggled(active: bool) -> void:
	_build_active = active
	var vs := visit_service()
	if active and not _warned_this_visit and vs != null:
		_warned_this_visit = true
		vs.send_build_start()


func _handle_build_tap(screen_pos: Vector2) -> void:
	var cell := _cell_under(screen_pos)
	if not room_view.grid.in_bounds(cell):
		return
	var vs := visit_service()
	if _remove_mode:
		var removed := room_view.remove_at(cell)
		if removed["ok"]:
			_persist_host_grid()
			if vs != null:
				vs.send_build_delta(my_room_id, "remove", str(removed["item"]), cell)
		return
	var item_id := hud.selected_item()
	if item_id.is_empty():
		return
	var placed := room_view.place_item(item_id, cell)
	if placed["ok"]:
		_persist_host_grid()
		if vs != null:
			vs.send_build_delta(my_room_id, "place", item_id, cell)


## Host-Änderungen ins EIGENE GameState übernehmen (VISIT_END lädt dann die
## finale rev hoch, Doc C §3.4 Punkt 5).
func _persist_host_grid() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs != null and role == VisitService.ROLE_HOST:
		HomeState.save_room_grid(gs, my_room_id, room_view.grid)


func _on_build_warning() -> void:
	hud.show_toast(I18nService.t("social.visit.build_warning"))


func _on_build_delta(delta: Dictionary) -> void:
	if role == VisitService.ROLE_HOST:
		return
	var delta_room := str(delta.get("roomId", my_room_id))
	if delta_room != my_room_id:
		var queue: Array = _pending_deltas.get(delta_room, [])
		queue.append(delta)
		_pending_deltas[delta_room] = queue
		return
	var occupant := GridData.cell_of(my_gooby.global_position)
	var res := room_view.apply_remote_delta(delta, occupant)
	if bool(res.get("teleport", false)):
		my_gooby.position = room_view.spawn_pos("")


func _apply_pending_deltas() -> void:
	var queue: Array = _pending_deltas.get(my_room_id, [])
	_pending_deltas.erase(my_room_id)
	for delta: Variant in queue:
		if delta is Dictionary:
			room_view.apply_remote_delta(delta, Vector2i(-99, -99))


# ── Lifecycle ────────────────────────────────────────────────────────────────


func _on_door_tapped(door_id: String) -> void:
	var door_def := RoomDefs.door(my_room_id, door_id)
	var target := str(door_def.get("to", ""))
	if _room_ids.has(target):
		_switch_room(target, str(door_def.get("to_door", "")))


func _on_peer_joined(data: Dictionary) -> void:
	hud.show_toast(
		I18nService.t("social.visit.peer_joined", {"name": str(data.get("goobyName", "?"))})
	)
	_update_peer_visibility()


func _on_peer_left(data: Dictionary) -> void:
	var vs := visit_service()
	var who := vs.peer_gooby_name if vs != null else str(data.get("friendCode", "?"))
	hud.show_toast(I18nService.t("social.visit.peer_left", {"name": who}))
	remote.visible = false


func _on_end_pressed() -> void:
	var vs := visit_service()
	if vs == null:
		_go_home()
		return
	if role == VisitService.ROLE_HOST:
		var gs := get_node_or_null("/root/GameState")
		if gs != null:
			await vs.upload_snapshot(gs)
	await vs.end_visit()
	# VISIT_ENDED-Push räumt auf; Fallback falls offline:
	if vs.room_id.is_empty() and is_inside_tree():
		_go_home()


func _on_visit_ended(_data: Dictionary) -> void:
	hud.show_toast(I18nService.t("social.visit.ended"))
	_go_home()


func _go_home() -> void:
	var router := get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("goto"):
		return
	var routes: Variant = router.get("_routes")
	if routes is Dictionary and (routes as Dictionary).has(&"home"):
		router.goto(&"home", {})


func _cell_under(screen_pos: Vector2) -> Vector2i:
	if _camera_rig == null or _camera_rig.camera == null:
		return Vector2i(-1, -1)
	var cam := _camera_rig.camera
	var origin := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return Vector2i(-1, -1)
	var t := -origin.y / dir.y
	if t < 0.0:
		return Vector2i(-1, -1)
	return GridData.cell_of(origin + dir * t)


func _event_position(event: InputEvent) -> Vector2:
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).position
	return (event as InputEventScreenTouch).position

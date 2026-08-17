class_name VisitManager
extends Node
## Besuchs-Manager (W13B COUCH-COOP): orchestriert im laufenden Besuch die
## Besucher-Couch-Regel (§C32, CouchLogic) und die Coop-Fahrt (Doc C §3.6,
## CoopDrive). Die VisitScene hängt GENAU EINEN Manager an und übergibt sich
## selbst (Duck-Typing) — Tests bauen stattdessen eine Mini-Fake-Szene und
## injizieren Zeit/Energie/Bewegung (FakeLink-Muster, keine 3D-Last).
##
## Rollen: Der GAST steuert seinen eigenen Gooby → die Einschlaf-Entscheidung
## fällt beim Gast (Host-Stunde + Host-Energie kommen über den additiven
## POS-Sync, VisitService.peer_hour/peer_energy). Der HOST sieht das Nickerchen
## über das NAP-Relay (RemoteGooby.start_nap) + knuffige Bubble. FAHRER der
## Coop-Fahrt ist immer der Gastgeber (CoopDrive).

## Lokal (Gast): das eigene Nickerchen hat begonnen/geendet.
signal nap_gestartet(boden: bool)
signal nap_beendet
## Host-Seite: der Besucher-Gooby pennt/ist wach (fürs HUD/Tests).
signal peer_nap_gestartet(boden: bool)
signal peer_nap_beendet

enum NapZustand { WACH, GEHT_ZUR_COUCH, SCHLAEFT }

## Wie oft die Couch-Regel zusätzlich zum POS-Takt geprüft wird.
const CHECK_INTERVALL_S := 2.0

var zustand := NapZustand.WACH

## Injektion (Tests): Lokal-Stunde 0–23 (Host schickt sie ins Relay).
var hour_provider := Callable(self, "_system_stunde")
## Injektion (Tests): eigener Energie-Stat 0–100 (−1 = unbekannt).
var energy_provider := Callable(self, "_state_energie")
## Injektion (Tests): kompletter Save-Dict (Radio-Gate des Fahrers).
var state_provider := Callable(self, "_state_dict")
## Injektion (Tests): Gooby zur Zielposition bewegen (async erlaubt).
var move_provider := Callable(self, "_default_move")

var coop: CoopDrive = null
var beifahrer_ui: BeifahrerUi = null

var _scene: Node = null
var _vs: VisitService = null
var _armed := true
var _nap_boden := false
var _nap_cell := Vector2i.ZERO
var _check_timer: Timer = null
var _ui_layer: CanvasLayer = null
var _wake_button: Button = null
var _fahrt_button: Button = null


## Andocken an die Besuchs-Szene (Duck-Typing: role, snapshot, my_gooby,
## remote, hud, my_room_id, visit_service()). `mit_ui=false` lässt Tests ohne
## Buttons/CanvasLayer laufen.
func setup(scene: Node, mit_ui := true) -> void:
	_scene = scene
	if scene.has_method("visit_service"):
		_vs = scene.call("visit_service") as VisitService
	if _vs != null:
		_vs.peer_pos.connect(_on_peer_pos)
		_vs.peer_nap.connect(_on_peer_nap)
		_vs.visit_ended.connect(func(_data: Dictionary) -> void: _aufraeumen())
	_check_timer = Timer.new()
	_check_timer.wait_time = CHECK_INTERVALL_S
	_check_timer.timeout.connect(pruefe_couch_regel)
	add_child(_check_timer)
	_check_timer.start()
	_baue_coop_fahrt()
	if mit_ui:
		_baue_ui()


# ── POS-Sync-Zulieferung (die Szene ruft das bei jedem Send) ────────────────


## Eigene Energie fürs POS-Relay (beide Rollen schicken sie mit).
func energie_fuer_relay() -> float:
	return float(energy_provider.call())


## Lokal-Stunde fürs POS-Relay — NUR der Host schickt sie (§C32: es zählt
## der Abend des Gastgebers), der Gast liefert −1 (Feld bleibt weg).
func stunde_fuer_relay() -> int:
	if _rolle() == VisitService.ROLE_HOST:
		return int(hour_provider.call())
	return -1


# ── Couch-Regel (Gast-Seite) ─────────────────────────────────────────────────


## Regel prüfen und ggf. das Nickerchen starten. Öffentlich, damit Tests den
## Takt selbst bestimmen (sonst: Timer + jeder POS-Empfang).
func pruefe_couch_regel() -> void:
	if _rolle() != VisitService.ROLE_GUEST or _vs == null or not _vs.is_active():
		return
	var soll := CouchLogic.soll_schlafen(
		int(_vs.peer_hour), float(energy_provider.call()), float(_vs.peer_energy)
	)
	if not soll:
		# Regel wieder aus → neu scharf (verhindert Einschlaf-Schleife nach
		# dem Aufwecken, solange Abend + Erschöpfung anhalten).
		_armed = true
		return
	if _armed and zustand == NapZustand.WACH:
		_starte_nickerchen()


func _starte_nickerchen() -> void:
	zustand = NapZustand.GEHT_ZUR_COUCH
	var snapshot: Dictionary = _scene.get("snapshot") if _scene != null else {}
	var couch := CouchLogic.couch_suchen(snapshot)
	if couch["ok"]:
		_nap_boden = false
		_nap_cell = couch["cell"]
		_wechsle_in_wohnzimmer()
		await move_provider.call(couch["pos"])
	else:
		# Kaputter Alt-Save ohne Couch → Boden-Nickerchen an Ort und Stelle.
		_nap_boden = true
		_nap_cell = Vector2i.ZERO
	if zustand != NapZustand.GEHT_ZUR_COUCH:
		return  # zwischenzeitlich geweckt/beendet
	zustand = NapZustand.SCHLAEFT
	_gooby_pose("sleep")
	if _vs != null:
		_vs.send_nap(true, _nap_cell, _nap_boden)
	var key := "social.nap.guest_bubble_boden" if _nap_boden else "social.nap.guest_bubble"
	_toast(I18nService.t(key))
	if _wake_button != null:
		_wake_button.visible = true
	nap_gestartet.emit(_nap_boden)


## „Aufwecken“-Knopf des Gastes: Gooby steht auf, Host bekommt NAP off.
func wecke_auf() -> void:
	if zustand == NapZustand.WACH:
		return
	zustand = NapZustand.WACH
	_armed = false
	_gooby_pose("idle")
	if _vs != null:
		_vs.send_nap(false, _nap_cell, _nap_boden)
	_toast(I18nService.t("social.nap.wake_toast_guest"))
	if _wake_button != null:
		_wake_button.visible = false
	nap_beendet.emit()


# ── NAP-Empfang (Host-Seite) ─────────────────────────────────────────────────


func _on_peer_nap(data: Dictionary) -> void:
	var nap := CouchLogic.parse_nap(data)
	if not nap["ok"]:
		return
	var remote: Node = _scene.get("remote") if _scene != null else null
	if nap["on"]:
		var boden: bool = nap["boden"]
		var pos := _peer_nap_position(boden)
		if remote != null and remote.has_method("start_nap"):
			remote.start_nap(pos)
		var key := "social.nap.host_bubble_boden" if boden else "social.nap.host_bubble"
		_toast(I18nService.t(key))
		peer_nap_gestartet.emit(boden)
	else:
		if remote != null and remote.has_method("end_nap"):
			remote.end_nap()
		_toast(I18nService.t("social.nap.host_wake"))
		peer_nap_beendet.emit()


## Liegeposition auf Host-Seite: Couch aus dem EIGENEN Snapshot (gleiches
## Haus), beim Boden-Nickerchen bleibt der Remote-Gooby wo er ist.
func _peer_nap_position(boden: bool) -> Vector3:
	var remote: Node = _scene.get("remote") if _scene != null else null
	if not boden and _scene != null:
		var couch := CouchLogic.couch_suchen(_scene.get("snapshot"))
		if couch["ok"]:
			return couch["pos"]
	if remote is Node3D:
		return (remote as Node3D).global_position
	return Vector3.ZERO


# ── Coop-Fahrt (Doc C §3.6) ─────────────────────────────────────────────────


func _baue_coop_fahrt() -> void:
	coop = CoopDrive.new()
	coop.name = "CoopDrive"
	add_child(coop)
	var net: Node = _vs.net() if _vs != null else null
	if net != null:
		coop.setup(net)
	coop.einladung_abgelehnt.connect(
		func() -> void: _toast(I18nService.t("coop.fahrt.abgelehnt", {"name": _peer_name()}))
	)
	coop.fahrt_beendet.connect(_on_fahrt_beendet)


func _on_fahrt_beendet(grund: String) -> void:
	var key := "coop.fahrt.fahrer_weg" if grund == "fahrer_weg" else "coop.fahrt.beendet"
	_toast(I18nService.t(key))


func _peer_name() -> String:
	if _vs != null and not _vs.peer_gooby_name.is_empty():
		return _vs.peer_gooby_name
	return "?"


## Host drückt „Gemeinsam fahren“: Radio-Gate lesen (Welle A, nur LESEN) und
## als Fahrer starten — der Gast bekommt die Einladung übers Besuchs-Relay.
func starte_coop_fahrt() -> void:
	if _vs == null or not _vs.is_active() or _rolle() != VisitService.ROLE_HOST:
		return
	var radio_owned := RadioLogic.besitzt_radio(state_provider.call())
	var snapshot: Dictionary = _scene.get("snapshot") if _scene != null else {}
	var von := str(snapshot.get("goobyName", "Gooby"))
	await coop.starte_als_fahrer(_vs.room_id, radio_owned, von)


# ── UI (G3 P06: Knöpfe reihen sich in die VisitHud-Aktionszeile ein) ────────


## Wake-/Fahrt-Knöpfe als SquishButtons im AC-Theme (g1/ui-onboarding 2.7:
## vorher Godot-Default-Look, feste Pixel, Ecken-Kleber ohne Safe-Area).
## Bevorzugt landen sie in der zentrierten VisitHud-Bottom-Aktionszeile
## (add_action_button — EINE Daumenzonen-Zeile statt eigener Ecke); ohne
## HUD (Test-Fakes) fällt der Manager auf einen eigenen Layer mit
## Safe-Area + Touch-Floor zurück.
func _baue_ui() -> void:
	_wake_button = SquishButton.new()
	_wake_button.theme_type_variation = &"AccentButton"
	_wake_button.text = I18nService.t("social.nap.wake_button")
	_wake_button.visible = false
	_wake_button.pressed.connect(_on_wake_gedrueckt)
	if _rolle() == VisitService.ROLE_HOST:
		_fahrt_button = SquishButton.new()
		_fahrt_button.theme_type_variation = &"BtnLeaf"
		_fahrt_button.text = I18nService.t("coop.fahrt.button")
		_fahrt_button.pressed.connect(_on_fahrt_gedrueckt)
	var hud: Node = _scene.get("hud") if _scene != null else null
	if hud != null and hud.has_method("add_action_button"):
		hud.call("add_action_button", _wake_button)
		if _fahrt_button != null:
			hud.call("add_action_button", _fahrt_button)
	else:
		_baue_eigenen_layer()
	beifahrer_ui = BeifahrerUi.new()
	beifahrer_ui.name = "BeifahrerUi"
	beifahrer_ui.setup(coop)
	add_child(beifahrer_ui)


func _on_wake_gedrueckt() -> void:
	AudioDirector.try_play(self, "ui_click")
	wecke_auf()


func _on_fahrt_gedrueckt() -> void:
	# Start einer gemeinsamen Aktion → ui_confirm (Audio-Grammatik §3).
	AudioDirector.try_play(self, "ui_confirm")
	starte_coop_fahrt()


## Fallback ohne VisitHud: eigener Layer, AC-Theme, zentrierte Bottom-Zeile
## in der Safe-Area, Touch-Floor über ScreenShell-Metriken.
func _baue_eigenen_layer() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 7
	add_child(_ui_layer)
	var wurzel := Control.new()
	wurzel.set_anchors_preset(Control.PRESET_FULL_RECT)
	wurzel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wurzel.theme = ThemeService.theme()
	_ui_layer.add_child(wurzel)
	var reihe := HBoxContainer.new()
	reihe.alignment = BoxContainer.ALIGNMENT_CENTER
	reihe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reihe.add_theme_constant_override("separation", 8)
	wurzel.add_child(reihe)
	reihe.add_child(_wake_button)
	if _fahrt_button != null:
		reihe.add_child(_fahrt_button)
	var vp := get_viewport()
	if vp != null:
		var m := ScreenShell.metrics(vp)
		var insets: Dictionary = m["insets"]
		var f: float = m["f"]
		reihe.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		reihe.offset_left = float(insets["left"]) + 12.0 * f
		reihe.offset_right = -float(insets["right"]) - 12.0 * f
		reihe.offset_bottom = -float(insets["bottom"]) - 12.0 * f
		reihe.offset_top = reihe.offset_bottom - 72.0 * f
		ScreenShell.touch_target(_wake_button, m)
		if _fahrt_button != null:
			ScreenShell.touch_target(_fahrt_button, m)


# ── Intern ───────────────────────────────────────────────────────────────────


func _on_peer_pos(_pos: Vector3, _anim: String, _room_id: String) -> void:
	pruefe_couch_regel()


func _rolle() -> String:
	if _scene == null:
		return VisitService.ROLE_NONE
	return str(_scene.get("role"))


## Nickerchen findet im Wohnzimmer statt — falls der Gast woanders steht,
## wechselt die Szene den Raum (VisitScene._switch_room, Duck-Typing).
func _wechsle_in_wohnzimmer() -> void:
	if _scene == null:
		return
	if str(_scene.get("my_room_id")) == CouchLogic.WOHNZIMMER:
		return
	if _scene.has_method("_switch_room"):
		_scene.call("_switch_room", CouchLogic.WOHNZIMMER, "")


## Standard-Bewegung: GoobyHome.walk_to (awaitbar, eigener Timeout) —
## Fallback Teleport, wenn die Szene keinen lauffähigen Gooby hat.
func _default_move(ziel: Vector3) -> void:
	var gooby: Node = _scene.get("my_gooby") if _scene != null else null
	if gooby is GoobyHome:
		await (gooby as GoobyHome).walk_to(ziel)
		return
	if gooby is Node3D:
		(gooby as Node3D).position = ziel


func _gooby_pose(clip: String) -> void:
	var gooby: Node = _scene.get("my_gooby") if _scene != null else null
	if gooby != null and gooby.has_method("play_clip"):
		gooby.call("play_clip", clip)


func _toast(text: String) -> void:
	var hud: Node = _scene.get("hud") if _scene != null else null
	if hud != null and hud.has_method("show_toast"):
		hud.call("show_toast", text)


func _aufraeumen() -> void:
	zustand = NapZustand.WACH
	_armed = true
	if _wake_button != null:
		_wake_button.visible = false
	if beifahrer_ui != null:
		beifahrer_ui.verstecke()


func _system_stunde() -> int:
	return Time.get_datetime_dict_from_system().hour


func _state_energie() -> float:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return -1.0
	return float(gs.get_value("stats.energy", -1.0))


func _state_dict() -> Dictionary:
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("state"):
		return gs.state()
	return {}

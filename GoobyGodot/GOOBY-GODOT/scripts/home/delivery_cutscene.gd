class_name DeliveryCutscene
extends Node3D
## Möbel-Bestell-Cutscene (Doc D §3.2): Gooby steht mit Klemmbrett an der
## Einfahrt und winkt den Liefer-LKW ein (car-kit `delivery.glb`), danach
## landen die Möbel im LAGER — nie direkt im Raum.
##
## BESTELL-DATENVERTRAG (Möbelladen = ORTE-Agent):
##   DeliveryCutscene.bestellen(gs, item_id, menge)   # Bezahlen macht der Laden
##   DeliveryCutscene.offene(gs) -> [{item, count}]
## Die Cutscene selbst läuft beim nächsten Betreten des Gartens
## (`attach_if_pending`), damit der LKW wirklich in die Einfahrt fahren kann.
## Handoff: /tmp/gooby-godot/handoffs/HAUS-baumarkt-api.md

signal fertig(menge: int)

const TRUCK_GLB := "res://assets/city/autos/delivery.glb"
const ROOM_ID := "garden"
## Fahrstrecke (m) und Dauer der Anfahrt.
const ANFAHRT_S := 2.6
const ABFAHRT_S := 2.0
const PAUSE_S := 1.1
const REDUZIERT_S := 0.25

var _room: Node
var _gs: Object
var _truck: Node3D
var _kartons: Array[Node3D] = []
var _skip := false
var _skip_button: Button


## Bestellung einreihen (der Laden hat schon kassiert).
static func bestellen(gs: Object, item_id: String, menge := 1) -> void:
	if FurnitureCatalog.def(item_id).is_empty() or menge <= 0:
		return
	gs.update(
		func(state: Dictionary) -> void:
			var home: Dictionary = state["home"]
			if not (home.get("lieferungen") is Array):
				home["lieferungen"] = []
			home["lieferungen"].append({"item": item_id, "count": menge})
	)
	gs.notify_slice_changed("home")


## Offene Bestellungen ([] = nichts unterwegs).
static func offene(gs: Object) -> Array:
	var raw: Variant = gs.get_value("home.lieferungen", [])
	return raw if raw is Array else []


## Cutscene an den Garten hängen, falls etwas unterwegs ist.
static func attach_if_pending(room: Node, gs: Object) -> DeliveryCutscene:
	if gs == null or str(room.get("room_id")) != ROOM_ID or offene(gs).is_empty():
		return null
	var szene := DeliveryCutscene.new()
	szene.name = "DeliveryCutscene"
	room.add_child(szene)
	szene._room = room
	szene._gs = gs
	return szene


## Die komplette Cutscene abspielen und die Möbel einlagern (awaitbar).
func spielen() -> void:
	var bestellungen := offene(_gs)
	if bestellungen.is_empty():
		queue_free()
		return
	# W18/4-B9: Gooby im Urlaub → kein Raum-Gooby zum Einweisen. Die
	# Lieferung bleibt OFFEN (lieferungen unangetastet) und läuft beim
	# nächsten Garten-Besuch nach der Rückkehr — kein Crash, kein Verlust.
	var gooby: GoobyHome = _room.gooby() if _room.has_method("gooby") else null
	if gooby == null:
		queue_free()
		return
	gooby.set_wander_enabled(false)
	_skip_taste()
	var einfahrt := _einfahrt()
	_truck = _truck_modell()
	_truck.position = einfahrt + Vector3(-_strecke(), 0.0, 0.0)
	add_child(_truck)
	var klemmbrett := HomeProps.klemmbrett()
	klemmbrett.position = Vector3(0.18, 0.55, 0.25)
	gooby.add_child(klemmbrett)
	_sagen("lieferung.warten")
	var posten := einfahrt + Vector3(2.6, 0.0, 1.5)
	await gooby.walk_to(posten, 4.0)
	# Frisch betretener Garten: das Navmesh ist evtl. noch nicht gebacken —
	# dann stellt sich Gooby eben direkt an die Einfahrt.
	if gooby.global_position.distance_to(posten) > 0.8:
		gooby.global_position = posten
	await _fahrt(_truck, einfahrt, ANFAHRT_S)
	gooby.rig.play_clip("wave")
	gooby.rig.set_emotion("happy")
	_sagen("lieferung.einweisen")
	await _warten(PAUSE_S)
	var menge := _abladen(bestellungen, einfahrt)
	_sagen("lieferung.abhaken")
	await _warten(PAUSE_S)
	_einlagern(bestellungen)
	await _fahrt(_truck, einfahrt + Vector3(_strecke(), 0.0, 0.0), ABFAHRT_S)
	_aufraeumen(klemmbrett)
	gooby.rig.play_clip("celebrate")
	gooby.rig.set_emotion("ecstatic")
	_sagen_text(I18nService.t("lieferung.fertig", {"menge": menge}))
	gooby.set_wander_enabled(true)
	fertig.emit(menge)
	queue_free()


func ueberspringen() -> void:
	_skip = true


func _skip_taste() -> void:
	if not _room.has_method("ui_layer"):
		return
	_skip_button = Button.new()
	_skip_button.text = I18nService.t("lieferung.ueberspringen")
	_skip_button.theme = ThemeService.theme()
	_skip_button.theme_type_variation = "GhostButton"
	_skip_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_skip_button.pressed.connect(ueberspringen)
	_room.ui_layer().add_child(_skip_button)


## Einfahrt = vor der Haustür-Kante des Gartens (Nordseite, Raummitte).
func _einfahrt() -> Vector3:
	var zellen: Vector2i = RoomDefs.room(ROOM_ID).get("grid", Vector2i(28, 24))
	var breite := zellen.x * GridData.CELL_SIZE
	return Vector3(breite * 0.5, 0.0, 0.9)


func _strecke() -> float:
	var zellen: Vector2i = RoomDefs.room(ROOM_ID).get("grid", Vector2i(28, 24))
	return zellen.x * GridData.CELL_SIZE * 0.6 + 3.0


func _truck_modell() -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "LieferLkw"
	if ResourceLoader.exists(TRUCK_GLB):
		var scene: PackedScene = load(TRUCK_GLB)
		if scene != null:
			var modell: Node3D = scene.instantiate()
			modell.scale = Vector3.ONE * 1.05
			modell.rotation.y = PI * 0.5
			wurzel.add_child(modell)
			return wurzel
	var ersatz := HomeProps.box(Vector3(2.4, 1.2, 1.1), "anstrich")
	ersatz.position.y = 0.6
	wurzel.add_child(ersatz)
	return wurzel


func _fahrt(node: Node3D, ziel: Vector3, dauer: float) -> void:
	if _skip or _reduziert():
		node.position = ziel
		await _warten(REDUZIERT_S)
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(node, "position", ziel, dauer)
	await tween.finished


## Kartons neben dem LKW abstellen (einer je bestelltem Möbel, max. 5).
func _abladen(bestellungen: Array, einfahrt: Vector3) -> int:
	var menge := 0
	for eintrag: Variant in bestellungen:
		if eintrag is Dictionary:
			menge += maxi(1, int(eintrag.get("count", 1)))
	for i in mini(5, maxi(1, menge)):
		var karton := HomeProps.karton()
		karton.position = einfahrt + Vector3(0.6 + i * 0.55, 0.0, 2.0)
		add_child(karton)
		_kartons.append(karton)
	AudioDirector.try_play(self, "ui_confirm")
	return menge


func _einlagern(bestellungen: Array) -> void:
	for eintrag: Variant in bestellungen:
		if not (eintrag is Dictionary):
			continue
		for _i in maxi(1, int(eintrag.get("count", 1))):
			HomeState.store_item(_gs, str(eintrag.get("item", "")))
	_gs.update(func(state: Dictionary) -> void: state["home"]["lieferungen"] = [])
	_gs.notify_slice_changed("home")


func _aufraeumen(klemmbrett: Node3D) -> void:
	for karton in _kartons:
		karton.queue_free()
	_kartons.clear()
	if is_instance_valid(klemmbrett):
		klemmbrett.queue_free()
	if _skip_button != null and is_instance_valid(_skip_button):
		_skip_button.queue_free()


func _warten(sekunden: float) -> void:
	var dauer := REDUZIERT_S if (_skip or _reduziert()) else sekunden
	await get_tree().create_timer(dauer).timeout


func _sagen(key: String) -> void:
	_sagen_text(I18nService.t(key))


func _sagen_text(text: String) -> void:
	if _room != null and _room.has_method("say"):
		_room.say(text)


func _reduziert() -> bool:
	var settings := get_node_or_null("/root/AppSettings")
	return settings != null and settings.is_reduced_motion()

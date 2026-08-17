extends "res://tools/capture/clip_driver.gd"
## Clip: Kühlschrank 2.0 + Fütter-Sequenz (W14/FRIDGE) — Gooby läuft in der
## Küche zum Kühlschrank, das appetitliche Regal-Grid öffnet sich (AC-Karten
## mit echter 3D-Vorschau, Vorrats-Badges, Stat-Pillen), dann schwebt die
## Möhre zu Gooby, wird in drei Bissen gemampft — und die Verliebtheit
## steigt ihm zu Kopf (Herz-Burst + „+10“-Float).
## Treiber-Regie statt FuetterRegie: Sequenz und `walk_to` takten über die
## WANDUHR (Time.get_ticks_msec) — im Movie-Maker (1–6 fps Wandzeit) würde
## die ~2,5-s-Mampf-Sequenz auf wenige Movie-Frames zusammenschnurren.
## Deshalb spielt der Treiber dieselben Beats über die CLIP-Zeit nach, mit
## den ECHTEN Bausteinen (FuetterModelle, babble_pulse, GoobyFeelings,
## RewardFx) — reine Aufnahme-Regie, kein Spielcode wird geändert.

const FOOD_ID := "carrot"
const BISSE := 3
const HERZ_TEILE := 12

var room: Node3D
var kuehlschrank: Node3D
var speise: Node3D


func _setup() -> void:
	duration = 12.0
	var packed: PackedScene = load("res://scenes/home/kueche.tscn")
	room = packed.instantiate()
	room.stunde_override = 12.5
	add_child(room)
	# Interactables dockt sonst home_entry an — hier direkt (Kühlschrank!).
	InteractablesHost.attach_to(room)
	_finde_kuehlschrank()
	_vorrat_sichern()
	schedule(0.3, _kamera_flacher)
	schedule(0.6, _zum_kuehlschrank)
	schedule(2.6, _panel_oeffnen)
	schedule(6.2, _mampfen)


## Wie in home_room: Deckenbalken aus der Bildmitte, flacherer Blick.
func _kamera_flacher() -> void:
	var rig: Node3D = room.camera_rig()
	if rig == null:
		return
	var dist: float = rig._offset.length()
	rig._offset = Vector3(0.0, 2.9, 5.6).normalized() * dist


func _finde_kuehlschrank() -> void:
	var host := room.get_node_or_null("InteractablesHost")
	if host == null:
		return
	for kind in host.get_children():
		if kind is Kuehlschrank:
			kuehlschrank = kind
			return


## Fotogener Vorrat: mindestens 3 Möhren + etwas Beiwerk im Regal-Grid
## (frische Saves haben das Starter-Food, alte VM-Saves vielleicht nicht).
func _vorrat_sichern() -> void:
	var gs: Object = room.game_state()
	if gs == null:
		return
	gs.update(
		func(state: Dictionary) -> void:
			var food: Dictionary = state["inventory"]["food"]
			food["carrot"] = maxi(int(food.get("carrot", 0)), 3)
			food["apple"] = maxi(int(food.get("apple", 0)), 2)
			food["cupcake"] = maxi(int(food.get("cupcake", 0)), 1)
	)


func _zum_kuehlschrank() -> void:
	var gooby: Node3D = room._gooby
	if gooby == null or kuehlschrank == null:
		return
	gooby.set_wander_enabled(false)
	# _start_walking statt walk_to: dessen Timeout ist Wanduhr-basiert und
	# bricht den Lauf im Movie-Maker (1–6 fps Wandzeit) nach Frames ab.
	gooby.call("_start_walking", kuehlschrank.global_position + Vector3(0.3, 0.0, 0.7))


func _panel_oeffnen() -> void:
	if kuehlschrank != null:
		kuehlschrank._open_panel()


func _mampfen() -> void:
	var gooby: Node3D = room._gooby
	if gooby == null or kuehlschrank == null:
		return
	kuehlschrank._close_panel()
	gooby.cancel_walk()
	speise = FuetterModelle.instanz(FOOD_ID)
	add_child(speise)
	var start := kuehlschrank.global_position + Vector3(0.0, 0.95, 0.35)
	speise.global_position = start
	var mund := _mund_position(gooby)
	# Bogen zum Mund (Movie-Zeit-Tween statt Wanduhr-Sequenz).
	var hoch := start.lerp(mund, 0.5) + Vector3(0.0, 0.35, 0.0)
	var tween := create_tween()
	tween.tween_property(speise, "global_position", hoch, 0.55).set_trans(Tween.TRANS_SINE)
	tween.tween_property(speise, "global_position", mund, 0.55).set_trans(Tween.TRANS_SINE)
	for i in BISSE:
		schedule(t + 1.4 + 0.7 * i, _biss.bind(i))
	schedule(t + 1.4 + 0.7 * BISSE, _verliebt)


func _biss(nummer: int) -> void:
	var gooby: Node3D = room._gooby
	if gooby != null and gooby.rig != null:
		gooby.rig.babble_pulse()
	if speise == null or not is_instance_valid(speise):
		return
	if nummer >= BISSE - 1:
		speise.visible = false
		return
	var ziel := speise.scale * 0.62
	create_tween().tween_property(speise, "scale", ziel, 0.2)


func _verliebt() -> void:
	if speise != null and is_instance_valid(speise):
		speise.queue_free()
		speise = null
	var gooby: Node3D = room._gooby
	if gooby == null or gooby.rig == null:
		return
	GoobyFeelings.attach_to(gooby.rig).zeige("verliebtheit")
	var kopf: Vector3 = gooby.global_position + Vector3(0.0, 0.9, 0.0)
	RewardFx.float_text(room, kopf, "+10", RewardFx.MINT)
	RewardFx.herz_burst(room, kopf + Vector3(0.0, -0.3, 0.0), HERZ_TEILE)
	gooby.rig.play_clip("hop")
	gooby.rig.set_emotion("ecstatic")


## Mundpunkt wie in der FuetterRegie (Höhe 0,5 m, 0,26 m vor Gooby —
## Richtung Kühlschrank, da schaut er beim Mampfen hin).
func _mund_position(gooby: Node3D) -> Vector3:
	var richtung: Vector3 = kuehlschrank.global_position - gooby.global_position
	richtung.y = 0.0
	if richtung.length() < 0.01:
		richtung = Vector3.FORWARD
	return gooby.global_position + Vector3(0.0, 0.5, 0.0) + richtung.normalized() * 0.26
